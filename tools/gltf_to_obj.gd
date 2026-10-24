extends SceneTree
## Converts a (static) glTF into one OBJ + MTL with world transforms baked,
## Y-up, metres. Material names are kept so textures can be re-applied later.
## Usage: Godot --headless --path . -s tools/gltf_to_obj.gd -- --in=scene.gltf --out=dir/name

func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var p := a.trim_prefix("--").split("=", true, 1)
		args[p[0]] = p[1] if p.size() > 1 else ""
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(str(args["in"]), state) != OK:
		print("FAIL load")
		quit(1)
		return
	var scene := doc.generate_scene(state) as Node3D
	root.add_child(scene)
	await process_frame
	var out := str(args["out"])
	var obj := FileAccess.open(out + ".obj", FileAccess.WRITE)
	var mtl := FileAccess.open(out + ".mtl", FileAccess.WRITE)
	obj.store_line("mtllib %s.mtl" % out.get_file())
	var base_v := 1
	var mats := {}
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	for mi: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
		var xf := mi.global_transform
		var nb := xf.basis.inverse().transposed()
		for s in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			var uvs: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			var mat := mi.mesh.surface_get_material(s)
			var mname := mat.resource_name if mat and mat.resource_name != "" else "mat_%d" % mats.size()
			mats[mname] = true
			obj.store_line("o %s_%d" % [mi.name, s])
			for v in verts:
				var w := xf * v
				lo = lo.min(w)
				hi = hi.max(w)
				obj.store_line("v %f %f %f" % [w.x, w.y, w.z])
			for uv in uvs:
				obj.store_line("vt %f %f" % [uv.x, 1.0 - uv.y])
			for n in norms:
				var wn := (nb * n).normalized()
				obj.store_line("vn %f %f %f" % [wn.x, wn.y, wn.z])
			obj.store_line("usemtl %s" % mname)
			if idx.is_empty():
				idx.resize(verts.size())
				for i in verts.size():
					idx[i] = i
			# Godot uses clockwise front faces; OBJ expects counter-clockwise.
			for t in range(0, idx.size(), 3):
				var a := idx[t] + base_v
				var b := idx[t + 2] + base_v
				var c := idx[t + 1] + base_v
				obj.store_line("f %d/%d/%d %d/%d/%d %d/%d/%d" % [a, a, a, b, b, b, c, c, c])
			base_v += verts.size()
	for m in mats:
		mtl.store_line("newmtl %s" % m)
		mtl.store_line("Kd 1 1 1")
		mtl.store_line("map_Kd %s_baseColor.png" % m)
		mtl.store_line("")
	print("OK verts=%d mats=%s bounds=%s .. %s" % [base_v - 1, mats.keys(), lo, hi])
	quit()
