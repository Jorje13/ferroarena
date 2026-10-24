class_name Scan
## Helpers to place Poly Haven scanned models (glTF) as lightweight props:
## meshes are extracted once (optionally a subset by node-name prefix) and
## shared between every instance.

const ROOT := "res://assets/polyhaven/models/"

## key -> {"parts": [[Mesh, Transform3D]], "aabb": AABB, "points": PackedVector3Array}
static var _cache := {}
## Every placed scanned prop: {id, prefix, scale, pos}. Same order on every peer (the map
## is built from a fixed seed): prop hunt disguises refer to entries by index.
static var catalog: Array = []


static func _key(id: String, prefix: String) -> String:
	return id + "|" + prefix


## Loads the model and keeps the mesh nodes whose name starts with `prefix`
## (all of them when empty). Parts are re-centred: XZ centre at 0, bottom at y=0.
static func get_parts(id: String, prefix := "") -> Dictionary:
	var key := _key(id, prefix)
	if _cache.has(key):
		return _cache[key]
	# Poly Haven id, or a full res:// path to any other glTF / scene.
	var path := id if id.begins_with("res://") else ROOT + id + "/" + id + "_2k.gltf"
	var ps := (load(path) as PackedScene) if ResourceLoader.exists(path) else null
	var parts := []
	var aabb := AABB()
	var first := true
	if ps:
		var inst := ps.instantiate()
		_collect(inst, Transform3D(), prefix, parts)
		inst.free()
	for p in parts:
		var b: AABB = p[1] * (p[0] as Mesh).get_aabb()
		aabb = b if first else aabb.merge(b)
		first = false
	var offset := Vector3(-(aabb.position.x + aabb.size.x * 0.5), -aabb.position.y, -(aabb.position.z + aabb.size.z * 0.5))
	var points := PackedVector3Array()
	for p in parts:
		p[1] = Transform3D(Basis(), offset) * p[1]
		var mesh: Mesh = p[0]
		var verts: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var step := maxi(1, verts.size() / 120)
		for i in range(0, verts.size(), step):
			points.append(p[1] * verts[i])
	aabb.position += offset
	var data := {"parts": parts, "aabb": aabb, "points": points}
	_cache[key] = data
	return data


static func _collect(n: Node, xf: Transform3D, prefix: String, out: Array) -> void:
	var t := xf
	if n is Node3D:
		t = xf * (n as Node3D).transform
	# A prefix ending with "$" means an exact node name.
	var nm := String(n.name)
	var match_name := prefix == "" or (nm == prefix.trim_suffix("$") if prefix.ends_with("$") else nm.begins_with(prefix))
	if n is MeshInstance3D and (n as MeshInstance3D).mesh and match_name:
		out.append([(n as MeshInstance3D).mesh, t])
	for c in n.get_children():
		_collect(c, t, prefix, out)


static func exists(id: String) -> bool:
	return not (get_parts(id).parts as Array).is_empty()


static func size_of(id: String, prefix := "") -> Vector3:
	return (get_parts(id, prefix).aabb as AABB).size


## Instantiates the model under `parent`. collider: "none" | "box" | "convex".
static func place(parent: Node3D, id: String, xf: Transform3D, prefix := "", collider := "box", layer := 1) -> Node3D:
	var data := get_parts(id, prefix)
	var root := Node3D.new()
	root.transform = xf
	parent.add_child(root)
	if not (data.parts as Array).is_empty() and parent.is_inside_tree():
		var sz: Vector3 = (data.aabb as AABB).size * root.global_basis.get_scale()
		if sz.y > 0.3 and sz.y < 9.0 and maxf(sz.x, sz.z) < 8.0 and not prefix.ends_with("post$") and not id.contains("fence"):
			catalog.append({"id": id, "prefix": prefix, "scale": root.global_basis.get_scale().x, "pos": root.global_position + Vector3(0, sz.y * 0.5, 0), "size": sz})
	for p in data.parts:
		var mi := MeshInstance3D.new()
		mi.mesh = p[0]
		mi.transform = p[1]
		root.add_child(mi)
	if collider != "none" and not (data.parts as Array).is_empty():
		var body := StaticBody3D.new()
		body.collision_layer = layer
		body.collision_mask = 0
		var cs := CollisionShape3D.new()
		var s := root.global_basis.get_scale()
		if collider == "convex":
			var sh := ConvexPolygonShape3D.new()
			var pts := PackedVector3Array()
			for v in data.points:
				pts.append(v * s)
			sh.points = pts
			cs.shape = sh
		else:
			var sh := BoxShape3D.new()
			var b: AABB = data.aabb
			sh.size = b.size * s
			cs.shape = sh
			cs.position = (b.position + b.size * 0.5) * s
		body.add_child(cs)
		# The body must not inherit the visual scale (physics shapes hate scale).
		body.top_level = true
		root.add_child(body)
		body.global_transform = Transform3D(root.global_basis.orthonormalized(), root.global_position)
	return root
