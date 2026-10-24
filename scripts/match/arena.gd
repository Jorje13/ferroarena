class_name Arena
extends Node3D
## Match scene root: builds the map, spawns players (MultiplayerSpawner),
## owns the camera, HUD, spectating and the bots' navmesh.

const PLAYER_SCENE := preload("res://scenes/player.tscn")

var map: MapBase
var camera_rig: CameraRig
var hud: Hud
var local_player: Player
var local_team := 0
var players: Array[Player] = []
var chests: Array[LootChest] = []
var grenades: Array = []
var smokes: Array = []
var barricades := {}
var _barricade_seq := 0
var _loot_rng := RandomNumberGenerator.new()

var _nav_region: NavigationRegion3D
## Mode helpers (null outside their mode): prop hunt rules, battle royale zone.
var prop_hunt: PropHunt
var zone: BattleZone
var monsters: MonsterManager
## Final-image shader (sharpening, aberration), tuned by the camera while aiming.
var post_mat: ShaderMaterial

@onready var players_root: Node3D = $Players
@onready var spawner: MultiplayerSpawner = $PlayerSpawner
@onready var match_mgr: MatchManager = $Match


func _ready() -> void:
	spawner.spawn_function = _spawn_player
	var me: Dictionary = Game.lobby.get(multiplayer.get_unique_id(), {})
	local_team = 0 if Game.is_zombie() else int(me.get("team", 0))

	var info := Game.map_info(str(Game.config.map))
	map = load(info.script).new()
	map.name = "Map"
	add_child(map)
	map.build(Game.quality)
	Audio.start_ambience(map.biome)

	camera_rig = CameraRig.new()
	camera_rig.name = "CameraRig"
	add_child(camera_rig)
	var sp := map.get_spawn(local_team, 0, 1)
	camera_rig.global_position = sp.pos + Vector3(0, 1.6, 0)
	camera_rig.rotation.y = sp.yaw
	if not Game.is_ph():
		_build_chests()
	if Game.is_ph():
		prop_hunt = PropHunt.new()
		prop_hunt.name = "PropHunt"
		add_child(prop_hunt)
	elif Game.is_ffa():
		zone = BattleZone.new()
		zone.name = "Zone"
		add_child(zone)
	elif Game.is_zombie():
		monsters = MonsterManager.new()
		monsters.name = "Monsters"
		add_child(monsters)
	var weather := map.make_weather()
	if weather:
		camera_rig.add_child(weather)

	if Game.quality >= 1:
		var post := CanvasLayer.new()
		post.name = "PostFX"
		post.layer = 1
		var rect := ColorRect.new()
		rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var pm := ShaderMaterial.new()
		pm.shader = load("res://shaders/post_fx.gdshader")
		rect.material = pm
		post_mat = pm
		post.add_child(rect)
		add_child(post)

	hud = Hud.new()
	hud.name = "Hud"
	add_child(hud)
	hud.setup(self)

	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if multiplayer.is_server():
		_bake_navigation()
		Game.all_peers_ready.connect(_on_all_ready, CONNECT_ONE_SHOT)
	Game.notify_arena_ready()
	if Game.debug.has("screenshot"):
		_debug_screenshot()


# ---------------------------------------------------------------- loot / items

func _build_chests() -> void:
	# Let the physics server register the freshly built map before raycasting.
	await get_tree().physics_frame
	var space := get_world_3d().direct_space_state
	var spots := map.all_loot_spots()
	for i in spots.size():
		var s: Vector3 = spots[i]
		var g := map.height_at(s.x, s.z)
		var from := Vector3(s.x, g + (1.4 if s.y < 0.5 else 5.5), s.z)
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 12.0, 1))
		var c := LootChest.new()
		c.index = i
		c.name = "Chest%d" % i
		add_child(c)
		c.global_position = hit.position if hit else Vector3(s.x, g, s.z)
		c.rotation.y = fmod(i * 1.7, TAU)
		chests.append(c)


## Server, at each round start: pick random chest pairs, clear thrown/placed items.
func server_round_reset() -> void:
	if chests.is_empty():
		net_round_reset.rpc([], {})
		return
	_loot_rng.randomize()
	var pairs := chests.size() / 2
	var order := range(pairs)
	for i in range(order.size() - 1, 0, -1):
		var j := _loot_rng.randi_range(0, i)
		var t = order[i]
		order[i] = order[j]
		order[j] = t
	# More raiders, more crates: 5 pairs for a 2v2 up to 9 for a 10v10.
	var want := clampi(4 + match_mgr.roster.size() / 4, 4, pairs)
	var active := []
	var specials := {}
	for k in want:
		active.append(order[k] * 2)
		active.append(order[k] * 2 + 1)
		# The first two pairs hide an attachment, one per side of the map (fair).
		if k < 2:
			specials[order[k] * 2] = "silencer" if k == 0 else "stock"
			specials[order[k] * 2 + 1] = "silencer" if k == 0 else "stock"
	net_round_reset.rpc(active, specials)


@rpc("authority", "call_local", "reliable")
func net_round_reset(active: Array, specials: Dictionary) -> void:
	if camera_rig:
		camera_rig.stop_kill_cam(true)
	if hud:
		hud.hide_kill_cam()
	for c in chests:
		c.set_active(active.has(c.index), specials.get(c.index, ""))
	for b in barricades.values():
		if is_instance_valid(b):
			b.queue_free()
	barricades.clear()
	for g in grenades.duplicate():
		if is_instance_valid(g):
			g.queue_free()
	for s in smokes.duplicate():
		if is_instance_valid(s):
			s.queue_free()


## Closest lootable chest within `reach` the player is roughly facing.
func chest_for(p: Player, reach := 2.2) -> LootChest:
	var best: LootChest = null
	var best_d := reach
	var fwd := p.look_direction()
	fwd.y = 0.0
	fwd = fwd.normalized()
	for c in chests:
		if not c.can_loot():
			continue
		var to := c.global_position - p.global_position
		to.y = 0.0
		var d := to.length()
		if d < best_d and (d < 0.9 or fwd.dot(to.normalized()) > 0.3):
			best_d = d
			best = c
	return best


func nearest_chest(pos: Vector3, max_d: float) -> LootChest:
	var best: LootChest = null
	var best_d := max_d
	for c in chests:
		if c.can_loot() and c.global_position.distance_to(pos) < best_d:
			best_d = c.global_position.distance_to(pos)
			best = c
	return best


@rpc("authority", "call_local", "reliable")
func net_chest_opened(idx: int) -> void:
	if idx >= 0 and idx < chests.size():
		chests[idx].set_opened()


@rpc("authority", "call_local", "reliable")
func net_spawn_grenade(thrower_name: String, kind: String, origin: Vector3, vel: Vector3) -> void:
	var p := get_player(thrower_name)
	if p == null:
		return
	var rg = p.get("rig")
	if rg:
		rg.play_throw()
	if p.is_multiplayer_authority():
		return # the thrower's machine already spawned it
	Grenade.spawn(p, kind, origin, vel, multiplayer.is_server())


func server_spawn_barricade(xf: Transform3D, team_id: int) -> void:
	_barricade_seq += 1
	net_spawn_barricade.rpc(_barricade_seq, xf, team_id)


@rpc("authority", "call_local", "reliable")
func net_spawn_barricade(id: int, xf: Transform3D, team_id: int) -> void:
	var b := Barricade.create(id, xf, team_id)
	add_child(b)
	barricades[id] = b


@rpc("authority", "call_local", "reliable")
func net_barricade_destroyed(id: int) -> void:
	var b: Barricade = barricades.get(id)
	barricades.erase(id)
	if b and is_instance_valid(b):
		b.destroy_fx()
		b.queue_free()


func server_barricade_hit(id: int, amount: float) -> void:
	var b: Barricade = barricades.get(id)
	if b and is_instance_valid(b):
		b.server_damage(amount)


## All peers: camera shake for the watched player.
func on_explosion(pos: Vector3) -> void:
	var t := camera_rig.target
	if t and is_instance_valid(t):
		var d := t.global_position.distance_to(pos)
		if d < 25.0:
			camera_rig.kick(clampf(1.6 - d / 15.0, 0.15, 1.6))
		if d < 14.0 and hud:
			hud.screen_flash(clampf(1.0 - d / 14.0, 0.0, 1.0))


## Server: frag damage with falloff, blocked by walls / barricades.
func server_explosion_damage(thrower: Player, pos: Vector3) -> void:
	var space := get_world_3d().direct_space_state
	var origin := pos + Vector3(0, 0.25, 0)
	for p: Player in players:
		if not p.is_hittable() or (p.team == thrower.team and p != thrower):
			continue
		var target := p.chest_position()
		var d := origin.distance_to(target)
		if d > Items.FRAG_RADIUS:
			continue
		var q := PhysicsRayQueryParameters3D.create(origin, target, 1)
		if space.intersect_ray(q):
			continue
		var t := clampf((d - Items.FRAG_FULL_RADIUS) / (Items.FRAG_RADIUS - Items.FRAG_FULL_RADIUS), 0.0, 1.0)
		var dmg := lerpf(Items.FRAG_MAX_DAMAGE, Items.FRAG_MIN_DAMAGE, t)
		if p == thrower:
			dmg *= 0.5
		p.server_apply_damage(dmg, thrower, false, "GRENADE")
	if monsters:
		monsters.server_explosion(thrower, pos)
	for b in barricades.values():
		if is_instance_valid(b) and b.global_position.distance_to(pos) < 6.5:
			b.server_damage(lerpf(150.0, 30.0, b.global_position.distance_to(pos) / 6.5))


## True if a smoke cloud blocks the segment a -> b (used by bots).
## True when a smoke cloud hides b from a. Same ellipsoid as the cloud's fog
## volume (wide and flat, centred 1.6 m up), so bots are blind exactly where a
## player sees thick smoke, edges included; standing inside it blinds too.
func is_sight_blocked(a: Vector3, b: Vector3) -> bool:
	for s in smokes:
		if not is_instance_valid(s) or not s.blocks():
			continue
		var r: float = s.radius() * 1.08
		var squash := 2.4 / 1.4 # fog volume: 2.4 R wide, 1.4 R tall
		var c: Vector3 = s.global_position + Vector3(0, 1.6, 0)
		# Work in a space where the ellipsoid is a sphere of radius r.
		var a2 := Vector3(a.x - c.x, (a.y - c.y) * squash, a.z - c.z)
		var b2 := Vector3(b.x - c.x, (b.y - c.y) * squash, b.z - c.z)
		var ab := b2 - a2
		var t := clampf(-a2.dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		if (a2 + ab * t).length() < r:
			return true
	return false


func _on_all_ready() -> void:
	match_mgr.server_begin()


func _spawn_player(data: Dictionary) -> Node:
	var p := PLAYER_SCENE.instantiate() as Player
	p.name = data.node
	p.player_id = data.id
	p.display_name = data.name
	p.team = data.team
	p.is_bot = data.bot
	p.loadout = data.get("loadout", {})
	p.position = data.pos
	p.look_yaw = data.yaw
	p.body_yaw = data.yaw
	p.set_multiplayer_authority(1 if data.bot else int(data.id))
	# Big matches: halve the snapshot rate (20 raiders at 60 Hz would flood the host's upload).
	var sync := p.get_node_or_null("Sync") as MultiplayerSynchronizer
	if sync and int(data.get("total", 0)) > 10:
		sync.replication_interval = 0.033
	return p


# ---------------------------------------------------------------- registry

func _exit_tree() -> void:
	Audio.stop_ambience()


func register_player(p: Player) -> void:
	if not players.has(p):
		players.append(p)


func unregister_player(p: Player) -> void:
	players.erase(p)


func register_local_player(p: Player) -> void:
	local_player = p
	local_team = p.team
	camera_rig.target = p
	hud.bind_local(p)


func get_player(node_name: String) -> Player:
	return players_root.get_node_or_null(node_name) as Player


func on_peer_left(id: int) -> void:
	var node := players_root.get_node_or_null("P%d" % id)
	if node:
		node.queue_free()
		match_mgr.server_on_player_left("P%d" % id)


# ---------------------------------------------------------------- rules

func match_allows_movement() -> bool:
	return match_mgr.state == MatchManager.State.LIVE or match_mgr.state == MatchManager.State.ROUND_END


func match_allows_fire() -> bool:
	return match_mgr.state == MatchManager.State.LIVE


## Per-player gates: prop hunt freezes the hunter while the props hide, and only he may shoot.
func can_move_for(p: Player) -> bool:
	if not match_allows_movement():
		return false
	return not (prop_hunt and p.team == 0 and prop_hunt.in_hiding_phase())


func can_fight_for(p: Player) -> bool:
	if not match_allows_fire():
		return false
	if prop_hunt:
		return p.team == 0 and not prop_hunt.in_hiding_phase()
	return true


func input_blocked() -> bool:
	return hud.is_menu_open() or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED


# ---------------------------------------------------------------- spectating

func on_local_death(_p: Player, killer_name: String) -> void:
	hud.on_local_death(killer_name)
	get_tree().create_timer(2.5).timeout.connect(_spectate_when_ready)


func _spectate_when_ready() -> void:
	if local_player == null or local_player.alive or local_player.downed:
		return
	# Let the kill cam finish first.
	if camera_rig.kill_cam_active():
		get_tree().create_timer(0.4).timeout.connect(_spectate_when_ready)
		return
	spectate_next()


func on_local_down(_p: Player, attacker_name: String) -> void:
	hud.on_local_down(attacker_name)


func on_local_respawn(p: Player) -> void:
	camera_rig.target = p
	camera_rig.stop_kill_cam(true)
	hud.hide_kill_cam()
	hud.set_spectating(null)


var _last_kill_cam := -100.0


## The local raider went down / was finished: fly the fatal shot (origin -> impact).
## Other damage (grenades) gets a look at the spot from above instead.
func start_kill_cam(killer: Player, origin: Vector3, hit: Vector3, weapon: String, headshot: bool) -> void:
	if not Game.kill_cam or camera_rig == null or hud == null or Game.debug.has("no_killcam"):
		return
	var now := Time.get_ticks_msec() * 0.001
	if now - _last_kill_cam < 6.0 or match_mgr.state != MatchManager.State.LIVE:
		return
	_last_kill_cam = now
	var who := killer.display_name if killer else "?"
	var dist := origin.distance_to(hit)
	if weapon != "FERRO":
		origin = hit
	camera_rig.start_kill_cam(origin, hit, who)
	hud.show_kill_cam(who, dist if weapon == "FERRO" else -1.0, headshot, weapon)
	Audio.play_2d("killcam_in", -4.0)


func spectate_next() -> void:
	var candidates: Array[Player] = []
	for p in players:
		if p.alive and p.team == local_team and p != local_player:
			candidates.append(p)
	if candidates.is_empty():
		for p in players:
			if p.alive:
				candidates.append(p)
	if candidates.is_empty():
		return
	var idx := candidates.find(camera_rig.target)
	var next := candidates[(idx + 1) % candidates.size()]
	camera_rig.target = next
	hud.set_spectating(next if next != local_player else null)


var _perf_t := 0.0


func _process(delta: float) -> void:
	_debug_tick(delta)
	# --perf_log: every 5 s, frame cost + bot AI cost + live smoke trails.
	# --perf_off=anim,players,mm,props,hud,particles,env: switch blocks off (perf bisection).
	if Game.debug.has("perf_off") and _perf_t > 3.0 and not has_meta("perf_off_done"):
		set_meta("perf_off_done", true)
		var what := str(Game.debug.perf_off).split(",")
		for p in players:
			if "anim" in what:
				p.rig.anim.active = false
			if "players" in what:
				p.rig.visible = false
		for n in get_tree().root.find_children("*", "MultiMeshInstance3D", true, false):
			if "mm" in what:
				(n as Node3D).visible = false
		for n in get_tree().root.find_children("*", "GPUParticles3D", true, false):
			if "particles" in what:
				(n as Node3D).visible = false
		if "props" in what:
			map.props_root.visible = false
		if "map" in what:
			for c in map.get_children():
				if c is Node3D and not (c is DirectionalLight3D):
					(c as Node3D).visible = false
		if "hud" in what:
			hud.visible = false
		if "env" in what:
			var env: Environment = map.environment_node.environment
			env.volumetric_fog_enabled = false
			env.sdfgi_enabled = false
			env.ssao_enabled = false
			env.ssil_enabled = false
			env.glow_enabled = false
			map.sun.shadow_enabled = false
		print("[PERF] off: ", what)
	if Game.debug.has("perf_log"):
		var vp := get_viewport().get_viewport_rid()
		if _perf_t == 0.0:
			RenderingServer.viewport_set_measure_render_time(vp, true)
		_perf_t += delta
		if _perf_t > 5.0:
			_perf_t = 0.0001
			print("[PERF5] fps=%d frame=%.1fms process=%.1fms physics=%.1fms render_cpu=%.1fms gpu=%.1fms draws=%d prims=%dk bots=%.2fms/frame" % [Engine.get_frames_per_second(),
				1000.0 / maxf(Engine.get_frames_per_second(), 1.0),
				Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
				RenderingServer.viewport_get_measured_render_time_cpu(vp) + RenderingServer.get_frame_setup_time_cpu(),
				RenderingServer.viewport_get_measured_render_time_gpu(vp),
				Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1000,
				BotBrain.cost_us / 1000.0 / maxf(5.0 * Engine.physics_ticks_per_second, 1.0)])
			BotBrain.cost_us = 0
			var frames := maxf(Engine.get_frames_per_second() * 5.0, 1.0)
			var parts := []
			for k in Game.prof:
				parts.append("%s=%.2fms" % [k, Game.prof[k] / 1000.0 / frames])
			print("[PROF] per frame: ", " ".join(parts))
			Game.prof.clear()
	var t := camera_rig.target
	if local_player == null:
		if t == null or not is_instance_valid(t) or not t.alive:
			if not players.is_empty():
				spectate_next()
		return
	if t and is_instance_valid(t) and t != local_player and not t.alive and not t.downed:
		spectate_next()


func _unhandled_input(event: InputEvent) -> void:
	# Any action key skips the kill cam (after a short beat so a held button doesn't).
	if camera_rig and camera_rig.kill_cam_active() and camera_rig.kill_cam_time() > 0.8:
		for a in ["fire", "jump", "interact", "crouch", "roll"]:
			if event.is_action_pressed(a):
				camera_rig.stop_kill_cam()
				get_viewport().set_input_as_handled()
				return
	if event.is_action_pressed("fire") and (local_player == null or (not local_player.alive and not local_player.downed)) and not hud.is_menu_open():
		spectate_next()


# ---------------------------------------------------------------- navigation (server, bots)

func _bake_navigation() -> void:
	var nm := NavigationMesh.new()
	nm.agent_radius = 0.42 # the capsule is 0.36: tight doorways and stairs stay walkable for bots
	nm.agent_height = 1.75
	nm.agent_max_climb = 0.5
	nm.agent_max_slope = 40.0
	nm.cell_size = 0.25
	nm.cell_height = 0.25
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_collision_mask = 5
	nm.filter_baking_aabb = map.get_bounds().grow(1.0)
	_nav_region = NavigationRegion3D.new()
	_nav_region.name = "Navigation"
	add_child(_nav_region)
	var src := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(nm, src, map)
	var t0 := Time.get_ticks_msec()
	NavigationServer3D.bake_from_source_geometry_data_async(nm, src, func():
		_nav_region.set_deferred("navigation_mesh", nm)
		print("[NAV] navmesh prêt: %d polygones (%d ms)" % [nm.get_polygon_count(), Time.get_ticks_msec() - t0])
		if Game.debug.has("nav_test"):
			_nav_test.call_deferred())


## --nav_test: can the navmesh get from outside the central building's front door to
## its upper floor (door, doorway width, stairs)? Prints the path found.
func _nav_test() -> void:
	await get_tree().create_timer(1.5).timeout
	var map_rid := get_world_3d().navigation_map
	var from := map.ground(Vector2(0, -9.0))
	var up := Vector3(4.0, map.height_at(0, 0) + MapBase.FLOOR_H + 0.2, -2.5)
	var path := NavigationServer3D.map_get_path(map_rid, from, up, true)
	var len := 0.0
	for i in range(1, path.size()):
		len += path[i].distance_to(path[i - 1])
	var end: Vector3 = path[path.size() - 1] if path.size() > 0 else Vector3.INF
	print("[NAVTEST] porte->étage: %d points, longueur %.1f m, arrivée à %.2f m de la cible (hauteur %.2f)" % [path.size(), len, end.distance_to(up), end.y - map.height_at(0, 0)])
	var gy := map.height_at(0, 0)
	for probe in [["dalle étage", Vector3(4.0, gy + MapBase.FLOOR_H + 0.1, -2.5)], ["bas de l'escalier", Vector3(-0.54, gy + 0.2, 3.35)], ["milieu escalier", Vector3(-3.4, gy + 0.06 + 0.5 * MapBase.FLOOR_H, 3.35)], ["haut escalier", Vector3(-6.8, gy + MapBase.FLOOR_H - 0.05, 3.35)], ["dalle haut escalier", Vector3(-6.9, gy + MapBase.FLOOR_H + 0.1, 3.0)]]:
		var cp := NavigationServer3D.map_get_closest_point(map_rid, probe[1])
		print("[NAVTEST] %s: point navmesh le plus proche à %.2f m (y %.2f, visé %.2f)" % [probe[0], cp.distance_to(probe[1]), cp.y - gy, probe[1].y - gy])
	# Walk up the stairs' centre line (x from the low end west) and see where the mesh stops.
	var line := ""
	for i in 14:
		var sx := -0.3 - i * 0.5
		var sy := gy + 0.06 + (MapBase.FLOOR_H / (MapBase.STAIR_STEPS * MapBase.STAIR_TREAD)) * (-0.3 - sx)
		var sp := Vector3(sx, sy, 3.35)
		var nc := NavigationServer3D.map_get_closest_point(map_rid, sp)
		line += " x%.1f:%.2f/%.2f" % [sx, Vector2(nc.x - sp.x, nc.z - sp.z).length(), nc.y - sp.y]
	print("[NAVTEST] escalier (écart plan/hauteur): ", line)
	var inside := Vector3(0.0, map.height_at(0, 0) + 0.1, 0.0)
	var p2 := NavigationServer3D.map_get_path(map_rid, from, inside, true)
	var e2: Vector3 = p2[p2.size() - 1] if p2.size() > 0 else Vector3.INF
	print("[NAVTEST] porte->intérieur: %d points, arrivée à %.2f m" % [p2.size(), e2.distance_to(inside)])


# ---------------------------------------------------------------- debug

var _dbg_t := 0.0
var _dbg_shots := 0


func _debug_screenshot() -> void:
	set_process(true)


## Counts "smooth" time only (hitches from shader compilation are clamped),
## then saves `--shots` screenshots spaced by `--shot_gap` seconds.
func _debug_tick(delta: float) -> void:
	if not Game.debug.has("screenshot"):
		return
	_dbg_t += minf(delta, 0.05)
	var delay := float(Game.debug.get("shot_delay", 12.0)) + _dbg_shots * float(Game.debug.get("shot_gap", 3.0))
	if _dbg_t < delay:
		if _dbg_t > delay - 0.5 and not has_meta("perf%d" % _dbg_shots):
			set_meta("perf%d" % _dbg_shots, true)
			print("[PERF-pre] fps=%d process=%.2fms physics=%.2fms draw_calls=%d" % [Engine.get_frames_per_second(), Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)])
		return
	var path := str(Game.debug.screenshot).replace(".png", "_%d.png" % _dbg_shots)
	get_viewport().get_texture().get_image().save_png(path)
	print("[DEBUG] capture %s  fps=%d  state=%d  round=%d  t=%.1f" % [path, Engine.get_frames_per_second(), match_mgr.state, match_mgr.round_num, match_mgr.time_left])
	print("[PERF] process=%.2fms physics=%.2fms draw_calls=%d objects=%d nodes=%d prims=%d" % [Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME), Performance.get_monitor(Performance.OBJECT_NODE_COUNT), Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)])
	_dbg_shots += 1
	if _dbg_shots >= int(Game.debug.get("shots", 1)) and not Game.debug.has("keep_running"):
		get_tree().quit()
