extends SceneTree
## Lists, for each FBX in a folder: meshes, skeleton bone count, first bones,
## animation names/lengths and hips motion (to check "In Place").
## Usage: Godot --headless --path . -s tools/inspect_fbx.gd -- --dir=path

func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var dir := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--dir="):
			dir = a.substr(6)
	for f in DirAccess.get_files_at(dir):
		if not f.to_lower().ends_with(".fbx"):
			continue
		var doc := FBXDocument.new()
		var state := FBXState.new()
		if doc.append_from_file(dir + "/" + f, state) != OK:
			print("FAIL ", f)
			continue
		var scene := doc.generate_scene(state)
		root.add_child(scene)
		var meshes := scene.find_children("*", "MeshInstance3D", true, false).size()
		var sks := scene.find_children("*", "Skeleton3D", true, false)
		var bones := 0
		var names := []
		var hips_y := 0.0
		if not sks.is_empty():
			var sk := sks[0] as Skeleton3D
			bones = sk.get_bone_count()
			for i in mini(4, bones):
				names.append(sk.get_bone_name(i))
			var h := sk.find_bone("mixamorig_Hips")
			if h < 0:
				h = sk.find_bone("mixamorig:Hips")
			if h >= 0:
				hips_y = (sk.global_transform * sk.get_bone_global_rest(h)).origin.y
		var anims := []
		for ap: AnimationPlayer in scene.find_children("*", "AnimationPlayer", true, false):
			for an in ap.get_animation_list():
				var anim := ap.get_animation(an)
				var travel := 0.0
				for t in anim.get_track_count():
					var path := str(anim.track_get_path(t))
					if path.contains("Hips") and anim.track_get_type(t) == Animation.TYPE_POSITION_3D and anim.track_get_key_count(t) > 1:
						var p0: Vector3 = anim.track_get_key_value(t, 0)
						var p1: Vector3 = anim.track_get_key_value(t, anim.track_get_key_count(t) - 1)
						travel = Vector2(p1.x - p0.x, p1.z - p0.z).length()
				anims.append("%s %.2fs travel=%.2f" % [an, anim.length, travel])
		print("%s | meshes=%d bones=%d %s hips_y=%.2f | %s" % [f, meshes, bones, names, hips_y, anims])
		scene.queue_free()
	quit()
