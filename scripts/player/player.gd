class_name Player
extends CharacterBody3D
## Raider: movement, Ferro rifle, shield, bandages, knock-down / revive.
## Same script for humans and bots.
##
## Authority model:
## - Movement/aim/weapon state: owned by the controlling peer (client), replicated
##   through the MultiplayerSynchronizer (net_position, net_look, net_flags, net_tick).
##   Other peers buffer those snapshots and render them ~100 ms in the past,
##   interpolating between two real states (no guessing, no rubber-banding).
## - Health, shield, knock-down, death, bandages, revives: owned by the server,
##   mirrored with RPCs.
## - Hits: detected by the shooter against skeleton hitboxes (what they see),
##   validated + applied by the server.

signal health_changed(hp: float)
## result: HIT_* constant.
signal hit_confirmed(headshot: bool, result: int)
## health_lost: false when only the shield took the hit.
signal damaged(from_pos: Vector3, health_lost: bool)
signal fired
signal bandage_changed
signal inventory_changed
signal loot_message(text: String)
signal knocked

const MAX_HEALTH := 100.0
## Ferro: 50 per body hit, x2 on the head. With a full shield (50) + 100 HP:
## 3 body shots, or 1 head + 1 body. Without shield: 2 body shots, or 1 head.
const DAMAGE := 50.0
const HEADSHOT_MULT := 2.0
const MAX_SHIELD := 50.0
## Shield recharge: one per round, channelled.
const SHIELD_CHARGES := 1
const SHIELD_CHARGE_TIME := 1.6
## Knocked down: crawl, can be revived by an ally (long channel) or a defibrillator.
const DOWN_HEIGHT := 0.75
const CRAWL_SPEED := 1.15
const REVIVE_TIME := 6.0
const REVIVE_HEALTH := 50.0
const REVIVE_RANGE := 2.2
const DEFIB_RANGE := 2.8
## Hit feedback sent to the shooter.
enum { HIT_HEALTH, HIT_SHIELD, HIT_SHIELD_BREAK, HIT_KNOCK, HIT_KILL }
const RELOAD_TIME := 2.15
const FIRE_RANGE := 260.0
## Movement: weighty, momentum-based, readable.
const RUN_SPEED := 4.1
const SPRINT_SPEED := 6.5
## Pure sideways sprint speed factor, and how far the body may face away from the camera in a sprint (rad).
const SPRINT_SIDE_MULT := 0.9
const SPRINT_FACE_MAX := 1.05
const CROUCH_SPEED := 2.0
const AIM_SPEED := 2.6
const BACKPEDAL_MULT := 0.72
const BANDAGE_MOVE_SPEED := 1.3
## Snappy: full run speed in ~0.11 s, stop in ~0.13 s.
const GROUND_ACCEL := 38.0
const SPRINT_ACCEL := 16.0
const GROUND_DECEL := 32.0
## Ground steering (rad/s): the velocity direction turns towards the input,
## keeping its speed, instead of cutting through zero (no speed dip on strafes).
const TURN_RATE := 26.0
const SPRINT_TURN_RATE := 9.0
const AIM_TURN_RATE := 30.0
const AIR_ACCEL := 3.0
const ROLL_SPEED := 8.4
const ROLL_TIME := 0.62
const ROLL_COST := 30.0
const SLIDE_MIN_SPEED := 5.2
const SLIDE_BOOST := 7.6
const SLIDE_FRICTION := 4.6
const SLIDE_END_SPEED := 2.4
const SLIDE_MAX_TIME := 1.25
const SLIDE_STEER := 1.4
const SLIDE_COST := 14.0
const SLIDE_COOLDOWN := 0.55
const MANTLE_MIN := 0.45
const MANTLE_MAX := 1.95
const VAULT_MAX := 1.25
## Vault: clip speed-up and the resulting duration (s).
const VAULT_SPEED := 1.6
## (1.35 s = VaultMath.LEN, the played window of the clip; not referenced
## directly to avoid a script dependency cycle.)
const VAULT_DURATION := 1.35 / VAULT_SPEED
const LAND_HARD_SPEED := 8.5
const SPRINT_TO_FIRE := 0.16
## Recoil (degrees of muzzle climb) and how fast the recovered part settles (1/s).
const KICK_HIP := 7.0
const KICK_AIM := 5.5
const RECOIL_RECOVER_RATE := 7.0
const SPRINT_DRAIN := 12.0
const STAMINA_REGEN := 24.0
const JUMP_VELOCITY := 5.2
const GRAVITY := 16.0
const STAND_HEIGHT := 1.8
const CROUCH_HEIGHT := 1.2
const BANDAGE_TIME := 2.2
const BANDAGE_HEAL := 50.0
const BANDAGE_REGEN_TIME := 5.0
const BANDAGE_RANGE := 3.0
const START_BANDAGES := 2

enum { F_CROUCH = 1, F_AIM = 2, F_ROLL = 4, F_SPRINT = 8, F_RELOAD = 16, F_SHOULDER_L = 32, F_LOADED = 64,
		F_SLIDE = 512, F_MANTLE = 1024, F_VAULT = 2048, F_LAND = 4096, F_SEARCH = 8192 }
## Bits 16-18 of flags: held item kind.
const ITEM_KINDS := ["", "frag", "smoke", "barricade", "defib"]
const ITEM_SHIFT := 16
## Remote interpolation: render this far behind the newest snapshot (adaptive).
const INTERP_DELAY_MIN := 0.075
const INTERP_DELAY_MAX := 0.22
const EXTRAPOLATE_MAX := 0.12


class PlayerInput:
	var move := Vector2.ZERO
	var sprint := false
	var aim := false
	var fire := false
	var reload := false
	var crouch := false
	var jump := false
	## Jump key currently down (releasing early makes a short hop); bots always hold it.
	var jump_held := true
	var roll := false
	var shoulder := false
	var bandage := false
	var shield := false
	var slot := 0
	var interact := false
	## Prop hunt: [interact] pressed this tick (turn into the prop in front).
	var disguise := false

	func clear_triggers() -> void:
		disguise = false
		fire = false
		reload = false
		crouch = false
		jump = false
		roll = false
		shoulder = false
		bandage = false
		shield = false
		slot = 0


# Identity (set by the spawn function, identical on every peer)
var player_id := 0
var display_name := ""
var team := 0
var is_bot := false
## Cosmetic outfit (ArmorKit), part of the spawn data.
var loadout := {}

# Replicated from the authority (snapshot): position, velocity,
# look (x = yaw, y = pitch, z = body yaw), state flags, sender physics tick.
var net_position := Vector3.ZERO
var net_velocity := Vector3.ZERO
var net_look := Vector3.ZERO
var net_flags := F_LOADED
var net_tick := 0
# Gameplay state (authority: simulated; others: from the interpolated snapshot)
var look_yaw := 0.0
var look_pitch := 0.0
var body_yaw := 0.0
var flags := F_LOADED

# Server-owned, mirrored by RPC
var health := MAX_HEALTH
var shield := MAX_SHIELD
var shield_charges := SHIELD_CHARGES
## Shield recharge channel time (-1 = not charging).
var shield_t := -1.0
## alive = standing and fighting. downed = knocked, crawling, still hittable.
var alive := true
var downed := false
var bandages := START_BANDAGES
var bandage_target := ""
var bandage_t := 0.0
## Ally this player is reviving ("" = none) and progress (s).
var revive_target := ""
var revive_t := 0.0

# Controller state
var input := PlayerInput.new()
var stamina := 100.0
var crouching := false
var aiming := false
var sprinting := false
var shoulder_left := false
var loaded := true
var reload_t := -1.0
var roll_t := -1.0
## Slide / mantle timers (-1 = inactive), landing recovery (s left).
var slide_t := -1.0
var mantle_t := -1.0
var mantle_vault := false
var mantle_height := 1.0
var land_t := 0.0
var spread := 2.0
## Ferro attachments found in the special crates (server-granted, mirrored, lost each round).
var has_silencer := false
var has_stock := false
## Server-owned, mirrored: 4 item slots ({} or {"id", "n"}).
var inventory := Items.empty_inventory()
## 0 = Ferro in hands, 1..4 = item slot in hand (authority).
var equipped := 0
var interact_progress := 0.0
## Prop hunt: index into Scan.catalog of the object this raider has turned into (-1 = none).
var prop_idx := -1
## Input buffers (s left): a key pressed a hair too early still counts once it can act.
var _jump_buf := 0.0
var _roll_buf := 0.0
var _slide_buf := 0.0
var _jump_t := 0.0
var _jump_cut := true
const JUMP_BUFFER := 0.16
const ROLL_BUFFER := 0.22
const SLIDE_BUFFER := 0.3
## Rummaging through a crate (replicated through the flags, drives the kneel pose).
var searching := false
var _item_cd := 0.0
var _held_remote := ""

var arena: Arena
var rig: CharacterRig
var brain: BotBrain
var hitboxes: Hitboxes

var _shape: CapsuleShape3D
var _stamina_delay := 0.0
var _roll_dir := Vector3.FORWARD
var _t_local := 0.0
var _slide_cd := 0.0
var _slide_dir := Vector3.FORWARD
var _slide_speed := 0.0
var _fire_delay := -1.0
var _turning := false
var _sprint_lock := 0.0
var _coyote := 0.0
var _recoil_recover := 0.0
var _kick_left := Vector2.ZERO
var _mantle_from := Vector3.ZERO
var _mantle_to := Vector3.ZERO
var _mantle_peak := Vector3.ZERO
var _mantle_dur := 0.6
## Vault: world points on the obstacle's top for the hands (right, left), travel
## direction, and the distances (along it) to the obstacle's face and the landing.
var vault_hands := PackedVector3Array()
var vault_dir := Vector3.FORWARD
var _vault_df := 0.0
var _vault_dl := 0.0
var _last_fire := -10.0
var _shot_seq := 0
## server: shot_id -> {origin, dir, t}
var server_shots := {}
var _regen_left := 0.0
var _regen_sync := 0.0
var _damagers := {}
var _prev_pos := Vector3.ZERO
var _curr_pos := Vector3.ZERO
var _prev_yaw := 0.0
var _curr_yaw := 0.0
var _prev_hv := Vector3.ZERO
## Smoothed horizontal acceleration (m/s²) and body turn rate (rad/s), for leans.
var move_accel := Vector3.ZERO
var yaw_rate := 0.0
# Remote snapshot buffer: [{t, pos, vel, look, flags}], oldest first.
var _snaps: Array = []
var _last_tick := -1
var _rclock := -1.0
var _interp_delay := 0.1
var _lagged: Array = [] ## debug --fake_lag: snapshots waiting to be "received"
var _revive_req := 0.0

@onready var collision: CollisionShape3D = $Collision


func _ready() -> void:
	arena = get_tree().current_scene as Arena
	_shape = CapsuleShape3D.new()
	_shape.radius = 0.36
	_shape.height = STAND_HEIGHT
	collision.shape = _shape
	collision.position.y = STAND_HEIGHT * 0.5
	floor_max_angle = deg_to_rad(48.0)
	floor_snap_length = 0.45
	rig = CharacterRig.new()
	rig.top_level = true
	add_child(rig)
	rig.setup(team, display_name, loadout)
	hitboxes = Hitboxes.new(self)
	net_position = global_position
	_prev_pos = global_position
	_curr_pos = global_position
	body_yaw = look_yaw
	_prev_yaw = body_yaw
	_curr_yaw = body_yaw
	if is_bot and multiplayer.is_server() and not Game.is_ph():
		brain = BotBrain.new()
		brain.name = "Brain"
		add_child(brain)
	arena.register_player(self)
	if is_local_human():
		arena.register_local_player(self)


func _exit_tree() -> void:
	if arena:
		arena.unregister_player(self)


func is_local_human() -> bool:
	return not is_bot and is_multiplayer_authority()


# ---------------------------------------------------------------- frame loop

func _physics_process(delta: float) -> void:
	if is_multiplayer_authority():
		if is_bot:
			if brain:
				brain.think(delta)
		else:
			_gather_human_input()
			_debug_auto_throw()
		_authority_step(delta)
		input.clear_triggers()
		flags = _pack_flags()
		searching = interact_progress > 0.0
		net_position = global_position
		net_velocity = velocity
		net_look = Vector3(look_yaw, look_pitch, body_yaw)
		net_flags = flags
		net_tick = Engine.get_physics_frames()
	else:
		_remote_step(delta)
	if bandage_target != "":
		bandage_t += delta
	if revive_target != "":
		revive_t += delta
	if shield_t >= 0.0:
		shield_t += delta
	if multiplayer.is_server():
		_server_step(delta)
	_prev_pos = _curr_pos
	_curr_pos = global_position
	_prev_yaw = _curr_yaw
	_curr_yaw = body_yaw
	# Smoothed movement dynamics for the rig's leans (physics-rate, not frame-rate).
	var hv := Vector3(velocity.x, 0.0, velocity.z)
	var kf := 1.0 - exp(-delta * 10.0)
	move_accel = move_accel.lerp((hv - _prev_hv) / delta, kf)
	yaw_rate = lerpf(yaw_rate, angle_difference(_prev_yaw, _curr_yaw) / delta, kf)
	_prev_hv = hv


func _process(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	rig.global_position = visual_position()
	rig.update_pose(self, delta)
	Game.prof_add("pose", t0)
	t0 = Time.get_ticks_usec()
	hitboxes.set_enabled(is_hittable())
	if prop_idx >= 0 and not alive:
		_clear_disguise()
	hitboxes.sync(rig.skeleton)
	Game.prof_add("hitbox", t0)
	rig.nameplate.visible = (alive or downed) and arena.local_team == team and not is_local_human() and prop_idx < 0 and not Game.is_ffa()
	rig.nameplate.text = display_name + ("  ▼ À TERRE" if downed else "")
	rig.nameplate.modulate = Color(1.0, 0.35, 0.3) if downed else Game.TEAM_COLORS[team]
	if is_local_human():
		_update_previews()
		_update_fire_blocked(delta)


## 0..1 (smoothed): the slug would hit geometry right in front of the muzzle instead
## of what the crosshair is on (a corner or low cover beside the shoulder, or the
## muzzle jammed against a wall). The HUD slides the sights sideways meanwhile.
var fire_blocked := 0.0


func _update_fire_blocked(delta: float) -> void:
	var want := false
	var rig_cam := arena.camera_rig
	if alive and held_item() == "" and rig_cam and rig_cam.target == self and not rig_cam.kill_cam_active() and not Game.debug.has("cam_at"):
		# Exactly the shot that would leave now (same origin, same direction, no spread):
		# blocked if the world stops it before the point under the crosshair.
		var aim := _compute_aim(false)
		var origin: Vector3 = aim.origin
		var dir: Vector3 = aim.dir
		var d: float = aim.dist
		if d > 0.05:
			var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * d, 1)
			var e := get_world_3d().direct_space_state.intersect_ray(q)
			if e and origin.distance_to(e.position) < d - 0.2:
				want = true # something stands between the muzzle and the aimed point
			elif d < 1.8 and not aim.hit_normal.is_equal_approx(Vector3.ZERO) and aim.hit_normal.y < 0.7:
				want = true # nose against a wall
	if Game.debug.has("force_blocked"):
		want = true # debug: preview the warning on the sights
	# Snaps on the moment the shot would hit the wall, fades out a little slower.
	if want:
		fire_blocked = 1.0
	else:
		fire_blocked = move_toward(fire_blocked, 0.0, delta * 14.0)

## Where a shot starts for the camera-aimed player: on the crosshair line at eye depth
## (what you see past a corner is what you hit), as long as nothing solid lies between
## the eye and that point; otherwise the eye itself.
func _shot_origin(eye: Vector3, start: Vector3, space: PhysicsDirectSpaceState3D) -> Vector3:
	if eye.distance_to(start) < 0.05 or eye.distance_to(start) > 1.6:
		return eye
	# A fat probe (not a ray) so a thin wall or a corner edge can never be slipped through.
	var sp := SphereShape3D.new()
	sp.radius = 0.18
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = sp
	q.transform = Transform3D(Basis(), eye)
	q.motion = start - eye
	q.collision_mask = 1
	if not space.intersect_shape(q, 1).is_empty():
		return eye
	var rest := space.cast_motion(q)
	if rest.size() < 2 or rest[0] < 0.999:
		return eye
	# The muzzle point must be in open air too, and the body-centre line to it must be clear.
	var q2 := PhysicsRayQueryParameters3D.create(global_position + Vector3(0, 1.0, 0), start, 1)
	return eye if not space.intersect_ray(q2).is_empty() else start


## What the feet are on ("snow" | "dirt" | "stone" | "metal"): a ray under the feet reads
## the collider's tag, else the map decides by position.
func surface_underfoot() -> String:
	var from := global_position + Vector3.UP * 0.4
	var hit := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 1.4, 1))
	if hit:
		return arena.map.surface_of(hit.collider, hit.position)
	return arena.map.surface_at(global_position)


## This raider's voice (0..3): the same on every peer.
func voice_id() -> int:
	return posmod(String(name).hash(), 4)


var _last_voice := -10.0


## Pain grunt / death cry, at most one every 0.6 s; the local player hears their own
## in 2D, a bit louder.
func _say(kind: String, volume_db := 0.0) -> void:
	var now := _now()
	if now - _last_voice < 0.6:
		return
	_last_voice = now
	if is_local_human():
		Audio.play_voice_2d(kind, voice_id(), volume_db - 2.0)
	else:
		Audio.play_voice(kind, voice_id(), global_position + Vector3(0, 1.4, 0), volume_db)


## Can be shot (standing or knocked down).

func is_hittable() -> bool:
	return alive or downed


## Busy with a channelled action (bandage, revive, shield recharge).
func is_channeling() -> bool:
	return bandage_target != "" or revive_target != "" or shield_t >= 0.0


func visual_position() -> Vector3:
	return _prev_pos.lerp(_curr_pos, Engine.get_physics_interpolation_fraction())


## Body yaw interpolated between physics ticks (no rotation stutter above 60 FPS).
func visual_yaw() -> float:
	return lerp_angle(_prev_yaw, _curr_yaw, Engine.get_physics_interpolation_fraction())


func _unhandled_input(event: InputEvent) -> void:
	if not is_local_human() or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event is InputEventMouseMotion and (alive or downed):
		var sens := Game.mouse_sensitivity * 0.0022 * (0.55 if aiming else 1.0)
		look_yaw = wrapf(look_yaw - event.relative.x * sens, -PI, PI)
		look_pitch = clampf(look_pitch - event.relative.y * sens, -1.3, 1.2)


func _gather_human_input() -> void:
	if arena.input_blocked():
		input.move = Vector2.ZERO
		input.sprint = false
		input.aim = false
		return
	input.move = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	input.sprint = Input.is_action_pressed("sprint")
	input.aim = Input.is_action_pressed("aim") or Game.debug.has("force_aim")
	input.fire = Input.is_action_just_pressed("fire")
	input.reload = Input.is_action_just_pressed("reload")
	input.crouch = Input.is_action_just_pressed("crouch")
	input.jump = Input.is_action_just_pressed("jump")
	input.roll = Input.is_action_just_pressed("roll")
	input.shoulder = Input.is_action_just_pressed("shoulder")
	input.bandage = Input.is_action_just_pressed("bandage")
	input.shield = Input.is_action_just_pressed("shield")
	input.interact = Input.is_action_pressed("interact")
	input.disguise = Input.is_action_just_pressed("interact")
	input.jump_held = Input.is_action_pressed("jump")
	for i in Items.SLOTS:
		if Input.is_action_just_pressed("slot_%d" % (i + 1)):
			input.slot = i + 1
	if Input.is_action_just_pressed("weapon"):
		equipped = 0
	if equipped > 0 and Input.is_action_just_pressed("aim"):
		equipped = 0


# ---------------------------------------------------------------- authority simulation

func _authority_step(delta: float) -> void:
	if downed:
		_downed_step(delta)
		return
	if not alive:
		velocity = Vector3.ZERO
		return
	_t_local += delta
	var can_move := arena.can_move_for(self)
	var can_fight := arena.can_fight_for(self)
	if input.disguise and Game.is_ph() and team == 1 and can_move:
		_try_disguise()
	# Any channelled action (bandage, revive, shield recharge) locks the same things.
	var bandaging := is_channeling()
	var on_floor := is_on_floor()
	_slide_cd = maxf(0.0, _slide_cd - delta)
	_fire_delay = maxf(-1.0, _fire_delay - delta)
	_sprint_lock = maxf(0.0, _sprint_lock - delta)
	_coyote = 0.12 if on_floor else maxf(0.0, _coyote - delta)
	land_t = maxf(0.0, land_t - delta)

	# ---- Mantle / vault in progress: scripted arc, nothing else moves.
	if mantle_t >= 0.0:
		_mantle_step(delta)
		_weapon_step(delta, can_fight, bandaging, true)
		return

	if roll_t >= 0.0:
		roll_t += delta
		if roll_t >= ROLL_TIME:
			roll_t = -1.0
	var rolling := roll_t >= 0.0
	var sliding := slide_t >= 0.0

	if input.shoulder:
		shoulder_left = not shoulder_left

	var wish := Vector3.ZERO
	if can_move:
		wish = Basis(Vector3.UP, look_yaw) * Vector3(input.move.x, 0.0, input.move.y)
		if wish.length() > 1.0:
			wish = wish.normalized()
	var moving := wish.length() > 0.1
	var hv := Vector3(velocity.x, 0.0, velocity.z)

	_jump_buf = maxf(0.0, _jump_buf - delta)
	_roll_buf = maxf(0.0, _roll_buf - delta)
	_slide_buf = maxf(0.0, _slide_buf - delta)
	_jump_t += delta
	if input.jump:
		_jump_buf = JUMP_BUFFER
	if input.roll:
		_roll_buf = ROLL_BUFFER
	# ---- Crouch key: slide out of a sprint, otherwise toggle crouch.
	var crouch_req := input.crouch
	if input.crouch and sprinting and on_floor and not sliding and hv.length() > 3.0 and (hv.length() < SLIDE_MIN_SPEED or _slide_cd > 0.0):
		# Too early for the slide (still speeding up / cooling down): remember it.
		_slide_buf = SLIDE_BUFFER
		crouch_req = false
	elif _slide_buf > 0.0 and sprinting and on_floor and hv.length() >= SLIDE_MIN_SPEED and _slide_cd <= 0.0:
		_slide_buf = 0.0
		crouch_req = true
	if crouch_req and can_move and not rolling:
		if sliding:
			_end_slide(false)
			sliding = false
		elif sprinting and on_floor and hv.length() >= SLIDE_MIN_SPEED and _slide_cd <= 0.0 and stamina >= SLIDE_COST * 0.5:
			_start_slide(hv)
			sliding = true
		elif crouching:
			if _can_stand():
				crouching = false
		else:
			crouching = true

	aiming = (input.aim or (Game.debug.has("force_aim") and is_local_human())) and can_move and not rolling and not bandaging
	# Sprint forwards or sideways (diagonals included); not straight back.
	var sprint_dir_ok := (input.move.y < -0.3 or absf(input.move.x) > 0.3) and input.move.y <= 0.3
	var want_sprint := input.sprint and moving and sprint_dir_ok and not aiming and not bandaging and not rolling and not sliding and _sprint_lock <= 0.0
	if want_sprint and crouching and _can_stand():
		crouching = false
	sprinting = want_sprint and not crouching and stamina > 0.0 and (sprinting or stamina > 12.0)
	if sprinting:
		stamina = maxf(0.0, stamina - SPRINT_DRAIN * delta)
		_stamina_delay = 0.9
	else:
		_stamina_delay -= delta
		if _stamina_delay <= 0.0:
			stamina = minf(100.0, stamina + STAMINA_REGEN * delta)

	if (input.roll or _roll_buf > 0.0) and can_move and not rolling and on_floor and not bandaging and stamina >= ROLL_COST * 0.6:
		_roll_buf = 0.0
		# Rolling out of a slide keeps its direction (or steers to the keys).
		var roll_from_slide := sliding
		if sliding:
			slide_t = -1.0
			_slide_cd = SLIDE_COOLDOWN
			sliding = false
		stamina = maxf(0.0, stamina - ROLL_COST)
		_stamina_delay = 1.0
		_roll_dir = wish.normalized() if moving else (_slide_dir if roll_from_slide else body_forward())
		roll_t = 0.0
		rolling = true
		crouching = false
		aiming = false
		body_yaw = atan2(-_roll_dir.x, -_roll_dir.z)
		Audio.play_3d("roll", global_position, -4.0, 30.0)

	# ---- Target speed
	var speed := RUN_SPEED
	if revive_target != "":
		speed = 0.0
	elif bandaging:
		speed = BANDAGE_MOVE_SPEED
	elif aiming:
		speed = AIM_SPEED
	elif crouching:
		speed = CROUCH_SPEED
	elif sprinting:
		speed = SPRINT_SPEED
		# A straight sideways sprint is a little slower than a forward one.
		if moving:
			var sprint_local := Basis(Vector3.UP, look_yaw).inverse() * wish.normalized()
			speed *= lerpf(1.0, SPRINT_SIDE_MULT, absf(sprint_local.x))
	if aiming and moving:
		# Back-pedalling and strafing while shouldered are slower.
		var local := Basis(Vector3.UP, look_yaw).inverse() * wish.normalized()
		speed *= lerpf(1.0, BACKPEDAL_MULT, clampf(local.z, 0.0, 1.0)) * lerpf(1.0, 0.9, absf(local.x))
	if reload_t >= 0.0 and not sprinting:
		speed *= 0.9
	if land_t > 0.0:
		speed *= 0.45

	# ---- Horizontal velocity
	if rolling:
		var k := 1.0 - roll_t / ROLL_TIME
		hv = _roll_dir * lerpf(2.5, ROLL_SPEED, k * k)
	elif sliding:
		hv = _slide_step(delta, wish, moving, on_floor)
		sliding = slide_t >= 0.0
	elif on_floor:
		hv = _ground_velocity(hv, wish, speed, delta)
	elif moving:
		hv = hv.move_toward(wish * maxf(hv.length(), speed * 0.6), AIR_ACCEL * delta)
	velocity.x = hv.x
	velocity.z = hv.z

	# ---- Jump / mantle
	if _jump_buf > 0.0 and can_move and not rolling and not bandaging:
		var dir := wish.normalized() if moving else Vector3(-sin(look_yaw), 0.0, -cos(look_yaw))
		if _try_mantle(dir):
			_jump_buf = 0.0
			_weapon_step(delta, can_fight, bandaging, true)
			return
		if on_floor or _coyote > 0.0:
			_jump_buf = 0.0
			if crouching and not sliding:
				if _can_stand():
					crouching = false
			else:
				if sliding:
					_end_slide(true)
				velocity.y = JUMP_VELOCITY
				_jump_t = 0.0
				_jump_cut = false
				_coyote = 0.0
				Audio.play_3d("step", global_position, -6.0, 25.0, 0.1)
	# Let go of the key early: the hop is cut short (hold it for the full jump).
	if not _jump_cut and velocity.y > 1.2 and not input.jump_held and _jump_t > 0.05:
		velocity.y *= 0.55
		_jump_cut = true
	if not is_on_floor():
		velocity.y -= GRAVITY * delta

	_set_collision_height(crouching or rolling or slide_t >= 0.0)
	var vy_before := velocity.y
	move_and_slide()

	# ---- Landing impact
	if is_on_floor() and not on_floor and vy_before < -3.5:
		var impact := -vy_before
		if impact > LAND_HARD_SPEED:
			land_t = clampf(impact / 20.0, 0.25, 0.5)
			if impact > 11.0:
				stamina = maxf(0.0, stamina - 15.0)
		Audio.play_3d("land", global_position, lerpf(-10.0, 2.0, clampf((impact - 3.5) / 8.0, 0.0, 1.0)), 35.0, 0.1)
		if is_local_human() and arena.camera_rig:
			arena.camera_rig.dip(clampf(impact / 12.0, 0.15, 1.0))

	# ---- Facing: camera when fighting, movement otherwise.
	if not rolling:
		var face_target := INF
		var ally := get_bandage_target_node()
		if ally == null and revive_target != "":
			ally = arena.get_player(revive_target)
		if bandaging and ally and ally != self:
			var to := ally.global_position - global_position
			face_target = atan2(-to.x, -to.z)
		elif aiming or recent_fire() or reload_t >= 0.0:
			face_target = look_yaw
		elif slide_t >= 0.0:
			face_target = atan2(-_slide_dir.x, -_slide_dir.z)
		elif sprinting and hv.length() > 0.6:
			# The body leans into the run direction but never turns more than ~60 deg
			# away from the camera, so a sideways sprint stays a strafe-sprint.
			var run_yaw := atan2(-hv.x, -hv.z)
			face_target = look_yaw + clampf(angle_difference(look_yaw, run_yaw), -SPRINT_FACE_MAX, SPRINT_FACE_MAX)
		elif moving or hv.length() > 0.6:
			# Strafe: the body keeps facing the camera, legs follow the motion.
			face_target = look_yaw
		else:
			# Standing still: the camera swings freely inside a dead zone; past it the
			# body turns in place at a steady, eased speed (with hysteresis, so it
			# neither snaps nor chatters) until it faces the camera again.
			var diff := absf(angle_difference(body_yaw, look_yaw))
			if diff > 0.7:
				_turning = true
			elif diff < 0.06:
				_turning = false
			if _turning:
				var speed_turn := clampf(diff * 3.2, 0.9, 5.5)
				body_yaw += clampf(angle_difference(body_yaw, look_yaw), -speed_turn * delta, speed_turn * delta)
		if face_target != INF:
			var rate := 22.0 if aiming else (14.0 if sprinting else 18.0)
			body_yaw = lerp_angle(body_yaw, face_target, 1.0 - exp(-rate * delta))

	_weapon_step(delta, can_fight, bandaging, rolling)

	# Tighter than before: shouldered and still the Ferro is pin-point; moving only
	# opens a light bloom (it grows with speed), settling back quickly.
	var target_spread := 0.05 if aiming else 1.6
	var move_k := clampf(hv.length() / RUN_SPEED, 0.0, 1.0)
	if hv.length() > 0.5:
		target_spread += (0.4 if aiming else 1.0) * move_k
	if sprinting:
		target_spread += 1.5
	if slide_t >= 0.0:
		target_spread += 0.9
	if not is_on_floor():
		target_spread += 3.2
	if crouching:
		target_spread *= 0.6
	spread = lerpf(spread, target_spread, 1.0 - exp(-12.0 * delta))


## Knocked down: crawl slowly (camera-relative), body turns to the crawl
## direction, nothing else. Free look still works so you can watch your back.
func _downed_step(delta: float) -> void:
	aiming = false
	sprinting = false
	crouching = false
	roll_t = -1.0
	slide_t = -1.0
	mantle_t = -1.0
	reload_t = -1.0
	equipped = 0
	var wish := Vector3.ZERO
	if arena.match_allows_movement():
		wish = Basis(Vector3.UP, look_yaw) * Vector3(input.move.x, 0.0, input.move.y)
		if wish.length() > 1.0:
			wish = wish.normalized()
	var hv := Vector3(velocity.x, 0.0, velocity.z)
	if is_on_floor():
		hv = hv.move_toward(wish * CRAWL_SPEED, 10.0 * delta)
	velocity.x = hv.x
	velocity.z = hv.z
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	_set_collision_height(true)
	move_and_slide()
	if hv.length() > 0.2:
		body_yaw = lerp_angle(body_yaw, atan2(-hv.x, -hv.z), 1.0 - exp(-4.0 * delta))
	spread = 6.0


## Ground movement split into direction and speed: the direction steers towards
## the input at a turn rate (slower in a sprint), the speed ramps on its own.
## Only near-reversals brake through zero (plant the feet and push back).
func _ground_velocity(hv: Vector3, wish: Vector3, speed: float, delta: float) -> Vector3:
	var cur := hv.length()
	if wish.length() < 0.1:
		return hv.move_toward(Vector3.ZERO, GROUND_DECEL * delta)
	var tdir := wish.normalized()
	var want := speed * minf(wish.length(), 1.0)
	if cur < 0.6:
		return hv.move_toward(tdir * want, GROUND_ACCEL * delta)
	var dir := hv / cur
	var ang := dir.signed_angle_to(tdir, Vector3.UP)
	if absf(ang) > 2.3:
		# Reversal: brake hard, then accelerate the other way.
		return hv.move_toward(tdir * want, (GROUND_ACCEL + GROUND_DECEL) * 0.6 * delta)
	var turn := AIM_TURN_RATE if aiming else (SPRINT_TURN_RATE if sprinting else TURN_RATE)
	var step := clampf(ang, -turn * delta, turn * delta)
	dir = dir.rotated(Vector3.UP, step)
	# Turning costs a little speed (more in a sprint), so cuts feel weighty.
	cur = maxf(0.0, cur - absf(step) * (1.6 if sprinting else 0.4))
	var rate := GROUND_ACCEL if want > cur else GROUND_DECEL
	if sprinting and want > cur:
		rate = SPRINT_ACCEL
	cur = move_toward(cur, want, rate * delta)
	return dir * cur


## Reload, firing (with sprint-out delay), bandage and items.
func _weapon_step(delta: float, can_fight: bool, bandaging: bool, busy: bool) -> void:
	if reload_t >= 0.0 and roll_t < 0.0:
		_advance_reload(delta)
		if reload_t >= RELOAD_TIME:
			reload_t = -1.0
			loaded = true
	if input.reload and can_fight:
		_start_reload()
	# Recoil recovery: part of the kick settles back down.
	# Recoil: the kick lands over ~50 ms (a hard shove, not a teleport), then
	# part of it eases back down.
	if _kick_left.length_squared() > 0.0:
		var step := _kick_left * minf(1.0, delta / 0.05)
		if _kick_left.length() < 0.0005:
			step = _kick_left
		look_pitch = clampf(look_pitch + step.y, -1.3, 1.2)
		look_yaw += step.x
		_kick_left -= step
	elif _recoil_recover > 0.0:
		var r := _recoil_recover * (1.0 - exp(-RECOIL_RECOVER_RATE * delta))
		if _recoil_recover < 0.0005:
			r = _recoil_recover
		look_pitch -= r
		_recoil_recover -= r
	if input.fire and can_fight and equipped == 0:
		if bandaging:
			server_cancel_bandage.rpc_id(1)
		elif not busy:
			if loaded and sprinting:
				# Sprint-out: drop the sprint, shoot a beat later.
				sprinting = false
				_sprint_lock = 0.35
				_fire_delay = SPRINT_TO_FIRE
			elif loaded:
				_fire()
			elif reload_t < 0.0:
				Audio.play_3d("dry", global_position, -6.0, 20.0)
				_start_reload()
	if _fire_delay > -1.0 and _fire_delay <= 0.0:
		_fire_delay = -1.0
		if loaded and can_fight and not busy and alive:
			_fire()
	if input.bandage and can_fight and not bandaging and not busy and bandages > 0:
		var t := get_bandage_candidate()
		if t:
			server_request_bandage.rpc_id(1, String(t.name))
	if input.shield and can_fight and not bandaging and not busy and shield_charges > 0 and shield < MAX_SHIELD:
		server_request_shield.rpc_id(1)
	_revive_input(delta, can_fight, busy)
	_items_step(delta, arena.match_allows_movement(), can_fight, busy or bandaging)


## Hold [interact] next to a knocked-down ally to pick them up (server-timed).
func _revive_input(delta: float, can_fight: bool, busy: bool) -> void:
	_revive_req = maxf(0.0, _revive_req - delta)
	var cand := get_revive_candidate(REVIVE_RANGE)
	if revive_target != "":
		if (not input.interact or cand == null or String(cand.name) != revive_target) and _revive_req <= 0.0:
			_revive_req = 0.3
			server_cancel_bandage.rpc_id(1)
		return
	if input.interact and cand and can_fight and not busy and bandage_target == "" and shield_t < 0.0 and _revive_req <= 0.0 and held_item() != "defib":
		_revive_req = 0.3
		server_request_revive.rpc_id(1, String(cand.name))


# ---------------------------------------------------------------- slide

func _start_slide(hv: Vector3) -> void:
	slide_t = 0.0
	_slide_dir = hv.normalized()
	_slide_speed = maxf(hv.length(), SLIDE_BOOST)
	stamina = maxf(0.0, stamina - SLIDE_COST)
	_stamina_delay = 1.0
	sprinting = false
	crouching = true
	Audio.play_3d("slide", global_position, 0.0, 35.0, 0.08)
	if Game.debug.has("log_moves"):
		print("[MOVE] %s glisse à %.1f m/s" % [display_name, _slide_speed])


func _slide_step(delta: float, wish: Vector3, moving: bool, on_floor: bool) -> Vector3:
	slide_t += delta
	var downhill := 0.0
	if on_floor:
		var n := get_floor_normal()
		var down := (Vector3.DOWN - n * n.dot(Vector3.DOWN))
		downhill = down.dot(_slide_dir) # >0 when sliding down a slope
	_slide_speed += (GRAVITY * 0.85 * downhill - SLIDE_FRICTION) * delta
	if moving:
		# Light steering towards the stick/keys.
		var ang := _slide_dir.signed_angle_to(wish.normalized(), Vector3.UP)
		_slide_dir = _slide_dir.rotated(Vector3.UP, clampf(ang, -SLIDE_STEER * delta, SLIDE_STEER * delta))
	if _slide_speed <= SLIDE_END_SPEED or (slide_t > SLIDE_MAX_TIME and downhill < 0.15):
		_end_slide(false)
		return _slide_dir * minf(_slide_speed, CROUCH_SPEED + 0.5)
	return _slide_dir * _slide_speed


func _end_slide(keep_momentum: bool) -> void:
	slide_t = -1.0
	_slide_cd = SLIDE_COOLDOWN
	# Pop back up if sprint is held and there's headroom, otherwise stay crouched.
	crouching = not (input.sprint or keep_momentum) or not _can_stand()


# ---------------------------------------------------------------- mantle / vault

## Climb onto (or vault over) an obstacle in `dir` between 0.45 and 1.95 m high.
func _try_mantle(dir: Vector3) -> bool:
	if dir.length() < 0.1:
		return false
	dir = Vector3(dir.x, 0.0, dir.z).normalized()
	var space := get_world_3d().direct_space_state
	var feet := global_position
	var ex: Array[RID] = [get_rid()]
	var hit := {}
	for probe_h: float in [0.5, 1.0, 1.5]:
		var q := PhysicsRayQueryParameters3D.create(feet + Vector3.UP * probe_h, feet + Vector3.UP * probe_h + dir * 1.0, 1, ex)
		hit = space.intersect_ray(q)
		if hit:
			break
	if not hit:
		if Game.debug.has("log_moves"):
			print("[MOVE] saut: rien devant")
		return false
	var found := _find_top(space, feet, hit.position, dir, ex)
	var top: Dictionary = found.get("top", {})
	if top.is_empty():
		if Game.debug.has("log_moves"):
			print("[MOVE] saut: pas de dessus")
		return false
	var h: float = top.position.y - feet.y
	if h < MANTLE_MIN or h > MANTLE_MAX:
		if Game.debug.has("log_moves"):
			print("[MOVE] saut: hauteur %.2f" % h)
		return false
	# Headroom on top for at least a crouching body.
	if not _space_free(top.position + Vector3.UP * (CROUCH_HEIGHT * 0.5 + 0.08), CROUCH_HEIGHT - 0.1):
		return false
	var target: Vector3 = top.position + Vector3.UP * 0.02
	var vault := false
	if h < VAULT_MAX:
		# Thin obstacle? Then vault over it and land on the far side.
		var far: Vector3 = (found.back as Vector3) + dir * 0.75
		var land := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(far.x, feet.y + h + 0.6, far.z), Vector3(far.x, feet.y - 1.5, far.z), 1, ex))
		if land and land.position.y < top.position.y - 0.35 and _space_free(land.position + Vector3.UP * (STAND_HEIGHT * 0.5 + 0.05), STAND_HEIGHT - 0.1):
			target = land.position + Vector3.UP * 0.02
			vault = true
	_mantle_from = feet
	_mantle_to = target
	_mantle_peak = (top.position if vault else Vector3(feet.x, target.y, feet.z)) + Vector3.UP * (0.45 if vault else 0.3)
	_mantle_dur = VAULT_DURATION if vault else (0.5 + h * 0.2)
	mantle_t = 0.0
	mantle_vault = vault
	mantle_height = h
	if vault:
		# Anchors of the vault: the obstacle's face (where the hands land) and the landing.
		vault_dir = dir
		_vault_df = Vector3(hit.position.x - feet.x, 0.0, hit.position.z - feet.z).dot(dir)
		_vault_dl = Vector3(target.x - feet.x, 0.0, target.z - feet.z).dot(dir)
		_set_vault_hands(Vector3(hit.position.x, top.position.y, hit.position.z) + dir * 0.12, dir)
	slide_t = -1.0
	roll_t = -1.0
	sprinting = false
	aiming = false
	crouching = not vault and not _space_free(target + Vector3.UP * (STAND_HEIGHT * 0.5 + 0.05), STAND_HEIGHT - 0.1)
	body_yaw = atan2(-dir.x, -dir.z)
	velocity = Vector3.ZERO
	stamina = maxf(0.0, stamina - 6.0)
	Audio.play_3d("mantle", global_position, -2.0, 30.0, 0.08)
	if Game.debug.has("log_moves"):
		print("[MOVE] %s %s %.2f m" % [display_name, "franchit" if vault else "escalade", h])
	if Game.debug.has("shot_on_mantle") and is_local_human():
		_debug_mantle_shots()
	return true


## First walkable surface just beyond an obstacle's face (tries a few depths, so thin
## walls work), plus the far edge of that surface: {top: ray hit, back: Vector3}.
func _find_top(space: PhysicsDirectSpaceState3D, feet: Vector3, face: Vector3, dir: Vector3, ex: Array[RID]) -> Dictionary:
	for off: float in [0.08, 0.18, 0.3, 0.5]:
		var p := face + dir * off
		var t := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(p.x, feet.y + 2.3, p.z), Vector3(p.x, feet.y + 0.3, p.z), 1, ex))
		if t and t.normal.y >= 0.7:
			var back: Vector3 = t.position
			for i in 14:
				var p2 := back + dir * 0.12
				var t2 := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(p2.x, feet.y + 2.3, p2.z), Vector3(p2.x, feet.y + 0.3, p2.z), 1, ex))
				if t2 and absf(t2.position.y - t.position.y) < 0.12:
					back = Vector3(p2.x, t.position.y, p2.z)
				else:
					break
			return {"top": t, "back": back}
	return {}


## Where the hands go on the obstacle's top: shoulder width apart, at the surface.
func _set_vault_hands(top_pos: Vector3, dir: Vector3) -> void:
	var side := dir.cross(Vector3.UP).normalized()
	var c := top_pos - dir * 0.08
	vault_hands = PackedVector3Array([c + side * 0.2, c - side * 0.2])


## Remote peers rebuild the hand targets (and the height) from the world, the
## same way the vaulting machine found them: they only receive the position.
func _probe_vault_remote() -> void:
	var dir := body_forward()
	var space := get_world_3d().direct_space_state
	var feet := global_position
	var ex: Array[RID] = [get_rid()]
	for probe_h: float in [0.5, 1.0, 1.5]:
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(feet + Vector3.UP * probe_h, feet + Vector3.UP * probe_h + dir * 1.6, 1, ex))
		if hit:
			var found := _find_top(space, feet, hit.position, dir, ex)
			if not found.is_empty():
				var top: Dictionary = found.top
				mantle_height = top.position.y - feet.y
				vault_dir = dir
				_set_vault_hands(Vector3(hit.position.x, top.position.y, hit.position.z) + dir * 0.12, dir)
				return
	vault_hands = PackedVector3Array()


func _mantle_step(delta: float) -> void:
	mantle_t += delta
	var k := clampf(mantle_t / _mantle_dur, 0.0, 1.0)
	var p: Vector3
	if mantle_vault:
		# Root-motion style: the capture's own rhythm along the real obstacle.
		var tau := VaultMath.T0 + k * VaultMath.LEN
		var along := VaultMath.root_distance(tau, _vault_df, _vault_dl)
		p = _mantle_from + vault_dir * along
		p.y = lerpf(_mantle_from.y, _mantle_to.y, smoothstep(1.0, 1.45, tau))
	else:
		var e := ease(k, -1.6)
		# Quadratic Bezier: up first, then over.
		p = _mantle_from * (1.0 - e) * (1.0 - e) + _mantle_peak * 2.0 * e * (1.0 - e) + _mantle_to * e * e
	global_position = p
	velocity = Vector3.ZERO
	_set_collision_height(true)
	if k >= 1.0:
		mantle_t = -1.0
		var d := Vector3(-sin(body_yaw), 0.0, -cos(body_yaw))
		velocity = d * (RUN_SPEED * 0.6 if input.move.length() > 0.1 else 0.0)


func _space_free(center: Vector3, height: float) -> bool:
	var q := PhysicsShapeQueryParameters3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.32
	cap.height = maxf(height, 0.7)
	q.shape = cap
	q.transform = Transform3D(Basis(), center)
	q.collision_mask = 1 | 4
	q.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty()


func _can_stand() -> bool:
	if _shape.height >= STAND_HEIGHT:
		return true
	var q := PhysicsShapeQueryParameters3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.33
	cap.height = STAND_HEIGHT - 0.1
	q.shape = cap
	q.transform = Transform3D(Basis(), global_position + Vector3(0, STAND_HEIGHT * 0.5 + 0.08, 0))
	q.collision_mask = 1
	q.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty()


func _set_collision_height(low: bool) -> void:
	var h := DOWN_HEIGHT if downed else (CROUCH_HEIGHT if low else STAND_HEIGHT)
	if not is_equal_approx(_shape.height, h):
		_shape.height = h
		collision.position.y = h * 0.5


func _pack_flags() -> int:
	var f := 0
	if crouching: f |= F_CROUCH
	if aiming: f |= F_AIM
	if roll_t >= 0.0: f |= F_ROLL
	if sprinting: f |= F_SPRINT
	if reload_t >= 0.0: f |= F_RELOAD
	if shoulder_left: f |= F_SHOULDER_L
	if loaded: f |= F_LOADED
	if slide_t >= 0.0: f |= F_SLIDE
	if mantle_t >= 0.0: f |= F_MANTLE
	if mantle_vault: f |= F_VAULT
	if land_t > 0.0: f |= F_LAND
	if interact_progress > 0.0: f |= F_SEARCH
	f |= maxi(ITEM_KINDS.find(held_item()), 0) << ITEM_SHIFT
	return f


# ---------------------------------------------------------------- remote interpolation

## Takes the newest replicated state as a snapshot (once per sender tick).
func _receive_snapshot() -> void:
	if net_tick == _last_tick:
		return
	if net_tick < _last_tick and _last_tick - net_tick < 600:
		return # stale / out of order
	_last_tick = net_tick
	var s := {"t": net_tick / float(Engine.physics_ticks_per_second), "pos": net_position,
		"vel": net_velocity, "look": net_look, "flags": net_flags}
	if Game.debug.has("fake_lag"):
		# Debug: simulate one-way latency + jitter on received movement.
		var lag := float(Game.debug.fake_lag) / 1000.0 + randf() * float(Game.debug.get("fake_jitter", 0.0)) / 1000.0
		_lagged.append({"at": _now() + lag, "s": s})
		return
	_push_snapshot(s)


func _push_snapshot(s: Dictionary) -> void:
	if not _snaps.is_empty() and s.t <= _snaps[-1].t:
		return
	_snaps.append(s)
	while _snaps.size() > 40:
		_snaps.pop_front()


## Renders the remote player `_interp_delay` behind the newest snapshot,
## interpolating between the two surrounding real states. The playback clock
## runs at real speed and is nudged (never jumped) towards its target, and the
## delay grows when packets come late, shrinks back when the link is clean.
func _remote_step(delta: float) -> void:
	_receive_snapshot()
	if not _lagged.is_empty():
		var now := _now()
		while not _lagged.is_empty() and _lagged[0].at <= now:
			_push_snapshot(_lagged.pop_front().s)
	if _snaps.is_empty():
		return
	var newest: Dictionary = _snaps[-1]
	var target: float = newest.t - _interp_delay
	if _rclock < 0.0 or absf(target - _rclock) > 0.5:
		_rclock = target
	else:
		_rclock += delta
		_rclock += (target - _rclock) * 0.08
	var st: Dictionary
	if _rclock >= newest.t:
		# Starving: extrapolate a little on the last velocity, and buffer more.
		_interp_delay = minf(INTERP_DELAY_MAX, _interp_delay + delta * 0.5)
		var ahead := minf(_rclock - newest.t, EXTRAPOLATE_MAX)
		st = newest.duplicate()
		st.pos = newest.pos + newest.vel * Vector3(1, 0, 1) * ahead
	else:
		_interp_delay = maxf(INTERP_DELAY_MIN, _interp_delay - delta * 0.01)
		var i := _snaps.size() - 1
		while i > 0 and _snaps[i - 1].t > _rclock:
			i -= 1
		if i == 0:
			st = _snaps[0]
		else:
			var a: Dictionary = _snaps[i - 1]
			var b: Dictionary = _snaps[i]
			var k := clampf((_rclock - a.t) / maxf(b.t - a.t, 0.0001), 0.0, 1.0)
			var la: Vector3 = a.look
			var lb: Vector3 = b.look
			st = {"pos": (a.pos as Vector3).lerp(b.pos, k), "vel": (a.vel as Vector3).lerp(b.vel, k),
				"look": Vector3(lerp_angle(la.x, lb.x, k), lerpf(la.y, lb.y, k), lerp_angle(la.z, lb.z, k)),
				"flags": a.flags if k < 0.5 else b.flags}
		# Drop snapshots that are fully in the past (keep one before the clock).
		while _snaps.size() > 2 and _snaps[1].t < _rclock:
			_snaps.pop_front()
	var pos: Vector3 = st.pos
	if Game.debug.has("log_net") and Engine.get_physics_frames() % 120 == 0:
		print("[NET] %s délai=%d ms snaps=%d extrapol=%s saut=%.3f m" % [display_name, int(_interp_delay * 1000.0), _snaps.size(), str(_rclock >= newest.t), pos.distance_to(global_position)])
	if pos.distance_to(global_position) > 6.0:
		_prev_pos = pos
		_curr_pos = pos
	global_position = pos
	velocity = st.vel
	var look: Vector3 = st.look
	look_yaw = look.x
	look_pitch = look.y
	body_yaw = look.z
	flags = st.flags
	crouching = flags & F_CROUCH != 0
	aiming = flags & F_AIM != 0
	sprinting = flags & F_SPRINT != 0
	shoulder_left = flags & F_SHOULDER_L != 0
	loaded = flags & F_LOADED != 0
	_held_remote = ITEM_KINDS[mini((flags >> ITEM_SHIFT) & 7, ITEM_KINDS.size() - 1)]
	if flags & F_ROLL != 0:
		roll_t = 0.0 if roll_t < 0.0 else minf(roll_t + delta, ROLL_TIME - 0.01)
	else:
		roll_t = -1.0
	if flags & F_RELOAD != 0:
		if reload_t < 0.0:
			reload_t = 0.0
		_advance_reload(delta)
		reload_t = minf(reload_t, RELOAD_TIME - 0.01)
	else:
		reload_t = -1.0
	slide_t = (0.0 if slide_t < 0.0 else slide_t + delta) if flags & F_SLIDE != 0 else -1.0
	mantle_vault = flags & F_VAULT != 0
	if flags & F_MANTLE != 0:
		if mantle_t < 0.0:
			mantle_t = 0.0
			_mantle_dur = VAULT_DURATION if mantle_vault else 0.75
			if mantle_vault:
				_probe_vault_remote()
		else:
			mantle_t += delta
	else:
		mantle_t = -1.0
	land_t = 0.3 if flags & F_LAND != 0 else maxf(0.0, land_t - delta)
	searching = flags & F_SEARCH != 0
	_set_collision_height(crouching or roll_t >= 0.0 or slide_t >= 0.0 or mantle_t >= 0.0)


# ---------------------------------------------------------------- weapon

## Break-action reload timeline (seconds into RELOAD_TIME) -> sound.
const RELOAD_EVENTS := [[0.27, "ferro_eject"], [1.0, "ferro_insert"], [1.63, "ferro_close"], [1.9, "ferro_ready"]]


func _start_reload() -> void:
	if loaded or reload_t >= 0.0 or bandage_target != "" or not alive:
		return
	reload_t = 0.0
	_reload_sound("ferro_open")


## Reload tempo: the ergonomic stock speeds the whole sequence up a little.
func reload_speed() -> float:
	return Items.STOCK_RELOAD_SPEED if has_stock else 1.0


func _advance_reload(delta: float) -> void:
	var prev := reload_t
	reload_t += delta * reload_speed()
	for ev in RELOAD_EVENTS:
		if prev < ev[0] and reload_t >= ev[0]:
			_reload_sound(ev[1])
			if ev[1] == "ferro_eject":
				FX.shell_eject(rig.gun.global_transform)


func _reload_sound(id: String) -> void:
	# Louder for the player being watched, so the reload rhythm is readable.
	var watched := arena.camera_rig != null and arena.camera_rig.target == self
	Audio.play_3d(id, rig.gun.global_position, 2.0 if watched else -2.0, 30.0, 0.04)


func _fire() -> void:
	loaded = false
	_last_fire = _now()
	var aim := _compute_aim()
	_shot_seq += 1
	var pr := Projectile.spawn(self, aim.origin, aim.dir, _shot_seq, true)
	pr.debug_pred = _dbg_pred
	if not is_bot:
		# Big-bore kick: the muzzle climbs hard (less when shouldered), with a
		# random sideways jerk; ~60% settles back once the shove is over.
		var kick := deg_to_rad(KICK_HIP if not aiming else KICK_AIM) * (0.8 if crouching else 1.0)
		_kick_left = Vector2(deg_to_rad(randf_range(-1.6, 1.6)), kick)
		_recoil_recover = kick * 0.6
		spread += 3.0 # crosshair blooms open on the shot
		if arena.camera_rig:
			arena.camera_rig.fire_kick(aiming)
		Audio.duck_music()
	_play_shot_fx()
	fired.emit()
	if multiplayer.is_server():
		arena.match_mgr.server_register_shot(self, aim.origin, aim.dir, _shot_seq)
	else:
		server_fire.rpc_id(1, aim.origin, aim.dir, _shot_seq)


## Where the bullet starts (eye height) and its direction. For the local human
## the direction converges on what's under the crosshair.
func _compute_aim(with_spread := true) -> Dictionary:
	var eye := eye_position()
	var space := get_world_3d().direct_space_state
	var excl: Array[RID] = hitboxes.rids()
	var aim_point: Vector3
	var origin := eye
	var hit_normal := Vector3.ZERO
	var rig_cam: CameraRig = arena.camera_rig
	if not is_bot and rig_cam and rig_cam.target == self:
		var cam := rig_cam.cam
		var cdir := _apply_spread(-cam.global_basis.z) if with_spread else -cam.global_basis.z
		var start := cam.global_position + cdir * maxf((eye - cam.global_position).dot(cdir), 0.0)
		var q := PhysicsRayQueryParameters3D.create(start, start + cdir * FIRE_RANGE, 1 | Hitboxes.LAYER, excl)
		var h := space.intersect_ray(q)
		hit_normal = h.normal if h else Vector3.ZERO
		aim_point = h.position if h else start + cdir * FIRE_RANGE
		origin = _shot_origin(eye, start, space)
		if Game.debug.has("log_shots"):
			var pv = Hitboxes.player_of(h.collider) if h else null
			_dbg_pred = ("%s/%s" % [pv.display_name, Hitboxes.zone_of(h.collider)]) if pv else ("monde" if h else "rien")
			if pv:
				_dbg_pred += " (cible à %.1f m/s, impact visé %s)" % [Vector3(pv.velocity.x, 0, pv.velocity.z).length(), str(h.position.snapped(Vector3.ONE * 0.01))]
	else:
		aim_point = eye + _apply_spread(look_direction()) * FIRE_RANGE
		return {"origin": eye, "dir": (aim_point - eye).normalized(), "dist": eye.distance_to(aim_point), "hit_normal": Vector3.ZERO}
	# Zeroed on the crosshair: aim above it by the drop over the flight, so the
	# slug lands exactly where the crosshair ray hit (bots lead/zero themselves).
	var dist := origin.distance_to(aim_point)
	var tof := dist / Projectile.SPEED
	aim_point.y += 0.5 * Projectile.GRAVITY * tof * tof
	return {"origin": origin, "dir": (aim_point - origin).normalized(), "dist": dist, "hit_normal": hit_normal}


func _apply_spread(dir: Vector3) -> Vector3:
	var ang := deg_to_rad(spread) * sqrt(randf())
	var rot := randf() * TAU
	var right := dir.cross(Vector3.UP).normalized()
	if right.length() < 0.01:
		right = Vector3.RIGHT
	var up := right.cross(dir).normalized()
	return (dir + (right * cos(rot) + up * sin(rot)) * tan(ang)).normalized()


func _play_shot_fx() -> void:
	_last_fire = _now()
	FX.muzzle_flash(rig.muzzle, has_silencer)
	FX.muzzle_blast(rig.muzzle.global_position, -rig.muzzle.global_basis.z, has_silencer)
	rig.fire_recoil()
	# Layered report: recording (near / far take) + sub-bass boom + supersonic
	# crack, then the echo rolling back from the arena a moment later.
	var listener := get_viewport().get_camera_3d()
	var dist := listener.global_position.distance_to(global_position) if listener else 0.0
	var mpos := rig.muzzle.global_position
	var mine := is_local_human() or (arena.camera_rig != null and arena.camera_rig.target == self)
	if has_silencer:
		# Suppressed: a dull "thup" and the action's clack, no crack, no echo.
		Audio.play_3d("sil_shot", mpos, 2.0, 70.0, 0.05)
		if mine:
			Audio.play_2d("sil_shot", 4.0, randf_range(0.97, 1.03))
			Audio.play_2d("shot_mech", -5.0, randf_range(0.95, 1.05))
		return
	if dist > 35.0:
		Audio.play_3d("shot_far", mpos, 6.0, 450.0, 0.04)
		Audio.play_3d("shot_boom", mpos, 2.0, 300.0, 0.05)
	else:
		Audio.play_3d("shot", mpos, 3.0, 450.0, 0.04)
		Audio.play_3d("shot_boom", mpos, 6.0, 300.0, 0.05)
		Audio.play_3d("shot_crack", mpos, 0.0, 120.0, 0.06)
		# A real shotgun report under the layers gives the blast its body.
		Audio.play_3d("shot_mid", mpos, -2.0, 260.0, 0.05, 0.85)
	if mine:
		# Shooter's ears: full, non-positional punch (stays big while turning).
		Audio.play_2d("shot_boom", 2.0)
		Audio.play_2d("shot_mech", -4.0, randf_range(0.95, 1.05))
	Audio.play_3d_delayed("shot_tail", mpos, 0.12 + dist / 340.0 * 0.3, -2.0, 500.0)


## Called by this player's authoritative projectile when it hits an enemy.
func report_hit(shot_id: int, victim: Player, headshot: bool, hit_pos: Vector3) -> void:
	if multiplayer.is_server():
		arena.match_mgr.server_handle_hit(self, shot_id, String(victim.name), headshot, hit_pos)
	else:
		server_hit.rpc_id(1, shot_id, String(victim.name), headshot, hit_pos)


@rpc("any_peer", "reliable")
func server_fire(origin: Vector3, dir: Vector3, shot_id: int) -> void:
	if not multiplayer.is_server() or multiplayer.get_remote_sender_id() != get_multiplayer_authority():
		return
	arena.match_mgr.server_register_shot(self, origin, dir, shot_id)


## Same for a zombie-mode monster (identified by its manager id).
func report_monster_hit(shot_id: int, monster_id: int, headshot: bool, hit_pos: Vector3) -> void:
	if multiplayer.is_server():
		arena.match_mgr.server_handle_monster_hit(self, shot_id, monster_id, headshot, hit_pos)
	else:
		server_monster_hit.rpc_id(1, shot_id, monster_id, headshot, hit_pos)


@rpc("any_peer", "reliable")
func server_monster_hit(shot_id: int, monster_id: int, headshot: bool, hit_pos: Vector3) -> void:
	if not multiplayer.is_server() or multiplayer.get_remote_sender_id() != get_multiplayer_authority():
		return
	arena.match_mgr.server_handle_monster_hit(self, shot_id, monster_id, headshot, hit_pos)


@rpc("any_peer", "reliable")
func server_hit(shot_id: int, target: String, headshot: bool, hit_pos: Vector3) -> void:
	if not multiplayer.is_server() or multiplayer.get_remote_sender_id() != get_multiplayer_authority():
		return
	arena.match_mgr.server_handle_hit(self, shot_id, target, headshot, hit_pos)


## Everyone except the shooter's own machine spawns a visual-only projectile.
@rpc("any_peer", "call_local", "reliable")
func net_shot_fx(origin: Vector3, dir: Vector3, shot_id: int) -> void:
	if not _from_server() or is_multiplayer_authority():
		return
	Projectile.spawn(self, origin, dir, shot_id, false)
	_play_shot_fx()

# ---------------------------------------------------------------- health (server-owned)

## Server: shield absorbs first, then health. Reaching 0 HP knocks the player
## down; any damage on a knocked-down player finishes them for the round.
func server_apply_damage(amount: float, attacker: Player, headshot: bool, weapon := "FERRO", shot_origin := Vector3.INF, hit_pos := Vector3.INF) -> void:
	if not is_hittable():
		return
	# attacker == null: a monster (zombie mode); `weapon` then names it and `shot_origin` is its position.
	var aname := String(attacker.name) if attacker else weapon
	if attacker:
		_damagers[aname] = true
		if brain:
			brain.on_hurt(attacker)
		arena.match_mgr.server_on_damage(attacker, self, amount)
	var result := HIT_HEALTH
	# Where the fatal shot came from and landed (kill cam, floating damage numbers).
	var org: Vector3 = shot_origin if shot_origin != Vector3.INF else attacker.eye_position()
	var hp_pos: Vector3 = hit_pos if hit_pos != Vector3.INF else chest_position()
	var from_pos: Vector3 = attacker.global_position if attacker else org
	if downed:
		downed = false
		net_die.rpc(aname, headshot, org, hp_pos, weapon)
		arena.match_mgr.server_on_finish(self, attacker, weapon)
		result = HIT_KILL
	else:
		var absorbed := minf(shield, amount)
		shield -= absorbed
		health = maxf(0.0, health - (amount - absorbed))
		if absorbed > 0.0:
			result = HIT_SHIELD_BREAK if shield <= 0.0 else HIT_SHIELD
		if Game.debug.has("log_items"):
			print("[DMG] %s -> %s : %d%s  bouclier=%d PV=%d" % [attacker.display_name if attacker else weapon, display_name, int(amount), " (TÊTE)" if headshot else "", int(shield), int(health)])
		if is_channeling():
			_server_end_all_channels()
		if health <= 0.0 and Game.instant_kill():
			# Battle royale / prop hunt: no knock-down, the hit is final.
			alive = false
			downed = false
			_regen_left = 0.0
			net_die.rpc(aname, headshot, org, hp_pos, weapon)
			arena.match_mgr.server_on_kill(self, attacker, headshot, _damagers.keys(), weapon)
			result = HIT_KILL
		elif health <= 0.0:
			alive = false
			downed = true
			_regen_left = 0.0
			net_down.rpc(aname, org, hp_pos, weapon, headshot)
			arena.match_mgr.server_on_kill(self, attacker, headshot, _damagers.keys(), weapon)
			result = HIT_KNOCK
		else:
			net_health.rpc(health, shield, from_pos, true)
	if attacker and not attacker.is_bot and attacker != self:
		attacker.net_hit_confirm.rpc_id(attacker.get_multiplayer_authority(), headshot, result, amount, hp_pos, display_name)


@rpc("any_peer", "call_local", "reliable")
func net_health(hp: float, sh: float, from_pos: Vector3, was_hit: bool) -> void:
	if not _from_server():
		return
	var broke := shield > 0.0 and sh <= 0.0
	var lost_health := hp < health - 0.01
	health = hp
	shield = sh
	if was_hit:
		rig.flinch()
		if broke:
			Audio.play_3d("shield_break", global_position + Vector3.UP, 2.0, 50.0, 0.05)
		# Whoever is hit gets a meaty impact heard around; the victim feels it most.
		Audio.play_3d("flesh_hit", chest_position(), 0.0, 40.0, 0.1)
		if lost_health and randf() < 0.75:
			_say("pain", 0.0)
		if is_local_human():
			damaged.emit(from_pos, lost_health)
			if arena.camera_rig:
				arena.camera_rig.hurt_kick(from_pos, lost_health)
			if lost_health:
				Audio.play_2d("hurt", -2.0)
				Audio.play_2d("pain", -3.0, randf_range(0.92, 1.08))
			else:
				Audio.play_2d("shield_zap", -3.0, randf_range(0.95, 1.05))
			if broke:
				Audio.play_2d("shield_break", -2.0)
	health_changed.emit(health)


func _clear_actions() -> void:
	bandage_target = ""
	revive_target = ""
	shield_t = -1.0
	_regen_left = 0.0
	velocity = Vector3.ZERO
	net_velocity = Vector3.ZERO
	aiming = false
	sprinting = false
	roll_t = -1.0
	slide_t = -1.0
	mantle_t = -1.0
	reload_t = -1.0
	equipped = 0


## Knocked down: crawl until revived, finished, or the round ends.
@rpc("any_peer", "call_local", "reliable")
func net_down(attacker_name: String, origin: Vector3, hit: Vector3, weapon: String, headshot: bool) -> void:
	if not _from_server():
		return
	alive = false
	downed = true
	health = 0.0
	shield = 0.0
	_clear_actions()
	_set_collision_height(true)
	Audio.play_3d("knock", global_position, 2.0, 45.0, 0.05)
	_last_voice = -10.0
	_say("pain", 3.0)
	if team == arena.local_team and not is_local_human():
		Audio.play_2d("ally_down", -8.0)
	health_changed.emit(health)
	bandage_changed.emit()
	knocked.emit()
	if is_local_human():
		var a := arena.get_player(attacker_name)
		arena.on_local_down(self, a.display_name if a else "")


@rpc("any_peer", "call_local", "reliable")
func net_die(killer_name: String, headshot: bool, origin: Vector3, hit: Vector3, weapon: String) -> void:
	if not _from_server():
		return
	alive = false
	downed = false
	health = 0.0
	shield = 0.0
	_clear_actions()
	collision.set_deferred("disabled", true)
	_clear_disguise()
	Audio.play_3d("hurt", global_position, 0.0, 40.0)
	_last_voice = -10.0
	_say("death", 3.0)
	health_changed.emit(health)
	bandage_changed.emit()
	if is_local_human():
		var k := arena.get_player(killer_name)
		arena.on_local_death(self, k.display_name if k else killer_name)
		arena.start_kill_cam(k, origin, hit, weapon, headshot)


## Picked back up (ally channel or defibrillator).
@rpc("any_peer", "call_local", "reliable")
func net_revived(hp: float, by_name: String) -> void:
	if not _from_server():
		return
	downed = false
	alive = true
	health = hp
	shield = 0.0
	_clear_actions()
	crouching = true
	_set_collision_height(true)
	health_changed.emit(health)
	bandage_changed.emit()
	Audio.play_3d("ui", global_position, -2.0, 25.0, 0.0)
	if is_local_human():
		var b := arena.get_player(by_name)
		arena.hud.on_local_revived(b.display_name if b else "")
		arena.camera_rig.stop_kill_cam()


@rpc("any_peer", "call_local", "reliable")
func net_hit_confirm(headshot: bool, result: int, amount: float, pos: Vector3, victim: String) -> void:
	if not _from_server():
		return
	hit_confirmed.emit(headshot, result)
	match result:
		HIT_KILL, HIT_KNOCK:
			Audio.play_2d("kill", -3.0)
			Audio.play_2d("hit_thump", -4.0)
		HIT_SHIELD, HIT_SHIELD_BREAK:
			Audio.play_2d("shield_hit", -4.0, 1.25)
			if result == HIT_SHIELD_BREAK:
				Audio.play_2d("shield_break", -8.0, 1.2)
		_:
			Audio.play_2d("headshot" if headshot else "hit", -2.0)
			Audio.play_2d("hit_thump", -6.0 if not headshot else -3.0, 1.3 if headshot else 1.0)
	arena.hud.on_hit_feedback(result, headshot, amount, pos, victim)


@rpc("any_peer", "call_local", "reliable")
func net_respawn(pos: Vector3, yaw: float) -> void:
	if not _from_server():
		return
	alive = true
	downed = false
	health = MAX_HEALTH
	shield = MAX_SHIELD
	shield_charges = SHIELD_CHARGES
	shield_t = -1.0
	revive_target = ""
	bandages = START_BANDAGES
	bandage_target = ""
	_regen_left = 0.0
	_damagers.clear()
	global_position = pos
	net_position = pos
	_prev_pos = pos
	_curr_pos = pos
	_snaps.clear()
	_lagged.clear()
	_rclock = -1.0
	velocity = Vector3.ZERO
	look_yaw = yaw
	body_yaw = yaw
	_prev_yaw = yaw
	_curr_yaw = yaw
	look_pitch = -0.05
	loaded = true
	reload_t = -1.0
	roll_t = -1.0
	slide_t = -1.0
	mantle_t = -1.0
	land_t = 0.0
	_fire_delay = -1.0
	_recoil_recover = 0.0
	_kick_left = Vector2.ZERO
	crouching = false
	aiming = false
	sprinting = false
	stamina = 100.0
	inventory = Items.empty_inventory()
	equipped = 0
	interact_progress = 0.0
	has_silencer = false
	has_stock = false
	rig.set_attachments(false, false)
	_clear_disguise()
	inventory_changed.emit()
	flags = F_LOADED
	collision.disabled = false
	_set_collision_height(false)
	rig.reset()
	health_changed.emit(health)
	bandage_changed.emit()
	if is_local_human():
		arena.on_local_respawn(self)


# ---------------------------------------------------------------- bandages

## Ally in front within reach that needs healing, else self if hurt.
func get_bandage_candidate() -> Player:
	var best: Player = null
	var best_d := INF
	var fwd := look_direction()
	fwd.y = 0.0
	fwd = fwd.normalized()
	for p: Player in arena.players:
		if p == self or not p.alive or p.team != team or p.health >= MAX_HEALTH:
			continue
		var to := p.global_position - global_position
		var d := to.length()
		if d > BANDAGE_RANGE or d < 0.01:
			continue
		to.y = 0.0
		if fwd.dot(to.normalized()) < 0.35:
			continue
		if d < best_d:
			best_d = d
			best = p
	if best:
		return best
	if health < MAX_HEALTH:
		return self
	return null


func get_bandage_target_node() -> Player:
	if bandage_target == "":
		return null
	return arena.get_player(bandage_target)


@rpc("any_peer", "call_local", "reliable")
func server_request_bandage(target_name: String) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != get_multiplayer_authority():
		return
	server_start_bandage(target_name)


func server_start_bandage(target_name: String) -> void:
	if not alive or bandages <= 0 or bandage_target != "" or not arena.match_allows_fire():
		return
	var t := arena.get_player(target_name)
	if t == null or not t.alive or t.team != team or t.health >= MAX_HEALTH:
		return
	if t != self and t.global_position.distance_to(global_position) > BANDAGE_RANGE + 0.8:
		return
	net_bandage.rpc(target_name, bandages, false)


@rpc("any_peer", "call_local", "reliable")
func server_cancel_bandage() -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != get_multiplayer_authority():
		return
	_server_end_all_channels()


func _server_end_bandage(completed: bool) -> void:
	net_bandage.rpc("", bandages, completed)


## Server: stops whatever is being channelled (bandage, revive, shield).
func _server_end_all_channels() -> void:
	if bandage_target != "":
		_server_end_bandage(false)
	if revive_target != "":
		net_revive.rpc("")
	if shield_t >= 0.0:
		net_shield_charge.rpc(false, shield_charges)


# ---------------------------------------------------------------- shield recharge

@rpc("any_peer", "call_local", "reliable")
func server_request_shield() -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != get_multiplayer_authority():
		return
	server_start_shield()


func server_start_shield() -> void:
	if not alive or shield_charges <= 0 or shield >= MAX_SHIELD or is_channeling() or not arena.match_allows_fire():
		return
	net_shield_charge.rpc(true, shield_charges)


@rpc("any_peer", "call_local", "reliable")
func net_shield_charge(on: bool, charges: int) -> void:
	if not _from_server():
		return
	shield_t = 0.0 if on else -1.0
	shield_charges = charges
	if on:
		aiming = false
		Audio.play_3d("shield_charge", global_position + Vector3.UP, -2.0, 30.0, 0.0)
	bandage_changed.emit()


func shield_progress() -> float:
	return clampf(shield_t / SHIELD_CHARGE_TIME, 0.0, 1.0) if shield_t >= 0.0 else -1.0


# ---------------------------------------------------------------- revive / defibrillator

## Nearest knocked-down ally within `reach`.
func get_revive_candidate(reach: float) -> Player:
	var best: Player = null
	var best_d := reach
	for p: Player in arena.players:
		if p == self or not p.downed or p.team != team:
			continue
		var d := p.global_position.distance_to(global_position)
		if d < best_d:
			best_d = d
			best = p
	return best


## The ally currently reviving this (knocked-down) player, if any.
func get_reviver() -> Player:
	for p: Player in arena.players:
		if p.revive_target == String(name):
			return p
	return null


func revive_progress() -> float:
	return clampf(revive_t / REVIVE_TIME, 0.0, 1.0) if revive_target != "" else -1.0


@rpc("any_peer", "call_local", "reliable")
func server_request_revive(target_name: String) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != get_multiplayer_authority():
		return
	server_start_revive(target_name)


func server_start_revive(target_name: String) -> void:
	if not alive or is_channeling() or not arena.match_allows_fire():
		return
	var t := arena.get_player(target_name)
	if t == null or not t.downed or t.team != team or t.get_reviver() != null:
		return
	if t.global_position.distance_to(global_position) > REVIVE_RANGE + 0.6:
		return
	net_revive.rpc(target_name)


@rpc("any_peer", "call_local", "reliable")
func net_revive(target_name: String) -> void:
	if not _from_server():
		return
	revive_target = target_name
	revive_t = 0.0
	if target_name != "":
		aiming = false
		Audio.play_3d("bandage", global_position, -6.0, 25.0, 0.0)
	bandage_changed.emit()


@rpc("any_peer", "reliable")
func server_use_defib(slot: int, target_name: String) -> void:
	if multiplayer.is_server() and multiplayer.get_remote_sender_id() == get_multiplayer_authority():
		server_do_defib(slot, target_name)


## Defibrillator: instant revive at full health.
func server_do_defib(slot: int, target_name: String) -> void:
	if not alive or not arena.match_allows_fire() or slot < 1 or slot > Items.SLOTS:
		return
	var s: Dictionary = inventory[slot - 1]
	if s.is_empty() or s.id != "defib":
		return
	var t := arena.get_player(target_name)
	if t == null or not t.downed or t.team != team or t.global_position.distance_to(global_position) > DEFIB_RANGE + 0.8:
		return
	_consume(slot)
	var r := t.get_reviver()
	if r:
		r.net_revive.rpc("")
	t.net_revived.rpc(MAX_HEALTH, String(name))
	net_defib_fx.rpc(t.global_position)
	if Game.debug.has("log_items"):
		print("[ITEM] %s défibrille %s" % [display_name, t.display_name])


@rpc("any_peer", "call_local", "reliable")
func net_defib_fx(pos: Vector3) -> void:
	if not _from_server():
		return
	rig.play_throw()
	Audio.play_3d("defib", pos, 2.0, 40.0, 0.0)
	FX.shield_hit(pos + Vector3.UP * 0.3, Vector3.UP)


@rpc("any_peer", "call_local", "reliable")
func net_bandage(target_name: String, count: int, completed: bool) -> void:
	if not _from_server():
		return
	bandage_target = target_name
	bandage_t = 0.0
	bandages = count
	if target_name != "":
		aiming = false
		Audio.play_3d("bandage", global_position, -6.0, 25.0, 0.0)
	elif completed and is_local_human():
		Audio.play_2d("ui", -6.0)
	bandage_changed.emit()


func _server_step(delta: float) -> void:
	if not alive:
		return
	if _regen_left > 0.0:
		var amt := minf(_regen_left, BANDAGE_HEAL / BANDAGE_REGEN_TIME * delta)
		_regen_left -= amt
		health = minf(MAX_HEALTH, health + amt)
		if health >= MAX_HEALTH:
			_regen_left = 0.0
		_regen_sync -= delta
		if _regen_sync <= 0.0 or _regen_left <= 0.0:
			_regen_sync = 0.2
			net_health.rpc(health, shield, Vector3.ZERO, false)
	if bandage_target != "":
		var t := get_bandage_target_node()
		var ok := t != null and t.alive and (t == self or t.global_position.distance_to(global_position) <= BANDAGE_RANGE + 1.0)
		if not ok:
			_server_end_bandage(false)
		elif bandage_t >= BANDAGE_TIME:
			bandages -= 1
			t._regen_left = minf(t._regen_left + BANDAGE_HEAL, MAX_HEALTH)
			_server_end_bandage(true)
	if shield_t >= 0.0:
		if not arena.match_allows_fire():
			net_shield_charge.rpc(false, shield_charges)
		elif shield_t >= SHIELD_CHARGE_TIME:
			shield = MAX_SHIELD
			net_shield_charge.rpc(false, shield_charges - 1)
			net_health.rpc(health, shield, Vector3.ZERO, false)
	if revive_target != "":
		var r := arena.get_player(revive_target)
		var ok := r != null and r.downed and arena.match_allows_fire() and r.global_position.distance_to(global_position) <= REVIVE_RANGE + 1.0
		if not ok:
			net_revive.rpc("")
		elif revive_t >= REVIVE_TIME:
			net_revive.rpc("")
			r.net_revived.rpc(REVIVE_HEALTH, String(name))
			if Game.debug.has("log_items"):
				print("[REVIVE] %s relève %s" % [display_name, r.display_name])


## Healing still to come from bandages (for the HUD preview).
func pending_regen() -> float:
	return _regen_left


# ---------------------------------------------------------------- items (slots 1-4, chests)

var _traj: MeshInstance3D
var _traj_mesh: ImmediateMesh
var _ghost: Node3D


## Local player only: throw arc for grenades, ghost for the barricade.
func _update_previews() -> void:
	var held := held_item() if alive else ""
	if _traj == null:
		_traj_mesh = ImmediateMesh.new()
		_traj = MeshInstance3D.new()
		_traj.mesh = _traj_mesh
		_traj.top_level = true
		_traj.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.no_depth_test = true
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.vertex_color_use_as_albedo = true
		_traj.material_override = m
		add_child(_traj)
		_ghost = Barricade.build_visual(Game.TEAM_COLORS[team])
		_ghost.top_level = true
		for mi in _ghost.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).transparency = 0.6
			(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_ghost)
	_traj_mesh.clear_surfaces()
	_ghost.visible = false
	if held == "frag" or held == "smoke":
		var origin := eye_position() + Basis(Vector3.UP, look_yaw) * Vector3(0.25, 0.1, -0.2)
		var vel := throw_direction() * Items.THROW_SPEED + Vector3.UP * 2.5
		var pts := Grenade.predict(get_world_3d().direct_space_state, origin, vel)
		if pts.size() > 2:
			var col := Items.color_of(held)
			_traj_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
			for i in range(1, pts.size()):
				_traj_mesh.surface_set_color(Color(col, 0.85 * float(i) / pts.size() + 0.15))
				_traj_mesh.surface_add_vertex(pts[i])
			_traj_mesh.surface_end()
			var end := pts[pts.size() - 1]
			_traj_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
			for k in 25:
				var a := TAU * k / 24.0
				_traj_mesh.surface_set_color(col)
				_traj_mesh.surface_add_vertex(end + Vector3(cos(a), 0.05, sin(a)) * (Items.FRAG_RADIUS * 0.5 if held == "frag" else 1.2))
			_traj_mesh.surface_end()
	elif held == "barricade":
		var xf = barricade_placement()
		if xf != null:
			_ghost.global_transform = xf
			_ghost.visible = true

## Item held in hand right now ("" = the Ferro).
var _dbg_thrown := false


## Debug: --auto_throw=frag|smoke|barricade uses that item once the round is live.
var _dbg_move_t := 0.0


var _dbg_fire_t := 0.0
var _dbg_pred := ""


## Saves `count` consecutive rendered frames (path_0.png ...).
func _debug_frame_burst(path: String, count: int) -> void:
	var base := path.get_basename()
	for i in count:
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s_%02d.png" % [base, i])


## --shot_on_fire=path.png: captures right around the first auto shot.
func _debug_fire_shots() -> void:
	var base := str(Game.debug.shot_on_fire).get_basename()
	var i := 0
	for wait in [0.0, 0.035, 0.05, 0.1, 0.25]:
		if wait > 0.0:
			await get_tree().create_timer(wait).timeout
		else:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("%s_%d.png" % [base, i])
		i += 1


## --shot_on_mantle=path.png: three captures across the local player's first mantle.
func _debug_mantle_shots() -> void:
	if has_meta("mantle_shot"):
		return
	set_meta("mantle_shot", true)
	var base := str(Game.debug.shot_on_mantle).get_basename()
	var n := int(Game.debug.get("mantle_frames", 3))
	for i in n:
		await get_tree().create_timer(_mantle_dur * (0.9 / n if n > 3 else 0.3)).timeout
		get_viewport().get_texture().get_image().save_png("%s_%d.png" % [base, i])


## --auto_aim in zombie mode: same, against the nearest visible monster.
func _debug_auto_aim_monsters() -> void:
	var cam := arena.camera_rig.cam
	var best: Monster = null
	var best_d := INF
	for m: Monster in arena.monsters.alive_list():
		var pt := m._body_body.global_position
		if get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(cam.global_position, pt, 1)):
			continue
		var d := cam.global_position.distance_to(pt)
		if d < best_d:
			best_d = d
			best = m
	if best == null:
		return
	var dir := (best._body_body.global_position - cam.global_position).normalized()
	look_yaw = atan2(-dir.x, -dir.z)
	look_pitch = asin(clampf(dir.y, -1.0, 1.0))
	aiming = true
	input.aim = true
	if not loaded:
		input.reload = true
		return
	var q2 := PhysicsRayQueryParameters3D.create(cam.global_position, cam.global_position - cam.global_basis.z * 300.0, 1 | Hitboxes.LAYER, hitboxes.rids())
	var h := get_world_3d().direct_space_state.intersect_ray(q2)
	if h and (h.collider as Node).has_meta("monster") and _now() - _last_fire > 0.3:
		input.fire = true


func _debug_auto_aim() -> void:
	if arena.monsters:
		_debug_auto_aim_monsters()
		return
	var cam := arena.camera_rig.cam
	var bone := CharacterRig.bone_name("Head" if str(Game.debug.auto_aim) == "head" else "spine_02")
	var best: Player = null
	var best_pt := Vector3.ZERO
	var best_d := INF
	for o in arena.players_root.get_children():
		var e := o as Player
		if e == null or e.team == team or not e.alive or e.rig.skeleton == null:
			continue
		var sk := e.rig.skeleton
		var pt := sk.global_transform * sk.get_bone_global_pose(sk.find_bone(bone)).origin
		if bone.ends_with("Head"):
			pt += Vector3.UP * 0.1
		var q := PhysicsRayQueryParameters3D.create(cam.global_position, pt, 1)
		if get_world_3d().direct_space_state.intersect_ray(q):
			continue
		var d := cam.global_position.distance_to(pt)
		if d < best_d and d < float(Game.debug.get("aim_range", 60.0)):
			best_d = d
			best = e
			best_pt = pt
	if best == null:
		return
	var dir := (best_pt - cam.global_position).normalized()
	look_yaw = atan2(-dir.x, -dir.z)
	look_pitch = asin(clampf(dir.y, -1.0, 1.0))
	aiming = true
	input.aim = true
	if not loaded:
		input.reload = true
		return
	# Fire only once the real crosshair ray (through the lagging camera) is on it.
	var q2 := PhysicsRayQueryParameters3D.create(cam.global_position, cam.global_position - cam.global_basis.z * 300.0, 1 | Hitboxes.LAYER, hitboxes.rids())
	var h := get_world_3d().direct_space_state.intersect_ray(q2)
	if h and Hitboxes.player_of(h.collider) == best and _now() - _last_fire > 0.3:
		input.fire = true
		if Game.debug.has("shot_on_fire") and _shot_seq == 2 and not has_meta("fire_shot"):
			set_meta("fire_shot", true)
			_debug_fire_shots()


func _debug_auto_throw() -> void:
	# --auto_move: sprint forward, slide every 3 s, jump (mantle) into walls.
	if Game.debug.has("auto_move") and arena.match_allows_movement():
		if Game.debug.has("test_wall") and not has_meta("test_wall"):
			# --test_wall=height[,thickness]: obstacle 6 m ahead to vault / mantle.
			set_meta("test_wall", true)
			var dims := str(Game.debug.test_wall).split(",")
			var size := Vector3(12.0, float(dims[0]), float(dims[1]) if dims.size() > 1 else 0.3)
			var wall := StaticBody3D.new()
			var cs := CollisionShape3D.new()
			cs.shape = BoxShape3D.new()
			(cs.shape as BoxShape3D).size = size
			wall.add_child(cs)
			var mi := MeshInstance3D.new()
			mi.mesh = BoxMesh.new()
			(mi.mesh as BoxMesh).size = size
			wall.add_child(mi)
			arena.add_child(wall)
			wall.global_transform = Transform3D(Basis(Vector3.UP, body_yaw), global_position + body_forward() * 6.0 + Vector3.UP * (size.y * 0.5 - 0.05))
		var prev := fmod(_dbg_move_t, 3.0)
		_dbg_move_t += get_physics_process_delta_time()
		var c := fmod(_dbg_move_t, 3.0)
		input.move = Vector2(0, -1)
		input.sprint = c < 1.6 or c > 2.7
		if prev < 1.6 and c >= 1.6 and not Game.debug.has("auto_roll"):
			input.crouch = true
		# --auto_roll: roll out of the sprint instead of sliding (+ --shot_on_roll=path).
		if Game.debug.has("auto_roll") and prev < 0.9 and c >= 0.9:
			input.roll = true
			if Game.debug.has("shot_on_roll") and not has_meta("roll_shot"):
				set_meta("roll_shot", true)
				_debug_frame_burst(str(Game.debug.shot_on_roll), 16)
		var ray := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 0.8, global_position + Vector3.UP * 0.8 + body_forward() * 1.0, 1, [get_rid()])
		if get_world_3d().direct_space_state.intersect_ray(ray):
			input.jump = true
	# --auto_strafe: alternate Q / D every 0.8 s (logs speed and facing with --log_moves).
	if Game.debug.has("auto_strafe") and arena.match_allows_movement():
		_dbg_move_t += get_physics_process_delta_time()
		input.move = Vector2(-1.0 if fmod(_dbg_move_t, 3.2) < 1.6 else 1.0, 0.0)
		# --strafe_sprint: hold Shift, and slide 0.9 s into each side (tests sideways sprint + slide).
		if Game.debug.has("strafe_sprint"):
			input.sprint = true
			var ph := fmod(_dbg_move_t, 1.6)
			if ph >= 0.9 and ph - get_physics_process_delta_time() < 0.9:
				input.crouch = true
		if Game.debug.has("log_moves") and Engine.get_physics_frames() % 6 == 0:
			print("[STRAFE] t=%.2f v=%.2f yaw_off=%.2f" % [_dbg_move_t, Vector3(velocity.x, 0, velocity.z).length(), angle_difference(body_yaw, look_yaw)])
	# --auto_aim[=head]: perfect aim through the camera at the nearest visible
	# enemy, fires as soon as the crosshair ray is on it (use with --log_shots).
	if Game.debug.has("auto_aim") and arena.match_allows_fire() and alive and arena.camera_rig:
		_debug_auto_aim()
	# --auto_fire: shoot whenever loaded (reloads automatically), every ~3 s.
	if Game.debug.has("auto_fire") and arena.match_allows_fire():
		_dbg_fire_t += get_physics_process_delta_time()
		if _dbg_fire_t > 3.0:
			_dbg_fire_t = 0.0
			input.fire = true
			if Game.debug.has("shot_on_fire") and not has_meta("fire_shot"):
				set_meta("fire_shot", true)
				_debug_fire_shots()
		elif not loaded:
			input.reload = true
	# --force_down: knock the local player down once the round is live (host only).
	if Game.debug.has("force_down") and arena.match_allows_fire() and alive and multiplayer.is_server() and not has_meta("forced_down"):
		set_meta("forced_down", true)
		shield = 0.0
		health = 1.0
		# Shot by the first enemy on the field (kill cam test), else by itself.
		var shooter: Player = self
		for o: Player in arena.players:
			if o.team != team and o.alive:
				shooter = o
				break
		server_apply_damage(10.0, shooter, shooter != self, "FERRO", shooter.eye_position(), chest_position())
	# --force_finish (with --force_down): finished off 2.5 s later (prone death).
	if Game.debug.has("force_finish") and has_meta("forced_down") and downed and not has_meta("forced_finish"):
		set_meta("down_dbg_t", float(get_meta("down_dbg_t", 0.0)) + get_physics_process_delta_time())
		if float(get_meta("down_dbg_t")) > 2.5:
			set_meta("forced_finish", true)
			server_apply_damage(10.0, self, false)
	if Game.debug.has("swap_loadout") and arena.match_allows_fire() and not has_meta("swapped"):
		set_meta("swapped", true)
		request_loadout(ArmorKit.random_loadout(4242))
		print("[DEBUG] tenue changée en jeu")
	# --walk_test: walk the navmesh path from spawn to the central building's upper floor
	# (door, doorway, stairs) by plain movement input, and report whether it arrives.
	if Game.debug.has("walk_test") and arena.match_allows_movement() and is_local_human():
		_dbg_walk_step()
	# --show_grenade[=frag|smoke]: a grenade hangs 2.5 m ahead at eye height (look / blink test).
	if Game.debug.has("show_grenade") and arena.match_allows_fire() and not has_meta("show_grenade"):
		set_meta("show_grenade", true)
		var gk := str(Game.debug.show_grenade) if str(Game.debug.show_grenade) in ["frag", "smoke"] else "frag"
		var gg := Grenade.spawn(self, gk, global_position + body_forward() * 2.5 + Vector3(0, 1.45, 0), Vector3.ZERO, false)
		gg._resting = true
	# --test_blast[=metres]: a frag goes off that far ahead 1 s into the round (FX / sound / ear-ring test).
	if Game.debug.has("test_blast") and arena.match_allows_fire() and not has_meta("test_blast"):
		set_meta("test_blast", true)
		await get_tree().create_timer(1.0).timeout
		var bp := global_position + body_forward() * float(Game.debug.test_blast if str(Game.debug.test_blast).is_valid_float() else 6.0) + Vector3(0, 0.1, 0)
		FX.explosion(bp)
		arena.on_explosion(bp)
	if _dbg_thrown or not Game.debug.has("auto_throw") or not arena.match_allows_fire():
		return
	var want := str(Game.debug.auto_throw)
	for i in inventory.size():
		if not inventory[i].is_empty() and inventory[i].id == want:
			_dbg_thrown = true
			if want == "barricade":
				use_item(i + 1)
			else:
				use_item(i + 1, look_direction() * 9.0 + Vector3.UP * 4.0)
			return


var _walk_path := PackedVector3Array()
var _walk_i := 0
var _walk_t := 0.0
var _walk_done := false


func _dbg_walk_step() -> void:
	if _walk_done:
		return
	_walk_t += get_physics_process_delta_time()
	var target := Vector3(4.0, arena.map.height_at(0, 0) + MapBase.FLOOR_H + 0.2, -2.5)
	if _walk_path.is_empty():
		if _walk_t < 2.0:
			return
		_walk_path = NavigationServer3D.map_get_path(get_world_3d().navigation_map, global_position, target, true)
		print("[WALKTEST] chemin de %d points" % _walk_path.size())
		if _walk_path.is_empty():
			_walk_done = true
		return
	if _walk_i >= _walk_path.size() or _walk_t > 60.0:
		_walk_done = true
		print("[WALKTEST] fin: pos %s, à %.1f m de la cible en plan, hauteur %.2f (cible %.2f) après %.1f s" % [str(global_position.snapped(Vector3.ONE * 0.1)), Vector2(global_position.x - target.x, global_position.z - target.z).length(), global_position.y, target.y, _walk_t])
		return
	var wp := _walk_path[_walk_i]
	var to := wp - global_position
	if Engine.get_physics_frames() % 150 == 0:
		print("[WALKTEST] t=%.0f pos %s point %d/%d (%s) sol=%s" % [_walk_t, str(global_position.snapped(Vector3.ONE * 0.1)), _walk_i, _walk_path.size(), str(wp.snapped(Vector3.ONE * 0.1)), surface_underfoot()])
	if Vector2(to.x, to.z).length() < 0.6 and absf(to.y) < 1.2:
		_walk_i += 1
		return
	look_yaw = atan2(-to.x, -to.z)
	look_pitch = 0.0
	input.move = Vector2(0, -1)
	input.sprint = _walk_t > 4.0


func held_item() -> String:
	if not is_multiplayer_authority():
		return _held_remote
	if equipped <= 0 or equipped > inventory.size() or inventory[equipped - 1].is_empty():
		return ""
	return inventory[equipped - 1].id


func _items_step(delta: float, can_move: bool, can_fight: bool, busy: bool) -> void:
	_item_cd = maxf(0.0, _item_cd - delta)
	if input.slot > 0 and can_move:
		var s: Dictionary = inventory[input.slot - 1]
		if s.is_empty():
			if not is_bot:
				Audio.play_2d("dry", -10.0)
		else:
			equipped = 0 if equipped == input.slot else input.slot
			if equipped > 0:
				Audio.play_3d("pin_pull" if s.id == "frag" or s.id == "smoke" else "item_equip", global_position, -4.0, 20.0)
	if equipped > 0 and held_item() == "":
		equipped = 0
	if equipped > 0:
		aiming = false
		if input.fire and can_fight and not busy and _item_cd <= 0.0:
			use_item(equipped)
	# Hold [interact] next to a crate to search it.
	var chest := arena.chest_for(self) if input.interact and can_fight and not busy and get_revive_candidate(REVIVE_RANGE) == null else null
	if chest:
		interact_progress += delta / 0.7
		if interact_progress >= 1.0:
			interact_progress = 0.0
			if multiplayer.is_server():
				server_do_open_chest(chest.index)
			else:
				server_open_chest.rpc_id(1, chest.index)
	else:
		interact_progress = 0.0


## Throw / place the item of `slot`. `throw_vel` overrides the aim (bots).
func use_item(slot: int, throw_vel := Vector3.INF) -> void:
	var s: Dictionary = inventory[slot - 1]
	if s.is_empty():
		return
	_item_cd = 0.8
	equipped = 0
	if s.id == "defib":
		var t := get_revive_candidate(DEFIB_RANGE)
		if t == null:
			Audio.play_2d("dry", -8.0)
			equipped = slot
			_item_cd = 0.3
			return
		if multiplayer.is_server():
			server_do_defib(slot, String(t.name))
		else:
			server_use_defib.rpc_id(1, slot, String(t.name))
		return
	if s.id == "barricade":
		var xf = barricade_placement()
		if xf == null:
			Audio.play_2d("dry", -8.0)
			equipped = slot
			return
		if multiplayer.is_server():
			server_do_place_barricade(slot, xf)
		else:
			server_place_barricade.rpc_id(1, slot, xf)
		return
	var origin := eye_position() + Basis(Vector3.UP, look_yaw) * Vector3(0.25, 0.1, -0.2)
	var vel := throw_vel
	if vel == Vector3.INF:
		vel = throw_direction() * Items.THROW_SPEED + Vector3.UP * 2.5
	Grenade.spawn(self, s.id, origin, vel, multiplayer.is_server())
	rig.play_throw()
	if multiplayer.is_server():
		server_do_use_item(slot, origin, vel)
	else:
		server_use_item.rpc_id(1, slot, origin, vel)


## Aim direction for throws: camera centre for the local human, look angles otherwise.
func throw_direction() -> Vector3:
	var rig_cam: CameraRig = arena.camera_rig
	if not is_bot and rig_cam and rig_cam.target == self:
		return -rig_cam.cam.global_basis.z
	return look_direction()


## Where a barricade would go (2 m ahead, on the ground, facing the aim) or null.
func barricade_placement() -> Variant:
	var fwd := Vector3(-sin(look_yaw), 0.0, -cos(look_yaw))
	var p := global_position + fwd * 2.0 + Vector3.UP * 1.5
	var space := get_world_3d().direct_space_state
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(p, p + Vector3.DOWN * 3.5, 1, [get_rid()]))
	if not hit or hit.normal.y < 0.8:
		return null
	var xf := Transform3D(Basis(Vector3.UP, look_yaw), hit.position)
	var q := PhysicsShapeQueryParameters3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(Barricade.SIZE.x, Barricade.SIZE.y - 0.2, 0.3)
	q.shape = box
	q.transform = Transform3D(xf.basis, hit.position + Vector3.UP * (Barricade.SIZE.y * 0.5 + 0.12))
	q.collision_mask = 3
	q.exclude = [get_rid()]
	if not space.intersect_shape(q, 1).is_empty():
		return null
	return xf


@rpc("any_peer", "reliable")
func server_use_item(slot: int, origin: Vector3, vel: Vector3) -> void:
	if multiplayer.is_server() and multiplayer.get_remote_sender_id() == get_multiplayer_authority():
		server_do_use_item(slot, origin, vel)


func server_do_use_item(slot: int, origin: Vector3, vel: Vector3) -> void:
	if not alive or not arena.match_allows_fire() or slot < 1 or slot > Items.SLOTS:
		return
	var s: Dictionary = inventory[slot - 1]
	if s.is_empty() or s.id == "barricade" or origin.distance_to(eye_position()) > 3.0 or vel.length() > 30.0:
		return
	var kind: String = s.id
	_consume(slot)
	arena.net_spawn_grenade.rpc(String(name), kind, origin, vel)
	if Game.debug.has("log_items"):
		print("[ITEM] %s lance %s" % [display_name, kind])


@rpc("any_peer", "reliable")
func server_place_barricade(slot: int, xf: Transform3D) -> void:
	if multiplayer.is_server() and multiplayer.get_remote_sender_id() == get_multiplayer_authority():
		server_do_place_barricade(slot, xf)


func server_do_place_barricade(slot: int, xf: Transform3D) -> void:
	if not alive or not arena.match_allows_fire() or slot < 1 or slot > Items.SLOTS:
		return
	var s: Dictionary = inventory[slot - 1]
	if s.is_empty() or s.id != "barricade" or xf.origin.distance_to(global_position) > Items.BARRICADE_RANGE + 1.0:
		return
	_consume(slot)
	arena.server_spawn_barricade(xf.orthonormalized(), team)
	if Game.debug.has("log_items"):
		print("[ITEM] %s pose une barricade" % display_name)


@rpc("any_peer", "reliable")
func server_open_chest(idx: int) -> void:
	if multiplayer.is_server() and multiplayer.get_remote_sender_id() == get_multiplayer_authority():
		server_do_open_chest(idx)


func server_do_open_chest(idx: int) -> void:
	if not alive or idx < 0 or idx >= arena.chests.size():
		return
	var c := arena.chests[idx]
	if not c.can_loot() or c.global_position.distance_to(global_position) > 3.2:
		return
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var inv := inventory.duplicate(true)
	var got := []
	var more_bandages := 0
	var more_cells := 0
	# A crate holds 2-3 things: grenades & co. go to the slots, bandages and
	# shield cells top up their counters.
	for i in rng.randi_range(2, 3):
		var id := Items.roll(rng)
		if id == "bandage":
			if bandages + more_bandages < Items.SUPPLIES.bandage.max:
				more_bandages += 1
				got.append(Items.name_of(id))
		elif id == "cell":
			if shield_charges + more_cells < Items.SUPPLIES.cell.max:
				more_cells += 1
				got.append(Items.name_of(id))
		elif Items.add(inv, id, 1) > 0:
			got.append(Items.name_of(id))
	var attach := ""
	if c.special == "silencer" and not has_silencer:
		attach = "silencer"
	elif c.special == "stock" and not has_stock:
		attach = "stock"
	if got.is_empty() and attach == "":
		net_loot.rpc_id(get_multiplayer_authority() if not is_bot else 1, "INVENTAIRE PLEIN")
		return
	arena.net_chest_opened.rpc(idx)
	net_inventory.rpc(inv)
	if more_bandages > 0:
		net_bandage.rpc("", bandages + more_bandages, false)
	if more_cells > 0:
		net_shield_charge.rpc(false, shield_charges + more_cells)
	if attach != "":
		net_attach.rpc(attach)
		got.push_front(Items.name_of(attach))
	if Game.debug.has("log_items"):
		print("[ITEM] %s ouvre la caisse %d%s : %s" % [display_name, idx, (" (" + c.special + ")") if c.special != "" else "", got])
	if not is_bot:
		net_loot.rpc_id(get_multiplayer_authority(), "+ " + "   + ".join(got))


## A Ferro attachment was fitted (server-granted, every peer plays the fitting).
@rpc("any_peer", "call_local", "reliable")
func net_attach(kind: String) -> void:
	if not _from_server():
		return
	match kind:
		"silencer":
			has_silencer = true
		"stock":
			has_stock = true
		_:
			return
	rig.set_attachments(has_silencer, has_stock)
	var watched := arena.camera_rig != null and arena.camera_rig.target == self
	if watched:
		Audio.play_2d("attach_" + kind, 3.0)
	else:
		Audio.play_3d("attach_" + kind, rig.gun.global_position, 0.0, 30.0, 0.0)
	if Game.debug.has("log_items"):
		print("[ITEM] %s monte %s" % [display_name, kind])


func _consume(slot: int) -> void:
	var inv := inventory.duplicate(true)
	inv[slot - 1].n -= 1
	if inv[slot - 1].n <= 0:
		inv[slot - 1] = {}
	net_inventory.rpc(inv)


@rpc("any_peer", "call_local", "reliable")
func net_inventory(inv: Array) -> void:
	if not _from_server():
		return
	inventory = inv
	inventory_changed.emit()


@rpc("any_peer", "call_local", "reliable")
func net_loot(text: String) -> void:
	if _from_server():
		loot_message.emit(text)


## Called by this player's projectile when it hits a barricade.
func report_barricade_hit(barricade_id: int, shot_id: int) -> void:
	if multiplayer.is_server():
		_server_barricade_hit(shot_id, barricade_id)
	else:
		server_barricade_hit.rpc_id(1, shot_id, barricade_id)


@rpc("any_peer", "reliable")
func server_barricade_hit(shot_id: int, barricade_id: int) -> void:
	if multiplayer.is_server() and multiplayer.get_remote_sender_id() == get_multiplayer_authority():
		_server_barricade_hit(shot_id, barricade_id)


func _server_barricade_hit(shot_id: int, barricade_id: int) -> void:
	if not server_shots.has(shot_id):
		return
	server_shots.erase(shot_id)
	arena.server_barricade_hit(barricade_id, DAMAGE)

# ---------------------------------------------------------------- prop hunt

func _clear_disguise() -> void:
	if prop_idx < 0:
		return
	prop_idx = -1
	rig.set_disguise({})
	hitboxes.set_prop(Vector3.ZERO)


## Prop hunt: the server moves a raider to the hunters (0) or the props (1); the visual
## is rebuilt (team colour) and the local view follows.
@rpc("any_peer", "call_local", "reliable")
func net_set_team(t: int) -> void:
	if not _from_server():
		return
	team = t
	_clear_disguise()
	var old := rig
	rig = CharacterRig.new()
	rig.top_level = true
	add_child(rig)
	rig.setup(team, display_name, loadout)
	rig.global_position = visual_position()
	old.queue_free()
	if is_local_human():
		arena.local_team = t

## Hider turning into a nearby scanned prop ([interact]): the server checks distance.
func _try_disguise() -> void:
	var idx := prop_candidate()
	if idx < 0 or idx == prop_idx:
		return
	if multiplayer.is_server():
		server_do_disguise(idx)
	else:
		server_disguise.rpc_id(1, idx)


## Closest catalogued prop in front of the hider, within reach (-1 = none).
func prop_candidate() -> int:
	if not Game.is_ph() or team != 1 or not alive:
		return -1
	var fwd := look_direction()
	fwd.y = 0.0
	fwd = fwd.normalized()
	var best := -1
	var best_d := PROP_REACH
	for i in Scan.catalog.size():
		var e: Dictionary = Scan.catalog[i]
		var to: Vector3 = (e.pos as Vector3) - global_position
		to.y = 0.0
		var d := to.length() - maxf(e.size.x, e.size.z) * 0.35
		if d < best_d and (d < 0.9 or fwd.dot(to.normalized()) > 0.35):
			best_d = d
			best = i
	return best


const PROP_REACH := 3.2


@rpc("any_peer", "reliable")
func server_disguise(idx: int) -> void:
	if multiplayer.is_server() and multiplayer.get_remote_sender_id() == get_multiplayer_authority():
		server_do_disguise(idx)


func server_do_disguise(idx: int) -> void:
	if not alive or team != 1 or not Game.is_ph() or idx < 0 or idx >= Scan.catalog.size():
		return
	if arena.match_mgr.state != MatchManager.State.LIVE:
		return
	var e: Dictionary = Scan.catalog[idx]
	if (e.pos as Vector3).distance_to(global_position) > PROP_REACH + 3.0:
		return
	net_disguise.rpc(idx)


@rpc("any_peer", "call_local", "reliable")
func net_disguise(idx: int) -> void:
	if not _from_server():
		return
	prop_idx = idx
	rig.set_disguise(Scan.catalog[idx] if idx >= 0 and idx < Scan.catalog.size() else {})
	hitboxes.set_prop((Scan.catalog[idx].size as Vector3) if prop_idx >= 0 else Vector3.ZERO)
	if idx >= 0:
		Audio.play_3d("pin_pull", global_position, -4.0, 25.0, 0.1, 0.7)
		FX.smoke_puff(global_position + Vector3(0, 0.6, 0), Vector3.UP, 10, 0.5, Color(0.8, 0.78, 0.72, 0.3))


## Hider's whistle (every 20 s): a loud, recognisable call so the hunter can home in.
@rpc("any_peer", "call_local", "reliable")
func net_whistle() -> void:
	if not _from_server():
		return
	Audio.play_3d("whistle", global_position + Vector3(0, 0.8, 0), 4.0, 85.0, 0.03)


# ---------------------------------------------------------------- outfit

## Ask for a new outfit (validated by the server, then applied on every peer).
func request_loadout(l: Dictionary) -> void:
	if multiplayer.is_server():
		net_loadout.rpc(ArmorKit.sanitize(l))
	else:
		server_set_loadout.rpc_id(1, l)


@rpc("any_peer", "reliable")
func server_set_loadout(l: Dictionary) -> void:
	if multiplayer.is_server() and multiplayer.get_remote_sender_id() == get_multiplayer_authority():
		net_loadout.rpc(ArmorKit.sanitize(l))


@rpc("any_peer", "call_local", "reliable")
func net_loadout(l: Dictionary) -> void:
	if not _from_server():
		return
	loadout = l
	# Rebuild the whole visual (body type may change); gameplay is unaffected.
	var old := rig
	rig = CharacterRig.new()
	rig.top_level = true
	add_child(rig)
	rig.setup(team, display_name, loadout)
	rig.set_attachments(has_silencer, has_stock)
	rig.global_position = visual_position()
	if not alive and not downed:
		rig.play_dead_instant()
	old.queue_free()


# ---------------------------------------------------------------- queries

func _from_server() -> bool:
	var s := multiplayer.get_remote_sender_id()
	return s == 1 or s == 0


func _now() -> float:
	return Time.get_ticks_msec() * 0.001


func recent_fire() -> bool:
	return _now() - _last_fire < 0.7


func reload_progress() -> float:
	return reload_t / RELOAD_TIME if reload_t >= 0.0 else -1.0


func roll_progress() -> float:
	return roll_t / ROLL_TIME if roll_t >= 0.0 else -1.0


func bandage_progress() -> float:
	return clampf(bandage_t / BANDAGE_TIME, 0.0, 1.0) if bandage_target != "" else -1.0


func grounded() -> bool:
	if mantle_t >= 0.0:
		return true
	if is_multiplayer_authority():
		return is_on_floor()
	return absf(net_velocity.y) < 1.0


func mantle_duration() -> float:
	return _mantle_dur


func head_height() -> float:
	return 0.35 if downed else (0.95 if crouching else 1.5)


func eye_position() -> Vector3:
	return global_position + Vector3(0, 0.4 if downed else (1.05 if crouching else 1.5), 0)


func chest_position() -> Vector3:
	return global_position + Vector3(0, 0.3 if downed else (0.8 if crouching else 1.25), 0)


func look_direction() -> Vector3:
	return Basis.from_euler(Vector3(look_pitch, look_yaw, 0.0)) * Vector3.FORWARD


func body_forward() -> Vector3:
	return Vector3(-sin(body_yaw), 0.0, -cos(body_yaw))
