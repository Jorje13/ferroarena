extends SceneTree
## Rewrites a static GLB with its textures capped at --max px (JPEG, or PNG for images with an
## alpha channel): Meshy exports embed 4K PNGs that push a prop past GitHub's 100 MB file limit.
## Usage: Godot --headless -s tools/shrink_glb.gd -- --file=abs/in.glb --out=abs/out.glb [--max=2048]


func _initialize() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var p := a.trim_prefix("--").split("=", true, 1)
		args[p[0]] = p[1] if p.size() > 1 else ""
	var limit := int(args.get("max", "2048"))
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(str(args.file), state) != OK:
		print("[SHRINK] lecture impossible")
		quit(1)
		return
	var scene := doc.generate_scene(state)
	var done := {}
	for mi: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
		for s in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(s) as BaseMaterial3D
			if m == null:
				continue
			for slot in [BaseMaterial3D.TEXTURE_ALBEDO, BaseMaterial3D.TEXTURE_NORMAL, BaseMaterial3D.TEXTURE_ORM,
					BaseMaterial3D.TEXTURE_ROUGHNESS, BaseMaterial3D.TEXTURE_METALLIC, BaseMaterial3D.TEXTURE_EMISSION, BaseMaterial3D.TEXTURE_AMBIENT_OCCLUSION]:
				var tex := m.get_texture(slot)
				if tex == null or done.has(tex):
					continue
				done[tex] = true
				var img := tex.get_image()
				if img == null:
					continue
				if img.is_compressed():
					img.decompress()
				var w := img.get_width()
				var h := img.get_height()
				if maxi(w, h) > limit:
					var k := float(limit) / maxi(w, h)
					img.resize(int(w * k), int(h * k), Image.INTERPOLATE_LANCZOS)
				m.set_texture(slot, ImageTexture.create_from_image(img))
				print("[SHRINK] texture %dx%d -> %dx%d" % [w, h, img.get_width(), img.get_height()])
	var out_doc := GLTFDocument.new()
	out_doc.image_format = "JPEG"
	out_doc.lossy_quality = 0.9
	var out_state := GLTFState.new()
	if out_doc.append_from_scene(scene, out_state) != OK or out_doc.write_to_filesystem(out_state, str(args.out)) != OK:
		print("[SHRINK] écriture impossible")
		quit(1)
		return
	print("[SHRINK] écrit %s (%.1f Mo)" % [args.out, FileAccess.get_file_as_bytes(str(args.out)).size() / 1048576.0])
	quit()
