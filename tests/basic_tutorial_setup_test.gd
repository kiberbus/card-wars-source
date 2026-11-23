extends SceneTree

const Game = preload("res://scripts/core/game.gd")

var failures := 0


func _initialize() -> void:
	_run_test.call_deferred()


func _run_test() -> void:
	var game = Game.new()
	game.setup(["finn", "jake"], 0, 1234, false)
	_check(game.configure_basic_tutorial(), "fixed tutorial decks can be configured")
	_check(_ids(game.players[0].hand) == [
		"blood_fortress", "ancient_scholar", "cool_dog", "spirit_soldier", "struzann_jinn",
	], "Finn receives the requested opening hand")
	_check(_ids(game.players[1].hand) == [
		"evil_eye", "archer_dan", "celestial_castle", "wall_of_ears", "corn_dog",
	], "Jake receives the requested opening hand")
	var finn_top := _top_ids(game.players[0].deck, 5)
	var finn_scripted := ["gnome_snot", "nice_ice_baby", "the_pig", "teleport", "psionic_architect"]
	var finn_order_ok := finn_top.size() == 5
	for i in finn_scripted.size():
		finn_order_ok = finn_order_ok and finn_top[i] == finn_scripted[i]
	_check(finn_order_ok, "Finn's scripted draw order begins with Gnome Snot")
	var jake_top := _top_ids(game.players[1].deck, 2)
	_check(jake_top == ["big_foot", "husker_knight"],
		"Jake draws a neutral card before Husker Knight")
	_check(game.players[0].mulligan_used and game.players[1].mulligan_used,
		"mulligans are disabled for the scenario")
	var repeat = Game.new()
	repeat.setup(["finn", "jake"], 0, 9876, false)
	repeat.configure_basic_tutorial()
	_check(_ids(game.players[0].deck) == _ids(repeat.players[0].deck)
			and _ids(game.players[1].deck) == _ids(repeat.players[1].deck),
			"scripted deck order does not depend on the random seed")
	await game.start_game()
	_check(game.players[0].hand.size() == 5
			and not game.players[0].hand.any(func(c): return c.id == "dragon_claw"),
			"Finn starts the tutorial with exactly five cards and no Dragon Claw")
	_check(game.players[0].deck.back().id == "gnome_snot",
		"Gnome Snot remains on top until Finn's second turn")
	var standard_game = Game.new()
	standard_game.setup(["finn", "jake"], 0, 1234, false)
	var first_draw: String = standard_game.players[0].deck.back().id
	await standard_game.start_game()
	_check(standard_game.players[0].hand.size() == 6
			and standard_game.players[0].hand.back().id == first_draw,
			"ordinary games keep their first-turn draw")
	quit(1 if failures > 0 else 0)


func _ids(cards: Array) -> Array:
	return cards.map(func(c): return c.id)


func _top_ids(deck: Array, count: int) -> Array:
	var ids := []
	for i in count:
		ids.append(deck[deck.size() - 1 - i].id)
	return ids


func _check(condition: bool, description: String) -> void:
	if condition:
		print("ok   ", description)
	else:
		failures += 1
		push_error("FAIL: " + description)
