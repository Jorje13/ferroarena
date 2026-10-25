extends MapBase
## "Barrage d'Alcantara" — sun-baked Mediterranean ruins below a giant dam.


func _init() -> void:
	map_seed = 7
	biome = "dry"
	layout_k = 1.45
	half = Vector2(85.0, 98.0)


func env_params() -> Dictionary:
	return {
		"top": Color(0.29, 0.5, 0.8), "horizon": Color(0.8, 0.82, 0.82), "ground": Color(0.4, 0.37, 0.32),
		"cover": 0.42, "sun_color": Color(1.0, 0.91, 0.78), "sun_energy": 2.2, "sun_elev": 34.0,
		"sun_azim": 150.0, "fog_color": Color(0.76, 0.79, 0.82), "fog_density": 0.0014,
		"vol_density": 0.004, "saturation": 1.08, "contrast": 1.08, "bounce": Color(0.7, 0.6, 0.48),
		"hdri": "res://assets/polyhaven/hdri/kloofendal_48d_partly_cloudy_puresky_2k.hdr",
		"hdri_energy": 0.45, "exposure": 0.92, "sun_dir": Vector3(0.378, 0.74, -0.556),
	}


func terrain_params() -> Dictionary:
	return {
		"grass_tint": Color(0.82, 0.86, 0.7), "dirt_tint": Color(0.9, 0.84, 0.76),
		"rock_tint": Color(1.0, 0.95, 0.88), "dirt_amount": 0.8,
	}


func grass_colors() -> Array:
	return [Color(0.14, 0.18, 0.07), Color(0.55, 0.56, 0.32)]


func layout_height(x: float, z: float) -> float:
	# Two mirrored mounds for high ground on the flanks.
	var h := 0.0
	for c in [Vector2(-40, 40), Vector2(40, -40)]:
		var d := Vector2(x, z).distance_to(c * layout_k)
		h += 3.2 * exp(-d * d / (2.0 * 14.0 * 14.0))
	return h


func loot_spots() -> Array:
	return mirrored_spots([
		Vector3(3.5, 0, -1.5), Vector3(4.0, 1, -2.5), Vector3(-33, 0, -16), Vector3(-9.0, 0, -27.0),
		Vector3(42.0, 0, -46.0), Vector3(27, 0, -40), Vector3(-42, 0, 22), Vector3(-41.5, 1, 21.0),
		Vector3(14.0, 0, -24.0),
	])


## Buildings are planned first so the ground can be levelled under them.
func plan_layout() -> void:
	# Centre: two-storey gutted building (high ground, contested).
	plan_building(Vector2.ZERO, Vector2(15, 9), 2, 0.0, 101)
	mirrored(Vector2(-33, -16), 0.0, func(p, y): plan_building(p, Vector2(9, 6), 1, y, 202))
	mirrored(Vector2(27, -40), 0.0, func(p, y): plan_building(p, Vector2(6, 6), 1, y, 303))
	mirrored(Vector2(-42, 22), PI / 2, func(p, y): plan_building(p, Vector2(9, 6), 2, y, 404))
	plan_extra_buildings(4)


func build_layout() -> void:

	mirrored(Vector2(-12, -30), 0.35, func(p, y): add_container(p, y, Color(0.55, 0.22, 0.16), true))
	mirrored(Vector2(-3, -37), -1.2, func(p, y): add_container(p, y, Color(0.2, 0.38, 0.4)))
	mirrored(Vector2(45, -50), 1.57, func(p, y): add_container(p, y, Color(0.62, 0.48, 0.2)))

	mirrored(Vector2(11, -20), 1.1, func(p, y): add_car(p, y, Color(0.55, 0.52, 0.46)))
	mirrored(Vector2(-24, -43), 0.4, func(p, y): add_car(p, y, Color(0.32, 0.38, 0.42)))
	mirrored(Vector2(43, -8), 2.3, func(p, y): add_car(p, y, Color(0.6, 0.3, 0.22)))
	mirrored(Vector2(19, -7), -0.5, func(p, y): add_car(p, y, Color(0.75, 0.73, 0.68)))

	for b in [[Vector2(-7, -53), 0.1], [Vector2(6, -52), -0.15], [Vector2(17, -49), 0.3],
			[Vector2(-19, -50), -0.4], [Vector2(-7, -14), 0.0], [Vector2(5, -11.5), 0.25], [Vector2(32, -30), 1.4]]:
		mirrored(b[0], b[1], add_barrier)

	for r in [[Vector2(-46, -52), 2.2], [Vector2(15, -58), 1.5], [Vector2(-22, -9), 1.8], [Vector2(49, -31), 2.6],
			[Vector2(31, -25), 1.2], [Vector2(-52, -18), 2.0], [Vector2(-8, -24), 1.1], [Vector2(-30, -58), 1.7]]:
		mirrored(r[0], rng.randf() * TAU, func(p, y): add_rock(p, r[1], y))

	for t in [[Vector2(-28, -30), 9.0], [Vector2(-30, -33.5), 7.5], [Vector2(34, -52), 10.0],
			[Vector2(-9, -45), 8.0], [Vector2(53, -60), 9.0], [Vector2(-50, 4), 8.5]]:
		mirrored(t[0], 0.0, func(p, _y): add_cypress(p, t[1]))
	for t in [[Vector2(40, -37), 9.0], [Vector2(-48, -37), 10.0], [Vector2(-21, -62), 8.0], [Vector2(22, -24), 7.0]]:
		mirrored(t[0], 0.0, func(p, _y): add_pine(p, t[1]))

	for i in 16:
		var p := Vector2(rng.randf_range(-55, 55), rng.randf_range(-60, -6))
		if absf(p.x) < 13 and p.y < -56:
			continue
		var s := rng.randf_range(0.5, 1.0)
		mirrored(p, 0.0, func(q, _y): add_bush(q, s))

	for z in [-60.0, -40.0, -20.0]:
		mirrored(Vector2(-55, z), 0.0, add_pole)

	# Supply-crate stacks: low cover in the open lanes.
	for c in [[Vector2(-8, -19), 0.3], [Vector2(30, -19), -0.8], [Vector2(-20, -36), 1.2], [Vector2(8, -44), 0.1], [Vector2(36, -12), 2.0]]:
		mirrored(c[0], c[1], add_crate_stack)
	for l in [[Vector2(-16, -6), 0.0], [Vector2(16, -31), 1.57], [Vector2(-31, -41), 0.6]]:
		mirrored(l[0], l[1], add_lamp)

	for f in [[Vector2(-40, -45), Vector2(-28, -47)], [Vector2(36, -60), Vector2(48, -56)], [Vector2(-15, -24), Vector2(-15, -16)]]:
		add_fence(f[0] * layout_k, f[1] * layout_k)
		add_fence(-f[0] * layout_k, -f[1] * layout_k)
	for c in [Vector2(-12, -27), Vector2(45, -46), Vector2(12, -24)]:
		mirrored(c, 0.0, func(p, _y): scatter_clutter(p, 3.5, 3))

	# Bigger arena: extra cover and crates in the gaps (point-symmetric).
	fill_cover(20)

	_build_backdrop()


func _build_backdrop() -> void:
	# The dam: huge concrete wall closing the north valley.
	var dam := Node3D.new()
	props_root.add_child(dam)
	dam.position = Vector3(0, -6, -172)
	var mat := Mats.concrete()
	var dark := Mats.concrete_dark()
	add_box(dam, Transform3D(Basis(Vector3.RIGHT, 0.12), Vector3(0, 30, 0)), Vector3(300, 70, 14), mat, false)
	add_box(dam, Transform3D(Basis(), Vector3(0, 65.5, 4)), Vector3(300, 2, 8), dark, false)
	for i in 13:
		var x := -144.0 + i * 24.0
		add_box(dam, Transform3D(Basis(Vector3.RIGHT, 0.12), Vector3(x, 30, 8)), Vector3(4, 70, 5), dark, false)
	for i in 4:
		var x := -30.0 + i * 20.0
		add_box(dam, Transform3D(Basis(Vector3.RIGHT, 0.12), Vector3(x, 10, 7.5)), Vector3(9, 14, 2), Mats.rust(), false)

	add_tower(Vector2(125, 125), Vector3(16, 46, 14), 0.3)
	add_tower(Vector2(-135, 105), Vector3(14, 34, 14), -0.2)
	add_tower(Vector2(70, 165), Vector3(22, 62, 18), 0.1)
	add_tower(Vector2(-75, 150), Vector3(12, 28, 12), 0.5)

	for i in 100:
		var p := Vector2(rng.randf_range(-180, 180), rng.randf_range(-150, 180))
		if absf(p.x) < half.x + 6 and absf(p.y) < half.y + 6:
			continue
		if rng.randf() < 0.5:
			add_cypress(p, rng.randf_range(8, 13))
		else:
			add_pine(p, rng.randf_range(8, 12))
	for i in 32:
		var p := Vector2(rng.randf_range(-175, 175), rng.randf_range(-150, 175))
		if absf(p.x) < half.x + 4 and absf(p.y) < half.y + 4:
			continue
		add_rock(p, rng.randf_range(2.5, 6.0), rng.randf() * TAU)


func make_weather() -> Node3D:
	return weather_particles(220, Vector3(18, 6, 18), Vector3(0.6, 0.05, 0.2), Color(1, 0.95, 0.85, 0.35), 0.035, 9.0, 0.6)
