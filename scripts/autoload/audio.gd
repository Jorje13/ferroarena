extends Node
## Sound effects (recorded CC0 assets + procedural synthesis) and music.

const RATE := 44100

var streams := {}
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.seed = 1337
	streams["shot"] = _make_shot()
	streams["shot_far"] = _make_shot_far()
	streams["dry"] = _make_click(2600.0, 0.05, 0.5)
	streams["reload_open"] = _make_click(1700.0, 0.12, 0.8)
	streams["reload_insert"] = _make_slide()
	streams["reload_close"] = _make_click(1100.0, 0.16, 1.0)
	streams["hit"] = _make_tone([1900.0], 0.06, 0.45)
	streams["headshot"] = _make_tone([2400.0, 3100.0], 0.09, 0.5)
	streams["kill"] = _make_tone([660.0, 990.0, 1320.0], 0.35, 0.45)
	streams["hurt"] = _make_thud(0.18, 0.9)
	streams["bandage"] = _make_bandage()
	streams["step"] = _make_thud(0.07, 0.35)
	streams["roll"] = _make_noise_swell(0.45, 0.4)
	streams["ui"] = _make_tone([880.0], 0.05, 0.3)
	streams["round"] = _make_tone([440.0, 554.0, 659.0], 0.8, 0.35)
	streams["beep"] = _make_tone([740.0], 0.12, 0.35)
	streams["whistle"] = _make_whistle()
	streams["ads_in"] = _make_noise_swell(0.2, 0.3)
	streams["ads_out"] = _make_noise_swell(0.14, 0.2)
	_make_ferro_reload()
	streams["ricochet"] = _make_ricochet()
	_make_movement()
	_make_shield_and_revive()
	_make_big_bore()
	_make_feedback()
	_make_blast_layers()
	_make_monsters()
	_load_files()


## Zombie-mode monsters: growl (rough, wavering low voice), claw swipe, screech (rising
## shriek), ground slam and death rattle (falling growl).
func _make_monsters() -> void:
	streams["mon_growl"] = _wav(_voice(0.9, 70.0, 55.0, 0.55, 3.0))
	streams["mon_death"] = _wav(_voice(1.3, 95.0, -50.0, 0.6, 2.0))
	streams["mon_screech"] = _wav(_voice(0.7, 360.0, 520.0, 0.5, 5.0))
	var s := _buf(0.35)
	var lp := 0.0
	for i in s.size():
		var t := float(i) / RATE
		lp += (_rng.randf_range(-1.0, 1.0) - lp) * 0.5
		s[i] = (_rng.randf_range(-1.0, 1.0) - lp) * sin(PI * clampf(t / 0.35, 0.0, 1.0)) * 0.55
	streams["mon_swipe"] = _wav(s)
	s = _buf(0.7)
	_thud_at(s, 0.0, 48.0, 1.0, 0.1)
	_thud_at(s, 0.05, 90.0, 0.5, 0.06)
	_friction(s, 0.02, 0.4, 0.4, 0.25)
	streams["mon_slam"] = _wav(s)


## Rough "voice": sawtooth with vibrato and noisy growl, pitch gliding by `glide` Hz over `dur`.
func _voice(dur: float, f0: float, glide: float, amp: float, rough: float) -> PackedFloat32Array:
	var s := _buf(dur)
	var ph := 0.0
	var lp := 0.0
	for i in s.size():
		var t := float(i) / RATE
		var u := t / dur
		var f := f0 + glide * u + 6.0 * sin(TAU * 6.0 * t)
		ph = fmod(ph + f / RATE, 1.0)
		var saw := ph * 2.0 - 1.0
		# Amplitude flutter gives the growl its rasp.
		var flutter := 0.65 + 0.35 * sin(TAU * (28.0 + rough * 6.0) * t)
		lp += (saw - lp) * 0.25
		var env := minf(t * 14.0, 1.0) * (1.0 - smoothstep(0.6, 1.0, u))
		s[i] = (lp * 0.9 + _rng.randf_range(-1.0, 1.0) * 0.12 * rough) * flutter * env * amp
	return s


## Big-bore report layers for the Ferro:
## - shot_boom: sub-bass pressure wave (pitch dive 70 -> 38 Hz) + low noise blast,
## - shot_crack: supersonic snap (very short broadband transient),
## - shot_mech: stock slamming the shoulder + action rattle (shooter only),
## - shot_tail: long rolling echo (several decaying reflections of low rumble).
func _make_big_bore() -> void:
	var s := _buf(0.9)
	var ph := 0.0
	var lp := 0.0
	for i in s.size():
		var t := float(i) / RATE
		ph += TAU * (38.0 + 32.0 * exp(-t * 9.0)) / RATE
		lp += (_rng.randf_range(-1.0, 1.0) - lp) * 0.06
		var body := sin(ph) * exp(-t * 5.5) * 1.0
		var blast := lp * 4.0 * exp(-t * 14.0)
		s[i] = (body + blast) * minf(t * 900.0, 1.0) * 0.85
	streams["shot_boom"] = _wav(s)
	s = _buf(0.12)
	for i in s.size():
		var t := float(i) / RATE
		var n := _rng.randf_range(-1.0, 1.0)
		s[i] = (n * exp(-t * 160.0) + sin(TAU * 2900.0 * t) * exp(-t * 90.0) * 0.4) * 0.9
	streams["shot_crack"] = _wav(s)
	s = _buf(0.35)
	_thud_at(s, 0.0, 85.0, 0.9, 0.035)
	_metal(s, 0.01, [1500.0, 2600.0, 4100.0], 0.35, 0.03)
	_metal(s, 0.06, [2200.0, 3500.0], 0.18, 0.02)
	streams["shot_mech"] = _wav(s)
	s = _buf(2.6)
	lp = 0.0
	var lp2 := 0.0
	for i in s.size():
		var t := float(i) / RATE
		lp += (_rng.randf_range(-1.0, 1.0) - lp) * 0.02
		lp2 += (lp - lp2) * 0.3
		# Rolling reflections: bumps at irregular delays, overall slow decay.
		var bumps := 0.0
		for d in [0.0, 0.21, 0.47, 0.8, 1.25]:
			if t >= d:
				bumps += exp(-(t - d) * 6.0) * (1.0 - d * 0.55)
		s[i] = lp2 * 5.0 * bumps * minf(t * 60.0, 1.0) * exp(-t * 0.9) * 0.7
	streams["shot_tail"] = _wav(s)


## Combat feedback and attachments:
## - sil_shot: suppressed report (muffled gas puff + low thump, no crack),
## - attach_silencer / attach_stock: threading the can on, snapping the stock in,
## - flesh_hit / pain / hit_thump / shield_zap: impacts on bodies, felt and dealt,
## - bullet_whiz: supersonic slug passing close by, heartbeat: low health,
## - killcam_in / killcam_out: whoosh into and out of the kill cam.
func _make_feedback() -> void:
	var s := _buf(0.55)
	var lp := 0.0
	var ph := 0.0
	for i in s.size():
		var t := float(i) / RATE
		var white := _rng.randf_range(-1.0, 1.0)
		lp += (white - lp) * 0.16
		ph += TAU * (110.0 - 55.0 * minf(t * 14.0, 1.0)) / RATE
		var puff := lp * exp(-t * 34.0) * 2.4
		var thump := sin(ph) * exp(-t * 20.0) * 0.75
		var hiss := (white - lp) * exp(-t * 11.0) * 0.1
		s[i] = (puff + thump + hiss) * minf(t * 2500.0, 1.0) * 0.8
	_metal(s, 0.018, [1700.0, 2900.0], 0.1, 0.012)
	streams["sil_shot"] = _wav(s)

	# Suppressor screwed onto the muzzle: ratchet ticks, then it bottoms out.
	s = _buf(1.25)
	for k in 8:
		var t0 := 0.04 + k * 0.07
		_friction(s, t0, 0.05, 0.3, 0.55)
		_metal(s, t0, [2900.0 + k * 90.0, 4300.0], 0.07, 0.006)
	_thud_at(s, 0.64, 130.0, 0.9, 0.045)
	_metal(s, 0.64, [1500.0, 2400.0, 3600.0], 0.55, 0.05)
	_metal(s, 0.69, [410.0, 830.0, 1240.0], 0.22, 0.14)
	for i in int(RATE * 0.5):
		var t := float(i) / RATE
		var idx := int(RATE * 0.72) + i
		s[idx] += (sin(TAU * 988.0 * t) + sin(TAU * 1480.0 * t) * 0.6) * exp(-t * 7.0) * minf(t * 80.0, 1.0) * 0.11
	streams["attach_silencer"] = _wav(s)

	# Stock slid onto the receiver and locked: slide, snap, second lock, rubber thud.
	s = _buf(1.0)
	_friction(s, 0.02, 0.24, 0.5, 0.3)
	_metal(s, 0.27, [2200.0, 3600.0, 5100.0], 0.65, 0.016)
	_thud_at(s, 0.28, 170.0, 0.75, 0.04)
	_metal(s, 0.4, [1800.0, 2900.0], 0.42, 0.011)
	_thud_at(s, 0.52, 85.0, 0.55, 0.06)
	for i in int(RATE * 0.45):
		var t := float(i) / RATE
		var idx := int(RATE * 0.5) + i
		s[idx] += (sin(TAU * 659.0 * t) + sin(TAU * 988.0 * t) * 0.6) * exp(-t * 8.0) * minf(t * 80.0, 1.0) * 0.1
	streams["attach_stock"] = _wav(s)

	s = _buf(0.3)
	_thud_at(s, 0.0, 95.0, 0.9, 0.05)
	_friction(s, 0.0, 0.12, 0.45, 0.3)
	_metal(s, 0.0, [900.0, 1500.0], 0.18, 0.01)
	streams["flesh_hit"] = _wav(s)

	# Victim's grunt: air knocked out of the lungs, a low pitch drop.
	s = _buf(0.4)
	lp = 0.0
	ph = 0.0
	for i in s.size():
		var t := float(i) / RATE
		lp += (_rng.randf_range(-1.0, 1.0) - lp) * 0.2
		ph += TAU * (150.0 - 60.0 * t / 0.4) / RATE
		var env := minf(t * 90.0, 1.0) * exp(-t * 9.0)
		s[i] = (sin(ph) * 0.45 + sin(ph * 2.0) * 0.2 + lp * 0.9) * env * 0.7
	streams["pain"] = _wav(s)

	s = _buf(0.14)
	_thud_at(s, 0.0, 175.0, 0.9, 0.03)
	_metal(s, 0.0, [1200.0], 0.15, 0.008)
	streams["hit_thump"] = _wav(s)

	# Energy shield zapped from the inside: crackle gated at random, falling whine.
	s = _buf(0.3)
	for i in s.size():
		var t := float(i) / RATE
		var gate := 1.0 if fmod(t * 90.0 + _rng.randf() * 0.4, 1.0) < 0.55 else 0.25
		s[i] = (_rng.randf_range(-1.0, 1.0) * 0.5 * gate + sin(TAU * (2200.0 - 1400.0 * t / 0.3) * t) * 0.5) * exp(-t * 11.0) * 0.6
	streams["shield_zap"] = _wav(s)

	# Slug zipping past the ear: bright noise sweeping down (Doppler), hump in the middle.
	s = _buf(0.5)
	lp = 0.0
	ph = 0.0
	for i in s.size():
		var t := float(i) / RATE
		var white := _rng.randf_range(-1.0, 1.0)
		lp += (white - lp) * 0.5
		ph += TAU * (3600.0 * exp(-t * 4.2) + 800.0) / RATE
		var env := exp(-pow((t - 0.1) / 0.075, 2.0)) + exp(-t * 7.0) * 0.25
		s[i] = ((white - lp) * 0.7 + sin(ph) * 0.35) * env * minf(t * 400.0, 1.0) * 0.8
	streams["bullet_whiz"] = _wav(s)

	s = _buf(0.9)
	_thud_at(s, 0.0, 62.0, 1.0, 0.075)
	_thud_at(s, 0.27, 52.0, 0.7, 0.075)
	streams["heartbeat"] = _wav(s)

	# Kill cam: a swelling rush with a deep boom, and a soft release.
	s = _buf(0.9)
	lp = 0.0
	for i in s.size():
		var t := float(i) / RATE
		lp += (_rng.randf_range(-1.0, 1.0) - lp) * (0.04 + 0.4 * t)
		s[i] = lp * sin(PI * minf(t / 0.9, 1.0)) * 1.8 * 0.6
	_thud_at(s, 0.0, 48.0, 0.9, 0.12)
	streams["killcam_in"] = _wav(s)
	s = _buf(0.6)
	lp = 0.0
	for i in s.size():
		var t := float(i) / RATE
		lp += (_rng.randf_range(-1.0, 1.0) - lp) * (0.5 - 0.4 * t / 0.6)
		s[i] = lp * exp(-t * 6.0) * 1.2
	streams["killcam_out"] = _wav(s)


## Synthesised layers under the recorded blast: a sub-bass pressure wave, a rain of
## debris, the ringing in the ears after a close detonation and the grenade's
## flying spoon.
func _make_blast_layers() -> void:
	var s := _buf(2.2)
	var lp := 0.0
	var ph := 0.0
	for i in s.size():
		var t := float(i) / RATE
		ph += TAU * (24.0 + 34.0 * exp(-t * 5.0)) / RATE
		lp += (_rng.randf_range(-1.0, 1.0) - lp) * 0.025
		s[i] = (sin(ph) * exp(-t * 2.4) * 1.0 + lp * 3.0 * exp(-t * 4.0)) * minf(t * 400.0, 1.0) * 0.9
	streams["expl_sub"] = _wav(s)
	# Debris: pebbles and splinters ticking down, dense at first, thinning out.
	s = _buf(2.8)
	var tick := 0
	var amp := 0.0
	var tone := 0.0
	for i in s.size():
		var t := float(i) / RATE
		if tick <= 0 and _rng.randf() < 0.0035 * exp(-t * 1.25):
			tick = int(RATE * _rng.randf_range(0.002, 0.007))
			amp = _rng.randf_range(0.25, 1.0) * exp(-t * 0.6)
			tone = _rng.randf_range(0.15, 0.6)
		if tick > 0:
			var w := _rng.randf_range(-1.0, 1.0)
			s[i] = (w * tone + sin(float(tick) * tone) * (1.0 - tone)) * amp * float(tick) / (RATE * 0.007)
			tick -= 1
	streams["expl_debris"] = _wav(s)
	# Tinnitus: two thin whistles that fade out slowly after the blast.
	s = _buf(4.0)
	for i in s.size():
		var t := float(i) / RATE
		var env := minf(t * 12.0, 1.0) * exp(-t * 0.85)
		s[i] = (sin(TAU * 4100.0 * t) * 0.6 + sin(TAU * 6300.0 * t) * 0.25 + sin(TAU * 2800.0 * t) * 0.2) * env * 0.22
	streams["tinnitus"] = _wav(s)
	# The safety lever pinging off the grenade.
	s = _buf(0.9)
	_metal(s, 0.0, [2800.0, 4200.0, 6300.0, 8100.0], 0.5, 0.18)
	_metal(s, 0.015, [1900.0, 3300.0], 0.25, 0.1)
	streams["grenade_spoon"] = _wav(s)
	# UI stingers: round won / lost, a teammate going down.
	streams["round_win"] = _make_tone([523.0, 659.0, 784.0, 1047.0], 1.0, 0.32)
	streams["round_lose"] = _make_tone([392.0, 330.0, 262.0], 1.1, 0.32)
	streams["ally_down"] = _make_tone([740.0, 520.0], 0.42, 0.38)
	# Bullet into soft ground (snow, earth): a dull thump and a puff.
	s = _buf(0.3)
	lp = 0.0
	_thud_at(s, 0.0, 70.0, 0.9, 0.05)
	for i in s.size():
		var t := float(i) / RATE
		lp += (_rng.randf_range(-1.0, 1.0) - lp) * 0.2
		s[i] += lp * exp(-t * 22.0) * 0.7
	streams["impact_soft"] = _wav(s)
	# Canister pop: low thump, gas puff, then the smoke starts to hiss.
	s = _buf(0.6)
	lp = 0.0
	_thud_at(s, 0.0, 95.0, 1.0, 0.07)
	for i in s.size():
		var t := float(i) / RATE
		lp += (_rng.randf_range(-1.0, 1.0) - lp) * 0.35
		s[i] += lp * exp(-t * 11.0) * 0.8 * minf(t * 500.0, 1.0)
	streams["smoke_pop_synth"] = _wav(s)


## Frag detonation heard from where the listener stands: close up a hard crack, a
## chest-thumping body, sub-bass and falling debris; far away a late, rounder
## rumble. Within ~12 m the ears ring.
func play_explosion(pos: Vector3) -> void:
	var cam := get_viewport().get_camera_3d()
	var dist := cam.global_position.distance_to(pos) if cam else 25.0
	var travel := clampf(dist / 340.0, 0.0, 0.7)
	if dist < 55.0:
		play_3d("expl_crack", pos, 7.0, 320.0, 0.05, 0.8)
		play_3d("expl_body", pos, 5.0, 340.0, 0.08, 0.9)
		play_3d("expl_sub", pos, 8.0, 280.0, 0.03)
		play_3d("explosion", pos, 0.0, 300.0, 0.06)
		play_3d_delayed("expl_debris", pos, 0.2 + travel, -3.0, 120.0)
		play_3d_delayed("expl_tail", pos, 0.3 + travel, -2.0, 420.0)
	else:
		play_3d_delayed("explosion_far", pos, travel, 6.0, 520.0)
		play_3d_delayed("expl_body", pos, travel + 0.05, 3.0, 480.0)
		play_3d_delayed("expl_sub", pos, travel, 6.0, 420.0)
		play_3d_delayed("expl_tail", pos, travel + 0.4, 0.0, 520.0)
	if dist < 12.0:
		ear_ring(clampf(1.0 - dist / 12.0, 0.0, 1.0))


var _ring_tw: Tween
var _lowpass_idx := -1


## Ringing ears after a loud close blast: a whistle and muffled sound that clears
## up over a few seconds. k 0..1.
func ear_ring(k: float) -> void:
	play_2d("tinnitus", lerpf(-22.0, -9.0, k))
	var bus := AudioServer.get_bus_index("SFX")
	if bus < 0 or _lowpass_idx < 0:
		return
	var lpf := AudioServer.get_bus_effect(bus, _lowpass_idx) as AudioEffectLowPassFilter
	AudioServer.set_bus_effect_enabled(bus, _lowpass_idx, true)
	lpf.cutoff_hz = lerpf(6000.0, 700.0, k)
	if _ring_tw:
		_ring_tw.kill()
	_ring_tw = create_tween()
	_ring_tw.tween_interval(0.5 + 0.9 * k)
	_ring_tw.tween_property(lpf, "cutoff_hz", 20000.0, 1.4 + 1.8 * k)
	_ring_tw.tween_callback(func(): AudioServer.set_bus_effect_enabled(bus, _lowpass_idx, false))


## Smoke canister going off: a pop, then a long hiss that follows the cloud's life
## (the cloud keeps its own looping 3D player, see SmokeCloud).
func play_smoke_pop(pos: Vector3) -> void:
	play_3d("smoke_pop" if streams.has("smoke_pop") else "smoke_pop_synth", pos, 4.0, 110.0, 0.05, 0.85)
	play_3d("smoke_pop_synth", pos, 0.0, 90.0, 0.05)


## Plays a 3D sound after `delay` seconds (echoes, distant reports).
func play_3d_delayed(id: String, pos: Vector3, delay: float, volume_db := 0.0, max_dist := 120.0) -> void:
	get_tree().create_timer(delay).timeout.connect(func(): play_3d(id, pos, volume_db, max_dist, 0.08))


## Short music dip on gunshots so the report owns the mix.
func duck_music(depth_db := -9.0, hold := 0.15, release := 0.9) -> void:
	var bus := AudioServer.get_bus_index("Music")
	if bus < 0:
		return
	var base := linear_to_db(maxf(Game.music_volume, 0.0001))
	if _duck_tw:
		_duck_tw.kill()
	AudioServer.set_bus_volume_db(bus, base + depth_db)
	_duck_tw = create_tween()
	_duck_tw.tween_interval(hold)
	_duck_tw.tween_method(func(v: float): AudioServer.set_bus_volume_db(bus, v), base + depth_db, base, release)


var _duck_tw: Tween


## Energy shield (glassy zaps), shield recharge (rising hum), shield break,
## knock-down thud and defibrillator charge + discharge.
func _make_shield_and_revive() -> void:
	var s := _buf(0.3)
	for i in s.size():
		var t := float(i) / RATE
		var f := 1500.0 - 900.0 * t / 0.3
		s[i] = (sin(TAU * f * t) * 0.5 + sin(TAU * f * 2.03 * t) * 0.25 + _rng.randf_range(-1, 1) * exp(-t * 60.0)) * exp(-t * 14.0) * 0.6
	streams["shield_hit"] = _wav(s)
	s = _buf(0.6)
	for i in s.size():
		var t := float(i) / RATE
		var crack := _rng.randf_range(-1, 1) * exp(-t * 25.0)
		s[i] = (crack * 0.9 + sin(TAU * (900.0 - 600.0 * t) * t) * exp(-t * 6.0) * 0.5) * 0.7
	_metal(s, 0.0, [2600.0, 3900.0, 5200.0], 0.35, 0.05)
	streams["shield_break"] = _wav(s)
	s = _buf(1.6)
	var ph := 0.0
	for i in s.size():
		var t := float(i) / RATE
		ph += TAU * (180.0 + 520.0 * pow(t / 1.6, 1.5)) / RATE
		var env := minf(t * 3.0, 1.0) * (1.0 - smoothstep(1.45, 1.6, t))
		s[i] = (sin(ph) * 0.4 + sin(ph * 2.0) * 0.2 + sin(ph * 3.01) * 0.1) * env * 0.5
	streams["shield_charge"] = _wav(s)
	s = _buf(0.7)
	_thud_at(s, 0.0, 55.0, 1.0, 0.08)
	_thud_at(s, 0.12, 70.0, 0.6, 0.05)
	_friction(s, 0.08, 0.5, 0.35, 0.3)
	streams["knock"] = _wav(s)
	s = _buf(1.4)
	ph = 0.0
	for i in int(RATE * 1.0):
		var t := float(i) / RATE
		ph += TAU * (600.0 + 2400.0 * t) / RATE
		s[i] = sin(ph) * minf(t * 4.0, 1.0) * 0.18
	_thud_at(s, 1.0, 60.0, 1.0, 0.06)
	_metal(s, 1.0, [1200.0, 2500.0], 0.4, 0.04)
	for i in int(RATE * 0.3):
		var t := float(i) / RATE
		s[int(RATE * 1.0) + i] += _rng.randf_range(-1, 1) * exp(-t * 30.0) * 0.8
	streams["defib"] = _wav(s)


## Gravel slide, ledge mantle and hard landing: thuds for the body and boots,
## filtered friction for fabric/gravel scrape, small clicks for gear rattle.
func _make_movement() -> void:
	var s := _buf(1.0)
	_thud_at(s, 0.0, 70.0, 0.55, 0.05)
	_friction(s, 0.02, 0.95, 0.45, 0.35)
	_friction(s, 0.05, 0.7, 0.25, 0.7)
	for i in 5:
		_metal(s, 0.08 + i * 0.13 + _rng.randf() * 0.05, [2300.0 + _rng.randf() * 900.0, 3700.0], 0.05, 0.01)
	streams["slide"] = _wav(s)
	s = _buf(0.75)
	_thud_at(s, 0.0, 110.0, 0.5, 0.03) # hands on the ledge
	_thud_at(s, 0.04, 140.0, 0.3, 0.02)
	_friction(s, 0.08, 0.4, 0.3, 0.5)
	_metal(s, 0.12, [1800.0, 2900.0, 4100.0], 0.12, 0.015)
	_metal(s, 0.3, [2100.0, 3300.0], 0.08, 0.012)
	_thud_at(s, 0.5, 80.0, 0.6, 0.04) # boots down
	streams["mantle"] = _wav(s)
	s = _buf(0.5)
	_thud_at(s, 0.0, 60.0, 0.9, 0.06)
	_thud_at(s, 0.03, 95.0, 0.5, 0.04)
	_friction(s, 0.01, 0.25, 0.3, 0.4)
	_metal(s, 0.04, [1900.0, 2800.0, 4300.0], 0.1, 0.02)
	streams["land"] = _wav(s)


# ---------------------------------------------------------------- Ferro reload foley
# Built from layered primitives: metal "clicks" (inharmonic partials with fast
# decay), low "thuds", band-limited friction noise. Each layer starts at t0.

func _buf(dur: float) -> PackedFloat32Array:
	var s := PackedFloat32Array()
	s.resize(int(RATE * dur))
	return s


func _metal(s: PackedFloat32Array, t0: float, freqs: Array, amp: float, decay: float) -> void:
	var start := int(t0 * RATE)
	var n := mini(int(decay * 6.0 * RATE), s.size() - start)
	var phases := []
	for f in freqs:
		phases.append(_rng.randf() * TAU)
	for i in n:
		var t := float(i) / RATE
		var v := 0.0
		for k in freqs.size():
			v += sin(TAU * freqs[k] * t + phases[k]) * exp(-t / (decay * (1.0 - k * 0.15)))
		var transient := _rng.randf_range(-1.0, 1.0) * exp(-t * 900.0)
		s[start + i] += (v / freqs.size() + transient * 1.2) * amp


func _thud_at(s: PackedFloat32Array, t0: float, f: float, amp: float, decay: float) -> void:
	var start := int(t0 * RATE)
	var n := mini(int(decay * 6.0 * RATE), s.size() - start)
	var lp := 0.0
	var phase := 0.0
	for i in n:
		var t := float(i) / RATE
		lp += (_rng.randf_range(-1.0, 1.0) - lp) * 0.12
		phase += TAU * f * (1.0 + exp(-t * 40.0)) / RATE
		s[start + i] += (sin(phase) * 0.8 + lp * 1.5) * exp(-t / decay) * amp


func _friction(s: PackedFloat32Array, t0: float, dur: float, amp: float, bright: float) -> void:
	var start := int(t0 * RATE)
	var n := mini(int(dur * RATE), s.size() - start)
	var lp := 0.0
	var hp_prev := 0.0
	for i in n:
		var t := float(i) / dur / RATE
		var w := _rng.randf_range(-1.0, 1.0)
		lp += (w - lp) * bright
		var hp := lp - hp_prev
		hp_prev = lp
		var grit := 0.6 + 0.4 * sin(TAU * 37.0 * t * dur) * _rng.randf()
		s[start + i] += hp * sin(PI * t) * grit * amp * 3.0


func _make_ferro_reload() -> void:
	# Latch thrown, barrel drops on its hinge.
	var open := _buf(0.6)
	_metal(open, 0.0, [2650.0, 4120.0, 5900.0], 0.55, 0.012)
	_metal(open, 0.035, [1850.0, 2980.0], 0.35, 0.02)
	_friction(open, 0.06, 0.16, 0.35, 0.35)
	_thud_at(open, 0.2, 140.0, 0.8, 0.05)
	_metal(open, 0.2, [980.0, 1530.0, 2410.0], 0.45, 0.06)
	streams["ferro_open"] = _wav(open)
	# Extractor flicks the spent case out; it pings, then bounces twice.
	var eject := _buf(0.75)
	_metal(eject, 0.0, [3100.0, 4700.0], 0.3, 0.008)
	_metal(eject, 0.03, [3210.0, 5130.0, 7420.0, 9800.0], 0.35, 0.12)
	_metal(eject, 0.42, [3240.0, 5160.0, 7460.0], 0.14, 0.05)
	_friction(eject, 0.42, 0.03, 0.2, 0.6)
	_metal(eject, 0.56, [3260.0, 5190.0], 0.07, 0.035)
	streams["ferro_eject"] = _wav(eject)
	# Fresh shell slides into the chamber and seats.
	var ins := _buf(0.4)
	_friction(ins, 0.0, 0.2, 0.45, 0.25)
	_metal(ins, 0.19, [2350.0, 3780.0], 0.4, 0.025)
	_thud_at(ins, 0.19, 220.0, 0.25, 0.03)
	streams["ferro_insert"] = _wav(ins)
	# Barrel swung shut: heavy lock-up.
	var close := _buf(0.55)
	_friction(close, 0.0, 0.08, 0.25, 0.4)
	_thud_at(close, 0.08, 110.0, 1.1, 0.07)
	_metal(close, 0.08, [1420.0, 2290.0, 3550.0], 0.75, 0.05)
	_metal(close, 0.14, [2900.0, 4300.0], 0.35, 0.015)
	streams["ferro_close"] = _wav(close)
	# Hammer cocked: two quick clicks.
	var ready := _buf(0.25)
	_metal(ready, 0.0, [3400.0, 5200.0], 0.4, 0.008)
	_metal(ready, 0.07, [2700.0, 4400.0], 0.5, 0.012)
	streams["ferro_ready"] = _wav(ready)


func _make_ricochet() -> AudioStreamWAV:
	var dur := 0.45
	var s := _buf(dur)
	var phase := 0.0
	for i in s.size():
		var t := float(i) / RATE
		var f := 3400.0 * exp(-t * 2.5) + 900.0
		phase += TAU * f / RATE
		var env := minf(t * 200.0, 1.0) * exp(-t * 7.0)
		s[i] = (sin(phase) * 0.5 + _rng.randf_range(-1.0, 1.0) * 0.25 * exp(-t * 30.0)) * env * 0.6
	return _wav(s)


## Recorded assets (CC0, see README) override / complement the synthesised set.
## An Array value = random variants.
const FILES := {
	"shot": "res://assets/audio/weapons/ferro_shot_near.wav",
	"shot_far": "res://assets/audio/weapons/ferro_shot_far.wav",
	"ferro_open": "res://assets/audio/foley/shotguncock_00.wav",
	"ferro_insert": "res://assets/audio/foley/equipment_clicks3_18.wav",
	"ferro_close": "res://assets/audio/foley/assaultriflereload1_01.wav",
	"ferro_ready": "res://assets/audio/foley/equipment_clicks3_07.wav",
	"ferro_extract": "res://assets/audio/foley/gunreload1_00.wav",
	"dry": "res://assets/audio/foley/equipment_clicks3_11.wav",
	"item_equip": "res://assets/audio/foley/equipment_clicks3_02.wav",
	"pin_pull": "res://assets/audio/foley/gunreload1_01.wav",
	"explosion": ["res://assets/audio/explosions/explosion1.ogg", "res://assets/audio/explosions/explosion3.ogg"],
	# Layers of the frag blast (rubberduck bangs/cannons CC0, dklon "Boom Pack 1" CC-BY 3.0).
	"expl_crack": ["res://assets/audio/explosions/cannon_01.ogg", "res://assets/audio/explosions/cannon_02.ogg", "res://assets/audio/explosions/cannon_03.ogg",
		"res://assets/audio/explosions/cannon_04.ogg", "res://assets/audio/explosions/cannon_05.ogg", "res://assets/audio/explosions/bang_03.ogg", "res://assets/audio/explosions/bang_05.ogg"],
	"expl_body": ["res://assets/audio/explosions/boom2.wav", "res://assets/audio/explosions/boom3.wav", "res://assets/audio/explosions/boom6.wav",
		"res://assets/audio/explosions/boom8.wav", "res://assets/audio/explosions/boom9.wav", "res://assets/audio/explosions/explosion1.ogg"],
	"expl_tail": ["res://assets/audio/explosions/boom5.wav", "res://assets/audio/explosions/boom7.wav", "res://assets/audio/explosions/boom4.wav"],
	"smoke_pop": "res://assets/audio/explosions/bang_08.ogg",
	"shot_mid": "res://assets/audio/weapons/shotgun_ref.wav",
	"explosion_far": "res://assets/audio/explosions/explosion_far.wav",
	"smoke_hiss": "res://assets/audio/impacts/smoke_hiss.wav",
	"grenade_bounce": ["res://assets/audio/impacts/metal_hit_01.ogg", "res://assets/audio/impacts/metal_hit_03.ogg", "res://assets/audio/impacts/metal_hit_05.ogg"],
	"impact_world": ["res://assets/audio/impacts/rock_hit_01.ogg", "res://assets/audio/impacts/hit_04.ogg"],
	"barricade_place": "res://assets/audio/impacts/metal_falling_02.ogg",
	"barricade_break": "res://assets/audio/impacts/wood_breaking_02.ogg",
	"chest_open": "res://assets/audio/impacts/misc_03.ogg",
}
const MUSIC := {
	"menu": "res://assets/audio/music/synthwave.ogg",
	"match": "res://assets/audio/music/match_ambient.mp3",
}

var _music_a: AudioStreamPlayer
var _music_b: AudioStreamPlayer
var _music_id := ""


func _load_files() -> void:
	for id in FILES:
		var v = FILES[id]
		if v is Array:
			var arr := []
			for p in v:
				if ResourceLoader.exists(p):
					arr.append(load(p))
			if not arr.is_empty():
				streams[id] = arr
		elif ResourceLoader.exists(v):
			streams[id] = load(v)
	_load_sets()
	for bus in ["Music", "SFX"]:
		if AudioServer.get_bus_index(bus) < 0:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, bus)
			AudioServer.set_bus_send(AudioServer.bus_count - 1, "Master")
	# SFX bus: a muffling filter (off; used for the ears ringing after a blast) and
	# a light outdoor reverb so shots and blasts sit in the landscape.
	var sfx := AudioServer.get_bus_index("SFX")
	if AudioServer.get_bus_effect_count(sfx) == 0:
		var lpf := AudioEffectLowPassFilter.new()
		lpf.cutoff_hz = 20000.0
		AudioServer.add_bus_effect(sfx, lpf)
		AudioServer.set_bus_effect_enabled(sfx, 0, false)
		_lowpass_idx = 0
		var rev := AudioEffectReverb.new()
		rev.room_size = 0.55
		rev.damping = 0.7
		rev.wet = 0.09
		rev.dry = 1.0
		rev.spread = 0.8
		AudioServer.add_bus_effect(sfx, rev)
	# Loud layered gunshots: a limiter on the master keeps them punchy without clipping.
	if AudioServer.get_bus_effect_count(0) == 0:
		var lim := AudioEffectHardLimiter.new()
		lim.ceiling_db = -0.5
		lim.pre_gain_db = 0.0
		AudioServer.add_bus_effect(0, lim)
	_music_a = AudioStreamPlayer.new()
	_music_b = AudioStreamPlayer.new()
	for m in [_music_a, _music_b]:
		m.bus = "Music"
		m.volume_db = -80.0
		add_child(m)
		m.finished.connect(func(): if m.volume_db > -60.0: m.play())
	apply_volumes()


## Footstep sets per surface (snow, dirt = dry grass / sand / gravel, stone = concrete),
## and the voices: 4 speakers with two pain grunts and two death cries each.
## Recorded sets (OpenGameArt, CC0): Corsica_S snow, Fantozzi, Thimras, TinyWorlds, HaelDB.
const STEP_SETS := {"step_snow": ["snow", 18], "step_dirt": ["dirt", 10], "step_stone": ["stone", 15]}


func _load_sets() -> void:
	for id in STEP_SETS:
		var arr := []
		for i in range(1, int(STEP_SETS[id][1]) + 1):
			var p := "res://assets/audio/steps/%s_%02d.ogg" % [STEP_SETS[id][0], i]
			if ResourceLoader.exists(p):
				arr.append(load(p))
		if not arr.is_empty():
			streams[id] = arr
	for v in 4:
		for kind in ["pain", "death"]:
			var arr := []
			for s in ["a", "b"]:
				var p := "res://assets/audio/voice/%s_%d_%s.ogg" % [kind, v, s]
				if ResourceLoader.exists(p):
					arr.append(load(p))
			if not arr.is_empty():
				streams["%s_%d" % [kind, v]] = arr
	# Zombie voices (CC0, OpenGameArt, see assets/audio/zombie/LICENSE.txt): random pick per play.
	for set in [["zmb_moan", ["moan", "groan"]], ["zmb_snarl", ["snarl"]], ["zmb_attack", ["attack"]], ["zmb_death", ["death"]]]:
		var arr := []
		for prefix in set[1]:
			for i in range(1, 13):
				var p := "res://assets/audio/zombie/%s_%d.ogg" % [prefix, i]
				if ResourceLoader.exists(p):
					arr.append(load(p))
		if not arr.is_empty():
			streams[set[0]] = arr
	if ResourceLoader.exists("res://assets/audio/ambience/wind.ogg"):
		var wind := load("res://assets/audio/ambience/wind.ogg") as AudioStreamOggVorbis
		if wind:
			wind.loop = true
			streams["wind"] = wind


## A footstep on `surface` ("snow" | "dirt" | "stone" | "metal"), heard up to ~40 m.
func play_step(pos: Vector3, surface: String, volume_db := -12.0) -> void:
	var id := "step_" + ("stone" if surface == "metal" else surface)
	if not streams.has(id):
		id = "step"
	play_3d(id, pos, volume_db, 40.0, 0.07)


## A voice line (kind "pain" | "death") of speaker `voice` (0..3).
func play_voice(kind: String, voice: int, pos: Vector3, volume_db := 0.0, max_dist := 70.0) -> void:
	play_3d("%s_%d" % [kind, voice], pos, volume_db, max_dist, 0.05)


func play_voice_2d(kind: String, voice: int, volume_db := 0.0) -> void:
	play_2d("%s_%d" % [kind, voice], volume_db, randf_range(0.97, 1.03))


# ---- ambience: a wind bed under the match, swelling and dropping in slow gusts
var _amb: AudioStreamPlayer
var _amb_base := -24.0
var _amb_t := 0.0


func start_ambience(biome: String) -> void:
	if not streams.has("wind"):
		return
	if _amb == null:
		_amb = AudioStreamPlayer.new()
		_amb.bus = "SFX"
		add_child(_amb)
	_amb.stream = streams["wind"]
	_amb_base = -14.0 if biome == "snow" else -23.0
	_amb.pitch_scale = 0.82 if biome == "snow" else 1.0
	_amb.volume_db = _amb_base
	_amb.play()


func stop_ambience() -> void:
	if _amb:
		_amb.stop()


var _room := 0.0
var _room_target := 0.0
var _room_t := 0.0


## Indoors (a roof close overhead): the reverb deepens and the wind outside is muffled.
func _update_room(delta: float) -> void:
	_room_t -= delta
	if _room_t <= 0.0:
		_room_t = 0.3
		var cam := get_viewport().get_camera_3d()
		var scene := get_tree().current_scene
		_room_target = 0.0
		if cam and scene is Node3D:
			var space := (scene as Node3D).get_world_3d().direct_space_state
			var q := PhysicsRayQueryParameters3D.create(cam.global_position, cam.global_position + Vector3.UP * 7.0, 1)
			var up := not space.intersect_ray(q).is_empty()
			# Walls close round the listener count too (a room, not just an awning).
			var walls := 0
			for dir in [Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK]:
				if not space.intersect_ray(PhysicsRayQueryParameters3D.create(cam.global_position, cam.global_position + dir * 6.0, 1)).is_empty():
					walls += 1
			_room_target = 1.0 if (up and walls >= 2) else (0.5 if up else 0.0)
	_room = move_toward(_room, _room_target, delta * 1.5)
	var sfx := AudioServer.get_bus_index("SFX")
	if sfx >= 0 and AudioServer.get_bus_effect_count(sfx) > 1:
		var rev := AudioServer.get_bus_effect(sfx, 1) as AudioEffectReverb
		if rev:
			rev.wet = lerpf(0.09, 0.3, _room)
			rev.room_size = lerpf(0.55, 0.72, _room)
			rev.damping = lerpf(0.7, 0.45, _room)


func _process(delta: float) -> void:
	_update_room(delta)
	if _amb and _amb.playing:
		_amb_t += delta
		_amb.volume_db = _amb_base + 3.5 * sin(_amb_t * 0.17) + 2.0 * sin(_amb_t * 0.41 + 1.3) - 7.0 * _room


func apply_volumes() -> void:
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"), linear_to_db(maxf(Game.music_volume, 0.0001)))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("SFX"), linear_to_db(maxf(Game.sfx_volume, 0.0001)))


## Cross-fades to a music track ("" = silence).
## Eases the current music track to `volume_db` (the launch screen starts it low, the menu
## brings it up).
func music_to(volume_db: float, fade := 3.0) -> void:
	for pl in [_music_a, _music_b]:
		if pl.playing and pl.volume_db > -60.0:
			create_tween().tween_property(pl, "volume_db", volume_db, fade)


func play_music(id: String, volume_db := -10.0, fade := 2.0) -> void:
	if id == _music_id:
		return
	_music_id = id
	var old := _music_a if _music_a.playing and _music_a.volume_db > -60.0 else _music_b
	var nxt := _music_b if old == _music_a else _music_a
	if old.playing:
		var tw := create_tween()
		tw.tween_property(old, "volume_db", -80.0, fade)
		tw.tween_callback(old.stop)
	if id != "" and MUSIC.has(id) and ResourceLoader.exists(MUSIC[id]):
		nxt.stream = load(MUSIC[id])
		nxt.volume_db = -50.0
		nxt.play()
		create_tween().tween_property(nxt, "volume_db", volume_db, fade)


func _pick(id: String) -> AudioStream:
	var v = streams.get(id)
	if v is Array:
		return v[_rng.randi() % v.size()]
	return v


func play_3d(id: String, pos: Vector3, volume_db := 0.0, max_dist := 120.0, pitch_var := 0.06, pitch := 1.0) -> void:
	var scene := get_tree().current_scene
	if scene == null or not streams.has(id):
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = _pick(id)
	p.bus = "SFX"
	p.volume_db = volume_db
	p.max_distance = max_dist
	p.unit_size = 8.0
	p.pitch_scale = pitch * (1.0 + _rng.randf_range(-pitch_var, pitch_var))
	p.attenuation_filter_cutoff_hz = 9000.0
	p.panning_strength = 1.35
	# Occlusion: sound behind a wall or building is dulled and quieter, so you hear that it\n	# is *there* without a clear line (and a clear line sounds crisp).
	var occ := _occlusion(scene, pos)
	if occ > 0.0:
		p.attenuation_filter_cutoff_hz = lerpf(9000.0, 900.0, occ)
		p.volume_db -= 5.0 * occ
	scene.add_child(p)
	p.global_position = pos
	p.finished.connect(p.queue_free)
	p.play()


## 0 = clear line to the listener, 1 = fully blocked (two solid layers in between).
func _occlusion(scene: Node, pos: Vector3) -> float:
	var cam := get_viewport().get_camera_3d()
	if cam == null or not (scene is Node3D):
		return 0.0
	var from := cam.global_position
	if from.distance_to(pos) < 3.0 or from.distance_to(pos) > 90.0:
		return 0.0
	var space := (scene as Node3D).get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, pos + Vector3.UP * 0.3, 1)
	var hits := 0
	for i in 2:
		var h := space.intersect_ray(q)
		if h.is_empty():
			break
		hits += 1
		q.from = h.position + (pos - h.position).normalized() * 0.3
	return clampf(hits / 2.0, 0.0, 1.0)


func play_2d(id: String, volume_db := 0.0, pitch := 1.0) -> void:
	if not streams.has(id):
		return
	var p := AudioStreamPlayer.new()
	p.stream = _pick(id)
	p.bus = "SFX"
	p.volume_db = volume_db
	p.pitch_scale = pitch
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()

# ---------------------------------------------------------------- synthesis

func _wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	return w


## Two-tone police-style whistle (prop hunt): rising warble, then a falling tail.
func _make_whistle() -> AudioStreamWAV:
	var s := _buf(1.15)
	var ph := 0.0
	for i in s.size():
		var t := float(i) / RATE
		var f := 1850.0 + 750.0 * smoothstep(0.0, 0.3, t) - 420.0 * smoothstep(0.5, 1.0, t) + 55.0 * sin(TAU * 26.0 * t)
		ph += TAU * f / RATE
		var env := minf(t * 40.0, 1.0) * (1.0 - smoothstep(0.75, 1.15, t))
		var breath := _rng.randf_range(-1.0, 1.0) * 0.06
		s[i] = (sin(ph) * 0.7 + sin(ph * 2.0) * 0.14 + breath) * env * 0.8
	return _wav(s)


func _make_shot() -> AudioStreamWAV:
	var n := int(RATE * 1.1)
	var s := PackedFloat32Array()
	s.resize(n)
	var lp := 0.0
	var lp2 := 0.0
	var phase := 0.0
	for i in n:
		var t := float(i) / RATE
		var white := _rng.randf_range(-1.0, 1.0)
		lp += (white - lp) * 0.35
		lp2 += (white - lp2) * 0.04
		var crack := white * exp(-t * 90.0) * 1.2
		var body := lp * exp(-t * 16.0) * 0.9
		var f := 45.0 + 110.0 * exp(-t * 25.0)
		phase += TAU * f / RATE
		var thump := sin(phase) * exp(-t * 9.0) * 0.9
		var tail := lp2 * exp(-t * 3.2) * 0.9
		s[i] = (crack + body + thump + tail) * 0.8
	return _wav(s)


func _make_shot_far() -> AudioStreamWAV:
	var n := int(RATE * 1.4)
	var s := PackedFloat32Array()
	s.resize(n)
	var lp := 0.0
	var phase := 0.0
	for i in n:
		var t := float(i) / RATE
		lp += (_rng.randf_range(-1.0, 1.0) - lp) * 0.03
		phase += TAU * (40.0 + 40.0 * exp(-t * 8.0)) / RATE
		s[i] = (lp * 3.0 * exp(-t * 2.6) + sin(phase) * exp(-t * 6.0) * 0.6) * 0.8
	return _wav(s)


func _make_click(freq: float, dur: float, amp: float) -> AudioStreamWAV:
	var n := int(RATE * dur)
	var s := PackedFloat32Array()
	s.resize(n)
	var hp_prev := 0.0
	var hp := 0.0
	for i in n:
		var t := float(i) / RATE
		var white := _rng.randf_range(-1.0, 1.0)
		hp = 0.7 * (hp + white - hp_prev)
		hp_prev = white
		var ring := sin(TAU * freq * t) * exp(-t * 60.0) + sin(TAU * freq * 1.47 * t) * exp(-t * 80.0) * 0.5
		s[i] = (hp * exp(-t * 140.0) * 0.9 + ring * 0.6) * amp
	return _wav(s)


func _make_slide() -> AudioStreamWAV:
	var n := int(RATE * 0.22)
	var s := PackedFloat32Array()
	s.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		lp += (_rng.randf_range(-1.0, 1.0) - lp) * 0.25
		var env := sin(PI * t / 0.22)
		s[i] = lp * env * 0.6 + sin(TAU * 900.0 * t) * exp(-maxf(t - 0.18, 0.0) * 200.0) * (1.0 if t > 0.18 else 0.0) * 0.4
	return _wav(s)


func _make_tone(freqs: Array, dur: float, amp: float) -> AudioStreamWAV:
	var n := int(RATE * dur)
	var s := PackedFloat32Array()
	s.resize(n)
	var seg := dur / freqs.size()
	for i in n:
		var t := float(i) / RATE
		var idx := mini(int(t / seg), freqs.size() - 1)
		var lt := t - idx * seg
		var env := minf(lt * 400.0, 1.0) * exp(-lt * 9.0 / seg)
		s[i] = (sin(TAU * freqs[idx] * t) + 0.3 * sin(TAU * freqs[idx] * 2.0 * t)) * env * amp
	return _wav(s)


func _make_thud(dur: float, amp: float) -> AudioStreamWAV:
	var n := int(RATE * dur)
	var s := PackedFloat32Array()
	s.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		lp += (_rng.randf_range(-1.0, 1.0) - lp) * 0.08
		s[i] = (lp * 3.0 + sin(TAU * 90.0 * t) * 0.5) * exp(-t * 30.0 / dur * 0.15) * exp(-t * 18.0) * amp
	return _wav(s)


func _make_noise_swell(dur: float, amp: float) -> AudioStreamWAV:
	var n := int(RATE * dur)
	var s := PackedFloat32Array()
	s.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		lp += (_rng.randf_range(-1.0, 1.0) - lp) * 0.12
		s[i] = lp * sin(PI * t / dur) * amp * 1.5
	return _wav(s)


func _make_bandage() -> AudioStreamWAV:
	var dur := 2.0
	var n := int(RATE * dur)
	var s := PackedFloat32Array()
	s.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		lp += (_rng.randf_range(-1.0, 1.0) - lp) * 0.3
		var wrap := pow(absf(sin(TAU * 2.2 * t)), 3.0)
		var tear := exp(-t * 20.0) * 1.5
		s[i] = lp * (wrap * 0.35 + tear) * 0.6
	return _wav(s)
