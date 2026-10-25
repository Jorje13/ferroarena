extends Node
## 1. Profile of each rifle in the gun frame (forward -Z, origin at the trigger): per 2 cm slice
##    along Z, the X / Y extents. Locates the butt plate and the stock line.
## 2. Front of each body's torso in the chest frame (spine_03 origin, skeleton axes: +Z forward,
##    -X right), around the shoulder pockets, plus the shoulder joints.
## Usage: Godot --path . -- --run_tool=res://tools/stock_profile.gd


func _ready() -> void:
	for w in 3:
		var rig := CharacterRig.new()
		add_child(rig)
		rig.setup(0, "", {"weapon": w})
		var inv := rig.gun.global_transform.affine_inverse()
		var bins := {}
		for mi: MeshInstance3D in rig.gun.find_children("*", "MeshInstance3D", true, false):
			var xf := inv * mi.global_transform
			for s in mi.mesh.get_surface_count():
				var verts: PackedVector3Array = mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
				for v0 in verts:
					var v := xf * v0
					var k := int(floor(v.z * 50.0))
					if not bins.has(k):
						bins[k] = [INF, -INF, INF, -INF]
					var b: Array = bins[k]
					b[0] = minf(b[0], v.x)
					b[1] = maxf(b[1], v.x)
					b[2] = minf(b[2], v.y)
					b[3] = maxf(b[3], v.y)
		var keys := bins.keys()
		keys.sort()
		print("== weapon %d grip_r %s grip_l %s muzzle %s" % [w, rig.grip_r.position, rig.grip_l.position, rig.muzzle.position])
		for k in keys:
			if k < -8:
				continue
			var b: Array = bins[k]
			print("z %+.2f  x[%+.3f..%+.3f]  y[%+.3f..%+.3f]" % [k / 50.0, b[0], b[1], b[2], b[3]])
		rig.free()
	var torso := ["Hips", "Spine", "Spine1", "Spine2", "Neck", "LeftShoulder", "RightShoulder"]
	for skin in 6:
		var body := CharacterModel.create_body(skin)
		add_child(body)
		var sk := body.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
		var ch := sk.get_bone_global_rest(sk.find_bone("mixamorig_Spine2"))
		var cf := Transform3D(Basis(), ch.origin).affine_inverse()
		var keep := {}
		for n in torso:
			keep[sk.find_bone("mixamorig_" + n)] = true
		var grid := {}
		for mi: MeshInstance3D in body.find_children("*", "MeshInstance3D", true, false):
			if mi.skin == null:
				continue
			var slot := {}
			for i in mi.skin.get_bind_count():
				slot[i] = sk.find_bone(mi.skin.get_bind_name(i)) if String(mi.skin.get_bind_name(i)) != "" else mi.skin.get_bind_bone(i)
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
					if not keep.has(bb):
						continue
					var p := cf * (mi.skin.get_bind_pose(0).affine_inverse() * mi.skin.get_bind_pose(0) * verts[v])
					var key := Vector2i(int(floor(p.x * 25.0)), int(floor(p.y * 25.0)))
					grid[key] = maxf(grid.get(key, -INF), p.z)
		var rows := []
		for n in ["RightShoulder", "RightArm", "LeftArm", "Neck", "Head"]:
			rows.append("%s %s" % [n, str((cf * sk.get_bone_global_rest(sk.find_bone("mixamorig_" + n)).origin).snapped(Vector3.ONE * 0.01))])
		print("== skin %d  %s" % [skin, "  ".join(rows)])
		for yi in range(8, -8, -1):
			var line := "y %+.2f :" % (yi / 25.0)
			for xi in range(-7, 7):
				var z: float = grid.get(Vector2i(xi, yi), -INF)
				line += ("  %+.2f" % z) if z > -INF else "    -- "
			print(line)
		print("   x cols: -0.28 .. +0.24 by 0.04 (right side is -X)")
		body.free()
	get_tree().quit()
