extends SceneTree
## Bounds (m) and triangle count of each imported prop scene.
## Usage: -s tools/prop_sizes.gd -- res://a.glb res://b.glb ...


func _initialize() -> void:
	for path in OS.get_cmdline_user_args():
		var scene := (load(path) as PackedScene).instantiate() as Node3D
		root.add_child(scene)
		var total := AABB()
		var first := true
		var tris := 0
		for mi: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
			var bb := (scene.global_transform.affine_inverse() * mi.global_transform) * mi.get_aabb()
			total = bb if first else total.merge(bb)
			first = false
			for s in mi.mesh.get_surface_count():
				var arr := mi.mesh.surface_get_arrays(s)
				var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
				tris += (idx.size() if not idx.is_empty() else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
		print("[PROP] %s pos %s size %s tris %d" % [path, str(total.position.snapped(Vector3.ONE * 0.01)), str(total.size.snapped(Vector3.ONE * 0.01)), tris])
		scene.free()
	quit()
