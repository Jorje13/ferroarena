class_name FX
## One-shot visual effects. All nodes free themselves.

static var _tracer_mesh: CylinderMesh
static var _flash_mesh: SphereMesh
static var _decal_tex: Texture2D


static func _scene() -> Node:
	return (Engine.get_main_loop() as SceneTree).current_scene


static func _free_after(node: Node, t: float) -> void:
	node.get_tree().create_timer(t).timeout.connect(node.queue_free)


## `subdued`: silenced shot, a faint glow instead of the full fireball.
static func muzzle_flash(muzzle: Node3D, subdued := false) -> void:
	var scene := _scene()
	if scene == null:
		return
	if _flash_mesh == null:
		_flash_mesh = SphereMesh.new()
		_flash_mesh.radius = 0.12
		_flash_mesh.height = 0.24
	var root := Node3D.new()
	scene.add_child(root)
	root.global_transform = muzzle.global_transform
	if subdued:
		root.scale = Vector3.ONE * 0.35
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.72, 0.38)
	light.light_energy = 2.5 if subdued else 11.0
	light.omni_range = 4.0 if subdued else 12.0
	light.position = Vector3(0, 0, -0.2)
	root.add_child(light)
	var m := MeshInstance3D.new()
	m.mesh = _flash_mesh
	m.material_override = Mats.emissive("flash", Color(1.0, 0.7, 0.3), 14.0)
	m.scale = Vector3(0.8, 0.8, 2.2)
	m.position = Vector3(0, 0, -0.1)
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(m)
	# Crossed flame planes along the barrel + a front "star" facing out.
	var mat := _flash_card_material()
	var rot := randf() * PI
	for i in 3:
		var q := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(0.34, 0.95) * randf_range(0.85, 1.2)
		q.mesh = qm
		q.material_override = mat
		q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		q.transform = Transform3D(Basis(Vector3.FORWARD, rot + i * PI / 3.0) * Basis(Vector3.RIGHT, PI / 2), Vector3(0, 0, -0.26))
		root.add_child(q)
	var star := MeshInstance3D.new()
	var sm := QuadMesh.new()
	sm.size = Vector2.ONE * 0.6
	star.mesh = sm
	star.material_override = mat
	star.position = Vector3(0, 0, -0.05)
	star.rotation.z = rot
	root.add_child(star)
	_free_after(root, 0.06)


## Big-bore muzzle blast: forward smoke cone, side jets, and dust kicked up
## from the ground under the muzzle.
static func muzzle_blast(pos: Vector3, dir: Vector3, subdued := false) -> void:
	var scene := _scene()
	if scene == null:
		return
	if subdued:
		smoke_puff(pos + dir * 0.2, dir, 5, 0.5, Color(0.8, 0.8, 0.8, 0.22))
		return
	smoke_puff(pos + dir * 0.3, dir, 16, 1.5)
	var side := dir.cross(Vector3.UP).normalized()
	if side.length() > 0.1:
		smoke_puff(pos, (side + dir * 0.3).normalized(), 5, 0.8)
		smoke_puff(pos, (-side + dir * 0.3).normalized(), 5, 0.8)
	var space := (scene as Node3D).get_world_3d().direct_space_state if scene is Node3D else null
	if space:
		var ahead := pos + dir * 1.2
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(ahead, ahead + Vector3.DOWN * 1.9, 1))
		if hit:
			smoke_puff(hit.position + Vector3.UP * 0.05, Vector3.UP, 12, 1.3, Color(0.62, 0.55, 0.42, 0.45))


static var _flash_mat: StandardMaterial3D


static func _flash_card_material() -> StandardMaterial3D:
	if _flash_mat == null:
		var grad := Gradient.new()
		grad.offsets = PackedFloat32Array([0.0, 0.25, 1.0])
		grad.colors = PackedColorArray([Color(1, 0.95, 0.8, 1), Color(1, 0.6, 0.2, 0.7), Color(1, 0.3, 0.05, 0)])
		var tex := GradientTexture2D.new()
		tex.gradient = grad
		tex.fill = GradientTexture2D.FILL_RADIAL
		tex.fill_from = Vector2(0.5, 0.5)
		tex.fill_to = Vector2(0.5, 0.0)
		_flash_mat = StandardMaterial3D.new()
		_flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_flash_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_flash_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_flash_mat.albedo_texture = tex
		_flash_mat.albedo_color = Color(1, 1, 1, 1)
	return _flash_mat


## Frag grenade detonation: flash, fireball, debris, smoke column, scorch.
static func explosion(pos: Vector3) -> void:
	var scene := _scene()
	if scene == null:
		return
	Audio.play_explosion(pos)
	_blast_extras(pos)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.6, 0.25)
	light.light_energy = 18.0
	light.omni_range = 18.0
	light.shadow_enabled = true
	scene.add_child(light)
	light.global_position = pos + Vector3(0, 0.8, 0)
	var tw := light.create_tween()
	tw.tween_property(light, "light_energy", 0.0, 0.35)
	tw.tween_callback(light.queue_free)
	# Fireball
	var fire := CPUParticles3D.new()
	fire.one_shot = true
	fire.amount = 34
	fire.lifetime = 0.6
	fire.explosiveness = 1.0
	fire.direction = Vector3.UP
	fire.spread = 95.0
	fire.initial_velocity_min = 4.0
	fire.initial_velocity_max = 13.0
	fire.damping_min = 7.0
	fire.damping_max = 10.0
	fire.scale_amount_min = 1.3
	fire.scale_amount_max = 3.0
	var fg := Gradient.new()
	fg.offsets = PackedFloat32Array([0.0, 0.3, 1.0])
	fg.colors = PackedColorArray([Color(1, 0.9, 0.6, 1), Color(1, 0.45, 0.1, 0.9), Color(0.2, 0.1, 0.05, 0)])
	fire.color_ramp = fg
	var fq := QuadMesh.new()
	fq.size = Vector2.ONE
	var fm := _soft_material().duplicate() as StandardMaterial3D
	fm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	fq.material = fm
	fire.mesh = fq
	scene.add_child(fire)
	fire.global_position = pos + Vector3(0, 0.4, 0)
	fire.emitting = true
	_free_after(fire, 1.0)
	# Smoke column + dust ring + debris
	var sm := CPUParticles3D.new()
	sm.one_shot = true
	sm.amount = 24
	sm.lifetime = 3.6
	sm.explosiveness = 0.9
	sm.direction = Vector3.UP
	sm.spread = 60.0
	sm.initial_velocity_min = 1.5
	sm.initial_velocity_max = 5.0
	sm.damping_min = 1.5
	sm.damping_max = 2.5
	sm.gravity = Vector3(0, 0.4, 0)
	sm.scale_amount_min = 2.2
	sm.scale_amount_max = 4.5
	var sc := Curve.new()
	sc.add_point(Vector2(0, 0.4))
	sc.add_point(Vector2(1, 1.3))
	sm.scale_amount_curve = sc
	var sg := Gradient.new()
	sg.offsets = PackedFloat32Array([0.0, 0.1, 0.7, 1.0])
	sg.colors = PackedColorArray([Color(0.25, 0.22, 0.2, 0.0), Color(0.3, 0.27, 0.24, 0.85), Color(0.45, 0.42, 0.38, 0.5), Color(0.5, 0.47, 0.42, 0.0)])
	sm.color_ramp = sg
	var sq := QuadMesh.new()
	sq.size = Vector2.ONE
	sq.material = _soft_material()
	sm.mesh = sq
	scene.add_child(sm)
	sm.global_position = pos + Vector3(0, 0.6, 0)
	sm.emitting = true
	_free_after(sm, 4.0)
	smoke_puff(pos + Vector3(0, 0.15, 0), Vector3.UP, 16, 3.0, Color(0.6, 0.55, 0.48, 0.6))
	var deb := CPUParticles3D.new()
	deb.one_shot = true
	deb.amount = 30
	deb.lifetime = 1.4
	deb.explosiveness = 1.0
	deb.direction = Vector3.UP
	deb.spread = 70.0
	deb.initial_velocity_min = 5.0
	deb.initial_velocity_max = 13.0
	deb.gravity = Vector3(0, -14, 0)
	deb.scale_amount_min = 0.03
	deb.scale_amount_max = 0.09
	var b := BoxMesh.new()
	b.size = Vector3.ONE
	b.material = Mats.flat("chips", Color(0.25, 0.23, 0.2))
	deb.mesh = b
	scene.add_child(deb)
	deb.global_position = pos + Vector3(0, 0.2, 0)
	deb.emitting = true
	_free_after(deb, 1.6)
	var dec := Decal.new()
	dec.size = Vector3(4.0, 2.0, 4.0)
	dec.texture_albedo = _hole_texture()
	dec.modulate = Color(0.06, 0.05, 0.04, 0.85)
	dec.cull_mask = 1
	scene.add_child(dec)
	dec.global_position = pos
	_free_after(dec, 30.0)


## Extra blast detail: an expanding shockwave shell, streaking sparks that arc
## down, and glowing embers that drift up and fade.
static func _blast_extras(pos: Vector3) -> void:
	var scene := _scene()
	# Shockwave: a translucent shell racing outwards.
	var shell := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 24
	sm.rings = 12
	shell.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_FRONT
	mat.albedo_color = Color(1.0, 0.7, 0.4, 0.5)
	shell.material_override = mat
	shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	scene.add_child(shell)
	shell.global_position = pos + Vector3(0, 0.5, 0)
	shell.scale = Vector3.ONE * 0.4
	var tw := shell.create_tween().set_parallel(true)
	tw.tween_property(shell, "scale", Vector3.ONE * 9.0, 0.32).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.32)
	tw.chain().tween_callback(shell.queue_free)
	# Sparks: thin fast streaks.
	var sp := CPUParticles3D.new()
	sp.one_shot = true
	sp.amount = 46
	sp.lifetime = 0.9
	sp.explosiveness = 1.0
	sp.direction = Vector3.UP
	sp.spread = 80.0
	sp.initial_velocity_min = 9.0
	sp.initial_velocity_max = 24.0
	sp.gravity = Vector3(0, -16, 0)
	sp.scale_amount_min = 0.5
	sp.scale_amount_max = 1.0
	var spark := BoxMesh.new()
	spark.size = Vector3(0.025, 0.3, 0.025)
	var smat := StandardMaterial3D.new()
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.albedo_color = Color(5.0, 2.2, 0.7)
	spark.material = smat
	sp.mesh = spark
	sp.particle_flag_align_y = true
	scene.add_child(sp)
	sp.global_position = pos + Vector3(0, 0.3, 0)
	sp.emitting = true
	_free_after(sp, 1.2)
	# Embers: slow glowing specks floating up.
	var em := CPUParticles3D.new()
	em.one_shot = true
	em.amount = 26
	em.lifetime = 2.4
	em.explosiveness = 0.8
	em.direction = Vector3.UP
	em.spread = 60.0
	em.initial_velocity_min = 1.5
	em.initial_velocity_max = 5.0
	em.gravity = Vector3(0, 0.8, 0)
	em.damping_min = 0.8
	em.damping_max = 1.6
	em.scale_amount_min = 0.03
	em.scale_amount_max = 0.07
	var eg := Gradient.new()
	eg.colors = PackedColorArray([Color(4.0, 1.6, 0.4, 1), Color(1.5, 0.3, 0.05, 0)])
	em.color_ramp = eg
	var eq := QuadMesh.new()
	eq.size = Vector2.ONE
	var emat := _soft_material().duplicate() as StandardMaterial3D
	emat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	eq.material = emat
	em.mesh = eq
	scene.add_child(em)
	em.global_position = pos + Vector3(0, 0.4, 0)
	em.emitting = true
	_free_after(em, 2.8)


## Brass casing thrown out of the breech when the Ferro is broken open.
static func shell_eject(gun_xf: Transform3D) -> void:
	var scene := _scene()
	if scene == null:
		return
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = 1
	p.lifetime = 0.9
	p.explosiveness = 1.0
	p.local_coords = false
	p.direction = gun_xf.basis * Vector3(0.3, 1.0, 0.8)
	p.spread = 12.0
	p.initial_velocity_min = 1.6
	p.initial_velocity_max = 2.2
	p.gravity = Vector3(0, -9.8, 0)
	p.angular_velocity_min = 400.0
	p.angular_velocity_max = 900.0
	p.particle_flag_rotate_y = true
	var c := CylinderMesh.new()
	c.top_radius = 0.011
	c.bottom_radius = 0.012
	c.height = 0.07
	c.radial_segments = 8
	c.material = Mats.flat("brass", Color(0.78, 0.58, 0.25), 0.3, 1.0)
	p.mesh = c
	scene.add_child(p)
	p.global_position = gun_xf * Vector3(0, 0.03, -0.1)
	p.emitting = true
	_free_after(p, 1.2)


static func tracer(from: Vector3, to: Vector3) -> void:
	var scene := _scene()
	if scene == null:
		return
	var d := to - from
	var length := d.length()
	if length < 0.5:
		return
	if _tracer_mesh == null:
		_tracer_mesh = CylinderMesh.new()
		_tracer_mesh.top_radius = 0.012
		_tracer_mesh.bottom_radius = 0.012
		_tracer_mesh.height = 1.0
		_tracer_mesh.radial_segments = 4
		_tracer_mesh.rings = 1
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(1.0, 0.85, 0.55, 0.9)
	var m := MeshInstance3D.new()
	m.mesh = _tracer_mesh
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	scene.add_child(m)
	var y := d / length
	var ref := Vector3.UP if absf(y.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	var x := y.cross(ref).normalized()
	var z := x.cross(y)
	m.global_transform = Transform3D(Basis(x, y * length, z), from + d * 0.5)
	var tw := m.create_tween()
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.14)
	tw.tween_callback(m.queue_free)


static func smoke_puff(pos: Vector3, dir: Vector3, amount: int, size: float, color := Color(0.85, 0.82, 0.78, 0.35)) -> void:
	var scene := _scene()
	if scene == null:
		return
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = amount
	p.lifetime = 1.4
	p.explosiveness = 0.95
	p.direction = dir
	p.spread = 25.0
	p.initial_velocity_min = 0.6
	p.initial_velocity_max = 2.0
	p.gravity = Vector3(0, 0.3, 0)
	p.damping_min = 2.0
	p.damping_max = 3.0
	p.scale_amount_min = size * 0.6
	p.scale_amount_max = size
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.3))
	curve.add_point(Vector2(1, 1.0))
	p.scale_amount_curve = curve
	var grad := Gradient.new()
	grad.set_color(0, color)
	grad.set_color(1, Color(color.r, color.g, color.b, 0.0))
	p.color_ramp = grad
	var q := QuadMesh.new()
	q.size = Vector2.ONE * 0.5
	q.material = _soft_material()
	p.mesh = q
	scene.add_child(p)
	p.global_position = pos
	p.emitting = true
	_free_after(p, 1.6)


static var _soft_mat: StandardMaterial3D


static func _soft_material() -> StandardMaterial3D:
	if _soft_mat == null:
		var grad := Gradient.new()
		grad.set_color(0, Color(1, 1, 1, 1))
		grad.set_color(1, Color(1, 1, 1, 0))
		var tex := GradientTexture2D.new()
		tex.gradient = grad
		tex.fill = GradientTexture2D.FILL_RADIAL
		tex.fill_from = Vector2(0.5, 0.5)
		tex.fill_to = Vector2(0.5, 0.0)
		_soft_mat = StandardMaterial3D.new()
		_soft_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_soft_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_soft_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		_soft_mat.billboard_keep_scale = true
		_soft_mat.vertex_color_use_as_albedo = true
		_soft_mat.proximity_fade_enabled = true
		_soft_mat.proximity_fade_distance = 0.6
		_soft_mat.albedo_texture = tex
	return _soft_mat


static func impact(pos: Vector3, normal: Vector3) -> void:
	var scene := _scene()
	if scene == null:
		return
	smoke_puff(pos, normal, 10, 1.1, Color(0.7, 0.64, 0.55, 0.55))
	# Sparks / chips
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = 14
	p.lifetime = 0.6
	p.explosiveness = 1.0
	p.direction = normal
	p.spread = 45.0
	p.initial_velocity_min = 3.0
	p.initial_velocity_max = 8.0
	p.gravity = Vector3(0, -12, 0)
	p.scale_amount_min = 0.02
	p.scale_amount_max = 0.05
	var b := BoxMesh.new()
	b.size = Vector3.ONE
	b.material = Mats.flat("chips", Color(0.35, 0.32, 0.28))
	p.mesh = b
	scene.add_child(p)
	p.global_position = pos
	p.emitting = true
	_free_after(p, 0.8)
	# Bullet hole decal
	var dec := Decal.new()
	dec.size = Vector3(0.18, 0.3, 0.18)
	dec.texture_albedo = _hole_texture()
	dec.modulate = Color(0.15, 0.13, 0.12)
	dec.cull_mask = 1
	scene.add_child(dec)
	dec.global_position = pos
	var up := normal if normal.length() > 0.1 else Vector3.UP
	var ref := Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
	var x := up.cross(ref).normalized()
	dec.global_basis = Basis(x, up, x.cross(up))
	_free_after(dec, 25.0)


static func flesh_hit(pos: Vector3, normal: Vector3) -> void:
	var scene := _scene()
	if scene == null:
		return
	smoke_puff(pos, normal, 8, 0.5, Color(0.55, 0.08, 0.06, 0.8))
	# Droplets thrown out along the exit side, falling back down.
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = 12
	p.lifetime = 0.55
	p.explosiveness = 1.0
	p.direction = normal
	p.spread = 38.0
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 6.5
	p.gravity = Vector3(0, -13, 0)
	p.scale_amount_min = 0.018
	p.scale_amount_max = 0.045
	var s := SphereMesh.new()
	s.radius = 0.5
	s.height = 1.0
	s.radial_segments = 6
	s.rings = 3
	s.material = Mats.flat("blood_drop", Color(0.42, 0.03, 0.02), 0.25, 0.0)
	p.mesh = s
	scene.add_child(p)
	p.global_position = pos
	p.emitting = true
	_free_after(p, 0.8)


## Bullet absorbed by an energy shield: cyan spark burst + short flash.
static func shield_hit(pos: Vector3, normal: Vector3) -> void:
	var scene := _scene()
	if scene == null:
		return
	Audio.play_3d("shield_hit", pos, 0.0, 60.0, 0.08)
	var light := OmniLight3D.new()
	light.light_color = Color(0.3, 0.75, 1.0)
	light.light_energy = 4.0
	light.omni_range = 3.0
	scene.add_child(light)
	light.global_position = pos + normal * 0.2
	_free_after(light, 0.08)
	var sp := CPUParticles3D.new()
	sp.one_shot = true
	sp.amount = 18
	sp.lifetime = 0.35
	sp.explosiveness = 1.0
	sp.direction = normal
	sp.spread = 70.0
	sp.initial_velocity_min = 2.5
	sp.initial_velocity_max = 6.0
	sp.gravity = Vector3(0, -4, 0)
	sp.scale_amount_min = 0.04
	sp.scale_amount_max = 0.09
	var g := Gradient.new()
	g.colors = PackedColorArray([Color(2.0, 3.5, 4.0, 1), Color(0.2, 0.6, 1.0, 0)])
	sp.color_ramp = g
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	var m := _soft_material().duplicate() as StandardMaterial3D
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	q.material = m
	sp.mesh = q
	scene.add_child(sp)
	sp.global_position = pos
	sp.emitting = true
	_free_after(sp, 0.8)


static func _hole_texture() -> Texture2D:
	if _decal_tex == null:
		var grad := Gradient.new()
		grad.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
		grad.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.6), Color(1, 1, 1, 0)])
		var tex := GradientTexture2D.new()
		tex.gradient = grad
		tex.fill = GradientTexture2D.FILL_RADIAL
		tex.fill_from = Vector2(0.5, 0.5)
		tex.fill_to = Vector2(0.5, 0.0)
		tex.width = 64
		tex.height = 64
		_decal_tex = tex
	return _decal_tex
