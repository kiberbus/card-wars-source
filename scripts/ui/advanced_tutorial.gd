extends "res://scripts/ui/basic_tutorial.gd"

const FIRE := 0
const FROST := 1
const GOBBLE := 2
const WHUMP := 3
const FLIP := 4
const FINN_ADVANCED := preload("res://assets/tutorial/characters/finn_advanced.png")
const BMO_DEFAULT := preload("res://assets/tutorial/characters/bmo_default.png")
const BMO_FIRE := preload("res://assets/tutorial/characters/bmo_fire.png")
const BMO_FROST := preload("res://assets/tutorial/characters/bmo_frost.png")
const BMO_GOBBLE := preload("res://assets/tutorial/characters/bmo_gobble.png")

var lesson := FIRE
var lesson_state := ""


static func prepare(g, number: int) -> bool:
	if number < FIRE or number > FLIP:
		push_error("Advanced tutorial: invalid lesson %d." % number)
		return false
	var deck := "flame_princess" if number == FIRE else ("fern" if number in [GOBBLE, WHUMP] else "finn")
	var player_pick := deck if deck == "finn" else deck + "@finn"
	g.setup([player_pick, "bmo"], 0, 1, false)
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
		var phoenix = g._take_tutorial_card(g.players[0].deck, "furious_phoenix")
		var dog = g._take_tutorial_card(g.players[0].deck, "fire_dog")
		if spell == null or ally == null or phoenix == null or dog == null:
			return false
		g.players[0].hand.append_array([spell, phoenix, dog])
		g.players[0].creatures[1] = ally
		g.players[1].creatures[0] = g._make_card("evil_eye", 1)
	elif number == FROST:
		var discard = g._take_tutorial_card(g.players[0].deck, "gnome_snot")
		var creature = g._take_tutorial_card(g.players[0].deck, "nice_ice_baby")
		var existing = g._take_tutorial_card(g.players[0].deck, "cool_dog")
		var building = g._take_tutorial_card(g.players[0].deck, "blood_fortress")
		var second_discard = g._take_tutorial_card(g.players[0].deck, "teleport")
		if discard == null or creature == null or existing == null or building == null or second_discard == null:
			return false
		g.players[0].hand.append_array([discard, creature, building, second_discard])
		g.players[0].creatures[1] = existing
		g.players[0].lands[0]["frozen"] = true
		g.players[0].lands[1]["frozen"] = true
	elif number == GOBBLE:
		var old = g._take_tutorial_card(g.players[0].deck, "darling_cobnoblin")
		var replacement = g._take_tutorial_card(g.players[0].deck, "treasured_cobnoblin")
		var next_creature = g._take_tutorial_card(g.players[0].deck, "darling_cobnoblin")
		if old == null or replacement == null or next_creature == null:
			return false
		g.players[0].creatures[0] = old
		g.players[0].creatures[1] = next_creature
		g.players[0].hand.append_array([replacement, g._make_card("darling_cobnoblin", 0)])
	elif number == WHUMP:
		var old = g._take_tutorial_card(g.players[0].deck, "genteel_armourdillo")
		var replacement = g._take_tutorial_card(g.players[0].deck, "valiant_armourdillo")
		var next_creature = g._take_tutorial_card(g.players[0].deck, "courageous_armourdillo")
		var helper = g._take_tutorial_card(g.players[0].deck, "darling_cobnoblin")
		if old == null or replacement == null or next_creature == null or helper == null:
			return false
		g.players[0].creatures[0] = old
		g.players[0].creatures[1] = helper
		g.players[0].hand.append_array([replacement, next_creature])
		g.players[1].creatures[0] = g._make_card("evil_eye", 1)
	else:
		var pig = g._take_tutorial_card(g.players[0].deck, "the_pig")
		var architect = g._take_tutorial_card(g.players[0].deck, "psionic_architect")
		if pig == null or architect == null:
			return false
		g.players[0].lands[0]["type"] = "corn"
		for land in g.players[1].lands:
			land["type"] = "corn"
		g.players[0].creatures[0] = pig
		g.players[0].hand.append(architect)
		g.players[1].creatures[0] = g._make_card("evil_eye", 1)
		g.players[1].creatures[1] = g._make_card("husker_knight", 1)
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
	_show_lesson("intro_finn" if lesson == FIRE else "intro_bmo")


func _show_lesson(state: String) -> void:
	lesson_state = state
	_clear_focus()
	if state == "intro_finn":
		_show_story_dialogue(FINN_ADVANCED, _text("advanced_intro_finn", "Бимо, научи меня лучше играть в Карточные войны!"))
		return
	if state == "intro_welcome":
		_show_story_dialogue(BMO_DEFAULT, _text("advanced_intro_welcome", "Конечно, Финн! Я покажу тебе несколько хитростей."))
		return
	if state == "intro_bmo":
		var keys := ["advanced_intro_fire", "advanced_intro_frost", "advanced_intro_gobble", "advanced_intro_whump", "advanced_intro_flip"]
		var lines := [
			"Начнём с огня!",
			"Отлично! Теперь разберёмся с морозом.",
			"Здорово! А теперь узнаем, как работает Хрум.",
			"А теперь познакомимся с Бухом броненосцев!",
			"Осталась ещё одна хитрость: переворот земель!",
		]
		var portraits := [BMO_FIRE, BMO_FROST, BMO_GOBBLE, BMO_GOBBLE, BMO_DEFAULT]
		_show_story_dialogue(portraits[lesson], _text(keys[lesson], lines[lesson]))
		return
	if state == "outro_finn":
		_show_story_dialogue(FINN_ADVANCED, _text("advanced_outro_finn", "Спасибо, Бимо! Теперь я лучше понимаю эти хитрости."))
		return
	if state == "outro_bmo":
		_show_story_dialogue(BMO_DEFAULT, _text("advanced_outro_bmo", "Ты отлично потренировался, Финн! Удачи в игре с Джейком!"))
		return
	dialogue_layer.visible = false
	guide_panel.visible = true
	next_button.visible = state in ["complete", "details", "practice_done"]
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
			WHUMP:
				guide_text.text = _text("advanced_whump_done", "Бух уменьшил стоимость Доблестного с 5 до 2: 5 минус 3, стоимость заменённого существа. Его способность уничтожила существо Бимо.")
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
			WHUMP:
				guide_text.text = _text("advanced_whump_details", "Бух учитывает стоимость на заменяемой карте и уменьшает требование к числу земель. Сам по себе он не передаёт характеристики: обычное существо уходит в сброс, в отличие от Хрум.")
			FLIP:
				guide_text.text = _text("advanced_flip_details", "Перевёрнутая земля не считается ни за какой тип при розыгрыше карт. Она остаётся перевёрнутой, пока эффект не вернёт её лицом вверх.")
	elif state == "practice_done":
		match lesson:
			FIRE:
				guide_text.text = _text("advanced_fire_practice_done", "Жетон огня усилил Феникса и помог Огненному псу нанести урон. Отличная работа!")
			FROST:
				guide_text.text = _text("advanced_frost_practice_done", "Строение можно поставить на замёрзшую землю, а лёд убрать позже. Существо при этом осталось на месте.")
			GOBBLE:
				guide_text.text = _text("advanced_gobble_practice_done", "Снова сработал Хрум: новое существо получило характеристики предыдущего, включая уже прибавленные бонусы.")
			WHUMP:
				guide_text.text = _text("advanced_whump_practice_done", "Молодец! Даже бесплатному существу нужного типа требуется хотя бы одна подходящая открытая земля. Жетон усилил Отважного.")
			FLIP:
				guide_text.text = _text("advanced_flip_practice_done", "Свинья может перевернуть подходящее поле любой стороны в своей зоне. Перевёрнутое поле больше не считается кукурузным.")
	elif state == "practice_one":
		match lesson:
			FIRE:
				guide_text.text = _text("advanced_fire_practice_one", "Сыграй «Яростный феникс» в подсвеченную зону. Посмотри, как жетон огня повышает его атаку.")
				_highlight_hand("furious_phoenix")
				board.tutorial_land_targets.append({"p": 0, "lane": 3})
			FROST:
				guide_text.text = _text("advanced_frost_practice_one", "Поставь «Кровавую крепость» на замёрзшую землю с Крутым псом. Мороз не мешает строениям.")
				_highlight_hand("blood_fortress")
				board.tutorial_building_targets.append({"p": 0, "lane": 1})
			GOBBLE:
				guide_text.text = _text("advanced_gobble_practice_one", "Флюпни «Милого початкогоблина» в соседней зоне и положи жетон атаки на Драгоценнейшего.")
				_highlight_table(game.players[0].creatures[0].uid)
				_highlight_table(game.players[0].creatures[1].uid)
			WHUMP:
				guide_text.text = _text("advanced_whump_practice_one", "Сыграй «Отважного броненосца» поверх Доблестного. Его стоимость 3, а указанная стоимость Доблестного — 5, поэтому розыгрыш бесплатен.")
				_highlight_hand("courageous_armourdillo")
				_highlight_table(game.players[0].creatures[0].uid)
				board.tutorial_land_targets.append({"p": 0, "lane": 0})
			FLIP:
				guide_text.text = _text("advanced_flip_practice_one", "Сыграй «Архитектор разума» в подсвеченную зону и выбери Свинью, чтобы подготовить её снова.")
				_highlight_hand("psionic_architect")
				_highlight_table(game.players[0].creatures[0].uid)
				board.tutorial_land_targets.append({"p": 0, "lane": 1})
	elif state == "practice_two":
		match lesson:
			FIRE:
				guide_text.text = _text("advanced_fire_practice_two", "Сыграй «Огненный пёс» в подсвеченную зону и выбери горящее существо Бимо. Пёс нанесёт урон за жетон огня.")
				_highlight_hand("fire_dog")
				_highlight_table(game.players[1].creatures[0].uid)
				board.tutorial_land_targets.append({"p": 0, "lane": 2})
			FROST:
				guide_text.text = _text("advanced_frost_practice_two", "Теперь растопи лёд под Крутым псом: нажми на его землю и сбрось «Телепорт».")
				_highlight_hand("teleport")
				board.tutorial_land_targets.append({"p": 0, "lane": 1})
			GOBBLE:
				guide_text.text = _text("advanced_gobble_practice_two", "Сыграй «Милого початкогоблина» с руки поверх Драгоценнейшего. Хрум передаст ему и жетон атаки.")
				_highlight_hand("darling_cobnoblin")
				_highlight_table(game.players[0].creatures[0].uid)
				board.tutorial_land_targets.append({"p": 0, "lane": 0})
			WHUMP:
				guide_text.text = _text("advanced_whump_practice_two", "Флюпни «Милого початкогоблина» рядом и положи жетон атаки на Отважного броненосца.")
				_highlight_table(game.players[0].creatures[0].uid)
				_highlight_table(game.players[0].creatures[1].uid)
			FLIP:
				guide_text.text = _text("advanced_flip_practice_two", "Снова выбери «ФЛЮП» у Свиньи. На этот раз переверни своё кукурузное поле в её зоне.")
				_highlight_table(game.players[0].creatures[0].uid)
				board.tutorial_land_targets.append({"p": 0, "lane": 0})
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
	elif lesson == WHUMP:
		guide_text.text = _text("advanced_whump", "Бух: сыграй «Доблестного броненосца» поверх Благородного. Замена уменьшит стоимость с 5 до 2 действий.")
		_highlight_hand("valiant_armourdillo")
		_highlight_table(game.players[0].creatures[0].uid)
		_highlight_table(game.players[1].creatures[0].uid)
		board.tutorial_land_targets.append({"p": 0, "lane": 0})
	else:
		guide_text.text = _text("advanced_flip", "Переворот земли: нажми на «Свинью» и выбери «ФЛЮП», чтобы перевернуть кукурузное поле напротив. Посмотри на характеристики Кожурыцаря.")
		_highlight_table(game.players[0].creatures[0].uid)
		_highlight_table(game.players[1].creatures[1].uid)
		board.tutorial_land_targets.append({"p": 1, "lane": 0})
	board.decor.queue_redraw()


func _show_story_dialogue(character: Texture2D, text: String) -> void:
	_show_dialogue(character, text)
	dialogue_character.visible = character != null


func _advance() -> void:
	if lesson_state == "intro_finn":
		_show_lesson("intro_welcome")
		return
	if lesson_state == "intro_welcome":
		_show_lesson("intro_bmo")
		return
	if lesson_state == "intro_bmo":
		_show_lesson("action")
		return
	if lesson_state == "outro_finn":
		_show_lesson("outro_bmo")
		return
	if lesson_state == "outro_bmo":
		_return_to_title()
		return
	if lesson_state == "complete" and lesson in [FIRE, GOBBLE, WHUMP, FLIP]:
		_show_lesson("details")
	elif lesson_state == "details" or (lesson_state == "complete" and lesson == FROST):
		_show_lesson("practice_one")
	elif lesson_state == "practice_done" and lesson == FLIP:
		_show_lesson("outro_finn")
	elif lesson_state == "practice_done":
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
		if lesson == WHUMP:
			return _play_is(command, "valiant_armourdillo") and int(command.get("lane", -1)) == 0
		return command.get("cmd") == "floop" and command.get("kind") == "creature" \
				and int(command.get("lane", -1)) == 0 and not command.get("hero", false) \
				and game.can_floop(0, "creature", 0)
	if lesson == FROST and lesson_state == "play":
		return _play_is(command, "nice_ice_baby") and int(command.get("lane", -1)) == 0
	if lesson_state == "practice_one":
		match lesson:
			FIRE:
				return _play_is(command, "furious_phoenix") and int(command.get("lane", -1)) == 3
			FROST:
				return _play_is(command, "blood_fortress") and int(command.get("lane", -1)) == 1
			GOBBLE:
				return _own_floop(command, 1)
			WHUMP:
				return _play_is(command, "courageous_armourdillo") and int(command.get("lane", -1)) == 0
			FLIP:
				return _play_is(command, "psionic_architect") and int(command.get("lane", -1)) == 1
	if lesson_state == "practice_two":
		match lesson:
			FIRE:
				return _play_is(command, "fire_dog") and int(command.get("lane", -1)) == 2
			FROST:
				return command.get("cmd") == "thaw" and int(command.get("lane", -1)) == 1 and game.can_thaw(0, 1)
			GOBBLE:
				return _play_is(command, "darling_cobnoblin") and int(command.get("lane", -1)) == 0
			WHUMP:
				return _own_floop(command, 1)
			FLIP:
				return _own_floop(command)
	return false


func _own_floop(command: Dictionary, lane := 0) -> bool:
	return command.get("cmd") == "floop" and command.get("kind") == "creature" \
			and int(command.get("lane", -1)) == lane and not command.get("hero", false) \
			and game.can_floop(0, "creature", lane)


func allow_choice(req: Dictionary, result) -> bool:
	if lesson == FIRE and lesson_state == "action" and req.get("kind") == "creature":
		return result is Dictionary and int(result.get("p", -1)) == 1 and int(result.get("lane", -1)) == 0
	if lesson == FROST and lesson_state == "action" and req.get("kind") == "hand_card":
		var card = game.card(int(result)) if result is int else null
		return card != null and card.id == "gnome_snot"
	if lesson == FIRE and lesson_state == "practice_two" and req.get("kind") == "creature":
		return result is Dictionary and int(result.get("p", -1)) == 1 and int(result.get("lane", -1)) == 0
	if lesson == FROST and lesson_state == "practice_two" and req.get("kind") == "hand_card":
		var card = game.card(int(result)) if result is int else null
		return card != null and card.id == "teleport"
	if lesson == FLIP and lesson_state == "practice_one" and req.get("kind") == "creature":
		return result is Dictionary and int(result.get("p", -1)) == 0 and int(result.get("lane", -1)) == 0
	if lesson == GOBBLE and lesson_state == "practice_one" and req.get("kind") == "creature":
		return result is Dictionary and int(result.get("p", -1)) == 0 and int(result.get("lane", -1)) == 0
	if lesson == WHUMP and lesson_state == "practice_two" and req.get("kind") == "creature":
		return result is Dictionary and int(result.get("p", -1)) == 0 and int(result.get("lane", -1)) == 0
	if lesson == FLIP and lesson_state in ["action", "practice_two"] and req.get("kind") == "land":
		var side := 1 if lesson_state == "action" else 0
		return result is Dictionary and int(result.get("p", -1)) == side and int(result.get("lane", -1)) == 0
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
	elif lesson == WHUMP and lesson_state == "action":
		var creature = game.players[0].creatures[0]
		if creature != null and creature.id == "valiant_armourdillo":
			_show_lesson("complete")
	elif lesson == FLIP and lesson_state == "action" and game.players[1].lands[0]["flipped"]:
		_show_lesson("complete")
	elif lesson_state == "practice_one":
		match lesson:
			FIRE:
				if game.players[0].creatures[3] != null and game.players[0].creatures[3].id == "furious_phoenix":
					_show_lesson("practice_two")
			FROST:
				if game.buildings_at(0, 1).any(func(entry): return entry[0].id == "blood_fortress"):
					_show_lesson("practice_two")
			GOBBLE:
				if game.tokens(game.players[0].creatures[0], "atk_tok") > 0:
					_show_lesson("practice_two")
			WHUMP:
				if game.players[0].creatures[0].id == "courageous_armourdillo":
					_show_lesson("practice_two")
			FLIP:
				if game.players[0].creatures[1] != null and not game.players[0].creatures[0].flooped:
					_show_lesson("practice_two")
	elif lesson_state == "practice_two":
		match lesson:
			FIRE:
				if game.players[0].creatures[2] != null and game.players[0].creatures[2].id == "fire_dog":
					_show_lesson("practice_done")
			FROST:
				if not game.is_frozen(0, 1):
					_show_lesson("practice_done")
			GOBBLE:
				if game.players[0].creatures[0].id == "darling_cobnoblin":
					_show_lesson("practice_done")
			WHUMP:
				if game.tokens(game.players[0].creatures[0], "atk_tok") > 0:
					_show_lesson("practice_done")
			FLIP:
				if game.players[0].lands[0]["flipped"]:
					_show_lesson("practice_done")


func on_game_event(_event: Dictionary) -> void:
	pass


func hold_combat_end(_p: int) -> bool:
	return false
