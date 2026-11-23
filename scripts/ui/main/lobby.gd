extends RefCounted
## Online play from the main screen (main.gd): the lobby (rooms and IP), the link lost and
## rejoined, a game for two over the network, the 2 на 2 room. The messages go through the
## Net autoload (scripts/net/net.gd). Its functions work on the main screen `m`, which keeps all the state.

const Main = preload("res://scripts/ui/main.gd")
const Game = preload("res://scripts/core/game.gd")
const CardDB = preload("res://scripts/core/card_db.gd")
const UI = preload("res://scripts/ui/ui_kit.gd")
const WoodUI = preload("res://scripts/ui/wood_ui.gd")
const AILevels = preload("res://scripts/ai/ai_levels.gd")
const FitCenter = preload("res://scripts/ui/fit_center.gd")
const Replay = preload("res://scripts/core/replay.gd")
const Phone = preload("res://scripts/ui/phone.gd")

var m: Main
# Tournament room (Net.tour): the seed of the last game the host started, the game number on the table.
var _tour_seed := -1
var _tour_game := 0
var _watch_label: Label = null     # room mode, host: the room's watch code
var _watch_copy: Button = null     # its «copy» button, shown once the code is known
# A match for two: both players pick their heroes once the other one is in the room.
var _cols: Control = null          # the columns of the lobby (creating / joining a room), then the match
var _hero_ready := false           # we picked (and said so)
var _remote_ready := false         # the other player picked
var _me_line: Label = null
var _foe_line: Label = null


func _init(main: Main) -> void:
	m = main


## mode "room": rooms on the room server (the default); "lan": by IP over Radmin VPN / LAN;
## "rank": a ranked match the server made, its bans and picks (ranked.gd).
func show_net_lobby(mode := "room") -> void:
	if m._lobby_root != null:
		return
	m._close_play_menu()
	m._lobby_mode = mode
	var root := m._overlay_root(Color(0.03, 0.02, 0.07, 0.8))
	m._lobby_root = root
	var center := FitCenter.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", m._panel_box())
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10 if Phone.active else 16)
	panel.add_child(v)
	var head_title := "Рейтинговый матч" if mode == "rank" else "Игра по сети"
	var head_at := v.get_child_count()
	if not Phone.active:
		v.add_child(m._title(head_title))

	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 14 if Phone.active else 30)
	cols.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(cols)
	_cols = cols

	if mode == "rank":
		m.ranked.draft_columns(cols)
	elif mode == "room":
		_room_columns(cols)
	else:
		_lan_columns(cols)

	m._lobby_status = WoodUI.label("", 24, Color.WHITE, 6, UI.UI_FONT)
	m._lobby_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	m._lobby_status.custom_minimum_size = Vector2(0, 40 if Phone.active else 70)
	m._lobby_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(m._lobby_status)
	var back := WoodUI.button("Назад", UI.PURPLE, 26, Vector2(220, 58))
	back.pressed.connect(func():
		m.net.leave()
		_close_lobby()
		m._back_to_play())
	var other := WoodUI.button("Игра по IP" if mode == "room" else "Игра через комнаты",
		UI.BLUE, 22, Vector2(330, 58))
	other.pressed.connect(func():
		m.net.leave()
		_close_lobby()
		show_net_lobby("lan" if mode == "room" else "room"))
	if Phone.active:
		# A phone: «Назад» and the other way in on the top line, the room under them goes to the columns.
		if mode == "rank":
			other.queue_free()
			other = null
		else:
			other.custom_minimum_size.x = 300
		var head := m._phone_header(head_title, back, other)
		v.add_child(head)
		v.move_child(head, head_at)
		return
	var back_row := HBoxContainer.new()
	back_row.alignment = BoxContainer.ALIGNMENT_CENTER
	back_row.add_theme_constant_override("separation", 20)
	back_row.add_child(back)
	if mode == "rank":
		other.queue_free()
		m._lobby_status.custom_minimum_size = Vector2(0, 40)
	else:
		back_row.add_child(other)
	v.add_child(back_row)


func _room_columns(cols: Control) -> void:
	var host_col := _lobby_column(cols, "Создать комнату")
	var bw := 290.0 if Phone.active else 440.0
	var host_btn := WoodUI.button("Создать комнату", UI.GREEN, 28, Vector2(bw, 66))
	host_btn.pressed.connect(_net_host_room)
	host_col.add_child(host_btn)
	var team_btn := WoodUI.button("Комната 2 на 2", UI.BLUE, 26, Vector2(bw, 58))
	team_btn.pressed.connect(func(): _net_host_room(4))
	host_col.add_child(team_btn)
	var three_btn := WoodUI.button("Комната на троих", UI.ORANGE, 26, Vector2(bw, 58))
	three_btn.pressed.connect(func(): _net_host_room(3))
	host_col.add_child(three_btn)
	# A phone: the room's settings in a column of their own, between the other two.
	var set_col := _lobby_column(cols, "Комната") if Phone.active else host_col
	set_col.add_child(_timer_row())
	set_col.add_child(_undo_check())
	set_col.add_child(_privacy_checks())
	host_col.add_child(WoodUI.label("Код комнаты:", 22, UI.CREAM, 5, UI.UI_FONT))
	m._lobby_code = WoodUI.label("—", 44 if Phone.active else 64, Color(0.6, 1.0, 0.65), 10)
	var code_row := HBoxContainer.new()
	code_row.add_theme_constant_override("separation", 16)
	code_row.add_child(m._lobby_code)
	code_row.add_child(_copy_button(func() -> String: return m._lobby_code.text if m._lobby_code != null else ""))
	host_col.add_child(code_row)
	_watch_label = WoodUI.label("", 22, UI.CREAM, 5, UI.UI_FONT)
	var watch_row := HBoxContainer.new()
	watch_row.add_theme_constant_override("separation", 12)
	watch_row.add_child(_watch_label)
	_watch_copy = _copy_button(func() -> String: return m.net.watch_code, 48)
	_watch_copy.visible = false
	watch_row.add_child(_watch_copy)
	host_col.add_child(watch_row)

	var join_col := _lobby_column(cols, "Войти по коду")
	join_col.add_child(WoodUI.label("Код от друга:", 22, UI.CREAM, 5, UI.UI_FONT))
	var code_edit := _lobby_edit("ABCD", "")
	code_edit.max_length = 8
	join_col.add_child(code_edit)
	var join_btn := WoodUI.button("Войти", UI.BLUE, 28, Vector2(260.0 if Phone.active else bw, 66))
	join_btn.pressed.connect(func(): _net_join_room(code_edit.text))
	code_edit.text_submitted.connect(func(txt): _net_join_room(txt))
	join_col.add_child(join_btn)


## A text-less «copy» button: puts the text `source` returns on the clipboard.
func _copy_button(source: Callable, side := 64) -> Button:
	var b := WoodUI.copy_button(UI.BLUE, side)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.pressed.connect(func():
		var code: String = source.call()
		if code.length() < 4:
			return
		DisplayServer.clipboard_set(code)
		_set_lobby_status("Код скопирован", Color(0.6, 1.0, 0.65)))
	return b


func _lan_columns(cols: Control) -> void:
	var host_col := _lobby_column(cols, "Создать игру")
	var host_btn := WoodUI.button("Создать игру", UI.GREEN, 28, Vector2(440, 66))
	host_btn.pressed.connect(_net_host)
	host_col.add_child(host_btn)
	host_col.add_child(_timer_row())
	host_col.add_child(_undo_check())
	var ips: Array = m.net.local_ipv4()
	var ip_text := "Твой адрес:\n" +("\n".join(ips) if not ips.is_empty() else "не найден — включи Radmin VPN")
	var ip_label := WoodUI.label(ip_text, 24, Color(0.6, 1.0, 0.65), 6)
	host_col.add_child(ip_label)
	if not ips.is_empty() and not String(ips[0]).begins_with("26."):
		host_col.add_child(WoodUI.label("Адрес Radmin VPN начинается с 26.", 18, Color(1, 1, 1, 0.6), 4, UI.UI_FONT))

	var join_col := _lobby_column(cols, "Подключиться")
	join_col.add_child(WoodUI.label("Адрес друга:", 22, UI.CREAM, 5, UI.UI_FONT))
	var ip_edit := _lobby_edit("26.x.x.x", m._load_setting("net", "last_ip", ""))
	join_col.add_child(ip_edit)
	var join_btn := WoodUI.button("Подключиться", UI.BLUE, 28, Vector2(440, 66))
	join_btn.pressed.connect(func(): _net_join(ip_edit.text))
	ip_edit.text_submitted.connect(func(txt): _net_join(txt))
	join_col.add_child(join_btn)


## The creator's turn timer: a tick to switch it on and the time per turn.
## Kept in the settings; read again when the match (or a rematch) starts.
func _timer_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var check := _check_button("Таймер хода", m._load_setting("net", "timer_on", false))
	check.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(check)
	var less := WoodUI.button("−", UI.PURPLE, 26, Vector2(48, 46))
	var value := WoodUI.label("", 28, Color.WHITE, 6)
	value.custom_minimum_size = Vector2(64 if Phone.active else 78, 0)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var more := WoodUI.button("+", UI.PURPLE, 26, Vector2(48, 46))
	for n in [less, value, more]:
		n.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(n)
	var refresh := func():
		var i := Main.TIMER_STEPS.find(_timer_seconds())
		value.text = _clock_text(Main.TIMER_STEPS[i])
		value.modulate.a = 1.0 if check.button_pressed else 0.35
		less.disabled = not check.button_pressed or i == 0
		more.disabled = not check.button_pressed or i == Main.TIMER_STEPS.size() - 1
	var step := func(d: int):
		var i := clampi(Main.TIMER_STEPS.find(_timer_seconds()) + d, 0, Main.TIMER_STEPS.size() - 1)
		m._save_setting("net", "timer_sec", Main.TIMER_STEPS[i])
		refresh.call()
	less.pressed.connect(step.bind(-1))
	more.pressed.connect(step.bind(1))
	check.toggled.connect(func(on: bool):
		m._save_setting("net", "timer_on", on)
		refresh.call())
	refresh.call()
	return row


## The creator's tick: one undo per turn for both players.
func _undo_check() -> Button:
	var check := _check_button("Отмена хода", m._load_setting("net", "undo_on", false))
	check.toggled.connect(func(on: bool): m._save_setting("net", "undo_on", on))
	return check


## Who may come into the creator's room without being called: all ticks off, everybody online (they see
## the room in the list of players); «Только друзья», friends only; «Вход только по коду», nobody is told
## the code; «Только по приглашению», nobody comes in, not even by the code, but the ones the creator
## calls (it needs an account). The relay hears it with the next status (main.room_privacy).
func _privacy_checks() -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	var friends := _check_button("Только друзья", m._load_setting("net", "friends_only", false))
	var code := _check_button("Вход только по коду", m._load_setting("net", "code_only", false))
	var invite := _check_button("Только по приглашению", m._load_setting("net", "invite_only", false) and m.account.logged_in())
	invite.disabled = not m.account.logged_in()
	var refresh := func():
		code.disabled = invite.button_pressed
		friends.disabled = invite.button_pressed or code.button_pressed
	friends.toggled.connect(func(on: bool): m._save_setting("net", "friends_only", on))
	code.toggled.connect(func(on: bool):
		m._save_setting("net", "code_only", on)
		refresh.call())
	invite.toggled.connect(func(on: bool):
		m._save_setting("net", "invite_only", on)
		refresh.call())
	refresh.call()
	box.add_child(friends)
	box.add_child(code)
	box.add_child(invite)
	return box


## Seconds per turn the creator picked (one of TIMER_STEPS), whether or not the timer is on.
func _timer_seconds() -> int:
	var sec := int(m._load_setting("net", "timer_sec", 90))
	return sec if Main.TIMER_STEPS.has(sec) else 90


## The turn timer of a new match: seconds per turn, 0 = no timer.
func _match_timer() -> int:
	return _timer_seconds() if bool(m._load_setting("net", "timer_on", false)) else 0


static func _clock_text(sec: int) -> String:
	return "%d:%02d" % [int(sec / 60.0), sec % 60]


## A toggle drawn as a tick box with a text.
func _check_button(text: String, on: bool) -> Button:
	var b := Button.new()
	b.toggle_mode = true
	b.button_pressed = on
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(0, 46) * WoodUI.font_scale
	if Phone.active:
		b.custom_minimum_size.y = Phone.TOUCH
	var fsize := WoodUI.fs(20 if Phone.active else 24)
	b.add_theme_font_override("font", WoodUI.letters(true, fsize))
	b.add_theme_font_size_override("font_size", fsize)
	b.add_theme_color_override("font_outline_color", WoodUI.INK)
	b.add_theme_constant_override("outline_size", 6)
	for st in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		var sb := StyleBoxEmpty.new()
		sb.content_margin_left = 48
		b.add_theme_stylebox_override(st, sb)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(c, UI.CREAM)
	b.draw.connect(func():
		var r := Rect2(2, b.size.y * 0.5 - 17, 34, 34)
		b.draw_style_box(WoodUI.paper(WoodUI.PAPER, 0.0, 4), r)
		if b.button_pressed:
			b.draw_polyline(PackedVector2Array([r.position + Vector2(7, 17), r.position + Vector2(15, 26),
				r.position + Vector2(30, 5)]), WoodUI.GO.darkened(0.3), 5.0, true))
	b.toggled.connect(func(_on: bool):
		b.queue_redraw()
		UI.sfx("click"))
	return b


func _lobby_edit(placeholder: String, text: String) -> LineEdit:
	var edit := LineEdit.new()
	edit.placeholder_text = placeholder
	edit.text = text
	edit.custom_minimum_size = (Vector2(260, Phone.TOUCH) if Phone.active else Vector2(440, 58)) * WoodUI.font_scale
	WoodUI.edit(edit, 28)
	return edit


func _refresh_lobby_hero() -> void:
	if m.net.team:
		# 2 на 2: the hero goes to the lobby.
		if m.net.is_host and not m._tl.is_empty():
			m._tl["heroes"][0] = m.my_hero
			_team_lobby_changed()
		elif not m.net.is_host:
			_team_guest_connected(true)
	if m._lobby_hero_box == null or not is_instance_valid(m._lobby_hero_box):
		return
	for ch in m._lobby_hero_box.get_children():
		ch.queue_free()
	var deck := CardDB.loadout_deck(m.my_hero)
	m._lobby_hero_box.add_child(m._hero_card_rect(CardDB.loadout_card(m.my_hero), Vector2(90, 124)))
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	m._lobby_hero_box.add_child(col)
	col.add_child(WoodUI.label("Ты играешь за:", 20, UI.CREAM, 5, UI.UI_FONT))
	col.add_child(WoodUI.label(CardDB.hero_card(CardDB.loadout_card(m.my_hero))["name"], 34, CardDB.hero_color(deck), 8))
	col.add_child(WoodUI.label("Колода: " + CardDB.hero(deck)["name"], 20, UI.CREAM, 5, UI.UI_FONT))
	col.add_child(m._land_row(deck, 24))


func _lobby_column(parent: Control, title: String) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", WoodUI.inset(title.hash() % 50, 22, 18))
	panel.custom_minimum_size = (Vector2(0, 0) if Phone.active else Vector2(500, 280)) * WoodUI.font_scale
	parent.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6 if Phone.active else 12)
	panel.add_child(col)
	col.add_child(WoodUI.label(title, 26 if Phone.active else 34, Color.WHITE, 8))
	return col


func _close_lobby() -> void:
	if m._lobby_root != null:
		m._close_overlay(m._lobby_root)
	m._lobby_root = null
	m._lobby_status = null
	m._lobby_hero_box = null
	m._lobby_code = null
	_watch_label = null
	_watch_copy = null
	_cols = null
	_me_line = null
	_foe_line = null


func _set_lobby_status(text: String, color := Color.WHITE) -> void:
	if m._lobby_status != null:
		m._lobby_status.text = text
		m._lobby_status.label_settings.font_color = color


func _net_host() -> void:
	var err: Error = m.net.host()
	if err != OK:
		_set_lobby_status("Не удалось открыть порт %d (ошибка %d). Возможно, игра уже запущена дважды." % [m.net.DEFAULT_PORT, err], Color(1, 0.5, 0.45))
		return
	_set_lobby_status("Игра создана. Ждём соперника…\nСкажи другу свой адрес из списка ниже.", Color(0.6, 1.0, 0.65))


func _net_host_room(seats := 2, quick := "") -> void:
	var err: Error = m.net.host_room(seats, quick)
	if err != OK:
		_set_lobby_status("Не удалось начать подключение к серверу (ошибка %d)." % err, Color(1, 0.5, 0.45))
		return
	if m._lobby_code != null:
		m._lobby_code.text = "…"
	_set_lobby_status("Создаём комнату…")


func _net_join_room(text: String, pass_key := "") -> void:
	var code := text.strip_edges().to_upper()
	if code.length() < 4:
		_set_lobby_status("Введи код комнаты из 4 символов — его видит друг, который создал комнату.", Color(1, 0.5, 0.45))
		return
	var err: Error = m.net.join_room(code, pass_key)
	if err != OK:
		_set_lobby_status("Не удалось начать подключение к серверу (ошибка %d)." % err, Color(1, 0.5, 0.45))
		return
	if m._lobby_code != null:
		m._lobby_code.text = "—"
	_set_lobby_status("Входим в комнату %s…" % code)


## Room mode: we sit in a room (just created, or joined by its code).
func _on_room_ready(code: String) -> void:
	if m.net.team:
		_show_team_lobby(code)
		return
	if m.net.ranked():
		_tour_seed = -1
		_set_lobby_status("")
		m.ranked.draft_update()
		return
	if not m.net.tour.is_empty():
		_tour_seed = -1
		var t: Dictionary = m.net.tour
		var mine: int = 0 if m.net.is_host else 1
		_set_lobby_status("Турнир %s. Твоя колода: %s\nЖдём соперника: %s" % [t.get("label", ""),
			_deck_name(String(t["heroes"][mine])), t["names"][1 - mine]], Color(0.6, 1.0, 0.65))
		return
	if m.net.is_host:
		if m._lobby_code != null:
			m._lobby_code.text = code
		if _watch_label != null and m.net.watch_code != "":
			_watch_label.text = "Наблюдатель: " + m.net.watch_code
			if _watch_copy != null:
				_watch_copy.visible = true
		_set_lobby_status("Комната создана", Color(0.6, 1.0, 0.65))
	else:
		_set_lobby_status("Ты в комнате %s. Ждём того, кто её создал…" % code, Color(0.6, 1.0, 0.65))


func _net_join(text: String) -> void:
	var addr: Array = m.net.parse_address(text)
	if not String(addr[0]).is_valid_ip_address():
		_set_lobby_status("Введи адрес вида 26.12.34.56", Color(1, 0.5, 0.45))
		return
	m._save_setting("net", "last_ip", text.strip_edges())
	var err: Error = m.net.join(addr[0], addr[1])
	if err != OK:
		_set_lobby_status("Не удалось начать подключение (ошибка %d)." % err, Color(1, 0.5, 0.45))
		return
	_set_lobby_status("Подключаемся к %s…" % addr[0])


func _on_net_connected() -> void:
	if m.net.team:
		_team_guest_connected()
		return
	if m.game != null:
		_abandon_game()     # a new player came in: an old game still waiting for its player is over
	m._remote_hero = ""
	m._remote_nick = ""
	m.seat = 0 if m.net.is_host else 1
	m.social.clear_game()
	_hero_ready = false
	_remote_ready = false
	m.net.send({"t": "hi", "nick": m.account.nick})
	if m.net.ranked():
		# A ranked match: the server holds the bans and the picks, the host starts once they are made.
		if m.net.is_host:
			_send_start()
		return
	if not m.net.tour.is_empty():
		# A tournament: the decks are the organizer's.
		m.net.send({"t": "hero", "hero": m.my_hero})
		_set_lobby_status("Соперник подключился!" if m.net.is_host else "Соединено! Ждём начала игры…", Color(0.6, 1.0, 0.65))
		return
	# Both players pick their heroes now, each in their own window.
	_show_match_lobby()
	m.show_hero_select("net")


## The lobby once the other player is in: who it is and who has picked a hero.
func _show_match_lobby() -> void:
	if _cols == null or not is_instance_valid(_cols):
		return
	for ch in _cols.get_children():
		ch.queue_free()
	var col := _lobby_column(_cols, "Соперник найден")
	col.get_parent().custom_minimum_size = Vector2(720, 280) * WoodUI.font_scale
	_foe_line = WoodUI.label("", 30, Color.WHITE, 6, UI.UI_FONT)
	col.add_child(_foe_line)
	_me_line = WoodUI.label("", 30, Color.WHITE, 6, UI.UI_FONT)
	col.add_child(_me_line)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	col.add_child(row)
	var pick := WoodUI.button("Выбрать героя", UI.ORANGE, 26, Vector2(300, 62))
	pick.pressed.connect(func(): m.show_hero_select("net"))
	row.add_child(pick)
	var chat := WoodUI.button("Чат", UI.BLUE, 26, Vector2(160, 62))
	chat.pressed.connect(func(): m.social_ui.show_panel("chat", Main.Social.GAME))
	row.add_child(chat)
	_match_lines()


func _match_lines() -> void:
	var foe: String = m._remote_nick if m._remote_nick != "" else "Соперник"
	if _foe_line != null and is_instance_valid(_foe_line):
		_foe_line.text = "%s: %s" % [foe, "готов" if _remote_ready else "выбирает героя…"]
		_foe_line.label_settings.font_color = Color(0.6, 1.0, 0.65) if _remote_ready else UI.CREAM
	if _me_line != null and is_instance_valid(_me_line):
		_me_line.text = "Ты: %s" % (CardDB.hero_card(CardDB.loadout_card(m.my_hero))["name"] + " · готов" if _hero_ready else "выбираешь героя…")
		_me_line.label_settings.font_color = Color(0.6, 1.0, 0.65) if _hero_ready else UI.CREAM
	if _foe_line == null:
		return
	if _hero_ready and not _remote_ready:
		_set_lobby_status("Ждём, пока %s выберет героя" % foe, Color(0.6, 1.0, 0.65))
	elif _remote_ready and not _hero_ready:
		_set_lobby_status("%s уже готов" % foe, Color(0.6, 1.0, 0.65))
	else:
		_set_lobby_status("")


## The hero window (mode "net") was closed with a pick: in a match for two that is not on the table
## yet, the other side learns that we are ready (the host's pick goes out with the start).
func net_hero_picked() -> void:
	if m.net.team or m.game != null or not m.net.active or not m.net.tour.is_empty():
		return
	_hero_ready = true
	if m.net.is_host:
		m.net.send({"t": "ready"})
		if _remote_ready:
			_send_start()
	else:
		m.net.send({"t": "hero", "hero": m.my_hero})
	_match_lines()


## Host only: picks the shared seed and the first player, starts both games.
## In a tournament room the room server has picked them, the decks and the settings too.
func _send_start() -> void:
	var t: Dictionary = m.net.tour
	if t.is_empty() and not CardDB.valid_loadout(m._remote_hero):
		return
	var seed_value := randi() & 0x7fffffff
	var first := randi() % 2
	var heroes := [m.my_hero, m._remote_hero]
	var timer := _match_timer()
	var undo := bool(m._load_setting("net", "undo_on", false))
	if not t.is_empty():
		if t.get("over", false) or int(t["seed"]) == _tour_seed:
			return      # the match is over, or the last game is not decided yet
		if m.net.ranked() and (t["rank"].get("phase") != "play" or not m.net.active):
			return      # the bans and the picks are not over yet
		_tour_seed = int(t["seed"])
		seed_value = int(t["seed"])
		first = int(t["first"])
		heroes = t["heroes"].duplicate()
		timer = int(t["turn_time"])
		undo = bool(t["undo"])
	m.net.send({"t": "start", "seed": seed_value, "first": first, "heroes": heroes, "timer": timer, "undo": undo})
	start_net_game(seed_value, first, 0, heroes, timer, undo)


func _on_net_message(d: Dictionary) -> void:
	if m.net.team:
		_team_message(d)
		return
	match d.get("t", ""):
		"hi":
			if d.get("nick") is String:
				m._remote_nick = _clean_nick(d["nick"])
				_match_lines()
		"specs":
			m.friend_cast.remote_spectators(d.get("nicks"))     # who watches the match, told the other player
		"ready":
			if not m.net.is_host and m.game == null:
				_remote_ready = true
				_match_lines()
		"chat":
			if d.get("text") is String:
				var nick := _clean_nick(d["nick"]) if d.get("nick") is String else ""
				m._got_game_chat(nick if nick != "" else (m._remote_nick if m._remote_nick != "" else "Соперник"),
					String(d["text"]).substr(0, Main.Social.TEXT_MAX))
		"hero":
			m._remote_hero = String(d.get("hero", ""))
			m._remote_hero_received.emit()
			if m.net.is_host and m.game == null:
				_remote_ready = CardDB.valid_loadout(m._remote_hero)
				_match_lines()
				if _hero_ready or not m.net.tour.is_empty():
					_send_start()
			elif m.game != null and m.game.phase == "over" and m.net.tour.is_empty():
				m._deck_changed["foe"] = true
				_show_rematch_note()
		"start":
			if not m.net.is_host and _start_ok(d, 2) and (m.net.tour.is_empty() or d["heroes"] == m.net.tour["heroes"]):
				start_net_game(int(d["seed"]), int(d["first"]), 1, d["heroes"], int(d.get("timer", 0)),
					bool(d.get("undo", false)))
		"lands":
			if _strings(d.get("types")):
				m._remote_lands = d["types"]
				m._remote_lands_received.emit()
		"mull":
			if d.get("change") is bool:
				m._remote_mull = d["change"]
				m._remote_mull_received.emit()
		"cmd", "choice":
			if m.board != null and m.online:
				m.board.net_receive(d)
		"surrender":
			_on_remote_surrender()
		"rematch":
			m._rematch_remote = true
			_show_rematch_note()
			_try_rematch()
		"tset":
			if m.board != null and m.online and d.get("n") is int and d.get("turn_time") is int and d.get("undo") is bool:
				m.board.queue_settings(d["n"], d["turn_time"], d["undo"])


## A "start" message from the other side starts a game only when it is one: whole numbers,
## `seats` real picks (no deck of a run), so a changed game there can't break ours.
func _start_ok(d: Dictionary, seats: int) -> bool:
	if not (d.get("seed") is int and d.get("first") is int and d.get("heroes") is Array) or d.get("heroes").size() != seats:
		return false
	if int(d["first"]) < 0 or int(d["first"]) >= seats or not (d.get("timer", 0) is int):
		return false
	return d["heroes"].all(func(h): return h is String and CardDB.valid_loadout(h) and not CardDB.loadout_deck(h).begins_with(CardDB.RUN_PREFIX))


## A nick from the other PC: short, one line.
static func _clean_nick(v: String) -> String:
	return v.replace("\n", " ").strip_edges().substr(0, 24)


static func _strings(v) -> bool:
	return v is Array and v.size() <= 8 and v.all(func(x): return x is String)


## The places of a 2 на 2 or на троих start: a room seat (or -1, the AI) for each of the n game seats.
static func _seats(v, n: int) -> bool:
	return v is Array and v.size() == n and v.all(func(x): return x is int and x >= -1 and x < n)


## The link dropped. The match is not thrown away: it waits, and whoever lost the
## link rejoins (with a direct link only the guest can; with a room, either player).
## "left" is the other player quitting on purpose; "version", "no_match" and "desync"
## end the match for good (see Net).
func _on_net_disconnected(reason: String) -> void:
	if reason == "left":
		_on_remote_left()
		return
	if reason == "closed":
		_tour_closed()
		return
	if m.game == null:
		_on_lobby_link_lost(reason)
		return
	if reason == "version" or reason == "no_match":
		_match_lost("Версии игры у вас разные, поэтому партию не продолжить." if reason == "version" \
			else "У соперника этой партии уже нет: он закрыл игру или начал новую.")
		return
	if reason == "desync":
		_match_lost("Копии партии у вас разошлись, продолжить нельзя. Начните новую игру.")
		return
	if m.game.phase == "over":
		if m._rematch_button != null and is_instance_valid(m._rematch_button):
			m._rematch_button.disabled = true
			m._rematch_button.text = "Связь потеряна"
	else:
		_show_link_lost()
	_start_rejoin()
	if not m._rejoin_running and m.game.phase != "over":
		_set_link_text(_link_wait_text())


## The link dropped before the game is on the table (lobby or setup).
func _on_lobby_link_lost(reason: String) -> void:
	if m.net.can_rejoin():
		_start_rejoin()
		return
	if m._lobby_root == null or m._rejoin_running:
		return
	var red := Color(1, 0.5, 0.45)
	match reason:
		"failed":
			if m._lobby_mode == "room":
				_set_lobby_status("Не удалось связаться с сервером игры. Проверь интернет и попробуй ещё раз.", red)
			else:
				_set_lobby_status("Не удалось подключиться. Проверь адрес, что друг нажал «Создать игру» и что Radmin VPN включён у обоих.", red)
		"version":
			_set_lobby_status("У вас разные версии игры — нужна одна и та же сборка.", red)
		"busy", "full":
			_set_lobby_status("В этой комнате уже двое игроков." if reason == "full" else "К этому игроку уже кто-то подключён. Попробуй через минуту.", red)
		"invite":
			_set_lobby_status("В эту комнату входят только по приглашению.", red)
		"no_room":
			_set_lobby_status("Комнаты с таким кодом нет. Проверь код — или друг уже вышел из неё.", red)
		"no_match":
			_set_lobby_status("Игра у соперника уже закрыта. Подключись заново.", red)
		_:
			_set_lobby_status("Соперник отключился. Ждём, пока он подключится снова." if m.net.is_host or m.net.link_up() else "Соединение разорвано.", red)


## The other player quit on purpose.
func _on_remote_left() -> void:
	_stop_rejoin()
	_close_link_overlay()
	if m.net.ranked() and m.game != null and m.game.phase != "over":
		return      # a ranked match: the room server gives the game to this one (_on_tour_changed, "left")
	if m._mode in ["teams_net", "three_net"] and m.game != null and m.game.phase != "over":
		var gone := m._message_overlay("Комната закрыта", "Создатель комнаты вышел из игры.")
		var gb := WoodUI.button("В главное меню", UI.PURPLE, 30, Vector2(320, 70))
		gb.pressed.connect(func():
			m._close_overlay(gone)
			m.net.close()
			m._end_game()
			m.show_title())
		gone.get_meta("box").add_child(gb)
		return
	if m.game == null:
		m.hero_select.close_net()
		if _foe_line != null and is_instance_valid(_foe_line) and m._lobby_root != null:
			# The match lobby goes back to the room (the host) or to the start (the guest).
			var mode: String = m._lobby_mode
			_close_lobby()
			show_net_lobby(mode)
			if m.net.is_host and m.net.mode == "relay" and m.net.room_code != "":
				_on_room_ready(m.net.room_code)
		_set_lobby_status("Соперник вышел. Ждём нового игрока…" if m.net.is_host else "Соперник вышел.", Color(1, 0.5, 0.45))
		return
	if m.game.phase == "over":
		if m._rematch_button != null and is_instance_valid(m._rematch_button):
			m._rematch_button.disabled = true
			m._rematch_button.text = "Соперник вышел"
		return
	var root := m._message_overlay("Соперник вышел", "Соперник покинул игру.")
	var b := WoodUI.button("В главное меню", UI.PURPLE, 30, Vector2(320, 70))
	b.pressed.connect(func():
		m._close_overlay(root)
		m.net.close()
		m._end_game()
		m.show_title())
	root.get_meta("box").add_child(b)


## The match cannot go on any more.
func _match_lost(text: String) -> void:
	_stop_rejoin()
	_close_link_overlay()
	m.net.close()
	var root := m._message_overlay("Партия потеряна", text)
	var b := WoodUI.button("В главное меню", UI.PURPLE, 30, Vector2(320, 70))
	b.pressed.connect(func():
		m._close_overlay(root)
		m._end_game()
		m.show_title())
	root.get_meta("box").add_child(b)


## The link is back: the match goes on from the same place.
func _on_net_resumed() -> void:
	_stop_rejoin()
	_close_link_overlay()
	if m.game == null:
		_set_lobby_status("Соединено!", Color(0.6, 1.0, 0.65))
		return
	if m.game.phase == "over" and m._rematch_button != null and is_instance_valid(m._rematch_button):
		m._rematch_button.disabled = m._rematch_local
		m._rematch_button.text = "Ждём соперника…" if m._rematch_local else "Реванш"


## Full-screen notice while the match waits for the link. Whoever lost it rejoins
## (with a direct link that is always the guest; the host's game is the server).
func _show_link_lost() -> void:
	if m._link_root != null and is_instance_valid(m._link_root):
		return
	var root := m._message_overlay("Связь потеряна", "")
	m._link_root = root
	m._link_label = root.get_meta("text")
	m._link_label.text = _link_wait_text()
	# The box centers each child on the same spot: two buttons go in a row of their own.
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	root.get_meta("box").add_child(row)
	if m.net.mode == "relay" or not m.net.is_host:
		var again := WoodUI.button("Переподключиться", UI.GREEN, 28, Vector2(360, 66))
		again.pressed.connect(_start_rejoin)
		row.add_child(again)
	var leave := WoodUI.button("Выйти в меню", UI.RED, 26, Vector2(320, 66))
	leave.pressed.connect(_leave_match)
	row.add_child(leave)


func _close_link_overlay() -> void:
	if m._link_root != null:
		m._close_overlay(m._link_root)
	m._link_root = null
	m._link_label = null


func _set_link_text(text: String) -> void:
	if m._link_label != null and is_instance_valid(m._link_label):
		m._link_label.text = text
	else:
		_set_lobby_status(text, Color(1, 0.85, 0.5))


func _link_wait_text() -> String:
	if m.game == null:
		if m.net.can_rejoin():
			return "Связь с сервером потеряна. Переподключаемся…"
		if m.net.mode == "relay" and m.net.match_id == 0:
			return "Связь восстановлена. Ты в комнате %s, ждём соперника…" % m.net.room_code
		return "Соперник отключился. Ждём, пока он подключится снова."
	return "Партия на паузе, она не сбрасывается.\n" + ("Переподключаемся…" if m.net.can_rejoin() \
		else "Ждём, пока соперник вернётся…")


## Keeps trying to get our own link back, while the match (or the room) waits for us.
func _start_rejoin() -> void:
	if m._rejoin_running or not m.net.can_rejoin():
		return
	m._rejoin_running = true
	m._link_attempt = 0
	m._rejoin_token += 1
	_rejoin_loop(m._rejoin_token)


func _stop_rejoin() -> void:
	m._rejoin_running = false
	m._rejoin_token += 1


## Keeps trying until the link is back or the player leaves: an outage can last a while.
## Once our link is up, the other player may still be away: then we wait for them.
func _rejoin_loop(token: int) -> void:
	while token == m._rejoin_token and not m.net.link_up() and (m.net.match_id != 0 or m.net.room_code != ""):
		if m.net.can_rejoin() and m.net.rejoin() == OK:
			m._link_attempt += 1
		var head := "Связь с сервером потеряна." if m.game == null else "Партия на паузе, она не сбрасывается."
		_set_link_text("%s\nПереподключаемся… (попытка %d)" % [head, m._link_attempt])
		await m.get_tree().create_timer(2.5).timeout
	if token == m._rejoin_token and m.net.link_up() and not m.net.active:
		_set_link_text(_link_wait_text())
	if token == m._rejoin_token:
		m._rejoin_running = false


## Leaves the online match on purpose: the other player is told at once.
func _leave_match() -> void:
	m.net.leave()
	_abandon_game()
	m.show_title()


## Throws the online game away on this PC, without a message.
func _abandon_game() -> void:
	if m._pause_root != null and is_instance_valid(m._pause_root):
		m._close_overlay(m._pause_root)
	m._pause_root = null
	if m._game_over_root != null and is_instance_valid(m._game_over_root):
		m._close_overlay(m._game_over_root)
	m._game_over_root = null
	m._rematch_button = null
	m._rematch_note = null
	m._end_game()


# ================================================================ online game


## timer: seconds per turn, 0 = no timer (the room creator's choice).
func start_net_game(seed_value: int, first: int, my_seat: int, heroes: Array, timer := 0, undo := false) -> void:
	_close_lobby()
	if m._game_over_root != null and is_instance_valid(m._game_over_root):
		m._close_overlay(m._game_over_root)
	m._game_over_root = null
	m._rematch_button = null
	m._rematch_note = null
	m._clear_title()
	if m.board != null:
		m.board.queue_free()
		m.board = null
	m.online = true
	m.ai_mode = false
	m._ai_vs_ai_mode = false
	m.seat = my_seat
	m._remote_mull = null
	m._remote_lands = null
	m._rematch_local = false
	m._rematch_remote = false
	m._deck_changed = {"me": false, "foe": false}
	m._last_heroes = heroes
	m._mode = "net"
	m.game = Game.new()
	var my_game = m.game
	m.game.setup(heroes, first, seed_value)
	m.game.journal = []
	if m.net.is_host:
		# The room's watchers get the game (Net streams the journal to the room server).
		var head := Replay.from_game(m.game, "net", 0, Main.version_text())
		head.erase("steps")
		head["nicks"] = m.match_nicks(0)
		m.net.spec_follow(m.game, head)
	m.hero_select.close_net()
	m._new_board()
	m.board.enable_net(m.net, m.seat, timer, undo)
	m.board.show_chat_button(true)
	m.board.set_chat_unread(m.social.unread_total())
	m.board.desync.connect(_on_desync)
	m.board.set_hands_hidden(true)
	_show_foe()

	var fname: String = m.game.players[first].name
	var me: String = m.game.players[m.seat].name
	var timer_text := "\nТаймер хода: %s." % _clock_text(timer) if timer > 0 else ""
	if undo:
		timer_text += "\nОтмена хода: 1 за ход."
	if m.net.ranked():
		_tour_game = int(m.net.tour["game"])
		m.net.tour["dispute"] = ""
		timer_text = "\nРейтинговый матч.%s" % timer_text
	elif not m.net.tour.is_empty():
		_tour_game = int(m.net.tour["game"])
		m.net.tour["dispute"] = ""
		timer_text = "\nТурнир %s, партия %d. Счёт %s.%s" % [m.net.tour.get("label", ""), _tour_game, _tour_score(), timer_text]
	await m._curtain(first, "Бросаем монетку…", "Ты играешь за: %s, соперник — %s.\nПервым ходит %s%s!%s" % [me,
		m.game.players[1 - m.seat].name, fname, " — это ты" if first == m.seat else "", timer_text], "Дальше", true)
	if m.game != my_game:
		return
	# Landscapes: everybody arranges their own, then both orders are applied.
	var types: Array = m.game.players[m.seat].lands.map(func(l): return l["type"])
	if CardDB.hero_land_types(m.game.players[m.seat].hero).size() > 1:
		types = await m.board.arrange_lands_prompt(m.seat)
		if m.game != my_game:
			return
	m.net.send({"t": "lands", "types": types})
	if m._remote_lands == null:
		m._setup_wait = m._message_overlay("Ждём соперника…", "Соперник расставляет земли.")
		await m._remote_lands_received
		if m.game != my_game:
			return
		m._close_overlay(m._setup_wait)
		m._setup_wait = null
	if m.game != my_game:
		return
	var lands := {m.seat: types, 1 - m.seat: m._remote_lands}
	for p in 2:
		await m.board.run_engine(func(): await m.game.cmd_arrange_lands(p, lands[p]))
	m.board.set_hands_hidden(false)
	var changed: bool = await m.board.mulligan_prompt(m.seat)
	if m.game != my_game:
		return
	m.net.send({"t": "mull", "change": changed})
	if m._remote_mull == null:
		m._setup_wait = m._message_overlay("Ждём соперника…", "Соперник ещё смотрит свою стартовую руку.")
		await m._remote_mull_received
		if m.game != my_game:
			return
		m._close_overlay(m._setup_wait)
		m._setup_wait = null
	if m.game != my_game:
		return
	var mull := {m.seat: changed, 1 - m.seat: bool(m._remote_mull)}
	# Both machines apply mulligans in the same order, so their decks stay identical.
	for p in [first, 1 - first]:
		if mull[p]:
			await m.board.run_engine(func(): await m.game.cmd_mulligan(p))
	if m.game != my_game:
		return
	m.board.net_accept = true
	await m.board.run_engine(func(): await m.game.start_game())


## The other player's nick on the table (a tournament's or a ranked match's from the room server),
## with «+» when it is not a friend yet and we have an account.
func _show_foe() -> void:
	var foe: String = m._remote_nick
	if not m.net.tour.is_empty():
		foe = String(m.net.tour["names"][1 - m.seat])
	if foe == "":
		return
	var board = m.board
	board.set_foe(foe, false)
	board.friend_requested.connect(_add_friend.bind(board))
	if not m.account.logged_in() or foe == m.account.nick:
		return
	var answer: Dictionary = await m.social.ask({"op": "s_profile", "nick": foe})
	if answer.get("op") == "s_profile" and answer.get("p") is Dictionary and String(answer["p"].get("fr", "")) == "" \
			and is_instance_valid(board) and m.board == board:
		board.set_foe(foe, true)


func _add_friend(nick: String, board) -> void:
	var answer: Dictionary = await m.social.ask({"op": "s_friend", "nick": nick, "act": "add"})
	if not is_instance_valid(board):
		return
	if answer.get("op") == "s_done" and String(answer.get("r", "")) in ["", "already"]:
		board.set_foe(nick, false)
		board.flash_note("Заявка отправлена")
	else:
		board.flash_note("Не получилось отправить заявку")


func _on_remote_surrender() -> void:
	if m.board == null or m.game == null or m.game.phase == "over":
		return
	m.board.force_over(m.seat)
	m._on_game_over(m.seat, "Соперник сдался.")


func _surrender_online() -> void:
	if m.board == null or m.game == null or m.game.phase == "over":
		return
	if m.game.three():
		# На троих the game goes on without the one who gives up: a command in their own turn,
		# so every PC drops them at the same point (the table sends it once their turn comes).
		m.board.concede_when_able()
		return
	if m.game.teams():
		m.net.send({"t": "surrender", "p": m.seat})
		var w: int = 1 - m.game.team(m.seat)
		m.board.force_over(w)
		m._on_game_over(w, "Твоя команда сдалась.")
		return
	m.net.send({"t": "surrender"})
	m.board.force_over(1 - m.seat)
	m._on_game_over(1 - m.seat, "Ты сдался.")


## Under the rematch button: the decks changed for the next match, whether the other
## player wants one.
func _show_rematch_note() -> void:
	if m._rematch_note == null or not is_instance_valid(m._rematch_note):
		return
	if not m.net.tour.is_empty():
		m._rematch_note.text = _tour_status()
		return
	var lines := []
	if m._deck_changed["me"]:
		lines.append("Твоя колода: " + _deck_name(m.my_hero))
	if m._deck_changed["foe"] and CardDB.valid_loadout(m._remote_hero):
		lines.append("Соперник сменил колоду: " + _deck_name(m._remote_hero))
	if m._rematch_remote:
		lines.append("Соперник хочет реванш!")
	m._rematch_note.text = "
".join(lines)


func _deck_name(pick: String) -> String:
	return CardDB.hero(CardDB.loadout_deck(pick))["name"]


func _try_rematch() -> void:
	if m.net.is_host and m._rematch_local and m._rematch_remote and m.net.active:
		_send_start()


# ================================================================ tournament room


## The score of the match from our side: "1:0".
func _tour_score() -> String:
	var sc: Array = m.net.tour.get("score", [0, 0])
	var mine: int = 0 if m.net.is_host else 1
	return "%d:%d" % [sc[mine], sc[1 - mine]]


## Under the buttons at the end of a game of the match.
func _tour_status() -> String:
	if m.net.ranked():
		return m.ranked.result_text()
	var t: Dictionary = m.net.tour
	if t.get("over", false):
		var won: bool = int(t.get("winner", -1)) == (0 if m.net.is_host else 1)
		return "Матч окончен: %s, счёт %s" % ["победа" if won else "поражение", _tour_score()]
	if int(t.get("game", 0)) == _tour_game and String(t.get("dispute", "")) == "":
		return "Проверяем результат…"
	if String(t.get("dispute", "")) != "":
		return "Результат спорный, ждём организатора"
	return "Счёт %s. Дальше партия %d" % [_tour_score(), int(t.get("game", 0))]


## Our replay of a game of the match goes to the room server.
func tour_game_over(winner: int, replay: Dictionary) -> void:
	if m.net.tour.is_empty() or _tour_game <= 0:
		return
	m.net.send_tour_result(_tour_game, winner, replay)


## The room server decided a game, or the organizer changed the settings.
func _on_tour_changed(what: String) -> void:
	if m.net.tour.is_empty():
		return
	if m.net.ranked():
		m.ranked.draft_update()
		if m.game == null and m.net.is_host:
			_send_start()
	if what == "settings":
		var t: Dictionary = m.net.tour
		var text := "Организатор: время на ход %s, отмена хода %s" % [_clock_text(int(t["turn_time"])) if int(t["turn_time"]) > 0 else "без лимита",
			"есть" if bool(t["undo"]) else "выключена"]
		if m.board != null and m.online and m.game != null and m.game.phase != "over":
			m.board.flash_note(text)
			if m.net.is_host:
				# From a turn neither side has begun yet: the turn player's side may be one turn ahead.
				var g = m.game
				var n: int = 3 if g.turn_number == 0 else g.turn_number + (1 if g.turn_player == m.seat else 2)
				m.net.send({"t": "tset", "n": n, "turn_time": int(t["turn_time"]), "undo": bool(t["undo"])})
				m.board.queue_settings(n, int(t["turn_time"]), bool(t["undo"]))
		elif m._lobby_root != null:
			_set_lobby_status(text, Color(1, 0.85, 0.5))
		return
	var last: Dictionary = m.net.tour.get("last", {})
	if m.game != null and m.board != null and m.online and m.game.phase != "over" \
			and last.get("by") in ["disconnect", "left"] and int(last.get("game", -1)) == _tour_game:
		# A player was away too long, or left a ranked match: the room server gave the game on the
		# table to the other one.
		var w := int(last["winner"])
		_tour_game = 0
		_close_link_overlay()
		m.board.force_over(w)
		if last.get("by") == "left":
			m._on_game_over(w, "Соперник вышел из матча." if w == m.seat else "Ты вышел из матча.")
		else:
			m._on_game_over(w, "Соперник не вернулся." if w == m.seat else "Ты не вернулся вовремя.")
		return
	_show_rematch_note()
	if m._rematch_button != null and is_instance_valid(m._rematch_button) and m.net.tour.get("over", false):
		m._rematch_button.disabled = true
		m._rematch_button.text = "Матч окончен"
	_try_rematch()


## The organizer closed the room.
func _tour_closed() -> void:
	var why: String = m.net.tour_closed
	if m.game == null:
		_set_lobby_status("Организатор закрыл комнату" + (": " + why if why != "" else ""), Color(1, 0.5, 0.45))
		return
	_match_lost("Организатор закрыл комнату" + (": " + why if why != "" else "") + ".")


func _on_desync(detail: String) -> void:
	push_warning("DESYNC: " + detail)
	print("DESYNC: ", detail)
	var root := m._message_overlay("Игры разошлись", "Копии игры у вас перестали совпадать (%s).\nМожно продолжить, но лучше начать партию заново." % detail)
	var b := WoodUI.button("Понятно", UI.PURPLE, 28, Vector2(260, 64))
	b.pressed.connect(func(): m._close_overlay(root))
	root.get_meta("box").add_child(b)


# ================================================================ 2 на 2 по сети


## A 2 на 2 room: the host creates it, up to three friends join by its code, the AI plays
## the empty seats (on the host's PC). The host decides who sits where: game seats 0 and 2
## are one team, 1 and 3 the other. Net passes the game messages through the host.
## A room на троих works the same with three seats, each for itself.
## The lobby, as the host keeps it and sends it round:
##   places: game seat -> room seat of the person there (-1: the AI),
##   heroes: room seat -> pick, nicks: room seat -> name, ai_heroes / levels: per game seat.
func _team_lobby_reset() -> void:
	var n := _room_n()
	var places := [0]
	var ai_heroes := []
	for gs in n:
		if gs > 0:
			places.append(-1)
		ai_heroes.append(m._random_hero())
	m._tl = {"places": places, "heroes": {0: ""}, "nicks": {0: _my_nick()},
		"ai_heroes": ai_heroes, "levels": m.seat_state(_room_mode()).duplicate(true)["levels"], "pick": -1}


## Seats of the room: 4 (2 на 2) or 3 (на троих).
func _room_n() -> int:
	return m.net.room_seats


## The local mode whose settings the room uses: "teams" or "three".
func _room_mode() -> String:
	return "three" if _room_n() == 3 else "teams"


func _my_nick() -> String:
	return m.account.nick if m.account.nick != "" else "Игрок %d" % (m.net.seat_no + 1)


## The room is there (just created, or joined): the 2 на 2 lobby replaces the room screen.
func _show_team_lobby(code: String) -> void:
	_close_lobby()
	if m.net.is_host:
		_team_lobby_reset()
	var root := m._overlay_root(Color(0.03, 0.02, 0.07, 0.9))
	m._lobby_root = root
	var center := FitCenter.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	center.add_child(v)
	v.add_child(m._title("%s · комната %s" % ["На троих" if _room_n() == 3 else "2 на 2", code]))
	m._tl_box = VBoxContainer.new()
	m._tl_box.add_theme_constant_override("separation", 14)
	v.add_child(m._tl_box)
	if m.net.is_host:
		var trow := CenterContainer.new()
		trow.add_child(_timer_row())
		v.add_child(trow)
	m._lobby_status = WoodUI.label("", 24, Color.WHITE, 6, UI.UI_FONT)
	m._lobby_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	m._lobby_status.custom_minimum_size = Vector2(0, 40)
	v.add_child(m._lobby_status)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 20)
	v.add_child(row)
	if m.net.is_host:
		m._tl_start = WoodUI.button("Начать игру", UI.GREEN, 30, Vector2(300, 66))
		m._tl_start.pressed.connect(_team_start)
		row.add_child(m._tl_start)
	var mine := WoodUI.button("Мой герой", UI.BLUE, 26, Vector2(240, 66))
	mine.pressed.connect(func(): m.show_hero_select("net"))
	row.add_child(mine)
	var back := WoodUI.button("Выйти", UI.PURPLE, 26, Vector2(200, 66))
	back.pressed.connect(func():
		m.net.leave()
		_close_lobby()
		show_net_lobby())
	row.add_child(back)
	_team_lobby_draw()
	if not m.net.is_host:
		_set_lobby_status("Подключаемся…")
	else:
		m.social.clear_game()
		m.show_hero_select("net")


## The seats as the lobby has them now.
func _team_lobby_draw() -> void:
	if m._tl_box == null or not is_instance_valid(m._tl_box) or m._tl.is_empty():
		return
	for ch in m._tl_box.get_children():
		ch.queue_free()
	var places: Array = m._tl["places"]
	if _room_n() == 3:
		# Each for itself: one seat a row.
		for gs in 3:
			var row3 := HBoxContainer.new()
			row3.alignment = BoxContainer.ALIGNMENT_CENTER
			row3.add_theme_constant_override("separation", 20)
			m._tl_box.add_child(row3)
			var label3 := WoodUI.label("Место %d" % (gs + 1), 26, Main.SLOT_COLORS[gs], 6)
			label3.custom_minimum_size = Vector2(170, 0)
			row3.add_child(label3)
			row3.add_child(_team_seat_panel(gs, int(places[gs])))
	for team in (0 if _room_n() == 3 else 2):
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 20)
		m._tl_box.add_child(row)
		var label := WoodUI.label("Команда %d" % (team + 1), 26, Main.SLOT_COLORS[team], 6)
		label.custom_minimum_size = Vector2(170, 0)
		row.add_child(label)
		for gs in [team, team + 2]:
			row.add_child(_team_seat_panel(gs, int(places[gs])))
	if m._tl_start != null and is_instance_valid(m._tl_start):
		var missing := _team_missing()
		m._tl_start.disabled = missing != ""
		if missing != "":
			_set_lobby_status(missing, UI.CREAM)
		else:
			_set_lobby_status("Все на местах!", Color(0.6, 1.0, 0.65))


## Why the host can't start yet ("" when it can).
func _team_missing() -> String:
	for gs in _room_n():
		var r := int(m._tl["places"][gs])
		if r >= 0 and not CardDB.valid_loadout(String(m._tl["heroes"].get(r, ""))):
			return "Ждём, пока %s выберет героя…" % String(m._tl["nicks"].get(r, "игрок"))
	return ""


func _team_seat_panel(gs: int, r: int) -> Control:
	var panel := PanelContainer.new()
	var me: bool = r >= 0 and r == m.net.seat_no
	var picked: bool = int(m._tl.get("pick", -1)) == gs
	var sb := WoodUI.inset(gs + 30, 10, 8)
	if me or picked:
		sb.line = WoodUI.GOLD if picked else Main.SLOT_COLORS[0]
		sb.line_width = 4.0
	sb.content_margin_right = 12
	panel.add_theme_stylebox_override("panel", sb)
	panel.custom_minimum_size = Vector2(560, 150) * WoodUI.font_scale
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(h)
	var pick: String = String(m._tl["heroes"].get(r, "")) if r >= 0 else String(m._tl["ai_heroes"][gs])
	var valid := CardDB.valid_loadout(pick)
	if valid:
		h.add_child(m._hero_card_rect(CardDB.loadout_card(pick), Vector2(96, 132)))
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(col)
	var who: String = "ИИ · " + AILevels.level(m._tl["levels"][gs])["name"] if r < 0 else String(m._tl["nicks"].get(r, "Игрок"))
	if me:
		who += " (ты)"
	col.add_child(WoodUI.label(who, 26, Color.WHITE, 6))
	if valid:
		var deck := CardDB.loadout_deck(pick)
		col.add_child(WoodUI.label(CardDB.hero_card(CardDB.loadout_card(pick))["name"], 24, CardDB.hero_color(deck), 6))
		col.add_child(WoodUI.label("Колода: " + CardDB.hero(deck)["name"], 18, UI.CREAM, 4, UI.UI_FONT))
	else:
		col.add_child(WoodUI.label("выбирает героя…", 20, UI.CREAM, 4, UI.UI_FONT))
	if m.net.is_host:
		var ctl := HBoxContainer.new()
		ctl.add_theme_constant_override("separation", 6)
		col.add_child(ctl)
		var move := WoodUI.button("Пересадить", UI.PURPLE, 16, Vector2(130, 34))
		move.pressed.connect(func(): _team_pick_seat(gs))
		ctl.add_child(move)
		if r < 0:
			for dir in [-1, 1]:
				var step: int = dir
				var b := WoodUI.button("◀" if dir < 0 else "▶", UI.BLUE, 16, Vector2(36, 34))
				b.pressed.connect(func():
					m._tl["levels"][gs] = AILevels.shift(m._tl["levels"][gs], step)
					m.seat_state(_room_mode())["levels"][gs] = m._tl["levels"][gs]
					m._save_setting(_room_mode(), "level_%d" % gs, m._tl["levels"][gs])
					_team_lobby_changed())
				ctl.add_child(b)
			var other := WoodUI.button("Другой герой", UI.BLUE, 16, Vector2(150, 34))
			other.pressed.connect(func():
				m._tl["ai_heroes"][gs] = m._random_hero()
				_team_lobby_changed())
			ctl.add_child(other)
	return panel


## Host: the first click picks a seat, the second swaps the two seats' players.
func _team_pick_seat(gs: int) -> void:
	var first := int(m._tl.get("pick", -1))
	if first < 0 or first == gs:
		m._tl["pick"] = -1 if first == gs else gs
		_team_lobby_draw()
		return
	var places: Array = m._tl["places"]
	var t = places[first]
	places[first] = places[gs]
	places[gs] = t
	var ai: Array = m._tl["ai_heroes"]
	var ah = ai[first]
	ai[first] = ai[gs]
	ai[gs] = ah
	m._tl["pick"] = -1
	UI.sfx("select")
	_team_lobby_changed()


## Host: the lobby changed; everybody gets it.
func _team_lobby_changed() -> void:
	var d := m._tl.duplicate(true)
	d.erase("pick")
	d["t"] = "lobby"
	m.net.send(d)
	_team_lobby_draw()


## Host: a guest's link is up. A new guest takes an empty seat, the teammate's first (на троих the next one).
func _on_seat_joined(g: int, resumed: bool) -> void:
	if not m.net.team or not m.net.is_host:
		return
	if resumed:
		_team_notice("")
		return
	if m.game != null or m._tl.is_empty():
		return
	var places: Array = m._tl["places"]
	if not places.has(g):
		for gs in ([1, 2] if _room_n() == 3 else [2, 1, 3]):
			if int(places[gs]) < 0:
				places[gs] = g
				break
	m._tl["nicks"][g] = "Игрок %d" % (g + 1)
	_team_lobby_changed()


## Host: a guest's link dropped (it may come back) or the guest left on purpose.
## In the lobby a leaver's seat goes back to the AI; in a game the AI plays on for them.
func _on_seat_left(g: int, on_purpose: bool) -> void:
	if not m.net.team or not m.net.is_host or m._tl.is_empty():
		return
	var places: Array = m._tl["places"]
	var gs := places.find(g)
	if m.game == null:
		if on_purpose and gs >= 0:
			places[gs] = -1
			m._tl["heroes"].erase(g)
			m._tl["nicks"].erase(g)
			_team_lobby_changed()
		return
	if gs < 0 or m.game.phase == "over" or m.board == null:
		return
	var pname: String = m.game.players[gs].name
	if on_purpose:
		_team_takeover(gs)
		return
	_team_notice("Связь с игроком %s потеряна. Ждём…" % pname, gs)


## Host: the AI plays seat gs from now on; the others are told.
func _team_takeover(gs: int) -> void:
	m._tl["places"][gs] = -1
	_team_notice("")
	m.net.send({"t": "takeover", "p": gs})
	m.board._add_log("— %s вышел, за него играет ИИ" % m.game.players[gs].name)
	var level: String = m.seat_state(_room_mode())["levels"][gs]
	m.board.takeover_seat(gs, AILevels.agent(level, CardDB.loadout(m.game.players[gs].hero, m.game.players[gs].hero_card)))


## Host: a small notice over the table while a guest is away ("" closes it). The host
## may let the AI play for the one who is away.
func _team_notice(text: String, gs := -1) -> void:
	if m._tl_notice != null and is_instance_valid(m._tl_notice):
		m._tl_notice.queue_free()
	m._tl_notice = null
	if text == "" or m.board == null:
		return
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", m._panel_box())
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 16)
	panel.add_child(h)
	h.add_child(WoodUI.label(text, 24, UI.CREAM, 6, UI.UI_FONT))
	if gs >= 0:
		var b := WoodUI.button("Пусть играет ИИ", UI.ORANGE, 20, Vector2(230, 50))
		b.pressed.connect(func(): _team_takeover(gs))
		h.add_child(b)
	m.overlay.add_child(panel)
	panel.position = Vector2(400, 20)
	m._tl_notice = panel


## Host: everybody is in. The seed, the first player and the picks go to every PC.
func _team_start() -> void:
	if _team_missing() != "":
		return
	var heroes := []
	for gs in _room_n():
		var r := int(m._tl["places"][gs])
		heroes.append(String(m._tl["heroes"][r]) if r >= 0 else String(m._tl["ai_heroes"][gs]))
	var d := {"t": "start", "seed": randi() & 0x7fffffff, "first": randi() % _room_n(), "heroes": heroes,
		"places": m._tl["places"].duplicate(), "levels": m._tl["levels"].duplicate(), "timer": _match_timer()}
	m.net.accept_new = false
	m.net.send(d)
	start_team_net_game(d)


## Every message of a 2 на 2 or на троих room (Net passes the guests' ones through the host).
func _team_message(d: Dictionary) -> void:
	var from := int(d.get("s", 0))
	var n := _room_n()
	match d.get("t", ""):
		"hero":
			if m.net.is_host and not m._tl.is_empty() and d.get("hero") is String:
				m._tl["heroes"][from] = String(d["hero"])
				if d.get("nick") is String and String(d["nick"]) != "":
					m._tl["nicks"][from] = String(d["nick"]).substr(0, 24)
				_team_lobby_changed()
		"lobby":
			if not m.net.is_host and from == 0:
				m._tl = d.duplicate(true)
				m._tl["pick"] = -1
				_team_lobby_draw()
				_set_lobby_status("Ждём начала игры", Color(0.6, 1.0, 0.65))
		"start":
			if not m.net.is_host and from == 0 and _start_ok(d, n) and _seats(d.get("places"), n):
				start_team_net_game(d)
		"lands", "mull":
			# Only for a seat the sender plays (the host also for the AI seats), with the right kind of answer.
			var sp: int = d["p"] if d.get("p") is int else -1
			var answer_ok: bool = _strings(d.get("types")) if d["t"] == "lands" else d.get("change") is bool
			if m.board != null and m.board.net_pcs.size() == n and sp >= 0 and sp < n and m.board._remote_seat_ok(sp, from) and answer_ok:
				m._tl_setup[String(d["t"])][sp] = d["types"] if d["t"] == "lands" else d["change"]
				m._tl_setup_msg.emit()
		"cmd", "choice":
			if m.board != null and m.online:
				m.board.net_receive(d)
		"surrender":
			var p: int = d["p"] if d.get("p") is int else -1
			if m.board != null and m.game != null and m.game.teams() and m.game.phase != "over" and p >= 0 and p < 4 and m.board._remote_seat_ok(p, from):
				var w: int = 1 - m.game.team(p)
				m.board.force_over(w)
				m._on_game_over(w, "%s сдаётся." % m.game.players[p].name)
		"chat":
			if d.get("text") is String:
				var nick := _clean_nick(d["nick"]) if d.get("nick") is String else ""
				m._got_game_chat(nick if nick != "" else "Игрок %d" % (from + 1), String(d["text"]).substr(0, Main.Social.TEXT_MAX))
		"takeover":
			if m.board != null and m.game != null and from == 0 and d.get("p") is int and int(d["p"]) >= 0 and int(d["p"]) < n:
				m.board.ai_names.append(int(d["p"]))
				for key in m.board.hero_ui:
					m.board.hero_ui[key]["side"] = -1
				m.board._add_log("— %s вышел, за него играет ИИ" % m.game.players[int(d["p"])].name)


## Guest: our link with the host is up: the host learns our name, then our hero once we pick it.
func _team_guest_connected(picked := false) -> void:
	m.net.send({"t": "hero", "hero": m.my_hero if picked else "", "nick": m.account.nick})
	if not picked:
		m.social.clear_game()
		m.show_hero_select("net")


## The game on every PC of the room: the same seed and picks, each PC at its own seat.
func start_team_net_game(d: Dictionary) -> void:
	_close_lobby()
	if m._game_over_root != null and is_instance_valid(m._game_over_root):
		m._close_overlay(m._game_over_root)
	m._game_over_root = null
	m._rematch_button = null
	m._rematch_note = null
	m._clear_title()
	if m.board != null:
		m.board.queue_free()
		m.board = null
	m.online = true
	m.ai_mode = false
	m._ai_vs_ai_mode = false
	var n := _room_n()
	m._mode = "three_net" if n == 3 else "teams_net"
	var places: Array = d["places"]
	if m.net.is_host:
		m._tl["places"] = places.duplicate()
	m.seat = places.find(m.net.seat_no)
	var heroes: Array = d["heroes"]
	var first := int(d["first"])
	m._tl_setup = {"lands": {}, "mull": {}}
	m.game = Game.new()
	var my_game = m.game
	m.game.setup(heroes, first, int(d["seed"]))
	m.game.journal = []
	m.hero_select.close_net()
	m._new_board()
	m.board.enable_net(m.net, m.seat, int(d.get("timer", 0)))
	m.board.show_chat_button(true)
	m.board.set_chat_unread(m.social.unread_total())
	m.board.humans = [m.seat]
	m.board.ai_names = range(n).filter(func(gs): return int(places[gs]) < 0)
	m.board.net_pcs = places.duplicate()
	m.board.desync.connect(_on_desync)
	var agents := {}
	if m.net.is_host:
		for gs in n:
			if int(places[gs]) < 0:
				agents[gs] = AILevels.agent(String(d["levels"][gs]), heroes[gs])
		m.board.set_seat_agents(agents)
	m.board.set_hands_hidden(true)
	var timer := int(d.get("timer", 0))
	var timer_text := "\nТаймер хода: %s." % _clock_text(timer) if timer > 0 else ""
	var coin := ""
	if n == 3:
		coin = "Ты играешь за: %s.\nСоперники: %s и %s.\nПервым ходит %s.%s" % [m.game.players[m.seat].name,
			m.game.players[(m.seat + 1) % 3].name, m.game.players[(m.seat + 2) % 3].name, m.game.players[first].name, timer_text]
	else:
		coin = "Ты играешь за: %s, напарник — %s.\nСоперники: %s.\nПервым ходит %s.%s" % [
			m.game.players[m.seat].name, m.game.players[(m.seat + 2) % 4].name, m.game.side_name(1 - m.game.team(m.seat)),
			m.game.players[first].name, timer_text]
	await m._curtain(first, "Бросаем монетку…", coin, "Дальше", true)
	if m.game != my_game:
		return
	# Landscapes: each person arranges their own, the AI keeps the deck's order.
	var types: Array = m.game.players[m.seat].lands.map(func(l): return l["type"])
	if CardDB.hero_land_types(m.game.players[m.seat].hero).size() > 1:
		types = await m.board.arrange_lands_prompt(m.seat)
		if m.game != my_game:
			return
	m._tl_setup["lands"][m.seat] = types
	m.net.send({"t": "lands", "p": m.seat, "types": types})
	var people: Array = range(n).filter(func(gs): return int(places[gs]) >= 0)
	if not await _team_wait("lands", people, "Ждём остальных…", "Игроки расставляют земли.", my_game):
		return
	for gs in people:
		await m.board.run_engine(func(): await m.game.cmd_arrange_lands(gs, m._tl_setup["lands"][gs]))
	m.board.set_hands_hidden(false)
	var changed: bool = await m.board.mulligan_prompt(m.seat)
	if m.game != my_game:
		return
	m._tl_setup["mull"][m.seat] = changed
	m.net.send({"t": "mull", "p": m.seat, "change": changed})
	for gs: int in agents:
		var ai_change: bool = agents[gs].has_method("mulligan") and agents[gs].mulligan(m.game, gs)
		m._tl_setup["mull"][gs] = ai_change
		m.net.send({"t": "mull", "p": gs, "change": ai_change})
	if not await _team_wait("mull", range(n), "Ждём остальных…", "Игроки смотрят стартовые руки.", my_game):
		return
	# Every PC applies the mulligans in the same order, so the decks stay the same.
	for gs in m.game.seats_from(first):
		if m._tl_setup["mull"][gs]:
			await m.board.run_engine(func(): await m.game.cmd_mulligan(gs))
	if m.game != my_game:
		return
	m.board.net_accept = true
	await m.board.run_engine(func(): await m.game.start_game())
	m.board.trigger_ai_turn()


## Waits until the setup step `key` has come from every seat in `seats`. False when the game was left.
func _team_wait(key: String, seats: Array, title: String, text: String, my_game) -> bool:
	var wait: Control = null
	while m.game == my_game and seats.any(func(gs): return not m._tl_setup[key].has(gs)):
		if wait == null:
			wait = m._message_overlay(title, text)
		await m._tl_setup_msg
	if wait != null:
		m._close_overlay(wait)
	return m.game == my_game
