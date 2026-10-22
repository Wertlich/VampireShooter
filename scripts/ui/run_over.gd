class_name RunOver
extends CanvasLayer
## Death screen: pauses the arena, shows the run's numbers, restarts on R / click.
##
## Cleared maps do not end the run yet: there is only one map so far, so the
## wave manager simply stops spawning after the last wave.

@onready var root: Control = $Root

var _shown: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	root.visible = false


func show_death(wave: int, total: int, level: int, kills: int) -> void:
	_show(
		"ВЫ ПОГИБЛИ",
		"орда оказалась сильнее",
		Color(1.0, 0.38, 0.32),
		wave, total, level, kills
	)


func _unhandled_input(event: InputEvent) -> void:
	if not _shown:
		return
	var restart := false
	if event is InputEventKey:
		var key := event as InputEventKey
		restart = key.pressed and not key.echo and key.physical_keycode == KEY_R
	elif event is InputEventMouseButton:
		var click := event as InputEventMouseButton
		restart = click.pressed and click.button_index == MOUSE_BUTTON_LEFT
	if restart:
		# Mark the input handled before restarting: reloading the scene frees
		# this node, and get_viewport() would come back null afterwards.
		var viewport := get_viewport()
		if viewport:
			viewport.set_input_as_handled()
		_restart()


func _restart() -> void:
	_shown = false
	visible = false
	root.visible = false
	get_tree().paused = false
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	get_tree().reload_current_scene()


# --- UI ---------------------------------------------------------------------

func _show(title: String, subtitle: String, accent: Color,
		wave: int, total: int, level: int, kills: int) -> void:
	if _shown:
		return
	_shown = true
	_build(title, subtitle, accent, wave, total, level, kills)
	visible = true
	root.visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _build(title: String, subtitle: String, accent: Color,
		wave: int, total: int, level: int, kills: int) -> void:
	for child in root.get_children():
		child.queue_free()

	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.01, 0.02, 0.88)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	center.add_child(column)

	var big := Label.new()
	big.text = title
	big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	big.add_theme_font_size_override("font_size", 56)
	big.add_theme_color_override("font_color", accent)
	column.add_child(big)

	var sub := Label.new()
	sub.text = subtitle
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 18)
	sub.add_theme_color_override("font_color", Color(0.82, 0.78, 0.86, 0.9))
	column.add_child(sub)

	var stats := Label.new()
	stats.text = "волна %d из %d      уровень %d      скелетов убито %d" % [
		maxi(wave, 1), total, level, kills]
	stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stats.add_theme_font_size_override("font_size", 22)
	stats.add_theme_color_override("font_color", Color(0.98, 0.94, 0.85))
	column.add_child(stats)

	var hint := Label.new()
	hint.text = "R или ЛКМ — начать заново"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 15)
	hint.add_theme_color_override("font_color", Color(0.62, 0.6, 0.68, 0.85))
	column.add_child(hint)
