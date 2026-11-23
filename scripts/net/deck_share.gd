extends RefCounted
## A deck sent in the chat (the common one, a private one, the match's): one message of plain text
## that fits Social.TEXT_MAX, so the server passes it like any other line, and a game without this
## code still shows a readable «Колода «Name»» with the code after it.
##   «Колода «Name» cw1:<hero>.<lands>.<cards>»
## Every field is in the characters of ALPHABET (no separators inside):
##   hero  — 4 characters: 24 bits of the hero card's id hash, empty for none;
##   lands — 2 characters a land: 12 bits of the land's id hash, in lane order;
##   cards — 4 characters a card: 22 bits of the card's id hash and 2 bits of copies (1..3); a card
##           with more copies (a draft) comes again.
## Hashes and not indexes: a card added to cards.json does not move the others, so games of
## different versions read each other's decks (a card one of them does not have stays unknown).
## tests/deck_share_test.gd checks that no two cards of cards.json have one hash.

const CardDB = preload("res://scripts/core/card_db.gd")

const MARK := " cw1:"
const HEAD := "Колода «"
const ALPHABET := "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
const TEXT_MAX := 200

static var _cards := {}             # 22-bit key -> card id ("" when two cards share it)
static var _lands := {}             # 12-bit key -> land id
static var _hero_cards := {}        # 24-bit key -> hero card id


static func _h24(id: String) -> int:
	var b := id.md5_buffer()
	return (b[0] << 16) | (b[1] << 8) | b[2]


static func _enc(n: int, chars: int) -> String:
	var s := ""
	for i in chars:
		s = ALPHABET[n & 63] + s
		n >>= 6
	return s


## The number of `s` (characters of ALPHABET), -1 when there is another character.
static func _dec(s: String) -> int:
	var n := 0
	for ch in s:
		var v := ALPHABET.find(ch)
		if v < 0:
			return -1
		n = (n << 6) | v
	return n


static func _maps() -> void:
	if not _cards.is_empty():
		return
	for id: String in CardDB.card_ids():
		var k := _h24(id) >> 2
		_cards[k] = "" if _cards.has(k) else id
	for t: String in CardDB.land_types():
		_lands[_h24(t) >> 12] = t
	if not _lands.has(_h24("rainbow") >> 12):
		_lands[_h24("rainbow") >> 12] = "rainbow"
	for id: String in CardDB.hero_card_ids():
		_hero_cards[_h24(id)] = id


## The message for a saved deck ({name, lands, deck, hero?}), "" when it does not fit one message.
static func encode(entry: Dictionary) -> String:
	var code := _enc(_h24(String(entry.get("hero", ""))), 4) if String(entry.get("hero", "")) != "" else ""
	code += "."
	for t in entry.get("lands", []):
		code += _enc(_h24(String(t)) >> 12, 2)
	code += "."
	var deck: Dictionary = entry.get("deck", {})
	var ids := deck.keys()
	ids.sort()
	for id: String in ids:
		var left := int(deck[id])
		while left > 0:
			var n := mini(left, 3)
			code += _enc(((_h24(id) >> 2) << 2) | n, 4)
			left -= n
	var tail := "»" + MARK + code
	var room := TEXT_MAX - HEAD.length() - tail.length()
	if room < 1:
		return ""
	var deck_name := String(entry.get("name", "")).strip_edges().replace("»", "\"").left(room)
	return HEAD + (deck_name if deck_name != "" else "Колода") + tail


## True when the message is a deck (by its form; decode tells what is in it).
static func is_deck(text: String) -> bool:
	return text.begins_with(HEAD) and text.find("»" + MARK) > 0


## The deck of a message: {name, lands, deck, hero?, unknown: copies of cards this game does not
## know}; {} when the message is not a deck. Unknown cards are left out of "deck".
static func decode(text: String) -> Dictionary:
	text = text.strip_edges()
	if not is_deck(text):
		return {}
	_maps()
	var at := text.rfind("»" + MARK)
	var deck_name := text.substr(HEAD.length(), at - HEAD.length()).strip_edges()
	var parts := text.substr(at + 1 + MARK.length()).split(".")
	if parts.size() != 3 or parts[0].length() not in [0, 4] or parts[1].length() % 2 != 0 or parts[2].length() % 4 != 0:
		return {}
	var out := {"name": deck_name if deck_name != "" else "Колода", "lands": [], "deck": {}, "unknown": 0}
	if parts[0] != "":
		var hk := _dec(parts[0])
		if hk < 0:
			return {}
		var hero: String = _hero_cards.get(hk, "")
		if hero != "":
			out["hero"] = hero
	for i in range(0, parts[1].length(), 2):
		var k := _dec(parts[1].substr(i, 2))
		if k < 0:
			return {}
		out["lands"].append(_lands.get(k, "plain"))
	for i in range(0, parts[2].length(), 4):
		var n := _dec(parts[2].substr(i, 4))
		if n < 0:
			return {}
		var copies := n & 3
		var id: String = _cards.get(n >> 2, "")
		if id == "":
			out["unknown"] += copies
		else:
			out["deck"][id] = int(out["deck"].get(id, 0)) + copies
	return out


## The most expensive cards of a deck (by cost, the dearest first, then by name), for its picture.
static func top_cards(deck: Dictionary, n := 3) -> Array:
	var ids := deck.keys()
	ids.sort_custom(func(a, b):
		var da := CardDB.get_def(a)
		var db := CardDB.get_def(b)
		if int(da["cost"]) != int(db["cost"]):
			return int(da["cost"]) > int(db["cost"])
		return String(da["name"]) < String(db["name"]))
	return ids.slice(0, n)


static func total(deck: Dictionary) -> int:
	var s := 0
	for id in deck:
		s += int(deck[id])
	return s
