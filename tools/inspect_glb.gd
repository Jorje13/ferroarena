extends SceneTree
## Dumps a glTF/GLB: node tree, skeletons (bones), animations, mesh bounds.
## Usage: -s tools/inspect_glb.gd -- --file=path/model.glb [--bones] [--depth=4]


func _initialize() -> void:
	var path := ""
	var show_bones := false
	var depth := 4
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--file="):
			path = a.get_slice("=", 1)
		elif a == "--bones":
			show_bones = true
		elif a.begins_with("--depth="):
			depth = int(a.get_slice("=", 1))
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_file(path, state)
	if err != OK:
		print("[GLB] erreur de lecture ", err)
		quit()
		return
	var scene := doc.generate_scene(state)
	root.add_child(scene)
	print("[GLB] ", path)
	_tree(scene, 0, depth)
	var total := AABB()
	var first := true
	for mi: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
		var b := mi.get_aabb()
		var gt := mi.transform
		var p: Node = mi.get_parent()
		while p and p != scene:
			if p is Node3D:
				gt = (p as Node3D).transform * gt
			p = p.get_parent()
		var wb := gt * b
		total = wb if first else total.merge(wb)
		first = false
		print("[GLB] mesh %s  aabb size %s  surfaces %d  skinned %s" % [mi.name, str(b.size.snapped(Vector3.ONE * 0.01)), mi.mesh.get_surface_count(), str(mi.skin != null)])
	print("[GLB] total (hors skin) pos %s size %s" % [str(total.position.snapped(Vector3.ONE * 0.01)), str(total.size.snapped(Vector3.ONE * 0.01))])
	for sk: Skeleton3D in scene.find_children("*", "Skeleton3D", true, false):
		print("[GLB] squelette %s : %d os" % [sk.name, sk.get_bone_count()])
		if show_bones:
			var names := []
			for i in sk.get_bone_count():
				names.append("%d:%s<-%d" % [i, sk.get_bone_name(i), sk.get_bone_parent(i)])
			print("   ", " | ".join(names))
	for ap: AnimationPlayer in scene.find_children("*", "AnimationPlayer", true, false):
		for lib_name in ap.get_animation_library_list():
			var lib := ap.get_animation_library(lib_name)
			for an in lib.get_animation_list():
				var a: Animation = lib.get_animation(an)
				print("[GLB] anim '%s' %.2f s, %d pistes, boucle %d" % [an, a.length, a.get_track_count(), a.loop_mode])
	quit()


func _tree(n: Node, d: int, max_depth: int) -> void:
	if d > max_depth:
		return
	var extra := ""
	if n is Node3D:
		extra = " pos=%s scale=%s" % [str((n as Node3D).position.snapped(Vector3.ONE * 0.001)), str((n as Node3D).scale.snapped(Vector3.ONE * 0.001))]
	print("  ".repeat(d), n.name, " [", n.get_class(), "]", extra)
	for c in n.get_children():
		_tree(c, d + 1, max_depth)
