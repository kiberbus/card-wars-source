extends Node2D
## A card on the table. It springs toward its target transform, tilts toward
## the mouse through the fake-3D card shader, and can flip, shake, flash and
## pop. The board decides *where* a card should be; this node makes getting
## there feel physical.

const CardDB = preload("res://scripts/core/card_db.gd")
const CARD_SHADER := preload("res://shaders/card.gdshader")
const CardBacks = preload("res://scripts/ui/card_backs.gd")
const SHARP := preload("res://shaders/sharp.tres")    # for card pictures in controls (previews, pickers)
const SIZE := Vector2(500, 700)
const FONT := preload("res://assets/fonts/display_font.tres")

static var _tex_cache: Dictionary = {}
static var _upright_cache: Dictionary = {}
static var _loading: Dictionary = {}   # card id -> its picture's path, read by ResourceLoader threads (prefetch)
static var _queue: Array = []          # card ids prefetch still has to ask for
const READING := 3                     # pictures read at a time: the window's own loads must not queue behind them
static var foil_on := true     # the shine on cards (the light band, the foil on Rainbow cards), a menu setting

var uid := -1
var card_id := ""
var face_up := true

## The target is in the parent's coordinates, unless on_screen: a card in a hand or on show
## keeps its place and size on the screen when the table under it is zoomed (the parent's
## transform). Setting target_pos makes it a table target again.
var target_pos := Vector2.ZERO:
	set(v):
		target_pos = v
		on_screen = false
var on_screen := false
var target_rot := 0.0
var target_scale := 0.3
var lift := 0.0                 # 0..1, how far the card floats above the table
var hovered := false
var dragging := false
var follow_speed := 14.0

var stats_visible := false
var atk_val := 0
var hp_val := 0
var atk_state := 0              # -1 debuffed, 0 base, 1 buffed
var hp_state := 0
var status := ""                # "", "floop", "attack"
var highlight := ""             # "", "legal", "target", "replace", "selected"
var focused := false            # the keyboard frame stands on it (board.gd): a ring, no tilt after the mouse
var dimmed := false
var secret := false             # Ночной вагон: the cost and the stats read "?"
var upgraded := false           # improved at a rest: a gold rim and a "+"
var burn_tokens := 0            # жетоны огня on a creature in play
var atk_tokens := 0             # жетоны атаки
var guard_hp := 0               # Голографический кролик / Корочкодав by it: their defence left

var _face: Sprite2D
var _shadow: Sprite2D
var _glow: Node2D
var _overlay: Node2D
var _mat: ShaderMaterial
var _vel := Vector2.ZERO
var _tilt := Vector2.ZERO
var _shake := 0.0
var _shake_offset := Vector2.ZERO
var _flash := 0.0
var _flash_color := Color.WHITE
var _pop := 0.0
var _flip_t := 1.0
var _seed := 0.0
var _time := 0.0
var _glow_box := StyleBoxFlat.new()
var _dim := 0.0
var _size := SIZE               # the drawn card: SIZE, or turned for a командная карта face up


static func texture_for(id: String) -> Texture2D:
	if not _tex_cache.has(id):
		if _loading.has(id):
			_take(id)
		else:
			_queue.erase(id)
			_tex_cache[id] = upright(id, load(CardDB.image_path(id)))
	return _tex_cache[id]


## Starts reading the pictures of these cards in background threads (a game's decks as it
## starts): a picture takes ~20 ms to read, and a choice of many cards waited for all of
## them at once. With `keep_only` the pictures of other cards are let go.
static func prefetch(ids: Array, keep_only := false) -> void:
	if keep_only:
		_queue.clear()
		for id: String in _tex_cache.keys():
			if not ids.has(id):
				_tex_cache.erase(id)
				_upright_cache.erase(id)
	# Godot 4.7's headless renderer can race when textures are loaded on worker threads.
	if DisplayServer.get_name() == "headless":
		return
	for id: String in ids:
		if not (_tex_cache.has(id) or _loading.has(id) or _queue.has(id)):
			_queue.append(id)
	_ask()


## Asks the loader for the next queued pictures, a few at a time.
static func _ask() -> void:
	while _loading.size() < READING and not _queue.is_empty():
		var id: String = _queue.pop_front()
		var path := CardDB.image_path(id)
		if ResourceLoader.load_threaded_request(path) == OK:
			_loading[id] = path


## Takes the pictures read so far, a few milliseconds' worth per call (the board calls it every frame).
static func poll_prefetch() -> void:
	var t0 := Time.get_ticks_usec()
	for id: String in _loading.keys():
		if ResourceLoader.load_threaded_get_status(_loading[id]) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			continue
		_take(id)
		if Time.get_ticks_usec() - t0 > 4000:
			break
	_ask()


## Moves a prefetched picture into the cache (waits for its thread when it is still reading).
static func _take(id: String) -> void:
	var path: String = _loading[id]
	_loading.erase(id)
	var tex: Texture2D = ResourceLoader.load_threaded_get(path)
	_tex_cache[id] = upright(id, tex if tex != null else load(path))


## The picture to read a card by: командные карты are scanned sideways, so they are turned
## upright and lie landscape everywhere. A picture already turned is returned as it is
## (tools/make_sharp.gd turns them all, so this is only a guard for one it has not made).
static func upright(id: String, tex: Texture2D) -> Texture2D:
	if tex == null or tex.get_width() > tex.get_height() or not CardDB.has_def(id) \
			or CardDB.get_def(id)["kind"] != "teamwork":
		return tex
	if not _upright_cache.has(id):
		var img := tex.get_image()
		if img.is_compressed():
			img.decompress()
		img.clear_mipmaps()
		img.rotate_90(COUNTERCLOCKWISE)
		img.generate_mipmaps()
		_upright_cache[id] = ImageTexture.create_from_image(img)
	return _upright_cache[id]


func setup(p_uid: int, p_id: String, p_face_up: bool) -> void:
	uid = p_uid
	card_id = p_id
	face_up = p_face_up
	_seed = float(p_uid) * 1.731
	_build()
	_apply_texture()


func _build() -> void:
	_shadow = Sprite2D.new()
	_shadow.modulate = Color(0, 0, 0, 0.38)
	add_child(_shadow)
	_glow = Node2D.new()
	_glow.draw.connect(_draw_glow)
	add_child(_glow)
	_face = Sprite2D.new()
	_mat = ShaderMaterial.new()
	_mat.shader = CARD_SHADER
	_face.material = _mat
	add_child(_face)
	_overlay = Node2D.new()
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)
	_glow_box.corner_radius_top_left = 40
	_glow_box.corner_radius_top_right = 40
	_glow_box.corner_radius_bottom_left = 40
	_glow_box.corner_radius_bottom_right = 40
	_glow_box.draw_center = true
	_glow_box.set_border_width_all(10)
	_glow_box.shadow_size = 40


func _apply_texture() -> void:
	var tex: Texture2D = texture_for(card_id) if face_up and card_id != "" else CardBacks.texture()
	_face.texture = tex
	_shadow.texture = tex
	# The faces are high resolution pictures; a card is drawn SIZE big whatever the picture's size
	# (a командная карта lies landscape: SIZE turned).
	_size = SIZE if tex.get_width() <= tex.get_height() else Vector2(SIZE.y, SIZE.x)
	_face.scale = _size / tex.get_size()
	_shadow.scale = _face.scale
	var foil := 0.0
	if foil_on and face_up and card_id != "" and CardDB.get_def(card_id)["land"] == "rainbow":
		foil = 0.55
	_mat.set_shader_parameter("foil", foil)
	_mat.set_shader_parameter("sheen", 1.0 if foil_on else 0.0)
	if _overlay != null:
		_overlay.queue_redraw()


func _enter_tree() -> void:
	add_to_group("card_views")


## The shine setting changed in the settings window.
func refresh_foil() -> void:
	if _mat != null:
		_apply_texture()


## Another card back was picked in the settings.
func refresh_back() -> void:
	if _mat != null and not (face_up and card_id != ""):
		_apply_texture()


func set_face_up(v: bool, animate := true) -> void:
	if v == face_up:
		return
	face_up = v
	if animate and is_inside_tree():
		_flip_t = 0.0
	else:
		_apply_texture()


func snap() -> void:
	var cam := _cam()
	position = cam.affine_inverse() * target_pos
	rotation = target_rot
	scale = Vector2.ONE * target_scale / cam.get_scale().x


## From the parent's coordinates to the ones target_pos is in.
func _cam() -> Transform2D:
	var p := get_parent() as Node2D
	return p.transform if on_screen and p != null else Transform2D.IDENTITY


func shake(strength := 1.0) -> void:
	_shake = maxf(_shake, strength)


func flash(color := Color.WHITE, amount := 0.85) -> void:
	_flash_color = color
	_flash = amount


func pop(amount := 0.18) -> void:
	_pop = maxf(_pop, amount)


## `below`: the card also reaches that far under its bottom edge (in its own size).
func contains_point(global_point: Vector2, below := 0.0) -> bool:
	var local := to_local(global_point)
	return Rect2(-_size * 0.5, _size + Vector2(0, below)).has_point(local)


func set_stats(visible_: bool, atk: int, hp: int, atk_s := 0, hp_s := 0, status_ := "") -> void:
	if stats_visible == visible_ and atk == atk_val and hp == hp_val and atk_s == atk_state \
			and hp_s == hp_state and status_ == status:
		return
	stats_visible = visible_
	atk_val = atk
	hp_val = hp
	atk_state = atk_s
	hp_state = hp_s
	status = status_
	_overlay.queue_redraw()


func set_secret(v: bool) -> void:
	if v != secret:
		secret = v
		_overlay.queue_redraw()


func set_tokens(burn: int, atk: int, guard := 0) -> void:
	if burn != burn_tokens or atk != atk_tokens or guard != guard_hp:
		burn_tokens = burn
		atk_tokens = atk
		guard_hp = guard
		_overlay.queue_redraw()


func set_upgraded(v: bool) -> void:
	if v != upgraded:
		upgraded = v
		_overlay.queue_redraw()


func set_highlight(mode: String) -> void:
	if mode != highlight:
		highlight = mode
		_glow.queue_redraw()


## The keyboard frame on this card or off it.
func set_focused(v: bool) -> void:
	if v != focused:
		focused = v
		_glow.queue_redraw()


func _process(delta: float) -> void:
	_time += delta
	var k := 1.0 - exp(-delta * follow_speed)
	if _shake > 0.0:
		_shake = maxf(_shake - delta * 3.0, 0.0)
		_shake_offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * _shake * 14.0
	else:
		_shake_offset = Vector2.ZERO
	var cam := _cam()
	var zoom := cam.get_scale().x
	var prev := cam * position
	var now := prev.lerp(target_pos + _shake_offset, k)
	position = cam.affine_inverse() * now
	_vel = _vel.lerp((now - prev) / maxf(delta, 0.0001), 0.3)

	var sway := clampf(_vel.x * 0.00022, -0.22, 0.22) if dragging else 0.0
	rotation = lerp_angle(rotation, target_rot + sway, k)
	_pop = maxf(_pop - delta * 1.6, 0.0)
	var s := target_scale * (1.0 + _pop * sin(minf(_pop * 9.0, PI)))
	scale = (scale * zoom).lerp(Vector2.ONE * s, k) / zoom

	# Tilt: follow the mouse while hovered, otherwise drift gently.
	var want := Vector2.ZERO
	if (hovered or dragging) and not focused:
		var m := to_local(get_global_mouse_position()) / (_size * 0.5)
		m = m.clamp(Vector2(-1.2, -1.2), Vector2(1.2, 1.2))
		want = Vector2(m.y * 16.0, -m.x * 20.0)
	else:
		want = Vector2(sin(_time * 1.3 + _seed) * 2.5, cos(_time * 1.05 + _seed) * 3.5)
	want += Vector2(clampf(_vel.y * 0.02, -18.0, 18.0), clampf(-_vel.x * 0.025, -24.0, 24.0))
	_tilt = _tilt.lerp(want, 1.0 - exp(-delta * 10.0))

	var flip_angle := 0.0
	if _flip_t < 1.0:
		var before := _flip_t < 0.5
		_flip_t = minf(_flip_t + delta * 3.6, 1.0)
		if before and _flip_t >= 0.5:
			_apply_texture()
		flip_angle = _flip_t * 180.0 if _flip_t < 0.5 else (_flip_t - 1.0) * 180.0
	_mat.set_shader_parameter("x_rot", _tilt.x)
	_mat.set_shader_parameter("y_rot", _tilt.y + flip_angle)

	_flash = maxf(_flash - delta * 2.8, 0.0)
	_mat.set_shader_parameter("flash_color", Color(_flash_color, _flash))
	_dim = lerpf(_dim, 1.0 if dimmed else 0.0, 1.0 - exp(-delta * 10.0))
	_mat.set_shader_parameter("dim", _dim)

	# Shadow drifts away as the card lifts and points away from screen center.
	var lift_px := 10.0 + lift * 26.0
	var away := (global_position - Vector2(960, 300)).normalized() * 6.0
	_shadow.position = (Vector2(lift_px * 0.6, lift_px) + away).rotated(-rotation)
	if highlight != "" or focused:
		_glow.queue_redraw()


func _draw_glow() -> void:
	if focused:
		_draw_focus()
	if highlight == "":
		return
	var c: Color
	match highlight:
		"legal":
			c = Color(1.0, 0.93, 0.55)
		"target":
			c = Color(0.35, 0.95, 1.0)
		"replace":
			c = Color(1.0, 0.35, 0.3)
		"selected":
			c = Color(0.55, 1.0, 0.45)
		_:
			c = Color.WHITE
	var pulse := 0.6 + 0.4 * sin(_time * 5.0)
	_glow_box.bg_color = Color(c, 0.85 * pulse)
	_glow_box.border_color = Color(c.lightened(0.5), pulse)
	_glow_box.shadow_color = Color(c, 0.6 * pulse)
	var m := Vector2(34, 34)
	_glow.draw_style_box(_glow_box, Rect2(-_size * 0.5 - m, _size + m * 2.0))


## The keyboard frame: a white line on a dark one around the card, as wide on the screen
## whatever the card's size (key_nav.gd draws the same around buttons).
func _draw_focus() -> void:
	var k := 1.0 / maxf(get_global_transform_with_canvas().get_scale().x, 0.05)
	var pulse := 0.5 + 0.5 * sin(_time * 6.0)
	var sb := StyleBoxFlat.new()
	sb.draw_center = false
	sb.set_corner_radius_all(int(14 * k))
	var r := Rect2(-_size * 0.5, _size).grow(7.0 * k)
	sb.set_border_width_all(int(9 * k))
	sb.border_color = Color(0.05, 0.03, 0.08, 0.7)
	_glow.draw_style_box(sb, r.grow(2.0 * k))
	sb.set_border_width_all(int(5 * k))
	sb.border_color = Color(1.0, 0.86, 0.3).lerp(Color.WHITE, pulse)
	_glow.draw_style_box(sb, r)


func _draw_overlay() -> void:
	var font: Font = FONT
	if secret and face_up:
		_badge(Vector2(-172, -255), "?", Color(0.3, 0.27, 0.22), 0, font)
	if upgraded and face_up:
		draw_upgrade_mark(_overlay, font)
	if not stats_visible:
		return
	# Attack tokens by the ATK badge, fire (it burns the defence) by the DEF badge.
	if atk_tokens > 0:
		_token(Vector2(-150, 150), "+" + str(atk_tokens), Color(0.8, 0.12, 0.12), font)
	if burn_tokens > 0:
		_token(Vector2(150, 150), str(burn_tokens), Color(0.95, 0.42, 0.08), font)
	if guard_hp > 0:
		_token(Vector2(0, 150), str(guard_hp), Color(0.2, 0.55, 0.95), font)
	_badge(Vector2(-188, 292), "?" if secret else str(atk_val), Color(0.86, 0.2, 0.18), 0 if secret else atk_state, font)
	_badge(Vector2(188, 292), "?" if secret else str(hp_val), Color(0.16, 0.45, 0.9), 0 if secret else hp_state, font)
	if status != "":
		var txt := "ФЛЮП" if status == "floop" else "АТАКОВАЛ"
		var col := Color(0.25, 0.75, 0.3) if status == "floop" else Color(0.85, 0.25, 0.2)
		var r := Rect2(-130, -372, 260, 64)
		var sb := StyleBoxFlat.new()
		sb.bg_color = col
		sb.set_corner_radius_all(30)
		sb.set_border_width_all(5)
		sb.border_color = Color(1, 1, 1, 0.9)
		_overlay.draw_style_box(sb, r)
		_overlay.draw_string(font, Vector2(-130, -326), txt, HORIZONTAL_ALIGNMENT_CENTER, 260, 40, Color.WHITE)


## The mark of an improved card: a gold rim and a "+" under the land symbol.
static func draw_upgrade_mark(canvas: CanvasItem, font: Font) -> void:
	var rim := StyleBoxFlat.new()
	rim.draw_center = false
	rim.set_corner_radius_all(34)
	rim.set_border_width_all(9)
	rim.border_color = Color(1.0, 0.82, 0.2, 0.95)
	canvas.draw_style_box(rim, Rect2(-SIZE * 0.5, SIZE))
	canvas.draw_circle(Vector2(170, -140), 40, Color(1.0, 0.82, 0.2))
	canvas.draw_circle(Vector2(170, -140), 33, Color(0.55, 0.32, 0.05))
	canvas.draw_string(font, Vector2(90, -112), "+", HORIZONTAL_ALIGNMENT_CENTER, 160, 64, Color(1.0, 0.9, 0.4))


## A round token on the card: fire (orange) or attack (red).
func _token(center: Vector2, txt: String, col: Color, font: Font) -> void:
	_overlay.draw_circle(center + Vector2(3, 5), 52, Color(0, 0, 0, 0.35))
	_overlay.draw_circle(center, 52, Color(1.0, 0.9, 0.55))
	_overlay.draw_circle(center, 44, col)
	var pos := center + Vector2(-70, 22)
	_overlay.draw_string_outline(font, pos, txt, HORIZONTAL_ALIGNMENT_CENTER, 140, 62, 10, Color(0, 0, 0, 0.85))
	_overlay.draw_string(font, pos, txt, HORIZONTAL_ALIGNMENT_CENTER, 140, 62, Color.WHITE)


func _badge(center: Vector2, txt: String, col: Color, state: int, font: Font) -> void:
	var ring := Color.WHITE
	if state > 0:
		ring = Color(1.0, 0.86, 0.2)
	elif state < 0:
		ring = Color(1.0, 0.45, 0.3)
	_overlay.draw_circle(center + Vector2(4, 6), 66, Color(0, 0, 0, 0.35))
	_overlay.draw_circle(center, 66, ring)
	_overlay.draw_circle(center, 56, col)
	var fs := 78
	var pos := center + Vector2(-80, 27)
	_overlay.draw_string_outline(font, pos, txt, HORIZONTAL_ALIGNMENT_CENTER, 160, fs, 12, Color(0, 0, 0, 0.85))
	_overlay.draw_string(font, pos, txt, HORIZONTAL_ALIGNMENT_CENTER, 160, fs, ring if state != 0 else Color.WHITE)
