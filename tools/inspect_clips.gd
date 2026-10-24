extends SceneTree
## Dev tool: how much do key UAL clips move the pelvis (root motion baked into
## the hips or not), and how long are they.

const CLIPS := {
	"ual1": ["Idle", "Walk", "Jog_Fwd", "Sprint", "Crouch_Fwd", "Roll", "Jump", "Jump_Start", "Jump_Land"],
	"ual2": ["Slide", "Slide_Start", "Slide_Exit", "ClimbUp_1m", "NinjaJump_Land", "Hit_Knockback"],
}


func _init() -> void:
	for lib_name in CLIPS:
		var lib := CharacterModel.library(lib_name)
		for clip in CLIPS[lib_name]:
			var a := lib.get_animation(clip)
			if a == null:
				print("MISSING ", lib_name, "/", clip)
				continue
			var line := "%s/%-14s len=%.2f loop=%d" % [lib_name, clip, a.length, a.loop_mode]
			for bone in ["root", "pelvis"]:
				var t := a.find_track(NodePath("Armature/Skeleton3D:" + bone), Animation.TYPE_POSITION_3D)
				if t < 0:
					line += "  %s:-" % bone
					continue
				var p0 := a.position_track_interpolate(t, 0.0)
				var p1 := a.position_track_interpolate(t, a.length)
				var mn := p0
				var mx := p0
				for i in 21:
					var p := a.position_track_interpolate(t, a.length * i / 20.0)
					mn = mn.min(p)
					mx = mx.max(p)
				line += "  %s: start=%s end=%s min=%s max=%s" % [bone, _v(p0), _v(p1), _v(mn), _v(mx)]
			print(line)
	quit()


func _v(v: Vector3) -> String:
	return "(%.2f,%.2f,%.2f)" % [v.x, v.y, v.z]
