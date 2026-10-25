class_name Monster
extends CharacterBody3D
## One zombie-mode monster. The server simulates it (AI, movement, attacks, health); every peer,
## the server included, shows it through a MonsterRig and keeps bullet hit bodies on it.
## Clients just follow the server's snapshots (see MonsterManager).
##
## Faucheur (kind 0): tall, slow, arms that reach the ground. Hacks at 3.6 m, and from 4.5-10 m
## rakes the ground in a long line (telegraphed by raised claws) that tears whoever stands in it.
## Bondisseur (kind 1): fast and hunched; crouches, then pounces from 5-13 m onto where its
## prey is heading; claws when close.
## Rôdeur (kind 2): slow walker that shambles straight at the nearest survivor and grabs / bites
## at arm's length; dies to one head shot early on.

const STATES := ["idle", "walk", "run", "windup", "strike", "recover", "crouch", "leap", "land", "stagger", "spawn", "dead"]
const GRAVITY := 24.0
const WEAPON_NAMES := ["FAUCHEUR", "BONDISSEUR", "RÔDEUR"]

var id := 0
var kind := 0
var data: Dictionary
var hp := 100.0
var max_hp := 100.0
var alive := true
var state := "spawn"
var rig: MonsterRig
var manager: MonsterManager

# Puppet (clients)
var net_pos := Vector3.ZERO
var net_yaw := 0.0
var _last_pos := Vector3.ZERO

# Server AI
var target: Player
var _t_state := 0.0
var _atk_cd := 1.0
var _special_cd := 3.0
var _attack := ""
var _path := PackedVector3Array()
var _path_i := 0
var _repath := 0.0
var _retarget := 0.0
var _strafe := 1.0
var _growl := randf_range(2.0, 6.0)
var _stuck_t := 0.0
var _los := false
var _los_t := 0.0
var _hit_bodies: Array = []
var _hit_shapes: Array = []
var _head_body: StaticBody3D
var _body_body: StaticBody3D
var _removing := -1.0


func setup(p_id: int, p_kind: int, p_manager: MonsterManager) -> void:
	id = p_id
	kind = p_kind
	manager = p_manager
	data = MonsterRig.kind_data(kind)
	max_hp = float(data.hp)
	hp = max_hp
	name = "M%d" % id
	tree_exiting.connect(func(): manager.monsters.erase(id))
	rig = MonsterRig.new()
	add_child(rig)
	rig.setup(kind)
	rig.set_state("spawn")
	# Layer 4 "monsters": players bump into it on every peer. Only the server moves it, so only
	# the server's body collides with the world, players and other monsters.
	collision_layer = 8
	collision_mask = 0
	if multiplayer.is_server():
		collision_mask = 1 | 2 | 8
		var cs := CollisionShape3D.new()
		var cap := CapsuleShape3D.new()
		cap.radius = float(data.radius)
		cap.height = [1.8, 1.3, 1.7][kind]
		cs.shape = cap
		cs.position.y = cap.height * 0.5
		add_child(cs)
		floor_snap_length = 0.5
		floor_max_angle = deg_to_rad(50.0)
	_build_hit_bodies()
	net_pos = global_position
	_last_pos = global_position


func _build_hit_bodies() -> void:
	# Bullets hit a head sphere and a body capsule that follow the animated skeleton.
	_head_body = _hit_body("head", SphereShape3D.new(), 0.27 * float(data.scale))
	_body_body = _hit_body("body", CapsuleShape3D.new(), 0.42 * float(data.scale))


func _hit_body(zone: String, shape: Shape3D, radius: float) -> StaticBody3D:
	var b := StaticBody3D.new()
	b.top_level = true
	b.collision_layer = Hitboxes.LAYER
	b.collision_mask = 0
	b.set_meta("monster", self)
	b.set_meta("zone", zone)
	var cs := CollisionShape3D.new()
	if shape is SphereShape3D:
		(shape as SphereShape3D).radius = radius
	else:
		(shape as CapsuleShape3D).radius = radius
		(shape as CapsuleShape3D).height = 1.2
	cs.shape = shape
	b.add_child(cs)
	add_child(b)
	return b


func _sync_hit_bodies() -> void:
	if not alive or rig == null or rig.skeleton == null:
		_head_body.collision_layer = 0
		_body_body.collision_layer = 0
		return
	_head_body.collision_layer = Hitboxes.LAYER
	_body_body.collision_layer = Hitboxes.LAYER
	var sk := rig.skeleton
	var gx := sk.global_transform
	var head := gx * sk.get_bone_global_pose(int(data.head)).origin
	var neck := gx * sk.get_bone_global_pose(int(data.neck)).origin
	var hips := gx * sk.get_bone_global_pose(int(data.hips)).origin
	_head_body.global_position = head + (head - neck).normalized() * 0.05
	var axis := neck - hips
	var length := axis.length()
	if length < 0.05:
		return
	var cap := (_body_body.get_child(0) as CollisionShape3D).shape as CapsuleShape3D
	cap.height = length + cap.radius * 2.0
	var y := axis / length
	var ref := Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
	var x := y.cross(ref).normalized()
	_body_body.global_transform = Transform3D(Basis(x, y, x.cross(y)), (hips + neck) * 0.5)


func set_state(s: String) -> void:
	if s == state:
		return
	var prev := state
	state = s
	_t_state = 0.0
	rig.set_state(s)
	_on_state(s, prev)


func state_index() -> int:
	return maxi(STATES.find(state), 0)


## Sounds on state changes (every peer plays its own).
func _on_state(s: String, _prev: String) -> void:
	var pos := global_position + Vector3(0, 1.2, 0)
	match s:
		"windup":
			Audio.play_3d("mon_growl", pos, 3.0, 60.0, 0.08, [0.85, 1.3, 0.7][kind])
		"strike":
			Audio.play_3d("mon_swipe", pos, 2.0, 40.0, 0.1, [0.8, 1.1, 0.9][kind])
		"crouch":
			Audio.play_3d("mon_growl", pos, 2.0, 55.0, 0.05, 1.6)
		"leap":
			Audio.play_3d("mon_screech", pos, 4.0, 70.0, 0.06)
		"land":
			Audio.play_3d("mon_slam", global_position, 2.0, 55.0, 0.08)
		"dead":
			collision_layer = 0
			Audio.play_3d("mon_death", pos, 4.0, 65.0, 0.06, [0.8, 1.1, 0.7][kind])
		"spawn":
			Audio.play_3d("mon_growl", pos, 1.0, 55.0, 0.05, 0.7)


func _process(delta: float) -> void:
	_sync_hit_bodies()
	if _removing >= 0.0:
		_removing += delta
		# Sinks into the ground before it disappears.
		rig.position.y = -minf(_removing * 0.25, 1.2)
		if _removing > 4.0:
			queue_free()


func _physics_process(delta: float) -> void:
	var moved := global_position.distance_to(_last_pos)
	_last_pos = global_position
	var vel := moved / maxf(delta, 0.0001)
	if multiplayer.is_server():
		if alive:
			_ai(delta)
	else:
		global_position = global_position.lerp(net_pos, 1.0 - exp(-delta * 14.0))
		rotation.y = lerp_angle(rotation.y, net_yaw, 1.0 - exp(-delta * 14.0))
	rig.tick(delta, minf(vel, 9.0), moved)
	if not multiplayer.is_server() and alive:
		# Locomotion states are derived from the speed on the puppet side too.
		pass


# ---------------------------------------------------------------- server: AI

func _ai(delta: float) -> void:
	_t_state += delta
	_atk_cd = maxf(0.0, _atk_cd - delta)
	_special_cd = maxf(0.0, _special_cd - delta)
	_growl -= delta
	_retarget -= delta
	if _retarget <= 0.0:
		_retarget = 0.4
		_pick_target()
	if _growl <= 0.0 and state in ["walk", "run", "idle"]:
		_growl = randf_range(4.0, 9.0)
		manager.server_sound(id, "mon_growl")
	match state:
		"spawn":
			if _t_state >= 1.4:
				set_state("idle")
		"windup":
			# The rake is aimed once (the red strip shows where): sidestep it.
			if _attack != "rake":
				_face_target(delta, 10.0)
			if kind == 2 and target:
				# Keeps shuffling in while it lunges, so stepping back a little is not enough.
				_steer(target.global_position, 0.9, delta)
				_gravity(delta)
				move_and_slide()
			else:
				_stand(delta)
			if _t_state >= _windup_time():
				_do_strike()
		"strike":
			_stand(delta)
			if _t_state >= 0.2:
				set_state("recover")
		"recover":
			_stand(delta)
			if _t_state >= [0.55, 0.25, 0.7][kind]:
				set_state("idle")
		"crouch":
			_face_target(delta, 14.0)
			_stand(delta)
			if _t_state >= 0.45:
				_begin_leap()
		"leap":
			_leap_step(delta)
		"land":
			_stand(delta)
			if _t_state >= 0.45:
				set_state("idle")
		"stagger":
			_stand(delta)
			if _t_state >= 0.35:
				set_state("idle")
		_:
			_hunt(delta)


func _pick_target() -> void:
	var best: Player = null
	var best_d := INF
	for p: Player in manager.arena.players:
		if not p.alive and not p.downed:
			continue
		# Standing players first; the fallen only when nobody is up.
		var d := p.global_position.distance_to(global_position) + (60.0 if p.downed else 0.0)
		if d < best_d:
			best_d = d
			best = p
	target = best


func _flat_to(pos: Vector3) -> Vector3:
	var v := pos - global_position
	v.y = 0.0
	return v


func _face_target(delta: float, rate: float) -> void:
	if target == null:
		return
	var v := _flat_to(target.global_position)
	if v.length() > 0.05:
		rotation.y = lerp_angle(rotation.y, atan2(-v.x, -v.z), 1.0 - exp(-delta * rate))


func _stand(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, 30.0 * delta)
	velocity.z = move_toward(velocity.z, 0.0, 30.0 * delta)
	_gravity(delta)
	move_and_slide()


func _gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = maxf(velocity.y, -1.0)


func _windup_time() -> float:
	if kind == 0:
		return 0.9 if _attack == "rake" else 0.55
	return 0.28 if kind == 1 else 0.5


func _hunt(delta: float) -> void:
	if target == null:
		set_state("idle")
		_stand(delta)
		return
	var to := _flat_to(target.global_position)
	var dist := to.length()
	_los_t -= delta
	if _los_t <= 0.0:
		_los_t = 0.15
		_los = _los_to(target)
	var los := _los
	# ---- attacks
	if kind == 0:
		if dist <= 3.4 and _atk_cd <= 0.0:
			_attack = "melee"
			set_state("windup")
			return
		if dist >= 4.5 and dist <= 10.0 and _special_cd <= 0.0 and los:
			_attack = "rake"
			rotation.y = atan2(-to.x, -to.z)
			manager.server_fx(id, "rake_tele", global_position, _forward())
			set_state("windup")
			return
	elif kind == 2:
		# The Rôdeur has one trick: reach the prey and grab it.
		if dist <= 1.7 and _atk_cd <= 0.0:
			_attack = "melee"
			set_state("windup")
			return
	else:
		if dist <= 1.9 and _atk_cd <= 0.0:
			_attack = "melee"
			set_state("windup")
			return
		if dist >= 5.0 and dist <= 13.0 and _special_cd <= 0.0 and los and is_on_floor():
			_attack = "leap"
			set_state("crouch")
			return
	# ---- movement
	var speed := float(data.speed)
	if kind == 0:
		# Stalks, then lopes faster across open ground.
		speed = float(data.speed) * (1.45 if dist > 14.0 else 1.0)
	var want_state := "run" if speed > 3.4 else "walk"
	set_state(want_state)
	var stop_at: float = [2.2, 1.3, 1.0][kind]
	if dist > stop_at:
		_steer(target.global_position, speed, delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, 25.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 25.0 * delta)
		_face_target(delta, 12.0)
	_gravity(delta)
	move_and_slide()
	# Stuck on geometry: jink sideways, re-plan.
	_stuck_t += delta
	if _stuck_t >= 1.0:
		_stuck_t = 0.0
		if Vector2(velocity.x, velocity.z).length() < 0.6 and dist > stop_at + 0.5:
			_strafe = -_strafe
			_repath = 0.0


func _steer(dest: Vector3, speed: float, delta: float) -> void:
	_repath -= delta
	var map := get_world_3d().navigation_map
	if _repath <= 0.0 or _path_i >= _path.size():
		_repath = 0.45
		if NavigationServer3D.map_get_iteration_id(map) > 0:
			_path = NavigationServer3D.map_get_path(map, global_position, dest, true)
		else:
			_path = PackedVector3Array()
		if _path.size() < 2:
			_path = PackedVector3Array([global_position, dest])
		_path_i = 1
	var next := dest
	while _path_i < _path.size():
		next = _path[_path_i]
		if Vector2(next.x - global_position.x, next.z - global_position.z).length() < 0.8:
			_path_i += 1
			continue
		break
	var dir := _flat_to(next).normalized()
	# Hunting packs spread out instead of stacking up on one line.
	var sep := Vector3.ZERO
	for m: Monster in manager.alive_list():
		if m != self:
			var away := global_position - m.global_position
			away.y = 0.0
			var d := away.length()
			if d < 1.6 and d > 0.01:
				sep += away / d * (1.6 - d)
	dir = (dir + sep * 0.8).normalized()
	if kind == 1:
		# The Bondisseur weaves from side to side while it closes in.
		var side := Vector3(-dir.z, 0.0, dir.x)
		dir = (dir + side * sin(Time.get_ticks_msec() * 0.004 + id) * 0.35 * _strafe).normalized()
	var want := dir * speed
	velocity.x = move_toward(velocity.x, want.x, 22.0 * delta)
	velocity.z = move_toward(velocity.z, want.z, 22.0 * delta)
	if dir.length() > 0.1:
		rotation.y = lerp_angle(rotation.y, atan2(-dir.x, -dir.z), 1.0 - exp(-delta * 9.0))


func _los_to(p: Player) -> bool:
	var from := global_position + Vector3(0, 1.4, 0)
	var q := PhysicsRayQueryParameters3D.create(from, p.chest_position(), 1)
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func _forward() -> Vector3:
	return Vector3(-sin(rotation.y), 0.0, -cos(rotation.y))


func _do_strike() -> void:
	set_state("strike")
	_atk_cd = [1.2, 0.7, 1.3][kind]
	var fwd := _forward()
	if _attack == "rake":
		_special_cd = 6.5
		manager.server_fx(id, "rake", global_position + fwd * 1.0, fwd)
		for p: Player in manager.arena.players:
			if not (p.alive or p.downed):
				continue
			var rel := p.global_position - global_position
			rel.y = 0.0
			var along := rel.dot(fwd)
			var lateral := absf(rel.cross(fwd).y)
			if along > 1.0 and along < 11.0 and lateral < 1.0 and _los_to(p):
				_hurt(p, 32.0)
		return
	var reach: float = [3.8, 2.2, 1.9][kind]
	for p: Player in manager.arena.players:
		if not (p.alive or p.downed):
			continue
		var rel := p.global_position - global_position
		rel.y = 0.0
		if rel.length() < reach and (rel.length() < 0.8 or rel.normalized().dot(fwd) > 0.15):
			_hurt(p, [42.0, 20.0, 26.0][kind])


func _hurt(p: Player, amount: float) -> void:
	amount *= Shop.armor_mult(p.upgrades)
	p.server_apply_damage(amount, null, false, WEAPON_NAMES[kind], global_position + Vector3(0, 1.2, 0), Vector3.INF)


func _begin_leap() -> void:
	if target == null:
		set_state("idle")
		return
	var tp := target.global_position + Vector3(target.velocity.x, 0.0, target.velocity.z) * 0.3
	var flight := 0.62
	var v := _flat_to(tp) / flight
	v = v.limit_length(20.0)
	velocity = Vector3(v.x, GRAVITY * flight * 0.5 + 0.8, v.z)
	rotation.y = atan2(-v.x, -v.z)
	_special_cd = 4.5
	set_state("leap")


func _leap_step(delta: float) -> void:
	velocity.y -= GRAVITY * delta
	move_and_slide()
	if _t_state > 0.12 and is_on_floor():
		# Landing: claws and weight on whoever is under it.
		for p: Player in manager.arena.players:
			if (p.alive or p.downed) and p.global_position.distance_to(global_position) < 2.1:
				_hurt(p, 28.0)
		manager.server_fx(id, "land", global_position, Vector3.UP)
		velocity = Vector3.ZERO
		set_state("land")
	elif _t_state > 1.6:
		set_state("idle")


# ---------------------------------------------------------------- server: taking damage

## `amount` of damage from `attacker` (a Player); returns true if this killed it.
func server_damage(amount: float, attacker: Player, headshot: bool) -> bool:
	if not alive:
		return false
	hp -= amount
	manager.server_flash(id)
	if hp <= 0.0:
		_die(attacker)
		return true
	# A solid hit rocks the Faucheur a little; the Bondisseur is too quick to care unless it is
	# mid-air (a hit there does nothing special).
	if state in ["idle", "walk", "run", "recover"] and (headshot or amount >= 90.0):
		set_state("stagger")
	return false


func _die(attacker: Player) -> void:
	alive = false
	velocity = Vector3.ZERO
	set_state("dead")
	collision_layer = 0
	collision_mask = 0
	manager.server_on_death(self, attacker)
	_removing = 0.0


## Puppet: apply the server's authoritative values.
func apply_snapshot(pos: Vector3, yaw: float, state_i: int, hp_frac: float) -> void:
	net_pos = pos
	net_yaw = yaw
	hp = hp_frac * max_hp
	var s: String = STATES[clampi(state_i, 0, STATES.size() - 1)]
	if s != state:
		set_state(s)


func mark_dead_local() -> void:
	if alive:
		alive = false
		set_state("dead")
		_removing = 0.0
