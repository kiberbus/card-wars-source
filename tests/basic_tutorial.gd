extends SceneTree

const Game = preload("res://scripts/core/game.gd")
const BasicTutorial = preload("res://scripts/ui/basic_tutorial.gd")

var failures := 0


func _initialize() -> void:
	var game = Game.new()
	game.setup(["finn", "jake"], 0, 733104)
	BasicTutorial.configure_game(game)
	_check_ids(game.players[0].hand, [
		"blood_fortress", "ancient_scholar", "cool_dog", "spirit_soldier", "struzann_jinn",
	], "Finn starting hand")
	_check_ids(game.players[1].hand, [
		"evil_eye", "archer_dan", "celestial_castle", "wall_of_ears", "corn_dog",
	], "Jake starting hand")
	_check_draw_order(game.players[0].deck, [
		"woad_talisman", "gnome_snot", "nice_ice_baby", "the_pig", "teleport", "psionic_architect",
	], "Finn draw order")
	_check_draw_order(game.players[1].deck, ["corn_scepter", "husker_knight"], "Jake draw order")
	quit(1 if failures > 0 else 0)


func _check_ids(cards: Array, expected: Array, label: String) -> void:
	var actual: Array = cards.map(func(c): return c.id)
	if actual != expected:
		push_error("%s mismatch: %s" % [label, actual])
		failures += 1


func _check_draw_order(deck: Array, expected: Array, label: String) -> void:
	var actual: Array = []
	for i in expected.size():
		actual.append(deck.pop_back().id)
	if actual != expected:
		push_error("%s mismatch: %s" % [label, actual])
		failures += 1
