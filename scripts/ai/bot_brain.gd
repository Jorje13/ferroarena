class_name BotBrain
extends Node
## Server-side AI. Drives its Player through the same PlayerInput a human
## fills, so bots obey every movement / weapon / bandage rule.
##
## Bots only know what they could know: enemies they see (world geometry and
## smoke block sight, see Arena.is_sight_blocked) or hear firing. Built around
## the Ferro's rhythm (one shot, then a long reload):
##   peek & shoot -> duck into nearby cover to reload -> peek again from the
##   spot they shot from, pre-aiming where the enemy was.
## Without contact they push the last known position from a flank (each bot
## of a team takes its own side), hold the angle on enemies hidden in smoke,
## and hunt the enemy's rough area when nothing is known.

## How long a sighting / sound stays useful (s).
const MEMORY := 9.0
## Max hearing distance of a Ferro shot (m).
const HEAR_RANGE := 90.0
## Max time spent holding the angle on a smoke before pushing through it (s).
const SMOKE_HOLD := 6.0

## Difficulty levels (Game.config.difficulty): aim skill range, reaction time, aim error,
## hearing, memory and thinking-rate multipliers, callouts between teammates.
const LEVELS := [
	{"skill": [0.22, 0.42], "react": 1.5, "err": 2.4, "hear": 0.6, "mem": 5.0, "think": 0.22, "callout": false, "tricks": 0.3},
	{"skill": [0.5, 0.8], "react": 1.0, "err": 1.0, "hear": 1.0, "mem": 9.0, "think": 0.12, "callout": true, "tricks": 1.0},
	{"skill": [0.75, 0.92], "react": 0.72, "err": 0.55, "hear": 1.15, "mem": 12.0, "think": 0.1, "callout": true, "tricks": 1.6},
	{"skill": [0.9, 1.0], "react": 0.5, "err": 0.3, "hear": 1.3, "mem": 16.0, "think": 0.08, "callout": true, "tricks": 2.2},
]

var lvl: Dictionary = LEVELS[1]
var p: Player
var skill := 0.7
var target: Player

var _rng := RandomNumberGenerator.new()
var _t := 0.0
var _think := 0.0
var _visible := false
var _seen_time := 0.0
var _last_seen := -100.0
var _last_seen_pos := Vector3.ZERO
var _path := PackedVector3Array()
var _path_i := 0
var _path_dest := Vector3.INF
var _repath := 0.0
var _strafe := 1.0
var _strafe_t := 0.0
var _err := Vector2.ZERO
var _err_t := 0.0
var _stuck_t := 0.0
var _last_pos := Vector3.ZERO
var _unstick := 0.0
var _next_item_t := 4.0
var _retreat_t := 0.0
## enemy node name -> {"pos": Vector3, "t": float}
var _known := {}
## Where we last had a clear shot from (peek spot).
var _peek_pos := Vector3.INF
var _cover_pos := Vector3.INF
var _cover_eval := 0.0
var _flank := 1.0
var _hunt_pos := Vector3.INF
var _hunt_t := 0.0
var _hold_t := 0.0
var _peek_t := 0.0
var _mode := ""
var _last_callout := -10.0
## enemy name -> {by: bot name, t: seconds}: who is shooting whom (shared by all brains).
static var focus := {}


func _ready() -> void:
	p = get_parent() as Player
	_rng.randomize()
	lvl = LEVELS[clampi(int(Game.config.get("difficulty", 1)), 0, 3)]
	skill = _rng.randf_range(lvl.skill[0], lvl.skill[1])
	_strafe = 1.0 if _rng.randf() < 0.5 else -1.0
	# Teammates spread over both flanks.
	_flank = 1.0 if String(p.name).hash() & 1 else -1.0


## --log_bots: total time spent thinking (µs), for the [PERF] line.
static var cost_us := 0


func think(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	_think_inner(delta)
	cost_us += Time.get_ticks_usec() - t0


func _think_inner(delta: float) -> void:
	_t += delta
	var inp := p.input
	inp.move = Vector2.ZERO
	inp.sprint = false
	inp.aim = false
	inp.interact = false
	if p.downed:
		_crawl(delta)
		return
	if not p.alive:
		return
	if not p.arena.match_allows_movement():
		target = null
		_seen_time = 0.0
		_known.clear()
		_peek_pos = Vector3.INF
		_cover_pos = Vector3.INF
		_path = PackedVector3Array()
		return
	_think -= delta
	if _think <= 0.0:
		_think = float(lvl.think)
		_pick_target()
	if target and _visible and target.is_hittable():
		_hold_t = 0.0
		_combat(delta)
	elif target and _knows(target) and target.is_hittable():
		_seen_time = 0.0
		if _tend_self(delta):
			_say("soin")
		else:
			_engage_known(delta)
	else:
		_seen_time = 0.0
		_roam(delta)
	_check_stuck(delta)


## --log_bots: prints each behaviour change.
func _say(m: String) -> void:
	if m != _mode:
		_mode = m
		if Game.debug.has("log_bots"):
			print("[BOT] %s -> %s%s" % [p.display_name, m, (" (cible %s)" % target.display_name) if target else ""])


# ---------------------------------------------------------------- perception

## A shot was fired: remember roughly where (sound gives a fuzzy position).
func hear(shooter: Player, origin: Vector3, max_range := HEAR_RANGE) -> void:
	if not p.alive or p.downed:
		return
	var d := origin.distance_to(p.global_position)
	if d > max_range * float(lvl.hear):
		return
	var fuzz := d * 0.06 / float(lvl.hear)
	var guess := shooter.global_position + Vector3(_rng.randf_range(-fuzz, fuzz), 0.0, _rng.randf_range(-fuzz, fuzz))
	var k := String(shooter.name)
	# Don't blur a fresher, exact sighting.
	if _known.has(k) and _t - float(_known[k].t) < 0.5:
		return
	_known[k] = {"pos": guess, "t": _t}


## A teammate saw o: pass it on (a second late, a couple of metres off).
func _callout(o: Player) -> void:
	for t: Player in p.arena.players:
		if t != p and t.alive and t.team == p.team and t.brain:
			t.brain.share(o, o.global_position)


func share(o: Player, pos: Vector3) -> void:
	var k := String(o.name)
	if _known.has(k) and _t - float(_known[k].t) < 1.5:
		return
	_known[k] = {"pos": pos + Vector3(_rng.randf_range(-2.0, 2.0), 0.0, _rng.randf_range(-2.0, 2.0)), "t": _t - 0.8}


## Took a hit from y: turn to where it came from.
func on_hurt(by: Player) -> void:
	if by == p or not p.alive:
		return
	_known[String(by.name)] = {"pos": by.global_position + Vector3(_rng.randf_range(-3.0, 3.0), 0.0, _rng.randf_range(-3.0, 3.0)), "t": _t}
	_hold_t = 0.0


func _knows(o: Player) -> bool:
	var k := String(o.name)
	return _known.has(k) and _t - float(_known[k].t) < float(lvl.mem)


func _known_pos(o: Player) -> Vector3:
	return _known[String(o.name)].pos


## Visible = a clear line (no wall, no smoke) to the enemy's head or chest.
func _los(o: Player) -> bool:
	var eye := p.eye_position()
	var space := p.get_world_3d().direct_space_state
	for pt in [o.chest_position(), o.global_position + Vector3(0, o.head_height(), 0)]:
		if p.arena.is_sight_blocked(eye, pt):
			continue
		var q := PhysicsRayQueryParameters3D.create(eye, pt, 1)
		if space.intersect_ray(q).is_empty():
			return true
	return false


func _pick_target() -> void:
	var best: Player = null
	var best_score := INF
	var best_vis := false
	for o: Player in p.arena.players:
		if o.team == p.team or not o.is_hittable():
			continue
		var d := o.global_position.distance_to(p.global_position)
		var vis := d < 120.0 and _los(o)
		if vis:
			_known[String(o.name)] = {"pos": o.global_position, "t": _t}
			if lvl.callout and _t - _last_callout > 1.2 and not Game.is_ffa():
				_last_callout = _t
				_callout(o)
		elif not _knows(o):
			continue
		var age := 0.0 if vis else _t - float(_known[String(o.name)].t)
		# Visible first, then freshest info; standing enemies before knocked-down ones.
		var score := d + age * 6.0 - (1000.0 if vis else 0.0) - (15.0 if o == target else 0.0) + (40.0 if o.downed else 0.0)
		# Focus fire: finish what a teammate is already shooting.
		var fk := String(o.name)
		if lvl.callout and not Game.is_ffa() and focus.has(fk) and focus[fk].by != String(p.name) and Time.get_ticks_msec() * 0.001 - float(focus[fk].t) < 1.5:
			score -= 22.0
		if score < best_score:
			best_score = score
			best = o
			best_vis = vis
	if best != target:
		_seen_time = 0.0
		_hold_t = 0.0
	target = best
	_visible = best_vis
	if best:
		focus[String(best.name)] = {"by": String(p.name), "t": Time.get_ticks_msec() * 0.001}
	if best_vis:
		_last_seen = _t
		_last_seen_pos = best.global_position


# ---------------------------------------------------------------- fighting

func _combat(delta: float) -> void:
	var inp := p.input
	_seen_time += delta
	var aim_pt := target.chest_position().lerp(target.global_position + Vector3(0, target.head_height(), 0), clampf((skill - 0.7) * 1.6, 0.0, 0.45))
	var dist := _aim_at(aim_pt, delta, true)
	var off := _aim_off(aim_pt)

	var react := lerpf(1.1, 0.5, skill) * float(lvl.react)
	var close := dist < 7.0
	inp.aim = not close and _seen_time > 0.15 and p.reload_t < 0.0
	if p.loaded and _seen_time > react:
		var tol := 0.03 + 0.5 / maxf(dist, 1.0)
		if (p.aiming and off < tol) or (close and off < 0.2):
			inp.fire = true
			# The spot we shot from: where we come back to after reloading.
			_peek_pos = p.global_position
			_peek_t = 0.0
			_cover_eval = 0.0
	if not p.loaded:
		inp.reload = true

	_retreat_t = maxf(0.0, _retreat_t - delta)
	if _retreat_t > 0.0:
		_say("repli")
		inp.move = Vector2(0.0, 1.0)
		inp.sprint = true
		# Break line of sight low: slide out of the retreat sprint.
		if p.sprinting and Vector2(p.velocity.x, p.velocity.z).length() > 5.4 and _rng.randf() < 0.03:
			inp.crouch = true
		_try_items(dist)
		return

	# Empty gun (or hurt and exposed): get out of sight to reload / heal.
	var exposed_hurt := p.shield <= 0.0 and p.health <= 50.0
	if (not p.loaded or exposed_hurt) and dist > 6.0:
		if _go_to_cover(delta):
			_say("couvert")
			_try_items(dist)
			return
		# No cover around: dance and roll while reloading.
		_say("esquive")
		inp.move = Vector2(_strafe_step(delta), 0.0)
		if dist < 35.0 and p.stamina > 60.0 and _rng.randf() < 0.015:
			inp.roll = true
		_try_items(dist)
		return

	# Loaded, in the open: ADAD at a good range, without wandering far from the peek.
	_say("combat")
	var mv := Vector2(_strafe_step(delta) * (0.7 if inp.aim else 1.0), 0.0)
	if dist > 45.0:
		mv.y = -1.0
	elif dist < 9.0:
		mv.y = 0.7
	inp.move = mv
	if p.is_on_floor() and not inp.aim and _rng.randf() < 0.004 * float(lvl.tricks) * (1.0 + skill):
		inp.jump = true
	_try_items(dist)
	var want_crouch := inp.aim and dist > 28.0 and skill > 0.65 and p.loaded
	if want_crouch != p.crouching and _rng.randf() < 0.05:
		inp.crouch = true


## No sight of the target but we know (roughly) where it is.
func _engage_known(delta: float) -> void:
	var inp := p.input
	if _zone_escape(delta):
		return
	var kp := _known_pos(target)
	var chest := kp + Vector3(0, 1.25, 0)
	var to := kp - p.global_position
	var dist := Vector2(to.x, to.z).length()
	if not p.loaded:
		inp.reload = true
		# Reload behind cover, then come back to the peek.
		if dist < 45.0 and _go_to_cover(delta, chest):
			_say("couvert")
			return
	_pre_aim(chest, delta)
	inp.aim = p.loaded and dist < 60.0
	# Enemy hidden in a smoke: hold the angle on it (a nade if we have one),
	# then push through once it's been too long.
	if p.loaded and p.arena.is_sight_blocked(p.eye_position(), chest) and _hold_t < SMOKE_HOLD and dist > 8.0 and dist < 45.0:
		_hold_t += delta
		_say("tient l'angle sur la fumée")
		inp.move = Vector2(_strafe_step(delta) * 0.35, 0.0)
		_try_items(dist)
		return
	# Back to the spot we last shot from: re-peek strafing, gun on the angle.
	if p.loaded and _peek_pos != Vector3.INF:
		_peek_t += delta
		if _peek_t >= 4.0:
			_peek_pos = Vector3.INF
		elif p.global_position.distance_to(_peek_pos) > 0.8:
			_say("re-peek")
			_move_to(_peek_pos, delta, false)
			return
	# Push the last known position from our flank.
	_say("pousse (flanc)")
	var dest := kp
	if dist > 14.0:
		var side := Vector3(-to.z, 0.0, to.x).normalized() * _flank * minf(10.0, dist * 0.35)
		dest = kp + side
	_move_to(dest, delta, dist > 25.0)


## Battle royale: head for the middle when the circle is closing on us.
func _zone_escape(delta: float) -> bool:
	var z := p.arena.zone
	if z == null:
		return false
	var over := z.overshoot(p.global_position)
	if over < -9.0 or (z.progress() <= 0.0 and over < -2.0):
		return false
	_say("zone")
	_move_to(p.arena.map.ground(Vector2(_rng.randf_range(-4, 4), _rng.randf_range(-4, 4))), delta, true)
	p.input.sprint = p.stamina > 20.0
	return true


## Out of fight or out of contact: heal / shield / revive / loot first. Returns true if busy.
func _tend_self(delta: float) -> bool:
	var inp := p.input
	if p.bandage_target != "" or p.shield_t >= 0.0:
		return true
	if not p.loaded:
		inp.reload = true
	var quiet := _t - _last_seen > 1.2
	if quiet and p.shield <= 0.0 and p.shield_charges > 0 and not p.is_channeling():
		inp.shield = true
		return true
	if quiet and p.bandages > 0 and p.health <= 60.0:
		inp.bandage = true
		return true
	return false


# ---------------------------------------------------------------- cover

## Runs to the nearest spot hidden from the threat (target's eye, or `threat`).
## False when there is none nearby.
func _go_to_cover(delta: float, threat := Vector3.INF) -> bool:
	var eye := threat
	if eye == Vector3.INF:
		eye = target.eye_position() if target else p.global_position
	_cover_eval -= delta
	if _cover_eval <= 0.0 or (_cover_pos != Vector3.INF and not _hidden_from(eye, _cover_pos)):
		_cover_eval = 0.6
		_cover_pos = _find_cover(eye)
	if _cover_pos == Vector3.INF:
		return false
	var d := Vector2(_cover_pos.x - p.global_position.x, _cover_pos.z - p.global_position.z).length()
	if d < 0.6:
		# In cover: keep the gun on the angle we'll peek.
		_pre_aim(eye, delta)
		return true
	_move_to(_cover_pos, delta, d > 3.0)
	if d <= 3.0:
		_pre_aim(eye, delta)
	return true


func _hidden_from(eye: Vector3, spot: Vector3) -> bool:
	var chest := spot + Vector3(0, 1.3, 0)
	if p.arena.is_sight_blocked(eye, chest):
		return true
	var q := PhysicsRayQueryParameters3D.create(eye, chest, 1)
	return not p.get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func _find_cover(eye: Vector3) -> Vector3:
	var map := p.get_world_3d().navigation_map
	if NavigationServer3D.map_get_iteration_id(map) == 0:
		return Vector3.INF
	var pos := p.global_position
	var away := Vector3(pos.x - eye.x, 0.0, pos.z - eye.z).normalized()
	for r in [2.5, 4.5, 7.0, 10.0]:
		var best := Vector3.INF
		var best_score := INF
		var a0 := _rng.randf() * TAU
		for k in 14:
			var ang: float = a0 + k * TAU / 14.0
			var dir := Vector3(cos(ang), 0.0, sin(ang))
			var c: Vector3 = pos + dir * r
			var snap := NavigationServer3D.map_get_closest_point(map, c)
			if Vector2(snap.x - c.x, snap.z - c.z).length() > 1.2 or absf(snap.y - pos.y) > 2.0:
				continue
			if not _hidden_from(eye, snap):
				continue
			# Prefer spots away from the enemy, never ones that close the distance a lot.
			var score: float = r - dir.dot(away) * r * 0.6
			if score < best_score:
				best_score = score
				best = snap
		if best != Vector3.INF:
			return best
	return Vector3.INF


# ---------------------------------------------------------------- aiming helpers

## Turns the gun onto `pt` (with skill-based error); returns the distance.
func _aim_at(pt: Vector3, delta: float, track: bool) -> float:
	# Compensate the slug's drop. No lead: hits resolve on the pose at the
	# moment of the shot (see Projectile._resolve_at_fire).
	var raw := pt - p.eye_position()
	var tof := raw.length() / Projectile.SPEED
	var to := raw + Vector3(0, 0.5 * Projectile.GRAVITY * tof * tof, 0)
	var want_yaw := atan2(-to.x, -to.z)
	var want_pitch := atan2(to.y, Vector2(to.x, to.z).length())
	if track:
		_err_t -= delta
		if _err_t <= 0.0:
			_err_t = 0.35
			var mag := lerpf(0.1, 0.01, clampf(_seen_time * skill * 0.8, 0.0, 1.0))
			mag *= (1.0 + target.velocity.length() * 0.08) * float(lvl.err)
			_err = Vector2(_rng.randf_range(-1, 1), _rng.randf_range(-0.6, 0.6)) * mag
	var turn := lerpf(4.5, 10.0, skill) * delta
	p.look_yaw = _approach_angle(p.look_yaw, want_yaw + (_err.x if track else 0.0), turn)
	p.look_pitch = move_toward(p.look_pitch, want_pitch + (_err.y if track else 0.0), turn * 0.7)
	return raw.length()


func _aim_off(pt: Vector3) -> float:
	var raw := pt - p.eye_position()
	var tof := raw.length() / Projectile.SPEED
	var to := raw + Vector3(0, 0.5 * Projectile.GRAVITY * tof * tof, 0)
	return absf(angle_difference(p.look_yaw, atan2(-to.x, -to.z))) + absf(p.look_pitch - atan2(to.y, Vector2(to.x, to.z).length()))


## Keeps the crosshair on where the enemy should appear (slower than tracking).
func _pre_aim(pt: Vector3, delta: float) -> void:
	var to := pt - p.eye_position()
	p.look_yaw = _approach_angle(p.look_yaw, atan2(-to.x, -to.z), lerpf(3.0, 6.0, skill) * delta)
	p.look_pitch = move_toward(p.look_pitch, atan2(to.y, Vector2(to.x, to.z).length()), 3.0 * delta)


func _strafe_step(delta: float) -> float:
	_strafe_t -= delta
	if _strafe_t <= 0.0:
		# Short, irregular ADAD: hard to track.
		_strafe_t = _rng.randf_range(0.3, 1.1)
		if _rng.randf() < 0.75:
			_strafe = -_strafe
	return _strafe


# ---------------------------------------------------------------- no contact

## Knocked down: crawl towards the nearest standing teammate (or away from the
## nearest enemy) and keep looking around.
func _crawl(delta: float) -> void:
	var best: Player = null
	var best_d := INF
	for o: Player in p.arena.players:
		if o != p and o.alive and o.team == p.team:
			var d := o.global_position.distance_to(p.global_position)
			if d < best_d:
				best_d = d
				best = o
	if best and best_d > 1.5:
		_follow(best.global_position, delta)
		p.input.sprint = false
		return
	var threat: Player = null
	for o: Player in p.arena.players:
		if o.team != p.team and o.alive and (threat == null or o.global_position.distance_to(p.global_position) < threat.global_position.distance_to(p.global_position)):
			threat = o
	if threat and not best:
		var away := p.global_position * 2.0 - threat.global_position
		_follow(away, delta)
		p.input.sprint = false


func _roam(delta: float) -> void:
	var inp := p.input
	if _zone_escape(delta):
		return
	if _tend_self(delta):
		return
	if p.revive_target != "":
		inp.interact = true
		return
	var safe := _t - _last_seen > 1.5
	# Pick up knocked-down teammates: defibrillator if carried, else hold [interact].
	var downed_ally := p.get_revive_candidate(30.0)
	if downed_ally and (safe or downed_ally.global_position.distance_to(p.global_position) < 6.0):
		var to_a := downed_ally.global_position - p.global_position
		var dist_a := Vector2(to_a.x, to_a.z).length()
		var defib := _slot_of("defib")
		if dist_a < (Player.DEFIB_RANGE - 0.4 if defib else Player.REVIVE_RANGE - 0.4):
			p.look_yaw = _approach_angle(p.look_yaw, atan2(-to_a.x, -to_a.z), 8.0 * delta)
			if defib:
				if p.held_item() == "" and p.revive_target == "":
					p.server_do_defib(defib, String(downed_ally.name))
			else:
				inp.interact = true
			return
		_follow(downed_ally.global_position, delta)
		return
	# Loot nearby crates when it's quiet and there's room in the bag.
	if _t - _last_seen > 3.0 and _has_room():
		var chest := p.arena.nearest_chest(p.global_position, 28.0)
		if chest:
			var to_c := chest.global_position - p.global_position
			if Vector2(to_c.x, to_c.z).length() < 1.5:
				p.look_yaw = _approach_angle(p.look_yaw, atan2(-to_c.x, -to_c.z), 8.0 * delta)
				inp.interact = true
				return
			_follow(chest.global_position, delta)
			return
	var ally := _hurt_ally()
	if ally and p.bandages > 0 and safe:
		if ally.global_position.distance_to(p.global_position) < 2.3:
			var to := ally.global_position - p.global_position
			p.look_yaw = _approach_angle(p.look_yaw, atan2(-to.x, -to.z), 8.0 * delta)
			inp.bandage = true
			return
		_follow(ally.global_position, delta)
		return
	_say("chasse")
	_follow(_hunt_dest(), delta)


## Nothing known: head for the rough area of the nearest enemy (a hunch, ±15 m,
## renewed every few seconds), so rounds don't stall.
func _hunt_dest() -> Vector3:
	_hunt_t -= get_physics_process_delta_time()
	if _hunt_pos == Vector3.INF or _hunt_t <= 0.0 or p.global_position.distance_to(_hunt_pos) < 4.0:
		_hunt_t = _rng.randf_range(5.0, 8.0)
		var near: Player = null
		for o: Player in p.arena.players:
			if o.team != p.team and o.is_hittable() and (near == null or o.global_position.distance_to(p.global_position) < near.global_position.distance_to(p.global_position)):
				near = o
		if near == null:
			return p.global_position
		var fuzz := clampf(near.global_position.distance_to(p.global_position) * 0.3, 4.0, 15.0)
		_hunt_pos = near.global_position + Vector3(_rng.randf_range(-fuzz, fuzz), 0.0, _rng.randf_range(-fuzz, fuzz))
		var z := p.arena.zone
		if z and Vector2(_hunt_pos.x, _hunt_pos.z).length() > z.radius() - 6.0:
			_hunt_pos = p.arena.map.ground(Vector2(_hunt_pos.x, _hunt_pos.z).limit_length(maxf(z.radius() - 6.0, 2.0)))
	return _hunt_pos


func _hurt_ally() -> Player:
	for o: Player in p.arena.players:
		if o != p and o.alive and o.team == p.team and o.health <= 50.0 and o.global_position.distance_to(p.global_position) < 25.0:
			return o
	return null


# ---------------------------------------------------------------- locomotion

func _follow(dest: Vector3, delta: float) -> void:
	_move_to(dest, delta, true)


## Walks the navmesh path to `dest`. face = turn towards the path (and sprint
## when far); otherwise move relative to where we're already looking (strafe-peek).
func _move_to(dest: Vector3, delta: float, face: bool) -> void:
	var pos := p.global_position
	_repath -= delta
	if _repath <= 0.0 or _path_i >= _path.size() or _path_dest.distance_to(dest) > 1.5:
		_repath = 0.8
		_path_dest = dest
		var map := p.get_world_3d().navigation_map
		if NavigationServer3D.map_get_iteration_id(map) > 0:
			_path = NavigationServer3D.map_get_path(map, pos, dest, true)
		else:
			_path = PackedVector3Array()
		if _path.size() < 2:
			_path = PackedVector3Array([pos, dest])
		_path_i = 1
	var next := dest
	while _path_i < _path.size():
		next = _path[_path_i]
		if Vector2(next.x - pos.x, next.z - pos.z).length() < 0.9:
			_path_i += 1
			continue
		break
	var to := next - pos
	to.y = 0.0
	if to.length() < 0.3:
		return
	if face:
		var want_yaw := atan2(-to.x, -to.z)
		p.look_yaw = _approach_angle(p.look_yaw, want_yaw, 6.0 * delta)
		p.look_pitch = move_toward(p.look_pitch, 0.0, delta)
	var local := Basis(Vector3.UP, p.look_yaw).inverse() * to.normalized()
	p.input.move = Vector2(local.x, local.z)
	p.input.sprint = face and dest.distance_to(pos) > 18.0 and p.stamina > 25.0 and _t - _last_seen > 2.0
	_movement_tricks(local)
	if _unstick > 0.0:
		_unstick -= delta
		p.input.move = Vector2(_strafe, -1.0).normalized()


## Vault low obstacles in the way and slide now and then out of a sprint,
## like players do (the Player decides whether the move is actually possible).
func _movement_tricks(local_move: Vector3) -> void:
	if p.slide_t >= 0.0 or p.mantle_t >= 0.0 or p.roll_t >= 0.0:
		return
	var hv := Vector3(p.velocity.x, 0.0, p.velocity.z)
	if hv.length() > 3.0:
		var dir := hv.normalized()
		var from := p.global_position + Vector3.UP * 0.7
		var q := PhysicsRayQueryParameters3D.create(from, from + dir * 1.1, 1, [p.get_rid()])
		var hit := p.get_world_3d().direct_space_state.intersect_ray(q)
		if hit and absf(hit.normal.y) < 0.5:
			p.input.jump = true
			return
	if p.sprinting and hv.length() > 5.6 and local_move.z < -0.7 and _rng.randf() < 0.004 * (1.0 + skill):
		p.input.crouch = true


func _check_stuck(delta: float) -> void:
	_stuck_t += delta
	if _stuck_t < 1.2:
		return
	var moved := p.global_position.distance_to(_last_pos)
	if p.input.move.length() > 0.5 and moved < 0.5 and p.bandage_target == "" and p.roll_t < 0.0:
		p.input.jump = true
		_unstick = 0.6
		_strafe = -_strafe
		_repath = 0.0
		_cover_pos = Vector3.INF
		_peek_pos = Vector3.INF
	_stuck_t = 0.0
	_last_pos = p.global_position


# ---------------------------------------------------------------- items

func _slot_of(id: String) -> int:
	for i in p.inventory.size():
		var s: Dictionary = p.inventory[i]
		if not s.is_empty() and s.id == id:
			return i + 1
	return 0


func _has_room() -> bool:
	for s in p.inventory:
		if s.is_empty():
			return true
	return false


## Velocity that lobs a grenade from the bot's hand onto `target`.
func _lob(at: Vector3) -> Vector3:
	var origin := p.eye_position()
	var d := at - origin
	var flat := Vector2(d.x, d.z).length()
	var tt := clampf(flat / 13.0, 0.55, 1.8)
	var v := d / tt
	v.y += 0.5 * Grenade.GRAVITY * tt
	return v


func _try_items(dist: float) -> void:
	if _t < _next_item_t or p.held_item() != "" or not p.arena.match_allows_fire():
		return
	# Aim the nade at what we know, not at the enemy's true position.
	var tp := target.global_position if _visible else _known_pos(target)
	var tv := target.velocity if _visible else Vector3.ZERO
	var to := tp - p.global_position
	var smoke := _slot_of("smoke")
	if smoke and _visible and p.health <= 50.0 and dist < 40.0:
		p.use_item(smoke, _lob(p.global_position + to.normalized() * 4.0))
		_retreat_t = 3.5
		_next_item_t = _t + 8.0
		return
	var frag := _slot_of("frag")
	var hiding := not _visible and _hold_t > 1.0
	if frag and dist > 10.0 and dist < 32.0 and (hiding or not p.loaded or _rng.randf() < 0.01):
		p.use_item(frag, _lob(tp + tv * 0.6))
		_next_item_t = _t + 6.0
		return
	var bar := _slot_of("barricade")
	if bar and _visible and not p.loaded and dist > 12.0 and p.is_on_floor() and _cover_pos == Vector3.INF:
		p.use_item(bar)
		_next_item_t = _t + 8.0


static func _approach_angle(a: float, b: float, step: float) -> float:
	return a + clampf(angle_difference(a, b), -step, step)
