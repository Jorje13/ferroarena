class_name ShopPanel
extends PanelContainer
## Zombie survival workbench window: scrap balance and the Shop catalogue, one row per entry
## (name, effect, level, price button). Purchases go through Player.buy (server-checked).

signal closed

var player: Player
var _scrap: Label
var _status: Label
var _rows := {} # id -> {"lvl": Label, "btn": Button}


func _ready() -> void:
	add_theme_stylebox_override("panel", UIStyle.panel(0.9, 0.15))
	set_anchors_preset(Control.PRESET_CENTER)
	offset_left = -380
	offset_right = 380
	offset_top = -330
	offset_bottom = 330
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	var title := UIStyle.label("ÉTABLI", 30, UIStyle.ACCENT, 700)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	_scrap = UIStyle.label("", 24, UIStyle.TEXT, 700)
	head.add_child(_scrap)
	_status = UIStyle.label("", 14, UIStyle.DIM)
	v.add_child(_status)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 4)
	scroll.add_child(list)
	for cat in Shop.CATEGORIES:
		var ch := UIStyle.label(cat[1], 15, UIStyle.ACCENT, 700)
		list.add_child(ch)
		for e in Shop.ENTRIES:
			if e.cat == cat[0]:
				list.add_child(_row(e))
	var close := Button.new()
	close.text = "FERMER  [%s]" % Game.key_label("interact")
	close.pressed.connect(func(): closed.emit())
	v.add_child(close)


func _row(e: Dictionary) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	var sw := ColorRect.new()
	sw.custom_minimum_size = Vector2(4, 0)
	sw.color = Items.color_of(e.id) if Items.color_of(e.id) != Color.WHITE else UIStyle.DIM
	h.add_child(sw)
	var texts := VBoxContainer.new()
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.add_theme_constant_override("separation", 0)
	texts.add_child(UIStyle.label(e.name, 17, UIStyle.TEXT, 600))
	texts.add_child(UIStyle.label(e.info, 13, UIStyle.DIM))
	h.add_child(texts)
	var lvl := UIStyle.label("", 14, UIStyle.DIM)
	lvl.custom_minimum_size = Vector2(70, 0)
	lvl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h.add_child(lvl)
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(130, 0)
	btn.pressed.connect(func():
		if player:
			player.buy(e.id)
			Audio.play_2d("attach_stock", -6.0))
	h.add_child(btn)
	_rows[e.id] = {"lvl": lvl, "btn": btn}
	return h


func open(p: Player) -> void:
	player = p
	if not p.wallet_changed.is_connected(refresh):
		p.wallet_changed.connect(refresh)
	refresh()
	show()


func refresh() -> void:
	if player == null or not is_instance_valid(player):
		return
	_scrap.text = "%d FERRAILLE" % player.scrap
	var open_now := player.arena.can_shop(player)
	_status.text = "Achats possibles entre les vagues." if open_now else "Fermé pendant les vagues — revenez à la pause."
	for e in Shop.ENTRIES:
		var r: Dictionary = _rows[e.id]
		var lv := player.upgrade_level(e.id)
		var price := Shop.cost(e, lv)
		if Shop.is_upgrade(e):
			r.lvl.text = "%d / %d" % [lv, Shop.max_level(e)] if Shop.max_level(e) > 1 else ("ACQUIS" if lv > 0 else "")
		var btn: Button = r.btn
		btn.text = "MAX" if price < 0 else "%d" % price
		btn.disabled = price < 0 or price > player.scrap or not open_now


func _process(_delta: float) -> void:
	if visible:
		refresh()
