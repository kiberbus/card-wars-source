extends RefCounted
## «Наблюдать» on a friend (the eye on their row, social_panel.gd): the watch code of the match we
## play now. The host of a room for two has the room's own (main.friend_watch_code). Every other
## match for two (a guest of a room, a quick game, a ranked or tournament game, a direct link) has
## none the players are told, so our game opens a room of its own on the room server, nobody sits
## in it, and streams the match there (Net.spec_follow, as a host does for its room's watchers);
## its watch code goes to the friend. A ranked or tournament match puts "own" (our seat) in the
## head: the watchers see our hand only (board.gd replay_own), never the other player's.

const NetScript = preload("res://scripts/net/net.gd")
const Replay = preload("res://scripts/core/replay.gd")
## How long the room server may take to give the watch code of the new room.
const CODE_WAIT_MS := 8000

var m                       # main.gd
var _net: Node = null       # our own link to the room server, for the watchers only
var _game = null            # the match it streams


func _init(main) -> void:
	m = main


## The watch code friends may watch our match by, "" when there is none (not a match for two online).
func code_for_friend() -> String:
	var own: String = m.friend_watch_code()
	if own != "":
		return own
	if not m.online_duel():
		return ""
	if _net != null and _game == m.game:
		# Already streaming this match (or opening the room for another friend's ask): its code.
		return await _code_of(_net)
	stop()
	var cast: Node = NetScript.new()
	cast.name = "FriendCast"
	m.add_child(cast)
	_net = cast
	_game = m.game
	if cast.host_room(2) != OK:
		stop()
		return ""
	var code := await _code_of(cast)
	if code == "" or _net != cast or _game != m.game:
		if _net == cast:
			stop()
		return ""
	var head := Replay.from_game(_game, "net", maxi(m.seat, 0), m.version_text())
	head.erase("steps")
	if not m.net.tour.is_empty():
		head["own"] = m.seat     # ranked / tournament: the watchers see our hand only
	cast.spec_follow(_game, head)
	return code


func _code_of(cast: Node) -> String:
	var t0 := Time.get_ticks_msec()
	while is_instance_valid(cast) and cast == _net and cast.watch_code == "" and Time.get_ticks_msec() - t0 < CODE_WAIT_MS:
		await m.get_tree().process_frame
	if not is_instance_valid(cast) or cast != _net:
		return ""
	return cast.watch_code


## The match is over or left: the room goes, its watchers are told the match is closed.
func stop() -> void:
	if _net != null and is_instance_valid(_net):
		var cast := _net
		cast.close()
		m.get_tree().create_timer(2.0).timeout.connect(func():
			if is_instance_valid(cast):
				cast.queue_free())
	_net = null
	_game = null
