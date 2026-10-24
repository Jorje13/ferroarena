extends SceneTree
## Contact sheet of a monster in several states (windowed).
## Usage: -s tools/monster_sheet.gd -- --kind=0 --states=idle:0,run:3.1,windup:0.4,strike:0.15 --view=side --out=sheet.png
## "name:time" = state held for `time` seconds (a walk/run state moves at its natural speed).

const TILE := Vector2i(420, 560)


func _initialize() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv: PackedStringArray = a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
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
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(10, 10)
	floor_mi.mesh = pm
	root.add_child(floor_mi)
	var rig := MonsterRig.new()
	root.add_child(rig)
	rig.setup(int(args.get("kind", 0)))
	var cam := Camera3D.new()
	cam.fov = 40.0
	root.add_child(cam)
	cam.make_current()
	var view := str(args.get("view", "side"))
	var dist := float(args.get("dist", 6.0))
	var dir := {"front": Vector3(0, 0, 1), "side": Vector3(-1, 0, 0), "back": Vector3(0, 0, -1), "left": Vector3(1, 0, 0), "q": Vector3(-0.8, 0.1, 0.7)}[view] as Vector3
	var states := str(args.get("states", "idle:0.5")).split(",")
	var sheet := Image.create(TILE.x * states.size(), TILE.y, false, Image.FORMAT_RGBA8)
	await process_frame
	cam.global_position = Vector3(0, 1.2, 0) + dir.normalized() * dist
	cam.look_at(Vector3(0, 1.0, 0))
	for i in states.size():
		var nm := states[i].get_slice(":", 0)
		var hold := float(states[i].get_slice(":", 1))
		rig.set_state(nm)
		var vel := 0.0
		if nm == "walk":
			vel = float(rig.data.speed) * 0.55
		elif nm == "run":
			vel = float(rig.data.speed)
		var t := 0.0
		while t < hold:
			var dt := 1.0 / 60.0
			rig.tick(dt, vel, vel * dt)
			t += dt
			await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		var img := root.get_texture().get_image()
		img.convert(Image.FORMAT_RGBA8)
		sheet.blit_rect(img, Rect2i((img.get_size() - TILE) / 2, TILE), Vector2i(TILE.x * i, 0))
	sheet.save_png(str(args.get("out", "sheet.png")))
	print("[SHEET] saved")
	quit()
