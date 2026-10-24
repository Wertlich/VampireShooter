class_name LevelUpMenu
extends CanvasLayer
## Pauses the game for level-up cards. A golden "seal" card has no text: it
## shows the weapon and opens a second window with that weapon's seals.

signal chosen(card: Dictionary)

var _cards: Array = []
var _seal_choices: Array = []
var _panels: Array[PanelContainer] = []
var _level: int = 1
var _in_seal_window: bool = false
var _seal_weapon_name: String = ""
var _seal_icon: String = ""

@onready var root: Control = $Root


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false


func open(cards: Array, level: int) -> void:
	_cards = cards
	_level = level
	_in_seal_window = false
	_seal_choices = []
	_build_main()
	visible = true
	root.visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close() -> void:
	visible = false
	root.visible = false
	_in_seal_window = false
	_seal_choices = []
	_cards = []
	get_tree().paused = false
	if DisplayServer.get_name() != "headless" and not "--capture" in OS.get_cmdline_user_args():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var key := (event as InputEventKey).physical_keycode
		if key == KEY_ESCAPE:
			if _in_seal_window:
				_back_to_main()
				get_viewport().set_input_as_handled()
			return

		var index := -1
		match key:
			KEY_1:
				index = 0
			KEY_2:
				index = 1
			KEY_3:
				index = 2
		var count := _seal_choices.size() if _in_seal_window else _cards.size()
		if index >= 0 and index < count:
			_choose(index)
			get_viewport().set_input_as_handled()


func _choose(index: int) -> void:
	if _in_seal_window:
		if index < 0 or index >= _seal_choices.size():
			return
		var seal_card: Dictionary = _seal_choices[index]
		_seal_choices = []
		_in_seal_window = false
		_cards = []
		chosen.emit(seal_card)
		return

	if index < 0 or index >= _cards.size():
		return
	var card: Dictionary = _cards[index]
	if bool(card.get("seal", false)):
		_open_seal_window(card)
		return
	_cards = []
	chosen.emit(card)


## Turns the sealed entry card into the dedicated seal picker for one weapon.
func _open_seal_window(seal: Dictionary) -> void:
	var choices: Array[Dictionary] = []
	for card in seal.get("seal_cards", []):
		choices.append((card as Dictionary).duplicate(true))
	if choices.is_empty():
		return
	_seal_choices = choices
	_in_seal_window = true
	_seal_weapon_name = String(seal.get("weapon_name", ""))
	_seal_icon = String(seal.get("icon", ""))
	_build_seal_window()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _back_to_main() -> void:
	_in_seal_window = false
	_seal_choices = []
	_build_main()


# --- UI construction --------------------------------------------------------

func _clear_root() -> void:
	for child in root.get_children():
		child.queue_free()
	_panels.clear()


func _build_main() -> void:
	_clear_root()

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
	title.text = "УРОВЕНЬ %d" % _level
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


func _build_seal_window() -> void:
	_clear_root()

	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.012, 0.005, 0.92)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	center.add_child(column)

	if _seal_icon != "":
		var texture := load(_seal_icon) as Texture2D
		if texture:
			var icon := TextureRect.new()
			icon.texture = texture
			icon.custom_minimum_size = Vector2(300, 150)
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			column.add_child(icon)

	var title := Label.new()
	title.text = "ПЕЧАТИ · %s" % _seal_weapon_name.to_upper()
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 36)
	title.add_theme_color_override("font_color", UNIQUE_GOLD)
	column.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "выбери одну печать для этого оружия"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 17)
	subtitle.add_theme_color_override("font_color", Color(0.82, 0.74, 0.58, 0.95))
	column.add_child(subtitle)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(row)

	for i in _seal_choices.size():
		row.add_child(_make_card(_seal_choices[i], i))

	var hint := Label.new()
	hint.text = "клик · клавиши 1–%d · Esc — назад" % _seal_choices.size()
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", Color(0.72, 0.64, 0.5, 0.8))
	column.add_child(hint)


func _make_card(card: Dictionary, index: int) -> PanelContainer:
	if bool(card.get("seal", false)):
		return _make_seal_card(card, index)

	var accent: Color = card.get("accent", Color(0.8, 0.8, 0.9))
	var golden := bool(card.get("golden", bool(card.get("unique", false))))
	var panel := _new_card_panel(accent, golden, index)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(column)

	var tag := Label.new()
	tag.text = ("★ " if golden else "") + String(card.get("tag", "")).to_upper()
	tag.add_theme_font_size_override("font_size", 14 if golden else 13)
	tag.add_theme_color_override("font_color", accent)
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(tag)

	var title := Label.new()
	title.text = String(card.get("title", ""))
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color",
		Color(1.0, 0.94, 0.72) if golden else Color(1.0, 0.96, 0.9))
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(title)

	var desc := Label.new()
	desc.text = String(card.get("desc", ""))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	desc.add_theme_font_size_override("font_size", 16)
	desc.add_theme_color_override("font_color",
		Color(0.94, 0.86, 0.67, 0.96) if golden else Color(0.8, 0.79, 0.84, 0.95))
	desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(desc)

	var key := Label.new()
	key.text = "%d" % (index + 1)
	key.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	key.add_theme_font_size_override("font_size", 22)
	key.add_theme_color_override("font_color",
		Color(accent.r, accent.g, accent.b, 0.85) if golden
		else Color(accent.r, accent.g, accent.b, 0.7))
	key.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(key)

	return panel


## The entry card is deliberately textless: golden frame plus weapon render.
func _make_seal_card(card: Dictionary, index: int) -> PanelContainer:
	var panel := _new_card_panel(UNIQUE_GOLD, true, index)
	var image := TextureRect.new()
	var icon_path := String(card.get("icon", ""))
	if icon_path != "":
		image.texture = load(icon_path) as Texture2D
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	image.size_flags_vertical = Control.SIZE_EXPAND_FILL
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(image)
	return panel


func _new_card_panel(accent: Color, golden: bool, index: int) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(300, 340)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.add_theme_stylebox_override("panel", _card_style(accent, false, golden))
	panel.mouse_entered.connect(func() -> void:
		panel.add_theme_stylebox_override("panel", _card_style(accent, true, golden)))
	panel.mouse_exited.connect(func() -> void:
		panel.add_theme_stylebox_override("panel", _card_style(accent, false, golden)))
	panel.gui_input.connect(_on_card_input.bind(index))
	_panels.append(panel)
	if golden:
		var pulse := panel.create_tween().set_loops()
		pulse.tween_property(panel, "modulate", Color(1.0, 0.92, 0.62), 0.85) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		pulse.tween_property(panel, "modulate", Color.WHITE, 0.85) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	return panel


const UNIQUE_GOLD := Color(1.0, 0.79, 0.26, 1.0)


func _card_style(accent: Color, hover: bool, golden: bool = false) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	if golden:
		style.bg_color = Color(0.16, 0.11, 0.035, 0.99) if hover else Color(0.11, 0.075, 0.02, 0.98)
	else:
		style.bg_color = Color(0.09, 0.08, 0.12, 0.98) if hover else Color(0.06, 0.055, 0.08, 0.97)
	var border := 3 if golden else 2
	style.border_width_left = border
	style.border_width_right = border
	style.border_width_top = border
	style.border_width_bottom = border
	if golden:
		style.border_color = Color(1.0, 0.83, 0.38, 1.0 if hover else 0.8)
		style.shadow_color = Color(1.0, 0.62, 0.12, 0.45 if hover else 0.28)
		style.shadow_size = 22 if hover else 16
	else:
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
