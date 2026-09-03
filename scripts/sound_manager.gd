extends Node
## Synthesized sound manager — every sound in the game is GENERATED IN CODE.
##
## The game ships primarily as a web build, and until now it was completely
## silent. Rather than adding .wav/.ogg asset files (which would grow the web
## download), this node synthesizes every sound effect at _ready() as an
## AudioStreamWAV: we fill a PackedFloat32Array with samples computed from
## sines/squares/noise plus simple envelopes, convert it to 16-bit PCM, and
## keep the resulting streams in memory for the whole session. Zero asset
## files, zero extra download bytes, and the chip-tune character fits the
## blocky procedural world.
##
## ----------------------------------------------------------------------------
## How an AudioStreamWAV buffer works (the mini-lesson)
## ----------------------------------------------------------------------------
## Digital audio is just a list of numbers ("samples") describing the speaker
## cone's position over time. We compute samples as floats in -1..1 (easy math),
## then convert each to a signed 16-bit integer (-32768..32767) stored as two
## little-endian bytes — that is the FORMAT_16_BITS layout AudioStreamWAV
## expects in its `data` PackedByteArray. `mix_rate` says how many samples play
## per second; we use 22050 Hz, half of CD quality, which is plenty for
## chip-style effects and costs half the memory.
##
## ----------------------------------------------------------------------------
## How other scripts use this (the contract)
## ----------------------------------------------------------------------------
## This node is added once to main.tscn and joins the "sound_manager" group.
## Callers follow the repo's group-discovery convention — no hard references:
##     var sm := get_tree().get_first_node_in_group("sound_manager")
##     if sm and sm.has_method("play_coin"): sm.play_coin()
## One-shots play through a small round-robin pool of AudioStreamPlayers owned
## by THIS node, so a caller that frees itself immediately (like a collected
## coin) never cuts its own sound off.
##
## ----------------------------------------------------------------------------
## The web audio unlock (the important gotcha)
## ----------------------------------------------------------------------------
## Browsers refuse to start audio until the user interacts with the page — a
## page that could blast sound before any gesture would be an ad-tech hellscape.
## Godot 4.5 resumes the WebAudio context on the first gesture automatically,
## but if WE start playing before that gesture the console fills with
## "AudioContext was not allowed to start" errors. So every play_* call is
## gated behind `_unlocked`: nothing plays until unlock_audio() fires. We
## unlock ourselves on the first key/click/touch (harmless on native desktop —
## that first input is when gameplay starts anyway), and the mobile touch UI's
## "enable motion controls" overlay tap also calls unlock_audio() explicitly.

# ============================================================================
# CONSTANTS — synthesis tunables
# ============================================================================
# All values below are starting defaults picked by math, not by ear — tune
# freely. Frequencies in Hz, durations in seconds, volumes in decibels
# (0 dB = full scale; every -6 dB is roughly half the perceived level).

## Sample rate for every generated buffer. 22050 Hz reproduces frequencies up
## to ~11 kHz — plenty for these effects — at half the memory of 44.1 kHz.
const MIX_RATE: int = 22050

## How many AudioStreamPlayers sit in the one-shot pool. Six lets a coin blip,
## a jump, a landing and an ability whoosh all overlap without stealing each
## other's voice; the pool round-robins so the 7th sound reuses the oldest.
const ONESHOT_PLAYER_COUNT: int = 6

# --- Coin pickup: a short, bright two-note chirp (low note then high note). ---
const COIN_FREQ: float = 880.0          # first note (A5)
const COIN_FREQ2: float = 1318.5        # second note (E6 — a cheerful fifth up)
const COIN_NOTE_DURATION: float = 0.07  # each note is very short = "blip"
const COIN_PITCH_JITTER: float = 0.08   # ±8% random pitch per pickup so a coin
										# run doesn't sound like a machine gun
const COIN_VOLUME_DB: float = -8.0

# --- Jump: a rising sine sweep ("boing" going up). ---
const JUMP_FREQ_START: float = 300.0
const JUMP_FREQ_END: float = 700.0
const JUMP_DURATION: float = 0.2
const JUMP_VOLUME_DB: float = -10.0

# --- Landing: a low thud, gone almost instantly. ---
const LAND_FREQ: float = 90.0
const LAND_DURATION: float = 0.15
const LAND_VOLUME_DB: float = -8.0

# --- Ability whoosh: a noise swell (air rushing past). ---
const WHOOSH_DURATION: float = 0.4
const WHOOSH_ATTACK: float = 0.15       # seconds spent swelling up before decay
const WHOOSH_VOLUME_DB: float = -8.0
## Per-character pitch offset for the whoosh so each power has its own voice.
## Unknown names fall back to 1.0 (see play_ability), so adding a character
## without touching this dict is safe.
const ABILITY_PITCH: Dictionary = {
	"windman": 1.0,    # airy and broad
	"primm": 1.4,      # quick high zip for the blink
	"teibi": 0.7,      # low and heavy for the resize
	"phoboman": 0.85,  # slightly low and gross for the stink wave
}

# --- Crocodile bite: a harsh descending square-wave burst. ---
const BITE_FREQ_START: float = 400.0
const BITE_FREQ_END: float = 120.0
const BITE_DURATION: float = 0.25
const BITE_VOLUME_DB: float = -6.0

# --- Boss growl: a low saw/noise rumble when a boss first smells the player. ---
const GROWL_FREQ: float = 70.0          # low fundamental = "something BIG"
const GROWL_DURATION: float = 0.5
const GROWL_NOISE_MIX: float = 0.35     # how much breathy noise rides on the saw
const GROWL_VOLUME_DB: float = -8.0

# --- Viper hiss: a bright noise burst when a sand viper acquires the player. ---
## THE AMBUSHER'S TELEGRAPH, and the exact sibling of the boss growl above: both
## fire ONCE on the not-chasing -> chasing transition, because a predator that
## announces itself is the difference between a threat and an unfair one. The
## viper needs it more than the boss does — it is buried and its detection radius
## is 5 m, so without a sound the FIRST signal the player gets is already the
## strike landing.
##
## Why it is the whoosh's synth with the filter opened up, and not a new idea:
## every noise sound in this file is one-pole-low-passed noise, and the factor IS
## the character (wind 0.02 rumbles, footstep 0.18 taps, whoosh 0.25 swells).
## 0.55 barely filters at all, which leaves the sibilant top end the whoosh
## deliberately throws away — that top end is what "hiss" means. The crunch shows
## the other end: fully unfiltered noise reads as violence, not warning.
const HISS_DURATION: float = 0.45
const HISS_LOWPASS: float = 0.55        # one-pole factor — barely filtered, so
										# the sibilant top end survives
const HISS_ATTACK: float = 0.07         # soft swell in, so it warns rather than
										# startles like the crunch's instant hit
const HISS_DECAY: float = 5.0           # exponential taper — a breath running out
const HISS_VOLUME_DB: float = -11.0     # between the growl (-8) and a footstep
										# (-14): audible over a chase, not a jolt

# --- Game over: a slow three-note descending minor phrase. ---
const GAME_OVER_FREQS: Array[float] = [392.0, 311.1, 261.6]  # G4, Eb4, C4
const GAME_OVER_NOTE_DURATION: float = 0.35
const GAME_OVER_VOLUME_DB: float = -6.0

# --- Footstep: a tiny low-passed noise tap (a soft "pat" on dirt). ---
const FOOTSTEP_DURATION: float = 0.06
const FOOTSTEP_LOWPASS: float = 0.18    # one-pole factor — duller than the whoosh
const FOOTSTEP_PITCH_JITTER: float = 0.15  # ±15% per step so a walk cycle
										# doesn't sound like a metronome
const FOOTSTEP_VOLUME_DB: float = -14.0  # quiet — fires twice per stride, forever

# --- Splash: the SAME footstep sample, played brighter and louder (wading). ---
## EDUCATIONAL NOTE: a wet slap and a dry pat are the same event — a foot hitting
## a surface — differing mostly in brightness and loudness. Raising the pitch of
## the noise tap shifts its spectrum up (that IS the "wetness"), so a splash costs
## two constants instead of a whole extra synth function and buffer.
## ponytail: reused sample, add a dedicated _synth_splash() only if it reads wrong.
const SPLASH_PITCH: float = 1.9         # well above the footstep's ±15% jitter, so
										# a splash never sounds like a normal step
const SPLASH_PITCH_JITTER: float = 0.18  # slightly wider jitter than dry steps —
										# water is messier than dirt
const SPLASH_VOLUME_DB: float = -9.0    # ~5 dB above a footstep: wading is loud

# --- Level-up chime: the coin blip replayed twice, a fifth apart (see the
# play_splash precedent above — a reused sample, not a fourth synth function).
# ponytail: two taps of one buffer; add a real _synth_chime() only if it reads
# as "you got two coins" rather than "you levelled up".
const LEVEL_UP_PITCH_LOW: float = 1.0
const LEVEL_UP_PITCH_HIGH: float = 1.5  # a perfect fifth above the coin blip
const LEVEL_UP_VOLUME_DB: float = -6.0  # a couple of dB above a pickup: rarer, louder

# --- Blocked-ability buzz: a curt low square "nope" (F pressed on cooldown). ---
const BUZZ_FREQ: float = 90.0
const BUZZ_DURATION: float = 0.15
const BUZZ_VOLUME_DB: float = -10.0

# --- Croc crush: a harsh noise burst with a fast decay (giant Teibi stomp). ---
const CRUNCH_DURATION: float = 0.2
const CRUNCH_VOLUME_DB: float = -8.0

# --- Boss projectile launch cues: ONE per projectile style. ---
## The muzzle telegraph for scripts/boss_projectile.gd. These sounds are the
## moment the fairness contract is measured FROM: the flight times there are only
## fair if the player is TOLD the shot happened, so a style with no cue is a
## style that kills people from off-screen.
##
## Keyed by the projectile style name, so a new ranged boss is (still) row data:
## an unknown style falls back to the entry below, the same forgiving shape as
## ABILITY_PITCH — a boss whose cue is generic is a tuning bug, a boss that
## crashes the audio thread is not.
##
## ponytail: both cues REPLAY an existing buffer at a new pitch rather than
## baking a third and fourth synth function — the exact precedent play_splash
## (the footstep, brightened) and play_level_up (the coin, twice) already set in
## this file, and the "no audio asset files" invariant is untouched either way.
## Add a real _synth_thunder() only if the pitched crunch reads as a stomp.
##   - thunder_bolt: the CRUNCH buffer (unfiltered noise, fast decay) dropped far
##     below its normal pitch. Pitching noise down moves its whole spectrum down,
##     which is the difference between a snapping twig and a thunderclap.
##   - ice_cream: the WHOOSH buffer (a low-passed noise swell) pitched up, which
##     shortens it into the light "fwip" of something small being thrown.
const PROJECTILE_SOUNDS: Dictionary = {
	"thunder_bolt": {"stream": "crunch", "db": -7.0, "pitch": 0.45},
	"ice_cream": {"stream": "whoosh", "db": -12.0, "pitch": 1.7},
}
## What an unrecognised style gets. Deliberately the quieter of the two: an
## unnamed cue should be audible enough to warn and quiet enough to notice as
## wrong.
const PROJECTILE_SOUND_FALLBACK: Dictionary = {
	"stream": "whoosh", "db": -12.0, "pitch": 1.7,
}

# --- Hunter lock-on: the retrieval unit's two-tone servo ping. ---
## THE ONE SOUND IN THIS FILE THAT IS NOT AN ANIMAL, and that is the whole point.
## Every other threat cue here is breath or flesh — a growl, a hiss, a chomp — so
## the hunter robot announcing itself has to read as ISSUED rather than born. Two
## short square-wave tones, no noise, no sweep inside a tone: a machine deciding.
##
## It is also the class's mercy lever made audible. `hunt_telegraph_time` (1.8 s
## in the hunter's SPECIES row) is only warning time if the player is TOLD the
## clock started, so this cue is load-bearing gameplay, not decoration.
##
## DELIBERATELY NOT A REPLAYED BUFFER, unlike play_splash / play_level_up /
## play_projectile. The nearest candidate was the coin blip (two short tones,
## already), and a lock-on warning that reads as "you picked something up" is
## worse than no warning at all — the pickup blip is the most-heard sound in the
## game. So this one gets its own eleven-line synth function.
##
## DESCENDING, where the coin ascends: a rising pair reads as reward in every
## game anyone has played, and the interval is the cheapest way to keep the two
## unconfusable even through a phone speaker. Square, and high, so it cuts
## through the wind bed and a chasing pack without being loud.
const HUNTER_PING_FREQS: Array[float] = [2200.0, 1650.0]  # a descending fourth
const HUNTER_PING_NOTE_DURATION: float = 0.055  # each tone: a blip, not a beep
const HUNTER_PING_GAP: float = 0.035    # silence between them — two events, not one
const HUNTER_PING_DECAY: float = 22.0   # per-tone exponential; fast, but it rings
const HUNTER_PING_VOLUME_DB: float = -12.0  # under the growl (-8) and hiss (-11):
                                            # a warning at range, not a jumpscare

# --- Hunter grab: the servo clamp landing. ---
## Fired when a hunter's contact is resolved (piglet_crocodile_ai's hunt branch in
## `_on_player_collision`), so it lands on top of the ordinary bite feedback and
## has to be distinguishable from it: the bite is a downward NOISE sweep, this is
## a low square thunk with no sweep at all — actuator, not jaw.
##
## ponytail: it REPLAYS the "buzz" buffer (a 90 Hz square with a fast decay) far
## below its own pitch rather than baking a twelfth synth function — the exact
## precedent play_splash, play_level_up and play_projectile already set in this
## file. Pitching a square down moves the whole harmonic stack down and stretches
## the decay, which is the difference between a UI "nope" and a clamp closing.
## Add a real _synth_clamp() only if it reads as the blocked-ability buzzer.
const HUNTER_GRAB_PITCH: float = 0.5   # 90 Hz -> 45 Hz, 0.15 s -> 0.3 s
const HUNTER_GRAB_VOLUME_DB: float = -7.0  # a hit, so around the bite's -6

# --- Car horn: the city's annoyed double-beep when a hero blocks the carriageway. ---
## Two short square-wave horns (a slightly dissonant pair, 380 + 320 Hz) with a
## brief gap — the universal "hey, move!" The car manager gates this behind a
## hold-off (must be blocked > 1s) and a per-car cooldown, and skips it when the
## player is > 55 m away so 60 honks is not a fire alarm. Like every other
## play_* it early-returns while _unlocked is false, so there is no path that
## bypasses the browser gesture gate. ponytail: replays the built buffer at a
## fixed pitch; add a dedicated doppler only if it reads wrong.
const CAR_HORN_FREQ_A: float = 380.0
const CAR_HORN_FREQ_B: float = 320.0
const CAR_HORN_NOTE_DURATION: float = 0.13
const CAR_HORN_GAP: float = 0.07
const CAR_HORN_VOLUME_DB: float = -9.0

# --- Danger heartbeat: ONE looping "lub-dub" cycle, driven externally. ---
## The danger vignette fetches this via get_loop_player("heartbeat") and owns
## play/stop/pitch/volume itself — we only bake the stream and park the player.
const HEARTBEAT_FREQ: float = 55.0        # low chest-thump fundamental
const HEARTBEAT_CYCLE: float = 0.8        # full lub-dub + silence = one loop
const HEARTBEAT_DUB_DELAY: float = 0.22   # seconds from "lub" to the "dub"
const HEARTBEAT_DUB_LEVEL: float = 0.7    # the second thump is slightly softer

# --- Ambient wind: a long smoothed-noise loop, DELIBERATELY very quiet. ---
## It should register subconsciously ("the world is alive"), never as a sound
## the player notices — hence far below every one-shot above.
const WIND_DURATION: float = 2.0
const WIND_LOWPASS: float = 0.02        # one-pole smoothing factor (smaller =
										# duller/deeper rumble, larger = hissier)
const WIND_CROSSFADE: float = 0.05      # seconds blended across the loop seam
const WIND_VOLUME_DB: float = -26.0

# ============================================================================
# STATE
# ============================================================================

## Browsers block audio until a user gesture (see header). Every play_* call
## early-returns while this is false; unlock_audio() flips it exactly once.
var _unlocked: bool = false

## The prebuilt streams, keyed by sound name ("coin", "jump", ...).
var _streams: Dictionary = {}

## Round-robin pool of one-shot players (children of this node) plus the index
## of the next player to use.
var _players: Array[AudioStreamPlayer] = []
var _next_player: int = 0

## Dedicated looping player for the ambient wind bed (never shared with the
## pool — a one-shot must not steal the loop's voice).
var _wind_player: AudioStreamPlayer = null

## Every dedicated looping player, keyed by name ("wind" today). Future
## systems that need a runtime-varied loop (e.g. a proximity heartbeat) grab
## a named player via get_loop_player() instead of adding their own audio
## nodes, so all voices stay owned by this one manager.
var _loop_players: Dictionary = {}


# ============================================================================
# LIFECYCLE
# ============================================================================

func _ready() -> void:
	# Group registration — how coin.gd / player_controller.gd find us.
	add_to_group("sound_manager")

	# Synthesize every sound once, up front. This runs in a few milliseconds
	# (a couple of seconds of 22 kHz mono is only ~44k samples per second of
	# audio) and never again — playback just reuses these buffers.
	_streams["coin"] = _build_wav(_synth_coin())
	_streams["jump"] = _build_wav(_synth_jump())
	_streams["land"] = _build_wav(_synth_land())
	_streams["whoosh"] = _build_wav(_synth_whoosh())
	_streams["bite"] = _build_wav(_synth_bite())
	_streams["growl"] = _build_wav(_synth_growl())
	_streams["hiss"] = _build_wav(_synth_hiss())
	_streams["game_over"] = _build_wav(_synth_game_over())
	_streams["footstep"] = _build_wav(_synth_footstep())
	_streams["buzz"] = _build_wav(_synth_buzz())
	_streams["crunch"] = _build_wav(_synth_crunch())
	_streams["hunter_ping"] = _build_wav(_synth_hunter_ping())
	_streams["car_horn"] = _build_wav(_synth_car_horn())

	# The wind is the one LOOPING stream: mark the whole buffer as the loop
	# region so it plays forever once started.
	var wind: AudioStreamWAV = _build_wav(_synth_wind())
	wind.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wind.loop_begin = 0
	wind.loop_end = wind.data.size() / 2  # frames, not bytes (2 bytes/frame)

	# Build the one-shot player pool.
	for i in range(ONESHOT_PLAYER_COUNT):
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)

	# And the dedicated wind player (stream set now, played at unlock).
	_wind_player = AudioStreamPlayer.new()
	_wind_player.stream = wind
	_wind_player.volume_db = WIND_VOLUME_DB
	add_child(_wind_player)
	_loop_players["wind"] = _wind_player

	# The danger heartbeat is the second looping stream — same recipe as the
	# wind (LOOP_FORWARD over the whole buffer), but we deliberately do NOT
	# play it here: the danger vignette drives play/stop/pitch/volume live via
	# get_loop_player("heartbeat"), gated on is_unlocked().
	var heartbeat: AudioStreamWAV = _build_wav(_synth_heartbeat())
	heartbeat.loop_mode = AudioStreamWAV.LOOP_FORWARD
	heartbeat.loop_begin = 0
	heartbeat.loop_end = heartbeat.data.size() / 2  # frames, not bytes (2 bytes/frame)
	var heartbeat_player := AudioStreamPlayer.new()
	heartbeat_player.stream = heartbeat
	add_child(heartbeat_player)
	_loop_players["heartbeat"] = heartbeat_player


func _input(event: InputEvent) -> void:
	# First real user gesture of the session → safe to start audio (see the
	# web-unlock section in the header). Any key press, mouse click or screen
	# touch counts; after that we stop listening entirely.
	if event is InputEventKey or event is InputEventMouseButton or event is InputEventScreenTouch:
		if event.is_pressed():
			unlock_audio()
			set_process_input(false)


# ============================================================================
# PUBLIC API — what the rest of the game calls
# ============================================================================

func unlock_audio() -> void:
	## Flip the browser-gesture gate and start the ambient wind bed. Safe to
	## call any number of times from anywhere (first-input handler above, the
	## mobile touch UI's enable-overlay tap, ...) — only the first call acts.
	if _unlocked:
		return
	_unlocked = true
	_wind_player.play()


func is_unlocked() -> bool:
	## Whether the browser-gesture gate has opened. Code driving a loop player
	## directly (via get_loop_player) must check this before calling play() —
	## the gate only guards our own play_* methods.
	return _unlocked


func get_loop_player(loop_name: String) -> AudioStreamPlayer:
	## Fetch (or lazily create) the dedicated looping AudioStreamPlayer for a
	## named ambient bed. "wind" is the only built-in; a future system (e.g. a
	## danger heartbeat) can request its own name, assign a looping stream, and
	## vary pitch_scale / volume_db live every frame. The player is a child of
	## this node, so it respects the same lifetime as everything else here.
	if not _loop_players.has(loop_name):
		var p := AudioStreamPlayer.new()
		add_child(p)
		_loop_players[loop_name] = p
	return _loop_players[loop_name]


func play_coin() -> void:
	## Coin pickup blip. A small random pitch per pickup keeps a rapid string
	## of coins from sounding mechanical. (Cosmetic runtime randomness only —
	## nowhere near the terrain's deterministic chunk RNG.)
	_play_oneshot("coin", COIN_VOLUME_DB,
			1.0 + randf_range(-COIN_PITCH_JITTER, COIN_PITCH_JITTER))


func play_jump() -> void:
	_play_oneshot("jump", JUMP_VOLUME_DB)


func play_land() -> void:
	_play_oneshot("land", LAND_VOLUME_DB)


func play_ability(character_name: String) -> void:
	## One shared whoosh buffer, re-pitched per character (see ABILITY_PITCH) —
	## cheaper than four separate buffers and they stay a recognizable family.
	_play_oneshot("whoosh", WHOOSH_VOLUME_DB, ABILITY_PITCH.get(character_name, 1.0))


func play_bite() -> void:
	_play_oneshot("bite", BITE_VOLUME_DB)


func play_boss_growl() -> void:
	## Boss crocodile acquiring the player — fired by piglet_crocodile_ai.gd on
	## the not-chasing → chasing transition (bosses only).
	_play_oneshot("growl", GROWL_VOLUME_DB)


func play_viper_hiss() -> void:
	## Sand viper acquiring the player — fired by piglet_crocodile_ai.gd on the
	## not-chasing -> chasing transition, from the same branch as the boss growl
	## and under the same rule: ONE cue per engagement, never per frame. The
	## viper's trigger is hysteresis-free (see its SPECIES row), so the same 5 m
	## that fires this ends the chase, and the next hiss is a genuinely new
	## ambush rather than a stutter at the boundary.
	##
	## Routing through _play_oneshot is what keeps the browser-gesture gate
	## honoured — there is no path here that bypasses _unlocked.
	_play_oneshot("hiss", HISS_VOLUME_DB)


func play_game_over() -> void:
	_play_oneshot("game_over", GAME_OVER_VOLUME_DB)


func play_footstep() -> void:
	## Footstep tap, fired on each walk-sine foot plant. Same cosmetic pitch
	## jitter idea as play_coin — identical taps twice a second read as a
	## machine, so each step lands at a slightly different pitch.
	_play_oneshot("footstep", FOOTSTEP_VOLUME_DB,
			1.0 + randf_range(-FOOTSTEP_PITCH_JITTER, FOOTSTEP_PITCH_JITTER))


func play_splash() -> void:
	## Wading splash — fired from the SAME walk-cycle foot plant as play_footstep,
	## whenever the player is standing in a river band (see is_river_at in
	## endless_terrain.gd). The cadence therefore comes free from the walk sine:
	## no timer, no extra state, just the other branch of a ternary in the player.
	##
	## It replays the "footstep" buffer well above its normal pitch, which brightens
	## the noise tap into a wet slap — no new stream is baked, so the "no audio asset
	## files" invariant and the web build size are both untouched. Routing through
	## _play_oneshot also means it inherits the _unlocked gesture gate for free.
	_play_oneshot("footstep", SPLASH_VOLUME_DB,
			SPLASH_PITCH + randf_range(-SPLASH_PITCH_JITTER, SPLASH_PITCH_JITTER))


func play_level_up() -> void:
	## Meta-progression level-up (see scripts/progression.gd).
	##
	## Same trick as play_splash: it REPLAYS the "coin" buffer rather than baking a
	## new stream, twice — once at the coin's own pitch and once a fifth above it,
	## which reads as a small rising chime instead of a fourth kind of coin blip.
	## The two taps overlap because one-shots go through the round-robin player
	## pool, so no scheduling or extra state is needed, and the "no audio asset
	## files" invariant holds.
	_play_oneshot("coin", LEVEL_UP_VOLUME_DB, LEVEL_UP_PITCH_LOW)
	_play_oneshot("coin", LEVEL_UP_VOLUME_DB, LEVEL_UP_PITCH_HIGH)


func play_buzz() -> void:
	## The blocked-ability "nope" — F pressed while the cooldown is running.
	_play_oneshot("buzz", BUZZ_VOLUME_DB)


func play_crunch() -> void:
	## Giant Teibi flattening a crocodile.
	_play_oneshot("crunch", CRUNCH_VOLUME_DB)


func play_hunter_lock_on() -> void:
	## A hunter robot acquiring its quarry — fired by piglet_crocodile_ai.gd on the
	## not-chasing -> chasing edge, from the SAME branch as the boss growl and the
	## viper hiss and under the same rule: one cue per engagement, never per frame.
	##
	## The name is the hook the hunt arm already reached for through `has_method`
	## while this did not exist (bead godot-test1-9rm.3), so the guard there now
	## simply finds it. Routing through _play_oneshot is what keeps the
	## browser-gesture gate honoured: there is no path here that bypasses _unlocked.
	_play_oneshot("hunter_ping", HUNTER_PING_VOLUME_DB)


func play_hunter_grab() -> void:
	## A hunter's retrieval attempt landing. See HUNTER_GRAB_PITCH for why this is
	## the buzz buffer dropped an octave rather than a stream of its own.
	_play_oneshot("buzz", HUNTER_GRAB_VOLUME_DB, HUNTER_GRAB_PITCH)


func play_car_horn(distance: float = 0.0) -> void:
	## Car horn — the traffic yield's "hey, move". Attenuates by distance so 60
	## cars at 50 m is not a fire alarm; skips entirely beyond 55 m (see
	## HONK_AUDIBLE_RADIUS in traffic_manager). Respects the browser gate like
	## every other play_*.
	if distance > 55.0:
		return
	# Attenuate ~ -0.18 dB per metre beyond 5 m, clamped.
	var vol := CAR_HORN_VOLUME_DB
	if distance > 5.0:
		vol -= clampf((distance - 5.0) * 0.18, 0.0, 12.0)
	_play_oneshot("car_horn", vol)


func play_projectile(style: String) -> void:
	## A boss launching a ranged attack — fired from BossProjectile.fire(), once
	## per shot, at the muzzle. See PROJECTILE_SOUNDS for the per-style recipe and
	## for why an unknown style still makes a noise instead of nothing.
	##
	## Routing through _play_oneshot is what keeps the browser-gesture gate
	## honoured: there is no path here that bypasses _unlocked.
	var cue: Dictionary = PROJECTILE_SOUNDS.get(style, PROJECTILE_SOUND_FALLBACK)
	_play_oneshot(cue["stream"], cue["db"], cue["pitch"])


# ============================================================================
# PLAYBACK INTERNALS
# ============================================================================

func _play_oneshot(sound: String, volume_db: float, pitch: float = 1.0) -> void:
	## Play a prebuilt buffer on the next pool player. Round-robin means up to
	## ONESHOT_PLAYER_COUNT sounds overlap freely; beyond that the oldest voice
	## is stolen, which for effects this short is inaudible.
	if not _unlocked:
		return  # browser-gesture gate — see header
	var p: AudioStreamPlayer = _players[_next_player]
	_next_player = (_next_player + 1) % ONESHOT_PLAYER_COUNT
	p.stream = _streams[sound]
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.play()


func _build_wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	## Convert float samples (-1..1) into a mono 16-bit little-endian
	## AudioStreamWAV — the float→PCM step from the header's mini-lesson.
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)  # 2 bytes per 16-bit frame
	for i in range(samples.size()):
		var s: int = clampi(int(samples[i] * 32767.0), -32768, 32767)
		# Little-endian: low byte first. Negative values are stored two's-
		# complement, which "& 0xFF" slicing handles for free.
		bytes[i * 2] = s & 0xFF
		bytes[i * 2 + 1] = (s >> 8) & 0xFF
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	wav.data = bytes
	return wav


# ============================================================================
# SYNTHESIS — one helper per sound, each a tiny lesson in sound design
# ============================================================================

func _synth_coin() -> PackedFloat32Array:
	## Two short sine notes, low then high ("bling!"). Each note decays
	## exponentially — like a struck bell, loud at the strike then dying away —
	## which is what makes it read as a bright *ping* rather than a beep.
	var samples := PackedFloat32Array()
	for freq in [COIN_FREQ, COIN_FREQ2]:
		var note_frames: int = int(COIN_NOTE_DURATION * MIX_RATE)
		for i in range(note_frames):
			var t: float = float(i) / MIX_RATE
			var envelope: float = exp(-t * 30.0)  # fast decay within the note
			samples.append(sin(TAU * freq * t) * envelope)
	return samples


func _synth_jump() -> PackedFloat32Array:
	## A sine whose frequency RISES over the note — pitch going up is the
	## universal cartoon shorthand for "something left the ground". We
	## accumulate phase sample-by-sample (rather than computing sin(f*t) with a
	## changing f, which would glitch) so the sweep is smooth.
	var samples := PackedFloat32Array()
	var frames: int = int(JUMP_DURATION * MIX_RATE)
	var phase: float = 0.0
	for i in range(frames):
		var progress: float = float(i) / frames
		var freq: float = lerpf(JUMP_FREQ_START, JUMP_FREQ_END, progress)
		phase += freq / MIX_RATE
		var envelope: float = 1.0 - progress  # simple linear fade-out
		samples.append(sin(TAU * phase) * envelope)
	return samples


func _synth_land() -> PackedFloat32Array:
	## A very low sine with a very fast decay = a dull *thud*. Low frequency
	## reads as "heavy"; the fast decay keeps it percussive instead of a hum.
	var samples := PackedFloat32Array()
	var frames: int = int(LAND_DURATION * MIX_RATE)
	for i in range(frames):
		var t: float = float(i) / MIX_RATE
		var envelope: float = exp(-t * 25.0)
		samples.append(sin(TAU * LAND_FREQ * t) * envelope)
	return samples


func _synth_whoosh() -> PackedFloat32Array:
	## White noise (a new random value every sample = all frequencies at once)
	## shaped by a swell envelope: rise, peak, fall — air rushing past. A light
	## one-pole low-pass takes the harsh hiss edge off the raw noise.
	var samples := PackedFloat32Array()
	var frames: int = int(WHOOSH_DURATION * MIX_RATE)
	var attack_frames: int = int(WHOOSH_ATTACK * MIX_RATE)
	var filtered: float = 0.0
	for i in range(frames):
		# One-pole low-pass: each output creeps toward the input, so fast
		# wiggles (high frequencies) get averaged away.
		filtered += 0.25 * (randf_range(-1.0, 1.0) - filtered)
		var envelope: float
		if i < attack_frames:
			envelope = float(i) / attack_frames  # swell up...
		else:
			envelope = 1.0 - float(i - attack_frames) / (frames - attack_frames)  # ...then fall
		samples.append(filtered * envelope * 2.0)  # ×2: low-passed noise is quiet
	return samples


func _synth_bite() -> PackedFloat32Array:
	## A square wave (harsh, buzzy — all odd harmonics) sweeping DOWNWARD:
	## falling pitch is the "something bad happened" inverse of the jump sweep.
	## Square = just the sign of a sine, which is why it sounds so much nastier.
	var samples := PackedFloat32Array()
	var frames: int = int(BITE_DURATION * MIX_RATE)
	var phase: float = 0.0
	for i in range(frames):
		var progress: float = float(i) / frames
		var freq: float = lerpf(BITE_FREQ_START, BITE_FREQ_END, progress)
		phase += freq / MIX_RATE
		var square: float = 1.0 if sin(TAU * phase) >= 0.0 else -1.0
		var envelope: float = 1.0 - progress
		samples.append(square * envelope * 0.6)  # 0.6: squares are LOUD at equal amplitude
	return samples


func _synth_growl() -> PackedFloat32Array:
	## A LOW sawtooth (buzzy, all harmonics — an animal throat) blended with a
	## little low-passed noise (breath), swelling in then dying away. The 70 Hz
	## fundamental is what sells "very large animal": compare the 90 Hz landing
	## thud, which is a clean sine and reads as impact, not menace.
	var samples := PackedFloat32Array()
	var frames: int = int(GROWL_DURATION * MIX_RATE)
	var phase: float = 0.0
	var filtered: float = 0.0
	for i in range(frames):
		var progress: float = float(i) / frames
		phase += GROWL_FREQ / MIX_RATE
		# Sawtooth: phase ramps 0→1 each cycle; remap to -1..1 with a hard drop.
		var saw: float = 2.0 * fmod(phase, 1.0) - 1.0
		# Breathy noise layer, low-passed so it rumbles instead of hissing.
		filtered += 0.15 * (randf_range(-1.0, 1.0) - filtered)
		var voice: float = saw * (1.0 - GROWL_NOISE_MIX) + filtered * 2.0 * GROWL_NOISE_MIX
		# Swell in over the first quarter, fade out over the rest.
		var envelope: float = minf(progress * 4.0, 1.0) * (1.0 - progress)
		samples.append(voice * envelope * 0.7)  # saws are loud at equal amplitude
	return samples


func _synth_hiss() -> PackedFloat32Array:
	## Air forced through a snake's glottis: noise, and almost nothing else. The
	## same one-pole low-pass every noise sound here uses, but opened to 0.55 —
	## the whoosh's 0.25 exists to take "the harsh hiss edge off the raw noise",
	## and this is the sound that wants that edge kept.
	##
	## The envelope is the whole difference between a warning and a hit. A soft
	## swell in (HISS_ATTACK) reads as a breath starting; the exponential taper
	## reads as one running out. The trailing (1 - progress) is not decoration —
	## the exponential is still at ~0.1 when the buffer ends, and a buffer that
	## stops at 0.1 ends in an audible click.
	var samples := PackedFloat32Array()
	var frames: int = int(HISS_DURATION * MIX_RATE)
	var attack_frames: int = int(HISS_ATTACK * MIX_RATE)
	var filtered: float = 0.0
	for i in range(frames):
		filtered += HISS_LOWPASS * (randf_range(-1.0, 1.0) - filtered)
		var progress: float = float(i) / frames
		var envelope: float
		if i < attack_frames:
			envelope = float(i) / attack_frames
		else:
			var t: float = float(i - attack_frames) / MIX_RATE
			envelope = exp(-t * HISS_DECAY) * (1.0 - progress)
		samples.append(filtered * envelope)
	return samples


func _synth_hunter_ping() -> PackedFloat32Array:
	## Two square-wave tones with a beat of silence between them — see the
	## HUNTER_PING_* consts for why this one is not a replayed buffer.
	##
	## `signf(sin(...))` is the same square generator the bite and the buzz use.
	## Square rather than sine because a pure sine reads as a musical note (the
	## coin, the level-up chime, the game-over triad are all sines); the odd
	## harmonics of a square are what make this read as a device.
	##
	## The trailing `(1 - progress)` on the envelope is the footgun _synth_hiss
	## already documents: exp(-t * 22) is still well above zero when a 55 ms tone
	## ends, and a buffer that stops mid-amplitude ends in an audible click. Here
	## it would click TWICE, once into the gap and once at the end.
	var samples := PackedFloat32Array()
	var note_frames: int = int(HUNTER_PING_NOTE_DURATION * MIX_RATE)
	var gap_frames: int = int(HUNTER_PING_GAP * MIX_RATE)
	for note in range(HUNTER_PING_FREQS.size()):
		if note > 0:
			for _i in range(gap_frames):
				samples.append(0.0)
		var freq: float = HUNTER_PING_FREQS[note]
		for i in range(note_frames):
			var t: float = float(i) / MIX_RATE
			var progress: float = float(i) / note_frames
			var envelope: float = exp(-t * HUNTER_PING_DECAY) * (1.0 - progress)
			samples.append(signf(sin(TAU * freq * t)) * envelope * 0.6)
	return samples


func _synth_car_horn() -> PackedFloat32Array:
	## Two square-wave horn blasts (380 Hz + 320 Hz) with a gap — an annoyed
	## but not hostile "beep beep". Same square generator as hunter_ping/buzz,
	## same click-free envelope. Loud enough to cut through wind but not a
	## jumpscare; the traffic manager's hold-off + cooldown prevents a siren.
	var samples := PackedFloat32Array()
	var note_frames: int = int(CAR_HORN_NOTE_DURATION * MIX_RATE)
	var gap_frames: int = int(CAR_HORN_GAP * MIX_RATE)
	for freq in [CAR_HORN_FREQ_A, CAR_HORN_FREQ_B]:
		if freq == CAR_HORN_FREQ_B:
			for _i in range(gap_frames):
				samples.append(0.0)
		for i in range(note_frames):
			var t: float = float(i) / MIX_RATE
			var progress: float = float(i) / note_frames
			var envelope: float = exp(-t * 28.0) * (1.0 - progress)
			samples.append(signf(sin(TAU * freq * t)) * envelope * 0.55)
	return samples


func _synth_game_over() -> PackedFloat32Array:
	## Three sine notes stepping down a minor triad (G → Eb → C): descending
	## minor is centuries-old musical shorthand for defeat. Longer notes and a
	## gentler decay than the coin blip make it feel conclusive, not percussive.
	var samples := PackedFloat32Array()
	var note_frames: int = int(GAME_OVER_NOTE_DURATION * MIX_RATE)
	for freq in GAME_OVER_FREQS:
		for i in range(note_frames):
			var t: float = float(i) / MIX_RATE
			var envelope: float = exp(-t * 6.0)  # slow-ish decay, notes ring a little
			samples.append(sin(TAU * freq * t) * envelope)
	return samples


func _synth_footstep() -> PackedFloat32Array:
	## A very short low-passed noise burst with a fast decay — the soft "pat"
	## of a foot on dirt. Same one-pole trick as the whoosh, but a heavier
	## filter and a tiny duration turn the hiss into a dull tap.
	var samples := PackedFloat32Array()
	var frames: int = int(FOOTSTEP_DURATION * MIX_RATE)
	var filtered: float = 0.0
	for i in range(frames):
		filtered += FOOTSTEP_LOWPASS * (randf_range(-1.0, 1.0) - filtered)
		var t: float = float(i) / MIX_RATE
		var envelope: float = exp(-t * 80.0)  # gone in a few hundredths of a second
		samples.append(filtered * envelope * 3.0)  # filtering eats amplitude; compensate
	return samples


func _synth_buzz() -> PackedFloat32Array:
	## A short LOW square wave with a fast decay — the classic "denied" buzzer.
	## Square for the same reason as the bite (harsh, all odd harmonics), but
	## at a constant low pitch: no sweep, no drama, just a curt "nope".
	var samples := PackedFloat32Array()
	var frames: int = int(BUZZ_DURATION * MIX_RATE)
	for i in range(frames):
		var t: float = float(i) / MIX_RATE
		var square: float = 1.0 if sin(TAU * BUZZ_FREQ * t) >= 0.0 else -1.0
		var envelope: float = exp(-t * 20.0)
		samples.append(square * envelope * 0.6)  # 0.6: squares are LOUD at equal amplitude
	return samples


func _synth_crunch() -> PackedFloat32Array:
	## A harsh RAW noise burst dying fast — bone and cartilage giving way under
	## a giant foot. Unlike the whoosh/footstep this noise is deliberately NOT
	## low-passed: the full-spectrum hiss edge is what makes it read as violent.
	var samples := PackedFloat32Array()
	var frames: int = int(CRUNCH_DURATION * MIX_RATE)
	for i in range(frames):
		var t: float = float(i) / MIX_RATE
		var envelope: float = exp(-t * 22.0)
		samples.append(randf_range(-1.0, 1.0) * envelope)
	return samples


func _synth_heartbeat() -> PackedFloat32Array:
	## ONE full "lub-dub" cycle, meant to loop forever (LOOP_FORWARD is set on
	## the stream in _ready). Two low sine thumps — the "dub" delayed a fraction
	## of a second and slightly quieter, just like a real heart — followed by
	## silence padding out the cycle, so the looped result is a slow resting
	## pulse. The danger vignette speeds it up by raising pitch_scale, which
	## shortens BOTH the thumps and the silent gap: exactly how panic sounds.
	var samples := PackedFloat32Array()
	var frames: int = int(HEARTBEAT_CYCLE * MIX_RATE)
	var dub_start: int = int(HEARTBEAT_DUB_DELAY * MIX_RATE)
	for i in range(frames):
		var t: float = float(i) / MIX_RATE
		# The "lub": a low sine thump decaying fast from the cycle start.
		var value: float = sin(TAU * HEARTBEAT_FREQ * t) * exp(-t * 18.0)
		# The "dub": the same thump re-struck at the delay, slightly softer.
		if i >= dub_start:
			var t2: float = float(i - dub_start) / MIX_RATE
			value += sin(TAU * HEARTBEAT_FREQ * t2) * exp(-t2 * 18.0) * HEARTBEAT_DUB_LEVEL
		samples.append(value)
	return samples


func _synth_wind() -> PackedFloat32Array:
	## The ambient bed: ~2 s of HEAVILY low-passed noise, looped forever. The
	## aggressive one-pole filter (see WIND_LOWPASS) turns hissy white noise
	## into a soft distant-wind rumble. To loop without an audible click, the
	## buffer's start and end must meet seamlessly: we synthesize a little
	## extra, then crossfade the surplus tail into the head so the loop seam
	## is a smooth blend instead of a jump.
	var fade_frames: int = int(WIND_CROSSFADE * MIX_RATE)
	var frames: int = int(WIND_DURATION * MIX_RATE)
	var raw := PackedFloat32Array()
	var filtered: float = 0.0
	for i in range(frames + fade_frames):  # surplus tail for the crossfade
		filtered += WIND_LOWPASS * (randf_range(-1.0, 1.0) - filtered)
		raw.append(filtered * 4.0)  # heavy filtering eats amplitude; compensate
	# Crossfade: blend the surplus tail over the head so sample[frames] (which
	# playback wraps to sample[0]) transitions smoothly.
	var samples := raw.slice(0, frames)
	for i in range(fade_frames):
		var blend: float = float(i) / fade_frames  # 0 at seam → 1 into the head
		samples[i] = raw[frames + i] * (1.0 - blend) + samples[i] * blend
	return samples
