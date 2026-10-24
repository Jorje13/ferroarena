class_name MapBase
extends Node3D
## Procedural arena: terrain, lighting/atmosphere and prop builders.
## Subclasses override `build_layout`, `env_params` and optionally `layout_height`.
## Everything is seeded so every peer builds the exact same geometry.

const TERRAIN_STEP := 2.0
const FLOOR_H := 4.0
const WALL_T := 0.3

var map_seed := 1
var biome := "dry"
var half := Vector2(58.0, 68.0) ## playable half extents (x, z)
## Hand-placed layouts are authored for a 58 x 68 m half-extent; `layout_k`
## spreads their positions out (props keep their size) for a bigger arena.
var layout_k := 1.0
var _extra_loot: Array = []
var terrain_extent := 200.0
var hill_amp := 16.0
var hill_var := 14.0
var quality := 2
var no_grass: Array[Rect2] = []
var environment_node: WorldEnvironment
var sun: DirectionalLight3D
var props_root: Node3D
var rng := RandomNumberGenerator.new()

var _n_ground := FastNoiseLite.new()
var _n_hills := FastNoiseLite.new()
var _box_meshes := {}


func build(q: int) -> void:
	Scan.catalog.clear()
	quality = q
	rng.seed = map_seed
	_n_ground.seed = map_seed
	_n_ground.frequency = 0.018
	_n_ground.fractal_octaves = 3
	_n_hills.seed = map_seed + 7
	_n_hills.frequency = 0.011
	_n_hills.fractal_octaves = 4
	props_root = Node3D.new()
	props_root.name = "Props"
	add_child(props_root)
	_build_environment()
	plan_layout()
	_build_terrain()
	build_planned_buildings()
	build_layout()
	_flush_batches()
	_build_bounds()
	_build_grass()


# ---------------------------------------------------------------- batching

## Mesh -> Array[Transform3D] (props_root space), drawn as one MultiMesh each.
var _batches := {}


## Queues one instance of `mesh` (visual only, no collision).
func batch(mesh: Mesh, xf: Transform3D) -> void:
	if not _batches.has(mesh):
		_batches[mesh] = []
	_batches[mesh].append(xf)


func _flush_batches() -> void:
	for mesh: Mesh in _batches:
		var xfs: Array = _batches[mesh]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = xfs.size()
		for i in xfs.size():
			mm.set_instance_transform(i, xfs[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		props_root.add_child(mmi)
	_batches.clear()


# ---------------------------------------------------------------- virtuals

## Called before the terrain exists: register buildings (plan_building) so the ground is levelled under them.
func plan_layout() -> void:
	pass


func build_layout() -> void:
	pass


func layout_height(_x: float, _z: float) -> float:
	return 0.0


func env_params() -> Dictionary:
	return {}


## Predefined supply-crate spots as Vector3(x, level, z): level 0 = ground,
## 1 = upper floor of a ruin. Listed as point-symmetric pairs (i, i+1) so the
## server can activate whole pairs and keep things fair.
func loot_spots() -> Array:
	return []


## Hand-placed spots (authored coordinates, spread by `layout_k`) + the ones
## `fill_cover` added next to its props.
func all_loot_spots() -> Array:
	return loot_spots() + _extra_loot


func mirrored_spots(spots: Array) -> Array:
	var out := []
	for s in spots:
		var k := Vector3(layout_k, 1.0, layout_k)
		out.append(s * k)
		out.append(Vector3(-s.x, s.y, -s.z) * k)
	return out


## Ambient particles (dust, snow) that the camera rig carries around.
func make_weather() -> Node3D:
	return null


func weather_particles(amount: int, box: Vector3, vel: Vector3, color: Color, size: float, lifetime: float, turbulence := 0.5) -> GPUParticles3D:
	var gp := GPUParticles3D.new()
	gp.amount = amount
	gp.lifetime = lifetime
	gp.preprocess = lifetime
	gp.local_coords = false
	gp.visibility_aabb = AABB(-box * 2.0, box * 4.0)
	gp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = box
	pm.direction = vel.normalized() if vel.length() > 0.01 else Vector3.DOWN
	pm.spread = 30.0
	pm.initial_velocity_min = vel.length() * 0.6
	pm.initial_velocity_max = vel.length() * 1.3
	pm.gravity = Vector3.ZERO
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = turbulence
	pm.turbulence_noise_scale = 4.0
	pm.scale_min = 0.5
	pm.scale_max = 1.3
	gp.process_material = pm
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 1))
	grad.set_color(1, Color(1, 1, 1, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	tex.width = 32
	tex.height = 32
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.albedo_color = color
	m.albedo_texture = tex
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	q.material = m
	gp.draw_pass_1 = q
	return gp


# ---------------------------------------------------------------- queries

func height_at(x: float, z: float) -> float:
	var h := _natural_height(x, z)
	for pad in _pads:
		var dx := maxf(absf(x - pad.c.x) - pad.h.x, 0.0)
		var dz := maxf(absf(z - pad.c.y) - pad.h.y, 0.0)
		var dd := sqrt(dx * dx + dz * dz)
		if dd < PAD_BLEND:
			h = lerpf(float(pad.y), h, smoothstep(0.0, PAD_BLEND, dd))
	return h


func _natural_height(x: float, z: float) -> float:
	var ex := maxf(absf(x) - half.x, 0.0)
	var ez := maxf(absf(z) - half.y, 0.0)
	var e := sqrt(ex * ex + ez * ez)
	var h := _n_ground.get_noise_2d(x, z) * 1.1
	var hills := smoothstep(0.0, 45.0, e) * (hill_amp + _n_hills.get_noise_2d(x, z) * hill_var) + e * 0.12
	return h + hills + layout_height(x, z) * (1.0 - smoothstep(0.0, 8.0, e))


func ground(p: Vector2) -> Vector3:
	return Vector3(p.x, height_at(p.x, p.y), p.y)


## What a point stands on for footsteps / bullet impacts: "stone" inside a building's
## footprint (floors, upper floors), else the biome's ground ("snow" or "dirt").
func surface_at(pos: Vector3) -> String:
	for pad in _pads:
		if absf(pos.x - pad.c.x) < pad.h.x - 0.9 and absf(pos.z - pad.c.y) < pad.h.y - 0.9 and pos.y > float(pad.y) - 0.6:
			return "stone"
	return "snow" if biome == "snow" else "dirt"


## Surface of a collider hit at `pos`: its "surface" meta when tagged (containers and
## wrecks are "metal", barriers "stone"), else by position.
func surface_of(col: Object, pos: Vector3) -> String:
	if col is Node and (col as Node).has_meta("surface"):
		return str((col as Node).get_meta("surface"))
	return surface_at(pos)


## Tags the static bodies under `node` with a surface (see surface_of).
func _tag_surface(node: Node, surface: String) -> void:
	for c in node.find_children("*", "StaticBody3D", true, false):
		c.set_meta("surface", surface)

## Teams line up along their edge, in rows of up to 5 (10v10 gets two rows).
func get_spawn(team: int, slot: int, count: int) -> Dictionary:
	var per_row := mini(count, 5)
	var row := slot / per_row
	var in_row := mini(per_row, count - row * per_row)
	var z := (half.y - 4.0) if team == 1 else -(half.y - 4.0)
	z += (-1.0 if team == 1 else 1.0) * row * 3.2
	var x := (slot % per_row - (in_row - 1) * 0.5) * 3.5
	return {"pos": ground(Vector2(x, z)) + Vector3(0, 0.15, 0), "yaw": PI if team == 0 else 0.0}


## Free-for-all start: raiders spread round the map (outer ring, plus an inner one when
## there are many), each on clear ground and looking at the centre.
func get_spawn_ffa(slot: int, count: int, jitter_seed := 1) -> Dictionary:
	var r := RandomNumberGenerator.new()
	r.seed = jitter_seed * 7919 + slot
	var inner := count > 10 and slot % 2 == 1
	var ring_n := count if count <= 10 else (count + 1) / 2
	var k := slot if count <= 10 else slot / 2
	var rx := (half.x - 9.0) * (0.45 if inner else 0.88)
	var rz := (half.y - 10.0) * (0.45 if inner else 0.88)
	var a0 := (jitter_seed % 360) * PI / 180.0
	var best := Vector2.ZERO
	for tries in 12:
		var ang := a0 + (float(k) + (0.5 if inner else 0.0)) / ring_n * TAU + r.randf_range(-0.12, 0.12) * (1 if tries > 0 else 0) * tries * 0.3
		var p := Vector2(cos(ang) * rx, sin(ang) * rz)
		best = p
		if is_free(p, 3.5):
			break
	var to_c := -best
	return {"pos": ground(best) + Vector3(0, 0.15, 0), "yaw": atan2(-to_c.x, -to_c.y)}


func get_bounds() -> AABB:
	return AABB(Vector3(-half.x, -20.0, -half.y), Vector3(half.x * 2.0, 60.0, half.y * 2.0))


# ---------------------------------------------------------------- environment

func _build_environment() -> void:
	var p := {
		"top": Color(0.3, 0.5, 0.78), "horizon": Color(0.78, 0.8, 0.8), "ground": Color(0.35, 0.33, 0.3),
		"cloud": Color(1, 0.98, 0.95), "cloud_shadow": Color(0.62, 0.66, 0.72), "cover": 0.45,
		"sky_energy": 1.0, "sun_color": Color(1.0, 0.93, 0.82), "sun_energy": 1.7, "sun_elev": 38.0,
		"sun_azim": -35.0, "fog_color": Color(0.74, 0.78, 0.82), "fog_density": 0.0035,
		"vol_density": 0.012, "exposure": 1.0, "saturation": 1.05, "contrast": 1.06, "ambient": 1.0,
	}
	p.merge(env_params(), true)

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/sky.gdshader")
	sm.set_shader_parameter("top_col", p.top)
	sm.set_shader_parameter("horizon_col", p.horizon)
	sm.set_shader_parameter("ground_col", p.ground)
	sm.set_shader_parameter("cloud_col", p.cloud)
	sm.set_shader_parameter("cloud_shadow", p.cloud_shadow)
	sm.set_shader_parameter("cloud_cover", p.cover)
	sm.set_shader_parameter("energy", p.sky_energy)
	sm.set_shader_parameter("cloud_noise", Mats.noise_tex(map_seed + 99, 0.006, false, 1024))
	sky.sky_material = sm
	if p.has("hdri"):
		var pano := PanoramaSkyMaterial.new()
		pano.panorama = load(p.hdri)
		pano.energy_multiplier = p.get("hdri_energy", 1.0)
		pano.filter = true
		sky.sky_material = pano
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = p.ambient
	# Blend the (blue) sky ambient with a warm bounce tint so shade isn't cyan.
	env.ambient_light_sky_contribution = 0.65
	env.ambient_light_color = p.get("bounce", Color(0.62, 0.55, 0.46))
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY

	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = p.exposure

	env.ssao_enabled = quality >= 1
	env.ssao_radius = 1.4
	env.ssao_intensity = 1.8
	env.ssao_detail = 0.6
	env.ssil_enabled = quality >= 2
	env.sdfgi_enabled = quality >= 2
	env.sdfgi_use_occlusion = true
	env.sdfgi_cascades = 6 if quality >= 3 else 4
	env.sdfgi_min_cell_size = 0.2
	env.sdfgi_bounce_feedback = 0.6
	env.sdfgi_energy = 1.4
	env.ssil_intensity = 1.3

	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.1

	env.fog_enabled = true
	env.fog_light_color = p.fog_color
	env.fog_density = p.fog_density
	env.fog_aerial_perspective = 0.55
	env.fog_sky_affect = 0.2
	env.fog_sun_scatter = 0.25

	env.volumetric_fog_enabled = quality >= 1
	env.volumetric_fog_density = p.vol_density
	env.volumetric_fog_albedo = p.fog_color
	env.volumetric_fog_anisotropy = 0.65
	env.volumetric_fog_length = 90.0
	env.volumetric_fog_ambient_inject = 0.35
	env.volumetric_fog_sky_affect = 0.0

	env.adjustment_enabled = true
	env.adjustment_contrast = p.contrast
	env.adjustment_saturation = p.saturation

	environment_node = WorldEnvironment.new()
	environment_node.environment = env
	add_child(environment_node)

	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-p.sun_elev, p.sun_azim, 0.0)
	if p.has("sun_dir"):
		# Match the sun baked into the HDRI (direction towards the sun).
		sun.basis = Basis.looking_at(-(p.sun_dir as Vector3).normalized())
	sun.light_color = p.sun_color
	sun.light_energy = p.sun_energy
	sun.light_angular_distance = 0.6
	sun.shadow_enabled = true
	sun.shadow_blur = 1.2
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = [60.0, 100.0, 140.0, 200.0][clampi(quality, 0, 3)]
	sun.light_volumetric_fog_energy = 1.2
	add_child(sun)


# ---------------------------------------------------------------- terrain

func _terrain_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/terrain.gdshader")
	m.set_shader_parameter("noise_tex", Mats.noise_tex(map_seed + 11, 0.01, false, 1024))
	var layers := {"grass": "aerial_grass_rock", "dirt": "brown_mud_dry", "rock": "rocky_terrain_02", "snow": "snow_02"}
	layers.merge(terrain_layers(), true)
	for layer in layers:
		var base: String = Mats.PH_TEX + layers[layer] + "/" + layers[layer]
		m.set_shader_parameter(layer + "_alb", load(base + "_diff_2k.jpg"))
		m.set_shader_parameter(layer + "_nrm", load(base + "_nor_gl_2k.jpg"))
		if layer != "snow":
			m.set_shader_parameter(layer + "_rgh", load(base + "_rough_2k.jpg"))
	var tp := terrain_params()
	for k in tp:
		m.set_shader_parameter(k, tp[k])
	return m


## Overrides for terrain.gdshader uniforms (tints, scales, snow_amount...).
func terrain_params() -> Dictionary:
	return {}


## Overrides for the terrain texture sets: {"grass"|"dirt"|"rock"|"snow": poly haven id}.
func terrain_layers() -> Dictionary:
	return {}


func _build_terrain() -> void:
	var n := int(terrain_extent * 2.0 / TERRAIN_STEP)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var heights := PackedFloat32Array()
	heights.resize((n + 1) * (n + 1))
	for iz in n + 1:
		for ix in n + 1:
			var x := -terrain_extent + ix * TERRAIN_STEP
			var z := -terrain_extent + iz * TERRAIN_STEP
			var h := height_at(x, z)
			heights[iz * (n + 1) + ix] = h
			var nx := height_at(x - 0.5, z) - height_at(x + 0.5, z)
			var nz := height_at(x, z - 0.5) - height_at(x, z + 0.5)
			st.set_normal(Vector3(nx, 1.0, nz).normalized())
			st.set_uv(Vector2(x, z) * 0.1)
			st.add_vertex(Vector3(x, h, z))
	for iz in n:
		for ix in n:
			var i := iz * (n + 1) + ix
			st.add_index(i)
			st.add_index(i + 1)
			st.add_index(i + n + 1)
			st.add_index(i + 1)
			st.add_index(i + n + 2)
			st.add_index(i + n + 1)
	st.generate_tangents()
	var mesh := st.commit()

	var mi := MeshInstance3D.new()
	mi.name = "Terrain"
	mi.mesh = mesh
	mi.material_override = _terrain_material()
	add_child(mi)

	# Collision only around the playable area (keeps physics + navmesh bake light).
	var faces := PackedVector3Array()
	var lim_x := half.x + 12.0
	var lim_z := half.y + 12.0
	for iz in n:
		for ix in n:
			var x0 := -terrain_extent + ix * TERRAIN_STEP
			var z0 := -terrain_extent + iz * TERRAIN_STEP
			if absf(x0) > lim_x or absf(z0) > lim_z:
				continue
			var x1 := x0 + TERRAIN_STEP
			var z1 := z0 + TERRAIN_STEP
			var a := Vector3(x0, heights[iz * (n + 1) + ix], z0)
			var b := Vector3(x1, heights[iz * (n + 1) + ix + 1], z0)
			var c := Vector3(x0, heights[(iz + 1) * (n + 1) + ix], z1)
			var d := Vector3(x1, heights[(iz + 1) * (n + 1) + ix + 1], z1)
			faces.append_array([a, b, c, b, d, c])
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	var body := StaticBody3D.new()
	body.name = "TerrainBody"
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	add_child(body)


func _build_bounds() -> void:
	var walls := [
		[Vector3(-half.x - 1.0, 10, 0), Vector3(2, 60, half.y * 2 + 4)],
		[Vector3(half.x + 1.0, 10, 0), Vector3(2, 60, half.y * 2 + 4)],
		[Vector3(0, 10, -half.y - 1.0), Vector3(half.x * 2 + 4, 60, 2)],
		[Vector3(0, 10, half.y + 1.0), Vector3(half.x * 2 + 4, 60, 2)],
	]
	for w in walls:
		var body := StaticBody3D.new()
		body.name = "Bound"
		# Layer 3 only: blocks players, ignored by bullets/camera/navmesh.
		body.collision_layer = 4
		body.collision_mask = 0
		body.position = w[0]
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = w[1]
		cs.shape = sh
		body.add_child(cs)
		add_child(body)


# ---------------------------------------------------------------- grass

func grass_colors() -> Array:
	return [Color(0.17, 0.2, 0.08), Color(0.66, 0.6, 0.34)]


func _grass_mesh(blade_h: float, blades: int) -> ArrayMesh:
	var r := RandomNumberGenerator.new()
	r.seed = map_seed + 5
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for b in blades:
		var a := r.randf() * TAU
		var off := Vector3(r.randf_range(-0.3, 0.3), 0.0, r.randf_range(-0.3, 0.3))
		var side := Vector3(cos(a), 0.0, sin(a)) * r.randf_range(0.015, 0.03)
		var lean := Vector3(-sin(a), 0.0, cos(a)) * r.randf_range(-0.2, 0.2)
		var tip := off + Vector3(0, blade_h * r.randf_range(0.45, 1.2), 0) + lean
		for v in [[off - side, Vector2(0, 1)], [off + side, Vector2(1, 1)], [tip, Vector2(0.5, 0)]]:
			st.set_normal(Vector3.UP)
			st.set_color(Color.WHITE)
			st.set_uv(v[1])
			st.add_vertex(v[0])
	return st.commit()


func _in_no_grass(p: Vector2) -> bool:
	for r in no_grass:
		if r.has_point(p):
			return true
	return false


func _build_grass() -> void:
	var density: float = [0.3, 0.6, 1.1, 1.8][clampi(quality, 0, 3)] * grass_density()
	if density <= 0.0:
		return
	var cols := grass_colors()
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/grass.gdshader")
	mat.set_shader_parameter("base_col", cols[0])
	mat.set_shader_parameter("tip_col", cols[1])
	var mesh := _grass_mesh(grass_height(), 16)
	var r := RandomNumberGenerator.new()
	r.seed = map_seed + 21
	var chunk := 16.0
	var ext := Vector2(half.x + 22.0, half.y + 22.0)
	var cx := int(ceil(ext.x * 2.0 / chunk))
	var cz := int(ceil(ext.y * 2.0 / chunk))
	for iz in cz:
		for ix in cx:
			var origin := Vector2(-ext.x + ix * chunk, -ext.y + iz * chunk)
			var xforms: Array[Transform3D] = []
			var tints: Array[Color] = []
			var count := int(chunk * chunk * density)
			for i in count:
				var p := origin + Vector2(r.randf() * chunk, r.randf() * chunk)
				var patch := _n_hills.get_noise_2d(p.x * 3.0, p.y * 3.0)
				if patch < grass_patchiness() or _in_no_grass(p):
					continue
				var h := height_at(p.x, p.y)
				var slope := absf(height_at(p.x + 0.7, p.y) - h) + absf(height_at(p.x, p.y + 0.7) - h)
				if slope > 0.45:
					continue
				var s := r.randf_range(0.7, 1.35)
				var b := Basis(Vector3.UP, r.randf() * TAU).scaled(Vector3(s, s * r.randf_range(0.8, 1.3), s))
				xforms.append(Transform3D(b, Vector3(p.x, h - 0.05, p.y)))
				var dry := clampf(_n_ground.get_noise_2d(p.x * 2.0, p.y * 2.0) + 0.5, 0.0, 1.0)
				var t := r.randf_range(0.85, 1.1)
				tints.append(Color(0.8, 1.05, 0.75).lerp(Color(1.15, 1.0, 0.8), dry) * t)
			if xforms.is_empty():
				continue
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_colors = true
			mm.mesh = mesh
			mm.instance_count = xforms.size()
			for i in xforms.size():
				mm.set_instance_transform(i, xforms[i])
				mm.set_instance_color(i, tints[i])
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			mmi.material_override = mat
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mmi.visibility_range_end = [35.0, 50.0, 70.0, 95.0][clampi(quality, 0, 3)]
			mmi.visibility_range_end_margin = 10.0
			mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			add_child(mmi)


func grass_density() -> float:
	return 1.0


func grass_height() -> float:
	return 0.42


func grass_patchiness() -> float:
	return -0.35


# ---------------------------------------------------------------- prop helpers

func _box_mesh(size: Vector3) -> BoxMesh:
	var key := str(size)
	if not _box_meshes.has(key):
		var bm := BoxMesh.new()
		bm.size = size
		_box_meshes[key] = bm
	return _box_meshes[key]


func add_box(parent: Node3D, xf: Transform3D, size: Vector3, mat: Material, collide := true) -> Node3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _box_mesh(size)
	mi.material_override = mat
	if not collide:
		mi.transform = xf
		parent.add_child(mi)
		return mi
	var body := StaticBody3D.new()
	body.transform = xf
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	body.add_child(cs)
	body.add_child(mi)
	parent.add_child(body)
	return body


func add_mesh(parent: Node3D, xf: Transform3D, mesh: Mesh, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.transform = xf
	parent.add_child(mi)
	return mi


func add_cylinder_collider(parent: Node3D, pos: Vector3, radius: float, height: float) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	var cs := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.radius = radius
	sh.height = height
	cs.shape = sh
	body.add_child(cs)
	parent.add_child(body)


func make_root(p: Vector2, yaw: float, sink := 0.0) -> Node3D:
	var root := Node3D.new()
	props_root.add_child(root)
	root.position = ground(p) - Vector3(0, sink, 0)
	root.rotation.y = yaw
	return root


## Places a prop twice, point-symmetric around the centre (fair for both teams).
func mirrored(p: Vector2, yaw: float, fn: Callable) -> void:
	p *= layout_k
	fn.call(p, yaw)
	fn.call(-p, yaw + PI)


## Trees inside the playable area count as occupied ground (backdrop trees don't).
func _tree_footprint(p: Vector2) -> void:
	if absf(p.x) < half.x + 2.0 and absf(p.y) < half.y + 2.0:
		no_grass.append(Rect2(p - Vector2(1.2, 1.2), Vector2(2.4, 2.4)))


## True if nothing registered in `no_grass` (ruins, vehicles, rocks, stacks,
## trees...) lies within `r` metres of `p`.
func is_free(p: Vector2, r: float) -> bool:
	return _pad_free(p, r) and _props_free(p, r)


## Same, ignoring the building pads.
func _props_free(p: Vector2, r: float) -> bool:
	for rc in no_grass:
		if Rect2(rc.position - Vector2(r, r), rc.size + Vector2(r, r) * 2.0).has_point(p):
			return false
	return true


## Fills the empty ground with extra cover and loot: `count` random spots in
## the first half (each placed twice, point-symmetric). Keeps the spawn lines
## and the centre clear. `kinds` weights: ruin, container, car, crates, barrier, rock, clutter.
func fill_cover(count: int, weights := [0, 2, 3, 5, 4, 3, 3]) -> void:
	var total := 0
	for w in weights:
		total += w
	var placed := 0
	var tries := 0
	while placed < count and tries < count * 60:
		tries += 1
		var p := Vector2(rng.randf_range(-half.x + 8.0, half.x - 8.0), rng.randf_range(-half.y + 10.0, -6.0))
		if p.y < -half.y + 18.0 and absf(p.x) < 24.0:
			continue
		var r := rng.randf() * total
		var kind := 0
		for i in weights.size():
			r -= weights[i]
			if r <= 0.0:
				kind = i
				break
		var clearance: float = [9.0, 6.5, 5.0, 3.0, 4.0, 3.5, 4.5][kind]
		if not is_free(p, clearance) or not is_free(-p, clearance):
			continue
		var yaw := rng.randf() * TAU
		var loot := false
		# Layout choices are drawn once so both sides get the same footprint.
		var box_color: Color = [Color(0.55, 0.22, 0.16), Color(0.2, 0.38, 0.4), Color(0.62, 0.48, 0.2), Color(0.35, 0.4, 0.3)][rng.randi_range(0, 3)]
		var stacked := rng.randf() < 0.3
		for side in 2:
			var q := p if side == 0 else -p
			var y := yaw + side * PI
			match kind:
				1:
					add_container(q, y, box_color, stacked)
				2:
					add_car(q, y, Color(0.5, 0.5, 0.46))
				3:
					add_crate_stack(q, y)
					loot = rng.randf() < 0.5
				4:
					add_barrier(q, y)
					add_barrier(q + Vector2(cos(y), -sin(y)) * 3.3, y + rng.randf_range(-0.2, 0.2))
				5:
					add_rock(q, rng.randf_range(1.8, 3.2), y)
				6:
					scatter_clutter(q, 3.5, 3)
		# A crate beside ruins and some stacks (point-symmetric pair, kept in order).
		if loot:
			var off := Vector2(rng.randf_range(-1.2, 1.2), rng.randf_range(-1.2, 1.2))
			_extra_loot.append(Vector3(p.x + off.x, 0, p.y + off.y))
			_extra_loot.append(Vector3(-p.x - off.x, 0, -p.y - off.y))
		placed += 1


# ---------------------------------------------------------------- buildings
#
# Gutted brick buildings from the scanned factory facade kit. Footprints are
# whole 3 m modules turned in quarter turns, standing on a levelled pad (the
# terrain is flattened under them before it is built, see plan_building), with
# real doorways (1.8 m wide, flush with the ground), windows with a 0.6 m sill
# (they can be vaulted) and a staircase (steps over a hidden ramp, so the
# character glides up it). Planned first so the pad exists when the terrain is
# generated, built later by build_planned_buildings().

const MODULE_W := 3.0
const PAD_BLEND := 7.0
const STAIR_STEPS := 15
const STAIR_TREAD := 0.36
const STAIR_WIDTH := 2.0
const STAIR_LANDING := 1.1
var _pads: Array = []
var _planned: Array = []
var _stair_mesh: BoxMesh


## Natural ground height averaged over a footprint (the level of its pad).
func _ground_avg(c: Vector2, h: Vector2) -> float:
	var sum := 0.0
	var n := 0
	for ix in [-1.0, 0.0, 1.0]:
		for iz in [-1.0, 0.0, 1.0]:
			sum += _natural_height(c.x + ix * h.x, c.y + iz * h.y)
			n += 1
	return sum / n


## Registers a building to build later and flattens the ground under it.
## `size` is rounded to whole modules, `yaw` to a quarter turn.
func plan_building(center: Vector2, size: Vector2, floors: int, yaw: float, seed: int, mat: Material = null) -> void:
	var quarter := roundi(yaw / (PI * 0.5))
	var nx := maxi(2, roundi(size.x / MODULE_W))
	var nz := maxi(2, roundi(size.y / MODULE_W))
	floors = mini(floors, 2)
	if floors > 1:
		nx = maxi(nx, 3) # the staircase needs 8 m of wall
	var half := Vector2(nx, nz) * MODULE_W * 0.5
	var world_half := half if posmod(quarter, 2) == 0 else Vector2(half.y, half.x)
	var level := _ground_avg(center, world_half)
	_pads.append({"c": center, "h": world_half + Vector2(1.0, 1.0), "y": level})
	_planned.append({"c": center, "nx": nx, "nz": nz, "floors": floors, "quarter": quarter, "seed": seed, "mat": mat, "y": level})


## True if no planned pad lies within `r` of `p`.
func _pad_free(p: Vector2, r: float) -> bool:
	for pad in _pads:
		if absf(p.x - pad.c.x) < pad.h.x + r and absf(p.y - pad.c.y) < pad.h.y + r:
			return false
	return true


## `count` extra single-storey buildings in the empty parts of the first half
## (each placed twice, point-symmetric), each with a crate pair inside.
func plan_extra_buildings(count: int) -> void:
	var pr := RandomNumberGenerator.new()
	pr.seed = map_seed + 404
	var placed := 0
	var tries := 0
	while placed < count and tries < count * 80:
		tries += 1
		var p := Vector2(pr.randf_range(-half.x + 14.0, half.x - 14.0), pr.randf_range(-half.y + 16.0, -10.0))
		if p.y < -half.y + 24.0 and absf(p.x) < 26.0:
			continue
		if not _pad_free(p, 12.0) or not _pad_free(-p, 12.0):
			continue
		var size := Vector2(MODULE_W * pr.randi_range(2, 3), MODULE_W * 2.0)
		var yaw := pr.randi_range(0, 3) * PI * 0.5
		plan_building(p, size, 1, yaw, 900 + placed)
		plan_building(-p, size, 1, yaw + PI, 900 + placed)
		_extra_loot.append(Vector3(p.x, 0, p.y))
		_extra_loot.append(Vector3(-p.x, 0, -p.y))
		placed += 1


func build_planned_buildings() -> void:
	for b in _planned:
		_build_building(b)
	_planned.clear()


## Wall modules of the facade kit used on buildings: [solid, window, door].
const RUIN_KIT := "factory"
const RUIN_MODULES := ["wall_standard_standard_01", "wall_window_centered_large_01", "wall_door_centered_large_01"]


static var _kit_brick: StandardMaterial3D


## The facade kit's brick, mapped in world space (triplanar, 3 m per tile like
## the kit) for the concrete blocks behind the modules and the broken walls.
static func kit_brick() -> StandardMaterial3D:
	if _kit_brick == null:
		var t := "res://assets/polyhaven/models/modular_factory_facade/textures/modular_factory_facade_brick_%s_2k.jpg"
		var m := StandardMaterial3D.new()
		m.albedo_texture = load(t % "diff")
		m.normal_enabled = true
		m.normal_texture = load(t % "nor_gl")
		var arm: Texture2D = load(t % "arm")
		m.ao_enabled = true
		m.ao_texture = arm
		m.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
		m.roughness_texture = arm
		m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
		m.metallic = 0.0
		m.uv1_triplanar = true
		m.uv1_world_triplanar = true
		m.uv1_scale = Vector3.ONE / 3.0
		_kit_brick = m
	return _kit_brick


func _build_building(b: Dictionary) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = int(b.seed)
	var nx: int = b.nx
	var nz: int = b.nz
	var floors: int = b.floors
	var w := nx * MODULE_W
	var d := nz * MODULE_W
	var c: Vector2 = b.c
	var root := Node3D.new()
	props_root.add_child(root)
	root.position = Vector3(c.x, float(b.y), c.y)
	root.rotation.y = int(b.quarter) * PI * 0.5
	var mat: Material = kit_brick()
	var dark := Mats.concrete_dark()
	var ext := maxf(w, d) * 0.5 + 1.5
	no_grass.append(Rect2(c - Vector2(ext, ext), Vector2(ext, ext) * 2.0))
	# Floor slab, 6 cm proud of the levelled ground (a doorstep the capsule glides over).
	add_box(root, Transform3D(Basis(), Vector3(0, -0.2, 0)), Vector3(w + 0.4, 0.52, d + 0.4), dark)

	# Which modules get a door on the ground floor. The back wall (+z) carries the
	# staircase of a two-storey building, so it stays doorless then.
	var doors := {} # wall index -> module index
	doors[0] = nx / 2 if posmod(nx, 2) == 1 else r.randi_range(nx / 2 - 1, nx / 2)
	if floors == 1:
		doors[1] = clampi(nx - 1 - int(doors[0]), 0, nx - 1)
	var side := r.randi_range(2, 3)
	doors[side] = nz / 2 if posmod(nz, 2) == 1 else r.randi_range(nz / 2 - 1, nz / 2)
	if r.randf() < 0.45:
		doors[5 - side] = clampi(nz - 1 - int(doors[side]), 0, nz - 1)
	var door_points: Array[Vector3] = []

	for f in floors:
		var y0 := 0.06 + f * FLOOR_H
		var top := f == floors - 1
		# Walls run corner to corner; side walls are inset by a wall thickness.
		var corners := [
			[Vector3(-w / 2, y0, -d / 2), Vector3(w / 2, y0, -d / 2), nx],
			[Vector3(w / 2, y0, d / 2), Vector3(-w / 2, y0, d / 2), nx],
			[Vector3(-w / 2, y0, d / 2 - WALL_T), Vector3(-w / 2, y0, -d / 2 + WALL_T), nz],
			[Vector3(w / 2, y0, -d / 2 + WALL_T), Vector3(w / 2, y0, d / 2 - WALL_T), nz],
		]
		for wi in 4:
			var cw: Array = corners[wi]
			var door_idx := int(doors[wi]) if (f == 0 and doors.has(wi)) else -1
			_building_wall(root, cw[0], cw[1], int(cw[2]), f, top, door_idx, r, mat, door_points)
		var ph := FLOOR_H + 0.12 if not top else r.randf_range(1.6, FLOOR_H)
		for cc in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
			add_box(root, Transform3D(Basis(), Vector3(cc.x * w / 2, y0 + ph / 2, cc.y * d / 2)), Vector3(0.45, ph, 0.45), dark)
		if f > 0:
			_building_upper_floor(root, w, d, y0, dark, mat)
	if floors > 1:
		_building_stairs(root, w, d, dark)
	# Doorsteps and clutter outside, kept off the doorways.
	var keep_clear: Array[Vector3] = []
	for dp in door_points:
		keep_clear.append(root.transform * dp)
	var placed_clutter := 0
	var ctries := 0
	var clutter_goal := r.randi_range(2, 3)
	while placed_clutter < clutter_goal and ctries < 20:
		ctries += 1
		var a := r.randf() * TAU
		var rad := Vector2(w, d).length() * 0.5 + r.randf_range(2.5, 4.5)
		var cp := c + Vector2(cos(a), sin(a)) * rad
		var near_door := false
		for k in keep_clear:
			if Vector2(k.x, k.z).distance_to(cp) < 4.0:
				near_door = true
		if near_door or not _props_free(cp, 1.5):
			continue
		scatter_clutter(cp, 1.2, 1)
		placed_clutter += 1
	# A crate stack inside a one-storey building (not on the way from door to door).
	if floors == 1 and r.randf() < 0.7:
		var inside := root.transform * Vector3(([-1.0, 1.0][r.randi() % 2]) * (w * 0.5 - 1.3), 0.0, ([-1.0, 1.0][r.randi() % 2]) * (d * 0.5 - 1.1))
		add_crate_stack(Vector2(inside.x, inside.z), root.rotation.y + r.randf_range(-0.2, 0.2), true)


## One wall of `n` modules from `a` to `b` (local coordinates), one floor. Modules
## keep their true proportions; the concrete behind them frames each opening so
## collisions match what is drawn. `door_idx` >= 0 puts a doorway on that module.
func _building_wall(root: Node3D, a: Vector3, b: Vector3, n: int, floor_i: int, top: bool, door_idx: int, r: RandomNumberGenerator, mat: Material, door_points: Array[Vector3]) -> void:
	var dir := b - a
	var length := dir.length()
	dir /= length
	var wm := length / n
	var basis := Basis(Vector3.UP, atan2(-dir.z, dir.x))
	var mid := (a + b) * 0.5
	var outward := basis.z if basis.z.dot(Vector3(mid.x, 0.0, mid.z)) > 0.0 else -basis.z
	var kx := Vector3.UP.cross(outward)
	var sx := wm / FacadeKit.MODULE
	var sy := FLOOR_H / FacadeKit.MODULE
	var kbasis := Basis(kx * sx, Vector3.UP * sy, outward)
	var win_p := 0.55 if floor_i == 0 else 0.75
	for i in n:
		var cx := (i + 0.5) * wm
		var kind := "solid"
		if i == door_idx:
			kind = "door"
		elif r.randf() < win_p:
			kind = "window"
		# The top floor is ragged: broken sills and tall stubs (never beside a doorway).
		if top and kind != "door":
			if kind == "solid" and r.randf() < 0.4:
				kind = "broken_high"
			elif kind == "window" and r.randf() < 0.3:
				kind = "broken"
		match kind:
			"broken":
				_wall_seg(root, a, dir, basis, cx, wm, 0.0, r.randf_range(0.5, 1.5), mat)
				continue
			"broken_high":
				_wall_seg(root, a, dir, basis, cx, wm, 0.0, r.randf_range(2.2, FLOOR_H - 0.3), mat)
				continue
		var wall: String = RUIN_MODULES[{"solid": 0, "window": 1, "door": 2}[kind]]
		var hole := FacadeKit.opening(RUIN_KIT, wall)
		var start := a + dir * (cx - wm * 0.5) if kx.dot(dir) > 0.0 else a + dir * (cx + wm * 0.5)
		var origin := start + outward * (WALL_T * 0.5 + 0.012)
		var kxf := Transform3D(kbasis, origin)
		for part in FacadeKit.module(RUIN_KIT, wall, false):
			batch(part[0], root.transform * kxf * (part[1] as Transform3D))
		if hole.size == Vector2.ZERO:
			_wall_seg(root, a, dir, basis, cx, wm, 0.0, FLOOR_H, mat)
			continue
		if kind == "door":
			door_points.append(a + dir * cx + outward * 2.4)
		# Concrete around the opening (a hair larger, so the kit's reveal shows).
		var hx0 := hole.position.x * sx - 0.02
		var hx1 := hole.end.x * sx + 0.02
		var hy0 := maxf(0.0, hole.position.y * sy - 0.02)
		var hy1 := hole.end.y * sy + 0.02
		var flip := kx.dot(dir) < 0.0
		var m0 := cx - wm * 0.5
		var x_lo := m0 + (wm - hx1 if flip else hx0)
		var x_hi := m0 + (wm - hx0 if flip else hx1)
		_wall_seg(root, a, dir, basis, (m0 + x_lo) * 0.5, x_lo - m0, 0.0, FLOOR_H, mat)
		_wall_seg(root, a, dir, basis, (x_hi + m0 + wm) * 0.5, m0 + wm - x_hi, 0.0, FLOOR_H, mat)
		_wall_seg(root, a, dir, basis, (x_lo + x_hi) * 0.5, x_hi - x_lo, 0.0, hy0, mat)
		_wall_seg(root, a, dir, basis, (x_lo + x_hi) * 0.5, x_hi - x_lo, hy1, FLOOR_H, mat)


## Upper floor slab with the stairwell cut out. The stairs climb towards the west
## wall along the back wall: the low end (east) is in the open room, so they are
## entered head-on, and they pass under the slab's east strip until 0.8 m up, where
## the hole starts. At the top a 1.1 m landing (part of the slab) lets you step off
## sideways onto the floor.
func _building_upper_floor(root: Node3D, w: float, d: float, y0: float, dark: Material, mat: Material) -> void:
	var x_st := -w / 2 + 0.5 + STAIR_LANDING # where the steps meet the landing
	var x_low := x_st + STAIR_STEPS * STAIR_TREAD
	var hole_x1 := x_low - 1.2 # east edge: the stairs are ~0.75 m up here, 2.2 m of headroom
	var z_back := d / 2 - WALL_T * 0.5 - 0.15
	var z_hole := z_back - STAIR_WIDTH - 0.08
	var t := 0.3
	# Main slab, plus the strips along the back wall either side of the hole.
	add_box(root, Transform3D(Basis(), Vector3(0, y0 - t / 2, (-d / 2 + z_hole) / 2)), Vector3(w, t, z_hole + d / 2), dark)
	add_box(root, Transform3D(Basis(), Vector3((hole_x1 + w / 2) / 2, y0 - t / 2, (z_hole + d / 2) / 2)), Vector3(w / 2 - hole_x1, t, d / 2 - z_hole), dark)
	add_box(root, Transform3D(Basis(), Vector3((-w / 2 + x_st) / 2, y0 - t / 2, (z_hole + d / 2) / 2)), Vector3(x_st + w / 2, t, d / 2 - z_hole), dark)
	# Waist-high guard rails round the opening (south and east edges).
	add_box(root, Transform3D(Basis(), Vector3((x_st + hole_x1) / 2, y0 + 0.5, z_hole)), Vector3(hole_x1 - x_st, 1.0, 0.12), mat)
	add_box(root, Transform3D(Basis(), Vector3(hole_x1, y0 + 0.5, (z_hole + d / 2) / 2)), Vector3(0.12, 1.0, d / 2 - z_hole - 0.3), mat)


## Staircase: visual steps over an invisible ramp the character walks up.
func _building_stairs(root: Node3D, w: float, d: float, dark: Material) -> void:
	var x_st := -w / 2 + 0.5 + STAIR_LANDING
	var y_base := 0.06
	var rise := FLOOR_H / STAIR_STEPS
	var run := STAIR_STEPS * STAIR_TREAD
	var x_low := x_st + run
	var zc := d / 2 - WALL_T * 0.5 - 0.15 - STAIR_WIDTH * 0.5
	if _stair_mesh == null:
		_stair_mesh = BoxMesh.new()
		_stair_mesh.size = Vector3.ONE
		_stair_mesh.material = Mats.concrete_dark()
	for i in STAIR_STEPS:
		var hgt := (i + 1) * rise
		var size := Vector3(STAIR_TREAD, hgt, STAIR_WIDTH)
		var pos := Vector3(x_low - i * STAIR_TREAD - STAIR_TREAD * 0.5, y_base + hgt * 0.5, zc)
		batch(_stair_mesh, root.transform * Transform3D(Basis.from_scale(size), pos))
	# Collision: one slope through the nosings, rising towards -x.
	var ang := atan2(FLOOR_H, run)
	var length := sqrt(run * run + FLOOR_H * FLOOR_H)
	var normal := Vector3(sin(ang), cos(ang), 0.0)
	var centre := Vector3(x_low - run * 0.5, y_base + FLOOR_H * 0.5, zc) - normal * 0.1
	var ramp := add_box(root, Transform3D(Basis(Vector3.BACK, -ang), centre), Vector3(length, 0.2, STAIR_WIDTH), dark, true)
	ramp.get_child(1).visible = false
	# The baked mesh doesn't always join the ramp to the floors above: an explicit link
	# (foot of the stairs <-> the landing, straight up the axis) keeps bots on the stairs.
	var link := NavigationLink3D.new()
	link.bidirectional = true
	link.start_position = Vector3(x_low + 0.3, y_base, zc)
	link.end_position = Vector3(x_st - 0.5, y_base + FLOOR_H, zc)
	root.add_child(link)
	# Balustrade on the open (south) side: without it the ramp's ledge, under 0.5 m
	# high near the bottom, looks climbable to the navmesh and bots try to walk onto it.
	var rail_len := run / cos(ang)
	var rail_mid_x := (x_low + x_st) * 0.5
	var surface := Vector3(rail_mid_x, y_base + (x_low - rail_mid_x) * tan(ang), zc - STAIR_WIDTH * 0.5 - 0.06)
	add_box(root, Transform3D(Basis(Vector3.BACK, -ang), surface + normal * 0.45), Vector3(rail_len, 1.1, 0.12), dark, true)

func _wall_seg(root: Node3D, a: Vector3, dir: Vector3, basis: Basis, cx: float, w: float, y_from: float, y_to: float, mat: Material) -> void:
	var h := y_to - y_from
	if h <= 0.05 or w <= 0.02:
		return
	var c := a + dir * cx + Vector3(0, y_from + h / 2, 0)
	add_box(root, Transform3D(basis, c), Vector3(w + 0.02, h, WALL_T), mat)


# ---------------------------------------------------------------- props

func add_container(p: Vector2, yaw: float, color: Color, stacked := false) -> void:
	if not _pad_free(p, 1.2):
		return
	if Scan.exists(CONTAINER_MODEL):
		# Scanned rusty 20' container, scaled to the real 6.06 x 2.59 x 2.44 m.
		var size := Scan.size_of(CONTAINER_MODEL)
		var turn := 0.0 if size.x >= size.z else PI / 2
		var s := 6.06 / maxf(maxf(size.x, size.z), 0.1)
		var croot := make_root(p, yaw, 0.1)
		Scan.place(croot, CONTAINER_MODEL, Transform3D(Basis(Vector3.UP, turn).scaled(Vector3.ONE * s), Vector3.ZERO), "", "box")
		if stacked:
			Scan.place(croot, CONTAINER_MODEL, Transform3D(Basis(Vector3.UP, turn + 0.12 + PI).scaled(Vector3.ONE * s), Vector3(0.3, size.y * s, 0.1)), "", "box")
		var ce := 4.2
		no_grass.append(Rect2(p - Vector2(ce, ce), Vector2(ce, ce) * 2))
		_tag_surface(croot, "metal")
		return
	var root := make_root(p, yaw, 0.15)
	var size := Vector3(6.06, 2.59, 2.44)
	var mat := Mats.corrugated(color.to_html(), color)
	add_box(root, Transform3D(Basis(), Vector3(0, size.y / 2, 0)), size, mat)
	add_box(root, Transform3D(Basis(), Vector3(size.x / 2 + 0.02, size.y / 2, 0)), Vector3(0.06, size.y - 0.1, size.z - 0.1), Mats.rust(), false)
	if stacked:
		add_box(root, Transform3D(Basis(Vector3.UP, 0.12), Vector3(0.3, size.y * 1.5 + 0.02, 0.1)), size, Mats.corrugated("c2" + color.to_html(), color.darkened(0.25)))
	var e := 4.2
	no_grass.append(Rect2(p - Vector2(e, e), Vector2(e, e) * 2))
	_tag_surface(root, "metal")


## Scanned / game-ready wrecks, used when present: [model, target length (m)].
## Sketchfab ones are CC BY (credits in README); covered_car is Poly Haven CC0.
const VEHICLES := [
	["res://assets/sketchfab/vehicles/crashed_car/scene.gltf", 4.4],
	["res://assets/sketchfab/vehicles/sedan_1/scene.gltf", 4.6],
	["res://assets/sketchfab/vehicles/sedan_2/scene.gltf", 4.6],
	["res://assets/sketchfab/vehicles/crashed_truck/scene.gltf", 5.4],
	["covered_car", 0.0],
]
const CONTAINER_MODEL := "res://assets/sketchfab/container/scene.gltf"


func _vehicles() -> Array:
	var out := []
	for v in VEHICLES:
		if Scan.exists(v[0]):
			out.append(v)
	return out


func add_car(p: Vector2, yaw: float, tint := Color(0.45, 0.47, 0.44)) -> void:
	if not _pad_free(p, 1.2):
		return
	var models := _vehicles()
	if not models.is_empty():
		var v: Array = models[rng.randi_range(0, models.size() - 1)]
		var size := Scan.size_of(v[0])
		var length := maxf(size.x, size.z)
		var s: float = 1.0 if float(v[1]) <= 0.0 else float(v[1]) / maxf(length, 0.1)
		# Long axis of the model along local X (like the old box car).
		var turn := 0.0 if size.x >= size.z else PI / 2
		var root := make_root(p, yaw, 0.03)
		root.rotation.z = rng.randf_range(-0.03, 0.03)
		Scan.place(root, v[0], Transform3D(Basis(Vector3.UP, turn).scaled(Vector3.ONE * s), Vector3.ZERO), "", "box")
		# A loose wheel rim or tyre lying around, now and then.
		if rng.randf() < 0.45:
			var side := Vector3(rng.randf_range(-2.5, 2.5), 0.0, 1.6 * (1.0 if rng.randf() < 0.5 else -1.0))
			var id := "rusted_wheel_rim_01" if rng.randf() < 0.6 else "old_tyre"
			Scan.place(root, id, Transform3D(Basis(Vector3.RIGHT, PI / 2).rotated(Vector3.UP, rng.randf() * TAU), side + Vector3(0, 0.08, 0)), "", "none")
		no_grass.append(Rect2(p - Vector2(3.0, 3.0), Vector2(6, 6)))
		_tag_surface(root, "metal")
		return
	var root := make_root(p, yaw, 0.05)
	root.rotation.x = rng.randf_range(-0.04, 0.04)
	root.rotation.z = rng.randf_range(-0.06, 0.06)
	var paint := Mats.paint("car" + tint.to_html(), tint)
	var rust := Mats.rust()
	# collision
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(4.3, 1.3, 1.8)
	cs.shape = sh
	cs.position = Vector3(0, 0.75, 0)
	body.add_child(cs)
	root.add_child(body)
	add_box(root, Transform3D(Basis(), Vector3(0, 0.62, 0)), Vector3(4.3, 0.62, 1.8), paint, false)
	add_box(root, Transform3D(Basis(), Vector3(0, 0.36, 0)), Vector3(4.1, 0.2, 1.7), rust, false)
	add_box(root, Transform3D(Basis(), Vector3(0.25, 1.2, 0)), Vector3(2.1, 0.55, 1.6), Mats.glass(), false)
	add_box(root, Transform3D(Basis(), Vector3(0.3, 1.5, 0)), Vector3(1.9, 0.07, 1.62), rust, false)
	add_box(root, Transform3D(Basis(Vector3.BACK, -0.1), Vector3(-1.55, 0.97, 0)), Vector3(1.3, 0.08, 1.7), paint, false)
	var wheel := CylinderMesh.new()
	wheel.top_radius = 0.33
	wheel.bottom_radius = 0.33
	wheel.height = 0.24
	for wx in [-1.35, 1.35]:
		for wz in [-0.82, 0.82]:
			if rng.randf() < 0.2:
				continue
			add_mesh(root, Transform3D(Basis(Vector3.RIGHT, PI / 2), Vector3(wx, 0.33, wz)), wheel, Mats.tire())
	no_grass.append(Rect2(p - Vector2(2.5, 2.5), Vector2(5, 5)))


func add_barrier(p: Vector2, yaw: float) -> void:
	if not _pad_free(p, 1.2):
		return
	# Two scanned jersey barriers side by side (~3.1 m), one box collider.
	var root := make_root(p, yaw, 0.04)
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(3.1, 0.9, 0.62)
	cs.shape = sh
	cs.position = Vector3(0, 0.45, 0)
	body.add_child(cs)
	root.add_child(body)
	# Mix the two scanned barrier models (the second one is a taller "Jersey").
	_tag_surface(root, "stone")
	var model := "concrete_road_barrier_02" if Scan.exists("concrete_road_barrier_02") and rng.randf() < 0.4 else "concrete_road_barrier"
	var sy := 1.08 if model == "concrete_road_barrier" else 0.85
	for x in [-0.775, 0.775]:
		Scan.place(root, model, Transform3D(Basis(Vector3.UP, rng.randf_range(-0.03, 0.03)).scaled(Vector3(1, sy, 1)), Vector3(x, 0, 0)), "", "none")


## Scanned rock variants: [model id, mesh-name prefix].
const ROCKS := [
	["boulder_01", ""], ["namaqualand_boulder_02", ""],
	["rock_moss_set_02", "rock_moss_set_02_rock07"], ["rock_moss_set_02", "rock_moss_set_02_rock09"],
	["rock_moss_set_02", "rock_moss_set_02_rock10"], ["rock_moss_set_02", "rock_moss_set_02_rock11"],
	["rock_moss_set_02", "rock_moss_set_02_rock12"], ["rock_moss_set_02", "rock_moss_set_02_rock13"],
]


func rock_tint() -> Color:
	return Color(0.56, 0.52, 0.47)


func add_rock(p: Vector2, scale: float, yaw: float, variant := -1) -> void:
	if not _pad_free(p, 1.2):
		return
	if variant < 0:
		variant = rng.randi_range(0, ROCKS.size() - 1)
	var v: Array = ROCKS[variant % ROCKS.size()]
	var size := Scan.size_of(v[0], v[1])
	# `scale` ~ radius in metres of the old procedural rocks: footprint ≈ 2.2 × scale.
	var s := scale * 2.2 / maxf(maxf(size.x, size.z), 0.1)
	s = maxf(s, scale * 0.9 / maxf(size.y, 0.1))
	var root := make_root(p, yaw, size.y * s * 0.15)
	Scan.place(root, v[0], Transform3D(Basis().scaled(Vector3.ONE * s), Vector3.ZERO), v[1], "convex")
	var e := scale * 1.3
	no_grass.append(Rect2(p - Vector2(e, e), Vector2(e, e) * 2))


func add_cypress(p: Vector2, h: float) -> void:
	if not _pad_free(p, 1.2):
		return
	_tree_footprint(p)
	var root := make_root(p, rng.randf() * TAU, 0.1)
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.12
	trunk.bottom_radius = 0.2
	trunk.height = 2.0
	add_mesh(root, Transform3D(Basis(), Vector3(0, 1.0, 0)), trunk, Mats.bark())
	var core := CapsuleMesh.new()
	core.radius = 0.55
	core.height = 6.0
	core.radial_segments = 8
	core.rings = 4
	var r0 := 0.85 + h * 0.025
	add_mesh(root, Transform3D(Basis().scaled(Vector3(1, h * 0.8 / 6.0, 1)), Vector3(0, h * 0.5 + 0.6, 0)), core, Mats.foliage("cypress_core", Color(0.08, 0.11, 0.05)))
	var canopy := Mats.canopy_mesh(100 + rng.randi_range(0, 3), Vector3(r0, h * 0.47, r0), 110, 0.75)
	add_mesh(root, Transform3D(Basis(), Vector3(0, h * 0.5 + 0.7, 0)), canopy, Mats.leaves("cypress", Color(0.32, 0.42, 0.2)))
	add_cylinder_collider(root, Vector3(0, 1.5, 0), 0.25, 3.0)


func add_pine(p: Vector2, h: float) -> void:
	if not _pad_free(p, 1.2):
		return
	_tree_footprint(p)
	var root := make_root(p, rng.randf() * TAU, 0.1)
	var lean := rng.randf_range(-0.18, 0.18)
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.14
	trunk.bottom_radius = 0.25
	trunk.height = h
	var tb := Basis(Vector3.BACK, lean)
	add_mesh(root, Transform3D(tb, tb * Vector3(0, h / 2, 0)), trunk, Mats.bark())
	var top := tb * Vector3(0, h, 0)
	var leaves := Mats.leaves("pine", Color(0.36, 0.44, 0.22))
	var core := Mats.foliage("pine_core", Color(0.1, 0.13, 0.06))
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 10
	sphere.rings = 5
	for i in 4:
		var o := Vector3(rng.randf_range(-1.8, 1.8), rng.randf_range(-0.4, 0.5), rng.randf_range(-1.8, 1.8))
		var rad := Vector3(rng.randf_range(1.8, 2.5), rng.randf_range(0.7, 0.95), rng.randf_range(1.8, 2.5))
		add_mesh(root, Transform3D(Basis().scaled(rad * 0.7), top + o), sphere, core)
		add_mesh(root, Transform3D(Basis(Vector3.UP, rng.randf() * TAU), top + o), Mats.canopy_mesh(200 + rng.randi_range(0, 3), Vector3(2.2, 0.85, 2.2), 55, 0.85), leaves)
	add_cylinder_collider(root, Vector3(0, 1.5, 0), 0.3, 3.0)


func add_fir(p: Vector2, h: float, snowy := true) -> void:
	if not _pad_free(p, 1.2):
		return
	_tree_footprint(p)
	var root := make_root(p, rng.randf() * TAU, 0.1)
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.08
	trunk.bottom_radius = 0.22
	trunk.height = h * 0.5
	add_mesh(root, Transform3D(Basis(), Vector3(0, h * 0.25, 0)), trunk, Mats.bark())
	var fol := Mats.foliage("fir", Color(0.12, 0.18, 0.12))
	var snow := Mats.surface("snowcap", Color(0.86, 0.9, 0.95), 0.6, 0.0, 0.8, 0.85, 1.0, 3.0)
	var tiers := 5
	for i in tiers:
		var t := float(i) / tiers
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = lerpf(2.2, 0.6, t) * h / 12.0 * 1.4
		cone.height = h * 0.32
		cone.radial_segments = 10
		var y := h * (0.22 + t * 0.62)
		add_mesh(root, Transform3D(Basis(), Vector3(0, y, 0)), cone, fol)
		if snowy:
			var cap := CylinderMesh.new()
			cap.top_radius = 0.0
			cap.bottom_radius = cone.bottom_radius * 0.82
			cap.height = cone.height * 0.55
			cap.radial_segments = 10
			add_mesh(root, Transform3D(Basis(), Vector3(0, y + cone.height * 0.24, 0)), cap, snow)
	add_cylinder_collider(root, Vector3(0, 1.5, 0), 0.3, 3.0)


func add_bush(p: Vector2, s: float, color := Color(0.22, 0.27, 0.13)) -> void:
	if not _pad_free(p, 1.2):
		return
	var root := make_root(p, rng.randf() * TAU, 0.1)
	var leaves := Mats.leaves("bush" + color.to_html(), color * 1.6)
	var mesh := Mats.canopy_mesh(300 + rng.randi_range(0, 3), Vector3(1.0, 0.65, 1.0), 26, 0.55)
	for i in 2:
		var o := Vector3(rng.randf_range(-0.5, 0.5), 0.45, rng.randf_range(-0.5, 0.5)) * s
		add_mesh(root, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s * rng.randf_range(0.7, 1.1)), o), mesh, leaves)


func add_pole(p: Vector2, yaw: float) -> void:
	if not _pad_free(p, 1.2):
		return
	# Scanned utility pole (one of the kit's three presets), ~8 m tall.
	var root := make_root(p, yaw, 0.3)
	var preset := "preset_0%d_" % rng.randi_range(1, 3)
	Scan.place(root, "modular_electricity_poles", Transform3D(Basis(Vector3.BACK, rng.randf_range(-0.03, 0.03)).scaled(Vector3.ONE * 1.35), Vector3.ZERO), preset, "none")
	add_cylinder_collider(root, Vector3(0, 2.5, 0), 0.16, 5.0)


## Scanned debris around a point: barrels, tyres, utility boxes, dead trunks, branches.
func scatter_clutter(center: Vector2, radius: float, count: int) -> void:
	for i in count:
		var a := rng.randf() * TAU
		var p := center + Vector2(cos(a), sin(a)) * rng.randf_range(radius * 0.6, radius)
		var yaw := rng.randf() * TAU
		match rng.randi_range(0, 10):
			6, 7:
				add_crate_stack(p, yaw)
			8:
				# Fuel corner: generator / compressor with jerrycans and a gas bottle.
				var root := make_root(p, yaw, 0.02)
				Scan.place(root, "portable_generator" if rng.randf() < 0.6 else "old_military_compressor", Transform3D(), "", "box")
				for k in rng.randi_range(1, 3):
					Scan.place(root, "metal_jerrycan", Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(rng.randf_range(-0.9, 0.9), 0, rng.randf_range(0.6, 1.0))), "", "none")
				if rng.randf() < 0.6:
					Scan.place(root, "propane_tank", Transform3D(Basis(), Vector3(-0.8, 0, -0.5)), "", "none")
			9:
				var root := make_root(p, yaw, 0.02)
				Scan.place(root, "wooden_barrels_01", Transform3D(Basis(), Vector3(-0.4, 0, 0)), "wooden_barrels_01_barrel01$", "box")
				Scan.place(root, "wooden_barrels_01", Transform3D(Basis(Vector3.UP, 1.3), Vector3(0.42, 0, 0.1)), "wooden_barrels_01_barrel02$", "box")
			10:
				var root := make_root(p, yaw, 0.1)
				Scan.place(root, "tree_stump_01", Transform3D(Basis().scaled(Vector3.ONE * rng.randf_range(0.8, 1.2)), Vector3.ZERO), "", "convex")
			0, 1:
				var root := make_root(p, yaw, 0.02)
				Scan.place(root, "Barrel_01", Transform3D(), "", "box")
				if rng.randf() < 0.5:
					Scan.place(root, "Barrel_01", Transform3D(Basis(), Vector3(0.62, 0, 0.1)), "", "box")
			2:
				var root := make_root(p, yaw, 0.0)
				Scan.place(root, "old_tyre", Transform3D(Basis(Vector3.RIGHT, PI / 2), Vector3(0, 0.08, 0)), "", "none")
			3:
				var root := make_root(p, yaw, 0.02)
				Scan.place(root, "utility_box_02", Transform3D(), "", "box")
			4:
				var root := make_root(p, yaw, 0.15)
				Scan.place(root, "dead_tree_trunk_02", Transform3D(Basis().scaled(Vector3.ONE * rng.randf_range(0.9, 1.3)), Vector3.ZERO), "", "box")
			5:
				var root := make_root(p, yaw, 0.02)
				Scan.place(root, "dry_branches_medium_01", Transform3D(Basis().scaled(Vector3.ONE * 1.5), Vector3.ZERO), "", "none")


## Stack of scanned military crates (low cover, 0.4 - 1.3 m), one collider per crate.
func add_crate_stack(p: Vector2, yaw: float, force := false) -> void:
	if not force and not _pad_free(p, 1.2):
		return
	var root := make_root(p, yaw, 0.02)
	var models := ["wooden_military_crate", "old_military_crate", "wooden_crate_02"]
	var y := 0.0
	var layers := rng.randi_range(1, 3)
	for l in layers:
		var count := 2 if l == 0 else 1
		var layer_h := INF
		for k in count:
			var id: String = models[rng.randi_range(0, models.size() - 1)]
			var size := Scan.size_of(id)
			var o := Vector3((k - (count - 1) * 0.5) * (size.x + 0.08) + rng.randf_range(-0.06, 0.06), y, rng.randf_range(-0.05, 0.05))
			Scan.place(root, id, Transform3D(Basis(Vector3.UP, rng.randf_range(-0.12, 0.12)), o), "", "box")
			layer_h = minf(layer_h, size.y)
		y += layer_h
	no_grass.append(Rect2(p - Vector2(1.6, 1.6), Vector2(3.2, 3.2)))


## Scanned street lamp (~3.9 m), thin collider on the post.
func add_lamp(p: Vector2, yaw: float) -> void:
	if not _pad_free(p, 1.2):
		return
	var root := make_root(p, yaw, 0.05)
	Scan.place(root, "street_lamp_01", Transform3D(Basis().scaled(Vector3.ONE * 1.25), Vector3.ZERO), "", "none")
	add_cylinder_collider(root, Vector3(0, 2.4, 0), 0.12, 4.8)


## Chain-link fence from a to b. Blocks players (layer 3) but not bullets or sight.
func add_fence(a: Vector2, b: Vector2) -> void:
	var dir := b - a
	var length := dir.length()
	var seg := Scan.size_of("modular_chainlink_fence", "modular_chainlink_fence_double$").x
	var n := maxi(1, int(round(length / seg)))
	var yaw := -dir.angle()
	for i in n:
		var p := a + dir * ((i + 0.5) / n)
		var root := make_root(p, yaw, 0.05)
		Scan.place(root, "modular_chainlink_fence", Transform3D(Basis().scaled(Vector3(length / n / seg, 1, 1)), Vector3.ZERO), "modular_chainlink_fence_double$", "box", 4)
		var post_p := a + dir * (float(i) / n)
		Scan.place(make_root(post_p, yaw, 0.05), "modular_chainlink_fence", Transform3D(), "modular_chainlink_fence_post$", "none")
	Scan.place(make_root(b, yaw, 0.05), "modular_chainlink_fence", Transform3D(), "modular_chainlink_fence_post$", "none")


const TOWER_KIT := "apart"
const TOWER_UPPER := ["wall_window_centered_large_01", "wall_window_centered_double_01", "wall_window_centered_small_01",
	"wall_window_offset_small_01", "wall_window_centered_large_01", "wall_window_centered_double_01"]
const TOWER_GROUND := ["wall_door_window_small_01", "wall_window_centered_double_01", "wall_door_centered_small_01"]


func add_tower(p: Vector2, size: Vector3, yaw: float) -> void:
	if FacadeKit.available(TOWER_KIT):
		_add_kit_tower(p, size, yaw)
		return
	# Background set-dressing: tall gutted block, no collision.
	var root := make_root(p, yaw, 1.0)
	var mat := Mats.pbr("concrete_wall_008", Color(0.5, 0.48, 0.45), 0.12, "tower")
	var dark := Mats.pbr("concrete_floor_worn_001", Color(0.32, 0.31, 0.3), 0.15, "tower_dark")
	add_box(root, Transform3D(Basis(), Vector3(0, size.y / 2, 0)), size, mat, false)
	var floors := int(size.y / 3.5)
	for f in floors:
		var y := 2.0 + f * 3.5
		add_box(root, Transform3D(Basis(), Vector3(0, y, -size.z / 2 - 0.01)), Vector3(size.x * 0.86, 1.3, 0.05), Mats.glass(), false)
		add_box(root, Transform3D(Basis(), Vector3(0, y, size.z / 2 + 0.01)), Vector3(size.x * 0.86, 1.3, 0.05), Mats.glass(), false)
		add_box(root, Transform3D(Basis(), Vector3(-size.x / 2 - 0.01, y, 0)), Vector3(0.05, 1.3, size.z * 0.86), Mats.glass(), false)
		add_box(root, Transform3D(Basis(), Vector3(size.x / 2 + 0.01, y, 0)), Vector3(0.05, 1.3, size.z * 0.86), Mats.glass(), false)
		add_box(root, Transform3D(Basis(), Vector3(0, y + 1.1, 0)), Vector3(size.x + 0.3, 0.25, size.z + 0.3), dark, false)


## Background apartment block from the scanned facade kit: windows with glass,
## shops / doors on the ground floor, crown moulding on top, dark core behind.
func _add_kit_tower(p: Vector2, size: Vector3, yaw: float) -> void:
	var root := make_root(p, yaw, 1.0)
	var m := FacadeKit.MODULE
	var nx := maxi(2, int(round(size.x / m)))
	var nz := maxi(2, int(round(size.z / m)))
	var floors := maxi(3, int(round(size.y / m)))
	var w := nx * m
	var d := nz * m
	add_box(root, Transform3D(Basis(), Vector3(0, floors * m * 0.5, 0)), Vector3(w - 0.5, floors * m, d - 0.5), Mats.surface("tower_core", Color(0.04, 0.04, 0.045), 1.0, 0.0, 0.0), false)
	add_box(root, Transform3D(Basis(), Vector3(0, floors * m + 0.3, 0)), Vector3(w, 0.4, d), Mats.concrete_dark(), false)
	# [start corner, outward, module count] for the four faces.
	var faces := [
		[Vector3(-w / 2, 0, d / 2), Vector3.BACK, nx], [Vector3(w / 2, 0, -d / 2), Vector3.FORWARD, nx],
		[Vector3(w / 2, 0, d / 2), Vector3.RIGHT, nz], [Vector3(-w / 2, 0, -d / 2), Vector3.LEFT, nz],
	]
	var style := rng.randi_range(0, TOWER_UPPER.size() - 1)
	for f in faces:
		var outward: Vector3 = f[1]
		var kx := Vector3.UP.cross(outward)
		for i in int(f[2]):
			for fl in floors:
				var wall: String = TOWER_GROUND[(i + style) % TOWER_GROUND.size()] if fl == 0 else TOWER_UPPER[(style + (i % 2) * (1 if fl % 3 else 0)) % TOWER_UPPER.size()]
				var parts := FacadeKit.module(TOWER_KIT, wall, true)
				if parts.is_empty():
					parts = FacadeKit.module(TOWER_KIT, "wall_standard_standard_01", false)
				var origin: Vector3 = f[0] + kx * (i * m) + Vector3.UP * (fl * m)
				var xf := Transform3D(Basis(kx, Vector3.UP, outward), origin)
				for part in parts:
					batch(part[0], root.transform * xf * (part[1] as Transform3D))
			for part in FacadeKit.piece(TOWER_KIT, "crown_standard_standard_01"):
				var origin: Vector3 = f[0] + kx * (i * m) + Vector3.UP * (floors * m)
				batch(part[0], root.transform * Transform3D(Basis(kx, Vector3.UP, outward), origin) * (part[1] as Transform3D))
