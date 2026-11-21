extends Node
## Players online, friends, invites and chat. While the game runs with an account it keeps a
## connection of its own to the room server (server/relay/relay_server.gd, «Players online»),
## separate from the one of a room (net.gd): the account is online as long as it is open. A guest
## has no such connection; the chat of a match (channel GAME) goes through the match link and works
## for everybody (main.gd passes those messages here with add()).
## The game never waits on it: a lost connection is opened again after a while, and a request
## (ask) gives {"op": "s_error", "r": "offline" | "timeout"} when there is no answer.
##   social.setup(account, url, status_fn)    # status_fn returns [status, room code, who sees the room, seat token, who may call] (relay «s_status»)
##   var answer: Dictionary = await social.ask({"op": "s_online"})
## Channels of the chat: COMMON (everybody online), GAME (the players of the match), a friend's nick.

const Account = preload("res://scripts/net/account.gd")
const COMMON := ""
const GAME := "#game"
const PING_MS := 15000
const SILENCE_MS := 45000
const CONNECT_MS := 12000
const RETRY_MS := [3000, 6000, 15000, 30000]
const ASK_MS := 8000
const KEEP := 100                   # messages of a channel kept
const TEXT_MAX := 200
const BIO_MAX := 160                # characters of the description of a profile
## «Наблюдать» on a friend (the eye on their row): the friend's game gives its watch code by a private
## message, so the lines are plain words, and one without the game's answer can still answer by hand.
const WATCH_ASK := "Хочу посмотреть твою игру"
const WATCH_CODE := "Код наблюдателя: "
const WATCH_NONE := "Сейчас мою игру смотреть нельзя"
const RESULTS_KEPT := 20            # results of games waiting for the link
## Why a request failed, as a short line for the player.
const REASONS := {"offline": "Нет связи", "timeout": "Нет связи", "token": "Нужно войти снова", "none": "Игрока нет в сети",
	"rate": "Не так быстро", "friends": "Только для друзей", "inv": "Зовут только друзья", "busy": "Игрок сейчас в игре", "room": "Сначала создай комнату",
	"self": "Это ты", "already": "Уже в друзьях", "full": "Слишком много друзей", "many": "У игрока много заявок",
	"bad": "Не получилось"}

signal changed                                  # the link came up or went, the number online changed
signal message(ch: String, msg: Dictionary)     # a new chat message in channel ch
signal invited(d: Dictionary)                   # a friend calls into a room: {"nick", "av", "code", "four"}
signal requested(nick: String, av: String)      # somebody asks to be friends
signal friend_added(nick: String)               # a request of ours was taken
signal unread_changed
signal styled(nick: String, style: Dictionary)  # a nick looks another way now: {"tag", "rb", "col"}
signal matchmaking(d: Dictionary)               # ranked games and the quick game: r_found, r_me, q_found, q_room, q_back

var account: Account
var url := ""
var status_fn := Callable()
var link_up := false
var count := 0                      # accounts online (with ours)
var requests: Array = []            # nicks that asked us to be friends, not answered yet
var chats := {}                     # channel -> Array of {"nick", "text", "rb", "tag", "me": bool, "sys": bool}
var unread := {}                    # channel -> new messages nobody has looked at
var open_channel := "-"             # the channel the player looks at now (its messages are read at once)
var best := 0                       # the record of the train to report
var server_best := -1               # the record the server keeps (s_ok), -1 before it said
var best_proof := "user://best_proof.gz"     # the journal of the run of the record (TrainRun.packed_journal)
const PART := 48 * 1024
var _slow: Array = []               # big messages (a record's journal) sent one at a time as the link takes them
var admin := false                  # the server lets this account change how nicks look (s_admin)
var rank := {}                      # the last r_me of the server: our stage in the ranked games ({} before it said)
var _ws: WebSocketPeer = null
var _open := false
var _started := 0
var _heard := 0
var _pinged := 0
var _retry_at := 0
var _fails := 0
var _req := 0
var _answers := {}                  # req -> answer
var _sent_status := []
var _next_status := 0
var _results: Array = []            # s_result messages not sent yet (no link at the end of the game)


func setup(p_account: Account, p_url: String, p_status_fn := Callable()) -> void:
	account = p_account
	url = p_url
	status_fn = p_status_fn
	account.changed.connect(_on_account_changed)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


## The connection follows the account: a new login opens it anew, a logout closes it.
func _on_account_changed() -> void:
	if not account.logged_in():
		_close()
		count = 0
		admin = false
		requests.clear()
		chats.erase(COMMON)
		changed.emit()
	elif _ws == null:
		_retry_at = 0


## Opens the connection anew at once (another server, tests).
func reconnect() -> void:
	_close()
	_fails = 0
	_retry_at = 0


func _close() -> void:
	if _ws != null:
		_ws.close()
	_ws = null
	_open = false
	link_up = false
	_sent_status = []
	_slow = []


func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	if _ws == null:
		if account != null and account.logged_in() and now >= _retry_at:
			_connect()
		return
	_ws.poll()
	match _ws.get_ready_state():
		WebSocketPeer.STATE_CONNECTING:
			if now - _started > CONNECT_MS:
				_lost()
		WebSocketPeer.STATE_OPEN:
			if not _open:
				_open = true
				_heard = now
				_pinged = now
				_put({"op": "s_hello", "token": account.token})
			while _ws != null and _ws.get_available_packet_count() > 0:
				var data = bytes_to_var(_ws.get_packet())
				_heard = now
				if data is Dictionary:
					_on_data(data)
			if _ws == null:
				return
			while not _slow.is_empty() and _ws.get_current_outbound_buffered_amount() < PART:
				_put(_slow.pop_front())
			if link_up and now >= _next_status:
				_next_status = now + 1000
				_push_status()
			if now - _pinged > PING_MS:
				_pinged = now
				_put({"op": "ping"})
			if now - _heard > SILENCE_MS:
				_lost()
		WebSocketPeer.STATE_CLOSED:
			_lost()


func _connect() -> void:
	var ws := WebSocketPeer.new()
	ws.inbound_buffer_size = 256 * 1024
	ws.outbound_buffer_size = 64 * 1024
	if ws.connect_to_url(url) != OK:
		_retry_at = Time.get_ticks_msec() + RETRY_MS[mini(_fails, RETRY_MS.size() - 1)]
		_fails += 1
		return
	_ws = ws
	_open = false
	_started = Time.get_ticks_msec()


func _lost() -> void:
	var was := link_up
	_close()
	_retry_at = Time.get_ticks_msec() + RETRY_MS[mini(_fails, RETRY_MS.size() - 1)]
	_fails += 1
	if was:
		changed.emit()


func _put(d: Dictionary) -> void:
	if _ws != null and _open:
		_ws.put_packet(var_to_bytes(d))


func _on_data(d: Dictionary) -> void:
	if d.get("req") is int:
		_answers[d["req"]] = d
	match String(d.get("op", "")):
		"r_me":
			rank = d
			if not d.get("req") is int:
				matchmaking.emit(d)
		"r_found", "q_found", "q_room", "q_back":
			matchmaking.emit(d)
		"s_ok":
			link_up = true
			_fails = 0
			server_best = int(d.get("best", 0))
			_send_best()
			count = int(d.get("n", 0))
			admin = d.get("adm") == true
			requests = []
			for n in d.get("requests", []):
				if n is String:
					requests.append(n)
			var old: Array = chats.get(COMMON, [])
			var log := []
			for m in d.get("chat", []):
				if m is Dictionary:
					log.append(_msg(m))
			# Messages we got before the link dropped are not shown twice: the server's history wins.
			chats[COMMON] = log if not log.is_empty() or old.is_empty() else old
			for r: Dictionary in _results:
				_put(r)
			_results.clear()
			changed.emit()
		"s_error":
			if String(d.get("r", "")) == "token" and not link_up:
				# The server does not know the token: the account asks to log in again (account.gd).
				_close()
				_retry_at = Time.get_ticks_msec() + 60000
		"pong":
			if d.get("n") is int and d["n"] != count:
				count = d["n"]
				changed.emit()
		"s_msg":
			var ch := String(d.get("ch", ""))
			add(ch, _msg(d))
		"s_invited":
			if d.get("code") is String and d.get("nick") is String:
				invited.emit(d)
		"s_request":
			var nick := String(d.get("nick", ""))
			if nick != "" and not requests.has(nick):
				requests.append(nick)
				requested.emit(nick, String(d.get("av", "")))
				changed.emit()
		"s_friend_ok":
			var nick := String(d.get("nick", ""))
			requests.erase(nick)
			friend_added.emit(nick)
			changed.emit()
		"s_style":
			var nick := String(d.get("nick", ""))
			if nick == "":
				return
			var style := {"tag": String(d.get("tag", "")), "rb": d.get("rb") == true, "col": String(d.get("col", ""))}
			for ch in chats:
				for msg: Dictionary in chats[ch]:
					if msg.get("nick") == nick and not msg.get("sys", false):
						msg.merge(style, true)
			if account != null and nick == account.nick:
				account.restyle(style)
			styled.emit(nick, style)


func _msg(d: Dictionary) -> Dictionary:
	var nick := String(d.get("nick", ""))
	return {"nick": nick, "text": String(d.get("text", "")).substr(0, TEXT_MAX), "rb": d.get("rb") == true,
		"tag": String(d.get("tag", "")), "col": String(d.get("col", "")), "me": account != null and nick == account.nick and nick != ""}


## A message into a channel (from the server, from the match, or a line of the game: "sys").
func add(ch: String, msg: Dictionary) -> void:
	if ch != COMMON and ch != GAME and is_service(String(msg.get("text", ""))):
		message.emit(ch, msg)       # the eye's messages (WATCH_*): the panel answers them, the chat never shows them
		return
	if not chats.has(ch):
		chats[ch] = []
	chats[ch].append(msg)
	if chats[ch].size() > KEEP:
		chats[ch].pop_front()
	if ch != open_channel and not msg.get("me", false) and not msg.get("sys", false):
		unread[ch] = int(unread.get(ch, 0)) + 1
		unread_changed.emit()
	message.emit(ch, msg)


## The player looks at the channel: its messages are read.
func read(ch: String) -> void:
	open_channel = ch
	if unread.has(ch):
		unread.erase(ch)
		unread_changed.emit()


func unread_total() -> int:
	var n := 0
	for ch in unread:
		n += int(unread[ch])
	return n


## The match is over or a new one begins: its chat starts empty.
func clear_game() -> void:
	chats.erase(GAME)
	unread.erase(GAME)
	unread_changed.emit()


## A request with an answer: the answer of the server, or {"op": "s_error", "r": "offline" | "timeout"}.
func ask(d: Dictionary) -> Dictionary:
	if not link_up:
		return {"op": "s_error", "r": "offline"}
	_req += 1
	var req := _req
	var msg := d.duplicate()
	msg["req"] = req
	_put(msg)
	var t0 := Time.get_ticks_msec()
	while not _answers.has(req):
		if Time.get_ticks_msec() - t0 > ASK_MS or not link_up:
			return {"op": "s_error", "r": "timeout"}
		await get_tree().process_frame
	var answer: Dictionary = _answers[req]
	_answers.erase(req)
	return answer


## A message of the common chat or to a friend (channel = the friend's nick).
func say(ch: String, text: String) -> void:
	text = text.strip_edges().substr(0, TEXT_MAX)
	if text == "" or not link_up or ch == GAME:
		return
	_put({"op": "s_chat", "to": ch, "text": text})


## A game against people is over (relay «s_result»): the room, our seat token there, the game's seed.
## The server counts it when the other side says the same; without a link it waits for one.
func report_result(code: String, seat_token: String, game_seed: int, won: bool) -> void:
	if code == "" or seat_token == "" or account == null or not account.logged_in():
		return
	var d := {"op": "s_result", "code": code, "rt": seat_token, "g": game_seed, "won": won}
	if link_up:
		_put(d)
	elif _results.size() < RESULTS_KEPT:
		_results.append(d)


## An admin changes how the nick of a player looks: `fields` has "tag", "col" ("541687", "" = none) and
## or "rb". {"op": "s_done"} or an s_error; every game online gets the new look (s_style).
func restyle(nick: String, fields: Dictionary) -> Dictionary:
	return await ask({"op": "s_admin", "nick": nick, "set": fields})


## The description of our profile: {"op": "s_done"} or an s_error.
func set_bio(text: String) -> Dictionary:
	return await ask({"op": "s_bio", "text": text.replace("\n", " ").strip_edges().substr(0, BIO_MAX)})


## Seconds played as a short line: «12 ч 5 мин», «40 мин».
static func play_text(sec: int) -> String:
	var h := int(sec / 3600.0)
	var mins := int((sec % 3600) / 60.0)
	if h == 0:
		return "%d мин" % mins
	return "%d ч %d мин" % [h, mins] if mins > 0 else "%d ч" % h


## The record of the train went up on this PC: it goes to the server with the journal of its run
## (kept in best_proof until the server has a record as good), which the server plays again.
func report_best(n: int, proof: PackedByteArray) -> void:
	if n <= best or proof.is_empty():
		return
	best = n
	var f := FileAccess.open(best_proof, FileAccess.WRITE)
	if f != null:
		f.store_buffer(proof)
		f.close()
	_send_best()


func _send_best() -> void:
	if not link_up or server_best < 0 or best <= server_best or not FileAccess.file_exists(best_proof):
		return
	var proof := FileAccess.get_file_as_bytes(best_proof)
	var parts := 0
	for at in range(0, proof.size(), PART):
		_slow.append({"op": "daily_part", "i": parts, "data": proof.slice(at, at + PART)})
		parts += 1
	_slow.append({"op": "s_best", "best": best, "parts": parts})
	server_best = best      # sent once a connection; the server's own number comes with the next s_ok


func _push_status() -> void:
	if not status_fn.is_valid():
		return
	var st: Array = status_fn.call()
	if st == _sent_status:
		return
	_sent_status = st
	var d := {"op": "s_status", "st": st[0], "code": st[1], "pv": st[2] if st.size() > 2 else "friends",
		"rt": st[3] if st.size() > 3 else "", "inv": st[4] if st.size() > 4 else "all"}
	if st.size() > 5 and String(st[5]) != "":
		d["wc"] = st[5]     # the watch code of our match: the server may give it to friends (rows' "wc")
	if st.size() > 6:
		d["w"] = st[6]      # in a game: can friends watch it (a match for two online), not one against the AI
	_put(d)


## A private message of the eye (WATCH_ASK / WATCH_CODE / WATCH_NONE): handled, never shown.
static func is_service(text: String) -> bool:
	text = text.strip_edges()
	return text == WATCH_ASK or text == WATCH_NONE or watch_code_in(text) != ""


## The watch code in a message of the form WATCH_CODE + code, or "".
static func watch_code_in(text: String) -> String:
	text = text.strip_edges()
	if not text.begins_with(WATCH_CODE):
		return ""
	var code := text.substr(WATCH_CODE.length()).strip_edges().to_upper()
	if code.length() < 4 or code.length() > 8:
		return ""
	for ch in code:
		if not ((ch >= "A" and ch <= "Z") or (ch >= "0" and ch <= "9")):
			return ""
	return code


static func reason(r: String) -> String:
	return REASONS.get(r, "Не получилось")


## A status of a row as a short line.
## The stages of the ranked games as the server counts them (server/relay/rank_store.gd STAGES), from the lowest.
const STAGES := ["Бронза III", "Бронза II", "Бронза I", "Серебро III", "Серебро II", "Серебро I",
	"Золото III", "Золото II", "Золото I", "Алмаз III", "Алмаз II", "Алмаз I"]


static func stage_name(st: int) -> String:
	return STAGES[clampi(st, 0, STAGES.size() - 1)]


static func status_text(st: String) -> String:
	return {"menu": "в меню", "room": "ждёт в комнате", "room4": "собирает 2 на 2", "room3": "собирает игру на троих", "game": "в игре", "train": "в поезде",
		"watch": "наблюдает", "off": "не в сети"}.get(st, "")
