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

# --- Game over: a slow three-note descending minor phrase. ---
const GAME_OVER_FREQS: Array[float] = [392.0, 311.1, 261.6]  # G4, Eb4, C4
const GAME_OVER_NOTE_DURATION: float = 0.35
const GAME_OVER_VOLUME_DB: float = -6.0

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
	_streams["game_over"] = _build_wav(_synth_game_over())

	# The wind is the one LOOPING stream: mark the whole buffer as the loop
	# region so it plays forever once started.
	var wind: AudioStreamWAV = _build_wav(_synth_wind())
	wind.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wind.loop_begin = 0
	wind.loop_end = wind.data.size() / 2  # frames, not bytes (2 bytes/frame)
	_streams["wind"] = wind

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


func play_game_over() -> void:
	_play_oneshot("game_over", GAME_OVER_VOLUME_DB)


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
