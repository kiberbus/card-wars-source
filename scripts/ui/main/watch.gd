extends RefCounted
## «Наблюдать» from the main screen (main.gd): a watcher of an online match, by its watch code
## (the host's lobby shows it, a tournament's bot gives it). The host's game comes through Net
## (scripts/net/net.gd, relay_server.gd «Spectators»): its head, then its journal as it grows.
## The table plays it as a replay that keeps waiting for the next steps (board.gd live_replay):
## both hands open, «Смотреть за» changes sides at any time. A watcher who comes in the middle
## of a match gets the game played up to the last steps at once, then watches from there.

const Main = preload("res://scripts/ui/main.gd")
const CardDB = preload("res://scripts/core/card_db.gd")
const Replay = preload("res://scripts/core/replay.gd")
const UI = preload("res://scripts/ui/ui_kit.gd")
const WoodUI = preload("res://scripts/ui/wood_ui.gd")
const FitCenter = preload("res://scripts/ui/fit_center.gd")
## The first steps of a game come in a few messages right after its head: the table is set this much later.
const CATCH_UP_SEC := 0.5

var m: Main
var active := false             # watching (or connecting to watch)
var data = null                 # the game watched: a replay whose "steps" keep growing
var g := 0                      # its id from the host
var view := 0                   # the side the table shows, kept from game to game
var _root: Control = null       # the window with the code
var _status: Label = null
var _edit: LineEdit = null
var _end_root: Control = null   # the game is over
var _link_root: Control = null  # the link to the server is lost
var _switching := false         # main's _end_game while the next game is set: watching goes on
var _retry_token := 0


func _init(main: Main) -> void:
	m = main


## The window: the watch code and «Смотреть».
func show_watch() -> void:
	if _root != null:
		return
	m._close_play_menu()
	var root := m._overlay_root(Color(0.03, 0.02, 0.07, 0.8))
	_root = root
	var center := FitCenter.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", m._panel_box())
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	panel.add_child(v)
	v.add_child(m._title("Наблюдать"))
	v.add_child(WoodUI.label("Код наблюдателя:", 24, UI.CREAM, 5, UI.UI_FONT))
	var edit := LineEdit.new()
	_edit = edit
	edit.placeholder_text = "ABCDEF"
	edit.max_length = 8
	edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	edit.custom_minimum_size = Vector2(440, 64)
	edit.add_theme_font_size_override("font_size", 34)
	v.add_child(edit)
	var go := WoodUI.button("Смотреть", UI.GREEN, 28, Vector2(440, 66))
	go.pressed.connect(func(): _start(edit.text))
	edit.text_submitted.connect(func(txt): _start(txt))
	v.add_child(go)
	_status = WoodUI.label("", 24, Color.WHITE, 6, UI.UI_FONT)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.custom_minimum_size = Vector2(0, 70)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_status)
	var back := WoodUI.button("Назад", UI.PURPLE, 26, Vector2(220, 58))
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back.pressed.connect(func():
		stop()
		_close_window()
		m._back_to_play())
	v.add_child(back)
	m._pop_in(v)
	edit.grab_focus.call_deferred()


func _close_window() -> void:
	if _root != null:
		m._close_overlay(_root)
	_root = null
	_status = null
	_edit = null


func _set_status(text: String, color := Color.WHITE) -> void:
	if _status != null and is_instance_valid(_status):
		_status.text = text
		_status.label_settings.font_color = color


## The window with this code already in it, connecting (a friend's match, the eye on their row).
func watch_code(code: String) -> void:
	show_watch()
	if _edit != null and is_instance_valid(_edit):
		_edit.text = code
	_start(code)


func _start(text: String) -> void:
	var code := text.strip_edges().to_upper()
	if code.length() < 4:
		_set_status("Введи код наблюдателя", Color(1, 0.5, 0.45))
		return
	var err: Error = m.net.watch(code)
	if err != OK:
		_set_status("Нет связи с сервером, ошибка %d" % err, Color(1, 0.5, 0.45))
		return
	active = true
	data = null
	g = 0
	_set_status("Подключаемся…")


## Stops watching (leaving the table or the window).
func stop() -> void:
	if not active:
		return
	active = false
	_retry_token += 1
	data = null
	g = 0
	m.net.close()
	_close_link()
	if _end_root != null and is_instance_valid(_end_root):
		m._close_overlay(_end_root)
	_end_root = null


## main._end_game: the table goes. Watching goes on only while the next game is being set.
func on_end_game() -> void:
	if not _switching:
		stop()


func on_ready() -> void:
	_close_link()
	if data == null:
		_set_status("Ждём начала партии…", Color(0.6, 1.0, 0.65))


## The host's new game: its head. The same game again (after a lost link) is kept.
func on_head(new_g: int, head: Dictionary) -> void:
	if not active or (new_g == g and data != null):
		return
	if int(head.get("rules", -1)) != Replay.RULES:
		_set_status("У игроков другая версия игры", Color(1, 0.5, 0.45))
		return
	var heroes = head.get("heroes")
	if not (heroes is Array) or heroes.size() != 2 or not heroes.all(func(h): return h is String and CardDB.valid_loadout(h)) \
			or not (head.get("seed") is int and head.get("first") is int):
		return
	var d := head.duplicate(true)
	d["steps"] = []
	data = d
	g = new_g
	await m.get_tree().create_timer(CATCH_UP_SEC).timeout
	if data == d and active:
		_begin(d)


## Steps of the host's journal from place `at` on; none: the journal was cut there (an undo).
func on_steps(from_g: int, at: int, steps: Array) -> void:
	if not active or data == null or from_g != g:
		return
	var have: Array = data["steps"]
	if at < 0 or at > have.size() or not steps.all(func(st): return st is Dictionary):
		return
	var cut := -1
	if steps.is_empty():
		cut = at if at < have.size() else -1
	else:
		# Steps the table already has come again after a lost link: only the new ones count.
		for i in steps.size():
			if at + i >= have.size():
				break
			if have[at + i] != steps[i]:
				cut = at + i
				break
	var board = m.board
	var played: int = board.replay_pos() if board != null and board.replay_steps == have else 0
	if cut >= 0:
		have.resize(cut)
	for i in steps.size():
		if at + i >= have.size():
			have.append(steps[i])
	if cut >= 0 and cut < played and board != null:
		board.seek_replay(cut)      # a step on the table was taken back: the game is set again from there


## The table: the game played up to its last whole step at once, then live from there.
func _begin(d: Dictionary) -> void:
	var steps: Array = d["steps"]
	var pos := steps.size() - 1
	while pos > 0 and steps[pos].get("t") == "pick":
		pos -= 1        # a step and the choices it asked: the last one may wait for more of them
	pos = maxi(pos, 0)
	var game = await Replay.play_to(d, pos)
	if data != d or not active:
		return
	_close_window()
	if _end_root != null and is_instance_valid(_end_root):
		m._close_overlay(_end_root)
	_end_root = null
	_switching = true
	m._end_game()
	_switching = false
	m._clear_title()
	m._replay = d
	m._mode = ""
	m.seat = -1
	m.game = game
	m._new_board()
	view = clampi(view, 0, game.players.size() - 1)
	var own = d.get("own")      # a friend's ranked match (friend_cast.gd): their hand only
	if own is float:
		own = int(own)
	var own_seat: int = own if own is int and own >= 0 and own < game.players.size() else -1
	if own_seat >= 0:
		view = own_seat
	m.board.enable_replay(steps, view, pos)
	if own_seat >= 0:
		m.board.replay_own = own_seat
		m.board.sync()
	m.board.live_replay = true
	m.board.replay_ended.connect(_on_ended)
	m.board.replay_seek.connect(_on_seek)
	m.board._update_hud()
	m.board.start_replay()


## A step taken back: the game is set again at `pos` steps, the table goes on from there.
func _on_seek(pos: int) -> void:
	var d = data
	var board = m.board
	var game = await Replay.play_to(d, pos)
	if data != d or m.board != board or board == null:
		return
	m.game = game
	board.replace_game(game, pos)
	board.start_replay()


## The game watched is over (or stopped matching the host's): the result, and the next game
## of the room comes by itself.
func _on_ended(reason: String) -> void:
	if m.board != null:
		view = m.board.viewer
	await m.get_tree().create_timer(0.8).timeout
	if m.game == null or m.board == null or m._replay != data:
		return
	var title := "Партия окончена"
	var text := "Запись разошлась с этой версией игры."
	if reason == "broken":
		pass
	elif m.game.phase == "over":
		text = "Победил %s." % m.game.players[m.game.winner].name if m.game.winner >= 0 else "Ничья."
	else:
		title = "Матч закрыт"
		text = "Игрок вышел из комнаты."
	var root := m._message_overlay(title, text)
	_end_root = root
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	root.get_meta("box").add_child(row)
	if active:
		var stay := WoodUI.button("Ждать реванш", UI.GREEN, 28, Vector2(300, 68))
		stay.pressed.connect(func():
			m._close_overlay(root)
			_end_root = null)
		row.add_child(stay)
	var menu := WoodUI.button("Главное меню", UI.PURPLE, 28, Vector2(260, 68))
	menu.pressed.connect(func():
		m._close_overlay(root)
		m._end_game()
		m.show_title())
	row.add_child(menu)


## Net's link is gone: "server_left" / "failed" (we try again), or for good.
func on_disconnected(reason: String) -> void:
	var red := Color(1, 0.5, 0.45)
	if reason == "server_left" or (reason == "failed" and m.net.can_rejoin() and data != null):
		_show_link()
		_retry(_retry_token)
		return
	var text := ""
	match reason:
		"no_room":
			text = "Матча с таким кодом нет"
		"version":
			text = "У игроков другая версия игры"
		"full":
			text = "У матча уже много зрителей"
		"closed":
			text = "Матч закрыт"
		"failed":
			text = "Нет связи с сервером"
		_:
			text = "Связь потеряна"
	active = false
	_close_link()
	if _root != null:
		data = null
		_set_status(text, red)
		return
	if m.board == null:
		data = null
		return
	if reason == "closed" and m.board.live_replay:
		# The room is gone (the host left): what came is played to its end, then _on_ended says so.
		m.board.live_replay = false
		if not m.board._replay_running:
			_on_ended("")
		return
	data = null
	var root := m._message_overlay("Наблюдение окончено", text)
	var b := WoodUI.button("Главное меню", UI.PURPLE, 28, Vector2(300, 68))
	b.pressed.connect(func():
		m._close_overlay(root)
		m._end_game()
		m.show_title())
	root.get_meta("box").add_child(b)


## Tries again every few seconds till the link is back or watching stops.
func _retry(token: int) -> void:
	while token == _retry_token and active and not m.net.link_up():
		if m.net.can_rejoin():
			m.net.rejoin()
		await m.get_tree().create_timer(2.5).timeout


func _show_link() -> void:
	if _root != null:
		_set_status("Переподключаемся…", Color(1, 0.85, 0.5))
		return
	if _link_root != null and is_instance_valid(_link_root):
		return
	var root := m._message_overlay("Связь потеряна", "Переподключаемся…")
	_link_root = root
	var b := WoodUI.button("Главное меню", UI.PURPLE, 28, Vector2(300, 68))
	b.pressed.connect(func():
		m._end_game()
		m.show_title())
	root.get_meta("box").add_child(b)


func _close_link() -> void:
	if _link_root != null and is_instance_valid(_link_root):
		m._close_overlay(_link_root)
	_link_root = null
