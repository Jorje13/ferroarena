class_name Projectile
extends Node3D
## Ferro slug with real travel time and a little drop.
## - The shooter's own machine (or the server, for bots) simulates the
##   "authoritative" copy: when it hits an enemy it reports the hit, which the
##   server validates against the registered shot.
## - Every other peer simulates a visual-only copy (tracer + impact FX).
## Visually the slug starts at the muzzle and blends onto the true line of fire.
##
## Hit registration is "what you aim at is what you hit": the authoritative copy
## traces its whole (dropping) path against the player hitboxes as they are
## when the shot leaves, then lands that hit when the slug gets there. Without
## it a target strafing at 4 m/s slips 30-40 cm out of the crosshair during the
## 0.1 s flight at mid range. Walls are still traced live.

const SPEED := 720.0 ## m/s
## Slug "thickness" against player hitboxes only (walls use the thin ray).
const HIT_RADIUS := 0.06
const GRAVITY := 7.0 ## m/s², gentle drop at long range (aim compensates, see Player._compute_aim)
const MAX_TIME := 1.0
const BLEND_TIME := 0.05
## Closest approach (m) to the watched player that still counts as a near miss.
const NEAR_MISS_RANGE := 2.6

static var _streak_mesh: CylinderMesh
static var _core_mat: StandardMaterial3D
static var _glow_mesh: CylinderMesh
static var _glow_mat: StandardMaterial3D
static var _head_mesh: SphereMesh
static var _head_mat: StandardMaterial3D
static var _sweep_shape: SphereShape3D

var shooter: Player
var shot_id := 0
var authoritative := false
## --log_shots: what the crosshair ray was on when this shot was fired.
var debug_pred := ""

var _pos := Vector3.ZERO
var _prev := Vector3.ZERO
var _vel := Vector3.ZERO
var _t := 0.0
var _visual_offset := Vector3.ZERO
var _exclude: Array[RID] = []
var _streak: MeshInstance3D
var _glow: MeshInstance3D
var _head: MeshInstance3D
var _light: OmniLight3D
var _trail: SmokeTrail
var _step := 0
var _whizzed := false
## Authoritative copy: player hit found at fire time ({} = none).
## {step, collider, local (hit point in collider space), normal (local)}
var _resolved := {}


static func spawn(p_shooter: Player, origin: Vector3, dir: Vector3, p_id: int, p_auth: bool) -> Projectile:
	var scene := p_shooter.get_tree().current_scene
	var pr := Projectile.new()
	pr.shooter = p_shooter
	pr.shot_id = p_id
	pr.authoritative = p_auth
	pr._pos = origin
	pr._prev = origin
	pr._vel = dir.normalized() * SPEED
	pr._exclude = p_shooter.hitboxes.rids() if p_shooter.hitboxes else []
	var rg = p_shooter.get("rig")
	if rg and rg.muzzle:
		pr._visual_offset = rg.muzzle.global_position - origin
	if p_auth:
		pr._resolve_at_fire(p_shooter.get_world_3d().direct_space_state)
	scene.add_child(pr)
	pr.global_position = origin + pr._visual_offset
	return pr


func _ready() -> void:
	if _streak_mesh == null:
		# Small white-hot slug: a thin needle core inside a narrow red additive
		# halo, both far above 1.0 (HDR) so they bloom without being thick.
		_streak_mesh = CylinderMesh.new()
		_streak_mesh.top_radius = 0.011
		_streak_mesh.bottom_radius = 0.002
		_streak_mesh.height = 1.0
		_streak_mesh.radial_segments = 6
		_streak_mesh.rings = 1
		_core_mat = StandardMaterial3D.new()
		_core_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_core_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_core_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_core_mat.albedo_color = Color(9.0, 3.2, 1.8, 1.0)
		_core_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_glow_mesh = CylinderMesh.new()
		_glow_mesh.top_radius = 0.035
		_glow_mesh.bottom_radius = 0.004
		_glow_mesh.height = 1.0
		_glow_mesh.radial_segments = 8
		_glow_mesh.rings = 1
		_glow_mat = _core_mat.duplicate()
		_glow_mat.albedo_color = Color(3.5, 0.18, 0.06, 0.6)
		_head_mesh = SphereMesh.new()
		_head_mesh.radius = 0.022
		_head_mesh.height = 0.044
		_head_mesh.radial_segments = 8
		_head_mesh.rings = 4
		_head_mat = _core_mat.duplicate()
		_head_mat.albedo_color = Color(14.0, 7.0, 4.5, 1.0)
	_streak = _mesh(_streak_mesh, _core_mat)
	_glow = _mesh(_glow_mesh, _glow_mat)
	_head = _mesh(_head_mesh, _head_mat)
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.2, 0.08)
	_light.light_energy = 3.0
	_light.omni_range = 3.0
	_light.shadow_enabled = false
	add_child(_light)
	# The smoke lives in the scene, so it keeps drifting after the slug is gone.
	_trail = SmokeTrail.new()
	get_parent().add_child.call_deferred(_trail)
	_orient()


func _mesh(m: Mesh, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.top_level = true
	add_child(mi)
	return mi


func _physics_process(delta: float) -> void:
	_t += delta
	_prev = _pos
	var next := _pos + _vel * delta
	_vel.y -= GRAVITY * delta
	_step += 1
	_check_near_miss(_prev, next)
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(_pos, next, 1, _exclude)
	var hit := space.intersect_ray(q)
	var body_hit := {}
	var body_d := INF
	if authoritative:
		# Player hit decided at fire time: land it on that hitbox, where it is now.
		if not _resolved.is_empty() and _step >= int(_resolved.step):
			var col: Node3D = _resolved.collider
			if is_instance_valid(col):
				body_hit = {"collider": col, "position": col.global_transform * (_resolved.local as Vector3),
					"normal": (col.global_basis * (_resolved.normal as Vector3)).normalized()}
				body_d = _resolved.along
			_resolved = {}
	else:
		body_hit = _sweep_hitboxes(space, _pos, next)
		if body_hit:
			body_d = _pos.distance_to(body_hit.position)
	# A wall met first (e.g. a barricade dropped meanwhile) still stops the slug.
	if body_hit and (hit.is_empty() or body_d + 0.12 <= _pos.distance_to(hit.position)):
		hit = body_hit
	if hit:
		_impact(hit)
		return
	_pos = next
	if _t >= MAX_TIME:
		if authoritative and Game.debug.has("log_shots") and debug_pred != "":
			print("[SHOT] #%d visé=%s touché=rien %s" % [shot_id, debug_pred, "OK" if debug_pred == "rien" else "ÉCART"])
		queue_free()


## An enemy slug passing within a couple of metres of the player being watched:
## supersonic whip-crack from the slug's path, a jolt of the camera.
func _check_near_miss(from: Vector3, to: Vector3) -> void:
	if _whizzed or not is_instance_valid(shooter) or shooter.arena == null or shooter.arena.camera_rig == null:
		return
	var watched: Player = shooter.arena.camera_rig.target
	if watched == null or not is_instance_valid(watched) or not watched.alive or watched.team == shooter.team:
		return
	var c := watched.chest_position()
	var seg := to - from
	var t := clampf((c - from).dot(seg) / maxf(seg.length_squared(), 0.0001), 0.0, 1.0)
	var closest := from + seg * t
	var d := closest.distance_to(c)
	if d > NEAR_MISS_RANGE:
		return
	_whizzed = true
	if d < 0.4:
		return # that one is a hit, not a miss
	var k := 1.0 - (d - 0.4) / (NEAR_MISS_RANGE - 0.4)
	Audio.play_3d("bullet_whiz", closest, lerpf(-4.0, 5.0, k), 45.0, 0.1)
	shooter.arena.camera_rig.suppress(k)


## Traces the whole flight now (same steps as _physics_process) and remembers
## the first player hitbox on it, unless a wall comes first.
func _resolve_at_fire(space: PhysicsDirectSpaceState3D) -> void:
	var dt := 1.0 / Engine.physics_ticks_per_second
	var p := _pos
	var v := _vel
	var steps := ceili(MAX_TIME / dt)
	for i in range(1, steps + 1):
		var next := p + v * dt
		v.y -= GRAVITY * dt
		var wall := space.intersect_ray(PhysicsRayQueryParameters3D.create(p, next, 1, _exclude))
		var body := _sweep_hitboxes(space, p, next)
		if body and (wall.is_empty() or p.distance_to(body.position) + 0.12 <= p.distance_to(wall.position)):
			var col := body.collider as Node3D
			var inv := col.global_transform.affine_inverse()
			_resolved = {"step": i, "collider": col, "local": inv * (body.position as Vector3),
				"normal": inv.basis * (body.normal as Vector3), "along": p.distance_to(body.position)}
			return
		if wall:
			return
		p = next


func _sweep_hitboxes(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> Dictionary:
	# Against bodies the slug has a little thickness (HIT_RADIUS): a sphere is
	# swept along the step, so grazing the edge of a hitbox still counts.
	if _sweep_shape == null:
		_sweep_shape = SphereShape3D.new()
		_sweep_shape.radius = HIT_RADIUS
	var sq := PhysicsShapeQueryParameters3D.new()
	sq.shape = _sweep_shape
	sq.collision_mask = Hitboxes.LAYER
	sq.exclude = _exclude
	sq.transform = Transform3D(Basis(), from)
	sq.motion = to - from
	var frac := space.cast_motion(sq)
	if frac.size() < 2 or frac[1] >= 1.0:
		return {}
	sq.transform = Transform3D(Basis(), from + sq.motion * frac[1])
	sq.motion = Vector3.ZERO
	var info := space.get_rest_info(sq)
	if info.is_empty():
		return {}
	var col := instance_from_id(info.collider_id)
	if col == null:
		return {}
	return {"collider": col, "position": info.point, "normal": info.normal}


func _process(_delta: float) -> void:
	var f := Engine.get_physics_interpolation_fraction()
	var blend := clampf(1.0 - _t / BLEND_TIME, 0.0, 1.0)
	global_position = _prev.lerp(_pos, f) + _visual_offset * blend
	_orient()
	if is_instance_valid(_trail):
		_trail.push(global_position)


func _exit_tree() -> void:
	if is_instance_valid(_trail):
		_trail.push(global_position)
		_trail.release()


func _orient() -> void:
	# Thin streak behind the slug (a few metres: it moves ~9 m per frame).
	var d := _vel.normalized()
	var length := clampf(SPEED * 0.008, 0.3, minf(4.0, _t * SPEED + 0.3))
	var ref := Vector3.UP if absf(d.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	var x := d.cross(ref).normalized()
	var z := x.cross(d)
	_streak.global_transform = Transform3D(Basis(x, d * length, z), global_position - d * length * 0.5)
	var gl := length * 1.25
	_glow.global_transform = Transform3D(Basis(x, d * gl, z), global_position - d * gl * 0.5)
	_head.global_position = global_position


func _impact(hit: Dictionary) -> void:
	var col: Object = hit.collider
	global_position = hit.position # the smoke ends on the impact
	var victim := Hitboxes.player_of(col) as Player
	if victim == null and col is Node and (col as Node).has_meta("monster"):
		var mon := (col as Node).get_meta("monster") as Monster
		FX.flesh_hit(hit.position, hit.normal)
		if is_instance_valid(mon):
			mon.rig.hit_flash()
			if authoritative and is_instance_valid(shooter) and mon.alive:
				shooter.report_monster_hit(shot_id, mon.id, (col as Node).get_meta("zone") == "head", hit.position)
		queue_free()
		return
	if authoritative and Game.debug.has("log_shots") and debug_pred != "":
		var got := ("%s/%s" % [victim.display_name, Hitboxes.zone_of(col)]) if victim else "monde"
		print("[SHOT] #%d visé=%s touché=%s %s dist=%.1f vol=%.3fs %s" % [shot_id, debug_pred, got, str((hit.position as Vector3).snapped(Vector3.ONE * 0.01)), shooter.eye_position().distance_to(hit.position), _t, "OK" if debug_pred.begins_with(got) else "ÉCART"])
	if victim:
		if victim.shield > 0.0 and victim.alive:
			FX.shield_hit(hit.position, hit.normal)
		else:
			FX.flesh_hit(hit.position, hit.normal)
		if authoritative and is_instance_valid(shooter) and victim.team != shooter.team and victim.is_hittable():
			shooter.report_hit(shot_id, victim, Hitboxes.zone_of(col) == "head", hit.position)
	else:
		FX.impact(hit.position, hit.normal)
		if col is Barricade:
			Audio.play_3d("grenade_bounce", hit.position, 2.0, 50.0, 0.1)
			if authoritative and is_instance_valid(shooter):
				shooter.report_barricade_hit((col as Barricade).id, shot_id)
		else:
			# The sound follows what was hit: soft ground thuds, metal rings, stone cracks.
			var surf := "stone"
			if is_instance_valid(shooter) and shooter.arena and shooter.arena.map:
				surf = shooter.arena.map.surface_of(col, hit.position)
			match surf:
				"snow", "dirt":
					Audio.play_3d("impact_soft", hit.position, 0.0, 40.0, 0.12)
				"metal":
					Audio.play_3d("grenade_bounce", hit.position, 3.0, 55.0, 0.12)
					Audio.play_3d("ricochet", hit.position, -4.0, 45.0, 0.15)
				_:
					Audio.play_3d("impact_world", hit.position, -2.0, 40.0, 0.15)
					if randf() < 0.35:
						Audio.play_3d("ricochet", hit.position, -8.0, 40.0, 0.15)
	queue_free()
