extends SceneTree
## Prints an imported scene's node tree (with global positions), skeleton bones
## (global rest origins) and mesh AABBs. Usage: -s tools/inspect_scene.gd -- --scene=res://...

func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var path := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--scene="):
			path = a.substr(8)
	var scene := (load(path) as PackedScene).instantiate() as Node3D
	root.add_child(scene)
	await process_frame
	_dump(scene, 0)
	for sk: Skeleton3D in scene.find_children("*", "Skeleton3D", true, false):
		for i in sk.get_bone_count():
			var g := sk.global_transform * sk.get_bone_global_rest(i)
			print("bone %d %s parent=%d pos=%s" % [i, sk.get_bone_name(i), sk.get_bone_parent(i), g.origin])
	for mi: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
		print("mesh %s aabb=%s" % [mi.name, mi.global_transform * mi.get_aabb()])
	quit()


func _dump(n: Node, d: int) -> void:
	var extra := ""
	if n is Node3D:
		extra = " pos=%s scale=%s" % [(n as Node3D).global_position, (n as Node3D).global_basis.get_scale()]
	print("  ".repeat(d) + "%s (%s)%s" % [n.name, n.get_class(), extra])
	for c in n.get_children():
		_dump(c, d + 1)
