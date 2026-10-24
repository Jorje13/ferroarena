extends SceneTree
## Length / peak / low-vs-high energy of loose audio files (wav only for levels).
## Usage: -s tools/audio_stats.gd -- --dir=path


func _initialize() -> void:
	var dir := "res://assets/audio"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--dir="):
			dir = a.get_slice("=", 1)
	_scan(dir)
	quit()


func _scan(dir: String) -> void:
	for f in DirAccess.get_files_at(dir):
		var path := dir.path_join(f)
		var ext := f.get_extension().to_lower()
		if ext == "ogg":
			var s := AudioStreamOggVorbis.load_from_file(path)
			if s:
				print("%-40s ogg  %.2f s" % [f, s.get_length()])
		elif ext == "wav":
			var b := FileAccess.get_file_as_bytes(path)
			var w := AudioStreamWAV.load_from_buffer(b)
			if w == null:
				continue
			print("%-40s wav  %.2f s  %s" % [f, w.get_length(), _levels(w)])
		elif ext == "mp3":
			var s2 := AudioStreamMP3.load_from_file(path)
			if s2:
				print("%-40s mp3  %.2f s" % [f, s2.get_length()])
	for d in DirAccess.get_directories_at(dir):
		_scan(dir.path_join(d))


func _levels(w: AudioStreamWAV) -> String:
	if w.format != AudioStreamWAV.FORMAT_16_BITS:
		return "fmt %d" % w.format
	var data := w.data
	var step := 2 * (2 if w.stereo else 1)
	var n := data.size() / step
	var peak := 0.0
	var lo := 0.0
	var hi := 0.0
	var lp := 0.0
	var e := 0.0
	for i in n:
		var v := data.decode_s16(i * step) / 32768.0
		peak = maxf(peak, absf(v))
		lp += (v - lp) * 0.04 # ~ <300 Hz at 44.1 kHz
		lo += lp * lp
		hi += (v - lp) * (v - lp)
		e += v * v
	return "peak %.2f rms %.3f low/high %.2f" % [peak, sqrt(e / maxf(n, 1.0)), lo / maxf(hi, 0.000001)]
