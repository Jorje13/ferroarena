class_name CrosshairPanel
extends PanelContainer
## Crosshair editor: style, colour, size, thickness, gap, opacity, outline,
## centre dot, dynamic spread, hit markers; live preview over a scene-like
## backdrop. Changes apply instantly and are saved with the settings.

signal closed

const COLORS := [
	Color(1, 1, 1), Color(0.3, 1.0, 0.35), Color(1.0, 0.95, 0.2), Color(0.2, 0.95, 1.0),
	Color(1.0, 0.3, 0.85), Color(1.0, 0.25, 0.2), Color(0.98, 0.78, 0.25),
]

var _preview: Control
var _controls := {}


func _init() -> void:
	theme = UIStyle.theme()
	add_theme_stylebox_override("panel", UIStyle.panel(0.94, 0.15))
	set_anchors_preset(Control.PRESET_CENTER)
	offset_left = -430
	offset_right = 430
	offset_top = -320
	offset_bottom = 320
	mouse_filter = Control.MOUSE_FILTER_STOP
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	add_child(v)
	v.add_child(UIStyle.label("RÉTICULE", 32, UIStyle.ACCENT, 700))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 18)
	h.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(h)

	_preview = Preview.new()
	_preview.custom_minimum_size = Vector2(300, 300)
	h.add_child(_preview)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	h.add_child(scroll)
	var form := VBoxContainer.new()
	form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form.add_theme_constant_override("separation", 8)
	scroll.add_child(form)

	var style := OptionButton.new()
	for s in Game.CROSSHAIR_STYLES:
		style.add_item(s)
	style.item_selected.connect(func(i): _change("style", i))
	_controls.style = style
	form.add_child(_row("Forme", style))

	var colors := HBoxContainer.new()
	colors.add_theme_constant_override("separation", 6)
	for c in COLORS:
		var b := Button.new()
		b.custom_minimum_size = Vector2(28, 28)
		var sb := StyleBoxFlat.new()
		sb.bg_color = c
		sb.set_border_width_all(2)
		sb.border_color = Color(0, 0, 0, 0.6)
		for st in ["normal", "hover", "pressed"]:
			b.add_theme_stylebox_override(st, sb)
		b.pressed.connect(func(): _change("color", c))
		colors.add_child(b)
	var picker := ColorPickerButton.new()
	picker.custom_minimum_size = Vector2(44, 28)
	picker.edit_alpha = false
	picker.color_changed.connect(func(c): _change("color", c))
	_controls.color = picker
	colors.add_child(picker)
	form.add_child(_row("Couleur", colors))

	_slider(form, "length", "Longueur", 2.0, 30.0, 0.5)
	_slider(form, "thickness", "Épaisseur", 1.0, 6.0, 0.5)
	_slider(form, "gap", "Écart", 0.0, 20.0, 0.5)
	_slider(form, "dot_size", "Taille du point", 1.0, 5.0, 0.1)
	_slider(form, "opacity", "Opacité", 0.2, 1.0, 0.05)
	_check(form, "outline", "Contour noir")
	_check(form, "dot", "Point central")
	_check(form, "dynamic", "Écart dynamique (s'ouvre en mouvement)")
	_check(form, "hitmarker", "Marqueurs de touche")

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 10)
	var reset := Button.new()
	reset.text = "RÉINITIALISER"
	reset.pressed.connect(func():
		Game.crosshair = Game.CROSSHAIR_DEFAULT.duplicate()
		_commit()
		_sync_controls())
	row.add_child(reset)
	var close := Button.new()
	close.text = "FERMER"
	close.pressed.connect(func():
		hide()
		closed.emit())
	row.add_child(close)
	v.add_child(row)
	_sync_controls()


func _row(text: String, control: Control) -> HBoxContainer:
	var r := HBoxContainer.new()
	var l := UIStyle.label(text, 15, UIStyle.TEXT)
	l.custom_minimum_size = Vector2(150, 0)
	r.add_child(l)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.add_child(control)
	return r


func _slider(form: Control, key: String, text: String, lo: float, hi: float, step: float) -> void:
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.custom_minimum_size = Vector2(180, 24)
	s.value_changed.connect(func(x): _change(key, float(x)))
	_controls[key] = s
	form.add_child(_row(text, s))


func _check(form: Control, key: String, text: String) -> void:
	var c := CheckBox.new()
	c.text = text
	c.toggled.connect(func(b): _change(key, b))
	_controls[key] = c
	form.add_child(c)


func _sync_controls() -> void:
	var cfg := Game.crosshair
	for k in _controls:
		var c: Control = _controls[k]
		if c is OptionButton:
			(c as OptionButton).select(int(cfg[k]))
		elif c is HSlider:
			(c as HSlider).set_value_no_signal(float(cfg[k]))
		elif c is CheckBox:
			(c as CheckBox).set_pressed_no_signal(bool(cfg[k]))
		elif c is ColorPickerButton:
			(c as ColorPickerButton).color = cfg[k]
	_preview.queue_redraw()


func _change(key: String, value) -> void:
	Game.crosshair[key] = value
	if key == "color":
		(_controls.color as ColorPickerButton).color = value
	_commit()


func _commit() -> void:
	Game.save_settings()
	Game.crosshair_changed.emit()
	_preview.queue_redraw()


class Preview extends Control:
	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		# Scene-like backdrop: sky, horizon and ground, to judge contrast.
		draw_rect(Rect2(0, 0, size.x, size.y * 0.55), Color(0.55, 0.68, 0.8))
		draw_rect(Rect2(0, size.y * 0.55, size.x, size.y * 0.45), Color(0.52, 0.47, 0.32))
		draw_rect(Rect2(size.x * 0.62, size.y * 0.3, size.x * 0.25, size.y * 0.4), Color(0.28, 0.27, 0.25))
		draw_rect(r, Color(1, 1, 1, 0.2), false, 1.0)
		CrosshairPainter.draw(self, size * 0.5, Game.crosshair, 0.0, 1.0)
		var big := Transform2D(0.0, Vector2(2.5, 2.5), 0.0, Vector2(size.x * 0.2, size.y * 0.2))
		draw_set_transform_matrix(big)
		CrosshairPainter.draw(self, Vector2.ZERO, Game.crosshair, 0.0, 1.0)
		draw_set_transform_matrix(Transform2D.IDENTITY)
