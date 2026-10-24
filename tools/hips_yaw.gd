extends SceneTree
## Hips yaw (deg, about skeleton Y) of clips relative to rifle_idle: how far the legs'
## facing is twisted from the aiming stance. Usage: -s tools/hips_yaw.gd

var sk: Skeleton3D


func _initialize() -> void:
	var model: Node3D = (load("res://assets/mixamo/trooper.fbx") as PackedScene).instantiate()
	root.add_child(model)
	sk = model.find_children("*", "Skeleton3D", true, false)[0]
	var a := load("res://assets/mixamo/anims/vault_over_box.res") as Animation
	print("length ", a.length)
	for i in 31:
		var t := a.length * i / 30.0
		var h := _global(a, "mixamorig_Hips", t).origin
		var lh := _global(a, "mixamorig_LeftHand", t).origin
		var rh := _global(a, "mixamorig_RightHand", t).origin
		var lf := _global(a, "mixamorig_LeftFoot", t).origin
		var rf := _global(a, "mixamorig_RightFoot", t).origin
		print("t=%.2f hips(%.2f,%.2f,%.2f) LH(%.2f,%.2f,%.2f) RH(%.2f,%.2f,%.2f) LF(%.2f,%.2f,%.2f) RF(%.2f,%.2f,%.2f)" % [t, h.x, h.y, h.z, lh.x, lh.y, lh.z, rh.x, rh.y, rh.z, lf.x, lf.y, lf.z, rf.x, rf.y, rf.z])
	quit()


func _clip(name: String) -> Animation:
	var sc := (load("res://assets/mixamo/anims/%s.fbx" % name) as PackedScene).instantiate()
	var ap := sc.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	return ap.get_animation(ap.get_animation_list()[0])


func _global(a: Animation, bone: String, t: float) -> Transform3D:
	var idx := sk.find_bone(bone)
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
