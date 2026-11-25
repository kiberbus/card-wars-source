extends "res://tests/zoom_test.gd"
## The «Лидерборд» button of the rank window and the leaderboard window (scripts/ui/main/leaderboard.gd)
## with made-up players, at a scale, with the check that nothing leaves the screen, and screenshots:
##   godot --path . --resolution 1440x1080 -s res://tests/shots_leaderboard.gd -- <output_dir> 1 --relay ws://127.0.0.1:9
##   godot --path . --resolution 2400x1080 -s res://tests/shots_leaderboard.gd -- <output_dir> 1 1 phone --relay ws://127.0.0.1:9
## Shots: the rank window, the table with us in it, the table with us under it, a server without r_top.
## Nothing goes to a server.

const NICKS := ["Bella", "негусь", "lolkeponi", "Ainurito", "Blitz_29", "PIZZA", "sleepy", "Скавен", "virloy",
	"dkosak", "Alen", "Очень_длинный_ник", "Finn_fan", "Марселин", "Gunter99"]


func _answer(me_in: bool) -> Dictionary:
	var players := []
	var st := 10
	var pts := 2950
	for i in NICKS.size():
		players.append({"nick": NICKS[i], "av": "", "st": st, "pts": pts, "w": 60 - i * 3, "l": 10 + i, "rb": i == 0})
		pts -= 110 + i * 7
		if i % 2 == 1:
			st = maxi(0, st - 1)
	players.append({"nick": "one_game", "st": 11, "pts": 9000, "w": 1, "l": 0})
	if me_in:
		players.insert(4, {"nick": "gerk", "st": 9, "pts": 2600, "w": 64, "l": 24})
	return {"op": "r_top", "players": players,
		"me": {"nick": "gerk", "st": 5, "pts": 1172, "w": 64, "l": 24, "place": 31}}


func _run() -> void:
	await _wait(1.0)
	var saved: float = main.ui_zoom
	main.social.set_process(false)          # no link: the states below are made up
	main.account.token = "test"
	main.account.nick = "gerk"
	main.social.link_up = true
	main.social.rank = {"op": "r_me", "st": 5, "in": 172, "need": 180, "w": 64, "l": 24, "left": 20 * 86400 + 3 * 3600, "code": ""}
	for z: float in zooms:
		_set_zoom(z)
		main.ranked.show_rank()
		await _wait(0.6)
		await _check("lb_rank_window")
		var lb = main.ranked.leaderboard
		for b: Button in main.overlay.find_children("*", "Button", true, false):
			if b.text == "Лидерборд":
				b.pressed.emit()
		await _wait(0.5)
		lb.fill(_answer(true))
		await _wait(0.5)
		await _check("lb_table")
		lb.fill(_answer(false))
		await _wait(0.5)
		await _check("lb_table_me_below")
		lb.fill({"op": "s_error", "r": "timeout"})
		await _wait(0.3)
		await _check("lb_no_server")
		await _close_overlays()
	main.account.token = ""
	main._save_setting("ui", "zoom", saved)
	print("ZOOM fails=%d" % fails)
	quit(1 if fails > 0 else 0)
