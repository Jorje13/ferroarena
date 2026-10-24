class_name Shapes
## Procedural meshes with bevelled / rounded edges (cached), used for the
## rifle and the raider gear so they read as manufactured objects, not boxes.

static var _cache := {}


## Box with rounded edges. `r` = edge radius, `seg` = segments per rounded edge.
static func rounded_box(size: Vector3, r: float, seg := 3) -> ArrayMesh:
	var key := "rb_%s_%f_%d" % [size, r, seg]
	if _cache.has(key):
		return _cache[key]
	var h := size * 0.5
	r = minf(r, minf(h.x, minf(h.y, h.z)) * 0.99)
	var inner := h - Vector3.ONE * r
	var axes := [_coords(h.x, r, seg), _coords(h.y, r, seg), _coords(h.z, r, seg)]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Six faces: (normal axis, sign, u axis, v axis)
	for f in [[0, 1, 1, 2], [0, -1, 1, 2], [1, 1, 0, 2], [1, -1, 0, 2], [2, 1, 0, 1], [2, -1, 0, 1]]:
		var na: int = f[0]
		var sg: float = f[1]
		var ua: int = f[2]
		var va: int = f[3]
		var cu: PackedFloat32Array = axes[ua]
		var cv: PackedFloat32Array = axes[va]
		var grid := []
		for i in cu.size():
			var col := []
			for j in cv.size():
				var p := Vector3.ZERO
				p[na] = h[na] * sg
				p[ua] = cu[i]
				p[va] = cv[j]
				var c := p.clamp(-inner, inner)
				var n := p - c
				n = n.normalized() if n.length() > 0.00001 else Vector3.ZERO
				if n == Vector3.ZERO:
					n[na] = sg
				col.append([c + n * r, n])
			grid.append(col)
		for i in cu.size() - 1:
			for j in cv.size() - 1:
				_quad(st, grid[i][j], grid[i + 1][j], grid[i + 1][j + 1], grid[i][j + 1])
	st.generate_tangents()
	var mesh := st.commit()
	_cache[key] = mesh
	return mesh


static func _coords(hh: float, r: float, seg: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for k in range(seg, -1, -1):
		out.append(-(hh - r) - r * sin(PI * 0.5 * k / seg))
	for k in range(0, seg + 1):
		out.append((hh - r) + r * sin(PI * 0.5 * k / seg))
	return out


## Adds two triangles with outward-facing winding (Godot: clockwise = front).
static func _quad(st: SurfaceTool, a: Array, b: Array, c: Array, d: Array) -> void:
	_tri(st, a, b, c)
	_tri(st, a, c, d)


static func _tri(st: SurfaceTool, a: Array, b: Array, c: Array) -> void:
	var pa: Vector3 = a[0]
	var pb: Vector3 = b[0]
	var pc: Vector3 = c[0]
	if (pb - pa).cross(pc - pa).length_squared() < 1e-14:
		return
	var nrm: Vector3 = (a[1] + b[1] + c[1]) as Vector3
	if (pb - pa).cross(pc - pa).dot(nrm) > 0.0:
		var t := b
		b = c
		c = t
	for v in [a, b, c]:
		st.set_normal(v[1])
		st.set_uv(Vector2(v[0].x + v[0].z, v[0].y))
		st.add_vertex(v[0])


## Thick curved plate: a patch of an ellipsoid (radii `r`) between azimuth
## phi0..phi1 (0 = +Z front, increasing towards +X) and polar angle th0..th1
## (0 = top, PI/2 = equator, PI = bottom). Outer skin, inner skin `thick`
## inside, and a rim joining them. Building block for helmets, plates, pads.
static func shell(r: Vector3, phi0: float, phi1: float, th0: float, th1: float, thick := 0.012, nu := 18, nv := 10) -> ArrayMesh:
	var key := "sh_%s_%f_%f_%f_%f_%f_%d_%d" % [r, phi0, phi1, th0, th1, thick, nu, nv]
	if _cache.has(key):
		return _cache[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ri := r - Vector3.ONE * thick
	var outer := []
	var inner := []
	for i in nu + 1:
		var phi := lerpf(phi0, phi1, float(i) / nu)
		var co := []
		var ci := []
		for j in nv + 1:
			var th := lerpf(th0, th1, float(j) / nv)
			var d := Vector3(sin(th) * sin(phi), cos(th), sin(th) * cos(phi))
			var po := d * r
			var pi := d * ri
			var n := Vector3(po.x / (r.x * r.x), po.y / (r.y * r.y), po.z / (r.z * r.z)).normalized()
			co.append([po, n])
			ci.append([pi, -n])
		outer.append(co)
		inner.append(ci)
	for i in nu:
		for j in nv:
			_quad(st, outer[i][j], outer[i + 1][j], outer[i + 1][j + 1], outer[i][j + 1])
			_quad(st, inner[i][j], inner[i + 1][j], inner[i + 1][j + 1], inner[i][j + 1])
	# Rim: the four borders of the patch (skipped where the patch closes on itself).
	var full_ring := absf(phi1 - phi0) >= TAU - 0.001
	var mid: Vector3 = outer[nu / 2][nv / 2][0]
	var edges := []
	if th0 > 0.001:
		edges.append(range(nu + 1).map(func(i): return [i, 0]))
	if th1 < PI - 0.001:
		edges.append(range(nu + 1).map(func(i): return [i, nv]))
	if not full_ring:
		edges.append(range(nv + 1).map(func(j): return [0, j]))
		edges.append(range(nv + 1).map(func(j): return [nu, j]))
	for e in edges:
		for k in e.size() - 1:
			var a: Array = e[k]
			var b: Array = e[k + 1]
			var oa: Vector3 = outer[a[0]][a[1]][0]
			var ob: Vector3 = outer[b[0]][b[1]][0]
			var ia: Vector3 = inner[a[0]][a[1]][0]
			var ib: Vector3 = inner[b[0]][b[1]][0]
			var surf: Vector3 = outer[a[0]][a[1]][1]
			var rn := (ob - oa).cross(surf).normalized()
			if rn.dot(oa - mid) < 0.0:
				rn = -rn
			_quad(st, [oa, rn], [ob, rn], [ib, rn], [ia, rn])
	st.generate_tangents()
	var mesh := st.commit()
	_cache[key] = mesh
	return mesh


## Extrudes a 2D profile (in the Y/Z plane, Z = forward) along X by `width`,
## with chamfered side edges of size `bevel`. Used for stocks, grips, plates.
static func extrude(key: String, profile: PackedVector2Array, width: float, bevel := 0.004) -> ArrayMesh:
	if _cache.has("ex_" + key):
		return _cache["ex_" + key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hw := width * 0.5
	var n := profile.size()
	# Outward 2D normals per edge (profile assumed counter-clockwise in (z, y)).
	var area := 0.0
	for i in n:
		var p0 := profile[i]
		var p1 := profile[(i + 1) % n]
		area += p0.x * p1.y - p1.x * p0.y
	var ccw := area > 0.0
	var inset := PackedVector2Array()
	for i in n:
		var prev := profile[(i - 1 + n) % n]
		var cur := profile[i]
		var nxt := profile[(i + 1) % n]
		var e0 := (cur - prev).normalized()
		var e1 := (nxt - cur).normalized()
		var n0 := Vector2(e0.y, -e0.x) if ccw else Vector2(-e0.y, e0.x)
		var n1 := Vector2(e1.y, -e1.x) if ccw else Vector2(-e1.y, e1.x)
		var nn := (n0 + n1).normalized()
		inset.append(cur - nn * bevel)
	# Caps (inset profile, at ±hw)
	var tris := Geometry2D.triangulate_polygon(inset)
	for side in [1.0, -1.0]:
		var nrm := Vector3(side, 0, 0)
		for t in range(0, tris.size(), 3):
			var vs := []
			for k in 3:
				var q := inset[tris[t + k]]
				vs.append([Vector3(hw * side, q.y, q.x), nrm])
			_tri(st, vs[0], vs[1], vs[2])
	# Walls: chamfer strip (cap edge -> outer) + side wall.
	for i in n:
		var j := (i + 1) % n
		var e := (profile[j] - profile[i]).normalized()
		var wn2 := Vector2(e.y, -e.x) if ccw else Vector2(-e.y, e.x)
		var wn := Vector3(0, wn2.y, wn2.x)
		var o_i := Vector3(0, profile[i].y, profile[i].x)
		var o_j := Vector3(0, profile[j].y, profile[j].x)
		var in_i := Vector3(0, inset[i].y, inset[i].x)
		var in_j := Vector3(0, inset[j].y, inset[j].x)
		var w := hw - bevel
		_quad(st, [o_i + Vector3(w, 0, 0), wn], [o_j + Vector3(w, 0, 0), wn], [o_j + Vector3(-w, 0, 0), wn], [o_i + Vector3(-w, 0, 0), wn])
		for side in [1.0, -1.0]:
			var cn := (wn + Vector3(side, 0, 0)).normalized()
			_quad(st, [o_i + Vector3(w * side, 0, 0), cn], [o_j + Vector3(w * side, 0, 0), cn], [in_j + Vector3(hw * side, 0, 0), cn], [in_i + Vector3(hw * side, 0, 0), cn])
	st.generate_tangents()
	var mesh := st.commit()
	_cache["ex_" + key] = mesh
	return mesh
