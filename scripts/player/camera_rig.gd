class_name CameraRig
extends Node3D
## Over-the-shoulder camera. Follows `target` (local player, or a teammate
## when spectating) using its replicated look angles.
##
## Feel: the pivot trails the body slightly (spring), dips on
## landings, drops low and rolls a touch during slides, bobs gently while
## running and pulls in tight when shouldering the Ferro.

const PIVOT_STAND := 1.6
const PIVOT_CROUCH := 1.2
const PIVOT_SLIDE := 0.85
const PIVOT_DOWN := 0.6

var target: Player
var cam: Camera3D
var _pitch_node: Node3D
var _spring: SpringArm3D
var _shoulder := 1.0
var _aim := 0.0
var _crouch := 0.0
var _slide := 0.0
var _trauma := 0.0
var _side_offset := 0.62
var _noise := FastNoiseLite.new()
var _t := 0.0
var _attrs: CameraAttributesPractical
## Spring-follow of the body position (lag) and landing dip.
var _follow := Vector3.ZERO
var _follow_vel := Vector3.ZERO
var _dip := 0.0
var _dip_vel := 0.0
var _bob_phase := 0.0
var _roll := 0.0
var _down := 0.0
# Shot springs: FOV punch (deg), push-back (m), roll jolt (rad), shake burst.
var _fov_kick := 0.0
var _fov_vel := 0.0
var _push := 0.0
var _push_vel := 0.0
var _roll_kick := 0.0
var _roll_kick_vel := 0.0
var _jolt := 0.0
var _base_fov := 0.0
var _was_aim := false


func arena_local_target() -> Player:
	var a := get_parent() as Arena
	return a.local_player if a else null
var _last_target: Player


func _ready() -> void:
	_pitch_node = Node3D.new()
	add_child(_pitch_node)
	_spring = SpringArm3D.new()
	_spring.collision_mask = 1
	_spring.margin = 0.15
	var sh := SphereShape3D.new()
	sh.radius = 0.2
	_spring.shape = sh
	_spring.spring_length = 2.9
	_pitch_node.add_child(_spring)
	cam = Camera3D.new()
	cam.fov = Game.fov
	cam.near = 0.05
	cam.far = 1200.0
	_spring.add_child(cam)
	cam.make_current()
	_noise.frequency = 2.0
	# Background depth-of-field while aiming down the Ferro (quality >= Élevé).
	if Game.quality >= 2:
		_attrs = CameraAttributesPractical.new()
		_attrs.dof_blur_far_distance = 55.0
		_attrs.dof_blur_far_transition = 40.0
		_attrs.dof_blur_amount = 0.0
		cam.attributes = _attrs


func kick(amount: float) -> void:
	_trauma = minf(_trauma + 0.55 * amount, 1.0)


## Ferro shot: FOV punch, camera shoved back, a roll jolt and a sharp shake,
## all on springs so they snap in and settle out.
func fire_kick(aimed: bool) -> void:
	var k := 0.7 if aimed else 1.0
	_fov_vel += 70.0 * k
	_push_vel += 2.6 * k
	_roll_kick_vel += randf_range(-1.0, 1.0) * 0.55 * k + 0.25 * k
	_trauma = minf(_trauma + 0.45 * k, 1.0)
	_jolt = 1.0


## Landing impact: 0..1.
func dip(amount: float) -> void:
	_dip_vel -= 2.6 * amount
	_trauma = minf(_trauma + 0.25 * amount * amount, 1.0)


var _env: Environment
var _fog_base := {}


## Shouldered on the Ferro the far view gets crisp: no depth-of-field blur,
## haze and volumetric fog thinned out, extra sharpening, less lens fringing.
func _apply_clarity() -> void:
	if _env == null:
		var arena := get_parent() as Arena
		if arena == null or arena.map == null or arena.map.environment_node == null:
			return
		_env = arena.map.environment_node.environment
		_fog_base = {"d": _env.fog_density, "v": _env.volumetric_fog_density, "a": _env.fog_aerial_perspective}
	var k := _aim
	_env.fog_density = _fog_base.d * lerpf(1.0, 0.3, k)
	_env.volumetric_fog_density = _fog_base.v * lerpf(1.0, 0.35, k)
	_env.fog_aerial_perspective = _fog_base.a * lerpf(1.0, 0.25, k)
	var arena2 := get_parent() as Arena
	if arena2 and arena2.post_mat:
		arena2.post_mat.set_shader_parameter("sharpen", lerpf(0.4, 1.0, k))
		arena2.post_mat.set_shader_parameter("aberration", lerpf(0.0025, 0.0008, k))
		# Shouldered: soft focus towards the edges, razor sharp in the middle, darker rim.
		arena2.post_mat.set_shader_parameter("focus", k)
		arena2.post_mat.set_shader_parameter("vignette", lerpf(0.3, 0.52, k))


## Taking a hit: the view is shoved and rolled away from where it came from
## (harder when health was lost, a lighter jolt when the shield took it).
func hurt_kick(from_pos: Vector3, health_lost: bool) -> void:
	var k := 1.0 if health_lost else 0.45
	var side := 0.0
	if target and is_instance_valid(target):
		var local_v := global_basis.inverse() * (from_pos - target.global_position)
		side = signf(local_v.x)
	_roll_kick_vel += (side * 0.9 + randf_range(-0.3, 0.3)) * k
	_push_vel += 1.8 * k
	_fov_vel -= 38.0 * k
	_trauma = minf(_trauma + 0.55 * k, 1.0)
	_jolt = 1.0


## A slug whipped past close by (k 0..1 = how close): flinch.
func suppress(k: float) -> void:
	_trauma = minf(_trauma + 0.3 * k, 1.0)
	_roll_kick_vel += randf_range(-1.0, 1.0) * 0.4 * k
	_fov_vel -= 26.0 * k


# ---------------------------------------------------------------- kill cam
#
# When the local raider goes down the camera flies the fatal shot: it starts
# over the shooter's shoulder, a glowing slug traces a dotted line to the
# impact, then the camera follows the line in and eases back to the body.

const KC_OUT := 0.5
const KC_HOLD := 1.25
var _kc_t := -1.0
var _kc_dur := 3.4
var _kc_origin := Vector3.ZERO
var _kc_hit := Vector3.ZERO
var _kc_dir := Vector3.FORWARD
var _kc_blend := 0.0
var _kc_dashes: MultiMeshInstance3D
var _kc_slug: MeshInstance3D
var _kc_ring: MeshInstance3D
var _kc_tag: Label3D
var _kc_cam: Camera3D
var _kc_count := 0


func kill_cam_active() -> bool:
	return _kc_t >= 0.0


func kill_cam_time() -> float:
	return _kc_t


func start_kill_cam(origin: Vector3, hit: Vector3, killer_name: String, dur := 3.4) -> void:
	stop_kill_cam(true)
	_kc_origin = origin
	_kc_hit = hit
	var d := hit - origin
	# Degenerate shot (explosion, point blank): look at the victim from above & behind.
	if d.length() < 1.5:
		d = Vector3(0.0, -0.2, -1.0) * 2.0
		_kc_origin = hit - d.normalized() * 4.0 + Vector3.UP * 1.5
	_kc_dir = (hit - _kc_origin).normalized()
	_kc_t = 0.0
	_kc_dur = dur
	_build_kill_cam_visuals(killer_name)


func stop_kill_cam(immediate := false) -> void:
	if _kc_t < 0.0:
		return
	_kc_t = -1.0
	if immediate:
		_kc_blend = 0.0
		_free_kill_cam_visuals()


func _build_kill_cam_visuals(killer_name: String) -> void:
	_free_kill_cam_visuals()
	var line := _kc_hit - _kc_origin
	var len := line.length()
	_kc_count = clampi(int(len / 0.8), 6, 140)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true
	mat.albedo_color = Color(4.0, 0.35, 0.25, 0.85)
	var dash := BoxMesh.new()
	dash.size = Vector3(0.045, 0.045, 0.34)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = dash
	mm.instance_count = _kc_count
	var basis := Basis.looking_at(_kc_dir, Vector3.UP)
	for i in _kc_count:
		mm.set_instance_transform(i, Transform3D(basis, _kc_origin + _kc_dir * (len * (i + 0.5) / _kc_count)))
	mm.visible_instance_count = 0
	_kc_dashes = MultiMeshInstance3D.new()
	_kc_dashes.multimesh = mm
	_kc_dashes.material_override = mat
	_kc_dashes.top_level = true
	_kc_dashes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_kc_dashes)
	var sphere := SphereMesh.new()
	sphere.radius = 0.09
	sphere.height = 0.18
	sphere.radial_segments = 12
	sphere.rings = 6
	var hot := mat.duplicate() as StandardMaterial3D
	hot.albedo_color = Color(16.0, 5.0, 3.0, 1.0)
	_kc_slug = MeshInstance3D.new()
	_kc_slug.mesh = sphere
	_kc_slug.material_override = hot
	_kc_slug.top_level = true
	_kc_slug.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_kc_slug)
	var ring := TorusMesh.new()
	ring.inner_radius = 0.15
	ring.outer_radius = 0.18
	ring.rings = 24
	ring.ring_segments = 6
	_kc_ring = MeshInstance3D.new()
	_kc_ring.mesh = ring
	_kc_ring.material_override = mat
	_kc_ring.top_level = true
	_kc_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_kc_ring.visible = false
	add_child(_kc_ring)
	_kc_tag = Label3D.new()
	_kc_tag.text = killer_name.to_upper()
	_kc_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_kc_tag.no_depth_test = true
	_kc_tag.fixed_size = true
	_kc_tag.pixel_size = 0.0011
	_kc_tag.font_size = 26
	_kc_tag.outline_size = 8
	_kc_tag.modulate = Color(1.0, 0.35, 0.3)
	_kc_tag.top_level = true
	add_child(_kc_tag)
	_kc_tag.global_position = _kc_origin + Vector3(0, 0.55, 0)


func _free_kill_cam_visuals() -> void:
	for n in [_kc_dashes, _kc_slug, _kc_ring, _kc_tag, _kc_cam]:
		if is_instance_valid(n):
			n.queue_free()
	_kc_dashes = null
	_kc_slug = null
	_kc_ring = null
	_kc_tag = null
	_kc_cam = null
	if cam and not cam.current:
		cam.make_current()


## Camera along the shot: behind the shooter during the hold, then dollying
## down the line of fire to the impact, always looking where the slug goes.
func _kill_cam_transform(t: float) -> Transform3D:
	var side := _kc_dir.cross(Vector3.UP)
	side = side.normalized() if side.length() > 0.05 else Vector3.RIGHT
	var p1 := _kc_origin - _kc_dir * 2.7 + Vector3.UP * 0.85 + side * 0.75
	var p3 := _kc_hit - _kc_dir * 3.4 + Vector3.UP * 0.7 - side * 1.1
	var k := clampf((t - KC_HOLD) / maxf(_kc_dur - KC_HOLD - KC_OUT, 0.3), 0.0, 1.0)
	k = k * k * (3.0 - 2.0 * k)
	var pos := p1.lerp(p3, k)
	pos += side * sin(t * 1.9) * 0.04 + Vector3.UP * sin(t * 2.3) * 0.03
	var look_from := _kc_origin + _kc_dir * 2.0
	var look := look_from.lerp(_kc_hit, clampf(k * 1.4, 0.0, 1.0))
	# Keep the lens out of walls: pull in along the view line.
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(look, pos, 1)
	var h := space.intersect_ray(q)
	if h:
		pos = h.position + h.normal * 0.25
	return Transform3D(Basis.looking_at(look - pos, Vector3.UP), pos)


func _apply_kill_cam(delta: float) -> void:
	if _kc_t < 0.0 and _kc_blend <= 0.0:
		return
	var normal_xf := cam.global_transform
	if _kc_t >= 0.0:
		_kc_t += delta
		if _kc_t >= _kc_dur:
			_kc_t = -1.0
			Audio.play_2d("killcam_out", -6.0)
	var running := _kc_t >= 0.0 and _kc_t < _kc_dur - KC_OUT
	_kc_blend = move_toward(_kc_blend, 1.0 if running else 0.0, delta / (0.28 if running else KC_OUT))
	if _kc_blend <= 0.0 and _kc_t < 0.0:
		_free_kill_cam_visuals()
		return
	var tt := _kc_t if _kc_t >= 0.0 else _kc_dur
	var w := smoothstep(0.0, 1.0, _kc_blend)
	# The gameplay camera keeps running underneath; a second one flies the shot.
	if _kc_cam == null:
		_kc_cam = Camera3D.new()
		_kc_cam.top_level = true
		_kc_cam.near = 0.05
		_kc_cam.far = 1200.0
		add_child(_kc_cam)
	if not _kc_cam.current:
		_kc_cam.make_current()
	_kc_cam.fov = lerpf(cam.fov, 58.0, w)
	_kc_cam.global_transform = normal_xf.interpolate_with(_kill_cam_transform(tt), w)
	# Slug flight: leaves the muzzle after the hold starts, takes ~0.8 s.
	if is_instance_valid(_kc_slug):
		var fly := clampf((tt - 0.35) / 0.85, 0.0, 1.0)
		fly = fly * fly * (3.0 - 2.0 * fly)
		_kc_slug.visible = tt > 0.35 and fly < 1.0
		_kc_slug.global_position = _kc_origin.lerp(_kc_hit, fly)
		_kc_dashes.multimesh.visible_instance_count = int(_kc_count * fly)
		_kc_ring.visible = fly >= 1.0
		if _kc_ring.visible:
			var pulse := 1.0 + 0.35 * sin((tt - 1.2) * 7.0)
			var look_back := Basis.looking_at(cam.global_position - _kc_hit, Vector3.UP) * Basis(Vector3.RIGHT, PI / 2)
			_kc_ring.global_transform = Transform3D(look_back.scaled(Vector3.ONE * pulse), _kc_hit)


func _process(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	_process_cam(delta)
	Game.prof_add("camera", t0)


func _process_cam(delta: float) -> void:
	# Debug free camera for map screenshots: --cam_at=x,y,z --cam_look=x,y,z
	if Game.debug.has("cam_at"):
		var at := str(Game.debug.cam_at).split_floats(",")
		var lk := str(Game.debug.get("cam_look", "0,0,0")).split_floats(",")
		cam.top_level = true
		cam.global_transform = Transform3D(Basis(), Vector3(at[0], at[1], at[2])).looking_at(Vector3(lk[0], lk[1], lk[2]))
		return
	if target == null or not is_instance_valid(target):
		return
	delta = minf(delta, 0.05)
	_t += delta
	var t := target
	var k := 1.0 - exp(-delta * 14.0)
	# Edge of the aim button: a quick zoom punch (overshoot then settle) and a foley whoosh.
	if t.aiming != _was_aim:
		_was_aim = t.aiming
		_fov_vel += -75.0 if t.aiming else 45.0
		_roll_kick_vel += 0.12 * _shoulder * (1.0 if t.aiming else -1.0)
		if t == arena_local_target():
			Audio.play_2d("ads_in" if t.aiming else "ads_out", -9.0)
	_aim = lerpf(_aim, 1.0 if t.aiming else 0.0, 1.0 - exp(-delta * 12.0))
	var low := t.crouching or t.roll_t >= 0.0 or t.mantle_t >= 0.0
	_crouch = lerpf(_crouch, 1.0 if low else 0.0, 1.0 - exp(-delta * 9.0))
	_slide = lerpf(_slide, 1.0 if t.slide_t >= 0.0 else 0.0, 1.0 - exp(-delta * (12.0 if t.slide_t >= 0.0 else 6.0)))
	_shoulder = lerpf(_shoulder, -1.0 if t.shoulder_left else 1.0, k)

	# Body follow: critically-damped spring, stiffer when aiming so ADS stays crisp.
	var body := t.visual_position()
	if t != _last_target or _follow.distance_to(body) > 3.0:
		_follow = body
		_follow_vel = Vector3.ZERO
		_last_target = t
	# Closed-form critically damped spring (SmoothDamp): stable at any frame rate.
	var smooth_time := lerpf(0.05, 0.02, _aim)
	var omega := 2.0 / smooth_time
	var x := omega * delta
	var e := 1.0 / (1.0 + x + 0.48 * x * x + 0.235 * x * x * x)
	var change := _follow - body
	var temp := (_follow_vel + change * omega) * delta
	_follow_vel = (_follow_vel - temp * omega) * e
	_follow = body + (change + temp) * e
	# Vertical: follow tighter (stairs/landings handled by the dip spring).
	_follow.y = lerpf(_follow.y, body.y, 1.0 - exp(-delta * 30.0))

	# Landing dip spring.
	_dip_vel += (-_dip * 120.0 - _dip_vel * 16.0) * delta
	_dip += _dip_vel * delta

	# Run bob (very subtle, off while aiming).
	var hspeed := Vector2(t.velocity.x, t.velocity.z).length()
	var grounded := t.is_on_floor() and t.slide_t < 0.0 and t.roll_t < 0.0
	_bob_phase += delta * hspeed * 1.55
	var bob_amt := clampf(hspeed / 6.5, 0.0, 1.0) * (1.0 - _aim) * (1.0 if grounded else 0.0)
	var bob_y := absf(sin(_bob_phase)) * 0.035 * bob_amt
	var bob_x := sin(_bob_phase * 0.5) * 0.02 * bob_amt

	_down = lerpf(_down, 1.0 if t.downed else 0.0, 1.0 - exp(-delta * 5.0))
	var pivot_h := lerpf(PIVOT_STAND, PIVOT_CROUCH, _crouch)
	pivot_h = lerpf(pivot_h, PIVOT_SLIDE, _slide)
	pivot_h = lerpf(pivot_h, PIVOT_DOWN, _down)
	var pivot := _follow + Vector3(0, pivot_h + _dip - bob_y, 0)
	if not t.alive and not t.downed:
		pivot = body + Vector3(0, 1.0, 0)
	global_position = pivot
	rotation = Vector3(0, t.look_yaw, 0)

	# Keep the shoulder offset out of walls.
	var want_side := lerpf(0.62, 0.72, _aim) * _shoulder
	var right := global_basis.x
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(pivot, pivot + right * (want_side + signf(want_side) * 0.25), 1)
	var hit := space.intersect_ray(q)
	if hit:
		var max_side := maxf(pivot.distance_to(hit.position) - 0.3, 0.0)
		want_side = signf(want_side) * minf(absf(want_side), max_side)
	_side_offset = lerpf(_side_offset, want_side, k)

	_trauma = move_toward(_trauma, 0.0, delta * 2.2)
	var shake := _trauma * _trauma
	var sx := _noise.get_noise_2d(_t * 40.0, 0.0) * 0.05 * shake
	var sy := _noise.get_noise_2d(0.0, _t * 40.0) * 0.05 * shake
	# Shot springs (stiff, slightly under-damped: snap in, small overshoot, settle).
	var steps := maxi(1, ceili(delta / 0.004))
	var h := delta / steps
	for i in steps:
		_fov_vel += (-_fov_kick * 260.0 - _fov_vel * 22.0) * h
		_fov_kick += _fov_vel * h
		_push_vel += (-_push * 320.0 - _push_vel * 24.0) * h
		_push += _push_vel * h
		_roll_kick_vel += (-_roll_kick * 280.0 - _roll_kick_vel * 18.0) * h
		_roll_kick += _roll_kick_vel * h
	# Very short high-frequency jolt right on the shot.
	_jolt = move_toward(_jolt, 0.0, delta * 9.0)
	sx += _noise.get_noise_2d(_t * 120.0, 31.0) * 0.03 * _jolt * _jolt
	sy += _noise.get_noise_2d(31.0, _t * 120.0) * 0.03 * _jolt * _jolt
	# Slide rumble.
	if t.slide_t >= 0.0:
		sx += _noise.get_noise_2d(_t * 25.0, 7.0) * 0.006
		sy += _noise.get_noise_2d(7.0, _t * 25.0) * 0.006

	# Camera roll: lean into slides (towards the shoulder side) and strafes.
	var local_v := global_basis.inverse() * t.velocity
	var want_roll := -local_v.x * 0.004 * (1.0 - _aim) - _slide * 0.045 * signf(_shoulder)
	_roll = lerpf(_roll, want_roll, 1.0 - exp(-delta * 6.0))

	_pitch_node.rotation = Vector3(t.look_pitch + sx, 0, 0)
	_spring.position = Vector3(_side_offset + bob_x, 0, 0)
	_spring.spring_length = lerpf(2.9, 1.8, _aim) + 0.25 * _slide - 0.4 * _down + (1.2 if not t.alive and not t.downed else 0.0)
	_spring.rotation = Vector3(0, 0, 0)
	cam.rotation = Vector3(0, sy, sy * 0.5 + _roll + _roll_kick)
	_spring.spring_length += _push
	_apply_clarity()
	# Debug framing (screenshots): --cam_dist=m --cam_yaw=deg --cam_pitch=deg
	if Game.debug.has("cam_dist"):
		_spring.spring_length = float(Game.debug.cam_dist)
		rotation.y += deg_to_rad(float(Game.debug.get("cam_yaw", 0.0)))
		_pitch_node.rotation.x = deg_to_rad(float(Game.debug.get("cam_pitch", -8.0)))
	var move_fov := 0.0
	if t.sprinting:
		move_fov = 6.0
	move_fov += 8.0 * _slide
	if _base_fov <= 0.0:
		_base_fov = cam.fov
	_base_fov = lerpf(_base_fov, lerpf(Game.fov + move_fov, Game.fov * 0.6, _aim), 1.0 - exp(-delta * 10.0))
	cam.fov = _base_fov + _fov_kick
	_apply_kill_cam(delta)
