extends SceneTree
## Profile of a (rifle) mesh along its long axis: per 0.1 m slice, the min / max of the other two axes.
## Usage: -s tools/mesh_profile.gd -- --file=x.glb [--axis=x]


func _initialize() -> void:
	var path := ""
	var axis := 0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--file="):
			path = a.get_slice("=", 1)
		elif a.begins_with("--axis="):
			axis = {"x": 0, "y": 1, "z": 2}[a.get_slice("=", 1)]
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	doc.append_from_file(path, state)
	var scene := doc.generate_scene(state)
	root.add_child(scene)
	var bins := {}
	for mi: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
		var arr := mi.mesh.surface_get_arrays(0)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		for v in verts:
			var k := int(floor(v[axis] * 10.0))
			var o1 := (axis + 1) % 3
			var o2 := (axis + 2) % 3
			if not bins.has(k):
				bins[k] = [INF, -INF, INF, -INF, 0]
			var b: Array = bins[k]
			b[0] = minf(b[0], v[o1])
			b[1] = maxf(b[1], v[o1])
			b[2] = minf(b[2], v[o2])
			b[3] = maxf(b[3], v[o2])
			b[4] += 1
	var keys := bins.keys()
	keys.sort()
	for k in keys:
		var b: Array = bins[k]
		print("%+.1f : %s[%+.3f..%+.3f]  %s[%+.3f..%+.3f]  n=%d" % [k / 10.0, "xyz"[(axis + 1) % 3], b[0], b[1], "xyz"[(axis + 2) % 3], b[2], b[3], b[4]])
	quit()
