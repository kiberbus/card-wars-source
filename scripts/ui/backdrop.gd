extends Control
## The pictures behind the menus and the table (assets/bg, cut to 1920x1080 from
## art_src/backgrounds): one after another in a shuffled order, with a cross-fade to
## the next. They stand still: a slow zoom moved them by parts of a pixel and looked
## jerky. The next picture loads in the background meanwhile, so the change never
## stalls the game. A picture may be pinned instead (Настройки → Фон): it stays.

const PICTURES := [
	"res://assets/bg/tree_fort.jpg", "res://assets/bg/daisies.jpg", "res://assets/bg/giant_tree.jpg",
	"res://assets/bg/moon_lake.jpg", "res://assets/bg/starry_night.jpg", "res://assets/bg/fireflies.jpg",
	"res://assets/bg/earth.jpg",
]
const NAMES := ["Домик на дереве", "Ромашки", "Большое дерево", "Лунное озеро", "Звёздная ночь", "Светлячки", "Земля"]
const HOLD := 16.0          # seconds a picture stays
const FADE := 2.5           # seconds of the cross-fade

var _layers: Array = []     # [under, top]: the top one fades in over the under one
var _order: Array = []
var _at := -1
var _tween: Tween = null
var pinned := ""            # the picture that stays ("" = one after another)


## Anchored before it enters the tree: under a CanvasLayer that is what sizes it.
func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	for i in 2:
		var r := TextureRect.new()
		r.set_anchors_preset(Control.PRESET_FULL_RECT)
		r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		r.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(r)
		_layers.append(r)
	_order = range(PICTURES.size())
	_order.shuffle()
	if pinned != "":
		_show(pinned, true)
	else:
		_show_next(true)


## Pins a picture (a path of PICTURES), or "" for one after another again.
func set_pinned(path: String) -> void:
	if path != "" and not PICTURES.has(path):
		path = ""
	pinned = path
	if _layers.is_empty():
		return          # _ready shows it
	if path != "":
		_show(path)
	else:
		_show_next()


## The picture on screen now (the hotseat curtain shows it too).
func current_texture() -> Texture2D:
	return _layers[1].texture


func _show_next(first := false) -> void:
	_at = (_at + 1) % _order.size()
	_show(PICTURES[_order[_at]], first)
	if DisplayServer.get_name() != "headless":
		ResourceLoader.load_threaded_request(PICTURES[_order[(_at + 1) % _order.size()]])


## Fades a picture in over the one on screen; unless one is pinned the next one follows.
func _show(path: String, first := false) -> void:
	if _tween != null:
		_tween.kill()
	var tex: Texture2D = ResourceLoader.load_threaded_get(path) if _requested(path) else load(path)
	if _layers[1].texture == tex and not first:
		return
	var top: TextureRect = _layers[0]
	_layers = [_layers[1], top]
	move_child(top, -1)
	top.texture = tex
	top.modulate.a = 1.0 if first else 0.0
	_tween = create_tween()
	if not first:
		_tween.tween_property(top, "modulate:a", 1.0, FADE if pinned == "" else 0.6)
	if pinned == "":
		_tween.tween_interval(HOLD)
		_tween.tween_callback(_show_next)


func _requested(path: String) -> bool:
	return ResourceLoader.load_threaded_get_status(path) != ResourceLoader.THREAD_LOAD_INVALID_RESOURCE
