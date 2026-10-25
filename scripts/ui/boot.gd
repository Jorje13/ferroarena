extends Node
## Launch screen (main scene): black, a rifle-shaped progress bar, and everything heavy done
## here once instead of later in the menu / at the start of a match:
## 1. every model, texture, sound and animation of res://assets loaded on worker threads and
##    kept alive for the whole session (Game.preloaded), so maps and raiders build from memory;
## 2. the raiders' animation library baked and retargeted to every body (CharacterRig);
## 3. the main menu (and its background map) built behind the black screen, which then fades.
## Debug launches (--autosolo / --host / --join) go on from here once loaded (Game.after_boot);
## --no_boot skips the preloading.

const EXTS := ["glb", "gltf", "fbx", "tscn", "scn", "res", "tres", "png", "jpg", "jpeg", "webp", "hdr", "exr", "wav", "ogg", "mp3"]
## Share of the bar per phase: files, animations, menu.
const W_FILES := 0.72
const W_ANIMS := 0.18

var _layer: CanvasLayer
var _bar: RifleBar
var _label: Label
var _paths: PackedStringArray = []
var _phase := ""
var _anim_step := 0
var _shown := 0.0


func _ready() -> void:
	Game.mark("démarrage : écran noir")
	# The menu theme starts softly on the black screen, the menu brings it up (no restart).
	Audio.play_music("menu", -26.0, 5.0)
	_layer = CanvasLayer.new()
	_layer.layer = 120
	add_child(_layer)
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_layer.add_child(bg)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.add_theme_constant_override("separation", 18)
	bg.add_child(box)
	_bar = RifleBar.new()
	_bar.custom_minimum_size = Vector2(520, 70)
	box.add_child(_bar)
	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_override("font", UIStyle.font(500))
	_label.add_theme_font_size_override("font_size", 14)
	_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.45))
	box.add_child(_label)
	if Game.debug.has("no_boot"):
		_phase = "menu"
		return
	_collect("res://assets/")
	for p in _paths:
		ResourceLoader.load_threaded_request(p, "", true)
	_phase = "files"
	Game.mark("démarrage : %d fichiers demandés" % _paths.size())


## Every loadable file under `dir` (ResourceLoader.list_directory also sees exported, remapped files).
func _collect(dir: String) -> void:
	for n in ResourceLoader.list_directory(dir):
		if n.ends_with("/"):
			_collect(dir + n)
		elif n.get_extension().to_lower() in EXTS:
			_paths.append(dir + n)


func _process(delta: float) -> void:
	match _phase:
		"files":
			var done := 0.0
			var finished := 0
			var prog := []
			for p in _paths:
				var st := ResourceLoader.load_threaded_get_status(p, prog)
				if st == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
					done += float(prog[0]) if not prog.is_empty() else 0.0
				else:
					done += 1.0
					finished += 1
			_set_progress(W_FILES * done / maxf(_paths.size(), 1.0), "Chargement des ressources  %d / %d" % [finished, _paths.size()])
			if finished == _paths.size():
				for p in _paths:
					if ResourceLoader.load_threaded_get_status(p) == ResourceLoader.THREAD_LOAD_LOADED:
						Game.preloaded.append(ResourceLoader.load_threaded_get(p))
				Game.mark("démarrage : ressources chargées (%d)" % Game.preloaded.size())
				_phase = "anims"
		"anims":
			# One body per frame, so the bar keeps moving.
			var skins := CharacterModel.SKIN_SCENES.size()
			CharacterRig.warm_up(_anim_step)
			_anim_step += 1
			_set_progress(W_FILES + W_ANIMS * float(_anim_step) / skins, "Préparation des animations  %d / %d" % [_anim_step, skins])
			if _anim_step >= skins:
				Game.mark("démarrage : animations prêtes")
				Game.log_pipelines()
				_phase = "warm"
		"warm":
			# Every model, raider and monster drawn once in a hidden viewport, so their GPU
			# pipelines are compiled now rather than on the first frame of a match.
			if _warm == null:
				_set_progress(0.92, "Préparation des shaders…")
				_start_warm()
			else:
				_warm_frames += 1
				if _warm_frames >= 4:
					_warm.queue_free()
					Game.mark("démarrage : shaders préparés")
					Game.log_pipelines()
					_phase = "menu_wait"
		"menu_wait":
			# Let the bar show "building" before the frame that blocks on it.
			_set_progress(0.94, "Construction du décor…")
			_phase = "menu"
		"menu":
			_phase = "fade"
			if Game.has_boot_target():
				Game.after_boot()
				return
			var menu := (load(Game.MENU_SCENE) as PackedScene).instantiate()
			get_tree().root.add_child(menu)
			get_tree().current_scene = menu
			_set_progress(1.0, "")
			Game.mark("démarrage : menu prêt")
		"fade":
			# Keep the black screen over the menu's first frames, then fade it out.
			_shown += delta
			if _shown > 0.15:
				_layer.get_child(0).modulate.a = maxf(0.0, 1.0 - (_shown - 0.15) / 0.35)
			if _shown > 0.5:
				queue_free()
	_bar.value = lerpf(_bar.value, _bar.target, 1.0 - exp(-delta * 10.0))
	_bar.queue_redraw()
	# Debug: --boot_shot=path.png captures the screen once the bar is past 40 %.
	if Game.debug.has("boot_shot") and _bar.value > 0.4 and not has_meta("shot"):
		set_meta("shot", true)
		get_viewport().get_texture().get_image().save_png(str(Game.debug.boot_shot))


var _warm: SubViewport
var _warm_frames := 0


func _start_warm() -> void:
	_warm = SubViewport.new()
	_warm.size = Vector2i(256, 256)
	_warm.own_world_3d = true
	_warm.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_warm)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 1.0, 6.0)
	_warm.add_child(cam)
	cam.make_current()
	var sun := DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.rotation = Vector3(-0.8, 0.5, 0.0)
	_warm.add_child(sun)
	var omni := OmniLight3D.new()
	omni.shadow_enabled = true
	omni.position = Vector3(0, 2, 2)
	_warm.add_child(omni)
	# Every preloaded model, all piled up in front of the camera (only the draw matters).
	for r in Game.preloaded:
		if r is PackedScene:
			var n := (r as PackedScene).instantiate()
			if n is Node3D:
				_warm.add_child(n)
			else:
				n.free()
	# Raiders (every body, the per-rig materials and the held rifles) and monsters.
	for skin in CharacterModel.SKIN_SCENES.size():
		var rig := CharacterRig.new()
		_warm.add_child(rig)
		rig.setup(0, "", {"skin": skin, "weapon": skin % 3})
	for k in MonsterRig.KINDS.size():
		var m := MonsterRig.new()
		_warm.add_child(m)
		m.setup(k)


func _set_progress(v: float, text: String) -> void:
	_bar.target = maxf(_bar.target, clampf(v, 0.0, 1.0))
	if text != "":
		_label.text = text.to_upper()


## Rifle silhouette that fills from the butt to the muzzle.
class RifleBar extends Control:
	var value := 0.0
	var target := 0.0
	## Over-under shotgun in profile, 520 x 70 (x right, y down): butt, wrist, pistol grip,
	## receiver, fore-end, barrel and front sight.
	const SHAPE := [
		Vector2(0, 18), Vector2(30, 16), Vector2(130, 24), Vector2(170, 20), Vector2(250, 20), Vector2(250, 22),
		Vector2(505, 22), Vector2(507, 16), Vector2(513, 16), Vector2(513, 22), Vector2(520, 22), Vector2(520, 31),
		Vector2(362, 31), Vector2(358, 39), Vector2(250, 41), Vector2(200, 41), Vector2(188, 45), Vector2(178, 63),
		Vector2(157, 63), Vector2(160, 47), Vector2(130, 44), Vector2(0, 60),
	]

	func _draw() -> void:
		var k := size.x / 520.0
		var off := Vector2(0, (size.y - 70.0 * k) * 0.5)
		var poly := PackedVector2Array()
		for p: Vector2 in SHAPE:
			poly.append(off + p * k)
		draw_colored_polygon(poly, Color(1, 1, 1, 0.06))
		var x := size.x * clampf(value, 0.0, 1.0)
		if x > 0.5:
			var clip := PackedVector2Array([Vector2(0, -10), Vector2(x, -10), Vector2(x, size.y + 10), Vector2(0, size.y + 10)])
			for part in Geometry2D.intersect_polygons(poly, clip):
				draw_colored_polygon(part, UIStyle.ACCENT)
		poly.append(poly[0])
		draw_polyline(poly, Color(1, 1, 1, 0.35), 1.5, true)
