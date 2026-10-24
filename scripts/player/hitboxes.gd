class_name Hitboxes
extends RefCounted
## Bullet hitboxes that follow the animated skeleton: head sphere, two torso
## capsules, upper/lower arms and legs. They live on their own physics layer
## (LAYER), are only used by raycasts (projectiles, aim), never by movement.
## Because they follow the rendered pose, you hit what you see: crouching,
## sliding, rolling, mantling or crawling all have exact hitboxes.
##
## Each body carries metadata: "player" (the Player) and "zone" ("head" / "body" / "limb").

const LAYER := 16 ## physics layer 5 "hitboxes"
## Small padding (m) on every radius: forgiving for network interpolation.
const PAD := 0.025

## [zone, bone_a, bone_b, radius]. bone_b = "" -> sphere on bone_a (head).
const PARTS := [
	["head", "Head", "", 0.15],
	["body", "pelvis", "spine_02", 0.19],
	["body", "spine_02", "neck_01", 0.21],
	["limb", "upperarm_l", "lowerarm_l", 0.075],
	["limb", "lowerarm_l", "hand_l", 0.06],
	["limb", "upperarm_r", "lowerarm_r", 0.075],
	["limb", "lowerarm_r", "hand_r", 0.06],
	["limb", "thigh_l", "calf_l", 0.1],
	["limb", "calf_l", "foot_l", 0.08],
	["limb", "thigh_r", "calf_r", 0.1],
	["limb", "calf_r", "foot_r", 0.08],
]

var player: Node3D
var _bodies: Array[StaticBody3D] = []
var _shapes: Array = []
var _bones := {}
var _skeleton: Skeleton3D
var _enabled := true
var _prop_body: StaticBody3D
var _prop_size := Vector3.ZERO
var _debug_meshes: Array = []


func _init(p: Node3D) -> void:
	player = p
	for part in PARTS:
		var b := StaticBody3D.new()
		b.top_level = true
		b.collision_layer = LAYER
		b.collision_mask = 0
		b.set_meta("player", p)
		b.set_meta("zone", part[0])
		var cs := CollisionShape3D.new()
		if part[2] == "":
			var s := SphereShape3D.new()
			s.radius = part[3] + PAD
			cs.shape = s
		else:
			var c := CapsuleShape3D.new()
			c.radius = part[3] + PAD
			c.height = 0.5
			cs.shape = c
		b.add_child(cs)
		p.add_child(b)
		_bodies.append(b)
		_shapes.append(cs.shape)
		if Game.debug.has("show_hitboxes"):
			# Debug: translucent shapes (head red, body orange, limbs yellow).
			var mi := MeshInstance3D.new()
			var m: PrimitiveMesh
			if cs.shape is SphereShape3D:
				m = SphereMesh.new()
				(m as SphereMesh).radius = (cs.shape as SphereShape3D).radius
				(m as SphereMesh).height = (cs.shape as SphereShape3D).radius * 2.0
			else:
				m = CapsuleMesh.new()
				(m as CapsuleMesh).radius = (cs.shape as CapsuleShape3D).radius
			var mat := StandardMaterial3D.new()
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.no_depth_test = true
			mat.albedo_color = {"head": Color(1, 0.1, 0.1, 0.45), "body": Color(1, 0.5, 0.1, 0.35), "limb": Color(1, 1, 0.2, 0.3)}[part[0]]
			m.material = mat
			mi.mesh = m
			b.add_child(mi)
			_debug_meshes.append(m)
		else:
			_debug_meshes.append(null)


func rids() -> Array[RID]:
	var out: Array[RID] = []
	for b in _bodies:
		out.append(b.get_rid())
	if _prop_body:
		out.append(_prop_body.get_rid())
	return out


func set_enabled(on: bool) -> void:
	if on == _enabled:
		return
	_enabled = on
	_apply_layers()


func _apply_layers() -> void:
	var body_on := _enabled and _prop_size == Vector3.ZERO
	for b in _bodies:
		b.collision_layer = LAYER if body_on else 0
	if _prop_body:
		_prop_body.collision_layer = LAYER if _enabled and _prop_size != Vector3.ZERO else 0


## Prop hunt: while the raider looks like a prop, a single box of that prop's size is the
## only thing a bullet can hit (zero size = back to the body parts).
func set_prop(size: Vector3) -> void:
	_prop_size = size
	if size != Vector3.ZERO:
		if _prop_body == null:
			_prop_body = StaticBody3D.new()
			_prop_body.top_level = true
			_prop_body.collision_mask = 0
			_prop_body.set_meta("player", player)
			_prop_body.set_meta("zone", "body")
			var cs := CollisionShape3D.new()
			cs.shape = BoxShape3D.new()
			_prop_body.add_child(cs)
			player.add_child(_prop_body)
		var cs2 := _prop_body.get_child(0) as CollisionShape3D
		(cs2.shape as BoxShape3D).size = size + Vector3.ONE * 0.1
		cs2.position = Vector3(0, size.y * 0.5, 0)
	_apply_layers()


## Places every hitbox on the skeleton's current (animated + IK) pose.
func sync(sk: Skeleton3D) -> void:
	if _prop_size != Vector3.ZERO and _prop_body:
		_prop_body.global_transform = Transform3D(Basis(Vector3.UP, (player as Player).body_yaw), player.global_position)
		return
	if sk == null or not is_instance_valid(sk):
		return
	if sk != _skeleton:
		_skeleton = sk
		_bones.clear()
		_bones["neck_01"] = sk.find_bone(CharacterRig.bone_name("neck_01"))
		for part in PARTS:
			for n in [part[1], part[2]]:
				if n != "":
					_bones[n] = sk.find_bone(CharacterRig.bone_name(n))
	var gx := sk.global_transform
	for i in PARTS.size():
		var part: Array = PARTS[i]
		var ia: int = _bones.get(part[1], -1)
		if ia < 0:
			continue
		var a := gx * sk.get_bone_global_pose(ia).origin
		var body := _bodies[i]
		if part[2] == "":
			# Head: the bone origin sits at the base of the skull; centre higher up.
			var neck := gx * sk.get_bone_global_pose(_bones.get("neck_01", ia)).origin
			var up := (a - neck).normalized() if a.distance_to(neck) > 0.01 else Vector3.UP
			body.global_transform = Transform3D(Basis(), a + up * 0.13)
			continue
		var ib: int = _bones.get(part[2], -1)
		if ib < 0:
			continue
		var b := gx * sk.get_bone_global_pose(ib).origin
		var axis := b - a
		var length := axis.length()
		if length < 0.01:
			continue
		var cap := _shapes[i] as CapsuleShape3D
		cap.height = maxf(length + cap.radius * 2.0, cap.radius * 2.0 + 0.01)
		if _debug_meshes[i]:
			(_debug_meshes[i] as CapsuleMesh).height = cap.height
		var y := axis / length
		var ref := Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
		var x := y.cross(ref).normalized()
		var z := x.cross(y)
		body.global_transform = Transform3D(Basis(x, y, z), (a + b) * 0.5)


static func player_of(collider: Object) -> Node:
	if collider and collider is Node and (collider as Node).has_meta("player"):
		return (collider as Node).get_meta("player")
	return null


static func zone_of(collider: Object) -> String:
	if collider and collider is Node and (collider as Node).has_meta("zone"):
		return str((collider as Node).get_meta("zone"))
	return ""
