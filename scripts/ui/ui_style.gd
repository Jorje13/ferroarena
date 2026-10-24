class_name UIStyle
## Shared look for menus and HUD (condensed type, dark glass panels).

const TEXT := Color(0.93, 0.92, 0.88)
const DIM := Color(0.93, 0.92, 0.88, 0.55)
const ACCENT := Color(0.98, 0.78, 0.25)
const HEALTH := Color(0.36, 0.86, 0.92)
const DANGER := Color(0.95, 0.3, 0.25)
const SHIELD := Color(0.35, 0.72, 1.0)

static var _theme: Theme


static func font(weight := 500) -> Font:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Bahnschrift", "DIN Alternate", "Roboto Condensed", "Segoe UI", "Arial"])
	f.font_weight = weight
	f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	var v := FontVariation.new()
	v.base_font = f
	v.spacing_glyph = 1
	return v


static func panel(alpha := 0.55, border := 0.12) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.04, 0.05, 0.06, alpha)
	s.border_color = Color(1, 1, 1, border)
	s.set_border_width_all(1)
	s.set_corner_radius_all(2)
	s.content_margin_left = 12
	s.content_margin_right = 12
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	return s


static func theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font = font(500)
	t.default_font_size = 18
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_outline_color", "Label", Color(0, 0, 0, 0.55))
	t.set_constant("outline_size", "Label", 4)

	var btn := StyleBoxFlat.new()
	btn.bg_color = Color(0.08, 0.09, 0.1, 0.8)
	btn.border_color = Color(1, 1, 1, 0.15)
	btn.set_border_width_all(1)
	btn.content_margin_left = 18
	btn.content_margin_right = 18
	btn.content_margin_top = 10
	btn.content_margin_bottom = 10
	var hover := btn.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.98, 0.78, 0.25, 0.92)
	hover.border_color = Color(1, 0.9, 0.5, 1)
	var pressed := hover.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.85, 0.65, 0.15, 1)
	var disabled := btn.duplicate() as StyleBoxFlat
	disabled.bg_color = Color(0.08, 0.09, 0.1, 0.4)
	for type in ["Button", "OptionButton", "CheckBox"]:
		t.set_stylebox("normal", type, btn)
		t.set_stylebox("hover", type, hover)
		t.set_stylebox("pressed", type, pressed)
		t.set_stylebox("focus", type, StyleBoxEmpty.new())
		t.set_stylebox("disabled", type, disabled)
		t.set_color("font_color", type, TEXT)
		t.set_color("font_hover_color", type, Color(0.05, 0.05, 0.05))
		t.set_color("font_pressed_color", type, Color(0.05, 0.05, 0.05))
		t.set_color("font_hover_pressed_color", type, Color(0.05, 0.05, 0.05))
		t.set_color("font_disabled_color", type, DIM)
	var field := StyleBoxFlat.new()
	field.bg_color = Color(0, 0, 0, 0.5)
	field.border_color = Color(1, 1, 1, 0.2)
	field.set_border_width_all(1)
	field.content_margin_left = 10
	field.content_margin_right = 10
	field.content_margin_top = 6
	field.content_margin_bottom = 6
	t.set_stylebox("normal", "LineEdit", field)
	t.set_stylebox("focus", "LineEdit", field)
	t.set_stylebox("normal", "SpinBox", field)
	t.set_stylebox("panel", "PanelContainer", panel())
	t.set_stylebox("panel", "PopupMenu", panel(0.95))
	var grab := StyleBoxFlat.new()
	grab.bg_color = ACCENT
	grab.set_content_margin_all(3)
	var slider := StyleBoxFlat.new()
	slider.bg_color = Color(1, 1, 1, 0.2)
	slider.content_margin_top = 2
	slider.content_margin_bottom = 2
	t.set_stylebox("slider", "HSlider", slider)
	t.set_stylebox("grabber_area", "HSlider", grab)
	t.set_stylebox("grabber_area_highlight", "HSlider", grab)
	_theme = t
	return t


static func label(text: String, size := 18, color := TEXT, weight := 500) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if weight != 500:
		l.add_theme_font_override("font", font(weight))
	return l
