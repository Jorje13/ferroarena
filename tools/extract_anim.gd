extends SceneTree
## Saves the (first) animation of imported FBX scenes as standalone .res files,
## so animations downloaded "with skin" don't keep their mesh in the project.
## Usage: -s tools/extract_anim.gd -- --src=res://dir/ --dst=res://dir/ --names=a,b

func _init() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var p := a.trim_prefix("--").split("=", true, 1)
		args[p[0]] = p[1] if p.size() > 1 else ""
	for n in str(args["names"]).split(","):
		var scene := (load(str(args["src"]) + n + ".fbx") as PackedScene).instantiate()
		var ap := scene.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
		var anim := ap.get_animation(ap.get_animation_list()[0]).duplicate(true) as Animation
		var out := str(args["dst"]) + n + ".res"
		print("%s -> %s (%.2fs, %d tracks) err=%d" % [n, out, anim.length, anim.get_track_count(), ResourceSaver.save(anim, out)])
		scene.free()
	quit()
