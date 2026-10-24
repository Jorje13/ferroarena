class_name Mats
## Cached procedural materials (noise textures, world-space triplanar).

static var _cache := {}


static func noise_tex(seed: int, freq: float, normal := false, size := 512, ramp: Gradient = null, bump := 6.0, octaves := 5) -> NoiseTexture2D:
	var key := "nt_%d_%f_%s_%d_%s_%f_%d" % [seed, freq, normal, size, ramp != null, bump, octaves]
	if ramp == null and _cache.has(key):
		return _cache[key]
	var n := FastNoiseLite.new()
	n.seed = seed
	n.frequency = freq
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	n.fractal_octaves = octaves
	var t := NoiseTexture2D.new()
	t.width = size
	t.height = size
	t.seamless = true
	t.noise = n
	t.as_normal_map = normal
	t.bump_strength = bump
	if ramp:
		t.color_ramp = ramp
	else:
		_cache[key] = t
	return t


static func _ramp(a: float, b: float) -> Gradient:
	var g := Gradient.new()
	g.set_color(0, Color(a, a, a))
	g.set_color(1, Color(b, b, b))
	return g


static func surface(id: String, color: Color, roughness := 0.9, metallic := 0.0, scale := 0.35, var_lo := 0.7, var_hi := 1.0, bump := 5.0) -> StandardMaterial3D:
	if _cache.has(id):
		return _cache[id]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.albedo_texture = noise_tex(id.hash() & 0xffff, 0.012, false, 512, _ramp(var_lo, var_hi))
	m.roughness = roughness
	m.metallic = metallic
	m.normal_enabled = true
	m.normal_texture = noise_tex((id.hash() >> 3) & 0xffff, 0.03, true, 512, null, bump)
	m.normal_scale = 0.8
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE * scale
	m.uv1_triplanar_sharpness = 4.0
	m.metallic_specular = 0.3
	_cache[id] = m
	return m


static func flat(id: String, color: Color, roughness := 0.8, metallic := 0.0) -> StandardMaterial3D:
	if _cache.has(id):
		return _cache[id]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.metallic = metallic
	_cache[id] = m
	return m


static func emissive(id: String, color: Color, energy := 4.0, unshaded := true) -> StandardMaterial3D:
	if _cache.has(id):
		return _cache[id]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_cache[id] = m
	return m


# ---------------------------------------------------------------- presets

const PH_TEX := "res://assets/polyhaven/textures/"


## Poly Haven PBR set (diffuse / GL normal / roughness 2k), world triplanar.
## `scale` = texture repeats per metre.
static func pbr(tex_id: String, tint := Color.WHITE, scale := 0.4, key := "") -> StandardMaterial3D:
	var cache_key := "pbr_%s_%s_%s" % [tex_id, tint.to_html(), key]
	if _cache.has(cache_key):
		return _cache[cache_key]
	var base := PH_TEX + tex_id + "/" + tex_id
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(base + "_diff_2k.jpg")
	m.albedo_color = tint
	m.normal_enabled = true
	m.normal_texture = load(base + "_nor_gl_2k.jpg")
	m.roughness_texture = load(base + "_rough_2k.jpg")
	m.roughness = 1.0
	m.metallic_specular = 0.35
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE * scale
	m.uv1_triplanar_sharpness = 6.0
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_cache[cache_key] = m
	return m


## Object-space triplanar variant of `surface` for things that move (weapon, gear):
## world triplanar would make the texture swim.
static func local_surface(id: String, color: Color, roughness: float, metallic: float, scale: Vector3, var_lo: float, var_hi: float, bump: float, freq := 0.012) -> StandardMaterial3D:
	if _cache.has("ls_" + id):
		return _cache["ls_" + id]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.albedo_texture = noise_tex(id.hash() & 0xffff, freq, false, 512, _ramp(var_lo, var_hi))
	m.roughness = roughness
	m.metallic = metallic
	m.normal_enabled = true
	m.normal_texture = noise_tex((id.hash() >> 3) & 0xffff, 0.03, true, 512, null, bump)
	m.normal_scale = 0.6
	m.uv1_triplanar = true
	m.uv1_scale = scale
	m.uv1_triplanar_sharpness = 6.0
	_cache["ls_" + id] = m
	return m


## Blued steel: scanned metal plate (Poly Haven) darkened, object-space.
static func gun_metal() -> StandardMaterial3D:
	if _cache.has("gunmetal3"):
		return _cache["gunmetal3"]
	var m := local_surface("gunmetal4", Color(0.2, 0.2, 0.21), 0.38, 0.88, Vector3.ONE * 6.0, 0.62, 1.0, 1.2)
	m.roughness_texture = noise_tex(4243, 0.025, false, 256, _ramp(0.55, 1.0))
	m.metallic_specular = 0.5
	_cache["gunmetal3"] = m
	return m


static func gun_metal_dark() -> StandardMaterial3D:
	if _cache.has("gunmetal_dark3"):
		return _cache["gunmetal_dark3"]
	var m := local_surface("gunmetal_dark4", Color(0.08, 0.08, 0.085), 0.5, 0.75, Vector3.ONE * 6.0, 0.7, 1.0, 1.0)
	_cache["gunmetal_dark3"] = m
	return m


## Walnut stock: scanned fine-grained wood, grain stretched along the gun (Z), light varnish.
static func gun_wood() -> StandardMaterial3D:
	if _cache.has("gun_wood3"):
		return _cache["gun_wood3"]
	var m := pbr_local("fine_grained_wood", Color(0.62, 0.38, 0.22), 1.0, "gunwood").duplicate() as StandardMaterial3D
	m.uv1_scale = Vector3(7.0, 7.0, 1.6)
	m.clearcoat_enabled = true
	m.clearcoat = 0.25
	m.clearcoat_roughness = 0.4
	_cache["gun_wood3"] = m
	return m

static func rubber() -> StandardMaterial3D:
	return local_surface("rubber", Color(0.06, 0.06, 0.06), 0.85, 0.0, Vector3.ONE * 8.0, 0.8, 1.0, 2.0)


static func canvas(id: String, color: Color) -> StandardMaterial3D:
	return local_surface("canvas_" + id, color, 0.95, 0.0, Vector3.ONE * 9.0, 0.72, 1.05, 3.5, 0.03)


## Painted plate with chipped edges look (noise-driven roughness/brightness).
static func painted_plate(id: String, color: Color) -> StandardMaterial3D:
	var m := local_surface("plate_" + id, color, 0.6, 0.15, Vector3.ONE * 4.0, 0.78, 1.02, 1.5, 0.02)
	m.roughness_texture = noise_tex(id.hash() & 0xfff, 0.04, false, 256, _ramp(0.5, 1.0))
	return m


## Object-space (local) triplanar PBR set, for props/gear that move or rotate.
static func pbr_local(tex_id: String, tint := Color.WHITE, scale := 1.0, key := "") -> StandardMaterial3D:
	var cache_key := "pbrl_%s_%s_%s_%f" % [tex_id, tint.to_html(), key, scale]
	if _cache.has(cache_key):
		return _cache[cache_key]
	var m := pbr(tex_id, tint, scale, "local_" + key + str(scale)).duplicate() as StandardMaterial3D
	m.uv1_world_triplanar = false
	_cache[cache_key] = m
	return m


## Painted armour with a pattern (customisation):
## 0 plain, 1 worn (bare metal patches), 2 camo, 3 digital camo, 4 hazard stripes.
static func armor(color: Color, pattern: int) -> StandardMaterial3D:
	var key := "armor_%s_%d" % [color.to_html(), pattern]
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.roughness = 0.55
	m.metallic = 0.15
	m.metallic_specular = 0.45
	m.uv1_triplanar = true
	m.uv1_triplanar_sharpness = 5.0
	m.normal_enabled = true
	m.normal_texture = noise_tex(5150, 0.012, true, 256, null, 1.0, 2)
	m.normal_scale = 0.12
	m.roughness_texture = noise_tex(5151, 0.04, false, 256, _ramp(0.55, 1.0))
	var g := Gradient.new()
	g.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	match pattern:
		1: # worn: paint with chipped bare-metal islands
			g.offsets = PackedFloat32Array([0.0, 0.8])
			g.colors = PackedColorArray([color, Color(0.42, 0.41, 0.4)])
			m.albedo_texture = noise_tex(5160 + color.to_rgba32() % 97, 0.06, false, 256, g, 6.0, 3)
			m.uv1_scale = Vector3.ONE * 7.0
		2: # camo
			g.offsets = PackedFloat32Array([0.0, 0.42, 0.6])
			g.colors = PackedColorArray([color, color.darkened(0.45), color.lightened(0.25).lerp(Color(0.45, 0.48, 0.32), 0.4)])
			m.albedo_texture = noise_tex(5170, 0.03, false, 256, g, 6.0, 2)
			m.uv1_scale = Vector3.ONE * 2.2
		3: # digital: blocky, nearest filtering
			g.offsets = PackedFloat32Array([0.0, 0.4, 0.62])
			g.colors = PackedColorArray([color, color.darkened(0.5), color.lightened(0.3)])
			var t := noise_tex(5180, 0.06, false, 32, g, 6.0, 2)
			m.albedo_texture = t
			m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
			m.uv1_scale = Vector3.ONE * 4.0
		4: # hazard stripes
			var img := Image.create(64, 64, false, Image.FORMAT_RGB8)
			for y in 64:
				for x in 64:
					img.set_pixel(x, y, color if ((x + y) / 16) % 2 == 0 else Color(0.08, 0.08, 0.08))
			img.generate_mipmaps()
			m.albedo_texture = ImageTexture.create_from_image(img)
			m.uv1_scale = Vector3.ONE * 4.0
		_:
			m.albedo_texture = noise_tex(5190, 0.03, false, 256, _ramp(0.82, 1.02))
			m.albedo_color = color
			m.uv1_scale = Vector3.ONE * 3.0
	_cache[key] = m
	return m


static func concrete() -> StandardMaterial3D:
	return pbr("concrete_wall_008", Color(0.78, 0.75, 0.7), 0.2)


static func concrete_dark() -> StandardMaterial3D:
	return pbr("concrete_floor_worn_001", Color(0.7, 0.68, 0.65), 0.25)


static func concrete_rough() -> StandardMaterial3D:
	return pbr("rough_concrete", Color(0.95, 0.93, 0.9), 0.35)


# ---------------------------------------------------------------- foliage cards

static var _leaf_tex: ImageTexture


## Procedural leaf-cluster texture (white, alpha-scissored): tinted per material.
static func leaf_texture() -> Texture2D:
	if _leaf_tex:
		return _leaf_tex
	var n := 256
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var r := RandomNumberGenerator.new()
	r.seed = 99
	var center := Vector2(n, n) * 0.5
	for i in 520:
		var c := Vector2(r.randf_range(8, n - 8), r.randf_range(8, n - 8))
		if c.distance_to(center) > n * 0.47 * r.randf_range(0.75, 1.0):
			continue
		var length := r.randf_range(5.0, 11.0)
		var w := length * 0.42
		var ang := r.randf() * TAU
		var dir := Vector2(cos(ang), sin(ang))
		var ortho := dir.orthogonal()
		var shade := r.randf_range(0.6, 1.0)
		var col := Color(shade, shade * r.randf_range(0.95, 1.05), shade * 0.9, 1.0)
		for y in range(maxi(int(c.y - length), 0), mini(int(c.y + length) + 1, n)):
			for x in range(maxi(int(c.x - length), 0), mini(int(c.x + length) + 1, n)):
				var d := Vector2(x, y) - c
				var u := d.dot(dir) / length
				var v := d.dot(ortho) / w
				if u * u + v * v <= 1.0:
					img.set_pixel(x, y, col)
	img.generate_mipmaps()
	_leaf_tex = ImageTexture.create_from_image(img)
	return _leaf_tex


static func leaves(id: String, color: Color) -> StandardMaterial3D:
	if _cache.has("leaves_" + id):
		return _cache["leaves_" + id]
	var m := StandardMaterial3D.new()
	m.albedo_texture = leaf_texture()
	m.albedo_color = color
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.5
	m.alpha_antialiasing_mode = BaseMaterial3D.ALPHA_ANTIALIASING_ALPHA_TO_COVERAGE
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.9
	m.metallic_specular = 0.25
	m.backlight_enabled = true
	m.backlight = Color(color.r * 0.6, color.g * 0.7, color.b * 0.4)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_cache["leaves_" + id] = m
	return m


## Cloud of camera-agnostic leaf cards inside an ellipsoid; normals point
## outwards so the canopy shades as one soft volume.
static func canopy_mesh(seed: int, radii: Vector3, cards: int, card_size: float) -> ArrayMesh:
	var key := "canopy_%d_%s_%d_%f" % [seed, radii, cards, card_size]
	if _cache.has(key):
		return _cache[key]
	var r := RandomNumberGenerator.new()
	r.seed = seed
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in cards:
		var p := Vector3(r.randf_range(-1, 1), r.randf_range(-1, 1), r.randf_range(-1, 1))
		while p.length() > 1.0:
			p = Vector3(r.randf_range(-1, 1), r.randf_range(-1, 1), r.randf_range(-1, 1))
		p = p.normalized() * pow(p.length(), 0.5)
		var pos := p * radii
		var normal := (p + Vector3(0, 0.35, 0)).normalized()
		var axis := Vector3(r.randf_range(-1, 1), r.randf_range(-1, 1), r.randf_range(-1, 1)).normalized()
		var right := axis.cross(Vector3.UP if absf(axis.y) < 0.9 else Vector3.RIGHT).normalized()
		var up := axis.cross(right).normalized()
		var s := card_size * r.randf_range(0.75, 1.25)
		var corners := [pos - right * s - up * s, pos + right * s - up * s, pos + right * s + up * s, pos - right * s + up * s]
		var uvs := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
		var shade := r.randf_range(0.75, 1.0)
		for idx in [0, 1, 2, 0, 2, 3]:
			st.set_normal(normal)
			st.set_color(Color(shade, shade, shade))
			st.set_uv(uvs[idx])
			st.add_vertex(corners[idx])
	var mesh := st.commit()
	_cache[key] = mesh
	return mesh


static func rust() -> StandardMaterial3D:
	return pbr("rust_coarse_01", Color(0.95, 0.9, 0.85), 0.5)


static func paint(id: String, color: Color) -> StandardMaterial3D:
	return surface("paint_" + id, color, 0.75, 0.25, 0.4, 0.55, 1.0, 4.0)


static func rock(tint: Color) -> StandardMaterial3D:
	return pbr("rock_face_03", tint * 1.7, 0.3)


static func bark() -> StandardMaterial3D:
	return surface("bark", Color(0.27, 0.2, 0.15), 0.95, 0.0, 1.2, 0.5, 1.0, 9.0)


static func foliage(id: String, color: Color) -> StandardMaterial3D:
	if _cache.has("fol_" + id):
		return _cache["fol_" + id]
	var m := surface("fol_" + id, color, 1.0, 0.0, 0.9, 0.5, 1.1, 12.0)
	m.backlight_enabled = true
	m.backlight = Color(0.12, 0.16, 0.05)
	return m


static func glass() -> StandardMaterial3D:
	return flat("glass", Color(0.05, 0.07, 0.08), 0.15, 0.6)


static func tire() -> StandardMaterial3D:
	return flat("tire", Color(0.06, 0.06, 0.06), 0.95)


static func cloth(id: String, color: Color) -> StandardMaterial3D:
	return surface("cloth_" + id, color, 0.92, 0.0, 2.5, 0.8, 1.0, 3.0)


## Corrugated metal (shipping containers), tinted with the paint colour.
static func corrugated(id: String, color: Color) -> StandardMaterial3D:
	var m := pbr("container_side", color * 2.2, 0.16, id)
	m.metallic = 0.3
	return m
