extends Control
## Screen flow: title → hero selection → coin toss → land arrangement →
## mulligans → turns → victory. Modes: hot-seat on one PC (with a curtain
## between turns), against the PPO AI, AI against AI, or online through the
## Net autoload (each player on their own PC). Owns the swirling backdrop and
## all full-screen overlays; the table itself lives in board.gd.

signal _remote_mull_received
signal _remote_lands_received
signal _remote_hero_received
signal _tl_setup_msg

const Game = preload("res://scripts/core/game.gd")
const Board = preload("res://scripts/ui/board.gd")
const BasicTutorial = preload("res://scripts/ui/basic_tutorial.gd")
const AdvancedTutorial = preload("res://scripts/ui/advanced_tutorial.gd")
const TutorialText = preload("res://scripts/ui/tutorial_text.gd")
const CardView = preload("res://scripts/ui/card_view.gd")
const CardBacks = preload("res://scripts/ui/card_backs.gd")
const KeyNavScript = preload("res://scripts/ui/key_nav.gd")
const GamepadScript = preload("res://scripts/ui/gamepad.gd")
const CardDB = preload("res://scripts/core/card_db.gd")
const BugReport = preload("res://scripts/net/bug_report.gd")
const BugReportDialog = preload("res://scripts/ui/bug_report_dialog.gd")
const UI = preload("res://scripts/ui/ui_kit.gd")
const CustomDecks = preload("res://scripts/core/custom_decks.gd")
const DeckBuilder = preload("res://scripts/ui/deck_builder.gd")
const DeckTiles = preload("res://scripts/ui/deck_tiles.gd")
const WoodUI = preload("res://scripts/ui/wood_ui.gd")
const Replay = preload("res://scripts/core/replay.gd")
const FileDialogs = preload("res://scripts/ui/file_dialogs.gd")
const Updater = preload("res://scripts/net/updater.gd")
const AILevels = preload("res://scripts/ai/ai_levels.gd")
const Backdrop = preload("res://scripts/ui/backdrop.gd")
const TrainRun = preload("res://scripts/train/train_run.gd")
const RunScreen = preload("res://scripts/ui/run_screen.gd")
const DailyBoard = preload("res://scripts/net/daily_board.gd")
const DailyScreen = preload("res://scripts/ui/daily_screen.gd")
const Account = preload("res://scripts/net/account.gd")
const AvatarView = preload("res://scripts/ui/avatar_view.gd")
const NickStyle = preload("res://scripts/ui/nick_style.gd")
const LoginScreen = preload("res://scripts/ui/login_screen.gd")
const ProfileScreen = preload("res://scripts/ui/profile_screen.gd")
const TouchInput = preload("res://scripts/ui/touch_input.gd")
const FitCenter = preload("res://scripts/ui/fit_center.gd")
const Phone = preload("res://scripts/ui/phone.gd")
const HeroSelect = preload("res://scripts/ui/main/hero_select.gd")
const TrainMenu = preload("res://scripts/ui/main/train_menu.gd")
const Lobby = preload("res://scripts/ui/main/lobby.gd")
const Watch = preload("res://scripts/ui/main/watch.gd")
const Ranked = preload("res://scripts/ui/main/ranked.gd")
const SandboxStart = preload("res://scripts/ui/main/sandbox_start.gd")
const Social = preload("res://scripts/net/social.gd")
const SocialPanel = preload("res://scripts/ui/social_panel.gd")
const RUN_COLOR := Color(0.86, 0.32, 0.62)
const MODE_NAMES := {"hotseat": "на одном устройстве", "ai": "против ИИ", "aivsai": "ИИ против ИИ", "net": "по сети",
	"teams": "2 на 2", "teams_net": "2 на 2 по сети", "three": "на троих", "three_net": "на троих по сети"}
const SETTINGS_PATH := "user://settings.cfg"
## Buttons that close a window or go back a screen: Escape and the phone's Back press them.
const BACK_TEXTS := ["Назад", "Закрыть", "Готово", "Позже", "Понятно", "Хорошо", "Back", "뒤로"]
const GAME_VERSION := "альфа 0.3.3"
## Build number of this version: the updater offers builds with a bigger one.
## Raise it with GAME_VERSION, then tools/publish.ps1 hands the new version out.
const GAME_BUILD := 64
const DISCORD_LINK := "https://discord.gg/hDNwrYtvy"
const TIMER_STEPS := [30, 45, 60, 90, 120, 180, 300]   # seconds per turn the room creator can pick
## Interface scale steps in the settings: windows and texts grow, the table shrinks back to fit the screen.
const ZOOMS := [1.0, 1.15, 1.3, 1.5]
const SLOT_COLORS := [Color(0.35, 0.75, 1.0), Color(1.0, 0.62, 0.25), Color(0.4, 0.95, 0.75), Color(1.0, 0.4, 0.45)]
const TEAMS_SLOTS := ["Ты", "Соперник 1", "Напарник", "Соперник 2"]   # 2 на 2 seats: 0 and 2 against 1 and 3
const THREE_SLOTS := ["Ты", "Соперник 1", "Соперник 2"]
# Hero selection: the seats column, the hero card in the grid, the grid margin, the text panel.
const SEAT_W := 460
const HERO_TILE := Vector2(112, 154)
const PAGE_MARGIN := 10
const INFO_H := 176
const NOTE_MIN_FONT := 18      # the note's text never takes a smaller font than this (with «Шрифт»)

var backdrop: Control
var _music_now := "-"              # the music playing (Sfx.MUSIC id, "" none): _update_music
var _music_hold := false           # a game is over: its music fades for the end tune
var _music_hold_until := 0.0       # ticks (ms) when the menu music comes back under the results
const END_QUIET_MS := 4000         # the end tune plays alone this long
var _battle_track := ""            # the fight music of the board on the table ("" = not picked yet)
## The fight music of a hero (deck or hero card): its own theme, or one of a hero like it.
const THEME_OF := {"finn": "finn", "fionna": "finn", "fern": "finn", "flame_princess": "finn",
	"baby_finn_and_jake": "finn", "jake": "jake", "jake_2x2": "jake", "cake": "jake", "rainicorn": "jake",
	"bmo": "bmo", "neptr": "bmo", "pb": "pb", "peppermint_butler": "pb", "cinnamon_bun": "pb",
	"tree_trunks": "pb", "marceline": "marceline", "lich": "marceline", "vampire_king": "marceline",
	"death": "marceline", "ice_king": "ice_king", "gunter": "ice_king", "ice_queen": "ice_king",
	"simon_petrikov": "ice_king", "lemongrab": "lemongrab", "magic_man": "lemongrab", "lsp": "lsp",
	"prismo": "lsp", "cosmic_owl": "lsp"}
const THEMES := ["finn", "jake", "bmo", "pb", "marceline", "ice_king", "lemongrab", "lsp"]
var stage: Control
var overlay: CanvasLayer
var menu_layer: CanvasLayer        # the main menu, over the stage and under the windows
var board = null
var _folder_warned := false     # the warning about a folder the game cannot update in, once a launch
var game = null
var title_root: Control = null
var net: Node
var _overlay_open := false
var ui_zoom := 1.0
## A phone: everything twice as big (Phone.SCALE), the table cut to its middle (board.gd).
## Tests set it before the scene enters the tree.
var phone_layout := OS.has_feature("mobile"):
	set(v):
		phone_layout = v
		Phone.active = v
var _warming := []              # paths _warm_up is reading
var _warm_kept := []            # what it has read: kept, so a load() of it is instant
var _hero_pics := {}            # path -> full hero card picture read while heroes are picked (null while reading)
const HERO_PICS_KEPT := 6
var _pause_root: Control = null
var _last_heroes: Array = ["finn", "jake"]    # picks: "deck" or "deck@hero card"
var _mode := ""                      # the game on the table: "hotseat" | "ai" | "aivsai" | "net" | "run"
var run = null                       # «Бесконечный поезд»: the run going on (train_run.gd)
var run_screen: Control = null
var _items_root: Control = null      # Tab in a fight of the run: the items over the table
var _replay = null                   # the replay being watched (its data), else null
var _replay_marks: Array = []        # where its turns begin (Replay.turn_marks), read once
var _replay_end_root: Control = null
var _replay_kept = null              # the game whose replay is already among the saved ones
var updater: Node
var account: Account                 # the player's account on the room server (a guest while not logged in)
var social: Social                   # players online, friends, chat (scripts/net/social.gd)
var social_ui: SocialPanel           # its panel on the right, on a layer over the windows
var _pill_shown := true
var _remote_nick := ""               # the other player of an online match for two
var _play_root: Control = null      # the «Играть» menu while it is open
var _account_chip: Control = null    # the avatar and the nick (or «Войти») in the corner of the title
var _update_info := {}               # a newer version on the server, not offered yet

# AI modes.
var ai_mode := false
var _ai_vs_ai_mode := false
var _ai_random := [false, false]     # re-roll these seats on "next game"
var _ai_series := [0, 0]             # AI-vs-AI wins per seat since the heroes were chosen
var _ai_levels := [AILevels.DEFAULT, AILevels.DEFAULT]   # per seat (vs AI: seat 1), ai_levels.gd ids
# 2 на 2 at this PC: the picks of the four seats, which of them the AI plays and at what level.
var _teams_heroes: Array = ["finn", "jake", "bmo", "marceline"]
var _teams_ai := [false, true, true, true]
var _teams_levels := [AILevels.DEFAULT, AILevels.DEFAULT, AILevels.DEFAULT, AILevels.DEFAULT]
var _teams_random := [false, false, false, false]
# На троих at this PC: the same for three seats.
var _three_heroes: Array = ["finn", "jake", "bmo"]
var _three_ai := [false, true, true]
var _three_levels := [AILevels.DEFAULT, AILevels.DEFAULT, AILevels.DEFAULT]
var _three_random := [false, false, false]
# 2 на 2 online (see the section «2 на 2 по сети»).
var _tl := {}                        # the room's lobby: places, heroes, nicks, ai_heroes, levels
var _tl_box: VBoxContainer = null    # the seats in the lobby screen
var _tl_start: Button = null         # host: «Начать игру»
var _tl_notice: Control = null       # host: a guest is away
var _tl_setup := {}                  # the setup steps got from every seat: {"lands": {seat: types}, "mull": {seat: bool}}

# Online state.
var online := false
var seat := -1                       # this PC's seat (host 0, guest 1)
var my_hero := "finn"
var _remote_hero := ""
var _remote_mull = null
var _remote_lands = null
var _setup_wait: Control = null      # «Ждём соперника…» while the other side sets up: gone with the game
var _rematch_local := false
var _rematch_remote := false
var _deck_changed := {"me": false, "foe": false}   # a deck changed for the rematch
var _lobby_root: Control = null
var _lobby_status: Label = null
var _lobby_hero_box: Control = null
var _lobby_mode := "room"           # "room" (room server) or "lan" (by IP)
var _lobby_code: Label = null       # room mode: the code of the room we created
var _game_over_root: Control = null
var _rematch_button: Button = null
var _rematch_note: Label = null
var _link_root: Control = null      # "connection lost" overlay while a match waits for the link
var _link_label: Label = null
var _rejoin_running := false        # guest: a rejoin loop is going
var _rejoin_token := 0              # bumped to stop a rejoin loop
var _link_attempt := 0

# The parts of this screen in their own files (scripts/ui/main/): their functions, this state.
var hero_select := HeroSelect.new(self)
var train_menu := TrainMenu.new(self)
var lobby := Lobby.new(self)
var watch := Watch.new(self)
var ranked := Ranked.new(self)
var sandbox_start := SandboxStart.new(self)


## The version as players see it: in the menu, in bug reports and in saved games.
static func version_text() -> String:
	return "%s, билд %d" % [GAME_VERSION, GAME_BUILD]


## KeyNav stands over the whole window like an autoload. It is made here and not in
## project.godot, so the keyboard comes with a patch and not with a new app.
func _install_key_nav() -> void:
	var root := get_tree().root
	if root.get_node_or_null("KeyNav") != null:
		return
	var kn := KeyNavScript.new()
	kn.name = "KeyNav"
	root.add_child.call_deferred(kn)
	# The gamepad turns its buttons into the keys of KeyNav (gamepad.gd).
	var pad := GamepadScript.new()
	pad.name = "Gamepad"
	root.add_child.call_deferred(pad)


func _ready() -> void:
	UI.add_font_fallback()
	BugReport.install()
	_install_key_nav()
	CardDB.ensure_loaded()
	my_hero = _load_setting("game", "hero", "finn")
	if not CardDB.valid_loadout(my_hero):
		my_hero = "finn"
	for i in 2:
		_ai_levels[i] = AILevels.level(str(_load_setting("ai", "level_%d" % i, AILevels.DEFAULT)))["id"]
	for i in 4:
		_teams_levels[i] = AILevels.level(str(_load_setting("teams", "level_%d" % i, AILevels.DEFAULT)))["id"]
		_teams_ai[i] = i != 0 and bool(_load_setting("teams", "ai_%d" % i, true))
		var pick := str(_load_setting("teams", "hero_%d" % i, _teams_heroes[i]))
		if CardDB.valid_loadout(pick):
			_teams_heroes[i] = pick
	for i in 3:
		_three_levels[i] = AILevels.level(str(_load_setting("three", "level_%d" % i, AILevels.DEFAULT)))["id"]
		_three_ai[i] = i != 0 and bool(_load_setting("three", "ai_%d" % i, true))
		var pick := str(_load_setting("three", "hero_%d" % i, _three_heroes[i]))
		if CardDB.valid_loadout(pick):
			_three_heroes[i] = pick
	Board.turn_speed = float(_load_setting("ui", "turn_speed", 1.0))
	if not Board.SPEEDS.has(Board.turn_speed):
		Board.turn_speed = 1.0
	CardView.foil_on = bool(_load_setting("ui", "foil", true))
	CardBacks.pick(str(_load_setting("ui", "card_back", CardBacks.CLASSIC)))
	ui_zoom = float(_load_setting("ui", "zoom", 1.0))
	WoodUI.font_scale = float(_load_setting("ui", "font", 1.0))
	if not WoodUI.FONTS.has(WoodUI.font_scale):
		WoodUI.font_scale = 1.0
	Phone.active = phone_layout
	if not zooms().has(ui_zoom):
		ui_zoom = 1.0
	apply_zoom()
	net = get_node("/root/Net")
	account = Account.new()
	account.setup(net.relay_url)
	account.changed.connect(_refresh_account_chip)
	social = Social.new()
	social.setup(account, net.relay_url, social_status)
	social.best = int(_load_setting("run", "best", 0))
	add_child(social)
	ranked.setup()
	net.connected.connect(_on_net_connected)
	net.disconnected.connect(_on_net_disconnected)
	net.resumed.connect(_on_net_resumed)
	net.message.connect(_on_net_message)
	net.room_ready.connect(_on_room_ready)
	net.tour_changed.connect(func(what: String): lobby._on_tour_changed(what))
	net.seat_joined.connect(_on_seat_joined)
	net.seat_left.connect(_on_seat_left)
	net.watch_ready.connect(watch.on_ready)
	net.spec_head.connect(watch.on_head)
	net.spec_steps.connect(watch.on_steps)
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(TouchInput.new())
	# Separate layer so table pieces with negative z_index still draw above it.
	var bg_layer := CanvasLayer.new()
	bg_layer.layer = -1
	add_child(bg_layer)
	backdrop = Backdrop.new()
	backdrop.pinned = str(_load_setting("ui", "background", ""))
	bg_layer.add_child(backdrop)
	stage = Control.new()
	stage.size = Vector2(1920, 1080)
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(stage)
	menu_layer = CanvasLayer.new()
	menu_layer.layer = 10
	add_child(menu_layer)
	overlay = CanvasLayer.new()
	overlay.layer = 20
	add_child(overlay)
	var social_layer := CanvasLayer.new()
	social_layer.layer = 25
	add_child(social_layer)
	social_ui = SocialPanel.new()
	social_ui.setup(self)
	social_layer.add_child(social_ui)
	get_viewport().size_changed.connect(_layout)
	_layout()
	show_title()
	get_window().files_dropped.connect(func(files: PackedStringArray):
		if not files.is_empty():
			open_file(files[0]))
	_open_launch_file.call_deferred()
	_register_file_types.call_deferred()
	updater = Updater.new()
	updater.build = GAME_BUILD
	add_child(updater)
	updater.update_available.connect(func(info: Dictionary):
		_update_info = info
		_offer_update())
	updater.check.call_deferred()
	account.verify.call_deferred(get_tree())
	_warm_up.call_deferred()


## What the first game and the hero selection need starts reading in background threads
## while the title is up, so the clicks after it do not stop the window: the AI's network,
## the land tiles of the table and the small hero cards (kept for the session, ~100 MB).
func _warm_up() -> void:
	AILevels.warm(_ai_levels[1])
	var paths := []
	for kind in CardDB.land_types():
		for i in range(1, 5):
			for suffix in ["", "_flipped"]:
				paths.append("res://assets/lands/%s_%d%s.png" % [kind, i, suffix])
	for id: String in CardDB.hero_card_ids():
		paths.append(CardDB.hero_thumb(id))
	for path: String in paths:
		if not ResourceLoader.has_cached(path) and ResourceLoader.load_threaded_request(path) == OK:
			_warming.append(path)


## Keeps the pictures _warm_up has read.
func _take_warmed() -> void:
	for path: String in _warming.duplicate():
		if ResourceLoader.load_threaded_get_status(path) != ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			_warming.erase(path)
			var res = ResourceLoader.load_threaded_get(path)
			if _hero_pics.has(path):
				_hero_pics[path] = res
			elif res != null:
				_warm_kept.append(res)


## Starts reading a hero card's full picture while the heroes are picked: the curtains at
## the start of a game show it, and a load() there waited ~30 ms for it. The last few are kept.
func _warm_hero_pic(card: String) -> void:
	var path := CardDB.hero_image(card)
	if _hero_pics.has(path) or ResourceLoader.has_cached(path) or ResourceLoader.load_threaded_request(path) != OK:
		return
	for old: String in _hero_pics.keys():
		if _hero_pics.size() < HERO_PICS_KEPT:
			break
		if _hero_pics[old] != null:
			_hero_pics.erase(old)
	_hero_pics[path] = null
	_warming.append(path)


## «Масштаб» steps: a phone has its own, around its doubled size (Phone.SCALE).
func zooms() -> Array:
	return Phone.ZOOMS if phone_layout else ZOOMS


## The interface scale of the window for «Масштаб» (twice as big on a phone).
func apply_zoom() -> void:
	get_window().content_scale_factor = Phone.content_scale(ui_zoom)
	_layout()


## The table is drawn for 1920x1080; with a big interface scale the screen holds less than that,
## so the table shrinks to fit it whole (it stays the same size on the screen).
func _layout() -> void:
	if stage == null:
		return
	var room := FitCenter.safe_rect(self, 0.0)
	var k := minf(1.0, minf(room.size.x / stage.size.x, room.size.y / stage.size.y))
	stage.scale = Vector2.ONE * k
	stage.position = (room.get_center() - stage.size * k * 0.5).floor()
	_place_title()
	if board != null:
		# A phone gets the field over the whole width (board.gd, phone_layout).
		board.set_side_room(maxf(0.0, (room.size.x / k - stage.size.x) * 0.5), phone_layout)


func _process(_delta: float) -> void:
	_animate_title()
	var pill := board == null and run_screen == null and _open_builder() == null
	if pill and phone_layout:
		# A phone: windows take the whole screen, the corner button would lie on them.
		for w in overlay.get_children():
			if w is CanvasItem and w.visible:
				pill = false
				break
	if pill != _pill_shown:
		_pill_shown = pill
		social_ui.set_pill_visible(pill)
	_update_music()
	if not _warming.is_empty():
		_take_warmed()


## The music for what is on the screen: the menus, the map of the train, a fight (the theme
## of the hero across the table first), none once a game is over (its end tune plays).
## Each is a mix: after its first track the others follow in a random order.
func _update_music() -> void:
	var want := "menu"
	if board != null:
		if not _music_hold:
			want = "fight:" + _battle_music()
		elif Time.get_ticks_msec() < _music_hold_until:
			want = ""
		elif _mode == "run":
			want = "train"
	elif run_screen != null:
		want = "train"
	if want == _music_now:
		return
	var was := _music_now
	_music_now = want
	var sfx := get_node("/root/Sfx")
	# A fight starts with the theme of the hero across the table; the menus and the train
	# with any track (but the one just heard). Then the others take turns in a random order.
	var first := want.trim_prefix("fight:") if want.begins_with("fight:") else ""
	var tracks: Array = THEMES + ["story"]
	if not want.begins_with("fight:"):
		tracks = [want] + tracks
	if want == "":
		# The game is over: its music sinks slowly under the end tune.
		sfx.stop_music(2.5)
	elif board != null and not _music_hold:
		# A fight's music comes in after the tune of its start.
		sfx.play_mix(want, tracks, first, 1.4, 3.0, 2.0)
	elif was == "":
		# After the end tune: the menu music comes back softly, under the results.
		sfx.play_mix(want, tracks, first, 0.0, 4.5)
	else:
		sfx.play_mix(want, tracks, first, 0.0, 3.0, 2.0)


func _battle_music() -> String:
	if _battle_track == "" and game != null and board.game != null:
		var ps = game.players[board.rival_seat()]
		for id: String in [String(ps.hero_card), String(ps.hero)]:
			var base := id.trim_suffix("_classic").trim_suffix("_promo").trim_suffix("_ks1")
			if THEME_OF.has(base):
				_battle_track = THEME_OF[base]
				break
		if _battle_track == "":
			_battle_track = THEMES[absi(hash(str(ps.hero) + str(game.rng_seed))) % THEMES.size()]
	return _battle_track if _battle_track != "" else "menu"


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_F11 and not OS.has_feature("mobile"):
		var w := get_window()
		w.mode = Window.MODE_WINDOWED if w.mode == Window.MODE_FULLSCREEN else Window.MODE_FULLSCREEN
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if _press_back():
			get_viewport().set_input_as_handled()


## The window on top closes, or the screen goes back, by its own button (the last one in the tree).
func _press_back() -> bool:
	var found: Button = null
	for b: Node in find_children("*", "Button", true, false):
		if b is Button and b.is_visible_in_tree() and not b.disabled and BACK_TEXTS.has(b.text):
			found = b
	if found == null:
		return false
	found.pressed.emit()
	return true


# ================================================================ title

func show_title() -> void:
	_close_run_screen()
	_clear_title()
	if net.mode == "":
		social.clear_game()
	_close_overlay(_setup_wait)
	_setup_wait = null
	if board != null:
		board.queue_free()
		board = null
	game = null
	online = false
	ai_mode = false
	_ai_vs_ai_mode = false
	# The menu is on its own layer over the screen (not the fixed 1920x1080 stage): with
	# a bigger interface scale it grows like the windows.
	title_root = Control.new()
	title_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu_layer.add_child(title_root)
	_place_title()

	var column := VBoxContainer.new()
	column.name = "Column"
	column.add_theme_constant_override("separation", 18)
	title_root.add_child(column)
	column.minimum_size_changed.connect(_fit_title_column)
	title_root.resized.connect(_fit_title_column)
	var title := WoodUI.label("КАРТОЧНЫЕ ВОЙНЫ", 64 if phone_layout else 128, WoodUI.GOLD, 16 if phone_layout else 28, null, false)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.name = "Title"
	column.add_child(title)

	# Four big paper buttons on a felt mat: the games open from «Играть».
	var mat := PanelContainer.new()
	mat.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	mat.add_theme_stylebox_override("panel", WoodUI.window(30, 28))
	column.add_child(mat)
	var buttons := VBoxContainer.new()
	buttons.add_theme_constant_override("separation", 14)
	mat.add_child(buttons)
	# A phone: the column fits the screen's height between the corners, at full size.
	var bw := 470.0 if phone_layout else 520.0
	var bh := 62.0 if phone_layout else 76.0
	if phone_layout:
		column.add_theme_constant_override("separation", 6)
		buttons.add_theme_constant_override("separation", 10)
		mat.add_theme_stylebox_override("panel", WoodUI.window(24, 16))
	var play := WoodUI.button("Играть", WoodUI.GO, 40 if phone_layout else 46, Vector2(bw, 74.0 if phone_layout else 100.0))
	play.pressed.connect(show_play_menu)
	buttons.add_child(play)
	var builder := WoodUI.button("Конструктор колод", WoodUI.BLUE, 30, Vector2(bw, bh))
	builder.pressed.connect(func(): show_deck_builder(""))
	buttons.add_child(builder)
	var tutorial := WoodUI.button("Обучение", WoodUI.GOLD, 30, Vector2(bw, bh))
	tutorial.pressed.connect(show_tutorial_menu)
	buttons.add_child(tutorial)
	var tutorial_english := WoodUI.label("Tutorial", 22, Color.WHITE, 4)
	tutorial_english.name = "EnglishLabel"
	tutorial_english.anchor_left = 0.03
	tutorial_english.anchor_right = 0.27
	tutorial_english.anchor_bottom = 1.0
	tutorial_english.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tutorial_english.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tutorial.add_child(tutorial_english)
	var tutorial_korean := WoodUI.label("튜토리얼", 22, Color.WHITE, 4)
	tutorial_korean.name = "KoreanLabel"
	tutorial_korean.label_settings.font = TutorialText.korean_font()
	tutorial_korean.anchor_left = 0.73
	tutorial_korean.anchor_right = 0.97
	tutorial_korean.anchor_bottom = 1.0
	tutorial_korean.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tutorial_korean.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tutorial.add_child(tutorial_korean)
	var settings := WoodUI.button("Настройки", WoodUI.VIOLET, 30, Vector2(bw, bh))
	settings.pressed.connect(show_settings)
	buttons.add_child(settings)
	var quit := WoodUI.button("Выйти", WoodUI.RED, 30, Vector2(bw, bh))
	quit.pressed.connect(func(): get_tree().quit())
	buttons.add_child(quit)

	var version := WoodUI.label(version_text(), 20, Color(UI.CREAM, 0.75), 5, UI.UI_FONT)
	version.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 8)
	version.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	version.grow_vertical = Control.GROW_DIRECTION_BEGIN
	title_root.add_child(version)
	# The bottom left corner: our Discord over the report button.
	var corner := VBoxContainer.new()
	corner.add_theme_constant_override("separation", 10)
	corner.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 8)
	corner.grow_vertical = Control.GROW_DIRECTION_BEGIN
	title_root.add_child(corner)
	var discord := WoodUI.button("Наш Discord", WoodUI.BLUE, 20, Vector2(290, 50))
	discord.pressed.connect(func(): OS.shell_open(DISCORD_LINK))
	corner.add_child(discord)
	var report := WoodUI.button("Сообщить об ошибке", WoodUI.VIOLET, 20, Vector2(290, 50))
	report.pressed.connect(func(): BugReportDialog.open(self, version_text(), "menu", account.nick))
	corner.add_child(report)
	_refresh_account_chip()
	_fit_title_column.call_deferred()
	_offer_update.call_deferred()
	_warn_folder.call_deferred()


## The menu takes the part of the screen nothing hides (the cutout of a phone, the edges).
func _place_title() -> void:
	if title_root == null or not is_instance_valid(title_root):
		return
	var room := FitCenter.safe_rect(title_root, 16.0)
	title_root.position = room.position
	title_root.size = room.size


## The title and the buttons in the middle, between the account in the top corner and the
## report button in the bottom one; scaled down when the screen holds less.
func _fit_title_column() -> void:
	if title_root == null or not is_instance_valid(title_root):
		return
	var column: Control = title_root.get_node_or_null("Column")
	if column == null:
		return
	var band := 84.0 * WoodUI.font_scale
	var area := Rect2(0.0, band, title_root.size.x, title_root.size.y - 2.0 * band)
	if phone_layout:
		# The account, the report button and the players online stay in the corners, at the sides
		# of the column: it takes the whole height between them.
		var side := 230.0 * WoodUI.font_scale
		area = Rect2(side, 0.0, maxf(1.0, title_root.size.x - 2.0 * side), title_root.size.y)
	var need := column.get_combined_minimum_size()
	var k := minf(1.0, minf(area.size.x / maxf(need.x, 1.0), area.size.y / maxf(need.y, 1.0)))
	column.size = need
	column.scale = Vector2.ONE * k
	column.position = (area.get_center() - need * k * 0.5).floor()


## «Играть»: the games, each a card on the felt. Back leads to the main menu.
func show_play_menu() -> void:
	if _overlay_open:
		return
	var root := _overlay_root(Color(0.02, 0.01, 0.05, 0.6))
	_play_root = root
	var center := FitCenter.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_box())
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10 if phone_layout else 18)
	panel.add_child(v)
	var back := WoodUI.button("Назад", WoodUI.BACK, 28, Vector2(220, 62))
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back.pressed.connect(func(): _close_overlay(root))
	if phone_layout:
		v.add_child(_phone_header("Играть", back))
	else:
		v.add_child(_title("Играть"))
	var open := func(what: Callable):
		_close_overlay(root)
		what.call()
	var modes := [
		["Рейтинг", Color(0.85, 0.66, 0.2), ["fionna", "marceline", "lich"], ranked.show_rank],
		["Быстрая игра", Color(0.3, 0.72, 0.5), ["jake", "finn"], ranked.show_quick],
		["Бесконечный поезд", RUN_COLOR, ["@res://assets/run/wagon.png"], open_run],
		["Против ИИ", UI.ORANGE, ["finn", "bmo"], func(): show_hero_select("ai")],
		["На одном устройстве", UI.RED, ["finn", "jake"], func(): show_hero_select("hotseat")],
		["По сети", UI.GREEN, ["marceline", "pb", "lsp"], show_net_lobby],
		["2 на 2", UI.BLUE, ["finn", "jake", "bmo", "marceline"], func(): show_hero_select("teams")],
		["На троих", Color(0.95, 0.55, 0.2), ["finn", "jake", "bmo"], func(): show_hero_select("three")],
		["ИИ против ИИ", Color(0.2, 0.7, 0.65), ["ice_king", "lich"], func(): show_hero_select("aivsai")],
		["Реплеи", UI.PURPLE, ["", "", ""], show_replays],
		["Наблюдать", Color(0.9, 0.72, 0.25), ["ice_king", "gunter"], watch.show_watch],
		["Песочница", Color(0.62, 0.5, 0.85), ["bmo", "prismo"], sandbox_start.show_tables],
	]
	var row: HBoxContainer = null
	for i in modes.size():
		if i == 0 or i == 6:
			row = HBoxContainer.new()
			row.alignment = BoxContainer.ALIGNMENT_CENTER
			row.add_theme_constant_override("separation", 10 if phone_layout else 18)
			v.add_child(row)
		var m: Array = modes[i]
		row.add_child(_mode_tile(m[0], m[1], m[2], open.bind(m[3])))
	if not phone_layout:
		v.add_child(back)
	_pop_in(v)


## «Обучение»: the submenu of the main menu. Back leads to the main menu.
func show_tutorial_menu() -> void:
	if _overlay_open:
		return
	var root := _overlay_root(Color(0.02, 0.01, 0.05, 0.6))
	var center := FitCenter.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_box())
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	panel.add_child(v)
	var back := WoodUI.button("Назад", WoodUI.BACK, 28, Vector2(220, 62))
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back.pressed.connect(func(): _close_overlay(root))
	if phone_layout:
		v.add_child(_phone_header("Обучение", back))
	else:
		v.add_child(_title("Обучение"))
	var button_size := Vector2(340, Phone.TOUCH) if phone_layout else Vector2(440, 70)
	var font_size := 28 if phone_layout else 30
	var basic := WoodUI.button("Базовое обучение", WoodUI.GOLD, font_size, button_size)
	basic.pressed.connect(func():
		_close_overlay(root)
		show_tutorial_language_menu())
	v.add_child(basic)
	var advanced := WoodUI.button("Продвинутое обучение", UI.ORANGE, font_size, button_size)
	advanced.pressed.connect(func():
		_close_overlay(root)
		show_tutorial_language_menu(false, true))
	v.add_child(advanced)
	var trainer := WoodUI.button("Тренажёр", UI.ORANGE, font_size, button_size)
	trainer.disabled = true
	v.add_child(trainer)
	var rules := WoodUI.button("Правила", UI.ORANGE, font_size, button_size)
	rules.pressed.connect(func():
		_close_overlay(root)
		show_tutorial_language_menu(true))
	v.add_child(rules)
	if not phone_layout:
		v.add_child(back)
	_pop_in(v)


func show_tutorial_language_menu(for_rules := false, for_advanced := false) -> void:
	if _overlay_open:
		return
	var root := _overlay_root(Color(0.02, 0.01, 0.05, 0.6))
	var center := FitCenter.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_box())
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	panel.add_child(v)
	var korean_font: Font = TutorialText.korean_font()
	var title := WoodUI.label("Выберите язык / Select language / 언어 선택", 26, UI.CREAM, 4)
	title.label_settings.font = korean_font
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var button_size := Vector2(340, Phone.TOUCH) if phone_layout else Vector2(440, 70)
	for choice: Array in [["Русский", "ru"], ["English", "en"], ["한국어", "ko"]]:
		var button := WoodUI.button(choice[0], WoodUI.GOLD, 28, button_size)
		if choice[1] == "ko":
			button.add_theme_font_override("font", korean_font)
		button.pressed.connect(func():
			_close_overlay(root)
			if for_rules:
				show_rules(choice[1], true)
			elif for_advanced:
				start_advanced_tutorial(choice[1])
			else:
				start_basic_tutorial(choice[1]))
		v.add_child(button)
	var back := WoodUI.button("Назад", WoodUI.BACK, 28, Vector2(220, 62))
	back.pressed.connect(func():
		_close_overlay(root)
		show_tutorial_menu())
	v.add_child(back)
	_pop_in(v)


func start_basic_tutorial(language := "ru") -> void:
	_clear_title()
	if not await _wait_ai([[_ai_levels[1], "jake"]]):
		return
	online = false
	ai_mode = true
	_ai_vs_ai_mode = false
	seat = 0
	_mode = "tutorial"
	game = Game.new()
	game.setup(["finn", "jake"], 0, 1, false)
	if not game.configure_basic_tutorial():
		push_error("Не удалось подготовить фиксированные колоды базового обучения.")
		show_title()
		return
	game.journal = []
	_new_board()
	var tutorial := BasicTutorial.new()
	board.add_child(tutorial)
	board.enable_ai(tutorial, 1, 0)
	tutorial.start(game, board, language)
	board.set_hands_hidden(false)
	await board.run_engine(func(): await game.start_game())


func start_advanced_tutorial(language := "ru", lesson := 0) -> void:
	_clear_title()
	online = false
	ai_mode = true
	_ai_vs_ai_mode = false
	seat = 0
	_mode = "tutorial"
	game = Game.new()
	if not AdvancedTutorial.prepare(game, lesson):
		push_error("Не удалось подготовить продвинутое обучение: урок %d." % lesson)
		show_title()
		return
	_new_board()
	board.enable_ai(null, 1, 0)
	var tutorial := AdvancedTutorial.new()
	board.add_child(tutorial)
	tutorial.start_lesson(game, board, language, lesson)
	board.set_hands_hidden(false)


## The «Играть» menu goes when a game screen opens, from it or from elsewhere.
func _close_play_menu() -> void:
	if _play_root != null and is_instance_valid(_play_root):
		_close_overlay(_play_root)
	_play_root = null


## Back from a screen the «Играть» menu opened: the menu again (not over a game).
func _back_to_play() -> void:
	if board == null and title_root != null and is_instance_valid(title_root):
		show_play_menu()


## A game of the «Играть» menu: a paper card with a fan of hero cards (a picture "@path",
## "" a card back) and the name of the game over a stroke of its colour.
func _mode_tile(text: String, color: Color, cards: Array, on_press: Callable) -> Button:
	var b := Button.new()
	b.custom_minimum_size = (Vector2(172, 196) if phone_layout else Vector2(236, 262)) * WoodUI.font_scale
	b.focus_mode = Control.FOCUS_NONE
	var seed := text.hash() % 61
	for st in ["normal", "hover", "pressed"]:
		var sb := WoodUI.card(WoodUI.PAPER.lightened(0.35) if st == "hover" else WoodUI.PAPER, 0.0, seed)
		sb.radius = 16.0
		if st == "pressed":
			sb.fill = WoodUI.PAPER_DARK
			sb.shadow = Vector2(1, 2)
		b.add_theme_stylebox_override(st, sb)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.mouse_entered.connect(func(): UI.sfx("click"))
	b.pressed.connect(func():
		UI.sfx("press")
		on_press.call())
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 12)
	v.add_theme_constant_override("separation", 4)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(v)
	var pic := Control.new()
	pic.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(pic)
	var fan: Array[Control] = []
	for id: String in cards:
		var r: TextureRect
		if id.begins_with("@") or id == "":
			r = TextureRect.new()
			r.texture = load(id.substr(1)) if id != "" else CardBacks.texture()
			r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		else:
			r = _hero_card_rect(id, Vector2(112, 154))
			r.custom_minimum_size = Vector2.ZERO     # the fan sizes it to the picture (a phone's tile is small)
		pic.add_child(r)
		fan.append(r)
	# The cards fan out from the bottom of the picture; the picture of the train fills it.
	pic.resized.connect(func():
		var n := fan.size()
		for k in n:
			var r: Control = fan[k]
			if cards[k].begins_with("@"):
				r.position = Vector2.ZERO
				r.size = pic.size
				continue
			var h := minf(pic.size.y * 0.92, pic.size.x * 0.56 / 0.727)
			r.size = Vector2(h * 0.727, h)
			var t := 0.0 if n == 1 else (k / float(n - 1)) * 2.0 - 1.0
			r.pivot_offset = Vector2(r.size.x * 0.5, r.size.y)
			r.rotation_degrees = t * (6.0 + 3.0 * n)
			r.position = Vector2(pic.size.x * 0.5 - r.size.x * 0.5 + t * pic.size.x * (0.1 + 0.03 * n), pic.size.y - r.size.y))
	var name_size := 20 if phone_layout else 25
	var name_l := WoodUI.text(text, name_size, WoodUI.INK, true)
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_l.custom_minimum_size = Vector2(0, WoodUI.fs(name_size) * 2.7)
	v.add_child(name_l)
	var line := WoodUI.squiggle(WoodUI.tone(color), 120)
	line.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(line)
	b.set_meta("game", text)
	return b


## Every setting in one window, in two columns: from the main menu and from the pause menu.
func show_settings() -> void:
	if _overlay_open:
		return
	var root := _overlay_root(Color(0.02, 0.01, 0.05, 0.75))
	var center := FitCenter.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_box())
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	panel.add_child(v)
	v.add_child(_title("Настройки"))
	var left: Container
	var right: Container
	var bsize := Vector2(400, 60)
	if phone_layout:
		# A phone: both sliders on one line, the buttons in three columns.
		v.add_theme_constant_override("separation", 10)
		var vols := HBoxContainer.new()
		vols.alignment = BoxContainer.ALIGNMENT_CENTER
		vols.add_theme_constant_override("separation", 24)
		vols.add_child(_volume_row())
		vols.add_child(_volume_row(true))
		v.add_child(vols)
		var grid := GridContainer.new()
		grid.columns = 3
		grid.add_theme_constant_override("h_separation", 12)
		grid.add_theme_constant_override("v_separation", 10)
		v.add_child(grid)
		left = grid
		right = grid
		bsize = Vector2(340, Phone.TOUCH)
	else:
		v.add_child(_volume_row())
		v.add_child(_volume_row(true))
		var cols := HBoxContainer.new()
		cols.add_theme_constant_override("separation", 18)
		v.add_child(cols)
		left = VBoxContainer.new()
		left.add_theme_constant_override("separation", 14)
		cols.add_child(left)
		right = VBoxContainer.new()
		right.add_theme_constant_override("separation", 14)
		cols.add_child(right)
	var sfx := get_node("/root/Sfx")
	var clicks := WoodUI.button("Звук кнопок: " + sfx.button_sound_name(), UI.PURPLE, 24, bsize)
	clicks.pressed.connect(func():
		await get_tree().create_timer(0.12).timeout
		sfx.next_button_sound()
		clicks.text = "Звук кнопок: " + sfx.button_sound_name())
	left.add_child(clicks)
	var sounds := WoodUI.button("Звуки: " + sfx.sound_set_name(), UI.PURPLE, 24, bsize)
	sounds.pressed.connect(func():
		await get_tree().create_timer(0.12).timeout
		sfx.next_sound_set()
		sounds.text = "Звуки: " + sfx.sound_set_name())
	right.add_child(sounds)
	var voices := WoodUI.button(_voices_text(), UI.PURPLE, 24, bsize)
	voices.pressed.connect(func():
		sfx.set_voices(not sfx.voices_on)
		voices.text = _voices_text())
	right.add_child(voices)
	var speed := WoodUI.button("Скорость хода " + Board.speed_text(Board.turn_speed), UI.PURPLE, 24, bsize)
	speed.pressed.connect(func():
		Board.turn_speed = Board.next_speed(Board.turn_speed)
		_save_setting("ui", "turn_speed", Board.turn_speed)
		speed.text = "Скорость хода " + Board.speed_text(Board.turn_speed))
	left.add_child(speed)
	var foil := WoodUI.button(_foil_text(), UI.PURPLE, 24, bsize)
	foil.pressed.connect(func():
		CardView.foil_on = not CardView.foil_on
		_save_setting("ui", "foil", CardView.foil_on)
		foil.text = _foil_text()
		get_tree().call_group("card_views", "refresh_foil"))
	left.add_child(foil)
	var bg := WoodUI.button(_background_text(), UI.PURPLE, 24, bsize)
	bg.pressed.connect(func(): _pick_background(func(): bg.text = _background_text()))
	left.add_child(bg)
	var backs := WoodUI.button("Рубашка карт", UI.PURPLE, 24, bsize)
	backs.pressed.connect(_pick_card_back)
	left.add_child(backs)
	var zoom := WoodUI.button(_zoom_text(), UI.BLUE, 24, bsize)
	zoom.pressed.connect(func():
		ui_zoom = zooms()[(zooms().find(ui_zoom) + 1) % zooms().size()]
		_save_setting("ui", "zoom", ui_zoom)
		apply_zoom()
		zoom.text = _zoom_text())
	right.add_child(zoom)
	var font := WoodUI.button(_font_text(), UI.BLUE, 24, bsize)
	font.pressed.connect(func():
		WoodUI.font_scale = WoodUI.FONTS[(WoodUI.FONTS.find(WoodUI.font_scale) + 1) % WoodUI.FONTS.size()]
		_save_setting("ui", "font", WoodUI.font_scale)
		# The windows are made for one size of letters: this one and the menu are made again.
		root.queue_free()
		_overlay_open = false
		if board == null and title_root != null:
			show_title()
		show_settings())
	right.add_child(font)
	if not OS.has_feature("mobile") and not phone_layout:
		var full := WoodUI.button("Полный экран F11", UI.BLUE, 24, bsize)
		full.pressed.connect(func():
			var w := get_window()
			w.mode = Window.MODE_WINDOWED if w.mode == Window.MODE_FULLSCREEN else Window.MODE_FULLSCREEN)
		right.add_child(full)
	if not OS.has_feature("mobile") and not phone_layout:
		var controls := WoodUI.button("Управление", UI.ORANGE, 24, bsize)
		controls.pressed.connect(show_controls)
		left.add_child(controls)
	# A phone shows it only with a pad plugged in.
	if not phone_layout or get_node("/root/Gamepad").connected():
		var pad_b := WoodUI.button("Геймпад", UI.ORANGE, 24, bsize)
		pad_b.pressed.connect(func():
			_close_overlay(root)
			show_gamepad())
		right.add_child(pad_b)
	var close := WoodUI.button("Готово", UI.GREEN, 28, Vector2(300, 62))
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(func(): _close_overlay(root))
	v.add_child(close)
	_pop_in(v)


## «Геймпад»: the buttons of the pad's actions (a press on one waits for the new button) and
## how far the stick goes before it moves the frame.
func show_gamepad() -> void:
	var pad = get_node("/root/Gamepad")
	var root := _overlay_root(Color(0.02, 0.01, 0.05, 0.8))
	var center := FitCenter.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_box())
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8 if phone_layout else 14)
	panel.add_child(v)
	var close := WoodUI.button("Готово", UI.GREEN, 28, Vector2(260, 60))
	close.pressed.connect(func():
		pad.capture = Callable()
		_close_overlay(root)
		show_settings())
	if phone_layout:
		v.add_child(_phone_header("Геймпад", close))
	else:
		v.add_child(_title("Геймпад"))
	var name_l := WoodUI.label(pad.pad_name if pad.device >= 0 else "Не подключён", 22, UI.CREAM, 6)
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(name_l)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 6 if phone_layout else 8)
	v.add_child(grid)
	var buttons := {}
	var refresh := func():
		for id in buttons:
			buttons[id].text = pad.binds_text(id)
	for a in pad.ACTIONS:
		var id: String = a[0]
		var name_t := WoodUI.text(a[1], 22)
		name_t.custom_minimum_size.x = 230
		name_t.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		name_t.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		grid.add_child(name_t)
		var b := WoodUI.button(pad.binds_text(id), UI.BLUE, 20, Vector2(190, 46))
		buttons[id] = b
		b.pressed.connect(func():
			b.text = "Нажми кнопку"
			pad.capture = func(bind: String):
				if bind != "":
					pad.set_bind(id, bind)
				refresh.call())
		grid.add_child(b)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	v.add_child(row)
	var sense := WoodUI.button("", UI.PURPLE, 22, Vector2(380, 60))
	var sense_text := func(): sense.text = "Чувствительность стика %d из %d" % [pad.sense + 1, pad.DEAD_ZONES.size()]
	sense_text.call()
	sense.pressed.connect(func():
		pad.set_sense((pad.sense + 1) % pad.DEAD_ZONES.size())
		sense_text.call())
	row.add_child(sense)
	var reset := WoodUI.button("Как было", UI.PURPLE, 24, Vector2(220, 60))
	reset.pressed.connect(func():
		pad.reset_binds()
		refresh.call()
		sense_text.call())
	row.add_child(reset)
	if not phone_layout:
		row.add_child(close)
	_pop_in(v)


## «Управление»: what every key does; a press on a key's button waits for the new key
## (with Ctrl, Shift or Alt if they are held), Esc keeps the old one.
func show_controls() -> void:
	var kn = get_node("/root/KeyNav")
	var root := _overlay_root(Color(0.02, 0.01, 0.05, 0.8))
	var center := FitCenter.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_box())
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	panel.add_child(v)
	v.add_child(_title("Управление"))
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 8)
	v.add_child(grid)
	var buttons := {}
	var refresh := func():
		for id in buttons:
			buttons[id].text = kn.keys_text(id)
	for a in kn.ACTIONS:
		var id: String = a[0]
		var name_l := WoodUI.text(a[1], 24)
		name_l.custom_minimum_size.x = 250
		grid.add_child(name_l)
		var b := WoodUI.button(kn.keys_text(id), UI.BLUE, 20, Vector2(250, 48))
		buttons[id] = b
		b.pressed.connect(func():
			b.text = "Нажми клавишу"
			kn.capture = func(k):
				if k != null:
					kn.set_key(id, k)
				refresh.call())
		grid.add_child(b)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	v.add_child(row)
	var reset := WoodUI.button("Как было", UI.PURPLE, 24, Vector2(260, 60))
	reset.pressed.connect(func():
		kn.reset_keys()
		refresh.call())
	row.add_child(reset)
	var close := WoodUI.button("Готово", UI.GREEN, 28, Vector2(260, 60))
	close.pressed.connect(func():
		kn.capture = Callable()
		_close_overlay(root))
	row.add_child(close)
	_pop_in(v)


func _background_text() -> String:
	var i: int = Backdrop.PICTURES.find(backdrop.pinned)
	return "Фон: " + (Backdrop.NAMES[i] if i >= 0 else "по очереди")


## The pictures behind the game: one of them stays, or they come one after another.
func _pick_background(done: Callable) -> void:
	var root := _overlay_root(Color(0.02, 0.01, 0.05, 0.8))
	var center := FitCenter.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_box())
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10 if phone_layout else 16)
	panel.add_child(v)
	var auto := WoodUI.button("По очереди", UI.BLUE if backdrop.pinned != "" else UI.GREEN, 26, Vector2(300, 60))
	var back := WoodUI.button("Назад", UI.PURPLE, 26, Vector2(200, 60))
	back.pressed.connect(func(): _close_overlay(root))
	if phone_layout:
		v.add_child(_phone_header("Фон", back, auto))
	else:
		v.add_child(_title("Фон"))
	var grid := GridContainer.new()
	grid.columns = 5 if phone_layout else 4
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	v.add_child(grid)
	var choose := func(path: String):
		backdrop.set_pinned(path)
		_save_setting("ui", "background", path)
		_close_overlay(root)
		done.call()
	for i in Backdrop.PICTURES.size():
		var path: String = Backdrop.PICTURES[i]
		var cell := VBoxContainer.new()
		cell.add_theme_constant_override("separation", 4)
		grid.add_child(cell)
		var pic := TextureButton.new()
		pic.texture_normal = load(path)
		pic.ignore_texture_size = true
		pic.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_COVERED
		pic.custom_minimum_size = Vector2(196, 110) if phone_layout else Vector2(288, 162)
		pic.pressed.connect(func(): choose.call(path))
		cell.add_child(pic)
		var name_l := WoodUI.label(Backdrop.NAMES[i], 20, Color(1.0, 0.86, 0.35) if backdrop.pinned == path else UI.CREAM, 5, UI.UI_FONT)
		name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cell.add_child(name_l)
	auto.pressed.connect(func(): choose.call(""))
	if not phone_layout:
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 20)
		v.add_child(row)
		row.add_child(auto)
		row.add_child(back)
	_pop_in(v)


## «Рубашка карт»: the backs to pick from, the picked one in a gold frame.
func _pick_card_back() -> void:
	var root := _overlay_root(Color(0.02, 0.01, 0.05, 0.8))
	var center := FitCenter.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_box())
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	panel.add_child(v)
	v.add_child(_title("Рубашка карт"))
	var backs := CardBacks.all()
	var grid := GridContainer.new()
	grid.columns = mini(backs.size(), 6)
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	v.add_child(grid)
	for path: String in backs:
		var frame := PanelContainer.new()
		var picked := path == CardBacks.path
		frame.add_theme_stylebox_override("panel", UI.box(Color.TRANSPARENT, 12, 5,
				Color(1.0, 0.82, 0.25) if picked else Color(0, 0, 0, 0)))
		grid.add_child(frame)
		var pic := TextureButton.new()
		pic.texture_normal = load(path)
		pic.ignore_texture_size = true
		pic.stretch_mode = TextureButton.STRETCH_SCALE
		pic.custom_minimum_size = Vector2(170, 238)
		pic.material = CardView.SHARP
		pic.set_meta("card_back", path)
		pic.pressed.connect(func():
			UI.sfx("press")
			CardBacks.pick(path)
			_save_setting("ui", "card_back", path)
			get_tree().call_group("card_views", "refresh_back")
			if board != null:
				board.refresh_back()
			_close_overlay(root))
		frame.add_child(pic)
	var back := WoodUI.button("Назад", UI.PURPLE, 26, Vector2(200, 60))
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back.pressed.connect(func(): _close_overlay(root))
	v.add_child(back)
	_pop_in(v)


func _voices_text() -> String:
	return "Голоса героев: " + ("вкл" if get_node("/root/Sfx").voices_on else "выкл")


func _zoom_text() -> String:
	return "Масштаб: %d%%" % roundi(ui_zoom * 100.0)


func _font_text() -> String:
	return "Шрифт: %d%%" % roundi(WoodUI.font_scale * 100.0)


func _foil_text() -> String:
	return "Блеск карт: " + ("вкл" if CardView.foil_on else "выкл")


func _animate_title() -> void:
	if title_root == null or not is_instance_valid(title_root):
		return
	var t := Time.get_ticks_msec() / 1000.0
	var title: Label = title_root.find_child("Title", true, false)
	if title != null:
		title.pivot_offset = title.size * 0.5
		title.rotation = sin(t * 1.3) * 0.025
		title.scale = Vector2.ONE * (1.0 + sin(t * 2.1) * 0.02)


func _clear_title() -> void:
	_close_play_menu()
	if title_root != null:
		title_root.queue_free()
		title_root = null


func show_rules(language := "ru", from_tutorial := false) -> void:
	var root := _overlay_root(Color(0.03, 0.02, 0.07, 0.86))
	var center := FitCenter.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_box())
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	panel.add_child(v)
	var title_text := TutorialText.get_text(language, "rules_title", "Правила")
	var title := _title(title_text)
	if language == "ko":
		(title.get_child(0) as Label).label_settings.font = TutorialText.korean_font()
	v.add_child(title)
	# A sheet of paper as big as the screen allows: ink letters read best on it.
	var sheet := PanelContainer.new()
	var sb := WoodUI.paper(WoodUI.PAPER, 0.0, 12)
	sb.content_margin_left = 24
	sb.content_margin_right = 14
	sb.content_margin_top = 14
	sb.content_margin_bottom = 14
	sheet.add_theme_stylebox_override("panel", sb)
	v.add_child(sheet)
	var room := FitCenter.safe_rect(root)
	var text := RichTextLabel.new()
	text.name = "RulesText"
	text.bbcode_enabled = true
	var text_size := Vector2(minf(1150.0, room.size.x - 150.0), maxf(300.0, room.size.y - 250.0 * WoodUI.font_scale))
	text.add_theme_font_override("normal_font", WoodUI.REGULAR)
	text.add_theme_font_override("bold_font", WoodUI.BOLD)
	if language == "ko":
		var korean_font: Font = TutorialText.korean_font()
		text.add_theme_font_override("normal_font", korean_font)
		text.add_theme_font_override("bold_font", korean_font)
	text.add_theme_font_size_override("normal_font_size", WoodUI.fs(22))
	text.add_theme_font_size_override("bold_font_size", WoodUI.fs(23))
	text.add_theme_color_override("default_color", WoodUI.INK)
	text.text = TutorialText.get_text(language, "rules_body", RULES_TEXT).replace("#ffd75a", "#a3501c").replace("#9fe7ff", "#2a6585")
	if OS.has_feature("mobile"):
		if language == "ru":
			text.text = text.text.replace("ПКМ — рассмотреть любую открытую карту. Пробел — ускорить анимации. F11 — полный экран. Esc — меню.",
				"Подержи палец на открытой карте, чтобы рассмотреть её. Кнопка «Назад» — меню.").replace("кликни", "нажми") \
				.replace("Клик по", "Нажатие на")
		else:
			text.text = text.text.replace(TutorialText.TEXT[language]["rules_desktop_controls"],
					TutorialText.TEXT[language]["rules_mobile_controls"])
	if phone_layout:
		var scroll := ScrollContainer.new()
		scroll.name = "RulesScroll"
		scroll.custom_minimum_size = text_size
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		text.fit_content = true
		text.scroll_active = false
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.add_child(text)
		sheet.add_child(scroll)
	else:
		text.custom_minimum_size = text_size
		sheet.add_child(text)
	var back_text := TutorialText.get_text(language, "rules_back", "Назад") if from_tutorial else "Понятно!"
	var back := WoodUI.button(back_text, UI.GREEN, 30, Vector2(260, 64))
	if language == "ko":
		back.add_theme_font_override("font", TutorialText.korean_font())
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back.pressed.connect(func():
		_close_overlay(root)
		if from_tutorial:
			show_tutorial_language_menu(true))
	v.add_child(back)
	_pop_in(v)


const RULES_TEXT := """[b][color=#ffd75a]Цель.[/color][/b] Снизь жизни соперника с 25 до 0.

[b][color=#ffd75a]Герои и колоды.[/color][/b] Перед игрой каждый выбирает героя — это его колода из 40 карт и 4 земли. Земли бывают: Синие равнины, Кукурузные поля, Милые земли, Бесплодные болота, Песчаные и Ледяные земли, а у Лича — Призрачные. Колоды Лича и Древесной Ветви — фанатские, из мода для Tabletop Simulator.

[b][color=#ffd75a]Подготовка.[/color][/b] Первый игрок определяется монеткой. У героев с землями двух типов (Лимонохват, Гантер, Пупырка, Марселин) игрок сам расставляет свои 4 земли. Каждый берёт 5 карт; один раз за игру можно сменить стартовую руку.

[b][color=#ffd75a]Поле.[/color][/b] Четыре зоны. В зоне на твоей стороне лежит земля; на ней может стоять одно твоё существо, а под ней — одно строение. Существо атакует только то, что напротив в той же зоне.

[b][color=#ffd75a]Ход.[/color][/b]
1. Все твои карты подготавливаются (встают прямо).
2. Возьми карту.
3. Потрать 2 действия: разыгрывай карты, применяй способности или бери карту за 1 действие. Остаток действий в конце хода пропадает.
4. Приём (флюп): поверни своё существо или строение, чтобы применить способность «ПРИЁМ >>>». Повёрнутое существо не атакует в этот ход, но защищается.
5. Атака: все неповёрнутые существа обязаны атаковать (порядок выбираешь сам). Если напротив есть существо — оба наносят урон одновременно. Если пусто — урон получает сам соперник.

[b][color=#ffd75a]Розыгрыш карт.[/color][/b] Стоимость в кружке — это и число действий, и сколько земель нужного типа ты должен контролировать. Радужным картам подходит любая земля. Перевёрнутые земли не считаются ни за какой тип. Карты стоимостью 0 можно играть в свой ход всегда.
Существо можно сыграть в любую свою зону. Если там уже стоит твоё неповёрнутое существо, оно заменяется и уходит в сброс. Строения кладутся под землю и заменяются так же. Заклинания срабатывают и уходят в сброс.

[b][color=#9fe7ff]Лёд.[/color][/b] Карты Ледяного Короля и Гантера замораживают земли (Ледяной жетон). Обычно на замёрзшую землю нельзя играть существ, но строения можно. В свой ход можно сбросить карту и растопить лёд на своей земле — кликни по замёрзшей земле.

[b][color=#ffd75a]Урон.[/color][/b] Урон на существах сохраняется между ходами. Когда урон достигает защиты, существо погибает и уходит в сброс владельца. «Восстановить урон» — снять урон с существа, «восстановить HP» — вернуть жизни игроку (не больше 25).

[b][color=#ffd75a]Важно.[/color][/b] Первый игрок в самый первый ход не может применять приёмы и атаковать. Предела руки нет; пустая колода не приводит к поражению. Если у способности есть подходящая цель, её нужно выбрать.

[b][color=#9fe7ff]Управление.[/color][/b] Перетащи карту из руки в зону — или кликни по карте, а затем по подсвеченной зоне. Клик по своему существу или строению открывает меню: Приём, способность, атака. Клик по своей колоде — взять карту за действие. ПКМ — рассмотреть любую открытую карту. Пробел — ускорить анимации. F11 — полный экран. Esc — меню.

[b][color=#ffd75a]2 на 2.[/color][/b] Две команды по два игрока, напарники сидят друг напротив друга, ходы идут по кругу. У команды общие 40 жизней. Две твои земли смотрят на соперника слева, две — на соперника справа: существо атакует того, кто напротив его зоны. Средние две земли считаются соседними. Первые три игрока в свой первый ход не применяют приёмы и не атакуют. «Противник» в тексте карты — любой из двух соперников: если это важно, его выбираешь ты; «каждое существо противника» — существа обоих. Жетонов льда сколько угодно, как в игре вдвоём. Пустые места занимает ИИ, по сети — на ПК создателя комнаты.

[b][color=#ffd75a]На троих.[/color][/b] Каждый сам за себя, у каждого 25 жизней, ходы идут по кругу. Две твои земли смотрят на соперника слева, две — на соперника справа. Первые два игрока в свой первый ход не применяют приёмы и не атакуют. «Противник» в тексте карты — любой из двух: если это важно, его выбираешь ты; «каждое существо противника» — существа обоих. Кто первым теряет все жизни, выбывает: его карты уходят со стола, а двое оставшихся доигрывают 1 на 1 на обычном поле, зона против зоны. Выбывший смотрит партию до конца. Побеждает последний.

[b][color=#9fe7ff]На одном устройстве.[/color][/b] Играйте вдвоём за одним устройством: между ходами экран закрывается шторкой, чтобы соперник не подглядел твою руку. Если соперник должен выбрать карту из своей руки в твой ход, на экране появятся его карты — отвернись.

[b][color=#9fe7ff]По сети.[/color][/b] Оба игрока подключаются к одной сети Radmin VPN (или сидят в одной локальной сети) и выбирают своих героев. Один нажимает «Создать игру» и сообщает другу свой адрес (в Radmin он вида 26.x.x.x), второй вводит этот адрес и жмёт «Подключиться». Если Windows спросит про брандмауэр — разреши доступ. У обоих должна быть одна и та же версия игры.
Если связь пропала, партия не сбрасывается: она встаёт на паузу. Гость нажимает «Переподключиться» (или ждёт — игра сама пытается вернуться), и партия продолжается с того же места.
"""


# ================================================================ hero selection
# hero_select: scripts/ui/main/hero_select.gd; what the rest of the game calls:

func show_hero_select(mode: String) -> void:
	hero_select.show_hero_select(mode)


func _hero_select_done(mode: String, picks: Array, randoms: Array) -> void:
	hero_select._hero_select_done(mode, picks, randoms)


func _start_mode(mode: String) -> void:
	hero_select._start_mode(mode)


func _random_hero() -> String:
	return hero_select._random_hero()


func show_deck_builder(start_code: String, on_pick := Callable(), note := "", hero := "") -> void:
	hero_select.show_deck_builder(start_code, on_pick, note, hero)


func _land_row(id: String, size: int) -> HBoxContainer:
	return hero_select._land_row(id, size)


# ================================================================ game setup helpers

## Coin toss, land arrangement and mulligans for local players.
## `humans` lists the seats controlled from this PC (others keep their defaults).
## hand_curtain: a screen before each starting hand (off in a run, there it is one step less).
func _prepare_local_game(first: int, humans: Array, coin_text: String, curtains: bool, hand_curtain := true,
		coin_title := "Бросаем монетку…") -> bool:
	var my_game = game
	await _curtain(first, coin_title, coin_text, "Дальше", true)
	if game != my_game:
		return false
	for p in game.seats_from(first):
		if not humans.has(p) or CardDB.hero_land_types(game.players[p].hero).size() < 2:
			continue
		board.set_hands_hidden(true)
		var types: Array = await board.arrange_lands_prompt(p)
		if game != my_game:
			return false
		await board.run_engine(func(): await game.cmd_arrange_lands(p, types))
	for p in game.seats_from(first):
		if not humans.has(p):
			continue
		var pname: String = game.players[p].name
		if curtains:
			await _curtain(p, "Стартовая рука", "Передай управление: %s смотрит свою руку.\nСоперник — отвернись!" % pname, "Я %s — смотреть руку" % pname)
		elif hand_curtain:
			await _curtain(p, "Стартовая рука", "Посмотри свою стартовую руку.\nЕё можно один раз сменить.", "Смотреть руку")
		if game != my_game:
			return false
		var changed: bool = await board.mulligan_prompt(p)
		if game != my_game:
			return false
		if changed:
			await board.run_engine(func(): await game.cmd_mulligan(p))
		board.set_hands_hidden(true)
	return game == my_game


func _new_board() -> void:
	if board != null:
		board.queue_free()      # a game started over another one: its table goes
	board = Board.new()
	_music_hold = false
	_battle_track = ""
	stage.add_child(board)
	board.start(game)
	_layout()
	board.game_finished.connect(_on_game_over)
	board.menu_requested.connect(show_pause)
	board.chat_requested.connect(func(): social_ui.show_panel("chat", Social.GAME))
	board.items_requested.connect(_toggle_run_items)


## Tab in a fight of «Бесконечный поезд»: the hero's items over the table, and away again.
func _toggle_run_items() -> void:
	if _items_root != null and is_instance_valid(_items_root):
		_close_overlay(_items_root)
		_items_root = null
		return
	if _mode != "run" or run == null or _overlay_open:
		return
	var root := _overlay_root(Color(0, 0, 0, 0.0))
	_items_root = root
	var screen = RunScreen.new()
	screen.setup(run, {}, {})
	var page: Control = screen.items_page(func(): _toggle_run_items())
	screen.free()
	page.scale = stage.scale
	page.position = stage.position
	root.add_child(page)


# ================================================================ hot-seat game

func start_new_game(heroes: Array = []) -> void:
	if heroes.is_empty():
		heroes = _last_heroes
	_clear_title()
	online = false
	ai_mode = false
	_ai_vs_ai_mode = false
	seat = -1
	_mode = "hotseat"
	game = Game.new()
	var first := randi() % 2
	game.setup(heroes, first)
	game.journal = []
	_new_board()
	board.handoff_needed.connect(_on_handoff)
	board.set_hands_hidden(true)
	var my_game = game
	var fname: String = game.players[first].name
	if not await _prepare_local_game(first, [0, 1], "Первым ходит %s!" % fname, true):
		return
	await _curtain(first, "Начинаем!", "%s ходит первым.\nВ первый ход нельзя применять приёмы и атаковать." % fname, "Начать ход")
	if game != my_game:
		return
	board.set_viewer(first)
	board.set_hands_hidden(false)
	await board.run_engine(func(): await game.start_game())


func _on_handoff() -> void:
	if game == null or game.phase != "handoff":
		return
	board.set_hands_hidden(true)
	var p: int = game.turn_player
	var pname: String = game.players[p].name
	await _curtain(p, "Ход переходит к игроку %s" % pname, "Передай управление.\nКогда соперник отвернётся — жми кнопку.", "Я %s — начать ход" % pname)
	if board == null or game == null:
		return
	board.set_viewer(p)
	board.set_hands_hidden(false)
	await board.run_engine(func(): await game.cmd_start_turn())


# ================================================================ vs AI game

func start_ai_game(heroes: Array = []) -> void:
	if heroes.is_empty():
		heroes = _last_heroes.duplicate()
		for i in 2:
			if _ai_random[i]:
				heroes[i] = _random_hero()
	_clear_title()
	if not await _wait_ai([[_ai_levels[1], heroes[1]]]):
		return
	online = false
	ai_mode = true
	_ai_vs_ai_mode = false
	seat = 0
	_mode = "ai"
	var agent = _new_ai_agent(1, heroes[1])
	game = Game.new()
	var my_game = game
	var first := randi() % 2
	game.setup(heroes, first)
	game.journal = []
	_new_board()
	board.enable_ai(agent, 1, 0)
	board.set_hands_hidden(true)
	var fname: String = game.players[first].name
	var first_text := "Первым ходишь ты (%s)!" % fname if first == 0 else "Первым ходит ИИ (%s)!" % fname
	if not await _prepare_local_game(first, [0], first_text, false):
		return
	if not await _ai_mulligan(1, agent):
		return
	var start_text := "Ты ходишь первым.\nВ первый ход нельзя применять приёмы и атаковать." if first == 0 \
		else "ИИ (%s) ходит первым.\nВ первый ход нельзя применять приёмы и атаковать." % fname
	await _curtain(first, "Начинаем!", start_text, "В бой!")
	if game != my_game:
		return
	board.set_viewer(0)
	board.set_hands_hidden(false)
	await board.run_engine(func(): await game.start_game())
	if first == 1:
		board.trigger_ai_turn()


# ================================================================ 2 на 2

## 2 на 2 at this PC (the Doubles Tournament rules): seats 0 and 2 against 1 and 3, any of
## them played by the AI. With more than one person they pass the PC round as in a hot-seat game.
func start_teams_game(heroes: Array = []) -> void:
	await _start_seats_game("teams", heroes)


## На троих at this PC: three seats each for itself, any of them played by the AI, as 2 на 2.
func start_three_game(heroes: Array = []) -> void:
	await _start_seats_game("three", heroes)


## The picks, AI seats, AI levels and random seats of "teams" or "three" (the arrays themselves).
func seat_state(mode: String) -> Dictionary:
	if mode == "three":
		return {"heroes": _three_heroes, "ai": _three_ai, "levels": _three_levels, "random": _three_random}
	return {"heroes": _teams_heroes, "ai": _teams_ai, "levels": _teams_levels, "random": _teams_random}


func _start_seats_game(mode: String, heroes: Array) -> void:
	var st := seat_state(mode)
	var n: int = st["heroes"].size()
	if heroes.is_empty():
		heroes = st["heroes"].duplicate()
		for i in n:
			if st["random"][i]:
				heroes[i] = _random_hero()
	_clear_title()
	var wanted := []
	for i in n:
		if st["ai"][i]:
			wanted.append([st["levels"][i], heroes[i]])
	if not await _wait_ai(wanted):
		return
	online = false
	ai_mode = true
	_ai_vs_ai_mode = false
	seat = 0
	_mode = mode
	var agents := {}
	var people := []
	for i in n:
		if st["ai"][i]:
			agents[i] = AILevels.agent(st["levels"][i], heroes[i])
		else:
			people.append(i)
	game = Game.new()
	var my_game = game
	var first := randi() % n
	game.setup(heroes, first)
	game.journal = []
	_new_board()
	board.enable_seats(agents, people)
	board.handoff_needed.connect(_on_handoff)
	board.set_hands_hidden(true)
	var fname: String = game.players[first].name
	var first_text := "Первым ходит %s." % fname
	if first == 0:
		first_text = "Первым ходишь ты (%s)!" % fname
	elif agents.has(first):
		first_text = "Первым ходит ИИ (%s)." % fname
	if not await _prepare_local_game(first, people, first_text, people.size() > 1):
		return
	for p in game.seats_from(first):
		if agents.has(p) and not await _ai_mulligan(p, agents[p]):
			return
	var start_text := "%s против %s.\nПервые три хода — без приёмов и атак." % [game.side_name(0), game.side_name(1)]
	if mode == "three":
		start_text = "%s, %s и %s.\nПервые два хода — без приёмов и атак." % game.players.map(func(ps): return ps.name)
	await _curtain(first, "Начинаем!", start_text, "В бой!")
	if game != my_game:
		return
	board.set_viewer(first if people.has(first) else 0)
	board.set_hands_hidden(false)
	await board.run_engine(func(): await game.start_game())
	board.trigger_ai_turn()


# ================================================================ «Бесконечный поезд»
# train_menu: scripts/ui/main/train_menu.gd; what the rest of the game calls:

func open_run() -> void:
	train_menu.open_run()


func start_daily() -> void:
	train_menu.start_daily()


func show_daily_board() -> void:
	train_menu.show_daily_board()


func _run_hero() -> String:
	return train_menu._run_hero()


func start_run(pick: String, difficulty := 0) -> void:
	train_menu.start_run(pick, difficulty)


func _run_open() -> int:
	return train_menu._run_open()


func _run_level() -> int:
	return train_menu._run_level()


func _difficulty_picker(width := 430) -> Control:
	return train_menu._difficulty_picker(width)


func _run_records() -> Dictionary:
	return train_menu._run_records()


func show_run(prev := {}) -> void:
	train_menu.show_run(prev)


func _close_run_screen() -> void:
	train_menu._close_run_screen()


func start_run_fight() -> void:
	await train_menu.start_run_fight()


func _on_run_fight_over(winner: int) -> void:
	await train_menu._on_run_fight_over(winner)


func _run_unlock() -> int:
	return train_menu._run_unlock()


func _run_over(by_fight := false) -> void:
	train_menu._run_over(by_fight)


# ================================================================ AI vs AI spectator

func start_ai_vs_ai_game(heroes: Array = []) -> void:
	if heroes.is_empty():
		heroes = _last_heroes.duplicate()
		for i in 2:
			if _ai_random[i]:
				heroes[i] = _random_hero()
	_clear_title()
	if not await _wait_ai([[_ai_levels[0], heroes[0]], [_ai_levels[1], heroes[1]]]):
		return
	online = false
	ai_mode = true
	_ai_vs_ai_mode = true
	seat = -1
	_mode = "aivsai"
	var agent_0 = _new_ai_agent(0, heroes[0])
	var agent_1 = _new_ai_agent(1, heroes[1])
	game = Game.new()
	var my_game = game
	var first := randi() % 2
	game.setup(heroes, first)
	game.journal = []
	_new_board()
	board.enable_ai_vs_ai(agent_0, agent_1)
	var fname: String = game.players[first].name
	await _curtain(first, "ИИ против ИИ", "%s против %s.\nПервым ходит %s." % [game.players[0].name, game.players[1].name, fname], "Начать!", true)
	if game != my_game:
		return
	for p in [first, 1 - first]:
		if not await _ai_mulligan(p, agent_0 if p == 0 else agent_1):
			return
	await board.run_engine(func(): await game.start_game())
	board.trigger_ai_turn()


## The AI of a seat at its chosen level (ai_levels.gd), for the seat's pick (its deck).
func _new_ai_agent(p: int, pick: String) -> Object:
	return AILevels.agent(_ai_levels[p], pick)


## Waits, with the window drawing, until the networks of these [level, pick] pairs are read
## (they read in a background thread, ai_levels.gd warm). False when another game started
## meanwhile (this start is then dropped).
func _wait_ai(pairs: Array) -> bool:
	for pr: Array in pairs:
		AILevels.warm(pr[0], pr[1])
	var my_game = game
	while not pairs.all(func(pr: Array) -> bool: return AILevels.is_ready(pr[0], pr[1])):
		await get_tree().process_frame
		if game != my_game:
			return false
	return true


## The AI seat decides on its starting hand (only the self-play network does).
## False when the game was left meanwhile.
func _ai_mulligan(p: int, agent: Object) -> bool:
	var my_game = game
	if agent.has_method("mulligan") and agent.mulligan(game, p):
		await board.run_engine(func(): await game.cmd_mulligan(p))
	return game == my_game


# ================================================================ online lobby
# lobby: scripts/ui/main/lobby.gd; what the rest of the game calls:

func show_net_lobby(mode := "room") -> void:
	lobby.show_net_lobby(mode)


func _refresh_lobby_hero() -> void:
	lobby._refresh_lobby_hero()


func _net_host_room(seats := 2) -> void:
	lobby._net_host_room(seats)


func _net_join_room(text: String) -> void:
	lobby._net_join_room(text)


func _on_room_ready(code: String) -> void:
	lobby._on_room_ready(code)


func _on_net_connected() -> void:
	lobby._on_net_connected()


func _on_net_message(d: Dictionary) -> void:
	lobby._on_net_message(d)


func _on_net_disconnected(reason: String) -> void:
	if watch.active:
		watch.on_disconnected(reason)
		return
	lobby._on_net_disconnected(reason)


func _on_net_resumed() -> void:
	lobby._on_net_resumed()


func _close_link_overlay() -> void:
	lobby._close_link_overlay()


func _stop_rejoin() -> void:
	lobby._stop_rejoin()


func _leave_match() -> void:
	lobby._leave_match()


func _surrender_online() -> void:
	lobby._surrender_online()


func _show_rematch_note() -> void:
	lobby._show_rematch_note()


func _try_rematch() -> void:
	lobby._try_rematch()


func _team_missing() -> String:
	return lobby._team_missing()


func _on_seat_joined(g: int, resumed: bool) -> void:
	lobby._on_seat_joined(g, resumed)


func _on_seat_left(g: int, on_purpose: bool) -> void:
	lobby._on_seat_left(g, on_purpose)


func _team_start() -> void:
	lobby._team_start()


# ================================================================ end of game

func _on_game_over(winner: int, note := "") -> void:
	if _replay != null:
		return          # a replay ends with its own screen (_on_replay_ended)
	_music_hold = true  # the fight music gives way to the end tune (board.gd)
	_music_hold_until = Time.get_ticks_msec() + END_QUIET_MS
	if _mode == "run":
		_on_run_fight_over(winner)
		return
	if _mode == "sandbox":
		return          # «Песочница» goes on after a win (board.gd), nothing is kept or counted
	_keep_replay()
	var replay_data := _game_replay()
	if online and _mode == "net":
		lobby.tour_game_over(winner, replay_data)
	if online and net.mode == "relay" and game != null:
		# Wins and losses against people (the profile): the server counts it when the other side says the same.
		social.report_result(net.room_code, net.seat_token(), game.rng_seed,
			game.team(seat) == winner if game.teams() else winner == seat)
	await get_tree().create_timer(0.8).timeout
	if game == null:
		return
	var ps = game.players[winner]
	var root := _overlay_root(Color(0.02, 0.01, 0.05, 0.7))
	_game_over_root = root
	var won: bool = (winner == seat) if (online or (ai_mode and not _ai_vs_ai_mode)) else true
	if game.teams():
		# The winner is a team. Lost only when nobody of this PC's people is in it.
		won = _mode != "teams" or board.humans.is_empty() or board.humans.any(func(h): return game.team(h) == winner)
		if online:
			won = game.team(seat) == winner
	elif game.three() and not online:
		won = board.humans.is_empty() or board.humans.has(winner)
	if won:
		_confetti(root)
	var center := FitCenter.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 18)
	# A phone: the hero card at the left of the words and buttons (the screen is low).
	var pic_box: Container = v
	if phone_layout:
		pic_box = HBoxContainer.new()
		pic_box.alignment = BoxContainer.ALIGNMENT_CENTER
		pic_box.add_theme_constant_override("separation", 30)
		center.add_child(pic_box)
		v.add_theme_constant_override("separation", 10)
	else:
		center.add_child(v)
	if game.teams():
		var pair := HBoxContainer.new()
		pair.alignment = BoxContainer.ALIGNMENT_CENTER
		pair.add_theme_constant_override("separation", 24)
		pair.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		pic_box.add_child(pair)
		for s2 in [winner, winner + 2]:
			pair.add_child(_hero_card_rect(game.players[s2].hero_card, Vector2(180, 245) if phone_layout else Vector2(300, 400)))
	else:
		var portrait := _hero_card_rect(ps.hero_card, Vector2(260, 330) if phone_layout else Vector2(380, 450))
		portrait.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		pic_box.add_child(portrait)
	if phone_layout:
		v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		pic_box.add_child(v)
	var t := WoodUI.label("ПОБЕДА!" if won else "ПОРАЖЕНИЕ", 72 if phone_layout else 120, Color(1.0, 0.86, 0.35) if won else Color(0.75, 0.75, 0.85), 24)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var line := "%s снизил жизни соперника до нуля. Это было круто!" % ps.name
	if game.teams():
		line = "%s снизили жизни команды соперников до нуля!" % game.side_name(winner)
	elif game.three():
		line = "%s остаётся последним за столом!" % ps.name
	if note != "":
		line = "%s Победа: %s." % [note, game.side_name(winner)]
	if _ai_vs_ai_mode:
		_ai_series[winner] += 1
		t.text = "ПОБЕДИЛ ИИ %d" % (winner + 1)
		line = "%s выигрывает! Счёт серии — ИИ 1 (%s) %d : %d ИИ 2 (%s)" % [ps.name, game.players[0].name,
			_ai_series[0], _ai_series[1], game.players[1].name]
	var s := WoodUI.label(line, 24 if phone_layout else 30, UI.hero_color(ps.hero), 8)
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if phone_layout:
		s.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		s.custom_minimum_size.x = 600
	v.add_child(s)
	var row: Container
	if phone_layout:
		row = GridContainer.new()
		row.columns = 2
		row.add_theme_constant_override("h_separation", 12)
		row.add_theme_constant_override("v_separation", 10)
		row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	else:
		row = HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 20)
	v.add_child(row)
	var again := WoodUI.button("Реванш", UI.RED, 34, Vector2(300, 76))
	again.set_meta("kn_primary", true)
	row.add_child(again)
	var other := WoodUI.button("Другие герои", UI.ORANGE, 30, Vector2(300, 76))
	row.add_child(other)
	var menu := WoodUI.button("Главное меню", UI.PURPLE, 30, Vector2(300, 76))
	row.add_child(menu)
	var auto_ref := {"active": true}
	var save := WoodUI.button("Сохранить реплей", UI.BLUE, 26, Vector2(300, 76))
	save.pressed.connect(func():
		auto_ref["active"] = false
		_export_replay(replay_data))
	row.add_child(save)
	if _mode == "tutorial":
		again.visible = false
		other.text = "Продвинутое обучение"
		other.pressed.connect(func():
			_close_overlay(root)
			_game_over_root = null
			_end_game()
			show_title()
			show_tutorial_language_menu(false, true))
		save.visible = false
		menu.pressed.connect(func():
			_close_overlay(root)
			_game_over_root = null
			_end_game()
			show_title())
		_pop_in(v)
		return
	if online:
		# The next match can be played with another deck: the pick goes to the others.
		other.text = "Сменить колоду"
		other.pressed.connect(func(): show_hero_select("net"))
	if online and not net.tour.is_empty():
		# A tournament match: the decks are the organizer's, the next game is the next of the series.
		other.visible = false
		again.text = "Следующая партия"
		if net.tour.get("over", false):
			again.disabled = true
			again.text = "Матч окончен"
	if online and _mode in ["teams_net", "three_net"]:
		if net.is_host:
			again.pressed.connect(func():
				_close_overlay(root)
				_game_over_root = null
				_team_start())
		else:
			again.disabled = true
			again.text = "Ждём реванша"
		menu.pressed.connect(func():
			net.leave()
			_close_overlay(root)
			_game_over_root = null
			_end_game()
			show_title())
		_pop_in(v)
		return
	if online:
		_rematch_button = again
		_rematch_note = WoodUI.label("", 24, UI.CREAM, 6, UI.UI_FONT)
		_rematch_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(_rematch_note)
		_show_rematch_note()
		if not net.active:
			again.disabled = true
			again.text = "Связь потеряна"
		again.pressed.connect(func():
			_rematch_local = true
			again.disabled = true
			again.text = "Ждём соперника…"
			other.disabled = true
			net.send({"t": "rematch"})
			_try_rematch())
		menu.pressed.connect(func():
			net.leave()
			_close_overlay(root)
			_game_over_root = null
			_end_game()
			show_title())
		_pop_in(v)
		return
	var mode := "aivsai" if _ai_vs_ai_mode else ("ai" if ai_mode else "hotseat")
	if _mode in ["teams", "three"]:
		mode = _mode
	again.pressed.connect(func():
		auto_ref["active"] = false
		_close_overlay(root)
		_game_over_root = null
		_end_game()
		_start_mode(mode))
	other.pressed.connect(func():
		auto_ref["active"] = false
		_close_overlay(root)
		_game_over_root = null
		_end_game()
		show_title()
		show_hero_select(mode))
	menu.pressed.connect(func():
		auto_ref["active"] = false
		_close_overlay(root)
		_game_over_root = null
		_end_game()
		show_title())
	_pop_in(v)
	if mode == "aivsai":
		again.text = "Следующая игра"
		var countdown := WoodUI.label("", 22, UI.CREAM, 5, UI.UI_FONT)
		countdown.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(countdown)
		for sec in range(6, 0, -1):
			if not (auto_ref["active"] and is_instance_valid(root)):
				break
			countdown.text = "Следующая игра через %d сек…" % sec
			await get_tree().create_timer(1.0).timeout
		if auto_ref["active"] and is_instance_valid(root) and _game_over_root == root:
			_close_overlay(root)
			_game_over_root = null
			_end_game()
			start_ai_vs_ai_game()
		elif is_instance_valid(countdown):
			countdown.text = ""


func _end_game() -> void:
	watch.on_end_game()
	_keep_replay()
	_stop_rejoin()
	_close_link_overlay()
	# The setup waits for a message that never comes once the other player is gone.
	_close_overlay(_setup_wait)
	_setup_wait = null
	if board != null:
		board.queue_free()
		board = null
	game = null
	online = false
	ai_mode = false
	_ai_vs_ai_mode = false
	_replay = null


func show_pause() -> void:
	if _pause_root != null and is_instance_valid(_pause_root):
		_close_overlay(_pause_root)
		_pause_root = null
		return
	if _overlay_open:
		return
	var root := _overlay_root(Color(0.02, 0.01, 0.05, 0.75))
	_pause_root = root
	var center := FitCenter.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_box())
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	panel.add_child(v)
	# Online the game keeps running for the other player, so it is a menu, not a pause.
	v.add_child(_title("Меню" if online else "Пауза", 44))
	var resume := WoodUI.button("Продолжить", UI.GREEN, 32, Vector2(380, 70))
	resume.set_meta("kn_primary", true)
	resume.pressed.connect(func(): _close_overlay(root))
	v.add_child(resume)
	var rules := WoodUI.button("Правила", UI.BLUE, 30, Vector2(380, 64))
	rules.pressed.connect(func():
		_close_overlay(root)
		show_rules())
	v.add_child(rules)
	var settings := WoodUI.button("Настройки", UI.PURPLE, 26, Vector2(380, 60))
	settings.pressed.connect(func():
		_close_overlay(root)
		show_settings())
	v.add_child(settings)
	var keys := WoodUI.button("Клавиши", UI.BLUE, 26, Vector2(380, 60))
	keys.pressed.connect(func(): get_node("/root/KeyNav").toggle_help())
	var pad = get_node_or_null("/root/Gamepad")
	if pad != null and pad.active:
		keys.text = "Кнопки"          # the pad's buttons, drawn (gamepad.gd)
	if not phone_layout or pad != null and pad.connected():          # a phone has no keys, maybe a pad
		v.add_child(keys)
	if online:
		# На троих whoever dropped out only watches: nothing to give up, they may just leave.
		var watching: bool = game != null and game.three() and game.is_out(seat)
		var give_up := WoodUI.button("Сдаться", UI.ORANGE, 26, Vector2(380, 60))
		give_up.pressed.connect(func():
			_close_overlay(root)
			_surrender_online())
		give_up.visible = not watching
		if board != null and board.concede_pending():
			give_up.text = "Сдашься в свой ход"
			give_up.disabled = true
		v.add_child(give_up)
		var leave_text := "Выйти в меню" if watching and not net.is_host else "Отключиться и выйти в меню"
		if net.ranked():
			leave_text = "Выйти, это поражение"     # the room server counts a ranked match left as lost
		var leave := WoodUI.button(leave_text, UI.RED, 24, Vector2(380, 60))
		leave.pressed.connect(func():
			_close_overlay(root)
			_leave_match())
		v.add_child(leave)
	elif _mode == "sandbox":
		if not sandbox_start.builder_back.is_empty():
			var builder := WoodUI.button("В конструктор", UI.ORANGE, 26, Vector2(380, 60))
			builder.pressed.connect(func():
				_close_overlay(root)
				sandbox_start.back_to_builder())
			v.add_child(builder)
		var leave := WoodUI.button("Выйти в меню", UI.RED, 26, Vector2(380, 60))
		leave.pressed.connect(func():
			_close_overlay(root)
			sandbox_start.builder_back = {}
			_end_game()
			show_title())
		v.add_child(leave)
	elif _mode == "run" and _replay == null:
		# The run is saved: leaving starts this fight over next time; giving up ends the run.
		var give_up := WoodUI.button("Сдаться", UI.ORANGE, 26, Vector2(380, 60))
		give_up.pressed.connect(func():
			_close_overlay(root)
			if game != null and game.phase != "over":
				board.force_over(1)
				_on_game_over(1))
		v.add_child(give_up)
		var leave := WoodUI.button("Выйти в меню", UI.RED, 26, Vector2(380, 60))
		leave.pressed.connect(func():
			_close_overlay(root)
			_end_game()
			show_title())
		v.add_child(leave)
	else:
		var menu := WoodUI.button("Выйти в меню" if _replay != null else "Сдаться и выйти в меню", UI.RED, 26, Vector2(380, 60))
		menu.pressed.connect(func():
			_close_overlay(root)
			_end_game()
			show_title())
		v.add_child(menu)
	if phone_layout:
		_phone_grid(v, 2)
	_pop_in(v)


## A phone: the buttons of a window's column (after its title) in `cols` columns, so the window
## fits the low screen. Their widths become alike.
func _phone_grid(v: Control, cols: int) -> void:
	var grid := GridContainer.new()
	grid.columns = cols
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 10)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var buttons: Array[Button] = []
	for ch in v.get_children():
		if ch is Button:
			buttons.append(ch)
	if buttons.is_empty():
		return
	v.add_child(grid)
	v.move_child(grid, buttons[0].get_index())
	for b in buttons:
		b.reparent(grid, false)
		b.size_flags_horizontal = Control.SIZE_FILL


# ================================================================ updates

## Offers the newer version the server has (scripts/net/updater.gd), on the title screen.
## Once a launch: the game lies where it cannot update itself (straight out of the archive, Program Files).
func _warn_folder() -> void:
	if _folder_warned or board != null or _overlay_open or title_root == null:
		return
	var problem: String = updater.folder_problem()
	if problem == "":
		return
	_folder_warned = true
	var text := "Игра запущена прямо из архива. Распакуй её в обычную папку, например на Рабочий стол, иначе она не сможет обновляться." if problem == "zip" 		else "В этой папке игра не сможет обновляться. Перенеси её в обычную папку, например на Рабочий стол."
	var root := _message_overlay("Неудобная папка", text)
	var ok := WoodUI.button("Понятно", UI.GREEN, 28, Vector2(260, 66))
	ok.pressed.connect(func(): _close_overlay(root))
	root.get_meta("box").add_child(ok)


func _offer_update() -> void:
	if _update_info.is_empty() or board != null or _overlay_open or title_root == null:
		return
	var info := _update_info
	_update_info = {}
	var size := int(info.get("size", 0))
	var line := "Вышла %s." % info["version"]
	if size > 0:
		line += " Загрузка %s." % ("%d МБ" % maxi(size >> 20, 1) if size >= 1 << 20 else "%d КБ" % maxi(size >> 10, 1))
	elif info.get("app", false):
		line += " Нужно установить новую версию игры."
	var root := _message_overlay("Новая версия", line)
	var text: Label = root.get_meta("text")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	root.get_meta("box").add_child(row)
	var go := WoodUI.button("Обновить", UI.GREEN, 28, Vector2(260, 66))
	go.pressed.connect(func(): _run_update(root, text, row))
	row.add_child(go)
	var later := WoodUI.button("Позже", UI.PURPLE, 28, Vector2(220, 66))
	later.pressed.connect(func(): _close_overlay(root))
	row.add_child(later)
	if updater.auto_accept:
		_run_update(root, text, row)


func _run_update(root: Control, text: Label, row: Control) -> void:
	var link: String = updater.app_link()
	if link != "":
		# A new app the game can't put in place itself: the browser downloads it.
		OS.shell_open(link)
		text.text = {"Android": "Установи скачанный файл поверх игры.",
			"macOS": "Открой скачанный файл и перенеси игру в Программы с заменой.",
			"iOS": "Установи новую версию так же, как первую."}.get(OS.get_name(),
			"Распакуй скачанный архив вместо старой игры.")
		for ch in row.get_children():
			ch.queue_free()
		var ok := WoodUI.button("Хорошо", UI.PURPLE, 28, Vector2(240, 66))
		ok.pressed.connect(func(): _close_overlay(root))
		row.add_child(ok)
		return
	row.visible = false
	text.text = "Готовим обновление…"
	await get_tree().process_frame
	await get_tree().process_frame
	var err: String = await updater.download(func(done: int, total: int):
		var shift := 20 if total >= 1 << 20 else 10
		text.text = "Скачиваем: %d%%  ·  %d из %d %s" % [int(done * 100.0 / maxi(total, 1)), done >> shift, total >> shift,
			"МБ" if shift == 20 else "КБ"])
	if err == "" and not updater.can_restart():
		text.text = "Готово. Закрой игру и открой снова."
		return
	if err == "":
		text.text = "Готово, перезапускаем…"
		await get_tree().create_timer(0.8).timeout
		err = updater.restart()
		if err == "":
			return
	text.text = "Не получилось обновиться: %s." % err
	for ch in row.get_children():
		ch.queue_free()
	var ok := WoodUI.button("Хорошо", UI.PURPLE, 28, Vector2(240, 66))
	ok.pressed.connect(func(): _close_overlay(root))
	row.add_child(ok)
	row.visible = true


# ================================================================ replays and files

## The game on the table as a replay.
func _game_replay() -> Dictionary:
	var d := Replay.from_game(game, _mode, maxi(seat, 0), version_text())
	if _mode == "ai":
		d["level"] = _ai_levels[1]
	return d


## A finished or abandoned game joins the saved replays. AI-against-AI games go
## to a file only on request: they come one after another.
func _keep_replay() -> void:
	if game == null or _replay != null or game.journal == null or game == _replay_kept:
		return
	if _mode == "aivsai" or game.turn_number < 1:
		return
	_replay_kept = game
	Replay.keep(_game_replay())


func _export_replay(data: Dictionary) -> void:
	FileDialogs.save_file(self, "Сохранить реплей", Replay.title(data), Replay.EXT, "Реплей", func(path: String):
		if not Replay.write(path, data):
			_notice("Не получилось", "Не удалось записать файл."))


func show_replays() -> void:
	_close_play_menu()
	if _overlay_open:
		return
	var root := _overlay_root(Color(0.03, 0.02, 0.07, 0.88))
	var center := FitCenter.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_box())
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	panel.add_child(v)
	v.add_child(_title("Реплеи"))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(1120, 620)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 10)
	scroll.add_child(list)
	var saved := Replay.saved()
	if saved.is_empty():
		var empty := WoodUI.label("Пока нет записей", 28, UI.CREAM, 6, UI.UI_FONT)
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		list.add_child(empty)
	for item in saved:
		list.add_child(_replay_row(root, item["data"]))
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 20)
	v.add_child(buttons)
	var open := WoodUI.button("Открыть файл", UI.BLUE, 26, Vector2(280, 62))
	open.pressed.connect(func():
		FileDialogs.open_file(self, "Открыть реплей", ["*.%s ; Реплей" % Replay.EXT], func(path: String):
			_close_overlay(root)
			open_file(path)))
	buttons.add_child(open)
	var back := WoodUI.button("Назад", UI.PURPLE, 26, Vector2(220, 62))
	back.pressed.connect(func():
		_close_overlay(root)
		_back_to_play())
	buttons.add_child(back)
	_pop_in(v)


func _replay_row(list_root: Control, d: Dictionary) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", WoodUI.inset(str(d.get("date", "")).hash() % 50, 18, 8))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	panel.add_child(row)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)
	var title := WoodUI.label(Replay.title(d), 28, Color.WHITE, 6)
	title.clip_text = true
	title.custom_minimum_size = Vector2(0, 0)
	col.add_child(title)
	var mode_name: String = MODE_NAMES.get(d.get("mode", ""), "")
	if AILevels.ids().has(d.get("level")):
		mode_name += " · " + AILevels.level(d["level"])["name"].to_lower()
	var sub := "%s · %s · %s · ходов: %d" % [_replay_date(d), mode_name, Replay.result(d), int(d.get("turns", 0))]
	col.add_child(WoodUI.label(sub, 20, UI.CREAM, 4, UI.UI_FONT))
	var watch := WoodUI.button("Смотреть", UI.GREEN, 24, Vector2(170, 56))
	watch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	watch.pressed.connect(func():
		_close_overlay(list_root)
		start_replay(d))
	row.add_child(watch)
	var to_file := WoodUI.button("В файл", UI.ORANGE, 24, Vector2(150, 56))
	to_file.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	to_file.pressed.connect(func(): _export_replay(d))
	row.add_child(to_file)
	return panel


## "14.10 13:05" from the replay's "2026-10-14 13:05".
func _replay_date(d: Dictionary) -> String:
	var date := str(d.get("date", ""))
	if date.length() < 16:
		return date
	return "%s.%s %s" % [date.substr(8, 2), date.substr(5, 2), date.substr(11, 5)]


## Plays a replay on the table, from the side of whoever recorded it.
func start_replay(data: Dictionary) -> void:
	_end_game()
	_clear_title()
	if _replay != data:
		_replay_marks = []
	_replay = data
	_mode = ""
	seat = -1
	game = Replay.new_game(data)
	var my_game = game
	_new_board()
	var view := clampi(int(data.get("seat", 0)), 0, game.players.size() - 1)
	board.enable_replay(data["steps"], view)
	board.replay_ended.connect(_on_replay_ended)
	board.replay_seek.connect(_on_replay_seek)
	board.replay_turns.connect(_show_replay_turns)
	var mode_name := str(MODE_NAMES.get(data.get("mode", ""), "запись"))
	var line := "%s, %s" % [mode_name.left(1).to_upper() + mode_name.substr(1), _replay_date(data)]
	await _curtain(view, "Реплей", "%s\n%s" % [Replay.title(data), line], "Смотреть")
	if game != my_game:
		return
	board.start_replay()


func _on_replay_ended(reason: String) -> void:
	await get_tree().create_timer(0.8).timeout
	if game == null or _replay == null:
		return
	var data: Dictionary = _replay
	var text := "Партия не была доиграна."
	if reason == "broken":
		text = "Дальше запись не совпадает с этой версией игры."
	elif game.phase == "over":
		text = "Победил %s." % game.players[game.winner].name if game.winner >= 0 else "Ничья."
	var root := _message_overlay("Конец реплея", text)
	_replay_end_root = root
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	root.get_meta("box").add_child(row)
	var again := WoodUI.button("Смотреть снова", UI.GREEN, 28, Vector2(300, 68))
	again.pressed.connect(func():
		_close_overlay(root)
		start_replay(data))
	row.add_child(again)
	var turns := WoodUI.button("Ходы", UI.ORANGE, 28, Vector2(200, 68))
	turns.pressed.connect(_show_replay_turns)
	row.add_child(turns)
	var list := WoodUI.button("Реплеи", UI.BLUE, 28, Vector2(220, 68))
	list.pressed.connect(func():
		_close_overlay(root)
		_end_game()
		show_title()
		show_replays())
	row.add_child(list)
	var menu := WoodUI.button("Главное меню", UI.PURPLE, 28, Vector2(260, 68))
	menu.pressed.connect(func():
		_close_overlay(root)
		_end_game()
		show_title())
	row.add_child(menu)


## «Ходы»: every turn of the replay, a click jumps there. A row is one round, a column
## one player.
func _show_replay_turns() -> void:
	var data = _replay
	if data == null or board == null:
		return
	if _replay_marks.is_empty():
		_replay_marks = await Replay.turn_marks(data)
		if _replay != data or board == null:
			return
	var root := _message_overlay("Ходы", "")
	root.get_meta("text").visible = false
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 18)
	root.get_meta("box").add_child(v)
	var cols: int = game.players.size()
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var rows := ceili(_replay_marks.size() / float(cols))
	scroll.custom_minimum_size = Vector2(cols * 290 + 20, mini(rows * 62, 560))
	v.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = cols
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 10)
	scroll.add_child(grid)
	var at: int = board.replay_pos()
	var current: Button = null
	for m in _replay_marks:
		var ps = game.players[int(m["p"])]
		var now: bool = int(m["pos"]) < at
		var b := WoodUI.button("Ход %d: %s" % [m["n"], ps.name], UI.hero_color(ps.hero), 22, Vector2(280, 52))
		b.pressed.connect(func():
			_close_overlay(root)
			board.seek_replay(int(m["pos"])))
		grid.add_child(b)
		if now:
			current = b
	if current != null:
		current.text = "▶ " + current.text
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 20)
	v.add_child(row)
	var start := WoodUI.button("Начало", UI.GREEN, 26, Vector2(220, 60))
	start.pressed.connect(func():
		_close_overlay(root)
		board.seek_replay(0))
	row.add_child(start)
	var back := WoodUI.button("Назад", UI.PURPLE, 26, Vector2(220, 60))
	back.pressed.connect(func(): _close_overlay(root))
	row.add_child(back)
	_pop_in(v)
	if current != null:
		await get_tree().process_frame
		if is_instance_valid(scroll):
			scroll.ensure_control_visible(current)


## The replay jumps: the game is played up to `pos` steps at once, then the table goes on from there.
func _on_replay_seek(pos: int) -> void:
	var data = _replay
	var my_board = board
	var g = await Replay.play_to(data, pos)
	if _replay != data or board == null or board != my_board:
		return
	if _replay_end_root != null and is_instance_valid(_replay_end_root):
		_close_overlay(_replay_end_root)
	_replay_end_root = null
	game = g
	board.replace_game(g, pos)
	board.start_replay()


## A deck or replay file: dropped on the window, given at launch (a double click
## on the file) or picked in a dialog.
func open_file(path: String) -> void:
	var ext := path.get_extension().to_lower()
	if ext == CustomDecks.EXT:
		var builder = _open_builder()
		if builder != null:
			builder.open_file(path)
		else:
			_open_deck_file(path)
	elif ext == Replay.EXT:
		_open_replay_file(path)


func _open_builder():
	for ch in overlay.get_children():
		for b in ch.get_children():
			if b is DeckBuilder and not ch.is_queued_for_deletion():
				return b
	return null


func _open_deck_file(path: String) -> void:
	var entry := CustomDecks.read_file(path)
	if entry.is_empty():
		_notice("Не получилось", "Это не файл колоды.")
		return
	var deck_name := CustomDecks.add(entry)
	if deck_name == "":
		_notice("Не получилось", "Не удалось сохранить колоду.")
		return
	if board == null and not _overlay_open:
		var saved := {"name": deck_name, "lands": entry["lands"], "deck": entry["deck"]}
		show_deck_builder(CustomDecks.code_of(saved), Callable(), "Колода «%s» добавлена" % deck_name)
	else:
		_notice("Колода добавлена", "«%s» теперь среди твоих колод." % deck_name)


func _open_replay_file(path: String) -> void:
	var data := Replay.read(path)
	if data.is_empty():
		_notice("Не получилось", "Это не реплей или он повреждён.")
		return
	if board != null or _lobby_root != null:
		_notice("Реплей", "Его можно открыть, когда партия закончится.")
		return
	if not path.replace("\\", "/").begins_with(ProjectSettings.globalize_path(Replay.DIR)) \
			and not path.begins_with(Replay.DIR):
		Replay.keep(data)       # a file from somebody stays in the list too
	for ch in overlay.get_children():
		_close_overlay(ch)
	start_replay(data)


## The game was started by a double click on a deck or replay file.
func _open_launch_file() -> void:
	for arg: String in OS.get_cmdline_args():
		var ext := arg.get_extension().to_lower()
		if (ext == CustomDecks.EXT or ext == Replay.EXT) and FileAccess.file_exists(arg):
			open_file(arg)
			return


## The exported game opens deck and replay files on a double click: it registers
## both file types for this Windows user (no admin rights needed), once per game folder.
func _register_file_types() -> void:
	if OS.get_name() != "Windows" or not OS.has_feature("template"):
		return
	var exe := OS.get_executable_path().replace("/", "\\")
	if _load_setting("files", "registered", "") == exe:
		return
	var reg := OS.get_user_data_dir().path_join("file_types.reg")
	var f := FileAccess.open(reg, FileAccess.WRITE)
	if f == null:
		return
	f.store_buffer(PackedByteArray([0xFF, 0xFE]) + _file_types_reg(exe).to_utf16_buffer())
	f.close()
	if OS.execute("reg", ["import", reg.replace("/", "\\")]) == 0:
		_save_setting("files", "registered", exe)


## .reg text that makes `exe` open *.cwdeck and *.cwreplay files.
func _file_types_reg(exe: String) -> String:
	var esc := func(s: String) -> String: return s.replace("\\", "\\\\").replace("\"", "\\\"")
	var lines := PackedStringArray(["Windows Registry Editor Version 5.00", ""])
	var classes := "HKEY_CURRENT_USER\\Software\\Classes\\"
	for kind in [[CustomDecks.EXT, "CardWars.deck", "Колода «Карточных войн»"],
			[Replay.EXT, "CardWars.replay", "Реплей «Карточных войн»"]]:
		lines.append_array(["[%s.%s]" % [classes, kind[0]], "@=\"%s\"" % kind[1], "",
			"[%s%s]" % [classes, kind[1]], "@=\"%s\"" % kind[2], "",
			"[%s%s\\DefaultIcon]" % [classes, kind[1]], "@=\"%s\"" % esc.call(exe + ",0"), "",
			"[%s%s\\shell\\open\\command]" % [classes, kind[1]], "@=\"%s\"" % esc.call("\"%s\" \"%%1\"" % exe), ""])
	return "\r\n".join(lines)


func _notice(title: String, text: String) -> void:
	var root := _message_overlay(title, text)
	var b := WoodUI.button("Хорошо", UI.PURPLE, 28, Vector2(240, 64))
	b.pressed.connect(func(): _close_overlay(root))
	root.get_meta("box").add_child(b)


# ================================================================ overlays

## The volume of the sounds, or with music = true of the menu music.
func _volume_row(music := false) -> HBoxContainer:
	var sfx := get_node("/root/Sfx")
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	var name_label := WoodUI.label("Музыка" if music else "Звук", 24, UI.CREAM, 6)
	name_label.custom_minimum_size.x = 110 * WoodUI.font_scale
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(name_label)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = sfx.music_volume if music else sfx.volume
	slider.custom_minimum_size = Vector2(260, 32) * WoodUI.font_scale
	if phone_layout:
		slider.custom_minimum_size = Vector2(300, Phone.TOUCH)       # the finger takes it anywhere on its height
	slider.focus_mode = Control.FOCUS_NONE
	var track := UI.box(WoodUI.PAPER_DARK, 8, 3, WoodUI.INK)
	var fill := UI.box(WoodUI.ORANGE, 8, 3, WoodUI.INK)
	var fill_hi := UI.box(WoodUI.ORANGE.lightened(0.15), 8, 3, WoodUI.INK)
	for sb in [track, fill, fill_hi]:
		sb.content_margin_top = 6
		sb.content_margin_bottom = 6
	slider.add_theme_stylebox_override("slider", track)
	slider.add_theme_stylebox_override("grabber_area", fill)
	slider.add_theme_stylebox_override("grabber_area_highlight", fill_hi)
	slider.value_changed.connect(func(v: float):
		if music:
			sfx.set_music_volume(v)
		else:
			sfx.set_volume(v)
			sfx.play("place"))
	row.add_child(slider)
	return row


func _panel_box() -> StyleBox:
	return WoodUI.window(22, 14) if phone_layout else WoodUI.window(36, 26)


## A phone: the top line of a full window, its back button at the left, the title in the middle
## (the room under it goes to the window's content). `extra` sits at the right.
func _phone_header(text: String, back: Control, extra: Control = null) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	back.custom_minimum_size.x = maxf(back.custom_minimum_size.x, 200.0)
	row.add_child(back)
	var t := _title(text)
	t.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_SHRINK_CENTER
	row.add_child(t)
	var right := Control.new()
	right.custom_minimum_size.x = back.custom_minimum_size.x
	if extra != null:
		right = extra
		right.custom_minimum_size.x = maxf(right.custom_minimum_size.x, back.custom_minimum_size.x)
	row.add_child(right)
	return row


## The title of a window: a paper tag in the middle of its top.
func _title(text: String, size := 38) -> Control:
	var t := WoodUI.title_tag(text, mini(size, 30) if phone_layout else size)
	t.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	return t


## Centered dialog with a title and a text; extra buttons go into meta "box".
func _message_overlay(title: String, text: String) -> Control:
	var root := _overlay_root(Color(0.02, 0.01, 0.05, 0.72))
	var center := FitCenter.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_box())
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 18)
	panel.add_child(v)
	v.add_child(_title(title))
	var s := WoodUI.label(text, 26, UI.CREAM, 6, UI.UI_FONT)
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(s)
	var box := CenterContainer.new()
	v.add_child(box)
	root.set_meta("box", box)
	root.set_meta("text", s)
	return root


func _overlay_root(dim: Color) -> Control:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.add_child(root)
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.04, 0.02, dim.a)      # the warm shade of the table's wood
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	root.modulate.a = 0.0
	root.create_tween().tween_property(root, "modulate:a", 1.0, 0.2)
	_overlay_open = true
	# The AI waits while a menu covers the table (online the game goes on).
	if board != null and not online:
		board.hold_ai += 1
		var b: WeakRef = weakref(board)
		root.tree_exiting.connect(func():
			if b.get_ref() != null:
				b.get_ref().hold_ai -= 1)
	return root


func _close_overlay(root: Control) -> void:
	if root == null or not is_instance_valid(root):
		return
	if root == _pause_root:
		_pause_root = null
	# Nothing in it takes a click while it fades: a quick second tap on «В бой!» used to start
	# a second game, and the first one's table stayed under the menu.
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for ch in root.find_children("*", "Control", true, false):
		(ch as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tw := root.create_tween()
	tw.tween_property(root, "modulate:a", 0.0, 0.18)
	tw.tween_callback(root.queue_free)
	# Still open if some other overlay remains.
	_overlay_open = false
	for ch in overlay.get_children():
		if ch != root and not ch.is_queued_for_deletion() and ch.mouse_filter != Control.MOUSE_FILTER_IGNORE:
			_overlay_open = true


## A full-screen window fills the screen; when the screen is smaller than the window needs
## (a big interface scale), the window is scaled down just enough to fit.
func _fill_screen(root: Control, node: Control) -> void:
	var fit := func():
		var need := Vector2.ONE
		for ch in node.get_children():
			if ch is Control:
				need = need.max(ch.get_combined_minimum_size())
		var room := FitCenter.safe_rect(root)
		var k := minf(1.0, minf(room.size.x / need.x, room.size.y / need.y))
		node.scale = Vector2.ONE * k
		node.position = room.position
		node.size = room.size / k
	root.resized.connect(fit)
	for ch in node.get_children():
		if ch is Control:
			ch.minimum_size_changed.connect(fit)
	fit.call()


func _pop_in(node: Control) -> void:
	node.pivot_offset = node.size * 0.5
	node.scale = Vector2.ONE * 0.8
	node.create_tween().tween_property(node, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Picture of a hero card (it carries the hero's ability text).
## A hero card picture; up to 160 wide it is the small copy (sharp enough at that size on 4K).
func _hero_card_rect(card: String, sz: Vector2) -> TextureRect:
	var r := TextureRect.new()
	r.texture = load(CardDB.hero_thumb(card) if sz.x <= 160.0 else CardDB.hero_image(card))
	r.material = CardView.SHARP
	r.custom_minimum_size = sz
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


## Full-screen curtain: hides the table until the right player clicks.
func _curtain(p: int, title: String, text: String, button_text: String, coin := false) -> void:
	var ps = game.players[p]
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.add_child(root)
	var bg := TextureRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.texture = backdrop.current_texture()
	root.add_child(bg)
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(UI.hero_color(ps.hero).darkened(0.8), 0.6)
	root.add_child(dim)
	var center := FitCenter.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 18)
	# A phone: the coin, the hero card and the words side by side (the screen is wide and low).
	var row: BoxContainer = v
	if phone_layout:
		row = HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 30)
		center.add_child(row)
	else:
		center.add_child(v)

	var coin_node: Control = null
	var letters := []
	if coin:
		for ps2 in game.players:
			letters.append(String(CardDB.hero(ps2.hero).get("letter", "?")))
		var unique := {}
		for l in letters:
			unique[l] = true
		if unique.size() < letters.size():
			letters = range(1, letters.size() + 1).map(func(n): return str(n))
		coin_node = Control.new()
		coin_node.custom_minimum_size = Vector2(240, 240)
		coin_node.pivot_offset = Vector2(120, 120)
		var face := {"text": "?"}
		coin_node.draw.connect(func():
			coin_node.draw_circle(Vector2(124, 128), 112, Color(0, 0, 0, 0.35))
			coin_node.draw_circle(Vector2(120, 120), 112, Color(0.75, 0.55, 0.12))
			coin_node.draw_circle(Vector2(120, 120), 96, Color(1.0, 0.8, 0.25))
			coin_node.draw_string(UI.DISPLAY_FONT, Vector2(0, 158), face["text"], HORIZONTAL_ALIGNMENT_CENTER, 240, 110, Color(0.55, 0.35, 0.05)))
		coin_node.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(coin_node)
		coin_node.set_meta("face", face)
	var portrait := _hero_card_rect(ps.hero_card, Vector2(220, 300) if phone_layout else Vector2(300, 360))
	row.add_child(portrait)
	if phone_layout:
		v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		v.custom_minimum_size.x = 460
		row.add_child(v)
	var t := WoodUI.label(title, 44 if phone_layout else 64, UI.hero_color(ps.hero), 14)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var s := WoodUI.label(text, 24 if phone_layout else 30, UI.CREAM, 8, UI.UI_FONT)
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if phone_layout:
		s.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		s.custom_minimum_size.x = 460
	v.add_child(s)
	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(btn_row)
	var b := WoodUI.button(button_text, UI.hero_color(ps.hero).darkened(0.15), 32, Vector2(380, 70) if phone_layout else Vector2(440, 80))
	b.set_meta("kn_primary", true)      # E presses it (key_nav.gd)
	btn_row.add_child(b)

	root.modulate.a = 0.0
	root.create_tween().tween_property(root, "modulate:a", 1.0, 0.25)
	if coin:
		portrait.modulate.a = 0.0
		s.modulate.a = 0.0
		b.disabled = true
		var face: Dictionary = coin_node.get_meta("face")
		for i in 9:
			var tw := coin_node.create_tween()
			tw.tween_property(coin_node, "scale:x", 0.05, 0.07)
			tw.tween_callback(func():
				face["text"] = letters[i % letters.size()]
				coin_node.queue_redraw())
			tw.tween_property(coin_node, "scale:x", 1.0, 0.07)
			UI.sfx("coin_tick")
			await tw.finished
		face["text"] = letters[p]
		coin_node.queue_redraw()
		UI.sfx("coin")
		var tw2 := root.create_tween().set_parallel()
		tw2.tween_property(portrait, "modulate:a", 1.0, 0.3)
		tw2.tween_property(s, "modulate:a", 1.0, 0.3)
		b.disabled = false
	_overlay_open = true
	await b.pressed
	var out := root.create_tween()
	out.tween_property(root, "modulate:a", 0.0, 0.22)
	out.tween_callback(root.queue_free)
	_overlay_open = false
	await out.finished


func _confetti(root: Control) -> void:
	var colors := [UI.RED, UI.BLUE, UI.GREEN, UI.ORANGE, Color(1.0, 0.86, 0.35), UI.PURPLE]
	for i in colors.size():
		var p := CPUParticles2D.new()
		p.position = Vector2(get_viewport_rect().size.x * 0.5, -20)
		p.amount = 40
		p.lifetime = 4.0
		p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
		p.emission_rect_extents = Vector2(get_viewport_rect().size.x * 0.5, 10)
		p.direction = Vector2.DOWN
		p.spread = 25.0
		p.gravity = Vector2(0, 160)
		p.initial_velocity_min = 80
		p.initial_velocity_max = 220
		p.angular_velocity_min = -400
		p.angular_velocity_max = 400
		p.scale_amount_min = 6
		p.scale_amount_max = 12
		p.color = colors[i]
		p.preprocess = float(i) * 0.3
		root.add_child(p)


# ================================================================ account

## The corner of the title: the avatar and the nick of the player who is logged in (a click opens
## the profile), or the button to log in.
func _refresh_account_chip() -> void:
	if _account_chip != null and is_instance_valid(_account_chip):
		_account_chip.queue_free()
	_account_chip = null
	if title_root == null or not is_instance_valid(title_root):
		return
	if not account.logged_in():
		var enter := WoodUI.button("Войти", UI.GREEN, 30, Vector2(190, 64))
		enter.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT, Control.PRESET_MODE_MINSIZE, 8)
		enter.pressed.connect(func(): show_login())
		title_root.add_child(enter)
		_account_chip = enter
		return
	var chip := PanelContainer.new()
	# A paper tag with the avatar and the nick.
	var normal := WoodUI.card(WoodUI.PAPER, 0.0, 21)
	normal.radius = 40.0
	normal.content_margin_left = 8
	normal.content_margin_right = 26
	normal.content_margin_top = 8
	normal.content_margin_bottom = 8
	var hover := normal.duplicate()
	hover.fill = WoodUI.PAPER.lightened(0.4)
	chip.add_theme_stylebox_override("panel", normal)
	chip.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT, Control.PRESET_MODE_MINSIZE, 8)
	chip.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(row)
	var face := AvatarView.make(account.nick, account.texture(), roundi(64 * WoodUI.font_scale), WoodUI.INK)
	row.add_child(face)
	var nick := WoodUI.text(account.nick, 32, WoodUI.INK, true)
	NickStyle.apply(nick, account.rainbow, account.color)
	var tag := NickStyle.tag(account.tag, 20)
	if tag == null:
		nick.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(nick)
	else:
		var names := VBoxContainer.new()
		names.add_theme_constant_override("separation", 0)
		names.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		names.mouse_filter = Control.MOUSE_FILTER_IGNORE
		names.add_child(nick)
		tag.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		names.add_child(tag)
		row.add_child(names)
	chip.mouse_entered.connect(func(): chip.add_theme_stylebox_override("panel", hover))
	chip.mouse_exited.connect(func(): chip.add_theme_stylebox_override("panel", normal))
	chip.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			UI.sfx("press")
			show_profile())
	title_root.add_child(chip)
	_account_chip = chip


## The window to log in or to register; `then` is called after a successful login.
func show_login(then := Callable()) -> void:
	var root := _overlay_root(Color(0.02, 0.01, 0.05, 0.8))
	var center := FitCenter.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var screen = LoginScreen.new()
	screen.setup(account)
	center.add_child(screen)
	screen.closed.connect(func(): _close_overlay(root))
	screen.done.connect(func():
		_close_overlay(root)
		if then.is_valid():
			then.call())


## The profile of the player who is logged in: the avatar, logging out.
func show_profile() -> void:
	if not account.logged_in():
		show_login()
		return
	var root := _overlay_root(Color(0.02, 0.01, 0.05, 0.8))
	var screen = ProfileScreen.new()
	screen.setup(account, social)
	ProfileScreen.place(root, screen)
	screen.closed.connect(func(): _close_overlay(root))
	screen.logged_out.connect(func():
		_close_overlay(root)
		account.logout(get_tree()))


# ================================================================ players online

## Who may come into the room of this player without being called: "open" (everybody online sees it),
## "friends", "code" (nobody sees it, the code lets in) or "invite" (only the ones called, not even by the
## code; it needs an account). The ticks of the online lobby.
func room_privacy() -> String:
	if bool(_load_setting("net", "invite_only", false)) and account.logged_in():
		return "invite"
	if bool(_load_setting("net", "code_only", false)):
		return "code"
	return "friends" if bool(_load_setting("net", "friends_only", false)) else "open"


## What the player does, for the others: [status, room code, who sees the room, the room's seat token,
## who may call the player] (relay_server.gd «Players online»).
func social_status() -> Array:
	var inv := "friends" if bool(_load_setting("net", "invites_friends", false)) else "all"
	if board != null:
		if net.mode == "relay" and net.room_code != "" and _replay == null:
			# The room and its seat token: the server names the player of the seat in its log.
			return ["game", net.room_code, "friends", net.seat_token(), inv]
		return ["watch" if net.mode == "watch" or _replay != null else ("game" if _mode != "run" else "train"), "", "friends", "", inv]
	if run_screen != null:
		return ["train", "", "friends", "", inv]
	if net.mode == "relay" and net.room_code != "" and net.is_host and net.tour.is_empty():
		if net.team:
			return [("room4" if net.room_seats == 4 else "room3") if net.accept_new else "game", net.room_code, room_privacy(),
				net.seat_token(), inv]
		return ["room" if not net.active else "game", net.room_code, room_privacy(), net.seat_token(), inv]
	if net.mode == "watch":
		return ["watch", "", "friends", "", inv]
	return ["menu", "", "friends", "", inv]


## The player waits in a room of their own: players online can be called into it.
func can_invite() -> bool:
	return social_status()[0].begins_with("room")


## A room of another player (an invite, or «Войти» on a player): the online lobby joins it by its code.
## pass: the one of an invite, it lets into a room by invites only.
func join_friend_room(code: String, pass_key := "") -> void:
	if board != null and online and game != null and game.phase != "over":
		social_ui.toast("Сначала закончи игру", [], 3.0)
		return
	if board != null or run_screen != null:
		if online:
			net.leave()
		_end_game()
		show_title()
	if net.mode != "":
		net.leave()
	if _lobby_root != null:
		lobby._close_lobby()
	for ch in overlay.get_children():
		_close_overlay(ch)
	_overlay_open = false
	lobby.show_net_lobby("room")
	lobby._net_join_room(code, pass_key)


## The chat of the match is there: an online match with its link (or a room with a player in it).
func game_chat_on() -> bool:
	return (net.mode == "relay" or net.mode == "lan") and net.match_id != 0


func send_game_chat(text: String) -> void:
	text = text.strip_edges().substr(0, Social.TEXT_MAX)
	if text == "" or not game_chat_on():
		return
	var nick := account.nick if account.nick != "" else "Игрок %d" % (net.seat_no + 1 if net.team else (1 if net.is_host else 2))
	net.send({"t": "chat", "text": text, "nick": nick})
	_got_game_chat(nick, text, true)


## A message of the match: into the chat and the log of the table.
func _got_game_chat(nick: String, text: String, me := false) -> void:
	social.add(Social.GAME, {"nick": nick, "text": text, "me": me})
	if board != null and online:
		board.add_chat_log(nick, text)


# ================================================================ settings

func _load_setting(section: String, key: String, default):
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		return cfg.get_value(section, key, default)
	return default


func _save_setting(section: String, key: String, value) -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value(section, key, value)
	cfg.save(SETTINGS_PATH)
