class_name LootChest
extends Node3D
## Supply crate at a predefined map spot. The server activates a random subset
## each round; opening one gives 1-2 random items.

var index := 0
var active := false
var opened := false
## "" for a regular crate, else the attachment inside ("silencer" / "stock"):
## those glow cyan so they can be spotted and fought over.
var special := ""

var _lid: Node3D
var _light: OmniLight3D
var _beacon: MeshInstance3D
var _body: StaticBody3D
var _open_t := 0.0
var _t := 0.0


func _ready() -> void:
	var crate := Mats.pbr_local("metal_plate", Color(0.38, 0.42, 0.3), 2.0, "crate")
	var trim := Mats.gun_metal_dark()
	var stripe := Mats.flat("crate_stripe", Color(0.95, 0.7, 0.15), 0.6)
	var rb := Shapes.rounded_box
	var size := Vector3(1.05, 0.48, 0.62)
	_mesh(self, rb.call(size, 0.03), crate, Vector3(0, size.y * 0.5 + 0.02, 0))
	for x in [-0.4, 0.4]:
		_mesh(self, rb.call(Vector3(0.07, size.y + 0.02, size.z + 0.03), 0.015), trim, Vector3(x, size.y * 0.5 + 0.02, 0))
	_mesh(self, rb.call(Vector3(0.5, 0.06, 0.005), 0.003), stripe, Vector3(0, size.y * 0.55, -size.z * 0.5 - 0.004))
	for x in [-0.6, 0.6]:
		_mesh(self, rb.call(Vector3(0.06, 0.08, 0.2), 0.02), trim, Vector3(x * 0.92, size.y * 0.7, 0))
	# Lid hinged on the back edge (+Z).
	_lid = Node3D.new()
	_lid.position = Vector3(0, size.y + 0.02, size.z * 0.5)
	add_child(_lid)
	_mesh(_lid, rb.call(Vector3(size.x + 0.02, 0.1, size.z + 0.02), 0.03), crate, Vector3(0, 0.05, -size.z * 0.5))
	_mesh(_lid, rb.call(Vector3(0.12, 0.06, 0.05), 0.015), trim, Vector3(0, 0.03, -size.z - 0.01))
	_beacon = MeshInstance3D.new()
	var bm := SphereMesh.new()
	bm.radius = 0.035
	bm.height = 0.07
	_beacon.mesh = bm
	_beacon.material_override = Mats.emissive("crate_beacon", Color(1.0, 0.65, 0.15), 6.0)
	_beacon.position = Vector3(0.3, 0.13, -size.z * 0.5)
	_lid.add_child(_beacon)
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.65, 0.2)
	_light.light_energy = 1.4
	_light.omni_range = 3.0
	_light.position = Vector3(0, 0.9, 0)
	_light.shadow_enabled = false
	_light.light_volumetric_fog_energy = 0.0
	_light.distance_fade_enabled = true
	_light.distance_fade_begin = 35.0
	_light.distance_fade_length = 10.0
	add_child(_light)
	_body = StaticBody3D.new()
	_body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(size.x, size.y + 0.12, size.z)
	cs.shape = sh
	cs.position = Vector3(0, (size.y + 0.12) * 0.5, 0)
	_body.add_child(cs)
	add_child(_body)
	set_active(false)


func _mesh(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)


func set_active(on: bool, p_special := "") -> void:
	active = on
	special = p_special if on else ""
	opened = false
	_open_t = 0.0
	_lid.rotation.x = 0.0
	visible = on
	_body.collision_layer = 1 if on else 0
	_light.visible = on
	_beacon.visible = on
	var glow := Color(0.35, 0.85, 1.0) if special != "" else Color(1.0, 0.65, 0.2)
	_light.light_color = glow
	_light.omni_range = 4.5 if special != "" else 3.0
	_beacon.material_override = Mats.emissive("crate_beacon_special" if special != "" else "crate_beacon", glow, 6.0)


func set_opened() -> void:
	if opened:
		return
	opened = true
	Audio.play_3d("chest_open", global_position, 0.0, 30.0)
	FX.smoke_puff(global_position + Vector3(0, 0.6, 0), Vector3.UP, 6, 0.6, Color(0.8, 0.75, 0.6, 0.4))


func can_loot() -> bool:
	return active and not opened


func _process(delta: float) -> void:
	if not active:
		return
	_t += delta
	if opened:
		_open_t = minf(1.0, _open_t + delta * 3.0)
		_lid.rotation.x = ease(_open_t, 0.4) * 1.9
		_light.light_energy = move_toward(_light.light_energy, 0.0, delta * 2.0)
		_beacon.visible = false
	else:
		_light.light_energy = (1.1 + sin(_t * 3.0) * 0.4) * (1.8 if special != "" else 1.0)
