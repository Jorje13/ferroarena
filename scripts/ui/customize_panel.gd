class_name CustomizePanel
extends PanelContainer
## "Armurerie": colour scheme of the trooper (combinaison, armure, équipement).
## Emits `changed` on every edit (the owner previews / applies it) and `closed`.

signal changed(loadout: Dictionary)
signal closed

## The realistic trooper is a single sculpted model: no swappable pieces.
const PIECES := [["skin", "Personnage"], ["weapon", "Fusil"]]
const COLORS := [["suit", "Combinaison", ArmorKit.SUIT_COLORS], ["armor", "Casque & plastron", ArmorKit.ARMOR_COLORS], ["fabric", "Équipement", ArmorKit.FABRIC_COLORS]]

var loadout := {}
var _values := {}
var _swatches := {}


func _init() -> void:
	theme = UIStyle.theme()
	add_theme_stylebox_override("panel", UIStyle.panel(0.88, 0.15))
	mouse_filter = Control.MOUSE_FILTER_STOP
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	add_child(v)
	v.add_child(UIStyle.label("ARMURERIE", 32, UIStyle.ACCENT, 700))
	var hint := UIStyle.label("Choisissez votre personnage et votre fusil. Les teintes ne s'appliquent qu'au Soldat. Les brassards lumineux prennent la couleur de votre équipe.", 13, UIStyle.DIM)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	v.add_child(hint)
	for p in PIECES:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var l := UIStyle.label(p[1], 16, UIStyle.TEXT)
		l.custom_minimum_size = Vector2(150, 0)
		row.add_child(l)
		var prev := Button.new()
		prev.text = "◀"
		prev.pressed.connect(_step.bind(p[0], -1))
		row.add_child(prev)
		var val := UIStyle.label("", 16, UIStyle.TEXT, 600)
		val.custom_minimum_size = Vector2(190, 0)
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.add_child(val)
		_values[p[0]] = val
		var nxt := Button.new()
		nxt.text = "▶"
		nxt.pressed.connect(_step.bind(p[0], 1))
		row.add_child(nxt)
		v.add_child(row)
	for c in COLORS:
		v.add_child(UIStyle.label(c[1], 14, UIStyle.DIM))
		var grid := GridContainer.new()
		grid.columns = 10
		grid.add_theme_constant_override("h_separation", 5)
		grid.add_theme_constant_override("v_separation", 5)
		var list: Array = []
		var palette: Array = c[2]
		for i in palette.size():
			var b := Button.new()
			b.custom_minimum_size = Vector2(34, 26)
			b.tooltip_text = palette[i][0]
			b.pressed.connect(_pick.bind(c[0], i))
			grid.add_child(b)
			list.append(b)
		_swatches[c[0]] = list
		v.add_child(grid)
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 10)
	bottom.alignment = BoxContainer.ALIGNMENT_END
	var rnd := Button.new()
	rnd.text = "ALÉATOIRE"
	rnd.pressed.connect(func():
		loadout = ArmorKit.random_loadout(randi())
		_refresh()
		changed.emit(loadout.duplicate()))
	bottom.add_child(rnd)
	var done := Button.new()
	done.text = "TERMINÉ"
	done.pressed.connect(func():
		hide()
		closed.emit())
	bottom.add_child(done)
	v.add_child(bottom)


func open(l: Dictionary) -> void:
	loadout = ArmorKit.sanitize(l)
	_refresh()
	show()


func _step(slot: String, d: int) -> void:
	loadout[slot] = posmod(int(loadout[slot]) + d, ArmorKit.SLOTS[slot])
	Audio.play_2d("ui", -8.0)
	_refresh()
	changed.emit(loadout.duplicate())


func _pick(slot: String, i: int) -> void:
	loadout[slot] = i
	Audio.play_2d("ui", -8.0)
	_refresh()
	changed.emit(loadout.duplicate())


func _refresh() -> void:
	for s in _values:
		(_values[s] as Label).text = ArmorKit.option_name(s, int(loadout[s])).to_upper()
	for c in COLORS:
		var palette: Array = c[2]
		var list: Array = _swatches[c[0]]
		for i in list.size():
			var sel: bool = int(loadout[c[0]]) == i
			var sb := StyleBoxFlat.new()
			sb.bg_color = palette[i][1]
			sb.set_border_width_all(3 if sel else 1)
			sb.border_color = UIStyle.ACCENT if sel else Color(1, 1, 1, 0.25)
			sb.set_corner_radius_all(3)
			var b: Button = list[i]
			for st in ["normal", "hover", "pressed", "focus", "disabled"]:
				b.add_theme_stylebox_override(st, sb)
			# Only the soldier takes the colour scheme; the other bodies keep their own look.
			b.disabled = int(loadout.skin) != 0
