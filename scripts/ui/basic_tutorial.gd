extends Node
## A guided Finn-vs-Jake match. The board remains the only input and animation layer.

signal _next_pressed

const CardView = preload("res://scripts/ui/card_view.gd")
const UI = preload("res://scripts/ui/ui_kit.gd")
const WoodUI = preload("res://scripts/ui/wood_ui.gd")
const JAKE_INTRO := preload("res://assets/tutorial/characters/jake_intro.png")
const FINN_CONFIDENT := preload("res://assets/tutorial/characters/finn_confident.png")
const JAKE_REPLY := preload("res://assets/tutorial/characters/jake_reply.png")
const FINN_LAUGH := preload("res://assets/tutorial/characters/finn_laugh.png")
const JAKE_YELL := preload("res://assets/tutorial/characters/jake_yell.png")

enum Step {
	GOAL, INTERFACE, PLAY_JINN, END_FIRST, DRAW_TWO, GNOME, BABY, FORTRESS,
	BEGIN_BATTLE_TWO, ATTACK_TWO, END_TWO, KNIGHT_NOTICE, KNIGHT_WAIT,
	TURN_THREE, PIG, FLOOP_PIG, TELEPORT, ARCHITECT, FLOOP_AGAIN,
	BEGIN_BATTLE_THREE, ATTACK_THREE, END_THREE, FREE_PLAY, HUSKER_STATS_ONE, HUSKER_STATS_TWO,
	GNOME_RESULT, ARCHER_SUMMARY,
	WELCOME_ONE, WELCOME_TWO, LAND_ZONES,
	REPLACE_ARCHITECT, JAKE_FINAL_NOTICE, JAKE_FINAL_WAIT, WALL_HIT_NOTICE, WALL_HIT_WAIT,
	BEGIN_BATTLE_FINAL, ATTACK_FINAL, JAKE_FINAL_DIALOGUE,
	JAKE_INTERFACE_DIALOGUE, FINN_FORTRESS_DIALOGUE, JAKE_SECOND_DIALOGUE,
	FINN_REACTION, JAKE_CORN_DIALOGUE,
}

var game
var board
var step: Step = Step.GOAL
var finn_turns := 0
var jinn_lane := -1
var baby_lane := -1
var pig_lane := -1
var teleport_lane := -1
var pig_uid := -1
var jinn_uid := -1
var baby_uid := -1
var architect_uid := -1
var husker_uid := -1
var cool_dog_uid := -1
var corn_dog_uid := -1
var wall_of_ears_uid := -1
var attacked_uids: Array[int] = []
var expected_attack_uids: Array[int] = []
var pending_attack_uid := -1
var jinn_attack_damage := 0
var archer_attack_damage := 0
var ai_first_stage := 0
var ai_second_stage := 0
var ai_final_stage := 0
var phase_panel: PanelContainer
var phase_text: Label
var guide_panel: PanelContainer
var guide_text: Label
var next_button: Button
var dialogue_layer: Control
var dialogue_character: TextureRect
var dialogue_panel: PanelContainer
var dialogue_text: Label
var dialogue_next_button: Button
var dialogue_jake_button: Button
var dialogue_friend_button: Button
var focus_layer: Control
var focus_rects: Array[Rect2] = []


func start(g, b) -> void:
	game = g
	board = b
	board.tutorial = self
	_build_ui()
	_set_step(Step.WELCOME_ONE)
	_update_phase("Начало первого хода: 5 карт уже в руке, восстанови 2 действия. Со следующего хода автоматически берётся 1 карта.")


func _build_ui() -> void:
	phase_panel = PanelContainer.new()
	phase_panel.position = Vector2(18, 12)
	phase_panel.custom_minimum_size = Vector2(560, 108)
	phase_panel.size = phase_panel.custom_minimum_size
	phase_panel.add_theme_stylebox_override("panel", WoodUI.window(18, 12))
	phase_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	board.hud.add_child(phase_panel)
	phase_text = Label.new()
	phase_text.custom_minimum_size = Vector2(530, 80)
	phase_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	phase_text.add_theme_font_size_override("font_size", 18)
	phase_text.add_theme_color_override("font_color", UI.CREAM)
	phase_panel.add_child(phase_text)

	guide_panel = PanelContainer.new()
	guide_panel.position = Vector2(1030, 14)
	guide_panel.custom_minimum_size = Vector2(520, 260)
	guide_panel.size = guide_panel.custom_minimum_size
	guide_panel.z_index = 90
	guide_panel.add_theme_stylebox_override("panel", WoodUI.window(20, 14))
	board.hud.add_child(guide_panel)
	var guide_box := VBoxContainer.new()
	guide_box.add_theme_constant_override("separation", 8)
	guide_panel.add_child(guide_box)
	guide_text = Label.new()
	guide_text.custom_minimum_size = Vector2(480, 150)
	guide_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	guide_text.add_theme_font_size_override("font_size", 20)
	guide_text.add_theme_color_override("font_color", UI.CREAM)
	guide_box.add_child(guide_text)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation", 10)
	guide_box.add_child(buttons)
	next_button = WoodUI.button("Далее", UI.GREEN, 20, Vector2(150, 44))
	next_button.pressed.connect(_advance)
	buttons.add_child(next_button)

	dialogue_layer = Control.new()
	dialogue_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	dialogue_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	dialogue_layer.z_index = 110
	dialogue_layer.visible = false
	board.hud.add_child(dialogue_layer)
	var dialogue_backdrop := ColorRect.new()
	dialogue_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	dialogue_backdrop.color = Color(0.02, 0.02, 0.04, 0.72)
	dialogue_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	dialogue_layer.add_child(dialogue_backdrop)
	dialogue_character = TextureRect.new()
	dialogue_character.position = Vector2(90, 365)
	dialogue_character.size = Vector2(620, 620)
	dialogue_character.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	dialogue_character.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	dialogue_character.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dialogue_layer.add_child(dialogue_character)
	dialogue_panel = PanelContainer.new()
	dialogue_panel.position = Vector2(620, 755)
	dialogue_panel.custom_minimum_size = Vector2(1210, 280)
	dialogue_panel.size = dialogue_panel.custom_minimum_size
	dialogue_panel.add_theme_stylebox_override("panel", WoodUI.window(22, 16))
	dialogue_layer.add_child(dialogue_panel)
	var dialogue_box := VBoxContainer.new()
	dialogue_box.add_theme_constant_override("separation", 10)
	dialogue_panel.add_child(dialogue_box)
	dialogue_text = Label.new()
	dialogue_text.custom_minimum_size = Vector2(1160, 150)
	dialogue_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dialogue_text.add_theme_font_size_override("font_size", 30)
	dialogue_text.add_theme_color_override("font_color", UI.CREAM)
	dialogue_box.add_child(dialogue_text)
	var dialogue_buttons := HBoxContainer.new()
	dialogue_buttons.alignment = BoxContainer.ALIGNMENT_END
	dialogue_buttons.add_theme_constant_override("separation", 14)
	dialogue_box.add_child(dialogue_buttons)
	dialogue_next_button = WoodUI.button("Далее", UI.GREEN, 22, Vector2(170, 52))
	dialogue_next_button.pressed.connect(_advance)
	dialogue_buttons.add_child(dialogue_next_button)
	dialogue_jake_button = WoodUI.button("Джейк Ботан!", UI.ORANGE, 20, Vector2(300, 52))
	dialogue_jake_button.pressed.connect(_choose_jake_response)
	dialogue_buttons.add_child(dialogue_jake_button)
	dialogue_friend_button = WoodUI.button(
			"Прости Джейк, давай сыграем еще", UI.GREEN, 20, Vector2(440, 52))
	dialogue_friend_button.pressed.connect(_choose_good_friend)
	dialogue_buttons.add_child(dialogue_friend_button)

	focus_layer = Control.new()
	focus_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	focus_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_layer.draw.connect(_draw_focus)
	focus_layer.z_index = 80
	board.hud.add_child(focus_layer)
	board.preview_rect.position.y = 150
	board.preview_info.position.y = 836
	_set_guide_layout(Vector2(1030, 14), Vector2(520, 260), 20)


func _set_guide_layout(pos: Vector2, dimensions: Vector2, font_size: int, centered := false) -> void:
	guide_panel.position = pos
	guide_panel.custom_minimum_size = dimensions
	guide_panel.size = dimensions
	guide_text.custom_minimum_size = Vector2(dimensions.x - 40, dimensions.y - 90)
	guide_text.add_theme_font_size_override("font_size", font_size)
	guide_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if centered else HORIZONTAL_ALIGNMENT_LEFT


func _show_dialogue(character: Texture2D, text: String, final_choices := false) -> void:
	guide_panel.visible = false
	dialogue_layer.visible = true
	dialogue_character.texture = character
	dialogue_character.visible = true
	dialogue_panel.visible = true
	dialogue_text.text = text
	dialogue_text.visible = true
	dialogue_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	dialogue_next_button.visible = not final_choices
	dialogue_jake_button.visible = final_choices
	dialogue_friend_button.visible = final_choices


func _show_reaction(character: Texture2D) -> void:
	guide_panel.visible = false
	dialogue_layer.visible = true
	dialogue_character.texture = character
	dialogue_character.visible = true
	dialogue_panel.visible = false
	dialogue_text.text = ""
	dialogue_text.visible = false
	dialogue_next_button.visible = false
	dialogue_jake_button.visible = false
	dialogue_friend_button.visible = false


func _choose_jake_response() -> void:
	_return_to_title()


func _choose_good_friend() -> void:
	dialogue_character.visible = false
	dialogue_panel.position = Vector2(350, 410)
	dialogue_panel.custom_minimum_size = Vector2(1220, 220)
	dialogue_panel.size = dialogue_panel.custom_minimum_size
	dialogue_text.custom_minimum_size = Vector2(1170, 150)
	dialogue_text.text = "Получено достижение «Хороший друг»!"
	dialogue_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dialogue_next_button.visible = false
	dialogue_jake_button.visible = false
	dialogue_friend_button.visible = false
	await get_tree().create_timer(2.0).timeout
	_return_to_title()


func _return_to_title() -> void:
	if board == null or not is_instance_valid(board) or board.get_parent() == null \
			or board.get_parent().get_parent() == null:
		push_error("Basic tutorial: unable to return to the main menu.")
		return
	var main = board.get_parent().get_parent()
	if main.has_method("show_title"):
		main.show_title()
	else:
		push_error("Basic tutorial: unable to return to the main menu.")


func _exit_intro_layout() -> void:
	_set_guide_layout(Vector2(1030, 14), Vector2(520, 260), 20)
	phase_panel.visible = true
	board.preview_rect.visible = true
	board.preview_info.visible = true


func _update_phase(text: String) -> void:
	phase_text.text = "ПАМЯТКА ФАЗЫ\n" + text


func _clear_focus() -> void:
	focus_rects.clear()
	board.tutorial_land_targets.clear()
	board.tutorial_building_targets.clear()
	board.tutorial_world_targets.clear()
	for view in board.views.values():
		view.set_highlight("")
	focus_layer.queue_redraw()
	board.decor.queue_redraw()


func _draw_focus() -> void:
	for rect: Rect2 in focus_rects:
		focus_layer.draw_rect(rect, Color(1.0, 0.84, 0.25, 0.95), false, 5.0)


func _focus_control(control: Control) -> void:
	if control == null or not is_instance_valid(control):
		return
	var inverse := focus_layer.get_global_transform_with_canvas().affine_inverse()
	var global_rect := control.get_global_rect()
	var top_left: Vector2 = inverse * global_rect.position
	var bottom_right: Vector2 = inverse * (global_rect.position + global_rect.size)
	focus_rects.append(Rect2(top_left, bottom_right - top_left).grow(6.0))
	focus_layer.queue_redraw()


func _highlight_hand(id: String) -> void:
	for c in game.players[0].hand:
		if c.id == id and board.views.has(c.uid):
			board.views[c.uid].set_highlight("target")
			return


func _highlight_table(uid: int) -> void:
	if uid >= 0 and board.views.has(uid):
		board.views[uid].set_highlight("target")


func _set_preview(id: String, description: String) -> void:
	board.preview_rect.texture = CardView.texture_for(id)
	board.preview_info.text = description


func _highlight_open_lands(exclude: Array = []) -> void:
	for lane in 4:
		if exclude.has(lane) or game.players[0].creatures[lane] != null:
			continue
		var across: Array = game.across(0, lane)
		if game.players[across[0]].creatures[across[1]] == null:
			board.tutorial_land_targets.append({"p": 0, "lane": lane})
	board.decor.queue_redraw()


func _set_step(next_step: Step) -> void:
	_exit_intro_layout()
	step = next_step
	_clear_focus()
	dialogue_layer.visible = false
	var message := ""
	next_button.visible = false
	next_button.text = "Далее"
	match step:
		Step.WELCOME_ONE:
			message = "Добро пожаловать на «Карточные войны». Это любимая игра Джейка и многих\nдругих, и скоро ты тоже её полюбишь. Впрочем, сначала давай изучим все эти КРАЙНЕ\nЗАУМНЫЕ правила."
			_set_guide_layout(Vector2(400, 370), Vector2(1120, 300), 28, true)
			next_button.visible = true
			phase_panel.visible = false
			board.preview_rect.visible = false
			board.preview_info.visible = false
		Step.WELCOME_TWO:
			message = "«Карточные войны» — настольный поединок, в котором у каждого игрока будет\nсобственная колода. Эпичные баталии развернутся на поле боя из четырёх зон, прямо как в мультфильме.\nЗадача игроков — снизить жизни соперника с 25 до 0. Сделаешь это — и ты крутой!"
			_set_guide_layout(Vector2(400, 370), Vector2(1120, 300), 28, true)
			next_button.visible = true
			phase_panel.visible = false
			board.preview_rect.visible = false
			board.preview_info.visible = false
			for key in board.hero_ui:
				_focus_control(board.hero_ui[key]["panel"])
		Step.LAND_ZONES:
			message = "Четыре земли на твоей стороне поля — это четыре «ячейки» для твоих существ и строений.\nОдна зона состоит из двух земель, выложенных напротив друг друга."
			_set_guide_layout(Vector2(590, 120), Vector2(740, 270), 24)
			next_button.visible = true
			phase_panel.visible = false
			board.preview_rect.visible = false
			board.preview_info.visible = false
			for lane in 4:
				board.tutorial_land_targets.append({"p": 0, "lane": lane})
				board.tutorial_land_targets.append({"p": 1, "lane": lane})
			board.decor.queue_redraw()
		Step.GOAL:
			message = "Цель игры — снизить жизни соперника до 0. Тип и количество земель определяют, какие карты можно разыграть."
			next_button.visible = true
			for key in board.hero_ui:
				_focus_control(board.hero_ui[key]["panel"])
			board.tutorial_land_targets = []
			for lane in 4:
				board.tutorial_land_targets.append({"p": 0, "lane": lane})
			board.decor.queue_redraw()
		Step.INTERFACE:
			message = "На карте: название сверху, стоимость слева вверху, тип земли справа вверху, атака и защита внизу. Есть три вида карт: существа ставятся на землю, строения — в зону под существом, заклинания дают мгновенный эффект и уходят в Сброс. В первый ход нельзя атаковать и использовать ФЛЮП."
			next_button.visible = true
			for c in game.players[0].hand:
				_highlight_table(c.uid)
			_focus_control(board.actions_widget)
			_highlight_hand("struzann_jinn")
			_set_preview("struzann_jinn", "Название сверху · стоимость слева · земля справа · атака и защита снизу")
		Step.JAKE_INTERFACE_DIALOGUE:
			_show_dialogue(JAKE_INTRO, "Друг, давай играть уже, всё просто, клади карты и всё.")
		Step.PLAY_JINN:
			message = "Начнём с существа: оно занимает зону на земле. У карты «Джинн Стрюзан» атака 1 и защита 11. Сыграй «Джинн Стрюзан» в любую свою зону за 2 действия."
			_highlight_hand("struzann_jinn")
			_set_preview("struzann_jinn", "Существо · стоимость 2 · атака 1 · защита 11")
		Step.END_FIRST:
			message = "В первый ход нельзя атаковать и использовать ФЛЮП. Нажми «Завершить ход»."
			_focus_control(board.main_button)
		Step.DRAW_TWO:
			message = "В начале хода готовятся повёрнутые карты, восстанавливаются 2 действия и автоматически берётся 1 карта — «Гномьи сопли»."
			next_button.visible = true
			_focus_world(board.deck_pos(0), Vector2(130, 185))
			for c in game.players[0].hand:
				_highlight_table(c.uid)
		Step.GNOME:
			message = "Теперь новый тип — заклинание: оно сразу применяет эффект и отправляется в Сброс. «Гномьи сопли» стоят 1 действие и дают 3 карты. Сыграй «Гномьи сопли»."
			_highlight_hand("gnome_snot")
			_focus_world(board.discard_pos(0), Vector2(120, 170))
			_set_preview("gnome_snot", "Заклинание · стоимость 1 · возьми 3 карты")
		Step.GNOME_RESULT:
			message = "Отлично! Осталось 1 действие. Посмотри на подсвеченный счётчик действий."
			next_button.visible = true
			_focus_control(board.actions_widget)
		Step.BABY:
			message = "«Прохладный младенец» — радужное существо: для его розыгрыша не нужна земля определённого типа. Сыграй его за 0 действий в свободную зону напротив пустой зоны соперника."
			_highlight_hand("nice_ice_baby")
			_highlight_open_lands([jinn_lane])
			_set_preview("nice_ice_baby", "Радужное существо · стоимость 0 · можно играть на любую землю")
		Step.FORTRESS:
			message = "Теперь новый тип — строение. Его можно выложить в любую зону, даже если там уже есть существо: для него есть отдельная зона под существом. Строение остаётся на поле и даёт постоянный эффект. Сыграй «Кровавую крепость» под Младенца за последнее действие: она даст ему +1 к атаке."
			_highlight_hand("blood_fortress")
			board.tutorial_land_targets.append({"p": 0, "lane": baby_lane})
			board.tutorial_building_targets.append({"p": 0, "lane": baby_lane})
			board.decor.queue_redraw()
			_set_preview("blood_fortress", "Строение · стоимость 1 · +1 к атаке существа в этой зоне")
		Step.FINN_FORTRESS_DIALOGUE:
			_show_dialogue(FINN_CONFIDENT, "Кажется, я понял эту игру, БОТАН!")
		Step.BEGIN_BATTLE_TWO:
			message = "Перейди в фазу боя кнопкой «В атаку!». Все подготовленные существа должны атаковать."
			_focus_control(board.main_button)
		Step.ATTACK_TWO:
			message = "Атакуй обеими подготовленными картами. В бою существа наносят урон друг другу одновременно; когда защита падает до 0, карта погибает и уходит в Сброс. Младенец бьёт по пустой зоне."
			_highlight_table(jinn_uid)
			_highlight_table(baby_uid)
		Step.JAKE_SECOND_DIALOGUE:
			_show_dialogue(JAKE_REPLY, "Как бы не так, Ботан Финн!")
		Step.END_TWO:
			message = "Джинн нанёс Дэну %d урона, а Дэн — Джинну %d. При защите 0 существо погибает и отправляется в Сброс. Младенец тоже атаковал Джейка. Заверши ход." % [
				jinn_attack_damage, archer_attack_damage]
			_focus_control(board.main_button)
		Step.KNIGHT_NOTICE:
			message = "Кожурыцарь довольно силён и легко убивает Младенца. Посмотри на его свойство: за каждое кукурузное поле Джейка он получает +1 к атаке и +2 к защите."
			next_button.visible = true
			_highlight_table(husker_uid)
			_set_preview("husker_knight", "Кожурыцарь: +1 к атаке и +2 к защите за каждое кукурузное поле.")
		Step.KNIGHT_WAIT:
			message = ""
		Step.TURN_THREE:
			message = "Попробуем ослабить Кожурыцаря и освоить комбинацию карт и способностей. В начале хода ты автоматически берёшь «Архитектора разума»."
			next_button.visible = true
			_focus_world(board.deck_pos(0), Vector2(130, 185))
			for c in game.players[0].hand:
				_highlight_table(c.uid)
		Step.PIG:
			message = "За 1 действие сыграй «Свинью» в свободную зону напротив неперевёрнутого кукурузного поля, не напротив Кожурыцаря."
			_highlight_hand("the_pig")
			_highlight_open_lands([jinn_lane, baby_lane])
			_set_preview("the_pig", "Радужное существо · стоимость 1 · ФЛЮП переворачивает кукурузное поле в этой зоне")
		Step.FLOOP_PIG:
			message = "ФЛЮП — активируемая способность: повернув существо набок, ты используешь её эффект, но оно перестаёт быть подготовленным и не атакует в этот ход. Всегда решай, что выгоднее. Сейчас наша цель — ослабить Кожурыцаря: флюпни Свинью, чтобы перевернуть поле напротив."
			_highlight_table(pig_uid)
			if pig_lane >= 0:
				var a: Array = game.across(0, pig_lane)
				board.tutorial_land_targets.append({"p": a[0], "lane": a[1]})
			board.decor.queue_redraw()
		Step.TELEPORT:
			message = "«Телепорт» — заклинание: оно сразу перемещает существо, а затем отправляется в Сброс. Сыграй его за 0 действий, выбери Свинью и перенеси её в другую свободную зону напротив активного кукурузного поля."
			_highlight_hand("teleport")
			if teleport_lane >= 0:
				board.tutorial_land_targets.append({"p": 0, "lane": teleport_lane})
			board.decor.queue_redraw()
			_set_preview("teleport", "Заклинание · стоимость 0 · перемещает существо в свободную зону")
		Step.HUSKER_STATS_ONE:
			message = "Кукурузное поле перевёрнуто. Кожурыцарь ослаб: сейчас атака %d, защита %d. Нажми «Далее»." % [
				game.atk_of(1, baby_lane), game.def_of(1, baby_lane)]
			next_button.visible = true
			_highlight_table(husker_uid)
			_set_preview("husker_knight", "Переворот поля немедленно уменьшил характеристики.")
		Step.ARCHITECT:
			message = "Вот бы Свинья могла флюпнуть ещё раз… Ого, у нас есть Архитектор разума! Когда он выходит на поле, его способность готовит флюпнутое существо. Сыграй Архитектора за последнее действие напротив Кожурыцаря и выбери Свинью."
			_highlight_hand("psionic_architect")
			if baby_lane >= 0:
				board.tutorial_land_targets.append({"p": 0, "lane": baby_lane})
			board.decor.queue_redraw()
			_set_preview("psionic_architect", "Существо · стоимость 1 · при входе готовит одно твоё флюпнутое существо")
		Step.FLOOP_AGAIN:
			message = "Свинья снова готова. Флюпни её ещё раз, чтобы перевернуть второе кукурузное поле и ослабить Кожурыцаря."
			_highlight_table(pig_uid)
			if teleport_lane >= 0:
				var a: Array = game.across(0, teleport_lane)
				board.tutorial_land_targets.append({"p": a[0], "lane": a[1]})
			board.decor.queue_redraw()
			_highlight_table(husker_uid)
			_set_preview("husker_knight", "После переворота полей его атака и защита уменьшаются.")
		Step.FINN_REACTION:
			_show_reaction(FINN_LAUGH)
		Step.HUSKER_STATS_TWO:
			message = "Второе поле перевёрнуто! У Кожурыцаря осталось %d защиты, а атака Архитектора — %d. Даже Архитектор за 1 действие может победить Кожурыцаря, который стоит 2. Нажми «Далее»." % [
				game.hp_of(1, baby_lane), game.atk_of(0, baby_lane)]
			next_button.visible = true
			_highlight_table(husker_uid)
			_set_preview("husker_knight", "Кожурыцарь продолжает терять атаку и защиту.")
		Step.BEGIN_BATTLE_THREE:
			message = "Перейди в фазу боя. Свинья повёрнута и не атакует."
			_focus_control(board.main_button)
		Step.ATTACK_THREE:
			message = "Атакуй подготовленными существами: Архитектором напротив Кожурыцаря и другими готовыми существами. Урон в бою наносится одновременно."
			_highlight_table(jinn_uid)
			_highlight_table(architect_uid)
			_highlight_table(husker_uid)
		Step.JAKE_CORN_DIALOGUE:
			_show_dialogue(JAKE_YELL, "МОЯ КУКУРУЗА!")
		Step.END_THREE:
			message = "Все готовые существа атаковали. Заверши ход."
			_focus_control(board.main_button)
		Step.JAKE_FINAL_NOTICE:
			message = "Джейк выставил «Кукутузика» напротив Джинна и «Стену початков» напротив Архитектора. Теперь он переходит к бою."
			next_button.visible = true
			_highlight_table(corn_dog_uid)
			_highlight_table(wall_of_ears_uid)
		Step.JAKE_FINAL_WAIT:
			message = ""
		Step.WALL_HIT_NOTICE:
			message = "Стена початков атакует Архитектора на 2 урона. У Архитектора осталось %d здоровья. Если оставить его, он погибнет, атакуя Стену, а на следующем ходу Стена сможет ударить прямо по тебе. Замени Архитектора Крутым псом в этой зоне." % game.hp_of(0, baby_lane)
			next_button.visible = true
			_highlight_table(wall_of_ears_uid)
			_highlight_table(architect_uid)
			_highlight_hand("cool_dog")
			_set_preview("cool_dog", "Существо · стоимость 2 · атака 2 · защита 7")
		Step.WALL_HIT_WAIT:
			message = ""
		Step.REPLACE_ARCHITECT:
			message = "Сыграй «Крутого пса» вместо Архитектора в этой зоне. Архитектор отправится в Сброс, а новый защитник не позволит Стене початков выйти на прямую атаку."
			_highlight_hand("cool_dog")
			_highlight_table(architect_uid)
			_highlight_table(wall_of_ears_uid)
			board.tutorial_land_targets.append({"p": 0, "lane": baby_lane})
			board.decor.queue_redraw()
			_set_preview("cool_dog", "Существо · стоимость 2 · атака 2 · защита 7")
		Step.BEGIN_BATTLE_FINAL:
			message = "Крутой пёс заменил Архитектора. Перейди в фазу боя и атакуй всеми подготовленными существами."
			_focus_control(board.main_button)
		Step.ATTACK_FINAL:
			message = "Атакуй всеми подготовленными существами: Крутым псом напротив Стены початков, Джинном напротив Кукутузика и Свиньёй."
			_highlight_table(cool_dog_uid)
			_highlight_table(jinn_uid)
			_highlight_table(pig_uid)
		Step.JAKE_FINAL_DIALOGUE:
			_show_dialogue(JAKE_YELL, "Финн мухлюет! Я ухожу!", true)
		Step.ARCHER_SUMMARY:
			var jinn = game.players[0].creatures[jinn_lane]
			var archer = game.players[1].creatures[jinn_lane]
			var jinn_hit: int = game.combat_atk(0, jinn_lane, archer, jinn_lane, true)
			var archer_hit: int = game.combat_atk(1, jinn_lane, jinn, jinn_lane, false)
			message = "Джейк выставил Лучника Дэна напротив Джинна. Они сразились одновременно: Джинн нанёс Дэну %d урона, а Дэн — Джинну %d. Теперь у Джинна %d из %d защиты, у Дэна — %d из %d. При защите 0 существо погибает и отправляется в Сброс." % [
				jinn_hit, archer_hit, game.hp_of(0, jinn_lane), game.def_of(0, jinn_lane),
				game.hp_of(1, jinn_lane), game.def_of(1, jinn_lane)]
			next_button.visible = true
	guide_text.text = message
	guide_panel.visible = message != ""
	focus_layer.queue_redraw()
	board.decor.queue_redraw()


func _focus_world(center: Vector2, size: Vector2) -> void:
	board.tutorial_world_targets.append(board._shape(center, size))
	board.decor.queue_redraw()


func _advance() -> void:
	match step:
		Step.WELCOME_ONE:
			_set_step(Step.WELCOME_TWO)
		Step.WELCOME_TWO:
			_set_step(Step.LAND_ZONES)
		Step.LAND_ZONES:
			_set_step(Step.INTERFACE)
		Step.GOAL:
			_set_step(Step.INTERFACE)
		Step.INTERFACE:
			_set_step(Step.JAKE_INTERFACE_DIALOGUE)
		Step.JAKE_INTERFACE_DIALOGUE:
			_set_step(Step.PLAY_JINN)
		Step.DRAW_TWO:
			_set_step(Step.GNOME)
		Step.GNOME_RESULT:
			_set_step(Step.BABY)
		Step.KNIGHT_NOTICE:
			_set_step(Step.KNIGHT_WAIT)
			_next_pressed.emit()
		Step.ARCHER_SUMMARY:
			guide_panel.visible = false
			next_button.visible = false
			_next_pressed.emit()
		Step.JAKE_FINAL_NOTICE:
			_set_step(Step.JAKE_FINAL_WAIT)
			_next_pressed.emit()
		Step.WALL_HIT_NOTICE:
			_set_step(Step.WALL_HIT_WAIT)
			_next_pressed.emit()
		Step.HUSKER_STATS_ONE:
			_set_step(Step.TELEPORT)
		Step.HUSKER_STATS_TWO:
			_set_step(Step.BEGIN_BATTLE_THREE)
		Step.TURN_THREE:
			_set_step(Step.PIG)
		Step.FINN_FORTRESS_DIALOGUE:
			_set_step(Step.BEGIN_BATTLE_TWO)
		Step.JAKE_SECOND_DIALOGUE:
			_set_step(Step.END_TWO)
		Step.JAKE_CORN_DIALOGUE:
			_set_step(Step.END_THREE)


func allow_command(p: int, command: Dictionary) -> bool:
	if p != 0:
		return false
	match step:
		Step.PLAY_JINN:
			return _play_is(command, "struzann_jinn")
		Step.END_FIRST:
			return command.get("cmd") == "end_turn"
		Step.END_TWO, Step.END_THREE:
			return command.get("cmd") == "end_turn" and _all_expected_attacked()
		Step.GNOME:
			return _play_is(command, "gnome_snot")
		Step.BABY:
			return _play_is(command, "nice_ice_baby") and _baby_lane_allowed(int(command.get("lane", -1)))
		Step.FORTRESS:
			return _play_is(command, "blood_fortress") \
					and int(command.get("lane", -1)) == baby_lane
		Step.BEGIN_BATTLE_TWO, Step.BEGIN_BATTLE_THREE:
			return command.get("cmd") == "begin_attack"
		Step.ATTACK_TWO, Step.ATTACK_THREE:
			return _attack_allowed(command)
		Step.PIG:
			return _play_is(command, "the_pig") and _pig_lane_allowed(int(command.get("lane", -1)))
		Step.FLOOP_PIG, Step.FLOOP_AGAIN:
			return command.get("cmd") == "floop" and command.get("kind") == "creature" \
					and int(command.get("lane", -1)) == pig_lane
		Step.TELEPORT:
			return _play_is(command, "teleport")
		Step.ARCHITECT:
			return _play_is(command, "psionic_architect") \
					and int(command.get("lane", -1)) == baby_lane
		Step.REPLACE_ARCHITECT:
			return _play_is(command, "cool_dog") \
					and int(command.get("lane", -1)) == baby_lane
		Step.BEGIN_BATTLE_FINAL:
			return command.get("cmd") == "begin_attack"
		Step.ATTACK_FINAL:
			return _attack_allowed(command)
	return false


func _play_is(command: Dictionary, id: String) -> bool:
	if command.get("cmd") != "play":
		return false
	var c = game.card(int(command.get("uid", -1)))
	return c != null and c.id == id and game.can_play(0, c.uid, int(command.get("lane", -1)))


func _baby_lane_allowed(lane: int) -> bool:
	if lane < 0 or lane >= 4 or lane == jinn_lane or game.players[0].creatures[lane] != null:
		return false
	var across: Array = game.across(0, lane)
	return game.players[across[0]].creatures[across[1]] == null


func _pig_lane_allowed(lane: int) -> bool:
	if lane < 0 or lane >= 4 or lane == jinn_lane or lane == baby_lane \
			or game.players[0].creatures[lane] != null:
		return false
	var across: Array = game.across(0, lane)
	var land: Dictionary = game.players[across[0]].lands[across[1]]
	return land["type"] == "corn" and not land["flipped"] \
			and game.players[across[0]].creatures[across[1]] == null


func _attack_allowed(command: Dictionary) -> bool:
	if command.get("cmd") != "attack":
		return false
	var lane := int(command.get("lane", -1))
	if lane < 0 or lane >= 4:
		return false
	var c = game.players[0].creatures[lane]
	if c == null or not expected_attack_uids.has(c.uid) or attacked_uids.has(c.uid):
		return false
	if c.id == "struzann_jinn" and lane == jinn_lane:
		var across: Array = game.across(0, lane)
		var defender = game.players[across[0]].creatures[across[1]]
		if defender != null:
			jinn_attack_damage = game.combat_atk(0, lane, defender, across[1], true)
			archer_attack_damage = game.combat_atk(across[0], across[1], c, lane, false)
	pending_attack_uid = c.uid
	return true


func _all_expected_attacked() -> bool:
	return not expected_attack_uids.is_empty() and expected_attack_uids.all(func(uid): return attacked_uids.has(uid))


func command_resolved(p: int, command: Dictionary) -> void:
	if p != 0:
		return
	match step:
		Step.PLAY_JINN:
			jinn_uid = int(command["uid"])
			jinn_lane = int(game.where(jinn_uid).get("lane", -1))
			_set_step(Step.END_FIRST)
		Step.GNOME:
			_set_step(Step.GNOME_RESULT)
		Step.BABY:
			baby_uid = int(command["uid"])
			baby_lane = int(game.where(baby_uid).get("lane", -1))
			_set_step(Step.FORTRESS)
		Step.FORTRESS:
			_set_step(Step.FINN_FORTRESS_DIALOGUE)
		Step.BEGIN_BATTLE_TWO:
			_set_expected_attackers(Step.ATTACK_TWO)
		Step.ATTACK_TWO:
			if command.get("cmd") == "attack" and pending_attack_uid >= 0:
				attacked_uids.append(pending_attack_uid)
				pending_attack_uid = -1
			if _all_expected_attacked():
				_set_step(Step.JAKE_SECOND_DIALOGUE)
		Step.PIG:
			pig_uid = int(command["uid"])
			pig_lane = int(game.where(pig_uid).get("lane", -1))
			_set_step(Step.FLOOP_PIG)
		Step.FLOOP_PIG:
			teleport_lane = _other_pig_lane()
			_set_step(Step.HUSKER_STATS_ONE)
		Step.TELEPORT:
			pig_lane = int(game.where(pig_uid).get("lane", -1))
			_set_step(Step.ARCHITECT)
		Step.ARCHITECT:
			architect_uid = int(command["uid"])
			_set_step(Step.FLOOP_AGAIN)
		Step.FLOOP_AGAIN:
			call_deferred("_show_finn_reaction")
		Step.BEGIN_BATTLE_THREE:
			_set_expected_attackers(Step.ATTACK_THREE)
		Step.ATTACK_THREE:
			if command.get("cmd") == "attack" and pending_attack_uid >= 0:
				attacked_uids.append(pending_attack_uid)
				pending_attack_uid = -1
			if _all_expected_attacked():
				_set_step(Step.JAKE_CORN_DIALOGUE)
		Step.REPLACE_ARCHITECT:
			cool_dog_uid = int(command["uid"])
			_set_step(Step.BEGIN_BATTLE_FINAL)
		Step.BEGIN_BATTLE_FINAL:
			_set_expected_attackers(Step.ATTACK_FINAL)
		Step.ATTACK_FINAL:
			if command.get("cmd") == "attack" and pending_attack_uid >= 0:
				attacked_uids.append(pending_attack_uid)
				pending_attack_uid = -1
			if _all_expected_attacked():
				_set_step(Step.JAKE_FINAL_DIALOGUE)


func _show_finn_reaction() -> void:
	_set_step(Step.FINN_REACTION)
	await get_tree().create_timer(2.0).timeout
	if is_inside_tree() and step == Step.FINN_REACTION:
		_set_step(Step.HUSKER_STATS_TWO)


func _set_expected_attackers(attack_step: Step) -> void:
	expected_attack_uids.clear()
	attacked_uids.clear()
	for lane in 4:
		if game.can_attack(0, lane):
			expected_attack_uids.append(game.players[0].creatures[lane].uid)
	_set_step(attack_step)


func _other_pig_lane() -> int:
	for lane in 4:
		if lane == jinn_lane or lane == baby_lane or lane == pig_lane:
			continue
		if game.players[0].creatures[lane] != null:
			continue
		var across: Array = game.across(0, lane)
		var land: Dictionary = game.players[across[0]].lands[across[1]]
		if land["type"] == "corn" and not land["flipped"] \
				and game.players[across[0]].creatures[across[1]] == null:
			return lane
	return -1


func allow_choice(req: Dictionary, result) -> bool:
	var kind: String = req.get("kind", "")
	if step == Step.FLOOP_PIG or step == Step.FLOOP_AGAIN:
		if kind == "land":
			return result is Dictionary and int(result.get("p", -1)) == game.across(0, pig_lane)[0] \
					and int(result.get("lane", -1)) == game.across(0, pig_lane)[1]
	if step == Step.TELEPORT:
		if kind == "creature":
			return result is Dictionary and int(result.get("p", -1)) == 0 \
					and int(result.get("lane", -1)) == pig_lane
		if kind == "lane":
			return result is Dictionary and int(result.get("p", -1)) == 0 \
					and int(result.get("lane", -1)) == teleport_lane
	if step == Step.ARCHITECT and kind == "creature":
		return result is Dictionary and int(result.get("p", -1)) == 0 \
				and int(result.get("lane", -1)) == pig_lane
	return true


func reject_command() -> void:
	guide_text.text += "\nСейчас выполни действие, выделенное подсветкой."


func reject_choice() -> void:
	if board.prompt_label != null:
		board.prompt_label.text = "Выбери подсвеченную цель."


func hold_combat_end(p: int) -> bool:
	return (p == 0 and (step == Step.ATTACK_TWO or step == Step.ATTACK_THREE \
			or step == Step.ATTACK_FINAL)) \
			or (p == 1 and game.turn_number == 2 and ai_first_stage == 3)


func optional_choice_skip_allowed() -> bool:
	return false


func on_game_event(event: Dictionary) -> void:
	match event.get("type", ""):
		"turn_start":
			if int(event.get("p", -1)) == 0:
				finn_turns += 1
				if finn_turns == 1:
					_update_phase("Первый ход: подготовь карты и восстанови 2 действия. В руке уже ровно 5 карт.")
				elif finn_turns == 2:
					_update_phase("Начало хода: подготовь повёрнутые карты, восстанови 2 действия и возьми 1 карту.")
					_set_step(Step.DRAW_TWO)
				elif finn_turns == 3:
					_update_phase("Начало хода: подготовь повёрнутые карты, восстанови 2 действия и возьми 1 карту.")
					_set_step(Step.TURN_THREE)
				elif finn_turns == 4:
					_update_phase("Начало хода: подготовь повёрнутые карты, восстанови 2 действия и возьми 1 карту.")
					_set_step(Step.REPLACE_ARCHITECT)
			else:
				_update_phase("Начало хода: подготовь повёрнутые карты, восстанови 2 действия и возьми 1 карту.")
		"actions":
			_update_phase("Фаза действий и способностей: разыгрывай существ, строения и заклинания; добор за действие и ФЛЮП можно делать в любом порядке.")
		"draw":
			if int(event.get("p", -1)) == 0 \
					and (step == Step.DRAW_TWO or step == Step.TURN_THREE):
				call_deferred("_highlight_table", int(event.get("uid", -1)))
		"phase":
			match event.get("phase", game.phase):
				"attack":
					_update_phase("Фаза боя: все подготовленные существа обязаны атаковать.")
				"handoff":
					_update_phase("Конец хода: передай ход сопернику.")
				"main":
					_update_phase("Фаза действий и способностей: разыгрывай карты, добирай за действие и используй ФЛЮП.")


func after_ai_command(p: int, command: Dictionary) -> void:
	if p != 1:
		return
	if game.turn_number == 6 and command.get("cmd") == "play":
		var played = game.card(int(command.get("uid", -1)))
		if played != null and played.id == "corn_dog":
			corn_dog_uid = played.uid
		elif played != null and played.id == "wall_of_ears":
			wall_of_ears_uid = played.uid
			_set_step(Step.JAKE_FINAL_NOTICE)
			await _next_pressed
	elif game.turn_number == 6 and command.get("cmd") == "attack" \
			and int(command.get("lane", -1)) == _opponent_lane(baby_lane):
		_set_step(Step.WALL_HIT_NOTICE)
		await _next_pressed
	if game.turn_number == 2 and command.get("cmd") == "attack":
		_set_step(Step.ARCHER_SUMMARY)
		await _next_pressed
	elif game.turn_number == 4 and command.get("cmd") == "play":
		var c = game.card(int(command.get("uid", -1)))
		if c != null and c.id == "husker_knight":
			husker_uid = c.uid
			_set_step(Step.KNIGHT_NOTICE)
			await _next_pressed


func _find_hand_card(p: int, id: String) -> int:
	for c in game.players[p].hand:
		if c.id == id:
			return c.uid
	return -1


func _opponent_lane(lane: int) -> int:
	var across: Array = game.across(0, lane)
	return int(across[1])


func pick_command(g, p: int) -> Dictionary:
	if p != 1:
		return {"cmd": "end_turn"}
	if g.turn_number == 2:
		if ai_first_stage == 0:
			ai_first_stage = 1
			var archer := _find_hand_card(1, "archer_dan")
			if archer < 0:
				push_error("Basic tutorial: Jake's Archer Dan is missing from his hand.")
				return {"cmd": "end_turn"}
			return {"cmd": "play", "uid": archer, "lane": jinn_lane}
		if ai_first_stage == 1:
			ai_first_stage = 2
			return {"cmd": "begin_attack"}
		if ai_first_stage == 2:
			ai_first_stage = 3
			return {"cmd": "attack", "lane": jinn_lane}
		if ai_first_stage == 3:
			return {"cmd": "end_turn"}
		return {"cmd": "end_turn"}
	if g.turn_number == 6:
		match ai_final_stage:
			0:
				ai_final_stage = 1
				var corn_dog := _find_hand_card(1, "corn_dog")
				var corn_lane := _opponent_lane(jinn_lane)
				if corn_dog < 0 or not g.can_play(1, corn_dog, corn_lane):
					push_error("Basic tutorial: Jake cannot play Corn Dog opposite Finn's Djinn.")
					return {"cmd": "end_turn"}
				return {"cmd": "play", "uid": corn_dog, "lane": corn_lane}
			1:
				ai_final_stage = 2
				var wall := _find_hand_card(1, "wall_of_ears")
				var wall_lane := _opponent_lane(baby_lane)
				if wall < 0 or not g.can_play(1, wall, wall_lane):
					push_error("Basic tutorial: Jake cannot play Wall of Ears opposite the Architect.")
					return {"cmd": "end_turn"}
				return {"cmd": "play", "uid": wall, "lane": wall_lane}
			2:
				ai_final_stage = 3
				return {"cmd": "begin_attack"}
			3:
				ai_final_stage = 4
				return {"cmd": "attack", "lane": _opponent_lane(baby_lane)}
			4:
				ai_final_stage = 5
				return {"cmd": "attack", "lane": _opponent_lane(jinn_lane)}
		return {"cmd": "end_turn"}
	if g.turn_number == 4:
		match ai_second_stage:
			0:
				ai_second_stage = 1
				var husker := _find_hand_card(1, "husker_knight")
				if husker < 0:
					push_error("Basic tutorial: Jake's Husker Knight is missing from his hand.")
					return {"cmd": "end_turn"}
				return {"cmd": "play", "uid": husker, "lane": baby_lane}
			1:
				ai_second_stage = 2
				return {"cmd": "begin_attack"}
			2:
				ai_second_stage = 3
				return {"cmd": "attack", "lane": baby_lane}
		return {"cmd": "end_turn"}
	return {"cmd": "end_turn"}
