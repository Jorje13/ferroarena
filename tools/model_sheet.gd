extends SceneTree
## Contact sheet of a glTF/GLB model seen from several sides (auto-framed).
## Usage (windowed): -s tools/model_sheet.gd -- --file=x.glb --out=sheet.png [--views=xp,xn,zp,top] [--anim=Running --t=0.2] [--rot=deg]
## Views: xp/xn = from +X / -X, zp/zn = from +Z / -Z, top.

var TILE := Vector2i(520, 520)


func _initialize() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv: PackedStringArray = a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	if args.has("tile"):
		TILE = Vector2i(int(str(args.tile).get_slice("x", 0)), int(str(args.tile).get_slice("x", 1)))
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.3, 0.33, 0.37)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.77, 0.8)
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	for r in [Vector3(-40, 30, 0), Vector3(-30, 210, 0)]:
		var sun := DirectionalLight3D.new()
		sun.rotation_degrees = r
		sun.light_energy = 0.9
		root.add_child(sun)
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(str(args.get("file")), state) != OK:
		print("[SHEET] lecture impossible")
		quit()
		return
	var model := doc.generate_scene(state) as Node3D
	root.add_child(model)
	if args.has("rot"):
		model.rotation_degrees.y = float(args.rot)
	if args.has("anim"):
		var ap := model.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
		ap.play(str(args.anim))
		ap.seek(float(args.get("t", 0.0)), true)
	await process_frame
	await process_frame
	# Bounds from the skinned meshes' current pose (or plain meshes).
	var box := AABB()
	var first := true
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		var b := mi.global_transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	var centre := box.get_center()
	var radius := box.size.length() * 0.55
	var cam := Camera3D.new()
	cam.fov = 35.0
	root.add_child(cam)
	cam.make_current()
	var views := str(args.get("views", "xp,zp,top")).split(",")
	var sheet := Image.create(TILE.x * views.size(), TILE.y, false, Image.FORMAT_RGBA8)
	for i in views.size():
		var dir := {"xp": Vector3(1, 0.1, 0), "xn": Vector3(-1, 0.1, 0), "zp": Vector3(0, 0.1, 1), "zn": Vector3(0, 0.1, -1), "top": Vector3(0.001, 1, 0.15)}[views[i]] as Vector3
		cam.global_position = centre + dir.normalized() * radius / tan(deg_to_rad(cam.fov * 0.5)) * float(args.get("zoom", 1.2))
		cam.look_at(centre, Vector3.UP if views[i] != "top" else Vector3.FORWARD)
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		var img := root.get_texture().get_image()
		img.convert(Image.FORMAT_RGBA8)
		sheet.blit_rect(img, Rect2i((img.get_size() - TILE) / 2, TILE), Vector2i(TILE.x * i, 0))
	sheet.save_png(str(args.get("out", "sheet.png")))
	print("[SHEET] saved ", args.get("out"))
	quit()
