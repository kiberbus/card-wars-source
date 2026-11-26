extends SceneTree

const MainScene = preload("res://scenes/main.tscn")

signal _command_done

var main: Control
var failures := 0
var command_done := false


func _initialize() -> void:
	_run_test.call_deferred()


func _run_test() -> void:
	main = MainScene.instantiate()
	root.add_child(main)
	await create_timer(1.0).timeout
	main.start_basic_tutorial()
	await _wait_idle()
	var tutor = main.board.tutorial
	_check(main.game.players[0].hand.size() == 5,
			"Finn starts with exactly five cards")
	tutor._advance()
	tutor._advance()
	tutor._advance()
	await process_frame
	await process_frame
	_check(tutor.guide_panel.visible and tutor.guide_text.text.contains("три вида карт"),
			"the interface lesson explains card properties and types without center-screen cards")
	var hero_panel: Control = main.board.hero_ui["top"]["panel"]
	_check(tutor.guide_panel.position.x + tutor.guide_panel.size.x <= hero_panel.position.x
			and not tutor.guide_panel.get_rect().intersects(tutor.phase_panel.get_rect()),
			"Russian tutorial guide leaves the hero and phase guide visible")
	tutor._advance()
	_check(tutor.step == 38 and tutor.dialogue_layer.visible
			and tutor.dialogue_text.text.contains("Друг, давай играть уже")
			and tutor.dialogue_character.texture != null,
			"Jake interrupts the interface lesson with his portrait and dialogue")
	tutor._advance()
	_check(not tutor.dialogue_layer.visible,
			"Jake's portrait disappears when the player continues")
	var jinn_uid := _hand_uid(0, "struzann_jinn")
	await _issue({"cmd": "play", "uid": jinn_uid, "lane": 0})
	_check(tutor.jinn_lane == 0, "the required Finn summon records its lane")
	await _issue({"cmd": "end_turn"})
	await _wait_step(tutor, 26)
	_check(tutor.guide_text.text.contains("Джейк выставил Лучника Дэна")
			and tutor.guide_text.text.contains("Джинн нанёс Дэну 1")
			and tutor.guide_text.text.contains("Дэн — Джинну 2"),
			"Jake's first-turn summary reports the simultaneous damage")
	tutor._advance()
	await _wait_turn(0, 3)
	_check(main.game.players[1].creatures[0] != null
			and main.game.players[1].creatures[0].id == "archer_dan",
			"Jake scripts Archer Dan opposite the first Finn creature")
	_check(main.game.hp_of(0, 0) == 9 and main.game.hp_of(1, 0) == 5,
			"Jake's Archer and Finn's Jinn both survive their first battle")
	_check(main.game.players[0].hand.any(func(c): return c.id == "gnome_snot"),
			"Finn draws Gnome Snot on turn two")
	tutor._advance()
	await _issue({"cmd": "play", "uid": _hand_uid(0, "gnome_snot"), "lane": -1})
	_check(tutor.step == 25 and main.game.players[0].actions == 1,
			"the post-spell step highlights the one remaining action")
	_check(not tutor.guide_text.text.contains("Радужное"),
			"the remaining-action summary does not introduce the rainbow creature early")
	tutor._advance()
	await _issue({"cmd": "play", "uid": _hand_uid(0, "nice_ice_baby"), "lane": 1})
	_check(tutor.step == 7 and main.board.tutorial_building_targets.size() == 1
			and main.board.tutorial_building_targets[0]["lane"] == 1,
			"the tutorial highlights the building slot below the Baby")
	await _issue({"cmd": "play", "uid": _hand_uid(0, "blood_fortress"), "lane": 1})
	_check(tutor.step == 39 and tutor.dialogue_text.text.contains("БОТАН")
			and tutor.dialogue_character.texture != null,
			"Finn reacts to playing the Blood Fortress")
	tutor._advance()
	await _issue({"cmd": "begin_attack"})
	await _issue({"cmd": "attack", "lane": 1})
	await _issue({"cmd": "attack", "lane": 0})
	_check(tutor.step == 40 and tutor.dialogue_layer.visible
			and tutor.dialogue_text.text.contains("Как бы не так"),
			"Jake responds after Finn's second-turn attacks")
	_check(main.game.hp_of(0, 0) == 7 and main.game.hp_of(1, 0) == 4,
			"Jinn and Archer Dan deal simultaneous damage again in Finn's second-turn battle")
	_check(main.board.main_button.text == "Завершить ход",
			"the combat button changes to End Turn after all attacks")
	tutor._advance()
	_check(tutor.step == 10 and not tutor.dialogue_layer.visible,
			"continuing from Jake's reply restores the normal end-turn prompt")
	main.board._on_main_button()
	await _wait_step(tutor, 11)
	_check(main.game.players[1].creatures[1] != null
			and main.game.players[1].creatures[1].id == "husker_knight",
			"Jake plays Husker Knight opposite the Ice Baby")
	tutor._advance()
	await _wait_turn(0, 5)
	_check(main.game.players[0].discard.any(func(c): return c.id == "nice_ice_baby"),
			"Husker Knight defeats the Ice Baby")
	_check(main.game.players[1].creatures[1].damage == 2,
			"Blood Fortress lets the Ice Baby damage Husker Knight before dying")
	tutor._advance()
	await _issue({"cmd": "play", "uid": _hand_uid(0, "the_pig"), "lane": 2})
	await _issue({"cmd": "floop", "kind": "creature", "lane": 2})
	_check(main.game.atk_of(1, 1) == 3 and main.game.def_of(1, 1) == 6,
			"flipping the first corn field reduces Husker Knight's stats")
	tutor._advance()
	_check(tutor.guide_text.text.contains("заклинание"),
			"the Teleport lesson identifies it as a spell")
	await _choose_command({"cmd": "play", "uid": _hand_uid(0, "teleport"), "lane": -1},
			[{"kind": "creature", "answer": {"p": 0, "lane": 2}},
				{"kind": "lane", "answer": {"p": 0, "lane": 3, "row": "creature"}}])
	_check(tutor.pig_lane == 3, "Teleport moves the flopped Pig to the scripted second lane")
	await _choose_command({"cmd": "play", "uid": _hand_uid(0, "psionic_architect"), "lane": 1},
			[{"kind": "creature", "answer": {"p": 0, "lane": 3}}])
	_check(not main.game.players[0].creatures[3].exhausted,
			"the Architect prepares the Pig")
	await _issue({"cmd": "floop", "kind": "creature", "lane": 3})
	_check(main.game.atk_of(1, 1) == 2 and main.game.def_of(1, 1) == 4,
			"flipping the second corn field further reduces Husker Knight's stats")
	await _wait_step(tutor, 24)
	_check(tutor.dialogue_layer.visible == false
			and tutor.guide_text.text.contains("Второе поле перевёрнуто"),
			"Finn's brief reaction ends and the second-field explanation appears")
	tutor._advance()
	await _issue({"cmd": "begin_attack"})
	await _issue({"cmd": "attack", "lane": 0})
	await _issue({"cmd": "attack", "lane": 1})
	_check(tutor.step == 42, "the third-turn battle requires both prepared creatures")
	_check(main.game.players[1].creatures[1] == null
			and main.game.players[1].discard.any(func(c): return c.id == "husker_knight"),
			"the Architect defeats the weakened Husker Knight")
	_check(main.game.players[1].creatures[0] == null
			and main.game.players[1].discard.any(func(c): return c.id == "archer_dan"),
			"Finn defeats Archer Dan during the third-turn battle")
	_check(main.board.main_button.text == "Завершить ход",
			"the combat button changes to End Turn after the third-turn attacks")
	_check(tutor.step == 42 and tutor.dialogue_text.text == "МОЯ КУКУРУЗА!",
			"Jake shouts about his corn after Finn's third-turn attack")
	tutor._advance()
	var jake_journal_start: int = main.game.journal.size()
	main.board._on_main_button()
	await _wait_message(tutor, "Кукутузика")
	tutor._advance()
	await _wait_message(tutor, "Стена початков атакует")
	_check(main.game.hp_of(0, 1) == 2,
			"Jake's Wall of Ears hits the Architect for two damage, leaving two health")
	tutor._advance()
	await _wait_turn(0, 7)
	_check(tutor.guide_text.text.contains("Сыграй «Крутого пса» вместо Архитектора"),
			"the final lesson explains why to replace the damaged Architect")
	var jake_played_cards := 0
	for i in range(jake_journal_start, main.game.journal.size()):
		var entry: Dictionary = main.game.journal[i]
		if entry.get("t") == "cmd" and entry.get("p") == 1 \
				and entry.get("c", {}).get("cmd", "") == "play":
			jake_played_cards += 1
	_check(jake_played_cards == 2
			and main.game.players[1].creatures[0].id == "corn_dog"
			and main.game.players[1].creatures[1].id == "wall_of_ears",
			"Jake plays only Corn Dog opposite the Jinn and Wall of Ears opposite the Architect")
	await _issue({"cmd": "play", "uid": _hand_uid(0, "cool_dog"), "lane": 1})
	_check(main.game.players[0].creatures[1].id == "cool_dog"
			and main.game.players[0].discard.any(func(c): return c.id == "psionic_architect"),
			"Cool Dog replaces the Architect and sends it to the discard pile")
	await _issue({"cmd": "begin_attack"})
	for lane in [0, 1, 3]:
		await _issue({"cmd": "attack", "lane": lane})
	_check(tutor.step == tutor.Step.JAKE_FINAL_DIALOGUE and tutor.dialogue_layer.visible
			and tutor.dialogue_text.text == "Ха, я поддавался новичку. Но сегодня я уже устал, завтра сыграем всерьёз. Потренируйся пока с Бимо."
			and tutor.dialogue_next_button.visible
			and main.game.turn_number == 7 and main.game.phase == "attack",
			"Jake's final scene appears after the attacks without continuing the match")
	await process_frame
	await process_frame
	_check(tutor.dialogue_text.get_visible_line_count() == tutor.dialogue_text.get_line_count()
			and tutor.dialogue_panel.position.y + tutor.dialogue_panel.size.y <= 1080.0,
			"Jake's final dialogue fits its panel")
	tutor.dialogue_next_button.pressed.emit()
	_check(tutor.step == tutor.Step.FINN_FINAL_DIALOGUE
			and tutor.dialogue_text.text == "Хорошо, брат, завтра я буду готов."
			and tutor.dialogue_next_button.visible and main.game != null,
			"Finn replies before the tutorial ends")
	tutor.dialogue_next_button.pressed.emit()
	_check(main.board == null and main.game == null,
			"continuing after Finn's reply returns to the main menu")
	quit(1 if failures > 0 else 0)


func _issue(command: Dictionary) -> void:
	command_done = false
	call_deferred("_issue_background", command)
	while not command_done:
		await _command_done


func _issue_background(command: Dictionary) -> void:
	await main.board._issue_as(0, command)
	command_done = true
	_command_done.emit()


func _choose_command(command: Dictionary, choices: Array) -> void:
	command_done = false
	call_deferred("_issue_background", command)
	for choice: Dictionary in choices:
		if not await _wait_choice(String(choice["kind"])):
			if choice["kind"] == "creature" and main.board._choice != null \
					and main.board._choice.get("kind", "") == "lane":
				continue
			break
		if main.board.tutorial.step == 17:
			_check(not main.board.skip_button.is_visible_in_tree(),
					"optional choice skipping is hidden during the guided tutorial")
		await process_frame
		main.board._resolve_choice(choice["answer"])
	while not command_done:
		await _command_done


func _wait_choice(kind: String) -> bool:
	for i in 200:
		if main.board._choice != null and main.board._choice.get("kind", "") == kind:
			return true
		if kind == "creature" and main.board._choice != null \
				and main.board._choice.get("kind", "") == "lane":
			return false
		if command_done:
			_check(false, "engine opened a %s choice" % kind)
			return false
		await create_timer(0.05).timeout
	printerr("Expected choice kind ", kind, ", actual request: ", main.board._choice)
	_check(false, "engine choice prompt appeared")
	return false


func _wait_idle() -> void:
	for i in 200:
		if main.board != null and not main.board._busy:
			return
		await create_timer(0.05).timeout
	_check(false, "board became ready")


func _wait_turn(player: int, turn: int) -> void:
	for i in 200:
		if main.game.turn_player == player and main.game.turn_number == turn \
				and not main.board._busy and main.game.players[player].actions > 0:
			return
		await create_timer(0.05).timeout
	_check(false, "scripted turn %d for player %d began" % [turn, player])


func _wait_step(tutor, expected: int) -> void:
	for i in 200:
		if tutor.step == expected:
			return
		await create_timer(0.05).timeout
	_check(false, "tutorial reached step %d" % expected)


func _hand_uid(player: int, id: String) -> int:
	for card in main.game.players[player].hand:
		if card.id == id:
			return card.uid
	_check(false, "card %s is in player %d's hand" % [id, player])
	return -1


func _wait_message(tutor, text: String) -> void:
	for i in 200:
		if tutor.guide_text.text.contains(text):
			return
		await create_timer(0.05).timeout
	_check(false, "tutorial displayed message containing %s" % text)


func _check(condition: bool, description: String) -> void:
	if condition:
		print("ok   ", description)
	else:
		failures += 1
		push_error("FAIL: " + description)
