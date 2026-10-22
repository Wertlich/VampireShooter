class_name SettingsPanel
extends VBoxContainer
## Shared sound / video / quality controls, used by the pause menu and by the
## main menu. Applies and saves everything immediately.

const TEXT := Color(0.92, 0.9, 0.95, 1.0)
const MUTED := Color(0.66, 0.63, 0.72, 1.0)
const GOLD := Color(1.0, 0.86, 0.55, 1.0)

var _volume_slider: HSlider
var _volume_label: Label
var _resolution_picker: OptionButton
var _fullscreen_check: CheckButton
var _vsync_check: CheckButton
var _quality_buttons: Array[Button] = []
var _quality_group := ButtonGroup.new()


func _ready() -> void:
	_build()
	refresh()


func refresh() -> void:
	if _volume_slider == null:
		return
	_volume_slider.set_value_no_signal(roundf(Settings.master_volume * 100.0))
	_volume_label.text = "%d%%" % roundi(Settings.master_volume * 100.0)
	var index := Settings.RESOLUTIONS.find(Settings.resolution)
	_resolution_picker.selected = index if index >= 0 else Settings.RESOLUTIONS.size() - 1
	_fullscreen_check.set_pressed_no_signal(Settings.fullscreen)
	_vsync_check.set_pressed_no_signal(Settings.vsync)
	for i in _quality_buttons.size():
		_quality_buttons[i].set_pressed_no_signal(i == Settings.quality)


func _build() -> void:
	add_theme_constant_override("separation", 14)

	add_child(_section("ЗВУК"))
	var volume_row := HBoxContainer.new()
	volume_row.add_theme_constant_override("separation", 14)
	add_child(volume_row)
	var caption := Label.new()
	caption.text = "Общая громкость"
	caption.custom_minimum_size = Vector2(200, 0)
	caption.add_theme_color_override("font_color", TEXT)
	volume_row.add_child(caption)
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

	add_child(_section("ВИДЕО"))
	var video_row := HBoxContainer.new()
	video_row.add_theme_constant_override("separation", 12)
	add_child(video_row)
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
	add_child(flags_row)
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

	add_child(_section("КАЧЕСТВО"))
	var quality_row := HBoxContainer.new()
	quality_row.add_theme_constant_override("separation", 10)
	add_child(quality_row)
	for i in Settings.QUALITY_NAMES.size():
		var button := Button.new()
		button.text = Settings.QUALITY_NAMES[i]
		button.toggle_mode = true
		button.button_group = _quality_group
		button.custom_minimum_size = Vector2(140, 44)
		button.pressed.connect(_on_quality_pressed.bind(i))
		quality_row.add_child(button)
		_quality_buttons.append(button)

	var hint := Label.new()
	hint.text = "низкое: без SSAO/свечения/тумана и рендер в 0.75×"
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", MUTED)
	add_child(hint)


func _section(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", GOLD)
	return label


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
