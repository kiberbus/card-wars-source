extends RefCounted
## The leaderboard of the ranked games: «Лидерборд» in the rank window (ranked.gd). Every player with more
## than one ranked game this season, by place: the mark of the place (a gold crown, a silver «2», a
## bronze «3», then the number), the avatar, the nick, the stage and the points of the season; our own
## row is lit, and pinned under the list when it is not in it.
## The server keeps the table (relay_server.gd «Ranked games», rank_store.gd):
##   -> {"op": "r_top", "n": 100}
##   <- {"op": "r_top", "players": [{"nick", "av", "st", "pts", "w", "l", "rb", "col"}, ...],
##       "me": {the same row, "place"} (absent when we have not played two games)}
## "st" is the stage (Social.STAGES), "pts" all the points of the season (what moves a player up the
## stages), "w"/"l" the ranked wins and losses of the season. A server without r_top does not answer:
## the window says the table comes with an update of the server.

const Main = preload("res://scripts/ui/main.gd")
const UI = preload("res://scripts/ui/ui_kit.gd")
const WoodUI = preload("res://scripts/ui/wood_ui.gd")
const FitCenter = preload("res://scripts/ui/fit_center.gd")
const Phone = preload("res://scripts/ui/phone.gd")
const Avatar = preload("res://scripts/net/avatar.gd")
const AvatarView = preload("res://scripts/ui/avatar_view.gd")
const NickStyle = preload("res://scripts/ui/nick_style.gd")
const PlaceBadge = preload("res://scripts/ui/place_badge.gd")

const ASK := {"op": "r_top", "n": 100}
const MIN_GAMES := 2                 # «more than one game»
const WIDTH := 820.0
const LIST_H := 560.0
const RANK_COLORS := [Color(0.85, 0.55, 0.32), Color(0.78, 0.82, 0.88), Color(1.0, 0.8, 0.3), Color(0.5, 0.88, 1.0)]
## The tint of the rows of the first three places (gold, silver, bronze) and of our own row.
const PODIUM := [Color(0.55, 0.42, 0.08), Color(0.36, 0.4, 0.46), Color(0.46, 0.27, 0.12)]
const MINE := Color(0.2, 0.42, 0.24)
const NO_SERVER := "Лидерборд заработает после обновления сервера"

var m: Main
var _root: Control = null
var _list: VBoxContainer = null
var _note: Label = null
var _pinned: Control = null
var _loading := false                # a request of the table is on its way


func _init(main: Main) -> void:
	m = main


# ================================================================ the table

## A row of the server as the window takes it: the fields typed, the games counted.
static func row(d: Dictionary) -> Dictionary:
	var w := maxi(0, int(d.get("w", 0)))
	var l := maxi(0, int(d.get("l", 0)))
	return {"nick": String(d.get("nick", "")), "av": String(d.get("av", "")), "st": maxi(0, int(d.get("st", 0))),
		"pts": maxi(0, int(d.get("pts", 0))), "w": w, "l": l, "games": w + l, "rb": d.get("rb") == true,
		"col": String(d.get("col", ""))}


## Whether a is above b: the higher stage, then more points, more wins, fewer losses, then the nick.
static func above(a: Dictionary, b: Dictionary) -> bool:
	if a["st"] != b["st"]:
		return a["st"] > b["st"]
	if a["pts"] != b["pts"]:
		return a["pts"] > b["pts"]
	if a["w"] != b["w"]:
		return a["w"] > b["w"]
	if a["l"] != b["l"]:
		return a["l"] < b["l"]
	return a["nick"].to_lower() < b["nick"].to_lower()


## The answer of r_top as the rows of the table: only those with more than one game, each nick once,
## sorted, with their places ("place" from 1). The server sorts too; this keeps the window right with
## any server.
static func table(answer: Dictionary) -> Array:
	var rows: Array = []
	var seen := {}
	for d in answer.get("players", []):
		if not d is Dictionary:
			continue
		var r := row(d)
		if r["nick"] == "" or r["games"] < MIN_GAMES or seen.has(r["nick"]):
			continue
		seen[r["nick"]] = true
		rows.append(r)
	rows.sort_custom(above)
	for i in rows.size():
		rows[i]["place"] = i + 1
	return rows


## Our row: from the table when we are in it, else the "me" of the answer (with its place), else {}.
static func my_row(answer: Dictionary, rows: Array, nick: String) -> Dictionary:
	for r: Dictionary in rows:
		if r["nick"] == nick:
			return r
	var me = answer.get("me")
	if me is Dictionary and String(me.get("nick", "")) == nick and nick != "":
		var r := row(me)
		if r["games"] < MIN_GAMES:
			return {}
		r["place"] = maxi(1, int(me.get("place", 0)))
		return r
	return {}


static func stage_color(st: int) -> Color:
	return RANK_COLORS[clampi(st, 0, Main.Social.STAGES.size() - 1) / 3]


## «1 234» — the points with a thin gap between thousands.
static func points_text(n: int) -> String:
	var s := str(n)
	var out := ""
	while s.length() > 3:
		out = " " + s.right(3) + out
		s = s.left(s.length() - 3)
	return s + out


# ================================================================ the window

func show() -> void:
	var root: Control = m._overlay_root(Color(0.02, 0.01, 0.05, 0.75))
	_root = root
	var center := FitCenter.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", m._panel_box())
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	panel.add_child(v)
	v.add_child(m._title("Лидерборд"))
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(WIDTH, 380.0 if Phone.active else LIST_H) * WoodUI.font_scale
	v.add_child(scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 8)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	_note = WoodUI.label("Загрузка", 26, UI.CREAM, 6, UI.UI_FONT)
	_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note.custom_minimum_size = Vector2(WIDTH * WoodUI.font_scale - 40.0, 0)
	_list.add_child(_note)
	_pinned = VBoxContainer.new()
	v.add_child(_pinned)
	# «Обновить» asks the server again, as in the table of the day (daily_screen.gd).
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 20)
	v.add_child(buttons)
	var again := WoodUI.button("Обновить", UI.GREEN, 28, Vector2(220, 62))
	again.pressed.connect(refresh)
	buttons.add_child(again)
	var back := WoodUI.button("Назад", WoodUI.BACK, 28, Vector2(220, 62))
	back.pressed.connect(close)
	buttons.add_child(back)
	refresh()


## Asks the server for the table and draws it (once at a time: a second press waits for the answer).
func refresh() -> void:
	var root := _root
	if _loading or root == null or not is_instance_valid(root):
		return
	_loading = true
	if _list.get_child_count() <= 1:
		_note.text = "Загрузка"
		_note.visible = true
	var answer: Dictionary = await m.social.ask(ASK)
	_loading = false
	if root == _root and is_instance_valid(root):
		fill(answer)


func close() -> void:
	if _root != null and is_instance_valid(_root):
		m._close_overlay(_root)
	_root = null
	_list = null


## Draws the answer of the server (or of a test) in the open window.
func fill(answer: Dictionary) -> void:
	if _list == null or not is_instance_valid(_list):
		return
	for ch in _list.get_children():
		if ch != _note:
			ch.queue_free()
	for ch in _pinned.get_children():
		ch.queue_free()
	if answer.get("op") != "r_top":
		var r := String(answer.get("r", ""))
		# No answer from a server that is up: it does not know r_top yet.
		_note.text = NO_SERVER if r == "timeout" and m.social.link_up else Main.Social.reason(r)
		_note.visible = true
		return
	var nick: String = m.account.nick
	var rows := table(answer)
	_note.visible = rows.is_empty()
	_note.text = "Пока никто не сыграл больше одной игры в рейтинге"
	for r: Dictionary in rows:
		_list.add_child(_row(r, r["nick"] == nick))
	var me := my_row(answer, rows, nick)
	if not me.is_empty() and not rows.has(me):
		_pinned.add_child(_row(me, true))
	_fetch_avatars(rows + ([me] if not me.is_empty() else []))


func _row(r: Dictionary, mine: bool) -> Control:
	var place: int = r["place"]
	var podium := place <= 3
	var panel := PanelContainer.new()
	var sb := WoodUI.inset(place * 7, 12, 4)
	if podium:
		sb.fill = PODIUM[place - 1]
	if mine:
		sb.fill = MINE if not podium else sb.fill
		sb.line = Color(0.6, 1.0, 0.65)
		sb.line_width = 4.0
	panel.add_theme_stylebox_override("panel", sb)
	panel.set_meta("nick", r["nick"])
	panel.set_meta("av", r["av"])
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	panel.add_child(h)
	var badge := PlaceBadge.make(place, (48.0 if podium else 40.0) * WoodUI.font_scale)
	badge.custom_minimum_size.x = 56.0 * WoodUI.font_scale         # the avatars of all rows in one column
	h.add_child(badge)
	var face := AvatarView.make(r["nick"], Avatar.cached(r["nick"], r["av"]), roundi(50.0 * WoodUI.font_scale),
		Color(1, 1, 1, 0.85) if not podium else PlaceBadge.METALS[place - 1][1])
	face.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	panel.set_meta("face", face)
	h.add_child(face)
	var name_l := WoodUI.label(r["nick"], 26, Color.WHITE, 6)
	name_l.clip_text = true
	name_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	NickStyle.apply(name_l, r["rb"], r["col"])
	h.add_child(name_l)
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", -2)
	right.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(right)
	var stage := WoodUI.label(Main.Social.stage_name(r["st"]), 22, stage_color(r["st"]), 6)
	stage.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_child(stage)
	var games := WoodUI.label("%d · %d" % [r["w"], r["l"]], 18, UI.CREAM, 4, UI.UI_FONT)
	games.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	games.tooltip_text = "Побед · Поражений"
	games.mouse_filter = Control.MOUSE_FILTER_PASS
	right.add_child(games)
	var pts := WoodUI.label(points_text(r["pts"]), 28 if podium else 26,
		PlaceBadge.METALS[place - 1][0] if podium else Color.WHITE, 7)
	pts.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	pts.custom_minimum_size = Vector2(120, 0) * WoodUI.font_scale
	pts.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(pts)
	var unit := WoodUI.label("очк.", 18, UI.CREAM, 4, UI.UI_FONT)
	unit.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(unit)
	return panel


## Avatars that are not on this PC yet: the rows get them when they come.
func _fetch_avatars(rows: Array) -> void:
	await Avatar.fetch(m.get_tree(), m.net.relay_url, rows)
	if _list == null or not is_instance_valid(_list):
		return
	for box: Control in [_list, _pinned]:
		for p in box.get_children():
			if p.has_meta("face"):
				var face = p.get_meta("face")
				if face != null and is_instance_valid(face) and face.has_method("set_texture"):
					face.set_texture(Avatar.cached(String(p.get_meta("nick")), String(p.get_meta("av"))))
