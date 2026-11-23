extends RefCounted
## Card Wars rules engine («Карточные войны»).
##
## The engine owns all game state and enforces every rule. Commands are
## coroutines: whenever something happens the engine awaits
## `animator.play(event)`, and whenever a player has to pick something it
## awaits `chooser.choose(request)`. Both hooks are optional, so the engine
## runs synchronously in headless simulations.
##
## Card abilities live in scripts/core/rules/*.gd, one file per deck. A rules
## object exposes methods named "<hook>_<ability id>" (for example
## "enter_pieclops" or "aura_atk_blood_fortress"); the engine finds them by
## name and calls them at the matching moment. See rules/base.gd for the list.

const CardDB = preload("res://scripts/core/card_db.gd")
const CardInst = preload("res://scripts/core/card_inst.gd")
const PlayerState = preload("res://scripts/core/player_state.gd")
const TrainRules = preload("res://scripts/train/train_rules.gd")
const RULES := [
	preload("res://scripts/core/rules/common.gd"),
	preload("res://scripts/core/rules/finn.gd"),
	preload("res://scripts/core/rules/jake.gd"),
	preload("res://scripts/core/rules/pb.gd"),
	preload("res://scripts/core/rules/fionna.gd"),
	preload("res://scripts/core/rules/bmo.gd"),
	preload("res://scripts/core/rules/lemongrab.gd"),
	preload("res://scripts/core/rules/gunter.gd"),
	preload("res://scripts/core/rules/lsp.gd"),
	preload("res://scripts/core/rules/marceline.gd"),
	preload("res://scripts/core/rules/ice_king.gd"),
	preload("res://scripts/core/rules/cake.gd"),
	preload("res://scripts/core/rules/rainicorn.gd"),
	preload("res://scripts/core/rules/flame_princess.gd"),
	preload("res://scripts/core/rules/fern.gd"),
	preload("res://scripts/core/rules/prismo.gd"),
	preload("res://scripts/core/rules/lich.gd"),
	preload("res://scripts/core/rules/peppermint_butler.gd"),
	preload("res://scripts/core/rules/magic_man.gd"),
	preload("res://scripts/core/rules/for_the_glory.gd"),
	preload("res://scripts/core/rules/land_of_legends.gd"),
	preload("res://scripts/core/rules/kickstarter.gd"),
	preload("res://scripts/core/rules/doubles.gd"),
	preload("res://scripts/core/rules/heroes.gd"),
]
const HOOK_PREFIXES := ["atk_", "def_", "aura_atk_", "aura_def_", "aura_dmg_", "dmg_in_", "vs_",
	"cost_", "playable_", "enter_", "leave_", "floop_", "act_", "spell_", "start_", "after_draw_",
	"battle_", "attack_", "dealt_", "hurt_", "killed_", "slain_", "moved_", "discarded_",
	"on_enter_", "sees_enter_", "on_leave_", "on_discard_", "on_freeze_", "on_burn_", "on_thaw_", "on_played_", "on_draw_", "on_hit_player_", "on_battle_", "on_moved_", "on_lane_left_", "healed_", "end_",
	"fought_", "hero_"]

const START_HP := 25
const MAX_HP := 25
const START_HAND := 5
const ACTIONS_PER_TURN := 2
## heal_creature(..., by = MOVED): the damage moves to another creature, nothing heals it.
const MOVED := -2
const LANES := 4
## 2 на 2 (the Doubles Tournament rulebook): four seats around the table, teammates across
## from each other (seats 0 and 2 against 1 and 3), turns go round the table, a team shares
## 40 hit points, every landscape faces a neighbour (see across).
const TEAM_HP := 40
## На троих (no official rules; built on the 2 на 2 table): three seats round a triangle, each
## for itself with 25 HP, lanes 0 and 1 face the next seat, 2 and 3 the one before. The first
## player at 0 HP drops out (_drop_out) and the other two play on 1 на 1, lane against lane.

var players: Array = []
var turn_player := 0
var first_player := 0
var turn_number := 0
## setup → main → attack → handoff → main ... → over
var phase := "setup"
var _tutorial_skip_first_draw := false
var winner := -1
var rng := RandomNumberGenerator.new()
var log_lines: Array = []
var fast_mode: bool = false     # RL training: no events, no log, no handoff pause
var entered_this_turn := 0      # creatures that entered play this turn (both sides)
## While on_leave_ hooks run: the state of the creature that left before it left (damage, flags…).
var leaving: Dictionary = {}
## While dealt_ hooks run: who took the fight damage, {"p", "lane" (-1: the player), "card"}.
var dealt_to: Dictionary = {}
## While healed_ hooks run: the player whose card or ability removed the damage (Пухлый пингвин:
## «когда ты снимаешь урон»), MOVED when the damage only moved on.
var heal_by := -1
## The card whose ability is running (see run_hook), null for none.
var effect_card: CardInst = null
## Where the card that just landed in a discard pile came from ("hand", "deck", "play"…), for discarded_ hooks.
var discard_from := ""
## A card being played for free, not from the hand (Лаборант).
var casting_free := false
## A frost token being removed by discarding (Ледник).
var thaw_by_discard := false
## «Бесконечный поезд»: the wagon's rule, the hero stats and items, the second enemy
## (scripts/train/train_rules.gd). Off in a plain game: then the engine never calls it.
var train: TrainRules

var animator: Object = null
## tools/train_balance.gd: with heal_log_on every heal of a hero is written down as [side, HP, place in the code].
var heal_log_on: bool = false
var heal_log: Array = []
var chooser: Object = null
## Card id of the command being run (the card asking any choice it makes);
## "" outside commands. The AI reads it; it is not part of the game state.
var cmd_source := ""
## Seed of rng given to setup: with the journal it replays the whole game.
var rng_seed := 0
## Replay journal (scripts/core/replay.gd): every call into the engine from outside
## and every answer of the chooser, in order. null (the default) records nothing.
var journal = null
## На троих: the turn player dropped out in their own turn. The phase is "over" for a moment
## so that everything still running for them stops; the outermost call then passes the turn on.
var _out_turn := false

## Undo (undo_point/undo_clean/undo_to): the player whose command is watched (-1: none)
## and whether it has shown something hidden.
var _undo_player := -1
var _undo_seen := false
var _calls := 0                 # depth of engine calls from outside: only the outermost is recorded
var _next_uid := 1
var _cards: Dictionary = {}     # uid -> CardInst
var _rules: Array = []
var _hooks: Dictionary = {}     # method name -> rules object
static var _hook_rule: Dictionary = {}   # method name -> index in RULES, found once for all games


func _init() -> void:
	CardDB.ensure_loaded()
	train = TrainRules.new(self)
	for s in RULES:
		var r = s.new()
		r.g = self
		_rules.append(r)
	if _hook_rule.is_empty():
		_build_hook_table()
	for n: String in _hook_rule:
		_hooks[n] = _rules[_hook_rule[n]]


func _build_hook_table() -> void:
	for i in _rules.size():
		for m in _rules[i].get_method_list():
			var n: String = m["name"]
			for prefix: String in HOOK_PREFIXES:
				if n.begins_with(prefix):
					if _hook_rule.has(n) and _hook_rule[n] != i:
						push_error("Card hook defined twice: " + n)
					_hook_rule[n] = i
					break


# ---------------------------------------------------------------- hooks

func has_hook(name: String) -> bool:
	return _hooks.has(name)


## Synchronous hook (stat modifiers, checks). Returns `default` if absent.
func call_hook(name: String, args: Array, default = null):
	var r = _hooks.get(name)
	if r == null:
		return default
	return r.callv(name, args)


## Coroutine hook (effects that may animate or ask for choices).
## While it runs, effect_card is the card whose ability it is (Пушистый лис: damage from a
## creature's ability); a hero card's hook has none.
func run_hook(name: String, args: Array):
	var r = _hooks.get(name)
	if r == null:
		return null
	var outer: CardInst = effect_card
	if name.begins_with("hero_"):
		effect_card = null
	elif not args.is_empty() and args[0] is CardInst:
		effect_card = args[0]
	var out = await r.callv(name, args)
	effect_card = outer
	return out


## Calls `prefix + id` for every card in play that has that ability.
## The observing card and its position come first in the arguments.
func _notify(prefix: String, args: Array) -> void:
	for e in in_play():
		var c: CardInst = e[0]
		if slot(e[1], e[2], e[3]) != c:
			continue
		for id: String in texts(c, e[1], e[2], e[3]):
			if _hooks.has(prefix + id):
				await run_hook(prefix + id, [c, e[1], e[2], e[3]] + args)
				if phase == "over":
					return


## Hero card hook of player p: "hero_<event>_<hero card id>" (rules/heroes.gd).
func hero_hook(p: int, event: String) -> String:
	return "hero_%s_%s" % [event, players[p].hero_card]


func _hero_event(p: int, event: String, args: Array = []) -> void:
	var name := hero_hook(p, event)
	if _hooks.has(name) and phase != "over" and not players[p].out:
		await run_hook(name, [p] + args)


# ---------------------------------------------------------------- setup

## heroes: one pick per seat, "deck" or "deck@hero card" (CardDB.loadout). Four picks
## make a 2 на 2 game (seats 0 and 2 are a team, 1 and 3 the other), three a game на троих.
func setup(heroes: Array, first: int, seed_value: int = -1, shuffle_decks := true) -> void:
	_tutorial_skip_first_draw = false
	if seed_value < 0:
		seed_value = randi() & 0x7fffffff
	rng.seed = seed_value
	rng_seed = seed_value
	players.clear()
	_cards.clear()
	_next_uid = 1
	var seats := mini(heroes.size(), 4) if heroes.size() >= 3 else 2
	for i in seats:
		players.append(_new_player(i, heroes[i], shuffle_decks))
	for i in range(1, seats):
		var n := 1
		var base: String = players[i].name
		while players.slice(0, i).any(func(o): return o.name == players[i].name):
			n += 1
			players[i].name = "%s %d" % [base, n]
	if seats == 4:
		_link_teams(TEAM_HP)
	first_player = first
	turn_player = first
	turn_number = 0
	phase = "setup"
	winner = -1
	entered_this_turn = 0
	for i in seats:
		for n in START_HAND:
			if not players[i].deck.is_empty():     # «Песочница»: a deck of a few cards
				players[i].hand.append(players[i].deck.pop_back())


## Reorders the ordinary Finn and Jake decks for the Basic Tutorial without creating
## cards outside either deck or changing their ownership/UIDs.
func configure_basic_tutorial() -> bool:
	if players.size() != 2 or players[0].hero != "finn" or players[1].hero != "jake":
		return false
	var opening_hands := [
		["blood_fortress", "ancient_scholar", "cool_dog", "spirit_soldier", "struzann_jinn"],
		["evil_eye", "archer_dan", "celestial_castle", "wall_of_ears", "corn_dog"],
	]
	var forced_draws := [
		["gnome_snot", "nice_ice_baby", "the_pig", "teleport", "psionic_architect"],
		["husker_knight"],
	]
	var first_turn_draws := [[], ["big_foot"]]
	for p in 2:
		var ps: PlayerState = players[p]
		var available: Array = []
		available.append_array(ps.hand)
		available.append_array(ps.deck)
		var hand: Array = []
		for id: String in opening_hands[p]:
			var c: CardInst = _take_tutorial_card(available, id)
			if c == null:
				return false
			hand.append(c)
		var draws: Array = []
		for id: String in forced_draws[p]:
			var draw_card: CardInst = _take_tutorial_card(available, id)
			if draw_card == null:
				return false
			draws.append(draw_card)
		for id: String in first_turn_draws[p]:
			var draw_card: CardInst = _take_tutorial_card(available, id)
			if draw_card == null:
				return false
			draws.push_front(draw_card)
		ps.hand.clear()
		ps.hand.append_array(hand)
		ps.deck.clear()
		ps.deck.append_array(available)
		draws.reverse()
		ps.deck.append_array(draws)
		ps.mulligan_used = true
	_tutorial_skip_first_draw = true
	return true


func _take_tutorial_card(available: Array, id: String) -> CardInst:
	for i in available.size():
		var c: CardInst = available[i]
		if c.id == id:
			available.remove_at(i)
			return c
	return null


## Player i with the deck of `pick` ("deck" or "deck@hero card"): optionally shuffled deck,
## lands in the order of the deck, no starting hand yet.
func _new_player(i: int, pick: String, shuffle_deck := true) -> PlayerState:
	var h := CardDB.hero(CardDB.loadout_deck(pick))
	var ps := PlayerState.new()
	ps.index = i
	ps.hero = CardDB.loadout_deck(pick)
	ps.hero_card = CardDB.loadout_card(pick)
	# A deck with its own hero card keeps the deck's (short) hero name.
	# Without a hero ("deck@") the deck's name too.
	ps.name = h["name"] if ps.hero_card == ps.hero or ps.hero_card == CardDB.NO_HERO else CardDB.hero_card(ps.hero_card)["name"]
	ps.hp = START_HP
	ps.max_hp = MAX_HP
	var arts := [1, 2, 3, 4]
	_shuffle(arts)
	var types: Array = h["lands"]
	for l in LANES:
		ps.lands.append({"type": types[l], "flipped": false, "art": arts[l], "frozen": false,
			"override": "", "override_until": -1, "flip_until": -1})
	for id: String in h["deck"]:
		for n in int(h["deck"][id]):
			ps.deck.append(_make_card(id, i))
	if shuffle_deck:
		_shuffle(ps.deck)
	return ps


## Before the game a player may order their landscapes (decks with two land types).
func cmd_arrange_lands(p: int, types: Array) -> void:
	_record({"t": "lands", "p": p, "types": types.duplicate()})
	await _arrange_lands(p, types)
	await _end_call()


func _arrange_lands(p: int, types: Array) -> void:
	if phase != "setup":
		return
	var cur: Array = players[p].lands.map(func(l): return l["type"])
	var a := cur.duplicate()
	var b := types.duplicate()
	a.sort()
	b.sort()
	if a != b:
		return
	for l in LANES:
		players[p].lands[l]["type"] = String(types[l])
	await _emit({"type": "lands", "p": p})


## Mulligan: shuffle the hand back and draw five new cards. Once per game.
func cmd_mulligan(p: int) -> void:
	_record({"t": "mull", "p": p})
	await _mulligan(p)
	await _end_call()


func _mulligan(p: int) -> void:
	var ps: PlayerState = players[p]
	if phase != "setup" or ps.mulligan_used:
		return
	ps.mulligan_used = true
	ps.deck.append_array(ps.hand)
	ps.hand.clear()
	_shuffle(ps.deck)
	for n in hand_size(p):
		if not ps.deck.is_empty():
			ps.hand.append(ps.deck.pop_back())
	await _log("%s меняет стартовую руку." % ps.name)
	await _emit({"type": "mulligan", "p": p})


func start_game() -> void:
	_record({"t": "start"})
	if phase == "setup":
		turn_number = 1
		turn_player = first_player
		for p in seats_from(first_player):
			await _hero_event(p, "setup")
		await _start_turn(first_player)
	await _end_call()


## An outside call into the engine starts: the journal gets it (with the state it
## applies to) unless it comes from inside another call. The caller ends it with _end_call.
func _record(step: Dictionary) -> void:
	if journal != null and _calls == 0:
		step["h"] = state_hash()
		journal.append(step)
	_calls += 1


## The end of a call started by _record. На троих: once the outermost call is over, a turn
## player who dropped out in their own turn gives the turn to the next seat.
func _end_call() -> void:
	_calls -= 1
	while _calls == 0 and _out_turn:
		_out_turn = false
		_calls += 1
		phase = "main"
		turn_player = next_seat(turn_player)
		turn_number += 1
		if fast_mode:
			await _start_turn(turn_player)
		else:
			phase = "handoff"
			await _emit({"type": "phase", "phase": phase})
		_calls -= 1


## The hero stats of a fight of the train (train_rules.gd): 0 for a stat that is not set.
func stat(p: int, key: String) -> int:
	return int(players[p].stats.get(key, 0))


func actions_per_turn(p: int) -> int:
	if train.active:
		return maxi(ACTIONS_PER_TURN + train.action_change(p), 0)
	return ACTIONS_PER_TURN


func hand_size(p: int) -> int:
	return START_HAND + stat(p, "hand")


# ---------------------------------------------------------------- basic queries

## The opponent: in 2 на 2 the next seat (an opponent all the same, and the team's hit
## points are shared, so damage to "the opponent" may go to either).
## На троих the next seat still in the game.
func opp(p: int) -> int:
	if players.size() == 3:
		return next_seat(p)
	return 1 - p if players.size() == 2 else (p + 1) % 4


func teams() -> bool:
	return players.size() == 4


## На троих: three seats, each for itself (one of them may have dropped out already).
func three() -> bool:
	return players.size() == 3


## На троих: the seat has dropped out of the game.
func is_out(p: int) -> bool:
	return players[p].out


## На троих after a player dropped out: the other two play 1 на 1.
func duel() -> bool:
	return players.size() == 3 and players.any(func(ps): return ps.out)


## The team of a seat: 0 or 1 (in an ordinary game and на троих the seat itself).
func team(p: int) -> int:
	return p % 2 if teams() else p


func is_foe(p: int, q: int) -> bool:
	return q >= 0 and team(p) != team(q)


func foes(p: int) -> Array:
	if players.size() == 3:
		return seats_from(p).filter(func(s): return s != p)
	return [1 - p] if players.size() == 2 else [(p + 1) % 4, (p + 3) % 4]


## Every seat in the game (на троих not the one that dropped out).
func sides() -> Array:
	if duel():
		return range(players.size()).filter(func(s): return not players[s].out)
	return range(players.size())


## Every seat starting with p, in turn order (на троих without the one that dropped out).
func seats_from(p: int) -> Array:
	var out := []
	for i in players.size():
		var s := (p + i) % players.size()
		if not players[s].out:
			out.append(s)
	return out


func next_seat(p: int) -> int:
	var s := (p + 1) % players.size()
	while players[s].out and s != p:
		s = (s + 1) % players.size()
	return s


## The spot across the lane from p's landscape: [side, lane]. 2 на 2 and на троих: lanes 0 and 1
## face the next seat's lanes 3 and 2, lanes 2 and 3 face the seat before's lanes 1 and 0.
## На троих after a player dropped out every lane faces the other one left, in the same mirrored
## order, so the creatures that already faced each other stay face to face.
func across(p: int, lane: int) -> Array:
	var n := players.size()
	if n == 2:
		return [1 - p, lane]
	if n == 3 and duel():
		return [next_seat(p), LANES - 1 - lane]
	return [(p + 1) % n if lane < 2 else (p + n - 1) % n, LANES - 1 - lane]


func foe_creature(p: int, lane: int) -> CardInst:
	var a := across(p, lane)
	return players[a[0]].creatures[a[1]]


## Is (q, ql) the spot across the lane from (p, lane)?
func facing(p: int, lane: int, q: int, ql: int) -> bool:
	var a := across(p, lane)
	return a[0] == q and a[1] == ql


## Is (q, ql) on the lane of (p, lane): that spot or the one across from it?
func on_lane(p: int, lane: int, q: int, ql: int) -> bool:
	return (q == p and ql == lane) or facing(p, lane, q, ql)


## Вязаный котик («на него действуют строения на соседних землях»): p's creature on `lane` is one.
func is_knit_kitty(p: int, lane: int) -> bool:
	return creature_text(p, lane, "knit_kitty")


## Is (q, ql) on the lane of p's building on `lane` for what that building does to creatures:
## on_lane, and also p's own Вязаный котик on a lane next door.
func bld_on_lane(p: int, lane: int, q: int, ql: int) -> bool:
	return on_lane(p, lane, q, ql) or (q == p and absi(ql - lane) == 1 and is_knit_kitty(q, ql))


## The same for "your creature in this lane" of a trigger: the creature (q, ql) is p's own on that lane or its kitty.
## A creature that has already left is given as `c` (its lane is empty by then).
func bld_own_lane(p: int, lane: int, q: int, ql: int, c: CardInst = null) -> bool:
	if q != p:
		return false
	if ql == lane:
		return true
	return absi(ql - lane) == 1 and (has_ability(c, "knit_kitty") if c != null else is_knit_kitty(q, ql))


## lane_spots(p, lane) with p's Вязаный котик next door as one more spot.
func bld_spots(p: int, lane: int) -> Array:
	var out := lane_spots(p, lane)
	for a in adjacent(lane):
		if is_knit_kitty(p, a):
			out.append([p, a])
	return out


## Does a building with this text stand on the lane of p's creature on `lane`, or next to it when it is a kitty?
func creature_bld_text(p: int, lane: int, id: String) -> bool:
	if spot_building_text(p, lane, id):
		return true
	if not is_knit_kitty(p, lane):
		return false
	for a in adjacent(lane):
		for e in buildings_at(p, a):
			if has_text(e[0], p, e[1], a, id):
				return true
	return false


## Both spots of p's lane as [side, lane], in seat order.
func lane_spots(p: int, lane: int) -> Array:
	var a := across(p, lane)
	return [[p, lane], a] if p < a[0] else [a, [p, lane]]


func total_lands() -> int:
	return LANES * sides().size()


## 2 на 2 and на троих: p chooses which opponent a card works on. `pred(side)` leaves out the
## ones it does not fit; -1 when none fits. An ordinary game never asks.
func pick_foe(p: int, prompt: String, pred := Callable()) -> int:
	var fs: Array = foes(p).filter(func(q): return not pred.is_valid() or pred.call(q))
	if fs.is_empty():
		return -1
	if fs.size() == 1:
		return fs[0]
	var names: Array = fs.map(func(q): return players[q].name)
	var pick = await pick_option(p, names, prompt)
	return fs[maxi(names.find(pick), 0)]


## The name of a side: a player, or both players of a team.
func side_name(p: int) -> String:
	if not teams():
		return players[p].name
	return "%s и %s" % [players[team(p)].name, players[team(p) + 2].name]


## 2 на 2: teammates share one hit point pool.
func _link_teams(hp: int) -> void:
	for t in 2:
		var pool := [hp]
		for s in [t, t + 2]:
			players[s].team_hp = pool
			players[s].max_hp = TEAM_HP


func card(uid: int) -> CardInst:
	return _cards.get(uid)


## No floops and no fights in the first turn of the game (2 на 2: in the first turn of
## each of the first three players, на троих of the first two).
func is_first_turn() -> bool:
	return turn_number < players.size()


## The opponent a card hurts when its text says "the opponent": на троих p picks one
## (`prompt`), elsewhere opp (2 на 2 a team shares its hit points, so either is the same).
func foe_to_hit(p: int, prompt: String) -> int:
	if three():
		return await pick_foe(p, prompt)
	return opp(p)


func adjacent(lane: int) -> Array:
	var out := []
	for l in [lane - 1, lane + 1]:
		if l >= 0 and l < LANES:
			out.append(l)
	return out


## Fingerprint of the whole game state, deck order and RNG included.
## Two lockstep copies of the game must always agree on it.
func state_hash() -> int:
	var parts := [turn_number, turn_player, phase, winner, rng.state, entered_this_turn]
	for ps: PlayerState in players:
		parts.append([ps.hp, ps.actions, ps.mulligan_used, ps.turn, ps.hero_card, ps.hero_state])
		if ps.burn > 0 or ps.next_actions > 0:
			parts.append([ps.burn, ps.next_actions])
		if ps.out:      # only then: the hashes of games for two and four stay as they were
			parts.append("out")
		if ps.teamwork != null:
			parts.append(_card_state(ps.teamwork))
		for zone in [ps.deck, ps.hand, ps.discard, ps.removed]:
			parts.append(zone.map(func(c): return c.uid))
		parts.append(ps.lands)
		for c in ps.creatures + ps.buildings:
			parts.append(_card_state(c))
		for lane in LANES:
			parts.append(ps.extra_buildings[lane].map(_card_state))
	train.hash_parts(parts)
	return hash(var_to_str(parts))


func _card_state(c) -> Variant:
	if c == null:
		return 0
	var s := [c.uid, c.damage, c.exhausted, c.flooped, c.moved_this_turn, c.temp_atk, c.temp_def,
		c.perm_atk, c.perm_def, c.lost_abilities, c.granted_floop, c.act_uses,
		c.under.map(func(u): return u.uid), c.flags, c.used_life]
	if c.upgraded:      # only then: the hashes of saved replays stay as they were
		s.append(true)
	return s


# ---------------------------------------------------------------- slots & positions

func slot(p: int, kind: String, lane: int) -> CardInst:
	if kind == "teamwork" and p >= 0 and p < players.size():
		return players[p].teamwork
	if p < 0 or p >= players.size() or lane < 0 or lane >= LANES:
		return null
	if kind == "creature":
		return players[p].creatures[lane]
	if kind == "building":
		return players[p].buildings[lane]
	if kind.begins_with("xb"):
		var i := int(kind.substr(2))
		var arr: Array = players[p].extra_buildings[lane]
		return arr[i] if i < arr.size() else null
	return null


func is_building_kind(kind: String) -> bool:
	return kind == "building" or kind.begins_with("xb")


## Every building on one land: the main one and any extra ones, as [card, kind].
func buildings_at(p: int, lane: int) -> Array:
	var out := []
	var b: CardInst = players[p].buildings[lane]
	if b != null:
		out.append([b, "building"])
	var extra: Array = players[p].extra_buildings[lane]
	for i in extra.size():
		out.append([extra[i], "xb%d" % i])
	return out


## Every card in play as [card, controller, kind, lane].
func in_play() -> Array:
	var out := []
	for p in players.size():
		var ps: PlayerState = players[p]
		for lane in LANES:
			if ps.creatures[lane] != null:
				out.append([ps.creatures[lane], p, "creature", lane])
			for e in buildings_at(p, lane):
				out.append([e[0], p, e[1], lane])
		if ps.teamwork != null:
			out.append([ps.teamwork, p, "teamwork", -1])
	return out


## Locates a card: {"zone": deck|hand|discard|removed|creature|building|under|limbo,
## "p": controller, "lane": int, "kind": slot kind for cards in play}
func where(uid: int) -> Dictionary:
	for p in players.size():
		var ps: PlayerState = players[p]
		for lane in LANES:
			if ps.creatures[lane] != null:
				if ps.creatures[lane].uid == uid:
					return {"zone": "creature", "p": p, "lane": lane, "kind": "creature"}
				for u in ps.creatures[lane].under:
					if u.uid == uid:
						return {"zone": "under", "p": p, "lane": lane, "host": ps.creatures[lane].uid}
			for e in buildings_at(p, lane):
				if e[0].uid == uid:
					return {"zone": "building", "p": p, "lane": lane, "kind": e[1]}
		if ps.teamwork != null and ps.teamwork.uid == uid:
			return {"zone": "teamwork", "p": p, "lane": -1, "kind": "teamwork"}
		for zone in ["hand", "discard", "deck", "removed"]:
			var arr: Array = ps.get(zone)
			for i in arr.size():
				if arr[i].uid == uid:
					return {"zone": zone, "p": p, "lane": -1, "index": i}
	return {"zone": "limbo", "p": -1, "lane": -1}


# ---------------------------------------------------------------- abilities in play

## Opponent's flooped Пёс on this lane leaves p's buildings without text.
func building_blanked(p: int, lane: int) -> bool:
	var dog: CardInst = foe_creature(p, lane)
	return dog != null and dog.flooped and dog.ab() == "the_dog" and not dog.lost_abilities


## The abilities a card in play currently has (empty if it lost its text).
func texts(c: CardInst, p: int, kind: String, lane: int) -> Array:
	if c == null or c.lost_abilities:
		return []
	if kind == "creature" or kind == "teamwork":
		return [c.ab()]
	if building_blanked(p, lane):
		return []
	var base := c.ab()
	if base != "learning_center":
		return [base]
	# Учебный центр: copies the text of p's buildings on neighbouring lanes.
	var out := ["learning_center"]
	for adj in adjacent(lane):
		if building_blanked(p, adj):
			continue
		for e in buildings_at(p, adj):
			var b: CardInst = e[0]
			if not b.lost_abilities and b.ab() != "learning_center" and not out.has(b.ab()):
				out.append(b.ab())
	return out


func has_text(c: CardInst, p: int, kind: String, lane: int, id: String) -> bool:
	return texts(c, p, kind, lane).has(id)


func has_ability(c: CardInst, id: String) -> bool:
	return c != null and c.ab() == id and not c.lost_abilities


## Does player p control a card in play with this ability?
func controls_text(p: int, id: String) -> bool:
	return count_text(p, id) > 0


func count_text(p: int, id: String) -> int:
	var n := 0
	for e in in_play():
		if e[1] == p and has_text(e[0], e[1], e[2], e[3], id):
			n += 1
	return n


## A building with this ability on the lane (either side, or only `side`).
## 2 на 2 the lane number alone names no lane: see spot_building_text.
func lane_building_text(lane: int, id: String, side := -1) -> bool:
	for p in players.size():
		if side >= 0 and p != side:
			continue
		for e in buildings_at(p, lane):
			if has_text(e[0], p, e[1], lane, id):
				return true
	return false


## A building with this ability on the lane of (p, lane): on either of its spots, or only on `side`'s.
func spot_building_text(p: int, lane: int, id: String, side := -1) -> bool:
	for s in lane_spots(p, lane):
		if side >= 0 and s[0] != side:
			continue
		for e in buildings_at(s[0], s[1]):
			if has_text(e[0], s[0], e[1], s[1], id):
				return true
	return false


func creature_text(p: int, lane: int, id: String) -> bool:
	var c: CardInst = players[p].creatures[lane]
	return c != null and has_text(c, p, "creature", lane, id)


# ---------------------------------------------------------------- land types

## The type the land currently counts as ("" while face down).
func land_type(p: int, lane: int) -> String:
	var l: Dictionary = players[p].lands[lane]
	if l["flipped"]:
		return ""
	if l.get("override", "") != "":
		return l["override"]
	return l["type"]


## Lands of a type p controls; "rainbow" counts every face-up land.
func land_count(p: int, type: String) -> int:
	var n := 0
	for lane in LANES:
		var t := land_type(p, lane)
		if t != "" and (type == "rainbow" or t == type):
			n += 1
	if type == "corn" or type == "rainbow":
		n += count_text(p, "farmhouse") + count_text(p, "sun_king")
	# Манежный танцзал: a copy of the land of its lane.
	for lane in LANES:
		var t := land_type(p, lane)
		if t != "" and (type == "rainbow" or t == type):
			for e in buildings_at(p, lane):
				if has_text(e[0], p, e[1], lane, "dressage_dance_hall"):
					n += 1
	return n


func corn_count(p: int) -> int:
	return land_count(p, "corn")


func unique_land_types(p: int) -> int:
	var types := {}
	for lane in LANES:
		var t := land_type(p, lane)
		if t != "":
			types[t] = true
	if controls_text(p, "farmhouse") or controls_text(p, "sun_king"):
		types["corn"] = true
	return types.size()


func flipped_lands() -> int:
	var n := 0
	for ps: PlayerState in players:
		for l: Dictionary in ps.lands:
			if l["flipped"]:
				n += 1
	return n


func is_frozen(p: int, lane: int) -> bool:
	return players[p].lands[lane].get("frozen", false)


## Frozen lands of one player, or of all (p = -1).
func frozen_count(p := -1) -> int:
	var n := 0
	for side in players.size():
		if p >= 0 and side != p:
			continue
		for lane in LANES:
			if is_frozen(side, lane):
				n += 1
	return n


# ---------------------------------------------------------------- card types

## Types a card counts as. Creatures in play may become Rainbow
## (Очаровательный город, Щенячий парад); Синюшный чудила makes hand cards Rainbow.
func card_types(c: CardInst, p := -1, lane := -1) -> Array:
	var d := c.def()
	if c.flags.get("rainbow", false):
		return ["rainbow"]
	if p >= 0 and lane >= 0 and d["kind"] == "creature" and players[p].creatures[lane] == c:
		if players[p].turn.get("rainbow_creatures", false) or creature_bld_text(p, lane, "charming_city"):
			return ["rainbow"]
	var out := [String(c.flags.get("land_as", d["land"]))]
	if not c.lost_abilities:
		out.append_array(d.get("also", []))
	return out


func is_type(c: CardInst, type: String, p := -1, lane := -1) -> bool:
	return c != null and card_types(c, p, lane).has(type)


## Land type a card needs to be played.
func play_land(c: CardInst) -> String:
	return "rainbow" if c.flags.get("rainbow", false) else c.def()["land"]


# ---------------------------------------------------------------- stats

func atk_of(p: int, lane: int) -> int:
	var c: CardInst = players[p].creatures[lane]
	if c == null:
		return 0
	var a: int = c.def()["atk"] + c.perm_atk + c.temp_atk + tokens(c, "atk_tok")
	if c.upgraded:
		a += 1
	for id: String in texts(c, p, "creature", lane):
		a += call_hook("atk_" + id, [c, p, lane], 0)
	for e in in_play():
		for id: String in texts(e[0], e[1], e[2], e[3]):
			if _hooks.has("aura_atk_" + id):
				a += call_hook("aura_atk_" + id, [e[0], e[1], e[3], c, p, lane], 0)
				if e[1] == p and is_building_kind(e[2]) and absi(e[3] - lane) == 1 and has_text(c, p, "creature", lane, "knit_kitty"):
					a += call_hook("aura_atk_" + id, [e[0], e[1], e[3], c, p, e[3]], 0)
	a += call_hook(hero_hook(p, "atk"), [p, c, lane], 0)
	if train.active:
		a += train.atk_bonus(p)
	var t: Dictionary = players[p].turn
	if t.get("cross_poll", 0) > 0 and is_type(c, "corn", p, lane):
		a += int(t["cross_poll"]) * unique_land_types(p)
	# Гейзерная пушка: friendly creatures of its lane doubled while its controller's hand is 1 card or none.
	for s in lane_spots(p, lane):
		if not is_foe(p, s[0]) and players[s[0]].hand.size() <= 1:
			for e in buildings_at(s[0], s[1]):
				if has_text(e[0], s[0], e[1], s[1], "geyser_cannon"):
					a *= 2
	if is_knit_kitty(p, lane) and players[p].hand.size() <= 1:
		for l in adjacent(lane):
			for e in buildings_at(p, l):
				if has_text(e[0], p, e[1], l, "geyser_cannon"):
					a *= 2
	# Перекормленный орангутан: doubled with 4 damage or more.
	if c.damage >= 4 and has_text(c, p, "creature", lane, "overstuffed_orangutan"):
		a *= 2
	# Трутовый тиран: doubled while its controller has 1 card in hand or none.
	if has_text(c, p, "creature", lane, "tinder_tyrant") and players[p].hand.size() <= 1:
		a *= 2
	# Зебророг-осадолущитель: doubled in p's turn after two non-Cornfield cards.
	if p == turn_player and has_text(c, p, "creature", lane, "zebracorn_seige_shucker") and played_not(p, "corn") >= 2:
		a *= 2
	# Медведь-пират: tripled on a Useless Swamp.
	if has_text(c, p, "creature", lane, "pirate_bear") and land_type(p, lane) == "swamp":
		a *= 3
	# Бессмертный маисовый ходок: its ATK is tripled while it is on a Cornfield.
	if has_text(c, p, "creature", lane, "immortal_maize_walker") and land_type(p, lane) == "corn":
		a *= 3
	return maxi(a, 0)


func def_of(p: int, lane: int) -> int:
	var c: CardInst = players[p].creatures[lane]
	if c == null:
		return 0
	var d: int = c.def()["def"] + c.perm_def + c.temp_def
	if c.upgraded:
		d += 1
	for id: String in texts(c, p, "creature", lane):
		d += call_hook("def_" + id, [c, p, lane], 0)
	for e in in_play():
		for id: String in texts(e[0], e[1], e[2], e[3]):
			if _hooks.has("aura_def_" + id):
				d += call_hook("aura_def_" + id, [e[0], e[1], e[3], c, p, lane], 0)
				if e[1] == p and is_building_kind(e[2]) and absi(e[3] - lane) == 1 and has_text(c, p, "creature", lane, "knit_kitty"):
					d += call_hook("aura_def_" + id, [e[0], e[1], e[3], c, p, e[3]], 0)
	d += call_hook(hero_hook(p, "def"), [p, c, lane], 0)
	if train.active:
		d = train.def_of(p, lane, c, d)
	return d


## Remaining toughness shown on the card.
func hp_of(p: int, lane: int) -> int:
	var c: CardInst = players[p].creatures[lane]
	return 0 if c == null else def_of(p, lane) - c.damage


## ATK in a fight against `other` (situational bonuses).
func combat_atk(p: int, lane: int, other: CardInst, olane: int, attacking: bool) -> int:
	var c: CardInst = players[p].creatures[lane]
	if c == null:
		return 0
	var a := atk_of(p, lane)
	for id: String in texts(c, p, "creature", lane):
		a += call_hook("vs_" + id, [c, p, lane, other, olane, attacking], 0)
	# Кондитерское кольцо и другие: +2 this turn when attacking a creature on a land of that type.
	if attacking and other != null:
		var w := where(other.uid)
		if w["zone"] == "creature":
			var t := land_type(w["p"], w["lane"])
			a += int(players[p].turn.get("vs_land", {}).get(t, 0))
	if attacking and train.active:
		a += train.attack_bonus(p, other != null)
	return maxi(a, 0)


func count_flooped(p: int) -> int:
	var n := 0
	for c: CardInst in players[p].creatures:
		if c != null and c.flooped:
			n += 1
	return n


func count_exhausted(p: int) -> int:
	var n := 0
	for c: CardInst in players[p].creatures:
		if c != null and c.exhausted:
			n += 1
	return n


func creature_count(p: int) -> int:
	var n := 0
	for c in players[p].creatures:
		if c != null:
			n += 1
	return n


func building_count(p: int) -> int:
	var n := 0
	for lane in LANES:
		n += buildings_at(p, lane).size()
	return n


func creature_lanes(p: int) -> Array:
	var out := []
	for lane in LANES:
		if players[p].creatures[lane] != null:
			out.append(lane)
	return out


func empty_lanes(p: int) -> Array:
	var out := []
	for lane in LANES:
		if players[p].creatures[lane] == null and _lane_open(lane):
			out.append(lane)
	return out


## Every 5 cards in p's discard pile.
func discard_fives(p: int) -> int:
	return players[p].discard.size() / 5


func turn_value(p: int, key: String, default = 0):
	return players[p].turn.get(key, default)


func add_turn(p: int, key: String, amount: int = 1) -> void:
	players[p].turn[key] = int(players[p].turn.get(key, 0)) + amount


# ---------------------------------------------------------------- costs & playing

## lane: where a creature would go (Бух: a creature replaced there makes it cheaper); -1 when unknown.
func cost_of(p: int, c: CardInst, lane := -1) -> int:
	var d := c.def()
	var cost: int = d["cost"]
	cost += call_hook("cost_" + c.ab(), [c, p], 0)
	cost += call_hook(hero_hook(p, "cost"), [p, c], 0)
	if d.get("whump", false) and not c.lost_abilities:
		cost -= count_text(p, "polished_armourdillo")
		if lane >= 0 and players[p].creatures[lane] != null:
			cost -= int(players[p].creatures[lane].def()["cost"])
	if c.upgraded and d["kind"] != "creature":
		cost -= 1
	if d["kind"] == "spell":
		cost -= int(turn_value(p, "spell_discount"))
		# Эрленмейер Спокойный: the second spell of the turn is cheaper.
		if int(turn_value(p, "spells")) == 1:
			cost -= count_text(p, "erlenmeyer_the_calm")
	# Клон: the next creature or building is free when one of that name is in play.
	if turn_value(p, "clone", false) and (d["kind"] == "creature" or d["kind"] == "building"):
		for e in in_play():
			if e[0] != c and e[0].card_name() == c.card_name():
				return 0
	# Шпаргалка: the next two «Зелье» cards cost 1 less.
	if int(turn_value(p, "potion_discount")) > 0 and is_potion(c):
		cost -= 1
	elif d["kind"] == "creature":
		cost -= int(turn_value(p, "creature_discount"))
	if train.active:
		cost = train.item_cost(p, c, cost)
	# Рентгеновские очки, Светлячок-фонарщик: +1 for each card already played from the top of the deck this turn.
	if c == xray_top(p):
		cost += int(turn_value(p, "xray_played"))
	return maxi(cost, 0)


## The cost in the circle is both actions and lands of the card's type. In Жара a
## creature needs one land more (never more than there are lands).
func land_ok(p: int, c: CardInst, lane := -1) -> bool:
	return land_count(p, play_land(c)) >= lands_needed(p, c, lane)


func lands_needed(p: int, c: CardInst, lane := -1) -> int:
	var cost := cost_of(p, c, lane)
	if train.active:
		cost = train.lands_needed(c, cost)
	# A card of a land type costing 0 still needs one face-up land of its type.
	return maxi(cost, 0 if play_land(c) == "rainbow" else 1)


## Compatibility helper for the UI: land requirement from a definition.
func land_req_ok(p: int, d: Dictionary) -> bool:
	var need: int = maxi(int(d["cost"]), 0 if d["land"] == "rainbow" else 1)
	return land_count(p, d["land"]) >= need


## A lane a wagon of the train has not closed.
func _lane_open(lane: int) -> bool:
	return not train.active or train.lane_open(lane)


func lane_actions(p: int, lane: int) -> int:
	return int(players[p].turn.get("lane_actions", {}).get(lane, 0))


func creature_lane_ok(p: int, lane: int, c: CardInst = null) -> bool:
	if lane < 0 or lane >= LANES or not _lane_open(lane):
		return false
	if is_frozen(p, lane) and (c == null or c.ab() != "frosted_deanimator") and not controls_text(p, "blizzard_born") \
			and not spot_building_text(p, lane, "ice_base", p) and not _coordinated(p):
		return false
	if c != null and int(c.def().get("only_lane", -1)) >= 0 and lane != int(c.def()["only_lane"]):
		return false
	var cur: CardInst = players[p].creatures[lane]
	if cur == null:
		return true
	if c != null and c.def().get("shares", false) and not cur.under.any(func(u): return u.flags.get("guard", false)):
		return true      # Голографический кролик, Корочкодав: shares the land instead of replacing
	if cur.exhausted:
		return false
	if cur.def().get("no_replace", false) and not cur.lost_abilities:
		return false
	return true


func building_lane_ok(p: int, lane: int, _c: CardInst = null) -> bool:
	if lane < 0 or lane >= LANES or not _lane_open(lane):
		return false
	var cur: CardInst = players[p].buildings[lane]
	if cur == null or creature_text(p, lane, "burly_lumberjack"):
		return true
	return not cur.exhausted


func spell_castable(p: int, c: CardInst) -> bool:
	if train.active and train.spells_banned():
		return false
	# Призрачный ниндзя: no spells in the player's next turn.
	var hit_at := int(players[p].hero_state.get("no_spells_at", -1))
	if hit_at >= 0 and p == turn_player and turn_number > hit_at and turn_number <= hit_at + players.size():
		return false
	return call_hook("playable_" + c.id, [c, p], true)


func _own_turn_main(p: int) -> bool:
	return phase == "main" and p == turn_player


## Can card `uid` from p's hand be played? lane = -1 asks "into any lane".
func can_play(p: int, uid: int, lane: int = -1) -> bool:
	if not _own_turn_main(p):
		return false
	var ps: PlayerState = players[p]
	var c := hand_or_xray(p, uid)
	if c == null:
		return false
	var d := c.def()
	var cost := cost_of(p, c)
	if not land_ok(p, c, lane if d["kind"] == "creature" else -1) and not (d.get("whump", false) and lane < 0):
		return false
	if ps.turn.get("creature_only", false) and d["kind"] != "creature":
		return false
	# Живая пустыня: its controller plays no creatures.
	if d["kind"] == "creature" and controls_text(p, "living_desert"):
		return false
	# Пентамилашка: the opponents of its controller can't play cards of printed cost 0.
	if int(d["cost"]) == 0 and foes(p).any(func(o): return controls_text(o, "pentacutie")):
		return false
	match d.get("extra_cost", ""):
		"discard":
			if ps.hand.size() < (2 if c in ps.hand else 1):
				return false
		"floop_creature":
			if is_first_turn() or _ready_creatures(p).is_empty():
				return false
	match d["kind"]:
		"creature":
			if not call_hook("playable_" + c.id, [c, p], true):
				return false
			if lane < 0:
				for l in LANES:
					if creature_lane_ok(p, l, c) and land_ok(p, c, l) and ps.actions + lane_actions(p, l) >= cost_of(p, c, l):
						return true
				return false
			cost = cost_of(p, c, lane)
			return creature_lane_ok(p, lane, c) and land_ok(p, c, lane) and ps.actions + lane_actions(p, lane) >= cost
		"building":
			if ps.actions < cost or not call_hook("playable_" + c.id, [c, p], true):
				return false
			if lane < 0:
				for l in LANES:
					if building_lane_ok(p, l, c):
						return true
				return false
			return building_lane_ok(p, lane, c)
		"spell":
			return ps.actions >= cost and spell_castable(p, c)
		"teamwork":
			# One a turn; it lies by the lands, a new one sends the old one to the discard pile.
			return ps.actions >= cost and not ps.turn.get("teamwork_played", false) \
				and call_hook("playable_" + c.id, [c, p], true)
	return false


## Рентгеновские очки: until the end of the turn the top card of p's deck lies open and may be played.
## Светлячок-фонарщик: the same while p has 1 card in hand or none.
func xray_top(p: int) -> CardInst:
	var ps: PlayerState = players[p]
	if ps.deck.is_empty():
		return null
	if not ps.turn.get("xray", false) and not (ps.hand.size() <= 1 and controls_text(p, "firefly_lamplighter")):
		return null
	return ps.deck.back()


## The card p may play by uid: from the hand or the open top of the deck.
func hand_or_xray(p: int, uid: int) -> CardInst:
	var c := _find(players[p].hand, uid)
	if c == null and xray_top(p) != null and xray_top(p).uid == uid:
		c = xray_top(p)
	return c


func play_lanes(p: int, uid: int) -> Array:
	var out := []
	var c := hand_or_xray(p, uid)
	if c == null or c.kind() == "spell":
		return out
	for lane in LANES:
		if can_play(p, uid, lane):
			out.append(lane)
	return out


func _ready_creatures(p: int) -> Array:
	var out := []
	for lane in LANES:
		var c: CardInst = players[p].creatures[lane]
		if c != null and not c.exhausted:
			out.append(lane)
	return out


# ---------------------------------------------------------------- floops & abilities

## Лединочная камера: creatures on frozen lands of its lane can't attack or use abilities.
func silenced(p: int, lane: int) -> bool:
	return is_frozen(p, lane) and spot_building_text(p, lane, "ice_olation_cell")


func floop_ability(c: CardInst, p := -1, kind := "", lane := -1) -> String:
	if c == null:
		return ""
	if c.granted_floop != "":
		return c.granted_floop
	if c.lost_abilities:
		return ""
	var ids := texts(c, p, kind, lane) if p >= 0 else [c.ab()]
	for id: String in ids:
		if CardDB.has_def(id) and CardDB.get_def(id).get("floop", false):
			return id
	return ""


func _floop_cost_ok(p: int, cost: String, _src: CardInst) -> bool:
	match cost:
		"action":
			return players[p].actions >= 1 and not players[p].turn.get("creature_only", false)
		"discard":
			return not players[p].hand.is_empty()
		"destroy_creature":
			# Any creature you control, the flooping one too (rulebook, Док Смерть).
			return players[p].creatures.any(func(c): return c != null)
		"destroy_building":
			return building_count(p) > 0
	return true


func can_floop(p: int, kind: String, lane: int) -> bool:
	if not _own_turn_main(p) or is_first_turn():
		return false
	var c := slot(p, kind, lane)
	if c == null or c.exhausted:
		return false
	if kind == "creature":
		if silenced(p, lane):
			return false
		for s in lane_spots(p, lane):
			if creature_text(s[0], s[1], "woadic_enchantress"):
				return false
	return own_floop_ok(p, kind, lane) or hero_floop_ok(p, kind, lane)


## The card's own floop (or one it was given) can be paid for and used.
func own_floop_ok(p: int, kind: String, lane: int) -> bool:
	var c := slot(p, kind, lane)
	var ab := floop_ability(c, p, kind, lane)
	if ab == "":
		return false
	if not _floop_cost_ok(p, CardDB.get_def(ab).get("floop_cost", ""), c):
		return false
	return call_hook("floop_ok_" + ab, [c, p, kind, lane], true)


## Финн (hero card): p's creatures may have a floop from the hero.
func hero_floop_ok(p: int, kind: String, lane: int) -> bool:
	if kind != "creature" or not _hooks.has(hero_hook(p, "floop")):
		return false
	return call_hook(hero_hook(p, "floop_ok"), [p, players[p].creatures[lane], lane], true)


## Active hero card ability: needs a "hero_power_<id>" hook.
func can_hero_power(p: int) -> bool:
	if not _own_turn_main(p) or players[p].turn.get("creature_only", false):
		return false
	return _hooks.has(hero_hook(p, "power")) and call_hook(hero_hook(p, "power_ok"), [p], true)


func act_ability(c: CardInst, p: int, kind: String, lane: int) -> String:
	for id: String in texts(c, p, kind, lane):
		if CardDB.has_def(id) and CardDB.get_def(id).has("activated"):
			return id
	return ""


func activation_cost(p: int, kind: String, lane: int) -> int:
	var c := slot(p, kind, lane)
	if c == null:
		return 0
	var ab := act_ability(c, p, kind, lane)
	return 0 if ab == "" else int(CardDB.get_def(ab)["activated"])


func can_activate(p: int, kind: String, lane: int) -> bool:
	if not _own_turn_main(p):
		return false
	var c := slot(p, kind, lane)
	if c == null:
		return false
	var ab := act_ability(c, p, kind, lane)
	if ab == "":
		return false
	if kind == "creature" and silenced(p, lane):
		return false
	var d := CardDB.get_def(ab)
	var ps: PlayerState = players[p]
	var cost: int = d["activated"]
	if cost > 0 and (ps.actions < cost or ps.turn.get("creature_only", false)):
		return false
	var limit: int = d.get("act_limit", 0)
	if limit > 0 and c.act_uses >= limit:
		return false
	match d.get("act_cost", ""):
		"discard":
			if ps.hand.is_empty():
				return false
		"remove_freeze":
			if not is_frozen(p, lane):
				return false
	return call_hook("act_ok_" + ab, [c, p, kind, lane], true)


func can_draw_for_action(p: int) -> bool:
	return _own_turn_main(p) and players[p].actions >= 1 and not players[p].deck.is_empty() \
		and not players[p].turn.get("creature_only", false)


## Discard a card to remove the frost token from one of your lands (main phase of your turn).
func can_thaw(p: int, lane: int) -> bool:
	return _own_turn_main(p) and is_frozen(p, lane) and players[p].hand.size() >= thaw_cost(p, lane)


## Cards to discard to thaw p's land: one, and one more for each opposing Кафе «Холодный рожок» on the lane.
func thaw_cost(p: int, lane: int) -> int:
	var n := 1
	for s in lane_spots(p, lane):
		if is_foe(p, s[0]):
			for e in buildings_at(s[0], s[1]):
				if has_text(e[0], s[0], e[1], s[1], "cool_cone_cafe"):
					n += 1
	return n


# ---------------------------------------------------------------- attacks

func protected_by_cool_dog(side: int, lane: int) -> bool:
	for adj in adjacent(lane):
		if creature_text(side, adj, "cool_dog"):
			return true
	return false


## Пещера одиночества: hidden from the opponent until its owner's next turn.
func shielded(side: int, lane: int) -> bool:
	var c: CardInst = players[side].creatures[lane]
	return c != null and c.flags.has("shield_until")


func can_be_attacked(side: int, lane: int) -> bool:
	return not protected_by_cool_dog(side, lane) and not shielded(side, lane)


func can_attack(p: int, lane: int) -> bool:
	if p != turn_player or not (phase == "main" or phase == "attack") or is_first_turn():
		return false
	var c: CardInst = players[p].creatures[lane]
	if c == null or c.exhausted or silenced(p, lane) or not _lane_open(lane):
		return false
	if c.def().get("no_attack", false) and not c.lost_abilities:
		return false
	var a := across(p, lane)
	if players[a[0]].creatures[a[1]] != null and not can_be_attacked(a[0], a[1]):
		return false
	if players[a[0]].creatures[a[1]] == null and hero_shielded(a[0]):
		return false
	return true


## Щит Магического человека (a wagon of the train): no attacks on the hero.
func hero_shielded(side: int) -> bool:
	return train.active and train.hero_shielded(side)


func attackers_left(p: int) -> Array:
	var out := []
	for lane in LANES:
		if can_attack(p, lane):
			out.append(lane)
	return out


## Координация: the team may play creatures onto frozen lands while one of theirs stands on one.
func _coordinated(p: int) -> bool:
	if not team_has(p, "coordination"):
		return false
	for s in team_of(p):
		for l in LANES:
			if players[s].creatures[l] != null and is_frozen(s, l):
				return true
	return false


## Облачная башня: an opponent can't pick p's creature of its lane with spells or creature abilities.
func cloud_hidden(chooser_p: int, side: int, lane: int) -> bool:
	if not is_foe(chooser_p, side) or cmd_source == "" or not CardDB.has_def(cmd_source):
		return false
	var k: String = CardDB.get_def(cmd_source)["kind"]
	if k != "spell" and k != "creature":
		return false
	var lanes := [lane]
	if is_knit_kitty(side, lane):
		lanes.append_array(adjacent(lane))
	for l in lanes:
		for e in buildings_at(side, l):
			if has_text(e[0], side, e[1], l, "cloud_tower"):
				return true
	return false


## Every legal command for the active player (used by bots and for UI hints).
func legal_commands(p: int) -> Array:
	var out := []
	if p != turn_player:
		return out
	if phase == "main":
		var cards: Array = players[p].hand.duplicate()
		if xray_top(p) != null:
			cards.append(xray_top(p))
		for c: CardInst in cards:
			if c.kind() == "spell" or c.kind() == "teamwork":
				if can_play(p, c.uid):
					out.append({"cmd": "play", "uid": c.uid, "lane": -1})
			else:
				for lane in play_lanes(p, c.uid):
					out.append({"cmd": "play", "uid": c.uid, "lane": lane})
		for e in in_play():
			if e[1] != p:
				continue
			if can_floop(p, e[2], e[3]):
				out.append({"cmd": "floop", "kind": e[2], "lane": e[3]})
				if own_floop_ok(p, e[2], e[3]) and hero_floop_ok(p, e[2], e[3]):
					out.append({"cmd": "floop", "kind": e[2], "lane": e[3], "hero": true})
			if can_activate(p, e[2], e[3]):
				out.append({"cmd": "activate", "kind": e[2], "lane": e[3]})
		for lane in LANES:
			if can_thaw(p, lane):
				out.append({"cmd": "thaw", "lane": lane})
		if can_hero_power(p):
			out.append({"cmd": "hero"})
		if can_draw_for_action(p):
			out.append({"cmd": "draw"})
		if not attackers_left(p).is_empty():
			out.append({"cmd": "begin_attack"})
	if phase == "attack":
		for lane in attackers_left(p):
			out.append({"cmd": "attack", "lane": lane})
	if phase == "main" or phase == "attack":
		out.append({"cmd": "end_turn"})
	return out


func run_command(p: int, c: Dictionary) -> void:
	_record({"t": "cmd", "p": p, "c": c.duplicate()})
	var outer := cmd_source
	cmd_source = command_card(p, c)
	await _run_command(p, c)
	cmd_source = outer
	await _end_call()


## Card id a command works with ("" for draw, begin_attack, end_turn).
func command_card(p: int, c: Dictionary) -> String:
	match c["cmd"]:
		"play":
			var h: CardInst = card(int(c["uid"]))
			return h.id if h != null else ""
		"floop", "activate", "attack":
			var s: CardInst = slot(p, c.get("kind", "creature"), int(c["lane"]))
			return s.id if s != null else ""
		"hero":
			return players[p].hero_card
	return ""


func _run_command(p: int, c: Dictionary) -> void:
	match c["cmd"]:
		"play":
			await cmd_play(p, int(c["uid"]), int(c["lane"]))
		"floop":
			await cmd_floop(p, c["kind"], int(c["lane"]), bool(c.get("hero", false)))
		"activate":
			await cmd_activate(p, c["kind"], int(c["lane"]))
		"thaw":
			await cmd_thaw(p, int(c["lane"]))
		"hero":
			await cmd_hero_power(p)
		"draw":
			await cmd_draw_for_action(p)
		"begin_attack":
			await cmd_begin_attack(p)
		"attack":
			await cmd_attack(p, int(c["lane"]))
		"end_turn":
			await cmd_end_turn(p)
		"concede":
			await _concede(p)


# ---------------------------------------------------------------- commands

func cmd_play(p: int, uid: int, lane: int = -1) -> void:
	if not can_play(p, uid, lane):
		return
	var ps: PlayerState = players[p]
	var c := hand_or_xray(p, uid)
	var d := c.def()
	if d["kind"] != "spell" and d["kind"] != "teamwork" and lane < 0:
		return
	var from_deck := c == xray_top(p)
	var cost := cost_of(p, c, lane if d["kind"] == "creature" else -1)
	match d.get("extra_cost", ""):
		"discard":
			var options := []
			for h: CardInst in ps.hand:
				if h != c:
					options.append(h.uid)
			var pick = await _choose({"kind": "hand_card", "player": p, "options": options,
				"prompt": "%s: сбрось карту (дополнительная плата)" % d["name"]})
			if pick == null:
				return
			await discard_card(p, _find(ps.hand, pick))
		"floop_creature":
			var opts := []
			for l in _ready_creatures(p):
				opts.append({"p": p, "lane": l})
			var pick = await _choose({"kind": "creature", "player": p, "options": opts,
				"prompt": "%s: флюпни своё существо (дополнительная плата)" % d["name"]})
			if pick == null:
				return
			var f: CardInst = ps.creatures[pick["lane"]]
			f.exhausted = true
			f.flooped = true
			await _emit({"type": "floop", "p": p, "kind": "creature", "lane": pick["lane"], "uid": f.uid})
	# Pay: Пирамидия's lane action first, then normal actions.
	var pay := cost
	if d["kind"] == "creature" and lane >= 0:
		var la := lane_actions(p, lane)
		if la > 0:
			var used := mini(la, pay)
			ps.turn["lane_actions"][lane] = la - used
			pay -= used
	ps.actions -= pay
	if from_deck:
		add_turn(p, "xray_played")
	if d["kind"] == "spell":
		ps.turn["spell_discount"] = 0
	elif d["kind"] == "creature":
		ps.turn["creature_discount"] = 0
		if train.active:
			train.creature_paid(p)
	_record_play(p, c)
	if d["kind"] == "creature":
		_mark_played(p, c)
	await _emit({"type": "actions", "p": p})
	match d["kind"]:
		"creature":
			await _put_creature(p, c, lane, true)
		"building":
			await _put_building(p, c, lane)
		"spell":
			await _cast_spell(p, c)
		"teamwork":
			await put_teamwork(p, c)
	await _hero_event(p, "played", [c])
	await _check_state()
	await _notify("on_played_", [p, c])
	await _check_state()


func cmd_draw_for_action(p: int) -> void:
	if not can_draw_for_action(p):
		return
	players[p].actions -= 1
	await _emit({"type": "actions", "p": p})
	await _log("%s тратит действие и берёт карту." % players[p].name)
	await _draw(p)


func cmd_thaw(p: int, lane: int) -> void:
	if not can_thaw(p, lane):
		return
	var ps: PlayerState = players[p]
	var need := thaw_cost(p, lane)
	for i in need:
		var pick = await _choose({"kind": "hand_card", "player": p, "options": ps.hand.map(func(h): return h.uid),
			"prompt": "Растопить лёд: сбрось карту" + (" (%d из %d)" % [i + 1, need] if need > 1 else "")})
		if pick == null or not is_frozen(p, lane):
			return
		await discard_card(p, _find(ps.hand, pick))
	await _log("%s сбрасывает карту, чтобы растопить лёд в зоне %d." % [ps.name, lane + 1])
	thaw_by_discard = true
	await thaw(p, lane)
	thaw_by_discard = false


## A card with its own floop and the one from the hero card (Финн) uses one of them:
## hero = the hero's floop.
func cmd_floop(p: int, kind: String, lane: int, hero := false) -> void:
	if not can_floop(p, kind, lane):
		return
	var c := slot(p, kind, lane)
	var ps: PlayerState = players[p]
	if not own_floop_ok(p, kind, lane) or (hero and hero_floop_ok(p, kind, lane)):
		c.exhausted = true
		c.flooped = true
		await _log("%s: ФЛЮП героя — «%s»." % [ps.name, c.card_name()])
		await _emit({"type": "floop", "p": p, "kind": kind, "lane": lane, "uid": c.uid})
		await run_hook(hero_hook(p, "floop"), [p, c, lane])
		if train.active:
			await train.flooped(p)
		await _check_state()
		return
	var ab := floop_ability(c, p, kind, lane)
	match CardDB.get_def(ab).get("floop_cost", ""):
		"action":
			ps.actions -= 1
			await _emit({"type": "actions", "p": p})
		"discard":
			var pick = await _choose({"kind": "hand_card", "player": p, "options": ps.hand.map(func(h): return h.uid),
				"prompt": "%s: сбрось карту, чтобы применить" % c.card_name()})
			if pick == null:
				return
			await discard_card(p, _find(ps.hand, pick))
		"destroy_creature":
			var opts := []
			for l in LANES:
				if ps.creatures[l] != null:
					opts.append({"p": p, "lane": l})
			var pick = await _choose({"kind": "creature", "player": p, "options": opts,
				"prompt": "%s: уничтожь своё существо, чтобы применить" % c.card_name()})
			if pick == null:
				return
			if ps.creatures[pick["lane"]] == c:
				# Paid with itself: the ability still works, from the lane it was on.
				c.flooped = true
				await _log("%s: ФЛЮП — «%s» уничтожает себя." % [ps.name, c.card_name()])
				await _emit({"type": "floop", "p": p, "kind": kind, "lane": lane, "uid": c.uid})
				await destroy_creature(p, lane)
				await run_hook("floop_" + ab, [c, p, kind, lane])
				if train.active:
					await train.flooped(p)
				await _check_state()
				return
			await destroy_creature(p, pick["lane"])
		"destroy_building":
			var opts := []
			for l in LANES:
				for e in buildings_at(p, l):
					opts.append({"p": p, "lane": l, "kind": e[1]})
			var pick = await _choose({"kind": "building", "player": p, "options": opts,
				"prompt": "%s: уничтожь своё строение, чтобы применить" % c.card_name()})
			if pick == null:
				return
			await destroy_building(p, pick["lane"], pick.get("kind", "building"))
	# The cost may have moved things around; find the card again.
	var w := where(c.uid)
	if w["zone"] != "creature" and w["zone"] != "building":
		await _check_state()
		return
	kind = w["kind"]
	lane = w["lane"]
	c.exhausted = true
	c.flooped = true
	await _log("%s: ФЛЮП — «%s»." % [ps.name, c.card_name()])
	await _emit({"type": "floop", "p": p, "kind": kind, "lane": lane, "uid": c.uid})
	await run_hook("floop_" + ab, [c, p, kind, lane])
	if train.active:
		await train.flooped(p)
	await _check_state()


func cmd_activate(p: int, kind: String, lane: int) -> void:
	if not can_activate(p, kind, lane):
		return
	var c := slot(p, kind, lane)
	var ab := act_ability(c, p, kind, lane)
	var d := CardDB.get_def(ab)
	var ps: PlayerState = players[p]
	ps.actions -= int(d["activated"])
	c.act_uses += 1
	await _emit({"type": "actions", "p": p})
	match d.get("act_cost", ""):
		"discard":
			var pick = await _choose({"kind": "hand_card", "player": p, "options": ps.hand.map(func(h): return h.uid),
				"prompt": "%s: сбрось карту" % c.card_name()})
			if pick == null:
				return
			await discard_card(p, _find(ps.hand, pick))
		"remove_freeze":
			await thaw(p, lane)
	await _emit({"type": "activate", "p": p, "kind": kind, "lane": lane, "uid": c.uid})
	if d.get("act_cost", "") == "destroy_self":
		await _log("%s уничтожает «%s»." % [ps.name, c.card_name()])
		if kind == "creature":
			await destroy_creature(p, lane)
		else:
			await destroy_building(p, lane, kind)
	await run_hook("act_" + ab, [c, p, kind, lane])
	await _check_state()


func cmd_hero_power(p: int) -> void:
	if not can_hero_power(p):
		return
	await _log("%s использует способность героя." % players[p].name)
	await _emit({"type": "hero_power", "p": p})
	await run_hook(hero_hook(p, "power"), [p])
	await _check_state()


func cmd_begin_attack(p: int) -> void:
	if not _own_turn_main(p) or is_first_turn():
		return
	await _enter_battle(p)


## Start of the fight phase.
func _enter_battle(p: int) -> void:
	if phase != "main":
		return
	phase = "attack"
	await _emit({"type": "phase", "phase": phase})
	await _hero_event(p, "battle")
	for e in in_play():
		if e[1] != p or slot(e[1], e[2], e[3]) != e[0]:
			continue
		for id: String in texts(e[0], e[1], e[2], e[3]):
			await run_hook("battle_" + id, [e[0], e[1], e[2], e[3]])
	await _check_state()
	if phase != "over":
		await _notify("on_battle_", [p])      # командные карты of both teammates
		await _check_state()


func cmd_attack(p: int, lane: int) -> void:
	if not can_attack(p, lane):
		return
	if phase == "main":
		await _enter_battle(p)
		if phase == "over" or not can_attack(p, lane):
			return
	var across_spot := across(p, lane)
	var o: int = across_spot[0]
	var olane: int = across_spot[1]
	var c: CardInst = players[p].creatures[lane]
	c.exhausted = true
	c.flooped = false
	if train.active:
		train.attack_declared(c)
	for id: String in texts(c, p, "creature", lane):
		await run_hook("attack_" + id, [c, p, lane])
	if train.active:
		await train.attack_started(p, lane, c)
	if phase == "over" or players[p].creatures[lane] != c:
		await _check_state()
		return
	var a_lane := lane
	var target: CardInst = players[o].creatures[olane]
	# Пламинго-огнеклюв: past a burning creature straight to the opponent (and the hurt Весёлый жираф, Обнимашный ёжик).
	if target != null and c.damage >= 4 and (creature_text(p, lane, "giddy_giraffe") or creature_text(p, lane, "huggable_hedgehog")):
		target = null
	if target != null and creature_text(p, lane, "flameingo_ignisbeak") and burning(target):
		await _log("Пламинго-огнеклюв пролетает над горящим существом.")
		target = null
	# Благородный / Любезный броненосец: the defender may take the attack on itself.
	var guard: int = await _armourdillo_guard(o, olane if target != null else -1, c)
	if guard >= 0:
		olane = guard
		target = players[o].creatures[olane]
	# Крысолов: a flooped creature may fight instead.
	if target != null and creature_text(p, lane, "pied_piper"):
		var opts := []
		for l in LANES:
			var f: CardInst = players[p].creatures[l]
			if f != null and f != c and f.flooped:
				opts.append({"p": p, "lane": l})
		if not opts.is_empty():
			var pick = await _choose({"kind": "creature", "player": p, "options": opts, "optional": true,
				"prompt": "Крысолов: атаковать вместо него флюпнутым существом?"})
			if pick != null:
				a_lane = pick["lane"]
	var attacker: CardInst = players[p].creatures[a_lane]
	if target == null:
		await _hero_event(p, "attack_empty", [attacker, a_lane])
		var a := combat_atk(p, a_lane, null, olane, true)
		var crit: int = train.crit(p, a) if train.active else 0
		await _emit({"type": "attack", "p": p, "lane": a_lane, "uid": attacker.uid, "target": "player"})
		if crit > 0:
			a = await train.show_crit(attacker, a, crit)
		await _log("«%s» атакует %s: %d урона." % [attacker.card_name(), players[o].name, a])
		var dealt := await damage_player(o, a, attacker, {"kind": "combat", "p": p})
		if dealt > 0 and int(attacker.flags.get("revelry", -1)) == turn_number and phase != "over":
			await _log("Королевский кутёж: ещё 2 урона.")
			await damage_player(o, 2, null, {"kind": "effect", "p": p})
		if dealt > 0 and phase != "over":
			await _notify("on_hit_player_", [p, a_lane, attacker, o, dealt])
		if train.active:
			await train.after_hit(p, dealt)
		await _herbal(p, a_lane, attacker, dealt)
		if train.active:
			await train.hit_hero(p, a_lane, attacker)
		if a > 0 and phase != "over":
			dealt_to = {"p": o, "lane": -1, "card": null}
			for id: String in texts(attacker, p, "creature", a_lane):
				await run_hook("dealt_" + id, [attacker, p, a_lane, a, "player"])
			dealt_to = {}
	else:
		# Солидарность: the first creature of the team's turns to attack a creature gets +1.
		if team_has(p, "solidarity") and not players[p].turn.get("solidarity", false):
			players[p].turn["solidarity"] = true
			await buff(attacker, 1)
		var a1 := combat_atk(p, a_lane, target, olane, true)
		var a2 := combat_atk(o, olane, attacker, a_lane, false)
		var crit: int = train.crit(p, a1) if train.active else 0
		await _emit({"type": "attack", "p": p, "lane": a_lane, "uid": attacker.uid, "target": "creature",
			"target_uid": target.uid})
		if crit > 0:
			a1 = await train.show_crit(attacker, a1, crit)
		await _log("«%s» (%d) сражается с «%s» (%d)." % [attacker.card_name(), a1, target.card_name(), a2])
		var d1 := await damage_creature(o, olane, a1, {"kind": "combat", "p": p, "card": attacker})
		var d2 := 0
		if players[p].creatures[a_lane] == attacker:
			d2 = await damage_creature(p, a_lane, a2, {"kind": "combat", "p": o, "card": target})
		if train.active:
			await train.after_hit(p, d1)
		await _herbal(p, a_lane, attacker, d1)
		# Reactions to the exchange.
		if d1 > 0 and players[p].creatures[a_lane] == attacker:
			dealt_to = {"p": o, "lane": olane, "card": target}
			for id: String in texts(attacker, p, "creature", a_lane):
				await run_hook("dealt_" + id, [attacker, p, a_lane, d1, "creature"])
			dealt_to = {}
		if d2 > 0 and players[o].creatures[olane] == target:
			dealt_to = {"p": p, "lane": a_lane, "card": attacker}
			for id: String in texts(target, o, "creature", olane):
				await run_hook("dealt_" + id, [target, o, olane, d2, "creature"])
			dealt_to = {}
		if d1 > 0 and players[o].creatures[olane] == target and hp_of(o, olane) > 0:
			for id: String in texts(target, o, "creature", olane):
				await run_hook("hurt_" + id, [target, o, olane, d1, attacker])
		if d2 > 0 and players[p].creatures[a_lane] == attacker and hp_of(p, a_lane) > 0:
			for id: String in texts(attacker, p, "creature", a_lane):
				await run_hook("hurt_" + id, [attacker, p, a_lane, d2, target])
		await _check_state()
		# After the fight: Ягнепир and the like, if they are still there.
		for e in [[attacker, p, a_lane], [target, o, olane]]:
			if players[e[1]].creatures[e[2]] == e[0] and phase != "over":
				for id: String in texts(e[0], e[1], "creature", e[2]):
					await run_hook("fought_" + id, [e[0], e[1], e[2]])
	await _check_state()


## Благородный / Любезный броненосец of the defender: may take an attack meant for another
## spot (lane, -1: the player). Returns the armourdillo's lane or -1.
func _armourdillo_guard(o: int, lane: int, attacker: CardInst) -> int:
	var opts := creature_opts(o, [o], func(x, _s, l): return l != lane and (has_text(x, o, "creature", l, "genteel_armourdillo")
		or has_text(x, o, "creature", l, "gracious_armourdillo") or has_text(x, o, "creature", l, "living_desert")))
	if opts.is_empty():
		return -1
	var pick = await _choose({"kind": "creature", "player": o, "options": opts, "optional": true,
		"prompt": "«%s» нападает. Подставить броненосца вместо цели?" % attacker.card_name()})
	if pick == null:
		return -1
	await _log("Броненосец принимает нападение «%s» на себя." % attacker.card_name())
	return int(pick["lane"])


## Травяные метатели: in this turn p's creatures heal the damage they deal.
func _herbal(p: int, lane: int, c: CardInst, dealt: int) -> void:
	if dealt > 0 and players[p].turn.get("herbal", false) and players[p].creatures[lane] == c and phase != "over":
		await heal_creature(p, lane, dealt)


## Ends the turn. Ready creatures that have not attacked yet must attack,
## so they attack now, left to right.
func cmd_end_turn(p: int) -> void:
	_record({"t": "end", "p": p})
	await _end_turn(p)
	await _end_call()


func _end_turn(p: int) -> void:
	if p != turn_player or not (phase == "main" or phase == "attack"):
		return
	if phase == "main":
		await _enter_battle(p)
		if phase == "over":
			return
	if not is_first_turn():
		# Left to right, again while some creature can still attack: one may have moved
		# onto a lane already passed (Некромант onto the land of a creature that died).
		var again := true
		var passes := 0
		while again and passes < 8:
			again = false
			passes += 1
			for lane in LANES:
				if can_attack(p, lane):
					await cmd_attack(p, lane)
					again = true
					if phase == "over":
						return
	if train.active:
		await train.turn_end(p)
		if phase == "over":
			return
	await _trigger_own(p, "end_")
	if phase == "over":
		return
	# Нейромант: the card it played leaves the game at the end of the turn.
	for x: CardInst in all_cards(p):
		if int(x.flags.get("neuro", -1)) == turn_number:
			var w := where(x.uid)
			if w["zone"] == "creature":
				players[w["p"]].creatures[w["lane"]] = null
				await _leave_play(x, w["p"], w["lane"], "creature", "remove", "removed")
			elif w["zone"] == "building":
				await destroy_building(w["p"], w["lane"], w["kind"])
				await remove_from_game(x)
			elif w["zone"] == "discard":
				await remove_from_game(x)
	# Облик феникса: the creatures it brought back are destroyed at the end of the turn.
	for lane in LANES:
		var fc: CardInst = players[p].creatures[lane]
		if fc != null and int(fc.flags.get("phoenix_form", -1)) == turn_number:
			await destroy_creature(p, lane)
	await _check_state()
	if phase == "over":
		return
	# Блестящая вспышка: at the end of the turn all cards but one go.
	if players[p].turn.get("flare", false) and players[p].hand.size() > 1:
		var keep = await _choose({"kind": "hand_card", "player": p, "options": players[p].hand.map(func(h): return h.uid),
			"prompt": "Блестящая вспышка: какую карту оставить?"})
		for h: CardInst in players[p].hand.duplicate():
			if keep == null or h.uid != int(keep):
				await discard_card(p, h)
	if train.active:
		await train.item_turn_end(p)
	await _end_turn_cleanup(p)
	if phase == "over":
		return
	await _log("%s завершает ход." % players[p].name)
	turn_player = next_seat(p)
	turn_number += 1
	if fast_mode:
		await _start_turn(turn_player)
	else:
		phase = "handoff"
		await _emit({"type": "phase", "phase": phase})


## Called once the next player has taken the seat.
func cmd_start_turn() -> void:
	_record({"t": "turn"})
	if phase == "handoff":
		await _start_turn(turn_player)
	await _end_call()


# ---------------------------------------------------------------- turn flow

func _start_turn(p: int) -> void:
	var ps: PlayerState = players[p]
	phase = "main"
	entered_this_turn = 0
	for side in players.size():
		players[side].turn = {}
	await _emit({"type": "turn_start", "p": p})
	await _log("— Ход %d: %s —" % [turn_number, ps.name])
	# Effects that last "until the start of your next turn".
	for side in players.size():
		for lane in LANES:
			var l: Dictionary = players[side].lands[lane]
			if l.get("flip_until", -1) == p:
				l["flip_until"] = -1
				await flip_land(side, lane, false)
			if l.get("override_until", -1) == p:
				l["override_until"] = -1
				l["override"] = ""
				await _emit({"type": "land", "p": side, "lane": lane})
			var c: CardInst = players[side].creatures[lane]
			if c != null and c.flags.get("shield_until", -1) == p:
				c.flags.erase("shield_until")
	for e in in_play():
		var c: CardInst = e[0]
		if e[1] != p or not c.exhausted:
			continue
		if e[2] == "creature" and c.def().get("no_ready", false) and not c.lost_abilities:
			continue
		c.exhausted = false
		c.flooped = false
		await _emit({"type": "ready", "p": p, "uid": c.uid})
	await _start_effects(p)
	if phase == "over":
		return
	var skipped_tutorial_draw := false
	if train.active:
		await train.turn_start(p)
		if phase == "over":
			return
		if await train.turn_draw(p, _turn_draws.bind(p)) and phase == "over":
			return
	else:
		skipped_tutorial_draw = _tutorial_skip_first_draw and p == first_player and turn_number == 1
		if skipped_tutorial_draw:
			_tutorial_skip_first_draw = false
		else:
			await _turn_draws(p)
	if not skipped_tutorial_draw:
		await _trigger_own(p, "after_draw_")
	if phase == "over":
		return
	ps.actions = actions_per_turn(p) + ps.next_actions
	ps.next_actions = 0
	if train.active:
		ps.actions += train.item_actions(p)
	await _emit({"type": "actions", "p": p})
	await _check_state()


## The draw at the start of p's turn, with the extra ones of Улитка.
func _turn_draws(p: int) -> void:
	await _draw(p)
	for i in int(call_hook(hero_hook(p, "extra_draws"), [p], 0)):
		await _draw(p)


## На троих online: the player gives up in their own turn (a command, so every PC does it at the
## same point) and drops out as at 0 HP; with one opponent left that one wins.
func _concede(p: int) -> void:
	if not three() or p != turn_player or players[p].out or phase == "over":
		return
	await _log("%s сдаётся." % players[p].name)
	players[p].hp = 0
	await _check_win()


## The player loses hit points, the last ones too (not damage: nothing prevents it).
func lose_hp(p: int, n: int, why: String) -> void:
	if n <= 0 or phase == "over":
		return
	players[p].hp -= n
	await _emit({"type": "player_damage", "p": p, "amount": n, "uid": -1})
	await _log("%s: %s теряет %d HP." % [why, players[p].name, n])
	await _check_win()


# ---------------------------------------------------------------- tokens

## Tokens on a creature that are not damage: "burn" (жетоны огня) and "atk_tok" (жетоны атаки, +1 ATK each).
const TOKEN_KINDS := ["burn", "atk_tok"]


func tokens(c: CardInst, kind: String) -> int:
	return int(c.flags.get(kind, 0)) if c != null else 0


func burning(c: CardInst) -> bool:
	return tokens(c, "burn") > 0


func non_damage_tokens(c: CardInst) -> int:
	var n := 0
	for k in TOKEN_KINDS:
		n += tokens(c, k)
	return n


## Burn tokens on every creature in play.
func burn_tokens_in_play() -> int:
	var n := 0
	for side in players.size():
		for c in players[side].creatures:
			n += tokens(c, "burn")
	return n


func add_atk_tokens(c: CardInst, n := 1) -> void:
	if c == null or n <= 0:
		return
	c.flags["atk_tok"] = tokens(c, "atk_tok") + n
	await _emit({"type": "buff", "uid": c.uid, "text": "+%d жетон атаки" % n if n > 1 else "+1 жетон атаки", "good": true})


func remove_token(c: CardInst, kind: String, n := 1) -> int:
	var have := tokens(c, kind)
	var k := mini(have, n)
	if k <= 0:
		return 0
	if have - k > 0:
		c.flags[kind] = have - k
	else:
		c.flags.erase(kind)
	await _emit({"type": "buff", "uid": c.uid, "text": "−%d %s" % [k, "огонь" if kind == "burn" else "жетон атаки"], "good": kind == "burn"})
	return k


## Player by_p sets creature (side, lane) on fire: n burn tokens more. Each new token deals 1 damage
## at once, and each token 1 damage at the start of the creature's controller's turn.
func burn_creature(by_p: int, side: int, lane: int, n := 1) -> void:
	var c: CardInst = players[side].creatures[lane]
	if c == null or n <= 0 or phase == "over":
		return
	c.flags["burn"] = tokens(c, "burn") + n
	await _log("«%s» горит (жетонов огня: %d)." % [c.card_name(), tokens(c, "burn")])
	await _emit({"type": "buff", "uid": c.uid, "text": "Огонь +%d" % n, "good": false})
	await damage_creature(side, lane, n, {"kind": "effect", "p": by_p, "burn": true})
	if by_p >= 0:
		add_turn(by_p, "burned")
		await _notify("on_burn_", [by_p, side, lane, c])


## Player by_p sets player `side` on fire.
func burn_player(by_p: int, side: int, n := 1) -> void:
	if n <= 0 or phase == "over":
		return
	players[side].burn += n
	await _log("%s горит (жетонов огня: %d)." % [players[side].name, players[side].burn])
	await _emit({"type": "hero_text", "p": side, "text": "Огонь +%d" % n, "good": false})


## Start of p's turn: burning creatures of p and p take 1 damage for each burn token.
func _burn_damage(p: int) -> void:
	for lane in LANES:
		var c: CardInst = players[p].creatures[lane]
		if burning(c):
			await damage_creature(p, lane, tokens(c, "burn"), {"kind": "effect", "p": -1, "burn": true})
	await _check_state()
	if players[p].burn > 0 and phase != "over":
		await _log("%s получает урон от огня." % players[p].name)
		await damage_player(p, players[p].burn, null, {"kind": "effect", "p": -1, "burn": true})


## Хрум: a replaced creature with Gobble goes under the one that replaced it (Початкогоблинизация gives it).
func gobbles(c: CardInst) -> bool:
	if c == null:
		return false
	if int(c.flags.get("gobble_turn", -1)) == turn_number:
		return true
	return c.def().get("gobble", false) and not c.lost_abilities


## Runs `prefix + ability` for each of p's cards in play, left to right.
func _trigger_own(p: int, prefix: String) -> void:
	for e in in_play():
		if e[1] != p or slot(e[1], e[2], e[3]) != e[0]:
			continue
		for id: String in texts(e[0], e[1], e[2], e[3]):
			if _hooks.has(prefix + id):
				await run_hook(prefix + id, [e[0], e[1], e[2], e[3]])
				await _check_state()
				if phase == "over":
					return


## Start of p's turn: burn damage, the hero card and the cards' "at the start of your
## turn" texts. With two or more of them p picks the order (Мшистое убежище can take a
## burn token off before it burns). Burn comes last when nobody picks.
func _start_effects(p: int) -> void:
	var items := []
	for e in in_play():
		if e[1] == p:
			for id: String in texts(e[0], e[1], e[2], e[3]):
				if _hooks.has("start_" + id):
					items.append({"uid": e[0].uid, "id": id})
	if _hooks.has(hero_hook(p, "start")):
		items.append({"hero": true})
	items.append({"burn": true})
	while phase != "over":
		items = items.filter(_start_item_ok.bind(p))
		if items.is_empty():
			return
		var item: Dictionary = items[0]
		if items.size() > 1:
			var labels := []
			for it: Dictionary in items:
				var label := _start_item_label(p, it)
				while labels.has(label):
					label += "+"
				labels.append(label)
			item = items[maxi(labels.find(await pick_option(p, labels, "Начало хода: какой эффект сначала?")), 0)]
		items.erase(item)
		if item.has("burn"):
			await _burn_damage(p)
		elif item.has("hero"):
			await _hero_event(p, "start")
		else:
			var w := where(int(item["uid"]))
			await run_hook("start_" + String(item["id"]), [card(int(item["uid"])), p, w["kind"], w["lane"]])
		await _check_state()


func _start_item_ok(item: Dictionary, p: int) -> bool:
	if item.has("burn"):
		return players[p].burn > 0 or players[p].creatures.any(burning)
	if item.has("hero"):
		return true
	var w := where(int(item["uid"]))
	if (w["zone"] != "creature" and w["zone"] != "building") or int(w["p"]) != p:
		return false
	var c := slot(p, w["kind"], w["lane"])
	return c != null and c.uid == int(item["uid"]) and texts(c, p, w["kind"], w["lane"]).has(item["id"])


func _start_item_label(p: int, item: Dictionary) -> String:
	if item.has("burn"):
		return "Урон от огня"
	if item.has("hero"):
		return "Герой: " + String(CardDB.hero_card(players[p].hero_card).get("name", ""))
	var w := where(int(item["uid"]))
	return "%s, зона %d" % [CardDB.get_def(String(item["id"]))["name"], int(w["lane"]) + 1]


func _end_turn_cleanup(p: int) -> void:
	# Башня духа: borrowed creatures go home.
	for lane in LANES:
		var c: CardInst = players[p].creatures[lane]
		if c != null and c.flags.has("borrowed"):
			var home: int = c.flags["borrowed"]
			var home_lane := int(c.flags.get("borrowed_lane", lane))   # 2 на 2: the lane it came from
			c.flags.erase("borrowed")
			c.flags.erase("borrowed_lane")
			var dest := home_lane if players[home].creatures[home_lane] == null else -1
			if dest < 0 and not empty_lanes(home).is_empty():
				dest = empty_lanes(home)[0]
			if dest >= 0:
				await take_control(p, lane, home, dest)
			else:
				players[p].creatures[lane] = null
				await _leave_play(c, p, lane, "creature", "discard")
	for e in in_play():
		var c: CardInst = e[0]
		c.act_uses = 0
		if c.flags.has("rainbow_turn"):
			c.flags.erase("rainbow")
			c.flags.erase("rainbow_turn")
		if e[2] == "creature":
			c.temp_atk = 0
			c.temp_def = 0
			c.moved_this_turn = false
			c.lost_abilities = false
			c.granted_floop = ""
	for side in players.size():
		for h: CardInst in players[side].hand:
			h.flags.erase("rainbow")
			h.flags.erase("rainbow_turn")
	var ps: PlayerState = players[p]
	ps.actions = 0
	ps.turn = {}
	await _check_state()


# ---------------------------------------------------------------- entering play

## Clears what a card had before it came into play. A card Синюшный чудила made
## Rainbow stays Rainbow in play until the end of the turn.
func _reset_entering(c: CardInst) -> void:
	var rainbow := int(c.flags.get("rainbow_turn", -1)) == turn_number
	c.reset_board_state()
	if rainbow:
		c.flags["rainbow"] = true
		c.flags["rainbow_turn"] = turn_number


func _put_creature(p: int, c: CardInst, lane: int, from_hand := false) -> void:
	var ps: PlayerState = players[p]
	_take_from_zones(c)
	if not _lane_open(lane):
		await _to_discard(c, "play")
		return
	var old: CardInst = ps.creatures[lane]
	var replaced := false
	_reset_entering(c)
	if old != null and c.def().get("shares", false):
		# Shares the land: it lies by the creature there and takes the damage meant for it.
		c.flags["guard"] = true
		old.under.append(c)
		await _log("«%s» делит землю с «%s»." % [c.card_name(), old.card_name()])
		await _emit({"type": "leave", "p": p, "uid": c.uid, "dest": "under", "reason": "play", "host": old.uid})
		return
	if old != null and creature_text(p, lane, "kernel_king_cobnoblin") and not empty_lanes(p).is_empty() \
			and (not gobbles(old) or await pick_option(p, ["Перейти в пустую зону", "Хрум"],
				"Король зёрен с Хрумом: перейти или уйти под новое существо?") != "Хрум"):
		# Початкогоблин — король зёрен: it moves away instead of being replaced.
		# Given Хрум, its controller picks which of the two happens.
		var to: int = await pick_lane(p, p, empty_lanes(p), "Король зёрен: куда он перейдёт?")
		if to >= 0:
			await move_creature(p, lane, to)
			old = null
	if old != null and creature_text(p, lane, "hostile_cobnoblin"):
		# Враждебный початкогоблин: the newcomer first hits the opposing creature of the lane.
		var a := across(p, lane)
		if players[a[0]].creatures[a[1]] != null:
			await _log("Враждебный початкогоблин: «%s» бьёт существо соперника." % c.card_name())
			await damage_creature(a[0], a[1], int(c.def()["atk"]), {"kind": "effect", "p": p})
			await _check_state()
	var guards := []      # Голографический кролик, Корочкодав: they share the land with the newcomer
	if old != null:
		guards = old.under.filter(func(u): return u.flags.get("guard", false))
		for u in guards:
			old.under.erase(u)
		ps.creatures[lane] = null
		replaced = true
		await _log("%s заменяет «%s»." % [ps.name, old.card_name()])
		var eaten := {}
		if gobbles(old):
			# Хрум: the replaced creature goes under the new one, which gains its ATK, DEF and tokens.
			eaten = {"atk": int(old.def()["atk"]) + old.perm_atk, "def": int(old.def()["def"]) + old.perm_def,
				"damage": old.damage, "burn": tokens(old, "burn"), "atk_tok": tokens(old, "atk_tok")}
			await _log("Хрум: «%s» уходит под «%s»." % [old.card_name(), c.card_name()])
		await _leave_play(old, p, lane, "creature", "replace", "discard", c if not eaten.is_empty() else null)
		if ps.creatures[lane] != null:
			# Something took the land while the old creature left; give up.
			if c.under.has(old):
				c.under.erase(old)
				await _to_discard(old, "under")
			for u in guards:
				await _to_discard(u, "under")
			await _to_discard(c, "play")
			return
		if not eaten.is_empty():
			c.perm_atk += eaten["atk"]
			c.perm_def += eaten["def"]
			c.damage += eaten["damage"]
			# Its tokens stay tokens on the new creature.
			for k in ["burn", "atk_tok"]:
				if eaten[k] > 0:
					c.flags[k] = tokens(c, k) + eaten[k]
	if replaced:
		c.flags["replaced"] = true
	if c.def().get("no_ready", false):
		c.exhausted = true
	if train.active:
		c.perm_def += train.enter_def(p)
	ps.creatures[lane] = c
	c.under.append_array(guards)
	entered_this_turn += 1
	add_turn(p, "entered")
	var per_lane: Dictionary = ps.turn.get("entered_lane", {})
	per_lane[lane] = int(per_lane.get(lane, 0)) + 1
	ps.turn["entered_lane"] = per_lane
	if p == turn_player and is_type(c, "sandy", p, lane):
		var sandy: Array = ps.turn.get("sandy_entered", [])
		sandy.append(c.uid)
		ps.turn["sandy_entered"] = sandy
	await _log("%s играет «%s» в зону %d." % [ps.name, c.card_name(), lane + 1])
	await _emit({"type": "play", "p": p, "uid": c.uid, "kind": "creature", "lane": lane})
	if int(ps.turn.get("enter_atk", 0)) > 0 and not ps.turn.get("enter_atk_skip", []).has(c.uid):     # Песчаный маг: later arrivals get the bonus too
		await buff(c, int(ps.turn["enter_atk"]))
	await _on_enter(p, c, lane, from_hand)
	if train.active:
		await train.entered(c)
	if replaced and p == turn_player:
		await _hero_event(p, "replaced")


## Enter-play abilities of a creature and everybody watching it enter.
## Костяной дворец: its entry triggers nothing at all, the watchers (Акула…) stay silent too.
## Two or more of them at once: the player whose turn it is picks the order.
func _on_enter(p: int, c: CardInst, lane: int, from_hand: bool) -> void:
	if _palace_blocks(p, lane):
		return
	c.flags["from_hand"] = from_hand
	var items := []
	for id: String in texts(c, p, "creature", lane):
		if _hooks.has("enter_" + id):
			items.append({"id": id})
	for e in in_play():
		for id: String in texts(e[0], e[1], e[2], e[3]):
			if _hooks.has("on_enter_" + id):
				items.append({"uid": e[0].uid, "id": id})
	while phase != "over":
		items = items.filter(_enter_item_ok.bind(c))
		if items.is_empty():
			break
		var item: Dictionary = items[0]
		if items.size() > 1:
			var labels := []
			for it: Dictionary in items:
				var label := _enter_item_label(it)
				while labels.has(label):
					label += "+"
				labels.append(label)
			item = items[maxi(labels.find(await pick_option(turn_player, labels, "«%s» входит в игру: какой эффект сначала?" % c.card_name())), 0)]
		items.erase(item)
		if not item.has("uid"):
			await run_hook("enter_" + String(item["id"]), [c, p, lane])
		else:
			var w := where(c.uid)
			var src := card(int(item["uid"]))
			var s := where(src.uid)
			await run_hook("on_enter_" + String(item["id"]), [src, s["p"], s["kind"], s["lane"], c, w["p"], w["lane"]])
	c.flags.erase("from_hand")
	c.flags.erase("replaced")


## An enter effect still happens: the creature's own text always, a watcher's while
## both are in play and its card says it sees this creature (sees_enter_ hook).
func _enter_item_ok(item: Dictionary, c: CardInst) -> bool:
	if not item.has("uid"):
		return true
	var w := where(c.uid)
	var s := where(int(item["uid"]))
	if w["zone"] != "creature" or not ["creature", "building", "teamwork"].has(s["zone"]):
		return false
	var src := card(int(item["uid"]))
	if not texts(src, s["p"], s["kind"], s["lane"]).has(item["id"]):
		return false
	return call_hook("sees_enter_" + String(item["id"]), [src, s["p"], s["kind"], s["lane"], c, w["p"], w["lane"]], true)


func _enter_item_label(item: Dictionary) -> String:
	if not item.has("uid"):
		return CardDB.get_def(String(item["id"]))["name"]
	var s := where(int(item["uid"]))
	return "%s, зона %d" % [CardDB.get_def(String(item["id"]))["name"], int(s["lane"]) + 1]


func _put_building(p: int, c: CardInst, lane: int) -> void:
	var ps: PlayerState = players[p]
	_take_from_zones(c)
	if not _lane_open(lane):
		await _to_discard(c, "play")
		return
	_reset_entering(c)
	var old: CardInst = ps.buildings[lane]
	if old != null and creature_text(p, lane, "burly_lumberjack"):
		ps.extra_buildings[lane].append(c)
		await _log("%s строит «%s» в зоне %d рядом с другим строением." % [ps.name, c.card_name(), lane + 1])
		await _emit({"type": "play", "p": p, "uid": c.uid, "kind": "building", "lane": lane})
		await _hero_event(p, "building", [lane])
		if train.active:
			await train.built(p)
		return
	if old != null:
		ps.buildings[lane] = null
		await _log("%s заменяет строение «%s»." % [ps.name, old.card_name()])
		await _leave_play(old, p, lane, "building", "replace")
	ps.buildings[lane] = c
	await _log("%s строит «%s» в зоне %d." % [ps.name, c.card_name(), lane + 1])
	await _emit({"type": "play", "p": p, "uid": c.uid, "kind": "building", "lane": lane})
	await run_hook("enter_" + c.ab(), [c, p, lane])
	await _hero_event(p, "building", [lane])
	if train.active:
		await train.built(p)


func _cast_spell(p: int, c: CardInst) -> void:
	var ps: PlayerState = players[p]
	_take_from_zones(c)
	add_turn(p, "spells")
	# Counted now: a spell this one plays (Хрустальный шар) would make it look like a second one.
	var first := int(ps.turn.get("spells", 0)) == 1
	await _log("%s колдует «%s»." % [ps.name, c.card_name()])
	await _emit({"type": "spell", "p": p, "uid": c.uid})
	await run_hook("spell_" + c.id, [c, p])
	await _check_state()
	# Лаборант: a spell played from anywhere but the hand may work a second time.
	if casting_free and controls_text(p, "lab_assistant") and phase != "over" \
			and await pick_option(p, ["Ещё раз", "Нет"], "Лаборант: применить «%s» ещё раз?" % c.card_name()) == "Ещё раз":
		casting_free = false
		await run_hook("spell_" + c.id, [c, p])
		await _check_state()
	# Глотиус Химик: the first spell of the turn may work a second time.
	if first and controls_text(p, "quaffius_the_chemist") and phase != "over" \
			and await pick_option(p, ["Ещё раз", "Нет"], "Глотиус Химик: применить «%s» ещё раз?" % c.card_name()) == "Ещё раз":
		await run_hook("spell_" + c.id, [c, p])
		await _check_state()
	await _to_discard(c, "spell")
	if train.active:
		await train.spell_cast(p)


## Костяной дворец: the opponent's creatures on its lane have no enter/leave effects.
func _palace_blocks(p: int, lane: int) -> bool:
	return spot_building_text(p, lane, "palace_of_bone", across(p, lane)[0])


## Plays a card for free from wherever it is (Амбар истины, Последний шанс…).
## Returns false if it could not be played.
## The creatures p played this turn, by uid (Гран-при puts one of them back and plays it again).
func _mark_played(p: int, c: CardInst) -> void:
	var uids: Array = players[p].turn.get("played_uids", [])
	uids.append(c.uid)
	players[p].turn["played_uids"] = uids


func play_free(p: int, c: CardInst, prompt := "") -> bool:
	match c.kind():
		"creature", "building":
			var row := c.kind()
			var options := []
			for l in LANES:
				if (creature_lane_ok(p, l, c) if row == "creature" else building_lane_ok(p, l, c)):
					options.append({"p": p, "lane": l, "row": row})
			var pick = await _choose({"kind": "lane", "player": p, "options": options,
				"prompt": prompt if prompt != "" else "Куда сыграть «%s»?" % c.card_name()})
			if pick == null:
				return false
			_record_play(p, c)
			if row == "creature":
				_mark_played(p, c)
				await _put_creature(p, c, pick["lane"])
			else:
				await _put_building(p, c, pick["lane"])
		"spell":
			if not spell_castable(p, c):
				return false
			_record_play(p, c)
			casting_free = true
			await _cast_spell(p, c)
			casting_free = false
		"teamwork":
			_record_play(p, c)
			await put_teamwork(p, c)
		_:
			return false
	await _hero_event(p, "played", [c])
	await _notify("on_played_", [p, c])
	await _check_state()
	return true


## «Зелье» (Potion) in the name.
static func is_potion(c: CardInst) -> bool:
	return c.card_name().to_lower().contains("зелье") or String(c.def().get("en", "")).to_lower().contains("potion")


## Puts a командная карта by p's lands; the one there before goes to the discard pile.
func put_teamwork(p: int, c: CardInst) -> void:
	var ps: PlayerState = players[p]
	_take_from_zones(c)
	c.reset_board_state()
	ps.turn["teamwork_played"] = true
	var old: CardInst = ps.teamwork
	ps.teamwork = c
	if old != null:
		await _log("«%s» уходит в сброс." % old.card_name())
		old.reset_board_state()
		await _to_discard(old, "play")
	await _log("%s выкладывает командную карту «%s»." % [ps.name, c.card_name()])
	await _emit({"type": "play", "p": p, "uid": c.uid, "kind": "teamwork", "lane": -1})
	await run_hook("enter_" + c.ab(), [c, p, -1])


## The teammate of p in 2 на 2 (-1 in a game for two).
func teammate(p: int) -> int:
	return (p + 2) % 4 if teams() else -1


## p's side: p and the teammate.
func team_of(p: int) -> Array:
	return [p, (p + 2) % 4] if teams() else [p]


## A командная карта with this ability on p's team.
func team_has(p: int, id: String) -> bool:
	for s in team_of(p):
		var t: CardInst = players[s].teamwork
		if t != null and t.ab() == id and not t.lost_abilities:
			return true
	return false


## A card p played this turn: its id and the land type it was played as (Хамелеон, Мрачный обмен).
func _record_play(p: int, c: CardInst) -> void:
	var ps: PlayerState = players[p]
	var played: Array = ps.turn.get("played", [])
	played.append(c.id)
	ps.turn["played"] = played
	if ps.turn.get("clone", false) and (c.kind() == "creature" or c.kind() == "building"):
		ps.turn.erase("clone")
	if int(ps.turn.get("potion_discount", 0)) > 0 and is_potion(c):
		ps.turn["potion_discount"] = int(ps.turn["potion_discount"]) - 1
	var as_land: Array = ps.turn.get("played_lands", [])
	as_land.append(play_land(c))
	ps.turn["played_lands"] = as_land
	# A rainbow card is one made Rainbow or one that counts as Rainbow too (Крошечный слон), played paid or free.
	if is_type(c, "rainbow"):
		add_turn(p, "rainbow_played")


## How many cards p played this turn that are not of this land type (rainbow ones count).
func played_not(p: int, land: String) -> int:
	return players[p].turn.get("played_lands", []).filter(func(t): return t != land).size()


## Different land types among the cards p played this turn. A rainbow card has no land type.
func played_types(p: int) -> int:
	var seen := {}
	for t in players[p].turn.get("played_lands", []):
		if t != "rainbow":
			seen[t] = true
	return seen.size()


# ---------------------------------------------------------------- leaving play

## Destroys a creature (lethal damage or a "destroy" effect).
func destroy_creature(side: int, lane: int) -> void:
	var c: CardInst = players[side].creatures[lane]
	if c == null:
		return
	c.flags.erase("killer")
	await _die(side, lane)


func _die(side: int, lane: int) -> void:
	var c: CardInst = players[side].creatures[lane]
	if c == null:
		return
	var killer: CardInst = card(int(c.flags.get("killer", -1)))
	# Тюк спасения: in this fight phase it does not leave play, its damage goes instead.
	if int(c.flags.get("bale_out", -1)) == turn_number and phase == "attack":
		c.flags.erase("bale_out")
		# Король вампиров: the damage may go to a creature instead, then this one leaves play.
		if not await heal_instead(side, c, side, lane, c.damage):
			c.damage = 0
			await _log("Тюк спасения: «%s» остаётся в игре." % c.card_name())
			await _emit({"type": "heal", "p": side, "lane": lane, "uid": c.uid, "amount": 0})
			return
		if players[side].creatures[lane] != c:
			return
	var kw := {}
	var will := int(c.flags.get("last_will", -1))
	players[side].creatures[lane] = null
	await _log("«%s» погибает." % c.card_name())
	var host: CardInst = null
	# Склеп (a wagon of the train): the dead go back to their owner's hand.
	var dest := "hand" if train.active and train.dead_to_hand() and host == null else "discard"
	# Талисман феникса: this turn friendly creatures go back to their owner's hand.
	if players[side].turn.get("phoenix_talisman", false) and host == null:
		dest = "hand"
		await _log("Талисман феникса: «%s» возвращается на руку." % c.card_name())
	# Фонарь из склепа: the first one of the fight goes back to the hand too.
	if dest == "discard" and host == null and c.owner == side and train.active and train.returns_first_dead(side):
		dest = "hand"
		await _log("Фонарь из склепа: «%s» возвращается в руку." % c.card_name())
	await _leave_play(c, side, lane, "creature", "destroy", dest, host)
	if killer != null and phase != "over":
		kw = where(killer.uid)
		if kw["zone"] == "creature" and kw["p"] != side:
			for id: String in texts(killer, kw["p"], "creature", kw["lane"]):
				await run_hook("killed_" + id, [killer, kw["p"], kw["lane"], c, side, lane])
			if train.active:
				await train.killed(kw["p"], killer)
			# Тотем ярости: a card when the creature defeats another this turn.
			if int(killer.flags.get("ragepop", -1)) == turn_number and phase != "over":
				await _log("Тотем ярости: %s берёт карту." % players[kw["p"]].name)
				await _draw(kw["p"])
		await run_hook("slain_" + c.ab(), [c, side, lane, killer])
	if train.active:
		await train.died(side)
	# Последняя воля и вред: the opponent of the cursed creature takes 4.
	if will >= 0 and phase != "over":
		await _log("Последняя воля и вред: %s получает 4 урона." % players[side].name)
		await damage_player(side, 4, null, {"kind": "effect", "p": will})
	# Орудия ремесла: 2 HP for every opposing creature destroyed this turn.
	for q in players.size():
		if is_foe(q, side) and players[q].turn.get("tools", false) and phase != "over":
			await heal_player(q, 2)


func destroy_building(side: int, lane: int, kind := "building") -> void:
	var b := slot(side, kind, lane)
	if b == null:
		return
	var ps: PlayerState = players[side]
	if kind == "building":
		ps.buildings[lane] = null
		if not ps.extra_buildings[lane].is_empty():
			ps.buildings[lane] = ps.extra_buildings[lane].pop_front()
	else:
		ps.extra_buildings[lane].erase(b)
	await _log("Строение «%s» уничтожено." % b.card_name())
	await _leave_play(b, side, lane, kind, "destroy")


## Returns a creature to its owner's hand.
func bounce_creature(side: int, lane: int) -> void:
	var c: CardInst = players[side].creatures[lane]
	if c == null:
		return
	players[side].creatures[lane] = null
	await _log("«%s» возвращается в руку владельца." % c.card_name())
	await _leave_play(c, side, lane, "creature", "bounce", "hand")


## Moves a card that left play to its destination and runs leave effects.
## The card must already be out of its slot.
func _leave_play(c: CardInst, side: int, lane: int, kind: String, reason: String, dest := "discard",
		host: CardInst = null) -> void:
	var info := {"exhausted": c.exhausted, "flooped": c.flooped, "flags": c.flags.duplicate(), "damage": c.damage}
	var ids: Array = [] if c.lost_abilities else [c.ab()]
	var suppressed := kind == "creature" and _palace_blocks(side, lane)
	# Cards lying under it go to their owners' discard piles.
	# Голографический кролик, Корочкодав sharing its land stay on it as an ordinary creature.
	var under := c.under.duplicate()
	c.under = []
	for u: CardInst in under:
		if u.flags.get("guard", false) and kind == "creature" and players[side].creatures[lane] == null and _lane_open(lane):
			u.flags.erase("guard")
			players[side].creatures[lane] = u
			await _log("«%s» остаётся на земле один." % u.card_name())
			await _emit({"type": "move", "p": side, "uid": u.uid, "from": lane, "to": lane})
			continue
		await _to_discard(u, "under")
	if host == null and kind == "creature" and dest == "discard":
		host = await _claim_leaving(c, side, lane, reason)
	c.reset_board_state()
	if host != null:
		host.under.append(c)
		await _emit({"type": "leave", "p": side, "uid": c.uid, "dest": "under", "reason": reason, "host": host.uid})
		await _log("«%s» уходит под «%s»." % [c.card_name(), host.card_name()])
	elif dest == "hand":
		players[c.owner].hand.append(c)
		await _emit({"type": "leave", "p": side, "uid": c.uid, "dest": dest, "reason": reason})
		await _returned_to_hand(c)
	elif dest == "removed":
		players[c.owner].removed.append(c)
		await _emit({"type": "leave", "p": side, "uid": c.uid, "dest": dest, "reason": reason})
	else:
		players[c.owner].discard.append(c)
		await _emit({"type": "leave", "p": side, "uid": c.uid, "dest": "discard", "reason": reason})
	if not suppressed:
		for id: String in ids:
			await run_hook("leave_" + id, [c, side, lane, reason, info])
			if phase == "over":
				return
	if kind == "creature" and phase != "over":
		await _hero_event(side, "left", [c])
	if kind == "creature" and not suppressed:
		leaving = info
		await _notify("on_leave_", [c, side, lane, reason])
		leaving = {}
	if host == null and dest == "discard":
		if c.kind() == "creature":
			add_turn(c.owner, "creatures_discarded")
		await _discarded(c)


## Карамельный верблюд and Бестелесный обжора may take a leaving creature under them.
func _claim_leaving(c: CardInst, side: int, lane: int, reason: String) -> CardInst:
	# Карамельный верблюд takes creatures its controller owns.
	var o: int = c.owner
	for l in LANES:
		var cam: CardInst = players[o].creatures[l]
		if cam != null and cam != c and has_text(cam, o, "creature", l, "carmel_camel"):
			var pick = await _choose({"kind": "option", "player": o, "options": ["Под Карамельный верблюд", "В сброс"],
				"prompt": "«%s» покидает игру. Подложить под Карамельный верблюд (+1/+1)?" % c.card_name()})
			if pick == "Под Карамельный верблюд":
				return cam
			break
	return null


func _to_discard(c: CardInst, from: String) -> void:
	discard_from = from
	if c.kind() == "creature":
		add_turn(c.owner, "creatures_discarded")
	players[c.owner].discard.append(c)
	await _emit({"type": "to_discard", "p": c.owner, "uid": c.uid, "from": from})
	await _discarded(c)


func _discarded(c: CardInst) -> void:
	if _hooks.has("discarded_" + c.id) and where(c.uid)["zone"] == "discard":
		await run_hook("discarded_" + c.id, [c])


## A player discards a card from hand.
func discard_card(p: int, c: CardInst) -> void:
	if c == null or not players[p].hand.has(c):
		return
	players[p].hand.erase(c)
	add_turn(turn_player, "hand_discards")     # Чёрный паладин counts them all
	await _log("%s сбрасывает «%s»." % [players[p].name, c.card_name()])
	await _to_discard(c, "hand")
	await _notify("on_discard_", [p, c])
	# Призыв слизи, Болотуко: discarded from the hand, they may be played for free.
	if _hooks.has("discarded_hand_" + c.ab()) and where(c.uid)["zone"] == "discard" and phase != "over":
		await run_hook("discarded_hand_" + c.ab(), [c, p])


## The player chooses and discards n cards (or fewer if the hand runs out).
func force_discard(p: int, n: int, prompt := "", pred := Callable(), optional := false) -> int:
	var done := 0
	for i in n:
		var options := []
		for h: CardInst in players[p].hand:
			if not pred.is_valid() or pred.call(h):
				options.append(h.uid)
		if options.is_empty() or phase == "over":
			break
		var text := prompt if prompt != "" else "%s: сбрось карту" % players[p].name
		if n > 1:
			text += " (%d из %d)" % [i + 1, n]
		var pick = await _choose({"kind": "hand_card", "player": p, "options": options, "optional": optional,
			"prompt": text})
		if pick == null:
			break
		await discard_card(p, _find(players[p].hand, pick))
		done += 1
	return done


func random_discard(p: int, n: int) -> int:
	var done := 0
	for i in n:
		var hand: Array = players[p].hand
		if hand.is_empty():
			break
		await discard_card(p, hand[rng.randi() % hand.size()])
		done += 1
	return done


## Moves the top card of p's deck to the discard pile.
func mill(p: int) -> CardInst:
	var ps: PlayerState = players[p]
	if ps.deck.is_empty():
		return null
	var c: CardInst = ps.deck.pop_back()
	await _log("%s сбрасывает с колоды «%s»." % [ps.name, c.card_name()])
	await _to_discard(c, "deck")
	return c


func return_to_hand(c: CardInst) -> void:
	var w := where(c.uid)
	match w["zone"]:
		"discard", "deck", "removed":
			players[w["p"]].get(w["zone"]).erase(c)
		_:
			return
	players[c.owner].hand.append(c)
	await _log("«%s» возвращается в руку." % c.card_name())
	await _emit({"type": "to_hand", "p": c.owner, "uid": c.uid, "from": w["zone"]})
	if w["zone"] == "discard":
		await _returned_to_hand(c)


## Леди Ливнерог (hero card) counts creatures coming back to their owner's hand.
func _returned_to_hand(c: CardInst) -> void:
	if c.kind() == "creature" and c.owner == turn_player:
		await _hero_event(c.owner, "to_hand", [c])


func remove_from_game(c: CardInst) -> void:
	var w := where(c.uid)
	if w["zone"] in ["discard", "deck", "hand"]:
		players[w["p"]].get(w["zone"]).erase(c)
		players[c.owner].removed.append(c)
		await _log("«%s» удаляется из игры." % c.card_name())
		await _emit({"type": "removed", "p": c.owner, "uid": c.uid})


## Cards in p's discard pile that may come back (filtered by `pred`).
func discard_pool(p: int, pred := Callable()) -> Array:
	var out := []
	for c: CardInst in players[p].discard:
		if not c.no_return and (not pred.is_valid() or pred.call(c)):
			out.append(c)
	return out


# ---------------------------------------------------------------- moving cards

func move_creature(side: int, from: int, to: int) -> void:
	var ps: PlayerState = players[side]
	var c: CardInst = ps.creatures[from]
	if c == null or from == to or ps.creatures[to] != null or not _lane_open(to):
		return
	ps.creatures[from] = null
	ps.creatures[to] = c
	await _emit({"type": "move", "p": side, "uid": c.uid, "from": from, "to": to})
	await _log("«%s» переходит в зону %d." % [c.card_name(), to + 1])
	await changed_lanes(c, side, from, to)
	await left_lane(c, side, from, side, to)


## A creature left a spot without leaving play (moved, swapped, changed sides): Пекло.
func left_lane(c: CardInst, from_side: int, from_lane: int, to_side: int, to_lane: int) -> void:
	if phase != "over":
		await _notify("on_lane_left_", [c, from_side, from_lane, to_side, to_lane])


## c, now p's creature on `to`, has changed Lanes: Панк-кот, Синюшная кровь, Синюшный злопыхатель.
func changed_lanes(c: CardInst, side: int, from: int, to: int) -> void:
	c.moved_this_turn = true
	for id: String in texts(c, side, "creature", to):
		await run_hook("moved_" + id, [c, side, from, to])
	await _hero_event(side, "moved", [c])
	add_turn(turn_player, "moves")
	await _notify("on_moved_", [c, side, from, to])


func swap_creatures(side: int, a: int, b: int) -> void:
	var ps: PlayerState = players[side]
	var ca: CardInst = ps.creatures[a]
	var cb: CardInst = ps.creatures[b]
	if ca == null or cb == null or a == b or not (_lane_open(a) and _lane_open(b)):
		return
	ps.creatures[a] = cb
	ps.creatures[b] = ca
	ca.moved_this_turn = true
	cb.moved_this_turn = true
	await _emit({"type": "move", "p": side, "uid": ca.uid, "from": a, "to": b})
	await _log("«%s» и «%s» меняются зонами." % [ca.card_name(), cb.card_name()])
	for e in [[ca, a, b], [cb, b, a]]:
		for id: String in texts(e[0], side, "creature", e[2]):
			await run_hook("moved_" + id, [e[0], side, e[1], e[2]])
		await _hero_event(side, "moved", [e[0]])
		add_turn(turn_player, "moves")
		await _notify("on_moved_", [e[0], side, e[1], e[2]])
	for e in [[ca, a, b], [cb, b, a]]:
		await left_lane(e[0], side, e[1], side, e[2])


## Moves a creature to another player's side (control changes, owner stays).
func take_control(from_side: int, from_lane: int, to_side: int, to_lane: int) -> void:
	var c: CardInst = players[from_side].creatures[from_lane]
	if c == null or players[to_side].creatures[to_lane] != null or not _lane_open(to_lane):
		return
	players[from_side].creatures[from_lane] = null
	players[to_side].creatures[to_lane] = c
	await _emit({"type": "move", "p": to_side, "uid": c.uid, "from": from_lane, "to": to_lane})
	await _log("«%s» переходит под контроль игрока %s (зона %d)." % [c.card_name(), players[to_side].name, to_lane + 1])
	await left_lane(c, from_side, from_lane, to_side, to_lane)


func move_building(side: int, from: int, to: int, kind := "building") -> void:
	var ps: PlayerState = players[side]
	var b := slot(side, kind, from)
	if b == null or ps.buildings[to] != null or not _lane_open(to):
		return
	if kind == "building":
		ps.buildings[from] = null
		if not ps.extra_buildings[from].is_empty():
			ps.buildings[from] = ps.extra_buildings[from].pop_front()
	else:
		ps.extra_buildings[from].erase(b)
	ps.buildings[to] = b
	await _emit({"type": "move_building", "p": side, "uid": b.uid, "from": from, "to": to})
	await _log("Строение «%s» переезжает в зону %d." % [b.card_name(), to + 1])


# ---------------------------------------------------------------- lands

func flip_land(side: int, lane: int, flipped: bool) -> void:
	var l: Dictionary = players[side].lands[lane]
	if l["flipped"] == flipped:
		return
	# Яблочный задира: the opponents can't turn its land face down.
	if flipped and creature_text(side, lane, "apple_bully") and is_foe(side, turn_player):
		await _log("Яблочный задира не даёт перевернуть свою землю.")
		return
	l["flipped"] = flipped
	if not flipped:
		l["flip_until"] = -1
	await _emit({"type": "flip_land", "p": side, "lane": lane, "flipped": flipped})
	await _log("%s: %s в зоне %d %s." % [players[side].name, CardDB.land_name(l["type"]), lane + 1,
		"переворачивается лицом вниз" if flipped else "снова лицом вверх"])


## Face down until the start of `until_p`'s next turn.
func flip_land_until(side: int, lane: int, until_p: int) -> void:
	var l: Dictionary = players[side].lands[lane]
	if l["flipped"]:
		return
	await flip_land(side, lane, true)
	l["flip_until"] = until_p


## Жетонов мороза сколько угодно. A frozen land may be frozen again: the old token
## comes off (thaw effects happen) and a new one goes on (freeze effects happen).
func freeze(side: int, lane: int) -> void:
	var l: Dictionary = players[side].lands[lane]
	if phase == "over":
		return
	if train.active and train.no_freeze(side):
		await _log("Варежки Ледяного короля: земля %s в зоне %d не замерзает." % [players[side].name, lane + 1])
		return
	if l.get("frozen", false):
		await thaw(side, lane)
	l["frozen"] = true
	await _emit({"type": "freeze", "p": side, "lane": lane, "frozen": true})
	await _log("%s: земля в зоне %d замерзает." % [players[side].name, lane + 1])
	await _notify("on_freeze_", [side, lane])


func thaw(side: int, lane: int) -> void:
	var l: Dictionary = players[side].lands[lane]
	if not l.get("frozen", false):
		return
	l["frozen"] = false
	await _emit({"type": "freeze", "p": side, "lane": lane, "frozen": false})
	await _log("%s: с земли в зоне %d снят жетон мороза." % [players[side].name, lane + 1])
	await _notify("on_thaw_", [side, lane])
	for q in players.size():
		await _hero_event(q, "thaw", [side])


func set_land_override(side: int, lane: int, type: String, until_p: int) -> void:
	var l: Dictionary = players[side].lands[lane]
	l["override"] = type
	l["override_until"] = until_p
	await _emit({"type": "land", "p": side, "lane": lane})
	await _log("%s: земля в зоне %d теперь считается как «%s»." % [players[side].name, lane + 1, CardDB.land_name(type)])


# ---------------------------------------------------------------- damage & healing

## Deals damage to a creature; returns how much it really took.
## src: {"kind": "combat"|"effect", "p": source side, "card": source creature}
func damage_creature(side: int, lane: int, amount: int, src := {}) -> int:
	var c: CardInst = players[side].creatures[lane]
	if c == null or amount <= 0 or phase == "over":
		return 0
	var combat: bool = src.get("kind", "effect") == "combat"
	if combat and is_foe(side, int(src.get("p", -1))) and players[side].turn.get("falling_star", false):
		await _emit({"type": "buff", "uid": c.uid, "text": "Защищено!", "good": true})
		return 0
	for id: String in texts(c, side, "creature", lane):
		amount = call_hook("dmg_in_" + id, [c, side, lane, amount, src], amount)
	for e in in_play():
		for id: String in texts(e[0], e[1], e[2], e[3]):
			if _hooks.has("aura_dmg_" + id):
				amount += call_hook("aura_dmg_" + id, [e[0], e[1], e[3], c, side, lane, amount, src], 0)
	# Извергающийся колосс: doubled while its controller has 1 card in hand or none.
	for s in players.size():
		if players[s].hand.size() <= 1:
			for l in LANES:
				if creature_text(s, l, "erupting_colossus"):
					amount *= 2
	# Принцесса Черепах: attack tokens may stop damage to her creatures.
	if amount > 0 and _hooks.has(hero_hook(side, "prevent")) and tokens(c, "atk_tok") > 0:
		amount -= int(await run_hook(hero_hook(side, "prevent"), [side, c, amount]))
	if amount <= 0:
		return 0
	for g_card: CardInst in c.under:
		if g_card.flags.get("guard", false):
			g_card.damage += amount
			await _log("«%s» принимает %d урона вместо «%s»." % [g_card.card_name(), amount, c.card_name()])
			await _emit({"type": "buff", "uid": c.uid, "text": "Защищено", "good": true})
			if g_card.damage >= int(g_card.def()["def"]):
				c.under.erase(g_card)
				await _log("«%s» уничтожен." % g_card.card_name())
				await _to_discard(g_card, "under")
			return amount
	c.damage += amount
	if amount == 1 and is_foe(side, int(src.get("p", -1))):
		await _hero_event(int(src["p"]), "dmg1", [c])      # Мяу-Мяу
	if combat and src.get("card") != null:
		c.flags["killer"] = src["card"].uid
	else:
		c.flags.erase("killer")
	await _emit({"type": "damage", "p": side, "lane": lane, "uid": c.uid, "amount": amount})
	return amount


## by: the player whose card or ability removes the damage, the creature's side if -1,
## MOVED when the damage goes on to another creature (Перенеси урон: no Король вампиров).
func heal_creature(side: int, lane: int, amount: int, by := -1) -> int:
	var c: CardInst = players[side].creatures[lane]
	if c == null or amount <= 0 or c.damage <= 0:
		return 0
	var healed := mini(amount, c.damage)
	if by != MOVED and await heal_instead(side if by < 0 else by, c, side, lane, healed):
		return 0
	c.damage -= healed
	await _emit({"type": "heal", "p": side, "lane": lane, "uid": c.uid, "amount": healed})
	heal_by = side if by == -1 else by
	for id: String in texts(c, side, "creature", lane):
		await run_hook("healed_" + id, [c, side, lane, healed])
	heal_by = -1
	return healed


## Король вампиров: player p is about to remove n damage from c and may deal n damage to
## any creature instead. True: the damage stays on c. The hero's choice is no spell's.
func heal_instead(p: int, c: CardInst, side: int, lane: int, n: int) -> bool:
	if n <= 0 or phase == "over" or p < 0 or p >= players.size() or players[p].out \
			or not _hooks.has(hero_hook(p, "heal")):
		return false
	var outer := cmd_source
	cmd_source = ""
	var done: bool = await run_hook(hero_hook(p, "heal"), [p, c, side, lane, n])
	cmd_source = outer
	return done


## Returns the hit points the player lost.
func damage_player(side: int, amount: int, source: CardInst = null, src := {}) -> int:
	if amount <= 0 or phase == "over":
		return 0
	var combat: bool = src.get("kind", "") == "combat"
	if combat and train.active and await train.dodged(side):
		return 0
	# Надувной замок Бонго: it takes the damage instead (and goes after 5 in all).
	if not src.get("bongo", false):
		for lane in LANES:
			for e in buildings_at(side, lane):
				if has_text(e[0], side, e[1], lane, "bongo_bounce_house"):
					e[0].damage += amount
					await _log("Надувной замок Бонго принимает %d урона." % amount)
					if e[0].damage >= 5:
						await destroy_building(side, lane, e[1])
					return 0
	if train.active:
		amount = await train.armor(side, amount)
	players[side].hp -= amount
	await _emit({"type": "player_damage", "p": side, "amount": amount,
		"uid": source.uid if source != null else -1})
	await _check_win()
	if source != null and phase != "over":
		var w := where(source.uid)
		if w["zone"] == "creature" and is_foe(side, w["p"]):
			await _hero_event(w["p"], "hit_player", [source, amount])
		if combat and train.active:
			await train.thorns(side, source)
	return amount


func heal_player(side: int, amount: int) -> int:
	var ps: PlayerState = players[side]
	var healed := mini(amount, ps.max_hp - ps.hp)
	if healed <= 0 or phase == "over":
		return 0
	ps.hp += healed
	if heal_log_on:
		var st: Array = get_stack()
		var from: Dictionary = st[1] if st.size() > 1 else {}
		heal_log.append([side, healed, "%s:%s:%d" % [String(from.get("source", "")).get_file(), from.get("function", ""), int(from.get("line", 0))]])
	await _emit({"type": "player_heal", "p": side, "amount": healed})
	await _log("%s восстанавливает %d HP." % [ps.name, healed])
	return healed


func gain_actions(p: int, n: int) -> void:
	if n <= 0:
		return
	players[p].actions += n
	await _log("%s получает %d действие." % [players[p].name, n])
	await _emit({"type": "actions", "p": p, "gain": n})


func buff(c: CardInst, atk: int, text := "", permanent := false) -> void:
	if c == null:
		return
	if permanent:
		c.perm_atk += atk
	else:
		c.temp_atk += atk
	await _emit({"type": "buff", "uid": c.uid, "text": text if text != "" else "%+d ATK" % atk, "good": atk >= 0})


## State-based checks: destroyed creatures and the end of the game.
func _check_state() -> void:
	var guard := 0
	while phase != "over" and guard < 40:
		guard += 1
		var dead := []
		for side in players.size():
			for lane in LANES:
				var c: CardInst = players[side].creatures[lane]
				if c != null and c.damage >= def_of(side, lane):
					dead.append([side, lane, c])
		if dead.is_empty():
			break
		for e in dead:
			if players[e[0]].creatures[e[1]] == e[2] and phase != "over":
				await _die(e[0], e[1])
		await _check_win()
	await _check_win()


func _check_win() -> void:
	if phase == "over":
		return
	if train.active:
		await train.save_heroes()
	# Билли: a player whose opponent's deck is empty wins.
	for side in players.size():
		if players[side].hero_card == "billy" and foes(side).any(func(o): return players[o].deck.is_empty()):
			winner = team(side) if teams() else side
			phase = "over"
			await _log("Билли: колода соперника кончилась. Победа: %s!" % side_name(winner))
			await _emit({"type": "game_over", "winner": winner}, true)
			return
	if three():
		await _check_three()
		return
	var dead0: bool = players[0].hp <= 0
	var dead1: bool = players[1].hp <= 0
	if not (dead0 or dead1):
		return
	if teams():
		# A team's seats share their hit points: the winner is a team, named by its first seat.
		winner = team(turn_player) if dead0 and dead1 else (1 if dead0 else 0)
		phase = "over"
		await _log("Победа: %s!" % side_name(winner))
		await _emit({"type": "game_over", "winner": winner}, true)
		return
	# A double wagon of the train: the second enemy comes in, the player goes on.
	var second: bool = not train.follow.is_empty()
	if dead1 and not dead0 and second:
		await train.next_enemy()
		return
	if dead0 and dead1:
		winner = 1 if second else turn_player
	else:
		winner = 1 if dead0 else 0
	phase = "over"
	await _log("Победа: %s!" % players[winner].name)
	await _emit({"type": "game_over", "winner": winner}, true)


## На троих: the last one standing wins (when the last two fall at once, the turn player). The
## first one down drops out and the other two play on.
func _check_three() -> void:
	var down := []
	var live := []
	for s in players.size():
		if not players[s].out:
			(down if players[s].hp <= 0 else live).append(s)
	if down.is_empty():
		return
	if live.size() <= 1:
		winner = live[0] if live.size() == 1 else turn_player
		phase = "over"
		await _log("Победа: %s!" % players[winner].name)
		await _emit({"type": "game_over", "winner": winner}, true)
		return
	for s in down:
		await _drop_out(s)


## На троих: player q is down to 0 HP with two players left. Their cards in play go to the owners'
## discard piles (it is not "destroyed": nothing triggers), effects waiting for their turn end,
## and the other two play 1 на 1, lane against lane (across). If it is q's own turn, it ends.
func _drop_out(q: int) -> void:
	var ps: PlayerState = players[q]
	ps.out = true
	ps.burn = 0
	ps.actions = 0
	ps.next_actions = 0
	await _log("%s выбывает из игры. Дальше 1 на 1!" % ps.name)
	for lane in LANES:
		var gone := []
		if ps.creatures[lane] != null:
			gone.append(ps.creatures[lane])
			ps.creatures[lane] = null
		if ps.buildings[lane] != null:
			gone.append(ps.buildings[lane])
			ps.buildings[lane] = null
		gone.append_array(ps.extra_buildings[lane])
		ps.extra_buildings[lane] = []
		for c: CardInst in gone:
			var under := c.under.duplicate()
			c.under = []
			c.reset_board_state()
			for x: CardInst in [c] + under:
				players[x.owner].discard.append(x)
				await _emit({"type": "leave", "p": q, "uid": x.uid, "dest": "discard", "reason": "out"})
		ps.lands[lane]["frozen"] = false
	if ps.teamwork != null:
		players[ps.teamwork.owner].discard.append(ps.teamwork)
		ps.teamwork = null
	for side in players.size():
		for lane in LANES:
			var l: Dictionary = players[side].lands[lane]
			if l.get("flip_until", -1) == q:
				l["flip_until"] = -1
				await flip_land(side, lane, false)
			if l.get("override_until", -1) == q:
				l["override_until"] = -1
				l["override"] = ""
				await _emit({"type": "land", "p": side, "lane": lane})
	await _emit({"type": "out", "p": q}, true)
	if q == turn_player:
		_out_turn = true
		phase = "over"


# ---------------------------------------------------------------- drawing

func _draw(p: int) -> bool:
	var ps: PlayerState = players[p]
	if ps.deck.is_empty():
		await _emit({"type": "draw_fail", "p": p})
		return false
	var c: CardInst = ps.deck.pop_back()
	ps.hand.append(c)
	add_turn(p, "drawn")
	await _emit({"type": "draw", "p": p, "uid": c.uid})
	await _notify("on_draw_", [p])
	return true


## Takes the bottom card of p's deck: a draw like any other (Призрачный мимимимик), so
## Пень с золотым топором and Синий огр see it.
func draw_bottom(p: int) -> bool:
	var ps: PlayerState = players[p]
	if ps.deck.is_empty():
		return false
	var c: CardInst = ps.deck.pop_front()
	ps.hand.append(c)
	add_turn(p, "drawn")
	await _emit({"type": "draw", "p": p, "uid": c.uid})
	await _notify("on_draw_", [p])
	return true


func draw_cards(p: int, n: int) -> int:
	var got := 0
	if n <= 0:
		return 0
	await _log("%s берёт карт: %d." % [players[p].name, n])
	for i in n:
		if await _draw(p):
			got += 1
	return got


# ---------------------------------------------------------------- choice helpers

## Creatures as choice options. The opponent can't pick creatures hidden by
## Пещера одиночества.
func creature_opts(chooser_p: int, sides: Array, pred := Callable()) -> Array:
	var out := []
	for side in sides:
		for lane in LANES:
			var c: CardInst = players[side].creatures[lane]
			if c == null:
				continue
			if side != chooser_p and shielded(side, lane):
				continue
			if cloud_hidden(chooser_p, side, lane):
				continue
			if pred.is_valid() and not pred.call(c, side, lane):
				continue
			out.append({"p": side, "lane": lane})
	return out


func pick_creature(p: int, sides: Array, prompt: String, pred := Callable(), optional := false):
	var pick = await _choose({"kind": "creature", "player": p, "options": creature_opts(p, sides, pred),
		"optional": optional, "prompt": prompt})
	if pick != null and is_foe(p, int(pick["p"])) and creature_text(int(pick["p"]), int(pick["lane"]), "endearing_elephant") \
			and CardDB.has_def(cmd_source) and CardDB.get_def(cmd_source)["kind"] == "spell" and phase != "over":
		var owner_side: int = pick["p"]
		await _log("Очаровательный слон: заклинание соперника выбрало его — 2 урона.")
		var o: int = await pick_foe(owner_side, "Очаровательный слон: какому сопернику 2 урона?")
		if o >= 0:
			await damage_player(o, 2, null, {"kind": "effect", "p": owner_side})
	return pick


func pick_option(p: int, options: Array, prompt: String):
	return await _choose({"kind": "option", "player": p, "options": options, "prompt": prompt})


func pick_card(p: int, cards: Array, prompt: String, optional := false):
	var pick = await _choose({"kind": "card", "player": p, "options": cards.map(func(c): return c.uid),
		"optional": optional, "prompt": prompt})
	return card(int(pick)) if pick != null else null


func pick_land(p: int, options: Array, prompt: String, optional := false):
	return await _choose({"kind": "land", "player": p, "options": options, "optional": optional, "prompt": prompt})


## Lands as choice options: pred(side, lane) -> bool.
func land_opts(sides: Array, pred := Callable()) -> Array:
	var out := []
	for side in sides:
		for lane in LANES:
			if not pred.is_valid() or pred.call(side, lane):
				out.append({"p": side, "lane": lane})
	return out


## Lands to freeze: frozen ones too (freezing them again gives no token but still
## counts), after the unfrozen ones so a default answer does not waste the freeze.
func freeze_opts(sides: Array, pred := Callable()) -> Array:
	var opts := land_opts(sides, pred)
	return opts.filter(func(o): return not is_frozen(o["p"], o["lane"])) + opts.filter(func(o): return is_frozen(o["p"], o["lane"]))


func pick_lane(p: int, side: int, lanes: Array, prompt: String, row := "creature", optional := false) -> int:
	var options := []
	for l in lanes:
		options.append({"p": side, "lane": l, "row": row})
	var pick = await _choose({"kind": "lane", "player": p, "options": options, "optional": optional, "prompt": prompt})
	return -1 if pick == null else int(pick["lane"])


## Like pick_lane, but over empty spots on any side: `spots` are {"p", "lane"}.
## Returns the picked spot or null. `extra` rides along in the request for the AI.
func pick_spot(p: int, spots: Array, prompt: String, extra := {}):
	var options := []
	for s: Dictionary in spots:
		options.append({"p": int(s["p"]), "lane": int(s["lane"]), "row": "creature"})
	var req := {"kind": "lane", "player": p, "options": options, "optional": false, "prompt": prompt}
	req.merge(extra)
	return await _choose(req)


func _choose(req: Dictionary):
	if phase == "over":
		return null
	var options: Array = req.get("options", [])
	if req.get("kind") == "lane":
		# A lane a wagon closed is no place to go, whatever the effect.
		options = options.filter(func(o): return _lane_open(int(o["lane"])))
		req["options"] = options
	if options.is_empty():
		return null
	var optional: bool = req.get("optional", false)
	if not optional and options.size() == 1:
		return options[0]
	if _undo_player >= 0 and (int(req.get("player", _undo_player)) != _undo_player or options.any(_undo_hidden)):
		_undo_seen = true
	if chooser == null:
		return null if optional else options[0]
	var r = await chooser.choose(req)
	if journal != null:
		# The answer is kept as its place among the options (null: skipped).
		var i := -1 if r == null else options.find(r)
		journal.append({"t": "pick", "i": i} if i >= 0 or r == null else {"t": "pick", "i": -2, "r": r})
	return r


# ---------------------------------------------------------------- undo

## Events that show what was hidden: such a command can't be taken back.
const UNDO_HIDDEN := ["draw", "draw_fail", "reveal", "peek", "mulligan", "to_deck"]


## Before a command of player p at one PC: the state to go back to.
func undo_point(p: int) -> Dictionary:
	_undo_player = p
	_undo_seen = false
	return {"copy": clone(), "p": p, "log": log_lines.size(), "journal": journal.size() if journal != null else 0}


## After the command: it may be taken back if it showed nothing hidden (no card drawn
## or looked at, no deck changed, no random roll, nobody else chose anything).
func undo_clean(point: Dictionary) -> bool:
	_undo_player = -1
	var c = point["copy"]
	if _undo_seen or phase == "over" or c.rng.state != rng.state or c.turn_player != turn_player:
		return false
	for i in players.size():
		if players[i].deck.map(func(x): return x.uid) != c.players[i].deck.map(func(x): return x.uid):
			return false
	return true


## A card in a deck or in somebody else's hand among the options of a choice.
func _undo_hidden(o) -> bool:
	var uid := -1
	if o is CardInst:
		uid = o.uid
	elif o is int:
		uid = o
	if uid < 0 or not _cards.has(uid):
		return false
	var w := where(uid)
	return w["zone"] == "deck" or (w["zone"] == "hand" and w["p"] != _undo_player)


## Puts the whole state back as it was at the point. The cards stay the same objects.
func undo_to(point: Dictionary) -> void:
	var c = point["copy"]
	for uid in _cards.keys():
		if not c._cards.has(uid):
			_cards.erase(uid)
	for uid in c._cards:
		if _cards.has(uid):
			_copy_card(c._cards[uid], _cards[uid])
		else:
			_cards[uid] = _copy_card(c._cards[uid])
	for uid in c._cards:
		_cards[uid].under = _remap(c._cards[uid].under, _cards)
	for i in players.size():
		_clone_player(c.players[i], _cards, players[i])
	turn_player = c.turn_player
	first_player = c.first_player
	turn_number = c.turn_number
	phase = c.phase
	winner = c.winner
	rng.state = c.rng.state
	entered_this_turn = c.entered_this_turn
	train.copy_from(c.train)
	_next_uid = c._next_uid
	log_lines.resize(point["log"])
	if journal != null:
		journal.resize(point["journal"])


# ---------------------------------------------------------------- copies for search

## Every card of one owner, in play or not (a card keeps its owner for good).
func all_cards(owner: int) -> Array:
	var out := []
	for uid in _cards:
		if _cards[uid].owner == owner:
			out.append(_cards[uid])
	return out


## A copy of the whole state for the AI search (scripts/ai/search.gd): same cards
## (uids, ids, state), same deck order, same engine rng state. The copy runs fast
## (no events, no log, no journal) and has no chooser; changing it never changes
## this game. Its rng is the same state until the caller reseeds it.
func clone():
	var c = get_script().new()
	var map := {}
	for uid in _cards:
		map[uid] = _copy_card(_cards[uid])
	for uid in _cards:
		map[uid].under = _remap(_cards[uid].under, map)
	c.players = []
	for ps: PlayerState in players:
		c.players.append(_clone_player(ps, map))
	if teams():
		for t in 2:
			var pool := [players[t].hp]
			c.players[t].team_hp = pool
			c.players[t + 2].team_hp = pool
	c.turn_player = turn_player
	c.first_player = first_player
	c.turn_number = turn_number
	c.phase = phase
	c.winner = winner
	c.rng.state = rng.state
	c.rng_seed = rng_seed
	c.entered_this_turn = entered_this_turn
	c.train.copy_from(train)
	c.cmd_source = cmd_source
	c.fast_mode = true
	c._next_uid = _next_uid
	c._cards = map
	return c


## The deck of player p in a new random order (search copies: the copy's rng).
func reshuffle(p: int) -> void:
	_shuffle(players[p].deck)


## A copy of card o (or o's state written into the card `into`).
func _copy_card(o: CardInst, into: CardInst = null) -> CardInst:
	var c := into if into != null else CardInst.new(o.uid, o.id, o.owner)
	c.id = o.id
	c.owner = o.owner
	c.damage = o.damage
	c.exhausted = o.exhausted
	c.flooped = o.flooped
	c.moved_this_turn = o.moved_this_turn
	c.temp_atk = o.temp_atk
	c.temp_def = o.temp_def
	c.perm_atk = o.perm_atk
	c.perm_def = o.perm_def
	c.lost_abilities = o.lost_abilities
	c.granted_floop = o.granted_floop
	c.act_uses = o.act_uses
	c.flags = o.flags.duplicate(true)
	c.used_life = o.used_life
	c.no_return = o.no_return
	c.upgraded = o.upgraded
	return c


func _clone_player(ps: PlayerState, map: Dictionary, into: PlayerState = null) -> PlayerState:
	var n := into if into != null else PlayerState.new()
	n.index = ps.index
	n.hero = ps.hero
	n.hero_card = ps.hero_card
	n.hero_state = _remap(ps.hero_state, map)
	n.name = ps.name
	n.hp = ps.hp
	n.max_hp = ps.max_hp
	n.stats = ps.stats.duplicate()
	n.item_state = ps.item_state.duplicate()
	n.actions = ps.actions
	n.mulligan_used = ps.mulligan_used
	n.burn = ps.burn
	n.next_actions = ps.next_actions
	n.teamwork = _remap(ps.teamwork, map)
	n.out = ps.out
	n.deck = _remap(ps.deck, map)
	n.hand = _remap(ps.hand, map)
	n.discard = _remap(ps.discard, map)
	n.removed = _remap(ps.removed, map)
	n.lands = _remap(ps.lands, map)
	n.creatures = _remap(ps.creatures, map)
	n.buildings = _remap(ps.buildings, map)
	n.extra_buildings = _remap(ps.extra_buildings, map)
	n.turn = _remap(ps.turn, map)
	return n


## A copy of a piece of state: arrays and dictionaries are copied deeply, and a card
## becomes its copy from `map` (uid -> copy).
func _remap(v, map: Dictionary):
	if v is CardInst:
		return map.get(v.uid)
	if v is Array:
		var out := []
		for x in v:
			out.append(_remap(x, map))
		return out
	if v is Dictionary:
		var d := {}
		for k in v:
			d[k] = _remap(v[k], map)
		return d
	return v


# ---------------------------------------------------------------- helpers

func _make_card(id: String, owner: int) -> CardInst:
	var c := CardInst.new(_next_uid, id, owner)
	_cards[_next_uid] = c
	_next_uid += 1
	return c


func _find(arr: Array, uid) -> CardInst:
	for c: CardInst in arr:
		if c.uid == uid:
			return c
	return null


func _take_from_zones(c: CardInst) -> void:
	for ps: PlayerState in players:
		if ps.teamwork == c:
			ps.teamwork = null
		ps.hand.erase(c)
		ps.discard.erase(c)
		ps.deck.erase(c)
		ps.removed.erase(c)


func _shuffle(arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = arr[i]
		arr[i] = arr[j]
		arr[j] = t


func shuffle_deck(p: int) -> void:
	_shuffle(players[p].deck)
	await _emit({"type": "mulligan", "p": p})


func _emit(ev: Dictionary, force := false) -> void:
	if _undo_player >= 0 and UNDO_HIDDEN.has(ev["type"]):
		_undo_seen = true
	if fast_mode:
		return
	if phase == "over" and not force:
		return
	if animator != null:
		await animator.play(ev)


func _log(text: String) -> void:
	if fast_mode:
		return
	log_lines.append(text)
	await _emit({"type": "log", "text": text}, true)


func log_msg(text: String) -> void:
	await _log(text)


func emit_event(ev: Dictionary) -> void:
	await _emit(ev)
