extends SceneTree
## Compares the trooper with a retargeted skin on baked clips: row 0 = trooper, row 1.. = skins.
## Usage (windowed): -s tools/skin_sheet.gd -- --skins=1,2 --clips=loco_run,st_vault --t=0.3 --view=side --out=C:/x/sheet.png

const TILE := Vector2i(300, 440)


func _initialize() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv: PackedStringArray = a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.32, 0.36, 0.4)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.72, 0.75)
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 30, 0)
	root.add_child(sun)
	var cam := Camera3D.new()
	cam.fov = 40.0
	root.add_child(cam)
	cam.make_current()
	var skins := [0]
	for s in str(args.get("skins", "1")).split(","):
		skins.append(int(s))
	var clips := str(args.get("clips", "loco_run")).split(",")
	var t := float(args.get("t", 0.0))
	var view := str(args.get("view", "side"))
	var dist := float(args.get("dist", 4.2))
	var cy := float(args.get("cy", 0.9))
	var dir := {"front": Vector3(0, 0, 1), "side": Vector3(-1, 0, 0), "back": Vector3(0, 0, -1), "left": Vector3(1, 0, 0)}[view] as Vector3
	cam.global_position = Vector3(0, cy, 0) + dir * dist
	cam.look_at(Vector3(0, cy, 0))
	var sheet := Image.create(TILE.x * clips.size(), TILE.y * skins.size(), false, Image.FORMAT_RGBA8)
	for r in skins.size():
		var skin: int = skins[r]
		var model := CharacterModel.create_body(skin)
		root.add_child(model)
		var lib := CharacterRig._skin_library(skin)
		var ap := AnimationPlayer.new()
		model.add_child(ap)
		ap.root_node = NodePath("..")
		ap.add_animation_library("", lib)
		for c in clips.size():
			ap.play(clips[c])
			ap.seek(t, true)
			await process_frame
			await process_frame
			await RenderingServer.frame_post_draw
			var img := root.get_texture().get_image()
			img.convert(Image.FORMAT_RGBA8)
			sheet.blit_rect(img, Rect2i((img.get_size() - TILE) / 2, TILE), Vector2i(TILE.x * c, TILE.y * r))
		model.queue_free()
		await process_frame
	sheet.save_png(str(args.get("out", "sheet.png")))
	print("[SHEET] saved ", args.get("out"))
	quit()
