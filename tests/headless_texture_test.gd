extends SceneTree

const Backdrop = preload("res://scripts/ui/backdrop.gd")
const CardDB = preload("res://scripts/core/card_db.gd")
const CardView = preload("res://scripts/ui/card_view.gd")
const DeckBuilder = preload("res://scripts/ui/deck_builder.gd")
const DeckTiles = preload("res://scripts/ui/deck_tiles.gd")
const ProfileScreen = preload("res://scripts/ui/profile_screen.gd")

var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() != "headless":
		push_error("This test must run with --headless.")
		quit(1)
		return

	var backdrop := Backdrop.new()
	root.add_child(backdrop)
	await process_frame
	for path: String in Backdrop.PICTURES:
		_check(ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE,
				"backdrop does not start threaded texture loads")
	_check(backdrop.current_texture() != null, "backdrop still loads its picture")

	CardView.prefetch(["gnome_snot"], true)
	_check(CardView._loading.is_empty() and CardView._queue.is_empty(),
			"card prefetch does not start worker loads")
	_check(CardView.texture_for("gnome_snot") != null, "card picture still loads on demand")

	var builder := DeckBuilder.new()
	_check(builder._card_tex("gnome_snot", true) != null, "builder loads a card picture")
	_check(builder._hero_best("bmo", true) != null, "builder loads a hero picture")
	_check(builder._loading.is_empty() and builder._hero_loading.is_empty(),
			"builder does not start worker loads")
	builder.free()

	var tiles := DeckTiles.new()
	var tile := TextureRect.new()
	tiles._ask(tile, CardDB.card_thumb("evil_eye"))
	_check(tile.texture != null and tiles._pending.is_empty(), "deck tile loads without a worker")
	tile.free()

	var profile := ProfileScreen.new()
	var avatar := TextureRect.new()
	await profile._load_thumbs({"bmo": avatar})
	_check(avatar.texture != null, "profile loads an avatar without a worker")
	avatar.free()
	profile.free()
	backdrop.free()

	if failures == 0:
		print("PASS: headless textures load without worker threads")
	quit(1 if failures else 0)


func _check(condition: bool, description: String) -> void:
	if not condition:
		failures += 1
		push_error("FAIL: " + description)
