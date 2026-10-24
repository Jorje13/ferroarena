class_name MonsterManager
extends Node
## Zombie survival: wave director (server) and monster replication (all peers).
## The server spawns the monsters, runs their AI and sends their state ~20 times a second;
## clients show puppets that follow it. A wave is a batch of Bondisseurs (fast, many) and
## Faucheurs (tanks, long reach) that grows each time; between waves the dead come back, the
## knocked-down are picked up, and the crates are restocked. Surviving WAVES waves wins.

const WAVES := 10
const PLAYER_DAMAGE_MULT := 2.0
const BREAK_TIME := 14.0
const FIRST_DELAY := 4.0
const SNAPSHOT_HZ := 20.0

enum Phase { IDLE, WAVE, BREAK, DONE }

var arena: Arena
var monsters := {}
var wave := 0
var phase := Phase.IDLE
var break_t := 0.0
## Remaining enemies of the current wave (alive + still to spawn), shown by the HUD.
var left := 0
var total := 0

var _next_id := 1
var _queue: Array = []
var _spawn_cd := 0.0
var _snap_t := 0.0
var _rng := RandomNumberGenerator.new()

signal wave_changed


func _ready() -> void:
	arena = get_parent() as Arena
	_rng.randomize()


# ---------------------------------------------------------------- queries

func get_monster(id: int) -> Monster:
	var m = monsters.get(id)
	return m if m != null and is_instance_valid(m) else null


func alive_list() -> Array:
	var out := []
	for m: Monster in monsters.values():
		if is_instance_valid(m) and m.alive:
			out.append(m)
	return out


# ---------------------------------------------------------------- server: waves

## Round start: wipe everything.
func server_reset() -> void:
	for id in monsters.keys():
		_net_remove.rpc(id)
	_queue.clear()
	wave = 0
	phase = Phase.IDLE
	left = 0
	total = 0
	_sync_wave()


func server_go() -> void:
	wave = 0
	phase = Phase.BREAK
	break_t = FIRST_DELAY
	_sync_wave()


func _plan_wave(w: int) -> Array:
	var n := maxi(1, arena.players.size())
	var scale := 0.75 + 0.25 * n
	var count := int((2.5 + 2.5 * w) * scale)
	var fauch := int(float(w) * 0.55 * (0.8 + 0.2 * n))
	if w < 2:
		fauch = 0
	fauch = mini(fauch, count / 2)
	var list := []
	for i in count:
		list.append(0 if i < fauch else 1)
	# Tanks come in last half of the wave, packs first: shuffle only within thirds.
	list.shuffle()
	return list


func _hp_scale() -> float:
	return 1.0 + 0.1 * float(wave - 1)


func _server_start_wave() -> void:
	wave += 1
	_queue = _plan_wave(wave)
	total = _queue.size()
	left = total
	phase = Phase.WAVE
	_spawn_cd = 1.5
	_sync_wave()


func _server_break() -> void:
	phase = Phase.BREAK
	break_t = BREAK_TIME
	# Dead come back, knocked-down are picked up, everyone gets a little shield back.
	var sp_i := 0
	for p: Player in arena.players:
		if p.alive:
			p.net_health.rpc(minf(Player.MAX_HEALTH, p.health + 40.0), maxf(p.shield, Player.MAX_SHIELD * 0.5), p.global_position, false)
		elif p.downed:
			p.net_revived.rpc(Player.MAX_HEALTH * 0.6, "")
		else:
			var live: Player = null
			for o: Player in arena.players:
				if o.alive:
					live = o
					break
			var sp := arena.map.get_spawn(0, sp_i, arena.players.size())
			var pos: Vector3 = sp.pos
			if live:
				pos = live.global_position + Vector3(1.5, 0, 0).rotated(Vector3.UP, sp_i * 1.3)
			p.net_respawn.rpc(pos, sp.yaw)
		sp_i += 1
	arena.server_round_reset()
	_sync_wave()


func _process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	if arena.match_mgr.state != MatchManager.State.LIVE:
		return
	match phase:
		Phase.BREAK:
			break_t -= delta
			if break_t <= 0.0:
				_server_start_wave()
		Phase.WAVE:
			_spawn_cd -= delta
			var cap := 12 + 2 * arena.players.size()
			if not _queue.is_empty() and _spawn_cd <= 0.0 and alive_list().size() < cap:
				_spawn_cd = clampf(1.4 - 0.08 * wave, 0.45, 1.4)
				_server_spawn(_queue.pop_back())
			if _queue.is_empty() and alive_list().is_empty():
				if wave >= WAVES:
					phase = Phase.DONE
					_sync_wave()
					arena.match_mgr.server_end_round(0)
				else:
					_server_break()
	_snap_t += delta
	if _snap_t >= 1.0 / SNAPSHOT_HZ:
		_snap_t = 0.0
		_send_snapshot()


## A random navmesh point out of the survivors' sight and a good way off.
func _spawn_point() -> Vector3:
	var map := arena.get_world_3d().navigation_map
	var space := arena.get_world_3d().direct_space_state
	var best := Vector3.INF
	var best_score := -INF
	for i in 24:
		var c := NavigationServer3D.map_get_random_point(map, 1, true)
		if c == Vector3.ZERO:
			continue
		var nearest := INF
		var seen := false
		for p: Player in arena.players:
			if not (p.alive or p.downed):
				continue
			var d := p.global_position.distance_to(c)
			nearest = minf(nearest, d)
			if d < 60.0 and not seen:
				var q := PhysicsRayQueryParameters3D.create(c + Vector3(0, 1.6, 0), p.chest_position(), 1)
				seen = space.intersect_ray(q).is_empty()
		if nearest == INF:
			nearest = 40.0
		var score := minf(nearest, 55.0) - (45.0 if seen else 0.0) - (60.0 if nearest < 22.0 else 0.0) + _rng.randf() * 6.0
		if score > best_score:
			best_score = score
			best = c
	if best == Vector3.INF:
		var sp := arena.map.get_spawn(1, _rng.randi(), 1)
		return sp.pos
	return best


func _server_spawn(kind: int) -> void:
	var pos := _spawn_point()
	var yaw := _rng.randf() * TAU
	var id := _next_id
	_next_id += 1
	var m := _make(id, kind, pos, yaw)
	m.max_hp *= _hp_scale()
	m.hp = m.max_hp
	_net_spawn.rpc(id, kind, pos, yaw)
	m.set_state("spawn")


func _make(id: int, kind: int, pos: Vector3, yaw: float) -> Monster:
	var m := Monster.new()
	m.manager = self
	add_child(m)
	m.setup(id, kind, self)
	m.global_position = pos
	m.rotation.y = yaw
	m.net_pos = pos
	m.net_yaw = yaw
	monsters[id] = m
	return m


@rpc("authority", "call_remote", "reliable")
func _net_spawn(id: int, kind: int, pos: Vector3, yaw: float) -> void:
	_make(id, kind, pos, yaw).set_state("spawn")


@rpc("authority", "call_local", "reliable")
func _net_remove(id: int) -> void:
	var m := get_monster(id)
	if m:
		m.queue_free()
	monsters.erase(id)


func server_on_death(m: Monster, attacker: Player) -> void:
	left = maxi(0, left - 1)
	if attacker and arena.match_mgr.stats.has(String(attacker.name)):
		arena.match_mgr.stats[String(attacker.name)].k += 1
		arena.match_mgr._sync_stats()
	_net_dead.rpc(m.id)
	_sync_wave()


@rpc("authority", "call_remote", "reliable")
func _net_dead(id: int) -> void:
	var m := get_monster(id)
	if m:
		m.mark_dead_local()


# ---------------------------------------------------------------- replication

func _send_snapshot() -> void:
	if monsters.is_empty():
		return
	var data := []
	for m: Monster in monsters.values():
		if is_instance_valid(m) and m.alive:
			data.append([m.id, m.global_position, m.rotation.y, m.state_index(), m.hp / m.max_hp])
	if not data.is_empty():
		_net_snapshot.rpc(data)


@rpc("authority", "call_remote", "unreliable")
func _net_snapshot(data: Array) -> void:
	for e in data:
		var m := get_monster(int(e[0]))
		if m and m.alive:
			m.apply_snapshot(e[1], float(e[2]), int(e[3]), float(e[4]))


func _sync_wave() -> void:
	_net_wave.rpc(wave, phase, break_t, left, total)


@rpc("authority", "call_local", "reliable")
func _net_wave(w: int, ph: int, bt: float, l: int, t: int) -> void:
	var new_wave := w != wave or ph != phase
	wave = w
	phase = ph as Phase
	break_t = bt
	left = l
	total = t
	if new_wave and phase == Phase.WAVE:
		Audio.play_2d("round", -2.0, 0.7)
	wave_changed.emit()


func server_flash(id: int) -> void:
	_net_flash.rpc(id)


@rpc("authority", "call_local", "unreliable")
func _net_flash(id: int) -> void:
	var m := get_monster(id)
	if m:
		m.rig.hit_flash()


func server_sound(id: int, snd: String) -> void:
	_net_sound.rpc(id, snd)


@rpc("authority", "call_local", "unreliable")
func _net_sound(id: int, snd: String) -> void:
	var m := get_monster(id)
	if m:
		Audio.play_3d(snd, m.global_position + Vector3(0, 1.2, 0), 1.0, 60.0, 0.1, 1.0 if m.kind == 1 else 0.8)


func server_fx(id: int, kind: String, pos: Vector3, dir: Vector3) -> void:
	_net_fx.rpc(id, kind, pos, dir)


@rpc("authority", "call_local", "reliable")
func _net_fx(_id: int, kind: String, pos: Vector3, dir: Vector3) -> void:
	match kind:
		"rake_tele":
			_rake_line(pos, dir)
		"rake":
			for i in 8:
				var p := pos + dir * (1.2 + i * 1.25)
				get_tree().create_timer(i * 0.045).timeout.connect(func(): FX.impact(p, Vector3.UP))
			Audio.play_3d("mon_slam", pos + dir * 3.0, 3.0, 70.0, 0.08, 1.2)
			if arena.camera_rig and arena.local_player and arena.local_player.global_position.distance_to(pos) < 14.0:
				arena.camera_rig.kick(0.5)
		"land":
			FX.impact(pos, Vector3.UP)
			if arena.camera_rig and arena.local_player and arena.local_player.global_position.distance_to(pos) < 10.0:
				arena.camera_rig.kick(0.3)


## Red warning strip on the ground along a Faucheur's coming rake.
func _rake_line(pos: Vector3, dir: Vector3) -> void:
	var space := arena.get_world_3d().direct_space_state
	var mi := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 10.5)
	quad.orientation = PlaneMesh.FACE_Y
	mi.mesh = quad
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 0.1, 0.05, 0.28)
	mat.no_depth_test = false
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	arena.add_child(mi)
	var mid := pos + dir * 6.3
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(mid + Vector3.UP * 3.0, mid + Vector3.DOWN * 6.0, 1))
	mid.y = (hit.position.y if hit else pos.y) + 0.08
	mi.global_position = mid
	mi.rotation.y = atan2(-dir.x, -dir.z)
	var tw := mi.create_tween()
	tw.tween_property(mat, "albedo_color:a", 0.55, 0.85)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.25)
	tw.tween_callback(mi.queue_free)


# ---------------------------------------------------------------- grenades

func server_explosion(thrower: Player, pos: Vector3) -> void:
	var space := arena.get_world_3d().direct_space_state
	var origin := pos + Vector3(0, 0.25, 0)
	for m: Monster in alive_list():
		var target := m.global_position + Vector3(0, 1.0, 0)
		var d := origin.distance_to(target)
		if d > Items.FRAG_RADIUS + 1.0:
			continue
		if space.intersect_ray(PhysicsRayQueryParameters3D.create(origin, target, 1)):
			continue
		var t := clampf((d - Items.FRAG_FULL_RADIUS) / (Items.FRAG_RADIUS - Items.FRAG_FULL_RADIUS), 0.0, 1.0)
		m.server_damage(lerpf(Items.FRAG_MAX_DAMAGE, Items.FRAG_MIN_DAMAGE, t) * 1.4, thrower, false)
