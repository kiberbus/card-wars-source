extends RefCounted
## Ranked games and the quick game (relay_server.gd «Ranked games», rank_store.gd): the rank window,
## the search for an opponent, the bans and the pick of a ranked match (in the online lobby, mode
## "rank"), the quick game window. The server keeps the rating, the queue and the bans; this only
## shows them. Its functions work on the main screen `m`, which keeps all the state.

const Main = preload("res://scripts/ui/main.gd")
const CardDB = preload("res://scripts/core/card_db.gd")
const UI = preload("res://scripts/ui/ui_kit.gd")
const WoodUI = preload("res://scripts/ui/wood_ui.gd")
const FitCenter = preload("res://scripts/ui/fit_center.gd")
const Phone = preload("res://scripts/ui/phone.gd")

const RANK_COLORS := [Color(0.85, 0.55, 0.32), Color(0.78, 0.82, 0.88), Color(1.0, 0.8, 0.3), Color(0.5, 0.88, 1.0)]
const GREY := Color(0.5, 0.5, 0.52)
const BANS := 2
const ALL_RANKS := "Игра со всеми рангами"
const ALL_RANKS_HINT := "Соперник найдётся быстрее, но может быть сильнее.
Победа над старшим рангом даёт больше очков, поражение отнимает меньше."
const DRAFT_COLS := 8
const DRAFT_COLS_PHONE := 11        # a phone: two rows, the whole draft on the screen without scrolling
const TILE := Vector2(96, 132)
const TILE_PHONE := Vector2(82, 113)  # a phone: 11 of them across the screen at the full scale

var m: Main
var _root: Control = null           # the rank window or the quick game window
var _rank_ui := {}                  # its labels: "name", "bar", "points", "record", "season", "find", "soon"
var _search: Control = null         # the search overlay
var _search_kind := ""              # "rank", or "q2" / "q3" / "q4" (the quick game of so many players)
var _search_t0 := 0
var _search_found := false          # quick game: the others wait for the host's room
# The bans and the pick of a ranked match (in the lobby window).
var _draft: VBoxContainer = null
var _head: Label = null
var _names: Label = null
var _clock: Label = null
var _grid: GridContainer = null
var _ready_btn: Button = null
var _tiles := {}                    # deck -> PanelContainer
var _phase := ""
var _sel: Array = []                # the decks marked now
var _until := 0                     # msec the phase ends here
var _ticking := false


func _init(main: Main) -> void:
	m = main


## Called once the social link exists (main.gd _ready).
func setup() -> void:
	m.social.matchmaking.connect(_on_matchmaking)
	m.social.changed.connect(func():
		if _search != null and not m.social.link_up:
			_close_search()
			m.social_ui.toast("Нет связи с сервером", [], 3.0))


static func stage_name(st: int) -> String:
	return Main.Social.stage_name(st)


static func stage_color(st: int) -> Color:
	return RANK_COLORS[clampi(st, 0, Main.Social.STAGES.size() - 1) / 3]


## «До сброса 23 д 4 ч».
static func left_text(sec: int) -> String:
	var d := sec / 86400
	var h := (sec % 86400) / 3600
	if d > 0:
		return "%d д %d ч" % [d, h]
	return "%d ч %d мин" % [h, maxi(1, (sec % 3600) / 60)]


# ================================================================ the rank window

func _need_account() -> bool:
	if m.account.logged_in() and m.social.link_up:
		return false
	var root: Control = m._message_overlay("Рейтинг", "Войди в аккаунт" if not m.account.logged_in() else "Нет связи с сервером")
	var b := WoodUI.button("Понятно", UI.PURPLE, 28, Vector2(240, 62))
	b.pressed.connect(func():
		m._close_overlay(root)
		m._back_to_play())
	root.get_meta("box").add_child(b)
	return true


func _window(title: String) -> VBoxContainer:
	var root: Control = m._overlay_root(Color(0.02, 0.01, 0.05, 0.75))
	_root = root
	var center := FitCenter.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", m._panel_box())
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 18)
	panel.add_child(v)
	v.add_child(m._title(title))
	return v


func _close_window() -> void:
	if _root != null and is_instance_valid(_root):
		m._close_overlay(_root)
	_root = null
	_rank_ui = {}


func _back_button(v: Control) -> void:
	var back := WoodUI.button("Назад", WoodUI.BACK, 28, Vector2(220, 62))
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back.pressed.connect(func():
		_close_window()
		m._back_to_play())
	v.add_child(back)


func show_rank() -> void:
	if _need_account():
		return
	var v := _window("Рейтинг")
	var name_l := WoodUI.label("…", 48, Color.WHITE, 10)
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(name_l)
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(520, 26) * WoodUI.font_scale
	bar.show_percentage = false
	bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.1, 0.07, 0.05, 0.8)
	bg.set_corner_radius_all(10)
	var fill := StyleBoxFlat.new()
	fill.bg_color = UI.GREEN
	fill.set_corner_radius_all(10)
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fill)
	v.add_child(bar)
	var pts := WoodUI.label("", 24, UI.CREAM, 5, UI.UI_FONT)
	pts.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(pts)
	var rec := WoodUI.label("", 24, UI.CREAM, 5, UI.UI_FONT)
	rec.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(rec)
	var season := WoodUI.label("", 24, Color(1, 0.85, 0.5), 5, UI.UI_FONT)
	season.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(season)

	var cols := HBoxContainer.new()
	cols.alignment = BoxContainer.ALIGNMENT_CENTER
	cols.add_theme_constant_override("separation", 30)
	v.add_child(cols)
	var ready_col := VBoxContainer.new()
	ready_col.add_theme_constant_override("separation", 10)
	cols.add_child(ready_col)
	var rl := WoodUI.label("Готовые колоды с героями", 26, Color.WHITE, 6, UI.UI_FONT)
	rl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ready_col.add_child(rl)
	var find := WoodUI.button("Найти соперника", UI.GREEN, 28, Vector2(340, 70))
	find.pressed.connect(_find_rank)
	ready_col.add_child(find)
	# «Игра со всеми рангами»: the server matches this one with any rank; a hint by a hover or a tap.
	var all_ranks: Button = m.lobby._check_button(ALL_RANKS, m._load_setting("rank", "all", false))
	all_ranks.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ready_col.add_child(all_ranks)
	var hint := WoodUI.label("", 20, Color(1, 0.85, 0.5), 5, UI.UI_FONT)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	all_ranks.toggled.connect(func(on: bool):
		m._save_setting("rank", "all", on)
		hint.text = ALL_RANKS_HINT)
	all_ranks.mouse_entered.connect(func(): hint.text = ALL_RANKS_HINT)
	all_ranks.mouse_exited.connect(func(): hint.text = "")
	var own_col := VBoxContainer.new()
	own_col.add_theme_constant_override("separation", 10)
	cols.add_child(own_col)
	var ol := WoodUI.label("Свои колоды", 26, Color.WHITE, 6, UI.UI_FONT)
	ol.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	own_col.add_child(ol)
	var soon_btn := WoodUI.button("Скоро", GREY, 28, Vector2(340, 70))
	own_col.add_child(soon_btn)
	var soon := WoodUI.label("", 22, Color(1, 0.85, 0.5), 5, UI.UI_FONT)
	soon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	soon.custom_minimum_size = Vector2(0, 34)
	v.add_child(soon)
	hint.custom_minimum_size = Vector2(0, 56)
	v.add_child(hint)
	v.move_child(hint, soon.get_index())
	if Phone.active:
		# A phone is low: the rank at the left, the buttons, the box and its hint at the right.
		v.add_theme_constant_override("separation", 10)
		bar.custom_minimum_size.x = 400.0
		name_l.label_settings.font_size = 40
		var split := HBoxContainer.new()
		split.add_theme_constant_override("separation", 30)
		split.alignment = BoxContainer.ALIGNMENT_CENTER
		v.add_child(split)
		v.move_child(split, name_l.get_index())
		var left := VBoxContainer.new()
		left.add_theme_constant_override("separation", 10)
		left.alignment = BoxContainer.ALIGNMENT_CENTER
		split.add_child(left)
		var right := VBoxContainer.new()
		right.add_theme_constant_override("separation", 6)
		split.add_child(right)
		for c: Control in [name_l, bar, pts, rec, season]:
			c.reparent(left, false)
		for c: Control in [cols, hint, soon]:
			c.reparent(right, false)
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.custom_minimum_size = Vector2(700, 84)
	soon_btn.pressed.connect(func(): soon.text = "Этот режим станет доступен в будущих обновлениях")
	_back_button(v)
	_rank_ui = {"name": name_l, "bar": bar, "points": pts, "record": rec, "season": season, "find": find}
	if not m.social.rank.is_empty():
		_fill_rank(m.social.rank)
	var answer: Dictionary = await m.social.ask({"op": "r_me"})
	if answer.get("op") == "r_me":
		_fill_rank(answer)


func _fill_rank(d: Dictionary) -> void:
	if _rank_ui.is_empty() or not is_instance_valid(_rank_ui["name"]):
		return
	var st := int(d.get("st", 0))
	_rank_ui["name"].text = stage_name(st)
	_rank_ui["name"].label_settings.font_color = stage_color(st)
	var need := int(d.get("need", 0))
	var have := int(d.get("in", 0))
	_rank_ui["bar"].max_value = maxi(need, 1)
	_rank_ui["bar"].value = have if need > 0 else 1
	_rank_ui["points"].text = "Очки: %d из %d" % [have, need] if need > 0 else "Очки: %d" % have
	_rank_ui["record"].text = "Побед %d · Поражений %d" % [int(d.get("w", 0)), int(d.get("l", 0))]
	_rank_ui["season"].text = "До сброса сезона: " + left_text(int(d.get("left", 0)))
	var code := String(d.get("code", ""))
	var find: Button = _rank_ui["find"]
	find.text = "Вернуться в матч" if code != "" else "Найти соперника"


func _find_rank() -> void:
	var answer: Dictionary = await m.social.ask({"op": "r_queue", "all": bool(m._load_setting("rank", "all", false))})
	if answer.get("r") == "busy" and String(answer.get("code", "")) != "":
		_enter_rank(String(answer["code"]))
		return
	if answer.get("op") != "s_done" or answer.get("r") != "":
		m.social_ui.toast("Не получилось встать в очередь", [], 3.0)
		return
	_show_search("rank")


# ================================================================ the quick game

func show_quick() -> void:
	if _need_account():
		return
	var v := _window("Быстрая игра")
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 20)
	v.add_child(row)
	for f: Array in [["1 на 1", 2, UI.GREEN], ["2 на 2", 4, UI.BLUE], ["На троих", 3, UI.ORANGE]]:
		var b := WoodUI.button(f[0], f[2], 30, Vector2(240, 80))
		b.pressed.connect(_find_quick.bind(f[1]))
		row.add_child(b)
	var note := WoodUI.label("Без рейтинга. Любые колоды, можно без героя", 22, UI.CREAM, 5, UI.UI_FONT)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(note)
	_back_button(v)


func _find_quick(n: int) -> void:
	var answer: Dictionary = await m.social.ask({"op": "q_queue", "n": n})
	if answer.get("op") != "s_done" or answer.get("r") != "":
		m.social_ui.toast("Не получилось встать в очередь", [], 3.0)
		return
	_show_search("q%d" % n)


# ================================================================ the search

func _show_search(kind: String) -> void:
	_close_search()
	_search_kind = kind
	_search_t0 = Time.get_ticks_msec()
	_search_found = false
	var title: String = "Рейтинг" if kind == "rank" else {"q2": "1 на 1", "q3": "На троих", "q4": "2 на 2"}[kind]
	var root: Control = m._message_overlay(title, "Ищем соперника\n0:00")
	_search = root
	var b := WoodUI.button("Отмена", UI.PURPLE, 28, Vector2(240, 62))
	b.pressed.connect(func():
		m.social.ask({"op": "r_cancel" if kind == "rank" else "q_cancel"})
		_close_search())
	root.get_meta("box").add_child(b)
	_search_tick(root)


func _search_tick(root: Control) -> void:
	while root == _search and is_instance_valid(root):
		var sec := (Time.get_ticks_msec() - _search_t0) / 1000
		var head := "Соперник найден\nЖдём комнату" if _search_found else "Ищем соперника"
		root.get_meta("text").text = "%s\n%d:%02d" % [head, sec / 60, sec % 60]
		await m.get_tree().create_timer(0.5).timeout


func _close_search() -> void:
	if _search != null and is_instance_valid(_search):
		m._close_overlay(_search)
	_search = null
	_search_kind = ""


func _on_matchmaking(d: Dictionary) -> void:
	match String(d.get("op", "")):
		"r_me":
			_fill_rank(d)
		"r_found":
			if _search_kind == "rank":
				_match_found()
				_enter_rank(String(d.get("code", "")))
		"q_found":
			if not _search_kind.begins_with("q"):
				return
			if not _search_found:
				_match_found()
			if d.get("host") == true and d.get("ticket") is String:
				_close_search()
				_close_window()
				m.lobby.show_net_lobby("room")
				m.lobby._net_host_room(int(d.get("n", 2)), String(d["ticket"]))
			else:
				_search_found = true
		"q_room":
			if _search_kind.begins_with("q") and d.get("code") is String:
				_close_search()
				_close_window()
				m.join_friend_room(String(d["code"]), String(d.get("pass", "")))
		"q_back":
			_search_found = false


## An opponent is found (a quick game or a ranked one, once per search): a bright chime (Sfx "found"),
## heard in the background too (the game never mutes itself there), and the taskbar button
## blinks while the window is not the active one. A sound volume of 0 keeps it quiet.
func _match_found() -> void:
	var sfx := m.get_node_or_null("/root/Sfx")
	if sfx != null:
		sfx.play("found")
	if not DisplayServer.window_is_focused():
		DisplayServer.window_request_attention()


## A ranked match is made (or we come back to ours): the lobby window shows its bans and picks.
func _enter_rank(code: String) -> void:
	if code == "" or m.board != null:
		return
	_close_search()
	_close_window()
	if m.net.mode != "":
		m.net.leave()
	if m._lobby_root != null:
		m.lobby._close_lobby()
	m.lobby.show_net_lobby("rank")
	var err: Error = m.net.join_room(code)
	if err != OK:
		m.lobby._set_lobby_status("Не удалось связаться с сервером", Color(1, 0.5, 0.45))


# ================================================================ bans and the pick

## The middle of the lobby window of a ranked match.
func draft_columns(cols: Control) -> void:
	_draft = VBoxContainer.new()
	_draft.add_theme_constant_override("separation", 10)
	cols.add_child(_draft)
	_names = WoodUI.label("", 26, Color.WHITE, 6, UI.UI_FONT)
	_names.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_draft.add_child(_names)
	var top := HBoxContainer.new()
	top.alignment = BoxContainer.ALIGNMENT_CENTER
	top.add_theme_constant_override("separation", 24)
	_draft.add_child(top)
	_head = WoodUI.label("Соперник найден", 32, Color(1, 0.85, 0.5), 7, UI.UI_FONT)
	top.add_child(_head)
	_clock = WoodUI.label("", 32, Color.WHITE, 7, UI.UI_FONT)
	top.add_child(_clock)
	_grid = GridContainer.new()
	_grid.columns = DRAFT_COLS_PHONE if Phone.active else DRAFT_COLS
	_grid.add_theme_constant_override("h_separation", 8)
	_grid.add_theme_constant_override("v_separation", 8)
	_grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_draft.add_child(_grid)
	_ready_btn = WoodUI.button("Готово", UI.GREEN, 28, Vector2(260, 62))
	_ready_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_ready_btn.pressed.connect(_send_choice)
	if Phone.active:
		# A phone: by the clock, never below the screen's edge.
		top.add_child(_ready_btn)
	else:
		_draft.add_child(_ready_btn)
	_tiles = {}
	_phase = ""
	_sel = []


func _mine() -> int:
	return 0 if m.net.is_host else 1


## The room server said how the match stands: the phase, the bans, who is ready.
func draft_update() -> void:
	var r: Dictionary = m.net.tour.get("rank", {})
	if r.is_empty() or _draft == null or not is_instance_valid(_draft):
		return
	var t: Dictionary = m.net.tour
	var me := _mine()
	_names.text = "%s против %s" % [String(t["names"][me]), String(t["names"][1 - me])]
	if _tiles.is_empty():
		for deck: String in r.get("decks", []):
			if CardDB.has_hero(deck) and CardDB.has_hero_card(deck):
				var tile := _deck_tile(deck)
				_grid.add_child(tile)
				_tiles[deck] = tile
	var phase := String(r.get("phase", ""))
	if phase != _phase:
		_phase = phase
		_sel = []
	_until = Time.get_ticks_msec() + int(r.get("left", 0)) * 1000
	var done: bool = r.get("done", [false, false])[me]
	var bans: Array = r.get("bans", [[], []])
	match phase:
		"ban":
			_head.text = "Запрети до %d колод" % BANS if not done else "Ждём соперника"
		"pick":
			_head.text = "Выбери колоду" if not done else "Ждём соперника"
		"play":
			_head.text = "%s против %s" % [_deck_name(String(t["heroes"][me])), _deck_name(String(t["heroes"][1 - me]))]
	if t.get("over", false):
		_head.text = "Матч окончен"
	_ready_btn.visible = phase != "play" and not done and not t.get("over", false)
	_ready_btn.text = "Без бана" if phase == "ban" and _sel.is_empty() else "Готово"
	_ready_btn.disabled = phase == "pick" and _sel.size() != 1
	for deck: String in _tiles:
		var banned_by := -1
		for s in 2:
			if bans.size() > s and bans[s].has(deck):
				banned_by = s
		_style_tile(_tiles[deck], deck, banned_by, phase, done)
	if phase != "play" and not _ticking:
		_tick()
	elif phase == "play":
		_clock.text = ""


func _tick() -> void:
	_ticking = true
	while _clock != null and is_instance_valid(_clock) and _phase != "play":
		var left := maxi(0, (_until - Time.get_ticks_msec() + 999) / 1000)
		_clock.text = "0:%02d" % mini(left, 99) if left < 100 else ""
		if left <= 2 and not _sel.is_empty():
			_send_late()
		await m.get_tree().create_timer(0.25).timeout
	_ticking = false


func _deck_name(deck: String) -> String:
	return CardDB.hero(CardDB.loadout_deck(deck))["name"] if CardDB.has_hero(CardDB.loadout_deck(deck)) else deck


func _deck_tile(deck: String) -> PanelContainer:
	var tile := PanelContainer.new()
	tile.mouse_filter = Control.MOUSE_FILTER_STOP
	tile.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.add_child(col)
	var tile_size := TILE_PHONE if Phone.active else TILE
	var pic: TextureRect = m._hero_card_rect(deck, tile_size)
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(pic)
	var name_l := WoodUI.text(CardDB.hero(deck)["name"], 17 if Phone.active else 15)
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_l.custom_minimum_size = Vector2(tile_size.x, 0)
	name_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(name_l)
	var mark := WoodUI.label("", 22, Color.WHITE, 6, UI.UI_FONT)
	mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mark.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tile.set_meta("mark", mark)
	pic.add_child(mark)
	mark.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tile.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and not e.pressed:
			_tap(deck))
	return tile


func _style_tile(tile: PanelContainer, deck: String, banned_by: int, phase: String, done: bool) -> void:
	var sb := WoodUI.card(WoodUI.PAPER, 0.0, tile.get_index())
	sb.radius = 10.0
	sb.line_width = 2.0
	var picked := _sel.has(deck)
	if picked:
		sb.line = UI.RED if phase == "ban" else UI.GREEN
		sb.line_width = 6.0
	sb.content_margin_left = 5
	sb.content_margin_right = 5
	sb.content_margin_top = 5
	sb.content_margin_bottom = 3
	tile.add_theme_stylebox_override("panel", sb)
	var mark: Label = tile.get_meta("mark")
	var t: Dictionary = m.net.tour
	var me := _mine()
	if banned_by >= 0:
		tile.modulate = Color(0.45, 0.45, 0.45)
		mark.text = "Бан"
		mark.label_settings.font_color = Color(1, 0.45, 0.4)
	else:
		tile.modulate = Color.WHITE
		mark.text = ""
		if phase == "play" and t.get("heroes") is Array:
			if String(t["heroes"][me]) == deck:
				mark.text = "Ты"
				mark.label_settings.font_color = Color(0.6, 1.0, 0.65)
			elif String(t["heroes"][1 - me]) == deck:
				mark.text = "Соперник"
				mark.label_settings.font_color = Color(1, 0.85, 0.5)
		elif picked and phase == "ban":
			mark.text = "Бан"
			mark.label_settings.font_color = Color(1, 0.45, 0.4)
	tile.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if not done and banned_by < 0 and phase != "play" \
		else Control.CURSOR_ARROW


func _tap(deck: String) -> void:
	var r: Dictionary = m.net.tour.get("rank", {})
	if r.is_empty() or r.get("done", [false, false])[_mine()] or m.net.tour.get("over", false):
		return
	var phase := String(r.get("phase", ""))
	if phase == "ban":
		if _sel.has(deck):
			_sel.erase(deck)
		elif _sel.size() < BANS:
			_sel.append(deck)
		else:
			return
	elif phase == "pick":
		var bans: Array = r.get("bans", [[], []])
		if bans.any(func(b): return b.has(deck)):
			return
		_sel = [deck]
	else:
		return
	UI.sfx("click")
	draft_update()


## The time is nearly over and the player marked decks but did not press «Готово»: send them,
## or the server bans nothing and picks a random deck.
func _send_late() -> void:
	var r: Dictionary = m.net.tour.get("rank", {})
	if r.is_empty() or r.get("done", [false, false])[_mine()] or m.net.tour.get("over", false):
		return
	if _ready_btn == null or not is_instance_valid(_ready_btn) or not _ready_btn.visible:
		return
	_send_choice()


func _send_choice() -> void:
	var r: Dictionary = m.net.tour.get("rank", {})
	match String(r.get("phase", "")):
		"ban":
			m.net.rank_ban(_sel.duplicate())
		"pick":
			if _sel.size() != 1:
				return
			m.net.rank_pick(String(_sel[0]))
		_:
			return
	_ready_btn.visible = false
	_head.text = "Ждём соперника"


## Under the buttons at the end of a ranked game: the points it brought, or why none.
func result_text() -> String:
	var t: Dictionary = m.net.tour
	var r: Dictionary = t.get("rank", {})
	if not t.get("over", false):
		return "Ждём итог соперника"
	if String(t.get("dispute", "")) != "":
		return "Итоги не совпали, очки не изменились"
	var me := _mine()
	var delta := int(r.get("delta", [0, 0])[me])
	var st := int(r.get("st", [0, 0])[me])
	return "%s%d · %s" % ["+" if delta >= 0 else "", delta, stage_name(st)]
