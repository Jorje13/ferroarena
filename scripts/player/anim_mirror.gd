class_name AnimMirror
## Left/right mirroring of Mixamo clips (no game dependencies, usable from tools).


## Mirror image of a clip (left <-> right) for the Mixamo skeleton. Done on
## skeleton-space poses so it holds whatever the bones' local axes are:
## G'(mate) = M G M K, with M the X reflection and K a per-bone constant that
## makes the mirrored rest pose equal the real rest pose of the mate bone.
static func mirror(src: Animation, sk: Skeleton3D) -> Animation:
	var nb := sk.get_bone_count()
	var mate := PackedInt32Array()
	mate.resize(nb)
	for b in nb:
		var nm := sk.get_bone_name(b)
		var other := nm
		if "Left" in nm:
			other = nm.replace("Left", "Right")
		elif "Right" in nm:
			other = nm.replace("Right", "Left")
		var o := sk.find_bone(other)
		mate[b] = o if o >= 0 else b
	var rot_tr := {}
	var pos_tr := {}
	var prefix := "Skeleton3D"
	for tr in src.get_track_count():
		var path := str(src.track_get_path(tr))
		var bi := sk.find_bone(path.get_slice(":", 1))
		if bi < 0:
			continue
		prefix = path.get_slice(":", 0)
		match src.track_get_type(tr):
			Animation.TYPE_ROTATION_3D:
				rot_tr[bi] = tr
			Animation.TYPE_POSITION_3D:
				pos_tr[bi] = tr
	var m := Transform3D(Basis.from_scale(Vector3(-1, 1, 1)), Vector3.ZERO)
	var rest_g := []
	for b in nb:
		rest_g.append(sk.get_bone_global_rest(b))
	var k_fix := []
	for s in nb:
		k_fix.append((m * (rest_g[s] as Transform3D) * m).affine_inverse() * (rest_g[mate[s]] as Transform3D))
	var out := Animation.new()
	out.length = src.length
	out.loop_mode = src.loop_mode
	var out_rot := {}
	var out_pos := {}
	for t in nb:
		var s := mate[t]
		if rot_tr.has(s):
			var nt := out.add_track(Animation.TYPE_ROTATION_3D)
			out.track_set_path(nt, NodePath("%s:%s" % [prefix, sk.get_bone_name(t)]))
			out.track_set_interpolation_type(nt, Animation.INTERPOLATION_LINEAR)
			out_rot[t] = nt
		if pos_tr.has(s):
			var np := out.add_track(Animation.TYPE_POSITION_3D)
			out.track_set_path(np, NodePath("%s:%s" % [prefix, sk.get_bone_name(t)]))
			out.track_set_interpolation_type(np, Animation.INTERPOLATION_LINEAR)
			out_pos[t] = np
	var frames := maxi(2, ceili(src.length * 60.0))
	for f in frames + 1:
		var time := minf(src.length * float(f) / frames, src.length)
		# Source local + global poses.
		var local := []
		var glob := []
		glob.resize(nb)
		for b in nb:
			var rest := sk.get_bone_rest(b)
			var q := rest.basis.get_rotation_quaternion()
			var p := rest.origin
			if rot_tr.has(b):
				q = src.rotation_track_interpolate(rot_tr[b], time)
			if pos_tr.has(b):
				p = src.position_track_interpolate(pos_tr[b], time)
			local.append(Transform3D(Basis(q), p))
		var done := PackedByteArray()
		done.resize(nb)
		for b in nb:
			_global_of(b, sk, local, glob, done)
		# Mirrored globals per target bone, then back to locals.
		var mg := []
		mg.resize(nb)
		for t in nb:
			var s := mate[t]
			mg[t] = m * (glob[s] as Transform3D) * m * (k_fix[s] as Transform3D)
		for t in nb:
			var par := sk.get_bone_parent(t)
			var l: Transform3D = (mg[par] as Transform3D).affine_inverse() * (mg[t] as Transform3D) if par >= 0 else (mg[t] as Transform3D)
			if out_rot.has(t):
				out.rotation_track_insert_key(out_rot[t], time, l.basis.get_rotation_quaternion())
			if out_pos.has(t):
				out.position_track_insert_key(out_pos[t], time, l.origin)
	return out


static func _global_of(b: int, sk: Skeleton3D, local: Array, glob: Array, done: PackedByteArray) -> Transform3D:
	if done[b]:
		return glob[b]
	var par := sk.get_bone_parent(b)
	var g: Transform3D = local[b] if par < 0 else _global_of(par, sk, local, glob, done) * (local[b] as Transform3D)
	glob[b] = g
	done[b] = 1
	return g
