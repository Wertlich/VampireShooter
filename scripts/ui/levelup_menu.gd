class_name LevelUpMenu
extends CanvasLayer
## Pauses the game and offers three cards: unlock a weapon or upgrade one.

signal chosen(card: Dictionary)

var _cards: Array = []
var _panels: Array[PanelContainer] = []

@onready var root: Control = $Root


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false


func open(cards: Array, level: int) -> void:
	_cards = cards
	_build(level)
	visible = true
	root.visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close() -> void:
	visible = false
	root.visible = false
	get_tree().paused = false
	if DisplayServer.get_name() != "headless" and not "--capture" in OS.get_cmdline_user_args():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var index := -1
		match (event as InputEventKey).physical_keycode:
			KEY_1:
				index = 0
			KEY_2:
				index = 1
			KEY_3:
				index = 2
		if index >= 0 and index < _cards.size():
			_choose(index)
			get_viewport().set_input_as_handled()


func _choose(index: int) -> void:
	if index < 0 or index >= _cards.size():
		return
	var card: Dictionary = _cards[index]
	_cards = []
	chosen.emit(card)


# --- UI construction --------------------------------------------------------

func _build(level: int) -> void:
	for child in root.get_children():
		child.queue_free()
	_panels.clear()

	var dim := ColorRect.new()
	dim.color = Color(0.015, 0.01, 0.025, 0.86)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 18)
	center.add_child(column)

	var title := Label.new()
	title.text = "УРОВЕНЬ %d" % level
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 38)
	title.add_theme_color_override("font_color", Color(1.0, 0.86, 0.55))
	column.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "выбери одно улучшение"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 17)
	subtitle.add_theme_color_override("font_color", Color(0.75, 0.72, 0.8, 0.9))
	column.add_child(subtitle)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(row)

	for i in _cards.size():
		row.add_child(_make_card(_cards[i], i))

	var hint := Label.new()
	hint.text = "клик мышью или клавиши 1 · 2 · 3"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", Color(0.6, 0.58, 0.65, 0.8))
	column.add_child(hint)


func _make_card(card: Dictionary, index: int) -> PanelContainer:
	var accent: Color = card.get("accent", Color(0.8, 0.8, 0.9))

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(300, 340)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.add_theme_stylebox_override("panel", _card_style(accent, false))
	panel.mouse_entered.connect(func() -> void:
		panel.add_theme_stylebox_override("panel", _card_style(accent, true)))
	panel.mouse_exited.connect(func() -> void:
		panel.add_theme_stylebox_override("panel", _card_style(accent, false)))
	panel.gui_input.connect(_on_card_input.bind(index))
	_panels.append(panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(column)

	var tag := Label.new()
	tag.text = String(card.get("tag", "")).to_upper()
	tag.add_theme_font_size_override("font_size", 13)
	tag.add_theme_color_override("font_color", accent)
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(tag)

	var title := Label.new()
	title.text = String(card.get("title", ""))
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(1.0, 0.96, 0.9))
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(title)

	var desc := Label.new()
	desc.text = String(card.get("desc", ""))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	desc.add_theme_font_size_override("font_size", 16)
	desc.add_theme_color_override("font_color", Color(0.8, 0.79, 0.84, 0.95))
	desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(desc)

	var key := Label.new()
	key.text = "%d" % (index + 1)
	key.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	key.add_theme_font_size_override("font_size", 22)
	key.add_theme_color_override("font_color", Color(accent.r, accent.g, accent.b, 0.7))
	key.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(key)

	return panel


func _card_style(accent: Color, hover: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.09, 0.08, 0.12, 0.98) if hover else Color(0.06, 0.055, 0.08, 0.97)
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = accent if hover else Color(accent.r, accent.g, accent.b, 0.45)
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_left = 12
	style.corner_radius_bottom_right = 12
	style.content_margin_left = 20
	style.content_margin_right = 20
	style.content_margin_top = 18
	style.content_margin_bottom = 18
	return style


func _on_card_input(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton:
		var click := event as InputEventMouseButton
		if click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
			_choose(index)
			get_viewport().set_input_as_handled()
