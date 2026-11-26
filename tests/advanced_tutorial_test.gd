extends SceneTree

const MainScene = preload("res://scenes/main.tscn")
const TutorialText = preload("res://scripts/ui/tutorial_text.gd")
const TutorialCardText = preload("res://scripts/ui/tutorial_card_text.gd")
const Phone = preload("res://scripts/ui/phone.gd")
const Game = preload("res://scripts/core/game.gd")
const AdvancedTutorial = preload("res://scripts/ui/advanced_tutorial.gd")

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
		await create_timer(0.3).timeout
		tutor = main.board.tutorial
		_check(tutor.lesson == tutor.FROST and main.game.is_frozen(0, 0), "frost lesson starts frozen")
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
		var building = main.game._take_tutorial_card(main.game.players[0].deck, "blood_fortress")
		_check(building != null, "frost scenario has a building available for the rules check")
		if building != null:
			main.game.players[0].hand.append(building)
			_check(main.game.can_play(0, building.uid, 0), "frozen land still permits buildings")
			main.game.players[0].hand.erase(building)
			main.game.players[0].deck.append(building)
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
		await create_timer(0.3).timeout
		tutor = main.board.tutorial
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
		await create_timer(0.3).timeout
		tutor = main.board.tutorial
		_check(tutor.lesson == tutor.FLIP, "flipped-land lesson starts")
		_check_translation(tutor, language, "advanced_flip")
		await _check_guide(tutor)
		_check(main.game.land_count(1, "corn") == 4 and main.game.atk_of(1, 1) == 4
				and main.game.def_of(1, 1) == 8, "knight starts with four cornfields")
		var opposite = main.game.players[1].creatures[0]
		_check(not tutor.allow_command(0, {"cmd": "floop", "kind": "creature", "lane": 0, "hero": true}),
				"the lesson requires the pig's own floop")
		await _command({"cmd": "floop", "kind": "creature", "lane": 0})
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
