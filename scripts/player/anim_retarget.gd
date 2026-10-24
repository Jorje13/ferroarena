class_name AnimRetarget
## Moves Mixamo-named clips onto another skeleton with the same bone names but a
## different rest pose (other bone axes, A-pose, proportions). No game dependencies.
##
## Per bone the source's animated global rotation is reduced to its change from rest
## (D = G(t) * G_rest^-1) and applied to the target's rest orientation, first turned by
## the shortest arc so the target bone points where the source bone points. The
## result is then re-expressed as local rotations down the target chain.

## Bone -> the child that gives its direction.
const MAIN_CHILD := {
	"mixamorig_Hips": "mixamorig_Spine", "mixamorig_Spine": "mixamorig_Spine1",
	"mixamorig_Spine1": "mixamorig_Spine2", "mixamorig_Spine2": "mixamorig_Neck",
	"mixamorig_Neck": "mixamorig_Head", "mixamorig_Head": "mixamorig_HeadTop_End",
}
const SIDE_CHAIN := {
	"Shoulder": "Arm", "Arm": "ForeArm", "ForeArm": "Hand", "Hand": "HandMiddle1",
	"UpLeg": "Leg", "Leg": "Foot", "Foot": "ToeBase", "ToeBase": "Toe_End",
}


static func _main_dir(sk: Skeleton3D, b: int) -> Vector3:
	var nm := sk.get_bone_name(b)
	var child := -1
	if MAIN_CHILD.has(nm):
		child = sk.find_bone(MAIN_CHILD[nm])
	else:
		for side in ["Left", "Right"]:
			if nm.begins_with("mixamorig_" + side):
				var key := nm.trim_prefix("mixamorig_" + side)
				if SIDE_CHAIN.has(key):
					child = sk.find_bone("mixamorig_" + side + SIDE_CHAIN[key])
	if child < 0:
		var kids := sk.get_bone_children(b)
		if kids.is_empty():
			return Vector3.ZERO
		child = kids[0]
	var d := sk.get_bone_global_rest(child).origin - sk.get_bone_global_rest(b).origin
	return d.normalized() if d.length() > 0.0001 else Vector3.ZERO


## Bones whose children come before them would break the single forward pass.
static func _ordered(sk: Skeleton3D) -> bool:
	for b in sk.get_bone_count():
		if sk.get_bone_parent(b) > b:
			return false
	return true


## `hips_shift` is added to the Hips position track (target rest hips - source idle hips).
## align = false: plain world-space delta (no per-bone turn of the target's rest direction), for rigs whose
## joint positions are noisy (auto-riggers) so that a bone's own direction means nothing.
static func retarget(src: Animation, from: Skeleton3D, to: Skeleton3D, hips_shift: Vector3, align := true, idle_hips := Vector3.ZERO) -> Animation:
	assert(_ordered(from) and _ordered(to))
	var nb := to.get_bone_count()
	var nf := from.get_bone_count()
	var smap := PackedInt32Array()
	smap.resize(nb)
	var aligned := []
	for tb in nb:
		var sb := from.find_bone(to.get_bone_name(tb))
		smap[tb] = sb
		var gt := to.get_bone_global_rest(tb).basis.orthonormalized()
		var q := Quaternion.IDENTITY
		if sb >= 0 and align:
			var dt := _main_dir(to, tb)
			var ds := _main_dir(from, sb)
			if dt != Vector3.ZERO and ds != Vector3.ZERO:
				q = Quaternion(dt, ds)
		aligned.append(Basis(q) * gt)
	var s_rest_inv := []
	var s_rest_local := []
	for sb in nf:
		s_rest_inv.append(from.get_bone_global_rest(sb).basis.orthonormalized().inverse())
		s_rest_local.append(from.get_bone_rest(sb).basis.get_rotation_quaternion())
	# Source rotation / position tracks by source bone.
	var rot_tr := {}
	var pos_tr := {}
	var grid_track := -1
	for tr in src.get_track_count():
		var bi := from.find_bone(str(src.track_get_path(tr)).get_slice(":", 1))
		if bi < 0:
			continue
		match src.track_get_type(tr):
			Animation.TYPE_ROTATION_3D:
				rot_tr[bi] = tr
				if grid_track < 0 or src.track_get_key_count(tr) > src.track_get_key_count(grid_track):
					grid_track = tr
			Animation.TYPE_POSITION_3D:
				pos_tr[bi] = tr
	var out := Animation.new()
	out.length = src.length
	out.loop_mode = src.loop_mode
	var hips_t := to.find_bone("mixamorig_Hips")
	var hips_s := from.find_bone("mixamorig_Hips")
	var out_rot := {}
	for tb in nb:
		if smap[tb] >= 0 and rot_tr.has(smap[tb]):
			var nt := out.add_track(Animation.TYPE_ROTATION_3D)
			out.track_set_path(nt, NodePath("Skeleton3D:" + to.get_bone_name(tb)))
			out.track_set_interpolation_type(nt, Animation.INTERPOLATION_LINEAR)
			out_rot[tb] = nt
	var out_pos := -1
	if hips_s >= 0 and pos_tr.has(hips_s) and hips_t >= 0:
		out_pos = out.add_track(Animation.TYPE_POSITION_3D)
		out.track_set_path(out_pos, NodePath("Skeleton3D:mixamorig_Hips"))
		out.track_set_interpolation_type(out_pos, Animation.INTERPOLATION_LINEAR)
	# Key times: those of the densest rotation track.
	var times := PackedFloat32Array()
	if grid_track >= 0:
		for i in src.track_get_key_count(grid_track):
			times.append(src.track_get_key_time(grid_track, i))
	if times.is_empty():
		return out
	var gs: Array[Basis] = []
	gs.resize(nf)
	var gt_anim: Array[Basis] = []
	gt_anim.resize(nb)
	for t in times:
		for sb in nf:
			var q: Quaternion = s_rest_local[sb]
			if rot_tr.has(sb):
				q = src.rotation_track_interpolate(rot_tr[sb], t)
			var par := from.get_bone_parent(sb)
			gs[sb] = Basis(q) if par < 0 else gs[par] * Basis(q)
		for tb in nb:
			var sb := smap[tb]
			var par := to.get_bone_parent(tb)
			var g: Basis
			if sb >= 0:
				g = (gs[sb] * (s_rest_inv[sb] as Basis)) * (aligned[tb] as Basis)
			else:
				# Extra bone (accessory): keeps its rest pose relative to the parent.
				var rest_local := to.get_bone_rest(tb).basis.orthonormalized()
				g = rest_local if par < 0 else gt_anim[par] * rest_local
			gt_anim[tb] = g
			if out_rot.has(tb):
				var local := g if par < 0 else gt_anim[par].inverse() * g
				out.rotation_track_insert_key(out_rot[tb], t, local.orthonormalized().get_rotation_quaternion())
		if out_pos >= 0:
			var sp := src.position_track_interpolate(pos_tr[hips_s], t) as Vector3
			if idle_hips != Vector3.ZERO:
				var hp := to.get_bone_parent(hips_t)
				var pinv := Basis() if hp < 0 else to.get_bone_global_rest(hp).basis.orthonormalized().inverse()
				out.position_track_insert_key(out_pos, t, to.get_bone_rest(hips_t).origin + pinv * (sp - idle_hips))
			else:
				out.position_track_insert_key(out_pos, t, sp + hips_shift)
	return out
