extends SceneTree
## Dev tool: rest positions of key bones + mesh vertex format of the base characters.


func _init() -> void:
	for g in ["Male", "Female"]:
		var ps := load("res://assets/quaternius/characters/Superhero_%s_FullBody.gltf" % g) as PackedScene
		var root := ps.instantiate()
		var sk := root.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
		print("== ", g)
		for b in ["root", "pelvis", "spine_01", "spine_03", "neck_01", "Head", "clavicle_r", "upperarm_r", "lowerarm_r", "hand_r", "upperarm_l", "hand_l", "thigh_r", "foot_r", "ball_r"]:
			var i := sk.find_bone(b)
			var t := sk.get_bone_global_rest(i)
			print("  %-12s pos=%s  x=%s y=%s z=%s" % [b, t.origin, t.basis.x.normalized(), t.basis.y.normalized(), t.basis.z.normalized()])
		for mi in root.find_children("*", "MeshInstance3D", true, false):
			var m := (mi as MeshInstance3D).mesh
			var arr: Array = m.surface_get_arrays(0)
			var nv: int = (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
			var nb: int = (arr[Mesh.ARRAY_BONES] as PackedInt32Array).size() if arr[Mesh.ARRAY_BONES] else 0
			var skin := (mi as MeshInstance3D).skin
			print("  mesh %s verts=%d bones/vert=%d fmt=%d blendshapes=%d skin_binds=%d" % [mi.name, nv, nb / maxi(nv, 1), m.surface_get_format(0), m.get_blend_shape_count(), skin.get_bind_count() if skin else -1])
			if skin and mi.name.begins_with("SuperHero"):
				print("    bind0=%s bone0=%d" % [skin.get_bind_name(0), skin.get_bind_bone(0)])
		root.free()
	quit()
