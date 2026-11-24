extends Control
## The table. Lays cards out from engine state, animates engine events
## (it is the engine's `animator`), turns mouse input into engine commands
## and answers the engine's choice requests (it is also the `chooser`).
## The active player always sits at the bottom of the screen.

signal handoff_needed
signal game_finished(winner: int)
signal menu_requested
signal chat_requested               # the chat button of an online game
signal hero_turn(hero: String)
signal desync(detail: String)
signal replay_ended(reason: String)
signal replay_seek(pos: int)       # a jump to another place of the replay: main sets the game up there
signal replay_turns                # «Ходы»: main shows the list of the replay's turns
signal _choice_done
signal _mulligan_done(changed: bool)
signal _arrange_done
signal _net_choice_arrived
signal items_requested              # Tab: «Бесконечный поезд» shows the hero's items
signal friend_requested(nick: String)   # online: «+» by the nick of the other player
signal sandbox_ai(on: bool)            # «Песочница»: the AI of the other seats wanted on or off (main makes the agents)

const CardDB = preload("res://scripts/core/card_db.gd")
const CardView = preload("res://scripts/ui/card_view.gd")
const UI = preload("res://scripts/ui/ui_kit.gd")
const SoundIndex = preload("res://scripts/ui/sound_index.gd")
const WoodUI = preload("res://scripts/ui/wood_ui.gd")
const FitCenter = preload("res://scripts/ui/fit_center.gd")
const TouchInput = preload("res://scripts/ui/touch_input.gd")
const CardZoom = preload("res://scripts/ui/card_zoom.gd")
const AIHelper = preload("res://scripts/ai/ai_helper.gd")
const Replay = preload("res://scripts/core/replay.gd")
const TrainRun = preload("res://scripts/train/train_run.gd")
const TrainWagons = preload("res://scripts/train/train_wagons.gd")
const CardBacks = preload("res://scripts/ui/card_backs.gd")
const SandboxPanel = preload("res://scripts/ui/sandbox_panel.gd")
const Phone = preload("res://scripts/ui/phone.gd")

const LANES := 4
# The table is the whole playmat (assets/ui/playmat.webp, 1800x1263) at the left of
# the screen, MAT_SCALE of its size: the lanes sit in the cells of its field, the decks
# on the decks drawn on it and the discard piles in the dashed frames next to them.
# The positions below are the playmat's own, measured on the picture, put through
# MAT_ORIGIN + MAT_SCALE * point.
static var PLAYMAT: Texture2D = load("res://assets/ui/playmat.webp")
## The phone's playmat: the top deck and discard frame drawn lower (tools/make_phone_mat.py),
## so the close view (PHONE_FOCUS) shows both rows of piles over the whole height.
static var PLAYMAT_PHONE: Texture2D = load("res://assets/ui/playmat_phone.webp")
const MAT_SCALE := 0.88
const PHONE_TOP_DY := 155.0 * MAT_SCALE
const MAT_ORIGIN := Vector2(-13.76, -15.68)
const LANE_X := [657.0, 842.0, 1027.0, 1213.0]
const LAND_Y_TOP := 411.0
const LAND_Y_BOTTOM := 668.0
const CREATURE_DY := 52.0          # creature: on the land, toward the middle of the field
const BUILDING_DY := 74.0          # building: on the land, toward its owner
const FIELD_CENTER := Vector2(935, 540)
const DECK_TOP := Vector2(414, 204)
const DECK_BOTTOM := Vector2(414, 826)
const DISCARD_TOP := Vector2(248, 224)
const DISCARD_BOTTOM := Vector2(248, 843)
const S_BOARD := 0.21
const S_BUILD := 0.14
const S_HAND := 0.36
const S_HAND_HOVER := 0.52
const S_OPP_HAND := 0.2
const S_OPEN_HAND := 0.27           # the top hand of a replay, face up
const OPEN_HAND_Y := 94.0
const S_PILE := 0.24
const S_SHOW := 0.5
const LIMBO_POS := Vector2(300, 540)   # a played spell waits left of the lanes, not over them
const PROMPT_Y := 112.0                # the choice banner sits above the lanes
const PILE_SIZE := Vector2(120, 168)
const TILE_SCALE := 0.44
const TILE_SIZE := Vector2(360, 556) * TILE_SCALE
const LAND_TEX_W := 360.0          # tile size the scales are for; the pictures are drawn to it
const CREATURE_SLOT := Vector2(114, 150)
const BUILDING_SLOT := Vector2(82, 106)
const MAT_VISIBLE := Rect2(27, 31, 1746, 1201)   # the playmat inside its transparent margin
const HUD_X := 1574.0              # right of the playmat: hero panels, turn, buttons, log
const HUD_W := 320.0
## The part of the table the field zoom (pinch, mouse wheel) shows: left of the right column.
const FIELD_VIEW := Rect2(0, 0, HUD_X - 12.0, 1080)
const ZOOM_MAX := 2.5
const PHONE_FOCUS := Rect2(170, 236, 1180, 704)    # phone: the part of the table shown big (piles, decks, lanes)
const PHONE_ZOOM_MAX := 1.8
# A phone (docs/MOBILE_UI.md): the right column is wider, its buttons a finger high (P_ROW stage
# units ≈ 116 px on a 1080 high screen), the hero panels bigger; the log a strip that opens.
const P_W := 368.0
const P_X := HUD_X + HUD_W - P_W
const P_ROW := 116.0
const P_GAP := 10.0
const P_PANEL_H := 212.0               # the hero panels (their texts bigger: _phone_panel)
const P_FONT := 24                   # the least font of the table's texts on a phone
const P_S_HAND := 0.44               # the own hand: bigger cards, each one a finger wide at least
const P_S_UP := 0.56                 # the picked card of the own hand: up whole, its text readable
const P_SEEN := 112.0                # the least width of a hand card that shows by the picked one
const P_OPEN_PART := 0.7             # less of a hand card shows: a tap opens the whole hand big
const P_HAND_CARD_MIN := 182         # the least height of a card in the open hand's rows, else one row
const P_HAND_Y := 1010.0
const UNDO_W := 58.0                # the undo button right of the draw button
const UNDO_GAP := 10.0
## 2 на 2: the table of the rulebook, no playmat. A square: the viewer sits at its bottom side,
## the teammate at the top, the opponents left and right. Each lane runs across a corner, so the
## two spots of a lane mirror each other over a diagonal of the square. As players lay it out on
## a real table, the lands of a corner make a block of four: a seat's two left landscapes lie in a row
## along the diagonal to its left corner, turned to it, and the two of the opponent they face lie
## right across, the outer lane outside. Every seat's spots are the viewer's turned round the
## center by a quarter turn a seat; the cards on them turn with them.
const T_CENTER := Vector2(780, 470)
const T_HALF := 470.0                                   # half the side of the square
## Lane 0 at 402 from the center along the diagonal, lane 1 at 270, both 107 off it
## (u * r + n * 107 with u = (-1, 1) / √2, n = (1, 1) / √2); lanes 2 and 3 mirror them.
const T_LANE_POS := [Vector2(-208.6, 359.9), Vector2(-115.3, 266.6), Vector2(115.3, 266.6), Vector2(208.6, 359.9)]
const T_TILE_SCALE := 0.34
const T_CREATURE_DY := 42.0                             # toward the spot across the lane
const T_BUILDING_DY := 60.0                             # away from it
const T_S_BOARD := 0.18
const T_S_BUILD := 0.125
const T_S_HAND := 0.3
const T_S_PILE := 0.15
const T_CREATURE_SLOT := Vector2(98, 132)
const T_BUILDING_SLOT := Vector2(72, 96)
## Seat places on the screen by seat relative to the viewer (0 = the viewer, 1 = the next
## seat on the left, 2 = the teammate, 3 = on the right): decks, discard piles, hands.
const T_DECK := [Vector2(90, 900), Vector2(90, 470), Vector2(90, 110), Vector2(1470, 470)]
const T_DISCARD := [Vector2(190, 900), Vector2(190, 470), Vector2(190, 110), Vector2(1370, 470)]
## The teammate's hand lies open in the free corner top right (teammates may see each other's cards).
const T_HAND := [Vector2(780, 1045), Vector2(140, 330), Vector2(1405, 150), Vector2(1420, 330)]
const T_S_MATE_HAND := 0.15
## На троих: the same table for three, a hexagon cut in three: the viewer at the bottom, the next
## seat up left, the seat before up right. A lane runs across a corner as in 2 на 2; the corners
## are a third of a turn apart, so the landscapes turn a twelfth of a turn to them.
const T3_CENTER := Vector2(780, 525)
const T3_HALF := 540.0                                  # from the center to a corner of the hexagon
## Lane 0 at 390 from the center toward the bottom left corner, lane 1 at 258, both 107 off that line
## (u * r + n * 107 with u = (-√3/2, 1/2), n = (1/2, √3/2)); lanes 2 and 3 mirror them.
const T3_LANE_POS := [Vector2(-284.2, 287.7), Vector2(-169.9, 221.7), Vector2(169.9, 221.7), Vector2(284.2, 287.7)]
## Seat places by seat relative to the viewer: 0 the viewer, 1 the next seat (up left), 2 up right.
const T3_DECK := [Vector2(90, 900), Vector2(90, 330), Vector2(1470, 330)]
const T3_DISCARD := [Vector2(190, 900), Vector2(190, 330), Vector2(1370, 330)]
const T3_HAND := [Vector2(780, 1045), Vector2(140, 190), Vector2(1420, 190)]

var game = null
var teams := false               # the table round the seats: 2 на 2, на троих till a player drops out
var tri := false                 # на троих on that table
var seated := false              # more than two seats (2 на 2, на троих): AI and people by seat
var _duel_layout: Array = []     # [control, position, size] of the playmat table, kept while the round one is up
var viewer := 0
var hide_hands := false
var views: Dictionary = {}

var world: Node2D
var decor: Node2D
var hud: Control
var land_sprites := [[], [], [], []]
var land_icons := [[], [], [], []]
var piles := []
var hero_ui := {}
var turn_label: Label
var phase_label: Label
var actions_widget: Control
var main_button: Button
var draw_button: Button
var hero_button: Button
var log_panel: PanelContainer
var wagon_label: Label              # «Бесконечный поезд»: the rule of the wagon
var log_box: RichTextLabel
var preview_rect: TextureRect
var preview_info: Label
var prompt_panel: PanelContainer
var prompt_label: Label
var skip_button: Button
var context_menu: VBoxContainer
var mulligan_panel: PanelContainer
var mulligan_title: Label
var mulligan_change: Button
var arrange_panel: PanelContainer
var arrange_title: Label

# Land arrangement before the game (decks with two land types).
var _arranging := -1
var _arr_types: Array = []
var _arr_pick := -1
var banner: Label
var inspect_layer: CanvasLayer
var inspect_rect: TextureRect
var picker_layer: CanvasLayer
var zoom_layer: CanvasLayer          # the big card over a list of cards (CardZoom)
var picker_grid: HFlowContainer
var picker_scroll: ScrollContainer     # a big pile scrolls instead of running off the screen
var picker_buttons: HBoxContainer      # «Закрыть» / «Пропустить», always under the cards
var picker_title: Label

var _busy := false
var _choice = null
var _choice_result = null
var _hover_view = null
var _hover_hero := -1          # side whose hero panel is under the mouse
var _peek_view = null          # a finger hovers over nothing: the card it last tapped is shown on the left
var _peek_hero := -1           # ... or the hero panel it last tapped
var _hero_pics := {}           # hero card -> its full picture, or its path while it is read (_hero_card_texture)
var _drag_view = null
var _drag_offset := Vector2.ZERO
var _press_view = null
var _press_pos := Vector2.ZERO
## A press that went down while a choice was asked: it picks on the release (not on the press),
## so a held finger or the right button can look at the card first.
var _choice_press := false
var _choice_view = null          # the card under that press
var _press_canvas := Vector2.ZERO  # where the left button went down, on the screen (canvas)
var _zoom := 1.0                 # the field zoom: world is scaled by it and moved by _pan
var _pan := Vector2.ZERO          # the shift of the zoomed field (world.position, plus a shake)
var _pan_at := Vector2.INF       # a press on bare table, in board coordinates: dragging it moves the field
var _panning := false            # that press became a move of the field: its release is no click
var _touches := {}               # finger index -> point (board coordinates), for the pinch
var _side_req := 0.0             # the screen beyond the 1920 wide table on each side (main.gd _layout)
var _phone_req := false
var _side := 0.0                 # phone: the field reaches over that room, the right column to the screen's edge
var _phone := false
var _home_zoom := 1.0            # the field as it is shown at first (a phone: its middle, bigger)
var _home_pan := Vector2.ZERO
var _screen_dx := 0.0            # the hands and the cards on show follow the middle of the field
var _column: Array[Control] = [] # the right column of the HUD
var _ph := false                 # a phone's HUD (Phone.active): every table
var _desk := {}                  # a control of the column -> [position, size] it has on a PC
var _menu_btn: Button
var _log_lines: PackedStringArray = []   # the log as BBCode lines (the big log of the pad)
var _log_big := false            # a phone: the log opened over the table
var _room_key := ""              # what _apply_room has set the table for
var _selected_uid := -1
var _drop_targets: Array = []
var _limbo: Array = []
var _revealed: Array = []          # uids opened by a «reveal»: shown face up by the lanes to both players
var _revealed_zone: Dictionary = {} # uid -> the zone it was opened in; it leaves the show when it moves
var _reveal_batch := 0              # counts reveals; the newest one owns the show
var _shake := 0.0
var _time := 0.0
static var _land_tex: Dictionary = {}    # "corn_2_flipped" -> picture; read when a table first shows it
var _symbols := {}
var _slot_box := UI.box(Color(0.05, 0.03, 0.08, 0.32), 14, 2, Color(1, 1, 1, 0.22))
var _empty_deck_box := UI.box(Color(0.12, 0.07, 0.03, 0.66), 14)
var _mat_nodes: Array = []      # the playmat and its shadow (2 на 2 has none)
var _table: Sprite2D             # the playmat
var _table_bg: Node2D = null    # 2 на 2: the fronts drawn under the landscapes

# Online play (lockstep): both machines run the same engine with the same
# seed. Each side sends only its own commands and choices; the other side
# replays them, so the two games never need to exchange state.
var net = null                  # the Net autoload while playing online
var _foe_nick := ""             # online, a game for two: the other player's nick on its hero panel
var _foe_add: Button = null     # ... and the button that asks it to be friends
var local_player := -1          # this machine's seat in an online game
var ai_agent: Object = null     # PPO agent if playing vs AI
var ai_player := -1             # AI player index (usually 1)
var _ai_turn_running := false
var ai_vs_ai := false           # Both sides are AI — spectator mode
var ai_agent_2: Object = null   # Second PPO agent (player 0 in ai-vs-ai)
var ai_paused := false          # spectator pause in AI-vs-AI
var ai_speed := 1.0             # spectator speed in AI-vs-AI, one of SPEEDS
var seat_agents := {}           # 2 на 2: seat -> AI agent of every AI seat
var humans: Array = []          # 2 на 2: seats played from this PC by people
var ai_names: Array = []        # 2 на 2 online: seats another PC's AI plays (their names get "(ИИ)")
var net_pcs: Array = []         # 2 на 2 online: game seat -> room seat of the PC that plays it (-1: the host's AI)
static var turn_speed := 1.0    # speed of the moves on the table, from the settings, one of SPEEDS
var hold_ai := 0                # menus open over the table: AI waits
var _ai_hero_skip := {}         # seat -> turn when its hero ability did nothing
var net_accept := false         # remote commands may run (game has started)
var _net_cmds: Array = []
var _net_choices: Array = []
var _net_seq_out := 0
var _net_seq_in := 0
var _net_seq_from := {}         # 2 на 2 online: the last command number of each sending PC (its room seat)
# Online turn timer, the room creator's choice: the turn player's time runs while the
# table waits for them; at zero their own machine ends the turn.
var turn_time := 0              # seconds per turn, 0 = no timer
var undo_online := false        # online: the room creator allowed one undo per turn
var undo_button: Button
var _undo_point: Dictionary = {}   # state before the last command that may be taken back
var _undo_used := -1            # turn number of the last undo: one per turn
var _set_next := {}             # tournament: the organizer's new turn_time / undo and "n", the turn they start at
var _clock_left := 0.0
var _clock_key := ""            # the turn the clock counts: "turn number:player"
var _clock_shown := -1          # whole seconds on the hero panel tag
var _chooser := -1              # online: the seat answering a choice right now
# Replay playback (scripts/core/replay.gd): the recorded steps move the game, the
# spectator buttons pause it and change the speed, the hero button changes sides.
var enemy_intro: Callable = Callable()   # «Бесконечный поезд», a double wagon: shows the second enemy (main.gd)
var replay_steps = null         # the steps while a replay plays
var _opened := false            # the first turn has begun: its tune and the heroes' greeting are done
var live_replay := false        # «Наблюдать»: the steps keep coming from the host of an online match
var _replay_pos := 0
var _replay_running := false
var _seek_to := -1              # a jump the playback makes once the current step is played
var turns_button: Button
var chat_button: Button
var _chat_unread := 0
var _concede_wanted := false      # на троих online: this PC's player gives up as soon as it is their turn
var _stats_tip: Control = null   # «Бесконечный поезд»: the hero stats under the mouse
var _kb_id := ""                # the table's keyboard frame: the id of what it stands on (_kb_targets)
var _kb_draw: Control           # draws that frame over the table
var _kb_lit = null               # the card that shows the frame (CardView.focused)
var _kb_covered := false         # a window of the main screen is over the table (_kb_free)
var _kb_cover_frame := -1
var _mulligan_keep: Button
## «Песочница» (scripts/core/sandbox.gd): the table is set up by hand, every seat is played from
## here unless its AI is on, all hands are open, and «Шаг назад» takes back any step.
var sandbox = null
var sb_panel: Control = null        # its panel at the left (scripts/ui/sandbox_panel.gd)
var sb_button: Button               # shows and hides the panel
var _sb_press := Vector2.INF        # a press on the table while the panel is open: a tap picks what is under it
var _sb_turn := ""                  # the turn the table last turned to (the viewer follows the turn player)
var _arrange_button: Button
var tutorial = null
var tutorial_land_targets: Array = []
var tutorial_building_targets: Array = []
var tutorial_world_targets: Array = []


func _ready() -> void:
	size = Vector2(1920, 1080)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for kind in CardDB.land_types():
		_symbols[kind] = load("res://assets/ui/symbol_%s.png" % kind)
	_build_world()
	_build_hud()
	_build_overlays()
	if _kn() != null:
		_kn().claim(self)


func start(g) -> void:
	game = g
	game.animator = self
	game.chooser = self
	viewer = game.first_player
	seated = game.players.size() > 2
	_fit_table()
	_apply_room()
	sync()
	_update_hud()
	_prefetch_cards()


## The card pictures of this game start reading in the background, the hands first, so
## neither the table nor a choice of cards stops to read them. 2 на 2 only the hands (four
## decks of pictures are too much memory); sync adds every new hand card.
func _prefetch_cards() -> void:
	var ids := []
	for ps in game.players:
		for c in ps.hand:
			if not ids.has(c.id):
				ids.append(c.id)
	if not teams:
		for ps in game.players:
			for c in ps.deck:
				if not ids.has(c.id):
					ids.append(c.id)
	CardView.prefetch(ids, true)
	for ps in game.players:
		_hero_card_texture(ps.hero_card, true)


## 2 на 2: AI seats and the people at this PC. With nobody at it the table only watches.
func enable_seats(agents: Dictionary, people: Array) -> void:
	seat_agents = agents
	humans = people.duplicate()
	ai_vs_ai = people.is_empty()
	local_player = people[0] if people.size() == 1 else -1
	viewer = people[0] if not people.is_empty() else 0
	hide_hands = false
	for key in hero_ui:
		hero_ui[key]["side"] = -1
	sync()


## Switches the table to AI mode: AI sits at `p_ai`, human at `p_human`.
func enable_ai(agent: Object, p_ai: int, p_human: int) -> void:
	ai_agent = agent
	ai_player = p_ai
	local_player = p_human
	viewer = p_human
	hide_hands = false
	for key in hero_ui:
		hero_ui[key]["side"] = -1
	sync()


## Switches the table to AI-vs-AI spectator mode.
func enable_ai_vs_ai(agent_0: Object, agent_1: Object) -> void:
	ai_agent = agent_1
	ai_agent_2 = agent_0
	ai_player = 1
	ai_vs_ai = true
	local_player = -1         # no human player
	viewer = 0                # spectate from player 0's side
	hide_hands = false
	for key in hero_ui:
		hero_ui[key]["side"] = -1
	sync()


## Switches the table to replay playback, seen from `seat`'s side. start_replay() runs it
## from step `pos` (the game on the table has the steps before it played).
func enable_replay(steps: Array, seat: int, pos := 0) -> void:
	replay_steps = steps
	_replay_pos = pos
	local_player = -1
	viewer = seat
	hide_hands = false
	for key in hero_ui:
		hero_ui[key]["side"] = -1
	sync()


## «Песочница»: every seat is played from this screen (the AI takes the other seats when it is
## switched on, sb_set_ai), all hands are open, the panel at the left changes the table.
func enable_sandbox(sb) -> void:
	sandbox = sb
	local_player = 0
	viewer = game.turn_player
	hide_hands = false
	if seated:
		humans = range(game.players.size())
		seat_agents = {}
	sb_panel = SandboxPanel.new()
	hud.add_child(sb_panel)
	sb_panel.setup(self)
	sb_button.visible = true
	for key in hero_ui:
		hero_ui[key]["side"] = -1
	_room_key = ""
	_apply_room()
	_update_hud()


## «Песочница»: the AI plays the seats of `agents` (seat -> agent), {} gives every seat back to the player.
func sb_set_ai(agents: Dictionary) -> void:
	if seated:
		seat_agents = agents
		humans = range(game.players.size()).filter(func(s): return not agents.has(s))
	else:
		ai_agent = agents.get(1)
		ai_player = 1 if ai_agent != null else -1
	if _is_ai_seat(viewer):
		set_viewer(0)
	for key in hero_ui:
		hero_ui[key]["side"] = -1
	sync()
	_update_hud()
	sb_panel.refresh()
	trigger_ai_turn()


func sb_ai_on() -> bool:
	return ai_agent != null or not seat_agents.is_empty()


## A change of the sandbox (a Callable that awaits the Sandbox): it may be taken back.
func sb_do(op: Callable) -> void:
	if sandbox == null or _busy or _choice != null:
		return
	sandbox.push()
	await _run(op)
	sandbox.settle()
	for key in hero_ui:
		hero_ui[key]["side"] = -1      # a hero may have changed: its card and name again
	_update_hud()
	sb_panel.refresh()


func sb_undo() -> void:
	if sandbox == null or _busy or _choice != null or not sandbox.can_undo():
		return
	sandbox.undo()
	_sb_restored("— Шаг назад")


func sb_reset() -> void:
	if sandbox == null or _busy or _choice != null:
		return
	sandbox.reset()
	_sb_restored("— Стол сначала")


func _sb_restored(note: String) -> void:
	_limbo.clear()
	_revealed = []
	log_box.clear()
	_log_lines.clear()
	for line in game.log_lines:
		_add_log(line)
	_add_log(note)
	for key in hero_ui:
		hero_ui[key]["side"] = -1
	_clear_selection()
	_sb_turn = ""
	_sb_follow()
	sync()
	_update_hud()
	sb_panel.forget_target()
	sb_panel.refresh()
	trigger_ai_turn()


## The table turns to the player whose turn has begun (when it is played from this screen).
func _sb_follow() -> void:
	var key := "%d:%d" % [game.turn_number, game.turn_player]
	if key == _sb_turn:
		return
	_sb_turn = key
	if _plays(game.turn_player) and viewer != game.turn_player:
		set_viewer(game.turn_player)


## A tap on the table while the panel is open: the card or the land under it goes to the panel.
func _sb_tap(wpos: Vector2, v) -> void:
	if v != null:
		var w: Dictionary = game.where(v.uid)
		if ["creature", "building", "hand", "teamwork"].has(w["zone"]):
			sb_panel.pick_card(v.uid)
			return
	for side in game.sides():
		for lane in LANES:
			if _shape_has(_land_shape(side, lane), wpos):
				sb_panel.pick_land(side, lane)
				return


## Spectator table: AI against AI, or a replay.
func _watching() -> bool:
	return ai_vs_ai or replay_steps != null


## The seat of the one person playing at this screen, -1 when there is none (AI against AI,
## a replay) or more than one (on one device).
func my_seat() -> int:
	if _watching():
		return -1
	if net != null or ai_agent != null or (seated and humans.size() == 1):
		return local_player
	return -1


## The seat across the table from this screen's player (whose fight music plays): the
## first other side, the second seat when nobody or everybody plays here.
func rival_seat() -> int:
	var me := my_seat()
	if me < 0:
		return 1 if game.players.size() > 1 else 0
	for p in game.players.size():
		if p != me and (not game.teams() or game.team(p) != game.team(me)):
			return p
	return 1 - mini(me, 1)


## The hero whose voice a seat speaks with (its hero card, else its deck), "" for none.
func speaker(p: int) -> String:
	if p < 0 or p >= game.players.size():
		return ""
	var ps = game.players[p]
	for id: String in [String(ps.hero_card), String(ps.hero)]:
		var base := id.trim_suffix("_classic").trim_suffix("_promo").trim_suffix("_ks1")
		if SoundIndex.LINES.has(base):
			return base
	return ""


## Seat p's hero says a line for a moment of the fight (Sfx.hero_voice).
func _say(p: int, event: String, chance := 1.0, force := false) -> bool:
	var sfx := get_node_or_null("/root/Sfx")
	var hero := speaker(p)
	if sfx == null or hero == "":
		return false
	return sfx.hero_voice(hero, event, chance, force)


## The end of a game: a winner cheers, or if no winner has a voice, a loser sighs.
func _end_words(winner: int) -> void:
	var wins := []
	var loses := []
	for p in game.players.size():
		var won: bool = game.team(p) == winner if game.teams() else p == winner
		(wins if won else loses).append(p)
	for p in wins:
		if _say(p, "win", 1.0, true):
			return
	for p in loses:
		if _say(p, "lose", 1.0, true):
			return


## Seat p is played by a person at this PC (online: this PC's own seat). На троих the one who
## dropped out only watches: the side at the bottom then is somebody else's, not theirs to play or see.
func _plays(p: int) -> bool:
	if _watching() or p < 0 or p >= game.players.size() or game.is_out(p):
		return false
	if sandbox != null:
		return not _is_ai_seat(p)
	if net != null:
		return p == local_player
	if seated:
		return humans.has(p)
	if ai_agent != null:
		return p == local_player
	return true


## 2 на 2 online, the host's table: the AI plays these seats here, and every command and
## choice of theirs goes to the other PCs like a player's.
func set_seat_agents(agents: Dictionary) -> void:
	seat_agents = agents
	for key in hero_ui:
		hero_ui[key]["side"] = -1
	sync()


## 2 на 2 online, the host's table: the player of seat p left, the AI plays on for them.
## A choice the table waits for from that seat gets the AI's answer.
func takeover_seat(p: int, agent: Object) -> void:
	seat_agents[p] = agent
	for key in hero_ui:
		hero_ui[key]["side"] = -1
	_net_choice_arrived.emit()      # a choice waited for from that seat: _remote_choice answers it now
	_update_hud()
	trigger_ai_turn()


## Switches the table to online mode: this machine always sits at `seat`.
func enable_net(net_node, seat: int, turn_seconds := 0, undo := false) -> void:
	net = net_node
	turn_time = turn_seconds
	undo_online = undo
	local_player = seat
	viewer = seat
	hide_hands = false
	for key in hero_ui:
		hero_ui[key]["side"] = -1    # refresh names with the "(ты)" tag
	sync()


func is_online() -> bool:
	return net != null


## Online, a game for two: the other player's nick goes on its hero panel, by its deck count;
## `can_add`: a «+» next to it asks that player to be friends.
func set_foe(nick: String, can_add: bool) -> void:
	_foe_nick = nick
	var ui: Dictionary = hero_ui.get("top", {})
	if ui.is_empty():
		return
	if _foe_add == null:
		_foe_add = WoodUI.button_fixed("+", UI.GREEN, 26, Vector2(40, 40))
		_foe_add.tooltip_text = "В друзья"
		_foe_add.position = Vector2(HUD_W - 46, 164)    # by the deck count, under the hit points
		_foe_add.pressed.connect(func(): friend_requested.emit(_foe_nick))
		ui["panel"].add_child(_foe_add)
	_foe_add.visible = can_add and nick != ""
	ui["side"] = -1
	_update_hud()


## The chat button over the log (online games).
func show_chat_button(on: bool) -> void:
	chat_button.visible = on
	_update_hud()


func set_chat_unread(n: int) -> void:
	_chat_unread = n
	if chat_button != null:
		chat_button.get_child(0).queue_redraw()


## A chat message of the match in the log: the nick in gold, no BBCode of the other PC.
func add_chat_log(nick: String, text: String) -> void:
	log_box.append_text("[color=#ffd75a]%s:[/color] [color=#f6efe0]%s[/color]
" % [nick.replace("[", "[lb]"), text.replace("[", "[lb]")])


## Tournament: the organizer changed the time per turn or the undo. Both sides take the new
## values at the start of turn n, so a remote undo is judged the same way on both.
func queue_settings(n: int, seconds: int, undo: bool) -> void:
	_set_next = {"n": n, "turn_time": seconds, "undo": undo}
	_apply_settings()


func _apply_settings() -> void:
	if _set_next.is_empty() or game == null or game.turn_number < int(_set_next["n"]):
		return
	turn_time = int(_set_next["turn_time"])
	undo_online = bool(_set_next["undo"])
	_set_next = {}
	_clock_key = ""         # the turn gets the new time
	if not undo_online:
		_undo_point = {}
	if turn_time <= 0:
		_show_clock(false)
	_update_hud()


## A line over the table for a few seconds (and in the log).
func flash_note(text: String) -> void:
	_add_log(text)
	var l := WoodUI.label(text, 30, UI.CREAM, 8, UI.UI_FONT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	l.reset_size()
	l.position = Vector2((size.x - l.size.x) * 0.5, size.y * 0.18)
	var tw := l.create_tween()
	tw.tween_interval(4.0)
	tw.tween_property(l, "modulate:a", 0.0, 0.8)
	tw.tween_callback(l.queue_free)


## Feeds a "cmd" or "choice" message from the other player.
func net_receive(data: Dictionary) -> void:
	match data["t"]:
		"cmd":
			_net_cmds.append(data)
		"choice":
			_net_choices.append([data.get("r"), data.get("s", 0)])
			_net_choice_arrived.emit()


## The fields every command needs, and their kind (anything else in it is not read).
const NET_CMD_FIELDS := {"play": {"uid": TYPE_INT, "lane": TYPE_INT}, "floop": {"kind": TYPE_STRING, "lane": TYPE_INT},
	"activate": {"kind": TYPE_STRING, "lane": TYPE_INT}, "thaw": {"lane": TYPE_INT}, "attack": {"lane": TYPE_INT},
	"hero": {}, "draw": {}, "begin_attack": {}, "end_turn": {}, "undo": {}, "concede": {}}


## A command from another PC is played only when it is for a seat that PC plays, in that
## seat's turn, and has the fields of a real command: a changed game on the other side can't
## move for us or slip in something the table never sends. Else the game stops matching.
func _remote_cmd_ok(d: Dictionary) -> bool:
	_apply_settings()
	if not (d.get("p") is int and d.get("c") is Dictionary and d.get("n") is int and d.get("h") is int):
		return false
	if d.has("tl") and not (d["tl"] is float or d["tl"] is int):
		return false
	var p: int = d["p"]
	if p != game.turn_player or p == local_player or seat_agents.has(p) or not _remote_seat_ok(p, d.get("s", 0)):
		return false
	var c: Dictionary = d["c"]
	var fields = NET_CMD_FIELDS.get(c.get("cmd"))
	if not (c.get("cmd") is String) or fields == null:
		return false
	for key: String in fields:
		if typeof(c.get(key)) != fields[key]:
			return false
	if c.has("hero") and not (c["hero"] is bool):
		return false
	return c["cmd"] != "undo" or _undo_mode()


## 2 на 2: seat p is played by the PC `pc` (its room seat; the host, 0, plays the AI seats).
func _remote_seat_ok(p: int, pc) -> bool:
	if not seated or net_pcs.is_empty():
		return true
	if not (pc is int) or p < 0 or p >= net_pcs.size():
		return false
	return int(net_pcs[p]) == pc or (pc == 0 and (int(net_pcs[p]) < 0 or ai_names.has(p)))


## Ends the game without the engine (surrender).
func force_over(winner_seat: int) -> void:
	if game.journal != null:
		game.journal.append({"t": "over", "w": winner_seat})
	game.phase = "over"
	game.winner = winner_seat
	net_accept = false
	_clear_selection()
	_update_hud()


# ================================================================ geometry

func is_bottom(side: int) -> bool:
	return side == viewer


## 2 на 2: a seat as seen from the viewer: 0 the viewer, 1 the left opponent (the next
## seat), 2 the teammate, 3 the right opponent. На троих 1 the next seat up left, 2 up right.
func _rel(side: int) -> int:
	var n: int = game.players.size()
	return (side - viewer + n) % n


## How a landscape is turned: its top points across the lane. 2 на 2 a quarter turn a seat
## and an eighth to its corner (на троих a third and a twelfth); in a game for two the top
## side's landscapes are upside down.
func _land_rot(side: int, lane: int) -> float:
	if teams:
		var n: int = game.players.size()
		var half := PI * 0.5 - PI / n
		return (-half if lane < 2 else half) + _rel(side) * TAU / n
	return 0.0 if is_bottom(side) else PI


## How the cards on a landscape are turned (in a game for two they stand upright).
func _card_rot(side: int, lane: int) -> float:
	return _land_rot(side, lane) if teams else 0.0


## The direction across the lane from a landscape, toward the other spot.
func _across_dir(side: int, lane: int) -> Vector2:
	return Vector2.UP.rotated(_land_rot(side, lane))


## A turned rectangle on the table: {"c": center, "s": size, "r": rotation}.
static func _shape(center: Vector2, sz: Vector2, rot := 0.0) -> Dictionary:
	return {"c": center, "s": sz, "r": rot}


static func _shape_has(sh: Dictionary, point: Vector2, grow := 0.0) -> bool:
	var local: Vector2 = (point - sh["c"]).rotated(-float(sh["r"]))
	var sz: Vector2 = sh["s"] + Vector2(grow, grow) * 2.0
	return Rect2(-sz * 0.5, sz).has_point(local)


func _land_shape(side: int, lane: int) -> Dictionary:
	return _shape(land_pos(side, lane), _tile_size(), _land_rot(side, lane))


func _draw_shape(sh: Dictionary, col: Color, filled := true, width := 2.0, box: StyleBox = null) -> void:
	decor.draw_set_transform(sh["c"], sh["r"])
	var r := Rect2(-sh["s"] * 0.5, sh["s"])
	if box != null:
		decor.draw_style_box(box, r)
	else:
		decor.draw_rect(r, col, filled, width if not filled else -1.0)
	decor.draw_set_transform(Vector2.ZERO, 0.0)


func _tile_scale() -> float:
	return T_TILE_SCALE if teams else TILE_SCALE


func _tile_size() -> Vector2:
	return Vector2(360, 556) * _tile_scale()


func _creature_slot() -> Vector2:
	return T_CREATURE_SLOT if teams else CREATURE_SLOT


func _building_slot() -> Vector2:
	return T_BUILDING_SLOT if teams else BUILDING_SLOT


func _pile_scale() -> float:
	return T_S_PILE if teams else S_PILE


func _pile_size() -> Vector2:
	return PILE_SIZE * _pile_scale() / S_PILE


func _center() -> Vector2:
	if teams:
		return T3_CENTER if tri else T_CENTER
	return FIELD_CENTER


func creature_pos(side: int, lane: int) -> Vector2:
	var dy := T_CREATURE_DY if teams else CREATURE_DY
	return land_pos(side, lane) + _across_dir(side, lane) * dy


func building_pos(side: int, lane: int) -> Vector2:
	var dy := T_BUILDING_DY if teams else BUILDING_DY
	return land_pos(side, lane) - _across_dir(side, lane) * dy


## Extra buildings (Крепкий лесоруб) fan out from the main building slot.
func building_slot_pos(side: int, lane: int, kind: String) -> Vector2:
	var base := building_pos(side, lane)
	if kind.begins_with("xb"):
		var i := int(kind.substr(2)) + 1
		if teams:
			return base + Vector2(21.0 * i, 10.0 * i).rotated(_land_rot(side, lane))
		return base + Vector2(25.0 * i, (11.0 if is_bottom(side) else -11.0) * i)
	return base


func land_pos(side: int, lane: int) -> Vector2:
	if teams:
		return _center() + (T3_LANE_POS if tri else T_LANE_POS)[lane].rotated(_rel(side) * TAU / game.players.size())
	return Vector2(LANE_X[_mat_column(side, lane)], LAND_Y_BOTTOM if is_bottom(side) else LAND_Y_TOP)


## The column of the playmat a lane is in. На троих after a player dropped out the top row goes
## right to left, as lanes face each other there (game.across).
func _mat_column(side: int, lane: int) -> int:
	return LANES - 1 - lane if not is_bottom(side) and game != null and game.duel() else lane


## On the deck drawn on the playmat (the top card of the pile).
func deck_pos(side: int) -> Vector2:
	if teams:
		return (T3_DECK if tri else T_DECK)[_rel(side)]
	if is_bottom(side):
		return DECK_BOTTOM
	return DECK_TOP + Vector2(0, PHONE_TOP_DY if _phone else 0.0)


## In the dashed frame next to the deck.
func discard_pos(side: int) -> Vector2:
	if teams:
		return (T3_DISCARD if tri else T_DISCARD)[_rel(side)]
	if is_bottom(side):
		return DISCARD_BOTTOM
	return DISCARD_TOP + Vector2(0, PHONE_TOP_DY if _phone else 0.0)


## The командная карта of a player (Парный турнир): by the discard pile, toward the middle.
func teamwork_pos(side: int) -> Vector2:
	if teams:
		var rel := _rel(side)
		return (T3_DISCARD if tri else T_DISCARD)[rel] + Vector2(0, 95 if rel == 2 or (tri and rel == 1) else -95)
	if _phone and not is_bottom(side):
		return deck_pos(side) + Vector2(0, 200)    # the piles are closer: under the discard it would meet the other one
	return discard_pos(side) + Vector2(0, -200 if is_bottom(side) else 200)


## The hero card in the hero panel.
func hero_anchor(side: int) -> Vector2:
	var key := _panel_key(side)
	var panel: Panel = hero_ui[key]["panel"]
	if teams and hero_ui[key]["portrait2"].visible:
		var portrait: TextureRect = hero_ui[key]["portrait"] if _panel_seats(key)[0] == side else hero_ui[key]["portrait2"]
		return panel.position + portrait.position + portrait.size * 0.5
	return panel.position + Vector2(78, 106)


## The hero panel of a seat: "bottom" for the viewer's side (2 на 2: team), "top" for the other.
func _panel_key(side: int) -> String:
	if teams:
		return "bottom" if game.team(side) == game.team(viewer) else "top"
	return "bottom" if is_bottom(side) else "top"


## 2 на 2: the two seats a hero panel shows, left to right: the viewer and the teammate
## below, the left and the right opponent on top (на троих the viewer alone below).
func _panel_seats(key: String) -> Array:
	if tri:
		return [viewer] if key == "bottom" else [(viewer + 1) % 3, (viewer + 2) % 3]
	if key == "bottom":
		return [viewer, (viewer + 2) % 4]
	return [(viewer + 1) % 4, (viewer + 3) % 4]


func _slot_rect(center: Vector2, sz: Vector2) -> Rect2:
	return Rect2(center - sz * 0.5, sz)


# ================================================================ construction

## The width of the screen beyond the 1920x1080 table on each side (main.gd _layout); a phone
## (`phone`) cuts the table to its middle and makes it bigger over the whole width.
func set_side_room(extra: float, phone: bool) -> void:
	_side_req = extra
	_phone_req = phone
	_apply_room()


## 2 на 2 keeps its square table; the others on a phone: the field fills the screen to the left
## of the right column, at a zoom that shows PHONE_FOCUS over the whole height.
func _apply_room() -> void:
	if game == null or world == null:
		return
	var on := _phone_req and not teams
	var side := _side_req if on else 0.0
	var key := "%s %d %s" % [on, roundi(side), Phone.active]
	if key == _room_key:
		return
	_room_key = key
	_phone = on
	_side = side
	_layout_column(Phone.active)
	_table.texture = PLAYMAT_PHONE if on else PLAYMAT
	for c in _column:
		c.position.x = c.get_meta("base_x") + side
	var field := world.get_parent() as Control
	field.position = Vector2(-side, FIELD_VIEW.position.y)
	field.size = Vector2(FIELD_VIEW.size.x + 2.0 * side, FIELD_VIEW.size.y)
	_home_zoom = 1.0
	_home_pan = Vector2(side, 0.0)
	if on:
		_home_zoom = clampf(minf(field.size.x / PHONE_FOCUS.size.x, field.size.y / PHONE_FOCUS.size.y), 1.0, PHONE_ZOOM_MAX)
		_home_pan = field.size * 0.5 - PHONE_FOCUS.get_center() * _home_zoom
	_set_cam(_home_zoom, _home_pan)
	_home_pan = _pan
	_screen_dx = _pan.x + FIELD_CENTER.x * _zoom - FIELD_CENTER.x
	banner.position.x = FIELD_CENTER.x + _hud_dx() - banner.size.x * 0.5
	preview_rect.position.x = 15.0 - side
	preview_info.position.x = 15.0 - side
	if sb_panel != null:
		sb_panel.place(Vector2(8.0 - _side_req, 8.0), _ph)      # at the screen's edge, the round tables too
	sync()


## The right column for a phone (`ph`) or a PC: on a phone it is wider and its buttons a finger
## high; the hero panels are drawn bigger (P_PANEL). The PC places are kept to go back to
## (the board is made once per game; tests switch the layout).
func _layout_column(ph: bool) -> void:
	if _desk.is_empty():
		for c in _column:
			_desk[c] = [c.position, c.size]
		for key in hero_ui:
			var panel: Control = hero_ui[key]["panel"]
			_desk[panel] = [panel.position, panel.size]
	_ph = ph
	for c in _desk:
		c.position = _desk[c][0]
		c.size = _desk[c][1]
		c.scale = Vector2.ONE
		c.set_meta("base_x", c.position.x)
	var undo_arrow: Control = undo_button.get_child(0)
	undo_arrow.position = Vector2(UNDO_W * 0.5, 25)
	undo_arrow.scale = Vector2.ONE
	if not ph:
		return
	var rows := P_PANEL_H + 18.0          # the first row under the top hero panel
	var place := func(c: Control, x: float, y: float, w: float, h: float):
		c.position = Vector2(x, y)
		c.custom_minimum_size = Vector2(w, h)
		c.size = Vector2(w, h)
		c.set_meta("base_x", x)
	var column: Control = _column[0]
	place.call(column, P_X - 12.0, 6.0, P_W + 24.0, 1068.0)
	for key in hero_ui:
		var panel: Control = hero_ui[key]["panel"]
		panel.position = Vector2(P_X + (P_W - HUD_W) * 0.5, 10.0 if key == "top" else 1070.0 - P_PANEL_H)
		panel.set_meta("base_x", panel.position.x)
		if not teams or (tri and key == "bottom"):
			_phone_panel(hero_ui[key])
		else:
			_phone_team_panel(hero_ui[key])
	# Row 1: whose turn and the actions; the menu at the right. Then the stage of the turn.
	var info_w := P_W - P_ROW - P_GAP
	place.call(turn_label, P_X, rows + 4.0, info_w, 48.0)
	place.call(actions_widget, P_X, rows + 62.0, info_w, 46.0)
	place.call(phase_label, P_X + 2.0, rows + P_ROW + 4.0, P_W - 4.0, 36.0)
	place.call(_menu_btn, P_X + P_W - P_ROW, rows, P_ROW, P_ROW)
	_menu_btn.set_meta("phone", true)
	_menu_btn.add_theme_font_size_override("font_size", 44)
	place.call(chat_button, P_X + P_W - 2.0 * P_ROW - P_GAP, rows, P_ROW, P_ROW)
	chat_button.get_child(0).scale = Vector2.ONE * 2.0
	chat_button.get_child(0).position = Vector2(6, 6)
	rows += 40.0                          # the line of the turn's stage
	# Row 2: the main button; row 3: the draw button and undo (or the turns of a replay).
	var y2 := rows + P_ROW + P_GAP
	place.call(main_button, P_X, y2, P_W, P_ROW)
	main_button.add_theme_font_size_override("font_size", 40)
	var y3 := y2 + P_ROW + P_GAP
	place.call(draw_button, P_X, y3, P_W - P_ROW - P_GAP, P_ROW)
	draw_button.add_theme_font_size_override("font_size", 30)
	place.call(undo_button, P_X + P_W - P_ROW, y3, P_ROW, P_ROW)
	undo_arrow.position = Vector2(P_ROW * 0.5, P_ROW * 0.5 - 4.0)
	undo_arrow.scale = Vector2.ONE * 2.0
	place.call(turns_button, P_X + P_W * 0.5 + 5.0, y3, P_W * 0.5 - 5.0, P_ROW)
	turns_button.add_theme_font_size_override("font_size", 28)
	# Row 4: the hero's ability or the sandbox; then the strip of the log down to the bottom panel.
	var y4 := y3 + P_ROW + P_GAP
	place.call(hero_button, P_X, y4, P_W, P_ROW)
	# The sandbox's button: at the left top of the field, by its panel (the column has no room).
	sb_button.position = Vector2(12.0, 12.0)
	sb_button.custom_minimum_size = Vector2(250, P_ROW)
	sb_button.size = Vector2(250, P_ROW)
	sb_button.set_meta("base_x", 12.0 - _side_req - _side)
	sb_button.add_theme_font_size_override("font_size", 30)
	place.call(log_panel, P_X, y4, P_W, 1070.0 - P_PANEL_H - P_GAP - y4)
	log_box.add_theme_font_size_override("normal_font_size", 22)
	log_box.mouse_filter = Control.MOUSE_FILTER_IGNORE     # a tap reaches the strip: it opens the log
	place.call(wagon_label, P_X + 2.0, y4, P_W - 4.0, 92.0)
	wagon_label.label_settings.font_size = P_FONT
	# The windows over the table: bigger letters and buttons.
	preview_info.label_settings.font_size = 30
	prompt_label.label_settings.font_size = 32
	skip_button.custom_minimum_size = Vector2(240, P_ROW)
	skip_button.add_theme_font_size_override("font_size", 30)
	for b: Button in [_mulligan_keep, mulligan_change, _arrange_button]:
		b.custom_minimum_size = Vector2(300, P_ROW)
		b.add_theme_font_size_override("font_size", 36)


## A phone: a hero panel of a game for two with big texts: a smaller hero card, the name, the
## hit points, the cards in hand, deck and discard pile one under the other.
func _phone_panel(ui: Dictionary) -> void:
	ui["portrait"].position = Vector2(8, 8)
	ui["portrait"].size = Vector2(112, 157)
	ui["name"].position = Vector2(128, 2)
	ui["name"].size = Vector2(186, 44)
	ui["name"].clip_text = true
	ui["name"].text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var heart := _heart(ui["panel"])
	heart.position = Vector2(128, 44)
	heart.label_settings.font_size = 38
	ui["hp"].position = Vector2(170, 30)
	ui["hp"].size = Vector2(140, 72)
	ui["hp"].label_settings.font_size = 64
	ui["info"].position = Vector2(128, 100)
	ui["info"].size = Vector2(188, 110)
	ui["info"].label_settings.font_size = 28
	ui["info"].label_settings.line_spacing = -8.0
	ui["turn"].position = Vector2(10, 160)
	ui["turn_text"].label_settings.font_size = P_FONT
	ui["side"] = -1


## A phone: a panel of two seats (2 на 2, the opponents на троих): the hero cards tell who is
## who (the names are by the seats on the table); the hit points and the hands in big letters.
func _phone_team_panel(ui: Dictionary) -> void:
	if not ui.has("portrait2") or not ui["portrait2"].visible:
		return
	ui["portrait"].size = Vector2(98, 150)
	ui["portrait2"].size = Vector2(98, 150)
	ui["name"].visible = false
	ui["name2"].visible = false
	ui["info"].position = Vector2(212, 128)
	ui["info"].size = Vector2(104, 80)
	ui["info"].label_settings.font_size = 28
	ui["turn"].position = Vector2(4, 160)
	ui["turn2"].position = Vector2(106, 160)
	ui["turn_text"].label_settings.font_size = P_FONT
	ui["turn_text2"].label_settings.font_size = P_FONT
	ui["side"] = -1


## A phone: the log over the table, big (`on`), or back to its strip in the column.
func phone_log_open(on: bool) -> void:
	if not _ph:
		return
	_log_big = on
	if on:
		log_box.visible = true
		wagon_label.visible = false
	log_box.add_theme_font_size_override("normal_font_size", 28 if on else 22)
	log_panel.z_index = 40 if on else 0
	if on:
		var w := 1100.0
		log_panel.position = Vector2(P_X + P_W - w + _side, 120.0)
		log_panel.size = Vector2(w, 820.0)
	else:
		log_panel.position.x = log_panel.get_meta("base_x") + _side
		_update_hud()
	log_box.scroll_to_line(maxi(0, log_box.get_line_count() - 1))


## The field's middle at its first zoom, from where the HUD (board coordinates) puts it.
func _hud_dx() -> float:
	return _screen_dx - _side


func _field_rect() -> Rect2:
	var field := world.get_parent() as Control
	return Rect2(field.position, field.size)


func _build_world() -> void:
	# A zoomed field is cut at the right column and the screen's edges (not at 100%: the
	# playmat's shadow reaches a little out of the stage).
	var field := Control.new()
	field.size = FIELD_VIEW.size
	field.position = FIELD_VIEW.position
	field.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(field)
	world = Node2D.new()
	field.add_child(world)

	# The backdrop pictures (main.gd) show around the playmat; it casts a soft shadow on them.
	var shadow := Panel.new()
	shadow.position = MAT_ORIGIN + MAT_VISIBLE.position * MAT_SCALE
	shadow.size = MAT_VISIBLE.size * MAT_SCALE
	var ssb := UI.box(Color(0, 0, 0, 0.35), 44)
	ssb.shadow_size = 26
	ssb.shadow_color = Color(0, 0, 0, 0.55)
	ssb.shadow_offset = Vector2(0, 8)
	shadow.add_theme_stylebox_override("panel", ssb)
	shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shadow.z_index = -21
	world.add_child(shadow)
	_mat_nodes.append(shadow)
	# Drawn a little smaller than the picture: no mipmaps, so it stays sharp.
	var table := Sprite2D.new()
	_table = table
	table.texture = PLAYMAT
	table.centered = false
	table.position = MAT_ORIGIN
	table.scale = Vector2.ONE * MAT_SCALE
	table.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	table.z_index = -20
	world.add_child(table)
	_mat_nodes.append(table)

	for side in 4:
		for lane in LANES:
			var s := Sprite2D.new()
			s.scale = Vector2.ONE * TILE_SCALE
			s.modulate = Color(0.8, 0.8, 0.82)
			s.z_index = -10
			world.add_child(s)
			land_sprites[side].append(s)
			var icon := Sprite2D.new()
			icon.scale = Vector2.ONE * 0.27
			icon.z_index = -9
			world.add_child(icon)
			land_icons[side].append(icon)

	decor = Node2D.new()
	decor.z_index = -8
	decor.draw.connect(_draw_decor)
	world.add_child(decor)

	for side in 4:
		var pile := Node2D.new()
		pile.z_index = 1
		pile.visible = false
		# The top card lies on the top card drawn on the mat, the ones under it
		# stick out down and left like the drawn ones.
		for i in 3:
			var b := Sprite2D.new()
			_set_back(b)
			b.position = Vector2(-(2 - i) * 2.5, (2 - i) * 3.5)
			pile.add_child(b)
		world.add_child(pile)
		piles.append(pile)


func _build_hud() -> void:
	hud = Control.new()
	hud.size = size
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.z_index = 250
	add_child(hud)

	# The right column sits on dark glass over the backdrop pictures.
	var column := Panel.new()
	column.position = Vector2(HUD_X - 12, 6)
	column.size = Vector2(HUD_W + 24, 1068)
	column.add_theme_stylebox_override("panel", _wood_column())
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(column)
	for key in ["top", "bottom"]:
		hero_ui[key] = _make_hero_panel(key == "top")

	# Right of the playmat, between the hero panels: turn and the menu, actions, buttons, log.
	turn_label = WoodUI.label_fixed("", 32)
	turn_label.position = Vector2(HUD_X, 248)
	hud.add_child(turn_label)
	var menu_btn := WoodUI.button_fixed("≡", UI.PURPLE, 28, Vector2(52, 52))
	_menu_btn = menu_btn
	menu_btn.position = Vector2(HUD_X + HUD_W - 52, 246)
	menu_btn.pressed.connect(func(): menu_requested.emit())
	hud.add_child(menu_btn)
	chat_button = WoodUI.button_fixed("", UI.BLUE, 28, Vector2(52, 52))
	chat_button.position = Vector2(HUD_X + HUD_W - 112, 246)
	chat_button.pressed.connect(func(): chat_requested.emit())
	chat_button.visible = false
	var bubble := Control.new()
	bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bubble.set_anchors_preset(Control.PRESET_FULL_RECT)
	bubble.draw.connect(func():
		# A speech bubble with three dots.
		var r := Rect2(11, 12, 30, 21)
		bubble.draw_rect(r.grow(2), WoodUI.INK)
		bubble.draw_colored_polygon(PackedVector2Array([Vector2(16, 34), Vector2(16, 43), Vector2(25, 34)]), WoodUI.INK)
		bubble.draw_rect(r, WoodUI.PAPER)
		bubble.draw_colored_polygon(PackedVector2Array([Vector2(18, 33), Vector2(18, 39), Vector2(23, 33)]), WoodUI.PAPER)
		for i in 3:
			bubble.draw_circle(Vector2(19 + i * 7, 22.5), 2.2, WoodUI.INK)
		if _chat_unread > 0:
			bubble.draw_circle(Vector2(44, 9), 9, Color(0.85, 0.2, 0.18))
			bubble.draw_string(WoodUI.BOLD, Vector2(35, 15), str(mini(_chat_unread, 9)), HORIZONTAL_ALIGNMENT_CENTER, 18, 16, Color.WHITE))
	chat_button.add_child(bubble)
	hud.add_child(chat_button)
	phase_label = WoodUI.label_fixed("", 18, UI.CREAM, 6, UI.UI_FONT)
	phase_label.position = Vector2(HUD_X + 2, 296)
	phase_label.size = Vector2(HUD_W, 26)
	phase_label.clip_text = true
	hud.add_child(phase_label)

	actions_widget = Control.new()
	actions_widget.position = Vector2(HUD_X, 326)
	actions_widget.size = Vector2(HUD_W, 46)
	actions_widget.mouse_filter = Control.MOUSE_FILTER_IGNORE
	actions_widget.draw.connect(_draw_actions)
	hud.add_child(actions_widget)

	main_button = WoodUI.button_fixed("В атаку!", UI.RED, 32, Vector2(HUD_W, 66))
	main_button.position = Vector2(HUD_X, 380)
	main_button.pressed.connect(_on_main_button)
	hud.add_child(main_button)

	draw_button = WoodUI.button_fixed("Взять карту  −1 действие", UI.BLUE, 20, Vector2(HUD_W, 50))
	draw_button.position = Vector2(HUD_X, 460)
	draw_button.pressed.connect(_on_draw_button)
	hud.add_child(draw_button)

	undo_button = WoodUI.button_fixed("", UI.PURPLE, 20, Vector2(UNDO_W, 50))
	undo_button.position = Vector2(HUD_X + HUD_W - UNDO_W, 460)
	undo_button.pressed.connect(_on_undo_button)
	undo_button.visible = false
	var arrow := Control.new()
	arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	arrow.position = Vector2(UNDO_W * 0.5, 25)
	arrow.draw.connect(func():
		var col := Color(1, 1, 1, 0.45 if undo_button.disabled else 1.0)
		arrow.draw_arc(Vector2.ZERO, 11.0, deg_to_rad(-200.0), deg_to_rad(60.0), 24, col, 4.0, true)
		var tip := Vector2.from_angle(deg_to_rad(-200.0)) * 11.0
		arrow.draw_colored_polygon(PackedVector2Array([tip + Vector2(-7, -2), tip + Vector2(7, -2), tip + Vector2(0, 8)]), col))
	undo_button.add_child(arrow)
	hud.add_child(undo_button)

	turns_button = WoodUI.button_fixed("Ходы", UI.BLUE, 20, Vector2(HUD_W * 0.5 - 5, 50))
	turns_button.position = Vector2(HUD_X + HUD_W * 0.5 + 5, 460)
	turns_button.pressed.connect(func(): replay_turns.emit())
	turns_button.visible = false
	hud.add_child(turns_button)

	hero_button = WoodUI.button_fixed("", UI.PURPLE, 18, Vector2(HUD_W, 44))
	hero_button.position = Vector2(HUD_X, 522)
	hero_button.pressed.connect(_on_hero_button)
	hero_button.visible = false
	hud.add_child(hero_button)

	sb_button = WoodUI.button_fixed("Песочница", UI.ORANGE, 24, Vector2(HUD_W, 54))
	sb_button.position = Vector2(HUD_X, 524)
	sb_button.pressed.connect(func():
		sb_panel.visible = not sb_panel.visible
		_sb_press = Vector2.INF
		if sb_panel.visible:
			sb_panel.refresh())
	sb_button.visible = false
	hud.add_child(sb_button)

	log_panel = PanelContainer.new()
	log_panel.position = Vector2(HUD_X, 524)
	log_panel.size = Vector2(HUD_W, 306)
	var sb := WoodUI.inset(5, 12, 8)
	sb.content_margin_left = 12
	sb.content_margin_right = 10
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	log_panel.add_theme_stylebox_override("panel", sb)
	log_panel.mouse_filter = Control.MOUSE_FILTER_PASS
	log_panel.gui_input.connect(func(e: InputEvent):
		# A phone: a tap on the strip of the log opens it over the table, another closes it.
		if _ph and e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and not e.pressed 				and not TouchInput.long_pressed:
			phone_log_open(not _log_big))
	hud.add_child(log_panel)
	log_box = RichTextLabel.new()
	log_box.bbcode_enabled = true
	log_box.scroll_following = true
	log_box.add_theme_font_override("normal_font", WoodUI.REGULAR)
	log_box.add_theme_font_size_override("normal_font_size", 16)
	log_box.add_theme_color_override("default_color", Color(0.92, 0.9, 0.85))
	log_panel.add_child(log_box)
	wagon_label = WoodUI.label_fixed("", 18, UI.CREAM, 6, UI.UI_FONT)
	wagon_label.position = Vector2(HUD_X + 2, 760)
	wagon_label.size = Vector2(HUD_W - 4, 70)
	wagon_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	wagon_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	wagon_label.visible = false
	hud.add_child(wagon_label)

	# Left column: big preview of the hovered card.
	preview_rect = TextureRect.new()
	# Left of the lanes, as big as the card's own picture: its text reads without the right click.
	preview_rect.position = Vector2(15, 92)
	preview_rect.size = Vector2(490, 686)
	preview_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview_rect.material = CardView.SHARP
	preview_rect.pivot_offset = preview_rect.size * 0.5
	hud.add_child(preview_rect)
	preview_info = WoodUI.label_fixed("", 20, Color.WHITE, 6, UI.UI_FONT)
	preview_info.position = Vector2(15, 782)
	preview_info.size = Vector2(490, 90)
	preview_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	preview_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hud.add_child(preview_info)

	# Prompt banner for choices.
	prompt_panel = PanelContainer.new()
	prompt_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE    # clicks on the cards under it go through
	prompt_panel.add_theme_stylebox_override("panel", _padded(WoodUI.plate(Color(0.4, 0.85, 0.95), 3, 11, 24), 22, 8))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	prompt_panel.add_child(row)
	prompt_label = WoodUI.label_fixed("", 24, Color.WHITE, 6, UI.UI_FONT)
	prompt_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(prompt_label)
	skip_button = WoodUI.button_fixed("Пропустить", UI.PURPLE, 20, Vector2(150, 44))
	skip_button.pressed.connect(func(): _resolve_choice(null))
	row.add_child(skip_button)
	prompt_panel.visible = false
	hud.add_child(prompt_panel)

	context_menu = VBoxContainer.new()
	context_menu.add_theme_constant_override("separation", 8)
	context_menu.visible = false
	hud.add_child(context_menu)

	mulligan_panel = PanelContainer.new()
	mulligan_panel.add_theme_stylebox_override("panel", _padded(WoodUI.window(), 28, 20))
	var mv := VBoxContainer.new()
	mv.add_theme_constant_override("separation", 14)
	mulligan_panel.add_child(mv)
	mulligan_title = WoodUI.label_fixed("", 34)
	mulligan_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mv.add_child(mulligan_title)
	var sub := WoodUI.label_fixed("Если в руке меньше двух существ, руку обычно стоит сменить.\nСменить руку можно только один раз за игру.", 28 if Phone.active else 20, UI.CREAM, 5, UI.UI_FONT)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mv.add_child(sub)
	var mb := HBoxContainer.new()
	mb.alignment = BoxContainer.ALIGNMENT_CENTER
	mb.add_theme_constant_override("separation", 20)
	mv.add_child(mb)
	var keep := WoodUI.button_fixed("Оставить", UI.GREEN, 28, Vector2(240, 64))
	_mulligan_keep = keep
	keep.set_meta("kn_primary", true)       # E presses it (key_nav.gd)
	keep.pressed.connect(func(): _mulligan_done.emit(false))
	mb.add_child(keep)
	mulligan_change = WoodUI.button_fixed("Сменить руку", UI.ORANGE, 28, Vector2(260, 64))
	mulligan_change.pressed.connect(func(): _mulligan_done.emit(true))
	mb.add_child(mulligan_change)
	mulligan_panel.visible = false
	hud.add_child(mulligan_panel)

	arrange_panel = PanelContainer.new()
	arrange_panel.add_theme_stylebox_override("panel", _padded(WoodUI.window(), 28, 18))
	var av := VBoxContainer.new()
	av.add_theme_constant_override("separation", 12)
	arrange_panel.add_child(av)
	arrange_title = WoodUI.label_fixed("", 34)
	arrange_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	av.add_child(arrange_title)
	var asub := WoodUI.label_fixed("Нажми на две свои земли, чтобы поменять их местами.\nКарты требуют земель своего типа — подумай, где что будет стоять.", 28 if Phone.active else 20, UI.CREAM, 5, UI.UI_FONT)
	asub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	av.add_child(asub)
	var abox := CenterContainer.new()
	av.add_child(abox)
	var adone := WoodUI.button_fixed("Готово", UI.GREEN, 28, Vector2(240, 60))
	_arrange_button = adone
	adone.pressed.connect(func(): _arrange_done.emit())
	abox.add_child(adone)
	arrange_panel.visible = false
	hud.add_child(arrange_panel)

	banner = WoodUI.label_fixed("", 96, Color.WHITE, 22)
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	banner.size = Vector2(1920, 160)
	banner.position = FIELD_CENTER - banner.size * 0.5
	banner.pivot_offset = banner.size * 0.5
	banner.modulate.a = 0.0
	hud.add_child(banner)
	_kb_draw = Control.new()
	_kb_draw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_kb_draw.draw.connect(_draw_kb)
	hud.add_child(_kb_draw)
	for ch in hud.get_children():
		if ch is Control and ch.position.x >= HUD_X - 13.0:
			ch.set_meta("base_x", ch.position.x)
			_column.append(ch)


## Right of the playmat, top and bottom: the hero card, the name, hit points and piles beside it.
func _make_hero_panel(top: bool) -> Dictionary:
	var panel := Panel.new()
	panel.position = Vector2(HUD_X, 16 if top else 852)
	panel.size = Vector2(HUD_W, 212)
	panel.mouse_filter = Control.MOUSE_FILTER_PASS       # the hero's stats under the mouse
	panel.mouse_entered.connect(func(): _show_stats_tip("top" if top else "bottom"))
	panel.mouse_exited.connect(_hide_stats_tip)
	panel.pivot_offset = panel.size * 0.5
	hud.add_child(panel)
	var portrait := TextureRect.new()    # the hero card
	portrait.position = Vector2(10, 10)
	portrait.size = Vector2(137, 192)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait.material = CardView.SHARP
	panel.add_child(portrait)
	var name_l := WoodUI.label_fixed("", 30)
	name_l.position = Vector2(160, 8)
	panel.add_child(name_l)
	var hp := WoodUI.label_fixed("25", 68, Color.WHITE, 12)
	hp.position = Vector2(204, 44)
	hp.size = Vector2(110, 86)
	hp.pivot_offset = Vector2(44, 43)
	panel.add_child(hp)
	var heart := WoodUI.label_fixed("♥", 42, Color(0.95, 0.28, 0.3), 8)
	heart.position = Vector2(162, 62)
	panel.add_child(heart)
	var info := WoodUI.label_fixed("", 17, UI.CREAM, 5, UI.UI_FONT)
	info.label_settings.line_spacing = -5.0
	info.position = Vector2(164, 128)
	info.size = Vector2(150, 78)
	panel.add_child(info)
	var turn_tag := PanelContainer.new()
	turn_tag.add_theme_stylebox_override("panel", _padded(WoodUI.paper(WoodUI.GO, 0.0, 13, 3.0), 12, 1))
	turn_tag.position = Vector2(30, 172)
	turn_tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var turn_text := WoodUI.label_fixed("ХОДИТ", 20, Color.WHITE, 5)
	turn_tag.add_child(turn_text)
	panel.add_child(turn_tag)
	return {"panel": panel, "portrait": portrait, "name": name_l, "hp": hp, "info": info,
		"turn": turn_tag, "turn_text": turn_text, "shown_hp": 25.0, "side": -1}


## «Бесконечный поезд»: the stats of the hero under the mouse, left of its panel.
func _show_stats_tip(key: String) -> void:
	_hide_stats_tip()
	var side: int = hero_ui[key]["side"]
	if game == null or side < 0 or game.players[side].stats.is_empty():
		return
	var st: Dictionary = game.players[side].stats
	var tip := PanelContainer.new()
	tip.add_theme_stylebox_override("panel", _padded(WoodUI.plate(UI.ORANGE, 3, 12, 14), 16, 10))
	tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var v := VBoxContainer.new()
	tip.add_child(v)
	var names: Dictionary = TrainRun.STATS.merged(TrainRun.FIGHT_STATS)
	for k: String in names:
		if int(st.get(k, 0)) > 0:
			v.add_child(WoodUI.label_fixed("%s %s" % [names[k]["name"], TrainRun.stat_text(k, int(st[k]))], 24, UI.CREAM, 5))
	hud.add_child(tip)
	tip.reset_size()
	var panel: Control = hero_ui[key]["panel"]
	tip.position = Vector2(HUD_X + _side - tip.size.x - 12, panel.position.y + (0.0 if key == "top" else panel.size.y - tip.size.y))
	_stats_tip = tip


func _hide_stats_tip() -> void:
	if _stats_tip != null and is_instance_valid(_stats_tip):
		_stats_tip.queue_free()
	_stats_tip = null


func _build_overlays() -> void:
	inspect_layer = CanvasLayer.new()
	inspect_layer.layer = 15
	inspect_layer.visible = false
	add_child(inspect_layer)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(e): if e is InputEventMouseButton and e.pressed: _close_inspect())
	inspect_layer.add_child(dim)
	inspect_rect = TextureRect.new()
	inspect_rect.size = Vector2(560, 784)
	inspect_rect.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_KEEP_SIZE)
	inspect_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	inspect_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	inspect_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inspect_rect.material = CardView.SHARP
	inspect_rect.pivot_offset = inspect_rect.size * 0.5
	inspect_layer.add_child(inspect_rect)

	zoom_layer = CanvasLayer.new()
	zoom_layer.layer = 16
	add_child(zoom_layer)

	picker_layer = CanvasLayer.new()
	picker_layer.layer = 14
	picker_layer.visible = false
	add_child(picker_layer)
	var pdim := ColorRect.new()
	pdim.color = Color(0.03, 0.02, 0.06, 0.8)
	pdim.set_anchors_preset(Control.PRESET_FULL_RECT)
	picker_layer.add_child(pdim)
	var center := FitCenter.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	picker_layer.add_child(center)
	var pv := VBoxContainer.new()
	pv.add_theme_constant_override("separation", 20)
	center.add_child(pv)
	picker_title = WoodUI.label_fixed("", 34)
	picker_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	picker_title.custom_minimum_size.x = 1000.0 if Phone.active else 0.0
	picker_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pv.add_child(picker_title)
	picker_scroll = ScrollContainer.new()
	picker_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	pv.add_child(picker_scroll)
	picker_grid = HFlowContainer.new()
	picker_grid.custom_minimum_size = Vector2(1300, 0)
	picker_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picker_grid.alignment = FlowContainer.ALIGNMENT_CENTER
	picker_grid.add_theme_constant_override("h_separation", 18)
	picker_grid.add_theme_constant_override("v_separation", 18)
	picker_scroll.add_child(picker_grid)
	picker_buttons = HBoxContainer.new()
	picker_buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	picker_buttons.add_theme_constant_override("separation", 20)
	pv.add_child(picker_buttons)


## The right column: dark planks of the table under the hero panels and the buttons.
func _wood_column() -> StyleBox:
	var sb := WoodUI.plate(WoodUI.SEAM, 3, 10, 20)
	sb.fill = Color(0.2, 0.13, 0.08, 0.88)
	return sb


func _padded(sb: StyleBox, h: int, v: int) -> StyleBox:
	sb.content_margin_left = h
	sb.content_margin_right = h
	sb.content_margin_top = v
	sb.content_margin_bottom = v
	return sb


# ================================================================ layout sync

func set_viewer(p: int) -> void:
	viewer = p
	_clear_selection()
	sync()


func set_hands_hidden(v: bool) -> void:
	hide_hands = v
	sync()


func sync() -> void:
	if game == null:
		return
	var seen := {}
	for side in game.sides():
		var ps = game.players[side]
		var bottom := is_bottom(side)
		# A card in a hidden hand is read before it is played.
		CardView.prefetch(ps.hand.map(func(c): return c.id))
		# «Бесконечный поезд»: the wagon may hide the other side's cards or their numbers.
		var hidden: bool = game.train.field_hidden(viewer, side) and not _watching()
		var secret: bool = game.train.numbers_hidden(viewer, side) and not _watching()
		for lane in LANES:
			var c = ps.creatures[lane]
			if c != null:
				var v = _view_for(c, creature_pos(side, lane))
				seen[c.uid] = true
				v.set_face_up(not hidden)
				v.set_secret(secret)
				v.set_upgraded(c.upgraded)
				v.z_index = 10
				v.lift = 0.0
				if v != _drag_view:
					v.target_pos = creature_pos(side, lane)
					v.target_rot = _card_rot(side, lane) + (PI * 0.5 if c.exhausted else 0.0)
					v.target_scale = (T_S_BOARD if teams else S_BOARD) * (1.08 if v == _hover_view else 1.0)
				var atk: int = game.atk_of(side, lane)
				var d: int = game.def_of(side, lane)
				var hp_state := -1 if c.damage > 0 else signi(d - int(c.def()["def"]))
				var status := ""
				if c.exhausted:
					status = "floop" if c.flooped else "attack"
				v.set_stats(not hidden, atk, d - c.damage, signi(atk - int(c.def()["atk"])), hp_state, status)
				var guard := 0
				for u in c.under:
					if u.flags.get("guard", false):
						guard = int(u.def()["def"]) - u.damage
				v.set_tokens(0 if hidden else game.tokens(c, "burn"), 0 if hidden else game.tokens(c, "atk_tok"), 0 if hidden else guard)
				v.dimmed = false
			var stack: Array = game.buildings_at(side, lane)
			for bi in stack.size():
				var b = stack[bi][0]
				var bpos := building_slot_pos(side, lane, stack[bi][1])
				var v = _view_for(b, bpos)
				seen[b.uid] = true
				v.set_face_up(not hidden)
				v.set_secret(secret)
				v.set_upgraded(b.upgraded)
				v.z_index = 8 - bi
				v.lift = 0.0
				v.target_pos = bpos
				v.target_rot = _card_rot(side, lane) + (PI * 0.5 if b.exhausted else 0.0)
				v.target_scale = (T_S_BUILD if teams else S_BUILD) * (1.1 if v == _hover_view else 1.0)
				v.set_stats(false, 0, 0, 0, 0, "floop" if b.exhausted else "")
				v.dimmed = false
		var n: int = ps.hand.size()
		for i in n:
			var c = ps.hand[i]
			var v = _view_for(c, deck_pos(side))
			seen[c.uid] = true
			var mate: bool = teams and side != viewer and not game.is_foe(viewer, side)
			var show: bool = ((bottom and (_plays(side) or _watching())) or mate or replay_steps != null \
				or sandbox != null or game.train.hand_shown(viewer, side)) and not hide_hands
			v.set_face_up(show)
			v.set_secret(false)
			v.set_upgraded(c.upgraded)
			v.set_stats(false, 0, 0)
			if v == _drag_view:
				continue
			var lay := _seat_hand_layout(side, i, n) if teams else _hand_layout(bottom, i, n)
			v.target_pos = lay[0]
			v.target_rot = lay[1]
			v.target_scale = (T_S_HAND if bottom else (T_S_MATE_HAND if mate else 0.12)) if teams else (S_HAND if bottom else S_OPP_HAND)
			if bottom and _ph:
				v.target_scale = 0.38 if teams else P_S_HAND
			v.z_index = 30 + i
			v.lift = 0.3
			if (replay_steps != null or sandbox != null) and not teams and not bottom:
				# A replay shows the other hand too: upright, so it can be read.
				lay = _open_hand_layout(i, n)
				v.target_pos = lay[0]
				v.target_rot = lay[1]
				v.target_scale = S_OPEN_HAND * (1.12 if v == _hover_view else 1.0)
				if v == _hover_view:
					v.z_index = 100
			if bottom and show:
				if v == _hover_view or c.uid == _selected_uid:
					v.target_pos.y = 890.0 if v == _hover_view else 915.0
					v.target_rot = 0.0
					v.target_scale = S_HAND_HOVER if v == _hover_view else (T_S_HAND if teams else S_HAND) * 1.12
					if _ph and not teams:
						# A phone: the picked card stands up whole, its cost and text over the hand.
						v.target_pos.y = 1080.0 - CardView.SIZE.y * P_S_UP * 0.5 - 6.0
						v.target_scale = P_S_UP
					v.z_index = 100
					v.lift = 1.0
				v.dimmed = side == game.turn_player and game.phase == "main" and not game.can_play(side, c.uid)
			else:
				v.dimmed = false
			v.on_screen = true
		if ps.teamwork != null:
			var tw = ps.teamwork
			var v = _view_for(tw, teamwork_pos(side))
			seen[tw.uid] = true
			v.set_face_up(true)
			v.set_secret(false)
			v.set_stats(false, 0, 0)
			v.target_pos = teamwork_pos(side)
			v.target_rot = 0.0           # the picture is already landscape (CardView.upright)
			v.target_scale = _pile_scale() * (1.08 if v == _hover_view else 1.0)
			v.z_index = 6
			v.lift = 0.0
			v.dimmed = false
		var dn: int = ps.discard.size()
		for i in range(maxi(0, dn - 3), dn):
			var c = ps.discard[i]
			var v = _view_for(c, discard_pos(side))
			seen[c.uid] = true
			v.set_face_up(true)
			v.set_secret(false)
			v.set_upgraded(c.upgraded)
			v.set_stats(false, 0, 0)
			var depth := dn - 1 - i
			v.target_pos = discard_pos(side) + Vector2(depth * 2.5, depth * 3.5)
			v.target_rot = deg_to_rad(float((c.uid * 37) % 13) - 6.0)
			v.target_scale = _pile_scale()
			v.z_index = 4 - depth
			v.lift = 0.0
			v.dimmed = false
		# Рентгеновские очки: the open top card of the deck, played like a card from the hand.
		var top = game.xray_top(side)
		if top != null:
			var v = _view_for(top, deck_pos(side))
			seen[top.uid] = true
			v.set_face_up(true)
			v.set_secret(false)
			v.set_upgraded(top.upgraded)
			v.set_stats(false, 0, 0)
			v.on_screen = true
			if v != _drag_view:
				v.target_pos = deck_pos(side) + (Vector2(0, -20) if top.uid == _selected_uid else Vector2.ZERO)
				v.target_rot = 0.0
				v.target_scale = _pile_scale() * (1.08 if v == _hover_view or top.uid == _selected_uid else 1.0)
				v.z_index = 7
				v.lift = 0.0
			v.dimmed = side == viewer and side == game.turn_player and game.phase == "main" and not game.can_play(side, top.uid)
	for i in _limbo.size():
		var c = game.card(_limbo[i])
		if c == null:
			continue
		var limbo: Vector2 = _center() if teams else LIMBO_POS
		var v = _view_for(c, limbo)
		seen[c.uid] = true
		v.set_face_up(true)
		v.set_secret(false)
		v.set_stats(false, 0, 0)
		v.target_pos = limbo + Vector2(i * 60 + _screen_dx, 0)
		v.on_screen = true
		v.target_rot = 0.0
		v.target_scale = S_SHOW
		v.z_index = 160
		v.lift = 1.0
		v.dimmed = false
	var shown := []
	for uid in _revealed:
		var c = game.card(uid)
		var w: Dictionary = game.where(uid) if c != null else {}
		if c == null or w.get("zone", "") != _revealed_zone.get(uid, "") or _limbo.has(uid):
			continue
		var v = _view_for(c, deck_pos(w.get("p", 0)))
		seen[uid] = true
		v.set_face_up(true)
		v.set_secret(false)
		v.set_stats(false, 0, 0)
		v.target_pos = _reveal_pos(shown.size()) + Vector2(_screen_dx, 0)
		v.on_screen = true
		v.target_rot = deg_to_rad(4.0 * (shown.size() % 2 * 2 - 1))
		v.target_scale = S_SHOW
		v.z_index = 170 + shown.size()
		v.lift = 1.0
		v.dimmed = false
		shown.append(uid)
	_revealed = shown
	for uid in views.keys():
		if not seen.has(uid):
			_retire_view(uid)
	_update_lands()
	_update_piles()
	_update_hud()
	_update_preview()
	decor.queue_redraw()


## 2 на 2: the viewer's hand fans out at the bottom, the teammate's backs at the top, the
## opponents' small backs above their piles.
func _seat_hand_layout(side: int, i: int, n: int) -> Array:
	var rel := _rel(side)
	var at: Vector2 = (T3_HAND if tri else T_HAND)[rel]
	if rel == 0:
		var spacing := minf(140.0, 700.0 / maxf(n, 1))
		if _ph:
			spacing = clampf(1100.0 / maxf(n, 1), 112.0, 160.0)     # a finger's width of each card
			# A long hand stays flat and on the screen: between its left edge and the right column
			# (a card under the column or below the edge would take no tap).
			var rest := CardView.SIZE.x * 0.38 * 0.5
			var lo := -_side_req + 12.0 + rest
			var hi := 1920.0 + _side_req - 12.0 - rest
			for c in _column:
				if c.visible and c.size.y > 0.0 and c.position.x > FIELD_CENTER.x:
					hi = minf(hi, c.position.x - 12.0 - rest)
			if n > 1:
				spacing = minf(spacing, maxf(40.0, (hi - lo) / float(n - 1)))
			var x0 := clampf(at.x - (n - 1) * 0.5 * spacing, lo, maxf(lo, hi - (n - 1) * spacing))
			var x := x0 + i * spacing
			var dxp := x - at.x
			return [Vector2(x, at.y + pow(dxp / 700.0, 2.0) * 30.0), dxp * 0.0004]
		var dx := (i - (n - 1) * 0.5) * spacing
		return [Vector2(at.x + dx, at.y + pow(dx / 420.0, 2.0) * 46.0), dx * 0.00075]
	if rel == 2 and not tri:
		# Open, as wide as the corner allows; one card more is pushed under its neighbours.
		var spacing3 := minf(52.0, 200.0 / maxf(n - 1, 1))
		var dx3 := (i - (n - 1) * 0.5) * spacing3
		return [at + Vector2(dx3, absf(dx3) * 0.06), dx3 * 0.0012]
	var spacing2 := minf(24.0, 220.0 / maxf(n, 1))
	var dx2 := (i - (n - 1) * 0.5) * spacing2
	return [at + Vector2(dx2, 0), dx2 * 0.004]


func _hand_layout(bottom: bool, i: int, n: int) -> Array:
	if bottom and _ph:
		# A phone: bigger cards and a finger's width of each at least; a long hand spreads over the field.
		var xs := _phone_hand_xs(n)
		var dxp: float = xs[i] - (FIELD_CENTER.x + _screen_dx + 15.0)
		return [Vector2(xs[i], P_HAND_Y + pow(dxp / 600.0, 2.0) * 40.0), dxp * 0.0005]
	if bottom:
		var spacing := minf(150.0, 760.0 / maxf(n, 1))
		var dx := (i - (n - 1) * 0.5) * spacing
		return [Vector2(FIELD_CENTER.x + _screen_dx + 15 + dx, 984 + pow(dx / 420.0, 2.0) * 46.0), dx * 0.00075]
	var spacing2 := minf(78.0, 520.0 / maxf(n, 1))
	var dx2 := (i - (n - 1) * 0.5) * spacing2
	return [Vector2(FIELD_CENTER.x + _screen_dx + dx2, -24 - pow(dx2 / 300.0, 2.0) * 20.0), PI - dx2 * 0.0012]


## A phone: where the n cards of the own hand lie (x, in the coordinates of the field). Each is
## a finger wide at least; the picked card stands up bigger over its neighbours, so they step
## aside (P_SEEN of each still shows, a finger finds it and not the picked one); the hand
## stays between the screen's left edge and the right column (a card under the column would
## take no tap, the column would).
func _phone_hand_xs(n: int) -> Array:
	var rest := CardView.SIZE.x * P_S_HAND * 0.5
	var up := CardView.SIZE.x * P_S_UP * 0.5
	var lo := 12.0 + rest
	var hi := _field_rect().size.x - 12.0 - rest
	for c in _column:
		if c.visible and c.size.y > 0.0 and c.position.x > FIELD_CENTER.x:   # not the sandbox's corner button
			hi = minf(hi, c.position.x + _side - 12.0 - rest)
	var room := clampf(_field_rect().size.x - 260.0, 900.0, 1500.0)
	var spacing := clampf(room / maxf(n, 1), P_SEEN, 200.0)
	var hand: Array = game.players[viewer].hand
	var at := -1
	if _selected_uid != -1 and n == hand.size():
		for k in n:
			if hand[k].uid == _selected_uid:
				at = k
	var xs := []
	for attempt in 4:
		var right := 0.0         # the cards right of the picked one step right by it, the left ones left
		var left := 0.0
		if at >= 0:
			right = maxf(0.0, P_SEEN + rest + up - 2.0 * spacing) if at < n - 2 \
				else maxf(0.0, P_SEEN + up - rest - spacing)
			left = maxf(0.0, P_SEEN + up - rest - spacing)
		xs.clear()
		for k in n:
			var x := (k - (n - 1) * 0.5) * spacing
			if at >= 0 and k > at:
				x += right
			elif at >= 0 and k < at:
				x -= left
			xs.append(x)
		var width: float = xs[-1] - xs[0] if n > 0 else 0.0
		if width <= hi - lo or n < 2 or spacing <= 40.0:
			break
		# A very long hand: the cards closer together (less than a finger of each shows).
		spacing = maxf(40.0, spacing - (width - (hi - lo)) / float(n - 1))
	var mid := FIELD_CENTER.x + _screen_dx + 15.0
	if n > 0:
		mid = clampf(mid, lo - float(xs[0]), maxf(lo - float(xs[0]), hi - float(xs[-1])))
	for k in n:
		xs[k] = mid + float(xs[k])
	return xs


## The top hand when it is shown (a replay): face up and upright along the top edge.
func _open_hand_layout(i: int, n: int) -> Array:
	var spacing := minf(118.0, 700.0 / maxf(n, 1))
	var dx := (i - (n - 1) * 0.5) * spacing
	return [Vector2(FIELD_CENTER.x + _screen_dx + dx, OPEN_HAND_Y + pow(dx / 420.0, 2.0) * 20.0), -dx * 0.0006]


## Where the n-th opened card lies: by the lanes on the left, after any spell waiting there.
func _reveal_pos(n: int) -> Vector2:
	var base: Vector2 = _center() if teams else LIMBO_POS
	return base + Vector2((_limbo.size() + n) * 70 + (40 if _limbo.size() > 0 else 0), 0)


## Opened cards stay on show a while and through the choice that follows, then go back.
## sync() drops cards that left their zone, so the batch is told apart by its number, not its list.
func _keep_revealed(batch: int) -> void:
	await _wait(2.2)
	while is_inside_tree() and _choice != null and _reveal_batch == batch:
		await _wait(0.3)
	if is_inside_tree() and _reveal_batch == batch:
		_revealed = []
		sync()


func _view_for(c, spawn: Vector2):
	if views.has(c.uid):
		return views[c.uid]
	var v = CardView.new()
	world.add_child(v)
	v.setup(c.uid, c.id, false)
	v.target_pos = spawn
	v.target_scale = S_PILE
	v.snap()
	views[c.uid] = v
	return v


func _retire_view(uid: int) -> void:
	var v = views[uid]
	views.erase(uid)
	if v == _hover_view:
		_hover_view = null
	var w: Dictionary = game.where(uid)
	var dest := _center()
	var end_scale := _pile_scale()
	if w["zone"] == "deck":
		dest = deck_pos(w["p"])
		v.set_face_up(false)
	elif w["zone"] == "discard":
		dest = discard_pos(w["p"])
	elif w["zone"] == "under" and views.has(w["host"]):
		dest = views[w["host"]].position
		end_scale = S_BOARD * 0.6
	elif w["zone"] == "removed":
		end_scale = 0.02
	v.target_pos = dest
	v.target_scale = end_scale
	v.target_rot = 0.0
	v.z_index = 1
	var tw: Tween = v.create_tween()
	tw.tween_interval(0.4)
	tw.tween_callback(v.queue_free)


func _update_lands() -> void:
	for side in game.players.size():
		var ps = game.players[side]
		var on: bool = game.sides().has(side)     # на троих the one who dropped out leaves the table
		for lane in LANES:
			land_sprites[side][lane].visible = on
			land_icons[side][lane].visible = on
			if not on:
				continue
			var l: Dictionary = ps.lands[lane].duplicate()
			if side == _arranging:
				l["type"] = _arr_types[lane]
			var s: Sprite2D = land_sprites[side][lane]
			var key := "%s_%d%s" % [l["type"], l["art"], "_flipped" if l["flipped"] else ""]
			if not _land_tex.has(key):
				_land_tex[key] = load("res://assets/lands/%s.png" % key)
			s.texture = _land_tex[key]
			s.position = land_pos(side, lane)
			s.rotation = _land_rot(side, lane)
			s.scale = Vector2.ONE * _tile_scale() * LAND_TEX_W / s.texture.get_width()
			var icon: Sprite2D = land_icons[side][lane]
			# Амбар свободы may make the land count as another type for a while.
			var shown: String = l["override"] if l.get("override", "") != "" else l["type"]
			icon.texture = _symbols[shown]
			icon.visible = not l["flipped"]
			icon.modulate = Color(1.0, 0.85, 0.4) if shown != l["type"] else Color.WHITE
			icon.scale = Vector2.ONE * (0.24 if teams else 0.27)
			var inset := 23.0 if teams else 26.0
			var corner := Vector2(-_tile_size().x * 0.5 + inset, -_tile_size().y * 0.5 + inset)
			icon.position = s.position + corner.rotated(s.rotation)
			icon.rotation = s.rotation if teams else 0.0


func _update_piles() -> void:
	for side in game.players.size():
		var pile: Node2D = piles[side]
		var n: int = game.players[side].deck.size()
		pile.position = deck_pos(side)
		pile.scale = Vector2.ONE * _pile_scale() / S_PILE
		pile.visible = n > 0 and game.sides().has(side)
		for i in pile.get_child_count():
			pile.get_child(i).visible = n > (2 - i) * 12


## A card of the deck piles: drawn as big as a card on the table, whatever back is picked.
func _set_back(b: Sprite2D) -> void:
	b.texture = CardBacks.texture()
	b.scale = CardView.SIZE / b.texture.get_size() * S_PILE


## Another card back was picked in the settings.
func refresh_back() -> void:
	for pile: Node2D in piles:
		for b: Sprite2D in pile.get_children():
			_set_back(b)


# ================================================================ HUD

func _update_hud() -> void:
	if game == null:
		return
	for key in ["top", "bottom"]:
		if teams and not (tri and key == "bottom"):
			_update_team_panel(key)
			continue
		var side := viewer if key == "bottom" else _top_side()
		var ui: Dictionary = hero_ui[key]
		var ps = game.players[side]
		if ui["side"] != side:
			ui["side"] = side
			var col := UI.hero_color(ps.hero)
			ui["panel"].add_theme_stylebox_override("panel", WoodUI.plate(col, 4, 14 if key == "top" else 15, 20))
			ui["portrait"].texture = _hero_card_texture(ps.hero_card)
			var tag := ""
			if ai_vs_ai:
				tag = " (ИИ)"
			elif ai_agent != null and side == ai_player:
				tag = " (ИИ)"
			elif (net != null or ai_agent != null) and side == local_player:
				tag = " (ты)"
			ui["name"].text = ps.name + tag
			var room := HUD_W - 170.0
			if key == "top" and _foe_nick != "":
				ui["name"].text = _foe_nick
			if _ph:
				_fit_font(ui["name"], 186.0, 34, P_FONT)
			else:
				_fit_font(ui["name"], room, 30, 14)
			ui["name"].label_settings.font_color = col
			ui["shown_hp"] = float(ps.hp)
		ui["hp"].text = str(maxi(ps.hp, 0))
		ui["hp"].label_settings.font_color = Color.WHITE if ps.hp > 8 else Color(1.0, 0.45, 0.4)
		ui["info"].text = ("Рука %d\nКолода %d\nСброс %d" if _ph else "Рука: %d\nКолода: %d\nСброс: %d") % [ps.hand.size(), ps.deck.size(), ps.discard.size()]
		if ps.burn > 0:
			ui["info"].text += "\nОгонь: %d" % ps.burn
		# Бетти's Исследовательские заметки (Блестящее открытие and Контролёр качества add to them).
		if ps.hero_state.has("notes"):
			ui["info"].text += "\nЗаметки: %d" % ps.hero_state["notes"].size()
		ui["turn"].visible = side == game.turn_player and game.phase != "over"
	var tp = game.players[game.turn_player]
	turn_label.text = "Ход %d · %s" % [maxi(game.turn_number, 1), tp.name]
	if _ph:
		_fit_font(turn_label, P_W - P_ROW - P_GAP, 36, P_FONT)
	else:
		_fit_font(turn_label, HUD_W - (122.0 if chat_button.visible else 62.0), 32, 18)
	turn_label.label_settings.font_color = UI.hero_color(tp.hero)
	match game.phase:
		"setup":
			phase_label.text = "Подготовка к игре"
		"main":
			phase_label.text = "Первый ход: без флюпов и атак" if game.is_first_turn() else "Розыгрыш карт и флюпы"
		"attack":
			phase_label.text = "Атака: кликай по своим существам"
		"handoff":
			phase_label.text = "Передача хода…"
		"over":
			phase_label.text = "Игра окончена"
	if replay_steps != null:
		var what := "Наблюдение" if live_replay else "Реплей"
		phase_label.text = what + " — пауза" if ai_paused else what
	elif ai_vs_ai and game.phase != "over":
		phase_label.text = "ИИ против ИИ — пауза" if ai_paused else "ИИ против ИИ — смотрим…"
	elif (net != null or ai_agent != null) and game.turn_player != local_player and (game.phase == "main" or game.phase == "attack"):
		phase_label.text = "Ход ИИ — подожди…" if ai_agent != null else "Ход %s — смотри и жди" % _whose_turn()
	if _ph:
		_fit_font(phase_label, P_W - 4.0, 30, P_FONT)
	else:
		_fit_font(phase_label, HUD_W - 4.0, 18, 13)
	actions_widget.queue_redraw()
	var my_turn: bool = _plays(viewer) and viewer == game.turn_player and not _busy and _choice == null
	match game.phase:
		"main":
			if game.is_first_turn() or game.attackers_left(game.turn_player).is_empty():
				main_button.text = "Завершить ход"
			else:
				main_button.text = "В атаку!"
		"attack":
			main_button.text = "Завершить ход" if game.attackers_left(game.turn_player).is_empty() \
					else "Атаковать всеми"
		_:
			main_button.text = "…"
	if _watching():
		main_button.text = "Продолжить" if ai_paused else "Пауза"
	elif (net != null or ai_agent != null) and game.turn_player != local_player and game.phase != "over":
		main_button.text = "Ходит ИИ…" if ai_agent != null else "Ход %s" % _whose_turn()
	main_button.disabled = not my_turn or not (game.phase == "main" or game.phase == "attack")
	draw_button.disabled = not my_turn or not game.can_draw_for_action(viewer)
	undo_button.visible = not _watching()
	undo_button.disabled = not _can_undo()
	undo_button.get_child(0).queue_redraw()
	# The text first: a button never gets narrower than its text.
	draw_button.text = "Взять карту  −1 д." if undo_button.visible else "Взять карту  −1 действие"
	draw_button.custom_minimum_size.x = HUD_W - UNDO_W - UNDO_GAP if undo_button.visible else HUD_W
	draw_button.size.x = draw_button.custom_minimum_size.x
	if _watching():
		main_button.disabled = game.phase == "over"
		draw_button.disabled = game.phase == "over"
		draw_button.text = "Скорость " + speed_text(ai_speed)
	turns_button.visible = replay_steps != null and not live_replay
	if turns_button.visible:
		draw_button.custom_minimum_size.x = HUD_W * 0.5 - 5
		draw_button.size.x = draw_button.custom_minimum_size.x
		draw_button.disabled = false
	# Active hero card ability of the player at the bottom.
	var power := ""
	if CardDB.has_hero_card(game.players[viewer].hero_card) and not _watching():
		power = CardDB.hero_card(game.players[viewer].hero_card).get("power", "")
	hero_button.visible = power != ""
	hero_button.text = "Герой: " + power
	if not _fits(hero_button, P_W if _ph else HUD_W, 20 if _ph else 15):
		hero_button.text = power      # a long ability: its text alone
	hero_button.disabled = not my_turn or not game.can_hero_power(viewer)
	if replay_steps != null:
		hero_button.visible = true
		hero_button.text = "Смотреть за: " + game.players[game.next_seat(viewer)].name
		hero_button.disabled = false
	if _ph:
		_phone_hud()
		return
	_fit_button(hero_button, HUD_W, 18, 13)
	log_panel.position.y = 578.0 if hero_button.visible else 524.0
	log_panel.size.y = 252.0 if hero_button.visible else 306.0
	if sandbox != null:
		sb_button.position.y = log_panel.position.y
		log_panel.position.y += 62.0
		log_panel.size.y -= 62.0
		undo_button.visible = true
	_update_wagon()


## A phone: the rows of the right column under the main button that come and go (_layout_column).
func _phone_hud() -> void:
	if sandbox != null:
		undo_button.visible = true
	var y3 := draw_button.position.y
	var half := turns_button.visible
	var w := P_W * 0.5 - 5.0 if half else (P_W - P_ROW - P_GAP if undo_button.visible else P_W)
	draw_button.custom_minimum_size.x = w
	draw_button.size = Vector2(w, P_ROW)
	draw_button.add_theme_font_size_override("font_size", 30 if w > 200.0 else 28)
	var y := y3 + P_ROW + P_GAP
	draw_button.text = "Взять карту\n−1 действие" if not _watching() else draw_button.text
	if turns_button.visible:
		draw_button.text = "Скорость " + speed_text(ai_speed)
	draw_button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var row_items: Array[Button] = []
	if hero_button.visible:
		row_items.append(hero_button)
	for i in row_items.size():
		var b := row_items[i]
		var bw := (P_W - P_GAP * (row_items.size() - 1)) / row_items.size()
		b.position = Vector2(P_X + _side + i * (bw + P_GAP), y)
		b.set_meta("base_x", P_X + i * (bw + P_GAP))
		b.custom_minimum_size = Vector2(bw, P_ROW)
		_fit_button(b, bw, 30, P_FONT)
		b.size = Vector2(bw, P_ROW)
	if not row_items.is_empty():
		y += P_ROW + P_GAP
	if _log_big:
		return
	var bottom := 1070.0 - P_PANEL_H - P_GAP
	var lw := P_W
	if chat_button.visible:
		# Online: the chat at the right of the log's strip.
		lw = P_W - P_ROW - P_GAP
		chat_button.position = Vector2(P_X + P_W - P_ROW + _side, y)
		chat_button.set_meta("base_x", P_X + P_W - P_ROW)
	log_panel.position = Vector2(P_X + _side, y)
	# Its least size too: the one _layout_column gave (no hero row) would push it over the own panel.
	log_panel.custom_minimum_size = Vector2(lw, maxf(60.0, bottom - y))
	log_panel.size = log_panel.custom_minimum_size
	log_panel.visible = true
	wagon_label.visible = false
	var rule: String = game.train.wagon
	if rule != "" and TrainWagons.has(rule):
		# The train: the rule of the wagon instead of the strip (the log opens with a tap on it).
		var wg := TrainWagons.wagon(rule)
		wagon_label.text = "%s: %s" % [wg["name"], wg["text"]]
		if game.train.wagon_state.has("closed"):
			wagon_label.text += "\nЗакрыта зона %d" % (int(game.train.wagon_state["closed"]) + 1)
		wagon_label.label_settings.font_color = TrainWagons.level(rule)["color"]
		wagon_label.visible = true
		wagon_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		wagon_label.position = log_panel.position + Vector2(12, 8)
		wagon_label.size = log_panel.size - Vector2(24, 16)
		log_box.visible = false
	else:
		log_box.visible = true


## 2 на 2: a hero panel shows a team: two hero cards with names, the team's hit points
## and the cards in hand of each.
func _update_team_panel(key: String) -> void:
	var ui: Dictionary = hero_ui[key]
	var seats := _panel_seats(key)
	var side: int = seats[0]
	if ui["side"] != side or ui.get("seats", []) != seats:
		ui["side"] = side
		ui["seats"] = seats
		var col := Color(0.45, 0.8, 1.0) if key == "bottom" else Color(1.0, 0.45, 0.4)
		ui["panel"].add_theme_stylebox_override("panel", WoodUI.plate(col, 4, 14 if key == "top" else 15, 20))
		for k in 2:
			var ps = game.players[seats[k]]
			ui["portrait" if k == 0 else "portrait2"].texture = _hero_card_texture(ps.hero_card)
			var name_l: Label = ui["name" if k == 0 else "name2"]
			name_l.text = ps.name + _seat_tag(seats[k])
			_fit_font(name_l, 98.0, 18, 11)
			name_l.label_settings.font_color = UI.hero_color(ps.hero)
		ui["shown_hp"] = float(game.players[side].hp)
	var hp: int = game.players[side].hp
	ui["hp"].text = str(maxi(hp, 0))
	ui["hp"].label_settings.font_color = Color.WHITE if hp > 12 else Color(1.0, 0.45, 0.4)
	for k in 2:
		var seat_hp: int = game.players[seats[k]].hp
		var hpb: Label = ui["hpb" if k == 0 else "hpb2"]
		hpb.text = "♥ %d" % maxi(seat_hp, 0)
		hpb.label_settings.font_color = Color.WHITE if seat_hp > 8 else Color(1.0, 0.45, 0.4)
	ui["info"].text = "Рука\n%d · %d" % [game.players[seats[0]].hand.size(), game.players[seats[1]].hand.size()]
	var playing: bool = game.phase != "over"
	ui["turn"].visible = playing and game.turn_player == seats[0]
	ui["turn2"].visible = playing and game.turn_player == seats[1]


## "соперника" or (2 на 2, the teammate's turn) "напарника".
func _whose_turn() -> String:
	return "напарника" if seated and local_player >= 0 and not game.is_foe(local_player, game.turn_player) else "соперника"


## " (ИИ)" / " (ты)" after a seat's name.
func _seat_tag(side: int) -> String:
	if ai_vs_ai or _is_ai_seat(side) or ai_names.has(side):
		return " (ИИ)"
	if (net != null or ai_agent != null or humans.size() == 1) and side == local_player:
		return " (ты)"
	return ""


## The table for the seats in the game: 2 на 2 and на троих the table round the seats, на троих
## after a player dropped out the playmat of a game for two (the one who dropped out watches).
func _fit_table() -> void:
	var round_table: bool = seated and not game.duel()
	var three: bool = round_table and game.three()
	if round_table == teams and three == tri:
		return
	teams = round_table
	tri = three
	if game.duel() and game.is_out(viewer):
		viewer = _duel_viewer()
	if teams:
		_setup_teams_table()
	else:
		_setup_duel_table()
	for key in hero_ui:
		hero_ui[key]["side"] = -1
	_room_key = ""
	_apply_room()


## На троих after a player dropped out: whose side is at the bottom (a person at this PC if
## one is still playing, or the seat after the one that dropped out).
func _duel_viewer() -> int:
	if local_player >= 0 and not game.is_out(local_player):
		return local_player
	for p in humans:
		if not game.is_out(p):
			return p
	return game.next_seat(viewer)


## The other side of a game for two (на троих after a player dropped out: the other one left).
func _top_side() -> int:
	for s in game.sides():
		if s != viewer:
			return s
	return 1 - viewer


## 2 на 2 and на троих: the table without the playmat, the hero panels for teams, the preview of
## the hovered card in the middle between the fronts. На троих the viewer's own panel stays as in
## a game for two and the panel of the other two shows each one's hit points on their card.
func _setup_teams_table() -> void:
	for n in _mat_nodes:
		n.visible = false
	if _table_bg == null:
		_table_bg = Node2D.new()
		_table_bg.z_index = -12
		_table_bg.draw.connect(_draw_table_bg)
		world.add_child(_table_bg)
		for n: Control in [preview_rect, preview_info, banner]:
			_duel_layout.append([n, n.position, n.size])
		for key in ["top", "bottom"]:
			for ch in hero_ui[key]["panel"].get_children():
				_duel_layout.append([ch, ch.position, ch.size])
	_table_bg.visible = true
	preview_rect.size = Vector2(250, 350)
	preview_rect.position = _center() - preview_rect.size * 0.5 - Vector2(0, 14)
	preview_rect.pivot_offset = preview_rect.size * 0.5
	preview_info.position = _center() + Vector2(-170, 166)
	preview_info.size = Vector2(340, 60)
	banner.position = _center() - banner.size * 0.5
	for key in ["top", "bottom"]:
		var ui: Dictionary = hero_ui[key]
		var panel: Panel = ui["panel"]
		if not ui.has("portrait2"):
			var p2 := TextureRect.new()
			p2.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			p2.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			p2.mouse_filter = Control.MOUSE_FILTER_IGNORE
			p2.material = CardView.SHARP
			panel.add_child(p2)
			ui["portrait2"] = p2
			var n2 := WoodUI.label_fixed("", 18)
			panel.add_child(n2)
			ui["name2"] = n2
			var tag2 := PanelContainer.new()
			tag2.add_theme_stylebox_override("panel", _padded(WoodUI.paper(WoodUI.GO, 0.0, 13, 3.0), 12, 1))
			tag2.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var t2 := WoodUI.label_fixed("ХОДИТ", 20, Color.WHITE, 5)
			tag2.add_child(t2)
			panel.add_child(tag2)
			ui["turn2"] = tag2
			ui["turn_text2"] = t2
			for k in ["", "2"]:
				var hpb := WoodUI.label_fixed("", 34, Color.WHITE, 8)
				hpb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				hpb.size = Vector2(98, 40)
				panel.add_child(hpb)
				ui["hpb" + k] = hpb
		if tri and key == "bottom":
			_duel_panel(ui)
			continue
		ui["portrait"].position = Vector2(8, 8)
		ui["portrait"].size = Vector2(98, 136)
		ui["portrait2"].position = Vector2(110, 8)
		ui["portrait2"].size = Vector2(98, 136)
		ui["name"].position = Vector2(8, 150)
		ui["name"].size = Vector2(98, 30)
		ui["name2"].position = Vector2(110, 150)
		ui["name2"].size = Vector2(98, 30)
		ui["hp"].position = Vector2(212, 40)
		ui["hp"].size = Vector2(102, 86)
		ui["info"].position = Vector2(222, 138)
		ui["info"].size = Vector2(92, 66)
		ui["turn"].position = Vector2(14, 112)
		ui["turn2"].position = Vector2(116, 112)
		ui["hpb"].position = Vector2(8, 4)
		ui["hpb2"].position = Vector2(110, 4)
		# На троих the two opponents keep their own hit points: on their cards, not in one number.
		var split: bool = tri and key == "top"
		ui["hp"].visible = not split
		_heart(panel).visible = not split
		_heart(panel).position = Vector2(244, 4)
		ui["hpb"].visible = split
		ui["hpb2"].visible = split
		for k in ["portrait2", "name2", "turn2"]:
			ui[k].visible = true
		ui["side"] = -1
		if _ph:
			_phone_team_panel(ui)
	if _ph:
		pass


func _heart(panel: Panel) -> Label:
	for ch in panel.get_children():
		if ch is Label and ch.text == "♥":
			return ch
	return null


## A hero panel laid out as in a game for two.
func _duel_panel(ui: Dictionary) -> void:
	for e in _duel_layout:
		if e[0].get_parent() == ui["panel"]:
			e[0].position = e[1]
			e[0].size = e[2]
	ui["hp"].visible = true
	_heart(ui["panel"]).visible = true
	for k in ["portrait2", "name2", "turn2", "hpb", "hpb2"]:
		ui[k].visible = false
	ui["name"].visible = true
	ui["side"] = -1
	if _ph:
		_phone_panel(ui)


## На троих after a player dropped out: the playmat of a game for two again.
func _setup_duel_table() -> void:
	if _table_bg == null:
		return      # it has never been anything else
	for n in _mat_nodes:
		n.visible = true
	_table_bg.visible = false
	for e in _duel_layout:
		if e[0].get_parent() is Panel:
			continue
		e[0].position = e[1]
		e[0].size = e[2]
	preview_rect.pivot_offset = preview_rect.size * 0.5
	for key in ["top", "bottom"]:
		_duel_panel(hero_ui[key])


## 2 на 2: the four fronts, a soft dark field each, and the names of the players by their piles.
func _draw_table_bg() -> void:
	if game == null or not teams:
		return
	if tri:
		_draw_tri_bg()
		return
	# The square cut along its diagonals: the triangle of each seat in its team's colour,
	# as on the playmat of the rulebook.
	var h := T_HALF
	var corners := [T_CENTER + Vector2(-h, h), T_CENTER + Vector2(-h, -h), T_CENTER + Vector2(h, -h), T_CENTER + Vector2(h, h)]
	var mine := Color(0.2, 0.42, 0.85, 0.55)
	var theirs := Color(0.35, 0.62, 0.25, 0.55)
	for k in 4:
		# Triangle k: the side of the seat k quarter turns from the viewer (0 = bottom).
		var tri := PackedVector2Array([T_CENTER, corners[k], corners[(k + 3) % 4]])
		_table_bg.draw_colored_polygon(tri, mine if k % 2 == 0 else theirs)
	_table_bg.draw_polyline(PackedVector2Array(corners + [corners[0]]), Color(0.05, 0.03, 0.02, 0.85), 10.0)
	_table_bg.draw_polyline(PackedVector2Array(corners + [corners[0]]), Color(0.95, 0.85, 0.6, 0.6), 3.0)
	for k in 2:
		_table_bg.draw_line(corners[k], corners[k + 2], Color(1, 1, 1, 0.18), 3.0)
	var font: Font = UI.DISPLAY_FONT
	for side in game.players.size():
		var rel := _rel(side)
		if rel == 0:
			continue
		var ps = game.players[side]
		var at: Vector2 = (deck_pos(side) + discard_pos(side)) * 0.5
		var y: float = T_HAND[rel].y - 62.0
		if rel == 2:
			# The teammate's name over their open hand.
			at = T_HAND[2]
			y = T_HAND[2].y - 86.0
		var col: Color = UI.hero_color(ps.hero)
		_table_bg.draw_string_outline(font, Vector2(at.x - 140, y), ps.name, HORIZONTAL_ALIGNMENT_CENTER, 280, 24, 6, Color(0, 0, 0, 0.8))
		_table_bg.draw_string(font, Vector2(at.x - 140, y), ps.name, HORIZONTAL_ALIGNMENT_CENTER, 280, 24, col)


## На троих: the hexagon cut from the middle to the three corners the lanes run across, the
## viewer's part blue, the others' green, and the names of the other two by their piles.
func _draw_tri_bg() -> void:
	var h := T3_HALF
	var hex := PackedVector2Array()
	for k in 6:
		hex.append(T3_CENTER + Vector2.DOWN.rotated(TAU / 6.0 * k) * h)
	# hex[1], hex[3], hex[5] are the corners (bottom left, top, bottom right); the viewer's part
	# runs from the bottom left corner over the bottom tip to the bottom right one.
	var mine := Color(0.2, 0.42, 0.85, 0.55)
	var theirs := Color(0.35, 0.62, 0.25, 0.55)
	for k in 3:
		var part := PackedVector2Array([T3_CENTER, hex[(2 * k + 5) % 6], hex[2 * k], hex[2 * k + 1]])
		_table_bg.draw_colored_polygon(part, mine if k == 0 else theirs)
	_table_bg.draw_polyline(PackedVector2Array(Array(hex) + [hex[0]]), Color(0.05, 0.03, 0.02, 0.85), 10.0)
	_table_bg.draw_polyline(PackedVector2Array(Array(hex) + [hex[0]]), Color(0.95, 0.85, 0.6, 0.6), 3.0)
	for k in [1, 3, 5]:
		_table_bg.draw_line(T3_CENTER, hex[k], Color(1, 1, 1, 0.18), 3.0)
	var font: Font = UI.DISPLAY_FONT
	for side in game.players.size():
		var rel := _rel(side)
		if rel == 0:
			continue
		var ps = game.players[side]
		var at: Vector2 = (deck_pos(side) + discard_pos(side)) * 0.5
		var y: float = T3_HAND[rel].y - 62.0
		var col: Color = UI.hero_color(ps.hero)
		_table_bg.draw_string_outline(font, Vector2(at.x - 140, y), ps.name, HORIZONTAL_ALIGNMENT_CENTER, 280, 24, 6, Color(0, 0, 0, 0.8))
		_table_bg.draw_string(font, Vector2(at.x - 140, y), ps.name, HORIZONTAL_ALIGNMENT_CENTER, 280, 24, col)


## The wagon's rule under the log. Where the wagon hides cards the log would tell
## them, so it goes and the rule takes its place.
func _update_wagon() -> void:
	var rule: String = game.train.wagon
	wagon_label.visible = rule != "" and TrainWagons.has(rule)
	log_panel.visible = true
	if not wagon_label.visible:
		return
	var wg := TrainWagons.wagon(rule)
	var text := "%s: %s" % [wg["name"], wg["text"]]
	if game.train.wagon_state.has("closed"):
		text += "\nЗакрыта зона %d" % (int(game.train.wagon_state["closed"]) + 1)
	wagon_label.text = text
	wagon_label.label_settings.font_color = TrainWagons.level(rule)["color"]
	var top := log_panel.position.y
	var bottom := top + log_panel.size.y
	if not _watching() and (game.train.field_hidden(viewer, 1 - viewer) or game.train.numbers_hidden(viewer, 1 - viewer)):
		log_panel.visible = false
		wagon_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		wagon_label.position.y = top
		wagon_label.size.y = bottom - top
		return
	wagon_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	wagon_label.size.y = 92.0
	wagon_label.position.y = bottom - wagon_label.size.y
	log_panel.size.y -= wagon_label.size.y + 6.0


## Shrinks a label's font until its one-line text fits the width.
## A fixed-width button keeps its width: a smaller font, two lines when even that is too wide.
func _fit_button(b: Button, width: float, max_size: int, min_size: int) -> void:
	var fs := max_size
	while fs > min_size and not _fits(b, width, fs):
		fs -= 1
	b.autowrap_mode = TextServer.AUTOWRAP_OFF if _fits(b, width, fs) else TextServer.AUTOWRAP_WORD_SMART
	b.add_theme_font_size_override("font_size", fs)
	b.size = Vector2(width, 0)


## Does the button's text fit `width` in one line at font size `fs`?
func _fits(b: Button, width: float, fs: int) -> bool:
	var pad: float = b.get_theme_stylebox("normal").get_minimum_size().x + 2.0 * b.get_theme_constant("outline_size")
	return b.get_theme_font("font").get_string_size(b.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + pad <= width


func _fit_font(l: Label, width: float, max_size: int, min_size: int) -> void:
	var ls: LabelSettings = l.label_settings
	var fs := max_size
	while fs > min_size and ls.font.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > width:
		fs -= 2
	ls.font_size = fs


## The hero panel's card: the small copy is sharp at that size (main.gd reads them at the title).
## `big` (the preview, the right click): the full picture once it is read in the background,
## the small copy until then.
func _hero_card_texture(id: String, big := false) -> Texture2D:
	if id == CardDB.NO_HERO:
		return load(CardDB.NO_HERO_PICTURE)       # played without a hero: the back of a card
	if not CardDB.has_hero_card(id):
		return null
	if big:
		var path := CardDB.hero_image(id)
		if not _hero_pics.has(id):
			_hero_pics[id] = load(path) if ResourceLoader.has_cached(path) 				else path if ResourceLoader.load_threaded_request(path) == OK else null
		if _hero_pics[id] is String and ResourceLoader.load_threaded_get_status(path) != ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			_hero_pics[id] = ResourceLoader.load_threaded_get(path)
		if _hero_pics[id] is Texture2D:
			return _hero_pics[id]
	return load(CardDB.hero_thumb(id))


## Takes the hero pictures still being read, so the loader does not keep them.
func _exit_tree() -> void:
	for v in _hero_pics.values():
		if v is String:
			ResourceLoader.load_threaded_get(v)


func _draw_actions() -> void:
	if game == null:
		return
	var ps = game.players[game.turn_player]
	var font: Font = WoodUI.BOLD
	# A phone: the circles alone, the column is narrow (the rules call them actions everywhere).
	var x0 := 22.0 if _ph else 150.0
	if not _ph:
		actions_widget.draw_string_outline(font, Vector2(2, 34), "Действия", HORIZONTAL_ALIGNMENT_LEFT, -1, 24, 6, WoodUI.INK)
		actions_widget.draw_string(font, Vector2(2, 34), "Действия", HORIZONTAL_ALIGNMENT_LEFT, -1, 24, UI.CREAM)
	var total := maxi(2, ps.actions)
	for i in total:
		var c := Vector2(x0 + i * 44, 24)
		actions_widget.draw_circle(c + Vector2(2, 4), 19, Color(0, 0, 0, 0.4))
		actions_widget.draw_circle(c, 19, WoodUI.INK)
		actions_widget.draw_circle(c, 16, WoodUI.PAPER)
		var filled: bool = i < ps.actions and game.phase == "main"
		actions_widget.draw_circle(c, 12, WoodUI.ORANGE if filled else WoodUI.PAPER_DARK.darkened(0.25))
	# Пирамидия: actions that only pay for a creature on one lane.
	var extra := ""
	for lane in LANES:
		var n: int = game.lane_actions(game.turn_player, lane)
		if n > 0:
			extra += "  +%d → зона %d" % [n, lane + 1]
	if extra != "" and game.phase == "main":
		actions_widget.draw_string(WoodUI.REGULAR, Vector2(x0 + total * 44, 32), extra, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, UI.ORANGE)


func _add_log(text: String) -> void:
	var col := "#f6efe0"
	if text.begins_with("—"):
		col = "#9fe7ff"
	elif text.begins_with("Победа"):
		col = "#ffd75a"
	# Names of players and of their own decks come from other PCs: no BBCode of theirs.
	var line := "[color=%s]%s[/color]\n" % [col, text.replace("[", "[lb]")]
	log_box.append_text(line)
	_log_lines.append(line)
	if _pad_log_text != null and is_instance_valid(_pad_log_text):
		_pad_log_text.append_text(line)


func _update_preview() -> void:
	_show_preview()
	if teams:
		# A landscape командная карта gets a box as wide as a card is tall.
		var tex := preview_rect.texture
		var wide := tex != null and tex.get_width() > tex.get_height()
		preview_rect.size = Vector2(350, 250) if wide else Vector2(250, 350)
		preview_rect.position = _center() - preview_rect.size * 0.5 - Vector2(0, 14)
		preview_rect.pivot_offset = preview_rect.size * 0.5


func _show_preview() -> void:
	var v = _hover_view
	var hero := _hover_hero
	if v == null and hero < 0 and not TouchInput.hovers():
		if _peek_view != null and is_instance_valid(_peek_view) and not _peek_view.is_queued_for_deletion():
			v = _peek_view
		hero = _peek_hero
	if v == null and hero >= 0:
		if tutorial != null:
			tutorial.show_card_property("")
		var ps = game.players[hero]
		preview_rect.texture = _hero_card_texture(ps.hero_card, true)
		var hc: Dictionary = CardDB.hero_card(ps.hero_card) if CardDB.has_hero_card(ps.hero_card) else {}
		var info := "Карта героя: %s" % hc.get("name", "")
		if hc.has("note"):
			info += "
" + hc["note"]
		preview_info.text = info
		return
	if v == null or not v.face_up or v.card_id == "":
		if tutorial != null:
			tutorial.show_card_property("")
		preview_rect.texture = null
		preview_info.text = ""
		return
	if v.secret:
		if tutorial != null:
			tutorial.show_card_property("")
		preview_rect.texture = null
		preview_info.text = CardDB.get_def(v.card_id)["name"]
		return
	preview_rect.texture = CardView.texture_for(v.card_id)
	if tutorial != null:
		tutorial.show_card_property(v.card_id)
	var w: Dictionary = game.where(v.uid)
	var d := CardDB.get_def(v.card_id)
	var info := CardDB.type_line(d)
	if w["zone"] == "creature":
		var c = game.card(v.uid)
		info = "АТК %d · защита %d из %d" % [game.atk_of(w["p"], w["lane"]),
			game.def_of(w["p"], w["lane"]) - c.damage, game.def_of(w["p"], w["lane"])]
		if c.granted_floop != "":
			info += "\nПриём: " + CardDB.get_def(c.granted_floop)["name"]
		if not c.under.is_empty():
			info += "\nПод картой: %d" % c.under.size()
		if c.flags.has("shield_until"):
			info += "\nУкрыто Пещерой одиночества"
		if c.flags.get("armed", false):
			info += "\nВзорвётся в начале следующего хода!"
	elif w["zone"] == "hand" and d["kind"] == "creature":
		var up := 1 if game.card(v.uid).upgraded else 0
		info += " · АТК %d / ЗАЩ %d" % [int(d["atk"]) + up, int(d["def"]) + up]
	if game.card(v.uid) != null and game.card(v.uid).upgraded:
		info += "\nУлучшена"
	if w["zone"] == "hand" and w["p"] == viewer:
		var hc = game.card(v.uid)
		var cost: int = game.cost_of(w["p"], hc)
		if cost != int(d["cost"]):
			info += "\nСейчас стоит: %d" % cost
		if game.play_land(hc) == "rainbow" and d["land"] != "rainbow":
			info += "\nСейчас Радужная карта"
	if (w["zone"] == "creature" or w["zone"] == "building") and game.is_frozen(w["p"], w["lane"]):
		info += "\nЗемля заморожена"
	preview_info.text = info


# ================================================================ main loop & input

func _process(delta: float) -> void:
	_time += delta
	CardView.poll_prefetch()
	if _shake > 0.0:
		_shake = maxf(_shake - delta * 2.5, 0.0)
		world.position = _pan + Vector2(randf_range(-1, 1), randf_range(-1, 1)) * _shake * 16.0
	else:
		world.position = _pan
	if game == null:
		return
	_pump_net()
	_run_clock(delta)
	_kb_tick()
	if _drag_view != null:
		_drag_view.target_pos = world.get_local_mouse_position() + _drag_offset
		decor.queue_redraw()
	_update_hover()
	if not _drop_targets.is_empty() or _choice != null or _arranging >= 0:
		decor.queue_redraw()
	for key in hero_ui:
		var ui: Dictionary = hero_ui[key]
		if ui["side"] >= 0 and ui["side"] < game.players.size():
			var target := float(maxi(game.players[ui["side"]].hp, 0))
			ui["shown_hp"] = lerpf(ui["shown_hp"], target, 1.0 - exp(-delta * 8.0))
			ui["hp"].text = str(int(round(ui["shown_hp"])))


func _update_hover() -> void:
	var v = null
	var keys: bool = _kn() != null and _kn().keyboard
	# A finger hovers over nothing: the mouse stays where it was lifted, and a card of the hand
	# risen there would cover its neighbours (and take their taps).
	var mouse := TouchInput.hovers()
	if keys:
		v = _kb_view()
	elif mouse and not inspect_layer.visible and not picker_layer.visible:
		v = _view_at(get_global_mouse_position())
	if v == _drag_view and _drag_view != null or not mouse and _drag_view != null:
		v = _drag_view
	var hero_side := _hero_panel_at(hud.get_local_mouse_position()) if v == null and not picker_layer.visible \
			and not inspect_layer.visible and not keys and mouse else -1
	if hero_side != _hover_hero:
		_hover_hero = hero_side
		_update_preview()
	if v != _hover_view:
		if _hover_view != null and is_instance_valid(_hover_view):
			_hover_view.hovered = false
		_hover_view = v
		if v != null:
			v.hovered = true
			if game.where(v.uid)["zone"] == "hand" and v.face_up:
				UI.sfx("hover")
		sync()
		_update_preview()


## Side whose hero panel contains `pos` (HUD coordinates), or -1 (2 на 2: whose hero card).
func _hero_panel_at(pos: Vector2) -> int:
	for key in hero_ui:
		var panel: Panel = hero_ui[key]["panel"]
		if hero_ui[key]["side"] >= 0 and Rect2(panel.position, panel.size * panel.scale).has_point(pos):
			if teams and hero_ui[key].has("portrait2") and hero_ui[key]["portrait2"].visible:
				var p2: Control = hero_ui[key]["portrait2"]
				return hero_ui[key]["seats"][1] if pos.x >= panel.position.x + p2.position.x * panel.scale.x else hero_ui[key]["seats"][0]
			return hero_ui[key]["side"]
	return -1


func _view_at(global_point: Vector2):
	var best = null
	for v in views.values():
		if not is_instance_valid(v) or v.is_queued_for_deletion():
			continue
		# A card of the bottom hand rises under the mouse: it still holds the mouse below its edge,
		# where it lay, or it would drop and rise again without end.
		var below := 0.0
		if v == _hover_view and v.lift >= 1.0 and game.where(v.uid)["zone"] == "hand" and v.target_pos.y > 600.0:
			below = v._size.y
		if v.contains_point(global_point, below) and (best == null or v.z_index > best.z_index):
			best = v
	return best


# ================================================================ keyboard

## The arrows move a frame over the table: the cards of the hand, the cards in play, the piles;
## a card picked shows where it may go, a choice shows its options. Enter or Space presses what
## the frame stands on, E, D and H are the buttons on the right. Windows over the table (a menu
## of a card, a list of cards) go by the frame of KeyNav (key_nav.gd).
func _kn():
	return get_node_or_null("/root/KeyNav")


## The table takes the keys: it is on screen and nothing covers it. `menus`: a menu of a card
## counts as no cover.
func _kb_free(menus := false) -> bool:
	if game == null or not is_visible_in_tree() or picker_layer.visible or inspect_layer.visible or pad_log_open() \
			or sb_panel != null and sb_panel.visible \
			or mulligan_panel.visible or zoom_layer.get_child_count() > 0 or context_menu.visible and not menus:
		return false
	if _kn() == null:
		return true
	# A window of the main screen over the table: looked for once a frame.
	var frame := Engine.get_process_frames()
	if frame != _kb_cover_frame:
		_kb_cover_frame = frame
		var top: Control = _kn().top_at(get_global_transform_with_canvas() * FIELD_CENTER)
		_kb_covered = top != null and top != self and not is_ancestor_of(top)
	return not _kb_covered


## For KeyNav: its frame waits while the table has the keys.
func kb_claims() -> bool:
	return _kb_free()


func _kb_input(k: InputEventKey) -> bool:
	var kn = _kn()
	if kn == null:
		return false
	var dir: Vector2 = kn.dir_of(k)
	if dir != Vector2.ZERO:
		if not _kb_free():
			return false
		if kn.keyboard:
			_kb_move(dir, k.shift_pressed)
		kn.keyboard = true
		return true
	if kn.is_action(k, "undo"):
		_on_undo_button()
		return true
	if k.echo:
		return false
	if kn.is_action(k, "press"):
		if inspect_layer.visible:
			_close_inspect()
			return true
		if not _kb_free():
			return false
		if kn.keyboard:
			_kb_press()
		kn.keyboard = true
		return true
	if kn.is_action(k, "items"):
		items_requested.emit()
		return true
	if kn.is_action(k, "card"):
		if inspect_layer.visible:
			_close_inspect()
			return true
		var v = _kb_view()
		if _kb_free() and kn.keyboard and v != null and v.face_up and not v.secret:
			_open_inspect(v.card_id)
			return true
		return false
	var lane: int = kn.lane_of(k)
	if lane >= 0:
		if not _kb_free(true):
			return false
		kn.keyboard = true
		_kb_lane(lane)
		return true
	for pair in [["main", main_button], ["draw", draw_button], ["hero", hero_button]]:
		if kn.is_action(k, pair[0]):
			if pair[0] == "main" and _arranging >= 0 and _kb_free():
				_arrange_done.emit()
				return true
			var b: Button = pair[1]
			if _kb_free(true) and b.is_visible_in_tree() and not b.disabled:
				context_menu.visible = false
				b.pressed.emit()
				return true
			return false
	return false


## A key 1-4: the zone of that number. In a choice its option there (yours first); a card
## picked goes there; a card of the hand under the frame is picked and goes there; in the
## attack the creature there attacks.
func _kb_lane(lane: int) -> void:
	if _arranging >= 0:
		_arrange_pick(lane)
		return
	if _choice != null:
		var found = null
		for opt in _choice["options"]:
			if opt is Dictionary and int(opt.get("lane", -1)) == lane and (found == null or int(opt.get("p", -1)) == viewer):
				found = opt
		if found != null:
			_resolve_choice(found)
		return
	if not _can_act():
		return
	if _drop_targets.is_empty() and game.phase == "main":
		var t := _kb_current()
		if t.get("hand", false) or t.has("view") and _is_xray_top(t["view"].uid):
			_click_view(t["view"])
	context_menu.visible = false
	for t in _drop_targets:
		if t["lane"] == lane:
			_play_selected(t)
			return
	if not _drop_targets.is_empty():
		UI.float_text(world, land_pos(viewer, lane), "Сюда нельзя", UI.CREAM, 24, 40)
		return
	if game.phase == "attack" and game.can_attack(viewer, lane):
		_issue({"cmd": "attack", "lane": lane})


## What the frame may stand on now: {id, shape (on the table), view or button, act}.
func _kb_targets() -> Array:
	var out := []
	if _arranging >= 0:
		for lane in LANES:
			out.append({"id": "land:%d" % lane, "shape": _land_shape(_arranging, lane), "act": _arrange_pick.bind(lane)})
		out.append({"id": "arrange", "button": _arrange_button, "act": func(): _arrange_done.emit()})
		return out
	if _choice != null:
		for opt in _choice["options"]:
			match _choice["kind"]:
				"creature", "building":
					var c = game.slot(opt["p"], opt.get("kind", _choice["kind"]), opt["lane"])
					if c != null and views.has(c.uid):
						out.append({"id": "u:%d" % c.uid, "view": views[c.uid], "act": _resolve_choice.bind(opt)})
				"hand_card":
					if views.has(opt) and views[opt].face_up:
						out.append({"id": "u:%d" % opt, "view": views[opt], "act": _resolve_choice.bind(opt)})
				"land":
					out.append({"id": "land:%d:%d" % [opt["p"], opt["lane"]], "shape": _land_shape(opt["p"], opt["lane"]),
						"act": _resolve_choice.bind(opt)})
				"lane":
					out.append(_kb_spot("lane:%d:%d:%s" % [opt["p"], opt["lane"], opt.get("row", "creature")], _choice_lane_shape(opt),
						_slot_view(opt["p"], opt["lane"], opt.get("row", "creature")), _resolve_choice.bind(opt)))
		if skip_button.is_visible_in_tree():
			out.append({"id": "skip", "button": skip_button, "act": func(): _resolve_choice(null)})
		return out
	if not _drop_targets.is_empty():
		for t in _drop_targets:
			var over = _slot_view(viewer, t["lane"], t["row"]) if t["lane"] >= 0 else null
			out.append(_kb_spot("drop:%d" % t["lane"], t["shape"], over, _play_selected.bind(t)))
		return out
	for c in game.players[viewer].hand:
		if views.has(c.uid) and views[c.uid].face_up:
			out.append({"id": "u:%d" % c.uid, "view": views[c.uid], "act": _kb_card.bind(c.uid), "hand": true})
	var top = game.xray_top(viewer)
	if top != null and views.has(top.uid):
		out.append({"id": "u:%d" % top.uid, "view": views[top.uid], "act": _kb_card.bind(top.uid)})
	for side in game.players.size():
		var ps = game.players[side]
		for lane in LANES:
			var cards: Array = game.buildings_at(side, lane).map(func(s): return s[0])
			if ps.creatures[lane] != null:
				cards.push_front(ps.creatures[lane])
			for c in cards:
				if views.has(c.uid):
					out.append({"id": "u:%d" % c.uid, "view": views[c.uid], "act": _kb_card.bind(c.uid)})
			if side == viewer and game.is_frozen(viewer, lane) and ps.creatures[lane] == null and _can_act():
				out.append({"id": "land:%d:%d" % [side, lane], "shape": _land_shape(side, lane), "act": _frozen_land.bind(lane)})
		if not ps.discard.is_empty():
			out.append({"id": "discard:%d" % side, "shape": _shape(discard_pos(side), _pile_size()),
				"act": _show_discard.bind(side)})
	if _can_act() and game.can_draw_for_action(viewer):
		out.append({"id": "deck", "shape": _shape(deck_pos(viewer), _pile_size()), "act": func(): _issue({"cmd": "draw"})})
	if sb_button != null and sb_button.is_visible_in_tree():
		out.append({"id": "sandbox", "button": sb_button, "act": func(): sb_button.pressed.emit()})
	return out


## A place for the frame: the card that lies there when there is one (the frame follows its turn,
## an exhausted card lies sideways in its upright place), else the place itself.
static func _kb_spot(id: String, shape: Dictionary, over, act: Callable) -> Dictionary:
	return {"id": id, "view": over, "act": act} if over != null else {"id": id, "shape": shape, "act": act}


## The card drawn in a place of a side (row "creature" or "building"), null when there is none.
func _slot_view(side: int, lane: int, row: String):
	var c = game.slot(side, row, lane)
	return views.get(c.uid) if c != null else null


## A card pressed by the keys: as a click on it in this turn, else it shows big.
func _kb_card(uid: int) -> void:
	var v = views.get(uid)
	if v == null:
		return
	var w: Dictionary = game.where(uid)
	if _can_act() and w["p"] == viewer and (w["zone"] == "hand" or w["zone"] == "creature" or w["zone"] == "building" \
			or _is_xray_top(uid)):
		_click_view(v)
	elif v.face_up and not v.secret:
		_open_inspect(v.card_id)


## The middle of a target on the screen's canvas.
func _kb_at(t: Dictionary) -> Vector2:
	if t.has("button"):
		var b: Control = t["button"]
		return b.get_global_transform_with_canvas() * (b.size * 0.5)
	if t.has("view"):
		return world.get_global_transform_with_canvas() * (t["view"] as Node2D).position
	return world.get_global_transform_with_canvas() * (t["shape"]["c"] as Vector2)


## The target under the frame; when its target is gone the frame starts again on a card of
## the hand that can be played, else on the first target.
func _kb_current() -> Dictionary:
	var list := _kb_targets()
	if list.is_empty():
		return {}
	for t in list:
		if t["id"] == _kb_id:
			return t
	var first: Dictionary = list[0]
	for t in list:
		if t.get("hand", false) and not t["view"].dimmed:
			first = t
			break
	_kb_id = first["id"]
	return first


func _kb_view():
	if not _kb_free(true):
		return null
	return _kb_current().get("view", null)


## The frame goes to the nearest target that way.
## The frame goes to the nearest target that way (`edge`: as far as it goes).
func _kb_move(dir: Vector2, edge := false) -> void:
	var cur := _kb_current()
	if cur.is_empty():
		return
	var list := _kb_targets()
	var moved := false
	for step in (30 if edge else 1):
		var from := _kb_at(cur)
		var best := {}
		var best_score := INF
		for t in list:
			if t["id"] == cur["id"]:
				continue
			var d := _kb_at(t) - from
			var along := d.dot(dir)
			if along <= 8.0:
				continue
			var score := along + absf(d.cross(dir)) * 2.5
			if score < best_score:
				best_score = score
				best = t
		if best.is_empty():
			break
		cur = best
		moved = true
	if moved:
		_kb_id = cur["id"]
		UI.sfx("hover")


func _kb_press() -> void:
	var t := _kb_current()
	if not t.is_empty():
		t["act"].call()


# ================================================================ gamepad (gamepad.gd)

var _pad_log: CanvasLayer = null      # the log in a window over the table, by the pad's Select
var _pad_log_text: RichTextLabel = null


func pad_log_open() -> bool:
	return _log_big or _pad_log != null and is_instance_valid(_pad_log)


## Select: the log of the game big over the table, again: back. A phone opens its own.
func pad_toggle_log() -> void:
	if _ph:
		phone_log_open(not _log_big)
		return
	if pad_log_open():
		pad_close_log()
		return
	_pad_log = CanvasLayer.new()
	_pad_log.layer = 14
	add_child(_pad_log)
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.02, 0.06, 0.7)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(e): if e is InputEventMouseButton and e.pressed: pad_close_log())
	_pad_log.add_child(dim)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", WoodUI.inset(5, 22, 16))
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 360
	panel.offset_right = -360
	panel.offset_top = 90
	panel.offset_bottom = -110
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pad_log.add_child(panel)
	_pad_log_text = RichTextLabel.new()
	_pad_log_text.bbcode_enabled = true
	_pad_log_text.add_theme_font_override("normal_font", WoodUI.REGULAR)
	_pad_log_text.add_theme_font_size_override("normal_font_size", 26)
	_pad_log_text.add_theme_color_override("default_color", Color(0.92, 0.9, 0.85))
	_pad_log_text.text = "".join(_log_lines)
	panel.add_child(_pad_log_text)
	_pad_log_text.scroll_to_line.call_deferred(maxi(0, _pad_log_text.get_line_count() - 1))


func pad_close_log() -> void:
	if _ph and _log_big:
		phone_log_open(false)
	if _pad_log != null and is_instance_valid(_pad_log):
		_pad_log.queue_free()
	_pad_log = null
	_pad_log_text = null


## The right stick: the log scrolls (the big one when it is open).
func pad_scroll(dy: float) -> void:
	var box: RichTextLabel = _pad_log_text if _pad_log_text != null and is_instance_valid(_pad_log_text) else log_box
	box.get_v_scroll_bar().value += dy


## The shoulders: the table frame goes to the card of the hand before or after.
func pad_hand_step(step: int) -> void:
	var kn = _kn()
	if kn == null or not _kb_free():
		return
	var hand := _kb_targets().filter(func(t): return t.get("hand", false))
	if hand.is_empty():
		return
	var i := -1
	for j in hand.size():
		if hand[j]["id"] == _kb_id:
			i = j
	i = posmod(i + step, hand.size()) if i >= 0 else (0 if step > 0 else hand.size() - 1)
	_kb_id = hand[i]["id"]
	kn.keyboard = true
	UI.sfx("hover")


## The card under the frame draws the frame itself (it follows its lift and turn); a land,
## a place or a button gets it drawn by _draw_kb.
func _kb_tick() -> void:
	var on: bool = _kn() != null and _kn().keyboard
	if on:
		_kb_draw.queue_redraw()
	var v = _kb_view() if on and _kb_free() else null
	if v != _kb_lit:
		if _kb_lit != null and is_instance_valid(_kb_lit):
			_kb_lit.set_focused(false)
		_kb_lit = v
		if v != null:
			v.set_focused(true)


func _draw_kb() -> void:
	if _kn() == null or not _kn().keyboard or not _kb_free():
		return
	var t := _kb_current()
	if t.is_empty():
		return
	var to_me := _kb_draw.get_global_transform_with_canvas().affine_inverse()
	var pulse := 0.5 + 0.5 * sin(_time * 6.0)
	if t.has("button"):
		_kb_draw.draw_set_transform_matrix(to_me)
		_kn().ring(_kb_draw, _kn().rect_of(t["button"]).grow(6.0), pulse)
	elif t.has("shape"):
		var sh: Dictionary = t["shape"]
		_kb_draw.draw_set_transform_matrix(to_me * world.get_global_transform_with_canvas() \
			* Transform2D(float(sh["r"]), sh["c"]))
		var s: Vector2 = sh["s"]
		_kn().ring(_kb_draw, Rect2(-s * 0.5, s).grow(6.0), pulse)
	_kb_draw.draw_set_transform_matrix(Transform2D.IDENTITY)


# ================================================================ field zoom

## Zoom of the field: the mouse wheel or two fingers (a pinch, the middle moves it), a press
## on bare table dragged moves a zoomed field, a double click on bare table shows it whole.
## The hands, the cards on show, the right column and the windows keep their place. True when
## the event was spent on it.
func _zoom_input(event: InputEvent) -> bool:
	if inspect_layer.visible or picker_layer.visible:
		return false
	var at := _to_board(event.position) if event is InputEventMouse else Vector2.ZERO
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and (mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN) \
				and _field_rect().has_point(at):
			var step := pow(1.15, mb.factor if mb.factor > 0.0 else 1.0)
			_zoom_at(at, step if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / step)
			return true
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			var bare := _field_rect().has_point(at) and _drag_view == null and _view_at(mb.position) == null
			_panning = false
			_pan_at = at if bare else Vector2.INF
			# Two quick taps while a card is picked or a choice is asked are two tries to play or to
			# choose (an empty lane is bare table too), not a zoom.
			if _selected_uid != -1 or _choice != null or _arranging >= 0:
				bare = bare and not mb.double_click
			if bare and mb.double_click and _ph and seated and _zoom < 1.05:
				# A phone, a round table: a double tap brings that part of the table close.
				_zoom_to(at, 2.0)
				_panning = true
				_pan_at = Vector2.INF
				return true
			if bare and mb.double_click and (_zoom > 1.0 or _phone):
				_zoom_home()
				_panning = true          # its release is no click either
				_pan_at = Vector2.INF
				return true
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			_pan_at = Vector2.INF
		return false
	if event is InputEventMouseMotion and _pan_at != Vector2.INF and _touches.size() < 2 and _zoom > 1.0:
		if not _panning and _moved(at, _pan_at, self):
			_panning = true
			_press_view = null
		if _panning:
			_set_cam(_zoom, _pan + at - _pan_at)
			_pan_at = at
			return true
		return false
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			if t.index == 0:
				_touches.clear()
			_touches[t.index] = _to_board(t.position)
			if _touches.size() == 2:
				# A pinch: what the first finger began is no click and no drag.
				_press_view = null
				_choice_press = false
				_pan_at = Vector2.INF
				_panning = true
				if _drag_view != null:
					_drag_view.dragging = false
					_drag_view = null
					sync()
		else:
			_touches.erase(t.index)
		return false
	if event is InputEventScreenDrag and _touches.has(event.index):
		var d := event as InputEventScreenDrag
		if _touches.size() < 2:
			_touches[d.index] = _to_board(d.position)
			return false
		var keys := _touches.keys()
		var a: Vector2 = _touches[keys[0]]
		var b: Vector2 = _touches[keys[1]]
		_touches[d.index] = _to_board(d.position)
		var a2: Vector2 = _touches[keys[0]]
		var b2: Vector2 = _touches[keys[1]]
		if a.distance_to(b) > 1.0:
			_zoom_at((a + b) * 0.5, a2.distance_to(b2) / a.distance_to(b))
		_set_cam(_zoom, _pan + (a2 + b2) * 0.5 - (a + b) * 0.5)
		return true
	return false


func _to_board(canvas_point: Vector2) -> Vector2:
	return get_global_transform_with_canvas().affine_inverse() * canvas_point


## Zoom by `factor` around `at` (board coordinates): the point under it stays under it.
func _zoom_at(at: Vector2, factor: float) -> void:
	var z := clampf(_zoom * factor, 1.0, ZOOM_MAX)
	_set_cam(z, at - (at - _pan) * (z / _zoom))


## Sets the zoom and the shift of the field: the table covers its view, or (smaller than the
## view, a phone) stays inside it.
func _set_cam(z: float, pan: Vector2) -> void:
	_zoom = z
	var view := _field_rect().size
	world.scale = Vector2.ONE * z
	var a := Vector2.ZERO
	var b := view - FIELD_VIEW.size * z
	_pan = pan.clamp(a.min(b), a.max(b))
	world.position = _pan
	(world.get_parent() as Control).clip_contents = z > 1.001
	context_menu.visible = false


## Smoothly to the zoom `z` around `at` (board coordinates): what is under it stays under it.
func _zoom_to(at: Vector2, z: float) -> void:
	var z0 := _zoom
	var p0 := _pan
	var z1 := clampf(z, 1.0, ZOOM_MAX)
	var p1 := at - (at - _pan) * (z1 / _zoom)
	create_tween().tween_method(func(t: float): _set_cam(lerpf(z0, z1, t), p0.lerp(p1, t)),
		0.0, 1.0, 0.25).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


## A phone, a round table: a tap by another seat's hand or piles brings its lanes close
## (a tap on the bare table again goes back). True when it did.
func _phone_seat_zoom(wpos: Vector2) -> bool:
	if not _ph or not seated or game.duel():
		return false
	if _zoom > 1.05:
		_zoom_home()
		return true
	for side in game.sides():
		if is_bottom(side):
			continue
		var rel := _rel(side)
		var spots: Array = [(T3_HAND if tri else T_HAND)[rel], deck_pos(side), discard_pos(side)]
		for spot: Vector2 in spots:
			if wpos.distance_to(spot) < 150.0:
				var mid := Vector2.ZERO
				for lane in LANES:
					mid += land_pos(side, lane)
				mid /= float(LANES)
				var field := world.get_parent() as Control
				_zoom_to(field.position + world.transform * mid, 2.0)
				return true
	return false


## Back to the field as it was shown at first, smoothly; a phone already there shows the whole table.
func _zoom_home() -> void:
	var z0 := _zoom
	var p0 := _pan
	var z1 := _home_zoom
	var p1 := _home_pan
	if _phone and absf(_zoom - _home_zoom) < 0.02 and _pan.distance_to(_home_pan) < 4.0:
		z1 = 1.0
		p1 = (_field_rect().size - FIELD_VIEW.size) * 0.5
	create_tween().tween_method(func(t: float): _set_cam(lerpf(z0, z1, t), p0.lerp(p1, t)),
		0.0, 1.0, 0.25).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _unhandled_input(event: InputEvent) -> void:
	if game == null:
		return
	if pad_log_open() and event is InputEventKey and event.pressed:
		# The big log: the arrows scroll it, Enter or Esc closes it.
		var kn = _kn()
		var dir: Vector2 = kn.dir_of(event) if kn != null else Vector2.ZERO
		if dir.y != 0.0:
			pad_scroll(dir.y * 120.0)
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_ESCAPE or kn != null and kn.is_action(event, "press"):
			pad_close_log()
			get_viewport().set_input_as_handled()
			return
	if event is InputEventKey and event.pressed and _kb_input(event):
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if zoom_layer.get_child_count() > 0:
			_close_zoom()
		elif inspect_layer.visible:
			_close_inspect()
		elif picker_layer.visible and _choice == null:
			picker_layer.visible = false
		elif context_menu.visible or _selected_uid != -1:
			_clear_selection()
		elif sb_panel != null and sb_panel.visible:
			sb_panel.visible = false
		else:
			menu_requested.emit()
		get_viewport().set_input_as_handled()
		return
	if _zoom_input(event):
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			var v = _view_at(get_global_mouse_position())
			if v != null and v.face_up and not v.secret:
				_open_inspect(v.card_id)
			elif _hero_panel_at(hud.get_local_mouse_position()) >= 0:
				_open_inspect_texture(_hero_card_texture(game.players[_hero_panel_at(hud.get_local_mouse_position())].hero_card, true))
			return
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if mb.pressed and not TouchInput.hovers() and not inspect_layer.visible and not picker_layer.visible:
			# A finger: the tapped card (or hero) goes to the preview on the left, as the mouse over it would.
			_peek_view = _view_at(get_global_mouse_position())
			_peek_hero = _hero_panel_at(hud.get_local_mouse_position()) if _peek_view == null else -1
			_update_preview()
		if not mb.pressed and _panning:
			_panning = false
			_press_view = null
			_choice_press = false
			return
		var wpos := world.get_local_mouse_position()
		if mb.pressed and _arranging >= 0:
			_arrange_click(wpos)
			return
		if mb.pressed:
			context_menu.visible = false
			_press_canvas = get_global_mouse_position()
			if _choice != null:
				_choice_press = true
				_press_pos = wpos
				_choice_view = _view_at(get_global_mouse_position())
				return
			# A discard pile opens with a click at any time: not only in your own turn.
			var pile := _discard_at(wpos)
			if pile >= 0 and not mulligan_panel.visible:
				_clear_selection()
				_show_discard(pile)
				return
			if sandbox != null and sb_panel.visible:
				_sb_press = wpos
			if not _can_act():
				return
			_press_view = _view_at(get_global_mouse_position())
			if _press_view != null and _limbo.has(_press_view.uid):
				_press_view = null
			_press_pos = wpos
		elif _choice_press:
			_choice_press = false
			# Not after a held finger (it looked at the card) or a drag.
			if _choice != null and not TouchInput.long_pressed and not _tap_moved(wpos):
				_choice_click(_press_pos, _choice_view)
		else:
			if _sb_press != Vector2.INF:
				var at := _sb_press
				_sb_press = Vector2.INF
				if _drag_view == null and not TouchInput.long_pressed and not _moved(at, wpos):
					_sb_tap(wpos, _view_at(get_global_mouse_position()))
			if _drag_view != null:
				_end_drag()
			elif TouchInput.long_pressed:
				pass  # the finger was held on the card to look at it
			elif _press_view != null and not _tap_moved(wpos):
				_click_view(_press_view)
			elif _press_view == null and _can_act():
				_click_empty(_press_pos)
			_press_view = null
	elif event is InputEventMouseMotion and _press_view != null and _drag_view == null:
		if _tap_moved(world.get_local_mouse_position()):
			var w: Dictionary = game.where(_press_view.uid)
			if (w["zone"] == "hand" and w["p"] == viewer or _is_xray_top(_press_view.uid)) and game.phase == "main":
				_begin_drag(_press_view)


## A press moved from `a` to `b` (points of `node`, the world by default) more than a tap may:
## 12 units for the mouse; for a finger TouchInput.slop_px() of the screen, whatever the zoom
## of the field and the size of the screen (12 units of a zoomed field on a 720 high phone are
## 8 pixels, less than a finger shakes: a tap became a drag of the card or of the field).
func _moved(a: Vector2, b: Vector2, node: CanvasItem = null) -> bool:
	if not TouchInput.finger:
		return a.distance_to(b) > 12.0
	var on := node if node != null else world
	var k := (get_viewport().get_final_transform() * on.get_global_transform_with_canvas()).get_scale().x
	return a.distance_to(b) * k > TouchInput.slop_px()


## The press went from where it went down to `wpos` (the world): more than a tap may, on the
## screen (a field zooming under a held finger moves the world, not the finger).
func _tap_moved(wpos: Vector2) -> bool:
	if not TouchInput.finger:
		return _press_pos.distance_to(wpos) > 12.0
	var k := get_viewport().get_final_transform().get_scale().x
	return _press_canvas.distance_to(get_global_mouse_position()) * k > TouchInput.slop_px()


func _is_xray_top(uid: int) -> bool:
	var top = game.xray_top(viewer)
	return top != null and top.uid == uid


func _can_act() -> bool:
	return not _busy and _choice == null and viewer == game.turn_player and _plays(viewer) \
		and (game.phase == "main" or game.phase == "attack") and not mulligan_panel.visible


func _click_view(v) -> void:
	var w: Dictionary = game.where(v.uid)
	var zone: String = w["zone"]
	if zone == "hand" and w["p"] == viewer or _is_xray_top(v.uid):
		if _selected_uid == v.uid:
			_clear_selection()
			return
		if zone == "hand" and _hand_crowded():
			_open_hand()
			return
		_select(v.uid)
		return
	if (zone == "creature" or zone == "building") and w["p"] == viewer:
		if game.phase == "attack" and zone == "creature" and game.can_attack(viewer, w["lane"]):
			_issue({"cmd": "attack", "lane": w["lane"]})
			return
		_show_card_menu(v, w["kind"], w["lane"])
		return
	if zone == "discard":
		_show_discard(w["p"])
		return
	_clear_selection()


func _click_empty(wpos: Vector2) -> void:
	if _selected_uid == -1 and _phone_seat_zoom(wpos):
		return
	for side in game.sides():
		if _slot_rect(discard_pos(side), _pile_size()).has_point(wpos) and not game.players[side].discard.is_empty():
			_show_discard(side)
			return
	if _selected_uid != -1:
		var t = _drop_target_at(wpos)
		if t != null:
			_play_selected(t)
			return
		_clear_selection()
		return
	if _slot_rect(deck_pos(viewer), _pile_size()).has_point(wpos) and game.can_draw_for_action(viewer):
		_issue({"cmd": "draw"})
		return
	for lane in LANES:
		if game.is_frozen(viewer, lane) and _shape_has(_land_shape(viewer, lane), wpos):
			_frozen_land(lane)
			return


## A frozen land of yours: offer to melt the ice by discarding a card.
func _frozen_land(lane: int) -> void:
	if game.can_thaw(viewer, lane):
		_show_menu_at(land_pos(viewer, lane) + Vector2(80, -60), [
			["Растопить лёд: сбросить карту", UI.BLUE, func(): _issue({"cmd": "thaw", "lane": lane})]])
	else:
		var why := "Лёд: сюда нельзя играть существ"
		if game.players[viewer].hand.is_empty():
			why = "Лёд: нужна карта для сброса"
		UI.float_text(world, land_pos(viewer, lane), why, UI.CREAM, 24, 40)


func _select(uid: int) -> void:
	_clear_selection()
	_selected_uid = uid
	var c = game.card(uid)
	if c.kind() == "spell" or c.kind() == "teamwork":
		if game.can_play(viewer, uid):
			_show_menu_at(views[uid].position + Vector2(-110, -260), [
				["Сыграть «%s»" % c.card_name(), UI.ORANGE, func(): _issue({"cmd": "play", "uid": uid, "lane": -1})]])
		else:
			UI.float_text(world, views[uid].position + Vector2(0, -200), _why_not(uid), UI.CREAM, 26, 50)
	else:
		_drop_targets = _targets_for(uid)
		if _drop_targets.is_empty():
			UI.float_text(world, views[uid].position + Vector2(0, -200), _why_not(uid), UI.CREAM, 26, 50)
	sync()


func _why_not(uid: int) -> String:
	var c = game.card(uid)
	var d: Dictionary = c.def()
	if game.phase != "main":
		return "Сейчас фаза атаки"
	var cost: int = game.cost_of(viewer, c)
	if not game.land_ok(viewer, c):
		return "Нужно %d земель: %s" % [game.lands_needed(viewer, c), CardDB.land_name(game.play_land(c))]
	if d["kind"] == "spell" and game.train.wagon == "silence":
		return "Тишина: заклинания нельзя играть"
	if game.players[viewer].turn.get("creature_only", false) and d["kind"] != "creature":
		return "Сейчас можно играть только существ"
	if game.players[viewer].actions < cost and d["kind"] != "creature":
		return "Не хватает действий"
	if d.get("extra_cost", "") == "discard":
		return "Нужна ещё карта для сброса"
	if d.get("extra_cost", "") == "floop_creature":
		return "Нужно неповёрнутое существо (и не первый ход)"
	if d["kind"] == "creature":
		var frozen := 0
		for lane in LANES:
			if game.is_frozen(viewer, lane):
				frozen += 1
		if frozen > 0:
			return "Замёрзшие земли закрыты для существ"
	if game.players[viewer].actions < cost:
		return "Не хватает действий"
	if d["kind"] != "spell" and (game.train.wagon == "narrow" or game.train.wagon_state.has("closed")):
		return "Свободные зоны закрыты"
	return "Сейчас не выполняется условие карты"


func _clear_selection() -> void:
	_selected_uid = -1
	_drop_targets = []
	context_menu.visible = false
	if game != null:
		sync()


func _targets_for(uid: int) -> Array:
	var out := []
	var c = game.card(uid)
	match c.kind():
		"creature":
			for lane in game.play_lanes(viewer, uid):
				out.append({"shape": _shape(creature_pos(viewer, lane), _creature_slot(), _card_rot(viewer, lane)), "lane": lane,
					"row": "creature", "replace": game.players[viewer].creatures[lane] != null})
		"building":
			for lane in game.play_lanes(viewer, uid):
				out.append({"shape": _shape(building_pos(viewer, lane), _building_slot(), _card_rot(viewer, lane)), "lane": lane,
					"row": "building", "replace": game.players[viewer].buildings[lane] != null \
						and not game.creature_text(viewer, lane, "burly_lumberjack")})
		"spell", "teamwork":
			if game.can_play(viewer, uid):
				var field := Rect2(_center() - Vector2(T_HALF, T_HALF), Vector2(T_HALF, T_HALF) * 2.0) if teams \
					else Rect2(448, 52, 1024, 796)
				out.append({"shape": _shape(field.get_center(), field.size), "lane": -1, "row": "", "replace": false, "spell": true})
	return out


func _drop_target_at(wpos: Vector2):
	for t in _drop_targets:
		if _shape_has(t["shape"], wpos, 18.0):
			return t
	return null


func _begin_drag(v) -> void:
	context_menu.visible = false
	_selected_uid = v.uid
	_drag_view = v
	_drag_offset = v.position - world.get_local_mouse_position()
	_drag_offset = _drag_offset.limit_length(40.0)
	v.dragging = true
	v.z_index = 240
	v.lift = 1.0
	v.target_scale = 0.4
	v.target_rot = 0.0
	_drop_targets = _targets_for(v.uid)
	UI.sfx("card")


func _end_drag() -> void:
	var v = _drag_view
	_drag_view = null
	v.dragging = false
	var t = _drop_target_at(world.get_local_mouse_position())
	if t != null:
		_play_selected(t)
	else:
		_clear_selection()


func _play_selected(t: Dictionary) -> void:
	var uid := _selected_uid
	_clear_selection()
	_issue({"cmd": "play", "uid": uid, "lane": t["lane"]})


func _show_card_menu(v, zone: String, lane: int) -> void:
	var items := []
	var c = game.slot(viewer, zone, lane)
	if game.can_floop(viewer, zone, lane) and game.own_floop_ok(viewer, zone, lane):
		var ab: String = game.floop_ability(c, viewer, zone, lane)
		var label: String = "ФЛЮП" if ab == c.ab() else "ФЛЮП: " + CardDB.get_def(ab)["name"]
		var fc: String = CardDB.get_def(ab).get("floop_cost", "")
		if fc == "action":
			label += "  −1 д."
		items.append([label, UI.GREEN, func(): _issue({"cmd": "floop", "kind": zone, "lane": lane})])
	if game.can_floop(viewer, zone, lane) and game.hero_floop_ok(viewer, zone, lane):
		items.append(["ФЛЮП героя: 1 урон", UI.GREEN,
			func(): _issue({"cmd": "floop", "kind": zone, "lane": lane, "hero": true})])
	if game.can_activate(viewer, zone, lane):
		var cost: int = game.activation_cost(viewer, zone, lane)
		var act_label := "Способность  −%d д." % cost
		match CardDB.get_def(game.act_ability(c, viewer, zone, lane)).get("act_cost", ""):
			"discard":
				act_label = "Способность: сбросить карту" if cost == 0 else act_label + " и карту"
			"destroy_self":
				act_label = "Способность: уничтожить её"
			"remove_freeze":
				act_label = "Способность: снять лёд"
		items.append([act_label, UI.BLUE, func(): _issue({"cmd": "activate", "kind": zone, "lane": lane})])
	if zone == "creature" and game.can_attack(viewer, lane):
		items.append(["Атаковать", UI.RED, func(): _issue({"cmd": "attack", "lane": lane})])
	if items.is_empty():
		var why := "Нет доступных действий"
		if game.is_first_turn() and game.floop_ability(c, viewer, zone, lane) != "":
			why = "Первый ход: без флюпов и атак"
		elif c.exhausted:
			why = "Карта уже повёрнута"
		elif zone == "creature" and game.silenced(viewer, lane):
			why = "Лединочная камера: существо скованно льдом"
		elif zone == "creature" and game.lane_spots(viewer, lane).any(func(s): return game.creature_text(s[0], s[1], "woadic_enchantress")) \
				and game.floop_ability(c, viewer, zone, lane) != "":
			why = "Синюшная чародейка запрещает флюпы в этой зоне"
		elif zone == "creature" and game.foe_creature(viewer, lane) != null \
				and game.protected_by_cool_dog(game.across(viewer, lane)[0], game.across(viewer, lane)[1]):
			why = "Атаке мешает Крутой пёс"
		elif zone == "creature" and game.foe_creature(viewer, lane) != null \
				and game.shielded(game.across(viewer, lane)[0], game.across(viewer, lane)[1]):
			why = "Существо напротив укрыто Пещерой"
		elif game.floop_ability(c, viewer, zone, lane) != "" or game.act_ability(c, viewer, zone, lane) != "":
			why = "Сейчас способность применить нельзя"
		UI.float_text(world, v.position + Vector2(0, -90), why, UI.CREAM, 24, 40)
		return
	_show_menu_at(v.position + Vector2(90, -60), items)


func _show_menu_at(pos: Vector2, items: Array) -> void:
	for ch in context_menu.get_children():
		ch.queue_free()
	for it in items:
		var b := WoodUI.button_fixed(it[0], it[1], 34 if _ph else 22, Vector2(340, P_ROW) if _ph else Vector2(230, 52))
		var cb: Callable = it[2]
		b.pressed.connect(func():
			context_menu.visible = false
			cb.call())
		context_menu.add_child(b)
	var low := Vector2(HUD_X - 300 + _side, 860)
	if _ph:
		low = Vector2(P_X - 360 + _side, 1070.0 - items.size() * (P_ROW + 8.0))
	context_menu.position = (_field_rect().position + world.transform * pos).clamp(Vector2(20 - _side, 20), low)
	context_menu.visible = true
	if _kn() != null:
		_kn().scope = context_menu
		if _kn().keyboard:
			_kn().pick(context_menu.get_child(context_menu.get_child_count() - items.size()))
	context_menu.modulate.a = 0.0
	context_menu.scale = Vector2.ONE * 0.85
	var tw := context_menu.create_tween().set_parallel()
	tw.tween_property(context_menu, "modulate:a", 1.0, 0.12)
	tw.tween_property(context_menu, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _on_main_button() -> void:
	if _watching():
		ai_paused = not ai_paused
		_update_hud()
		return
	if not _can_act():
		return
	if game.phase == "main" and not game.is_first_turn() and not game.attackers_left(viewer).is_empty():
		_issue({"cmd": "begin_attack"})
	else:
		_issue({"cmd": "end_turn"})


## A command from this machine's player. Online, it is also sent to the
## other player, together with a fingerprint of the state it applies to.
func _on_draw_button() -> void:
	if _watching():
		ai_speed = next_speed(ai_speed)
		_update_hud()
		return
	_issue({"cmd": "draw"})


func _on_hero_button() -> void:
	if replay_steps != null:
		set_viewer(game.next_seat(viewer))
		return
	_issue({"cmd": "hero"})


func _issue(c: Dictionary, timed_out := false) -> void:
	if not _plays(viewer):
		return      # на троих: whoever dropped out watches the bottom side, it is not theirs
	_issue_as(viewer, c, timed_out)


## A command of seat p from this machine: its player's, or (2 на 2 online, the host) its AI's.
func _issue_as(p: int, c: Dictionary, timed_out := false) -> void:
	if _busy:
		return
	if tutorial != null and not tutorial.allow_command(p, c):
		tutorial.reject_command()
		return
	if net != null:
		_net_seq_out += 1
		var msg := {"t": "cmd", "p": p, "c": c, "n": _net_seq_out, "h": game.state_hash()}
		if turn_time > 0:
			msg["tl"] = snappedf(_clock_left, 0.01)    # the other side sets its clock by ours
		if timed_out:
			msg["to"] = true
		net.send(msg)
	if timed_out:
		_add_log("— Время хода вышло")
	await _run(func(): await _command(p, c))
	if tutorial != null:
		tutorial.command_resolved(p, c)


## Runs one engine command with input locked, then checks what comes next.
func _run(cmd: Callable) -> void:
	if _busy:
		return
	_busy = true
	_clear_selection()
	_update_hud()
	await cmd.call()
	_busy = false
	if sandbox != null:
		sandbox.refill()
		_sb_follow()
	sync()
	if sb_panel != null:
		sb_panel.refresh()
	if replay_steps != null:
		return      # a replay has every step recorded, the turn ends included
	if _concede_wanted:
		_try_concede()
	if game.phase == "attack" and game.attackers_left(game.turn_player).is_empty() \
			and not (tutorial != null and tutorial.hold_combat_end(game.turn_player)):
		# Everybody has attacked: the turn ends. Online, only the acting side says so.
		if net == null:
			_run(func(): await game.cmd_end_turn(game.turn_player))
		elif game.turn_player == local_player or seat_agents.has(game.turn_player):
			_issue_as(game.turn_player, {"cmd": "end_turn"})
	elif game.phase == "handoff":
		if sandbox != null:
			await _run(func(): await game.cmd_start_turn())
			trigger_ai_turn()
		elif seated and net == null and not _is_ai_seat(game.turn_player) and humans.size() > 1 \
				and game.turn_player != viewer:
			handoff_needed.emit()    # 2 на 2 at one PC: the next person takes the seat
		elif seated and net == null:
			if humans.has(game.turn_player):
				set_viewer(game.turn_player)
			await _run(func(): await game.cmd_start_turn())
			trigger_ai_turn()
		elif net == null and ai_agent == null:
			handoff_needed.emit()
		else:
			await _run(func(): await game.cmd_start_turn())
			trigger_ai_turn()


## A player's command from this PC or from the other side online. Before it the state is
## kept, so that the command can be taken back ("undo" goes the same way online).
func _command(p: int, c: Dictionary) -> void:
	_apply_settings()
	if sandbox != null:
		# «Песочница»: every command may be taken back, with «Шаг назад» of the panel.
		if c.get("cmd", "") != "undo":
			sandbox.push()
			await game.run_command(p, c)
			sandbox.settle()
		return
	if c.get("cmd", "") == "undo":
		_undo()
		return
	if not _undo_seat(p):
		await game.run_command(p, c)
		return
	var point: Dictionary = game.undo_point(p)
	var h: int = game.state_hash()
	await game.run_command(p, c)
	var ok: bool = game.undo_clean(point) and game.state_hash() != h
	_undo_point = point if ok and game.turn_player == p and (game.phase == "main" or game.phase == "attack") else {}


## Undo is in this game: against the AI, or online when the room creator allowed it.
func _undo_mode() -> bool:
	if replay_steps != null or ai_vs_ai:
		return false
	if net != null:
		return undo_online and not seated
	if seated:
		return humans.size() == 1 and not seat_agents.is_empty()
	return ai_agent != null


## Seat p may take its commands back (people only, not the AI).
func _undo_seat(p: int) -> bool:
	if not _undo_mode():
		return false
	if net != null:
		return true
	return humans.has(p) if seated else p == local_player


func _can_undo() -> bool:
	if sandbox != null:
		return not _busy and _choice == null and sandbox.can_undo()
	if _busy or _choice != null or _undo_point.is_empty() or _undo_used == game.turn_number:
		return false
	var c = _undo_point["copy"]
	return _undo_point["p"] == viewer and c.turn_number == game.turn_number and game.turn_player == viewer \
		and (game.phase == "main" or game.phase == "attack")


func _on_undo_button() -> void:
	if sandbox != null:
		sb_undo()
		return
	if _can_undo():
		_issue({"cmd": "undo"})


func _undo() -> void:
	if _undo_point.is_empty():
		return
	game.undo_to(_undo_point)
	_undo_point = {}
	_undo_used = game.turn_number
	_limbo.clear()
	_revealed = []
	log_box.clear()
	_log_lines.clear()
	for line in game.log_lines:
		_add_log(line)
	_add_log("— Ход отменён")
	sync()


## На троих online: the player gives up. It is a command of their own turn, so it waits for it.
func concede_when_able() -> void:
	_concede_wanted = true
	if game.turn_player != local_player:
		flash_note("Ты сдашься в начале своего хода")
	_try_concede()


## The player has given up and waits for their turn to drop out.
func concede_pending() -> bool:
	return _concede_wanted


func _try_concede() -> void:
	if game == null or game.phase == "over" or game.is_out(local_player):
		_concede_wanted = false
		return
	if game.turn_player == local_player and (game.phase == "main" or game.phase == "attack") and not _busy and _choice == null:
		_concede_wanted = false
		_issue_as(local_player, {"cmd": "concede"})


func trigger_ai_turn() -> void:
	if game != null and game.phase != "over" and _is_ai_seat(game.turn_player):
		_run_ai_loop()


func _is_ai_seat(p: int) -> bool:
	if seated:
		return seat_agents.has(p)
	return ai_vs_ai or (ai_agent != null and p == ai_player)


func _agent_for(p: int):
	if seated:
		return seat_agents.get(p)
	if ai_vs_ai:
		return ai_agent if p == 1 else ai_agent_2
	return ai_agent if p == ai_player else null


## Plays AI turns until a human has to move or the game ends. One loop serves
## every AI seat, so in AI-vs-AI it simply carries on with the other side.
func _run_ai_loop() -> void:
	if _ai_turn_running or game == null:
		return
	_ai_turn_running = true
	var my_game = game
	while is_inside_tree() and game == my_game and game.phase != "over":
		await _wait(0.6)
		while is_inside_tree() and game == my_game and (_busy or _choice != null or hold_ai > 0 or (ai_vs_ai and ai_paused)):
			await get_tree().process_frame
		if not is_inside_tree() or game != my_game or game.phase == "over":
			break
		var p: int = game.turn_player
		if not (game.phase == "main" or game.phase == "attack") or not _is_ai_seat(p):
			break
		var agent = _agent_for(p)
		var cmd: Dictionary
		if agent.has_method("ban_command"):
			# The self-play network decides everything itself, hero abilities included.
			# A level with a search thinks for a while first (scripts/ai/search.gd).
			cmd = await agent.pick_command_async(game, p)
			if game != my_game:
				break
		else:
			# Old network: hero card abilities first (it does not know them), then
			# the network; an action it would waste may still go to the hero.
			var hero_ok: bool = _ai_hero_skip.get(p, -1) != game.turn_number
			cmd = AIHelper.hero_command(game, p) if hero_ok else {}
			if cmd.is_empty():
				cmd = agent.pick_command(game, p)
				if hero_ok and (cmd["cmd"] == "end_turn" or cmd["cmd"] == "begin_attack"):
					var spare: Dictionary = AIHelper.spare_action_command(game, p)
					if not spare.is_empty():
						cmd = spare
		await _run_ai_command(p, cmd)
		if tutorial != null:
			await tutorial.after_ai_command(p, cmd)
		AIHelper.clear_plan(game)
	_ai_turn_running = false


## Runs one AI command. A command of the self-play network that changed nothing
## is banned in that state (as in its training), so it picks something else.
## With the old network such a command ends the turn, so the AI never gets
## stuck repeating it; a hero ability that changed nothing is not tried again this turn.
func _run_ai_command(p: int, cmd: Dictionary) -> void:
	var before: int = game.state_hash()
	if sandbox != null:
		sandbox.push()
	if net != null:
		await _issue_as(p, cmd)
	else:
		await _run(func(): await game.run_command(p, cmd))
	if sandbox != null:
		sandbox.settle()
	if game == null or game.state_hash() != before or game.turn_player != p \
			or not (game.phase == "main" or game.phase == "attack"):
		return
	var agent = _agent_for(p)
	if agent != null and agent.has_method("ban_command"):
		agent.ban_command(before, cmd)
	elif cmd["cmd"] == "hero":
		_ai_hero_skip[p] = game.turn_number
	elif net != null:
		await _issue_as(p, {"cmd": "end_turn"})
	else:
		await _run(func(): await game.run_command(p, {"cmd": "end_turn"}))


## Plays the replay's steps one by one, with the table's animations. Ends with
## replay_ended: "" when every step is played, "broken" when the game stopped
## matching the recording (another version of the game made it). A live replay waits for
## more steps till the game is over.
func start_replay() -> void:
	var my_game = game
	var reason := ""
	_replay_running = true
	while is_inside_tree() and game == my_game and (_replay_pos < replay_steps.size() or (live_replay and game.phase != "over")):
		if _replay_pos < replay_steps.size():
			var behind: int = replay_steps.size() - _replay_pos
			if not live_replay or behind <= LIVE_BEHIND:
				await _wait(0.6 if replay_steps[_replay_pos].get("t") == "cmd" else 0.3)
		else:
			await get_tree().process_frame     # live: the next steps have not come yet
		while is_inside_tree() and game == my_game and (_busy or hold_ai > 0 or (ai_paused and _seek_to < 0)):
			await get_tree().process_frame
		if not is_inside_tree() or game != my_game:
			return
		if _seek_to >= 0:
			# Between two steps nothing is half done: main can put another game on the table.
			_replay_running = false
			var to := _seek_to
			_seek_to = -1
			replay_seek.emit(to)
			return
		if _replay_pos >= replay_steps.size():
			continue
		# Read after the wait: live, the steps not played yet may have been replaced meanwhile.
		var st: Dictionary = replay_steps[_replay_pos]
		_replay_pos += 1
		if st.get("t") == "pick" or (st.has("h") and int(st["h"]) != game.state_hash()):
			reason = "broken"
			break
		if st.get("t") == "over":
			force_over(int(st.get("w", -1)))
			continue
		await _run(func(): await Replay.apply(game, st))
		if _replay_pos < 0:
			reason = "broken"
			break
	_replay_running = false
	if is_inside_tree() and game == my_game:
		replay_ended.emit(reason)


## Jumps the replay to `pos` steps played: once the step on the table is played, or at
## once when the replay has ended.
func seek_replay(pos: int) -> void:
	if _replay_running:
		_seek_to = pos
	else:
		replay_seek.emit(pos)


## Index of the next step of the replay.
func replay_pos() -> int:
	return _replay_pos


## The replay jumped: the game set up at `pos` steps takes the table, the cards move to
## their places in it.
func replace_game(g, pos: int) -> void:
	game = g
	game.animator = self
	game.chooser = self
	_replay_pos = pos
	_limbo.clear()
	_revealed = []
	_clear_selection()
	_fit_table()
	for uid in views.keys():
		var c = game.card(uid)
		if c == null or c.id != views[uid].card_id:
			_retire_view(uid)
	log_box.clear()
	_log_lines.clear()
	sync()
	_update_hud()


## A recorded choice: show what the player is choosing, then take the recorded answer.
func _replay_choice(req: Dictionary):
	var p := int(req.get("player", game.turn_player))
	prompt_label.text = "%s: %s" % [game.players[p].name if p >= 0 and p < game.players.size() else "?", req.get("prompt", "выбор")]
	skip_button.visible = false
	prompt_panel.visible = true
	await get_tree().process_frame
	prompt_panel.position = _prompt_pos()
	var my_game = game
	while live_replay and is_inside_tree() and game == my_game and _replay_pos >= replay_steps.size():
		await get_tree().process_frame      # live: the player is still choosing
	if live_replay and _replay_pos >= 0 and _replay_pos < replay_steps.size() and replay_steps[_replay_pos].get("t") == "over":
		# The match ended in the middle of the choice (a surrender): the next step ends it here too.
		prompt_panel.visible = false
		var options: Array = req.get("options", [])
		return null if req.get("optional", false) or options.is_empty() else options[0]
	if _replay_pos < 0 or _replay_pos >= replay_steps.size() or replay_steps[_replay_pos].get("t") != "pick":
		_replay_pos = -1        # the recording has no answer here: it is broken
		prompt_panel.visible = false
		return null
	var st: Dictionary = replay_steps[_replay_pos]
	_replay_pos += 1
	await _wait(0.7)
	prompt_panel.visible = false
	return Replay.answer(req, st)


## Replays the other player's next command once the table is idle.
func _pump_net() -> void:
	if net == null or not net_accept or _busy or _choice != null or _net_cmds.is_empty():
		return
	if not (game.phase == "main" or game.phase == "attack"):
		return
	var d: Dictionary = _net_cmds.pop_front()
	if not _remote_cmd_ok(d):
		desync.emit("от соперника пришла неверная команда")
		return
	# Commands are numbered by the PC that sends them (2 на 2 there are several).
	var from := int(d.get("s", -1))
	var expected := int(_net_seq_from.get(from, 0)) + 1
	_net_seq_from[from] = expected
	if int(d["n"]) != expected:
		desync.emit("пропущена команда %d (пришла %d)" % [expected, int(d["n"])])
	elif int(d["h"]) != game.state_hash():
		desync.emit("состояние игры разошлось перед командой %d" % expected)
	var p: int = d["p"]
	var c: Dictionary = d["c"]
	if d.has("tl"):
		_clock_sync()
		_clock_left = float(d["tl"])
	if d.get("to", false):
		_add_log("— Время хода вышло")
	_run(func(): await _command(p, c))


## The choice banner: above the lanes (2 на 2: between the two fronts).
func _prompt_pos() -> Vector2:
	if teams:
		return _center() - prompt_panel.size * 0.5
	return Vector2(FIELD_CENTER.x + _hud_dx() - prompt_panel.size.x * 0.5, PROMPT_Y)


## Used by the main screen for engine calls outside normal input.
func run_engine(cmd: Callable) -> void:
	await _run(cmd)


## Lets player p reorder their landscapes; returns the chosen order of types.
func arrange_lands_prompt(p: int) -> Array:
	set_viewer(p)
	_arranging = p
	_arr_types = game.players[p].lands.map(func(l): return l["type"])
	_arr_pick = -1
	arrange_title.text = "Расстановка земель: %s" % game.players[p].name
	arrange_panel.visible = true
	_update_lands()
	decor.queue_redraw()
	await get_tree().process_frame
	arrange_panel.position = Vector2(_center().x + _hud_dx() - arrange_panel.size.x * 0.5, 40)
	await _arrange_done
	arrange_panel.visible = false
	var out := _arr_types.duplicate()
	_arranging = -1
	_arr_pick = -1
	decor.queue_redraw()
	return out


func _arrange_click(wpos: Vector2) -> void:
	for lane in LANES:
		if _shape_has(_land_shape(_arranging, lane), wpos):
			_arrange_pick(lane)
			return


## The first land picked waits; the second one trades places with it.
func _arrange_pick(lane: int) -> void:
	if _arr_pick < 0:
		_arr_pick = lane
		UI.sfx("select")
	else:
		var t = _arr_types[_arr_pick]
		_arr_types[_arr_pick] = _arr_types[lane]
		_arr_types[lane] = t
		_flip_land_anim(_arranging, _arr_pick)
		_flip_land_anim(_arranging, lane)
		_arr_pick = -1
		UI.sfx("flip")
	_update_lands()
	decor.queue_redraw()


func mulligan_prompt(p: int) -> bool:
	set_viewer(p)
	hide_hands = false
	sync()
	mulligan_title.text = "Стартовая рука: %s" % game.players[p].name
	mulligan_change.disabled = game.players[p].mulligan_used
	mulligan_panel.visible = true
	await get_tree().process_frame
	mulligan_panel.position = Vector2(_center().x + _hud_dx() - mulligan_panel.size.x * 0.5, _center().y + 20)
	if _kn() != null:
		_kn().scope = mulligan_panel
		if _kn().keyboard:
			_kn().pick(_mulligan_keep)
	var changed: bool = await _mulligan_done
	mulligan_panel.visible = false
	return changed


# ================================================================ turn timer

## A new turn on the table gets the full time.
func _clock_sync() -> void:
	var key := "%d:%d" % [game.turn_number, game.turn_player]
	if key != _clock_key:
		_clock_key = key
		_clock_left = float(turn_time)


## The turn player's time runs while they think: not while cards fly about, the link
## is down or the other player answers a choice. Both machines count it; every command
## of the turn player carries what their machine has left, and at zero that machine
## ends the turn.
func _run_clock(delta: float) -> void:
	_apply_settings()
	if net == null or turn_time <= 0:
		return
	var playing: bool = game.phase == "main" or game.phase == "attack"
	if playing:
		_clock_sync()
		var thinking: bool = _chooser == game.turn_player if _chooser >= 0 else not _busy
		if thinking and net.active:
			_clock_left = maxf(_clock_left - delta, 0.0)
		if _clock_left <= 0.0 and game.turn_player == local_player:
			_time_out()
	_show_clock(playing)


## Our time is up: a pending choice gets the AI's answer, then the turn ends
## as if the button were pressed.
func _time_out() -> void:
	if _choice != null:
		_resolve_choice(AIHelper.choose(game, _choice))
		return
	if _busy:
		return
	if _drag_view != null:
		_drag_view.dragging = false
		_drag_view = null
	_issue_as(local_player, {"cmd": "end_turn"}, true)


## The time left on the turn player's tag, red for the last ten seconds.
func _show_clock(playing: bool) -> void:
	var sec := ceili(_clock_left) if playing else -1
	if sec == _clock_shown:
		return
	var urgent := sec >= 0 and sec <= 10
	if urgent and sec < _clock_shown and game.turn_player == local_player:
		UI.sfx("click")
	_clock_shown = sec
	for key in hero_ui:
		var ui: Dictionary = hero_ui[key]
		for k in (["", "2"] if ui.has("turn2") else [""]):
			var tag: PanelContainer = ui["turn" + k]
			ui["turn_text" + k].text = "ХОДИТ %d:%02d" % [int(sec / 60.0), sec % 60] if sec >= 0 else "ХОДИТ"
			tag.add_theme_stylebox_override("panel", _padded(WoodUI.paper(WoodUI.RED if urgent else WoodUI.GO, 0.0, 13, 3.0), 12, 1))
			tag.reset_size()
			if ui.has("turn2") and ui["portrait2"].visible:     # 2 на 2: under the middle of each hero card
				var portrait: Control = ui["portrait" + k]
				tag.position.x = portrait.position.x + portrait.size.x * 0.5 - tag.size.x * 0.5
			else:
				tag.position.x = maxf(78.0 - tag.size.x * 0.5, 6.0)    # under the middle of the hero card


# ================================================================ inspect / picker

func _open_inspect(card_id: String) -> void:
	_open_inspect_texture(CardView.texture_for(card_id))


func _open_inspect_texture(tex: Texture2D) -> void:
	inspect_rect.texture = tex
	# The big card fits the screen whatever the interface scale.
	var room := FitCenter.safe_rect(self, 20.0).size
	inspect_rect.size = Vector2(560, 784) * minf(1.0, minf(room.x / 560.0, room.y / 784.0))
	inspect_rect.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_KEEP_SIZE)
	inspect_rect.pivot_offset = inspect_rect.size * 0.5
	inspect_layer.visible = true
	inspect_rect.scale = Vector2.ONE * 0.7
	var tw := inspect_rect.create_tween()
	tw.tween_property(inspect_rect, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	UI.sfx("deal")


func _close_inspect() -> void:
	inspect_layer.visible = false


# ================================================================ chooser

func choose(req: Dictionary):
	if replay_steps != null:
		return await _replay_choice(req)
	if (ai_vs_ai or ai_agent != null or not seat_agents.is_empty()) and _is_ai_seat(int(req.get("player", local_player))):
		await _wait(0.35)
		var ai_answer = _ai_choice(req)
		if net != null:
			net.send({"t": "choice", "r": ai_answer})     # 2 на 2 online: the host's AI seat
		return ai_answer
	if net != null:
		_chooser = int(req.get("player", local_player))
	if net != null and _chooser != local_player:
		var remote = await _remote_choice(req)
		_chooser = -1
		return remote
	var r = await _local_choice(req)
	_chooser = -1
	if net != null:
		net.send({"t": "choice", "r": r})
	return r


## The AI's answer to a choice of its seat.
func _ai_choice(req: Dictionary):
	var agent = _agent_for(int(req.get("player", local_player)))
	if agent != null and agent.has_method("pick_choice"):
		return agent.pick_choice(game, req)
	return AIHelper.choose(game, req)


## The other player is picking a target: show what they are deciding and
## wait for their answer to arrive.
func _remote_choice(req: Dictionary):
	var who := int(req.get("player", -1))
	var by := "Соперник"
	if seated and who >= 0 and who < game.players.size():
		by = game.players[who].name
	prompt_label.text = "%s выбирает: %s" % [by, str(req.get("prompt", "…"))]
	skip_button.visible = false
	prompt_panel.visible = true
	await get_tree().process_frame
	prompt_panel.position = _prompt_pos()
	while _net_choices.is_empty():
		if seat_agents.has(who):
			# 2 на 2 online: the player left meanwhile and the AI took the seat over.
			prompt_panel.visible = false
			var r = _ai_choice(req)
			net.send({"t": "choice", "r": r})
			return r
		await _net_choice_arrived
	prompt_panel.visible = false
	var got: Array = _net_choices.pop_front()
	var r = got[0]
	var options: Array = req.get("options", [])
	var skip_ok: bool = req.get("optional", false) or options.is_empty()
	# Only an answer the request offered (or the skip of an optional one), from the PC of that seat.
	if not _remote_seat_ok(who, got[1]) or not (options.has(r) or (r == null and skip_ok)):
		desync.emit("от соперника пришёл неверный выбор")
		return null if skip_ok else options[0]
	return r


func _local_choice(req: Dictionary):
	_choice = req
	_choice_result = null
	_clear_selection()
	var options: Array = req["options"]
	var chooser_p: int = int(req.get("player", viewer))
	match req["kind"]:
		"creature", "building":
			for opt in options:
				var c = game.slot(opt["p"], opt.get("kind", req["kind"]), opt["lane"])
				if c != null and views.has(c.uid):
					views[c.uid].set_highlight("target")
		"hand_card":
			if chooser_p != viewer or hide_hands or _hand_crowded():
				# Somebody else's hand (hot-seat), or a phone's long hand: the cards in the picker.
				_open_picker(req)
			else:
				for uid in options:
					if views.has(uid):
						views[uid].set_highlight("target")
		"discard_card", "card", "option":
			_open_picker(req)
	var text: String = req.get("prompt", "Сделай выбор")
	if chooser_p != viewer and net == null and chooser_p >= 0 and chooser_p < game.players.size():
		text = "Выбирает %s — %s" % [game.players[chooser_p].name, text]
		picker_title.text = text
	prompt_label.text = text
	skip_button.visible = req.get("optional", false) \
			and (tutorial == null or tutorial.optional_choice_skip_allowed())
	prompt_panel.visible = true
	_update_hud()
	await get_tree().process_frame
	prompt_panel.position = _prompt_pos()
	await _choice_done
	for v in views.values():
		v.set_highlight("")
	prompt_panel.visible = false
	picker_layer.visible = false
	var r = _choice_result
	_choice = null
	decor.queue_redraw()
	return r


func _resolve_choice(result) -> void:
	if _choice == null:
		return
	if tutorial != null and not tutorial.allow_choice(_choice, result):
		tutorial.reject_choice()
		return
	_choice_result = result
	UI.sfx("select")
	_choice_done.emit()


## A tap while a choice is asked, by what was under the finger when it went down (the field may
## have moved under it since: a zoom going on).
## Without `v` the card is looked for at `wpos`.
func _choice_click(wpos: Vector2, v = false) -> void:
	if v is bool:
		v = _view_at(world.get_global_transform_with_canvas() * wpos)
	if v != null and not views.values().has(v):
		v = null
	var options: Array = _choice["options"]
	match _choice["kind"]:
		"creature", "building":
			if v == null:
				return
			for opt in options:
				var c = game.slot(opt["p"], opt.get("kind", _choice["kind"]), opt["lane"])
				if c != null and c.uid == v.uid:
					_resolve_choice(opt)
					return
		"hand_card":
			if v != null and options.has(v.uid):
				_resolve_choice(v.uid)
		"land":
			for opt in options:
				if _shape_has(_land_shape(opt["p"], opt["lane"]), wpos):
					_resolve_choice(opt)
					return
		"lane":
			for opt in options:
				if _shape_has(_choice_lane_shape(opt), wpos, 16.0):
					_resolve_choice(opt)
					return


func _choice_lane_shape(opt: Dictionary) -> Dictionary:
	var rot := _card_rot(opt["p"], opt["lane"])
	if opt.get("row", "creature") == "building":
		return _shape(building_pos(opt["p"], opt["lane"]), _building_slot(), rot)
	return _shape(creature_pos(opt["p"], opt["lane"]), _creature_slot(), rot)


## The side whose discard pile is under `wpos` (one of its cards, or the place of the pile), or -1.
func _discard_at(wpos: Vector2) -> int:
	var v = _view_at(get_global_mouse_position())
	if v != null:
		var w: Dictionary = game.where(v.uid)
		return int(w["p"]) if w["zone"] == "discard" else -1
	for side in game.sides():
		if _slot_rect(discard_pos(side), _pile_size()).has_point(wpos) and not game.players[side].discard.is_empty():
			return side
	return -1


## Read-only look through a discard pile (it is public information).
func _show_discard(side: int) -> void:
	var cards: Array = game.players[side].discard
	if cards.is_empty():
		return
	var ids := []
	for i in range(cards.size() - 1, -1, -1):
		ids.append(cards[i].id)
	_show_cards("Сброс: %s (%d)" % [game.players[side].name, cards.size()], ids)


## Read-only overlay with card faces (discard piles, revealed hands).
func _show_cards(title: String, ids: Array) -> void:
	_clear_picker()
	picker_title.text = title
	var item := Vector2(170, 238) if ids.size() <= 14 else Vector2(112, 157)
	if _ph:
		item = Vector2(150, 210) if ids.size() <= 14 else Vector2(112, 157)
	for id in ids:
		var r := TextureRect.new()
		r.texture = CardView.texture_for(id)
		r.material = CardView.SHARP
		r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		r.custom_minimum_size = item
		r.gui_input.connect(_zoom_input_on.bind(id))
		r.set_meta("kn_zoom", true)          # Enter shows the card big (key_nav.gd)
		picker_grid.add_child(r)
	var close := WoodUI.button_fixed("Закрыть", UI.PURPLE, 24, Vector2(200, 60))
	close.pressed.connect(func(): picker_layer.visible = false)
	picker_buttons.add_child(close)
	_fit_picker(ids.size(), item)
	picker_layer.visible = true
	UI.sfx("deal")


## A phone: the own hand is so long its cards lie over each other (less than P_OPEN_PART of a
## card shows): a tap on it opens the whole hand big instead of picking a card under the finger.
func _hand_crowded() -> bool:
	if not _ph or game == null or viewer < 0 or viewer >= game.players.size():
		return false
	var n: int = game.players[viewer].hand.size()
	if n < 2:
		return false
	var a: Array = _seat_hand_layout(viewer, 0, n) if teams else _hand_layout(true, 0, n)
	var b: Array = _seat_hand_layout(viewer, 1, n) if teams else _hand_layout(true, 1, n)
	var w := CardView.SIZE.x * (0.38 if teams else P_S_HAND)
	return absf((b[0] as Vector2).x - (a[0] as Vector2).x) < w * P_OPEN_PART


## A phone: the whole own hand big over the table. A tap picks a card (as a tap on it in the
## hand would) and closes the hand; a held finger shows the card bigger; off its turn a tap
## only shows the card.
func _open_hand() -> void:
	var hand: Array = game.players[viewer].hand
	if hand.is_empty():
		return
	_clear_picker()
	picker_title.text = "Рука: %d" % hand.size()
	var n := hand.size()
	var gw := 1050.0
	var close := WoodUI.button_fixed("Закрыть", UI.PURPLE, 24, Vector2(200, 60))
	close.pressed.connect(func(): picker_layer.visible = false)
	picker_buttons.add_child(close)
	var room := _picker_room()
	var item := Vector2.ZERO
	for h in range(238, P_HAND_CARD_MIN - 1, -8):     # the biggest cards whose rows fit the screen
		var it := Vector2(roundf(h * CardView.SIZE.x / CardView.SIZE.y), h)
		var per_row := maxi(1, int((gw + 18.0) / (it.x + 18.0)))
		if ceili(n / float(per_row)) * (it.y + 18.0) - 18.0 <= room:
			item = it
			break
	# A small screen (a big «Масштаб»): rows would make the cards too small to read.
	var row := item == Vector2.ZERO
	if row:
		var h := clampf(room, 150.0, 238.0)
		item = Vector2(roundf(h * CardView.SIZE.x / CardView.SIZE.y), roundf(h))
	var mine: bool = game.turn_player == viewer and game.phase == "main"
	for c in hand:
		var b := TextureButton.new()
		b.texture_normal = CardView.texture_for(c.id)
		b.material = CardView.SHARP
		b.ignore_texture_size = true
		b.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		b.custom_minimum_size = item
		if mine and not game.can_play(viewer, c.uid):
			b.modulate = Color(0.55, 0.55, 0.55)
		var uid: int = c.uid
		var id: String = c.id
		b.pressed.connect(func():
			if TouchInput.long_pressed:
				return
			if _can_act():
				picker_layer.visible = false
				_select(uid)
			else:
				_close_zoom()
				CardZoom.open(zoom_layer, CardView.texture_for(id)))
		b.gui_input.connect(_zoom_input_on.bind(id))
		picker_grid.add_child(b)
	_fit_picker(n, item)
	if row:
		# One row of big cards that a finger moves sideways (TouchInput scrolls lists).
		picker_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
		picker_grid.custom_minimum_size.x = n * (item.x + 18.0) - 18.0
		picker_scroll.custom_minimum_size = Vector2(gw + 20.0, item.y)
		picker_scroll.scroll_horizontal = 0
	picker_layer.visible = true
	UI.sfx("deal")


## The right button (a held finger) on a card in a list: the card big, over the list.
func _zoom_input_on(e: InputEvent, id: String) -> void:
	if CardZoom.asks(e):
		_close_zoom()
		CardZoom.open(zoom_layer, CardView.texture_for(id))


func _close_zoom() -> void:
	for ch in zoom_layer.get_children():
		ch.queue_free()


func _clear_picker() -> void:
	picker_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	for box in [picker_grid, picker_buttons]:
		for ch in box.get_children():
			box.remove_child(ch)
			ch.queue_free()


## The card area is as tall as its rows, but never taller than the screen has room for:
## then it scrolls (the wheel), from the top.
func _fit_picker(n: int, item: Vector2) -> void:
	# A phone: the window of the picker is in units of a phone's screen (about 1200x540).
	var gw := 1050.0 if _ph else 1300.0
	picker_grid.custom_minimum_size.x = gw
	# The real size of an item: a phone makes buttons taller than they were asked for (WoodUI).
	for ch in picker_grid.get_children():
		if ch is Control:
			item = item.max((ch as Control).get_combined_minimum_size())
	var per_row := maxi(1, int((gw + 18.0) / (item.x + 18.0)))
	var rows := ceili(n / float(per_row))
	var h := rows * (item.y + 18.0) - 18.0
	var room := _picker_room()
	picker_scroll.custom_minimum_size = Vector2(gw + 20.0, minf(h, clampf(room, 180.0 if _ph else 300.0, 780.0)))
	picker_scroll.scroll_vertical = 0


## The height the picker's cards have on the screen: the screen less the title and the buttons
## (as tall as they really are: a phone makes buttons taller).
func _picker_room() -> float:
	var safe := FitCenter.safe_rect(self).size
	if not _ph:
		return safe.y - 260.0
	# A phone's FitCenter makes the window smaller only to fit the width (1050 of cards and the
	# scrollbar): so much more height it has in its own units.
	var k := minf(1.0, safe.x / 1070.0)
	var title := picker_title.get_combined_minimum_size().y if picker_title.text != "" else 0.0
	var buttons := picker_buttons.get_combined_minimum_size().y
	return safe.y / k - title - buttons - 2.0 * 20.0 - 24.0


func _open_picker(req: Dictionary) -> void:
	_clear_picker()
	picker_title.text = req.get("prompt", "Выбери карту")
	if req["kind"] == "option":
		for opt in req["options"]:
			var ob := WoodUI.button_fixed(str(opt), UI.BLUE, 26, Vector2(320, 72))
			var val = opt
			ob.pressed.connect(func(): _resolve_choice(val))
			picker_grid.add_child(ob)
		_fit_picker(req["options"].size(), Vector2(320, 72))
		picker_layer.visible = true
		return
	var big: bool = req["options"].size() <= 10
	for uid in req["options"]:
		var c = game.card(uid)
		var b := TextureButton.new()
		b.texture_normal = CardView.texture_for(c.id)
		b.material = CardView.SHARP
		b.ignore_texture_size = true
		b.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		b.custom_minimum_size = Vector2(220, 308) if big else Vector2(150, 210)
		if _ph:
			b.custom_minimum_size = Vector2(170, 238) if big else Vector2(130, 182)
		b.pivot_offset = b.custom_minimum_size * 0.5
		b.mouse_entered.connect(func(): b.scale = Vector2.ONE * 1.06)
		b.mouse_exited.connect(func(): b.scale = Vector2.ONE)
		b.pressed.connect(func():
			if not TouchInput.long_pressed:
				_resolve_choice(uid))
		b.gui_input.connect(_zoom_input_on.bind(c.id))
		picker_grid.add_child(b)
	if req.get("optional", false):
		var skip := WoodUI.button_fixed("Пропустить", UI.PURPLE, 24, Vector2(200, 60))
		skip.pressed.connect(func(): _resolve_choice(null))
		picker_buttons.add_child(skip)
	_fit_picker(req["options"].size(), (Vector2(170, 238) if big else Vector2(130, 182)) if _ph else (Vector2(220, 308) if big else Vector2(150, 210)))
	picker_layer.visible = true


# ================================================================ decor drawing

func _draw_decor() -> void:
	if game == null:
		return
	var font: Font = UI.DISPLAY_FONT
	if _table_bg != null:
		_table_bg.queue_redraw()
	var sides: Array = game.sides()
	for side in sides:
		for lane in LANES:
			var rot := _card_rot(side, lane)
			_draw_shape(_shape(creature_pos(side, lane), _creature_slot(), rot), Color.WHITE, true, 2.0, _slot_box)
			_draw_shape(_shape(building_pos(side, lane), _building_slot(), rot), Color.WHITE, true, 2.0, _slot_box)
	for spot: Dictionary in tutorial_land_targets:
		var sh := _land_shape(int(spot["p"]), int(spot["lane"]))
		_draw_shape(sh, Color(1.0, 0.84, 0.25, 0.22))
		_draw_shape(sh, Color(1.0, 0.84, 0.25, 0.95), false, 5.0)
	for spot: Dictionary in tutorial_building_targets:
		var side := int(spot["p"])
		var lane := int(spot["lane"])
		var sh := _shape(building_pos(side, lane), _building_slot(), _card_rot(side, lane))
		_draw_shape(sh, Color(1.0, 0.84, 0.25, 0.22))
		_draw_shape(sh, Color(1.0, 0.84, 0.25, 0.95), false, 5.0)
	for sh: Dictionary in tutorial_world_targets:
		_draw_shape(sh, Color(1.0, 0.84, 0.25, 0.2))
		_draw_shape(sh, Color(1.0, 0.84, 0.25, 0.95), false, 5.0)
	# The deck drawn on the mat stays when a player's deck runs out: it goes dark.
	var k := _pile_scale() / S_PILE
	for side in sides:
		if game.players[side].deck.is_empty():
			decor.draw_style_box(_empty_deck_box, Rect2(deck_pos(side) + Vector2(-82, -86) * k, Vector2(148, 204) * k))
	if teams or game.duel():
		# Every landscape has its zone number (the log names zones), under the cards on it.
		# На троих after a player dropped out too: the rows go opposite ways there.
		for side in sides:
			for lane in LANES:
				decor.draw_set_transform(land_pos(side, lane), _land_rot(side, lane))
				decor.draw_string_outline(font, Vector2(-30, 12), str(lane + 1), HORIZONTAL_ALIGNMENT_CENTER, 60, 34, 6,
					Color(0, 0, 0, 0.5))
				decor.draw_string(font, Vector2(-30, 12), str(lane + 1), HORIZONTAL_ALIGNMENT_CENTER, 60, 34,
					Color(1, 1, 1, 0.55))
				decor.draw_set_transform(Vector2.ZERO, 0.0)
	else:
		for lane in LANES:
			decor.draw_string(font, Vector2(LANE_X[lane] - 60, FIELD_CENTER.y + 6), "ЗОНА %d" % (lane + 1),
				HORIZONTAL_ALIGNMENT_CENTER, 120, 15, Color(1, 1, 1, 0.35))
	# Ice tokens.
	var tile := _tile_size()
	for side in sides:
		for lane in LANES:
			if not game.is_frozen(side, lane):
				continue
			var ice := _shape(land_pos(side, lane), tile - Vector2(10, 10), _land_rot(side, lane))
			_draw_shape(ice, Color(0.62, 0.86, 1.0, 0.3))
			_draw_shape(ice, Color(0.85, 0.97, 1.0, 0.85), false, 3.0)
			var corner := Vector2(tile.x * 0.5 - 26 * k, -tile.y * 0.5 + 30 * k)
			var at := land_pos(side, lane) + corner.rotated(_land_rot(side, lane))
			decor.draw_circle(at, 22 * k, Color(0.1, 0.25, 0.45, 0.85))
			_draw_snowflake(at, 15.0 * k, Color(0.85, 0.97, 1.0))
	var pulse := 0.5 + 0.5 * sin(_time * 6.0)
	var mouse := world.get_local_mouse_position()
	if _arranging >= 0:
		for lane in LANES:
			var sh := _land_shape(_arranging, lane)
			var col := Color(1.0, 0.85, 0.35) if lane == _arr_pick else Color(0.35, 0.95, 1.0)
			var hot := _shape_has(sh, mouse)
			_draw_shape(sh, Color(col, (0.12 + 0.1 * pulse) * (2.0 if hot or lane == _arr_pick else 1.0)))
			_draw_shape(sh, Color(col, 0.6 + 0.4 * pulse), false, 4.0 if lane == _arr_pick else 2.5)
	for t in _drop_targets:
		var sh: Dictionary = t["shape"]
		var col := Color(1.0, 0.35, 0.3) if t["replace"] else Color(1.0, 0.92, 0.5)
		if t.get("spell", false):
			col = Color(0.75, 0.55, 1.0)
		var hot := _shape_has(sh, mouse, 18.0)
		_draw_shape(sh, Color(col, (0.18 + 0.12 * pulse) * (1.8 if hot else 1.0)))
		_draw_shape(sh, Color(col, 0.6 + 0.4 * pulse), false, 4.0 if hot else 2.5)
		if t["replace"] and hot:
			var top: Vector2 = sh["c"] - Vector2(60, sh["s"].y * 0.5 + 8)
			decor.draw_string(font, top, "ЗАМЕНИТЬ", HORIZONTAL_ALIGNMENT_CENTER, 120, 18, col)
	if _choice != null:
		var cyan := Color(0.35, 0.95, 1.0)
		match _choice["kind"]:
			"land":
				for opt in _choice["options"]:
					var sh := _land_shape(opt["p"], opt["lane"])
					_draw_shape(sh, Color(cyan, 0.15 + 0.15 * pulse))
					_draw_shape(sh, Color(cyan, 0.6 + 0.4 * pulse), false, 4.0)
			"lane":
				for opt in _choice["options"]:
					var sh := _choice_lane_shape(opt)
					_draw_shape(sh, Color(cyan, 0.2 + 0.15 * pulse))
					_draw_shape(sh, Color(cyan, 0.6 + 0.4 * pulse), false, 4.0)


func _draw_snowflake(at: Vector2, r: float, col: Color) -> void:
	for i in 3:
		var dir := Vector2.RIGHT.rotated(PI / 3.0 * i + PI / 6.0)
		decor.draw_line(at - dir * r, at + dir * r, col, 3.0, true)
		for s in [-1.0, 1.0]:
			var tip: Vector2 = at + dir * r * 0.62 * s
			var n := dir.orthogonal() * r * 0.3
			decor.draw_line(tip, tip + dir * r * 0.3 * s + n, col, 2.0, true)
			decor.draw_line(tip, tip + dir * r * 0.3 * s - n, col, 2.0, true)


# ================================================================ animator

## Speeds of the moves: below 1 the table slows down (time to follow the AI).
const SPEEDS := [0.25, 0.5, 1.0, 2.0, 4.0]
## A live replay this many steps behind the match plays them without the pauses between steps.
const LIVE_BEHIND := 6


static func next_speed(k: float) -> float:
	var i := SPEEDS.find(k)
	return SPEEDS[(i + 1) % SPEEDS.size()] if i >= 0 else 1.0


static func speed_text(k: float) -> String:
	return "×" + (str(int(k)) if k >= 1.0 else str(k).replace(".", ","))


func _speed() -> float:
	var k := ai_speed if _watching() else turn_speed
	return (3.0 if Input.is_key_pressed(KEY_SPACE) else 1.0) * k


func _wait(t: float) -> void:
	await get_tree().create_timer(t / _speed()).timeout


func shake_screen(amount: float) -> void:
	_shake = maxf(_shake, amount)


func play(ev: Dictionary) -> void:
	if tutorial != null:
		tutorial.on_game_event(ev)
	var v = views.get(ev.get("uid", -1))
	match ev["type"]:
		"log":
			_add_log(ev["text"])
			return
		"actions":
			_update_hud()
			if ev.has("gain"):
				UI.float_text(hud, Vector2(HUD_X + _side + 135, 400), "+%d действие" % ev["gain"], UI.ORANGE, 30, 50)
				UI.sfx("chip")
				await _wait(0.3)
			return
		"phase":
			_update_hud()
			return
		"draw":
			sync()
			UI.sfx("draw")
			await _wait(0.17)
		"draw_fail":
			UI.float_text(world, deck_pos(ev["p"]), "Колода пуста", UI.CREAM, 26, 50)
			await _wait(0.4)
		"mulligan":
			sync()
			UI.sfx("shuffle")
			await _wait(0.45)
		"turn_start":
			hero_turn.emit(game.players[ev["p"]].hero)
			sync()
			var banner_text: String = "ХОДИТ %s" % game.players[ev["p"]].name.to_upper()
			if (net != null or (seated and humans.size() == 1)) and ev["p"] == local_player:
				banner_text = "ТВОЙ ХОД!"
			_show_banner(banner_text, UI.hero_color(game.players[ev["p"]].hero))
			if not _opened:
				# The fight begins: its tune, and the hero who starts greets the table.
				_opened = true
				UI.sfx("intro")
				get_tree().create_timer(1.0).timeout.connect(func():
					if is_inside_tree():
						_say(ev["p"], "opening"))
			else:
				var me := my_seat()
				UI.sfx("enemy_turn" if me >= 0 and ev["p"] != me and \
					(not game.teams() or game.team(ev["p"]) != game.team(me)) else "turn")
			await _wait(0.55)
		"ready":
			sync()
			if v != null:
				v.pop(0.08)
			await _wait(0.07)
		"play":
			_limbo.erase(ev["uid"])
			sync()
			v = views.get(ev["uid"])
			if v != null:
				v.pop(0.28)
				UI.burst(world, v.target_pos + Vector2(0, 80), Color(0.85, 0.75, 0.55), 18, 260.0, 7.0)
			UI.sfx("place")
			shake_screen(0.22)
			_say(ev["p"], "building" if ev.get("kind", "") == "building" else "creature", 0.35)
			await _wait(0.34)
		"leave":
			if v != null and ev["reason"] == "destroy":
				v.flash(Color(1.0, 0.2, 0.15), 0.9)
				v.shake(1.4)
				UI.burst(world, v.position, Color(0.95, 0.3, 0.25), 36, 520.0, 10.0)
				UI.sfx("death")
				shake_screen(0.35)
				# The side whose turn it is laughs, or the one who lost the card grumbles.
				var killer: int = game.turn_player
				if killer == ev["p"] or not _say(killer, "kill", 0.45):
					_say(ev["p"], "lost", 0.35)
				await _wait(0.32)
			elif v != null and ev["reason"] == "bounce":
				UI.float_text(world, v.position, "В руку!", UI.CREAM, 32)
				await _wait(0.2)
			sync()
			UI.sfx("card")
			await _wait(0.26)
		"damage":
			var amount: int = ev["amount"]
			if v != null and amount > 0:
				v.flash(Color(1.0, 0.25, 0.2), 0.75)
				v.shake(0.5 + amount * 0.12)
				UI.float_text(world, v.position + Vector2(randf_range(-20, 20), -60), "−%d" % amount, Color(1.0, 0.35, 0.3), 54 + amount * 3)
				UI.burst(world, v.position, Color(1.0, 0.55, 0.3), 10 + amount * 3, 360.0, 7.0)
				UI.sfx("hit")
			sync()
			await _wait(0.24 if amount > 0 else 0.05)
		"player_damage":
			var amount: int = ev["amount"]
			var pos := hero_anchor(ev["p"])
			UI.float_text(hud, pos + Vector2(180, -20), "−%d" % amount, Color(1.0, 0.3, 0.25), 76 + mini(amount, 10) * 3, 110.0, 1.1)
			UI.burst(hud, pos, Color(1.0, 0.3, 0.25), 20 + amount * 3, 520.0, 10.0)
			var ui: Dictionary = hero_ui[_panel_key(ev["p"])]
			_shake_panel(ui["panel"])
			shake_screen(0.25 + amount * 0.05)
			UI.sfx("big_hit" if amount >= 4 else "hit")
			if amount >= 2:
				_say(ev["p"], "hurt", 0.4 if amount < 4 else 0.7)
			_update_hud()
			await _wait(0.5)
		"attack":
			if v != null:
				var home: Vector2 = v.target_pos
				var to: Vector2 = hero_anchor(game.across(ev["p"], ev["lane"])[0])
				if ev["target"] == "creature" and views.has(ev["target_uid"]):
					to = views[ev["target_uid"]].position
				v.z_index = 120
				v.follow_speed = 24.0
				v.lift = 1.0
				v.target_pos = home + (home - to).normalized() * 30.0
				await _wait(0.12)
				v.target_pos = home.lerp(to, 0.68)
				UI.sfx("attack")
				await _wait(0.11)
				shake_screen(0.2)
				v.target_pos = home
				v.follow_speed = 14.0
				await _wait(0.08)
		"floop":
			sync()
			if v != null:
				v.pop(0.22)
				v.flash(Color(0.45, 1.0, 0.5), 0.6)
				UI.float_text(world, v.position + Vector2(0, -70), "ФЛЮП!", Color(0.5, 1.0, 0.55), 46)
				UI.burst(world, v.position, Color(0.4, 1.0, 0.5), 22, 380.0, 7.0)
			UI.sfx("floop")
			_say(ev["p"], "floop", 0.35)
			await _wait(0.5)
		"activate":
			if v != null:
				v.pop(0.2)
				v.flash(Color(0.5, 0.75, 1.0), 0.5)
				UI.float_text(world, v.position + Vector2(0, -70), "Способность!", Color(0.6, 0.85, 1.0), 40)
			UI.sfx("buff")
			await _wait(0.4)
		"move", "move_building":
			sync()
			UI.sfx("card")
			await _wait(0.34)
		"flip_land":
			_flip_land_anim(ev["p"], ev["lane"])
			UI.sfx("flip")
			await _wait(0.42)
		"buff":
			if v != null and ev.get("crit", false):
				UI.float_text(world, v.position + Vector2(0, -80), ev["text"], UI.ORANGE, 52, 110.0, 1.1)
				UI.burst(world, v.position, UI.ORANGE, 30, 480.0, 9.0)
				v.pop(0.3)
				shake_screen(0.3)
				UI.sfx("big_hit")
				sync()
				await _wait(0.45)
				return
			if v != null:
				var good: bool = ev.get("good", true)
				UI.float_text(world, v.position + Vector2(0, -60), ev["text"], Color(0.55, 1.0, 0.5) if good else Color(1.0, 0.5, 0.35), 34)
				v.pop(0.15)
			UI.sfx("power_up" if ev.get("good", true) else "debuff")
			sync()
			await _wait(0.38)
		"spell":
			if not _limbo.has(ev["uid"]):
				_limbo.append(ev["uid"])
			sync()
			v = views.get(ev["uid"])
			if v != null:
				v.pop(0.3)
				v.flash(Color(1, 1, 1), 0.5)
			UI.burst(world, _center(), Color(0.85, 0.6, 1.0), 40, 600.0, 8.0)
			UI.sfx("spell")
			_say(ev["p"], "spell", 0.45)
			await _wait(0.85)
		"steal":
			if not _limbo.has(ev["uid"]):
				_limbo.append(ev["uid"])
			sync()
			UI.float_text(world, _center() + Vector2(0, -150), "Украдено!", UI.ORANGE, 48)
			UI.sfx("spell")
			await _wait(0.8)
		"to_discard", "to_hand", "to_deck", "removed":
			_limbo.erase(ev["uid"])
			sync()
			UI.sfx("card")
			await _wait(0.22)
		"heal":
			var amount: int = ev["amount"]
			if v != null and amount > 0:
				v.flash(Color(0.45, 1.0, 0.55), 0.6)
				UI.float_text(world, v.position + Vector2(0, -60), "+%d" % amount, Color(0.5, 1.0, 0.55), 48)
				UI.sfx("heal")
			sync()
			await _wait(0.22 if amount > 0 else 0.05)
		"player_heal":
			var pos := hero_anchor(ev["p"])
			UI.float_text(hud, pos + Vector2(180, -20), "+%d" % ev["amount"], Color(0.5, 1.0, 0.55), 70, 90.0, 1.0)
			UI.burst(hud, pos, Color(0.5, 1.0, 0.55), 18, 380.0, 8.0)
			UI.sfx("heal")
			_update_hud()
			await _wait(0.4)
		"freeze":
			var lpos := land_pos(ev["p"], ev["lane"])
			if ev["frozen"]:
				UI.burst(world, lpos, Color(0.7, 0.92, 1.0), 30, 320.0, 8.0)
				UI.float_text(world, lpos, "Заморожено!", Color(0.7, 0.92, 1.0), 34)
			else:
				UI.burst(world, lpos, Color(0.55, 0.75, 1.0), 14, 260.0, 6.0)
				UI.float_text(world, lpos, "Оттаяло", Color(0.75, 0.9, 1.0), 30)
			UI.sfx("flip")
			sync()
			await _wait(0.35)
		"land", "lands":
			_update_lands()
			decor.queue_redraw()
			UI.sfx("land")
			await _wait(0.2)
		"hero_text":
			var tpos := hero_anchor(ev["p"])
			UI.float_text(hud, tpos + Vector2(0, -40), ev["text"], Color(0.55, 1.0, 0.5) if ev.get("good", true) else UI.ORANGE, 40, 80.0, 1.0)
			UI.burst(hud, tpos, Color(0.85, 0.95, 1.0), 16, 320.0, 7.0)
			UI.sfx("buff")
			await _wait(0.4)
		"hero_power":
			var hpos := hero_anchor(ev["p"])
			UI.burst(hud, hpos, Color(0.8, 0.6, 1.0), 22, 360.0, 8.0)
			UI.float_text(hud, hpos + Vector2(0, -40), "Способность героя!", Color(0.85, 0.7, 1.0), 34, 70.0, 1.0)
			UI.sfx("hero_power")
			await _wait(0.35)
		"peek":
			if ev["p"] == viewer and not _watching() and not _is_ai_seat(ev["p"]):
				var ids := []
				for uid in ev["uids"]:
					ids.append(game.card(uid).id)
				_show_cards("Верх твоей колоды", ids)
			await _wait(0.3)
		"reveal":
			var uids: Array = ev["uids"]
			if uids.size() > 4:
				if ev["p"] != viewer:
					var ids := []
					for uid in uids:
						ids.append(game.card(uid).id)
					_show_cards("Открытые карты: %s" % game.players[ev["p"]].name, ids)
				await _wait(0.4)
			elif not uids.is_empty():
				# A few cards: they fly out by the lanes face up, for both players to see.
				_revealed = uids.duplicate()
				_revealed_zone.clear()
				for uid in uids:
					_revealed_zone[uid] = game.where(uid).get("zone", "")
				sync()
				for uid in _revealed:
					var rv = views.get(uid)
					if rv != null:
						rv.pop(0.3)
						rv.shake(1.0)
						rv.flash(Color(1, 1, 1), 0.5)
				UI.float_text(world, _reveal_pos(0) + Vector2(0, -190), "Открыта: %s" % game.players[ev["p"]].name if uids.size() == 1 else "Открыты: %s" % game.players[ev["p"]].name, UI.CREAM, 32)
				UI.sfx("deal")
				_reveal_batch += 1
				_keep_revealed(_reveal_batch)
				await _wait(0.9)
		"next_enemy":
			# The first enemy of a double wagon is beaten: its cards go, the second takes the seat.
			for uid in ev.get("gone", []):
				var gone_view = views.get(uid)
				if gone_view != null:
					views.erase(uid)
					if gone_view == _hover_view:
						_hover_view = null
					var fade: Tween = gone_view.create_tween()
					fade.tween_property(gone_view, "modulate:a", 0.0, 0.35)
					fade.tween_callback(gone_view.queue_free)
			for key in hero_ui:
				hero_ui[key]["side"] = -1
			_limbo.clear()
			_revealed = []
			sync()
			_show_banner("ВРАГ ПОБЕЖДЁН!", Color(1.0, 0.86, 0.35))
			UI.sfx("win")
			await _wait(0.8)
			if enemy_intro.is_valid():
				await enemy_intro.call(ev)
		"out":
			# На троих: the player at 0 HP drops out, the other two go on 1 на 1 on the playmat.
			sync()
			_show_banner("%s ВЫБЫВАЕТ" % game.players[ev["p"]].name.to_upper(), UI.hero_color(game.players[ev["p"]].hero))
			UI.sfx("death")
			await _wait(1.0)
			_fit_table()
			sync()
			_show_banner("ДАЛЬШЕ 1 НА 1", Color(1.0, 0.86, 0.35))
			await _wait(0.8)
		"game_over":
			_limbo.clear()
			_revealed = []
			sync()
			var winner: int = ev["winner"]
			var me := my_seat()
			var won: bool = me < 0 or (game.team(me) == winner if game.teams() else me == winner)
			UI.sfx("win" if won else "lose")
			_end_words(winner)
			if sandbox != null:
				# «Песочница» goes on: a step back or new hit points bring the game back.
				var who: String = game.side_name(winner) if game.teams() else game.players[winner].name
				_show_banner("ПОБЕДА: %s" % who.to_upper(), UI.hero_color(game.players[winner].hero))
				flash_note("Игра окончена. Шаг назад вернёт её")
			else:
				game_finished.emit(winner)
	_update_hud()


func _flip_land_anim(side: int, lane: int) -> void:
	var s: Sprite2D = land_sprites[side][lane]
	var base := Vector2.ONE * _tile_scale()
	var tw := s.create_tween()
	tw.tween_property(s, "scale:x", 0.0, 0.16).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_callback(_update_lands)
	tw.tween_property(s, "scale:x", base.x, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	UI.burst(world, s.position, Color(0.8, 0.8, 0.7), 16, 300.0, 6.0)


func _shake_panel(panel: Control) -> void:
	var base := panel.position
	var tw := panel.create_tween()
	for i in 6:
		tw.tween_property(panel, "position", base + Vector2(randf_range(-12, 12), randf_range(-8, 8)), 0.04)
	tw.tween_property(panel, "position", base, 0.05)
	var flash := panel.create_tween()
	flash.tween_property(panel, "modulate", Color(1.6, 0.6, 0.6), 0.06)
	flash.tween_property(panel, "modulate", Color.WHITE, 0.3)


func _show_banner(text: String, color: Color) -> void:
	banner.text = text
	banner.label_settings.font_color = color
	var tw := banner.create_tween()
	banner.scale = Vector2(0.6, 0.6)
	banner.modulate.a = 0.0
	tw.set_parallel()
	tw.tween_property(banner, "modulate:a", 1.0, 0.15)
	tw.tween_property(banner, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.chain().tween_interval(0.45)
	tw.chain().tween_property(banner, "modulate:a", 0.0, 0.3)
