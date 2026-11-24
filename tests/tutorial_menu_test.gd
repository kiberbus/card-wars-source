extends SceneTree

const MainScene := preload("res://scenes/main.tscn")
const Phone = preload("res://scripts/ui/phone.gd")
const WoodUI = preload("res://scripts/ui/wood_ui.gd")

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
		_check_tutorial_labels(tutorial)
		var old_phone := Phone.active
		var old_layout: bool = main.phone_layout
		var old_font_scale := WoodUI.font_scale
		Phone.active = true
		main.phone_layout = true
		WoodUI.font_scale = 1.3
		main.show_title()
		await process_frame
		tutorial = _button("Обучение")
		_check(tutorial != null, "phone menu has a tutorial button at larger font size")
		if tutorial != null:
			_check_tutorial_labels(tutorial)
		Phone.active = old_phone
		main.phone_layout = old_layout
		WoodUI.font_scale = old_font_scale
		main.show_title()
		await process_frame
		tutorial = _button("Обучение")
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
			await create_timer(0.25).timeout
		var entry := _button("Обучение")
		if entry != null:
			entry.pressed.emit()
			await process_frame
			var basic := _button("Базовое обучение")
			if basic != null:
				basic.pressed.emit()
				await process_frame
				_check(_button("Русский") != null and _button("English") != null
						and _button("한국어") != null,
						"basic tutorial offers Russian, English and Korean")
				await create_timer(0.25).timeout
				var language_back := _button("Назад")
				_check(language_back != null, "language picker has a back button")
				if language_back != null:
					language_back.pressed.emit()
					await create_timer(0.25).timeout
					basic = _button("Базовое обучение")
					_check(basic != null, "back returns to the tutorial submenu")
					if basic != null:
						basic.pressed.emit()
						await process_frame
				var russian := _button("Русский")
				if russian == null:
					quit(1)
					return
				russian.pressed.emit()
				await create_timer(2.0).timeout
				_check(main._mode == "tutorial" and main.board != null,
						"Basic Tutorial opens its dedicated Finn-vs-Jake match")
				_check(main.game.players[0].hand.size() == 5 and main.game.turn_player == 0,
						"tutorial starts with exactly five cards in Finn's hand")
				var tutor = main.board.tutorial
				_check(_button("Пропустить") == null, "tutorial has no Skip button")
				_check(tutor.card_property_panel == null and main.board.preview_rect.size == Vector2(490, 686),
						"Russian tutorial keeps the original preview without a translation panel")
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


func _check_tutorial_labels(tutorial: Button) -> void:
	var english := tutorial.get_node_or_null("EnglishLabel") as Label
	var korean := tutorial.get_node_or_null("KoreanLabel") as Label
	_check(english != null and korean != null, "tutorial button has side translations")
	if english == null or korean == null:
		return
	var button_font := tutorial.get_theme_font("font")
	var button_font_size := tutorial.get_theme_font_size("font_size")
	var half_title_width := button_font.get_string_size(tutorial.text, HORIZONTAL_ALIGNMENT_LEFT,
			-1, button_font_size).x * 0.5
	_check(english.text == "Tutorial" and korean.text == "튜토리얼"
			and english.label_settings.font_size < button_font_size
			and korean.label_settings.font_size < button_font_size,
			"translations use smaller type than the Russian title")
	_check(english.get_rect().end.x < tutorial.size.x * 0.5 - half_title_width
			and korean.position.x > tutorial.size.x * 0.5 + half_title_width
			and english.size.x >= english.get_minimum_size().x
			and korean.size.x >= korean.get_minimum_size().x,
			"translations fit on either side of the button title")
	_check(english.mouse_filter == Control.MOUSE_FILTER_IGNORE
			and korean.mouse_filter == Control.MOUSE_FILTER_IGNORE
			and korean.label_settings.font.has_char("한".unicode_at(0)),
			"labels pass clicks through and Korean characters are supported")


func _check(condition: bool, description: String) -> void:
	if not condition:
		failures += 1
		push_error("FAIL: " + description)
