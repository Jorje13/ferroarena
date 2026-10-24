extends SceneTree
## Contact sheet of a Mixamo clip on the trooper: one tile per time.
## Usage (windowed, not headless):
##   -s tools/pose_sheet.gd -- --clip=rifle_jump --times=0,0.1,0.2 --view=front --out=C:/x/sheet.png [--mirror] [--lib=name]
## view: front | side (character's right) | back. --lib=st_xxx / loco_xxx reads a baked clip.

const TILE := Vector2i(420, 640)


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
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(6, 6)
	floor_mi.mesh = pm
	root.add_child(floor_mi)
	var model: Node3D = CharacterModel.create_trooper()
	root.add_child(model)
	var clip: String = str(args.get("clip", "rifle_idle"))
	var anim := (load("res://assets/mixamo/anims/%s.fbx" % clip) as PackedScene).instantiate().find_children("*", "AnimationPlayer", true, false)[0].get_animation(
		((load("res://assets/mixamo/anims/%s.fbx" % clip) as PackedScene).instantiate().find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer).get_animation_list()[0]) as Animation
	anim = anim.duplicate(true)
	CharacterModel._strip_root_motion(anim)
	if args.has("mirror"):
		anim = AnimMirror.mirror(anim, model.find_children("*", "Skeleton3D", true, false)[0])
	var ap := AnimationPlayer.new()
	model.add_child(ap)
	ap.root_node = NodePath("..")
	var l := AnimationLibrary.new()
	l.add_animation("c", anim)
	ap.add_animation_library("", l)
	var cam := Camera3D.new()
	cam.fov = 40.0
	root.add_child(cam)
	cam.make_current()
	await process_frame
	var view := str(args.get("view", "front"))
	var dist := float(args.get("dist", 5.0))
	var cy := float(args.get("cy", 0.95))
	# Model faces +Z; its right side is -X.
	var dir := {"front": Vector3(0, 0, 1), "side": Vector3(-1, 0, 0), "back": Vector3(0, 0, -1), "left": Vector3(1, 0, 0)}[view] as Vector3
	cam.global_position = Vector3(0, cy, 0) + dir * dist
	cam.look_at(Vector3(0, cy, 0))
	print("[SHEET] cam ", cam.global_position, " fwd ", -cam.global_basis.z, " model ", model.global_position, " in_tree ", model.is_inside_tree(), " size ", root.size)
	var times := str(args.get("times", "0")).split_floats(",")
	var sheet := Image.create(TILE.x * times.size(), TILE.y, false, Image.FORMAT_RGBA8)
	ap.play("c")
	for i in times.size():
		ap.seek(times[i], true)
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		var img := root.get_texture().get_image()
		img.convert(Image.FORMAT_RGBA8)
		sheet.blit_rect(img, Rect2i((img.get_size() - TILE) / 2, TILE), Vector2i(TILE.x * i, 0))
	sheet.save_png(str(args.get("out", "sheet.png")))
	print("[SHEET] saved ", args.get("out"))
	quit()
