class_name DebugConsole
extends CanvasLayer
## Debug console on "/": hand out weapons and stop the horde's brain.
##
## Commands are executed on this machine only. It pauses the run while open so
## the player can type without being clawed, then restores the previous pause
## state (a level-up or death screen may already own the pause).

const PANEL_BG := Color(0.045, 0.04, 0.06, 0.97)
const TEXT := Color(0.9, 0.91, 0.96, 1.0)
const MUTED := Color(0.62, 0.62, 0.72, 1.0)
const ACCENT := Color(0.55, 0.8, 1.0, 1.0)
const GOLD := Color(1.0, 0.86, 0.55, 1.0)
const ERROR := Color(1.0, 0.45, 0.4, 1.0)

## Human aliases per weapon slot; node names and display names also match.
const WEAPON_ALIASES := {
	0: ["revolver", "револьвер", "магнум", "magnum", "пистолет"],
	1: ["shotgun", "дробовик", "двустволка", "двухстволка", "double"],
	2: ["akm", "акм", "ak", "автомат"],
	3: ["svd", "свд", "sniper", "снайпер", "винтовка"],
	4: ["rpd", "рпд", "пулемет", "пулемёт", "lmg"],
	5: ["saiga", "сайга", "saiga12", "сайга12"],
	6: ["mp9", "пп", "smg", "пистолетпулемет"],
}

var _line: LineEdit
var _log: RichTextLabel
var _greeted: bool = false
## Whether this console paused the tree itself (it must not unpause a card menu).
var _own_pause: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 20
	_build()
	visible = false


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_console"):
		if not visible:
			open()
		# While open the slash goes into the line as a normal character.
		get_viewport().set_input_as_handled()
		return
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func open() -> void:
	if visible:
		return
	_own_pause = not get_tree().paused
	if _own_pause:
		get_tree().paused = true
	visible = true
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if not _greeted:
		_greeted = true
		_show_help()
	_line.text = "/"
	_line.grab_focus()
	_line.caret_column = _line.text.length()


func close() -> void:
	if not visible:
		return
	visible = false
	_line.release_focus()
	if _own_pause:
		_own_pause = false
		get_tree().paused = false
		if DisplayServer.get_name() != "headless":
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# --- Commands ---------------------------------------------------------------

func _on_submitted(text: String) -> void:
	_line.text = "/"
	_line.caret_column = 1
	_line.grab_focus()
	_run(text)


func _run(raw: String) -> void:
	var text := raw.strip_edges()
	if text.is_empty() or text == "/":
		return
	if text.begins_with("/"):
		text = text.substr(1)
	var parts := text.split(" ", false)
	if parts.is_empty():
		return
	var command := parts[0].to_lower()
	var args := parts.slice(1)

	match command:
		"help", "?", "помощь":
			_show_help()
		"get", "give", "выдать", "дать":
			_cmd_get(args)
		"stopmobs", "stop", "стопмобы", "заморозить":
			_cmd_stopmobs(args)
		"clear", "cls", "очистить":
			_log.clear()
		_:
			_print("Неизвестная команда: %s — введите /help" % command, ERROR)


func _cmd_get(args: PackedStringArray) -> void:
	var player := Net.local_player() as Player
	if player == null:
		_print("Игрок ещё не появился", ERROR)
		return
	var viewmodel: Viewmodel = player.viewmodel
	var names := _split_args(args)
	if names.is_empty():
		_print("Укажите оружие: /get <имя>[,<имя>] или /get all", MUTED)
		_print(_weapon_list(viewmodel), MUTED)
		return

	var last_index := -1
	for name in names:
		if name in ["all", "все", "всё", "*"]:
			for i in viewmodel.weapons.size():
				viewmodel.unlock(i)
			last_index = viewmodel.weapons.size() - 1
			_print("Выдано всё оружие", ACCENT)
			continue
		var index := _find_weapon(viewmodel, name)
		if index < 0:
			_print("Не знаю оружие «%s»" % name, ERROR)
			continue
		var weapon: Weapon = viewmodel.weapons[index]
		if viewmodel.is_unlocked(index):
			_print("%s уже есть" % weapon.display_name, MUTED)
		else:
			viewmodel.unlock(index)
			_print("Выдано: %s" % weapon.display_name, ACCENT)
		last_index = index

	if last_index >= 0:
		player.switch_to(last_index)


func _cmd_stopmobs(args: PackedStringArray) -> void:
	var value := not Enemy.ai_frozen
	if not args.is_empty():
		match args[0].to_lower():
			"on", "1", "true", "вкл", "да":
				value = true
			"off", "0", "false", "выкл", "нет":
				value = false
			_:
				_print("Использование: /stopmobs [on|off]", ERROR)
				return

	Enemy.ai_frozen = value
	if value:
		_print("Разум мобов остановлен", GOLD)
	else:
		_print("Мобы снова думают", ACCENT)


func _show_help() -> void:
	_print("Команды:", GOLD)
	_print("  /get <оружие>[,<оружие>] — выдать оружие (можно /get all)", TEXT)
	_print("  /stopmobs [on|off] — заморозить или вернуть разум мобов", TEXT)
	_print("  /clear — очистить консоль", TEXT)
	var player := Net.local_player() as Player
	if player != null:
		_print("  Оружие: " + _weapon_list(player.viewmodel), MUTED)


func _weapon_list(viewmodel: Viewmodel) -> String:
	var names: Array[String] = []
	for weapon in viewmodel.weapons:
		names.append(weapon.display_name)
	return ", ".join(names)


# --- Helpers ----------------------------------------------------------------

func _split_args(args: PackedStringArray) -> PackedStringArray:
	var raw := " ".join(args).replace(",", " ")
	var names: PackedStringArray = []
	for part in raw.split(" ", false):
		var name := part.strip_edges()
		if not name.is_empty():
			names.append(name)
	return names


func _find_weapon(viewmodel: Viewmodel, query: String) -> int:
	if query.is_valid_int():
		var numeric := int(query) - 1
		return numeric if viewmodel.has_weapon(numeric) else -1

	var wanted := _normalize(query)
	for i in viewmodel.weapons.size():
		var weapon: Weapon = viewmodel.weapons[i]
		if wanted == _normalize(weapon.name) or wanted == _normalize(weapon.display_name):
			return i
		for alias in WEAPON_ALIASES.get(i, []):
			if wanted == _normalize(alias):
				return i
	return -1


func _normalize(text: String) -> String:
	var out := text.to_lower().replace("ё", "е")
	for junk in [" ", "-", "_", ".", "«", "»", "\"", "'"]:
		out = out.replace(junk, "")
	return out


func _print(text: String, color: Color = TEXT) -> void:
	_log.append_text("[color=#%s]%s[/color]\n" % [color.to_html(false), text])


# --- UI ---------------------------------------------------------------------

func _build() -> void:
	var root := Control.new()
	root.name = "Root"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	margin.offset_left = 24
	margin.offset_top = -320
	margin.offset_right = -24
	margin.offset_bottom = -24
	root.add_child(margin)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_style())
	margin.add_child(panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	panel.add_child(column)

	var header := HBoxContainer.new()
	column.add_child(header)

	var title := Label.new()
	title.text = "КОНСОЛЬ"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", GOLD)
	header.add_child(title)

	var hint := Label.new()
	hint.text = "Enter — выполнить · Esc — закрыть"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", MUTED)
	header.add_child(hint)

	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.scroll_following = true
	_log.custom_minimum_size = Vector2(0, 200)
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log.add_theme_font_size_override("normal_font_size", 17)
	_log.add_theme_color_override("default_color", TEXT)
	column.add_child(_log)

	_line = LineEdit.new()
	_line.text = "/"
	_line.placeholder_text = "/get revolver,saiga"
	_line.custom_minimum_size = Vector2(0, 38)
	_line.add_theme_font_size_override("font_size", 20)
	_line.add_theme_color_override("font_color", TEXT)
	_line.add_theme_color_override("caret_color", ACCENT)
	_line.add_theme_stylebox_override("normal", _line_style(Color(0.55, 0.8, 1.0, 0.25)))
	_line.add_theme_stylebox_override("focus", _line_style(ACCENT))
	_line.text_submitted.connect(_on_submitted)
	column.add_child(_line)


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_BG
	style.border_color = Color(0.55, 0.8, 1.0, 0.4)
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.content_margin_left = 16
	style.content_margin_top = 12
	style.content_margin_right = 16
	style.content_margin_bottom = 14
	return style


func _line_style(border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.02, 0.03, 0.95)
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(5)
	style.content_margin_left = 10
	style.content_margin_right = 10
	return style
