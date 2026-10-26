extends Node
## Measures each monster's head and torso from its skinned mesh at rest (scale 1, model space):
## vertices whose dominant bone is the head (or below it) -> centre and radius in the head
## bone's frame (through the skin's bind pose); torso vertices (hips..neck) -> radius around the spine.
## Usage: Godot --path . -- --run_tool=res://tools/monster_head.gd


func _ready() -> void:
	for k in MonsterRig.KINDS.size():
		var data: Dictionary = MonsterRig.KINDS[k]
		var model := (load(data.scene) as PackedScene).instantiate() as Node3D
		add_child(model)
		var sk := model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
		var head := int(data.head)
		var torso := [int(data.hips)] + Array(data.spine) + [int(data.neck)]
		var head_set := {}
		for b in sk.get_bone_count():
			var p := b
			while p >= 0:
				if p == head:
					head_set[b] = true
					break
				p = sk.get_bone_parent(p)
		var hrest := sk.get_bone_global_rest(head)
		var pts: Array[Vector3] = []
		var tpts: Array[Vector3] = []
		for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
			if mi.skin == null:
				continue
			var slot := {}
			var head_bind := Transform3D()
			for i in mi.skin.get_bind_count():
				var bi := sk.find_bone(String(mi.skin.get_bind_name(i))) if String(mi.skin.get_bind_name(i)) != "" else mi.skin.get_bind_bone(i)
				if bi == head:
					head_bind = mi.skin.get_bind_pose(i)
				var bn := String(mi.skin.get_bind_name(i))
				slot[i] = sk.find_bone(bn) if bn != "" else mi.skin.get_bind_bone(i)
			var to_sk := sk.global_transform.affine_inverse() * mi.global_transform
			for s in mi.mesh.get_surface_count():
				var arr := mi.mesh.surface_get_arrays(s)
				var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
				var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
				var weights: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
				if bones.is_empty():
					continue
				var per := bones.size() / verts.size()
				for v in verts.size():
					var best := -1.0
					var bb := -1
					for j in per:
						if weights[v * per + j] > best:
							best = weights[v * per + j]
							bb = slot.get(bones[v * per + j], -1)
					if head_set.has(bb):
						# Bind pose: mesh space -> head bone space (the mesh may be bound in another pose than the rest).
						pts.append(head_bind * verts[v])
					elif bb in torso:
						tpts.append(to_sk * verts[v])
		var c := Vector3.ZERO
		for p in pts:
			c += p
		c /= maxf(pts.size(), 1)
		var dists := []
		for p in pts:
			dists.append(p.distance_to(c))
		dists.sort()
		var hips := sk.get_bone_global_rest(int(data.hips)).origin
		var neck := sk.get_bone_global_rest(int(data.neck)).origin
		var ax := (neck - hips).normalized()
		var td := []
		for p in tpts:
			var q := p - hips
			td.append((q - ax * q.dot(ax)).length())
		td.sort()
		print("[HEAD] %s verts %d centre(head frame) %s r50 %.3f r90 %.3f | head-neck %.3f | torso r50 %.3f r80 %.3f hips->neck %.3f" % [data.id, pts.size(), str(c.snapped(Vector3.ONE * 0.001)),
			dists[dists.size() / 2] if dists else 0.0, dists[int(dists.size() * 0.9)] if dists else 0.0,
			sk.get_bone_global_rest(head).origin.distance_to(neck), td[td.size() / 2] if td else 0.0, td[int(td.size() * 0.8)] if td else 0.0, hips.distance_to(neck)])
	get_tree().quit()
