extends SceneTree
## Dev tool: godot --headless --script res://tools/inspect_assets.gd
## Prints size, triangle count and mesh nodes of every imported glTF.


func _init() -> void:
	var dir := "res://assets/polyhaven/models"
	for id in DirAccess.get_directories_at(dir):
		for f in DirAccess.get_files_at(dir + "/" + id):
			if not f.ends_with(".gltf"):
				continue
			var ps := load(dir + "/" + id + "/" + f) as PackedScene
			if ps == null:
				print("FAIL ", id)
				continue
			var root := ps.instantiate()
			var info := []
			_walk(root, Transform3D(), info)
			var aabb := AABB()
			var tris := 0
			var first := true
			for m in info:
				tris += m.tris
				aabb = m.aabb if first else aabb.merge(m.aabb)
				first = false
			print("%-28s meshes=%d tris=%d size=%s" % [id, info.size(), tris, aabb.size])
			for m in info:
				print("    %-40s tris=%d pos=%s size=%s" % [m.name, m.tris, m.aabb.position + m.aabb.size * 0.5, m.aabb.size])
			root.free()
	quit()


func _walk(n: Node, xf: Transform3D, out: Array) -> void:
	var t := xf
	if n is Node3D:
		t = xf * (n as Node3D).transform
	if n is MeshInstance3D and n.mesh:
		var tris := 0
		for s in n.mesh.get_surface_count():
			var arr: Array = n.mesh.surface_get_arrays(s)
			var idx = arr[Mesh.ARRAY_INDEX]
			tris += (idx.size() if idx else arr[Mesh.ARRAY_VERTEX].size()) / 3
		out.append({"name": String(n.name), "tris": tris, "aabb": t * n.mesh.get_aabb()})
	for c in n.get_children():
		_walk(c, t, out)
