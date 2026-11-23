extends SceneTree
## Decks sent in the chat (scripts/net/deck_share.gd), headless:
##   godot --headless --path . -s res://tests/deck_share_test.gd

const CardDB = preload("res://scripts/core/card_db.gd")
const DeckShare = preload("res://scripts/net/deck_share.gd")
const Social = preload("res://scripts/net/social.gd")

var failures := 0


func _initialize() -> void:
	check_no_collisions()
	check_round_trip()
	check_long_name()
	check_not_decks()
	print("deck share tests: %d checks failed" % failures)
	quit(1 if failures > 0 else 0)


func expect(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", what)


## Every card, land and hero card has a hash of its own: a deck reads back as it was.
func check_no_collisions() -> void:
	var seen := {}
	for id: String in CardDB.card_ids():
		var k := DeckShare._h24(id) >> 2
		expect(not seen.has(k), "cards %s and %s share a hash" % [id, seen.get(k, "")])
		seen[k] = id
	var lands := {}
	for t: String in CardDB.land_types() + ["rainbow"]:
		var k := DeckShare._h24(t) >> 12
		expect(not lands.has(k) or lands[k] == t, "lands %s and %s share a hash" % [t, lands.get(k, "")])
		lands[k] = t
	var heroes := {}
	for id: String in CardDB.hero_card_ids():
		var k := DeckShare._h24(id)
		expect(not heroes.has(k), "hero cards %s and %s share a hash" % [id, heroes.get(k, "")])
		heroes[k] = id


func check_round_trip() -> void:
	var ids := CardDB.pool_ids()
	var deck := {}
	for i in 14:
		deck[ids[i * 7]] = 3 if i % 3 != 2 else 1
	deck[ids[200]] = 5      # a draft: more copies than the rules let
	var entry := {"name": "Тест «колода»", "lands": ["plain", "corn", "ice", "plain"], "deck": deck,
		"hero": CardDB.hero_card_ids()[3]}
	var text := DeckShare.encode(entry)
	expect(text != "" and text.length() <= Social.TEXT_MAX, "a deck fits one message: %d" % text.length())
	expect(DeckShare.is_deck(text), "the message is a deck")
	var back := DeckShare.decode(text)
	expect(back.get("deck") == deck, "cards come back: %s" % [back.get("deck")])
	expect(back.get("lands") == entry["lands"], "lands come back in lane order")
	expect(back.get("hero") == entry["hero"], "the hero card comes back")
	expect(int(back.get("unknown", -1)) == 0, "no unknown cards")
	expect(String(back.get("name", "")).begins_with("Тест"), "the name comes back: %s" % back.get("name"))
	var no_hero := entry.duplicate()
	no_hero.erase("hero")
	expect(not DeckShare.decode(DeckShare.encode(no_hero)).has("hero"), "a deck without a hero card")


## The longest name with 40 different cards still fits: the name gets shorter.
func check_long_name() -> void:
	var ids := CardDB.pool_ids()
	var deck := {}
	for i in 36:
		deck[ids[i]] = 1
	var text := DeckShare.encode({"name": "Я".repeat(CardDB.CUSTOM_NAME_MAX), "lands": ["plain", "plain", "plain", "plain"], "deck": deck})
	expect(text != "" and text.length() <= Social.TEXT_MAX, "a long deck fits: %d" % text.length())
	expect(DeckShare.decode(text).get("deck") == deck, "a long deck comes back")


func check_not_decks() -> void:
	for t: String in ["привет", "Колода «x» cw1:", "Колода «x» cw1:AAAA.AA.AAA", "Колода «x» cw1:!!!!.AAAAAAAA.AAAA"]:
		expect(DeckShare.decode(t).is_empty(), "not a deck: %s" % t)
