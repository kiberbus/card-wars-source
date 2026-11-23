extends SceneTree

const MainScene := preload("res://scenes/main.tscn")

var main: Control
var failures := 0


func _initialize() -> void:
	main = MainScene.instantiate()
	root.add_child(main)
	_check_menu.call_deferred()


func _button(text: String) -> Button:
	for node: Node in main.find_children("*", "Button", true, false):
		var button := node as Button
		if button != null and button.text == text and button.is_visible_in_tree():
			return button
	return null


func _check_menu() -> void:
	await process_frame
	var tutorial := _button("Обучение")
	_check(tutorial != null, "main menu has an Обучение button")
	if tutorial != null:
		tutorial.pressed.emit()
		await process_frame
		_check(_button("Базовое обучение") != null, "tutorial submenu has Basic Tutorial")
		var advanced := _button("Продвинутое обучение")
		_check(advanced != null and advanced.disabled, "advanced tutorial is disabled")
		var trainer := _button("Тренажёр")
		_check(trainer != null and trainer.disabled, "trainer is disabled")
		_check(_button("Правила игры") == null and _button("Управление") == null,
				"tutorial submenu contains only the requested modes")
		var back := _button("Назад")
		_check(back != null, "tutorial submenu has a back button")
		if back != null:
			back.pressed.emit()
			await process_frame
			_check(_button("Обучение") != null, "back returns to the main menu")
		var entry := _button("Обучение")
		if entry != null:
			entry.pressed.emit()
			await process_frame
			var basic := _button("Базовое обучение")
			if basic != null:
				basic.pressed.emit()
				await create_timer(2.0).timeout
				_check(main._mode == "tutorial" and main.board != null,
						"Basic Tutorial opens its dedicated Finn-vs-Jake match")
				_check(main.game.players[0].hand.size() == 5 and main.game.turn_player == 0,
						"tutorial starts with exactly five cards in Finn's hand")
				var tutor = main.board.tutorial
				_check(_button("Пропустить") == null, "tutorial has no Skip button")
				tutor._advance()
				tutor._advance()
				tutor._advance()
				tutor._advance()
				tutor._advance()
				var jinn_uid := -1
				for card in main.game.players[0].hand:
					if card.id == "struzann_jinn":
						jinn_uid = card.uid
				if jinn_uid >= 0:
					await main.board._issue_as(0, {"cmd": "play", "uid": jinn_uid, "lane": 0})
					_check(main.game.players[0].creatures[0] != null
							and main.game.players[0].creatures[0].id == "struzann_jinn",
							"tutorial accepts the required first-turn summon")
					await main.board._issue_as(0, {"cmd": "end_turn"})
					for i in 200:
						if tutor.step == 26:
							break
						await create_timer(0.1).timeout
					_check(tutor.step == 26, "Jake's first-turn summary appears")
					tutor._advance()
					for i in 80:
						if main.game.turn_player == 0 and main.game.turn_number == 3 \
								and main.game.players[0].hand.any(func(card): return card.id == "gnome_snot") \
								and not main.board._busy:
							break
						await create_timer(0.1).timeout
					_check(main.game.turn_player == 0 and main.game.turn_number == 3,
							"scripted Jake turn returns control for Finn's second turn")
					_check(main.game.players[1].creatures[0] != null
							and main.game.players[1].creatures[0].id == "archer_dan",
							"Jake plays Archer Dan opposite Finn's first creature")
					var jinn_hp: int = main.game.hp_of(0, 0)
					var archer_hp: int = main.game.hp_of(1, 0)
					_check(jinn_hp == 9 and archer_hp == 5,
							"Jinn and Archer Dan survive their simultaneous fight (Jinn %d, Archer %d)" % [
								jinn_hp, archer_hp])
					_check(main.game.players[0].hand.any(func(card): return card.id == "gnome_snot"),
							"Finn draws Gnome Snot on his second turn")
				else:
					_check(false, "Finn's scripted opening hand contains Struzann Djinn")
				main.show_title()
	quit(1 if failures > 0 else 0)


func _check(condition: bool, description: String) -> void:
	if not condition:
		failures += 1
		push_error("FAIL: " + description)
