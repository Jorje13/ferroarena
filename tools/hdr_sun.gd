extends SceneTree
## Dev tool: finds the sun in each HDRI and prints the direction (Godot panorama
## convention) so the DirectionalLight can match the sky.


func _init() -> void:
	var dir := "res://assets/polyhaven/hdri"
	for f in DirAccess.get_files_at(dir):
		if not f.ends_with(".hdr"):
			continue
		var img := Image.load_from_file(ProjectSettings.globalize_path(dir + "/" + f))
		var best := 0.0
		var bx := 0
		var by := 0
		var avg := Color()
		for y in range(0, img.get_height() / 2, 2):
			for x in range(0, img.get_width(), 2):
				var c := img.get_pixel(x, y)
				avg += c
				var l := c.r + c.g + c.b
				if l > best:
					best = l
					bx = x
					by = y
		var u := (bx + 0.5) / img.get_width()
		var v := (by + 0.5) / img.get_height()
		var theta := v * PI
		var phi := u * TAU - PI
		var d := Vector3(sin(theta) * sin(phi), cos(theta), -sin(theta) * cos(phi))
		print("%s  peak=%.1f  px=(%d,%d)  sun_dir=%s  elev=%.1f deg" % [f, best, bx, by, d, rad_to_deg(asin(d.y))])
	quit()
