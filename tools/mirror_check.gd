extends SceneTree
## Checks AnimMirror: skeleton-space positions / directions of the mirrored clip must be
## the X-reflection of the original's (left <-> right). Usage: -s tools/mirror_check.gd -- --clip=strafe_right_run

var sk: Skeleton3D


func _initialize() -> void:
	var clip := "strafe_right_run"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--clip="):
			clip = a.get_slice("=", 1)
	var model: Node3D = (load("res://assets/mixamo/trooper.fbx") as PackedScene).instantiate()
	root.add_child(model)
	sk = model.find_children("*", "Skeleton3D", true, false)[0]
	var sc := (load("res://assets/mixamo/anims/%s.fbx" % clip) as PackedScene).instantiate()
	var ap := sc.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	var a: Animation = ap.get_animation(ap.get_animation_list()[0]).duplicate(true)
	CharacterModel._strip_root_motion(a)
	var m := AnimMirror.mirror(a, sk)
	for t in [0.0, 0.2, 0.4]:
		var line := "t=%.1f " % t
		for pair in [["mixamorig_LeftFoot", "mixamorig_RightFoot"], ["mixamorig_LeftHand", "mixamorig_RightHand"], ["mixamorig_Head", "mixamorig_Head"], ["mixamorig_Hips", "mixamorig_Hips"]]:
			var p0 := _pos(a, pair[0], t)
			var p1 := _pos(m, pair[1], t)
			line += " %s: orig=%s mirrored(want x flipped)=%s |" % [pair[0].trim_prefix("mixamorig_"), str(Vector3(-p0.x, p0.y, p0.z).snapped(Vector3.ONE * 0.01)), str(p1.snapped(Vector3.ONE * 0.01))]
		print(line)
		for bn in ["mixamorig_Hips", "mixamorig_Spine2", "mixamorig_Head", "mixamorig_RightArm", "mixamorig_LeftArm"]:
			var q0 := _basis(a, bn, t)
			var q1 := _basis(m, bn if not ("Left" in bn or "Right" in bn) else (bn.replace("Left", "Right") if "Left" in bn else bn.replace("Right", "Left")), t)
			print("  ", bn, " ", "fwd(+Z): orig=%s mirrored=%s  up: orig=%s mirrored=%s" % [str((q0 * Vector3.BACK).snapped(Vector3.ONE * 0.01)), str((q1 * Vector3.BACK).snapped(Vector3.ONE * 0.01)), str((q0 * Vector3.UP).snapped(Vector3.ONE * 0.01)), str((q1 * Vector3.UP).snapped(Vector3.ONE * 0.01))])
	quit()


func _pos(a: Animation, bone: String, t: float) -> Vector3:
	return _global(a, sk.find_bone(bone), t).origin


func _basis(a: Animation, bone: String, t: float) -> Basis:
	return _global(a, sk.find_bone(bone), t).basis


func _global(a: Animation, idx: int, t: float) -> Transform3D:
	var xf := Transform3D()
	while idx >= 0:
		xf = _local(a, idx, t) * xf
		idx = sk.get_bone_parent(idx)
	return xf


func _local(a: Animation, idx: int, t: float) -> Transform3D:
	var rest := sk.get_bone_rest(idx)
	var pos := rest.origin
	var rot := rest.basis.get_rotation_quaternion()
	var bname := sk.get_bone_name(idx)
	for tr in a.get_track_count():
		if String(a.track_get_path(tr)).get_slice(":", 1) != bname:
			continue
		match a.track_get_type(tr):
			Animation.TYPE_POSITION_3D:
				pos = a.position_track_interpolate(tr, t)
			Animation.TYPE_ROTATION_3D:
				rot = a.rotation_track_interpolate(tr, t)
	return Transform3D(Basis(rot), pos)
