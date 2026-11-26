extends "res://scripts/ui/basic_tutorial.gd"

const FIRE := 0
const FROST := 1
const GOBBLE := 2
const FLIP := 3

var lesson := FIRE
var lesson_state := ""


static func prepare(g, number: int) -> bool:
	if number < FIRE or number > FLIP:
		push_error("Advanced tutorial: invalid lesson %d." % number)
		return false
	var hero := "flame_princess" if number == FIRE else ("fern" if number == GOBBLE else "finn")
	g.setup([hero, "jake"], 0, 1, false)
	g.phase = "main"
	g.turn_player = 0
	g.turn_number = 3
	g.players[0].actions = 2
	for player in g.players:
		player.deck.append_array(player.hand)
		player.hand.clear()
	if number == FIRE:
		var spell = g._take_tutorial_card(g.players[0].deck, "hot_shot")
		var ally = g._take_tutorial_card(g.players[0].deck, "flameingo_blazeling")
		var target = g._take_tutorial_card(g.players[1].deck, "evil_eye")
		if spell == null or ally == null or target == null:
			return false
		g.players[0].hand.append(spell)
		g.players[0].creatures[1] = ally
		g.players[1].creatures[0] = target
	elif number == FROST:
		var discard = g._take_tutorial_card(g.players[0].deck, "gnome_snot")
		var creature = g._take_tutorial_card(g.players[0].deck, "nice_ice_baby")
		var existing = g._take_tutorial_card(g.players[0].deck, "cool_dog")
		if discard == null or creature == null or existing == null:
			return false
		g.players[0].hand.append_array([discard, creature])
		g.players[0].creatures[1] = existing
		g.players[0].lands[0]["frozen"] = true
		g.players[0].lands[1]["frozen"] = true
	elif number == GOBBLE:
		var old = g._take_tutorial_card(g.players[0].deck, "darling_cobnoblin")
		var replacement = g._take_tutorial_card(g.players[0].deck, "treasured_cobnoblin")
		if old == null or replacement == null:
			return false
		g.players[0].creatures[0] = old
		g.players[0].hand.append(replacement)
	else:
		var pig = g._take_tutorial_card(g.players[0].deck, "the_pig")
		var opposite = g._take_tutorial_card(g.players[1].deck, "evil_eye")
		var knight = g._take_tutorial_card(g.players[1].deck, "husker_knight")
		if pig == null or opposite == null or knight == null:
			return false
		g.players[0].creatures[0] = pig
		g.players[1].creatures[0] = opposite
		g.players[1].creatures[1] = knight
	return true


func start_lesson(g, b, tutorial_language: String, number: int) -> void:
	game = g
	board = b
	language = tutorial_language
	lesson = number
	board.tutorial = self
	_build_ui()
	_exit_intro_layout()
	_update_phase(_text("phase_main", "Фаза действий и способностей: разыгрывай карты, добирай за действие и используй ФЛЮП."))
	_show_lesson("action")


func _show_lesson(state: String) -> void:
	lesson_state = state
	_clear_focus()
	dialogue_layer.visible = false
	guide_panel.visible = true
	next_button.visible = state == "complete" or state == "details"
	if state == "complete":
		match lesson:
			FIRE:
				guide_text.text = _text("advanced_fire_done", "Огонь нанёс 1 урон сразу; «Меткий выстрел» добавил ещё 1. В начале хода владельца каждый жетон огня снова наносит 1 урон.")
				_highlight_table(game.players[1].creatures[0].uid)
			FROST:
				guide_text.text = _text("advanced_frost_done", "Лёд снят сбросом карты. При заморозке существо, уже стоящее на земле, остаётся на месте: посмотри на Крутого пса по соседству.")
				_highlight_table(game.players[0].creatures[1].uid)
			GOBBLE:
				guide_text.text = _text("advanced_gobble_done", "Хрум срабатывает при замене существа с этим свойством. Оно ложится под новое: его базовые характеристики и постоянные бонусы прибавляются к новым. Здесь 2/3 + 1/4 = 3/7.")
				_highlight_table(game.players[0].creatures[0].uid)
			FLIP:
				guide_text.text = _text("advanced_flip_done", "Земля перевёрнута и больше не считается кукурузным полем. Существо на ней осталось; у Кожурыцаря стало меньше атаки и защиты.")
				_highlight_table(game.players[1].creatures[0].uid)
				_highlight_table(game.players[1].creatures[1].uid)
	elif state == "details":
		match lesson:
			FIRE:
				guide_text.text = _text("advanced_fire_examples", "Некоторые существа используют жетоны огня: «Яростный феникс» получает +1 к атаке за каждый на существах, а «Огненный пёс» при входе может нанести столько же урона.")
			GOBBLE:
				guide_text.text = _text("advanced_gobble_details", "Урон и жетоны тоже переходят новому существу, но способности старого не переходят. Когда новое существо покидает игру, карта под ним уходит в сброс.")
				_highlight_table(game.players[0].creatures[0].uid)
			FLIP:
				guide_text.text = _text("advanced_flip_details", "Перевёрнутая земля не считается ни за какой тип при розыгрыше карт. Она остаётся перевёрнутой, пока эффект не вернёт её лицом вверх.")
	elif lesson == FIRE:
		guide_text.text = _text("advanced_fire", "Огонь: сыграй «Меткий выстрел» и выбери подсвеченное существо соперника.")
		_highlight_hand("hot_shot")
		_highlight_table(game.players[1].creatures[0].uid)
	elif lesson == FROST and state == "action":
		guide_text.text = _text("advanced_frost", "Мороз: обычно на замороженную землю нельзя играть существ, но строения можно. Нажми на землю, выбери «Растопить лёд» и сбрось «Гномьи сопли».")
		_highlight_hand("gnome_snot")
		board.tutorial_land_targets.append({"p": 0, "lane": 0})
	elif lesson == FROST:
		guide_text.text = _text("advanced_frost_play", "Земля оттаяла. Сыграй «Прохладный младенец» на неё.")
		_highlight_hand("nice_ice_baby")
		board.tutorial_land_targets.append({"p": 0, "lane": 0})
	elif lesson == GOBBLE:
		guide_text.text = _text("advanced_gobble", "Хрум: сыграй «Драгоценнейший початкогоблин» поверх «Милого початкогоблина» в подсвеченной зоне.")
		_highlight_hand("treasured_cobnoblin")
		_highlight_table(game.players[0].creatures[0].uid)
		board.tutorial_land_targets.append({"p": 0, "lane": 0})
	else:
		guide_text.text = _text("advanced_flip", "Переворот земли: нажми на «Свинью» и выбери «ФЛЮП», чтобы перевернуть кукурузное поле напротив. Посмотри на характеристики Кожурыцаря.")
		_highlight_table(game.players[0].creatures[0].uid)
		_highlight_table(game.players[1].creatures[1].uid)
		board.tutorial_land_targets.append({"p": 1, "lane": 0})
	board.decor.queue_redraw()


func _advance() -> void:
	if lesson_state != "complete" and lesson_state != "details":
		return
	if lesson_state == "complete" and lesson in [FIRE, GOBBLE, FLIP]:
		_show_lesson("details")
	elif lesson == FLIP:
		_return_to_title()
	else:
		var main = board.get_parent().get_parent()
		main.start_advanced_tutorial(language, lesson + 1)


func allow_command(p: int, command: Dictionary) -> bool:
	if p != 0:
		return false
	if lesson_state == "action":
		if lesson == FIRE:
			return _play_is(command, "hot_shot")
		if lesson == FROST:
			return command.get("cmd") == "thaw" and int(command.get("lane", -1)) == 0 \
					and game.can_thaw(0, 0)
		if lesson == GOBBLE:
			return _play_is(command, "treasured_cobnoblin") and int(command.get("lane", -1)) == 0
		return command.get("cmd") == "floop" and command.get("kind") == "creature" \
				and int(command.get("lane", -1)) == 0 and not command.get("hero", false) \
				and game.can_floop(0, "creature", 0)
	if lesson == FROST and lesson_state == "play":
		return _play_is(command, "nice_ice_baby") and int(command.get("lane", -1)) == 0
	return false


func allow_choice(req: Dictionary, result) -> bool:
	if lesson == FIRE and lesson_state == "action" and req.get("kind") == "creature":
		return result is Dictionary and int(result.get("p", -1)) == 1 and int(result.get("lane", -1)) == 0
	if lesson == FROST and lesson_state == "action" and req.get("kind") == "hand_card":
		var card = game.card(int(result)) if result is int else null
		return card != null and card.id == "gnome_snot"
	if lesson == FLIP and lesson_state == "action" and req.get("kind") == "land":
		return result is Dictionary and int(result.get("p", -1)) == 1 and int(result.get("lane", -1)) == 0
	return true


func command_resolved(p: int, command: Dictionary) -> void:
	if p != 0:
		return
	if lesson == FIRE and lesson_state == "action" and game.burning(game.players[1].creatures[0]):
		_show_lesson("complete")
	elif lesson == FROST and lesson_state == "action" and not game.is_frozen(0, 0):
		_show_lesson("play")
	elif lesson == FROST and lesson_state == "play" and game.players[0].creatures[0] != null:
		_show_lesson("complete")
	elif lesson == GOBBLE and lesson_state == "action":
		var creature = game.players[0].creatures[0]
		if creature != null and creature.id == "treasured_cobnoblin" \
				and creature.under.any(func(c): return c.id == "darling_cobnoblin"):
			_show_lesson("complete")
	elif lesson == FLIP and lesson_state == "action" and game.players[1].lands[0]["flipped"]:
		_show_lesson("complete")


func on_game_event(_event: Dictionary) -> void:
	pass


func hold_combat_end(_p: int) -> bool:
	return false
