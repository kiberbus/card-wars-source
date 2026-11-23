extends RefCounted
## «Наблюдать» on a friend (the eye on their row, social_panel.gd): the watch code of the match we
## play now. The host of a room for two has the room's own (main.friend_watch_code). Every other
## match for two (a guest of a room, a quick game, a ranked or tournament game, a direct link) has
## none the players are told, so our game opens a room of its own on the room server, nobody sits
## in it, and streams the match there (Net.spec_follow, as a host does for its room's watchers);
## its watch code goes to the friend. "own" (our seat) in the head: the watchers see the table from
## our side; no hand is open to them (board.gd replay_closed).
##
## Who watches us: a watcher tells the players of the match (Social.WATCH_ON / WATCH_OFF, private
## messages never shown, watch.gd), and its status stays «наблюдает» while it watches. The table shows
## their number in its corner (board.set_spectators); one gone offline or doing something else drops out.
## The two players pass on whom they were told of ("specs" in the match), so both tables show every
## watcher of the match, whoever it came to watch (a private message may reach only a friend).

const NetScript = preload("res://scripts/net/net.gd")
const Replay = preload("res://scripts/core/replay.gd")
## How long the room server may take to give the watch code of the new room.
const CODE_WAIT_MS := 8000
## How often the watchers' statuses are checked while somebody watches.
const SPEC_POLL_MS := 6000

var m                       # main.gd
var _net: Node = null       # our own link to the room server, for the watchers only
var _game = null            # the match it streams
var spectators: Array = []  # the nicks of those who watch our match now (ours and the other player's)
var _mine: Array = []       # the watchers who told us (Social.WATCH_ON)
var _theirs: Array = []     # the watchers the other player was told of (its "specs" message)
var _poll_at := 0
var _polling := false


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
	head["own"] = m.seat         # the watchers see the table from our side
	head["nicks"] = m.match_nicks(m.seat)
	cast.spec_follow(_game, head)
	return code


func _code_of(cast: Node) -> String:
	var t0 := Time.get_ticks_msec()
	while is_instance_valid(cast) and cast == _net and cast.watch_code == "" and Time.get_ticks_msec() - t0 < CODE_WAIT_MS:
		await m.get_tree().process_frame
	if not is_instance_valid(cast) or cast != _net:
		return ""
	return cast.watch_code


## A watcher says it watches our match (Social.WATCH_ON).
func spectator_on(nick: String) -> void:
	if nick == "" or not m.online_duel():
		return
	if not _mine.has(nick):
		_mine.append(nick)
		_poll_at = Time.get_ticks_msec() + SPEC_POLL_MS
	_tell_other()


func spectator_off(nick: String) -> void:
	if _mine.has(nick):
		_mine.erase(nick)
		_tell_other()


## The other player's watchers ("specs" in the match, lobby.gd).
func remote_spectators(nicks) -> void:
	if not (nicks is Array) or not m.online_duel():
		return
	_theirs = []
	for n in nicks.slice(0, 100):
		if n is String and n != "" and not _theirs.has(n):
			_theirs.append(n.substr(0, 24))
	_update()


## Ours to the other player, and the counter.
func _tell_other() -> void:
	m.net.send({"t": "specs", "nicks": _mine})
	_update()


## Both lists on the table (no note over the screen: the counter in the corner is enough).
func _update() -> void:
	var all: Array = _mine.duplicate()
	for n in _theirs:
		if not all.has(n):
			all.append(n)
	spectators = all
	_show()


## main._process: one who left without saying so (closed the game, lost the link) drops out.
func tick() -> void:
	if _mine.is_empty() or _polling or Time.get_ticks_msec() < _poll_at:
		return
	if not m.online_duel():
		_mine.clear()
		_theirs.clear()
		_update()
		return
	_polling = true
	_poll_at = Time.get_ticks_msec() + SPEC_POLL_MS
	var answer: Dictionary = await m.social.ask({"op": "s_online"})
	_polling = false
	if answer.get("op") != "s_online" or not (answer.get("players") is Array):
		return      # no answer: nothing is known, nobody drops out
	var watching := {}
	for r in answer["players"]:
		if r is Dictionary and String(r.get("st", "")) == "watch":
			watching[String(r.get("nick", ""))] = true
	var left := _mine.filter(func(n): return not watching.has(n))
	if not left.is_empty():
		for n in left:
			_mine.erase(n)
		_tell_other()


## The counter on the table (a new table gets it too: main._new_board).
func _show() -> void:
	if m.board != null and is_instance_valid(m.board):
		m.board.set_spectators(spectators)


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
	spectators.clear()
	_mine.clear()
	_theirs.clear()
