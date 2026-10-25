extends MapBase
## "Col de Givre" — snowed-in mountain pass, abandoned ski station and fir forest.


func _init() -> void:
	map_seed = 23
	biome = "snow"
	layout_k = 1.45
	half = Vector2(82.0, 96.0)
	hill_amp = 30.0
	hill_var = 22.0


func env_params() -> Dictionary:
	return {
		"top": Color(0.5, 0.6, 0.72), "horizon": Color(0.86, 0.88, 0.91), "ground": Color(0.7, 0.72, 0.76),
		"cloud": Color(0.95, 0.96, 0.98), "cloud_shadow": Color(0.66, 0.7, 0.76), "cover": 0.68,
		"sun_color": Color(1.0, 0.9, 0.8), "sun_energy": 1.25, "sun_elev": 20.0, "sun_azim": 30.0,
		"fog_color": Color(0.82, 0.86, 0.92), "fog_density": 0.0028, "vol_density": 0.007,
		"saturation": 0.95, "contrast": 1.05, "exposure": 0.95,
		"hdri": "res://assets/polyhaven/hdri/snowy_park_01_2k.hdr", "hdri_energy": 0.9,
		"sun_dir": Vector3(0.94, 0.25, -0.32),
	}


func terrain_params() -> Dictionary:
	return {"snow_amount": 1.0, "rock_tint": Color(0.85, 0.88, 0.92), "dirt_amount": 0.3}


func terrain_layers() -> Dictionary:
	return {"rock": "rock_face_03"}


func grass_colors() -> Array:
	return [Color(0.35, 0.32, 0.24), Color(0.78, 0.72, 0.56)]


func grass_density() -> float:
	return 0.3


func grass_height() -> float:
	return 0.4


func grass_patchiness() -> float:
	return 0.15


func rock_tint() -> Color:
	return Color(0.48, 0.5, 0.53)


func layout_height(x: float, z: float) -> float:
	# A shallow frozen gully running diagonally through the middle.
	var xs := x / layout_k
	var zs := z / layout_k
	var d := absf(xs * 0.6 + zs * 0.8 - sin(xs * 0.07) * 6.0) * layout_k
	return -1.6 * exp(-d * d / 40.0) + 2.0 * exp(-pow(Vector2(xs, zs).distance_to(Vector2(-38, -10)), 2) / 300.0) \
		+ 2.0 * exp(-pow(Vector2(xs, zs).distance_to(Vector2(38, 10)), 2) / 300.0)


func loot_spots() -> Array:
	return mirrored_spots([
		Vector3(-9, 0, 6), Vector3(-9.5, 1, 5.0), Vector3(-36, 0, -32), Vector3(28, 0, -46),
		Vector3(23, 0, -11), Vector3(19, 0, -51), Vector3(-15, 0, -17), Vector3(4, 0, -21), Vector3(-34, 0, -14),
	])


func plan_layout() -> void:
	mirrored(Vector2(-9, 6), 0.0, func(p, y): plan_building(p, Vector2(9, 9), 2, y, 501))
	mirrored(Vector2(-36, -32), 0.0, func(p, y): plan_building(p, Vector2(9, 6), 1, y, 602))
	mirrored(Vector2(28, -46), 0.0, func(p, y): plan_building(p, Vector2(6, 6), 1, y, 703))
	plan_extra_buildings(4)


func build_layout() -> void:
	mirrored(Vector2(21, -14), 0.65, func(p, y): add_car(p, y, Color(0.75, 0.75, 0.73)))
	mirrored(Vector2(33, -25), 0.75, func(p, y): add_car(p, y, Color(0.42, 0.18, 0.15)))
	mirrored(Vector2(8, -30), 2.0, func(p, y): add_car(p, y, Color(0.3, 0.36, 0.42)))

	mirrored(Vector2(22, -54), 0.1, func(p, y): add_container(p, y, Color(0.5, 0.2, 0.15), true))
	mirrored(Vector2(-18, -20), 1.3, func(p, y): add_container(p, y, Color(0.45, 0.47, 0.48)))

	for b in [[Vector2(-7, -52), 0.1], [Vector2(6, -51), -0.15], [Vector2(-18, -48), -0.3], [Vector2(0, -18), 0.4], [Vector2(44, -36), 1.2]]:
		mirrored(b[0], b[1], add_barrier)

	for r in [[Vector2(-20, -40), 3.0], [Vector2(46, -14), 2.6], [Vector2(-50, -52), 3.2], [Vector2(2, -24), 1.6],
			[Vector2(-46, 0), 2.2], [Vector2(14, -62), 1.4], [Vector2(40, -60), 2.0]]:
		mirrored(r[0], rng.randf() * TAU, func(p, y): add_rock(p, r[1], y))

	var clusters := [[Vector2(-34, -14), 6], [Vector2(30, -36), 5], [Vector2(-48, 22), 5], [Vector2(12, -42), 3], [Vector2(-26, -56), 4]]
	for c in clusters:
		for i in c[1]:
			var p: Vector2 = c[0] + Vector2(rng.randf_range(-6, 6), rng.randf_range(-6, 6))
			var h := rng.randf_range(7.0, 12.0)
			mirrored(p, 0.0, func(q, _y): add_fir(q, h))

	for z in [-50.0, -25.0, 0.0]:
		mirrored(Vector2(-52, z), 0.0, add_pole)

	for c in [[Vector2(-2, -10), 0.4], [Vector2(14, -22), -0.6], [Vector2(-26, -24), 1.0], [Vector2(40, -40), 0.2], [Vector2(-8, -38), 1.9]]:
		mirrored(c[0], c[1], add_crate_stack)
	for l in [[Vector2(-15, -1), 0.2], [Vector2(12, -40), 1.4], [Vector2(-30, -50), 0.0]]:
		mirrored(l[0], l[1], add_lamp)

	for f in [[Vector2(-30, -60), Vector2(-20, -58)], [Vector2(14, -36), Vector2(24, -32)]]:
		add_fence(f[0] * layout_k, f[1] * layout_k)
		add_fence(-f[0] * layout_k, -f[1] * layout_k)
	for c in [Vector2(-18, -16), Vector2(22, -50), Vector2(30, -20)]:
		mirrored(c, 0.0, func(p, _y): scatter_clutter(p, 3.5, 3))

	# Bigger arena: extra cover and crates in the gaps (point-symmetric).
	fill_cover(20)

	_build_backdrop()


func _build_backdrop() -> void:
	add_tower(Vector2(-110, -135), Vector3(18, 22, 14), 0.4)
	add_tower(Vector2(125, 100), Vector3(14, 30, 14), -0.3)
	for i in 150:
		var p := Vector2(rng.randf_range(-185, 185), rng.randf_range(-185, 185))
		if absf(p.x) < half.x + 5 and absf(p.y) < half.y + 5:
			continue
		add_fir(p, rng.randf_range(8, 14))
	for i in 26:
		var p := Vector2(rng.randf_range(-180, 180), rng.randf_range(-180, 180))
		if absf(p.x) < half.x + 4 and absf(p.y) < half.y + 4:
			continue
		add_rock(p, rng.randf_range(3.0, 7.0), rng.randf() * TAU)


func make_weather() -> Node3D:
	return weather_particles(2600, Vector3(22, 10, 22), Vector3(0.8, -1.6, 0.3), Color(1, 1, 1, 0.85), 0.05, 8.0, 0.9)
