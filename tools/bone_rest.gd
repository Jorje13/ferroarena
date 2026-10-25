extends SceneTree
## Rest positions (skeleton space) of every bone of an imported model, to map chains by side.
## Usage: -s tools/bone_rest.gd -- --file=res://assets/monsters/walker.glb


func _initialize() -> void:
	var path := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--file="):
			path = a.get_slice("=", 1)
	var scene := (load(path) as PackedScene).instantiate()
	root.add_child(scene)
	var sk := scene.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	for i in sk.get_bone_count():
		print("[BONE] %d %s <- %d  %s" % [i, sk.get_bone_name(i), sk.get_bone_parent(i), str(sk.get_bone_global_rest(i).origin.snapped(Vector3.ONE * 0.01))])
	quit()
