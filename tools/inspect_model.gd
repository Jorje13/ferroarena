extends SceneTree
## Dev tool: godot --headless --script res://tools/inspect_model.gd -- --model=res://path.glb
## Prints mesh parts, triangle counts, sizes and materials of a model.


func _init() -> void:
	var path := "res://assets/models/kar98k.glb"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--model="):
			path = a.trim_prefix("--model=")
	var root := (load(path) as PackedScene).instantiate()
	_walk(root, Transform3D(), 0)
	root.free()
	quit()


func _walk(n: Node, xf: Transform3D, d: int) -> void:
	var t := xf
	if n is Node3D:
		t = xf * (n as Node3D).transform
	var line := "  ".repeat(d) + String(n.name) + " <" + n.get_class() + ">"
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		var m := (n as MeshInstance3D).mesh
		var tris := 0
		var mats := []
		for s in m.get_surface_count():
			var arr: Array = m.surface_get_arrays(s)
			var idx = arr[Mesh.ARRAY_INDEX]
			tris += (idx.size() if idx else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
			var mat := m.surface_get_material(s)
			if mat is StandardMaterial3D:
				mats.append("%s col=%s tex=%s" % [mat.resource_name, (mat as StandardMaterial3D).albedo_color.to_html(false), (mat as StandardMaterial3D).albedo_texture != null])
		var aabb := t * m.get_aabb()
		line += " tris=%d size=%s center=%s mats=%s" % [tris, aabb.size, aabb.get_center(), mats]
	print(line)
	for c in n.get_children():
		_walk(c, t, d + 1)
