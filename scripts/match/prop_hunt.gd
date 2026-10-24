class_name PropHunt
extends Node
## Prop hunt rules, child of the Arena in that mode. One hunter (team 0, picked at random)
## against hiders (team 1) who press [interact] next to a scanned object to turn into it.
## Phase 0: the hunter is frozen and blind while the props hide. Phase 1: he is released
## and every 20 s each hider whistles, which gives him a direction to search in.
## Time lives in MatchManager.time_left (HIDE_TIME + SEEK_TIME); the phase is derived
## from it, so every peer agrees without extra messages.

const HIDE_TIME := 30.0
const SEEK_TIME := 210.0
const WHISTLE_EVERY := 20.0

var hunter := ""
var _next_whistle := WHISTLE_EVERY

@onready var arena: Arena = get_parent() as Arena


## Server, at each round start: remember who hunts.
func server_prepare(hunter_node: String) -> void:
	_net_hunter.rpc(hunter_node)


@rpc("authority", "call_local", "reliable")
func _net_hunter(node: String) -> void:
	hunter = node
	_next_whistle = WHISTLE_EVERY


## Server: the round went live.
func server_go() -> void:
	_next_whistle = WHISTLE_EVERY


func in_hiding_phase() -> bool:
	var mm := arena.match_mgr
	return mm.state == MatchManager.State.LIVE and mm.time_left > SEEK_TIME


## Seconds left to hide (0 once the hunter is out).
func hide_left() -> float:
	return maxf(0.0, arena.match_mgr.time_left - SEEK_TIME)


func hunter_player() -> Player:
	return arena.get_player(hunter) if hunter != "" else null


func hiders_alive() -> int:
	var n := 0
	for p: Player in arena.players:
		if p.team == 1 and p.alive:
			n += 1
	return n


var _dbg_done := false


func _process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	var mm := arena.match_mgr
	# --log_ph: once, ray-test every disguised hider's hit box (must be the prop-sized box).
	if Game.debug.has("log_ph") and mm.state == MatchManager.State.LIVE and not _dbg_done and mm.time_left < SEEK_TIME + HIDE_TIME - 2.0:
		_dbg_done = true
		for p: Player in arena.players:
			if p.team == 1 and p.prop_idx >= 0:
				var c := p.global_position + Vector3(0, 0.3, 0)
				var q := PhysicsRayQueryParameters3D.create(c + Vector3(4, 0.4, 0), c, Hitboxes.LAYER)
				var h := arena.get_world_3d().direct_space_state.intersect_ray(q)
				print("[PH] tir test sur %s (%s) : %s" % [p.display_name, Scan.catalog[p.prop_idx].id, ("touché (" + Hitboxes.zone_of(h.collider) + ")") if h and Hitboxes.player_of(h.collider) == p else "raté"])
	if mm.state != MatchManager.State.LIVE or in_hiding_phase():
		return
	_next_whistle -= delta
	if _next_whistle <= 0.0:
		_next_whistle = WHISTLE_EVERY
		for p: Player in arena.players:
			if p.team == 1 and p.alive:
				p.net_whistle.rpc()
		if Game.debug.has("log_ph"):
			print("[PH] sifflement (%d props en vie)" % hiders_alive())
