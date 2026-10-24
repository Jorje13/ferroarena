class_name CharacterModel
## Loads the Quaternius base characters + UAL animation libraries once, and
## bakes a body-region mask (skin / gloves+boots / suit) into vertex colours
## so one shader can turn the base body into a team jumpsuit.

const CHAR_PATH := "res://assets/quaternius/characters/Superhero_%s_FullBody.gltf"
const ANIM_LIBS := {
	"ual1": "res://assets/quaternius/animations/UAL1_Standard.glb",
	"ual2": "res://assets/quaternius/animations/UAL2_Standard.glb",
}
const SKIN_BONES := ["Head", "neck_01"]
const GLOVE_HINTS := ["hand_", "index_", "middle_", "pinky_", "ring_", "thumb_", "foot_", "ball_"]

static var _scenes := {}
static var _body_meshes := {}
static var _skin_mats := {}
static var _libs := {}


static func gender_key(female: bool) -> String:
	return "Female" if female else "Male"


## Instantiates the character (root has Armature/Skeleton3D) with the masked body mesh.
static func create(female: bool) -> Node3D:
	var g := gender_key(female)
	if not _scenes.has(g):
		_scenes[g] = load(CHAR_PATH % g)
	var root := (_scenes[g] as PackedScene).instantiate() as Node3D
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if String(m.name).to_lower().begins_with("superhero"):
			if not _body_meshes.has(g):
				_bake_body(g, m)
			m.mesh = _body_meshes[g]
	return root


static func skin_textures(female: bool) -> Dictionary:
	return _skin_mats.get(gender_key(female), {})


static func _bake_body(g: String, m: MeshInstance3D) -> void:
	var src := m.mesh
	var arrays: Array = src.surface_get_arrays(0)
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var nv := (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	var per := bones.size() / maxi(nv, 1)
	var skin := m.skin
	var kind := {}
	for i in skin.get_bind_count():
		var bn := String(skin.get_bind_name(i))
		var k := 0
		if bn in SKIN_BONES:
			k = 1
		else:
			for h in GLOVE_HINTS:
				if bn.begins_with(h):
					k = 2
		kind[i] = k
	# COLOR.r = skin, COLOR.g = gloves/boots, COLOR.b = bind-pose z;
	# UV2 = bind-pose (x, y). Lets the shader draw suit details in rest-pose space.
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var cols := PackedColorArray()
	cols.resize(nv)
	var uv2 := PackedVector2Array()
	uv2.resize(nv)
	for v in nv:
		var acc := [0.0, 0.0, 0.0]
		for j in per:
			acc[kind.get(bones[v * per + j], 0)] += weights[v * per + j]
		cols[v] = Color(acc[1], acc[2], clampf(verts[v].z * 2.0 + 0.5, 0.0, 1.0))
		uv2[v] = Vector2(verts[v].x, verts[v].y)
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_TEX_UV2] = uv2
	# Custom channels need format flags we don't carry over; the shader doesn't use them.
	for ch in [Mesh.ARRAY_CUSTOM0, Mesh.ARRAY_CUSTOM1, Mesh.ARRAY_CUSTOM2, Mesh.ARRAY_CUSTOM3]:
		arrays[ch] = null
	var mesh := ArrayMesh.new()
	var flags: int = src.surface_get_format(0) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, flags)
	_body_meshes[g] = mesh
	var mat := src.surface_get_material(0) as StandardMaterial3D
	if mat:
		_skin_mats[g] = {"alb": mat.albedo_texture, "nrm": mat.normal_texture, "rgh": mat.roughness_texture}


static func library(lib_name: String) -> AnimationLibrary:
	if _libs.has(lib_name):
		return _libs[lib_name]
	var inst := (load(ANIM_LIBS[lib_name]) as PackedScene).instantiate()
	var ap := inst.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	var lib := ap.get_animation_library("")
	inst.free()
	_libs[lib_name] = lib
	return lib


# ---------------------------------------------------------------- realistic trooper (Mixamo rig)

const TROOPER_SCENE := "res://assets/mixamo/trooper.fbx"
const TROOPER_TEX := "res://assets/mixamo/textures/%s_%s.png"
## Which loadout colour (armoury) lightly tints each trooper part.
const TROOPER_TINT := {"pants": "suit", "material": "suit", "TECI_helmet": "armor", "torso": "armor", "gear": "fabric", "jumpjet": "fabric"}
const TINT_STRENGTH := 0.4
const MX_DIR := "res://assets/mixamo/anims/%s.fbx"
const MX_CLIPS := ["rifle_idle", "rifle_aiming_idle", "rifle_walk", "rifle_run", "rifle_sprint",
	"run_backwards", "strafe_left_run", "strafe_right_run", "strafe_right", "crouch_idle",
	"crouch_walking", "crawling", "kneeling", "rifle_jump", "running_dive_roll", "running_slide",
	"death", "hit_reaction", "reload", "climbing", "drinking", "vault_over_box", "grenade_throw", "prone_death"]
## Clips stored as standalone animations (downloaded with skin: mesh dropped).
const MX_RES := "res://assets/mixamo/anims/%s.res"
const MX_LOOPING := ["rifle_idle", "rifle_aiming_idle", "rifle_walk", "rifle_run", "rifle_sprint",
	"run_backwards", "strafe_left_run", "strafe_right_run", "strafe_right", "crouch_idle",
	"crouch_walking", "crawling", "kneeling"]

static var _trooper_mats := {}


static func create_trooper() -> Node3D:
	if not _scenes.has("trooper"):
		_scenes["trooper"] = load(TROOPER_SCENE)
	return (_scenes["trooper"] as PackedScene).instantiate() as Node3D


## Other playable bodies (Meshy AI models rigged on the same Mixamo bone names).
## Index = ArmorKit "skin" slot; 0 is the trooper above.
const SKIN_SCENES := ["", "res://assets/characters/cybernetic.glb", "res://assets/characters/sentinel.glb",
	"res://assets/characters/char1.glb", "res://assets/characters/char2.glb", "res://assets/characters/char3.glb"]
## Auto-rigged bodies (anonymous "Bone_NNN" bones, a spare joint above the chest that carries
## the backpack): skin -> Mixamo bone name -> bone index in the file. Bones left out
## (the spare chest joint, palms, fingers) keep their rest pose on their parent, so the
## backpack simply rides with the upper spine instead of being animated on its own.
const AUTO_RIGS := {
	3: {"Hips": 1, "Spine": 2, "Spine1": 3, "Spine2": 4, "Neck": 6, "Head": 7, "HeadTop_End": 8,
		"LeftShoulder": 9, "LeftArm": 10, "LeftForeArm": 11, "LeftHand": 12,
		"RightShoulder": 22, "RightArm": 23, "RightForeArm": 24, "RightHand": 25,
		"LeftUpLeg": 35, "LeftLeg": 36, "LeftFoot": 37, "LeftToeBase": 38, "LeftToe_End": 39,
		"RightUpLeg": 40, "RightLeg": 41, "RightFoot": 42, "RightToeBase": 43, "RightToe_End": 44},
	4: {"Hips": 1, "Spine": 2, "Spine1": 3, "Spine2": 4, "Neck": 6, "Head": 7, "HeadTop_End": 8,
		"LeftShoulder": 9, "LeftArm": 10, "LeftForeArm": 11, "LeftHand": 12,
		"RightShoulder": 17, "RightArm": 18, "RightForeArm": 19, "RightHand": 20,
		"LeftUpLeg": 25, "LeftLeg": 26, "LeftFoot": 27, "LeftToeBase": 28, "LeftToe_End": 29,
		"RightUpLeg": 30, "RightLeg": 31, "RightFoot": 32, "RightToeBase": 33, "RightToe_End": 34},
	5: {"Hips": 1, "Spine": 2, "Spine1": 3, "Spine2": 4, "Neck": 6, "Head": 7, "HeadTop_End": 8,
		"RightShoulder": 9, "RightArm": 10, "RightForeArm": 11, "RightHand": 12,
		"LeftShoulder": 34, "LeftArm": 35, "LeftForeArm": 36, "LeftHand": 37,
		"RightUpLeg": 59, "RightLeg": 60, "RightFoot": 61, "RightToeBase": 62, "RightToe_End": 63,
		"LeftUpLeg": 64, "LeftLeg": 65, "LeftFoot": 66, "LeftToeBase": 67, "LeftToe_End": 68},
}


static func is_auto_rig(skin: int) -> bool:
	return AUTO_RIGS.has(skin)


## Gives the mapped bones their Mixamo names (and the mesh skin's binds too, which look them up by name).
static func _rename_bones(sk: Skeleton3D, map: Dictionary) -> void:
	var old := {}
	for nm in map:
		var idx: int = map[nm]
		old[sk.get_bone_name(idx)] = "mixamorig_" + nm
	for mi in sk.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.skin:
			m.skin = m.skin.duplicate()
			for i in m.skin.get_bind_count():
				var bn := String(m.skin.get_bind_name(i))
				if old.has(bn):
					m.skin.set_bind_name(i, old[bn])
	for nm in map:
		sk.set_bone_name(int(map[nm]), "mixamorig_" + nm)


## A body whose root has the skeleton as direct child named "Skeleton3D" (the clips'
## track paths), whichever skin.
static func create_body(skin: int) -> Node3D:
	if skin <= 0 or skin >= SKIN_SCENES.size():
		return create_trooper()
	var key := "skin%d" % skin
	if not _scenes.has(key):
		_scenes[key] = load(SKIN_SCENES[skin])
	var inst := (_scenes[key] as PackedScene).instantiate() as Node3D
	var sk := inst.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	if AUTO_RIGS.has(skin):
		_rename_bones(sk, AUTO_RIGS[skin])
	sk.get_parent().remove_child(sk)
	sk.name = "Skeleton3D"
	sk.owner = null
	var body := Node3D.new()
	body.add_child(sk)
	inst.free()
	return body


## Full PBR material for one trooper part (original Sketchfab texture set),
## lightly tinted with the loadout colour that drives this part.
static func trooper_material(part: String, loadout: Dictionary) -> StandardMaterial3D:
	var slot: String = TROOPER_TINT.get(part, "")
	var tint := Color.WHITE
	match slot:
		"suit": tint = ArmorKit.suit_color(loadout)
		"armor": tint = ArmorKit.armor_color(loadout)
		"fabric": tint = ArmorKit.fabric_color(loadout)
	var key := "%s|%s" % [part, tint.to_html()]
	if _trooper_mats.has(key):
		return _trooper_mats[key]
	var m := StandardMaterial3D.new()
	m.resource_name = part
	if ResourceLoader.exists(TROOPER_TEX % [part, "baseColor"]):
		m.albedo_texture = load(TROOPER_TEX % [part, "baseColor"])
		m.normal_enabled = true
		m.normal_texture = load(TROOPER_TEX % [part, "normal"])
		var mr: Texture2D = load(TROOPER_TEX % [part, "metallicRoughness"])
		m.metallic = 1.0
		m.metallic_texture = mr
		m.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_BLUE
		m.roughness = 1.0
		m.roughness_texture = mr
		m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
		# The set's "emissive" map is really a baked ambient-occlusion map.
		m.ao_enabled = true
		m.ao_texture = load(TROOPER_TEX % [part, "emissive"])
		m.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
		m.ao_light_affect = 0.4
	# Tint by colour (keep the texture's value): normalise the tint's brightness.
	var lum := maxf(tint.get_luminance(), 0.05)
	m.albedo_color = Color.WHITE.lerp(Color(tint.r / lum, tint.g / lum, tint.b / lum).clamp(Color(0, 0, 0), Color(1.6, 1.6, 1.6)), TINT_STRENGTH)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_trooper_mats[key] = m
	return m


## All Mixamo clips in one library ("mx/<clip>"). Track paths are relative to
## the scene root ("Skeleton3D:mixamorig_*"), same as the trooper scene.
static func mixamo_library() -> AnimationLibrary:
	if _libs.has("mx"):
		return _libs["mx"]
	var lib := AnimationLibrary.new()
	for clip in MX_CLIPS:
		var a: Animation
		if ResourceLoader.exists(MX_RES % clip):
			a = (load(MX_RES % clip) as Animation).duplicate(true)
		else:
			var inst := (load(MX_DIR % clip) as PackedScene).instantiate()
			var ap := inst.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
			a = ap.get_animation(ap.get_animation_list()[0]).duplicate(true) as Animation
			inst.free()
		a.loop_mode = Animation.LOOP_LINEAR if clip in MX_LOOPING else Animation.LOOP_NONE
		if clip == "vault_over_box":
			# The Player carries the body along the real obstacle (see vault_root_distance):
			# remember the clip's own forward travel, then play it in place.
			VaultMath.z = _hips_z(a)
			_pin_hips(a)
		else:
			_strip_root_motion(a)
		lib.add_animation(clip, a)
	_libs["mx"] = lib
	return lib


# ---------------------------------------------------------------- vault clip (see VaultMath)

## Hips forward travel (m) sampled every 1/60 s over the raw clip.
static func _hips_z(a: Animation) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var tr := a.find_track(NodePath("Skeleton3D:mixamorig_Hips"), Animation.TYPE_POSITION_3D)
	if tr < 0:
		return out
	for i in int(ceil(a.length * 60.0)) + 1:
		out.append((a.position_track_interpolate(tr, minf(i / 60.0, a.length)) as Vector3).z)
	return out


## Removes the horizontal travel baked into the Hips track (clips exported
## without "In Place" walk forward up to ~3 m per cycle, then snap back at the
## loop): subtracts the straight line from the first to the last key on X/Z,
## keeping only the natural sway. The Player moves the body, not the clip.
static func _strip_root_motion(a: Animation) -> void:
	var tr := a.find_track(NodePath("Skeleton3D:mixamorig_Hips"), Animation.TYPE_POSITION_3D)
	if tr < 0:
		return
	var n := a.track_get_key_count(tr)
	if n < 2:
		return
	var first: Vector3 = a.track_get_key_value(tr, 0)
	var last: Vector3 = a.track_get_key_value(tr, n - 1)
	var t0 := a.track_get_key_time(tr, 0)
	var t1 := maxf(a.track_get_key_time(tr, n - 1), t0 + 0.0001)
	for i in n:
		var k := (a.track_get_key_time(tr, i) - t0) / (t1 - t0)
		var v: Vector3 = a.track_get_key_value(tr, i)
		v.x -= (last.x - first.x) * k + first.x
		v.z -= (last.z - first.z) * k + first.z
		a.track_set_key_value(tr, i, v)


## Keeps the hips' height and sway but removes ALL horizontal travel.
static func _pin_hips(a: Animation) -> void:
	var tr := a.find_track(NodePath("Skeleton3D:mixamorig_Hips"), Animation.TYPE_POSITION_3D)
	if tr < 0:
		return
	var first: Vector3 = a.track_get_key_value(tr, 0)
	for i in a.track_get_key_count(tr):
		var v: Vector3 = a.track_get_key_value(tr, i)
		v.x = first.x
		v.z = first.z
		a.track_set_key_value(tr, i, v)


static func suit_material(team: int, female: bool, color: Color) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/raider_suit.gdshader")
	var t := skin_textures(female)
	m.set_shader_parameter("skin_alb", t.get("alb"))
	m.set_shader_parameter("skin_nrm", t.get("nrm"))
	m.set_shader_parameter("skin_rgh", t.get("rgh"))
	# Real woven fabric (Poly Haven rough_linen) for the jumpsuit weave.
	m.set_shader_parameter("cloth_nrm", load(Mats.PH_TEX + "rough_linen/rough_linen_nor_gl_2k.jpg"))
	m.set_shader_parameter("cloth_var", load(Mats.PH_TEX + "rough_linen/rough_linen_diff_2k.jpg"))
	m.set_shader_parameter("suit_col", color)
	m.set_shader_parameter("suit_col2", [Color(0.36, 0.33, 0.22), Color(0.2, 0.22, 0.25)][team])
	return m
