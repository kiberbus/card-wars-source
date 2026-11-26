extends SceneTree

const MainScene = preload("res://scenes/main.tscn")
const TutorialText = preload("res://scripts/ui/tutorial_text.gd")
const TutorialCardText = preload("res://scripts/ui/tutorial_card_text.gd")
const Phone = preload("res://scripts/ui/phone.gd")
const Game = preload("res://scripts/core/game.gd")
const AdvancedTutorial = preload("res://scripts/ui/advanced_tutorial.gd")
const CardView = preload("res://scripts/ui/card_view.gd")

signal command_done

var main: Control
var failures := 0
var finished := false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	main = MainScene.instantiate()
	root.add_child(main)
	await _check_gobble_mechanics()
	await create_timer(0.5).timeout
	var locale := TranslationServer.get_locale()
	var old_phone := Phone.active
	var old_layout: bool = main.phone_layout
	Phone.active = true
	main.phone_layout = true
	main.show_tutorial_menu()
	await process_frame
	var phone_advanced := _button("Продвинутое обучение")
	_check(phone_advanced != null and not phone_advanced.disabled, "phone menu offers advanced tutorial")
	if phone_advanced != null:
		phone_advanced.pressed.emit()
		await create_timer(0.25).timeout
		_check(_button("한국어") != null, "phone language picker opens for advanced tutorial")
		var back := _button("Назад")
		if back != null:
			back.pressed.emit()
			await create_timer(0.25).timeout
		var menu_back := _button("Назад")
		if menu_back != null:
			menu_back.pressed.emit()
			await create_timer(0.25).timeout
	Phone.active = old_phone
	main.phone_layout = old_layout
	for language: String in ["ru", "en", "ko"]:
		main.show_tutorial_menu()
		await process_frame
		var advanced := _button("Продвинутое обучение")
		_check(advanced != null and not advanced.disabled, "advanced tutorial is available")
		if advanced == null:
			quit(1)
			return
		advanced.pressed.emit()
		await create_timer(0.25).timeout
		var choice := _button({"ru": "Русский", "en": "English", "ko": "한국어"}[language])
		_check(choice != null, "advanced language picker offers " + language)
		if choice == null:
			quit(1)
			return
		choice.pressed.emit()
		await create_timer(0.4).timeout
		var tutor = main.board.tutorial
		_check(tutor.lesson == tutor.FIRE and tutor.language == language, "fire lesson starts in " + language)
		if DisplayServer.get_name() == "headless":
			_check(main._warming.is_empty() and CardView._loading.is_empty(),
					"tutorial does not start headless background texture loads")
			_check(main.board._hero_card_texture("bmo", true) != null,
					"BMO's hero card remains available in headless mode")
		_check(main.game.players[0].hero_card == "finn" and main.game.players[1].hero_card == "bmo",
				"Finn and BMO are the actual heroes")
		await _dialogue(tutor, language, "intro_finn", "advanced_intro_finn", AdvancedTutorial.FINN_ADVANCED)
		await _dialogue(tutor, language, "intro_welcome", "advanced_intro_welcome", AdvancedTutorial.BMO_DEFAULT)
		await _dialogue(tutor, language, "intro_bmo", "advanced_intro_fire", AdvancedTutorial.BMO_FIRE)
		await _check_guide(tutor)
		if language != "ru":
			_check(tutor.guide_text.text == TutorialText.TEXT[language]["advanced_fire"], "fire instruction is translated")
		var fire_uid: int = main.game.players[0].hand[0].uid
		await _check_property(tutor, "hot_shot", language)
		await _check_property(tutor, "flameingo_blazeling", language)
		main.board._select(fire_uid)
		_check(_button("Сыграть «Меткий выстрел»") != null, "fire spell can be played from the card menu")
		main.board.context_menu.visible = false
		main.board._clear_selection()
		_check(not tutor.allow_command(0, {"cmd": "draw"}), "unrelated fire commands are blocked")
		_start_command({"cmd": "play", "uid": fire_uid, "lane": -1})
		if not await _wait_choice("creature"):
			quit(1)
			return
		_check(not tutor.allow_choice(main.board._choice, {"p": 0, "lane": 1}), "wrong fire target is rejected")
		main.board._resolve_choice({"p": 1, "lane": 0})
		await _wait_command()
		var target = main.game.players[1].creatures[0]
		_check(tutor.lesson_state == "complete" and main.game.tokens(target, "burn") == 1
				and target.damage == 2, "fire uses real spell damage and a fire token")
		_check_translation(tutor, language, "advanced_fire_done")
		await _check_guide(tutor)
		tutor.next_button.pressed.emit()
		_check(tutor.lesson_state == "details", "fire examples appear before the next lesson")
		_check_translation(tutor, language, "advanced_fire_examples")
		_check(tutor.guide_text.text.contains("Яростный феникс")
				and tutor.guide_text.text.contains("Огненный пёс"), "fire examples retain card names")
		await _check_guide(tutor)
		tutor.next_button.pressed.emit()
		_check(tutor.lesson_state == "practice_one", "fire has extra phoenix practice")
		_check_translation(tutor, language, "advanced_fire_practice_one")
		await _check_guide(tutor)
		await _check_property(tutor, "furious_phoenix", language)
		await _command({"cmd": "play", "uid": _hand_uid("furious_phoenix"), "lane": 3})
		_check(tutor.lesson_state == "practice_two" and main.game.atk_of(0, 3) == 2,
				"phoenix gains attack from a fire token")
		_check_translation(tutor, language, "advanced_fire_practice_two")
		await _check_guide(tutor)
		await _check_property(tutor, "fire_dog", language)
		_start_command({"cmd": "play", "uid": _hand_uid("fire_dog"), "lane": 2})
		if not await _wait_choice("creature"):
			quit(1)
			return
		_check(not tutor.allow_choice(main.board._choice, null), "fire dog choice cannot be skipped")
		main.board._resolve_choice({"p": 1, "lane": 0})
		await _wait_command()
		_check(tutor.lesson_state == "practice_done" and target.damage == 3,
				"fire dog deals damage based on fire tokens")
		_check_translation(tutor, language, "advanced_fire_practice_done")
		await _check_guide(tutor)
		tutor.next_button.pressed.emit()
		await create_timer(0.3).timeout
		tutor = main.board.tutorial
		_check(tutor.lesson == tutor.FROST and main.game.is_frozen(0, 0), "frost lesson starts frozen")
		_check(main.game.players[1].hero_card == "bmo", "BMO remains the opponent for frost")
		await _dialogue(tutor, language, "intro_bmo", "advanced_intro_frost", AdvancedTutorial.BMO_FROST)
		var existing = main.game.players[0].creatures[1]
		_check(existing != null and main.game.is_frozen(0, 1), "a creature remains on a frozen land")
		await main.board.run_engine(func():
			await main.game.thaw(0, 1)
			await main.game.freeze(0, 1))
		_check(main.game.players[0].creatures[1] == existing and main.game.is_frozen(0, 1),
				"freezing an occupied land does not remove its creature")
		_check_translation(tutor, language, "advanced_frost")
		await _check_guide(tutor)
		var baby = main.game.players[0].hand[1]
		_check(not main.game.can_play(0, baby.uid, 0), "frozen land blocks playing a creature")
		var building = main.game.card(_hand_uid("blood_fortress"))
		_check(building != null, "frost scenario has a building available for the rules check")
		if building != null:
			_check(main.game.can_play(0, building.uid, 0), "frozen land still permits buildings")
		main.board._frozen_land(0)
		_check(_button("Растопить лёд: сбросить карту") != null, "frozen land offers the thaw action")
		main.board.context_menu.visible = false
		_start_command({"cmd": "thaw", "lane": 0})
		if not await _wait_choice("hand_card"):
			quit(1)
			return
		_check(not tutor.allow_choice(main.board._choice, baby.uid), "wrong discard is rejected")
		var discard_uid: int = main.game.players[0].hand[0].uid
		main.board._resolve_choice(discard_uid)
		await _wait_command()
		_check(tutor.lesson_state == "play" and not main.game.is_frozen(0, 0)
				and main.game.players[0].actions == 2, "discarding thaws without spending an action")
		_check_translation(tutor, language, "advanced_frost_play")
		await _check_guide(tutor)
		await _command({"cmd": "play", "uid": baby.uid, "lane": 0})
		_check(tutor.lesson_state == "complete" and main.game.players[0].creatures[0] == baby,
				"creature can be played after thawing")
		_check_translation(tutor, language, "advanced_frost_done")
		await _check_guide(tutor)
		tutor.next_button.pressed.emit()
		_check(tutor.lesson_state == "practice_one", "frost has extra building practice")
		_check_translation(tutor, language, "advanced_frost_practice_one")
		await _check_guide(tutor)
		await _command({"cmd": "play", "uid": building.uid, "lane": 1})
		_check(tutor.lesson_state == "practice_two" and main.game.is_frozen(0, 1)
				and not main.game.buildings_at(0, 1).is_empty(), "building is played on frozen land")
		_check_translation(tutor, language, "advanced_frost_practice_two")
		await _check_guide(tutor)
		main.board._frozen_land(1)
		_check(_button("Растопить лёд: сбросить карту") != null,
				"occupied frozen land offers the thaw action")
		main.board.context_menu.visible = false
		await _command({"cmd": "thaw", "lane": 1})
		_check(tutor.lesson_state == "practice_done" and not main.game.is_frozen(0, 1)
				and main.game.players[0].creatures[1] == existing, "second thaw keeps the creature")
		_check_translation(tutor, language, "advanced_frost_practice_done")
		await _check_guide(tutor)
		tutor.next_button.pressed.emit()
		await create_timer(0.3).timeout
		tutor = main.board.tutorial
		_check(main.game.players[1].hero_card == "bmo", "BMO remains the opponent for gobble")
		await _dialogue(tutor, language, "intro_bmo", "advanced_intro_gobble", AdvancedTutorial.BMO_GOBBLE)
		var old = main.game.players[0].creatures[0]
		var replacement = main.game.players[0].hand[0]
		_check(tutor.lesson == tutor.GOBBLE and main.game.gobbles(old), "gobble lesson starts with a gobble creature")
		_check_translation(tutor, language, "advanced_gobble")
		await _check_guide(tutor)
		await _check_property(tutor, "darling_cobnoblin", language)
		await _check_property(tutor, "treasured_cobnoblin", language)
		main.board._select(replacement.uid)
		_check(main.board._selected_uid == replacement.uid and main.game.can_play(0, replacement.uid, 0),
				"replacement can be selected and played in the gobble lane")
		main.board._clear_selection()
		await _command({"cmd": "play", "uid": replacement.uid, "lane": 0})
		_check(tutor.lesson_state == "complete" and replacement.under.has(old)
				and main.game.atk_of(0, 0) == 3 and main.game.def_of(0, 0) == 7,
				"replacing the gobble creature transfers its stats")
		_check_translation(tutor, language, "advanced_gobble_done")
		await _check_guide(tutor)
		tutor.next_button.pressed.emit()
		_check(tutor.lesson_state == "details", "gobble details appear before the next lesson")
		_check_translation(tutor, language, "advanced_gobble_details")
		await _check_guide(tutor)
		tutor.next_button.pressed.emit()
		_check(tutor.lesson_state == "practice_one", "gobble has extra floop practice")
		_check_translation(tutor, language, "advanced_gobble_practice_one")
		await _check_guide(tutor)
		_start_command({"cmd": "floop", "kind": "creature", "lane": 1})
		if not await _wait_choice("creature"):
			quit(1)
			return
		main.board._resolve_choice({"p": 0, "lane": 0})
		await _wait_command()
		_check(tutor.lesson_state == "practice_two" and main.game.tokens(replacement, "atk_tok") == 1,
				"gobble creature receives an attack token")
		_check_translation(tutor, language, "advanced_gobble_practice_two")
		await _check_guide(tutor)
		await _command({"cmd": "play", "uid": _hand_uid("darling_cobnoblin"), "lane": 0})
		var final_creature = main.game.players[0].creatures[0]
		_check(tutor.lesson_state == "practice_done" and final_creature.under.has(replacement)
				and main.game.atk_of(0, 0) == 6 and main.game.def_of(0, 0) == 10
				and main.game.tokens(final_creature, "atk_tok") == 1,
				"gobble triggers a second time and transfers accumulated stats")
		_check_translation(tutor, language, "advanced_gobble_practice_done")
		await _check_guide(tutor)
		tutor.next_button.pressed.emit()
		await create_timer(0.3).timeout
		tutor = main.board.tutorial
		_check(tutor.lesson == tutor.WHUMP and main.game.players[1].hero_card == "bmo",
				"whump follows gobble with BMO as the opponent")
		await _dialogue(tutor, language, "intro_bmo", "advanced_intro_whump", AdvancedTutorial.BMO_GOBBLE)
		_check_translation(tutor, language, "advanced_whump")
		await _check_guide(tutor)
		await _check_property(tutor, "genteel_armourdillo", language)
		await _check_property(tutor, "valiant_armourdillo", language)
		var old_armourdillo = main.game.players[0].creatures[0]
		var valiant = main.game.card(_hand_uid("valiant_armourdillo"))
		_check(main.game.cost_of(0, valiant) == 5 and main.game.cost_of(0, valiant, 0) == 2
				and not main.game.can_play(0, valiant.uid, 2) and main.game.can_play(0, valiant.uid, 0),
				"whump makes the 5-cost creature playable for 2 when replacing a 3-cost creature")
		main.board._select(valiant.uid)
		_check(main.board._selected_uid == valiant.uid, "discounted armourdillo can be selected in the UI")
		main.board._clear_selection()
		_check(not tutor.allow_command(0, {"cmd": "play", "uid": valiant.uid, "lane": 2}),
				"whump requires the highlighted lane")
		await _command({"cmd": "play", "uid": valiant.uid, "lane": 0})
		_check(tutor.lesson_state == "complete" and main.game.players[0].actions == 0
				and main.game.players[0].discard.has(old_armourdillo) and valiant.under.is_empty()
				and main.game.players[1].creatures[0] == null,
				"whump pays 2, discards the old creature and triggers the entry ability")
		_check_translation(tutor, language, "advanced_whump_done")
		await _check_guide(tutor)
		tutor.next_button.pressed.emit()
		_check(tutor.lesson_state == "details", "whump explains printed costs and replacement")
		_check_translation(tutor, language, "advanced_whump_details")
		await _check_guide(tutor)
		tutor.next_button.pressed.emit()
		_check(tutor.lesson_state == "practice_one", "whump has extra replacement practice")
		_check_translation(tutor, language, "advanced_whump_practice_one")
		await _check_guide(tutor)
		await _check_property(tutor, "courageous_armourdillo", language)
		var courageous = main.game.card(_hand_uid("courageous_armourdillo"))
		_check(main.game.cost_of(0, courageous, 0) == 0 and main.game.can_play(0, courageous.uid, 0),
				"whump uses printed cost and cannot go below zero")
		_check(main.game.lands_needed(0, courageous, 0) == 1,
				"a free whump creature still requires one matching land")
		main.board._select(courageous.uid)
		_check(main.board._selected_uid == courageous.uid, "free armourdillo can be selected in the UI")
		main.board._clear_selection()
		await _command({"cmd": "play", "uid": courageous.uid, "lane": 0})
		_check(tutor.lesson_state == "practice_two" and main.game.players[0].actions == 0
				and main.game.players[0].discard.has(valiant) and courageous.under.is_empty(),
				"second whump replacement is free and does not inherit stats")
		_check_translation(tutor, language, "advanced_whump_practice_two")
		await _check_guide(tutor)
		_start_command({"cmd": "floop", "kind": "creature", "lane": 1})
		if not await _wait_choice("creature"):
			quit(1)
			return
		_check(not tutor.allow_choice(main.board._choice, {"p": 0, "lane": 1}),
				"whump practice requires the armourdillo as the target")
		main.board._resolve_choice({"p": 0, "lane": 0})
		await _wait_command()
		_check(tutor.lesson_state == "practice_done" and main.game.tokens(courageous, "atk_tok") == 1,
				"whump practice applies the attack token")
		_check_translation(tutor, language, "advanced_whump_practice_done")
		await _check_guide(tutor)
		tutor.next_button.pressed.emit()
		await create_timer(0.3).timeout
		tutor = main.board.tutorial
		_check(tutor.lesson == tutor.FLIP, "flipped-land lesson starts")
		_check(main.game.players[1].hero_card == "bmo", "BMO remains the opponent for flipping")
		await _dialogue(tutor, language, "intro_bmo", "advanced_intro_flip", AdvancedTutorial.BMO_DEFAULT)
		_check_translation(tutor, language, "advanced_flip")
		await _check_guide(tutor)
		_check(main.game.land_count(1, "corn") == 4 and main.game.atk_of(1, 1) == 4
				and main.game.def_of(1, 1) == 8, "knight starts with four cornfields")
		var opposite = main.game.players[1].creatures[0]
		_check(not tutor.allow_command(0, {"cmd": "floop", "kind": "creature", "lane": 0, "hero": true}),
				"the lesson requires the pig's own floop")
		_start_command({"cmd": "floop", "kind": "creature", "lane": 0})
		if not await _wait_choice("land"):
			quit(1)
			return
		_check(not tutor.allow_choice(main.board._choice, {"p": 0, "lane": 0}),
				"first flip requires BMO's land")
		main.board._resolve_choice({"p": 1, "lane": 0})
		await _wait_command()
		_check(tutor.lesson_state == "complete" and main.game.players[1].lands[0]["flipped"]
				and main.game.land_type(1, 0) == "" and main.game.land_count(1, "corn") == 3,
				"pig flips the land and it stops counting as corn")
		_check(main.game.players[1].creatures[0] == opposite and main.game.atk_of(1, 1) == 3
				and main.game.def_of(1, 1) == 6, "creature stays and the knight loses its land bonus")
		_check_translation(tutor, language, "advanced_flip_done")
		await _check_guide(tutor)
		tutor.next_button.pressed.emit()
		_check(tutor.lesson_state == "details", "flipped-land explanation follows the example")
		_check_translation(tutor, language, "advanced_flip_details")
		await _check_guide(tutor)
		tutor.next_button.pressed.emit()
		_check(tutor.lesson_state == "practice_one", "flipping has extra preparation practice")
		_check_translation(tutor, language, "advanced_flip_practice_one")
		await _check_guide(tutor)
		_start_command({"cmd": "play", "uid": _hand_uid("psionic_architect"), "lane": 1})
		if not await _wait_choice("creature"):
			quit(1)
			return
		_check(not tutor.allow_choice(main.board._choice, null), "preparing the pig cannot be skipped")
		main.board._resolve_choice({"p": 0, "lane": 0})
		await _wait_command()
		_check(tutor.lesson_state == "practice_two" and not main.game.players[0].creatures[0].flooped,
				"architect readies the pig")
		_check_translation(tutor, language, "advanced_flip_practice_two")
		await _check_guide(tutor)
		await _command({"cmd": "floop", "kind": "creature", "lane": 0})
		_check(tutor.lesson_state == "practice_done" and main.game.players[0].lands[0]["flipped"],
				"pig flips the player's land")
		_check_translation(tutor, language, "advanced_flip_practice_done")
		await _check_guide(tutor)
		tutor.next_button.pressed.emit()
		await _dialogue(tutor, language, "outro_finn", "advanced_outro_finn", AdvancedTutorial.FINN_ADVANCED)
		await _dialogue(tutor, language, "outro_bmo", "advanced_outro_bmo", AdvancedTutorial.BMO_DEFAULT)
		await create_timer(0.3).timeout
		_check(main.board == null and main.game == null and _button("Обучение") != null,
				"finishing returns to the main menu")
		_check(TranslationServer.get_locale() == locale, "advanced language does not change the game locale")
	if failures == 0:
		print("PASS: advanced tutorial completed in all three languages")
	quit(1 if failures else 0)


func _check_gobble_mechanics() -> void:
	var g = Game.new()
	if not AdvancedTutorial.prepare(g, AdvancedTutorial.GOBBLE):
		_check(false, "gobble scenario can be prepared")
		return
	var old = g.players[0].creatures[0]
	var replacement = g.players[0].hand[0]
	old.damage = 1
	old.perm_atk = 1
	old.perm_def = 2
	old.flags["burn"] = 1
	old.flags["atk_tok"] = 1
	await g.run_command(0, {"cmd": "play", "uid": replacement.uid, "lane": 0})
	_check(replacement.under.has(old) and replacement.damage == 1
			and g.tokens(replacement, "burn") == 1 and g.tokens(replacement, "atk_tok") == 1,
			"gobble transfers damage and both types of tokens")
	_check(g.atk_of(0, 0) == 5 and g.def_of(0, 0) == 9,
			"gobble transfers base stats and permanent bonuses")
	_check(not g.texts(replacement, 0, "creature", 0).has("darling_cobnoblin"),
			"gobble does not transfer the replaced card's abilities")
	await g.destroy_creature(0, 0)
	_check(g.players[0].discard.has(old), "card under a creature goes to discard when it leaves")


func _check_translation(tutor, language: String, key: String) -> void:
	if language != "ru":
		_check(tutor.guide_text.text == TutorialText.TEXT[language][key], key + " uses the selected language")


func _dialogue(tutor, language: String, state: String, key: String, portrait: Texture2D = null) -> void:
	_check(tutor.lesson_state == state and tutor.dialogue_layer.visible, state + " dialogue is visible")
	_check(tutor.dialogue_character.visible == (portrait != null)
			and tutor.dialogue_character.texture == portrait, state + " uses the requested portrait")
	if language != "ru":
		_check(tutor.dialogue_text.text == TutorialText.TEXT[language][key], key + " is translated")
	await process_frame
	await process_frame
	_check(tutor.dialogue_text.get_visible_line_count() == tutor.dialogue_text.get_line_count(),
			state + " dialogue fits its panel")
	var old_phone := Phone.active
	Phone.active = true
	main.board.set_side_room(0.0, true)
	await process_frame
	await process_frame
	_check(tutor.dialogue_text.get_visible_line_count() == tutor.dialogue_text.get_line_count(),
			state + " dialogue fits on phone")
	Phone.active = old_phone
	tutor.dialogue_next_button.pressed.emit()


func _hand_uid(id: String) -> int:
	for card in main.game.players[0].hand:
		if card.id == id:
			return card.uid
	return -1


func _check_property(tutor, id: String, language: String) -> void:
	if language == "ru":
		return
	tutor.show_card_property(id)
	await process_frame
	await process_frame
	_check(tutor.card_property_panel.visible
			and tutor.card_property_text.text == TutorialCardText.ADVANCED_TEXT[id][language],
			"advanced card property is translated for " + id)
	_check(tutor.card_property_text.get_visible_line_count() == tutor.card_property_text.get_line_count()
			and tutor.card_property_panel.position.y + tutor.card_property_panel.size.y <= 836,
			"advanced card property fits for " + id)


func _check_guide(tutor) -> void:
	await process_frame
	await process_frame
	_check(tutor.guide_text.get_visible_line_count() == tutor.guide_text.get_line_count()
			and tutor.guide_panel.position.y + tutor.guide_panel.size.y <= 1080.0,
			"advanced instruction fits the guide")
	var old_phone := Phone.active
	Phone.active = true
	main.board.set_side_room(0.0, true)
	await process_frame
	await process_frame
	var right: Control = main.board.hero_ui["top"]["panel"]
	_check(tutor.guide_panel.position.x + tutor.guide_panel.size.x <= right.position.x,
			"advanced guide stays clear of the right interface on phone")
	_check(tutor.guide_text.get_visible_line_count() == tutor.guide_text.get_line_count()
			and tutor.guide_panel.position.y + tutor.guide_panel.size.y <= 1080.0,
			"advanced instruction fits on phone")
	Phone.active = old_phone


func _start_command(command: Dictionary) -> void:
	finished = false
	_run_command.call_deferred(command)


func _run_command(command: Dictionary) -> void:
	await main.board._issue_as(0, command)
	finished = true
	command_done.emit()


func _wait_command() -> void:
	while not finished:
		await command_done


func _command(command: Dictionary) -> void:
	_start_command(command)
	await _wait_command()


func _wait_choice(kind: String) -> bool:
	for i in 200:
		if main.board._choice != null and main.board._choice.get("kind") == kind:
			return true
		await create_timer(0.05).timeout
	_check(false, "expected %s choice" % kind)
	return false


func _button(text: String) -> Button:
	for node: Node in main.find_children("*", "Button", true, false):
		var button := node as Button
		if button.text == text and button.is_visible_in_tree() \
				and button.mouse_filter != Control.MOUSE_FILTER_IGNORE:
			return button
	return null


func _check(condition: bool, description: String) -> void:
	if not condition:
		failures += 1
		push_error("FAIL: " + description)
