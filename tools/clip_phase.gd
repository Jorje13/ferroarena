extends SceneTree
## Prints, for each locomotion clip, the time (s and fraction of the cycle) at
## which the left foot is furthest forward. Used to phase-align the loco blend.
## Forward kinematics computed straight from the animation tracks.
var sk: Skeleton3D


func _init() -> void:
	var model: Node3D = CharacterModel.create(false)
	root.add_child(model)
	sk = model.find_children("*", "Skeleton3D", true, false)[0]
	var lib := CharacterModel.library("ual1")
	for clip in ["Walk", "Jog_Fwd", "Sprint", "Crouch_Fwd"]:
		var a := lib.get_animation(clip)
		var best := -INF
		var best_t := 0.0
		var n := 160
		for i in n:
			var t := a.length * i / n
			var d := _foot(a, "foot_l", t).z - _foot(a, "foot_r", t).z
			if d > best:
				best = d
				best_t = t
		var curve := []
		for i in 8:
			var tt := a.length * i / 8.0
			curve.append("%.2f" % (_foot(a, "foot_l", tt).z - _foot(a, "foot_r", tt).z))
		print("  curve ", " ".join(curve))
		print("%s len=%.3f left_fwd_t=%.3f frac=%.3f gap=%.3f" % [clip, a.length, best_t, best_t / a.length, best])
	quit()


func _foot(a: Animation, bone: String, t: float) -> Vector3:
	var idx := sk.find_bone(bone)
	var xf := Transform3D()
	while idx >= 0:
		xf = _local(a, idx, t) * xf
		idx = sk.get_bone_parent(idx)
	return xf.origin


func _local(a: Animation, idx: int, t: float) -> Transform3D:
	var rest := sk.get_bone_rest(idx)
	var pos := rest.origin
	var rot := rest.basis.get_rotation_quaternion()
	var path := NodePath("%s:%s" % [_skel_path(a), sk.get_bone_name(idx)])
	for tr in a.get_track_count():
		if String(a.track_get_path(tr)).get_slice(":", 1) != sk.get_bone_name(idx):
			continue
		match a.track_get_type(tr):
			Animation.TYPE_POSITION_3D:
				pos = a.position_track_interpolate(tr, t)
			Animation.TYPE_ROTATION_3D:
				rot = a.rotation_track_interpolate(tr, t)
	return Transform3D(Basis(rot), pos)


func _skel_path(_a: Animation) -> String:
	return ""

