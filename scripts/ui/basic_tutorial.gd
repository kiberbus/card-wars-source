extends Node
## Scripted Finn-versus-Jake tutorial layered over the regular game and board.

const UI = preload("res://scripts/ui/ui_kit.gd")
const WoodUI = preload("res://scripts/ui/wood_ui.gd")
const Phone = preload("res://scripts/ui/phone.gd")

const FINN_START := ["blood_fortress", "ancient_scholar", "cool_dog", "spirit_soldier", "struzann_jinn"]
const JAKE_START := ["evil_eye", "archer_dan", "celestial_castle", "wall_of_ears", "corn_dog"]
const FINN_TOP := ["woad_talisman", "gnome_snot", "nice_ice_baby", "the_pig", "teleport", "psionic_architect"]
const JAKE_TOP := ["corn_scepter", "husker_knight"]

var main
var board
var game
var free_agent
var state := "goal"
var phase_title := "Начало хода"
var phase_body := "Подготовь карты, получи 2 действия и возьми карту из колоды."
var hint_panel: PanelContainer
var hint_title: Label
var hint_body: Label
var next_button: Button
var phase_panel: PanelContainer
var phase_label: Label
var phase_body_label: Label
var skip_button: Button
var overlay: Control
var focus_controls: Array = []
var focus_lands: Array = []
var highlighted_uids: Array = []
var jinn_lane := -1
var baby_lane := -1
var pig_lane := -1
var pig_destination := -1
var knight_lane := -1
var free_notice_shown := false
var archer_played := false
var husker_played := false


static func configure_game(g) -> void:
	_configure_player(g, 0, FINN_START, FINN_TOP)
	_configure_player(g, 1, JAKE_START, JAKE_TOP)


static func _configure_player(g, side: int, starter: Array, top_down: Array) -> void:
	var player = g.players[side]
	var pool: Array = player.deck.duplicate()
	pool.append_array(player.hand)
	player.hand.clear()
	for id: String in starter:
		player.hand.append(_take_card(pool, id))
	var top_cards: Array = []
	for id: String in top_down:
		top_cards.append(_take_card(pool, id))
	pool.sort_custom(func(a, b):
		return a.id < b.id if a.id != b.id else a.uid < b.uid)
	player.deck = pool
	for i in range(top_cards.size() - 1, -1, -1):
		player.deck.append(top_cards[i])


static func _take_card(pool: Array, id: String):
	for i in pool.size():
		if pool[i].id == id:
			return pool.pop_at(i)
	assert(false, "Tutorial deck is missing card: " + id)
	return null


func setup(owner_node, game_board, g, agent) -> void:
	main = owner_node
	board = game_board
	game = g
	free_agent = agent
	board.tutorial = self
	_build_ui()
	_set_step("goal")


func _build_ui() -> void:
	overlay = Control.new()
	overlay.name = "BasicTutorialOverlay"
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.draw.connect(_draw_focus)
	board.add_child(overlay)

	phase_panel = PanelContainer.new()
	phase_panel.position = Vector2(16, 132 if Phone.active else 72)
	phase_panel.size = Vector2(405, 150 if Phone.active else 190)
	phase_panel.add_theme_stylebox_override("panel", WoodUI.window(18, 18))
	phase_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(phase_panel)
	var phase_box := VBoxContainer.new()
	phase_box.add_theme_constant_override("separation", 6)
	phase_panel.add_child(phase_box)
	phase_label = WoodUI.label_fixed("", 30 if Phone.active else 28, WoodUI.GOLD, 6)
	phase_box.add_child(phase_label)
	phase_body_label = WoodUI.label_fixed("", 24 if Phone.active else 20, UI.CREAM, 5, UI.UI_FONT)
	phase_body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	phase_box.add_child(phase_body_label)

	hint_panel = PanelContainer.new()
	hint_panel.position = Vector2(470, 18)
	hint_panel.size = Vector2(950, 285 if Phone.active else 166)
	hint_panel.add_theme_stylebox_override("panel", WoodUI.window(18, 18))
	hint_panel.mouse_filter = Control.MOUSE_FILTER_PASS
	overlay.add_child(hint_panel)
	var hint_box := VBoxContainer.new()
	hint_box.add_theme_constant_override("separation", 5)
	hint_panel.add_child(hint_box)
	hint_title = WoodUI.label_fixed("", 28 if Phone.active else 25, WoodUI.GOLD, 5)
	hint_box.add_child(hint_title)
	hint_body = WoodUI.label_fixed("", 24 if Phone.active else 19, UI.CREAM, 4, UI.UI_FONT)
	hint_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint_box.add_child(hint_body)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	hint_box.add_child(row)
	next_button = WoodUI.button_fixed("Далее", UI.GREEN, 30 if Phone.active else 22,
			Vector2(240, Phone.TOUCH) if Phone.active else Vector2(180, 44))
	next_button.pressed.connect(_advance)
	row.add_child(next_button)

	skip_button = WoodUI.button_fixed("Пропустить", UI.PURPLE, 28 if Phone.active else 19,
			Vector2(240, Phone.TOUCH) if Phone.active else Vector2(170, 44))
	skip_button.position = Vector2(16, 16)
	skip_button.pressed.connect(_skip)
	overlay.add_child(skip_button)

	# The tutorial memo and the enlarged card preview share the left column.
	board.preview_rect.position = Vector2(16, 305 if Phone.active else 285)
	board.preview_rect.size = Vector2(330, 465) if Phone.active else Vector2(350, 490)
	board.preview_rect.pivot_offset = board.preview_rect.size * 0.5
	board.preview_info.position = Vector2(16, 782)
	board.preview_info.size = Vector2(360, 92)


func _set_phase(title: String, body: String) -> void:
	phase_title = title
	phase_body = body
	if is_instance_valid(phase_label):
		phase_label.text = title
		phase_body_label.text = body


func _set_step(next_state: String) -> void:
	state = next_state
	focus_controls = []
	focus_lands = []
	var title := ""
	var body := ""
	var can_continue := true
	match state:
		"goal":
			title = "Цель и земли"
			body = "Снизь жизни соперника до 0. Тип и количество земель определяют, какие карты можно разыграть."
			focus_controls = _hero_panels()
			focus_lands = [[0, 0], [0, 1], [0, 2], [0, 3]]
		"interface":
			title = "Карты и действия"
			body = "Стоимость — вверху слева, тип земли — справа, атака и защита — снизу. В первый ход нельзя атаковать и использовать ФЛЮП."
			focus_controls = [board.actions_widget, board.preview_rect]
			focus_lands = [[0, 0], [0, 1], [0, 2], [0, 3]]
		"play_jinn":
			title = "Призови существо"
			body = "Выбери Джинна Стрюзана и сыграй его в любую свою зону за 2 действия."
			can_continue = false
		"turn1_end":
			title = "Завершение первого хода"
			body = "Действия потрачены. В первый ход нельзя атаковать или использовать ФЛЮП. Нажми «Завершить ход»."
			can_continue = false
		"turn2_start":
			title = "Начало хода 2"
			body = "Подготовленные карты готовы, действия восстановились, а верхняя карта — «Гномьи сопли» — уже взята. В первом ходу Финн получил безопасную карту по обычному правилу добора."
			focus_controls = [board.preview_rect]
		"play_gnome":
			title = "Заклинание и сброс"
			body = "Сыграй «Гномьи сопли» за 1 действие. Заклинания дают мгновенный эффект и сразу уходят в Сброс."
			can_continue = false
			focus_lands = []
		"baby_info":
			title = "Радужное существо"
			body = "Радужные карты можно играть на земли любого типа. Существо стоимостью 0 не тратит действия. Выставь «Прохладного младенца» на свободную линию без существа Джейка."
			focus_lands = []
		"play_baby":
			title = "Сыграй «Прохладного младенца»"
			body = "Выбери карту в руке и свободную зону напротив пустой зоны Джейка."
			can_continue = false
			focus_lands = []
		"fortress_info":
			title = "Строения"
			body = "Строение можно выложить в любую свою зону, даже с существом. Оно остаётся на поле и даёт постоянный бонус. Поставь «Кровавую крепость» рядом с Джинном."
			focus_lands = []
		"play_fortress":
			title = "Сыграй «Кровавую крепость»"
			body = "Выбери крепость в руке и зону Джинна."
			can_continue = false
			focus_lands = []
		"battle2_info":
			title = "Фаза боя"
			body = "Подготовленные существа должны атаковать. Младенец ударит по жизням Джейка, а Джинн сразится с Лучником Дэном: урон наносится одновременно, даже если существо погибает."
			focus_lands = []
		"battle2_begin":
			title = "Начни бой"
			body = "Нажми «В атаку!», затем выбери подготовленные существа. Завершение хода само проведёт оставшиеся обязательные атаки."
			can_continue = false
		"knight_pause":
			title = "Кожурыцарь"
			body = "Обрати внимание: он получает +1 к атаке и +2 к защите за каждое кукурузное поле Джейка. Его характеристики меняются, когда поле переворачивается."
			focus_lands = [[1, 0], [1, 1], [1, 2], [1, 3]]
		"pig_flipped":
			title = "Поле перевёрнуто"
			body = "Свинья перевернула кукурузное поле. Посмотри, как уменьшились атака и защита Кожурыцаря."
			focus_lands = [[1, pig_lane]]
		"pig_flipped_again":
			title = "Второе поле перевёрнуто"
			body = "Кожурыцарь ослаб ещё сильнее: его сила зависит от числа активных кукурузных полей."
			focus_lands = [[1, pig_lane]]
		"turn3_start":
			title = "Начало хода 3"
			body = "Восстановились 2 действия, подготовились карты, и Финн взял «Архитектора разума»."
			focus_controls = [board.preview_rect]
			focus_lands = []
		"play_pig":
			title = "Призови Свинью"
			body = "За 1 действие выставь Свинью на свободную линию напротив активного кукурузного поля."
			can_continue = false
			focus_lands = []
		"pig_floop_info":
			title = "ФЛЮП"
			body = "Поворот карты набок активирует способность, но карта не сможет атаковать. Свинья переворачивает кукурузное поле напротив."
			focus_lands = []
		"pig_floop":
			title = "Флюпни Свинью"
			body = "Выбери Свинью на поле и используй её ФЛЮП."
			can_continue = false
		"teleport_info":
			title = "Телепорт"
			body = "Сыграй Телепорт за 0 действий, выбери флюпнутую Свинью и перемести её на другую свободную линию напротив активного кукурузного поля."
			focus_lands = []
		"play_teleport":
			title = "Перемести Свинью"
			body = "Сыграй Телепорт и выбери Свинью, затем выделенную свободную зону."
			can_continue = false
		"architect_info":
			title = "Архитектор разума"
			body = "Поставь Архитектора за последнее действие напротив Кожурыцаря. Его способность вернёт флюпнутую Свинью в подготовленное положение."
			focus_lands = []
		"play_architect":
			title = "Сыграй Архитектора"
			body = "После розыгрыша выбери Свинью целью его способности."
			can_continue = false
		"repeat_floop_info":
			title = "Второй ФЛЮП"
			body = "Свинья снова подготовлена и стоит напротив другого активного кукурузного поля. Используй её ФЛЮП ещё раз."
			focus_lands = []
		"repeat_floop":
			title = "Флюпни Свинью повторно"
			body = "Выбери Свинью и активируй её способность."
			can_continue = false
		"battle3_info":
			title = "Бой хода 3"
			body = "Подготовленные существа атакуют: Архитектор сражается с ослабленным Кожурыцарем. Флюпнутая Свинья в атаке не участвует."
			focus_lands = []
		"battle3_begin":
			title = "Начни бой"
			body = "Нажми «В атаку!» и проведи атаки подготовленных существ."
			can_continue = false
		"free":
			title = "Обучение завершено"
			body = "Ты освоил розыгрыш карт, заклинания, строения, ФЛЮП и бой! Продолжай игру самостоятельно, чтобы победить Джейка."
			focus_lands = []
		_:
			title = ""
			body = ""
			can_continue = false
	hint_title.text = title
	hint_body.text = body
	hint_panel.visible = title != ""
	next_button.visible = can_continue and state != "free"
	_refresh_targets()
	overlay.queue_redraw()
	board._update_hud()


func _advance() -> void:
	match state:
		"goal": _set_step("interface")
		"interface": _set_step("play_jinn")
		"turn2_start": _set_step("play_gnome")
		"baby_info": _set_step("play_baby")
		"fortress_info": _set_step("play_fortress")
		"battle2_info": _set_step("battle2_begin")
		"knight_pause":
			state = "ai_battle"
			board.hold_ai = maxi(0, board.hold_ai - 1)
			_set_step("ai_battle")
		"pig_flipped": _set_step("teleport_info")
		"pig_flipped_again": _set_step("battle3_info")
		"turn3_start": _set_step("play_pig")
		"pig_floop_info": _set_step("pig_floop")
		"teleport_info": _set_step("play_teleport")
		"architect_info": _set_step("play_architect")
		"repeat_floop_info": _set_step("repeat_floop")
		"battle3_info": _set_step("battle3_begin")
		"free": pass


func on_event(ev: Dictionary) -> void:
	match ev.get("type", ""):
		"turn_start":
			var p := int(ev["p"])
			if p == 0 and game.turn_number == 3 and state == "turn1_end":
				_set_step("turn2_start")
			elif p == 0 and game.turn_number == 5 and state in ["knight_pause", "ai_battle"]:
				_set_step("turn3_start")
			elif p == 0 and game.turn_number >= 7 and state != "free":
				_finish_guidance()
			if p == 0:
				_set_phase("Начало хода", "Подготовь карты, получи 2 действия и возьми карту из колоды.")
			else:
				_set_phase("Ход соперника", "Джейк выполняет запланированный ход.")
		"actions":
			if state != "free":
				_set_phase("Фаза действий и способностей",
					"Разыгрывай существ, строения и заклинания; добирай карту за действие и используй ФЛЮП в любом порядке.")
		"phase":
			match ev.get("phase", ""):
				"attack":
					_set_phase("Фаза боя", "Подготовленные существа должны атаковать.")
					if state == "battle2_begin":
						_set_step("battle2")
					elif state == "battle3_begin":
						_set_step("battle3")
				"handoff":
					_set_phase("Конец хода", "Ход окончен — передача хода сопернику.")
				"over":
					_set_phase("Матч завершён", "Обучение завершено.")
		"draw":
			_refresh_targets()


func on_human_command(p: int, cmd: Dictionary) -> void:
	if p != 0:
		return
	match state:
		"play_jinn":
			if cmd.get("cmd", "") == "play" and _card_id(int(cmd.get("uid", -1))) == "struzann_jinn":
				jinn_lane = int(cmd.get("lane", -1))
				_set_step("turn1_end")
		"turn1_end":
			pass
		"play_gnome":
			if _is_play(cmd, "gnome_snot"):
				_set_step("baby_info")
		"play_baby":
			if _is_play(cmd, "nice_ice_baby"):
				baby_lane = int(cmd.get("lane", -1))
				_set_step("fortress_info")
		"play_fortress":
			if _is_play(cmd, "blood_fortress"):
				_set_step("battle2_info")
		"battle2":
			_refresh_targets()
		"play_pig":
			if _is_play(cmd, "the_pig"):
				pig_lane = int(cmd.get("lane", -1))
				var candidates: Array = []
				for lane in 4:
					if lane != pig_lane and lane != jinn_lane and lane != baby_lane \
							and game.players[0].creatures[lane] == null and not game.is_frozen(0, lane):
						candidates.append(lane)
				assert(not candidates.is_empty(), "Tutorial requires a second free Finn lane")
				pig_destination = int(candidates[0])
				_set_step("pig_floop_info")
		"pig_floop":
			if cmd.get("cmd", "") == "floop" and int(cmd.get("lane", -1)) == pig_lane:
				_set_step("pig_flipped")
		"play_teleport":
			if _is_play(cmd, "teleport"):
				_set_step("architect_info")
		"play_architect":
			if _is_play(cmd, "psionic_architect"):
				knight_lane = baby_lane
				_set_step("repeat_floop_info")
		"repeat_floop":
			if cmd.get("cmd", "") == "floop" and int(cmd.get("lane", -1)) == pig_destination:
				pig_lane = pig_destination
				_set_step("pig_flipped_again")
		"battle3":
			_refresh_targets()
	_refresh_targets()


func on_ai_command(p: int, cmd: Dictionary) -> void:
	if p == 1 and cmd.get("cmd", "") == "play":
		match _card_id(int(cmd.get("uid", -1))):
			"archer_dan":
				archer_played = true
			"husker_knight":
				husker_played = true
	if p == 1 and game.turn_number == 4 and cmd.get("cmd", "") == "play" \
			and _card_id(int(cmd.get("uid", -1))) == "husker_knight":
		knight_lane = int(cmd.get("lane", -1))
		state = "knight_pause"
		board.hold_ai += 1
		_set_step("knight_pause")


func allow_command(p: int, cmd: Dictionary) -> bool:
	if state == "free" or p != 0:
		return true
	var action: String = cmd.get("cmd", "")
	match state:
		"play_jinn":
			return action == "play" and _card_id(int(cmd.get("uid", -1))) == "struzann_jinn"
		"turn1_end":
			return action == "end_turn"
		"play_gnome":
			return action == "play" and _card_id(int(cmd.get("uid", -1))) == "gnome_snot"
		"play_baby":
			return action == "play" and _card_id(int(cmd.get("uid", -1))) == "nice_ice_baby"
		"play_fortress":
			return action == "play" and _card_id(int(cmd.get("uid", -1))) == "blood_fortress"
		"battle2_begin", "battle3_begin":
			return action == "begin_attack"
		"battle2", "battle3":
			return action == "attack" and game.attackers_left(0).has(int(cmd.get("lane", -1)))
		"play_pig":
			return action == "play" and _card_id(int(cmd.get("uid", -1))) == "the_pig"
		"pig_floop":
			return action == "floop" and int(cmd.get("lane", -1)) == pig_lane
		"play_teleport":
			return action == "play" and _card_id(int(cmd.get("uid", -1))) == "teleport"
		"play_architect":
			return action == "play" and _card_id(int(cmd.get("uid", -1))) == "psionic_architect"
		"repeat_floop":
			return action == "floop" and int(cmd.get("lane", -1)) == pig_destination
	return false


func allow_card_click(uid: int) -> bool:
	if state in ["goal", "interface", "turn2_start", "baby_info", "fortress_info", "battle2_info",
			"knight_pause", "pig_flipped", "pig_flipped_again", "turn3_start", "pig_floop_info", "teleport_info", "architect_info",
			"repeat_floop_info", "battle3_info", "free"]:
		return true
	var id := _card_id(uid)
	match state:
		"play_jinn": return id == "struzann_jinn"
		"play_gnome": return id == "gnome_snot"
		"play_baby": return id == "nice_ice_baby"
		"play_fortress": return id == "blood_fortress"
		"play_pig": return id == "the_pig"
		"play_teleport": return id == "teleport"
		"play_architect": return id == "psionic_architect"
		"pig_floop": return _card_on_lane(uid, pig_lane)
		"repeat_floop": return _card_on_lane(uid, pig_destination)
		"battle2", "battle3":
			var where: Dictionary = game.where(uid)
			return where.get("p", -1) == 0 and where.get("zone", "") == "creature" \
					and game.attackers_left(0).has(int(where.get("lane", -1)))
	return false


func blocks_field_click() -> bool:
	return state not in ["free", "goal", "interface", "turn2_start", "baby_info", "fortress_info",
			"battle2_info", "knight_pause", "pig_flipped", "pig_flipped_again", "turn3_start", "pig_floop_info", "teleport_info",
			"architect_info", "repeat_floop_info", "battle3_info"]


func reject_action() -> void:
	board.flash_note("Следуй подсказке, чтобы продолжить обучение.")


func allow_drop(uid: int, target: Dictionary) -> bool:
	if not allow_command(0, {"cmd": "play", "uid": uid, "lane": int(target.get("lane", -1))}):
		return false
	var id := _card_id(uid)
	var lane := int(target.get("lane", -1))
	match id:
		"nice_ice_baby":
			return lane >= 0 and game.players[1].creatures[lane] == null
		"blood_fortress":
			return lane == jinn_lane
		"the_pig":
			return lane >= 0 and lane != jinn_lane and lane != baby_lane \
					and game.players[1].creatures[lane] == null and not game.players[1].lands[lane]["flipped"]
		"psionic_architect":
			return lane == baby_lane and game.players[1].creatures[lane] != null \
					and game.players[1].creatures[lane].id == "husker_knight"
		"teleport":
			return lane == -1
	return true


func filter_choice(req: Dictionary) -> Dictionary:
	var out := req.duplicate(true)
	var kind: String = out.get("kind", "")
	if state == "play_teleport":
		if kind == "creature":
			out["options"] = out.get("options", []).filter(func(o):
				return _card_on_lane_uid(int(o["p"]), int(o["lane"]), _pig_uid()))
		elif kind == "lane":
			out["options"] = out.get("options", []).filter(func(o):
				return int(o.get("p", -1)) == 0 and int(o.get("lane", -1)) == pig_destination)
	elif state == "play_architect" and kind == "creature":
		out["options"] = out.get("options", []).filter(func(o):
			return _card_on_lane_uid(int(o["p"]), int(o["lane"]), _pig_uid()))
		out["optional"] = false
	return out


func filter_menu_items(items: Array) -> Array:
	if state == "pig_floop" or state == "repeat_floop":
		return items.filter(func(item): return str(item[0]).begins_with("ФЛЮП"))
	if state in ["battle2", "battle3"]:
		return items.filter(func(item): return item[0] == "Атаковать")
	return []


func ai_command(g, p: int) -> Dictionary:
	if p != 1:
		return {"cmd": "end_turn"}
	if g.turn_number == 2:
		if g.phase == "main":
			if not archer_played:
				var archer := _hand_uid(1, "archer_dan")
				assert(archer >= 0 and g.can_play(1, archer, jinn_lane),
						"Tutorial cannot play Archer Dan opposite Finn's Djinn")
				return {"cmd": "play", "uid": archer, "lane": jinn_lane}
			return {"cmd": "end_turn"}
	if g.turn_number == 4:
		if g.phase == "main":
			if not husker_played:
				var husker := _hand_uid(1, "husker_knight")
				assert(husker >= 0 and baby_lane >= 0 and g.can_play(1, husker, baby_lane),
						"Tutorial cannot play Husker Knight opposite Nice Ice Baby")
				return {"cmd": "play", "uid": husker, "lane": baby_lane}
			if not g.attackers_left(1).is_empty():
				return {"cmd": "begin_attack"}
			return {"cmd": "end_turn"}
		if g.phase == "attack":
			var attackers: Array = g.attackers_left(1)
			if attackers.has(knight_lane):
				return {"cmd": "attack", "lane": knight_lane}
			if not attackers.is_empty():
				return {"cmd": "attack", "lane": attackers[0]}
			return {"cmd": "end_turn"}
	if g.turn_number == 6:
		if g.phase == "main":
			return {"cmd": "begin_attack"} if not g.attackers_left(1).is_empty() else {"cmd": "end_turn"}
		if g.phase == "attack":
			var attackers: Array = g.attackers_left(1)
			return {"cmd": "attack", "lane": attackers[0]} if not attackers.is_empty() else {"cmd": "end_turn"}
	if state == "free" and free_agent != null:
		return free_agent.pick_command(g, p)
	return {"cmd": "end_turn"}


func pick_command(g, p: int) -> Dictionary:
	return ai_command(g, p)


func pick_command_async(g, p: int) -> Dictionary:
	return ai_command(g, p)


func ban_command(_before: int, _cmd: Dictionary) -> void:
	pass


func button_enabled() -> bool:
	if state == "free":
		return true
	if state == "turn1_end":
		return game.phase == "main" and game.turn_player == 0
	if state in ["battle2_begin", "battle3_begin"]:
		return game.phase == "main" and game.turn_player == 0 and not game.attackers_left(0).is_empty()
	return false


func update_board_ui() -> void:
	if state == "free":
		return
	board.main_button.disabled = not button_enabled()
	board.main_button.disabled = board.main_button.disabled or board._busy or board._choice != null
	board.draw_button.disabled = true
	board.hero_button.disabled = true
	board.undo_button.visible = false


func on_hud_event() -> void:
	_refresh_targets()


func _finish_guidance() -> void:
	state = "free"
	board.ai_agent = free_agent
	_set_phase("Фаза действий и способностей",
		"Разыгрывай карты, используй способности и планируй бой.")
	_set_step("free")
	if not free_notice_shown:
		free_notice_shown = true
		skip_button.text = "В меню"
		board.flash_note("Обучение завершено — теперь играй самостоятельно!")
		_hide_free_hint()


func _hide_free_hint() -> void:
	await get_tree().create_timer(6.0).timeout
	if state == "free" and is_instance_valid(hint_panel):
		hint_panel.visible = false


func _skip() -> void:
	main._end_game()
	main.show_title()


func _hero_panels() -> Array:
	return [board.hero_ui["bottom"]["panel"], board.hero_ui["top"]["panel"]]


func _is_play(cmd: Dictionary, id: String) -> bool:
	return cmd.get("cmd", "") == "play" and _card_id(int(cmd.get("uid", -1))) == id


func _card_id(uid: int) -> String:
	var c = game.card(uid) if uid >= 0 else null
	return c.id if c != null else ""


func _hand_uid(p: int, id: String) -> int:
	for c in game.players[p].hand:
		if c.id == id:
			return c.uid
	return -1


func _pig_uid() -> int:
	for lane in 4:
		var c = game.players[0].creatures[lane]
		if c != null and c.id == "the_pig":
			return c.uid
	return -1


func _card_on_lane(uid: int, lane: int) -> bool:
	if lane < 0:
		return false
	var c = game.players[0].creatures[lane]
	return c != null and c.uid == uid


func _card_on_lane_uid(side: int, lane: int, uid: int) -> bool:
	if side < 0 or side >= game.players.size() or lane < 0 or lane >= 4:
		return false
	var c = game.players[side].creatures[lane]
	return c != null and c.uid == uid


func _refresh_targets() -> void:
	for uid in highlighted_uids:
		if board.views.has(uid):
			board.views[uid].set_highlight("")
	highlighted_uids.clear()
	var ids: Array = []
	match state:
		"play_jinn": ids = ["struzann_jinn"]
		"play_gnome": ids = ["gnome_snot"]
		"play_baby": ids = ["nice_ice_baby"]
		"play_fortress": ids = ["blood_fortress"]
		"play_pig": ids = ["the_pig"]
		"play_teleport": ids = ["teleport"]
		"play_architect": ids = ["psionic_architect"]
		"pig_floop", "repeat_floop":
			var uid := _pig_uid()
			if uid >= 0:
				ids.append(uid)
		"knight_pause", "pig_flipped", "pig_flipped_again":
			if knight_lane >= 0 and game.players[1].creatures[knight_lane] != null:
				ids.append(game.players[1].creatures[knight_lane].uid)
		"battle2", "battle3":
			for lane in game.attackers_left(0):
				var c = game.players[0].creatures[lane]
				if c != null:
					ids.append(c.uid)
	for id in ids:
		var uid := int(id) if typeof(id) == TYPE_INT else _hand_uid(0, id)
		if uid >= 0 and board.views.has(uid):
			board.views[uid].set_highlight("target")
			highlighted_uids.append(uid)
	overlay.queue_redraw()


func _draw_focus() -> void:
	var focus: Array = []
	for c in focus_controls:
		if is_instance_valid(c) and c.visible:
			focus.append(_control_rect(c))
	for land in focus_lands:
		focus.append(_land_rect(int(land[0]), int(land[1])))
	if state == "interface":
		focus.append(Rect2(250, 815, 1240, 245))
	if state == "turn2_start":
		focus.append(_world_rect(board.deck_pos(0), Vector2(128, 168)))
		focus.append(Rect2(250, 815, 1240, 245))
	if state == "turn3_start":
		focus.append(_world_rect(board.deck_pos(0), Vector2(128, 168)))
		focus.append(Rect2(250, 815, 1240, 245))
	if state == "play_gnome":
		focus.append(_world_rect(board.discard_pos(0), Vector2(128, 168)))
	if state in ["play_jinn", "play_baby", "play_pig"]:
		for lane in range(4):
			if game.players[0].creatures[lane] == null \
					and (state == "play_jinn" or game.players[1].creatures[lane] == null):
				focus.append(_land_rect(0, lane))
	if state == "play_fortress" and jinn_lane >= 0:
		focus.append(_land_rect(0, jinn_lane))
	if state == "play_architect" and baby_lane >= 0:
		focus.append(_land_rect(0, baby_lane))
	if state == "play_teleport" and pig_destination >= 0:
		focus.append(_land_rect(0, pig_destination))
	for r in focus:
		overlay.draw_rect(r.grow(5), Color(1.0, 0.82, 0.2, 0.12), true)
		overlay.draw_rect(r.grow(5), Color(1.0, 0.82, 0.2, 0.95), false, 4.0)


func _control_rect(c: Control) -> Rect2:
	var transform := c.get_global_transform_with_canvas()
	var inverse := overlay.get_global_transform_with_canvas().affine_inverse()
	var points := [
		inverse * transform * Vector2.ZERO,
		inverse * transform * Vector2(c.size.x, 0),
		inverse * transform * c.size,
		inverse * transform * Vector2(0, c.size.y),
	]
	var rect := Rect2(points[0], Vector2.ZERO)
	for point in points:
		rect = rect.expand(point)
	return rect


func _land_rect(side: int, lane: int) -> Rect2:
	return _world_rect(board.land_pos(side, lane), Vector2(160, 240))


func _world_rect(center: Vector2, size: Vector2) -> Rect2:
	var inverse := overlay.get_global_transform_with_canvas().affine_inverse()
	var points := [
		inverse * board.world.to_global(center - size * 0.5),
		inverse * board.world.to_global(center + Vector2(size.x * 0.5, -size.y * 0.5)),
		inverse * board.world.to_global(center + size * 0.5),
		inverse * board.world.to_global(center + Vector2(-size.x * 0.5, size.y * 0.5)),
	]
	var rect := Rect2(points[0], Vector2.ZERO)
	for point in points:
		rect = rect.expand(point)
	return rect
