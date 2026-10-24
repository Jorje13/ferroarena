class_name BattleZone
extends Node3D
## Battle royale: the playable circle closes towards the map centre. A translucent wall
## marks the edge; outside it raiders lose health every second, faster as it closes.
## Radius is a function of the round's elapsed time (MatchManager.time_left), so every
## peer draws the same circle; only the server deals the damage.

const HOLD := 40.0 ## seconds before it starts to close
const CLOSE_END := 250.0 ## elapsed time at which it reaches MIN_RADIUS
const MIN_RADIUS := 8.0

var _start_radius := 90.0
var _mesh := CylinderMesh.new()
var _wall: MeshInstance3D
var _tick := 1.0

@onready var arena: Arena = get_parent() as Arena


func _ready() -> void:
	_start_radius = arena.map.half.length() * 1.04
	_mesh.height = 140.0
	_mesh.radial_segments = 96
	_mesh.rings = 1
	_mesh.cap_top = false
	_mesh.cap_bottom = false
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = Color(1.0, 0.25, 0.2, 0.16)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.2, 0.15)
	m.emission_energy_multiplier = 0.6
	m.no_depth_test = false
	_mesh.material = m
	_wall = MeshInstance3D.new()
	_wall.mesh = _mesh
	_wall.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_wall.position = Vector3(0, 30.0, 0)
	add_child(_wall)


## Seconds since the round went live (0 before).
func elapsed() -> float:
	var mm := arena.match_mgr
	if mm.state == MatchManager.State.LIVE:
		return MatchManager.BR_TIME - mm.time_left
	if mm.state == MatchManager.State.ROUND_END or mm.state == MatchManager.State.MATCH_END:
		return MatchManager.BR_TIME
	return 0.0


func progress() -> float:
	return clampf((elapsed() - HOLD) / (CLOSE_END - HOLD), 0.0, 1.0)


func radius() -> float:
	return lerpf(_start_radius, MIN_RADIUS, pow(progress(), 0.85))


## Metres past the edge (negative inside).
func overshoot(pos: Vector3) -> float:
	return Vector2(pos.x, pos.z).length() - radius()


## Seconds until the zone starts closing, or 0.
func hold_left() -> float:
	return maxf(0.0, HOLD - elapsed())


func _process(delta: float) -> void:
	var r := radius()
	_mesh.top_radius = r
	_mesh.bottom_radius = r
	if not multiplayer.is_server() or arena.match_mgr.state != MatchManager.State.LIVE:
		return
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = 1.0
	var dmg := lerpf(3.0, 12.0, progress())
	for p: Player in arena.players:
		if p.alive and overshoot(p.global_position) > 0.0:
			p.server_apply_damage(dmg, p, false, "ZONE")
