extends SceneTree
## Compares the rest poses of the game's trooper skeleton and other Mixamo-named
## rigs: local rest rotations (do the bone axes match?) and bone lengths.
## Usage: -s tools/rest_compare.gd -- --file=a.glb --file2=b.glb

const BONES := ["Hips", "Spine", "Spine2", "Neck", "Head", "LeftShoulder", "LeftArm", "LeftForeArm", "LeftHand", "RightArm", "LeftUpLeg", "LeftLeg", "LeftFoot", "RightUpLeg"]


func _initialize() -> void:
	var skels := {}
	skels["trooper"] = _skel((load("res://assets/mixamo/trooper.fbx") as PackedScene).instantiate())
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--file"):
			var path := a.get_slice("=", 1)
			var doc := GLTFDocument.new()
			var st := GLTFState.new()
			doc.append_from_file(path, st)
			skels[path.get_file().get_basename().substr(0, 24)] = _skel(doc.generate_scene(st))
	for b in BONES:
		var line := "%-13s" % b
		for k in skels:
			var sk: Skeleton3D = skels[k]
			var i := sk.find_bone("mixamorig_" + b)
			if i < 0:
				line += " | %s: -" % k
				continue
			var q := sk.get_bone_rest(i).basis.get_rotation_quaternion()
			var e := q.get_euler() * 180.0 / PI
			var len := 0.0
			var children := sk.get_bone_children(i)
			if not children.is_empty():
				len = sk.get_bone_rest(children[0]).origin.length()
			line += " | rot(%4.0f %4.0f %4.0f) len %.3f" % [e.x, e.y, e.z, len]
		print(line)
	for k in skels:
		var sk: Skeleton3D = skels[k]
		var hips := sk.get_bone_global_rest(sk.find_bone("mixamorig_Hips")).origin
		var head := sk.get_bone_global_rest(sk.find_bone("mixamorig_Head")).origin
		var lh := sk.get_bone_global_rest(sk.find_bone("mixamorig_LeftHand")).origin
		print("%s: hips %s head %s lefthand %s" % [k, str(hips.snapped(Vector3.ONE * 0.01)), str(head.snapped(Vector3.ONE * 0.01)), str(lh.snapped(Vector3.ONE * 0.01))])
	quit()


func _skel(n: Node) -> Skeleton3D:
	root.add_child(n)
	return n.find_children("*", "Skeleton3D", true, false)[0]
