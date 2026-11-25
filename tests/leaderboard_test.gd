extends SceneTree
## The leaderboard of the ranked games (scripts/ui/main/leaderboard.gd): the request, the rows of the
## answer, the filter «more than one game», the order and the places, our own row, headless:
##   godot --headless --path . -s res://tests/leaderboard_test.gd

const Leaderboard = preload("res://scripts/ui/main/leaderboard.gd")
const PlaceBadge = preload("res://scripts/ui/place_badge.gd")

var failures := 0


func _initialize() -> void:
	check_request()
	check_filter_and_order()
	check_me()
	check_texts()
	print("leaderboard tests: %d checks failed" % failures)
	quit(1 if failures > 0 else 0)


func expect(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", what)


func p(nick: String, st: int, pts: int, w: int, l: int) -> Dictionary:
	return {"nick": nick, "av": "", "st": st, "pts": pts, "w": w, "l": l}


func check_request() -> void:
	expect(Leaderboard.ASK.get("op") == "r_top", "the request is r_top")
	# The request and the answer go as Godot variants (social.gd var_to_bytes): they must survive it.
	var back = bytes_to_var(var_to_bytes(Leaderboard.ASK))
	expect(back is Dictionary and back == Leaderboard.ASK, "the request survives var_to_bytes")
	var answer := {"op": "r_top", "players": [p("a", 3, 400, 5, 2)]}
	var rows := Leaderboard.table(bytes_to_var(var_to_bytes(answer)))
	expect(rows.size() == 1 and rows[0]["nick"] == "a" and rows[0]["pts"] == 400, "an answer survives var_to_bytes")


func check_filter_and_order() -> void:
	var answer := {"op": "r_top", "players": [
		p("one_game", 11, 9999, 1, 0),        # one game: out, however high
		p("none", 0, 0, 0, 0),                # no games: out
		p("silver_low", 4, 300, 6, 4),
		p("gold", 6, 900, 20, 3),
		p("silver_high", 4, 350, 6, 4),
		p("Bravo", 4, 300, 6, 4),             # the same as silver_low: by nick, case aside
		p("alpha", 4, 300, 6, 4),
		p("more_wins", 4, 300, 7, 9),
		p("two_games", 0, 10, 1, 1),          # two games: in
		p("gold", 1, 1, 9, 9),                # the same nick again: the first one stays
		{"nick": "", "st": 9, "pts": 1, "w": 5, "l": 5},     # no nick: out
		"junk",
		{"nick": "strings", "st": "2", "pts": "50", "w": "3", "l": "1"}]}
	var rows := Leaderboard.table(answer)
	var order: Array = rows.map(func(r): return r["nick"])
	expect(order == ["gold", "silver_high", "more_wins", "alpha", "Bravo", "silver_low", "strings", "two_games"],
		"order %s" % [order])
	var places: Array = rows.map(func(r): return r["place"])
	expect(places == [1, 2, 3, 4, 5, 6, 7, 8], "places %s" % [places])
	expect(rows.all(func(r): return r["games"] > 1), "only more than one game")
	expect(rows[6]["pts"] == 50 and rows[6]["st"] == 2, "numbers sent as text are read")
	expect(Leaderboard.table({"op": "r_top"}).is_empty(), "no players: an empty table")
	expect(Leaderboard.table({"op": "r_top", "players": "bad"}).is_empty(), "a bad list: an empty table")


func check_me() -> void:
	var answer := {"op": "r_top", "players": [p("a", 5, 500, 9, 1), p("b", 3, 200, 4, 4)],
		"me": {"nick": "me", "st": 1, "pts": 40, "w": 2, "l": 3, "place": 57}}
	var rows := Leaderboard.table(answer)
	var me := Leaderboard.my_row(answer, rows, "b")
	expect(me.get("place") == 2 and rows.has(me), "our row is found in the table")
	me = Leaderboard.my_row(answer, rows, "me")
	expect(me.get("place") == 57 and me["pts"] == 40 and not rows.has(me), "our row under the table, with its place")
	expect(Leaderboard.my_row(answer, rows, "other").is_empty(), "a «me» of another nick is not ours")
	answer["me"] = {"nick": "me", "st": 0, "pts": 0, "w": 1, "l": 0, "place": 3}
	expect(Leaderboard.my_row(answer, rows, "me").is_empty(), "one game: we are not in the table")
	expect(Leaderboard.my_row(answer, rows, "").is_empty(), "a guest has no row")


func check_texts() -> void:
	expect(Leaderboard.points_text(7) == "7", "points 7")
	expect(Leaderboard.points_text(1234) == "1 234", "points 1 234: %s" % Leaderboard.points_text(1234))
	expect(Leaderboard.points_text(1234567) == "1 234 567", "points 1 234 567")
	# The metal is light at the top, darkest just under the middle.
	for place in [1, 2, 3]:
		var top := PlaceBadge.metal_at(place, 0.0).get_luminance()
		var band := PlaceBadge.metal_at(place, 0.58).get_luminance()
		var low := PlaceBadge.metal_at(place, 1.0).get_luminance()
		expect(top > band and low > band, "the metal of place %d shines" % place)
