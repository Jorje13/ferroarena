class_name KeybindMenu
extends PanelContainer
## Key / mouse rebinding panel (two slots per action). Click a slot, then press
## a key or mouse button. Échap cancels, Suppr / Retour arrière clears the slot.

signal closed

var _grid: GridContainer
var _hint: Label
var _listen_action := ""
var _listen_idx := -1
var _listen_btn: Button
var _armed := false


func _init() -> void:
	theme = UIStyle.theme()
	add_theme_stylebox_override("panel", UIStyle.panel(0.92, 0.15))
	set_anchors_preset(Control.PRESET_CENTER)
	offset_left = -380
	offset_right = 380
	offset_top = -330
	offset_bottom = 330
	mouse_filter = Control.MOUSE_FILTER_STOP
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	add_child(v)
	v.add_child(UIStyle.label("TOUCHES", 32, UIStyle.ACCENT, 700))
	_hint = UIStyle.label("Cliquez sur un emplacement puis appuyez sur une touche ou un bouton de souris.", 14, UIStyle.DIM)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	v.add_child(_hint)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	_grid = GridContainer.new()
	_grid.columns = 3
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 12)
	_grid.add_theme_constant_override("v_separation", 6)
	scroll.add_child(_grid)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 10)
	var reset := Button.new()
	reset.text = "RÉINITIALISER"
	reset.pressed.connect(func():
		_cancel()
		Game.reset_bindings())
	row.add_child(reset)
	var close := Button.new()
	close.text = "FERMER"
	close.pressed.connect(func():
		_cancel()
		hide()
		closed.emit())
	row.add_child(close)
	v.add_child(row)
	Game.bindings_changed.connect(_rebuild)
	_rebuild()


func is_listening() -> bool:
	return _listen_idx >= 0


func _rebuild() -> void:
	for c in _grid.get_children():
		c.queue_free()
	for a in Game.ACTIONS:
		var action: String = a[0]
		var l := UIStyle.label(a[1], 16, UIStyle.TEXT)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_grid.add_child(l)
		for i in 2:
			var b := Button.new()
			b.custom_minimum_size = Vector2(170, 0)
			b.text = Game.slot_label(Game.bindings[action][i])
			b.pressed.connect(_start_listen.bind(action, i, b))
			_grid.add_child(b)


func _start_listen(action: String, idx: int, btn: Button) -> void:
	_cancel()
	_listen_action = action
	_listen_idx = idx
	_listen_btn = btn
	btn.text = "…"
	_hint.text = "Appuyez sur une touche ou un bouton de souris  (Échap : annuler · Suppr : effacer)"
	_armed = false
	# Arm on the next frame so the click that opened listening isn't captured.
	get_tree().process_frame.connect(func(): _armed = true, CONNECT_ONE_SHOT)


func _cancel() -> void:
	if _listen_idx >= 0 and is_instance_valid(_listen_btn):
		_listen_btn.text = Game.slot_label(Game.bindings[_listen_action][_listen_idx])
	_listen_idx = -1
	_listen_action = ""
	_hint.text = "Cliquez sur un emplacement puis appuyez sur une touche ou un bouton de souris."


func _input(event: InputEvent) -> void:
	if _listen_idx < 0 or not _armed or not is_visible_in_tree():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		get_viewport().set_input_as_handled()
		var code: int = event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode
		if code == KEY_ESCAPE:
			_cancel()
		elif code == KEY_DELETE or code == KEY_BACKSPACE:
			_commit([])
		else:
			_commit(["key", code])
	elif event is InputEventMouseButton and event.pressed:
		get_viewport().set_input_as_handled()
		_commit(["mouse", event.button_index])


func _commit(slot: Array) -> void:
	var action := _listen_action
	var idx := _listen_idx
	_listen_idx = -1
	_listen_action = ""
	Game.set_binding(action, idx, slot)
	Audio.play_2d("ui", -8.0)
