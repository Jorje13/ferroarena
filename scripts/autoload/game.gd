extends Node
## Global state: settings, input map, networking (ENet) and lobby.

signal lobby_changed
signal status_message(text: String)
signal all_peers_ready

const DEFAULT_PORT := 7777
## Bump when the network protocol / gameplay changes: mismatched builds are refused.
const GAME_VERSION := "0.27.1"
const MAX_CLIENTS := 19
## Biggest team (format 10v10).
const MAX_TEAM := 10
const SETTINGS_PATH := "user://settings.cfg"
const MENU_SCENE := "res://scenes/main_menu.tscn"
const ARENA_SCENE := "res://scenes/arena.tscn"

const MAPS := [
	{"id": "dam", "name": "Barrage d'Alcantara", "script": "res://scripts/maps/map_dam.gd"},
	{"id": "pass", "name": "Col de Givre", "script": "res://scripts/maps/map_pass.gd"},
]
const TEAM_NAMES := ["OCRE", "AZUR"]
## Game modes (config.mode). Battle royale gives every raider a team index of their own
## (colours 2..), so friend / foe checks stay "same team index".
enum { MODE_TDM, MODE_BR, MODE_PH, MODE_ZOMBIE }
const MODE_NAMES := ["Élimination par équipes", "Battle royale", "Prop hunt", "Survie zombies"]
## Zombie survival: team 0 = the survivors, team 1 = the monsters (no players).
const ZOMBIE_NAMES := ["SURVIVANTS", "MONSTRES"]
const DIFFICULTY_NAMES := ["Facile", "Normal", "Difficile", "Expert"]
## Prop hunt roles: team 0 hunts, team 1 hides.
const PH_NAMES := ["CHASSEUR", "PROPS"]
const TEAM_COLORS := [Color(0.98, 0.74, 0.22), Color(0.36, 0.66, 1.0),
	Color(0.9, 0.3, 0.3), Color(0.4, 0.85, 0.45), Color(0.8, 0.45, 0.95), Color(0.3, 0.85, 0.85), Color(1.0, 0.55, 0.15),
	Color(0.95, 0.5, 0.7), Color(0.7, 0.9, 0.2), Color(0.55, 0.55, 1.0), Color(0.95, 0.9, 0.5), Color(0.6, 0.35, 0.2),
	Color(0.2, 0.6, 0.45), Color(0.85, 0.85, 0.85), Color(0.7, 0.2, 0.55), Color(0.25, 0.45, 0.9), Color(1.0, 0.7, 0.55),
	Color(0.5, 0.75, 0.9), Color(0.65, 0.55, 0.25), Color(0.45, 0.2, 0.7), Color(0.9, 0.2, 0.6), Color(0.3, 0.7, 0.2)]


func mode() -> int:
	return int(config.get("mode", MODE_TDM))


func is_ffa() -> bool:
	return mode() == MODE_BR


func is_ph() -> bool:
	return mode() == MODE_PH


func is_zombie() -> bool:
	return mode() == MODE_ZOMBIE


## Knock-downs and revives only exist in team matches (and against zombies).
func instant_kill() -> bool:
	return mode() != MODE_TDM and mode() != MODE_ZOMBIE


func team_name(t: int) -> String:
	if mode() == MODE_PH:
		return PH_NAMES[clampi(t, 0, 1)]
	if mode() == MODE_ZOMBIE:
		return ZOMBIE_NAMES[clampi(t, 0, 1)]
	if t < 2:
		return TEAM_NAMES[t]
	return "SOLO"


func team_color(t: int) -> Color:
	return TEAM_COLORS[clampi(t, 0, TEAM_COLORS.size() - 1)]
const QUALITY_NAMES := ["Bas", "Moyen", "Élevé", "Ultra"]

# Player settings (persisted)
var player_name := "Raider"
var mouse_sensitivity := 1.0
var fov := 72.0
var quality := 2
var fullscreen := false
## 0 = off, 1 = smooth (mailbox: no tearing, never halves to 30), 2 = classic.
const VSYNC_NAMES := ["Désactivée", "Fluide (recommandé)", "Classique"]
var vsync := 1
## FPS cap (0 = none).
const FPS_CAPS := [0, 60, 120, 144, 165, 240]
var max_fps := 0
var last_ip := "127.0.0.1"
## Replay of the fatal shot when the local raider goes down.
var kill_cam := true
var music_volume := 0.6
## Cosmetic outfit (see ArmorKit), persisted and sent to the host.
var loadout := {}
var sfx_volume := 1.0
## Crosshair look (see CrosshairPainter). Persisted in settings.cfg [crosshair].
const CROSSHAIR_STYLES := ["Croix", "Croix en T", "Cercle", "Point", "Cercle + croix", "Chevron"]
const CROSSHAIR_DEFAULT := {
	"style": 0, "color": Color(1, 1, 1), "length": 9.0, "thickness": 1.0, "gap": 5.0,
	"opacity": 0.85, "outline": true, "dot": true, "dot_size": 1.6, "dynamic": true, "hitmarker": true,
}
var crosshair := CROSSHAIR_DEFAULT.duplicate()
signal crosshair_changed

# Match configuration, decided by the host and sent to every peer.
## bots_0 / bots_1: bots added to each team (-1 = as many as needed to fill the team).
## mode: see MODE_*; difficulty: bot level 0..3; br_bots: bots in a battle royale.
var config := {"team_size": 2, "rounds_to_win": 5, "map": "dam", "bots_0": -1, "bots_1": -1, "round_time": 150.0,
	"mode": 0, "difficulty": 1, "br_bots": 9}
# peer_id -> {"name": String, "team": int}
var lobby := {}
var in_match := false
var ready_peers := {}
var pending_message := ""
var debug := {}
## --perf_log: accumulated µs per section (printed and reset every 5 s by Arena).
var prof := {}


func prof_add(key: String, t0_usec: int) -> void:
	prof[key] = int(prof.get(key, 0)) + Time.get_ticks_usec() - t0_usec


## --log_load: pipeline compilations so far (by when they happened) and video memory.
func log_pipelines() -> void:
	if not debug.has("log_load"):
		return
	var r := RenderingServer
	print("[PIPE] canvas %d  mesh %d  surface %d  draw %d  specialization %d   vram %d Mo  textures %d Mo" % [
		r.get_rendering_info(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_CANVAS),
		r.get_rendering_info(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_MESH),
		r.get_rendering_info(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SURFACE),
		r.get_rendering_info(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_DRAW),
		r.get_rendering_info(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SPECIALIZATION),
		r.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) / 1048576,
		r.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED) / 1048576])


var _mark_ms := 0
## --log_load: loading milestones (ms since launch, and since the previous milestone).
func mark(label: String) -> void:
	if not debug.has("log_load"):
		return
	var now := Time.get_ticks_msec()
	print("[LOAD] %6d ms  (+%5d)  %s" % [now, now - _mark_ms, label])
	_mark_ms = now


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_inputs()
	_load_settings()
	_parse_cmdline()
	_auto_quality()
	apply_video()
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	# Debug: --run_tool=res://tools/x.gd runs a measuring Node script with the autoloads loaded.
	if debug.has("run_tool"):
		get_tree().root.add_child.call_deferred((load(str(debug.run_tool)) as GDScript).new())


## Resources loaded by the launch screen (scenes/boot.tscn), held for the whole session.
var preloaded: Array = []


## Debug launches that skip the menu (--autosolo / --host / --join), started by the launch screen.
func has_boot_target() -> bool:
	return debug.has("autosolo") or debug.has("host") or debug.has("join")


func after_boot() -> void:
	if debug.has("autosolo"):
		_start_debug_solo()
	elif debug.has("host"):
		_start_debug_host()
	elif debug.has("join"):
		join_game(str(debug.join))


# ---------------------------------------------------------------- inputs

## Rebindable actions in menu order: [action, label]. "pause" (Échap) stays fixed.
const ACTIONS := [
	["move_forward", "Avancer"], ["move_back", "Reculer"], ["move_left", "Gauche"], ["move_right", "Droite"],
	["sprint", "Sprint"], ["crouch", "Accroupi"], ["jump", "Saut"], ["roll", "Roulade"],
	["fire", "Tirer"], ["aim", "Viser"], ["reload", "Recharger"], ["shoulder", "Changer d'épaule"],
	["bandage", "Bandage"], ["shield", "Recharger le bouclier"], ["interact", "Interagir (caisses, relever)"],
	["weapon", "Arme"], ["slot_1", "Objet 1"], ["slot_2", "Objet 2"], ["slot_3", "Objet 3"], ["slot_4", "Objet 4"],
	["scoreboard", "Tableau des scores"],
]
## Slots are ["key", physical_keycode] or ["mouse", button_index]; two slots per action.
## Physical keycodes: WASD on QWERTY is ZQSD on AZERTY automatically.
const DEFAULT_BINDINGS := {
	"move_forward": [["key", KEY_W], ["key", KEY_UP]],
	"move_back": [["key", KEY_S], ["key", KEY_DOWN]],
	"move_left": [["key", KEY_A], ["key", KEY_LEFT]],
	"move_right": [["key", KEY_D], ["key", KEY_RIGHT]],
	"sprint": [["key", KEY_SHIFT], []],
	"crouch": [["key", KEY_C], ["key", KEY_CTRL]],
	"jump": [["key", KEY_SPACE], []],
	"roll": [["key", KEY_ALT], []],
	"fire": [["mouse", MOUSE_BUTTON_LEFT], []],
	"aim": [["mouse", MOUSE_BUTTON_RIGHT], []],
	"reload": [["key", KEY_R], []],
	"shoulder": [["key", KEY_F], ["mouse", MOUSE_BUTTON_MIDDLE]],
	"bandage": [["key", KEY_Q], []],
	"shield": [["key", KEY_X], []],
	"interact": [["key", KEY_E], []],
	"weapon": [["key", KEY_1], []],
	"slot_1": [["key", KEY_2], []],
	"slot_2": [["key", KEY_3], []],
	"slot_3": [["key", KEY_4], []],
	"slot_4": [["key", KEY_5], []],
	"scoreboard": [["key", KEY_TAB], []],
}

signal bindings_changed

var bindings := {}


func _setup_inputs() -> void:
	bindings = DEFAULT_BINDINGS.duplicate(true)
	if not InputMap.has_action("pause"):
		InputMap.add_action("pause")
		var esc := InputEventKey.new()
		esc.physical_keycode = KEY_ESCAPE
		InputMap.action_add_event("pause", esc)
	apply_bindings()


func apply_bindings() -> void:
	for action in bindings:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		InputMap.action_erase_events(action)
		for slot in bindings[action]:
			var ev := event_from_slot(slot)
			if ev:
				InputMap.action_add_event(action, ev)
	bindings_changed.emit()


static func event_from_slot(slot: Array) -> InputEvent:
	if slot.size() < 2:
		return null
	if slot[0] == "key":
		var k := InputEventKey.new()
		k.physical_keycode = int(slot[1])
		return k
	if slot[0] == "mouse":
		var m := InputEventMouseButton.new()
		m.button_index = int(slot[1])
		return m
	return null


## Sets one slot; the same input is removed from every other action (no duplicates).
func set_binding(action: String, idx: int, slot: Array) -> void:
	if not slot.is_empty():
		for a in bindings:
			for i in bindings[a].size():
				if bindings[a][i] == slot:
					bindings[a][i] = []
	bindings[action][idx] = slot
	apply_bindings()
	save_settings()


func reset_bindings() -> void:
	bindings = DEFAULT_BINDINGS.duplicate(true)
	apply_bindings()
	save_settings()


func slot_label(slot: Array) -> String:
	if slot.size() < 2:
		return "—"
	if slot[0] == "mouse":
		match int(slot[1]):
			MOUSE_BUTTON_LEFT: return "CLIC G"
			MOUSE_BUTTON_RIGHT: return "CLIC D"
			MOUSE_BUTTON_MIDDLE: return "CLIC M"
			MOUSE_BUTTON_WHEEL_UP: return "MOLETTE ↑"
			MOUSE_BUTTON_WHEEL_DOWN: return "MOLETTE ↓"
			MOUSE_BUTTON_XBUTTON1: return "SOURIS 4"
			MOUSE_BUTTON_XBUTTON2: return "SOURIS 5"
		return "SOURIS %d" % int(slot[1])
	if int(slot[1]) >= KEY_0 and int(slot[1]) <= KEY_9:
		return str(int(slot[1]) - KEY_0)
	var kc: Key = KEY_NONE
	if DisplayServer.get_name() != "headless":
		kc = DisplayServer.keyboard_get_label_from_physical(int(slot[1]))
	if kc == KEY_NONE:
		kc = int(slot[1]) as Key
	var name := OS.get_keycode_string(kc).to_upper()
	const FR := {"UP": "↑", "DOWN": "↓", "LEFT": "←", "RIGHT": "→", "SPACE": "ESPACE", "SHIFT": "MAJ",
		"ENTER": "ENTRÉE", "BACKSPACE": "RETOUR", "CAPSLOCK": "VERR. MAJ", "DELETE": "SUPPR", "INSERT": "INSER"}
	return FR.get(name, name)


## Label of the first bound slot of an action, in the user's keyboard layout
## (so "bandage" shows "A" on AZERTY).
func key_label(action: String) -> String:
	if action == "pause":
		return "ÉCHAP"
	for slot in bindings.get(action, []):
		if not slot.is_empty():
			return slot_label(slot)
	return "?"

# ---------------------------------------------------------------- settings

func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	player_name = cfg.get_value("player", "name", player_name)
	mouse_sensitivity = cfg.get_value("controls", "sensitivity", mouse_sensitivity)
	fov = cfg.get_value("video", "fov", fov)
	quality = cfg.get_value("video", "quality", quality)
	_quality_saved = cfg.has_section_key("video", "quality")
	fullscreen = cfg.get_value("video", "fullscreen", fullscreen)
	vsync = cfg.get_value("video", "vsync", vsync)
	max_fps = cfg.get_value("video", "max_fps", max_fps)
	last_ip = cfg.get_value("net", "last_ip", last_ip)
	kill_cam = cfg.get_value("gameplay", "kill_cam", kill_cam)
	music_volume = cfg.get_value("audio", "music", music_volume)
	loadout = ArmorKit.sanitize(cfg.get_value("player", "loadout", {}))
	sfx_volume = cfg.get_value("audio", "sfx", sfx_volume)
	config.team_size = cfg.get_value("match", "team_size", config.team_size)
	config.rounds_to_win = cfg.get_value("match", "rounds_to_win", config.rounds_to_win)
	config.map = cfg.get_value("match", "map", config.map)
	config.mode = clampi(int(cfg.get_value("match", "mode", config.mode)), 0, MODE_NAMES.size() - 1)
	config.difficulty = clampi(int(cfg.get_value("match", "difficulty", config.difficulty)), 0, 3)
	config.br_bots = clampi(int(cfg.get_value("match", "br_bots", config.br_bots)), 0, 19)
	config.team_size = clampi(int(config.team_size), 1, MAX_TEAM)
	# Older settings had a single "bots" checkbox: off = humans only.
	var old_bots: bool = cfg.get_value("match", "bots", true)
	for t in 2:
		config["bots_%d" % t] = cfg.get_value("match", "bots_%d" % t, -1 if old_bots else 0)
	for k in CROSSHAIR_DEFAULT:
		var v = cfg.get_value("crosshair", k, CROSSHAIR_DEFAULT[k])
		if typeof(v) == typeof(CROSSHAIR_DEFAULT[k]) or (v is float and CROSSHAIR_DEFAULT[k] is float):
			crosshair[k] = v
	var input_version: int = cfg.get_value("meta", "input_version", 1)
	for action in DEFAULT_BINDINGS:
		if action == "shoulder" and input_version < 2:
			continue
		# 1 = weapon, 2-5 = items since input version 4.
		if (action == "weapon" or action.begins_with("slot_")) and input_version < 4:
			continue
		var saved = cfg.get_value("input", action) if cfg.has_section_key("input", action) else null
		if saved is Array and saved.size() == 2:
			bindings[action] = saved
	apply_bindings()
	apply_video()


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("player", "name", player_name)
	cfg.set_value("controls", "sensitivity", mouse_sensitivity)
	cfg.set_value("video", "fov", fov)
	cfg.set_value("video", "quality", quality)
	cfg.set_value("video", "fullscreen", fullscreen)
	cfg.set_value("video", "vsync", vsync)
	cfg.set_value("video", "max_fps", max_fps)
	cfg.set_value("net", "last_ip", last_ip)
	cfg.set_value("gameplay", "kill_cam", kill_cam)
	cfg.set_value("audio", "music", music_volume)
	cfg.set_value("player", "loadout", loadout)
	cfg.set_value("audio", "sfx", sfx_volume)
	cfg.set_value("match", "team_size", config.team_size)
	cfg.set_value("match", "rounds_to_win", config.rounds_to_win)
	cfg.set_value("match", "map", config.map)
	cfg.set_value("match", "mode", config.mode)
	cfg.set_value("match", "difficulty", config.difficulty)
	cfg.set_value("match", "br_bots", config.br_bots)
	cfg.set_value("match", "bots_0", config.bots_0)
	cfg.set_value("match", "bots_1", config.bots_1)
	cfg.set_value("meta", "input_version", 4)
	for k in crosshair:
		cfg.set_value("crosshair", k, crosshair[k])
	for action in bindings:
		cfg.set_value("input", action, bindings[action])
	cfg.save(SETTINGS_PATH)


var _quality_saved := false


## True on the OpenGL fallback renderer (no dedicated GPU / no Vulkan / no D3D12).
func is_compat_renderer() -> bool:
	return RenderingServer.get_current_rendering_method() == "gl_compatibility"


## First launch: pick the quality from the GPU (integrated or fallback renderer
## -> Bas, otherwise Élevé). An explicit choice in the options always wins.
func _auto_quality() -> void:
	if debug.has("quality"):
		return
	var integrated := RenderingServer.get_video_adapter_type() in [RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU, RenderingDevice.DEVICE_TYPE_CPU]
	if is_compat_renderer():
		quality = 0
	elif not _quality_saved:
		quality = 0 if integrated else 2
	print("[VIDEO] %s (%s) rendu=%s qualité=%s" % [RenderingServer.get_video_adapter_name(), "intégrée" if integrated else "dédiée",
		RenderingServer.get_current_rendering_method(), QUALITY_NAMES[quality]])


func apply_video() -> void:
	# Classic V-Sync in a window (DWM, mixed-refresh monitors) drops to 30 FPS
	# as soon as one frame misses the refresh: "smooth" (mailbox) renders freely
	# and shows the latest frame at each refresh, without tearing.
	var vs := int(debug.get("vsync", vsync))
	DisplayServer.window_set_vsync_mode([DisplayServer.VSYNC_DISABLED, DisplayServer.VSYNC_MAILBOX, DisplayServer.VSYNC_ENABLED][clampi(vs, 0, 2)])
	Engine.max_fps = int(debug.get("max_fps", max_fps))
	# Per-quality viewport: Bas renders 3D at 75 % with FSR upscaling and no TAA
	# (integrated GPUs); shadow map resolution follows the quality.
	var root := get_tree().root
	var q := clampi(quality, 0, 3)
	root.use_taa = q >= 1 and not is_compat_renderer()
	root.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if q == 0 and not is_compat_renderer() else Viewport.SCALING_3D_MODE_BILINEAR
	root.scaling_3d_scale = 0.75 if q == 0 else 1.0
	root.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if q == 0 else Viewport.SCREEN_SPACE_AA_DISABLED
	RenderingServer.directional_shadow_atlas_set_size([2048, 4096, 4096, 8192][q], true)
	if debug.has("screenshot"):
		return
	# Exclusive fullscreen bypasses the desktop compositor (best frame pacing).
	var mode := DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != mode:
		DisplayServer.window_set_mode(mode)


func map_info(id: String) -> Dictionary:
	for m in MAPS:
		if m.id == id:
			return m
	return MAPS[0]


# ---------------------------------------------------------------- cmdline / debug

func _parse_cmdline() -> void:
	for arg in OS.get_cmdline_user_args():
		var a: String = arg.trim_prefix("--")
		var parts := a.split("=", true, 1)
		debug[parts[0]] = parts[1] if parts.size() > 1 else true
	if debug.has("map"):
		config.map = str(debug.map)
	if debug.has("team_size"):
		config.team_size = clampi(int(debug.team_size), 1, MAX_TEAM)
	# --bots=a,b : bots on team 0 and team 1 (-1 = fill).
	if debug.has("bots"):
		var nb := str(debug.bots).split(",")
		config.bots_0 = int(nb[0])
		config.bots_1 = int(nb[1]) if nb.size() > 1 else int(nb[0])
	if debug.has("rounds"):
		config.rounds_to_win = int(debug.rounds)
	if debug.has("quality"):
		quality = int(debug.quality)
	if debug.has("timescale"):
		Engine.time_scale = float(debug.timescale)
	# --skin=N --weapon=N: force the local outfit (tests).
	for k in ["skin", "weapon"]:
		if debug.has(k):
			loadout[k] = int(debug[k])
	# --mode=tdm|br|ph  --difficulty=0..3  --br_bots=N  (tests)
	if debug.has("mode"):
		config.mode = {"tdm": 0, "br": 1, "ph": 2, "zombie": 3}.get(str(debug.mode), int(str(debug.mode)) if str(debug.mode).is_valid_int() else 0)
	if debug.has("difficulty"):
		config.difficulty = clampi(int(debug.difficulty), 0, 3)
	if debug.has("br_bots"):
		config.br_bots = clampi(int(debug.br_bots), 0, 19)
	loadout = ArmorKit.sanitize(loadout)


func _start_debug_solo() -> void:
	start_solo()


## --host --autostart=N : host, then launch once N players are in the lobby.
func _start_debug_host() -> void:
	host_game()
	var need := int(debug.get("autostart", 2))
	lobby_changed.connect(func():
		if not in_match and lobby.size() >= need:
			begin_match())


# ---------------------------------------------------------------- networking

func is_online() -> bool:
	return not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer)


func start_solo() -> void:
	_reset_peer()
	lobby = {1: {"name": player_name, "team": 0, "loadout": loadout}}
	begin_match()


func host_game(port: int = DEFAULT_PORT) -> Error:
	_reset_peer()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_CLIENTS)
	if err != OK:
		return err
	_tune_peer(peer)
	multiplayer.multiplayer_peer = peer
	lobby = {1: {"name": player_name, "team": 0, "loadout": loadout}}
	lobby_changed.emit()
	_start_upnp(port)
	return OK


## Same setting on both ends: range-coder compression (smaller snapshots).
func _tune_peer(peer: ENetMultiplayerPeer) -> void:
	peer.host.compress(ENetConnection.COMPRESS_RANGE_CODER)


## Round-trip time to the host in ms (0 when hosting / offline).
func ping_ms() -> int:
	var peer := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if peer == null or multiplayer.is_server():
		return 0
	var p := peer.get_peer(1)
	if p == null:
		return 0
	return int(p.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME))


## LAN addresses of this machine (for friends on the same network / a VPN).
func local_ips() -> PackedStringArray:
	var out := PackedStringArray()
	for a in IP.get_local_addresses():
		if a.begins_with("192.168.") or a.begins_with("10.") or a.begins_with("172.") or a.begins_with("26.") or a.begins_with("100."):
			if not out.has(a):
				out.append(a)
	return out


# ---------------------------------------------------------------- UPnP (auto port forward)

var _upnp: UPNP
var _upnp_thread: Thread
var _upnp_port := 0
## Public IP found through UPnP ("" if unknown).
var public_ip := ""


func _start_upnp(port: int) -> void:
	if _upnp_thread or debug.has("no_upnp"):
		return
	status_message.emit("Salon ouvert. Ouverture automatique du port UDP %d (UPnP)…" % port)
	_upnp_thread = Thread.new()
	_upnp_thread.start(_upnp_work.bind(port))


func _upnp_work(port: int) -> void:
	var u := UPNP.new()
	var ok := false
	var ext := ""
	if u.discover(2000, 2, "InternetGatewayDevice") == UPNP.UPNP_RESULT_SUCCESS and u.get_gateway() and u.get_gateway().is_valid_gateway():
		ok = u.add_port_mapping(port, port, "Ferro Arena", "UDP", 0) == UPNP.UPNP_RESULT_SUCCESS
		ext = u.query_external_address()
	_upnp_done.call_deferred(u, ok, ext, port)


func _upnp_done(u: UPNP, ok: bool, ext: String, port: int) -> void:
	_upnp_thread.wait_to_finish()
	_upnp_thread = null
	public_ip = ext
	if ok:
		_upnp = u
		_upnp_port = port
		print("[NET] UPnP: port UDP %d ouvert, IP publique %s" % [port, ext])
	if not multiplayer.is_server() or not is_online():
		_release_upnp()
		return
	var lan := ", ".join(local_ips())
	if ok:
		status_message.emit("Salon ouvert. Port UDP %d ouvert automatiquement. Donnez à vos amis votre IP publique : %s  (réseau local : %s)" % [port, ext, lan])
	else:
		status_message.emit("Salon ouvert, mais la box n'a pas ouvert le port automatiquement. Ouvrez le port UDP %d vers ce PC (ou utilisez un VPN de jeu). IP locale : %s" % [port, lan])
	lobby_changed.emit()


func _release_upnp() -> void:
	if _upnp and _upnp_port > 0:
		_upnp.delete_port_mapping(_upnp_port, "UDP")
	_upnp = null
	_upnp_port = 0


func _exit_tree() -> void:
	if _upnp_thread:
		_upnp_thread.wait_to_finish()
	_release_upnp()


func join_game(ip: String, port: int = DEFAULT_PORT) -> Error:
	_reset_peer()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, port)
	if err != OK:
		return err
	_tune_peer(peer)
	multiplayer.multiplayer_peer = peer
	last_ip = ip
	save_settings()
	return OK


func leave_session(message := "") -> void:
	_reset_peer()
	lobby.clear()
	in_match = false
	pending_message = message
	Engine.time_scale = 1.0
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = false
	get_tree().change_scene_to_file(MENU_SCENE)


func _reset_peer() -> void:
	if multiplayer.multiplayer_peer and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_release_upnp()
	ready_peers.clear()


func _on_peer_connected(_id: int) -> void:
	pass


func _on_peer_disconnected(id: int) -> void:
	if not multiplayer.is_server():
		return
	if lobby.has(id):
		var who: String = lobby[id].name
		lobby.erase(id)
		ready_peers.erase(id)
		status_message.emit("%s s'est déconnecté" % who)
		_broadcast_lobby()
	var arena := get_tree().current_scene
	if in_match and arena and arena.has_method("on_peer_left"):
		arena.on_peer_left(id)


func _on_connected_to_server() -> void:
	print("[NET] connecté au serveur (id %d)" % multiplayer.get_unique_id())
	_register.rpc_id(1, player_name, loadout, GAME_VERSION)


func _on_connection_failed() -> void:
	_reset_peer()
	status_message.emit("Connexion impossible : vérifiez l'IP, que l'hôte a bien ouvert le salon et que le port UDP %d est ouvert chez lui." % DEFAULT_PORT)


func _on_server_disconnected() -> void:
	leave_session("L'hôte a fermé la partie.")


@rpc("any_peer", "reliable")
func _register(pname: String, p_loadout: Dictionary = {}, version := "") -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if version != GAME_VERSION:
		_rejected.rpc_id(id, "Version différente de l'hôte (hôte %s, vous %s). Utilisez la même version du jeu." % [GAME_VERSION, version if version != "" else "?"])
		return
	if in_match:
		_rejected.rpc_id(id, "Partie déjà en cours.")
		return
	var counts := team_counts()
	var team := 0 if counts[0] <= counts[1] else 1
	lobby[id] = {"name": pname.strip_edges().substr(0, 16), "team": team, "loadout": ArmorKit.sanitize(p_loadout)}
	print("[NET] %s a rejoint (peer %d, équipe %d)" % [lobby[id].name, id, team])
	status_message.emit("%s a rejoint" % lobby[id].name)
	_broadcast_lobby()


@rpc("authority", "reliable")
func _rejected(reason: String) -> void:
	leave_session(reason)


@rpc("any_peer", "call_local", "reliable")
func request_team_switch() -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if id == 0:
		id = 1
	if not lobby.has(id):
		return
	var other: int = 1 - int(lobby[id].team)
	if team_counts()[other] >= int(config.team_size):
		return
	lobby[id].team = other
	_broadcast_lobby()


## Local outfit changed (menu or pause): save, tell the host, update in-match.
func set_loadout(l: Dictionary) -> void:
	loadout = ArmorKit.sanitize(l)
	save_settings()
	var me := multiplayer.get_unique_id()
	if lobby.has(me):
		lobby[me].loadout = loadout
	if is_online() and not multiplayer.is_server():
		_update_loadout.rpc_id(1, loadout)
	elif is_online():
		_broadcast_lobby()


@rpc("any_peer", "reliable")
func _update_loadout(l: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if lobby.has(id):
		lobby[id].loadout = ArmorKit.sanitize(l)
		_broadcast_lobby()


## Bots a team gets given its human count: the host's choice, capped by the free
## places, and never an empty team.
func bots_for(t: int, humans: int) -> int:
	var want := int(config.get("bots_%d" % t, -1))
	var room := maxi(0, int(config.team_size) - humans)
	var n := room if want < 0 else mini(want, room)
	if humans + n < 1:
		n = 1
	return n


func team_counts() -> Array:
	var c := [0, 0]
	for id in lobby:
		c[lobby[id].team] += 1
	return c


func set_config(key: String, value) -> void:
	config[key] = value
	if multiplayer.is_server():
		_broadcast_lobby()


func _broadcast_lobby() -> void:
	if is_online():
		_set_lobby.rpc(lobby, config)
	lobby_changed.emit()


@rpc("authority", "reliable")
func _set_lobby(new_lobby: Dictionary, new_config: Dictionary) -> void:
	lobby = new_lobby
	config = new_config
	lobby_changed.emit()


# ---------------------------------------------------------------- match flow

func begin_match() -> void:
	if not multiplayer.is_server():
		return
	if is_online():
		_load_match.rpc(lobby, config)
	else:
		_load_match(lobby, config)


@rpc("authority", "call_local", "reliable")
func _load_match(new_lobby: Dictionary, new_config: Dictionary) -> void:
	lobby = new_lobby
	config = new_config
	in_match = true
	ready_peers.clear()
	get_tree().change_scene_to_file(ARENA_SCENE)


## Called by the arena once its map is built.
func notify_arena_ready() -> void:
	if multiplayer.is_server():
		_mark_ready(1)
	else:
		_client_ready.rpc_id(1)


@rpc("any_peer", "reliable")
func _client_ready() -> void:
	if multiplayer.is_server():
		_mark_ready(multiplayer.get_remote_sender_id())


func _mark_ready(id: int) -> void:
	ready_peers[id] = true
	print("[NET] arène prête: peer %d (%d/%d)" % [id, ready_peers.size(), lobby.size()])
	for pid in lobby:
		if not ready_peers.has(pid):
			return
	all_peers_ready.emit()


func back_to_lobby() -> void:
	in_match = false
	Engine.time_scale = 1.0
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file(MENU_SCENE)
