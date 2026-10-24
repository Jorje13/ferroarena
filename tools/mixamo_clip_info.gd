extends SceneTree
## For each in-place locomotion clip: length, phase (time when the left foot is
## furthest along the motion direction) and ground speed (speed of the planted
## foot relative to the hips). Forward kinematics straight from the tracks.
## Usage: -s tools/mixamo_clip_info.gd

const DIR := "res://assets/mixamo/anims/"
## clip -> motion direction in model space (+Z forward, +X = character's left)
const CLIPS := {
	"rifle_walk": Vector3(0, 0, 1), "rifle_run": Vector3(0, 0, 1), "rifle_sprint": Vector3(0, 0, 1),
	"run_backwards": Vector3(0, 0, -1), "strafe_left_run": Vector3(1, 0, 0), "strafe_right_run": Vector3(-1, 0, 0),
	"strafe_right": Vector3(-1, 0, 0), "crouch_walking": Vector3(0, 0, 1), "crawling": Vector3(0, 0, 1),
}
var sk: Skeleton3D


func _init() -> void:
	for clip in CLIPS:
		var scene := (load(DIR + clip + ".fbx") as PackedScene).instantiate()
		sk = scene.find_children("*", "Skeleton3D", true, false)[0]
		var ap := scene.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
		var a := ap.get_animation(ap.get_animation_list()[0])
		var dir: Vector3 = CLIPS[clip]
		var n := 120
		var best := -INF
		var best_t := 0.0
		var speeds := []
		var prev_l := Vector3.ZERO
		var prev_r := Vector3.ZERO
		var dt := a.length / n
		for i in n + 1:
			var t := a.length * i / n
			var l := _pos(a, "mixamorig_LeftFoot", t) - _pos(a, "mixamorig_Hips", t) * Vector3(1, 0, 1)
			var r := _pos(a, "mixamorig_RightFoot", t) - _pos(a, "mixamorig_Hips", t) * Vector3(1, 0, 1)
			var d := (l - r).dot(dir)
			if i < n and d > best:
				best = d
				best_t = t
			if i > 0:
				# Planted foot = the lower one; it slides opposite to the motion.
				var foot := l if l.y < r.y else r
				var prev := prev_l if l.y < r.y else prev_r
				speeds.append(-(foot - prev).dot(dir) / dt)
			prev_l = l
			prev_r = r
		speeds.sort()
		var med: float = speeds[speeds.size() / 2]
		var lo := INF
		for i in n:
			var tt := a.length * i / n
			lo = minf(lo, (_pos(a, "mixamorig_LeftFoot", tt) - _pos(a, "mixamorig_RightFoot", tt)).dot(dir))
		print("%s len=%.3f left_fwd_t=%.3f planted=%.2f sep=%.2f..%.2f step_speed=%.2f" % [clip, a.length, best_t, med, lo, best, (best - lo) / a.length])
		scene.free()
	quit()


func _pos(a: Animation, bone: String, t: float) -> Vector3:
	var idx := sk.find_bone(bone)
	var xf := Transform3D()
	while idx >= 0:
		xf = _local(a, idx, t) * xf
		idx = sk.get_bone_parent(idx)
	return xf.origin


func _local(a: Animation, idx: int, t: float) -> Transform3D:
	var rest := sk.get_bone_rest(idx)
	var pos := rest.origin
	var rot := rest.basis.get_rotation_quaternion()
	var bname := sk.get_bone_name(idx)
	for tr in a.get_track_count():
		if String(a.track_get_path(tr)).get_slice(":", 1) != bname:
			continue
		match a.track_get_type(tr):
			Animation.TYPE_POSITION_3D:
				pos = a.position_track_interpolate(tr, t)
			Animation.TYPE_ROTATION_3D:
				rot = a.rotation_track_interpolate(tr, t)
	return Transform3D(Basis(rot), pos)
