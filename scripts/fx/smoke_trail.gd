class_name SmokeTrail
extends MeshInstance3D
## Thin wisp of smoke left along a slug's path: a camera-facing ribbon that
## widens, drifts up and fades out. Fed by the Projectile (push), it outlives
## it (release) and frees itself once fully faded.

const LIFE := 1.1 ## s
const SEG := 0.6 ## m between ribbon points
const MAX_POINTS := 360
const WIDTH := 0.025 ## m at birth
const GROW := 0.24 ## m/s of width gained while drifting
const ALPHA := 0.42

static var _mat: ShaderMaterial

var _pts: Array[Vector3] = []
var _birth: PackedFloat64Array = []
var _drift: Array[Vector3] = []
var _released := false
var _im := ImmediateMesh.new()


func _ready() -> void:
	if _mat == null:
		var sh := Shader.new()
		sh.code = """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void fragment() {
	float edge = 1.0 - abs(UV.x * 2.0 - 1.0);
	float n = vnoise(vec2(UV.y * 1.7, UV.x * 3.0 + TIME * 0.6)) * 0.6 + vnoise(vec2(UV.y * 5.0, UV.x * 6.0 - TIME)) * 0.4;
	ALBEDO = COLOR.rgb;
	ALPHA = COLOR.a * smoothstep(0.0, 0.8, edge) * mix(0.35, 1.0, n);
}
"""
		_mat = ShaderMaterial.new()
		_mat.shader = sh
	mesh = _im
	material_override = _mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	top_level = true
	global_transform = Transform3D.IDENTITY


func _now() -> float:
	return Time.get_ticks_usec() * 0.000001


## Extends the trail to `pos` (subdivided every SEG metres).
func push(pos: Vector3) -> void:
	var now := _now()
	if _pts.is_empty():
		_add(pos, now)
		return
	var last := _pts[-1]
	var d := last.distance_to(pos)
	var n := mini(ceili(d / SEG), MAX_POINTS)
	for i in range(1, n + 1):
		_add(last.lerp(pos, float(i) / n), now)
	while _pts.size() > MAX_POINTS:
		_drop_front()


func release() -> void:
	_released = true


func _add(p: Vector3, now: float) -> void:
	_pts.append(p)
	_birth.append(now)
	_drift.append(Vector3(randf_range(-0.12, 0.12), randf_range(0.12, 0.3), randf_range(-0.12, 0.12)))


func _drop_front() -> void:
	_pts.remove_at(0)
	_birth.remove_at(0)
	_drift.remove_at(0)


func _process(_delta: float) -> void:
	var now := _now()
	while not _pts.is_empty() and now - _birth[0] > LIFE:
		_drop_front()
	if _pts.is_empty() and _released:
		queue_free()
		return
	_im.clear_surfaces()
	var cam := get_viewport().get_camera_3d()
	if _pts.size() < 2 or cam == null:
		return
	var eye := cam.global_position
	_im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	var dist := 0.0
	var count := _pts.size()
	for i in count:
		var age := now - _birth[i]
		var p := _pts[i] + _drift[i] * age
		var nxt := _pts[mini(i + 1, count - 1)]
		var prv := _pts[maxi(i - 1, 0)]
		var tangent := (nxt - prv).normalized()
		var side := tangent.cross(eye - p).normalized()
		if side == Vector3.ZERO:
			side = Vector3.UP
		var w := WIDTH + GROW * age
		var life_k := 1.0 - age / LIFE
		# Born a few ms behind the glowing slug, thinning out at the trail's tip.
		var a := ALPHA * life_k * life_k * clampf(age / 0.04, 0.0, 1.0)
		if i == count - 1 and not _released:
			a = 0.0
		if i > 0:
			dist += _pts[i].distance_to(_pts[i - 1])
		var col := Color(0.78, 0.77, 0.75, a)
		_im.surface_set_color(col)
		_im.surface_set_uv(Vector2(0.0, dist))
		_im.surface_add_vertex(p - side * w)
		_im.surface_set_color(col)
		_im.surface_set_uv(Vector2(1.0, dist))
		_im.surface_add_vertex(p + side * w)
	_im.surface_end()
