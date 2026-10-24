extends SceneTree
## Dev tool: splits the raw gun-handling recordings in assets/audio/foley_src
## into individual events (onset detection on a 5 ms RMS envelope) and writes
## them as assets/audio/foley/<source>_<n>.wav (mono 16-bit). Also prints the
## length / peak of the gunshot files.

const SRC := "res://assets/audio/foley_src/"
const DST := "res://assets/audio/foley/"


func _init() -> void:
	for f in DirAccess.get_files_at(SRC):
		if f.ends_with(".wav"):
			_slice(f)
	for f in ["res://assets/audio/weapons/ferro_shot_near.wav", "res://assets/audio/weapons/ferro_shot_far.wav"]:
		var s := AudioStreamWAV.load_from_file(ProjectSettings.globalize_path(f))
		var mono := _mono(s)
		var peak := 0.0
		var peak_i := 0
		for i in mono.size():
			if absf(mono[i]) > peak:
				peak = absf(mono[i])
				peak_i = i
		print("%s  rate=%d len=%.2fs peak=%.2f at %.3fs fmt=%d stereo=%s" % [f.get_file(), s.mix_rate, mono.size() / float(s.mix_rate), peak, peak_i / float(s.mix_rate), s.format, s.stereo])
		# Trimmed, normalised, 48 kHz mono copy starting just before the shot.
		var rate := s.mix_rate
		var step := maxi(1, rate / 48000)
		var a := maxi(0, peak_i - int(rate * 0.012))
		var length := int(rate * (3.0 if f.contains("near") else 3.6))
		var b := mini(mono.size(), a + length)
		var bytes := PackedByteArray()
		var n_out := (b - a) / step
		bytes.resize(n_out * 2)
		for k in n_out:
			var v := 0.0
			for j in step:
				v += mono[a + k * step + j]
			v /= step
			var t := float(k) / n_out
			var fade := 1.0 - smoothstep(0.75, 1.0, t)
			bytes.encode_s16(k * 2, int(clampf(v / peak * 0.95 * fade, -1.0, 1.0) * 32000.0))
		var w := AudioStreamWAV.new()
		w.format = AudioStreamWAV.FORMAT_16_BITS
		w.mix_rate = rate / step
		w.data = bytes
		w.save_to_wav(ProjectSettings.globalize_path(f.replace(".wav", "_trim.wav")))
	quit()


func _mono(s: AudioStreamWAV) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var data := s.data
	var ch := 2 if s.stereo else 1
	if s.format == AudioStreamWAV.FORMAT_16_BITS:
		var n := data.size() / (2 * ch)
		out.resize(n)
		for i in n:
			var v := 0.0
			for c in ch:
				v += data.decode_s16((i * ch + c) * 2) / 32768.0
			out[i] = v / ch
	elif s.format == AudioStreamWAV.FORMAT_8_BITS:
		var n := data.size() / ch
		out.resize(n)
		for i in n:
			out[i] = data.decode_s8(i * ch) / 128.0
	return out


func _slice(file: String) -> void:
	var s := AudioStreamWAV.load_from_file(ProjectSettings.globalize_path(SRC + file))
	if s == null:
		print("FAIL ", file)
		return
	var x := _mono(s)
	var rate := s.mix_rate
	var win := maxi(1, int(rate * 0.005))
	var env := PackedFloat32Array()
	for i in range(0, x.size() - win, win):
		var e := 0.0
		for j in win:
			e += x[i + j] * x[i + j]
		env.append(sqrt(e / win))
	var peak := 0.0
	for v in env:
		peak = maxf(peak, v)
	var on_th := peak * 0.12
	var off_th := peak * 0.03
	var segs := []
	var i := 0
	while i < env.size():
		if env[i] > on_th:
			var start := maxi(0, i - 2)
			var quiet := 0
			var j := i
			while j < env.size() and quiet < 24:
				quiet = quiet + 1 if env[j] < off_th else 0
				j += 1
			segs.append([start, j - quiet + 6])
			i = j
		else:
			i += 1
	var base := file.get_basename()
	var k := 0
	for sg in segs:
		var a: int = sg[0] * win
		var b: int = mini(sg[1] * win, x.size())
		if b - a < int(rate * 0.03):
			continue
		var seg_peak := 0.0
		for n in range(a, b):
			seg_peak = maxf(seg_peak, absf(x[n]))
		var gain := 0.9 / maxf(seg_peak, 0.001)
		var bytes := PackedByteArray()
		bytes.resize((b - a) * 2)
		for n in range(a, b):
			var fade := minf(1.0, (b - n) / (rate * 0.01))
			bytes.encode_s16((n - a) * 2, int(clampf(x[n] * gain * fade, -1.0, 1.0) * 32000.0))
		var w := AudioStreamWAV.new()
		w.format = AudioStreamWAV.FORMAT_16_BITS
		w.mix_rate = rate
		w.stereo = false
		w.data = bytes
		var out := DST + "%s_%02d.wav" % [base, k]
		w.save_to_wav(ProjectSettings.globalize_path(out))
		print("%s  #%02d  t=%.3fs  len=%.3fs  peak=%.2f" % [file, k, a / float(rate), (b - a) / float(rate), seg_peak])
		k += 1
