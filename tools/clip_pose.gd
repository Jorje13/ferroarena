extends SceneTree
## Prints the torso direction (pelvis -> neck) and pelvis height of some clips,
## to know whether a clip is upright, prone or supine.
var sk: Skeleton3D


func _init() -> void:
	var model: Node3D = CharacterModel.create(false)
	root.add_child(model)
	sk = model.find_children("*", "Skeleton3D", true, false)[0]
	for pair in [["ual1", "Swim_Fwd"], ["ual1", "Swim_Idle"], ["ual2", "LayToIdle"], ["ual1", "Idle"], ["ual1", "Death01"]]:
		var a := CharacterModel.library(pair[0]).get_animation(pair[1])
		for f in [0.0, 0.5]:
			var t: float = a.length * f
			var pel := _pos(a, "pelvis", t)
			var neck := _pos(a, "neck_01", t)
			var d := (neck - pel).normalized()
			print("%s t=%.2f torso_dir=(%.2f, %.2f, %.2f) pelvis_y=%.2f head_y=%.2f" % [pair[1], t, d.x, d.y, d.z, pel.y, _pos(a, "Head", t).y])
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
	for tr in a.get_track_count():
		if String(a.track_get_path(tr)).get_slice(":", 1) != sk.get_bone_name(idx):
			continue
		match a.track_get_type(tr):
			Animation.TYPE_POSITION_3D:
				pos = a.position_track_interpolate(tr, t)
			Animation.TYPE_ROTATION_3D:
				rot = a.rotation_track_interpolate(tr, t)
	return Transform3D(Basis(rot), pos)
