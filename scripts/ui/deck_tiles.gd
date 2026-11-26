extends RefCounted
## Deck tiles of the hero selection's second step: a fan of three of the deck's
## cards on its colours, the name and the lands. The card pictures load in
## background threads: a tile shows card backs until `poll` puts the faces in.

const CardDB = preload("res://scripts/core/card_db.gd")
const UI = preload("res://scripts/ui/ui_kit.gd")
const WoodUI = preload("res://scripts/ui/wood_ui.gd")
const CardBacks = preload("res://scripts/ui/card_backs.gd")
const SHARP := preload("res://shaders/sharp.tres")
const SYMBOL := "res://assets/ui/symbol_%s.png"

const FAN_ANGLES := [-9.0, 9.0, 0.0]     # the side cards first, the front card last (on top)
const FAN_SHIFT := [-0.17, 0.17, 0.0]      # x offsets in fan widths

var _pending := {}      # path -> [TextureRect]
var _queue := []        # [TextureRect, path] not asked for yet: asking costs the window ~0.7 ms a picture
const ASK_USEC := 5000  # how long one poll may spend asking


## The cards shown on a deck: creatures first, the most expensive, then the most copies.
static func cover_cards(deck: String) -> Array:
	var cards: Dictionary = CardDB.hero(deck)["deck"]
	var ids: Array = cards.keys().filter(func(id): return CardDB.has_def(id))
	ids.sort_custom(func(a: String, b: String) -> bool:
		var da := CardDB.get_def(a)
		var db := CardDB.get_def(b)
		var ca := int(da["kind"] == "creature")
		var cb := int(db["kind"] == "creature")
		if ca != cb:
			return ca > cb
		if int(da.get("cost", 0)) != int(db.get("cost", 0)):
			return int(da.get("cost", 0)) > int(db.get("cost", 0))
		if int(cards[a]) != int(cards[b]):
			return int(cards[a]) > int(cards[b])
		return a < b)
	return ids.slice(0, 3)


## "Финн: существа 23, заклинания 9, строения 8".
static func summary(deck: String) -> String:
	var counts := {"creature": 0, "spell": 0, "building": 0, "teamwork": 0}
	var cards: Dictionary = CardDB.hero(deck)["deck"]
	for id: String in cards:
		if CardDB.has_def(id):
			counts[CardDB.get_def(id)["kind"]] += int(cards[id])
	var text := "%s: существа %d, заклинания %d, строения %d" % [CardDB.hero(deck)["name"],
		counts["creature"], counts["spell"], counts["building"]]
	if counts["teamwork"] > 0:
		text += ", командные %d" % counts["teamwork"]
	return text


## A deck tile: {panel, ribbon, edit (own decks only)}. deck "" makes the tile of a new own deck.
func tile(deck: String, small: bool) -> Dictionary:
	var fan_size := Vector2(150, 118) if small else Vector2(200, 166)
	var card_size := Vector2(66, 92) if small else Vector2(90, 126)
	var h: Dictionary = CardDB.hero(deck) if deck != "" else {}
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(col)

	var fan := Control.new()
	fan.custom_minimum_size = fan_size
	fan.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(fan)
	var glow_col: Color = Color(h.get("bg", ["#2a2140", "#8a6cc4"])[1]) if deck != "" else Color(0.55, 0.5, 0.75)
	fan.add_child(_glow(glow_col, fan_size))
	var covers: Array = cover_cards(deck) if deck != "" else []
	for i in 3:
		var pic := _card_pic(card_size)
		pic["clip"].position = Vector2(fan_size.x * (0.5 + FAN_SHIFT[i]) - card_size.x * 0.5,
			fan_size.y - card_size.y - (2.0 if i == 2 else 8.0))
		pic["clip"].pivot_offset = Vector2(card_size.x * 0.5, card_size.y)
		pic["clip"].rotation_degrees = FAN_ANGLES[i]
		fan.add_child(pic["clip"])
		if deck == "":
			pic["clip"].modulate = Color(0.5, 0.5, 0.58)
		var slot := 2 - i if covers.size() == 3 else i      # the first cover card goes in front
		if slot < covers.size():
			_want(pic["rect"], CardDB.card_thumb(covers[slot]))
	if deck == "":
		var plus := UI.label("+", 84 if not small else 64, Color.WHITE, 12)
		plus.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		plus.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		plus.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		plus.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fan.add_child(plus)
	# The active hero card's own deck.
	var ribbon := PanelContainer.new()
	var rb := UI.box(Color(1.0, 0.82, 0.3), 9, 0)
	rb.content_margin_left = 8
	rb.content_margin_right = 8
	ribbon.add_theme_stylebox_override("panel", rb)
	ribbon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rl := WoodUI.text("колода героя", 14 if small else 16, WoodUI.INK, true)
	rl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ribbon.add_child(rl)
	ribbon.visible = false
	fan.add_child(ribbon)      # no z_index: it would be drawn over a window opened above the tiles
	ribbon.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE)

	# An own deck can be opened in the builder from here.
	var edit: Button = null
	if CardDB.is_custom(deck):
		edit = WoodUI.button("Изменить", WoodUI.BLUE, 14 if small else 16, Vector2(0, 28 if small else 32))
		fan.add_child(edit)
		edit.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE)

	var name: String = h.get("name", "Новая колода")
	var name_l := WoodUI.text(name, 16 if small else 22, Color.WHITE if deck == "" else CardDB.hero_color(deck).lightened(0.25), true, 6)
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_l.custom_minimum_size = Vector2(fan_size.x, 0)
	name_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(name_l)
	var sym := 18 if small else 24
	var lands := HBoxContainer.new()
	lands.alignment = BoxContainer.ALIGNMENT_CENTER
	lands.add_theme_constant_override("separation", 3)
	lands.custom_minimum_size = Vector2(0, sym)
	lands.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(lands)
	for t in h.get("lands", []):
		var r := TextureRect.new()
		r.texture = load(SYMBOL % t)
		r.custom_minimum_size = Vector2(sym, sym)
		r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lands.add_child(r)
	if deck == "" or h.get("fan", false) or CardDB.is_custom(deck):
		var sub := WoodUI.text("своя колода" if CardDB.is_custom(deck) else ("фан-колода" if deck != "" else "собрать"),
			14, Color(1, 1, 1, 0.7))
		sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if deck == "":
			lands.add_child(sub)
		else:
			col.add_child(sub)

	panel.mouse_entered.connect(func():
		panel.scale = Vector2.ONE * 1.05
		UI.sfx("hover"))
	panel.mouse_exited.connect(func(): panel.scale = Vector2.ONE)
	panel.resized.connect(func(): panel.pivot_offset = panel.size * 0.5)
	return {"panel": panel, "ribbon": ribbon, "edit": edit, "base": Color(h.get("bg", ["#2a2140"])[0]) if deck != "" else Color(0.16, 0.14, 0.24)}


## marks: the seats that play this deck (their colours frame the tile).
static func style(t: Dictionary, marks: Array, colors: Array) -> void:
	var base: Color = t["base"]
	var sb := WoodUI.card(base.darkened(0.45), 0.0, t["panel"].get_index())
	sb.line_width = 2.5
	if not marks.is_empty():
		sb.line = colors[marks[0]] if marks.size() == 1 else Color(0.95, 0.95, 1.0)
		sb.line_width = 5.0
	sb.content_margin_left = 5
	sb.content_margin_right = 5
	sb.content_margin_top = 5
	sb.content_margin_bottom = 6
	t["panel"].add_theme_stylebox_override("panel", sb)


## Puts the loaded card faces in; true when nothing is left to load.
func poll() -> bool:
	var t0 := Time.get_ticks_usec()
	while not _queue.is_empty() and Time.get_ticks_usec() - t0 < ASK_USEC:
		var q: Array = _queue.pop_front()
		if is_instance_valid(q[0]):
			_ask(q[0], q[1])
	for path: String in _pending.keys():
		var state := ResourceLoader.load_threaded_get_status(path)
		if state == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			continue
		var tex: Texture2D = ResourceLoader.load_threaded_get(path) if state == ResourceLoader.THREAD_LOAD_LOADED else null
		for r: TextureRect in _pending[path]:
			if tex != null and is_instance_valid(r):
				r.texture = _trimmed(tex)
		_pending.erase(path)
	return _pending.is_empty() and _queue.is_empty()


## Takes the loads still running so the loader does not keep them.
func drain() -> void:
	for path: String in _pending:
		if ResourceLoader.load_threaded_get_status(path) != ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			ResourceLoader.load_threaded_get(path)
	_pending.clear()
	_queue.clear()


## A face for the tile: at once when it is loaded, otherwise poll asks for it (a few a frame,
## so a page of tiles opens without waiting for ~70 requests).
func _want(r: TextureRect, path: String) -> void:
	if ResourceLoader.has_cached(path):
		r.texture = _trimmed(load(path))
	else:
		_queue.append([r, path])


func _ask(r: TextureRect, path: String) -> void:
	if DisplayServer.get_name() == "headless" or ResourceLoader.has_cached(path):
		r.texture = _trimmed(load(path))
		return
	if not _pending.has(path):
		if ResourceLoader.load_threaded_request(path) != OK:
			return
		_pending[path] = []
	_pending[path].append(r)


## The scanned cards have a rough edge with stepped corners: it is cut off.
static func _trimmed(tex: Texture2D) -> AtlasTexture:
	var trim := tex.get_size() * 0.02
	var at := AtlasTexture.new()
	at.atlas = tex
	at.region = Rect2(trim, tex.get_size() - trim * 2.0)
	return at


## A card picture with round smooth corners, a card back until the face is loaded.
static func _card_pic(sz: Vector2) -> Dictionary:
	var radius := roundi(sz.x * 0.06)
	var clip := Panel.new()
	clip.size = sz
	clip.add_theme_stylebox_override("panel", UI.box(Color.WHITE, radius, 0, Color.WHITE, 6))
	clip.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var r := TextureRect.new()
	r.texture = _trimmed(CardBacks.texture())
	r.material = SHARP
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	clip.add_child(r)
	var rim := Panel.new()
	var rim_box := UI.box(Color.TRANSPARENT, radius, 2, Color(0.08, 0.06, 0.04, 0.85))
	rim_box.draw_center = false
	rim.add_theme_stylebox_override("panel", rim_box)
	rim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	clip.add_child(rim)
	return {"clip": clip, "rect": r}


## A soft round light of the deck's colour behind the fan.
static func _glow(color: Color, sz: Vector2) -> TextureRect:
	var g := Gradient.new()
	g.set_color(0, Color(color, 0.55))
	g.set_color(1, Color(color, 0.0))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.6)
	tex.fill_to = Vector2(0.5, 0.0)
	tex.width = 128
	tex.height = 128
	var r := TextureRect.new()
	r.texture = tex
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.size = sz
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r
