extends SceneTree
## Prints hips height and right-hand forward speed over time for a few clips
## (to find the jump window of a vault, the release frame of a throw...).
var sk: Skeleton3D


func _init() -> void:
	var model := (load("res://assets/mixamo/trooper.fbx") as PackedScene).instantiate()
	sk = model.find_children("*", "Skeleton3D", true, false)[0]
	for clip in ["vault_over_box", "grenade_throw", "drinking"]:
		var a := load("res://assets/mixamo/anims/%s.res" % clip) as Animation
		var line := []
		var prev := Vector3.ZERO
		var n := 24
		for i in n + 1:
			var t := a.length * i / n
			var hips := _pos(a, "mixamorig_Hips", t)
			var hand := _pos(a, "mixamorig_RightHand", t)
			var v := (hand - prev).z / (a.length / n) if i > 0 else 0.0
			prev = hand
			line.append("%.2f:y%.2f hz%.2f v%.1f" % [t, hips.y, hand.z - hips.z, v])
		print(clip, " ", a.length, "\n  ", "\n  ".join(line))
	quit()


func _pos(a: Animation, bone: String, t: float) -> Vector3:
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
