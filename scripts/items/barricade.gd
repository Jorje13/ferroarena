class_name Barricade
extends StaticBody3D
## Deployable steel shield. Blocks movement and bullets; server-owned HP.
## Three Ferro hits or one close frag bring it down.

const SIZE := Vector3(2.1, 1.25, 0.12)

var id := 0
var team := 0
var hp := Items.BARRICADE_HP
var _deploy := 0.0
var _visual: Node3D


static func create(p_id: int, xf: Transform3D, p_team: int) -> Barricade:
	var b := Barricade.new()
	b.id = p_id
	b.team = p_team
	b.name = "Barricade%d" % p_id
	b.transform = xf
	return b


func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(SIZE.x, SIZE.y, 0.3)
	cs.shape = sh
	cs.position = Vector3(0, SIZE.y * 0.5, 0)
	add_child(cs)
	_visual = build_visual(Game.TEAM_COLORS[team])
	add_child(_visual)
	_visual.scale = Vector3(1, 0.05, 1)
	Audio.play_3d("barricade_place", global_position, 0.0, 40.0, 0.05)


## Shared by the placement preview ("ghost") and the real barricade.
static func build_visual(accent: Color) -> Node3D:
	var root := Node3D.new()
	var steel := Mats.pbr_local("painted_metal_shutter", Color(0.55, 0.56, 0.5), 1.2)
	var frame := Mats.gun_metal_dark()
	var hazard := Mats.flat("hazard_%s" % accent.to_html(), accent, 0.6)
	var rb := Shapes.rounded_box
	_m(root, rb.call(Vector3(SIZE.x, SIZE.y, SIZE.z), 0.025), steel, Vector3(0, SIZE.y * 0.5, 0))
	_m(root, rb.call(Vector3(SIZE.x + 0.04, 0.07, SIZE.z + 0.04), 0.02), frame, Vector3(0, SIZE.y, 0))
	_m(root, rb.call(Vector3(SIZE.x + 0.04, 0.07, SIZE.z + 0.04), 0.02), frame, Vector3(0, 0.035, 0))
	for x in [-SIZE.x * 0.5, 0.0, SIZE.x * 0.5]:
		_m(root, rb.call(Vector3(0.07, SIZE.y, SIZE.z + 0.05), 0.02), frame, Vector3(x, SIZE.y * 0.5, 0))
	# Folding legs behind the shield
	for x in [-0.7, 0.7]:
		var leg := Node3D.new()
		leg.position = Vector3(x, SIZE.y * 0.75, 0.05)
		leg.rotation.x = 0.55
		root.add_child(leg)
		_m(leg, rb.call(Vector3(0.05, 1.1, 0.05), 0.015), frame, Vector3(0, -0.55, 0))
	# Hazard chevrons along the top + vision slit
	for i in 7:
		var chev := Node3D.new()
		chev.position = Vector3(-0.9 + i * 0.3, SIZE.y - 0.12, -SIZE.z * 0.5 - 0.004)
		chev.rotation.z = 0.6
		root.add_child(chev)
		_m(chev, rb.call(Vector3(0.07, 0.2, 0.01), 0.004), hazard, Vector3.ZERO)
	_m(root, rb.call(Vector3(0.5, 0.05, 0.02), 0.01), Mats.flat("slit", Color(0.02, 0.02, 0.02), 0.9), Vector3(0, SIZE.y * 0.7, -SIZE.z * 0.5 - 0.004))
	return root


static func _m(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)


func _process(delta: float) -> void:
	if _deploy < 1.0:
		_deploy = minf(1.0, _deploy + delta * 3.5)
		_visual.scale = Vector3(1, ease(_deploy, 0.4), 1)


func server_damage(amount: float) -> void:
	hp -= amount
	if hp <= 0.0:
		var arena := get_tree().current_scene as Arena
		if arena:
			arena.net_barricade_destroyed.rpc(id)


func destroy_fx() -> void:
	FX.smoke_puff(global_position + Vector3(0, 0.6, 0), Vector3.UP, 14, 1.6, Color(0.5, 0.48, 0.45, 0.7))
	Audio.play_3d("barricade_break", global_position, 2.0, 50.0)
	Audio.play_3d("grenade_bounce", global_position, 0.0, 40.0)
