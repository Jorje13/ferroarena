extends SceneTree
## Prints the hips position keys of a clip and the largest jump between
## consecutive keys (and across the loop seam). -- --clip=name [--baked]

func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var clip := "rifle_sprint"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--clip="):
			clip = a.substr(7)
	var lib := CharacterRig._bake_library()
	var anim := lib.get_animation(clip)
	print("clip %s len=%.3f loop=%d tracks=%d" % [clip, anim.length, anim.loop_mode, anim.get_track_count()])
	for tr in anim.get_track_count():
		var path := str(anim.track_get_path(tr))
		if not path.ends_with("Hips"):
			continue
		var type := anim.track_get_type(tr)
		var n := anim.track_get_key_count(tr)
		var worst := 0.0
		var worst_i := -1
		for i in n:
			var v0 = anim.track_get_key_value(tr, i)
			var v1 = anim.track_get_key_value(tr, (i + 1) % n)
			var d: float = (v1 - v0).length() if type == Animation.TYPE_POSITION_3D else (v0 as Quaternion).angle_to(v1)
			if d > worst:
				worst = d
				worst_i = i
		print("  %s type=%d keys=%d first=%s last=%s worst=%.3f at key %d (t=%.3f)" % [path, type, n, anim.track_get_key_value(tr, 0), anim.track_get_key_value(tr, n - 1), worst, worst_i, anim.track_get_key_time(tr, worst_i)])
	quit()
