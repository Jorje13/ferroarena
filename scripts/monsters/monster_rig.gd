class_name MonsterRig
extends Node3D
## Visual of one monster: a rigged Meshy body (anonymous "Bone_NNN" bones, no clips) brought to
## life by a procedural pose (MonsterPose). The same node is used on the server (invisible
## puppet is not needed: the server only simulates) and on every client.
##
## Kinds (see MonsterRig.KINDS): 0 = Faucheur (tall, arms down to the ground, long claws),
## 1 = Bondisseur (skeletal, hunched, leaps), 2 = Rôdeur (walker: slow, shambles straight at
## its prey, arms reaching, grabs and bites).
## Animation states are plain names: idle, walk, run, windup, strike, crouch, leap, land,
## stagger, spawn, dead.

const KINDS := [
	{
		"id": "faucheur", "name": "Faucheur", "scene": "res://assets/monsters/faucheur.glb",
		"scale": 1.18, "hp": 220.0, "speed": 3.0, "radius": 0.5,
		# Bone indices in the file: hips, spine (low -> high), neck, head, arms [shoulder, elbow,
		# wrist], legs [hip, knee, ankle].
		"hips": 1, "spine": [2, 3, 4, 5], "neck": 6, "head": 7,
		"arm_l": [9, 10, 11], "arm_r": [34, 35, 36], "leg_l": [64, 65, 66], "leg_r": [69, 70, 71],
		"stride": 0.62, "arm_swing": 0.28, "leg_swing": 0.5, "bob": 0.03, "lean_walk": 0.12,
		# Hit zones, measured on the mesh (tools/monster_head.gd): head centre in the head bone's
		# frame and its radius, torso radius around the spine (a little generous, both).
		"head_off": Vector3(0.0, 0.07, 0.02), "head_r": 0.14, "body_r": 0.24,
	},
	{
		"id": "bondisseur", "name": "Bondisseur", "scene": "res://assets/monsters/bondisseur.glb",
		"scale": 1.0, "hp": 80.0, "speed": 5.2, "radius": 0.4,
		"hips": 1, "spine": [2, 3, 4, 5], "neck": 6, "head": 7,
		"arm_l": [10, 11, 12], "arm_r": [35, 36, 37], "leg_l": [59, 60, 61], "leg_r": [64, 65, 66],
		"stride": 0.5, "arm_swing": 0.5, "leg_swing": 0.6, "bob": 0.04, "lean_walk": 0.2,
		"head_off": Vector3(0.0, 0.19, 0.07), "head_r": 0.2, "body_r": 0.27,
	},
	{
		# T-pose rig (arms straight out sideways): MonsterPose swings them forward itself.
		"id": "walker", "name": "Rôdeur", "scene": "res://assets/monsters/walker.glb",
		"scale": 1.05, "hp": 130.0, "speed": 1.5, "radius": 0.38,
		"hips": 1, "spine": [2, 3, 4, 5], "neck": 6, "head": 7,
		"arm_l": [10, 11, 12], "arm_r": [15, 16, 17], "leg_l": [19, 20, 21], "leg_r": [24, 25, 26],
		"stride": 0.42, "arm_swing": 0.14, "leg_swing": 0.21, "bob": 0.03, "lean_walk": 0.22,
		"head_off": Vector3(0.0, 0.1, 0.015), "head_r": 0.15, "body_r": 0.23,
	},
]

var kind := 0
var data: Dictionary
var skeleton: Skeleton3D
var pose: MonsterPose
var _model: Node3D
var _mats: Array[StandardMaterial3D] = []

## Animation inputs (set by the owner every frame).
var state := "idle"
var state_t := 0.0
var speed := 0.0
var phase := 0.0
var flash := 0.0 ## damage flash 0..1
var death_t := -1.0


static func kind_data(k: int) -> Dictionary:
	return KINDS[clampi(k, 0, KINDS.size() - 1)]


func setup(p_kind: int) -> void:
	kind = clampi(p_kind, 0, KINDS.size() - 1)
	data = KINDS[kind]
	_model = (load(data.scene) as PackedScene).instantiate() as Node3D
	_model.scale = Vector3.ONE * float(data.scale)
	# The meshes face +Z; a monster's forward is -Z like everything else in the game.
	_model.rotation.y = PI
	add_child(_model)
	skeleton = _model.find_children("*", "Skeleton3D", true, false)[0]
	for mi: MeshInstance3D in _model.find_children("*", "MeshInstance3D", true, false):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		# Frustum culling uses the rest-pose box: the claws swing way outside it.
		mi.extra_cull_margin = 2.0
		for s in mi.mesh.get_surface_count():
			var m := (mi.mesh.surface_get_material(s) as StandardMaterial3D).duplicate() as StandardMaterial3D
			mi.set_surface_override_material(s, m)
			_mats.append(m)
	pose = MonsterPose.new()
	pose.rig = self
	skeleton.add_child(pose)


func set_state(s: String) -> void:
	if s != state:
		state = s
		state_t = 0.0


## Per-frame update. `dist_moved` advances the stride; `vel` is the horizontal speed (m/s).
func tick(delta: float, vel: float, dist_moved: float) -> void:
	state_t += delta
	speed = lerpf(speed, vel, 1.0 - exp(-delta * 10.0))
	phase += dist_moved / maxf(float(data.stride), 0.1) * TAU * 0.5
	flash = move_toward(flash, 0.0, delta * 4.0)
	if state == "dead":
		if death_t < 0.0:
			death_t = 0.0
		death_t += delta
		# The whole body topples backwards.
		rotation.x = lerpf(rotation.x, -1.45, 1.0 - exp(-delta * 4.5)) if death_t > 0.12 else rotation.x
	elif death_t >= 0.0:
		death_t = -1.0
		rotation.x = 0.0
	var e := flash * 0.8
	for m in _mats:
		m.emission_enabled = e > 0.01
		m.emission = Color(1.0, 0.15, 0.1)
		m.emission_energy_multiplier = e * 2.0


func hit_flash() -> void:
	flash = 1.0
