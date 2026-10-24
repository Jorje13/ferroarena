extends SceneTree
## Where do the hand's fingers really point? For a skinned GLB: centroid + far end of the
## vertices weighted to the finger bones, in the hand bone's rest frame.
## Usage: -s tools/hand_axes.gd -- --file=res://assets/characters/sentinel.glb


func _initialize() -> void:
	var path := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--file="):
			path = a.get_slice("=", 1)
	var scene := (load(path) as PackedScene).instantiate()
	root.add_child(scene)
	var sk := scene.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var mi := scene.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	var arrays: Array = mi.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var per := bones.size() / verts.size()
	var skin := mi.skin
	# Mesh bone slot -> skeleton bone index.
	var slot_bone := {}
	for i in skin.get_bind_count():
		slot_bone[i] = sk.find_bone(skin.get_bind_name(i)) if String(skin.get_bind_name(i)) != "" else skin.get_bind_bone(i)
	for side in ["Left", "Right"]:
		var hand := sk.find_bone("mixamorig_%sHand" % side)
		var hrest := sk.get_bone_global_rest(hand)
		var fingers := {}
		for b in sk.get_bone_count():
			var nm := sk.get_bone_name(b)
			if nm.begins_with("mixamorig_%sHand" % side) and nm != "mixamorig_%sHand" % side:
				fingers[b] = true
		var sum := Vector3.ZERO
		var n := 0
		var pts := []
		for v in verts.size():
			var w := 0.0
			for j in per:
				if fingers.has(slot_bone.get(bones[v * per + j], -1)):
					w += weights[v * per + j]
			if w > 0.5:
				var local := hrest.affine_inverse() * verts[v]
				sum += local
				n += 1
				pts.append(local)
		if n == 0:
			var hs := Vector3.ZERO
			var hn := 0
			var hfar := Vector3.ZERO
			for v in verts.size():
				var w2 := 0.0
				for j in per:
					if slot_bone.get(bones[v * per + j], -1) == hand:
						w2 += weights[v * per + j]
				if w2 > 0.5:
					var lc := hrest.affine_inverse() * verts[v]
					if lc.length() > 0.07:
						hs += lc
						hn += 1
						if lc.length() > hfar.length():
							hfar = lc
			print("[HAND] %s hand-only verts %d centroid %s far %s" % [side, hn, str((hs / maxf(hn, 1)).snapped(Vector3.ONE * 0.001)), str(hfar.snapped(Vector3.ONE * 0.001))])
			print("[HAND] %s : no finger vertices" % side)
			continue
		var c := sum / n
		var far := Vector3.ZERO
		for p in pts:
			if (p as Vector3).length() > far.length():
				far = p
		print("[HAND] %s verts %d centroid %s dir %s far %s" % [side, n, str(c.snapped(Vector3.ONE * 0.001)), str(c.normalized().snapped(Vector3.ONE * 0.01)), str(far.snapped(Vector3.ONE * 0.001))])
	quit()
