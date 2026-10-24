class_name Grenade
extends Node3D
## Thrown frag / smoke grenade. Every peer runs the same deterministic bounce
## simulation against world geometry; only the server's copy deals damage.

const GRAVITY := 13.0
const RADIUS := 0.06
const BOUNCE := 0.38
const FRICTION := 0.55

var kind := "frag"
var thrower: Player
var authoritative := false

var _pos := Vector3.ZERO
var _prev := Vector3.ZERO
var _vel := Vector3.ZERO
var _t := 0.0
var _resting := false
var _done := false
var _spin := Vector3.ZERO
var _model: Node3D
var _last_bounce := -1.0


static func spawn(p_thrower: Player, p_kind: String, origin: Vector3, vel: Vector3, p_auth: bool) -> Grenade:
	var g := Grenade.new()
	g.kind = p_kind
	g.thrower = p_thrower
	g.authoritative = p_auth
	g._pos = origin
	g._prev = origin
	g._vel = vel
	g._spin = Vector3(randf_range(-12, 12), randf_range(-6, 6), randf_range(-12, 12))
	var scene := p_thrower.get_tree().current_scene
	scene.add_child(g)
	g.global_position = origin
	if scene is Arena:
		(scene as Arena).grenades.append(g)
	# Pin out, lever off (the spoon pings away from a frag).
	Audio.play_3d("pin_pull", origin, -4.0, 25.0, 0.05)
	if p_kind == "frag":
		Audio.play_3d_delayed("grenade_spoon", origin, 0.12, -6.0, 40.0)
	return g


func _ready() -> void:
	_model = Node3D.new()
	add_child(_model)
	if kind == "frag":
		# Bigger than the hand model so it reads from afar: olive shell, ribs, a yellow
		# warning band, spoon and a blinking red beacon.
		var body := SphereMesh.new()
		body.radius = 0.075
		body.height = 0.16
		_add(body, Mats.flat("frag_body", Color(0.22, 0.27, 0.16), 0.6, 0.2), Vector3.ZERO)
		var band := CylinderMesh.new()
		band.top_radius = 0.077
		band.bottom_radius = 0.077
		band.height = 0.022
		band.radial_segments = 16
		band.rings = 1
		_add(band, Mats.emissive("frag_band", Color(0.95, 0.8, 0.1), 0.5, false), Vector3(0, -0.015, 0))
		var top := CylinderMesh.new()
		top.top_radius = 0.024
		top.bottom_radius = 0.03
		top.height = 0.055
		_add(top, Mats.gun_metal(), Vector3(0, 0.095, 0))
		var lever := BoxMesh.new()
		lever.size = Vector3(0.016, 0.12, 0.028)
		_add(lever, Mats.gun_metal(), Vector3(0.05, 0.04, 0))
		_led_pos = Vector3(0, 0.128, 0)
	else:
		var can := CylinderMesh.new()
		can.top_radius = 0.05
		can.bottom_radius = 0.05
		can.height = 0.2
		_add(can, Mats.flat("smoke_can", Color(0.55, 0.57, 0.58), 0.5, 0.3), Vector3.ZERO)
		var band := CylinderMesh.new()
		band.top_radius = 0.053
		band.bottom_radius = 0.053
		band.height = 0.035
		_add(band, Mats.emissive("smoke_band", Color(0.9, 0.9, 0.95), 0.6, false), Vector3(0, 0.055, 0))
		var cap := CylinderMesh.new()
		cap.top_radius = 0.03
		cap.bottom_radius = 0.04
		cap.height = 0.03
		_add(cap, Mats.gun_metal(), Vector3(0, 0.115, 0))
		_led_pos = Vector3(0, 0.145, 0)
	# Blinking red beacon: a bright bead plus a small light that tints what is nearby.
	_led_mat = StandardMaterial3D.new()
	_led_mat.albedo_color = Color(1.0, 0.1, 0.05)
	_led_mat.emission_enabled = true
	_led_mat.emission = Color(1.0, 0.08, 0.04)
	_led_mat.emission_energy_multiplier = 0.0
	var bead := SphereMesh.new()
	bead.radius = 0.016
	bead.height = 0.032
	_add(bead, _led_mat, _led_pos)
	_halo = MeshInstance3D.new()
	var hq := QuadMesh.new()
	hq.size = Vector2(0.9, 0.9)
	_halo.mesh = hq
	var hm := StandardMaterial3D.new()
	hm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	hm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	hm.albedo_texture = _glow_texture()
	hm.albedo_color = Color(1, 0.12, 0.06, 0.0)
	hm.no_depth_test = false
	_halo.material_override = hm
	_halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_halo.position = _led_pos
	_model.add_child(_halo)
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.12, 0.06)
	_light.omni_range = 3.0
	_light.light_energy = 0.0
	_light.shadow_enabled = false
	_light.position = _led_pos
	_model.add_child(_light)


var _led_pos := Vector3.ZERO
var _led_mat: StandardMaterial3D
var _halo: MeshInstance3D
var _light: OmniLight3D
static var _glow_tex: GradientTexture2D


static func _glow_texture() -> GradientTexture2D:
	if _glow_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		_glow_tex = GradientTexture2D.new()
		_glow_tex.gradient = g
		_glow_tex.fill = GradientTexture2D.FILL_RADIAL
		_glow_tex.fill_from = Vector2(0.5, 0.5)
		_glow_tex.fill_to = Vector2(1.0, 0.5)
		_glow_tex.width = 64
		_glow_tex.height = 64
	return _glow_tex


## Beacon: blinks at 2 Hz and speeds up towards the blast (frag); the smoke can keeps a
## steady slow pulse.
func _blink() -> void:
	var rate := 2.0
	if kind == "frag":
		rate = lerpf(2.5, 12.0, clampf(_t / Items.FRAG_FUSE, 0.0, 1.0) ** 2.0)
	_blink_phase += get_process_delta_time() * rate
	var on := fposmod(_blink_phase, 1.0) < 0.45
	var k := 1.0 if on else 0.0
	_led_mat.emission_energy_multiplier = 1.0 + 7.0 * k
	_light.light_energy = 1.6 * k
	(_halo.material_override as StandardMaterial3D).albedo_color.a = 0.85 * k
	if on and not _last_on:
		_on_blink()
	_last_on = on


func _on_blink() -> void:
	# Tick of the fuse, rising in pitch as the blast nears (frag only).
	if kind == "frag" and not _done:
		Audio.play_3d("beep", global_position, -13.0, 26.0, 0.0, 1.3 + 1.1 * clampf(_t / Items.FRAG_FUSE, 0.0, 1.0))


var _blink_phase := 0.0
var _last_on := false

func _add(mesh: Mesh, mat: Material, pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	_model.add_child(mi)


func _physics_process(delta: float) -> void:
	if _done:
		return
	_t += delta
	_prev = _pos
	if not _resting:
		_vel.y -= GRAVITY * delta
		var next := _pos + _vel * delta
		var q := PhysicsRayQueryParameters3D.create(_pos, next + _vel.normalized() * RADIUS, 1)
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		if hit:
			var n: Vector3 = hit.normal
			_pos = hit.position + n * RADIUS
			var speed := _vel.length()
			var vn := n * _vel.dot(n)
			var vt := _vel - vn
			_vel = vt * FRICTION - vn * BOUNCE
			_spin *= 0.6
			if speed > 2.5 and _t - _last_bounce > 0.08:
				_last_bounce = _t
				Audio.play_3d("grenade_bounce", _pos, -8.0 + minf(speed, 10.0), 35.0, 0.2)
			if _vel.length() < 1.2 and n.y > 0.6:
				_resting = true
				_vel = Vector3.ZERO
		else:
			_pos = next
	if kind == "frag" and _t >= Items.FRAG_FUSE:
		_explode()
	elif kind == "smoke" and (_resting or _t > 1.8) and _t > 0.5:
		_start_smoke()
	elif _t > 30.0:
		queue_free()


func _process(delta: float) -> void:
	_blink()
	var f := Engine.get_physics_interpolation_fraction()
	global_position = _prev.lerp(_pos, f)
	if not _resting:
		_model.rotation += _spin * delta


func _explode() -> void:
	_done = true
	FX.explosion(_pos)
	var arena := get_tree().current_scene as Arena
	if arena:
		arena.on_explosion(_pos)
		if authoritative and is_instance_valid(thrower):
			arena.server_explosion_damage(thrower, _pos)
	queue_free()


func _start_smoke() -> void:
	_done = true
	SmokeCloud.spawn(_pos)
	_model.visible = true
	get_tree().create_timer(2.0).timeout.connect(queue_free)


func _exit_tree() -> void:
	var arena := get_tree().current_scene as Arena if get_tree() else null
	if arena:
		arena.grenades.erase(self)


## Point where a throw from `origin` with `vel` comes to rest-ish (for previews / bots).
static func predict(space: PhysicsDirectSpaceState3D, origin: Vector3, vel: Vector3, steps := 90, dt := 1.0 / 30.0) -> PackedVector3Array:
	var pts := PackedVector3Array([origin])
	var p := origin
	var v := vel
	for i in steps:
		v.y -= GRAVITY * dt
		var next := p + v * dt
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(p, next, 1))
		if hit:
			pts.append(hit.position)
			break
		p = next
		pts.append(p)
	return pts
