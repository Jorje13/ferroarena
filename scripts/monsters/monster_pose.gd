class_name MonsterPose
extends SkeletonModifier3D
## Procedural animation of a MonsterRig. The Meshy rigs have no clips and noisy joint
## positions, so nothing here depends on the bones' own axes: rotations are applied about
## world (skeleton-space) axes through each joint (+X = the monster's left, +Y up, +Z forward),
## and the legs are solved with two-bone IK towards foot targets taken from the rest pose, so
## crouching, leaping and stepping keep the feet where they should be.
##
## The pose is a handful of smoothed values (lean, arm angles, hips drop...) chosen by the
## state, plus a stride cycle on top while moving.

var rig: MonsterRig
var _v := {}
var _foot_rest := {}
var _seed := randf() * 10.0


func _process_modification_with_delta(delta: float) -> void:
	var sk := get_skeleton()
	if sk == null or rig == null:
		return
	_pose(sk, delta)


func _target(st: String, t: float, d: Dictionary) -> Dictionary:
	# lean: forward pitch of the spine; sh_*: shoulder swing (negative = forward / up);
	# sp_*: arms spread outwards; el_*: elbow bend (negative = forearm forward);
	# dy: hips drop; head: head pitch; twist: spine yaw; rate: how fast values follow.
	var g := {"lean": 0.0, "sh_l": 0.0, "sh_r": 0.0, "sp_l": 0.0, "sp_r": 0.0, "el_l": 0.0, "el_r": 0.0,
		"dy": 0.0, "head": 0.0, "twist": 0.0, "walk": 0.0, "rate": 10.0}
	var big: bool = rig.kind == 0
	match st:
		"idle":
			var br := sin(Time.get_ticks_msec() * 0.0016 + _seed)
			g.lean = 0.04 + 0.025 * br
			g.sh_l = 0.05 * br
			g.sh_r = -0.05 * br
			g.head = 0.05 * sin(Time.get_ticks_msec() * 0.0011 + _seed * 2.0)
		"walk", "run":
			g.walk = 1.0
			g.lean = float(d.lean_walk) * (1.4 if st == "run" else 1.0)
			g.head = -0.1
			g.rate = 8.0
		"windup":
			# Arms hauled up and back, body rearing: the Faucheur raises both claws overhead,
			# the Bondisseur cocks one arm.
			g.lean = -0.3
			g.rate = 9.0
			if big:
				g.sh_l = -2.5
				g.sh_r = -2.5
				g.sp_l = 0.3
				g.sp_r = 0.3
				g.el_l = -0.4
				g.el_r = -0.4
			else:
				g.sh_r = -2.2
				g.el_r = -0.6
				g.twist = 0.4
		"strike":
			# Snap down and forward: claws sweep from overhead through the target.
			g.rate = 34.0
			g.lean = 0.65
			g.dy = 0.08
			g.head = 0.2
			if big:
				g.sh_l = -0.55
				g.sh_r = -0.55
				g.sp_l = -0.15
				g.sp_r = -0.15
			else:
				g.sh_r = -0.8
				g.el_r = 0.0
				g.twist = -0.5
		"recover":
			g.rate = 7.0
			g.lean = 0.2
		"crouch":
			# Gathers itself for the leap: deep squat, arms back.
			g.dy = 0.38
			g.lean = 0.55
			g.sh_l = 0.9
			g.sh_r = 0.9
			g.el_l = -0.5
			g.el_r = -0.5
			g.head = -0.3
			g.rate = 11.0
		"leap":
			# Airborne: stretched out, arms and claws thrown forward.
			g.lean = 0.5
			g.sh_l = -1.9
			g.sh_r = -1.9
			g.sp_l = 0.25
			g.sp_r = 0.25
			g.el_l = -0.3
			g.el_r = -0.3
			g.head = -0.3
			g.rate = 18.0
		"land":
			g.dy = 0.28
			g.lean = 0.45
			g.sh_l = -0.5
			g.sh_r = -0.5
			g.rate = 14.0
		"stagger":
			g.lean = -0.45
			g.head = -0.4
			g.sh_l = -0.5
			g.sh_r = -0.5
			g.rate = 22.0
		"spawn":
			# Claws itself up out of the ground.
			g.dy = lerpf(0.6, 0.0, clampf(t / 1.4, 0.0, 1.0))
			g.lean = lerpf(0.9, 0.0, clampf(t / 1.4, 0.0, 1.0))
			g.sh_l = lerpf(-1.2, 0.0, clampf(t / 1.4, 0.0, 1.0))
			g.sh_r = g.sh_l
			g.rate = 6.0
		"dead":
			g.lean = -0.8
			g.dy = 0.55
			g.sh_l = 0.6
			g.sh_r = 0.6
			g.el_l = -0.2
			g.el_r = -0.2
			g.head = -0.5
			g.rate = 7.0
	return g


func _pose(sk: Skeleton3D, delta: float) -> void:
	var d := rig.data
	var tg := _target(rig.state, rig.state_t, d)
	if _v.is_empty():
		_v = tg.duplicate()
	var k := 1.0 - exp(-delta * float(tg.rate))
	for key in tg:
		if key != "rate":
			_v[key] = lerpf(float(_v[key]), float(tg[key]), k)
	var ph := rig.phase
	var sp := clampf(rig.speed / maxf(float(d.speed), 0.1), 0.0, 1.4)
	var walk := float(_v.walk) * clampf(sp * 1.6, 0.0, 1.0)
	var osc := sin(ph)
	var bob := absf(sin(ph)) * float(d.bob) * walk

	# ---- Hips: bob and drop (everything above and below follows).
	var hips := int(d.hips)
	var hp := sk.get_bone_global_pose(hips)
	hp.origin.y -= float(_v.dy) - bob
	hp.origin.z += sin(ph) * 0.0
	sk.set_bone_global_pose(hips, hp)
	_rot(sk, hips, Vector3.BACK, 0.06 * osc * walk) # roll with the steps
	_rot(sk, hips, Vector3.UP, (0.12 * osc * walk) + float(_v.twist) * 0.35)

	# ---- Spine: lean, spread over the chain; twist counter-rotates up the back.
	var spine: Array = d.spine
	for i in spine.size():
		var share := 1.0 / spine.size()
		_rot(sk, int(spine[i]), Vector3.RIGHT, float(_v.lean) * share)
		_rot(sk, int(spine[i]), Vector3.UP, (float(_v.twist) * 0.65 - 0.1 * osc * walk) * share)
	# Head stays level-ish: undo part of the lean and add the head pitch.
	_rot(sk, int(d.neck), Vector3.RIGHT, -float(_v.lean) * 0.45 + float(_v.head) * 0.5)
	_rot(sk, int(d.head), Vector3.RIGHT, float(_v.head) * 0.5)

	# ---- Arms: stride counter-swing + state angles (+X is the monster's left).
	var asw := float(d.arm_swing) * walk
	_arm(sk, d.arm_l, -(float(_v.sh_l) + osc * asw), float(_v.sp_l), float(_v.el_l) - maxf(0.0, -osc) * asw * 0.8, 1.0)
	_arm(sk, d.arm_r, -(float(_v.sh_r) - osc * asw), float(_v.sp_r), float(_v.el_r) - maxf(0.0, osc) * asw * 0.8, -1.0)

	# ---- Legs: IK to foot targets that step forward and lift.
	var sw := float(d.leg_swing) * walk
	_leg(sk, d.leg_l, osc * sw, maxf(0.0, cos(ph)) * 0.16 * walk, float(_v.dy))
	_leg(sk, d.leg_r, -osc * sw, maxf(0.0, -cos(ph)) * 0.16 * walk, float(_v.dy))


## Rotates `bone` (and so everything below it) about a skeleton-space axis through its joint.
func _rot(sk: Skeleton3D, bone: int, axis: Vector3, ang: float) -> void:
	if absf(ang) < 0.0001:
		return
	var t := sk.get_bone_global_pose(bone)
	sk.set_bone_global_pose(bone, Transform3D(Basis(axis, ang) * t.basis, t.origin))


func _arm(sk: Skeleton3D, chain: Array, swing: float, spread: float, elbow: float, side: float) -> void:
	# swing > 0 pushes the arm back, < 0 forward (about +X); spread opens it sideways (about +Z).
	_rot(sk, int(chain[0]), Vector3.RIGHT, -swing)
	_rot(sk, int(chain[0]), Vector3.BACK, -spread * side)
	_rot(sk, int(chain[1]), Vector3.RIGHT, elbow)
	# Wrist / claws trail a little behind the swing.
	_rot(sk, int(chain[2]), Vector3.RIGHT, -swing * 0.25)


func _leg(sk: Skeleton3D, chain: Array, step: float, lift: float, drop: float) -> void:
	var a_i := int(chain[0])
	var k_i := int(chain[1])
	var f_i := int(chain[2])
	if not _foot_rest.has(f_i):
		_foot_rest[f_i] = sk.get_bone_global_rest(f_i).origin
	var target: Vector3 = _foot_rest[f_i]
	target += Vector3(0.0, lift, step)
	var a := sk.get_bone_global_pose(a_i).origin
	var knee := sk.get_bone_global_pose(k_i).origin
	var foot := sk.get_bone_global_pose(f_i).origin
	var l1 := a.distance_to(knee)
	var l2 := knee.distance_to(foot)
	if l1 < 0.01 or l2 < 0.01:
		return
	var r := _ik(a, target, l1, l2, a + Vector3(0, 0.0, 1.0) * 0.5 + Vector3(0, 0.15, 0))
	_aim(sk, a_i, k_i, r[0])
	_aim(sk, k_i, f_i, r[1])


func _aim(sk: Skeleton3D, bone: int, child: int, target: Vector3) -> void:
	var t := sk.get_bone_global_pose(bone)
	var cur := sk.get_bone_global_pose(child).origin - t.origin
	var want := target - t.origin
	if cur.length() < 0.0001 or want.length() < 0.0001:
		return
	sk.set_bone_global_pose(bone, Transform3D(Basis(Quaternion(cur.normalized(), want.normalized())) * t.basis, t.origin))


## Two-bone solve: returns [knee, foot] positions for a root `a`, bone lengths, and a pole point
## the knee bends towards.
static func _ik(a: Vector3, target: Vector3, l1: float, l2: float, pole: Vector3) -> Array:
	var d := target - a
	var dist := clampf(d.length(), 0.02, l1 + l2 - 0.002)
	var dir := d.normalized() if d.length() > 0.0001 else Vector3.DOWN
	var cos_a := (l1 * l1 + dist * dist - l2 * l2) / (2.0 * l1 * dist)
	var ang := acos(clampf(cos_a, -1.0, 1.0))
	var pd := pole - a
	pd = pd - dir * pd.dot(dir)
	if pd.length() < 0.0001:
		pd = dir.cross(Vector3.RIGHT)
	pd = pd.normalized()
	var mid := a + dir * cos(ang) * l1 + pd * sin(ang) * l1
	return [mid, a + dir * dist]