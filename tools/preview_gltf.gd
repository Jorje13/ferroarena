extends SceneTree
## Renders glTF files (absolute paths, loaded at runtime) to PNGs for a quick look.
## Usage: Godot --path . -s tools/preview_gltf.gd -- --files=a.gltf,b.gltf --out=dir

var _items := []


func _init() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var p := a.trim_prefix("--").split("=", true, 1)
		args[p[0]] = p[1] if p.size() > 1 else ""
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.32, 0.34, 0.37)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.55, 0.57, 0.6)
	env.environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 35, 0)
	sun.light_energy = 1.6
	root.add_child(sun)
	for f in str(args.get("files", "")).split(","):
		_items.append(f)
	_run.call_deferred(str(args.get("out", ".")))


func _run(out: String) -> void:
	var i := 0
	for f in _items:
		var doc := GLTFDocument.new()
		var state := GLTFState.new()
		if doc.append_from_file(f, state) != OK:
			print("FAIL ", f)
			continue
		var scene := doc.generate_scene(state) as Node3D
		root.add_child(scene)
		var aabb := _aabb(scene)
		print("%s aabb pos=%s size=%s" % [f.get_file(), aabb.position, aabb.size])
		var cam := Camera3D.new()
		root.add_child(cam)
		var c := aabb.get_center()
		var r := aabb.size.length()
		for view in 2:
			var dir := Vector3(0.6, 0.25, 1.0).normalized() if view == 0 else Vector3(-0.9, 0.15, -0.5).normalized()
			cam.look_at_from_position(c + dir * r * 1.05, c)
			cam.fov = 40
			await process_frame
			await process_frame
			await process_frame
			root.get_viewport().get_texture().get_image().save_png("%s/view_%d_%d.png" % [out, i, view])
		scene.queue_free()
		cam.queue_free()
		await process_frame
		i += 1
	quit()


func _aabb(n: Node) -> AABB:
	var box := AABB()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = (mi as MeshInstance3D).global_transform * (mi as MeshInstance3D).get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box
