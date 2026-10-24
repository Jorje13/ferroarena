class_name SmokeCloud
extends Node3D
## Dense smoke screen: billowing soft particles + a FogVolume so it also
## occludes inside the volumetric fog. Registered on the arena so bots can't
## see through it.

var _particles: GPUParticles3D
var _fog: FogVolume
var _fog_mat: FogMaterial
var _t := 0.0
var _hiss: AudioStreamPlayer3D


static func spawn(pos: Vector3) -> SmokeCloud:
	var scene := (Engine.get_main_loop() as SceneTree).current_scene
	var s := SmokeCloud.new()
	scene.add_child(s)
	s.global_position = pos
	if scene is Arena:
		(scene as Arena).smokes.append(s)
	Audio.play_smoke_pop(pos)
	return s


func _ready() -> void:
	_particles = GPUParticles3D.new()
	_particles.amount = 90
	_particles.lifetime = 7.0
	_particles.preprocess = 0.0
	_particles.local_coords = false
	_particles.visibility_aabb = AABB(Vector3(-10, -2, -10), Vector3(20, 12, 20))
	_particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 1.5
	pm.direction = Vector3.UP
	pm.spread = 80.0
	pm.initial_velocity_min = 1.0
	pm.initial_velocity_max = 3.2
	pm.gravity = Vector3(0, 0.25, 0)
	pm.damping_min = 0.6
	pm.damping_max = 1.0
	pm.scale_min = 2.6
	pm.scale_max = 4.2
	var sc := Curve.new()
	sc.add_point(Vector2(0, 0.4))
	sc.add_point(Vector2(0.3, 1.0))
	sc.add_point(Vector2(1, 1.25))
	var sct := CurveTexture.new()
	sct.curve = sc
	pm.scale_curve = sct
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.15, 0.75, 1.0])
	grad.colors = PackedColorArray([Color(0.9, 0.9, 0.9, 0.0), Color(0.86, 0.86, 0.86, 0.92), Color(0.8, 0.8, 0.8, 0.85), Color(0.78, 0.78, 0.78, 0.0)])
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	pm.angle_min = -180.0
	pm.angle_max = 180.0
	pm.angular_velocity_min = -12.0
	pm.angular_velocity_max = 12.0
	_particles.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.billboard_keep_scale = true
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = _puff_texture()
	mat.proximity_fade_enabled = true
	mat.proximity_fade_distance = 1.0
	mat.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
	q.material = mat
	_particles.draw_pass_1 = q
	add_child(_particles)

	# Gas escaping the canister: a looping 3D hiss that swells with the cloud and dies with it.
	if Audio.streams.has("smoke_hiss"):
		_hiss = AudioStreamPlayer3D.new()
		_hiss.stream = Audio.streams["smoke_hiss"]
		_hiss.bus = "SFX"
		_hiss.max_distance = 60.0
		_hiss.unit_size = 8.0
		_hiss.volume_db = -30.0
		_hiss.position = Vector3(0, 0.6, 0)
		_hiss.finished.connect(func(): if is_instance_valid(_hiss) and _t < Items.SMOKE_DURATION - 1.0: _hiss.play())
		add_child(_hiss)
		_hiss.play()

	_fog = FogVolume.new()
	_fog.size = Vector3(Items.SMOKE_RADIUS * 2.4, Items.SMOKE_RADIUS * 1.4, Items.SMOKE_RADIUS * 2.4)
	_fog.shape = RenderingServer.FOG_VOLUME_SHAPE_ELLIPSOID
	_fog.position = Vector3(0, 1.6, 0)
	_fog_mat = FogMaterial.new()
	_fog_mat.density = 0.0
	_fog_mat.albedo = Color(0.86, 0.86, 0.86)
	_fog.material = _fog_mat
	add_child(_fog)


func _process(delta: float) -> void:
	_t += delta
	var grow := clampf(_t / 2.0, 0.0, 1.0)
	var fade := 1.0 - clampf((_t - (Items.SMOKE_DURATION - 3.0)) / 3.0, 0.0, 1.0)
	_fog_mat.density = 1.6 * grow * fade
	if _hiss:
		_hiss.volume_db = lerpf(-30.0, 2.0, grow) - (1.0 - fade) * 24.0 - clampf((_t - 5.0) / 6.0, 0.0, 1.0) * 6.0
	(_particles.process_material as ParticleProcessMaterial).emission_sphere_radius = lerpf(0.5, Items.SMOKE_RADIUS * 0.7, grow)
	if _t > Items.SMOKE_DURATION - 6.0:
		_particles.emitting = false
	if _t > Items.SMOKE_DURATION + 1.0:
		queue_free()


## True while the cloud is thick enough to block sight.
func blocks() -> bool:
	return _t > 0.8 and _t < Items.SMOKE_DURATION - 1.5


func radius() -> float:
	return Items.SMOKE_RADIUS * clampf(_t / 2.0, 0.3, 1.0)


func _exit_tree() -> void:
	var scene := get_tree().current_scene if get_tree() else null
	if scene is Arena:
		(scene as Arena).smokes.erase(self)


static var _tex: Texture2D


static func _puff_texture() -> Texture2D:
	if _tex == null:
		# Soft lumpy puff: radial falloff modulated by noise.
		var n := FastNoiseLite.new()
		n.frequency = 0.08
		var img := Image.create(128, 128, false, Image.FORMAT_RGBA8)
		for y in 128:
			for x in 128:
				var d := Vector2(x - 64, y - 64).length() / 64.0
				var v := clampf(1.0 - d, 0.0, 1.0)
				v = v * v * (0.65 + 0.35 * (n.get_noise_2d(x, y) * 0.5 + 0.5))
				img.set_pixel(x, y, Color(1, 1, 1, v))
		img.generate_mipmaps()
		_tex = ImageTexture.create_from_image(img)
	return _tex
