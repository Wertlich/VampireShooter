extends Control
## Front screen: play, online (host or join), settings, quit.
## Built in code, like the rest of the UI in this project.

const ARENA := "res://scenes/main.tscn"

const GOLD := Color(1.0, 0.86, 0.55, 1.0)
const TEXT := Color(0.92, 0.9, 0.95, 1.0)
const MUTED := Color(0.62, 0.6, 0.7, 1.0)
const BLOOD := Color(0.55, 0.06, 0.12, 1.0)

var _pages: Array[Control] = []
var _status: Label
var _address: LineEdit
var _join_button: Button
var _connecting: bool = false
var _bridge: SteamBridge
var _lobby_field: LineEdit
var _steam_status: Label
var _lobby_list: VBoxContainer
var _steam_pending_owner: bool = false


func _ready() -> void:
	Settings.load_all()
	Settings.apply_all(self)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build()
	_show_page(0)

	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


# --- Pages ------------------------------------------------------------------

func _show_page(index: int) -> void:
	for i in _pages.size():
		_pages[i].visible = i == index
	if index == 2:
		var panel := _pages[2].get_node_or_null("Panel/Settings") as SettingsPanel
		if panel != null:
			panel.refresh()


func _build() -> void:
	var back := ColorRect.new()
	back.color = Color(0.03, 0.02, 0.05)
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(back)

	# A soft red glow behind the title, cheap enough for any GPU.
	var glow := ColorRect.new()
	glow.color = Color(0.22, 0.02, 0.05, 0.55)
	glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	glow.anchor_top = -0.55
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(glow)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 18)
	column.custom_minimum_size = Vector2(520, 0)
	center.add_child(column)

	var title := Label.new()
	title.text = "VAMPIRE SHOOTER"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 56)
	title.add_theme_color_override("font_color", GOLD)
	column.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "переживи волны в проклятом замке"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 16)
	subtitle.add_theme_color_override("font_color", MUTED)
	column.add_child(subtitle)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 22)
	column.add_child(spacer)

	_pages.append(_main_page())
	_pages.append(_online_page())
	_pages.append(_settings_page())
	for page in _pages:
		column.add_child(page)


func _main_page() -> Control:
	var page := VBoxContainer.new()
	page.name = "Main"
	page.add_theme_constant_override("separation", 12)
	page.add_child(_menu_button("ИГРАТЬ", _on_play))
	page.add_child(_menu_button("ОНЛАЙН", func() -> void: _show_page(1)))
	page.add_child(_menu_button("НАСТРОЙКИ", func() -> void: _show_page(2)))
	page.add_child(_menu_button("ВЫХОД", func() -> void: get_tree().quit()))
	return page


func _online_page() -> Control:
	var page := VBoxContainer.new()
	page.name = "Online"
	page.add_theme_constant_override("separation", 12)

	var title := Label.new()
	title.text = "ОНЛАЙН"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", GOLD)
	page.add_child(title)

	var hint := Label.new()
	hint.text = "Хост держит волны и врагов, остальные подключаются по IP.\nДо 4 игроков, порт %d.\nТвой IP для друга: %s" % [Net.PORT, _local_address()]
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", MUTED)
	page.add_child(hint)

	var warning := Label.new()
	warning.text = _address_warning()
	warning.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	warning.custom_minimum_size = Vector2(560, 0)
	warning.add_theme_font_size_override("font_size", 13)
	warning.add_theme_color_override("font_color", Color(1.0, 0.62, 0.45))
	warning.visible = not warning.text.is_empty()
	page.add_child(warning)

	page.add_child(_menu_button("СОЗДАТЬ ХОСТ", _on_host))

	var address_row := HBoxContainer.new()
	address_row.add_theme_constant_override("separation", 10)
	page.add_child(address_row)

	var caption := Label.new()
	caption.text = "IP хоста"
	caption.custom_minimum_size = Vector2(120, 0)
	caption.add_theme_color_override("font_color", TEXT)
	address_row.add_child(caption)

	_address = LineEdit.new()
	_address.text = _default_address()
	_address.placeholder_text = "192.168.1.10"
	_address.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_address.custom_minimum_size = Vector2(0, 44)
	address_row.add_child(_address)

	_join_button = _menu_button("ПРИСОЕДИНИТЬСЯ", _on_join)
	page.add_child(_join_button)

	_status = Label.new()
	_status.text = ""
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_font_size_override("font_size", 14)
	_status.add_theme_color_override("font_color", MUTED)
	page.add_child(_status)

	page.add_child(_steam_block())

	page.add_child(_menu_button("НАЗАД", func() -> void: _show_page(0)))
	return page


## Steam block: hidden entirely when the extension or the Steam client is absent.
func _steam_block() -> Control:
	var box := VBoxContainer.new()
	box.name = "SteamBox"
	box.add_theme_constant_override("separation", 10)

	_bridge = SteamBridge.ensure(self)
	var reason := _bridge.diagnostic()
	if reason.is_empty() and not _bridge.init_steam():
		reason = _bridge.last_error
	if not reason.is_empty():
		# Keep the block visible: a silent disappearance looks like a bug.
		var why := Label.new()
		why.text = "STEAM недоступен: %s" % reason
		why.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		why.custom_minimum_size = Vector2(560, 0)
		why.add_theme_font_size_override("font_size", 13)
		why.add_theme_color_override("font_color", Color(1.0, 0.62, 0.45))
		box.add_child(why)
		return box

	var title := Label.new()
	title.text = "STEAM · %s" % _bridge.persona
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", GOLD)
	box.add_child(title)

	box.add_child(_menu_button("СОЗДАТЬ ЛОББИ STEAM", _on_steam_host))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)
	var caption := Label.new()
	caption.text = "ID лобби"
	caption.custom_minimum_size = Vector2(120, 0)
	caption.add_theme_color_override("font_color", TEXT)
	row.add_child(caption)
	_lobby_field = LineEdit.new()
	_lobby_field.placeholder_text = "109775241833505732"
	_lobby_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lobby_field.custom_minimum_size = Vector2(0, 44)
	row.add_child(_lobby_field)

	box.add_child(_menu_button("ВОЙТИ ПО ID", _on_steam_join))
	box.add_child(_menu_button("НАЙТИ ЛОББИ", func() -> void: _bridge.find_lobbies()))

	_lobby_list = VBoxContainer.new()
	_lobby_list.name = "LobbyList"
	_lobby_list.add_theme_constant_override("separation", 6)
	box.add_child(_lobby_list)
	_bridge.lobbies_found.connect(_on_lobbies_found)

	box.add_child(_menu_button("ПРИГЛАСИТЬ ДРУГА", func() -> void: _bridge.invite_friend()))

	_steam_status = Label.new()
	_steam_status.text = "оверлей Steam — Shift+Tab"
	_steam_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_steam_status.add_theme_font_size_override("font_size", 13)
	_steam_status.add_theme_color_override("font_color", MUTED)
	box.add_child(_steam_status)

	_bridge.status_changed.connect(func(text: String) -> void: _steam_status.text = text)
	_bridge.lobby_ready.connect(_on_steam_lobby_ready)
	_bridge.lobby_failed.connect(func(text: String) -> void: _steam_status.text = text)
	return box


func _on_steam_host() -> void:
	_steam_pending_owner = true
	_bridge.create_lobby(_local_address(), "Vampire Shooter · %s" % _bridge.persona)


## Results of "Найти лобби": one button per live lobby, no typing at all.
func _on_lobbies_found(lobbies: Array) -> void:
	if _lobby_list == null:
		return
	for child in _lobby_list.get_children():
		child.queue_free()
	if lobbies.is_empty():
		_steam_status.text = "Лобби не найдено: хост должен нажать «Создать лобби Steam»"
		return
	for id in lobbies:
		var button := _menu_button(_bridge.lobby_label(int(id)), _on_steam_join_id.bind(int(id)))
		button.custom_minimum_size = Vector2(0, 44)
		button.add_theme_font_size_override("font_size", 16)
		_lobby_list.add_child(button)


func _on_steam_join_id(id: int) -> void:
	_steam_pending_owner = false
	_bridge.join_lobby(id)


func _on_steam_join() -> void:
	var text := _lobby_field.text.strip_edges()
	if not text.is_valid_int():
		_steam_status.text = "Нужен числовой ID лобби"
		return
	_steam_pending_owner = false
	_bridge.join_lobby(int(text))


func _on_steam_lobby_ready(_id: int, owner: bool) -> void:
	if owner:
		# Host: start the game server; guests read the address from lobby data.
		if not Net.host(self):
			_steam_status.text = Net.last_error
			return
		get_tree().change_scene_to_file(ARENA)
		return
	var address := _bridge.lobby_address()
	if address.is_empty():
		_steam_status.text = "В лобби нет адреса хоста"
		return
	var parts := address.split(":")
	var port := Net.PORT
	if parts.size() > 1 and parts[1].is_valid_int():
		port = int(parts[1])
	if not Net.join(self, parts[0], port):
		_steam_status.text = Net.last_error
		return
	_connecting = true
	if _join_button != null:
		_join_button.disabled = true


## LAN address of this machine, so lobby guests know where to connect.
## Link-local 169.254.x addresses are skipped: they only appear when an adapter
## has no DHCP lease and nobody can connect to them.
func _local_address() -> String:
	var usable := _usable_addresses()
	if usable.is_empty():
		return "нет сети (проверь Wi-Fi/Ethernet)"
	return "%s:%d" % [usable[0], Net.PORT]


func _usable_addresses() -> Array[String]:
	var private_ones: Array[String] = []
	var others: Array[String] = []
	for address in IP.get_local_addresses():
		if address.count(".") != 3:
			continue
		if address.begins_with("127.") or address.begins_with("169.254."):
			continue
		if address.begins_with("192.168.") or address.begins_with("10.") \
				or address.begins_with("172.16.") or address.begins_with("172.17.") \
				or address.begins_with("172.18.") or address.begins_with("172.19.") \
				or address.begins_with("172.2") or address.begins_with("172.30.") \
				or address.begins_with("172.31."):
			private_ones.append(address)
		else:
			others.append(address)
	private_ones.append_array(others)
	return private_ones


func _address_warning() -> String:
	var usable := _usable_addresses()
	if usable.is_empty():
		return "Локальной сети не видно (адаптер получил только 169.254.x.x).\nПодключи Wi-Fi/кабель или используй Radmin VPN / Tailscale."
	if usable.size() > 1:
		return "Ещё адреса этого ПК: %s" % ", ".join(usable.slice(1))
	return ""


func _settings_page() -> Control:
	var page := VBoxContainer.new()
	page.name = "SettingsPage"

	var title := Label.new()
	title.text = "НАСТРОЙКИ"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", GOLD)
	page.add_child(title)

	var panel := PanelContainer.new()
	panel.name = "Panel"
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.06, 0.1, 0.9)
	style.border_color = Color(0.35, 0.1, 0.16)
	style.set_border_width_all(1)
	style.set_corner_radius_all(12)
	style.content_margin_left = 24
	style.content_margin_right = 24
	style.content_margin_top = 18
	style.content_margin_bottom = 18
	panel.add_theme_stylebox_override("panel", style)
	page.add_child(panel)

	var settings := preload("res://scenes/settings_panel.tscn").instantiate() as SettingsPanel
	settings.name = "Settings"
	panel.add_child(settings)

	page.add_child(_menu_button("НАЗАД", func() -> void: _show_page(0)))
	return page


func _menu_button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 52)
	button.add_theme_font_size_override("font_size", 20)
	button.pressed.connect(action)
	return button


func _default_address() -> String:
	return "127.0.0.1"


# --- Actions ----------------------------------------------------------------

func _on_play() -> void:
	Net.shutdown(self)
	get_tree().change_scene_to_file(ARENA)


func _on_host() -> void:
	_status.text = "Поднимаем сервер…"
	if not Net.host(self):
		_status.text = Net.last_error
		return
	get_tree().change_scene_to_file(ARENA)


func _on_join() -> void:
	if _connecting:
		return
	var address := _address.text.strip_edges()
	if address.is_empty():
		_status.text = "Введи IP хоста"
		return
	_status.text = "Подключаемся к %s:%d…" % [address, Net.PORT]
	if not Net.join(self, address):
		_status.text = Net.last_error
		return
	_connecting = true
	_join_button.disabled = true


func _on_connected_to_server() -> void:
	if not _connecting:
		return
	_connecting = false
	get_tree().change_scene_to_file(ARENA)


func _on_connection_failed() -> void:
	_reset_connection("Сервер не ответил — проверь IP и порт")
	_show_page(1)


func _on_server_disconnected() -> void:
	_reset_connection("Соединение с хостом потеряно")
	_show_page(1)


func _reset_connection(reason: String) -> void:
	_connecting = false
	if _join_button != null:
		_join_button.disabled = false
	Net.shutdown(self)
	if _status != null:
		_status.text = reason
