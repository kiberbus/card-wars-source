extends Node
## Sounds, music and the heroes' voices. Autoloaded as `Sfx`.
##
## Sounds: two sets a player picks in the settings, «Мультик» (CW_BANK, the sounds of the
## Card Wars app from "my cardwars", made by tools/cw_sounds.py into assets/sfx/cw) and
## «Обычные» (BANK, recorded foley from Kenney's CC0 packs in assets/sfx). Sfx.play("hit").
## A name a set does not have plays its FALLBACK.
##
## Music (assets/music, ids and gains in sound_index.gd): Sfx.play_mix("menu", tracks, first)
## goes from track to track in a random order with cross-fades; Sfx.play_music("menu") keeps
## one track. On a bus of its own with its own volume. The end of a game has short tunes of
## its own (play("win") / play("lose")).
##
## Voices (assets/sfx/voices): Sfx.hero_voice("finn", "creature") says a line of the hero
## for a moment of the fight, one at a time with a pause between them.
##
## Every sound runs through an "SFX" bus that softens the top end and
## catches peaks, so stacked effects never get shrill or clip. Levels in
## BANK were set from measured RMS so the groups sit evenly in the mix.

const SoundIndex = preload("res://scripts/ui/sound_index.gd")
const DevAssets = preload("res://scripts/dev_assets.gd")

const DIR := "res://assets/sfx/"
const MUSIC_DIR := "res://assets/music/"
const VOICE_DIR := "res://assets/sfx/voices/"
const SETTINGS_PATH := "user://settings.cfg"
const BUS := "SFX"
const MUSIC_BUS := "Music"
const VOICES := 12
const MIN_GAP := 0.045           # seconds between two plays of the same name
const VOICE_GAP := 3.5           # seconds of quiet between two lines of the heroes
const VOICE_DB := -2.0
const MIN_PLAY := 55.0           # seconds a track of a mix plays at least (a short one goes round)
const XFADE := 3.0               # seconds of the cross-fade from one track of a mix to the next
const ONCE := ["story"]          # tracks that do not loop: they play once in a mix
const SETS := [["Мультик", "cw"], ["Обычные", ""]]

## name: [variants, volume_db, pitch_variance, layered_name]
const BANK := {
	"card": [["card-slide-1", "card-slide-2", "card-slide-3", "card-slide-5", "card-slide-8"], -6.0, 0.05, ""],
	"hover": [["card-slide-1", "card-slide-2", "card-slide-3"], -15.0, 0.08, ""],
	"draw": [["card-slide-1", "card-slide-2", "card-slide-3", "card-slide-5", "card-slide-8"], -6.0, 0.06, ""],
	"deal": [["card-slide-2", "card-slide-3", "card-slide-5"], -10.0, 0.06, ""],
	"place": [["card-place-1", "card-place-4", "card-place-3"], -2.0, 0.04, ""],
	"flip": [["card-fan-1", "card-shove-4"], -1.0, 0.05, ""],
	"shuffle": [["card-fan-2"], 0.0, 0.0, ""],
	"floop": [["card-shove-4", "card-slide-8"], 0.0, 0.04, "floop_magic"],
	"floop_magic": [["maximize_006", "maximize_008"], -12.0, 0.03, ""],
	"attack": [["card-slide-5", "card-slide-8"], -5.0, 0.06, ""],
	"hit": [["impactPunch_medium_000", "impactPunch_medium_001", "impactPunch_medium_002",
		"impactPunch_medium_003", "impactPunch_medium_004"], -5.0, 0.05, ""],
	"big_hit": [["impactPunch_heavy_000", "impactPunch_heavy_001", "impactPunch_heavy_002",
		"impactPunch_heavy_003", "impactPunch_heavy_004"], -2.5, 0.04, ""],
	"death": [["impactPlank_medium_000", "impactPlank_medium_001", "impactPlank_medium_002",
		"impactPlank_medium_003", "impactPlank_medium_004"], -5.0, 0.04, ""],
	"spell": [["maximize_009"], -9.5, 0.03, "buff"],
	"buff": [["glass_002", "glass_003", "glass_006"], -12.0, 0.02, ""],
	"chip": [["chip-lay-3"], -4.0, 0.06, ""],
	"coin_tick": [["chip-lay-3"], -9.0, 0.12, ""],
	"coin": [["confirmation_001"], -10.0, 0.0, ""],
	"turn": [["maximize_008"], -10.0, 0.0, ""],
	"win": [["confirmation_004"], -5.0, 0.0, ""],
	"click": [["tick_004"], -16.0, 0.06, ""],
	"press": [["click_002", "click_003", "click_005"], -14.0, 0.05, ""],
	"select": [["select_002"], -12.0, 0.04, ""],
	"error": [["error_008"], -9.0, 0.0, ""],
	"found": [["confirmation_004"], -3.0, 0.0, ""],
}

## «Мультик»: BANK's names and some more. Each file plays at its level of
## SoundIndex.SOUNDS (tools/cw_sounds.py: a bit under the Kenney set, peaks capped, the top
## softened), plus the number here.
const CW_BANK := {
	"card": [["cw/card_move"], 0.0, 0.05, ""],
	"hover": [["cw/card_move"], -9.0, 0.08, ""],
	"draw": [["cw/card_move", "cw/card_pick"], -1.0, 0.06, ""],
	"deal": [["cw/card_move"], -2.5, 0.06, ""],
	"place": [["cw/place_1", "cw/place_3", "cw/place_4", "cw/place_5"], 0.0, 0.04, ""],
	"land": [["cw/landscape"], 0.0, 0.04, ""],
	"flip": [["cw/card_double"], 0.0, 0.05, ""],
	"shuffle": [["cw/shuffle"], 0.0, 0.0, ""],
	"floop": [["cw/floop"], 0.0, 0.03, ""],
	"attack": [["cw/attack"], 0.0, 0.06, ""],
	"hit": [["cw/hit"], 0.0, 0.06, ""],
	"big_hit": [["cw/crit"], 0.0, 0.04, ""],
	"death": [["cw/derez"], 0.0, 0.04, ""],
	"spell": [["cw/spell"], 0.0, 0.03, ""],
	"buff": [["cw/buff"], 0.0, 0.04, ""],
	"power_up": [["cw/attack_up"], 0.0, 0.03, ""],
	"debuff": [["cw/attack_down"], 0.0, 0.03, ""],
	"heal": [["cw/health_up"], 0.0, 0.03, ""],
	"hero_power": [["cw/leader"], 0.0, 0.0, ""],
	"chip": [["chip-lay-3"], -5.0, 0.06, ""],
	"coin_tick": [["chip-lay-3"], -10.0, 0.12, ""],
	"coin": [["cw/heart"], 0.0, 0.0, ""],
	"turn": [["cw/your_turn"], 0.0, 0.0, ""],
	"enemy_turn": [["cw/opponent_turn"], 0.0, 0.0, ""],
	"intro": [["cw/battle_intro"], 0.0, 0.0, ""],
	"win": [["cw/win"], 0.0, 0.0, ""],
	"lose": [["cw/lose"], 0.0, 0.0, ""],
	"click": [["cw/ui_click"], 0.0, 0.06, ""],
	"press": [["cw/ui_select"], 0.0, 0.05, ""],
	"back": [["cw/ui_back"], 0.0, 0.04, ""],
	"select": [["cw/ui_select"], 2.0, 0.04, ""],
	"error": [["cw/ui_error"], 0.0, 0.0, ""],
	"found": [["confirmation_004"], -3.0, 0.0, ""],   # an opponent is found (ranked.gd)
}

## What a set without a sound plays instead ("" = nothing).
const FALLBACK := {"land": "place", "power_up": "buff", "debuff": "buff", "heal": "buff",
	"hero_power": "buff", "enemy_turn": "turn", "intro": "", "lose": "win", "back": "press"}

## The sounds of the buttons a player picks in the title (assets/sfx/buttons): [name, file], "" is the
## default press and hover of BANK. The pick plays for "press", and higher and softer for "click" (hover).
const BUTTON_SOUNDS := [["Обычный", ""], ["Пузырёк", "bubble"], ["Карта", "card"], ["Калимба", "kalimba"],
	["Клавиша", "key"], ["Дерево", "wood"], ["Капля", "drop"], ["Войлок", "felt"], ["Буп", "boop"],
	["BMO", "bmo"], ["Хрусталь", "crystal"], ["Мехклавиатура", "thock"], ["Пробка", "cork"],
	["Пиццикато", "pizz"], ["Ручка", "pen"], ["Пух", "puff"], ["Камушек", "stone"]]

var volume := 0.8                 # linear 0..1, saved to user://settings.cfg
var button_sound := ""            # a file of BUTTON_SOUNDS, saved to user://settings.cfg
var sound_set := "cw"             # a set of SETS, saved to user://settings.cfg
var music_volume := 0.5           # linear 0..1, saved to user://settings.cfg
var voices_on := true             # the heroes speak in a fight, saved to user://settings.cfg
var _streams: Dictionary = {}     # file name -> AudioStream
var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _last_variant: Dictionary = {}
var _last_time: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _bus_idx := -1
var _music_bus := -1
var _decks: Array[AudioStreamPlayer] = []   # two music players: one fades out as the other comes in
var _deck := 0                    # the one playing the current track
var _level := {}                  # player -> its linear level 0..1 (over the track's gain)
var _fades := {}                  # player -> its fade Tween
var _music_id := ""               # the track playing or coming ("" = none)
var _last_track := ""             # the last track started (a new mix does not begin with it)
var _mix_name := ""               # the mix playing (play_mix)
var _mix: Array = []              # its tracks
var _mix_queue: Array = []        # those still to come in this round
var _switch_at := -1.0            # seconds (ticks) when the next track of the mix takes over
var _voice: AudioStreamPlayer = null
var _voice_until := 0.0           # no new line of a hero before this time
var _last_line := ""


func _init() -> void:
	DevAssets.load_packs()       # the open source copy: pictures and sounds of an installed game


func _ready() -> void:
	_rng.randomize()
	randomize()          # the mixes shuffle with the global generator
	_setup_bus()
	for bank: Dictionary in [BANK, CW_BANK]:
		for entry: Array in bank.values():
			for f: String in entry[0]:
				if not _streams.has(f):
					_streams[f] = load(DIR + f + ".ogg")
	for entry: Array in BUTTON_SOUNDS:
		if entry[1] != "":
			_streams[entry[1]] = load(DIR + "buttons/" + entry[1] + ".ogg")
	for i in VOICES:
		var pl := AudioStreamPlayer.new()
		pl.bus = BUS
		add_child(pl)
		_players.append(pl)
	_voice = AudioStreamPlayer.new()
	_voice.bus = BUS
	add_child(_voice)
	for i in 2:
		var deck := AudioStreamPlayer.new()
		deck.bus = MUSIC_BUS
		add_child(deck)
		_decks.append(deck)
		_level[deck] = 0.0
	_load_settings()


func play(name: String, _pitch_var := -1.0, volume_db := 0.0) -> void:
	var bank := _bank()
	if not bank.has(name):
		var instead: String = FALLBACK.get(name, "")
		if instead == "" or not bank.has(instead):
			return
		name = instead
	if volume <= 0.0:
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(_last_time.get(name, -1.0)) < MIN_GAP:
		return
	_last_time[name] = now
	if button_sound != "" and (name == "press" or name == "click" or name == "back"):
		_play_button(name == "click", volume_db)
		return
	var entry: Array = bank[name]
	var variants: Array = entry[0]
	var pick := _rng.randi() % variants.size()
	if variants.size() > 1 and pick == _last_variant.get(name, -1):
		pick = (pick + 1) % variants.size()
	_last_variant[name] = pick
	var pl := _players[_next]
	_next = (_next + 1) % VOICES
	pl.stream = _streams[variants[pick]]
	var pv: float = entry[2]
	pl.pitch_scale = 1.0 + _rng.randf_range(-pv, pv)
	pl.volume_db = float(entry[1]) + float(SoundIndex.SOUNDS.get(variants[pick], 0.0)) + volume_db
	pl.play()
	if entry[3] != "":
		play(entry[3], -1.0, volume_db)


func _bank() -> Dictionary:
	return CW_BANK if sound_set == "cw" else BANK


# ---------------------------------------------------------------- music

## A mix of tracks of SoundIndex.TRACKS, named `name` (the same name goes on as it is):
## `first` (or a random one, not the last track heard) starts after `delay` and comes in over `fade_in` while the
## music before fades out over `fade_out`. Each track plays MIN_PLAY seconds or more (a
## short one goes round), then the next random one takes over in a XFADE cross-fade; all
## the tracks play before one comes again.
func play_mix(name: String, tracks: Array, first := "", delay := 0.0, fade_in := 2.5, fade_out := 1.8) -> void:
	if name == _mix_name:
		return
	_mix_name = name
	_mix = tracks.filter(func(t): return SoundIndex.TRACKS.has(t))
	_mix_queue = []
	if _mix.is_empty():
		stop_music(fade_out)
		return
	var id := first if _mix.has(first) else _take_next()
	_play_track(id, delay, fade_in, fade_out)
	_schedule(id, delay)


## One track, round and round (no mix).
func play_music(id: String, delay := 0.0, fade_in := 2.5, fade_out := 1.8) -> void:
	_mix_name = ""
	_mix = []
	_switch_at = -1.0
	if not SoundIndex.TRACKS.has(id):
		stop_music()
		return
	if id != _music_id:
		_play_track(id, delay, fade_in, fade_out)


## The music fades out.
func stop_music(fade := 2.0) -> void:
	_music_id = ""
	_mix_name = ""
	_mix = []
	_switch_at = -1.0
	_fade(_decks[_deck], 0.0, fade, true)


## The track playing or coming, "" for none.
func music_id() -> String:
	return _music_id


## The mix playing (play_mix), "" for none or a single track.
func mix_name() -> String:
	return _mix_name


func _process(_delta: float) -> void:
	if _switch_at > 0.0 and Time.get_ticks_msec() / 1000.0 >= _switch_at:
		_switch_at = -1.0
		var id := _take_next()
		_play_track(id, 0.0, XFADE, XFADE)
		_schedule(id, 0.0)


## The next track of the mix: a shuffled round of them all, never the same one twice running.
func _take_next() -> String:
	if _mix_queue.is_empty():
		_mix_queue = _mix.duplicate()
		_mix_queue.shuffle()
		if _mix_queue.size() > 1 and _mix_queue[0] == _last_track:
			_mix_queue.push_back(_mix_queue.pop_front())
	var id: String = _mix_queue.pop_front()
	if id == _last_track and not _mix_queue.is_empty():
		_mix_queue.push_back(id)
		id = _mix_queue.pop_front()
	return id


## When the track just started hands over to the next one of the mix.
func _schedule(id: String, delay: float) -> void:
	_switch_at = -1.0
	var length: float = _decks[_deck].stream.get_length() if _decks[_deck].stream != null else 0.0
	if _mix.size() < 2 or length <= XFADE * 2.0:
		return
	var rounds := 1 if ONCE.has(id) else ceili(MIN_PLAY / length)
	_switch_at = Time.get_ticks_msec() / 1000.0 + delay + rounds * length - XFADE


## A track comes in on the free player while the one playing fades out. The fades go by
## the sound's amplitude, so they have no sudden drop.
func _play_track(id: String, delay: float, fade_in: float, fade_out: float) -> void:
	_music_id = id
	_last_track = id
	_fade(_decks[_deck], 0.0, fade_out, true)
	_deck = 1 - _deck
	var deck := _decks[_deck]
	var stream: AudioStream = load(MUSIC_DIR + id + ".ogg")
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = not ONCE.has(id)
	if _fades.has(deck):
		(_fades[deck] as Tween).kill()
	deck.stop()
	deck.stream = stream
	deck.set_meta("gain", float(SoundIndex.TRACKS[id]))
	_set_level(0.0, deck)
	var t := create_tween()
	_fades[deck] = t
	if delay > 0.0:
		t.tween_interval(delay)
	t.tween_callback(deck.play)
	t.tween_method(_set_level.bind(deck), 0.0, 1.0, fade_in).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## A music player goes to `level` over `time` seconds (and stops at 0 if `stop`).
func _fade(deck: AudioStreamPlayer, level: float, time: float, stop: bool) -> void:
	if _fades.has(deck):
		(_fades[deck] as Tween).kill()
	if not deck.playing:
		return
	var t := create_tween()
	_fades[deck] = t
	t.tween_method(_set_level.bind(deck), float(_level[deck]), level, time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if stop and level <= 0.0:
		t.tween_callback(deck.stop)


func _set_level(level: float, deck: AudioStreamPlayer) -> void:
	_level[deck] = level
	deck.volume_db = float(deck.get_meta("gain", 0.0)) + linear_to_db(maxf(level, 0.0001))


## Some music is heard now.
func music_playing() -> bool:
	return _decks.any(func(d: AudioStreamPlayer): return d.playing)


func set_music_volume(v: float) -> void:
	music_volume = clampf(v, 0.0, 1.0)
	_apply_volume()
	_save("music_volume", music_volume)


# ---------------------------------------------------------------- voices

## A hero (a key of SoundIndex.LINES) says a line for a moment of a fight (an event of
## tools/cw_sounds.py EVENTS: opening, creature, building, spell, floop, kill, lost,
## hurt, win, lose). Only one line at a time and a pause after it; `chance` keeps the
## heroes from talking on every card. `force` (the end of a game) speaks over the last one.
func hero_voice(hero: String, event: String, chance := 1.0, force := false) -> bool:
	if not voices_on or volume <= 0.0:
		return false
	var lines: Array = SoundIndex.LINES.get(hero, {}).get(event, [])
	if lines.is_empty():
		return false
	var now := Time.get_ticks_msec() / 1000.0
	if not force and (now < _voice_until or _voice.playing or _rng.randf() > chance):
		return false
	var pick: Array = lines[_rng.randi() % lines.size()]
	if lines.size() > 1 and pick[0] == _last_line:
		pick = lines[(lines.find(pick) + 1) % lines.size()]
	_last_line = pick[0]
	var stream: AudioStream = load(VOICE_DIR + String(pick[0]) + ".ogg")
	_voice.stream = stream
	_voice.volume_db = float(pick[1]) + VOICE_DB
	_voice.play()
	_voice_until = now + stream.get_length() + VOICE_GAP
	return true


## Does a hero have lines of its own (a key of SoundIndex.LINES)?
static func has_voice(hero: String) -> bool:
	return SoundIndex.LINES.has(hero)


func voice_playing() -> bool:
	return _voice.playing


func set_voices(on: bool) -> void:
	voices_on = on
	if not on:
		_voice.stop()
	_save("voices", on)


# ---------------------------------------------------------------- settings

func sound_set_name() -> String:
	for entry: Array in SETS:
		if entry[1] == sound_set:
			return entry[0]
	return SETS[0][0]


## Picks the next set of sounds, saves it and lets it be heard.
func next_sound_set() -> void:
	var ids: Array = SETS.map(func(e): return e[1])
	sound_set = ids[(ids.find(sound_set) + 1) % ids.size()]
	_save("sound_set", sound_set)
	_apply_volume()
	_last_time.erase("place")
	play("place")


func _save(key: String, value) -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("audio", key, value)
	cfg.save(SETTINGS_PATH)


func _play_button(hover: bool, volume_db := 0.0) -> void:
	var pl := _players[_next]
	_next = (_next + 1) % VOICES
	pl.stream = _streams[button_sound]
	pl.pitch_scale = (1.12 if hover else 1.0) + _rng.randf_range(-0.03, 0.03)
	pl.volume_db = (-20.0 if hover else -9.0) + volume_db
	pl.play()


## The name of the picked button sound, for the title.
func button_sound_name() -> String:
	for entry: Array in BUTTON_SOUNDS:
		if entry[1] == button_sound:
			return entry[0]
	return BUTTON_SOUNDS[0][0]


## Picks the next button sound, saves it and lets it be heard.
func next_button_sound() -> void:
	var files: Array = BUTTON_SOUNDS.map(func(e): return e[1])
	button_sound = files[(files.find(button_sound) + 1) % files.size()]
	_save("button_sound", button_sound)
	_last_time.erase("press")
	play("press")


func set_volume(v: float) -> void:
	volume = clampf(v, 0.0, 1.0)
	_apply_volume()
	_save("sfx_volume", volume)


func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		volume = clampf(float(cfg.get_value("audio", "sfx_volume", volume)), 0.0, 1.0)
		var picked := String(cfg.get_value("audio", "button_sound", ""))
		if BUTTON_SOUNDS.any(func(e): return e[1] == picked):
			button_sound = picked
		var set_id := String(cfg.get_value("audio", "sound_set", sound_set))
		if SETS.any(func(e): return e[1] == set_id):
			sound_set = set_id
		music_volume = clampf(float(cfg.get_value("audio", "music_volume", music_volume)), 0.0, 1.0)
		voices_on = bool(cfg.get_value("audio", "voices", voices_on))
	_apply_volume()


func _apply_volume() -> void:
	AudioServer.set_bus_mute(_bus_idx, volume <= 0.0)
	AudioServer.set_bus_volume_db(_bus_idx, linear_to_db(maxf(volume, 0.0001)))
	# The music sits under the sounds: at full volume it is 8 dB below them.
	AudioServer.set_bus_mute(_music_bus, music_volume <= 0.0)
	AudioServer.set_bus_volume_db(_music_bus, linear_to_db(maxf(music_volume, 0.0001)) - 8.0)
	AudioServer.set_bus_effect_enabled(_bus_idx, 0, sound_set != "cw")


func _setup_bus() -> void:
	_music_bus = AudioServer.get_bus_index(MUSIC_BUS)
	if _music_bus == -1:
		_music_bus = AudioServer.bus_count
		AudioServer.add_bus(_music_bus)
		AudioServer.set_bus_name(_music_bus, MUSIC_BUS)
		AudioServer.set_bus_send(_music_bus, "Master")
	_bus_idx = AudioServer.get_bus_index(BUS)
	if _bus_idx == -1:
		_bus_idx = AudioServer.bus_count
		AudioServer.add_bus(_bus_idx)
		AudioServer.set_bus_name(_bus_idx, BUS)
		AudioServer.set_bus_send(_bus_idx, "Master")
	# Gentle high-shelf cut: takes the sting out of the paper and glass of the «Обычные» set.
	# Off for «Мультик», whose sounds tools/cw_sounds.py already evened out: it made them dull.
	var shelf := AudioEffectHighShelfFilter.new()
	shelf.cutoff_hz = 5500.0
	shelf.gain = 0.55
	AudioServer.add_bus_effect(_bus_idx, shelf, 0)
	# Only the loudest moments: a slower attack lets the start of a hit through.
	var comp := AudioEffectCompressor.new()
	comp.threshold = -14.0
	comp.ratio = 2.0
	comp.attack_us = 8000.0
	comp.release_ms = 120.0
	AudioServer.add_bus_effect(_bus_idx, comp)
	var limiter := AudioEffectHardLimiter.new()
	limiter.ceiling_db = -1.5
	AudioServer.add_bus_effect(_bus_idx, limiter)
