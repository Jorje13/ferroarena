class_name CharacterRig
extends Node3D
## Visual raider: realistic trooper (Sketchfab, CC BY, rigged on Mixamo) driven by
## Mixamo motion-capture clips, PBR materials with team-tinted emissive lights,
## a shield/hit overlay pass, and the Ferro (IZH-27) held through RaiderIK.
## Reads the Player's replicated state every frame.

const FLIP := Basis(Vector3.UP, PI) ## game forward (-Z) <-> model forward (+Z)
## Logical bone names used by IK, hitboxes and attachments -> Mixamo skeleton.
const BONES := {
	"pelvis": "mixamorig_Hips", "spine_01": "mixamorig_Spine", "spine_02": "mixamorig_Spine1",
	"spine_03": "mixamorig_Spine2", "neck_01": "mixamorig_Neck", "Head": "mixamorig_Head",
	"upperarm_l": "mixamorig_LeftArm", "lowerarm_l": "mixamorig_LeftForeArm", "hand_l": "mixamorig_LeftHand",
	"upperarm_r": "mixamorig_RightArm", "lowerarm_r": "mixamorig_RightForeArm", "hand_r": "mixamorig_RightHand",
	"thigh_l": "mixamorig_LeftUpLeg", "calf_l": "mixamorig_LeftLeg", "foot_l": "mixamorig_LeftFoot",
	"thigh_r": "mixamorig_RightUpLeg", "calf_r": "mixamorig_RightLeg", "foot_r": "mixamorig_RightFoot",
}


static func bone_name(logical: String) -> String:
	return BONES.get(logical, logical)

var team := 0
var female := false
var model: Node3D
var skeleton: Skeleton3D
var anim: AnimationTree
var ik: RaiderIK
var gun: Node3D
var muzzle: Node3D
var grip_r: Node3D
var grip_l: Node3D
var barrel_pivot: Node3D
var pack: Node3D
var nameplate: Label3D

# Vault hand plant: weight, world points (right, left) and travel direction (RaiderIK).
var vault_w := 0.0
var vault_hand_pos := PackedVector3Array()
var vault_dir := Vector3.FORWARD
# Values consumed by RaiderIK
var hip_yaw := 0.0
var spine_pitch := 0.0
var arm_w := 1.0

var _suit: ShaderMaterial
var _aim := 0.0
var _sprint := 0.0
var _sling := 0.0
var _pitch := 0.0
var _flinch := 0.0
var _air_t := 0.0
var _phase := 0.0
var _last_step := 0
var _reload_k := -1.0
var _pouch_s := Vector3.ZERO
var _hand_items := {}
var _throw_t := 0.0


var loadout := {}
## ArmorKit "skin": 0 trooper, others are retargeted Meshy bodies.
var skin := 0


func setup(p_team: int, p_name: String, p_loadout: Dictionary = {}) -> void:
	team = p_team
	loadout = ArmorKit.sanitize(p_loadout)
	var accent: Color = Game.TEAM_COLORS[team]

	skin = int(loadout.skin)
	model = CharacterModel.create_body(skin)
	model.basis = FLIP
	add_child(model)
	skeleton = model.find_children("*", "Skeleton3D", true, false)[0]
	# Per-rig overlay pass (shield shimmer + hit flash) on top of shared PBR materials.
	_suit = ShaderMaterial.new()
	_suit.shader = load("res://shaders/shield_overlay.gdshader")
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		for s in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(s)
			var m: StandardMaterial3D
			if skin == 0:
				var part := src.resource_name.trim_suffix("mat") if src else ""
				m = CharacterModel.trooper_material(part, loadout).duplicate() as StandardMaterial3D
			else:
				m = (src as StandardMaterial3D).duplicate() as StandardMaterial3D
			mi.set_surface_override_material(s, m)
			_body_mats.append(m)

	_build_anim_tree()
	var mid_i := skeleton.find_bone("mixamorig_LeftHandMiddle1")
	_palm_len = skeleton.get_bone_global_rest(skeleton.find_bone(bone_name("hand_l"))).origin.distance_to(skeleton.get_bone_global_rest(mid_i).origin) if mid_i >= 0 else 0.08
	_build_team_marks(accent)

	_build_gun(accent)
	_build_hand_items()
	_merge_static_meshes()

	ik = RaiderIK.new()
	ik.rig = self
	skeleton.add_child(ik)

	nameplate = Label3D.new()
	nameplate.text = p_name
	nameplate.position = Vector3(0, 2.2, 0)
	nameplate.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	nameplate.no_depth_test = true
	nameplate.fixed_size = true
	nameplate.pixel_size = 0.0009
	nameplate.font_size = 22
	nameplate.outline_size = 6
	nameplate.modulate = accent
	nameplate.visible = false
	add_child(nameplate)


# ---------------------------------------------------------------- animation graph
#
#  loco (BlendSpace2D: local velocity, x = right, y = forward; walk / run / sprint,
#        backwards, strafe left / right; every cycle stretched to a 1 s timeline and
#        phase-aligned so blends never mix mismatched strides) -> loco_ts (cycle rate)
#     -> move (Blend2 with idle) -> aim_idle (Blend2 with aiming idle)
#     -> crouch (Blend2 with crouch BS1D -> crouch_ts)
#     -> state (Transition: loco + the one-off states below)
# All clips are Mixamo motion capture (library "mx", CharacterModel.mixamo_library()).

const ROLL_TIMELINE := 0.9
## Crouch walk: phase offset (s), cycle length (s) and stride (m per cycle).
const CROUCH_PHASE := 0.301
const CROUCH_LEN := 1.167
const CROUCH_STRIDE := 1.14
## [start, length] windows of the vault clip (seconds).
const MANTLE_CLIP := [0.2, 0.85]
const VAULT_CLIP := [0.2, 1.35]
## Hips height of the vault clip at its start frame (rise above it is cancelled).
const VAULT_HIPS_REST := 0.84

## state -> [clip, default time scale, custom timeline [start, length, loop] or []]
const STATES := {
	"air": ["mx/rifle_jump", 1.0, [0.22, 0.12, Animation.LOOP_PINGPONG]],
	"land": ["mx/crouch_idle", 1.0, []],
	# Only the tumble of the dive roll (no airborne dive, no ground impact):
	# from 0.72 s (already rolling) to standing again at ~1.62 s.
	"roll": ["mx/running_dive_roll", 1.0, [0.72, ROLL_TIMELINE, Animation.LOOP_NONE]],
	"slide_in": ["mx/running_slide", 1.3, [0.0, 0.5, Animation.LOOP_NONE]],
	"slide": ["mx/running_slide", 1.0, [0.45, 0.4, Animation.LOOP_PINGPONG]],
	# Vault clip: hands plant ~0.3 s, hips peak 0.74 s, landing ~1.5 s. Mantle
	# (climb onto) uses the up half only. Hips rise is cancelled in update_pose
	# since the Player already carries the body over the obstacle.
	"mantle": ["mx/vault_over_box", 1.0, [MANTLE_CLIP[0], MANTLE_CLIP[1], Animation.LOOP_NONE]],
	"vault": ["mx/vault_over_box", 1.0, [VAULT_CLIP[0], VAULT_CLIP[1], Animation.LOOP_NONE]],
	# Grenade throw: wind-up then release at 2.07 s in the clip.
	"throw": ["mx/grenade_throw", 1.2, [1.85, 0.6, Animation.LOOP_NONE]],
	"dead": ["mx/death", 1.0, []],
	# Finished while crawling: already lying on the belly, last spasm then flat.
	"dead_prone": ["mx/prone_death", 1.0, []],
	# Drinking a flask: the gesture lives between 2 s and 5.2 s of the clip.
	"heal_self": ["mx/drinking", 3.2 / Player.BANDAGE_TIME, [2.0, 3.2, Animation.LOOP_NONE]],
	"heal_ally": ["mx/kneeling", 1.0, []],
	# Rummaging through a crate / slotting a shield cell: kneel, gun slung.
	"search": ["mx/kneeling", 1.0, []],
	"shield": ["mx/kneeling", 1.0, []],
	"down": ["mx/crawling", 1.0, []],
	"revive": ["mx/kneeling", 1.0, []],
}
## The crawl clip is already on the ground (hands and knees): no extra lift.
const DOWN_LIFT := 0.0
const JUMP_LEN := 0.6
## Hip counter-twist (deg) while airborne, see update_pose.
const AIR_HIP_TWIST := 60.0
const DEATH_LEN := 3.03
## Directional cycles: [name, clip, blend position (m/s, x right / y forward),
## phase offset in clip seconds (left foot furthest along the motion)].
const LOCO_POINTS := [
	["walk", "mx/rifle_walk", Vector2(0, 1.6), 0.336],
	["run", "mx/rifle_run", Vector2(0, 4.1), 0.165],
	["sprint", "mx/rifle_sprint", Vector2(0, 6.5), 0.133],
	["back_walk", "mx/run_backwards", Vector2(0, -1.6), 0.14],
	["back_run", "mx/run_backwards", Vector2(0, -3.2), 0.14],
	["right_walk", "mx/strafe_right", Vector2(1.6, 0), 1.521],
	["right_run", "mx/strafe_right_run", Vector2(4.1, 0), 0.167],
	# Left strafes are the mirror image of the right ones (the captured left clip
	# is a short shuffle that reads as backwards at game speeds).
	["left_walk", "mx/strafe_left_walk_m", Vector2(-1.6, 0), 0.755],
	["left_run", "mx/strafe_left_run_m", Vector2(-4.1, 0), 0.5],
]
## Cycle tables per direction: [game speed, clip length (s), stride (m per cycle)],
## measured with tools/mixamo_clip_info.gd.
const RATE_FWD := [[1.6, 1.3, 1.43], [4.1, 0.733, 1.9], [6.5, 0.667, 2.07]]
const RATE_BACK := [[1.6, 1.2, 1.9], [3.2, 1.2, 1.9]]
const RATE_RIGHT := [[1.6, 1.533, 0.6], [4.1, 0.667, 1.67]]
const RATE_LEFT := RATE_RIGHT
## 1 = feet never slide (legs may look frantic at game speeds), 0 = clip rate.
const STRIDE_MATCH := 0.7

var _state := ""
var _state_t := 0.0
var _land_seen := false
var _backwards := false
## Spine yaw (rad) towards the camera while the legs lag behind, read by RaiderIK.
var torso_twist := 0.0
## Prop hunt disguise (see set_disguise).
var disguised := false
var _prop_node: Node3D
## Shouldering the rifle blades the upper body (left shoulder forward), head kept on target.
var blade := 0.0
const BLADE_AIM := 0.55
const TORSO_TWIST_MAX := 1.2
var _recoil := 0.0
var _recoil_v := 0.0
## Torso rock-back from the shot, read by RaiderIK.
var kick_lean := 0.0
var _vault_comp := 0.0
var _hips_tracks := {}
var _body_mats: Array[StandardMaterial3D] = []
var _overlay_on := false
var _down_seen := false
var _lift := 0.0
var _glow := 0.0
var _prev_shield := 0.0


## Shield shimmer on the suit: flashes when the shield is hit or breaks, and
## pulses while recharging.
func _shield_glow(p: Player, charging: bool, delta: float) -> float:
	if p.shield < _prev_shield - 0.5:
		_glow = 1.0
	_prev_shield = p.shield
	_glow = move_toward(_glow, 0.0, delta * 3.0)
	var g := _glow
	if charging:
		g = maxf(g, 0.35 + 0.25 * sin(Time.get_ticks_msec() * 0.02))
	return g
var _crouch_w := 0.0
var _crouch_dir := 1.0
var _crouch_move := 0.0
var _aim_idle := 0.0
var _loco_pos := Vector2.ZERO
var _move_w := 0.0
var _turn_w := 0.0
## Spine lean consumed by RaiderIK: x = roll into turns, y = forward pitch.
var lean := Vector2.ZERO


func _anim_node(clip: String) -> AnimationNodeAnimation:
	var a := AnimationNodeAnimation.new()
	a.animation = clip
	return a


static var _baked := false


## Bakes, once, the clips the tree actually plays into the shared "mx" library:
## - "mx/loco_<name>": each locomotion cycle phase-shifted (left foot first) and
##   resampled onto a seamless 1 s loop, so 2D blends stay in step;
## - "mx/st_<state>": the window of a clip a state uses (ping-pong loops baked
##   forward + back). Real keys only: no runtime timeline cropping, which made
##   Godot output an empty (rest) pose for one frame at every loop seam.
static func _bake_library() -> AnimationLibrary:
	var lib := CharacterModel.mixamo_library()
	if _baked:
		return lib
	_baked = true
	var probe := CharacterModel.create_trooper()
	var psk := probe.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	lib.add_animation("strafe_left_walk_m", AnimMirror.mirror(lib.get_animation("strafe_right"), psk))
	lib.add_animation("strafe_left_run_m", AnimMirror.mirror(lib.get_animation("strafe_right_run"), psk))
	probe.free()
	for pt in LOCO_POINTS:
		var src := lib.get_animation(String(pt[1]).get_slice("/", 1))
		var a := _resample(src, pt[3], src.length, 1.0, "loop")
		a.loop_mode = Animation.LOOP_LINEAR
		lib.add_animation("loco_" + pt[0], a)
	var cw := lib.get_animation("crouch_walking")
	for dir in [["crouch_fwd", "loop"], ["crouch_back", "reverse"]]:
		var c := _resample(cw, CROUCH_PHASE, cw.length, 1.0, dir[1])
		c.loop_mode = Animation.LOOP_LINEAR
		lib.add_animation(dir[0], c)
	for s in STATES:
		var win: Array = STATES[s][2]
		var src := lib.get_animation(String(STATES[s][0]).get_slice("/", 1))
		var a: Animation
		if win.is_empty():
			a = src.duplicate(true)
		elif win[2] == Animation.LOOP_PINGPONG:
			a = _resample(src, win[0], win[1], win[1] * 2.0, "pingpong")
			a.loop_mode = Animation.LOOP_LINEAR
		else:
			a = _resample(src, win[0], win[1], win[1], "window")
			a.loop_mode = win[2]
		lib.add_animation("st_" + s, a)
	if Game.debug.has("dump_jumps"):
		for name in ["running_dive_roll", "st_roll"]:
			_dump_jumps(lib.get_animation(name), name)
	if Game.debug.has("dump_loops"):
		for name in ["rifle_sprint", "loco_sprint", "rifle_run", "loco_run", "rifle_walk", "loco_walk"]:
			_dump_hips(lib.get_animation(name), name)
	return lib


static var _skin_libs := {}


## The baked clips the tree plays, for one skin: the trooper's own, or a retargeted copy
## (built once, on first use).
static func _skin_library(skin: int) -> AnimationLibrary:
	var base := _bake_library()
	if skin <= 0:
		return base
	if _skin_libs.has(skin):
		return _skin_libs[skin]
	var t0 := Time.get_ticks_msec()
	var from_body := CharacterModel.create_trooper()
	var from_sk := from_body.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var to_body := CharacterModel.create_body(skin)
	var to_sk := to_body.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var idle := base.get_animation("rifle_idle")
	var idle_hips := idle.position_track_interpolate(idle.find_track(NodePath("Skeleton3D:mixamorig_Hips"), Animation.TYPE_POSITION_3D), 0.0) as Vector3
	# Hips position tracks are in the parent's space (auto-rigs hang the hips under a root bone).
	var shift := to_sk.get_bone_rest(to_sk.find_bone("mixamorig_Hips")).origin - idle_hips
	var lib := AnimationLibrary.new()
	for clip in base.get_animation_list():
		var n := String(clip)
		if n in ["rifle_idle", "rifle_aiming_idle", "crouch_idle", "vault_over_box", "crouch_fwd", "crouch_back"] or n.begins_with("loco_") or n.begins_with("st_"):
			lib.add_animation(clip, AnimRetarget.retarget(base.get_animation(clip), from_sk, to_sk, shift, not CharacterModel.is_auto_rig(skin), idle_hips))
	from_body.free()
	to_body.free()
	_skin_libs[skin] = lib
	print("[SKIN] animations retargetées pour la peau %d en %d ms" % [skin, Time.get_ticks_msec() - t0])
	return lib


## Biggest per-key rotation steps (deg) over all bones, to locate capture glitches.
static func _dump_jumps(anim: Animation, label: String) -> void:
	var rows := []
	for tr in anim.get_track_count():
		if anim.track_get_type(tr) != Animation.TYPE_ROTATION_3D:
			continue
		var n := anim.track_get_key_count(tr)
		for i in n - 1:
			var q0: Quaternion = anim.track_get_key_value(tr, i)
			var q1: Quaternion = anim.track_get_key_value(tr, i + 1)
			var dt := maxf(anim.track_get_key_time(tr, i + 1) - anim.track_get_key_time(tr, i), 0.001)
			rows.append([rad_to_deg(q0.angle_to(q1)) / dt / 60.0, anim.track_get_key_time(tr, i), str(anim.track_get_path(tr)).get_slice(":", 1)])
	rows.sort_custom(func(a, b): return a[0] > b[0])
	for r in rows.slice(0, 12):
		print("[JUMP] %s %.1f deg/frame60 at t=%.3f bone=%s" % [label, r[0], r[1], r[2]])


static func _dump_hips(anim: Animation, label: String) -> void:
	for tr in anim.get_track_count():
		if not str(anim.track_get_path(tr)).ends_with("Hips"):
			continue
		var type := anim.track_get_type(tr)
		var n := anim.track_get_key_count(tr)
		var worst := 0.0
		var worst_i := 0
		for i in n:
			var v0 = anim.track_get_key_value(tr, i)
			var v1 = anim.track_get_key_value(tr, (i + 1) % n)
			var d: float = (v1 - v0).length() if type == Animation.TYPE_POSITION_3D else (v0 as Quaternion).angle_to(v1)
			if d > worst:
				worst = d
				worst_i = i
		print("[LOOP] %s len=%.3f type=%d keys=%d first=%s last=%s worst=%.3f at %d/%d t=%.3f" % [label, anim.length, type, n,
			anim.track_get_key_value(tr, 0), anim.track_get_key_value(tr, n - 1), worst, worst_i, n, anim.track_get_key_time(tr, worst_i)])


## Resamples `src` (transform tracks) over [start, start + span] into a new clip
## of length `out_len`. mode: "loop" (wraps around the source clip), "window"
## (straight crop) or "pingpong" (there and back again).
static func _resample(src: Animation, start: float, span: float, out_len: float, mode: String) -> Animation:
	var a := Animation.new()
	a.length = out_len
	var n := maxi(8, ceili(span * 60.0))
	for tr in src.get_track_count():
		var type := src.track_get_type(tr)
		if type != Animation.TYPE_POSITION_3D and type != Animation.TYPE_ROTATION_3D and type != Animation.TYPE_SCALE_3D:
			continue
		var nt := a.add_track(type)
		a.track_set_path(nt, src.track_get_path(tr))
		a.track_set_interpolation_type(nt, Animation.INTERPOLATION_LINEAR)
		# Loops get no end key (the loop closes on the first one); crops do.
		var count := n if mode != "window" else n + 1
		for i in count:
			var u := out_len * float(i) / n
			var st: float
			match mode:
				"loop":
					st = fposmod(start + u / out_len * span, src.length)
				"reverse":
					st = fposmod(start - u / out_len * span, src.length)
				"pingpong":
					var half := out_len * 0.5
					st = start + (u if u <= half else out_len - u) / half * span
				_:
					st = start + minf(u, out_len) / out_len * span
			st = clampf(st, 0.0, src.length)
			match type:
				Animation.TYPE_POSITION_3D:
					a.position_track_insert_key(nt, u, src.position_track_interpolate(tr, st))
				Animation.TYPE_ROTATION_3D:
					a.rotation_track_insert_key(nt, u, src.rotation_track_interpolate(tr, st))
				Animation.TYPE_SCALE_3D:
					a.scale_track_insert_key(nt, u, src.scale_track_interpolate(tr, st))
	return a


func _build_anim_tree() -> void:
	anim = AnimationTree.new()
	model.add_child(anim)
	anim.root_node = NodePath("..")
	anim.add_animation_library("mx", _skin_library(skin))
	var bt := AnimationNodeBlendTree.new()
	var loco := AnimationNodeBlendSpace2D.new()
	loco.min_space = Vector2(-7, -7)
	loco.max_space = Vector2(7, 7)
	loco.sync = true
	for pt in LOCO_POINTS:
		loco.add_blend_point(_anim_node("mx/loco_" + pt[0]), pt[2], -1, StringName(pt[0]))
	bt.add_node("loco", loco, Vector2(0, 0))
	bt.add_node("loco_ts", AnimationNodeTimeScale.new(), Vector2(200, 0))
	bt.connect_node("loco_ts", 0, "loco")
	bt.add_node("idle", _anim_node("mx/rifle_idle"), Vector2(200, -150))
	bt.add_node("move", AnimationNodeBlend2.new(), Vector2(300, 0))
	bt.connect_node("move", 0, "idle")
	bt.connect_node("move", 1, "loco_ts")
	bt.add_node("aim_pose", _anim_node("mx/rifle_aiming_idle"), Vector2(200, 150))
	bt.add_node("aim_idle", AnimationNodeBlend2.new(), Vector2(400, 0))
	bt.connect_node("aim_idle", 0, "move")
	bt.connect_node("aim_idle", 1, "aim_pose")
	# Crouch: forward and backward walks are two real baked loops (no reversed
	# playback), blended by the forward speed; idle mixed in separately.
	var cr := AnimationNodeBlendSpace1D.new()
	cr.min_space = -1.0
	cr.max_space = 1.0
	cr.sync = true
	cr.add_blend_point(_anim_node("mx/crouch_back"), -1.0, -1, &"back")
	cr.add_blend_point(_anim_node("mx/crouch_fwd"), 1.0, -1, &"fwd")
	bt.add_node("crouch_bs", cr, Vector2(200, 300))
	bt.add_node("crouch_ts", AnimationNodeTimeScale.new(), Vector2(400, 300))
	bt.connect_node("crouch_ts", 0, "crouch_bs")
	bt.add_node("crouch_idle", _anim_node("mx/crouch_idle"), Vector2(400, 420))
	bt.add_node("crouch_move", AnimationNodeBlend2.new(), Vector2(500, 300))
	bt.connect_node("crouch_move", 0, "crouch_idle")
	bt.connect_node("crouch_move", 1, "crouch_ts")
	bt.add_node("crouch", AnimationNodeBlend2.new(), Vector2(600, 0))
	bt.connect_node("crouch", 0, "aim_idle")
	bt.connect_node("crouch", 1, "crouch_move")
	var tr := AnimationNodeTransition.new()
	tr.xfade_time = 0.18
	# Ease in / out rather than a straight cross-fade (no visible start / stop of the blend).
	var xcurve := Curve.new()
	xcurve.add_point(Vector2(0, 0), 0.0, 0.0)
	xcurve.add_point(Vector2(1, 1), 0.0, 0.0)
	tr.xfade_curve = xcurve
	tr.add_input("loco")
	for s in STATES:
		tr.add_input(s)
	bt.add_node("state", tr, Vector2(900, 0))
	bt.connect_node("state", 0, "crouch")
	var i := 1
	for s in STATES:
		bt.add_node(s, _anim_node("mx/st_" + s), Vector2(600, 150 + i * 80))
		bt.add_node(s + "_ts", AnimationNodeTimeScale.new(), Vector2(750, 150 + i * 80))
		bt.connect_node(s + "_ts", 0, s)
		bt.connect_node("state", i, s + "_ts")
		i += 1
	bt.connect_node("output", 0, "state")
	anim.tree_root = bt
	anim.active = true
	for s in STATES:
		anim.set("parameters/%s_ts/scale" % s, STATES[s][1])
	anim.set("parameters/loco_ts/scale", 1.0)
	anim.set("parameters/crouch_ts/scale", 1.0)
	_trans = tr
	_set_state("loco", 0.0)


var _pop_hist := {}
var _pop_dt: Array = []
var _pop_count := 0


## Debug --log_pops: flags frames where a bone (skeleton space = animation only)
## or the head in world space jumps — the second difference of its position,
## normalised to 60 FPS, exceeds a threshold a smooth motion never reaches.
func _debug_pops(p: Player, delta: float, state: String) -> void:
	if delta <= 0.0 or (Game.debug.has("pops_local") and not p.is_local_human()):
		return
	_pop_dt.append(delta)
	if _pop_dt.size() > 2:
		_pop_dt.pop_front()
	var probes := {}
	for n in ["pelvis", "Head", "spine_03"]:
		probes["sk_" + n] = skeleton.get_bone_global_pose(skeleton.find_bone(bone_name(n))).origin
	probes["world_head"] = skeleton.global_transform * probes["sk_Head"]
	for k in probes:
		var h: Array = _pop_hist.get(k, [])
		h.append(probes[k])
		if h.size() > 3:
			h.pop_front()
		_pop_hist[k] = h
		if h.size() == 3 and _pop_dt.size() == 2:
			# Real acceleration from uneven frame times, expressed as the
			# position change it would cause over one 60 FPS frame.
			var d0: float = _pop_dt[0]
			var d1: float = _pop_dt[1]
			var acc: Vector3 = ((h[2] - h[1]) / d1 - (h[1] - h[0]) / d0) / ((d0 + d1) * 0.5)
			var j: float = acc.length() / 3600.0
			if j > 0.03:
				_pop_count += 1
				print("[POP] %s %s j=%.3f state=%s prev=%s st=%.2f loco=%s move=%.2f crouch=%.2f aim=%.2f air=%.2f spd=%.2f yaw_rate=%.1f" % [
					p.display_name, k, j, state, _state, _state_t, _loco_pos, _move_w, _crouch_w, _aim_idle, _air_t,
					Vector2(p.velocity.x, p.velocity.z).length(), p.yaw_rate])


## Hips height of a library clip at time t (reads its position track).
func _clip_hips_y(clip: String, t: float) -> float:
	var a := CharacterModel.mixamo_library().get_animation(clip)
	if not _hips_tracks.has(clip):
		_hips_tracks[clip] = a.find_track(NodePath("Skeleton3D:" + bone_name("pelvis")), Animation.TYPE_POSITION_3D)
	var tr: int = _hips_tracks[clip]
	if tr < 0:
		return VAULT_HIPS_REST
	return a.position_track_interpolate(tr, t).y


## Cycle rate (cycles/s on the 1 s timelines) for a local velocity: per
## direction, interpolate the clip's own rate and the stride-matched rate.
func _loco_rate(v: Vector2) -> float:
	var speed := v.length()
	if speed < 0.05:
		return 1.0 / RATE_FWD[0][1]
	var d := v / speed
	var w := [maxf(d.y, 0.0), maxf(-d.y, 0.0), maxf(d.x, 0.0), maxf(-d.x, 0.0)]
	var tables := [RATE_FWD, RATE_BACK, RATE_RIGHT, RATE_LEFT]
	var total := 0.0
	var rate := 0.0
	for k in 4:
		if w[k] <= 0.001:
			continue
		rate += w[k] * _table_rate(tables[k], maxf(speed, 0.9))
		total += w[k]
	return rate / maxf(total, 0.001)


static func _table_rate(table: Array, speed: float) -> float:
	var length: float = table[0][1]
	var stride: float = table[0][2]
	if speed >= table[-1][0]:
		length = table[-1][1]
		stride = table[-1][2]
	else:
		for i in range(1, table.size()):
			if speed <= table[i][0]:
				var k := clampf((speed - table[i - 1][0]) / (table[i][0] - table[i - 1][0]), 0.0, 1.0)
				length = lerpf(table[i - 1][1], table[i][1], k)
				stride = lerpf(table[i - 1][2], table[i][2], k)
				break
	var natural := 1.0 / length
	var matched := speed / stride
	return natural * pow(matched / natural, STRIDE_MATCH)


var _trans: AnimationNodeTransition


## Blend time (s) when LEAVING a one-off state back to free movement: longer than going in,
## so a slide, a roll or a landing melts into the run instead of snapping.
const EXIT_XFADE := {
	"slide": 0.34, "slide_in": 0.22, "roll": 0.26, "air": 0.16, "land": 0.24, "mantle": 0.22, "vault": 0.3,
	"throw": 0.24, "heal_self": 0.3, "heal_ally": 0.3, "revive": 0.3, "search": 0.3, "shield": 0.3,
}


func _set_state(s: String, xfade: float) -> void:
	if s == _state:
		return
	if s == "loco":
		xfade = maxf(xfade, float(EXIT_XFADE.get(_state, xfade)))
	_trans.xfade_time = xfade
	anim.set("parameters/state/transition_request", s)
	_state = s
	_state_t = 0.0


# ---------------------------------------------------------------- gear

func _attach(bone: String) -> Node3D:
	var ba := BoneAttachment3D.new()
	bone = bone_name(bone)
	ba.bone_name = bone
	skeleton.add_child(ba)
	# Child frame aligned with skeleton axes at rest, so gear is authored in
	# model space (+Z forward, -X right) relative to the bone origin.
	var rest := skeleton.get_bone_global_rest(skeleton.find_bone(bone))
	var frame := Node3D.new()
	frame.basis = rest.basis.orthonormalized().inverse()
	ba.add_child(frame)
	return frame


## Team identification on the realistic trooper: glowing armbands on both upper
## arms and a light strip on the back of the helmet, in the team colour.
func _build_team_marks(accent: Color) -> void:
	var glow := Mats.emissive("teamband%d" % team, accent, 0.45, false)
	for side in ["l", "r"]:
		var arm := _attach("upperarm_" + side)
		var band := CylinderMesh.new()
		band.top_radius = 0.083
		band.bottom_radius = 0.083
		band.height = 0.035
		band.radial_segments = 16
		band.rings = 1
		# Align the band with the upper arm's real rest direction (the rig rests
		# in an A-pose), 45% of the way down to the elbow.
		var a := skeleton.get_bone_global_rest(skeleton.find_bone(bone_name("upperarm_" + side))).origin
		var b := skeleton.get_bone_global_rest(skeleton.find_bone(bone_name("lowerarm_" + side))).origin
		var dir := (b - a).normalized()
		_mesh(arm, band, glow, dir * a.distance_to(b) * 0.45, Vector3.ONE, Basis(Quaternion(Vector3.UP, dir)))
	var head := _attach("Head")
	# Other bodies have no helmet: the strip rides low on the back of the skull.
	_mesh(head, Shapes.rounded_box(Vector3(0.09, 0.025, 0.02), 0.008), glow, Vector3(0, 0.17, -0.15) if skin == 0 else Vector3(0, 0.1, -0.125))


## The Ferro is an IZH-27 over-under (CC BY, PeLmEsHkO): real model, its own
## skeleton has a "barrel_01" bone on the hinge, driven here for the break-open.
## Gun frame: forward is -Z, origin near the pistol grip (hands/IK targets below).
const GUN_SCENE := "res://assets/sketchfab/izh27/scene.gltf"
## IZH model space (+Z forward) -> gun frame (-Z forward), trigger aligned.
const GUN_MODEL_XF := Transform3D(Basis(Vector3.UP, PI), Vector3(0, -0.05, 0.115))

var _gun_skel: Skeleton3D
var _gun_barrel := -1
var _gun_barrel_rest := Transform3D()


func _build_gun(accent: Color) -> void:
	var weapon := int(loadout.weapon)
	_muzzle_z = -0.82 if weapon == 1 else -0.87
	_stock_back = 0.39 if weapon == 1 else 0.33
	gun = Node3D.new()
	gun.top_level = true
	add_child(gun)
	var hinge := Vector3(0, 0, -0.1)
	if weapon == 1:
		var model := (load(GUN_SCENE) as PackedScene).instantiate() as Node3D
		model.transform = GUN_MODEL_XF
		gun.add_child(model)
		_gun_skel = model.find_children("*", "Skeleton3D", true, false)[0]
		_gun_barrel = _gun_skel.find_bone("barrel_01")
		_gun_barrel_rest = _gun_skel.get_bone_global_rest(_gun_barrel)
		for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		hinge = GUN_MODEL_XF * _gun_barrel_rest.origin
	else:
		# Longshot (Meshy AI): long axis is model X (muzzle at -X, stock at +X). Turn it to
		# the gun frame (forward -Z) and scale it down to rifle size, trigger at the origin.
		var model := (load(LONGSHOT_SCENE) as PackedScene).instantiate() as Node3D
		var rot := Basis(Vector3.UP, -PI / 2) * LONGSHOT_SCALE
		model.transform = Transform3D(rot, -(rot * LONGSHOT_ORIGIN))
		gun.add_child(model)
		for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_break_open = weapon == 1
	# Hinge in the gun frame, barrels rotate around it on break-action guns.
	barrel_pivot = Node3D.new()
	barrel_pivot.position = hinge
	gun.add_child(barrel_pivot)
	var b := Node3D.new()
	b.position = -barrel_pivot.position
	barrel_pivot.add_child(b)
	_gun_barrels = b
	# Team-coloured bead near the muzzle (readable from afar).
	_mesh(b, Shapes.rounded_box(Vector3(0.006, 0.01, 0.012), 0.002), Mats.emissive("sight%d" % team, accent, 2.0, false), Vector3(0, 0.0, -0.78) if weapon == 1 else Vector3(0, 0.045, -0.62))
	muzzle = Node3D.new()
	muzzle.position = Vector3(0, -0.02 if weapon == 1 else 0.0, _muzzle_z)
	b.add_child(muzzle)
	grip_r = Node3D.new()
	grip_r.position = Vector3(0, -0.095, 0.085) if weapon == 1 else LONGSHOT_GRIP_R
	gun.add_child(grip_r)
	grip_l = Node3D.new()
	grip_l.position = Vector3(0, -0.07, -0.22) if weapon == 1 else LONGSHOT_GRIP_L
	b.add_child(grip_l)


const LONGSHOT_SCENE := "res://assets/weapons/longshot.glb"
const LONGSHOT_SCALE := 0.62
## Trigger area in the model's own frame (becomes the gun frame origin, bore axis height).
const LONGSHOT_ORIGIN := Vector3(0.44, 0.066, 0.0)
const LONGSHOT_GRIP_R := Vector3(0, -0.075, 0.06)
const LONGSHOT_GRIP_L := Vector3(0, -0.085, -0.15)
var _muzzle_z := -0.82
## Trigger -> butt distance: the aimed rifle sits with its butt in the shoulder pocket.
var _stock_back := 0.39
var _break_open := true

var _gun_barrels: Node3D
var _silencer: Node3D
var _stock_pad: Node3D
const SILENCER_LEN := 0.2


## Shows the attachments found in the crates: a suppressor on the muzzle (the
## muzzle flash moves to its end) and a cheek riser + recoil pad on the stock.
func set_attachments(silencer: bool, stock: bool) -> void:
	if _gun_barrels == null:
		return
	if silencer and _silencer == null:
		_silencer = Node3D.new()
		var can := CylinderMesh.new()
		can.top_radius = 0.031
		can.bottom_radius = 0.031
		can.height = SILENCER_LEN
		can.radial_segments = 14
		can.rings = 1
		_mesh(_silencer, can, Mats.gun_metal_dark(), Vector3(0, 0, -SILENCER_LEN * 0.5), Vector3.ONE, Basis(Vector3.RIGHT, PI / 2))
		var ring := CylinderMesh.new()
		ring.top_radius = 0.034
		ring.bottom_radius = 0.034
		ring.height = 0.012
		ring.radial_segments = 14
		ring.rings = 1
		for z in [0.02, SILENCER_LEN - 0.012]:
			_mesh(_silencer, ring, Mats.gun_metal(), Vector3(0, 0, -z), Vector3.ONE, Basis(Vector3.RIGHT, PI / 2))
		_silencer.position = Vector3(0, -0.02, _muzzle_z + 0.03)
		_gun_barrels.add_child(_silencer)
	if _silencer:
		_silencer.visible = silencer
	muzzle.position.z = _muzzle_z - (SILENCER_LEN - 0.03 if silencer else 0.0)
	if stock and _stock_pad == null:
		_stock_pad = Node3D.new()
		_mesh(_stock_pad, Shapes.rounded_box(Vector3(0.056, 0.03, 0.17), 0.008), Mats.flat("stock_riser", Color(0.16, 0.2, 0.15), 0.8, 0.0), Vector3(0, 0.045, 0.24))
		_mesh(_stock_pad, Shapes.rounded_box(Vector3(0.062, 0.17, 0.028), 0.01), Mats.flat("stock_pad", Color(0.05, 0.05, 0.05), 0.95, 0.0), Vector3(0, -0.06, 0.392))
		_mesh(_stock_pad, Shapes.rounded_box(Vector3(0.058, 0.012, 0.2), 0.004), Mats.emissive("stock_strip", Items.ATTACHMENTS.stock.color, 1.2, false), Vector3(0, 0.063, 0.24))
		gun.add_child(_stock_pad)
	if _stock_pad:
		_stock_pad.visible = stock


## Mirrors barrel_pivot's break angle onto the IZH barrel bone.
func _sync_gun_barrel() -> void:
	if _gun_skel == null or _gun_barrel < 0:
		return
	# Gun-frame X is the model's -X (rotated 180° about Y): same angle, opposite sign.
	var ang := -barrel_pivot.rotation.x
	var parent := _gun_skel.get_bone_parent(_gun_barrel)
	var parent_g := _gun_skel.get_bone_global_pose(parent) if parent >= 0 else Transform3D()
	var want := Transform3D(Basis(Vector3.RIGHT, ang) * _gun_barrel_rest.basis, _gun_barrel_rest.origin)
	_gun_skel.set_bone_pose(_gun_barrel, parent_g.affine_inverse() * want)


## Grenade / smoke can / folded barricade shown in the right hand when selected.
func _build_hand_items() -> void:
	var hand := _attach("hand_r")
	var frag := Node3D.new()
	var fb := SphereMesh.new()
	fb.radius = 0.05
	fb.height = 0.11
	_mesh(frag, fb, Mats.flat("frag_body", Color(0.22, 0.27, 0.16), 0.6, 0.2), Vector3.ZERO)
	_mesh(frag, _cyl(0.018, 0.04), Mats.gun_metal(), Vector3(0, 0.065, 0))
	var smoke := Node3D.new()
	_mesh(smoke, _cyl(0.035, 0.14), Mats.flat("smoke_can", Color(0.55, 0.57, 0.58), 0.5, 0.3), Vector3.ZERO)
	_mesh(smoke, _cyl(0.037, 0.025), Mats.emissive("smoke_band", Color(0.9, 0.9, 0.95), 0.6, false), Vector3(0, 0.04, 0))
	var barr := Node3D.new()
	_mesh(barr, Shapes.rounded_box(Vector3(0.5, 0.36, 0.08), 0.02), Mats.pbr_local("painted_metal_shutter", Color(0.55, 0.56, 0.5), 1.2), Vector3(0, -0.12, 0.0))
	var defib := Node3D.new()
	_mesh(defib, Shapes.rounded_box(Vector3(0.09, 0.05, 0.13), 0.012), Mats.flat("defib_body", Color(0.85, 0.86, 0.82), 0.5, 0.1), Vector3.ZERO)
	_mesh(defib, Shapes.rounded_box(Vector3(0.07, 0.012, 0.09), 0.004), Mats.emissive("defib_led", Color(0.35, 0.95, 0.55), 1.5, false), Vector3(0, 0.03, 0))
	_mesh(defib, _cyl(0.012, 0.05), Mats.gun_metal(), Vector3(0, -0.04, 0.03))
	for pair in [["frag", frag, Vector3(-0.07, -0.02, 0.04)], ["smoke", smoke, Vector3(-0.07, -0.02, 0.04)], ["barricade", barr, Vector3(-0.08, -0.05, 0.12)], ["defib", defib, Vector3(-0.07, -0.03, 0.05)]]:
		var n: Node3D = pair[1]
		n.position = pair[2]
		n.visible = false
		hand.add_child(n)
		_hand_items[pair[0]] = n


## Collapses the many small gear meshes into one mesh per material under each
## static parent (bone attachments, backpack, gun parts): ~80 -> ~20 draw calls
## per raider. Moving parts (barrel pivot, hand items) stay separate nodes.
func _merge_static_meshes() -> void:
	var parents: Array[Node3D] = []
	for n in find_children("*", "Node3D", true, false):
		var has_meshes := false
		for ch in n.get_children():
			if ch is MeshInstance3D:
				has_meshes = true
				break
		if has_meshes and not (n is MeshInstance3D) and n != gun.get_parent():
			parents.append(n)
	for parent in parents:
		if _hand_items.values().has(parent):
			continue
		var groups := {}
		for ch in parent.get_children():
			if ch is MeshInstance3D and ch.get_child_count() == 0 and not String(ch.name).to_lower().begins_with("superhero"):
				var mi := ch as MeshInstance3D
				if mi.material_override == null or mi.mesh == null:
					continue
				# Only same material AND same vertex format merge cleanly.
				var key := [mi.material_override, mi.mesh is PrimitiveMesh]
				if not groups.has(key):
					groups[key] = []
				groups[key].append(mi)
		for key in groups:
			var mat: Material = key[0]
			var list: Array = groups[key]
			if list.size() < 2:
				continue
			var st := SurfaceTool.new()
			for mi: MeshInstance3D in list:
				st.append_from(mi.mesh, 0, mi.transform)
			var merged := MeshInstance3D.new()
			merged.mesh = st.commit()
			merged.material_override = mat
			parent.add_child(merged)
			for mi: MeshInstance3D in list:
				parent.remove_child(mi)
				mi.queue_free()


## Menu turntable: idle pose, rifle at low ready, no Player needed.
func update_preview(delta: float) -> void:
	# Debug --prev_pose=aim|sprint|ready: freeze the menu model in that carry pose.
	var pose := str(Game.debug.get("prev_pose", "ready"))
	_aim = 1.0 if pose == "aim" else 0.0
	_sprint = 1.0 if pose == "sprint" else 0.0
	_sling = 0.0
	blade = BLADE_AIM * _aim
	arm_w = 1.0
	hip_yaw = 0.0
	spine_pitch = 0.0
	_reload_k = float(Game.debug.get("prev_reload", -1.0))
	_recoil = float(Game.debug.get("prev_recoil", 0.0))
	_recoil_v = 0.0
	_pitch = lerpf(_pitch, -0.1, delta * 3.0)
	lean = Vector2.ZERO
	# Debug --prev_state=slide|roll|air|vault...: freeze the menu model in that state.
	_set_state(str(Game.debug.get("prev_state", "loco")), 0.0 if Game.debug.has("prev_state") else 0.2)
	anim.set("parameters/move/blend_amount", 0.0)
	anim.set("parameters/crouch/blend_amount", 0.0)
	anim.set("parameters/aim_idle/blend_amount", 0.0)


func play_dead_instant() -> void:
	_set_state("dead", 0.0)
	anim.advance(DEATH_LEN + 0.1)


func play_throw() -> void:
	_throw_t = 0.55


## Ferro shot: shove the recoil spring (gun into the shoulder, muzzle up,
## torso rocked back). Integrated in update_pose.
func fire_recoil() -> void:
	_recoil_v += 30.0


## Recoil spring (stiff, slightly under-damped): ~0.7 peak 40 ms after the shot.
func _step_recoil(delta: float) -> void:
	# Fixed small sub-steps: stable whatever the frame time (hitches included).
	delta = minf(delta, 0.1)
	var steps := maxi(1, ceili(delta / 0.004))
	var h := delta / steps
	for i in steps:
		_recoil_v += (-_recoil * 420.0 - _recoil_v * 27.0) * h
		_recoil += _recoil_v * h
	kick_lean = _recoil * 0.17


# ---------------------------------------------------------------- API used by Player

## Prop hunt: look like a scanned prop (entry of Scan.catalog) instead of a raider; {} = back.
func set_disguise(e: Dictionary) -> void:
	disguised = not e.is_empty()
	if _prop_node:
		_prop_node.queue_free()
		_prop_node = null
	model.visible = not disguised
	gun.visible = not disguised
	if not disguised:
		return
	_prop_node = Node3D.new()
	_prop_node.scale = Vector3.ONE * float(e.scale)
	add_child(_prop_node)
	for part in Scan.get_parts(e.id, e.prefix).parts:
		var mi := MeshInstance3D.new()
		mi.mesh = part[0]
		mi.transform = part[1]
		_prop_node.add_child(mi)


func reset() -> void:
	_flinch = 0.0
	lean = Vector2.ZERO
	_down_seen = false
	_lift = 0.0
	model.position.y = 0.0
	_set_state("loco", 0.0)


func flinch() -> void:
	_flinch = 1.0
	_suit.set_shader_parameter("flash", 0.25)


## Called every rendered frame by Player.
func update_pose(p: Player, delta: float) -> void:
	rotation.y = p.visual_yaw()
	_step_recoil(delta)
	var hv := Vector3(p.velocity.x, 0, p.velocity.z)
	var speed := hv.length()
	var k := 1.0 - exp(-delta * 12.0)
	var bandaging := p.bandage_target != ""
	var rolling := p.roll_progress() >= 0.0
	_aim = lerpf(_aim, 1.0 if (p.aiming or p.recent_fire()) and not bandaging else 0.0, 1.0 - exp(-delta * 16.0))
	_sprint = lerpf(_sprint, 1.0 if p.sprinting else 0.0, k)
	var held := p.held_item()
	for key in _hand_items:
		_hand_items[key].visible = key == held and p.alive
	_throw_t = maxf(0.0, _throw_t - delta)
	var mantling := p.mantle_t >= 0.0
	var reviving := p.revive_target != ""
	var charging := p.shield_t >= 0.0
	var searching := p.searching and speed < 1.0 and p.alive and p.grounded()
	_sling = lerpf(_sling, 1.0 if (bandaging or reviving or charging or searching or rolling or (Game.is_ph() and team == 1) or mantling or not p.alive or held != "" or _throw_t > 0.0) else 0.0, 1.0 - exp(-delta * 14.0))
	if p.downed:
		_down_seen = true
	elif p.alive:
		_down_seen = false
	var prone := p.downed or (not p.alive and _down_seen)
	_lift = lerpf(_lift, DOWN_LIFT if prone else 0.0, 1.0 - exp(-delta * 10.0))
	model.position.y = _lift
	var unarmed := Game.is_ph() and team == 1 # prop hunt: props carry no weapon
	gun.visible = not prone and not disguised and not unarmed
	var sg := _shield_glow(p, charging, delta)
	_suit.set_shader_parameter("shield_glow", sg)
	# The overlay pass doubles the body's draw cost: only attach it while visible.
	var want_overlay := sg > 0.01 or _flinch > 0.01
	if want_overlay != _overlay_on:
		_overlay_on = want_overlay
		for m in _body_mats:
			m.next_pass = _suit if want_overlay else null
	arm_w = 1.0 - _sling
	_flinch = move_toward(_flinch, 0.0, delta * 4.0)
	_suit.set_shader_parameter("flash", _flinch * 0.25)
	_reload_k = p.reload_progress()
	_pitch = lerpf(_pitch, p.look_pitch, 1.0 - exp(-delta * 20.0))
	spine_pitch = _pitch * _aim * 0.8 + _flinch * 0.2
	_air_t = 0.0 if p.grounded() else _air_t + delta
	_state_t += delta
	var sliding := p.slide_t >= 0.0

	# Movement direction relative to the body (F frame: forward -Z, +X right).
	var local := Basis(Vector3.UP, p.body_yaw).inverse() * hv
	var ang := atan2(local.x, -local.z)
	# Hysteresis around 90° so a pure strafe doesn't flicker between forward
	# and backwards legs.
	var back_limit := 1.45 if _backwards else 1.75
	var backwards := speed > 0.4 and absf(ang) > back_limit
	_backwards = backwards
	var want_hip := 0.0
	# Standing: real directional clips (strafes, backwards) carry the legs.
	# Crouched there is only a forward walk, so twist the hips towards the motion.
	if _air_t > 0.05 and p.alive and not rolling and not sliding and not mantling:
		# The rifle-jump capture has the hips yawed ~70 deg off the body (legs
		# kicked sideways): square them up with the torso while airborne.
		want_hip = deg_to_rad(AIR_HIP_TWIST)
	elif speed > 0.4 and p.crouching and not rolling and not sliding and not mantling and p.alive:
		want_hip = -(wrapf(ang - PI, -PI, PI) if backwards else ang)
		want_hip = clampf(want_hip, -1.45, 1.45)
	elif speed > 0.4 and p.sprinting and p.alive:
		# Body lags the sprint direction a little: keep the legs on the motion.
		want_hip = clampf(-ang, -0.5, 0.5)
	hip_yaw = lerp_angle(hip_yaw, want_hip, 1.0 - exp(-delta * 24.0))

	# Lean: into turns (yaw rate x speed) and with acceleration, from the
	# Player's physics-rate smoothed dynamics (no frame-rate jitter).
	var acc_local := Basis(Vector3.UP, p.body_yaw).inverse() * p.move_accel
	var yaw_rate := p.yaw_rate
	var want_lean := Vector2.ZERO
	if p.alive and p.grounded() and not rolling and not mantling and not sliding:
		var turn := clampf(yaw_rate * speed * 0.018, -0.2, 0.2)
		var side := clampf(acc_local.x * 0.012, -0.12, 0.12)
		# Model space roll: positive z rotation tips the top towards model -X (= game right).
		want_lean.x = (turn - side) * (1.0 - _aim * 0.7)
		want_lean.y = clampf(-acc_local.z * 0.012, -0.12, 0.16) * (1.0 - _aim * 0.7) + _sprint * 0.08 + _aim * 0.16
	if sliding and p.alive:
		# Sit the torso up a little during the slide, gun ready.
		want_lean.y = 0.25 - _aim * 0.1
	lean = lean.lerp(want_lean, 1.0 - exp(-delta * (10.0 if sliding else 7.0)))

	# ---- State machine (top-level transition)
	var state := "loco"
	var xfade := 0.18
	if p.downed:
		state = "down"
		xfade = 0.3
	elif prone:
		# Finished while down: collapse flat on the belly.
		state = "dead_prone"
		xfade = 0.25
	elif not p.alive:
		state = "dead"
		xfade = 0.12
	elif reviving:
		state = "revive"
		xfade = 0.2
	elif _throw_t > 0.0:
		state = "throw"
		xfade = 0.08
	elif mantling:
		state = "vault" if p.mantle_vault else "mantle"
		xfade = 0.08
	elif rolling:
		state = "roll"
		xfade = 0.12
	elif sliding:
		state = "slide" if (_state == "slide" or (_state == "slide_in" and _state_t > 0.38)) else "slide_in"
		xfade = 0.1 if state == "slide_in" else 0.2
	elif bandaging:
		var t := p.get_bandage_target_node()
		state = "heal_ally" if t and t != p else "heal_self"
	elif charging:
		state = "shield"
	elif searching:
		state = "search"
	elif _air_t > 0.12 or (_air_t > 0.0 and p.velocity.y > 2.5):
		# A jump leaves the ground at once (no 0.12 s of floating legs); a walk-off waits.
		state = "air"
		xfade = 0.1 if p.velocity.y > 1.0 else 0.25
	elif p.land_t > 0.0 or (_state == "land" and _state_t < 0.3):
		state = "land"
		xfade = 0.06
	_set_state(state, xfade)
	if Game.debug.has("log_pops"):
		_debug_pops(p, delta, state)

	# Per-state speeds.
	match state:
		"roll":
			anim.set("parameters/roll_ts/scale", ROLL_TIMELINE / Player.ROLL_TIME * 0.95)
		"mantle":
			anim.set("parameters/mantle_ts/scale", MANTLE_CLIP[1] / maxf(p.mantle_duration(), 0.2))
		"vault":
			anim.set("parameters/vault_ts/scale", Player.VAULT_SPEED)
		"slide":
			anim.set("parameters/slide_ts/scale", clampf(speed / 6.0, 0.3, 1.0))
		"down":
			# Crawl cycle follows the crawl speed (clip: 0.43 m/s).
			anim.set("parameters/down_ts/scale", maxf(clampf(speed / 0.43, 0.0, 3.0) * 0.8, 0.03))

	# The vault clip lifts its own hips over the box; the Player already moves the
	# body along the arc, so cancel the clip's rise (sampled at the current clip time).
	var comp := 0.0
	if state == "mantle":
		var clip_t: float = MANTLE_CLIP[0] + minf(_state_t * MANTLE_CLIP[1] / maxf(p.mantle_duration(), 0.2), MANTLE_CLIP[1])
		comp = maxf(0.0, _clip_hips_y("vault_over_box", clip_t) - VAULT_HIPS_REST)
	_vault_comp = lerpf(_vault_comp, comp, 1.0 - exp(-delta * 30.0))
	# Vault: the capture was made over a 1.05 m box. Lift / lower the body over
	# the real obstacle, and plant the hands on its top during the support phase.
	var vault_lift := 0.0
	vault_w = 0.0
	if state == "vault":
		var tau := VaultMath.T0 + clampf(p.mantle_t / maxf(p.mantle_duration(), 0.2), 0.0, 1.0) * VaultMath.LEN
		vault_lift = VaultMath.lift(tau, p.mantle_height)
		if p.vault_hands.size() == 2:
			vault_w = smoothstep(0.26, 0.4, tau) * (1.0 - smoothstep(0.72, 1.0, tau))
			vault_hand_pos = p.vault_hands
			vault_dir = p.vault_dir
	model.position.y = _lift - _vault_comp + vault_lift

	# ---- Locomotion blend (always evaluated, so leaving a state lands on the right pose)
	# Local velocity in the model's frame (x = right, y = forward) picks the
	# directional blend; the cycle rate follows the real speed (see _loco_rate).
	var lv := Vector2(local.x, -local.z)
	# Upper body leads the camera, the legs catch up (see Player facing): twist the
	# spine by the gap between the camera and the legs.
	var want_twist := 0.0
	if p.alive and not p.downed and not rolling and not mantling and not sliding and not p.sprinting and p.grounded():
		want_twist = clampf(angle_difference(p.visual_yaw(), p.look_yaw), -TORSO_TWIST_MAX, TORSO_TWIST_MAX)
	torso_twist = lerpf(torso_twist, want_twist, 1.0 - exp(-delta * 18.0))
	blade = lerpf(blade, BLADE_AIM * _aim * (1.0 - _sling) if p.alive and not p.downed else 0.0, 1.0 - exp(-delta * 14.0))
	_loco_pos = _loco_pos.lerp(lv.limit_length(7.0), 1.0 - exp(-delta * 10.0))
	anim.set("parameters/loco/blend_position", _loco_pos)
	_move_w = lerpf(_move_w, smoothstep(0.15, 1.1, speed), 1.0 - exp(-delta * 24.0))
	anim.set("parameters/move/blend_amount", _move_w)
	anim.set("parameters/loco_ts/scale", _loco_rate(_loco_pos))
	_crouch_w = lerpf(_crouch_w, 1.0 if p.crouching else 0.0, 1.0 - exp(-delta * 10.0))
	anim.set("parameters/crouch/blend_amount", _crouch_w)
	# Crouched: forward or backward walk (the hips twist covers the sides),
	# idle mixed in by speed, cycle rate from the real speed.
	_crouch_dir = lerpf(_crouch_dir, -1.0 if backwards else 1.0, 1.0 - exp(-delta * 12.0))
	anim.set("parameters/crouch_bs/blend_position", _crouch_dir)
	_crouch_move = lerpf(_crouch_move, smoothstep(0.15, 0.8, speed), 1.0 - exp(-delta * 16.0))
	anim.set("parameters/crouch_move/blend_amount", _crouch_move)
	var c_nat := 1.0 / CROUCH_LEN
	var c_req := maxf(speed, 0.5) / CROUCH_STRIDE
	anim.set("parameters/crouch_ts/scale", c_nat * pow(c_req / c_nat, STRIDE_MATCH))
	_aim_idle = lerpf(_aim_idle, _aim * (1.0 - clampf(speed / 1.2, 0.0, 1.0)), k)
	anim.set("parameters/aim_idle/blend_amount", _aim_idle)

	# Footsteps
	_phase += speed / maxf(1.2, 1.6 + _sprint) * TAU * delta
	var step := int(_phase / PI)
	if step != _last_step and speed > 1.0 and p.grounded() and p.alive and not rolling and not sliding and not mantling:
		_last_step = step
		var cam := get_viewport().get_camera_3d()
		if cam == null or cam.global_position.distance_to(p.global_position) < 45.0:
			Audio.play_step(p.global_position, p.surface_underfoot(), -11.0 + _sprint * 4.0 - (6.0 if p.crouching else 0.0))


## Rifle transform in skeleton space, from the (animated) chest bone origin.
func gun_transform(chest: Vector3) -> Transform3D:
	var pivot := Vector3(0, 0.13, 0)
	var pb := Basis(Vector3.RIGHT, _pitch)
	var aimed := Transform3D(pb, pivot + pb * Vector3(0.15, -0.02, -_stock_back))
	# Low ready and sprint carry keep the butt tucked in the shoulder pocket (the rifle swings
	# about it), so the stock never pokes out behind the raider.
	var r_ready := Basis.from_euler(Vector3(-0.42, 0.62, 0.18))
	var ready := Transform3D(r_ready, Vector3(0.26, 0.03, -0.3) - r_ready * Vector3(0, 0, _stock_back))
	var r_sprint := Basis.from_euler(Vector3(-0.4, 0.75, 0.45))
	var sprint := Transform3D(r_sprint, Vector3(0.15, 0.03, -0.03) - r_sprint * Vector3(0, 0, _stock_back))
	var slung := Transform3D(Basis.from_euler(Vector3(1.2, 0.0, 0.9)), Vector3(0.0, 0.05, 0.32))
	var gx := ready.interpolate_with(aimed, _aim)
	gx = gx.interpolate_with(sprint, _sprint * (1.0 - _aim))
	gx = gx.interpolate_with(slung, _sling)
	if absf(_recoil) > 0.001:
		# Recoil: gun driven back into the shoulder (+Z), muzzle flips up, slight roll.
		var r := _recoil * (1.0 - _sling)
		gx = gx * Transform3D(Basis(Vector3.RIGHT, 0.36 * r) * Basis(Vector3.FORWARD, 0.06 * r), Vector3(0, 0.03 * r, 0.11 * r))
	if _reload_k >= 0.0:
		# Break-action: barrel drops on its hinge, gun is tilted up towards the chest.
		var open := smoothstep(0.0, 0.08, _reload_k) * (1.0 - smoothstep(0.73, 0.78, _reload_k))
		gx = gx * Transform3D(Basis(Vector3.RIGHT, 0.25 * open) * Basis(Vector3.UP, -0.3 * open), Vector3(-0.05 * open, 0.06 * open, 0.08 * open))
		barrel_pivot.rotation.x = -0.62 * open if _break_open else 0.0
	else:
		barrel_pivot.rotation.x = 0.0
	_sync_gun_barrel()
	_pouch_s = chest + FLIP * Vector3(-0.12, -0.25, -0.12)
	# The rifle rides with the twisted upper body.
	return Transform3D(FLIP, chest) * Transform3D(Basis(Vector3.UP, torso_twist), Vector3.ZERO) * gx


## Finger direction of each hand in the gun frame (-Z forward, +X right, +Y up): the right
## hand wraps the pistol grip from the right, the left hand cups the handguard from below.
const HAND_DIR_R := Vector3(-0.9, -0.35, -0.1)
const HAND_DIR_L := Vector3(0.9, 0.25, -0.1)
## Wrist -> palm centre, as a share of the wrist -> middle knuckle length.
const PALM_SHARE := 0.55
var _palm_len := 0.09


## Global finger direction of hand 0 = right, 1 = left.
func hand_dir(i: int) -> Vector3:
	return (gun.global_basis * (HAND_DIR_R if i == 0 else HAND_DIR_L)).normalized()


## Where the palm centre must sit (global): on the grip.
func grip_point(i: int) -> Vector3:
	var t := grip_r.global_position if i == 0 else grip_l.global_position
	if i == 1 and _reload_k >= 0.0:
		var mid := clampf(sin(_reload_k * PI) * 1.6, 0.0, 1.0)
		t = t.lerp(skeleton.global_transform * _pouch_s, mid)
	return t


## Point the fingertips close in on: just past the far side of the grip, so the fingers wrap it.
func grip_wrap(i: int) -> Vector3:
	var off := Vector3(-0.03, 0.0, -0.01) if i == 0 else Vector3(0.05, 0.05, 0.0)
	return grip_point(i) + gun.global_basis * off


## IK target (global) for the wrist of hand 0 = right, 1 = left.
func hand_target(i: int) -> Vector3:
	return grip_point(i) - hand_dir(i) * _palm_len * PALM_SHARE

# ---------------------------------------------------------------- helpers

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


func _mesh(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, scl := Vector3.ONE, basis := Basis()) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.transform = Transform3D(basis.scaled(scl), pos)
	parent.add_child(mi)
	return mi


static var _mesh_cache := {}


static func _box(s: Vector3) -> BoxMesh:
	var key := "b" + str(s)
	if not _mesh_cache.has(key):
		var m := BoxMesh.new()
		m.size = s
		_mesh_cache[key] = m
	return _mesh_cache[key]


static func _sphere(r: float) -> SphereMesh:
	var key := "s%f" % r
	if not _mesh_cache.has(key):
		var m := SphereMesh.new()
		m.radius = r
		m.height = r * 2.0
		m.radial_segments = 16
		m.rings = 10
		_mesh_cache[key] = m
	return _mesh_cache[key]


static func _cyl(r: float, h: float) -> CylinderMesh:
	var key := "y%f_%f" % [r, h]
	if not _mesh_cache.has(key):
		var m := CylinderMesh.new()
		m.top_radius = r
		m.bottom_radius = r
		m.height = h
		m.radial_segments = 12
		_mesh_cache[key] = m
	return _mesh_cache[key]
