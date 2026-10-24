class_name CrosshairPainter
## Draws the configurable crosshair (Game.crosshair) on any CanvasItem.
## Used by the HUD and by the live preview in the crosshair panel.


## `extra_gap`: dynamic spread in px (0 in the preview). `alpha_mul` fades it.
## `blocked` (0..1): the shot would hit something right in front of the muzzle; the
## sights slide sideways and turn amber while the centre dot stays on the aim point.
static func draw(ci: CanvasItem, c_aim: Vector2, cfg: Dictionary, extra_gap := 0.0, alpha_mul := 1.0, blocked := 0.0) -> void:
	var col: Color = cfg.color
	col = col.lerp(Color(1.0, 0.62, 0.15), blocked)
	col.a = float(cfg.opacity) * alpha_mul
	var c := c_aim + Vector2(24.0 * blocked, 0.0)
	var outline := Color(0, 0, 0, col.a * 0.75)
	var th := float(cfg.thickness)
	var length := float(cfg.length)
	var gap := float(cfg.gap) + (extra_gap if cfg.dynamic else 0.0)
	var ol: bool = cfg.outline
	match int(cfg.style):
		0: # cross
			for d in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
				_line(ci, c + d * gap, c + d * (gap + length), col, outline, th, ol)
		1: # T (no top arm)
			for d in [Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
				_line(ci, c + d * gap, c + d * (gap + length), col, outline, th, ol)
		2: # circle
			var r := gap + length * 0.5
			if ol:
				ci.draw_arc(c, r, 0, TAU, 48, outline, th + 2.0, true)
			ci.draw_arc(c, r, 0, TAU, 48, col, th, true)
		3: # dot only (the dot below is forced on)
			pass
		4: # circle + short cross
			var r2 := gap + length
			if ol:
				ci.draw_arc(c, r2, 0, TAU, 48, outline, th + 2.0, true)
			ci.draw_arc(c, r2, 0, TAU, 48, col, th, true)
			for d in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
				_line(ci, c + d * (r2 - length * 0.45), c + d * (r2 + length * 0.45), col, outline, th, ol)
		5: # chevron
			var w := length
			var top := c + Vector2(0, gap)
			for s in [-1.0, 1.0]:
				_line(ci, top, top + Vector2(w * s, w * 0.8), col, outline, th, ol)
	if blocked > 0.01:
		# Small tether back to the aim point so the offset reads as a deliberate warning.
		ci.draw_line(c_aim + Vector2(5.0, 0.0), c - Vector2(2.0, 0.0) + Vector2(0, 0), Color(col.r, col.g, col.b, 0.5 * blocked), 1.5)
	if cfg.dot or int(cfg.style) == 3:
		var ds := maxf(float(cfg.dot_size), 1.0) * (1.6 if int(cfg.style) == 3 else 1.0)
		if ol:
			ci.draw_circle(c_aim, ds + 1.0, outline)
		ci.draw_circle(c_aim, ds, col)


static func _line(ci: CanvasItem, a: Vector2, b: Vector2, col: Color, outline: Color, th: float, ol: bool) -> void:
	if ol:
		var d := (b - a).normalized()
		ci.draw_line(a - d, b + d, outline, th + 2.0)
	ci.draw_line(a, b, col, th)
