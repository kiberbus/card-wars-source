extends PanelContainer
## The profile of the player who is logged in: the avatar, the nick, the description (others see it in
## the profile of the players online), what the server knows of the player (the train, the time played,
## the games against people, the day of the account, the awards): what the others see, a button to change the avatar (a picture of a hero or any picture file,
## cut to a square and made small, see scripts/net/avatar.gd) and a button to log out. main.gd opens it
## (show_profile, through place()).
## Nothing may move under the finger: the window keeps its top where it is and the avatars open
## below the buttons (when they hid in the middle, «Выйти» came under the next tap and players
## lost their account), and «Выйти» asks once more before it logs out.

const UI = preload("res://scripts/ui/ui_kit.gd")
const WoodUI = preload("res://scripts/ui/wood_ui.gd")
const Phone = preload("res://scripts/ui/phone.gd")
const FitCenter = preload("res://scripts/ui/fit_center.gd")
const Account = preload("res://scripts/net/account.gd")
const Avatar = preload("res://scripts/net/avatar.gd")
const CardDB = preload("res://scripts/core/card_db.gd")
const AvatarView = preload("res://scripts/ui/avatar_view.gd")
const NickStyle = preload("res://scripts/ui/nick_style.gd")
const FileDialogs = preload("res://scripts/ui/file_dialogs.gd")
const Social = preload("res://scripts/net/social.gd")
const SocialPanel = preload("res://scripts/ui/social_panel.gd")
const GOLD := Color(1.0, 0.86, 0.35)
const COLUMNS := 15
const IMAGE_FILTER := "*.png, *.jpg, *.jpeg, *.webp, *.bmp ; Картинки"
const TOP := 200                 # px from the top of the screen to the window
const CONFIRM_SEC := 3.0         # how long «Точно выйти?» waits for the second press
const ARM_SEC := 0.4             # a second press sooner than this is the same tap, not a yes
const FRAME_MS := 8              # avatar pictures made per frame, at most this long

signal closed
signal logged_out

static var _thumbs := {}         # hero card id -> Texture2D, made once

var account: Account
var social: Social              # the description and the facts come through it (null: not shown)
var _big: Control
var _facts: Control
var _bio: TextEdit
var _chooser: Control
var _status: Label
var _busy := false
var _asked_at := -1              # ticks of the first press of «Выйти», -1 = not asked
var _full := Vector2.ZERO        # full_size(), made once


func setup(p_account: Account, p_social: Social = null) -> void:
	account = p_account
	social = p_social


## Puts the profile into an overlay: centred across, its top fixed. On a small screen (a big
## interface scale) the window is scaled down so that it fits with the avatars open, and the
## scale stays when they open or hide, so still nothing moves under the finger.
static func place(parent: Control, screen: Control) -> void:
	if Phone.active:
		# A phone: at full size; with the avatars open the window scrolls (FitCenter).
		var center := FitCenter.new()
		center.set_anchors_preset(Control.PRESET_FULL_RECT)
		parent.add_child(center)
		center.add_child(screen)
		return
	var holder := Control.new()
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(holder)
	holder.add_child(screen)
	var fit := func():
		if not holder.is_inside_tree():
			return
		var need: Vector2 = screen.full_size()
		var room := FitCenter.safe_rect(holder)
		var top := clampf(room.end.y - need.y, room.position.y, TOP)
		var k := minf(1.0, minf(room.size.x / need.x, (room.end.y - top) / need.y))
		var own: Vector2 = screen.get_combined_minimum_size()
		screen.scale = Vector2.ONE * k
		screen.size = own
		screen.position = Vector2(room.get_center().x - own.x * k * 0.5, top).floor()
	holder.resized.connect(fit)
	screen.minimum_size_changed.connect(fit)
	fit.call()


## The size of the window with the avatars open (it is made once: the avatars do not change).
func full_size() -> Vector2:
	if _chooser == null:              # not built yet
		return get_combined_minimum_size()
	if _full == Vector2.ZERO:
		var was := _chooser.visible
		_chooser.visible = true
		_full = get_combined_minimum_size()
		_chooser.visible = was
	return _full


func _ready() -> void:
	var sb := WoodUI.window()
	sb.content_margin_left = 40
	sb.content_margin_right = 40
	sb.content_margin_top = 28
	sb.content_margin_bottom = 28
	add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(v)
	var head := HBoxContainer.new()
	head.alignment = BoxContainer.ALIGNMENT_CENTER
	head.add_theme_constant_override("separation", 24)
	v.add_child(head)
	_big = AvatarView.make(account.nick, account.texture(), 150, GOLD)
	head.add_child(_big)
	var nick := WoodUI.label(account.nick, 56, GOLD, 12)
	NickStyle.apply(nick, account.rainbow, account.color)
	var tag := NickStyle.tag(account.tag, 28)
	if tag == null:
		nick.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		head.add_child(nick)
	else:
		var names := VBoxContainer.new()
		names.add_theme_constant_override("separation", 4)
		names.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		names.add_child(nick)
		tag.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		names.add_child(tag)
		head.add_child(names)
	if social != null:
		_about(v)
	_status = WoodUI.label("", 28, UI.CREAM, 7)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.custom_minimum_size = Vector2(0, 38)
	v.add_child(_status)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	v.add_child(row)
	var change := WoodUI.button("Сменить аватарку", UI.BLUE, 30, Vector2(340, 66))
	change.pressed.connect(func():
		_chooser.visible = not _chooser.visible
		_status.text = "")
	row.add_child(change)
	var out := WoodUI.button("Выйти", UI.RED, 30, Vector2(270, 66))
	out.pressed.connect(func(): _out_pressed(out))
	row.add_child(out)
	var back := WoodUI.button("Назад", UI.PURPLE, 30, Vector2(200, 66))
	back.pressed.connect(func(): closed.emit())
	row.add_child(back)
	_chooser = _build_chooser()
	_chooser.visible = false
	v.add_child(_chooser)
	account.changed.connect(_refresh)


## The facts, the awards and the description with «Сохранить»; they come from the server (our own s_profile).
func _about(v: VBoxContainer) -> void:
	_facts = VBoxContainer.new()
	_facts.add_theme_constant_override("separation", 10)
	_fill_facts({})
	_facts.modulate.a = 0.0         # its room is kept till the server answers
	v.add_child(_facts)
	v.add_child(WoodUI.label("Описание", 26, GOLD, 6))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	v.add_child(row)
	_bio = TextEdit.new()
	_bio.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_bio.placeholder_text = "Пара слов о себе"
	_bio.custom_minimum_size = Vector2(620, 96)
	_bio.editable = false
	WoodUI.edit(_bio, 22)
	_bio.text_changed.connect(func():
		var t := _bio.text.replace("\n", " ")
		if t.length() > Social.BIO_MAX:
			t = t.substr(0, Social.BIO_MAX)
		if t != _bio.text:
			_bio.text = t
			_bio.set_caret_column(t.length()))
	row.add_child(_bio)
	var save := WoodUI.button("Сохранить", UI.GREEN, 26, Vector2(200, 60))
	save.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	save.pressed.connect(_save_bio)
	row.add_child(save)
	_load_about()


func _load_about() -> void:
	var answer: Dictionary = await social.ask({"op": "s_profile", "nick": account.nick})
	if not is_instance_valid(self):
		return
	if answer.get("op") != "s_profile" or not answer.get("p") is Dictionary:
		_status.text = Social.reason(String(answer.get("r", "")))
		return
	var p: Dictionary = answer["p"]
	_fill_facts(p)
	_facts.modulate.a = 1.0
	_bio.text = String(p.get("bio", ""))
	_bio.editable = true
	_full = Vector2.ZERO


func _fill_facts(p: Dictionary) -> void:
	for ch in _facts.get_children():
		_facts.remove_child(ch)
		ch.queue_free()
	_facts.add_child(SocialPanel.facts(p))
	var head := WoodUI.label("Награды", 26, GOLD, 6)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_facts.add_child(head)
	_facts.add_child(SocialPanel.awards(p))


func _save_bio() -> void:
	if _busy or not _bio.editable:
		return
	_busy = true
	_status.text = "Подождите"
	var answer: Dictionary = await social.set_bio(_bio.text)
	if not is_instance_valid(self):
		return
	_busy = false
	_status.text = "Сохранено" if answer.get("op") == "s_done" else Social.reason(String(answer.get("r", "")))


## The first press asks «Точно выйти?», a press after it (not the same tap) logs out; the question
## goes away by itself.
func _out_pressed(out: Button) -> void:
	var now := Time.get_ticks_msec()
	if _asked_at < 0:
		_asked_at = now
		out.text = "Точно выйти?"
		await get_tree().create_timer(CONFIRM_SEC).timeout
		if is_instance_valid(out) and _asked_at == now:
			_asked_at = -1
			out.text = "Выйти"
	elif now - _asked_at >= ARM_SEC * 1000.0:
		_asked_at = -1
		logged_out.emit()


func _build_chooser() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	var grid := GridContainer.new()
	grid.columns = COLUMNS
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	box.add_child(grid)
	var cells := {}
	for hero: String in Avatar.hero_ids():
		var cell := AvatarView.make_button(String(hero), _thumbs.get(hero), 84)
		cell.pressed.connect(func(): _apply(Avatar.from_hero(hero)))
		grid.add_child(cell)
		cells[hero] = cell
	_load_thumbs.call_deferred(cells)
	var own := WoodUI.button("Своя картинка", UI.GREEN, 30, Vector2(340, 62))
	own.pressed.connect(func():
		FileDialogs.open_file(self, "Картинка", [IMAGE_FILTER], func(path: String): _apply(Avatar.from_file(path))))
	var wrap := CenterContainer.new()
	wrap.add_child(own)
	box.add_child(wrap)
	return box


## The avatar pictures load in the background after the window is open: all the heroes at once
## kept the profile from opening for seconds.
func _load_thumbs(cells: Dictionary) -> void:
	var todo: Array = cells.keys().filter(func(h): return not _thumbs.has(h) and CardDB.has_hero_card(h))
	if DisplayServer.get_name() == "headless":
		for hero: String in todo:
			cells[hero].set_texture(_thumb(hero))
		return
	for hero: String in todo:
		ResourceLoader.load_threaded_request(CardDB.hero_thumb(hero))
	var start := Time.get_ticks_msec()
	for hero: String in todo:
		var path := CardDB.hero_thumb(hero)
		while ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_IN_PROGRESS \
				or Time.get_ticks_msec() - start > FRAME_MS:
			await get_tree().process_frame
			if not is_instance_valid(self) or not is_inside_tree():
				return
			start = Time.get_ticks_msec()
		ResourceLoader.load_threaded_get(path)
		cells[hero].set_texture(_thumb(hero))


func _thumb(hero: String) -> Texture2D:
	if not _thumbs.has(hero):
		var img := Avatar.hero_image(hero, true)
		if img == null:
			return null
		var side := mini(img.get_width(), img.get_height())
		img = img.get_region(Rect2i((img.get_width() - side) / 2, (img.get_height() - side) / 2, side, side))
		img.resize(96, 96, Image.INTERPOLATE_LANCZOS)
		_thumbs[hero] = ImageTexture.create_from_image(img)
	return _thumbs[hero]


## Sends the avatar to the server; empty bytes mean the picture could not be used.
func _apply(bytes: PackedByteArray) -> void:
	if _busy:
		return
	if bytes.is_empty():
		_status.text = "Не получилось взять картинку"
		return
	_busy = true
	_status.text = "Подождите"
	var answer: Dictionary = await account.set_avatar(get_tree(), bytes)
	if not is_instance_valid(self):
		return
	_busy = false
	if answer["ok"]:
		_status.text = "Готово"
		_chooser.visible = false
	else:
		_status.text = Account.reason(String(answer["r"]))


func _refresh() -> void:
	if _big != null and is_instance_valid(_big) and account.logged_in():
		_big.set_texture(account.texture())
