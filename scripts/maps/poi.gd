class_name Poi
## Points of interest: hand-built little places that give the map landmarks and stories.
## Each is planned like a building (a flat pad the random cover keeps off, its own buildings
## with chosen furniture and surveillance cameras), placed point-symmetric like everything else
## (fair for both teams), turned to face the middle of the map. Local frame: -Z is the front.
##
## Kinds: "gas" (gas station: canopy, pump islands, price sign, shop with its counter),
## "scrap" (scrapyard: fenced yard, stacked wrecks, tyres, crane, office),
## "flats" (derelict flats: two gutted two-storey blocks round a yard full of rubble).
##
## Placeholders (simple boxes, to be replaced by real models): fuel pumps, price sign, crane,
## dumpster. See PLACEHOLDERS.

const PLACEHOLDERS := ["pompe à essence", "totem de prix carburant", "grue de casse à grappin", "benne à ordures"]
## Half extents of each kind's pad (m, before turning).
const SIZE := {"gas": Vector2(14, 12), "scrap": Vector2(14, 12), "flats": Vector2(15, 11)}

const RUBBLE := "res://assets/props/rubble.glb"
const CAR_STACK := "res://assets/props/car_stack.glb"
const SNACK_AISLE := "res://assets/props/snack_aisle.glb"
const GARAGE_SHELF := "res://assets/props/garage_shelf.glb"
const TOOL_CABINET := "res://assets/props/tool_cabinet.glb"


## Plans the first candidate spot (authored coordinates, spread by layout_k) where the pad and
## its mirror image fit. Returns false if none did.
static func plan(m: MapBase, kind: String, candidates: Array) -> bool:
	var hs: Vector2 = SIZE[kind]
	for c: Vector2 in candidates:
		var p := c * m.layout_k
		var yaw := roundf(atan2(p.x, p.y) / (PI * 0.5)) * PI * 0.5
		var wh := hs if posmod(roundi(yaw / (PI * 0.5)), 2) == 0 else Vector2(hs.y, hs.x)
		if absf(p.x) + wh.x > m.half.x - 3.0 or absf(p.y) + wh.y > m.half.y - 8.0:
			continue
		if absf(p.x) < wh.x + 10.0 and absf(p.y) + wh.y > m.half.y - 14.0:
			continue # the spawn lines
		if not m._pad_free(p, maxf(wh.x, wh.y) * 0.5 + 3.0) or not m._pad_free(-p, maxf(wh.x, wh.y) * 0.5 + 3.0):
			continue
		for side in 2:
			var q := p if side == 0 else -p
			var y := yaw + side * PI
			var level := m._ground_avg(q, wh)
			m._pads.append({"c": q, "h": wh, "y": level})
			var poi := {"kind": kind, "c": q, "yaw": y, "y": level, "seed": m.map_seed * 31 + m.pois.size()}
			m.pois.append(poi)
			_plan_buildings(m, poi)
		if Game.debug.has("log_poi"):
			print("[POI] %s en %s (orientation %d°)" % [kind, str(p.round()), roundi(rad_to_deg(yaw))])
		return true
	if Game.debug.has("log_poi"):
		print("[POI] %s : aucun emplacement libre" % kind)
	return false


## World position of a point in a POI's frame (x right, y = -front .. +back).
static func _w(poi: Dictionary, local: Vector2) -> Vector2:
	return (poi.c as Vector2) + local.rotated(-float(poi.yaw))


static func _plan_buildings(m: MapBase, poi: Dictionary) -> void:
	var y: float = poi.yaw
	match poi.kind:
		"gas":
			m.plan_building(_w(poi, Vector2(0, 7)), Vector2(12, 6), 1, y, poi.seed, null, true,
				{"y": poi.y, "furniture": ["counter", "fridge", "fridge", "electric_panel"], "random_furniture": false, "cctv": true})
		"scrap":
			m.plan_building(_w(poi, Vector2(9, 7)), Vector2(6, 6), 1, y, poi.seed, null, true,
				{"y": poi.y, "furniture": ["tool_bench", "garage_shelf", "tool_cabinet", "lockers"], "random_furniture": false, "cctv": true})
		"flats":
			for sx in [-1.0, 1.0]:
				m.plan_building(_w(poi, Vector2(sx * 7.5, 3)), Vector2(12, 9), 2, y + (PI * 0.5 if sx < 0 else -PI * 0.5), poi.seed + int(sx), null, true,
					{"y": poi.y, "furniture": ["bed", "couch", "toilet", "fridge"], "cctv": sx > 0})


## Everything but the buildings (built with the others), once the terrain exists.
static func build(m: MapBase, poi: Dictionary) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = int(poi.seed)
	var root := Node3D.new()
	m.props_root.add_child(root)
	root.position = Vector3((poi.c as Vector2).x, float(poi.y), (poi.c as Vector2).y)
	root.rotation.y = poi.yaw
	m._ignore_pads = true
	match poi.kind:
		"gas":
			_gas(m, root, r)
		"scrap":
			_scrap(m, root, r)
		"flats":
			_flats(m, root, r)
	m._ignore_pads = false
	var hs: Vector2 = SIZE[poi.kind]
	var c: Vector2 = poi.c
	m.no_grass.append(Rect2(c - Vector2(hs.x, hs.x), Vector2(hs.x, hs.x) * 2.0))


## Local point -> world 2D (for the MapBase helpers that take ground positions).
static func _g(root: Node3D, x: float, z: float) -> Vector2:
	var p := root.transform * Vector3(x, 0, z)
	return Vector2(p.x, p.z)


static func _place(root: Node3D, scene: String, x: float, z: float, yaw: float, scale: float, collider := "box", y := 0.0) -> Node3D:
	return Scan.place(root, scene, Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * scale), Vector3(x, y, z)), "", collider)


# ---------------------------------------------------------------- gas station

static func _gas(m: MapBase, root: Node3D, r: RandomNumberGenerator) -> void:
	var white := Mats.flat("gas_canopy", Color(0.5, 0.5, 0.48), 0.75, 0.1)
	var red := Mats.flat("gas_red", Color(0.62, 0.1, 0.08), 0.6, 0.1)
	var strip := Mats.emissive("gas_strip", Color(0.9, 0.2, 0.15), 0.5, false)
	var dark := Mats.concrete_dark()
	# Forecourt slab and the canopy over the pumps (14 x 9 m, 4.8 m clear).
	m.add_box(root, Transform3D(Basis(), Vector3(0, -0.12, -4)), Vector3(22, 0.3, 14), Mats.concrete_dark())
	for px in [-6.0, 6.0]:
		for pz in [-8.0, -1.5]:
			m.add_box(root, Transform3D(Basis(), Vector3(px, 2.4, pz)), Vector3(0.45, 4.8, 0.45), white)
	m.add_box(root, Transform3D(Basis(), Vector3(0, 5.05, -4.75)), Vector3(15, 0.5, 9.5), white)
	for e in [[Vector3(0, 5.05, -9.52), Vector3(15, 0.42, 0.06)], [Vector3(0, 5.05, 0.02), Vector3(15, 0.42, 0.06)],
			[Vector3(-7.52, 5.05, -4.75), Vector3(0.06, 0.42, 9.5)], [Vector3(7.52, 5.05, -4.75), Vector3(0.06, 0.42, 9.5)]]:
		m.add_box(root, Transform3D(Basis(), e[0]), e[1], strip, false)
	# Under-canopy lights.
	for lx in [-3.5, 3.5]:
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.92, 0.82)
		l.light_energy = 1.4
		l.omni_range = 9.0
		l.position = Vector3(lx, 4.6, -4.75)
		root.add_child(l)
	# Two pump islands, two pumps each (placeholders: "pompe à essence").
	for ix in [-3.2, 3.2]:
		m.add_box(root, Transform3D(Basis(), Vector3(ix, 0.12, -4.75)), Vector3(1.3, 0.24, 5.2), dark)
		for iz in [-6.3, -3.2]:
			_pump(m, root, Vector3(ix, 0.24, iz), red, white)
		_place(root, "metal_jerrycan", ix + 0.9, -4.6, r.randf() * TAU, 1.0, "none")
	# An abandoned car still at the pump.
	m.add_car(_g(root, -5.6, -4.0), root.rotation.y + PI * 0.5 + r.randf_range(-0.1, 0.1), Color(0.5, 0.45, 0.4))
	# Price sign by the road (placeholder: "totem de prix carburant").
	var sx := 10.5
	m.add_box(root, Transform3D(Basis(), Vector3(sx, 3.0, -10.5)), Vector3(0.35, 6.0, 0.35), dark)
	m.add_box(root, Transform3D(Basis(), Vector3(sx, 5.6, -10.5)), Vector3(2.0, 2.4, 0.3), red)
	for k in 3:
		m.add_box(root, Transform3D(Basis(), Vector3(sx, 6.2 - k * 0.6, -10.67)), Vector3(1.5, 0.35, 0.02), Mats.emissive("gas_digits", Color(1.0, 0.75, 0.25), 2.0, false), false)
	# Shop aisles: two snack racks back to back down the middle of the shop.
	for ax in [-2.4, 2.4]:
		_place(root, SNACK_AISLE, ax, 7.0, 0.0, 1.0)
		_place(root, SNACK_AISLE, ax, 7.45, PI, 1.0)
	# Gas bottles cage and drums by the shop, rubble where the lot has crumbled.
	for k in 3:
		_place(root, "propane_tank", -8.5 + k * 0.55, 3.2, r.randf() * TAU, 1.0, "box")
	_place(root, "Barrel_01", 8.5, 3.0, 0.0, 1.0)
	_place(root, "Barrel_01", 9.1, 3.3, 0.6, 1.0)
	_place(root, RUBBLE, -10.5, -9.5, r.randf() * TAU, 1.6, "convex")
	# Camera watching the pumps from a canopy pillar.
	m.add_cctv(root, Vector3(6.0, 0.0, -8.0), Vector3(0, 0, -1), 1.0, 3.8)


static func _pump(m: MapBase, root: Node3D, at: Vector3, body: Material, trim: Material) -> void:
	m.add_box(root, Transform3D(Basis(), at + Vector3(0, 0.9, 0)), Vector3(0.75, 1.8, 0.5), body)
	m.add_box(root, Transform3D(Basis(), at + Vector3(0, 1.95, 0)), Vector3(0.85, 0.3, 0.6), trim)
	for side in [-1.0, 1.0]:
		m.add_box(root, Transform3D(Basis(), at + Vector3(side * 0.38, 1.35, 0)), Vector3(0.02, 0.4, 0.34), Mats.emissive("pump_screen", Color(0.4, 0.9, 1.0), 1.2, false), false)
		m.add_box(root, Transform3D(Basis(), at + Vector3(side * 0.42, 0.9, 0.12)), Vector3(0.06, 0.25, 0.08), Mats.rubber(), false)


# ---------------------------------------------------------------- scrapyard

static func _scrap(m: MapBase, root: Node3D, r: RandomNumberGenerator) -> void:
	var yard := Vector2(13, 11)
	# Fence all round, with a gate gap in the front.
	var corners := [Vector2(-yard.x, -yard.y), Vector2(yard.x, -yard.y), Vector2(yard.x, yard.y), Vector2(-yard.x, yard.y)]
	for i in 4:
		var a: Vector2 = corners[i]
		var b: Vector2 = corners[(i + 1) % 4]
		if i == 0:
			m.add_fence(_g(root, a.x, a.y), _g(root, -2.5, a.y))
			m.add_fence(_g(root, 2.5, a.y), _g(root, b.x, b.y))
		else:
			m.add_fence(_g(root, a.x, a.y), _g(root, b.x, b.y))
	# Stacked wrecks along the back and the left side, loose ones in the yard.
	var stacks := [Vector3(-8.5, 0, 8.0), Vector3(-3.0, 0, 8.6), Vector3(-10.0, 0, 2.0), Vector3(-10.2, 0, -4.5), Vector3(5.5, 0, 3.0)]
	for s in stacks:
		_place(root, CAR_STACK, s.x, s.z, r.randf_range(-0.25, 0.25) + (PI * 0.5 if s.x < -9.0 else 0.0), 2.4)
	for k in 3:
		m.add_car(_g(root, r.randf_range(-4.0, 6.0), r.randf_range(-6.0, 2.5)), root.rotation.y + r.randf() * TAU, Color(0.4, 0.33, 0.28))
	# Tyre piles and rims.
	var tyre := "old_tyre"
	for pile in [Vector2(6.5, -7.5), Vector2(-5.5, -8.0), Vector2(9.5, 1.0)]:
		for k in r.randi_range(3, 6):
			_place(root, tyre, pile.x + r.randf_range(-0.25, 0.25), pile.y + r.randf_range(-0.25, 0.25), r.randf() * TAU, 1.0, "none", 0.08 + k * 0.2).rotate_object_local(Vector3.RIGHT, PI * 0.5)
		m.add_cylinder_collider(root, Vector3(pile.x, 0.6, pile.y), 0.45, 1.2)
	_place(root, "rusted_wheel_rim_01", 7.4, -6.2, 0.3, 1.0, "none")
	_place(root, RUBBLE, 0.5, 4.5, r.randf() * TAU, 2.0, "convex")
	m.add_container(_g(root, 9.0, -2.5), root.rotation.y + PI * 0.5, Color(0.42, 0.25, 0.18))
	# Open-air workshop by the office: shelves of parts and a tool chest against the fence.
	_place(root, GARAGE_SHELF, 4.5, 10.4, PI, 1.0)
	_place(root, GARAGE_SHELF, 6.0, 10.4, PI, 1.0)
	_place(root, TOOL_CABINET, 2.6, 10.3, PI, 0.62)
	# Crane (placeholder: "grue de casse à grappin"): tower, jib and a dangling claw.
	var yellow := Mats.flat("crane_yellow", Color(0.85, 0.62, 0.12), 0.6, 0.3)
	m.add_box(root, Transform3D(Basis(), Vector3(-4.5, 4.0, 2.5)), Vector3(0.9, 8.0, 0.9), yellow)
	m.add_box(root, Transform3D(Basis(Vector3.UP, 0.4), Vector3(-2.2, 8.2, 1.6)), Vector3(7.0, 0.6, 0.6), yellow, false)
	m.add_box(root, Transform3D(Basis(), Vector3(0.2, 6.0, 0.6)), Vector3(0.05, 4.0, 0.05), Mats.gun_metal(), false)
	m.add_box(root, Transform3D(Basis(), Vector3(0.2, 3.7, 0.6)), Vector3(1.1, 0.6, 1.1), Mats.rust(), false)


# ---------------------------------------------------------------- derelict flats

static func _flats(m: MapBase, root: Node3D, r: RandomNumberGenerator) -> void:
	# The yard between the two blocks: rubble, a burnt-out car, a dumpster, junk.
	for k in 3:
		_place(root, RUBBLE, r.randf_range(-2.5, 2.5), r.randf_range(-6.0, 6.0), r.randf() * TAU, r.randf_range(1.4, 2.2), "convex")
	m.add_car(_g(root, 1.0, -8.5), root.rotation.y + r.randf_range(-0.4, 0.4), Color(0.12, 0.1, 0.09))
	# Dumpster (placeholder: "benne à ordures").
	var green := Mats.flat("dumpster", Color(0.16, 0.28, 0.18), 0.7, 0.4)
	m.add_box(root, Transform3D(Basis(Vector3.UP, 0.1), Vector3(-1.5, 0.65, 8.5)), Vector3(2.0, 1.3, 1.2), green)
	m.add_box(root, Transform3D(Basis(Vector3.UP, 0.1) * Basis(Vector3.RIGHT, -0.5), Vector3(-1.5, 1.45, 8.95)), Vector3(2.0, 0.06, 1.2), green, false)
	m.scatter_clutter(_g(root, 0.0, 0.0), 4.0, 3)
	# Electricity cabinet at the foot of the yard.
	_place(root, "res://assets/props/electric_panel.glb", 3.2, 9.5, PI, 0.55)
