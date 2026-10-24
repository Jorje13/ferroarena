extends Node3D
## Main menu: solo vs bots, host / join (ENet), lobby, settings.
## The selected map renders behind the UI with a slow orbiting camera.

var _map: MapBase
var _cam: Camera3D
var _orbit := 0.0

var _status: Label
var _name: LineEdit
var _mode: OptionButton
var _mapsel: OptionButton
var _rounds: SpinBox
var _modesel: OptionButton
var _diffsel: OptionButton
var _brsel: OptionButton
var _mode_note: Label
var _row_diff: Control
var _row_format: Control
var _row_br: Control
var _row_rounds: Control
var _rows_bots: Array = []
var _team_btn: Button
var _bots: Array[OptionButton] = []
var _ip: LineEdit
var _main_box: VBoxContainer
var _lobby_panel: PanelContainer
var _lobby_list: VBoxContainer
var _start_btn: Button
var _lobby_title: Label
var _help_grid: GridContainer
var _keybinds: KeybindMenu
var _crosshair: CrosshairPanel
var _custom: CustomizePanel
var _preview: CharacterRig
var _customizing := false
var _preview_yaw := 0.0
var _base_yaw := 0.0
var _auto_spin := true
var _left_nodes: Array[Control] = []
var _help_panel: Control


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Audio.play_music("menu", -9.0, 1.5)
	_build_background()
	_build_ui()
	Game.lobby_changed.connect(_refresh_lobby)
	Game.status_message.connect(func(t): _status.text = t)
	if Game.pending_message != "":
		_status.text = Game.pending_message
		Game.pending_message = ""
	_refresh_lobby()
	# Debug: --custom_shots=path.png [--variants=N] captures the armoury with random outfits.
	# Debug: --menu_shot=path.png saves the main menu after a moment (--mode / --difficulty apply).
	if Game.debug.has("menu_shot"):
		get_tree().create_timer(2.5).timeout.connect(func():
			get_viewport().get_texture().get_image().save_png(str(Game.debug.menu_shot))
			get_tree().quit())
	if Game.debug.has("custom_shots"):
		_debug_custom_shots()
	# Debug: --menu_shot=path.png [--show_keys] saves a capture of the menu and quits.
	if Game.debug.has("menu_shot"):
		if Game.debug.has("show_keys"):
			_keybinds.show()
		get_tree().create_timer(6.0).timeout.connect(func():
			get_viewport().get_texture().get_image().save_png(str(Game.debug.menu_shot))
			get_tree().quit())


func _build_background() -> void:
	if _map:
		_map.queue_free()
	var info := Game.map_info(str(Game.config.map))
	_map = load(info.script).new()
	add_child(_map)
	_map.build(mini(Game.quality, 2))
	if _cam == null:
		_cam = Camera3D.new()
		_cam.fov = 55.0
		_cam.far = 1500.0
		add_child(_cam)
		_cam.make_current()


func _process(delta: float) -> void:
	if _customizing:
		_update_showcase(delta)
		return
	_orbit += delta * 0.025
	var p := Vector3(sin(_orbit) * 62.0, 0.0, cos(_orbit) * 62.0)
	p.y = _map.height_at(p.x, p.z) + 13.0
	_cam.global_position = p
	_cam.look_at(Vector3(0, 3.0, 0))


# ---------------------------------------------------------------- armoury showcase

func _open_custom() -> void:
	_customizing = true
	for n in _left_nodes:
		n.hide()
	_help_panel.hide()
	_lobby_panel.hide()
	var sp := _map.get_spawn(0, 0, 1)
	_base_yaw = sp.yaw
	_preview_yaw = sp.yaw
	_auto_spin = true
	_spawn_preview()
	_custom.open(Game.loadout)


func _close_custom() -> void:
	_customizing = false
	for n in _left_nodes:
		n.show()
	_help_panel.show()
	_refresh_lobby()
	if _preview:
		_preview.queue_free()
		_preview = null


func _spawn_preview() -> void:
	if _preview:
		_preview.queue_free()
	_preview = CharacterRig.new()
	add_child(_preview)
	_preview.setup(0, "", Game.loadout)
	var sp: Vector3 = _map.get_spawn(0, 0, 1).pos
	# Stand on the actual terrain (spawn points sit a little above it).
	_preview.global_position = Vector3(sp.x, _map.height_at(sp.x, sp.z), sp.z)


func _update_showcase(delta: float) -> void:
	if _preview == null:
		return
	if _auto_spin:
		_preview_yaw += delta * 0.35
	_preview.rotation.y = _preview_yaw
	_preview.update_preview(delta)
	# Camera in front of the raider, framed so it sits left of the panel.
	var target := _preview.global_position + Vector3(0, 1.0, 0)
	var fwd := Vector3(-sin(_base_yaw), 0.0, -cos(_base_yaw))
	var side := fwd.cross(Vector3.UP).normalized()
	# Camera right = -side (it looks back at the raider); aim right of the raider
	# so it sits in the left third, clear of the panel.
	var want := target + fwd * 2.7 + Vector3.UP * 0.15
	var look := target - side * 0.85 + Vector3.DOWN * 0.05
	if Game.debug.has("prev_close"):
		# Debug: close-up on the hands and rifle (--prev_close=dist,height).
		var cl := str(Game.debug.prev_close).split(",")
		var d := float(cl[0]) if cl.size() > 0 and cl[0] != "" else 1.4
		var h := float(cl[1]) if cl.size() > 1 else 1.25
		var aim_at := _preview.global_position + Vector3(0, h, 0) + Basis(Vector3.UP, _preview_yaw) * Vector3(0, 0, -(float(cl[4]) if cl.size() > 4 else 0.0))
		var ang := deg_to_rad(float(cl[2])) if cl.size() > 2 else 0.0
		var el := deg_to_rad(float(cl[3])) if cl.size() > 3 else 0.0
		want = aim_at + Basis(Vector3.UP, _preview_yaw + ang) * Vector3(0.0, 0.0, -d * cos(el)) + Vector3.UP * d * sin(el)
		look = aim_at
	_cam.global_position = _cam.global_position.lerp(want, 1.0 - exp(-delta * 6.0))
	_cam.look_at(look)


func _unhandled_input(event: InputEvent) -> void:
	if _customizing and event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT):
		_auto_spin = false
		_preview_yaw += event.relative.x * 0.01


func _debug_custom_shots() -> void:
	await get_tree().create_timer(2.0).timeout
	_open_custom()
	_auto_spin = false
	var n := int(Game.debug.get("variants", 4))
	var path := str(Game.debug.custom_shots)
	for i in n:
		var l := ArmorKit.random_loadout(1000 + i * 77) if i > 0 else Game.loadout
		if Game.debug.has("all_pieces"):
			l = {"body": i % 2, "helmet": i % 5, "chest": i % 4, "pack": i % 4, "legs": i % 3,
				"suit": (i * 3) % 10, "fabric": i % 6, "armor": (i * 7) % 10, "pattern": i % 5, "skin": i % 6, "weapon": (i / 6) % 2}
		Game.loadout = ArmorKit.sanitize(l)
		_custom.open(Game.loadout)
		_spawn_preview()
		_preview_yaw = _base_yaw + (0.0 if Game.debug.has("prev_close") else (0.6 if i % 2 == 0 else -0.6))
		if Game.debug.has("prev_close"):
			_custom.hide()
		await get_tree().create_timer(2.5).timeout
		get_viewport().get_texture().get_image().save_png(path.replace(".png", "_%d.png" % i))
		print("[DEBUG] armurerie ", i, " ", Game.loadout)
	get_tree().quit()


# ---------------------------------------------------------------- UI

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = UIStyle.theme()
	layer.add_child(root)

	var shade := ColorRect.new()
	shade.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	shade.offset_right = 620
	shade.color = Color(0.02, 0.025, 0.03, 0.72)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(shade)
	_left_nodes.append(shade)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	scroll.offset_left = 60
	scroll.offset_right = 580
	scroll.offset_top = 50
	scroll.offset_bottom = -30
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	_left_nodes.append(scroll)
	_main_box = VBoxContainer.new()
	_main_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_main_box.add_theme_constant_override("separation", 10)
	scroll.add_child(_main_box)
	var v := _main_box

	v.add_child(UIStyle.label("FERRO ARENA", 64, UIStyle.ACCENT, 700))
	v.add_child(UIStyle.label("DUELS D'ÉQUIPE · UN SEUL FUSIL · BOUCLIER, TÊTE ×2, À TERRE", 15, UIStyle.DIM))
	_status = UIStyle.label("", 15, UIStyle.ACCENT)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD
	v.add_child(_status)

	v.add_child(_section("PROFIL"))
	_name = LineEdit.new()
	_name.text = Game.player_name
	_name.max_length = 16
	_name.placeholder_text = "Nom de raider"
	_name.text_changed.connect(func(t): Game.player_name = t if t.strip_edges() != "" else "Raider")
	v.add_child(_row("Nom", _name))
	v.add_child(_button("PERSONNALISER LE RAIDER (ARMURERIE)", _open_custom))

	v.add_child(_section("PARTIE"))
	_modesel = OptionButton.new()
	for i in Game.MODE_NAMES.size():
		_modesel.add_item(Game.MODE_NAMES[i])
	_modesel.select(Game.mode())
	_modesel.item_selected.connect(func(i):
		Game.set_config("mode", i)
		_apply_mode_rows())
	v.add_child(_row("Mode de jeu", _modesel))
	_mode_note = UIStyle.label("", 13, UIStyle.DIM)
	_mode_note.autowrap_mode = TextServer.AUTOWRAP_WORD
	v.add_child(_mode_note)
	_diffsel = OptionButton.new()
	for n in Game.DIFFICULTY_NAMES:
		_diffsel.add_item(n)
	_diffsel.select(int(Game.config.difficulty))
	_diffsel.item_selected.connect(func(i): Game.set_config("difficulty", i))
	_row_diff = _row("Difficulté des bots", _diffsel)
	v.add_child(_row_diff)
	_mode = OptionButton.new()
	for i in range(1, Game.MAX_TEAM + 1):
		_mode.add_item("%dv%d" % [i, i], i)
	_mode.select(clampi(int(Game.config.team_size) - 1, 0, Game.MAX_TEAM - 1))
	_mode.item_selected.connect(func(i): Game.set_config("team_size", i + 1))
	_row_format = _row("Format (max / équipe)", _mode)
	v.add_child(_row_format)
	_brsel = OptionButton.new()
	for n in range(0, 20):
		_brsel.add_item("%d bot%s" % [n, "s" if n > 1 else ""])
	_brsel.select(int(Game.config.br_bots))
	_brsel.item_selected.connect(func(i): Game.set_config("br_bots", i))
	_row_br = _row("Bots dans la partie", _brsel)
	v.add_child(_row_br)
	_mapsel = OptionButton.new()
	for m in Game.MAPS:
		_mapsel.add_item(m.name)
	for i in Game.MAPS.size():
		if Game.MAPS[i].id == Game.config.map:
			_mapsel.select(i)
	_mapsel.item_selected.connect(func(i):
		Game.set_config("map", Game.MAPS[i].id)
		_build_background())
	v.add_child(_row("Carte", _mapsel))
	_rounds = SpinBox.new()
	_rounds.min_value = 1
	_rounds.max_value = 9
	_rounds.value = int(Game.config.rounds_to_win)
	_rounds.value_changed.connect(func(x): Game.set_config("rounds_to_win", int(x)))
	_row_rounds = _row("Manches pour gagner", _rounds)
	v.add_child(_row_rounds)
	# Bots per team: "Auto" fills the team up to the format, or a fixed number.
	for t in 2:
		var ob := OptionButton.new()
		ob.add_item("Auto (compléter l'équipe)", 0)
		for n in range(0, Game.MAX_TEAM + 1):
			ob.add_item("%d bot%s" % [n, "s" if n > 1 else ""], n + 1)
		ob.select(clampi(int(Game.config["bots_%d" % t]) + 1, 0, Game.MAX_TEAM + 1))
		ob.item_selected.connect(func(i): Game.set_config("bots_%d" % t, i - 1))
		_bots.append(ob)
		var row := _row("Bots · équipe %s" % Game.TEAM_NAMES[t], ob)
		(row.get_child(0) as Label).add_theme_color_override("font_color", Game.TEAM_COLORS[t])
		v.add_child(row)
		_rows_bots.append(row)

	var solo := _button("ENTRAÎNEMENT  —  SOLO CONTRE BOTS", func():
		_save()
		if Game.is_ph():
			_status.text = "Le prop hunt se joue à plusieurs, sans bots : hébergez une partie et invitez au moins un ami."
			return
		Game.start_solo())
	solo.add_theme_font_size_override("font_size", 20)
	v.add_child(solo)
	var host := _button("HÉBERGER UNE PARTIE (port %d)" % Game.DEFAULT_PORT, func():
		_save()
		var err := Game.host_game()
		_status.text = ("Salon ouvert (IP locale : %s). Ouverture du port UDP %d sur la box…" % [", ".join(Game.local_ips()), Game.DEFAULT_PORT]) if err == OK else "Impossible d'héberger (erreur %d) : le port %d est peut-être déjà utilisé." % [err, Game.DEFAULT_PORT]
		_refresh_lobby())
	v.add_child(host)
	var join_row := HBoxContainer.new()
	_ip = LineEdit.new()
	_ip.text = Game.last_ip
	_ip.placeholder_text = "Adresse IP de l'hôte"
	_ip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	join_row.add_child(_ip)
	join_row.add_child(_button("REJOINDRE", func():
		_save()
		var err := Game.join_game(_ip.text.strip_edges())
		_status.text = "Connexion à %s…" % _ip.text if err == OK else "Adresse invalide."))
	v.add_child(join_row)

	v.add_child(_section("OPTIONS"))
	var quality := OptionButton.new()
	for q in Game.QUALITY_NAMES:
		quality.add_item(q)
	quality.select(Game.quality)
	quality.item_selected.connect(func(i):
		Game.quality = i
		Game.save_settings()
		Game.apply_video()
		_build_background())
	v.add_child(_row("Qualité graphique", quality))
	var vs := OptionButton.new()
	for n in Game.VSYNC_NAMES:
		vs.add_item(n)
	vs.select(Game.vsync)
	vs.item_selected.connect(func(i):
		Game.vsync = i
		Game.save_settings()
		Game.apply_video())
	v.add_child(_row("Synchro verticale", vs))
	var cap := OptionButton.new()
	for c in Game.FPS_CAPS:
		cap.add_item("Illimitées" if c == 0 else "%d" % c)
	cap.select(maxi(0, Game.FPS_CAPS.find(Game.max_fps)))
	cap.item_selected.connect(func(i):
		Game.max_fps = Game.FPS_CAPS[i]
		Game.save_settings()
		Game.apply_video())
	v.add_child(_row("Limite d'images/s", cap))
	var sens := HSlider.new()
	sens.min_value = 0.2
	sens.max_value = 3.0
	sens.step = 0.05
	sens.value = Game.mouse_sensitivity
	sens.custom_minimum_size = Vector2(200, 24)
	sens.value_changed.connect(func(x): Game.mouse_sensitivity = x)
	v.add_child(_row("Sensibilité souris", sens))
	var mus := HSlider.new()
	mus.max_value = 1.0
	mus.step = 0.05
	mus.value = Game.music_volume
	mus.custom_minimum_size = Vector2(200, 24)
	mus.value_changed.connect(func(x):
		Game.music_volume = x
		Audio.apply_volumes())
	v.add_child(_row("Musique", mus))
	var sfx := HSlider.new()
	sfx.max_value = 1.0
	sfx.step = 0.05
	sfx.value = Game.sfx_volume
	sfx.custom_minimum_size = Vector2(200, 24)
	sfx.value_changed.connect(func(x):
		Game.sfx_volume = x
		Audio.apply_volumes())
	v.add_child(_row("Effets sonores", sfx))
	var kc := CheckBox.new()
	kc.text = "Kill cam (rejouer le tir fatal)"
	kc.button_pressed = Game.kill_cam
	kc.toggled.connect(func(b):
		Game.kill_cam = b
		Game.save_settings())
	v.add_child(kc)
	var full := CheckBox.new()
	full.text = "Plein écran"
	full.button_pressed = Game.fullscreen
	full.toggled.connect(func(b):
		Game.fullscreen = b
		Game.apply_video())
	v.add_child(full)
	v.add_child(_button("CONFIGURER LES TOUCHES", func(): _keybinds.show()))
	v.add_child(_button("PERSONNALISER LE RÉTICULE", func(): _crosshair.show()))
	v.add_child(_button("QUITTER", func():
		_save()
		get_tree().quit()))

	# Lobby (right)
	_lobby_panel = PanelContainer.new()
	_lobby_panel.add_theme_stylebox_override("panel", UIStyle.panel(0.78, 0.15))
	_lobby_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_lobby_panel.offset_left = -520
	_lobby_panel.offset_right = -60
	_lobby_panel.offset_top = 60
	_lobby_panel.visible = false
	root.add_child(_lobby_panel)
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 10)
	_lobby_panel.add_child(lv)
	_lobby_title = UIStyle.label("SALON", 30, UIStyle.ACCENT, 700)
	lv.add_child(_lobby_title)
	_lobby_list = VBoxContainer.new()
	lv.add_child(_lobby_list)
	_team_btn = _button("CHANGER D'ÉQUIPE", func():
		if multiplayer.is_server():
			Game.request_team_switch()
		else:
			Game.request_team_switch.rpc_id(1))
	lv.add_child(_team_btn)
	_start_btn = _button("LANCER LA PARTIE", func():
		_save()
		if Game.is_ph() and Game.lobby.size() < 2 and not Game.debug.has("ph_dummy"):
			_status.text = "Prop hunt : il faut au moins 2 joueurs dans le salon."
			return
		Game.begin_match())
	lv.add_child(_start_btn)
	lv.add_child(_button("QUITTER LE SALON", func(): Game.leave_session("Salon fermé.")))

	# Controls help (bottom right)
	var help := PanelContainer.new()
	help.add_theme_stylebox_override("panel", UIStyle.panel(0.6))
	help.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	help.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	help.grow_vertical = Control.GROW_DIRECTION_BEGIN
	help.offset_left = -400
	help.offset_right = -60
	help.offset_top = -40
	help.offset_bottom = -40
	root.add_child(help)
	_help_panel = help
	_help_grid = GridContainer.new()
	_help_grid.columns = 2
	_help_grid.add_theme_constant_override("h_separation", 24)
	help.add_child(_help_grid)
	_rebuild_help()
	Game.bindings_changed.connect(_rebuild_help)

	# CC BY attribution for the 3D models (required by their licences).
	var credits := UIStyle.label("Raider : « Sci-Fi Soldier / Futuristic Combat Trooper » par ART_LOLL · Ferro : « IZH-27 » par PeLmEsHkO · Sketchfab, CC BY 4.0 · Animations Mixamo · Personnages Cybernétique / Sentinelle et fusil Longshot : générés avec Meshy AI · Explosions : Boom Pack 1 par dklon (CC BY 3.0)", 11, UIStyle.DIM)
	credits.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	credits.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	credits.offset_top = -20
	credits.offset_bottom = -4
	credits.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(credits)

	_keybinds = KeybindMenu.new()
	_keybinds.hide()
	root.add_child(_keybinds)
	_crosshair = CrosshairPanel.new()
	_crosshair.hide()
	root.add_child(_crosshair)
	if Game.debug.has("show_crosshair"):
		_crosshair.show()

	_custom = CustomizePanel.new()
	_custom.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	_custom.offset_left = -640
	_custom.offset_right = -40
	_custom.offset_top = 60
	_custom.offset_bottom = -60
	_custom.hide()
	_custom.changed.connect(func(l):
		Game.set_loadout(l)
		_spawn_preview())
	_custom.closed.connect(_close_custom)
	root.add_child(_custom)
	_apply_mode_rows()


func _rebuild_help() -> void:
	for c in _help_grid.get_children():
		c.queue_free()
	var k := func(a): return Game.key_label(a)
	var binds := [
		["Se déplacer", "%s %s %s %s" % [k.call("move_forward"), k.call("move_left"), k.call("move_back"), k.call("move_right")]],
		["Sprint", k.call("sprint")], ["Accroupi", k.call("crouch")],
		["Roulade", k.call("roll")], ["Saut", k.call("jump")],
		["Viser / Tirer", "%s / %s" % [k.call("aim"), k.call("fire")]], ["Recharger", k.call("reload")],
		["Changer d'épaule", k.call("shoulder")], ["Bandage (soi / allié visé)", k.call("bandage")],
		["Arme / objets", "%s / %s %s %s %s" % [k.call("weapon"), k.call("slot_1"), k.call("slot_2"), k.call("slot_3"), k.call("slot_4")]],
		["Recharger le bouclier (1/manche)", k.call("shield")],
		["Fouiller / relever un allié", k.call("interact")],
		["Scores", k.call("scoreboard")], ["Menu", "ÉCHAP"],
	]
	for b in binds:
		_help_grid.add_child(UIStyle.label(b[0], 14, UIStyle.DIM))
		_help_grid.add_child(UIStyle.label(b[1], 14, UIStyle.TEXT, 600))


func _section(text: String) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 8)
	v.add_child(spacer)
	v.add_child(UIStyle.label(text, 13, UIStyle.ACCENT, 700))
	var line := ColorRect.new()
	line.color = Color(1, 1, 1, 0.15)
	line.custom_minimum_size = Vector2(0, 1)
	v.add_child(line)
	return v


func _row(text: String, control: Control) -> Control:
	var h := HBoxContainer.new()
	var l := UIStyle.label(text, 16, UIStyle.TEXT)
	l.custom_minimum_size = Vector2(200, 0)
	h.add_child(l)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(control)
	return h


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(func():
		Audio.play_2d("ui", -8.0)
		cb.call())
	return b


func _save() -> void:
	Game.player_name = _name.text.strip_edges() if _name.text.strip_edges() != "" else "Raider"
	Game.save_settings()


## Shows only the settings that matter for the chosen mode.
func _apply_mode_rows() -> void:
	var m := Game.mode()
	_row_format.visible = m == Game.MODE_TDM
	_row_rounds.visible = m == Game.MODE_TDM
	for r in _rows_bots:
		(r as Control).visible = m == Game.MODE_TDM
	_row_br.visible = m == Game.MODE_BR
	_row_diff.visible = m != Game.MODE_PH
	_mode_note.text = ["Deux équipes, manches successives, à terre / relevage.", "Chacun pour soi : tout le monde est lâché aux quatre coins de la carte, une zone se resserre, le dernier en vie gagne.", "Un chasseur (tiré au sort) contre des props. Les props se transforment en objets (E) pendant 30 s, puis le chasseur les traque : un tir tue. Sifflement des props toutes les 20 s. Pas de bots, 2 joueurs minimum."][m]
	if _team_btn:
		_team_btn.visible = m == Game.MODE_TDM


func _refresh_lobby() -> void:
	if _lobby_panel == null:
		return
	_apply_mode_rows()
	var online := Game.is_online() and not Game.lobby.is_empty()
	_lobby_panel.visible = online
	var is_host := multiplayer.is_server()
	for c in [_mode, _mapsel, _modesel, _diffsel, _brsel] + _bots:
		c.disabled = online and not is_host
	_rounds.editable = not online or is_host
	if not online:
		return
	# Reflect host config on clients
	_mode.select(clampi(int(Game.config.team_size) - 1, 0, Game.MAX_TEAM - 1))
	_modesel.select(Game.mode())
	_diffsel.select(int(Game.config.difficulty))
	_brsel.select(int(Game.config.br_bots))
	for i in Game.MAPS.size():
		if Game.MAPS[i].id == Game.config.map and _mapsel.selected != i:
			_mapsel.select(i)
	_rounds.set_value_no_signal(int(Game.config.rounds_to_win))
	for t in 2:
		_bots[t].select(clampi(int(Game.config["bots_%d" % t]) + 1, 0, Game.MAX_TEAM + 1))
	_lobby_title.text = "SALON — %s" % ("HÔTE" if is_host else "INVITÉ")
	_start_btn.visible = is_host
	for c in _lobby_list.get_children():
		c.queue_free()
	if Game.mode() != Game.MODE_TDM:
		_lobby_list.add_child(UIStyle.label(Game.MODE_NAMES[Game.mode()].to_upper(), 16, UIStyle.ACCENT, 700))
		for id in Game.lobby:
			var me2 := " (vous)" if id == multiplayer.get_unique_id() else ""
			_lobby_list.add_child(UIStyle.label("   " + str(Game.lobby[id].name) + me2, 16, UIStyle.TEXT))
		if Game.is_ffa():
			_lobby_list.add_child(UIStyle.label("   + %d bots" % clampi(int(Game.config.br_bots), 0, 20 - Game.lobby.size()), 14, UIStyle.DIM))
		return
	for t in 2:
		_lobby_list.add_child(UIStyle.label("ÉQUIPE %s" % Game.TEAM_NAMES[t], 16, Game.TEAM_COLORS[t], 700))
		var n := 0
		for id in Game.lobby:
			if int(Game.lobby[id].team) == t:
				var me := " (vous)" if id == multiplayer.get_unique_id() else ""
				_lobby_list.add_child(UIStyle.label("   " + str(Game.lobby[id].name) + me, 16, UIStyle.TEXT))
				n += 1
		var bots := Game.bots_for(t, n)
		if bots > 0:
			_lobby_list.add_child(UIStyle.label("   + %d bot%s" % [bots, "s" if bots > 1 else ""], 14, UIStyle.DIM))
		var free := int(Game.config.team_size) - n - bots
		if free > 0:
			_lobby_list.add_child(UIStyle.label("   %d place%s libre%s" % [free, "s" if free > 1 else "", "s" if free > 1 else ""], 14, UIStyle.DIM))
