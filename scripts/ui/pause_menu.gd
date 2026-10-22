class_name PauseMenu
extends CanvasLayer
## Esc menu: pause the run and change sound, resolution, fullscreen and the
## quality preset. Everything applies live and is remembered between runs.

const PANEL_BG := Color(0.055, 0.05, 0.075, 0.97)
const TEXT := Color(0.92, 0.9, 0.95, 1.0)
const MUTED := Color(0.66, 0.63, 0.72, 1.0)
const GOLD := Color(1.0, 0.86, 0.55, 1.0)

@onready var root: Control = $Root

var _volume_slider: HSlider
var _volume_label: Label
var _resolution_picker: OptionButton
var _fullscreen_check: CheckButton
var _vsync_check: CheckButton
var _quality_buttons: Array[Button] = []
var _quality_group := ButtonGroup.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	root.visible = false
	_build()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	if visible:
		close()
		get_viewport().set_input_as_handled()
		return
	if get_tree().paused:
		# A level-up menu or the death screen owns the pause.
		return
	open()
	get_viewport().set_input_as_handled()


func open() -> void:
	_refresh()
	visible = true
	root.visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close() -> void:
	visible = false
	root.visible = false
	get_tree().paused = false
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# --- UI ---------------------------------------------------------------------

func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.01, 0.02, 0.82)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_style())
	panel.custom_minimum_size = Vector2(620, 0)
	center.add_child(panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	panel.add_child(column)

	var title := Label.new()
	title.text = "ПАУЗА"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_color_override("font_color", GOLD)
	column.add_child(title)

	column.add_child(_section("ЗВУК"))
	var volume_row := HBoxContainer.new()
	volume_row.add_theme_constant_override("separation", 14)
	column.add_child(volume_row)

	var volume_caption := Label.new()
	volume_caption.text = "Общая громкость"
	volume_caption.custom_minimum_size = Vector2(200, 0)
	volume_caption.add_theme_color_override("font_color", TEXT)
	volume_row.add_child(volume_caption)

	_volume_slider = HSlider.new()
	_volume_slider.min_value = 0
	_volume_slider.max_value = 100
	_volume_slider.step = 1
	_volume_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_volume_slider.value_changed.connect(_on_volume_changed)
	volume_row.add_child(_volume_slider)

	_volume_label = Label.new()
	_volume_label.custom_minimum_size = Vector2(56, 0)
	_volume_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_volume_label.add_theme_color_override("font_color", MUTED)
	volume_row.add_child(_volume_label)

	column.add_child(_section("ВИДЕО"))
	var video_row := HBoxContainer.new()
	video_row.add_theme_constant_override("separation", 12)
	column.add_child(video_row)

	var resolution_caption := Label.new()
	resolution_caption.text = "Разрешение"
	resolution_caption.custom_minimum_size = Vector2(200, 0)
	resolution_caption.add_theme_color_override("font_color", TEXT)
	video_row.add_child(resolution_caption)

	_resolution_picker = OptionButton.new()
	for size in Settings.RESOLUTIONS:
		_resolution_picker.add_item("%d × %d" % [size.x, size.y])
	_resolution_picker.item_selected.connect(_on_resolution_changed)
	video_row.add_child(_resolution_picker)

	var flags_row := HBoxContainer.new()
	flags_row.add_theme_constant_override("separation", 28)
	column.add_child(flags_row)

	_fullscreen_check = CheckButton.new()
	_fullscreen_check.text = "Полный экран"
	_fullscreen_check.add_theme_color_override("font_color", TEXT)
	_fullscreen_check.toggled.connect(_on_fullscreen_toggled)
	flags_row.add_child(_fullscreen_check)

	_vsync_check = CheckButton.new()
	_vsync_check.text = "Вертикальная синхронизация"
	_vsync_check.add_theme_color_override("font_color", TEXT)
	_vsync_check.toggled.connect(_on_vsync_toggled)
	flags_row.add_child(_vsync_check)

	column.add_child(_section("КАЧЕСТВО"))
	var quality_row := HBoxContainer.new()
	quality_row.add_theme_constant_override("separation", 10)
	column.add_child(quality_row)

	for i in Settings.QUALITY_NAMES.size():
		var button := Button.new()
		button.text = Settings.QUALITY_NAMES[i]
		button.toggle_mode = true
		button.button_group = _quality_group
		button.custom_minimum_size = Vector2(140, 44)
		button.pressed.connect(_on_quality_pressed.bind(i))
		quality_row.add_child(button)
		_quality_buttons.append(button)

	var quality_hint := Label.new()
	quality_hint.text = "низкое: без SSAO/свечения/тумана и рендер в 0.75×"
	quality_hint.add_theme_font_size_override("font_size", 13)
	quality_hint.add_theme_color_override("font_color", MUTED)
	column.add_child(quality_hint)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	column.add_child(buttons)

	var resume := Button.new()
	resume.text = "Продолжить"
	resume.custom_minimum_size = Vector2(0, 46)
	resume.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	resume.add_theme_font_size_override("font_size", 20)
	resume.pressed.connect(close)
	buttons.add_child(resume)

	var quit := Button.new()
	quit.text = "Выход"
	quit.custom_minimum_size = Vector2(150, 46)
	quit.add_theme_font_size_override("font_size", 20)
	quit.pressed.connect(_on_quit_pressed)
	buttons.add_child(quit)

	var hint := Label.new()
	hint.text = "Esc — закрыть"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", MUTED)
	column.add_child(hint)


func _section(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", GOLD)
	return label


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_BG
	style.border_color = Color(1.0, 0.86, 0.55, 0.35)
	style.set_border_width_all(1)
	style.set_corner_radius_all(14)
	style.content_margin_left = 28
	style.content_margin_right = 28
	style.content_margin_top = 24
	style.content_margin_bottom = 24
	return style


func _refresh() -> void:
	_volume_slider.set_value_no_signal(roundf(Settings.master_volume * 100.0))
	_volume_label.text = "%d%%" % roundi(Settings.master_volume * 100.0)

	var index := Settings.RESOLUTIONS.find(Settings.resolution)
	_resolution_picker.selected = index if index >= 0 else Settings.RESOLUTIONS.size() - 1
	_fullscreen_check.set_pressed_no_signal(Settings.fullscreen)
	_vsync_check.set_pressed_no_signal(Settings.vsync)
	for i in _quality_buttons.size():
		_quality_buttons[i].set_pressed_no_signal(i == Settings.quality)


# --- Callbacks --------------------------------------------------------------

func _on_volume_changed(value: float) -> void:
	Settings.apply_audio(value / 100.0)
	Settings.save()
	_volume_label.text = "%d%%" % roundi(value)


func _on_resolution_changed(index: int) -> void:
	if index < 0 or index >= Settings.RESOLUTIONS.size():
		return
	Settings.resolution = Settings.RESOLUTIONS[index]
	Settings.apply_video()
	Settings.save()


func _on_fullscreen_toggled(pressed: bool) -> void:
	Settings.fullscreen = pressed
	Settings.apply_video()
	Settings.save()


func _on_vsync_toggled(pressed: bool) -> void:
	Settings.vsync = pressed
	Settings.apply_video()
	Settings.save()


func _on_quality_pressed(index: int) -> void:
	Settings.apply_quality(index)
	Settings.save()


func _on_quit_pressed() -> void:
	# Settings are saved as they change, so leaving is safe at any point.
	get_tree().paused = false
	Net.shutdown(self)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
