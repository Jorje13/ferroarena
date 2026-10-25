class_name RaiderIK
extends SkeletonModifier3D
## Runs after the animation each frame:
## 1. twists the hips towards the movement direction (strafing while aiming),
## 2. bends the spine with the aim pitch and leans it into turns/acceleration,
## 3. places the Ferro relative to the chest (ready / shouldered / slung),
## 4. solves two-bone IK so both hands hold the rifle.
## Skeleton space: the model faces +Z, its right side is -X.

var rig: CharacterRig
var _b := {}


func _bone(n: String) -> int:
	if not _b.has(n):
		_b[n] = get_skeleton().find_bone(CharacterRig.bone_name(n))
	return _b[n]


var _reach := Vector3.ZERO
var _push := Vector3.ZERO
var _slide := 0.0
var _delta_t := 0.016


## Skeleton-space shift that brings both grips within arm's reach.
func _reach_offset(sk: Skeleton3D, inv: Transform3D, gun_s: Transform3D) -> Vector3:
	var sh_r := sk.get_bone_global_pose(_bone("upperarm_r")).origin
	var sh_l := sk.get_bone_global_pose(_bone("upperarm_l")).origin
	var len_r := sh_r.distance_to(sk.get_bone_global_pose(_bone("lowerarm_r")).origin) + sk.get_bone_global_pose(_bone("lowerarm_r")).origin.distance_to(sk.get_bone_global_pose(_bone("hand_r")).origin)
	var len_l := sh_l.distance_to(sk.get_bone_global_pose(_bone("lowerarm_l")).origin) + sk.get_bone_global_pose(_bone("lowerarm_l")).origin.distance_to(sk.get_bone_global_pose(_bone("hand_l")).origin)
	# Short arms first grab the fore-end closer to the receiver, as a real shooter does;
	# whatever is still out of reach moves the rifle.
	var sup := 1 if rig.shoulder_k < 0.5 else 0
	var sup_sh := sh_l if sup == 1 else sh_r
	var sup_reach := (len_l if sup == 1 else len_r) * 0.95
	rig.gun.global_transform = sk.global_transform * gun_s
	var want_slide := 0.0
	while want_slide < CharacterRig.SUPPORT_SLIDE_MAX:
		rig.set_support_slide(want_slide)
		if sup_sh.distance_to(inv * rig.hand_target(sup)) <= sup_reach:
			break
		want_slide += 0.01
	_slide = lerpf(_slide, want_slide, 1.0 - exp(-_delta_t * 15.0))
	rig.set_support_slide(_slide)
	var off := Vector3.ZERO
	for it in 5:
		rig.gun.global_transform = sk.global_transform * (Transform3D(Basis(), off) * gun_s)
		var worst := Vector3.ZERO
		for side in 2:
			var tgt: Vector3 = inv * rig.hand_target(side)
			var sh := sh_r if side == 0 else sh_l
			var reach := (len_r if side == 0 else len_l) * 0.95
			var d := tgt - sh
			if d.length() > reach:
				worst += d.normalized() * (d.length() - reach)
		if worst.length() < 0.002:
			break
		off -= worst * 0.6
	if Game.debug.has("log_reach") and Engine.get_process_frames() % 120 == 0:
		var ch := sk.get_bone_global_pose(_bone("spine_03")).origin
		var gf := CharacterRig.FLIP.inverse()
		print("[BODY] skin %d shR %s shL %s head %s neck %s hips %s" % [rig.skin, str((gf * (sh_r - ch)).snapped(Vector3.ONE * 0.01)), str((gf * (sh_l - ch)).snapped(Vector3.ONE * 0.01)), str((gf * (sk.get_bone_global_pose(_bone("Head")).origin - ch)).snapped(Vector3.ONE * 0.01)), str((gf * (sk.get_bone_global_pose(_bone("neck_01")).origin - ch)).snapped(Vector3.ONE * 0.01)), str((gf * (sk.get_bone_global_pose(_bone("pelvis")).origin - ch)).snapped(Vector3.ONE * 0.01))])
		print("[REACH] skin %d off %s lenR %.2f lenL %.2f dR %.2f dL %.2f" % [rig.skin, str(off.snapped(Vector3.ONE * 0.01)), len_r, len_l,
			sh_r.distance_to(inv * rig.hand_target(0)), sh_l.distance_to(inv * rig.hand_target(1))])
	return off.limit_length(0.4)


func _process_modification_with_delta(delta: float) -> void:
	_delta_t = delta
	var t0 := Time.get_ticks_usec()
	_modify()
	Game.prof_add("ik", t0)


func _modify() -> void:
	var sk := get_skeleton()
	if sk == null or rig == null:
		return
	# 1. Hip twist (legs follow movement, upper body keeps facing the aim).
	var h := rig.hip_yaw
	if absf(h) > 0.001:
		_rotate_global(sk, _bone("pelvis"), Basis(Vector3.UP, h))
		# Counter-twist spread up the spine so a wide strafe twist stays natural.
		_rotate_global(sk, _bone("spine_01"), Basis(Vector3.UP, -h * 0.55))
		_rotate_global(sk, _bone("spine_02"), Basis(Vector3.UP, -h * 0.3))
		_rotate_global(sk, _bone("spine_03"), Basis(Vector3.UP, -h * 0.15))
	# Upper body follows the camera ahead of the legs.
	var tw := rig.torso_twist - rig.blade
	if absf(tw) > 0.001:
		_rotate_global(sk, _bone("spine_01"), Basis(Vector3.UP, tw * 0.3))
		_rotate_global(sk, _bone("spine_02"), Basis(Vector3.UP, tw * 0.35))
		_rotate_global(sk, _bone("spine_03"), Basis(Vector3.UP, tw * 0.35))
	if rig.blade > 0.001:
		_rotate_global(sk, _bone("neck_01"), Basis(Vector3.UP, rig.blade * 0.5))
		_rotate_global(sk, _bone("Head"), Basis(Vector3.UP, rig.blade * 0.5))
	# Cheek weld: shouldered, the head leans onto the stock (towards the rifle's side) and dips.
	var cheek := rig.blade / CharacterRig.BLADE_AIM
	if absf(cheek) > 0.01:
		_rotate_global(sk, _bone("neck_01"), Basis(Vector3(0, 0, 1), cheek * 0.1) * Basis(Vector3.RIGHT, absf(cheek) * 0.05))
		_rotate_global(sk, _bone("Head"), Basis(Vector3(0, 0, 1), cheek * 0.12) * Basis(Vector3.RIGHT, absf(cheek) * 0.06))
	# 2. Spine: aim pitch + hit flinch + lean.
	var p := rig.spine_pitch
	for n in ["spine_02", "spine_03"]:
		_rotate_global(sk, _bone(n), Basis(Vector3.RIGHT, -p * 0.5))
	# Body lean from acceleration / turning (x: roll into the turn, y: forward pitch).
	# Shot rocks the torso back (negative forward pitch).
	var ln := rig.lean - Vector2(0, rig.kick_lean)
	if ln.length_squared() > 0.00001:
		_rotate_global(sk, _bone("spine_01"), Basis(Vector3(0, 0, 1), ln.x) * Basis(Vector3.RIGHT, ln.y))
	# Backpack: follows the chest position but only part of its rotation, so it
	# rides the back instead of flapping with every jog/sprint keyframe.
	var sp := sk.get_bone_global_pose(_bone("spine_03"))
	if rig.pack:
		var rest := sk.get_bone_global_rest(_bone("spine_03"))
		var delta := (sp.basis.orthonormalized() * rest.basis.orthonormalized().inverse()).get_rotation_quaternion()
		rig.pack.global_transform = sk.global_transform * Transform3D(Basis(Quaternion.IDENTITY.slerp(delta, 0.5)), sp.origin)
	# 3. Gun placement (skeleton space -> global).
	var gun_s := rig.gun_transform(sp)
	var inv := sk.global_transform.affine_inverse()
	# Short-armed bodies: slide the whole rifle towards the shoulders until both hands
	# reach their grips (a rigid gun, so the grips never drift off the weapon).
	var want_off := _reach_offset(sk, inv, gun_s)
	_reach = _reach.lerp(want_off, 1.0 - exp(-_delta_t * 20.0))
	gun_s = Transform3D(Basis(), _reach) * gun_s
	# Never through the chest: out to the measured torso surface (at once), eased back after.
	var push := rig.clip_push(gun_s)
	_push = push if push.length() >= _push.length() else _push.lerp(push, 1.0 - exp(-_delta_t * 12.0))
	gun_s = Transform3D(Basis(), _push) * gun_s
	if Game.debug.has("log_reach") and Engine.get_process_frames() % 60 == 0:
		print("[CLIP] skin %d slide %.2f pocket %s reach %s push %s butt %s" % [rig.skin, _slide, str(rig._torso.pocket), str(_reach.snapped(Vector3.ONE * 0.01)), str(push.snapped(Vector3.ONE * 0.01)),
			str((rig._chest_frame.affine_inverse() * (gun_s * Vector3(0, rig._butt_y, rig._stock_back))).snapped(Vector3.ONE * 0.01))])
	rig.gun.global_transform = sk.global_transform * gun_s
	# 4. Arm IK onto the grips.
	var tr: Vector3 = inv * rig.hand_target(0)
	var tl: Vector3 = inv * rig.hand_target(1)
	var fwd: Vector3 = (gun_s.basis * Vector3.FORWARD).normalized()
	_arm(sk, "r", tr, Vector3(-0.6, -0.5, -0.3).lerp(Vector3(-0.22, -0.8, -0.3), rig.shoulder_k), (inv.basis * rig.hand_dir(0)).normalized(), -1.0, 0.0)
	_arm(sk, "l", tl, Vector3(0.22, -0.8, -0.3).lerp(Vector3(0.6, -0.5, -0.3), rig.shoulder_k), (inv.basis * rig.hand_dir(1)).normalized(), -1.0, 0.0)
	_grip(sk, "r", inv * rig.grip_wrap(0), rig.arm_w)
	_grip(sk, "l", inv * rig.grip_wrap(1), rig.arm_w)
	# 5. Vault: hands planted flat on the obstacle's top (right hand = first point).
	if rig.vault_w > 0.01 and rig.vault_hand_pos.size() == 2:
		var vf: Vector3 = (inv.basis * rig.vault_dir).normalized()
		_arm(sk, "r", inv * rig.vault_hand_pos[0], Vector3(-0.6, -0.4, -0.1), vf, rig.vault_w)
		_arm(sk, "l", inv * rig.vault_hand_pos[1], Vector3(0.6, -0.4, -0.1), vf, rig.vault_w)


func _rotate_global(sk: Skeleton3D, bone: int, rot: Basis) -> void:
	if bone < 0:
		return
	var t := sk.get_bone_global_pose(bone)
	sk.set_bone_global_pose(bone, Transform3D(rot * t.basis, t.origin))


func _aim_bone(sk: Skeleton3D, bone: int, child: int, target: Vector3) -> void:
	var t := sk.get_bone_global_pose(bone)
	var cur := sk.get_bone_global_pose(child).origin - t.origin
	var want := target - t.origin
	if cur.length() < 0.0001 or want.length() < 0.0001:
		return
	var q := Quaternion(cur.normalized(), want.normalized())
	sk.set_bone_global_pose(bone, Transform3D(Basis(q) * t.basis, t.origin))


func _arm(sk: Skeleton3D, side: String, target: Vector3, pole_dir: Vector3, gun_fwd: Vector3, weight := -1.0, droop := 0.35) -> void:
	var up := _bone("upperarm_" + side)
	var lo := _bone("lowerarm_" + side)
	var hd := _bone("hand_" + side)
	if up < 0 or lo < 0 or hd < 0:
		return
	var w := rig.arm_w if weight < 0.0 else weight
	if w < 0.01:
		return
	var a := sk.get_bone_global_pose(up).origin
	var l1 := a.distance_to(sk.get_bone_global_pose(lo).origin)
	var l2 := sk.get_bone_global_pose(lo).origin.distance_to(sk.get_bone_global_pose(hd).origin)
	target = sk.get_bone_global_pose(hd).origin.lerp(target, w)
	var r := CharacterRig._ik(a, target, l1, l2, a + pole_dir)
	_aim_bone(sk, up, lo, r[0])
	_aim_bone(sk, lo, hd, r[1])
	# Hand: fingers (bone +Y) along the rifle, slightly curled down.
	var ht := sk.get_bone_global_pose(hd)
	var y := _finger_axis(sk, side, ht)
	var want := y.lerp((gun_fwd + Vector3(0, -droop, 0)).normalized(), w).normalized()
	var q := Quaternion(y, want)
	sk.set_bone_global_pose(hd, Transform3D(Basis(q) * ht.basis, ht.origin))


# ---------------------------------------------------------------- fingers

const FINGERS := ["Index", "Middle", "Ring", "Pinky", "Thumb"]
## Curl per joint (rad) of each finger when closed round the gun: [right hand, left hand].
const CURL_R := {"Index": [0.35, 0.6, 0.4], "Middle": [0.95, 1.2, 0.8], "Ring": [1.0, 1.25, 0.8], "Pinky": [1.0, 1.2, 0.8], "Thumb": [0.25, 0.45, 0.35]}
const CURL_L := {"Index": [0.85, 1.15, 0.8], "Middle": [0.9, 1.2, 0.8], "Ring": [0.95, 1.25, 0.8], "Pinky": [1.0, 1.25, 0.8], "Thumb": [0.25, 0.4, 0.3]}
## Finger curl multiplier per body (the cybernetic hand needs a deeper bend to close).
const CURL_SKIN := [1.0, 1.9, 1.0]
## Hands whose mesh fingers are not what the bones say (measured with tools/hand_axes.gd):
## the cybernetic right hand is a rigid claw along hand-local +Z, unskinned to its fingers.
const FAX_OVERRIDE := {"1r": Vector3(0.0, 0.45, 0.89)}
const RIGID_HANDS := ["1r"]
var _fax := {}
var _sax := {}
var _roll := {"r": INF, "l": INF}


func _hname(side: String) -> String:
	return "mixamorig_" + ("Right" if side == "r" else "Left")


func _fb(side: String, finger: String, joint: int) -> int:
	var key := "%sHand%s%d" % [_hname(side), finger, joint]
	if not _b.has(key):
		_b[key] = get_skeleton().find_bone(key)
	return _b[key]


## Unit direction of the fingers, from the REST pose (the clip's relaxed curl and the
## wrist -> knuckle offset of odd hands would both skew it): hand frame -> middle finger chain.
func _finger_axis(sk: Skeleton3D, side: String, hand_pose: Transform3D) -> Vector3:
	if not _fax.has(side):
		var m1 := _fb(side, "Middle", 1)
		var m4 := _fb(side, "Middle", 4)
		var hd := _bone("hand_" + side)
		if m1 < 0 or m4 < 0 or hd < 0:
			# No finger bones (auto-rigged bodies): the fingers continue the forearm.
			var lo := _bone("lowerarm_" + side)
			if lo < 0 or hd < 0:
				return hand_pose.basis.y.normalized()
			var fd := (sk.get_bone_global_rest(hd).origin - sk.get_bone_global_rest(lo).origin).normalized()
			_fax[side] = sk.get_bone_global_rest(hd).basis.orthonormalized().inverse() * fd
			_sax[side] = Vector3.LEFT if side == "r" else Vector3.RIGHT
			return (hand_pose.basis.orthonormalized() * (_fax[side] as Vector3)).normalized()
		var hr := sk.get_bone_global_rest(hd).basis.orthonormalized()
		if Game.debug.has("log_reach"):
			var o := sk.get_bone_global_rest(hd).origin
			print("[FAX] skin %d %s m1 %s m2 %s m3 %s m4 %s idx1 %s pnk1 %s thumb1 %s" % [rig.skin, side, str((hr.inverse() * (sk.get_bone_global_rest(m1).origin - o)).snapped(Vector3.ONE * 0.001)), str((hr.inverse() * (sk.get_bone_global_rest(_fb(side, "Middle", 2)).origin - o)).snapped(Vector3.ONE * 0.001)), str((hr.inverse() * (sk.get_bone_global_rest(_fb(side, "Middle", 3)).origin - o)).snapped(Vector3.ONE * 0.001)), str((hr.inverse() * (sk.get_bone_global_rest(m4).origin - o)).snapped(Vector3.ONE * 0.001)), str((hr.inverse() * (sk.get_bone_global_rest(_fb(side, "Index", 1)).origin - o)).snapped(Vector3.ONE * 0.001)), str((hr.inverse() * (sk.get_bone_global_rest(_fb(side, "Pinky", 1)).origin - o)).snapped(Vector3.ONE * 0.001)), str((hr.inverse() * (sk.get_bone_global_rest(_fb(side, "Thumb", 1)).origin - o)).snapped(Vector3.ONE * 0.001))])
		var key := "%d%s" % [rig.skin, side]
		if FAX_OVERRIDE.has(key):
			_fax[side] = (FAX_OVERRIDE[key] as Vector3).normalized()
			_sax[side] = Vector3.LEFT if side == "r" else Vector3.RIGHT
			return (hand_pose.basis.orthonormalized() * (_fax[side] as Vector3)).normalized()
		_fax[side] = hr.inverse() * (sk.get_bone_global_rest(m4).origin - sk.get_bone_global_rest(hd).origin).normalized()
		var i1 := _fb(side, "Index", 1)
		var p1 := _fb(side, "Pinky", 1)
		var sl := hr.inverse() * (sk.get_bone_global_rest(p1).origin - sk.get_bone_global_rest(i1).origin)
		if sl.length() < 0.03:
			# Claw-like hand (all knuckles on one point): the knuckle line is the hand's X axis.
			sl = Vector3.LEFT if side == "r" else Vector3.RIGHT
		_sax[side] = sl.normalized()
	return (hand_pose.basis.orthonormalized() * (_fax[side] as Vector3)).normalized()

## Closes the fingers round `target` (skeleton space) and rolls the hand about its own
## finger axis so the palm faces it. Each finger bends about the axis perpendicular to
## itself and to the knuckle line, the side that brings its tip nearest the target.
func _grip(sk: Skeleton3D, side: String, target: Vector3, w: float) -> void:
	if w < 0.01:
		return
	var hd := _bone("hand_" + side)
	var mid1 := _fb(side, "Middle", 1)
	var idx1 := _fb(side, "Index", 1)
	var pnk1 := _fb(side, "Pinky", 1)
	if hd < 0 or mid1 < 0 or idx1 < 0 or pnk1 < 0:
		return
	if "%d%s" % [rig.skin, side] in RIGID_HANDS:
		return
	# The trigger hand curls like a pistol grip, the other like a hand-guard (roles swap with the shoulder).
	var trigger_hand := (side == "r") == (rig.shoulder_k < 0.5)
	var curl: Dictionary = CURL_R if trigger_hand else CURL_L
	var h0 := sk.get_bone_global_pose(hd)
	var f := _finger_axis(sk, side, h0)
	# Roll search: full circle the first time, then around the last answer.
	var prev: float = _roll[side]
	var cands: Array[float] = []
	if prev == INF:
		for i in 24:
			cands.append(i * TAU / 24.0)
	else:
		for i in range(-4, 5):
			cands.append(prev + i * deg_to_rad(12.0))
	var best := INF
	var best_roll := 0.0
	for r in cands:
		sk.set_bone_global_pose(hd, Transform3D(Basis(f, r) * h0.basis, h0.origin))
		var c := _tip_cost(sk, side, target, curl)
		if c < best:
			best = c
			best_roll = r
	_roll[side] = best_roll
	sk.set_bone_global_pose(hd, Transform3D(Basis(f, best_roll) * h0.basis, h0.origin))
	var s_dir: Vector3 = (sk.get_bone_global_pose(hd).basis.orthonormalized() * (_sax[side] as Vector3)).normalized()
	for fname in FINGERS:
		var j1 := _fb(side, fname, 1)
		var j2 := _fb(side, fname, 2)
		var j4 := _fb(side, fname, 4)
		if j1 < 0 or j2 < 0 or j4 < 0:
			continue
		var axis := (sk.get_bone_global_pose(j2).origin - sk.get_bone_global_pose(j1).origin).cross(s_dir).normalized()
		var sign_ := _curl_sign(sk, side, fname, axis, target, curl[fname])
		if Game.debug.has("log_reach") and Engine.get_process_frames() % 120 == 0:
			print("[CURL] skin %d %s %s sign %.0f roll %.2f cost %.3f axis %s j1 %s j2 %s tip %s tgt %s" % [rig.skin, side, fname, sign_, best_roll, best, str(axis.snapped(Vector3.ONE * 0.01)), str(sk.get_bone_global_pose(j1).origin.snapped(Vector3.ONE * 0.001)), str(sk.get_bone_global_pose(j2).origin.snapped(Vector3.ONE * 0.001)), str(sk.get_bone_global_pose(j4).origin.snapped(Vector3.ONE * 0.001)), str(target.snapped(Vector3.ONE * 0.001))])
		for j in 3:
			var jb := _fb(side, fname, j + 1)
			_rotate_global(sk, jb, Basis(axis, sign_ * float(curl[fname][j]) * w * float(Game.debug.get("curl_mul", CURL_SKIN[clampi(rig.skin, 0, 2)]))))


## Tip distance of the middle finger curled the better way round, for a given hand roll.
func _tip_cost(sk: Skeleton3D, side: String, target: Vector3, curl: Dictionary) -> float:
	var best := INF
	var idx1 := _fb(side, "Index", 1)
	var pnk1 := _fb(side, "Pinky", 1)
	var s_dir: Vector3 = (sk.get_bone_global_pose(_bone("hand_" + side)).basis.orthonormalized() * (_sax[side] as Vector3)).normalized()
	var p1 := sk.get_bone_global_pose(_fb(side, "Middle", 1)).origin
	var p2 := sk.get_bone_global_pose(_fb(side, "Middle", 2)).origin
	var axis := (p2 - p1).cross(s_dir).normalized()
	for sg in [-1.0, 1.0]:
		best = minf(best, _sim_tip(sk, side, "Middle", axis, sg, curl["Middle"]).distance_to(target))
	return best


func _sim_tip(sk: Skeleton3D, side: String, finger: String, axis: Vector3, sg: float, amounts: Array) -> Vector3:
	var pt := sk.get_bone_global_pose(_fb(side, finger, 1)).origin
	var acc := 0.0
	for j in 3:
		var a := sk.get_bone_global_pose(_fb(side, finger, j + 1)).origin
		var b := sk.get_bone_global_pose(_fb(side, finger, j + 2)).origin
		acc += sg * float(amounts[j])
		pt += Basis(axis, acc) * (b - a)
	return pt


func _curl_sign(sk: Skeleton3D, side: String, finger: String, axis: Vector3, target: Vector3, amounts: Array) -> float:
	var a := _sim_tip(sk, side, finger, axis, 1.0, amounts).distance_to(target)
	var b := _sim_tip(sk, side, finger, axis, -1.0, amounts).distance_to(target)
	return 1.0 if a < b else -1.0