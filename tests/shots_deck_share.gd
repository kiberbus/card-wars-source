extends SceneTree
## Screenshots of a deck sent in the chat (scripts/net/deck_share.gd) and of the list of own decks
## to send (windowed, not headless):
##   godot --path . -s res://tests/shots_deck_share.gd -- <output_dir>

const MainScene := preload("res://scenes/main.tscn")
const CardDB = preload("res://scripts/core/card_db.gd")
const DeckShare = preload("res://scripts/net/deck_share.gd")

const FRIEND := "Друг"

var out_dir := "user://shots_deck_share"
var n := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run()


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	n += 1
	root.get_viewport().get_texture().get_image().save_png("%s/%02d_%s.png" % [out_dir, n, shot_name])
	print("shot ", shot_name)


func _wait(t: float) -> void:
	await create_timer(t).timeout


func _press(text: String) -> bool:
	for b in root.find_children("*", "Button", true, false):
		if b.text == text and b.is_visible_in_tree() and not b.disabled:
			b.pressed.emit()
			return true
	return false


func _run() -> void:
	var main = MainScene.instantiate()
	root.add_child(main)
	await _wait(1.2)
	var ids := CardDB.pool_ids()
	var deck := {}
	for i in 14:
		deck[ids[i * 5]] = 3
	var text := DeckShare.encode({"name": "Ледяной натиск", "lands": ["ice", "ice", "plain", "plain"], "deck": deck,
		"hero": CardDB.hero_card_ids()[0]})
	main.social.add(FRIEND, {"nick": FRIEND, "text": "Глянь мою колоду", "me": false})
	main.social.add(FRIEND, {"nick": FRIEND, "text": text, "me": false, "live": true})
	await _wait(0.6)
	await _shot("toast")
	main.social_ui.show_panel("chat", FRIEND)
	await _wait(0.8)
	await _shot("chat_deck")
	_press("Колода")
	await _wait(0.5)
	await _shot("picker")
	quit(0)
