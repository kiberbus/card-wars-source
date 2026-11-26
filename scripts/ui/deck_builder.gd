extends Control
## Own deck builder («Конструктор колоды») on Finn and Jake's table (WoodUI). The table and the
## deck are put together by hand: land tiles are dragged onto the four lanes (a click on a lane
## turns it to the next land), cards are dragged from the pool into the deck and back, a click
## on a card adds a copy, «−» in the deck list takes one away, and the right button (on a
## phone: a held finger) shows the card big with its count. The card under the mouse is shown big
## enough to read at the left. The official rules are checked live (CardDB.deck_errors): at
## least 40 cards with no upper limit, each card at most 3 times, four lands of any types.
## Emits `picked(code)` (hero selection) and `closed` (Back).
##
## The deck is built for a hero: its card, name, lands and ability stand at the top of the deck
## column, «Сменить» opens the window of heroes. A hero with a deck of its own gives a copy of
## that deck to edit and save as an own deck (the hero's deck itself stays as it is).
##
## Narrow screens (a phone, a big «Масштаб») have no room for the big card: the lanes go to
## a tab of the deck column instead. Texts and buttons follow the «Шрифт» setting.
##
## A full picture is ~6 MB of video memory (945x1260), so a pool tile shows the small copy
## (320 px, CardDB.card_thumb) once it scrolls into view, loaded in the background. The full
## picture is for the card in the preview and in the big view; only the BIG_KEEP seen last stay.

const CardDB = preload("res://scripts/core/card_db.gd")
const CustomDecks = preload("res://scripts/core/custom_decks.gd")
const UI = preload("res://scripts/ui/ui_kit.gd")
const WoodUI = preload("res://scripts/ui/wood_ui.gd")
const TouchInput = preload("res://scripts/ui/touch_input.gd")
const CardView = preload("res://scripts/ui/card_view.gd")
const FileDialogs = preload("res://scripts/ui/file_dialogs.gd")
const CardBacks = preload("res://scripts/ui/card_backs.gd")
const Phone = preload("res://scripts/ui/phone.gd")

signal picked(code: String)
signal closed
## «Песочница» with the deck as it is now (it may still break the rules) and its hero.
signal sandbox_wanted(deck_name: String, lands: Array, deck: Dictionary, hero: String)

const DEFAULT_NAME := "Моя колода"
const RAINBOW := "rainbow"
const KINDS := ["creature", "building", "spell", "teamwork"]
const KIND_NAMES := {"creature": "Существа", "building": "Здания", "spell": "Заклинания", "teamwork": "Командные"}
## The sets the cards come from (data "set").
const SETS := [["", "Все наборы"], ["fj", "Финн против Джейка"], ["br", "Бимо против Леди Ливнерог"],
	["pl", "Бубльгум против Пупырки"], ["im", "Снежный король против Марселин"], ["lg", "Лимонохват против Гантера"],
	["fc", "Фионна против Кейк"], ["dt", "Парный турнир"], ["fg", "Во имя славы"], ["promo", "Промо"],
	["ks1", "Kickstarter 1"], ["ff", "Огненная Принцесса против Ферна"], ["pli", "Призмо против Лича"],
	["pm", "Мятный Дворецкий против Волшебника"], ["ks2", "Kickstarter 2"], ["ll", "Земля легенд"]]
const GOOD := Color(0.78, 0.95, 0.6)            # the checks, on the felt
const BAD := Color(1.0, 0.62, 0.52)
const WARN := Color(1.0, 0.8, 0.45)
const LIT := Color(0.98, 0.8, 0.42)             # a filter that is on, a count badge
const TILE := Vector2(150, 210)              # a card in the pool (pictures are 500x700)
const LANE_TILE := Vector2(92, 142)          # a land on the table (pictures are 360x556)
const PALETTE_TILE := Vector2(50, 77)
const COST_BARS := 4                         # 0, 1, 2 and 3+
const THUMB_KEEP := 160                      # small copies kept (~0.8 MB of video memory each)
const BIG_KEEP := 8                          # full pictures kept (~6 MB each)
const CLICK_SLOP := 8.0
const LEFT_W := 430.0                        # the column of the lanes and the big card
const DECK_W := 500.0                        # the deck column at «Шрифт» 100%
const POOL_MIN := 760.0                      # a pool narrower than this: the lanes go to a tab

var _pickable := false
var _name := DEFAULT_NAME
var _lands: Array = []
var _deck: Dictionary = {}              # card id -> copies
var _order: Array = []                  # land types, rainbow last (sort order)
var _tiles: Dictionary = {}             # card id -> {"box", "art", "badge", "count"}
var _pool_order: Array = []             # card ids in the grid's own order
var _grid_order: Array = []             # the order the grid shows now
var _haystack: Dictionary = {}          # card id -> [name, the whole text], lowered for the search
var _lanes: Array = []                  # per lane {"art", "icon", "box"}
var _land_filter := ""                  # "" all, a land type or RAINBOW
var _kind_filter := ""                  # "" all or a kind
var _set_filter := ""                   # "" all or a set code (SETS)
var _only_payable := false
var _land_buttons: Dictionary = {}
var _kind_buttons: Dictionary = {}
var _set_btn: Button
var _search: LineEdit
var _name_edit: LineEdit
var _title_tag: Control
var _use_btn: Button
var _toast: PanelContainer
var _status: Label
var _toast_tween: Tween
var _left: Control                      # the column of the lanes and the big card
var _field: Control                     # the lanes and the land tiles
var _narrow := false                    # the lanes are on the «Поле» tab of the deck column
var _short := false                     # a low screen: the deck list keeps the room, the summary goes
var _tabs: HBoxContainer
var _tab_deck: Button
var _tab_field: Button
var _deck_page: Control
var _field_page: Control
var _pool_scroll: ScrollContainer
var _grid: GridContainer
var _preview: TextureRect
var _preview_id := ""
var _deck_title: Label
var _deck_count: Label
var _progress: Control
var _deck_list: VBoxContainer
var _kind_line: Label
var _curve: Control
var _costs: Array = []                  # cards that cost 0, 1, 2 and 3+
var _total := 0
var _check_size: Label
var _check_copies: Label
var _check_cost: Label
var _popup: Control                     # the window over the builder (decks, sets, a card)
var _inspect_id := ""
var _inspect_pic: TextureRect
var _inspect_count: Label
var _inspect_plus: Button
var _thumbs: Dictionary = {}            # card id -> small copy (pool tiles)
var _big: Dictionary = {}               # card id -> full picture (preview, big view)
var _loading: Dictionary = {}           # path -> [card id, big] being read in the background
var _seen: Dictionary = {}              # card id -> frame it was last needed
var _press_at := Vector2.INF
var _hero := ""                         # the hero card the deck is built for, "" none
var _hero_box: Control                  # the hero strip at the top of the deck column
var _hero_pic: TextureRect
var _hero_name: Label
var _hero_lands: HBoxContainer
var _hero_text: Label
var _hero_btn: Button
var _check_hero: Label
var _hero_small: Dictionary = {}        # hero card id -> small copy
var _hero_full: Dictionary = {}         # hero card id -> full picture (the preview, the hero window)
var _hero_loading: Dictionary = {}      # path -> [hero card id, full]
var _hero_rects: Array = []             # TextureRects waiting for a hero picture


## start_code: a pick code to edit ("" for a new deck). pickable: show "В колоду".
## note: a first status line. hero: the hero card to build for ("" the one saved with the deck).
func setup(start_code: String, pickable: bool, note := "", hero := "") -> void:
	_pickable = pickable
	_order = CardDB.land_types() + [RAINBOW]
	_costs.resize(COST_BARS)
	_costs.fill(0)
	_build()
	var d := CardDB.parse_custom(start_code)
	if d.is_empty():
		_load_state(DEFAULT_NAME, ["plain", "plain", "plain", "plain"], {}, hero)
	else:
		if hero == "":
			hero = _saved_hero(start_code)
		_load_state(String(d["name"]), d["lands"], d["deck"], hero)
	_refresh()
	_hover(_sorted(_deck.keys() if not _deck.is_empty() else CardDB.pool_ids())[0])
	if note != "":
		_say(note)


func _exit_tree() -> void:
	for path in _loading.keys() + _hero_loading.keys():
		ResourceLoader.load_threaded_get(path)
	_loading.clear()
	_hero_loading.clear()


## The hero card the deck is built for, "" when none is chosen.
func hero_card() -> String:
	return _hero


func _process(_delta: float) -> void:
	for path: String in _loading.keys():
		var state := ResourceLoader.load_threaded_get_status(path)
		if state == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			continue
		var id: String = _loading[path][0]
		var big: bool = _loading[path][1]
		_loading.erase(path)
		if state == ResourceLoader.THREAD_LOAD_LOADED:
			var tex := CardView.upright(id, ResourceLoader.load_threaded_get(path))
			if big:
				_big[id] = tex
			else:
				_thumbs[id] = tex
			_show_tex(id, big)
	for path: String in _hero_loading.keys():
		var state := ResourceLoader.load_threaded_get_status(path)
		if state == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			continue
		var id: String = _hero_loading[path][0]
		var full: bool = _hero_loading[path][1]
		_hero_loading.erase(path)
		if state == ResourceLoader.THREAD_LOAD_LOADED:
			(_hero_full if full else _hero_small)[id] = ResourceLoader.load_threaded_get(path)
			_show_hero_tex()
	if _pool_scroll == null or not _pool_scroll.is_visible_in_tree():
		return
	var view := _pool_scroll.get_global_rect()
	for id: String in _tiles:
		var box: Control = _tiles[id]["box"]
		if box.visible and box.get_global_rect().intersects(view):
			var tex := _card_tex(id)
			var art: TextureRect = _tiles[id]["art"]
			if tex != null and art.texture != tex:
				art.texture = tex
	_trim_textures()


# ================================================================ layout

func _build() -> void:
	add_child(WoodUI.table())
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, 18)
	add_child(margin)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	margin.add_child(v)
	v.add_child(_header())
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 14)
	v.add_child(body)
	_left = _left_column()
	body.add_child(_left)
	body.add_child(_pool_column())
	body.add_child(_deck_column())
	_toast = _make_toast()
	add_child(_toast)
	resized.connect(_fit_layout)


func _header() -> Control:
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	var back := WoodUI.button("Назад", WoodUI.VIOLET, 26, Vector2(150, 58))
	back.pressed.connect(func(): closed.emit())
	top.add_child(back)
	_title_tag = WoodUI.title_tag("Конструктор колоды", 30)
	_title_tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(_title_tag)
	_name_edit = LineEdit.new()
	WoodUI.edit(_name_edit, 26)
	_name_edit.placeholder_text = "Название колоды"
	_name_edit.max_length = CardDB.CUSTOM_NAME_MAX
	_name_edit.custom_minimum_size = Vector2(240, 58) * WoodUI.font_scale
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.text_changed.connect(func(t: String): _name = t)
	top.add_child(_name_edit)
	var decks := WoodUI.button("Колоды", WoodUI.BLUE, 26, Vector2(160, 58))
	decks.pressed.connect(_show_decks)
	top.add_child(decks)
	var save := WoodUI.button("Сохранить", WoodUI.GO, 26, Vector2(180, 58))
	save.pressed.connect(_on_save)
	top.add_child(save)
	var try := WoodUI.button("Песочница", WoodUI.VIOLET, 26, Vector2(180, 58))
	try.pressed.connect(func(): sandbox_wanted.emit(_current_name(), _lands.duplicate(), _deck.duplicate(), _hero))
	top.add_child(try)
	if _pickable:
		_use_btn = WoodUI.button("В колоду", WoodUI.ORANGE, 26, Vector2(180, 58))
		_use_btn.pressed.connect(_on_use)
		top.add_child(_use_btn)
	return top


## The lanes and the big picture of the card under the mouse.
func _left_column() -> Control:
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(LEFT_W, 0)
	col.add_theme_constant_override("separation", 14)
	_field = _field_panel()
	col.add_child(_field)
	_preview = TextureRect.new()
	_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_preview.texture = CardBacks.texture()
	_preview.material = CardView.SHARP
	_preview.modulate = Color(1, 1, 1, 0.35)
	col.add_child(_preview)
	return col


## The four lanes with the land tiles to drag onto them.
func _field_panel() -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", WoodUI.mat())
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	v.add_child(WoodUI.label("Поле", 26, WoodUI.PAPER, 6))
	var lanes := HBoxContainer.new()
	lanes.add_theme_constant_override("separation", 10)
	lanes.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(lanes)
	for i in CardDB.LANE_COUNT:
		lanes.add_child(_lane_slot(i))
	var palette := HBoxContainer.new()
	palette.name = "Palette"
	palette.add_theme_constant_override("separation", 8)
	palette.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(palette)
	for t: String in CardDB.land_types():
		palette.add_child(_palette_tile(t))
	return panel


func _pool_column() -> Control:
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 10)
	var filters := PanelContainer.new()
	filters.add_theme_stylebox_override("panel", WoodUI.inset(4, 12, 10))
	col.add_child(filters)
	# One bar that wraps: lands, kinds, set, «Под мои земли» and the search at the end of its line.
	var lands_bar: Container
	if Phone.active:
		# A phone: one line that the finger scrolls sideways, the cards get the height.
		var strip := ScrollContainer.new()
		strip.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		strip.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
		strip.custom_minimum_size.y = Phone.TOUCH
		filters.add_child(strip)
		lands_bar = HBoxContainer.new()
		lands_bar.add_theme_constant_override("separation", 6)
		strip.add_child(lands_bar)
	else:
		lands_bar = HFlowContainer.new()
		lands_bar.add_theme_constant_override("h_separation", 6)
		lands_bar.add_theme_constant_override("v_separation", 8)
		filters.add_child(lands_bar)
	for key: String in [""] + CardDB.land_types() + [RAINBOW]:
		var b := _toggle("Все" if key == "" else ("Радужные" if key == RAINBOW else ""),
			_land_texture(key) if key != "" else null)
		if key != "" and key != RAINBOW:
			b.tooltip_text = CardDB.land_name(key)
		b.pressed.connect(func():
			_land_filter = key
			_apply_filter())
		lands_bar.add_child(b)
		_land_buttons[key] = b
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(6, 0)
	lands_bar.add_child(gap)
	var kinds_bar := lands_bar
	for key: String in [""] + KINDS:
		var b := _toggle("Все типы" if key == "" else String(KIND_NAMES[key]), null)
		b.pressed.connect(func():
			_kind_filter = key
			_apply_filter())
		kinds_bar.add_child(b)
		_kind_buttons[key] = b
	_set_btn = _toggle("Набор", null)
	_set_btn.pressed.connect(_show_sets)
	kinds_bar.add_child(_set_btn)
	var payable := _toggle("Под мои земли", null)
	payable.pressed.connect(func():
		_only_payable = not _only_payable
		_apply_filter())
	kinds_bar.add_child(payable)
	_land_buttons["payable"] = payable
	_search = LineEdit.new()
	WoodUI.edit(_search, 22)
	_search.placeholder_text = "Поиск"
	_search.clear_button_enabled = true
	_search.custom_minimum_size = Vector2(220, 50) * WoodUI.font_scale
	if Phone.active:
		_search.custom_minimum_size = Vector2(280, Phone.TOUCH)
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.text_changed.connect(func(_t: String): _apply_filter())
	lands_bar.add_child(_search)
	if Phone.active:
		lands_bar.move_child(_search, 0)        # the search in sight, the filters after it

	var pool := PanelContainer.new()
	pool.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var sb := WoodUI.mat()
	sb.set_content_margin_all(16)
	pool.add_theme_stylebox_override("panel", sb)
	col.add_child(pool)
	_pool_scroll = ScrollContainer.new()
	_pool_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_pool_scroll.resized.connect(_fit_columns)
	_pool_scroll.set_drag_forwarding(Callable(), _can_drop_pool, _drop_pool)
	pool.add_child(_pool_scroll)
	_grid = GridContainer.new()
	_grid.columns = 5
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 12)
	_grid.add_theme_constant_override("v_separation", 12)
	_grid.set_drag_forwarding(Callable(), _can_drop_pool, _drop_pool)
	_pool_scroll.add_child(_grid)
	_pool_order = _sorted(CardDB.pool_ids())
	_grid_order = _pool_order
	for id in _pool_order:
		_grid.add_child(_pool_tile(id))
	return col


func _deck_w() -> float:
	return roundf(DECK_W * lerpf(1.0, WoodUI.font_scale, 0.7))


## The width the wrapping lines are sized for: the deck column less its frame. A wrapping label
## with no minimum width counts its height one letter wide, which made the whole builder ~2.8 s
## of layout on opening (its min height ~2600 px, so it was scaled down to fit).
func _wrap_width() -> float:
	return _deck_w() - 60.0


## The deck list with its count, kinds, cost curve and the rule checks. On a narrow screen
## its tabs switch between the deck and the lanes.
func _deck_column() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(_deck_w(), 0)
	panel.add_theme_stylebox_override("panel", WoodUI.mat())
	panel.set_drag_forwarding(Callable(), _can_drop_deck, _drop_deck)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	panel.add_child(col)
	_tabs = HBoxContainer.new()
	_tabs.add_theme_constant_override("separation", 8)
	_tabs.visible = false
	col.add_child(_tabs)
	_tab_deck = WoodUI.tab("Колода", 24, Vector2(0, 52))
	_tab_field = WoodUI.tab("Поле", 24, Vector2(0, 52))
	for t: Button in [_tab_deck, _tab_field]:
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_tabs.add_child(t)
	_tab_deck.pressed.connect(_show_page.bind(false))
	_tab_field.pressed.connect(_show_page.bind(true))

	var page := VBoxContainer.new()
	page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_theme_constant_override("separation", 8)
	col.add_child(page)
	_deck_page = page
	_field_page = VBoxContainer.new()
	_field_page.add_theme_constant_override("separation", 14)
	_field_page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_field_page.visible = false
	col.add_child(_field_page)

	page.add_child(_hero_strip())
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	page.add_child(head)
	_deck_title = WoodUI.label("Колода", 30, WoodUI.PAPER, 7)
	_deck_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_deck_title)
	_deck_count = WoodUI.label("", 30, GOOD, 7)
	head.add_child(_deck_count)
	_progress = Control.new()
	_progress.custom_minimum_size = Vector2(0, roundf(16 * WoodUI.font_scale))
	_progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_progress.draw.connect(_draw_progress)
	page.add_child(_progress)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.set_drag_forwarding(Callable(), _can_drop_deck, _drop_deck)
	page.add_child(scroll)
	_deck_list = VBoxContainer.new()
	_deck_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_deck_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_deck_list.add_theme_constant_override("separation", 6)
	_deck_list.set_drag_forwarding(Callable(), _can_drop_deck, _drop_deck)
	scroll.add_child(_deck_list)

	_kind_line = WoodUI.label("", 19, WoodUI.PAPER, 5)
	_kind_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_kind_line.custom_minimum_size.x = _wrap_width()
	page.add_child(_kind_line)
	_curve = Control.new()
	_curve.custom_minimum_size = Vector2(0, roundf(96 * WoodUI.font_scale))
	_curve.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_curve.draw.connect(_draw_curve)
	page.add_child(_curve)
	_check_size = _check_line(page)
	_check_copies = _check_line(page)
	_check_cost = _check_line(page)
	_check_hero = _check_line(page)
	return panel


## The lanes beside the pool when the screen is wide enough, on a tab of the deck column
## when it is not.
func _fit_layout() -> void:
	var narrow := size.x < LEFT_W + _deck_w() + POOL_MIN + 70.0
	_title_tag.visible = size.x >= 1750.0 * lerpf(1.0, WoodUI.font_scale, 0.6)
	var short := size.y < 940.0 * lerpf(1.0, WoodUI.font_scale, 0.7)    # with the hero strip
	if short != _short:
		_short = short
		_kind_line.visible = not short
		_curve.visible = not short
		_fit_hero_strip()
		_refresh()
	if narrow == _narrow:
		return
	_narrow = narrow
	_left.visible = not narrow
	_tabs.visible = narrow
	_deck_title.text = "" if narrow else "Колода"           # the tab says it
	for c: Control in [_field, _preview]:
		c.reparent(_field_page if narrow else _left, false)
	_show_page(false)


func _show_page(field: bool) -> void:
	_deck_page.visible = not field
	_field_page.visible = field and _narrow
	WoodUI.set_tab(_tab_deck, not field)
	WoodUI.set_tab(_tab_field, field)


func _draw_progress() -> void:
	var r := Rect2(Vector2.ZERO, _progress.size)
	var track := WoodUI.paper(Color(0.16, 0.22, 0.15), 0.0, 3, 2.0)
	track.radius = r.size.y * 0.5
	track.wobble = 0.6
	_progress.draw_style_box(track, r)
	var k := clampf(float(_total) / CardDB.DECK_MIN, 0.0, 1.0)
	if k > 0.0:
		var bar := WoodUI.paper(WoodUI.GO.lightened(0.15) if _total >= CardDB.DECK_MIN else LIT, 0.0, 5, 2.0)
		bar.radius = r.size.y * 0.5
		bar.wobble = 0.6
		_progress.draw_style_box(bar, Rect2(r.position, Vector2(maxf(r.size.y, r.size.x * k), r.size.y)))


## Bars of how many cards cost 0, 1, 2 and 3 or more, their counts above, the costs below.
func _draw_curve() -> void:
	var w := _curve.size.x
	var h := _curve.size.y
	var size_px := WoodUI.fs(20)
	var font: Font = WoodUI.BOLD
	var line := size_px * 1.25
	var well := h - line * 2.0
	var top := maxi(1, _costs.max())
	var slot := w / COST_BARS
	var bar_w := minf(64.0, slot * 0.6)
	_curve.draw_line(Vector2(slot * 0.2, line + well), Vector2(w - slot * 0.2, line + well), Color(WoodUI.PAPER, 0.5), 2.0)
	for i in COST_BARS:
		var bh := well * int(_costs[i]) / top
		var x := slot * (i + 0.5)
		if bh > 0.0:
			var sb := WoodUI.paper(LIT, 0.0, 11 + i, 2.0)
			sb.radius = 6.0
			sb.wobble = 0.8
			_curve.draw_style_box(sb, Rect2(x - bar_w * 0.5, line + well - bh, bar_w, bh))
		for t: Array in [[str(_costs[i]), line + well - bh - 5.0, WoodUI.PAPER],
				[str(i) + ("+" if i == COST_BARS - 1 else ""), h - 4.0, LIT]]:
			var at := Vector2(slot * i, t[1])
			_curve.draw_string_outline(font, at, t[0], HORIZONTAL_ALIGNMENT_CENTER, slot, size_px, 6, WoodUI.INK)
			_curve.draw_string(font, at, t[0], HORIZONTAL_ALIGNMENT_CENTER, slot, size_px, t[2])


func _check_line(parent: Control) -> Label:
	var l := WoodUI.label("", 20, GOOD, 5)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = _wrap_width()
	parent.add_child(l)
	return l


## A filter chip of paper: lit while its filter is on (see _apply_filter).
func _toggle(text: String, icon: Texture2D) -> Button:
	var b := Button.new()
	b.text = text
	b.icon = icon
	b.expand_icon = true
	b.focus_mode = Control.FOCUS_NONE
	b.toggle_mode = true
	var h := roundf(50 * WoodUI.font_scale)
	if Phone.active:
		h = maxf(h, Phone.TOUCH)
	b.custom_minimum_size = Vector2(h if text == "" else 0.0, h)
	b.add_theme_font_override("font", WoodUI.letters(true, WoodUI.fs(21)))
	b.add_theme_font_size_override("font_size", WoodUI.fs(21))
	b.add_theme_constant_override("icon_max_width", roundi(h * 0.66))
	var seed := hash(text + str(icon)) % 61
	for state: String in ["normal", "hover", "pressed", "hover_pressed"]:
		var on := state.contains("pressed")
		var sb := WoodUI.paper(LIT if on else WoodUI.PAPER_DARK, 0.0, seed, 3.0 if on else 2.0)
		sb.radius = 12.0
		sb.content_margin_left = 6 if text == "" else 14
		sb.content_margin_right = 6 if text == "" else 14
		if state.begins_with("hover"):
			sb.fill = sb.fill.lightened(0.12)
		b.add_theme_stylebox_override(state, sb)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(c, WoodUI.INK if c.contains("pressed") else Color(WoodUI.INK, 0.8))
	b.pressed.connect(func(): UI.sfx("select"))
	return b


func _lane_slot(lane: int) -> Control:
	var box := Control.new()
	box.custom_minimum_size = LANE_TILE
	box.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var art := TextureRect.new()
	art.set_anchors_preset(Control.PRESET_FULL_RECT)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(art)
	var icon := TextureRect.new()
	icon.position = Vector2(6, 6)
	icon.size = Vector2(30, 30)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(icon)
	box.gui_input.connect(_on_lane_input.bind(lane))
	box.set_drag_forwarding(func(_at: Vector2): return _drag_lane(box, lane),
		_can_drop_lane, _drop_lane.bind(lane))
	_lanes.append({"art": art, "icon": icon, "box": box})
	return box


func _palette_tile(land: String) -> Control:
	var box := TextureRect.new()
	box.custom_minimum_size = PALETTE_TILE
	box.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	box.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	box.texture = _land_art(land)
	box.tooltip_text = CardDB.land_name(land)
	box.mouse_default_cursor_shape = Control.CURSOR_DRAG
	var icon := TextureRect.new()
	icon.position = Vector2(PALETTE_TILE.x * 0.5 - 13, PALETTE_TILE.y * 0.5 - 13)
	icon.size = Vector2(26, 26)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture = _land_texture(land)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(icon)
	var drag := func(_at: Vector2) -> Variant:
		box.set_drag_preview(_drag_picture(_land_art(land), LANE_TILE * 0.8))
		return {"land": land}
	box.set_drag_forwarding(drag, Callable(), Callable())
	# A tap puts the land on the first lane of another type (dragging is hard with a finger).
	box.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
			if ev.pressed:
				_press_at = ev.global_position
			elif ev.global_position.distance_to(_press_at) < CLICK_SLOP and not TouchInput.long_pressed:
				_press_at = Vector2.INF
				var lane := _lands.find(_lands.filter(func(t): return t != land).front()) \
					if _lands.count(land) < CardDB.LANE_COUNT else 0
				_set_land(lane, land)
				UI.sfx("deal"))
	return box


func _pool_tile(id: String) -> Control:
	var box := Control.new()
	box.custom_minimum_size = TILE
	box.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var art := TextureRect.new()
	art.set_anchors_preset(Control.PRESET_FULL_RECT)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.texture = CardBacks.texture()
	art.material = CardView.SHARP
	box.add_child(art)
	var badge := PanelContainer.new()
	var sb := WoodUI.paper(LIT, 0.0, hash(id) % 59, 3.0)
	sb.radius = 16.0
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	badge.add_theme_stylebox_override("panel", sb)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.anchor_left = 0.5
	badge.anchor_right = 0.5
	badge.anchor_top = 1.0
	badge.anchor_bottom = 1.0
	badge.offset_left = -30
	badge.offset_right = 30
	badge.offset_top = -50
	badge.offset_bottom = -10
	badge.grow_horizontal = Control.GROW_DIRECTION_BOTH
	badge.grow_vertical = Control.GROW_DIRECTION_BEGIN
	box.add_child(badge)
	var count := WoodUI.text("", 24, WoodUI.INK, true)
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.add_child(count)
	box.mouse_entered.connect(_hover.bind(id))
	box.gui_input.connect(_on_card_input.bind(id))
	box.set_meta("kn_remove", _add.bind(id, -1))     # Delete takes a copy out (key_nav.gd)
	box.set_drag_forwarding(func(_at: Vector2): return _drag_card(box, id, "pool"), _can_drop_pool, _drop_pool)
	_tiles[id] = {"box": box, "art": art, "badge": badge, "count": count}
	return box


## A line of the deck: cost, land, name, «−» copies «+».
func _deck_row(id: String) -> Control:
	var d := CardDB.get_def(id)
	var n := int(_deck[id])
	var k := WoodUI.font_scale
	var row := PanelContainer.new()
	var sb := WoodUI.paper(WoodUI.PAPER, 0.0, hash(id) % 89, 2.5)
	sb.radius = 10.0
	sb.content_margin_left = 10
	sb.content_margin_right = 6
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	row.add_theme_stylebox_override("panel", sb)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(h)
	var cost := WoodUI.text(str(int(d["cost"])), 26, WoodUI.INK, true)
	cost.custom_minimum_size = Vector2(24 * k, 0)
	cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cost.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cost.size_flags_vertical = Control.SIZE_FILL
	h.add_child(cost)
	var icon := _land_icon_rect(d["land"])
	icon.custom_minimum_size = Vector2(26, 26) * k
	h.add_child(icon)
	var name_l := WoodUI.text(String(d["name"]), 20, WoodUI.INK, true)
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_l.size_flags_vertical = Control.SIZE_FILL
	name_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_l.custom_minimum_size = Vector2(40, 0)
	h.add_child(name_l)
	var minus := _step_button("−", WoodUI.RED)
	minus.pressed.connect(_add.bind(id, -1))
	h.add_child(minus)
	var full := n >= CardDB.DECK_MAX_COPIES
	var copies := WoodUI.text("×%d" % n, 22, WoodUI.ORANGE.darkened(0.35) if full else WoodUI.INK, true)
	copies.custom_minimum_size = Vector2(36 * k, 0)
	copies.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	copies.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	copies.size_flags_vertical = Control.SIZE_FILL
	h.add_child(copies)
	var plus := _step_button("+", WoodUI.GO)
	plus.disabled = full
	plus.pressed.connect(_add.bind(id, 1))
	h.add_child(plus)

	row.mouse_entered.connect(_hover.bind(id))
	row.gui_input.connect(_on_row_input.bind(id))
	row.set_meta("kn_remove", _add.bind(id, -1))
	row.set_meta("kn_zoom", true)                    # Enter shows the card big
	row.set_drag_forwarding(func(_at: Vector2): return _drag_card(row, id, "deck"), _can_drop_deck, _drop_deck)
	return row


func _step_button(s: String, color: Color) -> Button:
	var b := WoodUI.button(s, color, 26, Vector2(46, 42))
	for st in ["normal", "hover", "pressed", "disabled"]:
		var sb: StyleBox = b.get_theme_stylebox(st)
		sb.content_margin_left = 4
		sb.content_margin_right = 4
	b.focus_mode = Control.FOCUS_NONE
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return b


## The line at the bottom that says what has just happened; it fades away.
func _make_toast() -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", WoodUI.card(WoodUI.PAPER, 0.0, 13))
	var sb: StyleBox = p.get_theme_stylebox("panel")
	sb.content_margin_left = 26
	sb.content_margin_right = 26
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.anchor_left = 0.5
	p.anchor_right = 0.5
	p.anchor_top = 1.0
	p.anchor_bottom = 1.0
	p.offset_bottom = -34
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	p.grow_vertical = Control.GROW_DIRECTION_BEGIN
	p.visible = false
	_status = WoodUI.text("", 24, WoodUI.INK, true)
	p.add_child(_status)
	return p


# ================================================================ windows over the builder

## A felt window in the middle, over a dimmed builder; a tap beside it closes it.
func _open_popup(title: String) -> VBoxContainer:
	_close_popup()
	_popup = Control.new()
	_popup.name = "Popup"
	_popup.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_popup)
	var dim := ColorRect.new()
	dim.color = Color(0.07, 0.04, 0.02, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed and not TouchInput.long_pressed:
			_close_popup())
	_popup.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_popup.add_child(center)
	var win := PanelContainer.new()
	win.add_theme_stylebox_override("panel", WoodUI.window(30, 24))
	center.add_child(win)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	win.add_child(v)
	if title != "":
		var tag := WoodUI.title_tag(title, 32)
		tag.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		v.add_child(tag)
	return v


func _close_popup() -> void:
	if _popup != null and is_instance_valid(_popup):
		_popup.queue_free()
	_popup = null
	_inspect_id = ""
	_inspect_pic = null
	_inspect_count = null
	_inspect_plus = null


func _popup_buttons(parent: Control, items: Array) -> void:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	parent.add_child(row)
	for it: Array in items:
		var b := WoodUI.button(it[0], it[1], 24, Vector2(160, 56))
		b.pressed.connect(it[2])
		row.add_child(b)


## A list that scrolls when it is taller than the room the window has.
func _popup_list(parent: Control, list: Control, width: float, rows: int, row_h: float) -> void:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var room := maxf(row_h, size.y - 300.0 * WoodUI.font_scale)
	scroll.custom_minimum_size = Vector2(width, minf(rows * row_h, room))
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	parent.add_child(scroll)


## The saved decks: a tap opens one, «Удалить» twice removes it; new deck and files below.
func _show_decks() -> void:
	var v := _open_popup("Колоды")
	var entries := CustomDecks.load_all()
	var k := WoodUI.font_scale
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 8)
	for e: Dictionary in entries:
		list.add_child(_saved_row(e))
	if entries.is_empty():
		var none := WoodUI.label("Сохранённых колод пока нет", 26, WoodUI.PAPER, 6)
		none.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		list.add_child(none)
	_popup_list(v, list, minf(760.0 * k, size.x - 120.0), maxi(1, entries.size()), 70.0 * k)
	_popup_buttons(v, [["Новая", WoodUI.GO, _on_new], ["Из файла", WoodUI.ORANGE, _on_import],
		["В файл", WoodUI.ORANGE, _on_export], ["Закрыть", WoodUI.VIOLET, _close_popup]])


func _saved_row(e: Dictionary) -> Control:
	var deck_name := String(e.get("name", "?"))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	var draft := not CardDB.has_hero(CustomDecks.code_of(e))
	var open := WoodUI.tab(deck_name + (" · черновик" if draft else ""), 24, Vector2(0, 60))
	WoodUI.set_tab(open, true)
	open.alignment = HORIZONTAL_ALIGNMENT_LEFT
	open.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	open.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	open.pressed.connect(func():
		_close_popup()
		_load_state(deck_name, e.get("lands", []), e.get("deck", {}), String(e.get("hero", "")))
		_say("Открыта: «%s»" % _name))
	h.add_child(open)
	var del := WoodUI.button("Удалить", WoodUI.RED, 22, Vector2(150, 60))
	del.pressed.connect(func():
		if del.text != "Точно?":
			del.text = "Точно?"
			return
		CustomDecks.remove(deck_name)
		_show_decks()
		_say("Колода «%s» удалена" % deck_name))
	h.add_child(del)
	return h


## The sets to show cards of.
func _show_sets() -> void:
	_set_btn.set_pressed_no_signal(_set_filter != "")
	var v := _open_popup("Набор")
	var k := WoodUI.font_scale
	var cols := 3 if size.x >= 1500.0 * k else 2
	var grid := GridContainer.new()
	grid.columns = cols
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	var w := floorf(minf(400.0 * k, (size.x - 160.0 - 10.0 * (cols - 1)) / cols))
	for e: Array in SETS:
		var b := WoodUI.tab(e[1], 22, Vector2(w / k, 56))
		b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		WoodUI.set_tab(b, e[0] == _set_filter)
		var key: String = e[0]
		b.pressed.connect(func():
			_set_filter = key
			_close_popup()
			_apply_filter())
		grid.add_child(b)
	_popup_list(v, grid, w * cols + 10.0 * (cols - 1), ceili(float(SETS.size()) / cols), 66.0 * k)
	_popup_buttons(v, [["Закрыть", WoodUI.VIOLET, _close_popup]])


## The card big, with its copies in the deck: for the right button or a held finger.
func _inspect(id: String) -> void:
	_hover(id)
	var v := _open_popup("")
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 26)
	v.add_child(h)
	_inspect_pic = TextureRect.new()
	_inspect_pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_inspect_pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_inspect_pic.material = CardView.SHARP
	var tex := _best_tex(id)
	_inspect_pic.texture = tex if tex != null else CardBacks.texture()
	var wide: bool = CardDB.get_def(id)["kind"] == "teamwork"
	var tall := size.y - 120.0
	# A tall screen (a phone held upright): the card leaves the room of the side at its right.
	tall = minf(tall, (size.x - 330.0 * WoodUI.font_scale - 160.0) * TILE.y / TILE.x)
	var pic_size := Vector2(tall * TILE.x / TILE.y, tall)
	if wide:
		pic_size = Vector2(minf(size.x * 0.55, tall * TILE.y / TILE.x), 0)
		pic_size.y = pic_size.x * TILE.x / TILE.y
	_inspect_pic.custom_minimum_size = pic_size
	h.add_child(_inspect_pic)
	var side := VBoxContainer.new()
	side.alignment = BoxContainer.ALIGNMENT_CENTER
	side.add_theme_constant_override("separation", 18)
	h.add_child(side)
	var name_l := WoodUI.label(String(CardDB.get_def(id)["name"]), 30, WoodUI.PAPER, 7)
	name_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_l.custom_minimum_size = Vector2(280 * WoodUI.font_scale, 0)
	side.add_child(name_l)
	var counts := HBoxContainer.new()
	counts.alignment = BoxContainer.ALIGNMENT_CENTER
	counts.add_theme_constant_override("separation", 14)
	side.add_child(counts)
	var minus := WoodUI.button("−", WoodUI.RED, 34, Vector2(72, 66))
	minus.pressed.connect(_add.bind(id, -1))
	counts.add_child(minus)
	_inspect_count = WoodUI.label("", 34, LIT, 8)
	_inspect_count.custom_minimum_size = Vector2(70 * WoodUI.font_scale, 0)
	_inspect_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	counts.add_child(_inspect_count)
	_inspect_plus = WoodUI.button("+", WoodUI.GO, 34, Vector2(72, 66))
	_inspect_plus.pressed.connect(_add.bind(id, 1))
	counts.add_child(_inspect_plus)
	var close := WoodUI.button("Закрыть", WoodUI.VIOLET, 26, Vector2(200, 60))
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(_close_popup)
	side.add_child(close)
	_inspect_id = id
	_show_inspect_count()


func _show_inspect_count() -> void:
	if _inspect_count == null or not is_instance_valid(_inspect_count):
		return
	var n := int(_deck.get(_inspect_id, 0))
	_inspect_count.text = "×%d" % n
	_inspect_plus.disabled = n >= CardDB.DECK_MAX_COPIES


# ================================================================ mouse

## A click adds a copy; the right button (a held finger) shows the card big.
func _on_card_input(ev: InputEvent, id: String) -> void:
	if not ev is InputEventMouseButton:
		return
	var mb := ev as InputEventMouseButton
	if mb.button_index == MOUSE_BUTTON_LEFT:
		if mb.pressed:
			_press_at = mb.global_position
		elif mb.global_position.distance_to(_press_at) < CLICK_SLOP and not TouchInput.long_pressed:
			_press_at = Vector2.INF
			_hover(id)
			_add(id, 1)
	elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
		_inspect(id)


## A deck line: the right button (a held finger) shows the card big.
func _on_row_input(ev: InputEvent, id: String) -> void:
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_RIGHT and ev.pressed:
		_inspect(id)
	elif ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and not ev.pressed:
		_hover(id)


## A click turns the lane to the next land (the right button: the previous one).
func _on_lane_input(ev: InputEvent, lane: int) -> void:
	if not ev is InputEventMouseButton:
		return
	var mb := ev as InputEventMouseButton
	if mb.pressed:
		_press_at = mb.global_position
	elif mb.global_position.distance_to(_press_at) < CLICK_SLOP:
		_press_at = Vector2.INF
		var types := CardDB.land_types()
		var step := 1 if mb.button_index == MOUSE_BUTTON_LEFT and not TouchInput.long_pressed else -1
		_set_land(lane, types[(types.find(_lands[lane]) + step + types.size()) % types.size()])
		UI.sfx("select")


func _hover(id: String) -> void:
	_preview_id = id
	var tex := _best_tex(id)
	_preview.texture = tex if tex != null else CardBacks.texture()
	_preview.modulate = Color.WHITE if tex != null else Color(1, 1, 1, 0.35)


func _drag_card(source: Control, id: String, from: String) -> Variant:
	var tex := _card_tex(id)
	source.set_drag_preview(_drag_picture(tex if tex != null else CardBacks.texture(), TILE * 0.9))
	return {"card": id, "from": from}


func _drag_lane(source: Control, lane: int) -> Variant:
	source.set_drag_preview(_drag_picture(_land_art(_lands[lane]), LANE_TILE * 0.8))
	return {"lane": lane}


## The picture that follows the mouse while dragging, centred on it.
func _drag_picture(tex: Texture2D, size: Vector2) -> Control:
	var holder := Control.new()
	var pic := TextureRect.new()
	pic.texture = tex
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.size = size
	pic.position = -size * 0.5
	pic.modulate = Color(1, 1, 1, 0.9)
	holder.add_child(pic)
	return holder


func _can_drop_deck(_at: Vector2, data: Variant) -> bool:
	return data is Dictionary and data.get("from") == "pool"


func _drop_deck(_at: Vector2, data: Variant) -> void:
	_add(String(data["card"]), 1)


func _can_drop_pool(_at: Vector2, data: Variant) -> bool:
	return data is Dictionary and data.get("from") == "deck"


func _drop_pool(_at: Vector2, data: Variant) -> void:
	_add(String(data["card"]), -1)


func _can_drop_lane(_at: Vector2, data: Variant) -> bool:
	return data is Dictionary and (data.has("land") or data.has("lane"))


## A land tile takes the lane; another lane swaps places with it.
func _drop_lane(_at: Vector2, data: Variant, lane: int) -> void:
	if data.has("land"):
		_set_land(lane, String(data["land"]))
	else:
		var other := int(data["lane"])
		var mine: String = _lands[lane]
		_set_land(lane, String(_lands[other]))
		_set_land(other, mine)
	UI.sfx("deal")


# ================================================================ deck

func _add(id: String, delta: int) -> void:
	var n := int(_deck.get(id, 0)) + delta
	if n > CardDB.DECK_MAX_COPIES:
		_say("Больше %d копий одной карты нельзя" % CardDB.DECK_MAX_COPIES, true)
		return
	if delta > 0 and _needs_land(id):
		_say("Для карты за 0 нужна земля «%s»" % CardDB.land_name(CardDB.get_def(id)["land"]), true)
		return
	if n < 0:
		return
	if n == 0:
		_deck.erase(id)
	else:
		_deck[id] = n
	UI.sfx("select" if delta > 0 else "click")
	_refresh()


func _set_land(lane: int, land: String) -> void:
	_lands[lane] = land
	_lanes[lane]["art"].texture = _land_art(land)
	_lanes[lane]["icon"].texture = _land_texture(land)
	_lanes[lane]["box"].tooltip_text = CardDB.land_name(land)
	_refresh()


func _refresh() -> void:
	var total := 0
	var kinds := {}
	_costs.fill(0)
	for id in _deck:
		var n := int(_deck[id])
		var d := CardDB.get_def(id)
		total += n
		kinds[d["kind"]] = int(kinds.get(d["kind"], 0)) + n
		_costs[mini(int(d["cost"]), COST_BARS - 1)] += n
	_total = total
	for id: String in _tiles:
		var n := int(_deck.get(id, 0))
		var badge: Control = _tiles[id]["badge"]
		badge.visible = n > 0
		_tiles[id]["count"].text = "×%d" % n
		_tiles[id]["art"].modulate = Color.WHITE if _payable(id) else Color(0.5, 0.5, 0.55)

	var scroll := _deck_list.get_parent() as ScrollContainer
	var keep := scroll.scroll_vertical
	for ch in _deck_list.get_children():
		_deck_list.remove_child(ch)
		ch.queue_free()
	for id in _sorted(_deck.keys()):
		_deck_list.add_child(_deck_row(id))
	if _deck.is_empty():
		var empty := WoodUI.label("Нажимай на карты" if OS.has_feature("mobile") or Phone.active else "Перетащи карты сюда", 24,
			Color(WoodUI.PAPER, 0.6), 0)
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		empty.custom_minimum_size = Vector2(0, 120)
		_deck_list.add_child(empty)
	scroll.set_deferred("scroll_vertical", keep)
	_deck_count.text = "%d / %d" % [total, CardDB.DECK_MIN] if total < CardDB.DECK_MIN else str(total)
	_deck_count.label_settings.font_color = GOOD if total >= CardDB.DECK_MIN else WARN
	_tab_deck.text = "Колода · %d" % total
	_progress.queue_redraw()
	_curve.queue_redraw()
	var shown: Array = KINDS.filter(func(k): return k != "teamwork" or int(kinds.get(k, 0)) > 0)
	_kind_line.text = "  ·  ".join(PackedStringArray(shown.map(func(k): return "%s %d" % [KIND_NAMES[k], int(kinds.get(k, 0))])))

	_tint_check(_check_size, total >= CardDB.DECK_MIN, "%d карт, минимум %d" % [total, CardDB.DECK_MIN],
		"Не хватает %d карт до %d" % [CardDB.DECK_MIN - total, CardDB.DECK_MIN])
	var copies_ok := true
	for id in _deck:
		if int(_deck[id]) > CardDB.DECK_MAX_COPIES:
			copies_ok = false
	_tint_check(_check_copies, copies_ok, "Не больше %d копий карты" % CardDB.DECK_MAX_COPIES,
		"Есть карта больше %d раз" % CardDB.DECK_MAX_COPIES)
	var costly := _costly_cards()
	var zero := _zero_without_land()
	if zero > 0:
		_tint_check(_check_cost, false, "", "%d карт за 0 без своей земли" % zero)
	elif costly == 0:
		_tint_check(_check_cost, true, "Землям хватает на все карты", "")
	else:
		_check_cost.text = "! %d карт дороже своих земель" % costly
		_check_cost.label_settings.font_color = WARN
		_check_cost.visible = true
	var over := _over_hero_limit()
	_check_hero.visible = CardDB.HERO_MAX_ATK.has(_hero) and not (over.is_empty() and _short)
	if _check_hero.visible:
		_tint_check(_check_hero, over.is_empty(),
			"Атака существ до %d" % CardDB.HERO_MAX_ATK[_hero],
			"Атака больше %d: %s" % [CardDB.HERO_MAX_ATK[_hero], ", ".join(PackedStringArray(over))])
	if _use_btn != null:
		_use_btn.disabled = not CardDB.deck_errors(_lands, _deck).is_empty() or not over.is_empty()
	_show_inspect_count()
	_apply_filter()


## A rule check; on a low screen only the broken ones are shown.
func _tint_check(l: Label, ok: bool, good_text: String, bad_text: String) -> void:
	l.text = ("✓ " if ok else "✗ ") + (good_text if ok else bad_text)
	l.label_settings.font_color = GOOD if ok else BAD
	l.visible = not (ok and _short)


## Whether the lanes can pay for the card: as many lands of its type as it costs
## (rainbow cards count every land).
func _payable(id: String) -> bool:
	var d := CardDB.get_def(id)
	var have: int = CardDB.LANE_COUNT if d["land"] == RAINBOW else _lands.count(d["land"])
	return int(d["cost"]) <= have and not _needs_land(id)


## A card of printed cost 0 goes into a deck only with a land of its type.
func _needs_land(id: String) -> bool:
	var d := CardDB.get_def(id)
	return int(d["cost"]) == 0 and d["land"] != RAINBOW and not _lands.has(d["land"])


func _zero_without_land() -> int:
	var n := 0
	for id in _deck:
		if _needs_land(id):
			n += int(_deck[id])
	return n


func _costly_cards() -> int:
	var n := 0
	for id in _deck:
		if not _payable(id):
			n += int(_deck[id])
	return n


func _apply_filter() -> void:
	if _grid == null:
		return
	var q := _fold(_search.text.strip_edges())
	var by_name: Array = []
	for id: String in _tiles:
		var d := CardDB.get_def(id)
		var ok: bool = (_land_filter == "" or d["land"] == _land_filter) and (_kind_filter == "" or d["kind"] == _kind_filter) and (_set_filter == "" or d.get("set", "") == _set_filter)
		if ok and _only_payable:
			ok = _payable(id)
		if ok and not q.is_empty():
			var hay: Array = _search_text(id)
			ok = String(hay[1]).contains(q)
			if ok and String(hay[0]).contains(q):
				by_name.append(id)
		_tiles[id]["box"].visible = ok
	_order_pool(by_name)
	for key: String in _land_buttons:
		var b: Button = _land_buttons[key]
		b.set_pressed_no_signal(_only_payable if key == "payable" else key == _land_filter)
	for key: String in _kind_buttons:
		var b: Button = _kind_buttons[key]
		b.set_pressed_no_signal(key == _kind_filter)
	_set_btn.set_pressed_no_signal(_set_filter != "")
	_set_btn.text = "Набор"
	for e: Array in SETS:
		if e[0] == _set_filter and _set_filter != "":
			var t: String = e[1]
			_set_btn.text = t if t.length() <= 18 else t.left(16).strip_edges() + "…"


## Lowered with «ё» as «е», the way the search compares.
static func _fold(t: String) -> String:
	return t.to_lower().replace("ё", "е")


## [name, name + text + type line + land] of a card, made once.
func _search_text(id: String) -> Array:
	if not _haystack.has(id):
		var d := CardDB.get_def(id)
		var name := _fold("%s\n%s" % [d["name"], d.get("en", "")])
		var parts := [name, d.get("text", ""), d.get("flavor", ""), CardDB.type_line(d), CardDB.land_name(d["land"])]
		_haystack[id] = [name, _fold("\n".join(parts))]
	return _haystack[id]


## Cards found by their name go before the ones found by their text.
func _order_pool(by_name: Array) -> void:
	var order := _pool_order
	if not by_name.is_empty():
		var first := {}
		for id in by_name:
			first[id] = true
		order = by_name + _pool_order.filter(func(id): return not first.has(id))
	if order == _grid_order:
		return
	_grid_order = order
	for i in order.size():
		_grid.move_child(_tiles[order[i]]["box"], i)


## As many columns of at least TILE as fit, stretched to the full width.
func _fit_columns() -> void:
	var gap := float(_grid.get_theme_constant("h_separation"))
	var width := _pool_scroll.size.x - 16
	var cols := maxi(1, int((width + gap) / (TILE.x + gap)))
	var w := floorf((width - gap * (cols - 1)) / cols)
	_grid.columns = cols
	for id: String in _tiles:
		var box: Control = _tiles[id]["box"]
		box.custom_minimum_size = Vector2(w, roundf(w * TILE.y / TILE.x))


# ================================================================ pictures

## The card's small copy (big false, for the pool tiles) or full picture (big true); when it
## is not loaded yet it is asked for in the background (_process puts it in place) and this
## returns null.
func _card_tex(id: String, big := false) -> Texture2D:
	_seen[id] = Engine.get_process_frames()
	var cache := _big if big else _thumbs
	if cache.has(id):
		return cache[id]
	var path := CardDB.image_path(id) if big else CardDB.card_thumb(id)
	if DisplayServer.get_name() == "headless":
		var texture: Texture2D = load(path)
		if texture == null:
			return null
		cache[id] = CardView.upright(id, texture)
		return cache[id]
	if not _loading.has(path) and ResourceLoader.load_threaded_request(path) == OK:
		_loading[path] = [id, big]
	return null


## The full picture when it is loaded, else the small copy (null when neither is).
func _best_tex(id: String) -> Texture2D:
	var tex := _card_tex(id, true)
	return tex if tex != null else _card_tex(id)


func _show_tex(id: String, big: bool) -> void:
	if not big and _tiles.has(id) and _tiles[id]["box"].visible:
		_tiles[id]["art"].texture = _thumbs[id]
	if _preview_id == id:
		_hover(id)
	if big and _inspect_id == id and _inspect_pic != null and is_instance_valid(_inspect_pic):
		_inspect_pic.texture = _big[id]
	elif not big and _inspect_id == id and _inspect_pic != null and is_instance_valid(_inspect_pic) \
			and not _big.has(id):
		_inspect_pic.texture = _thumbs[id]


## Drops the pictures not needed for the longest time: the small copies beyond THUMB_KEEP and
## the full pictures beyond BIG_KEEP (the card in the preview and the one shown big stay).
func _trim_textures() -> void:
	_trim(_thumbs, THUMB_KEEP, true)
	_trim(_big, BIG_KEEP, false)


func _trim(cache: Dictionary, keep: int, small: bool) -> void:
	if cache.size() <= keep:
		return
	var ids := cache.keys()
	ids.sort_custom(func(a, b): return int(_seen.get(a, 0)) < int(_seen.get(b, 0)))
	for id: String in ids.slice(0, cache.size() - keep):
		if _deck.has(id) or id == _preview_id or id == _inspect_id:
			continue
		cache.erase(id)
		if small and _tiles.has(id):
			_tiles[id]["art"].texture = CardBacks.texture()


## Symbol of a land type; rainbow has none, so its cards show an empty slot.
func _land_icon_rect(land: String) -> TextureRect:
	var r := TextureRect.new()
	r.custom_minimum_size = Vector2(34, 34)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.texture = _land_texture(land)
	return r


func _land_texture(land: String) -> Texture2D:
	var path := "res://assets/ui/symbol_%s.png" % land
	return load(path) if ResourceLoader.exists(path) else null


## The picture of a land tile on the table.
func _land_art(land: String) -> Texture2D:
	var path := "res://assets/lands/%s_1.png" % land
	return load(path) if ResourceLoader.exists(path) else null


# ================================================================ the hero

## The hero at the top of the deck column: its card, name, lands, ability and «Сменить».
## A tap on it shows the hero big; the mouse over it puts its card in the preview.
func _hero_strip() -> Control:
	var k := WoodUI.font_scale
	var box := PanelContainer.new()
	box.name = "HeroStrip"
	var sb := WoodUI.paper(WoodUI.PAPER, 0.0, 7, 2.5)
	sb.radius = 12.0
	sb.content_margin_left = 8
	sb.content_margin_right = 10
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	box.add_theme_stylebox_override("panel", sb)
	box.mouse_filter = Control.MOUSE_FILTER_STOP
	box.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(h)
	_hero_pic = TextureRect.new()
	_hero_pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_hero_pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_hero_pic.material = CardView.SHARP
	_hero_pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hero_pic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(_hero_pic)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(v)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(top)
	var names := VBoxContainer.new()
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.add_theme_constant_override("separation", 0)
	names.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(names)
	_hero_name = WoodUI.text("", 24, WoodUI.INK, true)
	_hero_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_hero_name.custom_minimum_size = Vector2(40, 0)
	names.add_child(_hero_name)
	_hero_lands = HBoxContainer.new()
	_hero_lands.add_theme_constant_override("separation", 3)
	_hero_lands.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hero_lands.custom_minimum_size = Vector2(0, roundf(24 * k))
	names.add_child(_hero_lands)
	_hero_btn = WoodUI.button("Сменить", WoodUI.BLUE, 20, Vector2(0, 46))
	_hero_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_hero_btn.focus_mode = Control.FOCUS_NONE
	_hero_btn.pressed.connect(_show_heroes)
	top.add_child(_hero_btn)
	_hero_text = WoodUI.text("", 16, Color(WoodUI.INK, 0.85))
	_hero_text.label_settings.font = WoodUI.letters(false, WoodUI.fs(16), true)
	_hero_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hero_text.max_lines_visible = 2
	_hero_text.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_hero_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(_hero_text)
	_hero_box = box
	_fit_hero_strip()
	box.mouse_entered.connect(_hover_hero)
	box.gui_input.connect(func(ev: InputEvent):
		if not ev is InputEventMouseButton:
			return
		var mb := ev as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			_open_hero()
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_press_at = mb.global_position
			elif mb.global_position.distance_to(_press_at) < CLICK_SLOP:
				_press_at = Vector2.INF
				_open_hero())
	return box


## The card of the strip and the width of its ability line; a low screen goes without it.
func _fit_hero_strip() -> void:
	if _hero_pic == null:
		return
	var k := WoodUI.font_scale
	var pic := Vector2(66, 88) * (0.82 if _short else 1.0) * k
	_hero_pic.custom_minimum_size = pic.round()
	_hero_text.custom_minimum_size.x = maxf(80.0, _wrap_width() - pic.x - 30.0)
	_hero_text.max_lines_visible = 2
	_hero_text.visible = _hero != "" and not _short     # a low screen: the deck list keeps the room


## The hero the deck is built for ("" none): the strip shows it, the checks follow its limit.
func _set_hero(id: String) -> void:
	_hero = id
	if _hero_box == null:
		return
	for ch in _hero_lands.get_children():
		_hero_lands.remove_child(ch)
		ch.queue_free()
	if id == "":
		_hero_name.text = "Герой не выбран"
		_hero_text.text = ""
		_hero_text.visible = false
		_hero_btn.text = "Выбрать"
		_hero_pic.texture = CardBacks.texture()
		_hero_pic.modulate = Color(1, 1, 1, 0.5)
		return
	var hc := CardDB.hero_card(id)
	_hero_name.text = String(hc["name"])
	_hero_text.text = String(hc["text"])
	_hero_text.visible = not _short
	_hero_btn.text = "Сменить"
	var deck: String = hc.get("deck", "")
	if deck != "":
		for t: String in CardDB.hero(deck)["lands"]:
			var r := _land_icon_rect(t)
			r.custom_minimum_size = Vector2(24, 24) * WoodUI.font_scale
			_hero_lands.add_child(r)
	else:
		var any := WoodUI.text("Любая колода", 16, Color(WoodUI.INK, 0.7))
		_hero_lands.add_child(any)
	_hero_pic.modulate = Color.WHITE
	_hero_pic.texture = _hero_best(id, false)
	if not _hero_rects.has(_hero_pic):
		_hero_rects.append(_hero_pic)


## A tap on the strip: the hero big, or the heroes when none is chosen.
func _open_hero() -> void:
	if _hero == "":
		_show_heroes()
	else:
		_show_hero(_hero)


## The hero's card in the preview at the left.
func _hover_hero() -> void:
	if _hero == "":
		return
	_preview_id = "hero:" + _hero
	_preview.texture = _hero_best(_hero, true)
	_preview.modulate = Color.WHITE


## Every hero card to pick from: its picture, name and the lands of its deck.
func _show_heroes() -> void:
	var v := _open_popup("Герои")
	var k := WoodUI.font_scale
	var pic := (Vector2(120, 160) * lerpf(1.0, k, 0.6)).round()
	var tile := Vector2(pic.x + 16.0, pic.y + roundf(78 * k) + 16.0)
	var gap := 10.0
	var width := minf(1180.0 * k, size.x - 140.0)
	var cols := maxi(2, int((width - 20.0 + gap) / (tile.x + gap)))
	width = cols * tile.x + (cols - 1) * gap + 20.0
	var grid := GridContainer.new()
	grid.name = "HeroGrid"
	grid.columns = cols
	grid.add_theme_constant_override("h_separation", int(gap))
	grid.add_theme_constant_override("v_separation", int(gap))
	for id: String in CardDB.hero_card_ids():
		grid.add_child(_hero_tile(id, pic, tile))
	_popup_list(v, grid, width, ceili(float(CardDB.hero_card_ids().size()) / cols), tile.y + gap)
	_popup_buttons(v, [["Закрыть", WoodUI.VIOLET, _close_popup]])


func _hero_tile(id: String, pic_size: Vector2, tile: Vector2) -> Control:
	var hc := CardDB.hero_card(id)
	var b := Button.new()
	b.name = "Hero_" + id
	b.custom_minimum_size = tile
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for state: String in ["normal", "hover", "pressed", "hover_pressed"]:
		var sb := WoodUI.paper(LIT if id == _hero else WoodUI.PAPER, 0.0, hash(id) % 53, 4.0 if id == _hero else 2.0)
		sb.radius = 10.0
		if state.begins_with("hover"):
			sb.fill = sb.fill.lightened(0.15)
		b.add_theme_stylebox_override(state, sb)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.offset_left = 8
	col.offset_top = 8
	col.offset_right = -8
	col.offset_bottom = -6
	col.add_theme_constant_override("separation", 2)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(col)
	var pic := TextureRect.new()
	pic.custom_minimum_size = pic_size
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.material = CardView.SHARP
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pic.set_meta("hero", id)
	pic.texture = _hero_best(id, false)
	_hero_rects.append(pic)
	col.add_child(pic)
	var name_l := WoodUI.text(String(hc["name"]), 16, WoodUI.INK, true)
	name_l.label_settings.font = WoodUI.letters(true, WoodUI.fs(16), true)
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_l.max_lines_visible = 2
	name_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_l.custom_minimum_size = Vector2(pic_size.x, 0)
	name_l.size_flags_vertical = Control.SIZE_EXPAND_FILL
	name_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(name_l)
	var lands := HBoxContainer.new()
	lands.alignment = BoxContainer.ALIGNMENT_CENTER
	lands.add_theme_constant_override("separation", 2)
	lands.custom_minimum_size = Vector2(0, roundf(20 * WoodUI.font_scale))
	lands.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(lands)
	var deck: String = hc.get("deck", "")
	if deck != "":
		for t: String in CardDB.hero(deck)["lands"]:
			var r := _land_icon_rect(t)
			r.custom_minimum_size = Vector2(20, 20) * WoodUI.font_scale
			lands.add_child(r)
	b.pressed.connect(func():
		UI.sfx("select")
		_show_hero(id))
	return b


## One hero big: its card, name, lands and ability; «Выбрать» builds the deck for it,
## «Копия колоды» opens a copy of its own deck to edit.
func _show_hero(id: String) -> void:
	var hc := CardDB.hero_card(id)
	var deck: String = hc.get("deck", "")
	var v := _open_popup("")
	var k := WoodUI.font_scale
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 26)
	v.add_child(h)
	var tall := minf(size.y - 120.0, 760.0 * k)
	var side_w := roundf(minf(440.0 * k, size.x - 200.0 - tall * 0.75))
	if side_w < 260.0 * k:               # a narrow screen: the card gives room to the text
		tall = maxf(200.0, (size.x - 200.0 - 260.0 * k) / 0.75)
		side_w = roundf(260.0 * k)
	var pic := TextureRect.new()
	pic.name = "HeroPicture"
	pic.custom_minimum_size = Vector2(tall * 0.75, tall).round()
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.material = CardView.SHARP
	pic.set_meta("hero", id)
	pic.set_meta("full", true)
	pic.texture = _hero_best(id, true)
	_hero_rects.append(pic)
	h.add_child(pic)
	var side := VBoxContainer.new()
	side.alignment = BoxContainer.ALIGNMENT_CENTER
	side.add_theme_constant_override("separation", 14)
	side.custom_minimum_size = Vector2(side_w, 0)
	h.add_child(side)
	var name_l := WoodUI.label(String(hc["name"]), 32, WoodUI.PAPER, 7)
	name_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_l.custom_minimum_size = Vector2(side_w, 0)
	side.add_child(name_l)
	if deck != "":
		var lands := HBoxContainer.new()
		lands.alignment = BoxContainer.ALIGNMENT_CENTER
		lands.add_theme_constant_override("separation", 6)
		side.add_child(lands)
		for t: String in CardDB.hero(deck)["lands"]:
			var r := _land_icon_rect(t)
			r.custom_minimum_size = Vector2(36, 36) * k
			r.tooltip_text = CardDB.land_name(t)
			lands.add_child(r)
	else:
		var any := WoodUI.label("Любая колода", 22, LIT, 5)
		any.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		side.add_child(any)
	# The ability on paper; a long one scrolls in the room the buttons leave.
	var note := PanelContainer.new()
	var paper := WoodUI.card(WoodUI.PAPER, 0.0, 5)
	paper.radius = 12.0
	paper.content_margin_left = 14
	paper.content_margin_right = 14
	paper.content_margin_top = 10
	paper.content_margin_bottom = 10
	note.add_theme_stylebox_override("panel", paper)
	side.add_child(note)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	note.add_child(scroll)
	var text := WoodUI.text(String(hc["text"]), 21, WoodUI.INK)
	text.label_settings.font = WoodUI.letters(false, WoodUI.fs(21), true)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.custom_minimum_size = Vector2(side_w - 48.0, 0)
	scroll.add_child(text)
	var buttons := (3 if deck != "" else 2) * (60.0 + 14.0) * k
	var room := tall - name_l.get_combined_minimum_size().y - 50.0 * k - buttons - 40.0
	scroll.custom_minimum_size = Vector2(side_w - 28.0, clampf(text.get_combined_minimum_size().y, 40.0, maxf(40.0, room)))
	var mine := id == _hero
	var pick := WoodUI.button("Выбран" if mine else "Выбрать", WoodUI.GO, 26, Vector2(0, 60))
	pick.disabled = mine
	pick.pressed.connect(func():
		_close_popup()
		_set_hero(id)
		_refresh()
		_hover_hero()
		_say("Герой: %s" % hc["name"]))
	side.add_child(pick)
	if deck != "":
		var copy := WoodUI.button("Копия колоды", WoodUI.ORANGE, 26, Vector2(0, 60))
		copy.pressed.connect(_copy_hero_deck.bind(id))
		side.add_child(copy)
	var back := WoodUI.button("Все герои", WoodUI.VIOLET, 26, Vector2(0, 60))
	back.pressed.connect(_show_heroes)
	side.add_child(back)
	_preview_id = "hero:" + id
	_preview.texture = _hero_best(id, true)
	_preview.modulate = Color.WHITE


## The hero's own deck opens here as an own deck: a copy under a free name, with its lands
## and cards; saving it keeps it with the own decks. The hero's deck does not change.
func _copy_hero_deck(id: String) -> void:
	var deck: String = CardDB.hero_card(id).get("deck", "")
	if deck == "":
		return
	var h := CardDB.hero(deck)
	_close_popup()
	_load_state(_free_name("%s · копия" % h["name"]), (h["lands"] as Array).duplicate(),
		(h["deck"] as Dictionary).duplicate(), id)
	_hover_hero()
	_say("Копия колоды «%s»" % h["name"])


## The name, or the name with a number when a saved deck has it already.
func _free_name(base: String) -> String:
	var taken := {}
	for e in CustomDecks.load_all():
		taken[String(e.get("name", ""))] = true
	base = base.left(CardDB.CUSTOM_NAME_MAX)
	var deck_name := base
	var n := 1
	while taken.has(deck_name):
		n += 1
		deck_name = "%s %d" % [base.left(CardDB.CUSTOM_NAME_MAX - 3), n]
	return deck_name


## The hero saved with the deck of a pick code, "" when it is not saved or has none.
func _saved_hero(code: String) -> String:
	for e in CustomDecks.load_all():
		if CustomDecks.code_of(e) == code:
			return String(e.get("hero", ""))
	return ""


## Creatures of the deck that the hero's limit does not allow (their names in «»).
func _over_hero_limit() -> Array:
	if not CardDB.HERO_MAX_ATK.has(_hero):
		return []
	var top: int = CardDB.HERO_MAX_ATK[_hero]
	var out := []
	for id: String in _sorted(_deck.keys()):
		var d := CardDB.get_def(id)
		if d["kind"] == "creature" and int(d.get("atk", 0)) > top:
			out.append("«%s»" % d["name"])
	return out


## A hero card's picture: the full one (full) or the small copy, whichever is loaded; it is
## asked for in the background, and the card back stands in until one is there.
func _hero_best(id: String, full: bool) -> Texture2D:
	if full and _hero_full.has(id):
		return _hero_full[id]
	if full:
		_hero_load(id, true)
		if _hero_full.has(id):
			return _hero_full[id]
	if _hero_small.has(id):
		return _hero_small[id]
	_hero_load(id, false)
	if _hero_small.has(id):
		return _hero_small[id]
	return CardBacks.texture()


func _hero_load(id: String, full: bool) -> void:
	var path := CardDB.hero_image(id) if full else CardDB.hero_thumb(id)
	if DisplayServer.get_name() == "headless":
		var texture: Texture2D = load(path)
		if texture != null:
			(_hero_full if full else _hero_small)[id] = texture
		return
	if not _hero_loading.has(path) and ResourceLoader.load_threaded_request(path) == OK:
		_hero_loading[path] = [id, full]


## A hero picture has come: it goes to the places waiting for it.
func _show_hero_tex() -> void:
	var waiting := []
	for r in _hero_rects:
		if not is_instance_valid(r):
			continue
		var id: String = _hero if r == _hero_pic else String(r.get_meta("hero", ""))
		if id == "":
			continue
		var full: bool = r.get_meta("full", false)
		r.texture = _hero_best(id, full)
		if not (_hero_full if full else _hero_small).has(id):
			waiting.append(r)
	_hero_rects = waiting
	if _preview_id.begins_with("hero:"):
		_preview.texture = _hero_best(_preview_id.substr(5), true)
	# Full pictures are ~6 MB each: only the chosen hero's and the one shown stay.
	for id: String in _hero_full.keys():
		if _hero_full.size() > 3 and id != _hero and "hero:" + id != _preview_id:
			_hero_full.erase(id)

# ================================================================ saved decks and files

func _on_save() -> void:
	var deck_name := _current_name()
	if not CustomDecks.put(_entry(deck_name)):
		_say("Не удалось записать файл колод", true)
		return
	if CardDB.deck_errors(_lands, _deck).is_empty():
		_say("Сохранено: «%s»" % deck_name)
	else:
		_say("Сохранено как черновик: «%s»" % deck_name, true)


## The deck as it is now goes to a file to send to somebody.
func _on_export() -> void:
	_close_popup()
	var entry := _entry(_current_name())
	FileDialogs.save_file(self, "Сохранить колоду", entry["name"], CustomDecks.EXT, "Колода", func(path: String):
		if CustomDecks.write_file(path, entry):
			_say("Колода в файле: " + path.get_file())
		else:
			_say("Не удалось записать файл", true))


## A deck file from somebody: it joins the saved decks and opens here.
func _on_import() -> void:
	_close_popup()
	FileDialogs.open_file(self, "Открыть колоду", ["*.%s ; Колода" % CustomDecks.EXT], open_file)


func open_file(path: String) -> void:
	var entry := CustomDecks.read_file(path)
	if entry.is_empty():
		_say("Это не файл колоды", true)
		return
	var deck_name := CustomDecks.add(entry)
	if deck_name == "":
		_say("Не удалось записать файл колод", true)
		return
	_load_state(deck_name, entry["lands"], entry["deck"], String(entry.get("hero", "")))
	_say("Колода «%s» добавлена" % deck_name)


func _on_new() -> void:
	_close_popup()
	_load_state(DEFAULT_NAME, ["plain", "plain", "plain", "plain"], {}, _hero)
	_say("Новая колода")


func _on_use() -> void:
	if not CardDB.deck_errors(_lands, _deck).is_empty() or not _over_hero_limit().is_empty():
		return
	var deck_name := _current_name()
	CustomDecks.put(_entry(deck_name))
	picked.emit(CardDB.custom_code(deck_name, _lands, _deck))


func _load_state(deck_name: String, lands: Array, deck: Dictionary, hero := "") -> void:
	_set_hero(hero if CardDB.has_hero_card(hero) else "")
	_name = deck_name
	_name_edit.text = deck_name
	_lands = []
	for i in CardDB.LANE_COUNT:
		var t: String = String(lands[i]) if i < lands.size() else "plain"
		if not CardDB.land_types().has(t):
			t = "plain"
		_lands.append(t)
	_deck = {}
	for id in deck:
		var copies := int(deck[id])
		if CardDB.has_def(id) and copies >= 1:
			_deck[id] = copies
	for i in CardDB.LANE_COUNT:
		_set_land(i, _lands[i])


func _current_name() -> String:
	var deck_name := _name.strip_edges()
	if deck_name.is_empty():
		deck_name = DEFAULT_NAME
	_name = deck_name
	_name_edit.text = deck_name
	return deck_name


func _entry(deck_name: String) -> Dictionary:
	var e := {"name": deck_name, "lands": _lands.duplicate(), "deck": _deck.duplicate()}
	if _hero != "":
		e["hero"] = _hero
	return e


## A short note over the builder (the sandbox could not start, for one).
func say(text: String, bad := false) -> void:
	_say(text, bad)


func _say(text: String, bad := false) -> void:
	_status.text = text
	_status.label_settings.font_color = WoodUI.RED.darkened(0.25) if bad else WoodUI.INK
	move_child(_toast, -1)
	_toast.visible = true
	_toast.modulate.a = 1.0
	if _toast_tween != null:
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.tween_interval(4.0 if bad else 2.6)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.5)
	_toast_tween.tween_callback(func(): _toast.visible = false)


## Card ids sorted by land (rainbow last), cost and name.
func _sorted(ids: Array) -> Array:
	var out := ids.duplicate()
	out.sort_custom(func(a, b):
		var da := CardDB.get_def(a)
		var db := CardDB.get_def(b)
		var la := _order.find(da["land"])
		var lb := _order.find(db["land"])
		if la != lb:
			return la < lb
		if int(da["cost"]) != int(db["cost"]):
			return int(da["cost"]) < int(db["cost"])
		return String(da["name"]) < String(db["name"]))
	return out
