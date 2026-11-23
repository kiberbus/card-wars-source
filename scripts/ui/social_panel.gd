extends Control
## «Игроки онлайн»: a panel that slides in from the right over any screen, with three tabs: who is
## online, the friends (requests, invites, coming into a friend's room) and the chat (the common one,
## the match's, private ones with friends). A button in the top corner opens it on the menu screens,
## the chat button of the table during an online game. A player's profile (a long press or a click on
## a row) opens over it; invites, friend requests and messages of the match come as notes under the corner.
## It sits on a layer of its own over the windows (main.gd). The data comes from scripts/net/social.gd.

const UI = preload("res://scripts/ui/ui_kit.gd")
const WoodUI = preload("res://scripts/ui/wood_ui.gd")
const FitCenter = preload("res://scripts/ui/fit_center.gd")
const Phone = preload("res://scripts/ui/phone.gd")
const Social = preload("res://scripts/net/social.gd")
const Avatar = preload("res://scripts/net/avatar.gd")
const AvatarView = preload("res://scripts/ui/avatar_view.gd")
const NickStyle = preload("res://scripts/ui/nick_style.gd")
const AwardsShelf = preload("res://scripts/ui/awards_shelf.gd")
const DeckShare = preload("res://scripts/net/deck_share.gd")
const CardDB = preload("res://scripts/core/card_db.gd")
const CustomDecks = preload("res://scripts/core/custom_decks.gd")
const DECK_PIC_H := 92          # the height of a card's picture on a deck in the chat
const GOLD := Color(1.0, 0.86, 0.35)
const GREEN := Color(0.6, 1.0, 0.65)
const RED := Color(1.0, 0.5, 0.45)
const WIDTH := 620.0
const HOLD_SEC := 0.45          # a long press on a row
const DRAG_PX := 14.0           # a press that moved more than this was a scroll
const REFRESH_MS := 8000
const QUICK := ["Привет!", "Удачи!", "Хороший ход!", "Спасибо за игру!"]
## The colours an admin picks for a nick with one press (any other one by its code).
const NICK_COLORS := ["ff4d4d", "ff9f1c", "ffd23f", "7ae582", "2ec4b6", "4dabf7", "9b5de5", "f15bb5", "ffffff", "541687"]

var m                           # main.gd
var social: Social
var pill: Button                # the corner button: players online, unread messages
var _pill_badge: Control
var _panel: PanelContainer
var _shown := false
var _pill_on := true            # main.gd: the corner button belongs on this screen
var _built_up := false          # the link and the login when the tab was drawn
var _built_in := false
var _tab := "online"
var _channel := Social.COMMON
var _tabs := {}                 # tab -> Button
var _body: VBoxContainer
var _list: VBoxContainer        # rows of the online / friends tab
var _note: Label                # a line under the list: an answer, a reason
var _chat_log: VBoxContainer    # the chat's lines (_log) and decks (_append_deck)
var _chat_scroll: ScrollContainer
var _chat_edit: LineEdit
var _chips: HBoxContainer
var _refresh_at := 0
var _loading := false
var _toasts: VBoxContainer
var _profile: Control = null
var _last_rows: Array = []      # the rows of the last answer (for the avatars that come later)
var _picking := false           # the chat tab shows the list of own decks to send («Колода»)
var _fans := {}                 # "<height>:<card ids>" -> the fan picture of a deck (_fan_texture)


func setup(main) -> void:
	m = main
	social = main.social


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill = WoodUI.button("", WoodUI.GO, 24, Vector2(250, 58)) if not Phone.active else WoodUI.button("", WoodUI.GO, 20, Vector2(190, 58))
	pill.pressed.connect(func(): toggle())
	add_child(pill)
	_pill_badge = _badge()
	pill.add_child(_pill_badge)
	_toasts = VBoxContainer.new()
	_toasts.add_theme_constant_override("separation", 10)
	_toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_toasts)
	_build_panel()
	social.changed.connect(_on_changed)
	social.unread_changed.connect(_refresh_pill)
	social.message.connect(_on_message)
	social.invited.connect(_on_invited)
	social.requested.connect(_on_requested)
	social.styled.connect(_on_styled)
	social.friend_added.connect(func(nick: String):
		drop_toasts("friend:" + nick)
		toast("%s теперь твой друг" % nick, [], 5.0)
		if _shown and _tab == "friends":
			_load_list())
	resized.connect(_place)
	_place()
	_refresh_pill()


func _process(_delta: float) -> void:
	if _shown and (_tab == "online" or _tab == "friends") and Time.get_ticks_msec() >= _refresh_at and not _loading:
		_load_list()


## The room the corner button takes at the top right of a menu screen (zero where it does not show):
## a screen with its own row of controls at the top keeps them out from under it.
func corner_room() -> Vector2:
	if not _pill_on:
		return Vector2.ZERO
	return pill.get_combined_minimum_size() + Vector2(12.0, 12.0)


## The corner button shows on the menu screens (not over a table, which has its own chat button).
func set_pill_visible(on: bool) -> void:
	_pill_on = on
	pill.visible = on and not _shown
	_place()


# ================================================================ layout

func _place() -> void:
	var room := FitCenter.safe_rect(self, 12.0)
	var k := WoodUI.font_scale
	pill.position = Vector2(room.end.x - pill.size.x, room.position.y)
	var w := minf(WIDTH * k, size.x)
	_panel.size = Vector2(w, size.y)
	_panel.position = Vector2(size.x - w if _shown else size.x + 12.0, 0.0)
	_toasts.custom_minimum_size = Vector2(minf(520.0 * k, room.size.x), 0)
	_toasts.size = Vector2(_toasts.custom_minimum_size.x, 0)
	var right := (size.x - w - 12.0) if _shown else room.end.x
	if m != null and m.board != null and not _shown:
		right = room.get_center().x + _toasts.size.x * 0.5     # over a table: in the middle, off the hero panels
	_toasts.position = Vector2(right - _toasts.size.x, room.position.y + (pill.size.y + 12.0 if pill.visible and not _shown else 0.0))


## A small red circle with a number, in the top right corner of its parent; hidden at 0.
func _badge() -> Control:
	var b := Label.new()
	b.visible = false
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var ls := LabelSettings.new()
	ls.font = WoodUI.BOLD
	ls.font_size = WoodUI.fs(18)
	ls.font_color = Color.WHITE
	b.label_settings = ls
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.85, 0.2, 0.18)
	sb.set_corner_radius_all(14)
	sb.border_color = WoodUI.INK
	sb.set_border_width_all(2)
	sb.content_margin_left = 7
	sb.content_margin_right = 7
	b.add_theme_stylebox_override("normal", sb)
	b.anchor_left = 1.0
	b.anchor_right = 1.0
	b.offset_left = -18.0
	b.offset_right = -18.0
	b.offset_top = -14.0
	b.grow_horizontal = Control.GROW_DIRECTION_BOTH
	return b


static func _set_badge(b: Control, n: int) -> void:
	b.visible = n > 0
	(b as Label).text = str(n) if n < 100 else "99+"


func _refresh_pill() -> void:
	if social.link_up:
		pill.text = "Онлайн: %d" % social.count
	else:
		pill.text = "Игроки онлайн"
	_set_badge(_pill_badge, social.unread_total() + social.requests.size())
	if m != null and m.board != null and m.board.has_method("set_chat_unread"):
		m.board.set_chat_unread(social.unread_total())
	for key in _tabs:
		if key == "chat":
			_set_badge(_tabs[key].get_child(0), social.unread_total())
		elif key == "friends":
			_set_badge(_tabs[key].get_child(0), social.requests.size())
	_refresh_chips()


## The link came up or went, the count or the requests changed: the tab is drawn anew only when
## the link changed (a chat being typed stays), the lists ask for their rows again.
func _on_changed() -> void:
	_refresh_pill()
	if not _shown:
		return
	if social.link_up != _built_up or m.account.logged_in() != _built_in:
		_show_tab(_tab)
	else:
		_refresh_at = 0


# ================================================================ the panel

func _build_panel() -> void:
	_panel = PanelContainer.new()
	var sb := WoodUI.window(22, 20)
	_panel.add_theme_stylebox_override("panel", sb)
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.visible = false
	add_child(_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	_panel.add_child(v)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	v.add_child(head)
	for key in ["online", "friends", "chat"]:
		var b := WoodUI.tab({"online": "Онлайн", "friends": "Друзья", "chat": "Чат"}[key], 24, Vector2(150, 54))
		b.add_child(_badge())
		b.pressed.connect(_show_tab.bind(key))
		head.add_child(b)
		_tabs[key] = b
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(gap)
	var close := WoodUI.button("Закрыть", WoodUI.BACK, 22, Vector2(0, 54))
	close.pressed.connect(hide_panel)
	head.add_child(close)
	_body = VBoxContainer.new()
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 10)
	v.add_child(_body)


func toggle() -> void:
	if _shown:
		hide_panel()
	else:
		show_panel()


## Opens the panel on a tab ("" keeps the last one); a chat tab may open on a channel.
func show_panel(tab := "", channel = null) -> void:
	if channel != null:
		_channel = channel
	_shown = true
	_panel.visible = true
	_place()
	_panel.position.x = size.x + 12.0
	create_tween().tween_property(_panel, "position:x", size.x - _panel.size.x, 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	pill.visible = false
	_show_tab(tab if tab != "" else _tab)
	_place()


func hide_panel() -> void:
	if not _shown:
		return
	_shown = false
	_picking = false
	social.read("-")
	var tw := create_tween()
	tw.tween_property(_panel, "position:x", size.x + 12.0, 0.18)
	tw.tween_callback(func():
		if not _shown:
			_panel.visible = false)
	pill.visible = _pill_on
	_place()
	if _chat_edit != null and is_instance_valid(_chat_edit):
		_chat_edit.release_focus()


func is_open() -> bool:
	return _shown


func _show_tab(tab: String) -> void:
	if tab != "chat":
		_picking = false
	_tab = tab
	_built_up = social.link_up
	_built_in = m.account.logged_in()
	for key in _tabs:
		WoodUI.set_tab(_tabs[key], key == tab)
	for ch in _body.get_children():
		ch.queue_free()
	_list = null
	_note = null
	_chat_log = null
	_chat_edit = null
	_chips = null
	if tab != "chat":
		social.read("-")
	match tab:
		"online":
			_online_tab()
		"friends":
			_friends_tab()
		"chat":
			_chat_tab()


## A guest, or no link: one line instead of the tab (and the button to log in).
func _offline_body() -> bool:
	if not m.account.logged_in():
		_body.add_child(_line("Войди, чтобы видеть игроков онлайн, добавлять друзей и писать в чат"))
		var enter := WoodUI.button("Войти", UI.GREEN, 26, Vector2(220, 58))
		enter.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		enter.pressed.connect(func():
			hide_panel()
			m.show_login())
		_body.add_child(enter)
		return true
	if not social.link_up:
		_body.add_child(_line("Нет связи с сервером"))
		return true
	return false


func _line(text: String, color := UI.CREAM, size := 22) -> Label:
	var l := WoodUI.label(text, size, color, 5, UI.UI_FONT)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.custom_minimum_size = Vector2(200, 0)
	return l


func _scroll_list() -> void:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_body.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 8)
	scroll.add_child(_list)
	_note = _line("", UI.CREAM, 20)
	_body.add_child(_note)


func _online_tab() -> void:
	if _offline_body():
		return
	_scroll_list()
	_refresh_at = 0
	_load_list()


func _friends_tab() -> void:
	if _offline_body():
		return
	var add_row := HBoxContainer.new()
	add_row.add_theme_constant_override("separation", 8)
	_body.add_child(add_row)
	var edit := LineEdit.new()
	edit.placeholder_text = "Ник друга"
	edit.max_length = 16
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	WoodUI.edit(edit, 24)
	add_row.add_child(edit)
	var add := WoodUI.button("Добавить", UI.GREEN, 22, Vector2(0, 54))
	var send := func(_t = ""):
		var nick := edit.text.strip_edges()
		if nick.length() >= 3:
			edit.text = ""
			_friend_act(nick, "add")
	add.pressed.connect(send)
	edit.text_submitted.connect(send)
	add_row.add_child(add)
	# Who may call this player into a game (main.social_status gives it to the relay).
	var only: Button = m.lobby._check_button("Звать меня могут только друзья", m._load_setting("net", "invites_friends", false))
	only.toggled.connect(func(on: bool): m._save_setting("net", "invites_friends", on))
	_body.add_child(only)
	_scroll_list()
	_refresh_at = 0
	_load_list()


## Asks the server for the rows of the tab and draws them.
func _load_list() -> void:
	_refresh_at = Time.get_ticks_msec() + REFRESH_MS
	if _list == null or not social.link_up:
		return
	_loading = true
	var tab := _tab
	var answer: Dictionary = await social.ask({"op": "s_online" if tab == "online" else "s_friends"})
	_loading = false
	if tab != _tab or _list == null or not is_instance_valid(_list):
		return
	if answer.get("op") == "s_error":
		_set_note(Social.reason(String(answer.get("r", ""))), RED)
		return
	for ch in _list.get_children():
		ch.queue_free()
	var rows: Array = answer.get("players", [])
	if tab == "online":
		if rows.is_empty():
			_list.add_child(_line("Кроме тебя никого нет"))
		for r in rows:
			if r is Dictionary:
				_list.add_child(_row(r))
	else:
		var asked: Array = answer.get("requests", [])
		social.requests = asked.map(func(r): return String(r.get("nick", "")))
		_refresh_pill()
		if not asked.is_empty():
			_list.add_child(WoodUI.label("Заявки в друзья", 24, GOLD, 6))
			for r in asked:
				_list.add_child(_row(r, true))
		rows.sort_custom(func(a, b): return (a.get("st") != "off") and b.get("st") == "off")
		if not rows.is_empty():
			_list.add_child(WoodUI.label("Друзья", 24, GOLD, 6))
		elif asked.is_empty():
			_list.add_child(_line("Друзей пока нет. Добавь по нику или из списка онлайн"))
		for r in rows:
			_list.add_child(_row(r))
	_last_rows = rows + answer.get("requests", [])
	_fetch_avatars(_last_rows)


func _set_note(text: String, color := UI.CREAM) -> void:
	if _note != null and is_instance_valid(_note):
		_note.text = text
		_note.label_settings.font_color = color


## Avatars that are not on this PC yet: the rows get them when they come.
func _fetch_avatars(rows: Array) -> void:
	await Avatar.fetch(get_tree(), m.net.relay_url, rows)
	if _list == null or not is_instance_valid(_list):
		return
	for row in _list.get_children():
		if row.has_meta("face"):
			var face = row.get_meta("face")
			if face != null and is_instance_valid(face) and face.has_method("set_texture"):
				face.set_texture(Avatar.cached(String(row.get_meta("nick")), String(row.get_meta("av"))))


## A row of a player: the avatar, the nick, what they do; the buttons that fit. A press opens the
## profile (a long press too, so a finger on a phone finds it).
func _row(r: Dictionary, request := false) -> Control:
	var nick := String(r.get("nick", ""))
	var st := String(r.get("st", "off"))
	var panel := PanelContainer.new()
	var sb := WoodUI.inset(nick.hash() % 50, 10, 6)
	panel.add_theme_stylebox_override("panel", sb)
	panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	panel.set_meta("nick", nick)
	panel.set_meta("av", String(r.get("av", "")))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(h)
	var face := AvatarView.make(nick, Avatar.cached(nick, String(r.get("av", ""))), roundi(54 * WoodUI.font_scale),
		GREEN if st != "off" else Color(1, 1, 1, 0.4))
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.set_meta("face", face)
	h.add_child(face)
	var names := VBoxContainer.new()
	names.add_theme_constant_override("separation", 0)
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	names.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(names)
	var name_label := WoodUI.label(nick, 24, Color.WHITE, 5)
	name_label.clip_text = true
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	NickStyle.apply(name_label, r.get("rb") == true, String(r.get("col", "")))
	names.add_child(name_label)
	var fr := String(r.get("fr", ""))
	var under := "хочет дружить" if request else Social.status_text(st)
	if fr == "friend" and not request:
		under = "друг · " + under
	if r.get("rk") is int and not request:
		under = Social.stage_name(r["rk"]) + " · " + under
	var st_label := WoodUI.label(under, 18, GREEN if st != "off" and st != "game" else UI.CREAM, 4, UI.UI_FONT)
	st_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	names.add_child(st_label)
	if request:
		h.add_child(_small("Принять", UI.GREEN, func(): _friend_act(nick, "accept")))
		h.add_child(_small("Нет", UI.RED, func(): _friend_act(nick, "decline")))
	else:
		_play_button(h, r, nick, st, "Войти", "Позвать")
		if fr == "friend":
			if st != "off":
				h.add_child(_small("Написать", UI.BLUE, func(): open_chat(nick)))
		elif fr == "" and _tab == "online":
			h.add_child(_small("+", UI.GREEN, func(): _friend_act(nick, "add"), 54))
	_press_opens_profile(panel, nick)
	return panel


## «Войти» into the room of a player (the relay shows its code to those it is open to: a friend, or
## everybody when its owner left it open), or «Позвать» into our own room: anybody online, but not one
## who takes invites from friends only ("ni").
func _play_button(row: Control, r: Dictionary, nick: String, st: String, join_text: String, call_text: String) -> void:
	if String(r.get("code", "")) != "" and m.social_status()[0] != "game":
		row.add_child(_small(join_text, UI.GREEN, func(): _join(String(r["code"]))))
	elif m.can_invite() and st != "off" and st != "game" and r.get("ni") != true:
		row.add_child(_small(call_text, UI.ORANGE, func(): _invite(nick)))


func _small(text: String, color: Color, on_press: Callable, w := 0) -> Button:
	var b := WoodUI.button(text, color, 20, Vector2(w, 48))
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.pressed.connect(on_press)
	return b


## A press (or a long press) on the control opens the player's profile; a press that scrolled does not.
func _press_opens_profile(c: Control, nick: String) -> void:
	var state := {"down": false, "at": Vector2.ZERO, "done": false, "n": 0}
	c.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
			if e.pressed:
				state["down"] = true
				state["done"] = false
				state["at"] = e.global_position
				state["n"] += 1
				var n: int = state["n"]
				get_tree().create_timer(HOLD_SEC).timeout.connect(func():
					if state["down"] and state["n"] == n and not state["done"] and is_instance_valid(c):
						state["done"] = true
						show_profile(nick))
			elif state["down"]:
				state["down"] = false
				if not state["done"] and e.global_position.distance_to(state["at"]) < DRAG_PX:
					state["done"] = true
					UI.sfx("press")
					show_profile(nick)
		elif e is InputEventMouseMotion and state["down"] and e.global_position.distance_to(state["at"]) >= DRAG_PX:
			state["down"] = false)


# ================================================================ actions

func _friend_act(nick: String, act: String) -> void:
	_set_note("…")
	var answer: Dictionary = await social.ask({"op": "s_friend", "nick": nick, "act": act})
	if answer.get("op") == "s_error" or String(answer.get("r", "")) != "":
		var why := Social.reason(String(answer.get("r", "")))
		_set_note(why, RED)
		toast(why, [], 3.0)
		return
	social.requests.erase(nick)
	drop_toasts("friend:" + nick)
	var fr := String(answer.get("fr", ""))
	var text: String = {"friend": "%s теперь твой друг", "sent": "Заявка отправлена: %s"}.get(fr, "Готово: %s") % nick
	if act == "remove":
		text = "%s больше не друг" % nick
	elif act == "decline":
		text = "Заявка отклонена"
	_set_note(text, GREEN)
	_refresh_pill()
	_refresh_at = 0
	if _profile != null and is_instance_valid(_profile) and String(_profile.get_meta("nick", "")) == nick:
		show_profile(nick)


func _invite(nick: String) -> void:
	var answer: Dictionary = await social.ask({"op": "s_invite", "nick": nick})
	var ok: bool = answer.get("op") == "s_done" and String(answer.get("r", "")) == ""
	var text := "Приглашение отправлено: %s" % nick if ok else Social.reason(String(answer.get("r", "")))
	_set_note(text, GREEN if ok else RED)
	toast(text, [], 3.0)


func _join(code: String, pass_key := "") -> void:
	for t in _toasts.get_children():
		if String(t.get_meta("key", "")).begins_with("invite:"):
			t.queue_free()
	hide_panel()
	close_profile()
	m.join_friend_room(code, pass_key)


# ================================================================ chat

## Opens the chat on a channel (a friend's nick: a private chat with them).
func open_chat(ch: String) -> void:
	close_profile()
	show_panel("chat", ch)


func _chat_tab() -> void:
	var channels := _channels()
	if not channels.has(_channel):
		_channel = channels[0] if not channels.is_empty() else Social.COMMON
	_chips = HBoxContainer.new()
	_chips.add_theme_constant_override("separation", 6)
	var chip_scroll := ScrollContainer.new()
	chip_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	chip_scroll.custom_minimum_size = Vector2(0, 64 * WoodUI.font_scale)
	chip_scroll.add_child(_chips)
	_body.add_child(chip_scroll)
	_refresh_chips()
	if _channel == Social.COMMON and _offline_body():
		return
	if _picking:
		_deck_picker()
		return
	var log_panel := PanelContainer.new()
	log_panel.add_theme_stylebox_override("panel", WoodUI.inset(7, 12, 8))
	log_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_child(log_panel)
	# The log: runs of text lines (one RichTextLabel each) and, between them, the decks sent (a box each).
	_chat_scroll = ScrollContainer.new()
	_chat_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	log_panel.add_child(_chat_scroll)
	_chat_log = VBoxContainer.new()
	_chat_log.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_chat_log.add_theme_constant_override("separation", 6)
	_chat_scroll.add_child(_chat_log)
	var lines: Array = social.chats.get(_channel, [])
	if lines.is_empty():
		_log("[color=#b8ad9a]%s[/color]" % ("Сообщений пока нет" if _channel != Social.GAME else "Здесь чат с соперником"))
	for msg: Dictionary in lines:
		_append(msg)
	social.read(_channel)
	if _channel == Social.GAME:
		var quick := HFlowContainer.new()
		quick.add_theme_constant_override("h_separation", 6)
		quick.add_theme_constant_override("v_separation", 6)
		_body.add_child(quick)
		for q: String in QUICK:
			quick.add_child(_small(q, UI.PURPLE, func(): _send(q)))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_body.add_child(row)
	_chat_edit = LineEdit.new()
	_chat_edit.max_length = Social.TEXT_MAX
	_chat_edit.placeholder_text = "Сообщение"
	_chat_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	WoodUI.edit(_chat_edit, 22)
	row.add_child(_chat_edit)
	var share := WoodUI.button("Колода", WoodUI.ORANGE, 22, Vector2(0, 54))
	share.tooltip_text = "Поделиться своей колодой"
	share.pressed.connect(func():
		_picking = true
		_show_tab("chat"))
	row.add_child(share)
	var send := WoodUI.button("Отправить", UI.GREEN, 22, Vector2(0, 54))
	row.add_child(send)
	send.pressed.connect(func(): _send(_chat_edit.text))
	_chat_edit.text_submitted.connect(func(t: String): _send(t))
	if not OS.has_feature("mobile"):
		_chat_edit.grab_focus.call_deferred()


## The channels of the chip row: the match's while there is one, the common one, private ones.
func _channels() -> Array:
	var out := []
	if m.game_chat_on() or social.chats.has(Social.GAME):
		out.append(Social.GAME)
	out.append(Social.COMMON)
	for ch: String in social.chats:
		if ch != Social.GAME and ch != Social.COMMON:
			out.append(ch)
	if _channel != Social.GAME and _channel != Social.COMMON and not out.has(_channel):
		out.append(_channel)
	return out


func _refresh_chips() -> void:
	if _chips == null or not is_instance_valid(_chips):
		return
	for ch in _chips.get_children():
		ch.queue_free()
	for ch: String in _channels():
		var name: String = {Social.GAME: "Игра", Social.COMMON: "Общий"}.get(ch, ch)
		var b := WoodUI.tab(name, 20, Vector2(0, 48))
		WoodUI.set_tab(b, ch == _channel)
		var badge := _badge()
		b.add_child(badge)
		_set_badge(badge, 0 if ch == _channel else int(social.unread.get(ch, 0)))
		b.pressed.connect(func():
			_channel = ch
			_picking = false
			_show_tab("chat"))
		_chips.add_child(b)


func _send(text: String) -> void:
	text = text.strip_edges()
	if text == "":
		return
	if _channel == Social.GAME:
		if not m.game_chat_on():
			_log("[color=#ff8a80]Матч закончился[/color]")
			return
		m.send_game_chat(text)
	elif not social.link_up:
		_log("[color=#ff8a80]Нет связи с сервером[/color]")
		return
	else:
		social.say(_channel, text)
	if _chat_edit != null and is_instance_valid(_chat_edit):
		_chat_edit.text = ""
		if not OS.has_feature("mobile"):
			_chat_edit.grab_focus()


func _append(msg: Dictionary) -> void:
	if _chat_log == null or not is_instance_valid(_chat_log):
		return
	var text := String(msg.get("text", "")).replace("[", "[lb]")
	if msg.get("sys", false):
		_log("[color=#9fe7ff]%s[/color]" % text)
		return
	var nick := String(msg.get("nick", ""))
	var color := NickStyle.color_of(String(msg.get("col", "")), GOLD if msg.get("me", false) else AvatarView.nick_color(nick).lightened(0.35))
	var deck := DeckShare.decode(String(msg.get("text", "")))
	if not deck.is_empty():
		_log("[b][color=#%s]%s[/color][/b]  [color=#b8ad9a]делится колодой[/color]" % [color.to_html(false), nick.replace("[", "[lb]")])
		_append_deck(deck)
		return
	_log("[b][color=#%s]%s[/color][/b]  %s" % [color.to_html(false), nick.replace("[", "[lb]"), text])


## A line of the chat log (bbcode): it joins the run of text after the last deck, or starts one.
func _log(bbcode: String) -> void:
	if _chat_log == null or not is_instance_valid(_chat_log):
		return
	var run: RichTextLabel = null
	if _chat_log.get_child_count() > 0 and _chat_log.get_child(-1) is RichTextLabel:
		run = _chat_log.get_child(-1)
		run.append_text("\n")
	else:
		run = RichTextLabel.new()
		run.bbcode_enabled = true
		run.fit_content = true
		run.scroll_active = false
		run.selection_enabled = true
		run.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		run.add_theme_font_override("normal_font", WoodUI.REGULAR)
		run.add_theme_font_override("bold_font", WoodUI.BOLD)
		run.add_theme_font_size_override("normal_font_size", WoodUI.fs(21))
		run.add_theme_font_size_override("bold_font_size", WoodUI.fs(21))
		run.add_theme_color_override("default_color", Color(0.95, 0.92, 0.86))
		_chat_log.add_child(run)
	run.append_text(bbcode)
	_scroll_down()


## The log shows its newest line (as the chat always did).
func _scroll_down() -> void:
	if _chat_scroll == null or not is_instance_valid(_chat_scroll):
		return
	await get_tree().process_frame
	if is_instance_valid(_chat_scroll):
		_chat_scroll.scroll_vertical = int(_chat_scroll.get_v_scroll_bar().max_value)


## A deck in the chat: a box in the look of the window (felt, an ink outline, round corners) with
## the fan of its dearest cards at the left, in the middle of the box's height, and at the right its
## name, hero, size and lands, and the button that adds it to the own decks.
func _append_deck(deck: Dictionary) -> void:
	var cards: Dictionary = deck["deck"]
	var box := PanelContainer.new()
	var sb := WoodUI.paper(WoodUI.FELT.darkened(0.08), 0.0, _chat_log.get_child_count() * 7, 2.5)
	sb.radius = 14.0
	sb.content_margin_left = 12
	sb.content_margin_right = 14
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	box.add_theme_stylebox_override("panel", sb)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	box.add_child(h)
	var top := DeckShare.top_cards(cards)
	var fan := _fan_texture(top, int(DECK_PIC_H * WoodUI.font_scale))
	if fan != null:
		var pic := TextureRect.new()
		pic.texture = fan
		pic.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		pic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		pic.tooltip_text = ", ".join(PackedStringArray(top.map(func(id): return String(CardDB.get_def(id)["name"]))))
		h.add_child(pic)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	v.add_theme_constant_override("separation", 4)
	h.add_child(v)
	var title := WoodUI.label(String(deck["name"]), 22, GOLD, 4)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(title)
	var facts := "%d карт" % DeckShare.total(cards)
	if deck.has("hero"):
		facts = String(CardDB.hero_card(deck["hero"]).get("name", "")) + " · " + facts
	var lands := []
	for t: String in deck["lands"]:
		if not lands.has(t):
			lands.append(t)
	facts += " · " + ", ".join(PackedStringArray(lands.map(func(t): return CardDB.land_name(t))))
	var note := ""
	var note_color := Color(0.95, 0.92, 0.86)
	if int(deck["unknown"]) > 0:
		note = "Незнакомых карт: %d, обнови игру" % int(deck["unknown"])
		note_color = RED
	elif not CardDB.deck_errors(deck["lands"], cards).is_empty():
		note = "Черновик: нарушает правила колоды"
	for line: Array in [[facts, Color(0.95, 0.92, 0.86)], [note, note_color]]:
		if String(line[0]) == "":
			continue
		var l := WoodUI.label(line[0], 19, line[1], 0, UI.UI_FONT)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(l)
	var take := WoodUI.button("Забрать колоду", WoodUI.GO, 20, Vector2(0, 46))
	take.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	take.pressed.connect(func(): _take_deck(deck))
	v.add_child(take)
	_chat_log.add_child(box)
	_scroll_down()


## The deck's dearest cards as a fan in one picture: the first one whole in front, the second
## behind it showing half of itself, the third behind that showing a third; the cards behind are
## a little smaller and the ones in front cast a shadow on them. null when no card has a picture.
func _fan_texture(ids: Array, h: int) -> Texture2D:
	var key := "%d:%s" % [h, ",".join(PackedStringArray(ids))]
	if _fans.has(key):
		return _fans[key]
	var pics := []      # front first: [Image, scale]
	var scales := [1.0, 0.92, 0.84]
	for id: String in ids:
		var path := CardDB.card_thumb(id)
		var tex: Texture2D = load(path) if ResourceLoader.exists(path) else null
		if tex == null:
			continue
		var img := tex.get_image()
		if img == null:
			continue
		if img.is_compressed():
			img.decompress()
		img.convert(Image.FORMAT_RGBA8)
		var ch := int(round(h * scales[pics.size()]))
		img.resize(maxi(1, int(round(ch * float(img.get_width()) / img.get_height()))), ch, Image.INTERPOLATE_LANCZOS)
		pics.append(img)
	if pics.is_empty():
		return null
	# Where each card's left edge goes: one behind shows SHOW[i] of its width past the one in front.
	const SHOW := [1.0, 0.5, 1.0 / 3.0]
	var xs := [0]
	var right: int = pics[0].get_width()
	for i in range(1, pics.size()):
		var w: int = pics[i].get_width()
		right += int(round(w * SHOW[i]))
		xs.append(right - w)
	var canvas := Image.create_empty(right, h, false, Image.FORMAT_RGBA8)
	for i in range(pics.size() - 1, -1, -1):
		var img: Image = pics[i]
		var y: int = (h - img.get_height()) / 2
		canvas.blend_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i(xs[i], y))
		if i > 0:
			# The card in front casts a soft shadow on this one, along its own right edge.
			var edge: int = xs[i - 1] + pics[i - 1].get_width()
			var shade := Image.create_empty(1, img.get_height(), false, Image.FORMAT_RGBA8)
			for k in 8:
				shade.fill(Color(0, 0, 0, 0.5 * (1.0 - k / 8.0)))
				canvas.blend_rect(shade, Rect2i(0, 0, 1, img.get_height()), Vector2i(edge + k, y))
	var out := ImageTexture.create_from_image(canvas)
	_fans[key] = out
	return out


## Adds a deck from the chat to the own decks (the deck builder's «Колоды»).
func _take_deck(deck: Dictionary) -> void:
	if (deck["deck"] as Dictionary).is_empty():
		toast("В этой колоде нет знакомых карт, обнови игру", [], 4.0)
		return
	var entry := {"name": deck["name"], "lands": deck["lands"], "deck": deck["deck"]}
	if deck.has("hero"):
		entry["hero"] = deck["hero"]
	var saved := CustomDecks.add(entry)
	if saved == "":
		toast("Не получилось сохранить колоду", [], 4.0)
		return
	UI.sfx("coin")
	toast("Колода «%s» в твоих колодах (Конструктор колод → Колоды)" % saved, [], 5.0, "deck_taken")


## «Колода»: the own decks to send into the open channel; one press sends it.
func _deck_picker() -> void:
	_body.add_child(_line("Какой колодой поделиться?", GOLD, 24))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_body.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 8)
	scroll.add_child(list)
	var entries := CustomDecks.load_all()
	if entries.is_empty():
		list.add_child(_line("Своих колод пока нет. Собери колоду в «Конструкторе колод» и сохрани её"))
	for e: Dictionary in entries:
		var deck_name := String(e.get("name", "?"))
		var draft := not CardDB.has_hero(CustomDecks.code_of(e))
		var b := WoodUI.tab(deck_name + (" · черновик" if draft else ""), 22, Vector2(0, 56))
		WoodUI.set_tab(b, true)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func(): _share_deck(e))
		list.add_child(b)
	var back := WoodUI.button("Назад", WoodUI.BACK, 22, Vector2(200, 54))
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back.pressed.connect(func():
		_picking = false
		_show_tab("chat"))
	_body.add_child(back)


func _share_deck(e: Dictionary) -> void:
	var text := DeckShare.encode(e)
	if text == "":
		toast("Колода не помещается в одно сообщение: слишком много разных карт", [], 5.0)
		return
	_picking = false
	_show_tab("chat")
	_send(text)


func _on_message(ch: String, msg: Dictionary) -> void:
	if _shown and _tab == "chat" and ch == _channel:
		_append(msg)
		social.read(ch)
		return
	_refresh_chips()
	if msg.get("me", false) or msg.get("sys", false) or ch == Social.COMMON:
		return
	if _shown and _tab == "chat":
		return
	# The match's messages and private ones come as a note while the chat is not looked at.
	var who := String(msg.get("nick", ""))
	var head := who if ch == Social.GAME else "%s пишет" % who
	if DeckShare.is_deck(String(msg.get("text", ""))):
		return      # a deck waits in the chat (its unread mark shows it): no note over the screen
	toast("%s: %s" % [head, String(msg.get("text", ""))], [["Ответить", UI.BLUE, func(): open_chat(ch)]], 6.0, "chat:" + ch)


# ================================================================ notes

## A note under the corner: a text and buttons [[text, colour, Callable]]; it goes after `sec`
## or when a button is pressed. A note with a `key` replaces the one with the same key (drop_toasts).
func toast(text: String, buttons: Array, sec: float, key := "") -> Control:
	if key != "":
		drop_toasts(key)
	var panel := PanelContainer.new()
	panel.set_meta("key", key)
	var sb := WoodUI.card(WoodUI.PAPER, 0.0, text.hash() % 40)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", sb)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var v := HBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	var l := WoodUI.text(text, 22, WoodUI.INK, true)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	l.custom_minimum_size = Vector2(180, 0)
	v.add_child(l)
	var gone := func():
		if is_instance_valid(panel):
			panel.queue_free()
	if not buttons.is_empty():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		v.add_child(row)
		for b: Array in buttons:
			var press: Callable = b[2]
			row.add_child(_small(b[0], b[1], func():
				gone.call()
				press.call()))
	_toasts.add_child(panel)
	_place()
	while _toasts.get_child_count() > 4:
		_toasts.get_child(0).queue_free()
	panel.modulate.a = 0.0
	panel.create_tween().tween_property(panel, "modulate:a", 1.0, 0.2)
	get_tree().create_timer(sec).timeout.connect(func():
		if is_instance_valid(panel):
			var tw := panel.create_tween()
			tw.tween_property(panel, "modulate:a", 0.0, 0.3)
			tw.tween_callback(panel.queue_free))
	_place()
	return panel


## The notes with this key go (a request answered elsewhere, an invite taken).
func drop_toasts(key: String) -> void:
	for t in _toasts.get_children():
		if String(t.get_meta("key", "")) == key:
			t.queue_free()


func _on_invited(d: Dictionary) -> void:
	var nick := String(d["nick"])
	var code := String(d["code"])
	var pass_key := String(d.get("pass", ""))
	UI.sfx("coin")
	var kind := " 2 на 2" if d.get("four") == true else (" на троих" if d.get("seats") == 3 else "")
	toast("%s зовёт в игру%s" % [nick, kind],
		[["Принять", UI.GREEN, func(): _join(code, pass_key)], ["Нет", UI.RED, func(): pass]], 30.0, "invite:" + nick)


func _on_requested(nick: String, _av: String) -> void:
	_refresh_pill()
	toast("%s хочет дружить" % nick, [["Принять", UI.GREEN, func(): _friend_act(nick, "accept")],
		["Нет", UI.RED, func(): _friend_act(nick, "decline")]], 20.0, "friend:" + nick)


# ================================================================ profile

func close_profile() -> void:
	if _profile != null and is_instance_valid(_profile):
		_profile.queue_free()
	_profile = null


## The profile of a player: the avatar, the nick, what they do, the record of the train, the awards
## and what can be done with them (friends, invite, chat, come into their room).
func show_profile(nick: String) -> void:
	close_profile()
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.set_meta("nick", nick)
	add_child(root)
	_profile = root
	var dim := ColorRect.new()
	dim.color = Color(0.05, 0.03, 0.02, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	dim.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed:
			close_profile())
	var center := FitCenter.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", WoodUI.window(34, 26))
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	v.custom_minimum_size = Vector2(560, 0)
	panel.add_child(v)
	var wait := WoodUI.label("Загрузка", 28, UI.CREAM, 6)
	wait.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(wait)
	var close := WoodUI.button("Закрыть", WoodUI.BACK, 24, Vector2(200, 56))
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(close_profile)
	v.add_child(close)
	var answer: Dictionary = await social.ask({"op": "s_profile", "nick": nick})
	if root != _profile or not is_instance_valid(root):
		return
	if answer.get("op") != "s_profile":
		wait.text = Social.reason(String(answer.get("r", "")))
		return
	wait.queue_free()
	var p: Dictionary = answer["p"]
	_fill_profile(v, p)
	v.move_child(close, v.get_child_count() - 1)


func _fill_profile(v: VBoxContainer, p: Dictionary) -> void:
	var nick := String(p.get("nick", ""))
	var av := String(p.get("av", ""))
	var st := String(p.get("st", "off"))
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 20)
	head.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(head)
	var face := AvatarView.make(nick, Avatar.cached(nick, av), 130, GOLD)
	head.add_child(face)
	if Avatar.cached(nick, av) == null and av != "":
		_face_later(face, nick, av)
	var names := VBoxContainer.new()
	names.add_theme_constant_override("separation", 4)
	names.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(names)
	var name_label := WoodUI.label(nick, 46, GOLD, 10)
	NickStyle.apply(name_label, p.get("rb") == true, String(p.get("col", "")))
	names.add_child(name_label)
	var tag := NickStyle.tag(String(p.get("tag", "")), 22)
	if tag != null:
		tag.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		names.add_child(tag)
	var on := st != "off"
	names.add_child(WoodUI.label(("В сети · " + Social.status_text(st)) if on else "Не в сети", 22, GREEN if on else UI.CREAM, 5, UI.UI_FONT))

	var bio := String(p.get("bio", ""))
	if bio != "":
		var about := WoodUI.label(bio, 22, Color.WHITE, 5, UI.UI_FONT)
		about.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		about.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		about.custom_minimum_size = Vector2(420, 0)
		v.add_child(about)
	v.add_child(facts(p))

	v.add_child(WoodUI.label("Награды", 26, GOLD, 6))
	v.add_child(awards(p))
	if social.admin:
		v.add_child(_admin_box(p))

	if nick == m.account.nick:
		return
	var fr := String(p.get("fr", ""))
	var row := HFlowContainer.new()
	row.alignment = FlowContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("h_separation", 10)
	row.add_theme_constant_override("v_separation", 10)
	v.add_child(row)
	_play_button(row, p, nick, st if on else "off", "Войти в игру", "Позвать в игру")
	match fr:
		"friend":
			if on:
				row.add_child(_small("Написать", UI.BLUE, func(): open_chat(nick)))
			row.add_child(_confirm_button("Удалить из друзей", "Точно удалить?", func(): _friend_act(nick, "remove")))
		"sent":
			var b := _small("Заявка отправлена", UI.PURPLE, func(): pass)
			b.disabled = true
			row.add_child(b)
			row.add_child(_small("Отменить", UI.RED, func(): _friend_act(nick, "decline")))
		"got":
			row.add_child(_small("Принять в друзья", UI.GREEN, func(): _friend_act(nick, "accept")))
			row.add_child(_small("Отклонить", UI.RED, func(): _friend_act(nick, "decline")))
		_:
			row.add_child(_small("Добавить в друзья", UI.GREEN, func(): _friend_act(nick, "add")))


## What an admin of the game may change in a profile: the colour of the nick, the tag, the rainbow.
## The server checks that the account is an admin; the new look reaches everybody online at once.
func _admin_box(p: Dictionary) -> Control:
	var nick := String(p.get("nick", ""))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.add_child(WoodUI.label("Админ", 26, RED, 6))
	var swatches := HFlowContainer.new()
	swatches.add_theme_constant_override("h_separation", 6)
	swatches.add_theme_constant_override("v_separation", 6)
	swatches.alignment = FlowContainer.ALIGNMENT_CENTER
	box.add_child(swatches)
	for col: String in NICK_COLORS:
		var b := Button.new()
		b.custom_minimum_size = Vector2(44, 44)
		b.tooltip_text = col
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color.html(col)
		sb.set_corner_radius_all(22)
		sb.set_border_width_all(3)
		sb.border_color = GOLD if String(p.get("col", "")) == col else Color(0, 0, 0, 0.6)
		for state in ["normal", "hover", "pressed", "focus"]:
			b.add_theme_stylebox_override(state, sb)
		b.pressed.connect(func(): _admin_set(nick, {"col": col, "rb": false}))
		swatches.add_child(b)
	var code_row := HBoxContainer.new()
	code_row.add_theme_constant_override("separation", 8)
	box.add_child(code_row)
	var code := LineEdit.new()
	code.placeholder_text = "Код цвета"
	code.max_length = 7
	code.text = String(p.get("col", ""))
	code.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	WoodUI.edit(code, 22)
	code_row.add_child(code)
	var set_code := func(_t = ""):
		var col := code.text.strip_edges().trim_prefix("#").to_lower()
		if NickStyle.is_color(col):
			_admin_set(nick, {"col": col, "rb": false})
		else:
			toast("Код из 6 знаков, например 541687", [], 4.0, "admin")
	code.text_submitted.connect(set_code)
	code_row.add_child(_small("Цвет", UI.BLUE, set_code))
	code_row.add_child(_small("Обычный", UI.PURPLE, func(): _admin_set(nick, {"col": "", "rb": false})))
	var rb: bool = p.get("rb") == true
	code_row.add_child(_small("Радуга выкл" if rb else "Радуга", UI.ORANGE, func(): _admin_set(nick, {"rb": not rb})))
	var tag_row := HBoxContainer.new()
	tag_row.add_theme_constant_override("separation", 8)
	box.add_child(tag_row)
	var tag := LineEdit.new()
	tag.placeholder_text = "Звание"
	tag.max_length = 24
	tag.text = String(p.get("tag", ""))
	tag.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	WoodUI.edit(tag, 22)
	tag_row.add_child(tag)
	var set_tag := func(_t = ""): _admin_set(nick, {"tag": tag.text.strip_edges()})
	tag.text_submitted.connect(set_tag)
	tag_row.add_child(_small("Дать", UI.GREEN, set_tag))
	tag_row.add_child(_small("Убрать", UI.RED, func(): _admin_set(nick, {"tag": ""})))
	return box


func _admin_set(nick: String, fields: Dictionary) -> void:
	var answer: Dictionary = await social.restyle(nick, fields)
	if answer.get("op") != "s_done":
		toast(Social.reason(String(answer.get("r", ""))), [], 4.0, "admin")
	# The profile is drawn anew by _on_styled when the server tells everybody.


## A nick looks another way now (an admin changed it): what shows it is drawn anew.
func _on_styled(nick: String, _style: Dictionary) -> void:
	if _profile != null and is_instance_valid(_profile) and String(_profile.get_meta("nick", "")) == nick:
		show_profile(nick)
	if not _shown:
		return
	if _tab != "chat":
		_refresh_at = 0
	elif _chat_log != null and is_instance_valid(_chat_log):
		for c in _chat_log.get_children():
			_chat_log.remove_child(c)
			c.queue_free()
		for msg: Dictionary in social.chats.get(_channel, []):
			_append(msg)


func _face_later(face: Control, nick: String, av: String) -> void:
	await Avatar.fetch(get_tree(), m.net.relay_url, [{"nick": nick, "av": av}])
	if is_instance_valid(face):
		face.set_texture(Avatar.cached(nick, av))


## A button that asks once more before it does what it does.
func _confirm_button(text: String, ask: String, on_yes: Callable) -> Button:
	var b := _small(text, UI.RED, func(): pass)
	var asked := {"at": -1}
	b.pressed.connect(func():
		var now := Time.get_ticks_msec()
		if asked["at"] >= 0 and now - int(asked["at"]) < 3000 and now - int(asked["at"]) > 300:
			on_yes.call()
			return
		asked["at"] = now
		b.text = ask
		get_tree().create_timer(3.0).timeout.connect(func():
			if is_instance_valid(b):
				b.text = text))
	return b


## The facts of a profile (an s_profile row) as a two-column table: the train, the time played, the
## games against people, the day of the account. Our own profile shows the same (profile_screen.gd).
static func facts(p: Dictionary) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 6)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var best := int(p.get("best", 0))
	var w := int(p.get("w", 0))
	var l := int(p.get("l", 0))
	for pair: Array in [["Ранг", Social.stage_name(int(p.get("rk", 0)))],
			["Рекорд поезда", "%d %s" % [best, _wagons(best)] if best > 0 else "нет"],
			["Наиграно", Social.play_text(int(p.get("pt", 0)))],
			["Игры с людьми", "%d %s · %d %s" % [w, _plural(w, "победа", "победы", "побед"), l, _plural(l, "поражение", "поражения", "поражений")]],
			["С нами с", _date(int(p.get("since", 0)))]]:
		grid.add_child(WoodUI.label(pair[0], 22, UI.CREAM, 5, UI.UI_FONT))
		grid.add_child(WoodUI.label(pair[1], 24, Color.WHITE, 6))
	return grid


## The awards of a profile: the tournament cups and medals on a shelf (AwardsShelf), the other
## awards as plates under it, or «Пока нет».
static func awards(p: Dictionary) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	var list: Array = p.get("aw", [])
	var shelf := AwardsShelf.make(list)
	if shelf != null:
		box.add_child(shelf)
	var flow := HFlowContainer.new()
	flow.alignment = FlowContainer.ALIGNMENT_CENTER
	flow.add_theme_constant_override("h_separation", 8)
	flow.add_theme_constant_override("v_separation", 8)
	if list.is_empty():
		flow.add_child(WoodUI.label("Пока нет", 22, Color(UI.CREAM, 0.7), 5, UI.UI_FONT))
	for a in list:
		if not AwardsShelf.parse(String(a)).is_empty():
			continue
		var plate := NickStyle.tag(String(a), 20)
		if plate != null:
			flow.add_child(plate)
	if flow.get_child_count() > 0:
		box.add_child(flow)
	return box


static func _plural(n: int, one: String, few: String, many: String) -> String:
	var d10 := n % 10
	var d100 := n % 100
	if d10 == 1 and d100 != 11:
		return one
	if d10 >= 2 and d10 <= 4 and (d100 < 12 or d100 > 14):
		return few
	return many


static func _wagons(n: int) -> String:
	var d10 := n % 10
	var d100 := n % 100
	if d10 == 1 and d100 != 11:
		return "вагон"
	if d10 >= 2 and d10 <= 4 and (d100 < 12 or d100 > 14):
		return "вагона"
	return "вагонов"


static func _date(unix: int) -> String:
	if unix <= 0:
		return "давно"
	var d := Time.get_date_dict_from_unix_time(unix)
	return "%02d.%02d.%d" % [d["day"], d["month"], d["year"]]