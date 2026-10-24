class_name MatchManager
extends Node
## Server-authoritative round loop: countdown at the arena edges, elimination
## rounds, first team to `rounds_to_win` takes the match. Clients mirror state.
## Three modes (Game.config.mode): team elimination (rounds), battle royale (one
## round, every raider alone, a closing zone, last one standing wins) and prop
## hunt (one hunter against props that hide, see PropHunt).

signal state_changed
## kind: FEED_KNOCK (knocked down) or FEED_FINISH (finished while down).
signal kill_feed(killer: String, killer_team: int, victim: String, victim_team: int, headshot: bool, weapon: String, kind: int)

enum { FEED_KNOCK, FEED_FINISH }
signal stats_changed

enum State { WAITING, COUNTDOWN, LIVE, ROUND_END, MATCH_END }

const COUNTDOWN_TIME := 5.0
const ROUND_END_TIME := 5.0
## Battle royale round length (s); the zone closes inside it, see BattleZone.
const BR_TIME := 330.0
const BOT_NAMES := ["Vasquez", "Okafor", "Lindqvist", "Moreau", "Tanaka", "Reyes", "Kowalski", "Haddad",
	"Novak", "Ferreira", "Dubois", "Yilmaz", "Andersen", "Sato", "Mbeki", "Rossi", "Petrov", "Cohen", "Silva", "Larsen"]

var state := State.WAITING
var round_num := 0
var time_left := 0.0
var scores := [0, 0]
var round_winner := -1
var match_winner := -1
## node name -> {name, team, bot, k, d, a, dmg}
var stats := {}
var roster := []

@onready var arena: Arena = get_parent() as Arena


func rounds_to_win() -> int:
	# Battle royale and prop hunt are a single round.
	return int(Game.config.rounds_to_win) if Game.mode() == Game.MODE_TDM else 1


# ---------------------------------------------------------------- server

func server_begin() -> void:
	roster.clear()
	stats.clear()
	match Game.mode():
		Game.MODE_BR:
			_begin_br()
		Game.MODE_PH:
			_begin_ph()
		Game.MODE_ZOMBIE:
			_begin_zombie()
		_:
			_begin_teams()
	for e in roster:
		e.total = roster.size()
		arena.spawner.spawn(e)
	_sync_stats()
	get_tree().create_timer(0.6).timeout.connect(_start_round)


func _human_entries() -> Array:
	var out := []
	var ids := Game.lobby.keys()
	ids.sort()
	for id in ids:
		var e: Dictionary = Game.lobby[id]
		out.append({"node": "P%d" % id, "id": id, "name": e.name, "team": int(e.team), "bot": Game.debug.has("allbots"), "loadout": ArmorKit.sanitize(e.get("loadout", {}))})
	return out


func _bot_entry(bi: int, t: int) -> Dictionary:
	var nm: String = BOT_NAMES[bi % BOT_NAMES.size()]
	return {"node": "B%d" % bi, "id": -1 - bi, "name": nm, "team": t, "bot": true, "loadout": ArmorKit.random_loadout(nm.hash())}


func _register(e: Dictionary) -> void:
	roster.append(e)
	stats[e.node] = {"name": e.name, "team": e.team, "bot": e.bot, "k": 0, "d": 0, "a": 0, "dmg": 0}


func _begin_teams() -> void:
	var per_team := [[], []]
	for e in _human_entries():
		per_team[int(e.team)].append(e)
	var bi := 0
	for t in 2:
		var want: int = per_team[t].size() + Game.bots_for(t, per_team[t].size())
		while per_team[t].size() < want:
			per_team[t].append(_bot_entry(bi, t))
			bi += 1
		for i in per_team[t].size():
			var e: Dictionary = per_team[t][i]
			var sp := arena.map.get_spawn(t, i, per_team[t].size())
			e.pos = sp.pos
			e.yaw = sp.yaw
			_register(e)
	print("[MATCH] %dv%d (%d joueurs, %d bots)" % [per_team[0].size(), per_team[1].size(), roster.size(), bi])


## Battle royale: everyone on a team of one, spread round the map.
func _begin_br() -> void:
	var list := _human_entries()
	var humans := list.size()
	var nb := clampi(int(Game.config.br_bots), 0, 20 - humans)
	if humans + nb < 2:
		nb = 2 - humans
	for bi in nb:
		list.append(_bot_entry(bi, 0))
	for i in list.size():
		var e: Dictionary = list[i]
		e.team = i
		var sp := arena.map.get_spawn_ffa(i, list.size(), int(Game.config.get("seed", 1)))
		e.pos = sp.pos
		e.yaw = sp.yaw
		_register(e)
	print("[MATCH] Battle royale : %d joueurs (%d bots), difficulté %s" % [list.size(), nb, Game.DIFFICULTY_NAMES[int(Game.config.difficulty)]])


## Prop hunt: humans only (--ph_dummy=N adds motionless test hiders). Everyone starts as
## a prop; _start_round names the hunter.
func _begin_ph() -> void:
	var list := _human_entries()
	for bi in int(Game.debug.get("ph_dummy", 0)):
		list.append(_bot_entry(bi, 1))
	for i in list.size():
		var e: Dictionary = list[i]
		e.team = 1
		e.bot = bool(e.bot)
		var sp := arena.map.get_spawn_ffa(i, list.size(), 3)
		e.pos = sp.pos
		e.yaw = sp.yaw
		_register(e)
	print("[MATCH] Prop hunt : %d joueurs" % list.size())


## Zombie survival: every human on the survivors' side (team 0), no bots.
func _begin_zombie() -> void:
	var list := _human_entries()
	for i in list.size():
		var e: Dictionary = list[i]
		e.team = 0
		var sp := arena.map.get_spawn(0, i, list.size())
		e.pos = sp.pos
		e.yaw = sp.yaw
		_register(e)
	print("[MATCH] Survie zombies : %d joueurs" % list.size())


func server_restart() -> void:
	if not multiplayer.is_server():
		return
	scores = [0, 0]
	round_num = 0
	match_winner = -1
	for k in stats:
		for f in ["k", "d", "a", "dmg"]:
			stats[k][f] = 0
	_sync_stats()
	_start_round()


func _start_round() -> void:
	round_num += 1
	round_winner = -1
	arena.server_round_reset()
	match Game.mode():
		Game.MODE_BR:
			for i in roster.size():
				var p := arena.get_player(roster[i].node)
				if p:
					var sp := arena.map.get_spawn_ffa(i, roster.size(), int(Game.config.get("seed", 1)) + round_num)
					p.net_respawn.rpc(sp.pos, sp.yaw)
		Game.MODE_PH:
			_start_ph_round()
		Game.MODE_ZOMBIE:
			arena.monsters.server_reset()
			for i in roster.size():
				var p := arena.get_player(roster[i].node)
				if p:
					var sp := arena.map.get_spawn(0, i, roster.size())
					p.net_respawn.rpc(sp.pos, sp.yaw)
		_:
			var by_team := [[], []]
			for e in roster:
				var p := arena.get_player(e.node)
				if p:
					by_team[e.team].append(p)
			for t in 2:
				for i in by_team[t].size():
					var sp := arena.map.get_spawn(t, i, by_team[t].size())
					by_team[t][i].net_respawn.rpc(sp.pos, sp.yaw)
	for p in arena.players:
		# --give_attach[=silencer|stock]: fit the attachments at round start (tests).
		if Game.debug.has("give_attach"):
			for kind in ["silencer", "stock"]:
				if str(Game.debug.give_attach) in ["1", "true", kind]:
					p.net_attach.rpc(kind)
		if Game.debug.has("give_items"):
			p.net_inventory.rpc([{"id": "frag", "n": 2}, {"id": "smoke", "n": 2}, {"id": "barricade", "n": 1}, {"id": "defib", "n": 1}])
	_set_state(State.COUNTDOWN, COUNTDOWN_TIME)


## Picks the hunter (random human, or --ph_hunter=name), sends the others to the props.
func _start_ph_round() -> void:
	if Game.debug.has("ph_dummy"):
		seed(7)
	var humans := []
	for e in roster:
		if not e.bot:
			humans.append(e)
	var hunter: Dictionary = humans[randi() % humans.size()] if not humans.is_empty() else roster[0]
	if Game.debug.has("ph_hunter"):
		for e in roster:
			if e.name == str(Game.debug.ph_hunter):
				hunter = e
	var spread := roster.filter(func(e): return e != hunter)
	for i in roster.size():
		var e: Dictionary = roster[i]
		var p := arena.get_player(e.node)
		if p == null:
			continue
		var is_hunter: bool = e == hunter
		e.team = 0 if is_hunter else 1
		stats[e.node].team = e.team
		p.net_set_team.rpc(e.team)
		var sp: Dictionary
		if is_hunter:
			sp = arena.map.get_spawn(0, 0, 1)
		else:
			sp = arena.map.get_spawn_ffa(spread.find(e), spread.size(), 3 + round_num)
		var spawn_pos: Vector3 = sp.pos
		var dummy_prop := -1
		if e.bot and not is_hunter and not Scan.catalog.is_empty():
			# Test dummies (--ph_dummy): hide as a random prop, standing on it.
			dummy_prop = randi() % Scan.catalog.size()
			var ce: Dictionary = Scan.catalog[dummy_prop]
			spawn_pos = (ce.pos as Vector3) - Vector3(0, ce.size.y * 0.5 - 0.1, 0)
		p.net_respawn.rpc(spawn_pos, sp.yaw)
		if dummy_prop >= 0:
			p.net_disguise.rpc(dummy_prop)
			if Game.debug.has("log_ph"):
				print("[PH] %s se cache en %s à %s (%d objets au catalogue)" % [e.name, Scan.catalog[dummy_prop].id, str(spawn_pos.snapped(Vector3.ONE * 0.1)), Scan.catalog.size()])
	arena.prop_hunt.server_prepare(hunter.node)
	_sync_stats()


func _set_state(s: State, t: float) -> void:
	_net_state.rpc(s, round_num, t, scores, round_winner, match_winner)


@rpc("authority", "call_local", "reliable")
func _net_state(s: int, r: int, t: float, sc: Array, rw: int, mw: int) -> void:
	state = s as State
	round_num = r
	time_left = t
	scores = sc
	round_winner = rw
	match_winner = mw
	state_changed.emit()


func _live_time() -> float:
	match Game.mode():
		Game.MODE_BR:
			return BR_TIME
		Game.MODE_PH:
			return PropHunt.HIDE_TIME + PropHunt.SEEK_TIME
		Game.MODE_ZOMBIE:
			return 86400.0 # no clock: the waves decide
	return float(Game.config.round_time) + 10.0 * maxf(float(Game.config.team_size) - 2.0, 0.0) # bigger squads need more time


func _process(delta: float) -> void:
	if state != State.WAITING:
		time_left = maxf(0.0, time_left - delta)
	if not multiplayer.is_server():
		return
	match state:
		State.COUNTDOWN:
			if time_left <= 0.0:
				_set_state(State.LIVE, _live_time())
				if Game.is_ph():
					arena.prop_hunt.server_go()
				elif Game.is_zombie():
					arena.monsters.server_go()
		State.LIVE:
			if time_left <= 0.0:
				_end_round(_timeout_winner())
		State.ROUND_END:
			if time_left <= 0.0:
				if round_winner >= 0 and scores[mini(round_winner, 1)] >= rounds_to_win() or (Game.mode() != Game.MODE_TDM):
					match_winner = round_winner
					_set_state(State.MATCH_END, 0.0)
					print("[MATCH] Fin du match. Vainqueur: %s" % (Game.team_name(match_winner) if match_winner >= 0 else "personne"))
					if Game.debug.has("quit_after_match"):
						get_tree().create_timer(1.0, true, false, true).timeout.connect(get_tree().quit)
				else:
					_start_round()


## Standing players per team: knocked-down players don't count, so a team that
## is entirely down (or dead) loses the round.
func _alive_counts() -> Array:
	var a := [0, 0]
	var hp := [0.0, 0.0]
	for p: Player in arena.players:
		if p.alive:
			var t := mini(p.team, 1)
			a[t] += 1
			hp[t] += p.health + p.shield
	return [a, hp]


func _timeout_winner() -> int:
	match Game.mode():
		Game.MODE_PH:
			return 1 # the props held out
		Game.MODE_BR:
			var best: Player = null
			for p: Player in arena.players:
				if p.alive and (best == null or p.health + p.shield > best.health + best.shield):
					best = p
			return best.team if best else -1
	var r := _alive_counts()
	if r[0][0] != r[0][1]:
		return 0 if r[0][0] > r[0][1] else 1
	if absf(r[1][0] - r[1][1]) > 0.5:
		return 0 if r[1][0] > r[1][1] else 1
	return -1


func server_check_round() -> void:
	if state != State.LIVE:
		return
	if Game.is_zombie():
		# Lost once nobody is left standing (knocked-down survivors can still be revived).
		for p: Player in arena.players:
			if p.alive:
				return
		_end_round(1)
		return
	if Game.is_ffa():
		var left: Array[Player] = []
		for p: Player in arena.players:
			if p.alive:
				left.append(p)
		if left.size() <= 1:
			_end_round(left[0].team if left.size() == 1 else -1)
		return
	var a: Array = _alive_counts()[0]
	if a[0] == 0 and a[1] == 0:
		_end_round(-1)
	elif a[0] == 0:
		_end_round(1)
	elif a[1] == 0:
		_end_round(0)


func server_end_round(w: int) -> void:
	if state == State.LIVE:
		_end_round(w)


func _end_round(w: int) -> void:
	round_winner = w
	if w >= 0 and w < 2:
		scores[w] += 1
	print("[MATCH] Manche %d -> %s  (%d-%d)" % [round_num, Game.team_name(w) if w >= 0 else "égalité", scores[0], scores[1]])
	_sync_stats()
	_set_state(State.ROUND_END, ROUND_END_TIME)


## A shot left the barrel: rate-limit it, remember it for hit validation and
## show it to the other peers.
func server_register_shot(shooter: Player, origin: Vector3, dir: Vector3, shot_id: int) -> void:
	if not shooter.alive or state != State.LIVE:
		return
	var now := Time.get_ticks_msec() * 0.001
	# Rate limit with slack for network jitter (reliable packets can bunch up).
	if now - float(shooter.get_meta("last_shot", -10.0)) < Player.RELOAD_TIME * 0.55:
		if Game.debug.has("log_shots"):
			print("[SHOT-SRV] #%d REJETÉ: cadence" % shot_id)
		return
	if origin.distance_to(shooter.eye_position()) > 4.0:
		if Game.debug.has("log_shots"):
			print("[SHOT-SRV] #%d REJETÉ: origine à %.1f m" % [shot_id, origin.distance_to(shooter.eye_position())])
		return
	shooter.set_meta("last_shot", now)
	if Game.debug.has("log_bots") and shooter.is_bot and shooter.brain.target:
		var tg: Player = shooter.brain.target
		if arena.is_sight_blocked(origin, tg.chest_position()) and arena.is_sight_blocked(origin, tg.global_position + Vector3(0, tg.head_height(), 0)):
			print("[BOT-SMOKE] %s a tiré sur %s à travers une fumée !" % [shooter.display_name, tg.display_name])
	shooter.server_shots[shot_id] = {"origin": origin, "t": now}
	for k in shooter.server_shots.keys():
		if now - float(shooter.server_shots[k].t) > 4.0:
			shooter.server_shots.erase(k)
	shooter.net_shot_fx.rpc(origin, dir.normalized(), shot_id)
	# Bots hear the shot (through walls and smoke): they learn roughly where it came from.
	# A silenced Ferro is only heard from close by.
	for o: Player in arena.players:
		if o.brain and o.team != shooter.team:
			o.brain.hear(shooter, origin, Items.SILENCED_HEAR_RANGE if shooter.has_silencer else BotBrain.HEAR_RANGE)


## A projectile reported hitting `target`: validate against the registered shot.
func server_handle_hit(shooter: Player, shot_id: int, target: String, headshot: bool, hit_pos := Vector3.INF) -> void:
	if not shooter.server_shots.has(shot_id):
		if Game.debug.has("log_shots"):
			print("[SHOT-SRV] #%d REJETÉ: tir non enregistré" % shot_id)
		return
	var shot: Dictionary = shooter.server_shots[shot_id]
	shooter.server_shots.erase(shot_id)
	var v := arena.get_player(target)
	if v == null or not v.is_hittable() or v.team == shooter.team:
		return
	var age := Time.get_ticks_msec() * 0.001 - float(shot.t)
	var dist := (shot.origin as Vector3).distance_to(v.global_position)
	# Bullet can't outrun its speed (generous slack for latency/interpolation).
	if dist > Projectile.SPEED * (age + 0.35) + 4.0 or dist > Player.FIRE_RANGE + 5.0:
		if Game.debug.has("log_shots"):
			print("[SHOT-SRV] #%d REJETÉ: distance %.1f m en %.2f s" % [shot_id, dist, age])
		return
	# The reported impact point is only trusted when it is on the victim (kill cam / damage numbers).
	var impact := Vector3.INF
	if hit_pos != Vector3.INF and hit_pos.distance_to(v.global_position + Vector3(0, 0.9, 0)) < 2.5:
		impact = hit_pos
	# Prop hunt: one hit kills, shield or not.
	var dmg := 1000.0 if Game.is_ph() else Player.DAMAGE * (Player.HEADSHOT_MULT if headshot else 1.0)
	v.server_apply_damage(dmg, shooter, headshot, "FERRO", shot.origin, impact)


## Zombie mode: damage a Ferro slug dealt to monster `monster_id`. Weapons hit harder than
## against players; a head shot doubles it.
func server_handle_monster_hit(shooter: Player, shot_id: int, monster_id: int, headshot: bool, hit_pos := Vector3.INF) -> void:
	if not shooter.server_shots.has(shot_id) or arena.monsters == null:
		return
	var shot: Dictionary = shooter.server_shots[shot_id]
	shooter.server_shots.erase(shot_id)
	var m := arena.monsters.get_monster(monster_id)
	if m == null or not m.alive or not shooter.alive:
		return
	var age := Time.get_ticks_msec() * 0.001 - float(shot.t)
	var dist := (shot.origin as Vector3).distance_to(m.global_position)
	if dist > Projectile.SPEED * (age + 0.35) + 4.0 or dist > Player.FIRE_RANGE + 5.0:
		return
	var dmg := Player.DAMAGE * MonsterManager.PLAYER_DAMAGE_MULT * (Player.HEADSHOT_MULT if headshot else 1.0)
	var was_alive := m.alive
	var key := String(shooter.name)
	if stats.has(key):
		stats[key].dmg += int(dmg)
	var killed := m.server_damage(dmg, shooter, headshot)
	if not shooter.is_bot:
		shooter.net_hit_confirm.rpc_id(shooter.get_multiplayer_authority(), headshot, Player.HIT_KILL if killed and was_alive else Player.HIT_HEALTH, dmg, hit_pos if hit_pos != Vector3.INF else m.global_position + Vector3(0, 1.2, 0), MonsterRig.kind_data(m.kind).name)


func server_on_damage(attacker: Player, _victim: Player, amount: float) -> void:
	var k := String(attacker.name)
	if stats.has(k):
		stats[k].dmg += int(amount)


func server_on_kill(victim: Player, killer: Player, headshot: bool, damagers: Array, weapon := "FERRO") -> void:
	var vk := String(victim.name)
	if killer == null:
		# A monster got them.
		if stats.has(vk):
			stats[vk].d += 1
		_net_kill.rpc(weapon.capitalize(), 1, victim.display_name, victim.team, false, weapon, FEED_KNOCK)
		_sync_stats()
		server_check_round()
		return
	var kk := String(killer.name)
	if stats.has(kk) and kk != vk:
		stats[kk].k += 1
	if stats.has(vk):
		stats[vk].d += 1
	for d in damagers:
		if d != kk and stats.has(d):
			stats[d].a += 1
	_net_kill.rpc(killer.display_name, killer.team, victim.display_name, victim.team, headshot, weapon, FEED_FINISH if Game.instant_kill() else FEED_KNOCK)
	if Game.debug.has("log_items"):
		print("[KILL] %s -> %s (%s, à terre)" % [killer.display_name, victim.display_name, weapon])
	_sync_stats()
	server_check_round()


## A knocked-down player was finished off: feed only (the knock was the kill).
func server_on_finish(victim: Player, killer: Player, weapon := "FERRO") -> void:
	if killer == null:
		_net_kill.rpc(weapon.capitalize(), 1, victim.display_name, victim.team, false, weapon, FEED_FINISH)
		_sync_stats()
		server_check_round()
		return
	_net_kill.rpc(killer.display_name, killer.team, victim.display_name, victim.team, false, weapon, FEED_FINISH)
	if Game.debug.has("log_items"):
		print("[KILL] %s achève %s" % [killer.display_name, victim.display_name])
	_sync_stats()
	server_check_round()


func server_on_player_left(node_name: String) -> void:
	for i in range(roster.size() - 1, -1, -1):
		if roster[i].node == node_name:
			roster.remove_at(i)
	server_check_round.call_deferred()


func _sync_stats() -> void:
	_net_stats.rpc(stats)


@rpc("authority", "call_local", "reliable")
func _net_stats(s: Dictionary) -> void:
	stats = s
	stats_changed.emit()


@rpc("authority", "call_local", "reliable")
func _net_kill(killer: String, kt: int, victim: String, vt: int, headshot: bool, weapon: String, kind: int) -> void:
	kill_feed.emit(killer, kt, victim, vt, headshot, weapon, kind)
