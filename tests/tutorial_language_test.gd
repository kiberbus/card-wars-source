extends SceneTree

const MainScene = preload("res://scenes/main.tscn")
const TutorialText = preload("res://scripts/ui/tutorial_text.gd")
const TutorialCardText = preload("res://scripts/ui/tutorial_card_text.gd")
const CardDB = preload("res://scripts/core/card_db.gd")
const TouchInput = preload("res://scripts/ui/touch_input.gd")
const Phone = preload("res://scripts/ui/phone.gd")

var main: Control
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_check_translation_coverage()
	_check_card_translation_coverage()
	main = MainScene.instantiate()
	root.add_child(main)
	await create_timer(0.5).timeout
	var original_locale := TranslationServer.get_locale()
	for item: Array in [
			["English", "en", "Welcome to Card Wars", "Next", "Dude, let's play", "TURN PHASE"],
			["한국어", "ko", "카드 전쟁에 오신 걸 환영해", "다음", "친구야", "턴 단계 안내"]]:
		main.show_tutorial_language_menu()
		await process_frame
		var button := _button(item[0])
		_check(button != null, "language picker shows " + item[0])
		if button == null:
			quit(1)
			return
		button.pressed.emit()
		for i in 200:
			if main.board != null and main.board.tutorial != null and not main.board._busy:
				break
			await create_timer(0.05).timeout
		_check(main.board != null and main.board.tutorial != null, "selected language starts tutorial")
		if main.board == null or main.board.tutorial == null:
			quit(1)
			return
		var tutor = main.board.tutorial
		_check(tutor.language == item[1] and tutor.guide_text.text.contains(item[2])
				and tutor.next_button.text == item[3],
				"selected language is applied to introduction and tutorial buttons")
		_check(not tutor.card_property_panel.visible, "introduction hides the card property panel")
		_check(tutor.phase_text.text.contains(item[5]), "phase guide uses the selected language")
		await process_frame
		await process_frame
		_check(is_equal_approx(tutor.guide_panel.position.x, 400.0),
				"introduction keeps its centered position")
		_check_guide_bounds(tutor, "during the introduction")
		tutor._advance()
		tutor._advance()
		tutor._advance()
		await process_frame
		await process_frame
		_check_guide_bounds(tutor, "after the introduction")
		_check(tutor.guide_panel.size.x <= 520.0,
				"guide shrinks back after the wide introduction")
		var guide_right: float = tutor.guide_panel.position.x + tutor.guide_panel.size.x
		var guide_left: float = tutor.guide_panel.position.x
		tutor.guide_panel.custom_minimum_size.x = 800
		await process_frame
		await process_frame
		_check(tutor.guide_panel.position.x < guide_left
				and is_equal_approx(tutor.guide_panel.position.x + tutor.guide_panel.size.x, guide_right),
				"a wider guide expands to the left")
		tutor._set_step(tutor.Step.INTERFACE)
		tutor._advance()
		_check(tutor.dialogue_text.text.contains(item[4]), "character dialogue uses the selected language")
		tutor._advance()
		_check(tutor.guide_text.text.contains("Джинн Стрюзан"),
				"translated instructions retain the card's in-game Russian name")
		for lesson: int in [tutor.Step.FORTRESS, tutor.Step.FLOOP_PIG,
				tutor.Step.TELEPORT, tutor.Step.ARCHITECT]:
			tutor._set_step(lesson)
			await process_frame
			_check_guide_bounds(tutor, "during lesson %d" % lesson)
			_check(tutor.guide_text.get_visible_line_count() == tutor.guide_text.get_line_count()
					and tutor.guide_panel.position.y + tutor.guide_panel.size.y <= 1080.0,
					"translated lesson %d fits the tutorial panel" % lesson)
		tutor.jinn_attack_damage = 3
		tutor.archer_attack_damage = 2
		tutor._set_step(tutor.Step.END_TWO)
		_check(tutor.guide_text.text.contains("3") and tutor.guide_text.text.contains("2"),
				"translated combat summary formats the actual damage")
		tutor._set_step(tutor.Step.JAKE_FINAL_DIALOGUE)
		_check(tutor.dialogue_jake_button.visible and tutor.dialogue_friend_button.visible
				and tutor.dialogue_friend_button.text == TutorialText.TEXT[item[1]]["friend"],
				"final responses use the selected language")
		if item[1] == "ko":
			var font: Font = tutor.guide_text.get_theme_font("font")
			_check(font.has_char("한".unicode_at(0)) and font.has_char("Д".unicode_at(0)),
					"Korean tutorial font renders Korean and original card names")
			_check(tutor.card_property_text.get_theme_font("font").has_char("한".unicode_at(0)),
					"card property uses the Korean font")
		await _check_card_preview(tutor)
		var old_phone := Phone.active
		Phone.active = true
		main.board.set_side_room(0.0, true)
		tutor._set_step(tutor.Step.INTERFACE)
		await process_frame
		await process_frame
		_check_guide_bounds(tutor, "in the phone layout")
		Phone.active = old_phone
		_check(TranslationServer.get_locale() == original_locale,
				"tutorial language does not alter the game's global locale")
		main.show_title()
		await create_timer(0.3).timeout
		_check(_button("Обучение") != null, "main menu remains in Russian after the tutorial")
	quit(1 if failures > 0 else 0)


func _check_guide_bounds(tutor, context: String) -> void:
	var board = main.board
	var top_hero: Control = board.hero_ui["top"]["panel"]
	var right_column_x: float = minf(top_hero.position.x, board.main_button.position.x)
	_check(tutor.guide_panel.position.x + tutor.guide_panel.size.x <= right_column_x,
			"tutorial guide stays left of the right-hand interface " + context)


func _check_translation_coverage() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/ui/basic_tutorial.gd")
	var pattern := RegEx.new()
	pattern.compile('_text\\("([^"]+)",\\s*"((?:[^"\\\\]|\\\\.)*)"\\)')
	var matches := pattern.search_all(source)
	_check(not matches.is_empty(), "tutorial text calls were found")
	for result: RegExMatch in matches:
		var key := result.get_string(1)
		var russian := result.get_string(2)
		for language: String in ["en", "ko"]:
			var translations: Dictionary = TutorialText.TEXT[language]
			if not translations.has(key):
				_check(false, "%s translation exists for %s" % [language, key])
				continue
			var translated: String = translations[key]
			_check(not translated.is_empty() and translated.count("%d") == russian.count("%d"),
					"%s translation for %s preserves numeric placeholders" % [language, key])


func _check_card_translation_coverage() -> void:
	var ids: Dictionary = {}
	for hero: String in ["finn", "jake"]:
		for id: String in CardDB.hero(hero)["deck"]:
			ids[id] = true
	_check(ids.size() == TutorialCardText.TEXT.size(), "translations cover exactly the tutorial decks")
	for id: String in ids:
		if not TutorialCardText.TEXT.has(id):
			_check(false, "card translation exists for " + id)
			continue
		var definition := CardDB.get_def(id)
		var original: String = definition.get("text", "")
		for language: String in ["en", "ko"]:
			var translations: Dictionary = TutorialCardText.TEXT[id]
			var translated: String = translations.get(language, "")
			_check(translations.has(language) and translated.is_empty() == original.is_empty(),
					"%s property matches source presence for %s" % [language, id])
			if original.contains(definition["name"]):
				_check(translated.contains(definition["name"]),
						"%s keeps the Russian name in %s" % [language, id])
			if id == "archer_dan":
				_check(translated.contains("Лучника Дэна"), language + " keeps the inflected card name")


func _check_card_preview(tutor) -> void:
	var board = main.board
	board.set_process(false)
	tutor._set_step(tutor.Step.INTERFACE)
	_check(tutor.card_property_id == "struzann_jinn" and tutor.card_property_panel.visible,
			"guided preview shows the matching property")
	_check(not tutor.card_property_panel.get_rect().intersects(board.preview_rect.get_rect())
			and tutor.card_property_panel.mouse_filter == Control.MOUSE_FILTER_IGNORE
			and tutor.card_property_text.mouse_filter == Control.MOUSE_FILTER_IGNORE,
			"property panel does not cover the preview or intercept input")
	var card = board.game.players[0].hand[0]
	var view = board.views[card.uid]
	board._hover_view = view
	board._hover_hero = -1
	board._show_preview()
	_check(tutor.card_property_id == card.id, "hover changes the property to the visible card")
	view.secret = true
	board._show_preview()
	_check(not tutor.card_property_panel.visible, "secret cards do not expose properties")
	view.secret = false
	view.face_up = false
	board._show_preview()
	_check(not tutor.card_property_panel.visible, "face-down cards do not expose properties")
	view.face_up = true
	board._hover_view = null
	board._hover_hero = 0
	board._show_preview()
	_check(not tutor.card_property_panel.visible, "hero previews do not show card properties")
	board._hover_hero = -1
	TouchInput.finger = true
	board._peek_view = view
	board._show_preview()
	_check(tutor.card_property_id == card.id, "touch preview shows the tapped card's property")
	board._peek_view = null
	board._show_preview()
	_check(not tutor.card_property_panel.visible, "clearing the preview also clears the property")
	TouchInput.finger = false
	tutor._set_preview("phyllis", "")
	_check(not tutor.card_property_panel.visible, "cards without properties have no translation panel")
	tutor._set_preview("schoolhouse", "")
	tutor._show_dialogue(null, "")
	tutor._process(0.0)
	_check(not tutor.card_property_panel.visible, "dialogue hides the translation")
	tutor.dialogue_layer.visible = false
	board.preview_rect.visible = false
	tutor._process(0.0)
	_check(not tutor.card_property_panel.visible, "hidden preview hides the translation")
	board.preview_rect.visible = true
	var x: float = board.preview_rect.position.x
	board.preview_rect.position.x -= 50
	tutor._process(0.0)
	_check(is_equal_approx(tutor.card_property_panel.position.x,
			board.preview_rect.position.x + board.preview_rect.size.x + 8),
			"translation follows the preview when the layout moves")
	board.preview_rect.position.x = x
	for id: String in TutorialCardText.TEXT:
		tutor.show_card_property(id)
		await process_frame
		await process_frame
		if tutor.card_property_id == "":
			continue
		_check(tutor.card_property_text.get_visible_line_count() == tutor.card_property_text.get_line_count()
				and tutor.card_property_panel.position.y + tutor.card_property_panel.size.y <= 836
				and tutor.card_property_panel.size.x <= 280
				and not tutor.card_property_panel.get_rect().intersects(board.preview_info.get_rect()),
				"translated property fits the panel for " + id)
	board.set_process(true)


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
