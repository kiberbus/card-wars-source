extends Control
## The mark of a place in the leaderboard. The first three: their pictures (PICTURES: a gold, a silver,
## a bronze crown with the number on it); a game without the pictures gets drawn ones (a gold crown with «1»
## on its band, a silver «2», a bronze «3», cast in metal: a light shine, a dark band, an ink edge).
## A lower place: its plain number.
##   var b := PlaceBadge.make(1, 64)

const UI = preload("res://scripts/ui/ui_kit.gd")
const WoodUI = preload("res://scripts/ui/wood_ui.gd")

## The metals from the top of the shine to its dark band: gold, silver, bronze.
const METALS := [
	[Color(1.0, 0.97, 0.72), Color(1.0, 0.82, 0.25), Color(0.62, 0.4, 0.06)],
	[Color(1.0, 1.0, 1.0), Color(0.8, 0.84, 0.9), Color(0.42, 0.47, 0.55)],
	[Color(1.0, 0.84, 0.66), Color(0.84, 0.52, 0.24), Color(0.45, 0.24, 0.09)],
]
const INK := Color(0.16, 0.1, 0.06)

var place := 0
var side := 64.0


static func make(p_place: int, p_side: float) -> Control:
	var b := new()
	b.place = p_place
	b.side = p_side
	b.custom_minimum_size = Vector2(p_side, p_side)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b


## The metal at a height t of the mark (0 its top, 1 its bottom): light, then a dark band just under
## the middle, then a softer shine at the bottom.
static func metal_at(place_: int, t: float) -> Color:
	var m: Array = METALS[clampi(place_ - 1, 0, 2)]
	if t < 0.48:
		return m[0].lerp(m[1], t / 0.48)
	if t < 0.58:
		return m[1].lerp(m[2], (t - 0.48) / 0.1)
	return m[2].lerp(m[1], minf(1.0, (t - 0.58) / 0.3))


func _draw() -> void:
	var s := minf(size.x, size.y)
	var o := (size - Vector2(s, s)) / 2.0
	var pic := picture(place)
	if pic != null:
		_picture(o, s, pic)
	elif place == 1:
		_crown(o, s)
	elif place == 2 or place == 3:
		_digit(o, s, str(place))
	elif place > 0:
		var font: Font = WoodUI.letters(true, roundi(s * 0.42), true)
		var fs := roundi(s * (0.42 if place < 100 else 0.32))
		var txt := str(place)
		var w := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var at := o + Vector2((s - w) / 2.0, s * 0.5 + fs * 0.36)
		draw_string_outline(font, at, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 6, INK)
		draw_string(font, at, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UI.CREAM)


## The picture of the first three places (PICTURES, from the game's pictures like the rest of assets/),
## null when the game has none: then the mark is drawn here.
static func picture(place_: int) -> Texture2D:
	if place_ < 1 or place_ > 3:
		return null
	if not _pictures.has(place_):
		var path: String = PICTURES % place_
		_pictures[place_] = load(path) if ResourceLoader.exists(path) else null
	return _pictures[place_]


const PICTURES := "res://assets/ui/leaderboard/place%d.png"
static var _pictures := {}


## The picture whole in the square (it carries the number of its place itself).
func _picture(o: Vector2, s: float, pic: Texture2D) -> void:
	var k := minf(s / pic.get_width(), s / pic.get_height())
	var ps := pic.get_size() * k
	draw_texture_rect(pic, Rect2(o + (Vector2(s, s) - ps) / 2.0, ps), false)


## A polygon filled with the metal from y0 to y1 (its points get the colour of their height).
func _metal_poly(pts: PackedVector2Array, y0: float, y1: float) -> void:
	var cols := PackedColorArray()
	for p in pts:
		cols.append(metal_at(place, clampf((p.y - y0) / maxf(1.0, y1 - y0), 0.0, 1.0)))
	draw_polygon(pts, cols)


func _crown(o: Vector2, s: float) -> void:
	var top := o.y + s * 0.1
	var bot := o.y + s * 0.88
	var l := o.x + s * 0.06
	var r := o.x + s * 0.94
	var band := o.y + s * 0.5
	# Five points, the middle one the highest; the band under them.
	var pts := PackedVector2Array([
		Vector2(l, band), Vector2(l - s * 0.02, top + s * 0.08), Vector2(o.x + s * 0.3, o.y + s * 0.32),
		Vector2(o.x + s * 0.5, top - s * 0.02), Vector2(o.x + s * 0.7, o.y + s * 0.32), Vector2(r + s * 0.02, top + s * 0.08),
		Vector2(r, band), Vector2(r, bot), Vector2(l, bot)])
	var shadow := PackedVector2Array()
	for p in pts:
		shadow.append(p + Vector2(0, s * 0.05))
	draw_colored_polygon(shadow, Color(0, 0, 0, 0.35))
	_metal_poly(pts, top, bot)
	var edge := pts.duplicate()
	edge.append(pts[0])
	draw_polyline(edge, INK, maxf(2.0, s * 0.045), true)
	# The band: a line over it, balls on the points.
	draw_line(Vector2(l, band), Vector2(r, band), INK, maxf(1.5, s * 0.03), true)
	for p: Vector2 in [pts[1], pts[3], pts[5]]:
		draw_circle(p, s * 0.06, INK)
		draw_circle(p, s * 0.045, METALS[0][0])
	# Gems on the band at the sides, «1» stamped in its middle.
	for x: float in [o.x + s * 0.19, o.x + s * 0.81]:
		var c := Vector2(x, (band + bot) / 2.0)
		draw_circle(c, s * 0.07, INK)
		draw_circle(c, s * 0.052, Color(0.86, 0.14, 0.2))
		draw_circle(c + Vector2(-s * 0.016, -s * 0.016), s * 0.018, Color(1, 0.75, 0.75))
	var fs := roundi(s * 0.46)
	var font: Font = WoodUI.letters(true, fs, true)
	var w := font.get_string_size("1", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var at := Vector2(o.x + (s - w) / 2.0, (band + bot) / 2.0 + fs * 0.36)
	draw_string_outline(font, at, "1", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, maxi(3, roundi(s * 0.08)), INK)
	draw_string(font, at, "1", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 0.98, 0.86))
	# A glint on the top-left point.
	draw_line(pts[1] + Vector2(s * 0.05, s * 0.1), pts[1] + Vector2(s * 0.09, s * 0.28), Color(1, 1, 1, 0.75), maxf(1.5, s * 0.03), true)


## A big digit of metal: an ink edge and a shadow here, the glyph itself in a child whose shader
## paints it with the metal by height.
func _digit(o: Vector2, s: float, txt: String) -> void:
	var fs := roundi(s * 1.0)
	var font: Font = WoodUI.letters(true, fs, true)
	var w := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var at := o + Vector2((s - w) / 2.0, s * 0.5 + fs * 0.35)
	draw_string_outline(font, at + Vector2(0, s * 0.05), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, roundi(s * 0.16), Color(0, 0, 0, 0.35))
	draw_string_outline(font, at, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, roundi(s * 0.13), INK)
	var fill := _metal_fill()
	fill.set_meta("draw", [font, at, txt, fs])
	var mat: ShaderMaterial = fill.material
	var m: Array = METALS[place - 1]
	for i in 3:
		mat.set_shader_parameter("c%d" % i, m[i])
	mat.set_shader_parameter("y0", at.y - fs * 0.72)
	mat.set_shader_parameter("y1", at.y)
	fill.queue_redraw()


const METAL_SHADER := "shader_type canvas_item;
uniform vec4 c0 : source_color;
uniform vec4 c1 : source_color;
uniform vec4 c2 : source_color;
uniform float y0;
uniform float y1;
varying float ly;
void vertex() { ly = VERTEX.y; }
void fragment() {
	float t = clamp((ly - y0) / max(1.0, y1 - y0), 0.0, 1.0);
	vec3 m = t < 0.48 ? mix(c0.rgb, c1.rgb, t / 0.48)
		: (t < 0.58 ? mix(c1.rgb, c2.rgb, (t - 0.48) / 0.1) : mix(c2.rgb, c1.rgb, min(1.0, (t - 0.58) / 0.3)));
	COLOR = vec4(m, COLOR.a);
}"
static var _shader: Shader = null


## The child that draws the glyph of the digit with the metal shader (made once).
func _metal_fill() -> Control:
	var fill: Control = get_node_or_null("Metal")
	if fill != null:
		return fill
	if _shader == null:
		_shader = Shader.new()
		_shader.code = METAL_SHADER
	fill = Control.new()
	fill.name = "Metal"
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fill.set_anchors_preset(Control.PRESET_FULL_RECT)
	var mat := ShaderMaterial.new()
	mat.shader = _shader
	fill.material = mat
	fill.draw.connect(func():
		var d: Array = fill.get_meta("draw", [])
		if not d.is_empty():
			fill.draw_string(d[0], d[1], d[2], HORIZONTAL_ALIGNMENT_LEFT, -1, d[3], Color.WHITE))
	add_child(fill)
	return fill
