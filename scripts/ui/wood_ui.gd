extends RefCounted
## The look of the hero selection: Finn and Jake's Card Wars table. A wooden table top, a felt
## mat the cards lie on, paper cards, tags and notes with an outline drawn by hand, soft
## cartoon colours and the hand-lettered Balsamiq Sans.

const UI = preload("res://scripts/ui/ui_kit.gd")
const PaperBox = preload("res://scripts/ui/paper_box.gd")
const Phone = preload("res://scripts/ui/phone.gd")

const BOLD := preload("res://assets/fonts/BalsamiqSans-Bold.ttf")
const REGULAR := preload("res://assets/fonts/BalsamiqSans-Regular.ttf")

const INK := Color(0.23, 0.16, 0.13)              # outlines and text on paper
const PAPER := Color(0.96, 0.92, 0.82)
const PAPER_DARK := Color(0.85, 0.78, 0.64)
const PLANKS := [Color(0.48, 0.32, 0.21), Color(0.53, 0.36, 0.23), Color(0.44, 0.29, 0.19)]
const SEAM := Color(0.24, 0.15, 0.1)
const FELT := Color(0.36, 0.48, 0.35)
const STITCH := Color(0.7, 0.8, 0.62, 0.8)
const GO := Color(0.42, 0.62, 0.31)
const BACK := Color(0.33, 0.55, 0.6)
const VIOLET := Color(0.54, 0.45, 0.68)
const BLUE := Color(0.33, 0.5, 0.68)
const RED := Color(0.74, 0.34, 0.28)
const ORANGE := Color(0.85, 0.58, 0.27)
const GOLD := Color(1.0, 0.84, 0.36)
const FONTS := [0.85, 1.0, 1.15, 1.3]             # «Шрифт» in the settings

## The «Шрифт» setting: every text and button made here is this much bigger.
static var font_scale := 1.0
const STAGE_TOUCH := 116.0         # a phone: the least button of the 1920x1080 stage (board, train)
const STAGE_FONT_MIN := 26         # ... and its least text
static var _lettering := {}        # "bold size" -> its FontVariation (letters)


static func _static_init() -> void:
	# The arrows and other signs Balsamiq Sans does not have come from DejaVu Sans.
	for f: FontFile in [BOLD, REGULAR]:
		f.fallbacks = [UI.FALLBACK_FONT]


## A font size with the «Шрифт» setting.
static func fs(size: float) -> int:
	return roundi(size * font_scale)


## A text size of a menu: on a phone never under Phone.FONT_MIN (docs/MOBILE_UI.md).
static func text_px(size: float) -> int:
	return maxi(fs(size), Phone.FONT_MIN) if Phone.active else fs(size)


## The tails of «р», «у», «д», «ц» and the breve of «й» in Balsamiq Sans reach past the
## height the font gives its line, and a label that trims its text with «…» cuts off what
## sticks out: the font gets that room above and below its line.
## `tight`: less room, for texts of several lines (the room comes between every two lines).
static func letters(bold: bool, size: int, tight := false) -> Font:
	var key := "%s %d %s" % [bold, size, tight]
	if not _lettering.has(key):
		var v := FontVariation.new()
		v.base_font = BOLD if bold else REGULAR
		v.spacing_top = ceili(size * (0.03 if tight else 0.06))
		v.spacing_bottom = ceili(size * (0.1 if tight else 0.2))
		_lettering[key] = v
	return _lettering[key]


## A paper box: `fill` with a hand-drawn outline; margin is the room inside it.
static func paper(fill := PAPER, margin := 12.0, seed := 0, line_width := 3.0, line := INK) -> PaperBox:
	var sb := PaperBox.new()
	sb.fill = fill
	sb.line = line
	sb.line_width = line_width
	sb.seed = seed
	sb.set_content_margin_all(margin)
	return sb


## A paper box lying on the table: it casts a soft shadow.
static func card(fill := PAPER, margin := 12.0, seed := 0) -> PaperBox:
	var sb := paper(fill, margin, seed)
	sb.shadow = Vector2(3, 5)
	sb.shadow_color = Color(0.1, 0.05, 0.02, 0.35)
	return sb


## The felt mat the cards lie on, with a seam along its edge.
static func mat() -> PaperBox:
	var sb := card(FELT, 14.0, 3)
	sb.radius = 20.0
	sb.stitch = STITCH
	return sb


static func text(s: String, size: int, color := INK, bold := false, outline := 0) -> Label:
	var l := UI.label(s, text_px(size), color, outline, letters(bold, text_px(size)))
	l.label_settings.outline_color = INK
	l.label_settings.shadow_color.a = 0.0
	return l


## UI.label in this look, with the same arguments: the body font (UI.UI_FONT) becomes Balsamiq
## Sans, the display font its bold, the outline is ink. `scaled` false keeps the size off the
## «Шрифт» setting (texts placed on the fixed 1920x1080 table).
static func label(s: String, size := 28, color := Color.WHITE, outline := 8, font: Font = null, scaled := true) -> Label:
	var px := text_px(size) if scaled else size
	var l := UI.label(s, px, color, mini(outline, maxi(4, roundi(px * 0.22))) if outline > 0 else 0,
		letters(font != UI.UI_FONT, px, true))
	l.label_settings.line_spacing = -ceilf(px * 0.06)
	l.label_settings.outline_color = INK
	l.label_settings.shadow_color = Color(INK, 0.45)
	l.label_settings.shadow_offset = Vector2(0, 2)
	if outline == 0:
		l.label_settings.shadow_color.a = 0.0
	return l


## button and label on the fixed 1920x1080 table (the board, the train): off the «Шрифт» setting.
## A phone: the stage is the screen's height (1080 units ≈ the screen's pixels at 1080), so the
## least sizes are Phone.TOUCH and Phone.FONT_MIN times Phone.SCALE (docs/MOBILE_UI.md).
static func button_fixed(s: String, color: Color, size := 26, min_size := Vector2(0, 58)) -> Button:
	if Phone.active:
		size = maxi(size, STAGE_FONT_MIN)
		min_size = min_size.max(Vector2(STAGE_TOUCH, STAGE_TOUCH))
	return button(s, color, size, min_size, false)


static func label_fixed(s: String, size := 28, color := Color.WHITE, outline := 8, font: Font = null) -> Label:
	return label(s, maxi(size, STAGE_FONT_MIN) if Phone.active else size, color, outline, font, false)


## The bright colours of the old menus, softened to the paper ones of the table.
static func tone(c: Color) -> Color:
	if c == UI.RED:
		return RED
	if c == UI.ORANGE:
		return ORANGE
	if c == UI.GREEN:
		return GO
	if c == UI.BLUE:
		return BLUE
	if c == UI.PURPLE:
		return VIOLET
	if [GO, BACK, VIOLET, BLUE, RED, ORANGE, PAPER, PAPER_DARK, FELT].has(c) or c.s < 0.3:
		return c
	return Color.from_hsv(c.h, c.s * 0.72, minf(c.v, 0.82))


## A window over the table: a felt mat with a seam, its title is a paper tag (title_tag).
static func window(h := 34.0, v := 26.0) -> PaperBox:
	var sb := card(FELT, 0.0, 7)
	sb.radius = 22.0
	sb.line_width = 4.0
	sb.stitch = STITCH
	sb.stitch_inset = 9.0
	sb.shadow = Vector2(5, 9)
	sb.shadow_color = Color(0.05, 0.02, 0.0, 0.5)
	sb.content_margin_left = h
	sb.content_margin_right = h
	sb.content_margin_top = v
	sb.content_margin_bottom = v
	return sb


## A darker patch of felt inside a window: a column, a row of a list.
static func inset(seed := 0, h := 18.0, v := 12.0) -> PaperBox:
	var sb := paper(FELT.darkened(0.25), 0.0, seed, 2.5)
	sb.radius = 14.0
	sb.content_margin_left = h
	sb.content_margin_right = h
	sb.content_margin_top = v
	sb.content_margin_bottom = v
	return sb


## A dark wooden plate with an edge of `edge`: the panels of the train (doors, items, perks).
static func plate(edge: Color, width := 3.0, seed := 0, radius := 18.0) -> PaperBox:
	var sb := paper(Color(0.24, 0.17, 0.12, 0.96), 0.0, seed, maxf(2.0, width), tone(edge))
	sb.radius = radius
	sb.shadow = Vector2(3, 6)
	sb.shadow_color = Color(0.05, 0.02, 0.0, 0.45)
	return sb


## A text field (LineEdit, TextEdit): a paper strip with ink letters.
static func edit(e: Control, size := 28) -> void:
	e.add_theme_font_override("font", BOLD)
	e.add_theme_font_size_override("font_size", text_px(size))
	e.add_theme_color_override("font_color", INK)
	e.add_theme_color_override("font_placeholder_color", Color(INK, 0.4))
	e.add_theme_color_override("caret_color", INK)
	e.add_theme_color_override("selection_color", Color(ORANGE, 0.45))
	for st in ["normal", "focus", "read_only"]:
		var sb := paper(PAPER if st != "read_only" else PAPER_DARK, 0.0, 9, 4.0 if st == "focus" else 3.0,
			ORANGE.darkened(0.2) if st == "focus" else INK)
		sb.radius = 10.0
		sb.content_margin_left = 16
		sb.content_margin_right = 16
		sb.content_margin_top = 6
		sb.content_margin_bottom = 6
		e.add_theme_stylebox_override(st, sb)


## The wooden table top under the whole window: planks with grain, seams and knots.
static func table() -> Control:
	var c := Control.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.draw.connect(func():
		var rng := RandomNumberGenerator.new()
		rng.seed = 11
		var h := 118.0
		var y := -rng.randf() * h
		var i := 0
		while y < c.size.y:
			var col: Color = PLANKS[i % PLANKS.size()]
			c.draw_rect(Rect2(0, y, c.size.x, h), col.lerp(PLANKS[(i + 1) % PLANKS.size()], rng.randf() * 0.4))
			for g in 6:
				var gy := y + rng.randf_range(8.0, h - 8.0)
				var amp := rng.randf_range(1.5, 5.0)
				var f := rng.randf_range(0.003, 0.01)
				var ph := rng.randf() * TAU
				var pts := PackedVector2Array()
				for x in range(-40, int(c.size.x) + 80, 40):
					pts.append(Vector2(x, gy + sin(x * f + ph) * amp))
				c.draw_polyline(pts, Color(SEAM, rng.randf_range(0.12, 0.26)), rng.randf_range(1.0, 2.5), true)
			if rng.randf() < 0.6:
				var k := Vector2(rng.randf_range(0.05, 0.95) * c.size.x, y + h * rng.randf_range(0.35, 0.65))
				c.draw_set_transform(k, 0.0, Vector2(1.0, 0.45))
				for ring in 3:
					c.draw_arc(Vector2.ZERO, 7.0 + ring * 6.0, 0.0, TAU, 24, Color(SEAM, 0.35 - ring * 0.08), 2.0, true)
				c.draw_set_transform(Vector2.ZERO)
			var sx := rng.randf_range(0.15, 0.85) * c.size.x
			c.draw_line(Vector2(sx, y), Vector2(sx, y + h), Color(SEAM, 0.8), 3.0)
			c.draw_line(Vector2(0, y), Vector2(c.size.x, y), SEAM, 4.0)
			c.draw_line(Vector2(0, y + 4), Vector2(c.size.x, y + 4), Color(1, 0.9, 0.7, 0.08), 2.0)
			y += h
			i += 1)
	c.resized.connect(c.queue_redraw)
	# Darker towards the edges, so the eye stays on the middle.
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, 0.0))
	g.set_color(1, Color(0.05, 0.02, 0.0, 0.55))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.05, 1.05)
	var v := TextureRect.new()
	v.texture = tex
	v.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	v.stretch_mode = TextureRect.STRETCH_SCALE
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(v)
	return c


## A paper tag taped to the table, a little askew.
static func title_tag(s: String, size := 34) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := card(PAPER, 0.0, 5)
	sb.tape = true
	sb.content_margin_left = 28
	sb.content_margin_right = 28
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	p.add_theme_stylebox_override("panel", sb)
	p.add_child(text(s, size, INK, true))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.rotation_degrees = -1.5
	p.resized.connect(func(): p.pivot_offset = p.size * 0.5)
	return p


## A wavy line drawn with a marker, under a name; its colour is the meta "color". Drawn as a row
## of round dabs that thin out to the ends, so the line starts and stops softly like a brush.
static func squiggle(color: Color, width := 90.0) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(width, 10)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.set_meta("color", color)
	c.draw.connect(func():
		var w := c.custom_minimum_size.x
		var n := maxi(24, int(w / 1.5))
		for k in n + 1:
			var t := float(k) / n
			var p := Vector2(3.0 + (w - 6.0) * t, 5.0 + sin(t * w / 4.5) * 2.2)
			var r := 0.6 + 1.3 * pow(sin(t * PI), 0.6)     # thick in the middle, thin at the ends
			c.draw_circle(p, r, c.get_meta("color"), true, -1.0, true))
	return c


## A chunky button cut out of coloured paper (the old bright colours are softened by tone).
## `scaled` false keeps it off the «Шрифт» setting (the fixed 1920x1080 table).
static func button(s: String, color: Color, size := 26, min_size := Vector2(0, 58), scaled := true) -> Button:
	color = tone(color)
	var k := font_scale if scaled else 1.0
	var px := roundi(size * k)
	min_size *= k
	if scaled and Phone.active:
		# A phone: a finger presses it (docs/MOBILE_UI.md).
		px = maxi(px, Phone.FONT_MIN)
		min_size = min_size.max(Vector2(Phone.TOUCH, Phone.TOUCH))
	var b := UI.button(s, color, px, min_size)
	b.add_theme_font_override("font", BOLD)
	b.add_theme_color_override("font_outline_color", INK)
	b.add_theme_constant_override("outline_size", 6)
	_paper_states(b, color, hash(s) % 97)
	return b


## The standard "copy" button: no text, two sheets of paper one behind the other.
static func copy_button(color: Color, side := 64) -> Button:
	var k := font_scale
	var b := button("", color, 26, Vector2(side, side) * k)
	b.custom_minimum_size = Vector2(side, side) * k
	var icon := Control.new()
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.draw.connect(func():
		var u := minf(icon.size.x, icon.size.y) / 64.0
		var sheet := Vector2(24, 30) * u
		var back := Vector2(14, 12) * u + (icon.size - Vector2(64, 64) * u) * 0.5
		var front := back + Vector2(12, 12) * u
		for at in [back, front]:
			var r := Rect2(at, sheet)
			icon.draw_rect(r.grow(2.0 * u), INK)
			icon.draw_rect(r, PAPER if at == front else PAPER_DARK))
	icon.resized.connect(icon.queue_redraw)
	b.add_child(icon)
	return b


## The «watch» button: no text, a paper eye (a friend's row: watch their match).
static func eye_button(color: Color, side := 54) -> Button:
	var k := font_scale
	var b := button("", color, 26, Vector2(side, side) * k)
	b.custom_minimum_size = b.custom_minimum_size.max(Vector2(side, side) * k)
	var icon := Control.new()
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.draw.connect(func():
		var u := minf(icon.size.x, icon.size.y) / 64.0
		var c := icon.size * 0.5
		var w := 22.0 * u       # half the width of the eye
		var h := 13.0 * u       # half its height
		var n := 16
		var pts := PackedVector2Array()
		for i in n + 1:         # the upper lid, left to right
			var t := float(i) / n
			pts.append(c + Vector2(-w + 2.0 * w * t, -h * sin(PI * t)))
		for i in range(n - 1, 0, -1):   # the lower lid, back
			var t := float(i) / n
			pts.append(c + Vector2(-w + 2.0 * w * t, h * sin(PI * t)))
		var outline := pts.duplicate()
		outline.append(pts[0])
		icon.draw_colored_polygon(pts, PAPER)
		icon.draw_polyline(outline, INK, 3.0 * u, true)
		icon.draw_circle(c, 8.0 * u, INK, true, -1.0, true)
		icon.draw_circle(c + Vector2(-2.5, -2.5) * u, 2.5 * u, PAPER, true, -1.0, true))
	icon.resized.connect(icon.queue_redraw)
	b.add_child(icon)
	return b


## A step tab: paper, light when it is the current step.
static func tab(s: String, size := 26, min_size := Vector2(210, 52)) -> Button:
	var b := button(s, PAPER, size, min_size)
	b.add_theme_constant_override("outline_size", 0)
	set_tab(b, false)
	return b


static func set_tab(b: Button, on: bool) -> void:
	_paper_states(b, PAPER if on else PAPER_DARK.darkened(0.08), hash(b.text) % 97)
	for state in ["font_color", "font_hover_color", "font_pressed_color"]:
		b.add_theme_color_override(state, INK if on else Color(INK, 0.6))


static func _paper_states(b: Button, color: Color, seed: int) -> void:
	# The capital letters in the middle of the button: in the bigger sizes Balsamiq Sans puts
	# them above the middle of its line (measured: 2 px at 28, 0 at 17), so the text goes a
	# little lower. The dark step under the button is drawn outside it.
	var low := roundi((b.get_theme_font_size("font_size") - 17) * 0.18)
	for state in ["normal", "hover", "pressed", "disabled"]:
		var sb := paper(color, 0.0, seed)
		sb.content_margin_left = 16
		sb.content_margin_right = 16
		sb.content_margin_top = 4 + low
		sb.content_margin_bottom = maxi(0, 4 - low)
		sb.radius = 12.0
		sb.shadow = Vector2(0, 2 if state == "pressed" else 5)
		sb.shadow_color = Color(INK, 0.85)
		match state:
			"hover":
				sb.fill = color.lightened(0.12)
			"pressed":
				sb.fill = color.darkened(0.08)
				sb.content_margin_top = 7 + low          # a pressed button moves its text down
				sb.content_margin_bottom = maxi(0, 1 - low)
			"disabled":
				sb.fill = Color(0.6, 0.57, 0.52)
		b.add_theme_stylebox_override(state, sb)
