extends SceneTree
## Prints the Hips position track of a trooper clip and of a Meshy GLB animation, plus rest data.
## Usage: -s tools/hips_probe.gd -- --file=x.glb --anim=Walking


func _initialize() -> void:
	var path := ""
	var an := "Walking"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--file="):
			path = a.get_slice("=", 1)
		elif a.begins_with("--anim="):
			an = a.get_slice("=", 1)
	var tr_scene := (load("res://assets/mixamo/trooper.fbx") as PackedScene).instantiate()
	root.add_child(tr_scene)
	var tsk := tr_scene.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	print("trooper skeleton node path: ", tr_scene.get_path_to(tsk), " scale ", tsk.scale, " xform ", tsk.global_transform)
	var h := tsk.find_bone("mixamorig_Hips")
	print("trooper hips rest local ", tsk.get_bone_rest(h).origin, " global ", tsk.get_bone_global_rest(h).origin)
	var lib := CharacterModel.mixamo_library()
	for c in ["rifle_idle", "rifle_run"]:
		var a := lib.get_animation(c)
		var t := a.find_track(NodePath("Skeleton3D:mixamorig_Hips"), Animation.TYPE_POSITION_3D)
		print("trooper clip ", c, " len ", a.length, " hips pos t0 ", a.position_track_interpolate(t, 0.0), " t.3 ", a.position_track_interpolate(t, 0.3))
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	doc.append_from_file(path, st)
	var sc := doc.generate_scene(st)
	root.add_child(sc)
	var sk := sc.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var mh := sk.find_bone("mixamorig_Hips")
	print("meshy hips rest local ", sk.get_bone_rest(mh).origin, " global ", sk.get_bone_global_rest(mh).origin, " skel scale ", sk.scale, " parent ", sk.get_parent().name, " ", (sk.get_parent() as Node3D).transform)
	var ap := sc.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	var a := ap.get_animation(an)
	for i in a.get_track_count():
		var p := str(a.track_get_path(i))
		if p.ends_with("Hips") or p.ends_with("Spine") or p.ends_with("LeftArm"):
			print("meshy track ", i, " ", p, " type ", a.track_get_type(i), " keys ", a.track_get_key_count(i), " v0 ", a.track_get_key_value(i, 0))
	print("trooper height probe: head global ", tsk.get_bone_global_rest(tsk.find_bone("mixamorig_Head")).origin)
	quit()
