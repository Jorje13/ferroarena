extends SceneTree
## Rest positions of every bone of a GLB, indented by depth: index name (x y z) [children].
## Usage: -s tools/bone_dump.gd -- --file=x.glb


func _initialize() -> void:
	var path := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--file="):
			path = a.get_slice("=", 1)
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	doc.append_from_file(path, st)
	var sc := doc.generate_scene(st)
	root.add_child(sc)
	var sk := sc.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	for b in sk.get_bone_count():
		var d := 0
		var p := sk.get_bone_parent(b)
		while p >= 0:
			d += 1
			p = sk.get_bone_parent(p)
		var o := sk.get_bone_global_rest(b).origin
		print("%s%d %s (%.3f %.3f %.3f) kids=%d" % ["  ".repeat(d), b, sk.get_bone_name(b), o.x, o.y, o.z, sk.get_bone_children(b).size()])
	quit()
