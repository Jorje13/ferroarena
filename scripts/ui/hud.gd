class_name Hud
extends CanvasLayer
## In-match HUD: compass, score/timer, squad health, weapon + bandages,
## crosshair & hit feedback, kill feed, announcements, scoreboard, pause menu.

var arena: Arena
var local: Player

var _root: Control
var _compass: Compass
var _crosshair: Crosshair
var _score_l: Label
var _team_l: Label
var _team_r: Label
var _mode_info: Label
var _blind: ColorRect
var _blind_label: Label
var _score_r: Label
var _timer: Label
var _round_label: Label
var _squad: VBoxContainer
var _squad_rows := {}
var _stamina: Bar
var _ammo: Label
var _weapon_state: Label
var _attach_label: Label
var _bandage_count: Label
var _bandage_key: Label
var _shield_count: Label
var _shield_key: Label
var _ping: Label
var _crosshair_panel: CrosshairPanel
var _prompt: Label
var _progress: Bar
var _announce: Label
var _announce_sub: Label
var _announce_t := 0.0
var _killfeed: VBoxContainer
var _spectate: Label
var _vignette: ColorRect
var _hurt_flash := 0.0
var _hurt_blue := false
var _flash: ColorRect
var _kill_banner: Label
var _kill_tw: Tween
var _kc_panel: Control
var _kc_title: Label
var _kc_sub: Label
var _kc_hint: Label
var _heart_t := 0.0
var _base_saturation := -1.0
var _sat := 1.0
var _scoreboard: PanelContainer
var _sb_grid: VBoxContainer
var _pause: PanelContainer
var _end_panel: PanelContainer
var _end_title: Label
var _end_score: Label
var _end_buttons: HBoxContainer
var _last_countdown := -1
var _hints: VBoxContainer
var _keybinds: KeybindMenu
var _armory: CustomizePanel
## Zombie survival: the workbench window and the scrap counter.
var _shop: ShopPanel
var _scrap_label: Label


func setup(p_arena: Arena) -> void:
	arena = p_arena
	layer = 10
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = UIStyle.theme()
	add_child(_root)

	_vignette = ColorRect.new()
	_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vm := ShaderMaterial.new()
	vm.shader = load("res://shaders/vignette.gdshader")
	_vignette.material = vm
	_root.add_child(_vignette)

	# --- top: compass + score
	_compass = Compass.new()
	_compass.hud = self
	_compass.custom_minimum_size = Vector2(640, 44)
	_compass.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_offsets(_compass, Vector2(-320, 12), Vector2(640, 44))
	_root.add_child(_compass)

	var score_row := HBoxContainer.new()
	score_row.set_anchors_preset(Control.PRESET_CENTER_TOP)
	score_row.alignment = BoxContainer.ALIGNMENT_CENTER
	score_row.add_theme_constant_override("separation", 18)
	_offsets(score_row, Vector2(-200, 60), Vector2(400, 40))
	_root.add_child(score_row)
	_score_l = UIStyle.label("0", 30, Game.TEAM_COLORS[0], 700)
	_score_r = UIStyle.label("0", 30, Game.TEAM_COLORS[1], 700)
	var mid := VBoxContainer.new()
	mid.add_theme_constant_override("separation", -4)
	_timer = UIStyle.label("0:00", 22, UIStyle.TEXT, 600)
	_timer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_round_label = UIStyle.label("MANCHE 1", 13, UIStyle.DIM)
	_round_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mid.add_child(_timer)
	mid.add_child(_round_label)
	_team_l = UIStyle.label(Game.TEAM_NAMES[0], 14, Game.TEAM_COLORS[0])
	_team_r = UIStyle.label(Game.TEAM_NAMES[1], 14, Game.TEAM_COLORS[1])
	for c in [_team_l, _score_l, mid, _score_r, _team_r]:
		c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		score_row.add_child(c)

	# --- kill feed (top right)
	_killfeed = VBoxContainer.new()
	_killfeed.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_offsets(_killfeed, Vector2(-440, 20), Vector2(420, 200))
	_killfeed.alignment = BoxContainer.ALIGNMENT_BEGIN
	_killfeed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_killfeed)
	_ping = UIStyle.label("", 13, UIStyle.DIM)
	_ping.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_ping.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_offsets(_ping, Vector2(-200, 2), Vector2(180, 18))
	_root.add_child(_ping)

	# --- squad (bottom left)
	_squad = VBoxContainer.new()
	_squad.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_squad.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_offsets(_squad, Vector2(32, -40), Vector2(280, 0))
	_squad.add_theme_constant_override("separation", 6)
	_root.add_child(_squad)
	_stamina = Bar.new()
	_stamina.color = Color(0.95, 0.95, 0.92)
	_stamina.custom_minimum_size = Vector2(260, 5)

	# --- weapon panel (bottom right)
	var wp := HBoxContainer.new()
	wp.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	wp.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	wp.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_offsets(wp, Vector2(-504, -128), Vector2(474, 96))
	wp.add_theme_constant_override("separation", 6)
	wp.alignment = BoxContainer.ALIGNMENT_END
	_root.add_child(wp)
	var bslot := PanelContainer.new()
	bslot.add_theme_stylebox_override("panel", UIStyle.panel(0.5))
	bslot.custom_minimum_size = Vector2(78, 92)
	var bv := VBoxContainer.new()
	bv.alignment = BoxContainer.ALIGNMENT_CENTER
	_bandage_key = UIStyle.label(Game.key_label("bandage"), 13, UIStyle.DIM)
	_bandage_key.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var cross := UIStyle.label("✚", 26, UIStyle.TEXT)
	cross.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bandage_count = UIStyle.label("2", 16, UIStyle.TEXT, 700)
	_bandage_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bv.add_child(_bandage_key)
	bv.add_child(cross)
	bv.add_child(_bandage_count)
	bslot.add_child(bv)
	wp.add_child(bslot)
	var sslot := PanelContainer.new()
	sslot.add_theme_stylebox_override("panel", UIStyle.panel(0.5))
	sslot.custom_minimum_size = Vector2(78, 92)
	var sv := VBoxContainer.new()
	sv.alignment = BoxContainer.ALIGNMENT_CENTER
	_shield_key = UIStyle.label(Game.key_label("shield"), 13, UIStyle.DIM)
	_shield_key.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var sicon := UIStyle.label("◈", 26, UIStyle.SHIELD)
	sicon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_shield_count = UIStyle.label("×1", 16, UIStyle.SHIELD, 700)
	_shield_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sv.add_child(_shield_key)
	sv.add_child(sicon)
	sv.add_child(_shield_count)
	sslot.add_child(sv)
	wp.add_child(sslot)
	wp.move_child(sslot, 0)
	var wslot := PanelContainer.new()
	wslot.add_theme_stylebox_override("panel", UIStyle.panel(0.5))
	wslot.custom_minimum_size = Vector2(230, 92)
	var wv := VBoxContainer.new()
	wv.add_theme_constant_override("separation", -2)
	var wtop := HBoxContainer.new()
	wtop.add_child(UIStyle.label(Game.key_label("weapon"), 13, UIStyle.DIM))
	var wname := UIStyle.label("FERRO", 20, UIStyle.TEXT, 700)
	wname.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wname.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	wtop.add_child(wname)
	wv.add_child(wtop)
	var wmid := HBoxContainer.new()
	_ammo = UIStyle.label("001", 34, UIStyle.TEXT, 700)
	wmid.add_child(_ammo)
	var res := UIStyle.label("/ ∞", 16, UIStyle.DIM)
	res.size_flags_vertical = Control.SIZE_SHRINK_END
	wmid.add_child(res)
	wv.add_child(wmid)
	_weapon_state = UIStyle.label("", 13, UIStyle.ACCENT)
	wv.add_child(_weapon_state)
	_attach_label = UIStyle.label("", 11, Items.ATTACHMENTS.silencer.color, 600)
	wv.add_child(_attach_label)
	wslot.add_child(wv)
	wp.add_child(wslot)

	var hints := VBoxContainer.new()
	hints.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	hints.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	hints.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_offsets(hints, Vector2(-260, -250), Vector2(230, 110))
	hints.add_theme_constant_override("separation", 2)
	_root.add_child(hints)
	_hints = hints
	_rebuild_hints()
	Game.bindings_changed.connect(_rebuild_hints)

	# --- centre
	_crosshair = Crosshair.new()
	_crosshair.hud = self
	_crosshair.set_anchors_preset(Control.PRESET_FULL_RECT)
	_crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_crosshair)

	_prompt = UIStyle.label("", 16, UIStyle.TEXT, 600)
	_prompt.set_anchors_preset(Control.PRESET_CENTER)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_offsets(_prompt, Vector2(-200, 70), Vector2(400, 24))
	_root.add_child(_prompt)
	_progress = Bar.new()
	_progress.color = UIStyle.HEALTH
	_progress.set_anchors_preset(Control.PRESET_CENTER)
	_offsets(_progress, Vector2(-90, 98), Vector2(180, 6))
	_progress.visible = false
	_root.add_child(_progress)

	_announce = UIStyle.label("", 64, UIStyle.TEXT, 700)
	_announce.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_announce.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_offsets(_announce, Vector2(-500, 220), Vector2(1000, 80))
	_announce.add_theme_constant_override("outline_size", 8)
	_root.add_child(_announce)
	_announce_sub = UIStyle.label("", 22, UIStyle.DIM, 500)
	_announce_sub.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_announce_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_offsets(_announce_sub, Vector2(-500, 300), Vector2(1000, 30))
	_root.add_child(_announce_sub)

	_spectate = UIStyle.label("", 18, UIStyle.TEXT, 600)
	_spectate.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_spectate.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_offsets(_spectate, Vector2(-400, -150), Vector2(800, 30))
	_root.add_child(_spectate)

	_kill_banner = UIStyle.label("", 26, Color(1, 0.92, 0.85), 700)
	_kill_banner.set_anchors_preset(Control.PRESET_CENTER)
	_kill_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_offsets(_kill_banner, Vector2(-300, 118), Vector2(600, 36))
	_kill_banner.add_theme_constant_override("outline_size", 7)
	_kill_banner.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_kill_banner.modulate.a = 0.0
	_root.add_child(_kill_banner)

	# Kill cam: cinematic bars + who/where/how far.
	_kc_panel = Control.new()
	_kc_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_kc_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_kc_panel.visible = false
	_root.add_child(_kc_panel)
	for top in [true, false]:
		var bar := ColorRect.new()
		bar.color = Color(0, 0, 0, 0.88)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.set_anchors_preset(Control.PRESET_TOP_WIDE if top else Control.PRESET_BOTTOM_WIDE)
		if top:
			bar.offset_bottom = 74
		else:
			bar.offset_top = -74
		_kc_panel.add_child(bar)
	_kc_title = UIStyle.label("", 44, UIStyle.DANGER, 700)
	_kc_title.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_kc_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_offsets(_kc_title, Vector2(-500, -190), Vector2(1000, 56))
	_kc_title.add_theme_constant_override("outline_size", 8)
	_kc_panel.add_child(_kc_title)
	_kc_sub = UIStyle.label("", 22, UIStyle.TEXT, 600)
	_kc_sub.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_kc_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_offsets(_kc_sub, Vector2(-500, -136), Vector2(1000, 30))
	_kc_panel.add_child(_kc_sub)
	_kc_hint = UIStyle.label("", 14, UIStyle.DIM)
	_kc_hint.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_kc_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_offsets(_kc_hint, Vector2(-260, -62), Vector2(230, 24))
	_kc_panel.add_child(_kc_hint)

	_build_hotbar()
	_build_scoreboard()
	_build_pause()
	if Game.is_zombie():
		_build_shop()
	_build_mode_ui()

	arena.match_mgr.state_changed.connect(_on_state_changed)
	arena.match_mgr.kill_feed.connect(_on_kill_feed)
	arena.match_mgr.stats_changed.connect(_refresh_scoreboard)
	if arena.monsters:
		arena.monsters.wave_changed.connect(_on_wave_changed)


var _last_wave_phase := -1
var _last_wave := -1


func _on_wave_changed() -> void:
	var mo := arena.monsters
	if mo.wave == _last_wave and mo.phase == _last_wave_phase:
		return
	_last_wave = mo.wave
	_last_wave_phase = mo.phase
	match mo.phase:
		MonsterManager.Phase.WAVE:
			var from := ""
			var v := viewed()
			if v and mo.wave_origin != Vector3.INF:
				var to := mo.wave_origin - v.global_position
				var b := fposmod(rad_to_deg(atan2(to.x, -to.z)), 360.0)
				from = " · ils arrivent du %s (%d m)" % [["nord", "nord-est", "est", "sud-est", "sud", "sud-ouest", "ouest", "nord-ouest"][int(roundf(b / 45.0)) % 8], int(Vector2(to.x, to.z).length())]
			_show_announce("VAGUE %d" % mo.wave, "%d ennemis%s" % [mo.total, from], 4.0)
			_close_shop()
		MonsterManager.Phase.BREAK:
			if mo.wave > 0:
				_show_announce("VAGUE %d REPOUSSÉE" % mo.wave, "+%d ferraille · les tombés se relèvent · l'établi est ouvert" % Shop.WAVE_SCRAP, 4.0)
			else:
				_show_announce("RESTEZ ENSEMBLE", "Équipez-vous à l'établi : la première vague arrive", 3.5)


static func _offsets(c: Control, pos: Vector2, sz: Vector2) -> void:
	c.offset_left = pos.x
	c.offset_top = pos.y
	c.offset_right = pos.x + sz.x
	c.offset_bottom = pos.y + sz.y


func _rebuild_hints() -> void:
	for c in _hints.get_children():
		c.queue_free()
	_bandage_key.text = Game.key_label("bandage")
	_shield_key.text = Game.key_label("shield")
	for h in [["ÉPAULE", "shoulder"], ["ROULADE", "roll"], ["ACCROUPI", "crouch"], ["BANDAGE", "bandage"], ["BOUCLIER", "shield"]]:
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_END
		row.add_child(UIStyle.label(h[0], 13, UIStyle.DIM))
		var k := UIStyle.label(" " + Game.key_label(h[1]) + " ", 12, Color(0.05, 0.05, 0.05), 700)
		var kb := StyleBoxFlat.new()
		kb.bg_color = Color(0.92, 0.92, 0.9, 0.9)
		kb.set_content_margin_all(1)
		k.add_theme_stylebox_override("normal", kb)
		row.add_child(k)
		_hints.add_child(row)


func bind_local(p: Player) -> void:
	local = p
	p.damaged.connect(_on_damaged)
	p.hit_confirmed.connect(_crosshair.on_hit)
	p.loot_message.connect(func(t): _show_toast(t))


func viewed() -> Player:
	var t := arena.camera_rig.target
	if t and is_instance_valid(t) and t.is_inside_tree():
		return t
	if local and is_instance_valid(local) and local.is_inside_tree():
		return local
	return null


func is_menu_open() -> bool:
	return _pause.visible or _end_panel.visible or (_shop != null and _shop.visible) or (_keybinds != null and _keybinds.visible) or (_armory != null and _armory.visible) or (_crosshair_panel != null and _crosshair_panel.visible)


# ---------------------------------------------------------------- frame update

func _process(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	_process_hud(delta)
	Game.prof_add("hud", t0)


func _process_hud(delta: float) -> void:
	var mm := arena.match_mgr
	_score_l.text = str(mm.scores[0])
	_score_r.text = str(mm.scores[1])
	var tl := int(ceil(mm.time_left))
	_timer.text = "" if Game.is_zombie() else "%d:%02d" % [tl / 60, tl % 60]
	_round_label.text = "MANCHE %d  ·  %d POUR GAGNER" % [mm.round_num, mm.rounds_to_win()]
	_update_mode_ui()

	if mm.state == MatchManager.State.COUNTDOWN:
		var c := int(ceil(mm.time_left))
		if c != _last_countdown and c > 0:
			_last_countdown = c
			_show_announce(str(c), "MANCHE %d — PRÉPAREZ-VOUS" % mm.round_num if Game.mode() == Game.MODE_TDM else Game.MODE_NAMES[Game.mode()].to_upper() + " — PRÉPAREZ-VOUS", 1.1)
			Audio.play_2d("beep", -6.0)

	_announce_t -= delta
	var a := clampf(_announce_t * 2.0, 0.0, 1.0)
	_announce.modulate.a = a
	_announce_sub.modulate.a = a

	var v := viewed()
	_update_squad()
	if v:
		_ammo.text = "001" if v.loaded else "000"
		_ammo.add_theme_color_override("font_color", UIStyle.TEXT if v.loaded else UIStyle.DANGER)
		if v.reload_t >= 0.0:
			_weapon_state.text = "RECHARGEMENT…"
		elif not v.loaded:
			_weapon_state.text = "[%s] RECHARGER" % Game.key_label("reload")
		else:
			_weapon_state.text = ""
		var mods := []
		if v.has_silencer:
			mods.append("◖ SILENCIEUX")
		if v.has_stock:
			mods.append("▮ CROSSE")
		for e in Shop.ENTRIES:
			if Shop.is_upgrade(e) and e.cat == "weapon" and v.upgrade_level(e.id) > 0 and not e.id in ["silencer", "stock"]:
				mods.append("%s %d" % [String(e.name).get_slice(" ", 0), v.upgrade_level(e.id)])
		_attach_label.text = "   ".join(mods)
		if _scrap_label:
			_scrap_label.text = "FERRAILLE  %d" % v.scrap
		_bandage_count.text = "×%d" % v.bandages
		_bandage_count.add_theme_color_override("font_color", UIStyle.TEXT if v.bandages > 0 else UIStyle.DANGER)
		_shield_count.text = "×%d" % v.shield_charges
		_shield_count.add_theme_color_override("font_color", UIStyle.SHIELD if v.shield_charges > 0 else UIStyle.DANGER)
		_update_prompt(v)
	var low := 0.0
	if v and v.alive and v.health <= 50.0:
		low = (0.25 + 0.12 * sin(Time.get_ticks_msec() * 0.006)) * (1.0 - v.health / 50.0 * 0.6)
	if v and v.downed:
		low = 0.5 + 0.12 * sin(Time.get_ticks_msec() * 0.005)
	elif v and not v.alive:
		low = 0.35
	_ping.text = ("PING %d ms" % Game.ping_ms()) if Game.is_online() and not multiplayer.is_server() else ""
	_hurt_flash = move_toward(_hurt_flash, 0.0, delta * 1.8)
	var vm := _vignette.material as ShaderMaterial
	vm.set_shader_parameter("intensity", maxf(low, _hurt_flash))
	vm.set_shader_parameter("tint", Color(0.05, 0.3, 0.7) if _hurt_blue and _hurt_flash > low else Color(0.55, 0.02, 0.0))
	_low_health_feedback(v, delta)
	if _kc_panel.visible and not arena.camera_rig.kill_cam_active():
		_kc_panel.visible = false

	# Debug: --open_shop shows the workbench window (wherever the player stands) once in.
	if _shop and Game.debug.has("open_shop") and local and not _shop.visible and mm.state == MatchManager.State.LIVE:
		# --buy=id,id...: walk up to the bench and buy them (host only), then show the window.
		if Game.debug.has("buy") and multiplayer.is_server() and arena.monsters.phase == MonsterManager.Phase.BREAK:
			var b: Dictionary = arena.map.zombie_bench
			local.global_position = b.pos + b.facing * 1.6
			for id in str(Game.debug.buy).split(","):
				local.buy(id)
				print("[SHOP] %s -> ferraille %d %s" % [id, local.scrap, str(local.upgrades)])
		_shop.open(local)
	_compass.queue_redraw()
	_crosshair.visible = not _blind.visible and not (Game.is_ph() and local != null and local.team == 1)
	_crosshair.queue_redraw()
	_update_hotbar(delta)
	_scoreboard.visible = (Input.is_action_pressed("scoreboard") and not _pause.visible) or _end_panel.visible
	if _scoreboard.visible and Engine.get_process_frames() % 20 == 0:
		_refresh_scoreboard()


## Low health: the colours drain away and a heartbeat thumps, faster the worse it is.
func _low_health_feedback(v: Player, delta: float) -> void:
	var want := 0.0
	var beat := -1.0
	if v and v == local and (v.alive or v.downed):
		if v.downed:
			want = 0.85
			beat = 0.75
		elif v.health <= 40.0:
			var worst := 1.0 - v.health / 40.0
			want = worst * 0.6
			beat = lerpf(1.0, 0.55, worst)
	_sat = lerpf(_sat, 1.0 - want, 1.0 - exp(-delta * 3.0))
	var map := arena.map
	if map and map.environment_node and map.environment_node.environment:
		var env := map.environment_node.environment
		if _base_saturation < 0.0:
			_base_saturation = env.adjustment_saturation
		# Night washes the colours out too (zombie survival).
		env.adjustment_saturation = _base_saturation * _sat * (1.0 - 0.3 * map.night)
	_heart_t -= delta
	if beat > 0.0 and _heart_t <= 0.0:
		_heart_t = beat
		Audio.play_2d("heartbeat", lerpf(-16.0, -5.0, clampf(1.0 - beat, 0.0, 1.0) * 2.0))


func _update_prompt(v: Player) -> void:
	_progress.visible = false
	_progress.color = UIStyle.HEALTH
	_prompt.text = ""
	if v != local:
		return
	if v.downed:
		var r := v.get_reviver()
		if r:
			_prompt.text = "%s VOUS RELÈVE…" % r.display_name.to_upper()
			_progress.visible = true
			_progress.value = r.revive_progress()
		else:
			_prompt.text = "À TERRE — rampez à couvert, un allié peut vous relever"
		return
	if not v.alive:
		return
	if Game.is_ph():
		_prop_prompt(v)
		return
	var bp := v.bandage_progress()
	if bp >= 0.0:
		var t := v.get_bandage_target_node()
		_prompt.text = "APPLICATION DU BANDAGE…" if t == v else "SOIN DE %s…" % (t.display_name.to_upper() if t else "")
		_progress.visible = true
		_progress.value = bp
		return
	var rp := v.revive_progress()
	if rp >= 0.0:
		var rt := arena.get_player(v.revive_target)
		_prompt.text = "RELÈVE %s…  (maintenir [%s])" % [rt.display_name.to_upper() if rt else "", Game.key_label("interact")]
		_progress.visible = true
		_progress.value = rp
		return
	var sp := v.shield_progress()
	if sp >= 0.0:
		_prompt.text = "RECHARGE DU BOUCLIER…"
		_progress.color = UIStyle.SHIELD
		_progress.visible = true
		_progress.value = sp
		return
	if not arena.match_allows_fire():
		return
	# Item in hand
	var held := v.held_item()
	if held != "":
		if held == "defib":
			var dt := v.get_revive_candidate(Player.DEFIB_RANGE)
			_prompt.text = ("[%s] DÉFIBRILLER %s     [%s] RANGER" % [Game.key_label("fire"), dt.display_name.to_upper(), Game.key_label("aim")]) if dt else "APPROCHEZ-VOUS D'UN ALLIÉ À TERRE"
			return
		var verb := "POSER" if held == "barricade" else "LANCER"
		_prompt.text = "[%s] %s %s     [%s] RANGER" % [Game.key_label("fire"), verb, Items.DEFS[held].name, Game.key_label("aim")]
		if held == "barricade" and v.barricade_placement() == null:
			_prompt.text = "EMPLACEMENT INVALIDE"
		return
	# Knocked-down ally
	var down := v.get_revive_candidate(Player.REVIVE_RANGE)
	if down:
		_prompt.text = "[%s] (maintenir) RELEVER %s" % [Game.key_label("interact"), down.display_name.to_upper()]
		for i in v.inventory.size():
			if not v.inventory[i].is_empty() and v.inventory[i].id == "defib":
				_prompt.text += "     [%s] DÉFIBRILLATEUR" % Game.key_label("slot_%d" % (i + 1))
		return
	if v.shield <= 0.0 and v.shield_charges > 0:
		_prompt.text = "[%s] RECHARGER LE BOUCLIER" % Game.key_label("shield")
	# Zombie workbench
	if _shop and v == local and arena.near_bench(v) and _prompt.text == "" and arena.chest_for(v) == null:
		if arena.can_shop(v):
			_prompt.text = "[%s] ÉTABLI — ACHATS ET AMÉLIORATIONS  (%d ferraille)" % [Game.key_label("interact"), v.scrap]
		else:
			_prompt.text = "[%s] ÉTABLI — FERMÉ PENDANT LES VAGUES" % Game.key_label("interact")
		return
	# Supply crate
	var chest := arena.chest_for(v)
	if chest and _prompt.text == "":
		_prompt.text = "[%s] (maintenir) FOUILLER LA CAISSE" % Game.key_label("interact")
		if v.interact_progress > 0.0:
			_progress.visible = true
			_progress.value = v.interact_progress
		return
	if v.bandages <= 0 or _prompt.text != "":
		return
	var c := v.get_bandage_candidate()
	if c and c != v:
		_prompt.text = "[%s] SOIGNER %s" % [Game.key_label("bandage"), c.display_name.to_upper()]
	elif c == v and v.health <= 60.0:
		_prompt.text = "[%s] SE SOIGNER" % Game.key_label("bandage")


func _update_squad() -> void:
	var team := arena.local_team
	var members: Array[Player] = []
	if local:
		members.append(local)
	for p in arena.players:
		if p.team == team and p != local:
			members.append(p)
	var keys := []
	for p in members:
		keys.append(p.name)
	if keys != _squad_rows.keys():
		for c in _squad.get_children():
			_squad.remove_child(c)
			c.queue_free()
		_squad_rows.clear()
		# Big squads (up to 10) get slimmer rows for the teammates.
		var tight := members.size() > 5
		for p in members:
			var row := VBoxContainer.new()
			row.add_theme_constant_override("separation", 1 if tight and p != local else 2)
			var top := HBoxContainer.new()
			var marker := ColorRect.new()
			marker.color = Game.team_color(team)
			marker.custom_minimum_size = Vector2(4, 16 if p == local or not tight else 11)
			top.add_child(marker)
			var name_l := UIStyle.label(" " + p.display_name, 16 if p == local else (12 if tight else 14), UIStyle.TEXT, 600 if p == local else 500)
			top.add_child(name_l)
			row.add_child(top)
			var sbar := Bar.new()
			sbar.color = UIStyle.SHIELD
			sbar.custom_minimum_size = Vector2(260 if p == local else (160 if tight else 200), 5 if p == local else (3 if tight else 4))
			row.add_child(sbar)
			var bar := Bar.new()
			bar.color = UIStyle.HEALTH
			bar.segments = 4
			bar.custom_minimum_size = Vector2(260 if p == local else (160 if tight else 200), 10 if p == local else (5 if tight else 7))
			row.add_child(bar)
			if p == local:
				if _stamina.get_parent():
					_stamina.get_parent().remove_child(_stamina)
				row.add_child(_stamina)
			_squad.add_child(row)
			_squad_rows[p.name] = {"bar": bar, "sbar": sbar, "name": name_l, "player": p}
	var pulse := 0.6 + 0.4 * sin(Time.get_ticks_msec() * 0.008)
	for k in _squad_rows:
		var r: Dictionary = _squad_rows[k]
		var p: Player = r.player
		if not is_instance_valid(p):
			continue
		var bar: Bar = r.bar
		bar.value = p.health / Player.MAX_HEALTH
		bar.pending = minf(p.health + p.pending_regen(), Player.MAX_HEALTH) / Player.MAX_HEALTH if multiplayer.is_server() else bar.value
		bar.color = UIStyle.HEALTH if p.health > 50.0 else UIStyle.DANGER
		bar.dead = not p.alive and not p.downed
		var sbar: Bar = r.sbar
		sbar.value = p.shield / Player.MAX_SHIELD
		sbar.pending = p.shield_progress() if p.shield_t >= 0.0 else 0.0
		sbar.dead = bar.dead
		var nl := r.name as Label
		if p.downed:
			bar.value = 0.0
			nl.text = " " + p.display_name + "   ▼ À TERRE"
			nl.modulate = Color(1.0, 0.4, 0.35, pulse)
		else:
			nl.text = " " + p.display_name
			nl.modulate = Color(1, 1, 1, 1.0 if p.alive else 0.4)
	if local:
		_stamina.value = local.stamina / 100.0


# ---------------------------------------------------------------- events

func _show_announce(text: String, sub := "", dur := 2.5) -> void:
	_announce.text = text
	_announce_sub.text = sub
	_announce_t = dur


func _on_state_changed() -> void:
	var mm := arena.match_mgr
	var my_team := arena.local_team
	if Game.mode() != Game.MODE_TDM and (mm.state == MatchManager.State.LIVE or mm.state == MatchManager.State.ROUND_END):
		_mode_state_changed()
		return
	match mm.state:
		MatchManager.State.LIVE:
			_last_countdown = -1
			_show_announce("COMBATTEZ", "Éliminez l'équipe adverse · fouillez les caisses", 1.6)
			Audio.play_music("match", -14.0) # the calm ambient track for every round
			Audio.play_2d("round", -4.0)
		MatchManager.State.ROUND_END:
			if mm.round_winner >= 0:
				Audio.play_2d("round_win" if mm.round_winner == my_team else "round_lose", -4.0)
			if mm.round_winner < 0:
				_show_announce("ÉGALITÉ", "Personne ne marque", 4.0)
			elif mm.round_winner == my_team:
				_show_announce("MANCHE REMPORTÉE", "%d — %d" % [mm.scores[my_team], mm.scores[1 - my_team]], 4.0)
			else:
				_show_announce("MANCHE PERDUE", "%d — %d" % [mm.scores[my_team], mm.scores[1 - my_team]], 4.0)
		MatchManager.State.MATCH_END:
			_show_end()
		MatchManager.State.COUNTDOWN:
			_end_panel.visible = false
			if not _pause.visible:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _on_damaged(from: Vector3, health_lost: bool) -> void:
	# Red when health went, blue when the shield absorbed it.
	_hurt_flash = 0.62 if health_lost else 0.4
	_hurt_blue = not health_lost
	_crosshair.add_damage(from, health_lost)


## White-out after a close explosion (k 0..1): instant, then clears over ~1.5 s.
func screen_flash(k: float) -> void:
	if _flash == null:
		_flash = ColorRect.new()
		_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
		_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_flash.color = Color(1.0, 0.95, 0.85, 0.0)
		_root.add_child(_flash)
		_root.move_child(_flash, 1)
	_flash.color.a = clampf(0.25 + 0.6 * k, 0.0, 0.85)
	var tw := create_tween()
	tw.tween_interval(0.08)
	tw.tween_property(_flash, "color:a", 0.0, 0.5 + 1.1 * k)


## Shooter side: floating damage number at the impact, kill banner under the crosshair.
func on_hit_feedback(result: int, headshot: bool, amount: float, pos: Vector3, victim: String) -> void:
	var shield := result == Player.HIT_SHIELD or result == Player.HIT_SHIELD_BREAK
	var col := UIStyle.SHIELD if shield else (UIStyle.ACCENT if headshot else Color(1, 1, 1))
	var txt := "%d" % int(amount) + (" ◎" if headshot else "")
	var lbl := Label3D.new()
	lbl.text = txt
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = true
	lbl.fixed_size = true
	lbl.pixel_size = 0.0011 if not headshot else 0.0014
	lbl.font_size = 30
	lbl.outline_size = 8
	lbl.modulate = col
	lbl.top_level = true
	arena.add_child(lbl)
	lbl.global_position = pos + Vector3(randf_range(-0.15, 0.15), 0.25, randf_range(-0.15, 0.15))
	lbl.scale = Vector3.ONE * 1.5
	var tw := lbl.create_tween().set_parallel(true)
	tw.tween_property(lbl, "scale", Vector3.ONE, 0.12)
	tw.tween_property(lbl, "global_position", lbl.global_position + Vector3(0, 1.1, 0), 0.9).set_ease(Tween.EASE_OUT)
	tw.tween_property(lbl, "modulate:a", 0.0, 0.35).set_delay(0.55)
	tw.chain().tween_callback(lbl.queue_free)
	if result == Player.HIT_KNOCK or result == Player.HIT_KILL:
		_kill_banner.text = ("%s · %s%s" % ["ACHEVÉ" if result == Player.HIT_KILL else "À TERRE", victim.to_upper(), "  ◎" if headshot else ""])
		_kill_banner.modulate = Color(1, 1, 1, 1)
		_kill_banner.pivot_offset = _kill_banner.size * 0.5
		_kill_banner.scale = Vector2.ONE * 1.5
		if _kill_tw:
			_kill_tw.kill()
		_kill_tw = create_tween()
		_kill_tw.tween_property(_kill_banner, "scale", Vector2.ONE, 0.15).set_ease(Tween.EASE_OUT)
		_kill_tw.tween_interval(1.4)
		_kill_tw.tween_property(_kill_banner, "modulate:a", 0.0, 0.5)


# ---------------------------------------------------------------- kill cam overlay

func show_kill_cam(killer: String, dist: float, headshot: bool, weapon: String) -> void:
	_kc_title.text = "ABATTU PAR %s" % killer.to_upper()
	var bits := []
	if dist >= 0.0:
		bits.append("%d m" % int(dist))
	if headshot:
		bits.append("TÊTE ◎")
	if weapon != "FERRO":
		bits.append(weapon)
	_kc_sub.text = "   ·   ".join(bits)
	_kc_hint.text = "[%s] passer" % Game.key_label("jump")
	_kc_panel.visible = true
	_kc_panel.modulate.a = 0.0
	create_tween().tween_property(_kc_panel, "modulate:a", 1.0, 0.3)


func hide_kill_cam() -> void:
	if _kc_panel:
		_kc_panel.visible = false


func on_local_death(killer_name: String) -> void:
	_show_announce("ÉLIMINÉ", "par %s" % killer_name, 3.0)


func on_local_down(attacker_name: String) -> void:
	_show_announce("À TERRE", ("par %s — " % attacker_name if attacker_name != "" else "") + "rampez, un allié peut vous relever", 3.0)


func on_local_revived(by_name: String) -> void:
	_show_announce("RELEVÉ", "par %s" % by_name if by_name != "" else "", 2.0)


func set_spectating(p: Player) -> void:
	if p == null:
		_spectate.text = ""
	else:
		_spectate.text = "SPECTATEUR — %s     [%s] suivant" % [p.display_name.to_upper(), Game.key_label("fire")]


func _on_kill_feed(killer: String, kt: int, victim: String, vt: int, headshot: bool, weapon := "FERRO", kind := 0) -> void:
	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", UIStyle.panel(0.45, 0.0))
	row.size_flags_horizontal = Control.SIZE_SHRINK_END
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	h.add_child(UIStyle.label(killer, 15, Game.team_color(kt), 600))
	var what := weapon + ("  ◎" if headshot else "")
	if kind == MatchManager.FEED_KNOCK:
		what = "▼ " + what
	else:
		what = "✖ ACHEVÉ"
	h.add_child(UIStyle.label(what, 13, UIStyle.DANGER if kind == MatchManager.FEED_FINISH else (UIStyle.ACCENT if weapon != "FERRO" else UIStyle.DIM)))
	h.add_child(UIStyle.label(victim, 15, Game.team_color(vt), 600))
	row.add_child(h)
	_killfeed.add_child(row)
	while _killfeed.get_child_count() > 5:
		_killfeed.get_child(0).queue_free()
		_killfeed.remove_child(_killfeed.get_child(0))
	var tw := row.create_tween()
	tw.tween_interval(6.0)
	tw.tween_property(row, "modulate:a", 0.0, 0.6)
	tw.tween_callback(row.queue_free)


# ---------------------------------------------------------------- scoreboard

func _build_scoreboard() -> void:
	_scoreboard = PanelContainer.new()
	_scoreboard.add_theme_stylebox_override("panel", UIStyle.panel(0.78, 0.15))
	_scoreboard.set_anchors_preset(Control.PRESET_CENTER)
	_offsets(_scoreboard, Vector2(-420, -260), Vector2(840, 0))
	_scoreboard.visible = false
	_root.add_child(_scoreboard)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	_scoreboard.add_child(v)

	_end_panel = PanelContainer.new()
	_end_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	_end_panel.visible = false
	var ev := VBoxContainer.new()
	ev.alignment = BoxContainer.ALIGNMENT_CENTER
	_end_title = UIStyle.label("VICTOIRE", 54, UIStyle.ACCENT, 700)
	_end_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_end_score = UIStyle.label("", 22, UIStyle.TEXT)
	_end_score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ev.add_child(_end_title)
	ev.add_child(_end_score)
	_end_panel.add_child(ev)
	v.add_child(_end_panel)

	_sb_grid = VBoxContainer.new()
	_sb_grid.add_theme_constant_override("separation", 14)
	v.add_child(_sb_grid)

	_end_buttons = HBoxContainer.new()
	_end_buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	_end_buttons.add_theme_constant_override("separation", 12)
	_end_buttons.visible = false
	v.add_child(_end_buttons)


func _refresh_scoreboard() -> void:
	if _sb_grid == null:
		return
	for c in _sb_grid.get_children():
		c.queue_free()
	var stats := arena.match_mgr.stats
	var groups := [-1] if Game.is_ffa() else ([0] if Game.is_zombie() else [0, 1])
	for t in groups:
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 3)
		var head := HBoxContainer.new()
		var title_text := "CLASSEMENT" if t < 0 else ("%s   %d" % [Game.team_name(t), arena.match_mgr.scores[t]] if Game.mode() == Game.MODE_TDM else Game.team_name(t))
		if t >= 0 and Game.mode() == Game.MODE_TDM:
			title_text = "ÉQUIPE " + title_text
		var title := UIStyle.label(title_text, 20, UIStyle.ACCENT if t < 0 else Game.team_color(t), 700)
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(title)
		for col in ["É", "M", "A", "DÉGÂTS"]:
			var l := UIStyle.label(col, 13, UIStyle.DIM)
			l.custom_minimum_size = Vector2(70 if col != "DÉGÂTS" else 90, 0)
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			head.add_child(l)
		box.add_child(head)
		var rows := []
		for k in stats:
			if t < 0 or int(stats[k].team) == t:
				rows.append([k, stats[k]])
		rows.sort_custom(func(a, b): return a[1].k > b[1].k or (a[1].k == b[1].k and a[1].dmg > b[1].dmg))
		for r in rows:
			var s: Dictionary = r[1]
			var p := arena.get_player(r[0])
			var line := PanelContainer.new()
			var is_me: bool = local != null and p == local
			line.add_theme_stylebox_override("panel", UIStyle.panel(0.35 if not is_me else 0.6, 0.3 if is_me else 0.0))
			var h := HBoxContainer.new()
			var dot_txt := "●" if (p and p.alive) else ("▼" if (p and p.downed) else "✕")
			var alive_dot := UIStyle.label(dot_txt, 13, Game.team_color(int(s.team)) if (p and p.alive) else (UIStyle.DANGER if (p and p.downed) else UIStyle.DIM))
			alive_dot.custom_minimum_size = Vector2(22, 0)
			h.add_child(alive_dot)
			var n := UIStyle.label(str(s.name) + ("  [BOT]" if s.bot else ""), 16, UIStyle.TEXT, 600 if is_me else 500)
			n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			h.add_child(n)
			for f in ["k", "d", "a", "dmg"]:
				var l := UIStyle.label(str(s[f]), 16, UIStyle.TEXT)
				l.custom_minimum_size = Vector2(70 if f != "dmg" else 90, 0)
				l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
				h.add_child(l)
			line.add_child(h)
			box.add_child(line)
		_sb_grid.add_child(box)


func _show_end() -> void:
	var mm := arena.match_mgr
	var won := mm.match_winner == arena.local_team
	_end_title.text = "VICTOIRE" if won else "DÉFAITE"
	_end_title.add_theme_color_override("font_color", UIStyle.ACCENT if won else UIStyle.DANGER)
	_end_score.text = "%s %d — %d %s" % [Game.TEAM_NAMES[0], mm.scores[0], mm.scores[1], Game.TEAM_NAMES[1]]
	if Game.mode() == Game.MODE_BR:
		var wname := "personne"
		for k in mm.stats:
			if int(mm.stats[k].team) == mm.match_winner:
				wname = str(mm.stats[k].name)
		_end_score.text = "Dernier survivant : %s" % wname
	elif Game.mode() == Game.MODE_PH:
		_end_score.text = "Le chasseur gagne" if mm.match_winner == 0 else "Les props gagnent"
	elif Game.is_zombie():
		_end_score.text = "Vague %d / %d" % [arena.monsters.wave, MonsterManager.WAVES]
	for c in _end_buttons.get_children():
		c.queue_free()
	if multiplayer.is_server():
		var again := Button.new()
		again.text = "REJOUER"
		again.pressed.connect(func():
			_end_panel.visible = false
			_end_buttons.visible = false
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			mm.server_restart())
		_end_buttons.add_child(again)
	else:
		_end_buttons.add_child(UIStyle.label("En attente de l'hôte…", 16, UIStyle.DIM))
	var quit := Button.new()
	quit.text = "QUITTER"
	quit.pressed.connect(func(): Game.leave_session())
	_end_buttons.add_child(quit)
	_end_panel.visible = true
	_end_buttons.visible = true
	_refresh_scoreboard()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


# ---------------------------------------------------------------- pause menu

func _build_pause() -> void:
	_pause = PanelContainer.new()
	_pause.add_theme_stylebox_override("panel", UIStyle.panel(0.85, 0.15))
	_pause.set_anchors_preset(Control.PRESET_CENTER)
	_offsets(_pause, Vector2(-220, -200), Vector2(440, 0))
	_pause.visible = false
	_root.add_child(_pause)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	_pause.add_child(v)
	v.add_child(UIStyle.label("PAUSE", 34, UIStyle.ACCENT, 700))
	v.add_child(UIStyle.label("Sensibilité souris", 14, UIStyle.DIM))
	var sens := HSlider.new()
	sens.min_value = 0.2
	sens.max_value = 3.0
	sens.step = 0.05
	sens.value = Game.mouse_sensitivity
	sens.value_changed.connect(func(x): Game.mouse_sensitivity = x)
	v.add_child(sens)
	v.add_child(UIStyle.label("Champ de vision", 14, UIStyle.DIM))
	var fov := HSlider.new()
	fov.min_value = 60
	fov.max_value = 95
	fov.step = 1
	fov.value = Game.fov
	fov.value_changed.connect(func(x): Game.fov = x)
	v.add_child(fov)
	v.add_child(UIStyle.label("Musique", 14, UIStyle.DIM))
	var mus := HSlider.new()
	mus.max_value = 1.0
	mus.step = 0.05
	mus.value = Game.music_volume
	mus.value_changed.connect(func(x):
		Game.music_volume = x
		Audio.apply_volumes())
	v.add_child(mus)
	v.add_child(UIStyle.label("Effets sonores", 14, UIStyle.DIM))
	var sfx := HSlider.new()
	sfx.max_value = 1.0
	sfx.step = 0.05
	sfx.value = Game.sfx_volume
	sfx.value_changed.connect(func(x):
		Game.sfx_volume = x
		Audio.apply_volumes())
	v.add_child(sfx)
	var kc := CheckBox.new()
	kc.text = "Kill cam (rejouer le tir fatal)"
	kc.button_pressed = Game.kill_cam
	kc.toggled.connect(func(b): Game.kill_cam = b)
	v.add_child(kc)
	var armory := Button.new()
	armory.text = "ARMURERIE"
	armory.pressed.connect(func():
		_pause.hide()
		_armory.open(Game.loadout))
	v.add_child(armory)
	var xh := Button.new()
	xh.text = "RÉTICULE"
	xh.pressed.connect(func():
		_pause.hide()
		_crosshair_panel.show())
	v.add_child(xh)
	_crosshair_panel = CrosshairPanel.new()
	_crosshair_panel.hide()
	_crosshair_panel.closed.connect(func(): _pause.show())
	_root.add_child(_crosshair_panel)
	var keys := Button.new()
	keys.text = "TOUCHES"
	keys.pressed.connect(func():
		_pause.hide()
		_keybinds.show())
	v.add_child(keys)
	var resume := Button.new()
	resume.text = "REPRENDRE"
	resume.pressed.connect(_toggle_pause)
	v.add_child(resume)
	_keybinds = KeybindMenu.new()
	_keybinds.hide()
	_keybinds.closed.connect(func(): _pause.show())
	_root.add_child(_keybinds)
	_armory = CustomizePanel.new()
	_armory.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	_armory.offset_left = -640
	_armory.offset_right = -40
	_armory.offset_top = 60
	_armory.offset_bottom = -60
	_armory.hide()
	_armory.changed.connect(func(l):
		Game.set_loadout(l)
		if local and is_instance_valid(local):
			local.request_loadout(l))
	_armory.closed.connect(func(): _pause.show())
	_root.add_child(_armory)
	var quit := Button.new()
	quit.text = "QUITTER LA PARTIE"
	quit.pressed.connect(func():
		Game.save_settings()
		Game.leave_session())
	v.add_child(quit)
	v.add_child(UIStyle.label("La partie continue en arrière-plan.", 13, UIStyle.DIM))


func _toggle_pause() -> void:
	if _end_panel.visible:
		return
	if _armory.visible:
		_armory.hide()
		_pause.show()
		return
	if _crosshair_panel.visible:
		_crosshair_panel.hide()
		_pause.show()
		return
	if _shop and _shop.visible:
		_close_shop()
		return
	if _keybinds.visible:
		if not _keybinds.is_listening():
			_keybinds.hide()
			_pause.show()
		return
	_pause.visible = not _pause.visible
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if _pause.visible else Input.MOUSE_MODE_CAPTURED
	if not _pause.visible:
		Game.save_settings()


func _input(event: InputEvent) -> void:
	if _shop and event.is_action_pressed("interact") and not event.is_echo():
		if _shop.visible:
			_close_shop()
			get_viewport().set_input_as_handled()
			return
		if local and arena.near_bench(local) and not is_menu_open() and arena.chest_for(local) == null and local.get_revive_candidate(Player.REVIVE_RANGE) == null:
			_shop.open(local)
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("pause"):
		_toggle_pause()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and not is_menu_open() and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()


# ---------------------------------------------------------------- hotbar (slots 1-4)

var _slots: Array = []
var _toast: Label
var _toast_t := 0.0


func _build_shop() -> void:
	_shop = ShopPanel.new()
	_shop.hide()
	_shop.closed.connect(_close_shop)
	_root.add_child(_shop)
	_scrap_label = UIStyle.label("", 18, UIStyle.ACCENT, 700)
	_scrap_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_scrap_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_offsets(_scrap_label, Vector2(-150, -128), Vector2(300, 26))
	_root.add_child(_scrap_label)


func _close_shop() -> void:
	if _shop and _shop.visible:
		_shop.hide()
		if not is_menu_open():
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _build_hotbar() -> void:
	var bar := HBoxContainer.new()
	bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_offsets(bar, Vector2(-150, -96), Vector2(300, 66))
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	bar.add_theme_constant_override("separation", 6)
	_root.add_child(bar)
	for i in Items.SLOTS:
		var w := SlotWidget.new()
		w.index = i
		w.custom_minimum_size = Vector2(68, 66)
		bar.add_child(w)
		_slots.append(w)
	_toast = UIStyle.label("", 20, UIStyle.ACCENT, 700)
	_toast.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_offsets(_toast, Vector2(-300, -132), Vector2(600, 30))
	_root.add_child(_toast)


func _show_toast(text: String) -> void:
	_toast.text = text
	_toast_t = 2.5
	Audio.play_2d("ui", -6.0)


func _update_hotbar(delta: float) -> void:
	_toast_t -= delta
	_toast.modulate.a = clampf(_toast_t * 2.0, 0.0, 1.0)
	var v := viewed()
	for w in _slots:
		w.player = v
		w.queue_redraw()


class SlotWidget extends Control:
	var index := 0
	var player: Player

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var s: Dictionary = player.inventory[index] if player and index < player.inventory.size() else {}
		var selected := player != null and player.is_multiplayer_authority() and player.equipped == index + 1
		var font := get_theme_default_font()
		draw_rect(r, Color(0.04, 0.05, 0.06, 0.6))
		draw_rect(r, UIStyle.ACCENT if selected else Color(1, 1, 1, 0.14), false, 2.0 if selected else 1.0)
		draw_string(font, Vector2(6, 15), Game.key_label("slot_%d" % (index + 1)), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.55))
		if s.is_empty():
			return
		var c := Items.color_of(s.id)
		var mid := size * 0.5 + Vector2(0, 2)
		match s.id:
			"frag":
				draw_circle(mid, 11, c)
				draw_rect(Rect2(mid + Vector2(-3, -17), Vector2(6, 7)), c.darkened(0.4))
				draw_line(mid + Vector2(3, -14), mid + Vector2(10, -4), c.darkened(0.4), 2.0)
			"smoke":
				draw_rect(Rect2(mid + Vector2(-8, -13), Vector2(16, 26)), c)
				draw_rect(Rect2(mid + Vector2(-8, -6), Vector2(16, 4)), Color(0.2, 0.2, 0.2))
			"barricade":
				draw_rect(Rect2(mid + Vector2(-17, -9), Vector2(34, 18)), c)
				for k in 4:
					draw_line(mid + Vector2(-14 + k * 9, -9), mid + Vector2(-9 + k * 9, 9), Color(0.1, 0.1, 0.1), 2.0)
			"defib":
				draw_rect(Rect2(mid + Vector2(-14, -11), Vector2(28, 22)), Color(0.85, 0.86, 0.82))
				draw_polyline(PackedVector2Array([mid + Vector2(-11, 1), mid + Vector2(-4, 1), mid + Vector2(-1, -7), mid + Vector2(3, 8), mid + Vector2(6, 1), mid + Vector2(11, 1)]), c.darkened(0.3), 2.5)
		draw_string(font, Vector2(0, size.y - 6), Items.DEFS[s.id].short, HORIZONTAL_ALIGNMENT_LEFT, size.x - 4, 11, Color(1, 1, 1, 0.8))
		draw_string(font, Vector2(0, size.y - 6), "×%d" % s.n, HORIZONTAL_ALIGNMENT_RIGHT, size.x - 5, 13, Color(1, 1, 1, 0.95))

# ---------------------------------------------------------------- game modes (battle royale / prop hunt)

func _build_mode_ui() -> void:
	_mode_info = UIStyle.label("", 18, UIStyle.ACCENT, 700)
	_mode_info.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_mode_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_mode_info.add_theme_constant_override("outline_size", 6)
	_offsets(_mode_info, Vector2(-400, 106), Vector2(800, 28))
	_root.add_child(_mode_info)
	# The prop-hunt hunter is blind while the props hide.
	_blind = ColorRect.new()
	_blind.set_anchors_preset(Control.PRESET_FULL_RECT)
	_blind.color = Color(0.01, 0.012, 0.015, 1.0)
	_blind.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_blind.visible = false
	_root.add_child(_blind)
	_root.move_child(_blind, 1)
	_blind_label = UIStyle.label("", 34, UIStyle.TEXT, 700)
	_blind_label.set_anchors_preset(Control.PRESET_CENTER)
	_blind_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_offsets(_blind_label, Vector2(-450, -60), Vector2(900, 120))
	_blind.add_child(_blind_label)


static func prop_name(idx: int) -> String:
	if idx < 0 or idx >= Scan.catalog.size():
		return "OBJET"
	var id: String = Scan.catalog[idx].id
	return id.get_file().get_basename().replace("_", " ").to_upper()


## Per-frame texts for battle royale (survivors, zone) and prop hunt (phases, blindfold).
func _update_mode_ui() -> void:
	var mm := arena.match_mgr
	var mode := Game.mode()
	_blind.visible = false
	if mode == Game.MODE_TDM:
		_mode_info.text = ""
		return
	var live := mm.state == MatchManager.State.LIVE
	var v := viewed()
	_score_r.visible = false
	_team_r.visible = false
	if mode == Game.MODE_BR:
		var alive := 0
		for p: Player in arena.players:
			if p.alive:
				alive += 1
		_team_l.text = "EN VIE"
		_team_l.add_theme_color_override("font_color", UIStyle.TEXT)
		_score_l.text = str(alive)
		_score_l.add_theme_color_override("font_color", UIStyle.ACCENT)
		_round_label.text = "BATTLE ROYALE  ·  DERNIER EN VIE GAGNE"
		var info := ""
		var z := arena.zone
		if live and z:
			if z.hold_left() > 0.0:
				info = "LA ZONE SE RESSERRE DANS %d s" % int(ceil(z.hold_left()))
			elif z.progress() < 1.0:
				info = "ZONE EN RÉDUCTION"
			if v and v.alive and z.overshoot(v.global_position) > 0.0:
				info = "⚠ HORS DE LA ZONE — REVENEZ VERS LE CENTRE !"
		_mode_info.text = info
		_mode_info.add_theme_color_override("font_color", UIStyle.DANGER if info.begins_with("⚠") else UIStyle.ACCENT)
		return
	if mode == Game.MODE_ZOMBIE:
		var mo := arena.monsters
		if mo == null:
			return
		_team_l.text = "VAGUE"
		_team_l.add_theme_color_override("font_color", UIStyle.TEXT)
		_score_l.text = "%d / %d" % [maxi(mo.wave, 1), MonsterManager.WAVES]
		_score_l.add_theme_color_override("font_color", UIStyle.ACCENT)
		var standing := 0
		for p: Player in arena.players:
			if p.alive:
				standing += 1
		_round_label.text = "SURVIE ZOMBIES  ·  %d SURVIVANT%s" % [standing, "S" if standing > 1 else ""]
		var zinfo := ""
		if live:
			match mo.phase:
				MonsterManager.Phase.WAVE:
					zinfo = "ENNEMIS RESTANTS : %d" % mo.left
				MonsterManager.Phase.BREAK:
					zinfo = ("VAGUE %d DANS %d s" % [mo.wave + 1, int(ceil(mo.break_t))]) if mo.break_t > 0.0 else ""
		_mode_info.text = zinfo
		_mode_info.add_theme_color_override("font_color", UIStyle.ACCENT)
		return
	# Prop hunt
	var ph := arena.prop_hunt
	if ph == null:
		return
	var hunter := ph.hunter_player()
	_team_l.text = "PROPS EN VIE"
	_team_l.add_theme_color_override("font_color", Game.team_color(1))
	_score_l.text = str(ph.hiders_alive())
	_score_l.add_theme_color_override("font_color", Game.team_color(1))
	_round_label.text = "PROP HUNT  ·  CHASSEUR : %s" % (hunter.display_name.to_upper() if hunter else "?")
	var text := ""
	var hiding := ph.in_hiding_phase()
	if v and v.team == 0 and local == v and (hiding or mm.state == MatchManager.State.COUNTDOWN):
		_blind.visible = true
		_blind_label.text = "LES PROPS SE CACHENT…\n%d s" % int(ceil(ph.hide_left() if live else PropHunt.HIDE_TIME))
	if Game.debug.has("cam_at"):
		_blind.visible = false
	if live and v and v.alive:
		if v.team == 1:
			text = ("CACHEZ-VOUS — LE CHASSEUR ARRIVE DANS %d s" % int(ceil(ph.hide_left()))) if hiding else "RESTEZ IMMOBILE — LE CHASSEUR VOUS CHERCHE"
		else:
			text = "" if hiding else "TROUVEZ ET ÉLIMINEZ LES PROPS — UN TIR SUFFIT"
	_mode_info.text = text
	_mode_info.add_theme_color_override("font_color", UIStyle.ACCENT)


func _prop_prompt(v: Player) -> void:
	if v.team != 1 or arena.match_mgr.state != MatchManager.State.LIVE:
		return
	var idx := v.prop_candidate()
	if idx >= 0 and idx != v.prop_idx:
		_prompt.text = "[%s] SE TRANSFORMER EN : %s" % [Game.key_label("interact"), prop_name(idx)]
	elif v.prop_idx < 0:
		_prompt.text = "APPROCHEZ-VOUS D'UN OBJET ET APPUYEZ SUR [%s]" % Game.key_label("interact")


func _mode_state_changed() -> void:
	var mm := arena.match_mgr
	var my_team := arena.local_team
	if mm.state == MatchManager.State.LIVE:
		_last_countdown = -1
		Audio.play_music("match", -14.0)
		Audio.play_2d("round", -4.0)
		if Game.mode() == Game.MODE_BR:
			_show_announce("SURVIVEZ", "Dernier en vie gagne · fouillez les caisses · restez dans la zone", 3.0)
		elif Game.is_zombie():
			_show_announce("SURVIVEZ", "Tenez %d vagues · relevez vos alliés [%s] · fouillez les caisses" % [MonsterManager.WAVES, Game.key_label("interact")], 3.5)
		elif my_team == 0:
			_show_announce("CHASSEUR", "Patientez : les props se cachent. Puis trouvez-les — un tir suffit.", 3.5)
		else:
			_show_announce("CACHEZ-VOUS", "[%s] près d'un objet pour vous y transformer · restez immobile" % Game.key_label("interact"), 4.0)
		return
	# ROUND_END (the only round of the match)
	var won := mm.round_winner == my_team
	if mm.round_winner >= 0:
		Audio.play_2d("round_win" if won else "round_lose", -4.0)
	if Game.mode() == Game.MODE_BR:
		var wn := ""
		for k in mm.stats:
			if int(mm.stats[k].team) == mm.round_winner:
				wn = str(mm.stats[k].name)
		_show_announce("VICTOIRE !" if won else "TERMINÉ", ("Vous êtes le dernier survivant" if won else "Vainqueur : %s" % wn) if wn != "" else "Personne n'a survécu", 4.0)
	elif Game.is_zombie():
		if won:
			_show_announce("VICTOIRE !", "Les %d vagues ont été repoussées" % MonsterManager.WAVES, 4.5)
		else:
			_show_announce("ÉQUIPE ANÉANTIE", "Vous avez tenu jusqu'à la vague %d" % arena.monsters.wave, 4.5)
	else:
		if mm.round_winner < 0:
			_show_announce("ÉGALITÉ", "", 4.0)
		elif mm.round_winner == 0:
			_show_announce("LE CHASSEUR GAGNE", "Tous les props ont été trouvés", 4.0)
		else:
			_show_announce("LES PROPS GAGNENT", "Le temps est écoulé", 4.0)

# ================================================================ widgets

class Bar extends Control:
	var value := 1.0
	var pending := 0.0
	var color := Color.WHITE
	var segments := 0
	var dead := false

	func _process(_d: float) -> void:
		queue_redraw()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, Color(0, 0, 0, 0.55))
		if dead:
			draw_rect(r, Color(1, 1, 1, 0.08))
			return
		if pending > value:
			draw_rect(Rect2(Vector2.ZERO, Vector2(size.x * clampf(pending, 0, 1), size.y)), Color(color, 0.35))
		draw_rect(Rect2(Vector2.ZERO, Vector2(size.x * clampf(value, 0, 1), size.y)), color)
		for i in range(1, segments):
			var x := size.x * i / segments
			draw_line(Vector2(x, 0), Vector2(x, size.y), Color(0, 0, 0, 0.7), 2.0)


class Compass extends Control:
	var hud: Hud
	const SPAN := 75.0
	const NAMES := {0: "N", 45: "NE", 90: "E", 135: "SE", 180: "S", 225: "SO", 270: "O", 315: "NO"}

	func _draw() -> void:
		var rig := hud.arena.camera_rig
		var bearing := fposmod(-rad_to_deg(rig.rotation.y), 360.0)
		var w := size.x
		var cx := w * 0.5
		var font := get_theme_default_font()
		draw_line(Vector2(0, 22), Vector2(w, 22), Color(1, 1, 1, 0.12), 1.0)
		for d in range(0, 360, 5):
			var rel := wrapf(d - bearing, -180.0, 180.0)
			if absf(rel) > SPAN:
				continue
			var x := cx + rel / SPAN * cx
			var fade := 1.0 - absf(rel) / SPAN
			var col := Color(1, 1, 1, 0.7 * fade)
			if NAMES.has(d):
				var s: String = NAMES[d]
				draw_string(font, Vector2(x - 20, 16), s, HORIZONTAL_ALIGNMENT_CENTER, 40, 15, col)
				draw_line(Vector2(x, 20), Vector2(x, 30), col, 2.0)
			elif d % 15 == 0:
				draw_line(Vector2(x, 22), Vector2(x, 30), col, 1.0)
			else:
				draw_line(Vector2(x, 24), Vector2(x, 28), Color(col, col.a * 0.6), 1.0)
		# teammates
		var v := hud.viewed()
		if v:
			for p: Player in hud.arena.players:
				if p == v or not p.is_hittable() or p.team != hud.arena.local_team:
					continue
				var to := p.global_position - v.global_position
				var b := fposmod(rad_to_deg(atan2(to.x, -to.z)), 360.0)
				var rel := wrapf(b - bearing, -180.0, 180.0)
				if absf(rel) > SPAN:
					continue
				var x := cx + rel / SPAN * cx
				var c: Color = UIStyle.DANGER if p.downed else Game.team_color(p.team)
				draw_colored_polygon(PackedVector2Array([Vector2(x - 5, 34), Vector2(x + 5, 34), Vector2(x, 41)]), c)
		# Zombie survival: where the current wave pours out from (red, pulsing).
		var mo: MonsterManager = hud.arena.monsters
		if v and mo and mo.phase == MonsterManager.Phase.WAVE and mo.wave_origin != Vector3.INF:
			var to3 := mo.wave_origin - v.global_position
			var rel3 := wrapf(fposmod(rad_to_deg(atan2(to3.x, -to3.z)), 360.0) - bearing, -180.0, 180.0)
			var x3 := cx + clampf(rel3, -SPAN, SPAN) / SPAN * cx
			var pulse := 0.65 + 0.35 * sin(Time.get_ticks_msec() * 0.008)
			draw_colored_polygon(PackedVector2Array([Vector2(x3 - 8, 31), Vector2(x3 + 8, 31), Vector2(x3, 45)]), Color(1.0, 0.15, 0.08, pulse))
			draw_string(font, Vector2(x3 - 30, 60), "%d m" % int(Vector2(to3.x, to3.z).length()), HORIZONTAL_ALIGNMENT_CENTER, 60, 12, Color(1.0, 0.35, 0.25, 0.9))
		# Active supply crates within 60 m
		if v and v.is_inside_tree():
			for ch in hud.arena.chests:
				if not ch.can_loot() or not ch.is_inside_tree():
					continue
				var to2 := ch.global_position - v.global_position
				if to2.length() > 60.0:
					continue
				var b2 := fposmod(rad_to_deg(atan2(to2.x, -to2.z)), 360.0)
				var rel2 := wrapf(b2 - bearing, -180.0, 180.0)
				if absf(rel2) > SPAN:
					continue
				var x2 := cx + rel2 / SPAN * cx
				var cc := Color(0.35, 0.9, 1.0, 1.0) if ch.special != "" else Color(1.0, 0.65, 0.15, 0.95)
				draw_colored_polygon(PackedVector2Array([Vector2(x2, 33), Vector2(x2 + 5, 38), Vector2(x2, 43), Vector2(x2 - 5, 38)]), cc)
		var box := Rect2(cx - 24, 30, 48, 18)
		draw_rect(box, Color(1, 1, 1, 0.15))
		draw_string(font, Vector2(cx - 24, 44), "%03d" % int(bearing), HORIZONTAL_ALIGNMENT_CENTER, 48, 14, Color(1, 1, 1, 0.95))


class Crosshair extends Control:
	var hud: Hud
	var _hit_t := 0.0
	var _hit_kill := false
	var _hit_head := false
	var _hit_shield := false
	var _damage := []

	const HIT_TIME := 0.85
	const HIT_KILL_TIME := 1.2

	func on_hit(headshot: bool, result: int) -> void:
		_hit_kill = result == Player.HIT_KILL or result == Player.HIT_KNOCK
		_hit_t = HIT_KILL_TIME if _hit_kill else HIT_TIME
		_hit_head = headshot
		_hit_shield = result == Player.HIT_SHIELD or result == Player.HIT_SHIELD_BREAK

	func add_damage(from: Vector3, health_lost := true) -> void:
		_damage.append({"pos": from, "t": 1.6, "hp": health_lost})

	func _process(delta: float) -> void:
		_hit_t = maxf(0.0, _hit_t - delta)
		for d in _damage:
			d.t -= delta
		_damage = _damage.filter(func(d): return d.t > 0.0)

	func _draw() -> void:
		var c := size * 0.5
		var p := hud.viewed()
		if p == null:
			return
		if p.alive and not p.is_channeling() and not (Game.is_ph() and p.team == 1):
			var cam := hud.arena.camera_rig.cam
			var px := tan(deg_to_rad(p.spread)) / tan(deg_to_rad(cam.fov * 0.5)) * size.y * 0.5
			CrosshairPainter.draw(self, c, Game.crosshair, px, 1.0 if p.aiming else 0.85, p.fire_blocked if p == hud.local else 0.0)
			var rp := p.reload_progress()
			if rp >= 0.0:
				draw_arc(c, 26, -PI / 2, -PI / 2 + TAU * rp, 48, Color(0, 0, 0, 0.4), 5.0)
				draw_arc(c, 26, -PI / 2, -PI / 2 + TAU * rp, 48, UIStyle.ACCENT, 3.0)
			elif not p.loaded:
				var blink := 0.55 + 0.45 * sin(Time.get_ticks_msec() * 0.012)
				draw_arc(c, 26, 0, TAU, 48, Color(1, 0.3, 0.25, 0.35 + 0.35 * blink), 2.0)
				var font := get_theme_default_font()
				draw_string(font, c + Vector2(-70, 54), "[%s] RECHARGER" % Game.key_label("reload"), HORIZONTAL_ALIGNMENT_CENTER, 140, 14, Color(1, 0.45, 0.4, 0.5 + 0.5 * blink))
		if _hit_t > 0.0 and Game.crosshair.hitmarker:
			# Pops out big, holds, then fades over the last 40% of its life.
			var life := HIT_KILL_TIME if _hit_kill else HIT_TIME
			var age := life - _hit_t
			var a := clampf(_hit_t / (life * 0.4), 0.0, 1.0)
			var pop := 1.0 + 0.45 * exp(-age * 14.0)
			var hc := UIStyle.DANGER if _hit_kill else (UIStyle.ACCENT if _hit_head else (UIStyle.SHIELD if _hit_shield else Color.WHITE))
			hc.a = a
			var r0 := 10.0 * pop
			var r1 := (34.0 if _hit_kill else (30.0 if _hit_head else 26.0)) * pop
			var w := 3.5 if _hit_kill or _hit_head else 2.5
			for d in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
				var n: Vector2 = d.normalized()
				draw_line(c + n * (r0 - 1.0), c + n * (r1 + 1.0), Color(0, 0, 0, a * 0.55), w + 2.5)
				draw_line(c + n * r0, c + n * r1, hc, w)
		var yaw := hud.arena.camera_rig.rotation.y
		for d in _damage:
			var to: Vector3 = d.pos - p.global_position
			var local_v := Basis(Vector3.UP, yaw).inverse() * to
			var ang := atan2(local_v.x, -local_v.z) - PI / 2
			var fade := clampf(d.t, 0.0, 1.0)
			var base := Color(0.95, 0.15, 0.1) if d.get("hp", true) else Color(0.25, 0.65, 1.0)
			# Fresh hits kick the arc outwards and make it wider.
			var fresh := clampf((d.t - 1.2) / 0.4, 0.0, 1.0)
			var r := 120.0 + 14.0 * fresh
			draw_arc(c, r, ang - 0.36 - 0.1 * fresh, ang + 0.36 + 0.1 * fresh, 24, Color(0, 0, 0, fade * 0.45), 11.0)
			draw_arc(c, r, ang - 0.34 - 0.1 * fresh, ang + 0.34 + 0.1 * fresh, 24, Color(base, fade * 0.9), 7.0)
			draw_arc(c, r + 9.0, ang - 0.2, ang + 0.2, 16, Color(base.lightened(0.4), fade * 0.7), 2.5)
