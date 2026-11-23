extends SceneTree
## The phone layout (docs/MOBILE_UI.md): every screen and every table, screenshots and checks.
## On a phone: nothing leaves the safe part of the screen (a cutout and a gesture bar are
## faked at the edges), every visible button is at least Phone.TOUCH_PART of the screen height
## on both sides, every text at least Phone.FONT_MIN units. With `pc` the same screens are shot
## in the PC layout (only the out-of-screen check), to see that the PC did not change.
##   godot --path . --resolution 2400x1080 -s res://tests/phone_ui.gd -- <output_dir> [phone|pc] [only]
## `only`: comma separated parts to run: menus, select, builder, train, online, sandbox, game, tables.
## Exit code 1 when a check fails; every problem is printed with the screen's name.

const MainScene := preload("res://scenes/main.tscn")
const CardDB = preload("res://scripts/core/card_db.gd")
const WoodUI = preload("res://scripts/ui/wood_ui.gd")
const Phone = preload("res://scripts/ui/phone.gd")

var out_dir := "user://shots_phone"
var phone := true
var only: Array = []
var main
var fails := 0
var shots := 0
var problems := {}


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	if args.size() > 1:
		phone = args[1] != "pc"
	if args.size() > 2:
		only = Array(args[2].split(","))
	DirAccess.make_dir_recursive_absolute(out_dir)
	DisplayServer.window_set_mouse_passthrough(PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(0, 1)]))
	if phone:
		# A camera cutout at the left edge and a gesture bar at the bottom, as a phone held sideways.
		var w := DisplayServer.window_get_size()
		Phone.fake_insets = Vector4(roundf(w.x * 0.035), 0.0, 0.0, roundf(w.y * 0.03))
	main = MainScene.instantiate()
	main.phone_layout = phone
	root.add_child(main)
	_run()


func _part(name: String) -> bool:
	return only.is_empty() or only.has(name)


func _wait(t: float) -> void:
	await create_timer(t).timeout


func _idle() -> void:
	for i in 400:
		await process_frame
		if main.board == null or (not main.board._busy and main.board._choice == null):
			break
	await _wait(0.3)


## The rect of a control in window pixels.
func _px(c: Control) -> Rect2:
	var t := c.get_global_transform_with_canvas()
	var r := Rect2(t.origin, c.size * t.get_scale()).abs()
	var k := root.get_final_transform()
	return Rect2(k * r.position, r.size * k.get_scale())


## Inside a window taller than the phone, that scrolls (FitCenter): the finger brings it in.
func _in_tall_window(c: Node) -> bool:
	var p := c.get_parent()
	while p != null and p != main:
		if p.has_method("can_scroll") and p.can_scroll():
			return true
		p = p.get_parent()
	return false


func _scroll_of(c: Node) -> ScrollContainer:
	var p := c.get_parent()
	while p != null and p != main:
		if p is ScrollContainer:
			return p
		p = p.get_parent()
	return null


func _font_px(c: Control) -> float:
	var size := 0
	if c is Label and c.label_settings != null:
		size = c.label_settings.font_size
	else:
		size = c.get_theme_font_size("font_size")
	var t := c.get_global_transform_with_canvas()
	return size * t.get_scale().y * root.get_final_transform().get_scale().y


func _hidden_by_parent(c: Control) -> bool:
	var p := c.get_parent()
	while p != null and p != main:
		if p is CanvasItem and p.modulate.a < 0.05:
			return true
		if p is CanvasLayer and not p.visible:
			return true
		p = p.get_parent()
	return c.modulate.a < 0.05


## Screenshot, then the checks. `extra` controls are checked as touch targets too.
func _check(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	shots += 1
	root.get_texture().get_image().save_png("%s/%02d_%s.png" % [out_dir, shots, name])
	var win := Rect2(Vector2.ZERO, Vector2(DisplayServer.window_get_size()))
	var safe := (Phone.safe_window_rect() if phone else win).grow(2.0)
	var touch := Phone.touch_px()
	var font_min := Phone.FONT_MIN * Phone.SCALE * win.size.y / 1080.0 - 0.5
	var bad := []
	# A window over the screen: only it and the friends panel are in reach of the finger.
	var scope: Array = [main]
	for r in main.overlay.get_children():
		if r is CanvasItem and r.visible:
			scope = [main.overlay, main.social_ui]
	var all: Array = []
	for top: Node in scope:
		all.append_array(top.find_children("*", "Control", true, false))
	for c: Node in all:
		if not (c is Button or c is Label or c is LineEdit) or not c.is_visible_in_tree() or _hidden_by_parent(c):
			continue
		if c.name == "Title" or c.get_meta("phone_skip", false):
			continue
		if main.board != null and c == main.board.banner:
			continue
		var r := _px(c)
		if r.size.x < 2.0 or r.size.y < 2.0:
			continue
		var sc := _scroll_of(c)
		if sc != null:
			var sr := _px(sc)
			if not sr.intersects(r):
				continue             # scrolled away
			r = r.intersection(sr) if c is Button else r
		elif r.size.x < win.size.x - 8.0 or r.size.y < win.size.y - 8.0:
			if not safe.encloses(r) and not _in_tall_window(c):
				bad.append("out  %s «%s» %s" % [c.get_class(), _txt(c), r])
		if not phone:
			continue
		if c is Button and not c.get_meta("phone_small", false):
			if (r.size.x < touch or r.size.y < touch) and (sc == null or _px(c).size.y < touch or _px(c).size.x < touch):
				bad.append("small %s «%s» %dx%d < %d" % [c.get_class(), _txt(c), r.size.x, r.size.y, touch])
		# The table (a fixed 1920x1080 stage) keeps its own least font: board.gd P_FONT.
		var fmin := font_min
		if main.stage.is_ancestor_of(c):
			fmin = 24.0 * win.size.y / 1080.0 * 0.94
		if (c is Label or c is Button or c is LineEdit) and _txt(c) != "" and _font_px(c) < fmin:
			bad.append("font %s «%s» %d < %d" % [c.get_class(), _txt(c), _font_px(c), fmin])
	if main.board != null and phone:
		bad.append_array(_board_checks(touch))
	if phone:
		bad.append_array(await _scroll_checks(scope))
	if bad.is_empty():
		print("OK   ", name)
	else:
		fails += 1
		problems[name] = bad
		print("FAIL %s: %d" % [name, bad.size()])
		for b in bad.slice(0, 12):
			print("       ", b)


## A finger on the screen (window pixels), as a phone sends it: touches and drags; Godot makes
## the left button of them, TouchInput the scrolling.
func _finger(from: Vector2, to: Vector2, steps := 8) -> void:
	var t := InputEventScreenTouch.new()
	t.index = 0
	t.position = from
	t.pressed = true
	Input.parse_input_event(t)
	await process_frame
	for i in range(1, steps + 1):
		var d := InputEventScreenDrag.new()
		d.index = 0
		d.position = from.lerp(to, float(i) / steps)
		d.relative = (to - from) / steps
		Input.parse_input_event(d)
		await process_frame
	var u := InputEventScreenTouch.new()
	u.index = 0
	u.position = to
	u.pressed = false
	Input.parse_input_event(u)
	await process_frame
	await process_frame


## A tap of a finger on the middle of a control.
func _finger_tap(c: Control) -> void:
	var at := _px(c).get_center()
	await _finger(at, at, 0)


## Every window taller than the screen and every list with more than it shows moves under a
## dragged finger (then goes back where it was).
func _scroll_checks(scope: Array) -> Array:
	var out := []
	var win := Vector2(DisplayServer.window_get_size())
	for n: Node in get_nodes_in_group("phone_scroll"):
		if not (n.is_visible_in_tree() and n.can_scroll()):
			continue
		var was: float = n.scroll_y
		n.scroll_y = 0.0
		n.queue_sort()
		await process_frame
		# A point of the window on the screen that is no list of its own (a finger there moves the list).
		var box := _px(n.get_child(0)).intersection(Rect2(Vector2.ZERO, win))
		var lists_in: Array = n.find_children("*", "ScrollContainer", true, false).filter(
			func(c): return c.is_visible_in_tree() and (c.get_v_scroll_bar().max_value > c.size.y + 1 or c.get_h_scroll_bar().max_value > c.size.x + 1))
		var at := Vector2(-1, -1)
		for iy in range(8, 0, -1):
			for ix in 9:
				var q := box.position + box.size * Vector2((ix + 0.5) / 9.0, (iy - 0.5) / 8.0)
				if lists_in.any(func(c): return _px(c).has_point(q)):
					continue
				at = q
				break
			if at.x >= 0.0:
				break
		if at.x < 0.0:
			out.append("tall window %s: no place to drag it" % n.get_path())
			continue
		await _finger(at, at - Vector2(0, win.y * 0.3))
		if n.scroll_y < minf(1.0, n._overflow * 0.9):
			out.append("tall window %s does not scroll under the finger (%.1f of %.1f, at %s)" % [n.get_path(), n.scroll_y, n._overflow, at])
		n.scroll_y = was
		n.queue_sort()
		await process_frame
	var lists := 0
	for top: Node in scope:
		for sc: ScrollContainer in top.find_children("*", "ScrollContainer", true, false):
			if lists >= 3 or not sc.is_visible_in_tree() or _hidden_by_parent(sc):
				continue
			var r := _px(sc)
			var vis := r.intersection(Rect2(Vector2.ZERO, win))
			if vis.size.x < 40.0 or vis.size.y < 40.0:
				continue
			var v := sc.get_v_scroll_bar().max_value > sc.size.y + 4.0 and sc.vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED
			var h := sc.get_h_scroll_bar().max_value > sc.size.x + 4.0 and sc.horizontal_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED
			if not v and not h:
				continue
			lists += 1
			var v0 := sc.scroll_vertical
			var h0 := sc.scroll_horizontal
			sc.scroll_vertical = 0
			sc.scroll_horizontal = 0
			await process_frame
			var at := vis.get_center()
			var dir := Vector2(0, -vis.size.y * 0.35) if v else Vector2(-vis.size.x * 0.35, 0)
			await _finger(at, at + dir)
			if sc.scroll_vertical < 1 and sc.scroll_horizontal < 1:
				out.append("list %s does not scroll under the finger" % sc.name)
			sc.scroll_vertical = v0
			sc.scroll_horizontal = h0
			await process_frame
	return out


## Press and release of the left button at a point of the window (pixels).
func _tap_at(px: Vector2) -> void:
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = pressed
		e.position = px
		e.global_position = px
		root.push_input(e)
		await process_frame


func ok_zoom(cond: bool, what: String) -> void:
	if not cond:
		fails += 1
		print("FAIL ", what)


func _txt(c: Control) -> String:
	var t = c.get("text")
	return str(t).left(28).replace("\n", " ") if t != null else ""


## The cards of the table a finger presses: the own hand and the creatures/buildings of the field.
func _board_checks(touch: float) -> Array:
	var b = main.board
	var out := []
	if b.game == null or b.picker_layer.visible or b.inspect_layer.visible:
		return out
	var k := root.get_final_transform()
	for uid in b.views:
		var v = b.views[uid]
		if not v.visible or not v.is_inside_tree():
			continue
		var c = b.game.card(uid)
		if c == null:
			continue
		var zone: String = str(c.get("zone")) if c.get("zone") != null else ""
		var rect: Rect2 = v.get_global_transform_with_canvas() * v.get_rect() if v.has_method("get_rect") else Rect2()
		if rect.size == Vector2.ZERO:
			continue
		var r := Rect2(k * rect.position, rect.size * k.get_scale()).abs()
		if (zone == "creature" or zone == "building") and minf(r.size.x, r.size.y) < touch:
			out.append("card %s %s %dx%d < %d" % [zone, c.id, r.size.x, r.size.y, touch])
	return out


func _close_overlays() -> void:
	for r in main.overlay.get_children():
		main._close_overlay(r)
	await _wait(0.4)


func _button(where: Node, text: String) -> Button:
	for btn: Button in where.find_children("*", "Button", true, false):
		if btn.is_visible_in_tree() and (btn.text == text or btn.get_meta("game", "") == text):
			return btn
	return null


func _press(where: Node, text: String) -> bool:
	var b := _button(where, text)
	if b == null:
		print("FAIL no button «%s»" % text)
		fails += 1
		return false
	b.pressed.emit()
	return true


func _run() -> void:
	await _wait(1.2)
	if _part("menus"):
		await _menus()
	if _part("select"):
		await _selects()
	if _part("builder"):
		await _builder()
	if _part("train"):
		await _train()
	if _part("online"):
		await _online()
	if _part("game"):
		await _game()
	if _part("tables") or _part("sandbox"):
		await _tables()
	print("PHONE %s shots=%d fails=%d" % ["phone" if phone else "pc", shots, fails])
	quit(1 if fails > 0 else 0)


func _menus() -> void:
	main.show_title()
	await _wait(0.6)
	await _check("title")
	main.show_play_menu()
	await _wait(0.6)
	await _check("play")
	await _close_overlays()
	main.show_settings()
	await _wait(0.5)
	await _check("settings")
	await _close_overlays()
	if not phone:
		main.show_controls()
		await _wait(0.5)
		await _check("controls")
		await _close_overlays()
	main.show_gamepad()
	await _wait(0.5)
	await _check("gamepad")
	await _close_overlays()
	main._pick_background(func(): pass)
	await _wait(0.5)
	await _check("background")
	await _close_overlays()
	main._pick_card_back()
	await _wait(0.5)
	await _check("card_back")
	await _close_overlays()
	main.show_rules()
	await _wait(0.5)
	await _check("rules")
	await _close_overlays()
	main.show_replays()
	await _wait(0.5)
	await _check("replays")
	await _close_overlays()
	main.show_login()
	await _wait(0.5)
	await _check("login")
	await _close_overlays()
	if main.account.logged_in():
		main.show_profile()
		await _wait(0.6)
		await _check("profile")
		await _close_overlays()
	main.show_title()
	await _wait(0.4)
	main.social_ui.show_panel()
	await _wait(0.6)
	await _check("social")
	# Rows of friends as the server gives them (no server here): the eye of a friend in a game fits.
	var list: VBoxContainer = main.social_ui._list
	if list != null:
		for ch in list.get_children():
			ch.queue_free()
		for r in [{"nick": "Blitz_29", "st": "menu", "fr": "friend", "rk": 1},
				{"nick": "BrownBubbles", "st": "game", "fr": "friend", "rk": 5},
				{"nick": "MiMiK", "st": "game", "fr": "friend", "rk": 6, "wc": "ABCDEF"},
				{"nick": "Doc", "st": "game", "fr": "", "rk": 3}]:
			list.add_child(main.social_ui._row(r))
		await _wait(0.3)
		await _check("social_friends")
	main.social_ui.toggle()
	await _wait(0.4)


func _selects() -> void:
	for mode in ["ai", "hotseat", "teams", "three", "run", "aivsai"]:
		main.show_title()
		await _wait(0.3)
		main.show_hero_select(mode)
		await _wait(0.9)
		await _check("select_" + mode)
		if mode == "ai":
			var sw := _button(main.overlay, "С героем")
			if sw != null:
				sw.pressed.emit()
				await _wait(0.3)
				await _check("select_ai_no_hero")
				sw.pressed.emit()
		for btn in main.overlay.find_children("*", "Button", true, false):
			if btn.text == "2  Колода":
				btn.pressed.emit()
		await _wait(0.5)
		await _check("select_%s_deck" % mode)
		await _close_overlays()
	main.show_title()
	await _wait(0.3)


func _builder() -> void:
	main.show_deck_builder("")
	await _wait(1.4)
	await _check("builder")
	await _close_overlays()
	main.show_title()
	await _wait(0.4)


func _train() -> void:
	main.open_run()
	await _wait(0.8)
	await _check("train_menu")
	await _close_overlays()
	var saved = preload("res://scripts/train/train_run.gd").new()
	if saved.restore():
		main.run = saved           # the saved run, only shown
		main.show_run()
		await _wait(1.2)
		await _check("train_map")
		main.show_title()
		main.run = null
	main.show_title()
	await _wait(0.3)


func _online() -> void:
	main.show_net_lobby()
	await _wait(0.7)
	await _check("lobby")
	main.lobby._close_lobby()
	await _close_overlays()
	main.show_title()
	main.ranked.show_rank()
	await _wait(0.7)
	await _check("rank")
	await _close_overlays()
	await _rank_draft()
	main.show_title()
	main.ranked.show_quick()
	await _wait(0.7)
	await _check("quick")
	await _close_overlays()
	main.show_title()
	main.show_net_lobby("lan")
	await _wait(0.7)
	await _check("lobby_lan")
	main.lobby._close_lobby()
	await _close_overlays()
	main.show_title()
	main.watch.show_watch()
	await _wait(0.7)
	await _check("watch")
	await _close_overlays()
	main.show_title()
	main.sandbox_start.show_tables()
	await _wait(0.6)
	await _check("sandbox_tables")
	await _close_overlays()
	main.show_title()
	await _wait(0.3)


## The bans and the pick of a ranked match (no server: its state is set here), every deck in
## sight and pressed with a finger.
func _rank_draft() -> void:
	main.show_title()
	await _wait(0.3)
	var decks := []
	for d in CardDB.hero_ids():
		if CardDB.has_hero_card(d):
			decks.append(d)
	var r := {"phase": "ban", "decks": decks, "bans": [[], []], "done": [false, false], "left": 30}
	main.net.tour = {"names": ["Финн", "Джейк"], "rank": r}
	main.lobby.show_net_lobby("rank")
	main.ranked.draft_update()
	await _wait(0.7)
	await _check("rank_ban")
	var rk = main.ranked
	if not phone:
		main.lobby._close_lobby()
		await _close_overlays()
		return
	var win := Rect2(Vector2.ZERO, Vector2(DisplayServer.window_get_size()))
	for d in rk._tiles:
		if not win.encloses(_px(rk._tiles[d])):
			print("FAIL rank_ban: deck %s off the screen %s" % [d, _px(rk._tiles[d])])
			fails += 1
	await _finger_tap(rk._tiles[decks[0]])
	await _finger_tap(rk._tiles[decks[1]])
	if rk._sel != [decks[0], decks[1]]:
		print("FAIL rank_ban: a tap does not mark a deck: ", rk._sel)
		fails += 1
	await _finger_tap(rk._ready_btn)
	if rk._ready_btn.visible:
		print("FAIL rank_ban: «Готово» does not answer a tap")
		fails += 1
	r["phase"] = "pick"
	r["bans"] = [[decks[0], decks[1]], [decks[2]]]
	main.ranked.draft_update()
	await _wait(0.3)
	await _check("rank_pick")
	await _finger_tap(rk._tiles[decks[0]])
	if not rk._sel.is_empty():
		print("FAIL rank_pick: a banned deck was picked")
		fails += 1
	await _finger_tap(rk._tiles[decks[5]])
	if rk._sel != [decks[5]]:
		print("FAIL rank_pick: a tap does not pick a deck: ", rk._sel)
		fails += 1
	await _finger_tap(rk._ready_btn)
	if rk._ready_btn.visible:
		print("FAIL rank_pick: «Готово» does not answer a tap")
		fails += 1
	main.net.tour = {}
	main.lobby._close_lobby()
	await _close_overlays()


func _press_curtain() -> void:
	for r in main.overlay.get_children():
		for b in r.find_children("*", "Button", true, false):
			if b.is_visible_in_tree() and not b.disabled:
				b.pressed.emit()
				return


func _game() -> void:
	main.start_new_game()
	await _wait(2.0)
	await _check("coin")
	_press_curtain()
	for i in 2:
		await _wait(0.8)
		_press_curtain()
		await _wait(1.0)
		if i == 0:
			await _check("mulligan")
		main.board._mulligan_done.emit(i == 1)
		await _wait(1.2)
	_press_curtain()
	await _wait(1.5)
	_press_curtain()
	await _wait(1.0)
	await _check("board_start")
	var b = main.board
	# Watchers of our match: their number in the corner, the list under it when pressed.
	b.set_spectators(["gerk", "BrownBubbles", "Длинный_ник_зрителя"])
	b._spec_button.pressed.emit()
	await _check("board_spectators")
	var many := []
	for i in 20:
		many.append("Зритель_%d" % (i + 1))
	b.set_spectators(many)
	await _check("board_spectators_20")
	b.set_spectators([])
	var p: int = main.game.turn_player
	b._open_inspect(main.game.players[p].hand[0].id)
	await _wait(0.5)
	await _check("inspect")
	b._close_inspect()
	var ids := []
	for c in main.game.players[p].deck:
		ids.append(c.id)
	b._show_cards("Колода", ids)
	await _wait(0.6)
	await _check("picker")
	b.picker_layer.visible = false
	main.show_pause()
	await _wait(0.5)
	await _check("pause")
	await _close_overlays()
	main._on_game_over(0)
	await _wait(1.6)
	await _check("game_over")
	await _close_overlays()
	main.show_title()
	await _wait(0.5)


## The tables of every mode, filled with cards through the sandbox.
func _tables() -> void:
	for it in [["one", ["magic_man", "jake"]], ["teams", ["finn", "jake", "bmo", "marceline"]], ["three", ["finn", "jake", "bmo"]]]:
		var name: String = it[0]
		main.show_title()
		await _wait(0.3)
		main.sandbox_start.start(it[1])
		await _wait(2.0)
		await _idle()
		var b = main.board
		var g = main.game
		var sb = b.sandbox
		await _check("sb_%s_panel" % name)
		b.sb_panel.visible = false
		var ids := ["cool_dog", "corn_lord", "big_foot", "archer_dan"]
		for p in g.players.size():
			for lane in 4:
				if (lane + p) % 4 != 3:
					await sb.add_card(p, ids[(lane + p) % ids.size()], "creature", lane)
			for i in 2:
				await sb.add_card(p, "cool_dog", "hand")
		await sb.add_card(0, "blood_fortress", "building", 1)
		await sb.add_card(0, "cerebral_bloodstorm", "hand")
		sb.damage(1, 0, 2)
		sb.boost(0, 1, 2, 1)
		var c0 = g.players[0].creatures[0]
		if c0 != null:
			sb.toggle_exhausted(c0.uid)
		b.sync()
		b._update_hud()
		await _wait(1.2)
		await _check("table_%s" % name)
		if phone:
			# The strip of the log stays above the hero panels (a hero's ability button takes a row).
			var lr: Rect2 = b.log_panel.get_global_rect()
			for key in b.hero_ui:
				var pr: Rect2 = b.hero_ui[key]["panel"].get_global_rect()
				if b.log_panel.visible and b.hero_ui[key]["panel"].visible and lr.grow(-1.0).intersects(pr):
					print("FAIL table_%s: the log %s covers the %s panel %s" % [name, lr, key, pr])
					fails += 1
		if phone and name != "one":
			# A tap by an opponent's piles brings their lanes close; a tap on the bare table goes back.
			for side in g.sides():
				if not b.is_bottom(side) and g.is_foe(b.viewer, side):
					ok_zoom(b._phone_seat_zoom(b.deck_pos(side)), "zoom to a seat")
					await _wait(0.6)
					await _check("zoom_%s" % name)
					b._zoom_home()
					await _wait(0.5)
					break
		# A choice of a creature on the table, with the skip.
		var req := {"kind": "creature", "player": b.viewer, "optional": true, "prompt": "Выбери существо соперника",
			"options": [{"p": 1, "lane": 0}, {"p": 1, "lane": 1}]}
		b._local_choice(req)
		await _wait(0.6)
		await _check("choice_%s" % name)
		b._resolve_choice(null)
		await _wait(0.5)
		var opt := {"kind": "option", "player": b.viewer, "optional": false, "prompt": "Что сделать?",
			"options": ["Взять карту", "Нанести 2 урона"]}
		b._local_choice(opt)
		await _wait(0.6)
		await _check("option_%s" % name)
		# Two buttons fit their list whole: no half cut button, no scroll bar.
		ok_zoom(b.picker_scroll.get_v_scroll_bar().max_value <= b.picker_scroll.size.y + 1.0,
			"option_%s: the buttons are cut by their list (%.0f of %.0f)" % [name, b.picker_scroll.size.y, b.picker_scroll.get_v_scroll_bar().max_value])
		b._resolve_choice("Взять карту")
		await _wait(0.5)
		if phone:
			# A real tap on the strip of the log opens it, another closes it.
			await _tap_at(_px(b.log_panel).get_center())
			await _wait(0.4)
			ok_zoom(b._log_big, "a tap opens the log")
			ok_zoom(b.log_box.is_visible_in_tree() and b.log_box.get_parsed_text().strip_edges() != "" \
				and _px(b.log_box).size.y > 200.0, "the open log shows its lines (%s)" % _px(b.log_box))
			await _check("log_%s" % name)
			await _tap_at(_px(b.log_panel).get_center())
			await _wait(0.6)
			ok_zoom(not b._log_big, "a tap closes the log (under it: %s, log %s)" % [root.gui_get_hovered_control(), _px(b.log_panel)])
		main._end_game()
		await _wait(0.4)
	main.show_title()
	await _wait(0.4)
