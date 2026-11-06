extends SceneTree
## Generates every sound in the game from code into res://audio/: the sound
## effects (sfx/<cue>.wav, 44.1 kHz) and a calm ambient loop for each world
## (music/world_<n>.wav, 22.05 kHz), all mono 16-bit. Nothing is sampled,
## so there is nothing to license. The output is the same on every run (the
## random choices are seeded).
##
## Instruments are additive: a sum of decaying sine partials (kalimba,
## marimba, bells, plucked strings, the tanpura's buzzing drone), soft
## detuned pads, and filtered noise for waves, wind and scrapes. Music gets
## a small Schroeder reverb and its tail is folded back onto the start, so
## the loop runs on without a seam.
##
##   godot --headless --path . -s res://tools/make_audio.gd [-- sfx|music]

const OUT: String = "res://audio"
const SFX_RATE: int = 44100
const MUSIC_RATE: int = 22050
## Sound effects peak here; music is levelled to an RMS of about -20 dBFS.
const SFX_PEAK: float = 0.708
const MUSIC_RMS: float = 0.1
const MUSIC_PEAK: float = 0.89
## Seconds rendered past a loop's end, then folded back onto its start.
const TAIL: float = 6.0

const CUES: Array[StringName] = [
	&"step", &"tap", &"slide", &"rotate", &"snap", &"pickup", &"drop", &"pad_complete",
	&"level_complete", &"ui_click", &"error", &"glide", &"creak", &"fall", &"whoosh", &"bounce",
	&"crackle", &"shatter",
]

var _rate: int = SFX_RATE
var _rng := RandomNumberGenerator.new()
## Rendered notes by instrument and pitch.
var _notes: Dictionary = {}


func _initialize() -> void:
	var what: PackedStringArray = OS.get_cmdline_user_args()
	var started: int = Time.get_ticks_msec()
	if what.is_empty() or what.has("sfx"):
		_make_sfx()
	if what.is_empty() or what.has("music"):
		_make_music()
	print("make_audio: done in %.1f s" % ((Time.get_ticks_msec() - started) / 1000.0))
	quit(0)


# --- Sound effects ---------------------------------------------------------

func _make_sfx() -> void:
	_rate = SFX_RATE
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT.path_join("sfx")))
	for cue: StringName in CUES:
		_rng.seed = hash(cue)
		var samples: PackedFloat32Array = call("_sfx_" + cue)
		_scale_to_peak(samples, SFX_PEAK)
		_trim(samples)
		_fade_out(samples, 0.004)
		_write_wav(OUT.path_join("sfx/%s.wav" % cue), samples, _rate)


## A soft clay footfall: a low thump that drops in pitch and a squish of noise.
func _sfx_step() -> PackedFloat32Array:
	var buf: PackedFloat32Array = _buffer(0.16)
	_sweep(buf, 0.0, 190.0, 95.0, 0.03, 1.0, 0.035)
	_noise(buf, 0.0, 0.05, 0.35, 0.001, 0.012, 1800.0, 200.0)
	return buf


## A small round pop.
func _sfx_tap() -> PackedFloat32Array:
	var buf: PackedFloat32Array = _buffer(0.14)
	_sweep(buf, 0.0, 900.0, 520.0, 0.02, 1.0, 0.03)
	_partial(buf, 0.0, 1560.0, 0.15, 0.012)
	return buf


## A wooden block, struck lightly.
func _sfx_ui_click() -> PackedFloat32Array:
	var buf: PackedFloat32Array = _buffer(0.16)
	_partial(buf, 0.0, 1046.5, 1.0, 0.04, 0.0008)
	_partial(buf, 0.0, 2826.0, 0.3, 0.012, 0.0008)
	_noise(buf, 0.0, 0.01, 0.2, 0.0005, 0.003, 6000.0, 1500.0)
	return buf


## Stone sliding on stone: a grainy band of noise that swells and settles.
func _sfx_slide() -> PackedFloat32Array:
	var length: float = 0.42
	var buf: PackedFloat32Array = _buffer(length + 0.05)
	var low: float = 0.0
	var band: float = 0.0
	var grain: float = 1.0
	var a: float = _one_pole(900.0)
	var b: float = _one_pole(250.0)
	for i in int(length * _rate):
		var t: float = float(i) / _rate
		if i % 300 == 0:
			grain = _rng.randf_range(0.55, 1.0)
		var white: float = _rng.randf_range(-1.0, 1.0)
		low += a * (white - low)
		band += b * (low - band)
		var envelope: float = sin(PI * t / length)
		buf[i] += (low - band) * envelope * envelope * grain * 2.4
	_sweep(buf, 0.0, 70.0, 60.0, 0.2, 0.18, 0.25, 0.08)
	return buf


## A ratchet turning a quarter: clicks over a low hum.
func _sfx_rotate() -> PackedFloat32Array:
	var buf: PackedFloat32Array = _buffer(0.55)
	for k in 6:
		var at: float = 0.02 + k * 0.065
		_partial(buf, at, 2200.0 - k * 60.0, 0.45, 0.008, 0.0005)
		_noise(buf, at, 0.012, 0.5, 0.0003, 0.003, 5000.0, 900.0)
	_partial(buf, 0.0, 98.0, 0.25, 0.3, 0.05)
	return buf


## A part locking into place: a deep clunk with a bright edge.
func _sfx_snap() -> PackedFloat32Array:
	var buf: PackedFloat32Array = _buffer(0.3)
	_sweep(buf, 0.0, 180.0, 110.0, 0.02, 1.0, 0.07)
	_partial(buf, 0.0, 420.0, 0.35, 0.025, 0.0005)
	_noise(buf, 0.0, 0.02, 0.45, 0.0003, 0.005, 4000.0, 600.0)
	return buf


## Two rising kalimba notes.
func _sfx_pickup() -> PackedFloat32Array:
	var buf: PackedFloat32Array = _buffer(0.6)
	_kalimba_into(buf, 0.0, _freq("G5"), 0.8, 0.18)
	_kalimba_into(buf, 0.075, _freq("D6"), 1.0, 0.22)
	return buf


## A parcel set down: a papery thud and a soft low note.
func _sfx_drop() -> PackedFloat32Array:
	var buf: PackedFloat32Array = _buffer(0.35)
	_sweep(buf, 0.0, 240.0, 150.0, 0.04, 0.8, 0.08)
	_noise(buf, 0.0, 0.08, 0.5, 0.002, 0.03, 2500.0, 300.0)
	_kalimba_into(buf, 0.02, _freq("C5"), 0.35, 0.15)
	return buf


## A pad lighting up: a bright two-bell chime.
func _sfx_pad_complete() -> PackedFloat32Array:
	var buf: PackedFloat32Array = _buffer(1.4)
	_bell_into(buf, 0.0, _freq("C6"), 0.8, 0.5)
	_bell_into(buf, 0.06, _freq("G6"), 0.6, 0.45)
	return buf


## The finish jingle: a rising arpeggio landing on a shimmering chord.
func _sfx_level_complete() -> PackedFloat32Array:
	var buf: PackedFloat32Array = _buffer(2.6)
	var notes: Array[String] = ["C5", "E5", "G5", "C6"]
	for k in notes.size():
		_kalimba_into(buf, k * 0.11, _freq(notes[k]), 0.8, 0.4)
	for note: String in ["C6", "E6", "G6"]:
		_bell_into(buf, 0.46, _freq(note), 0.4, 1.1)
	_partial(buf, 0.44, _freq("C4"), 0.35, 0.8, 0.01)
	_fade_out(buf, 0.6)
	return _reverb(buf, 0.25, 0.75)


## A gentle "no": two soft low notes stepping down.
func _sfx_error() -> PackedFloat32Array:
	var buf: PackedFloat32Array = _buffer(0.42)
	_marimba_into(buf, 0.0, _freq("A3"), 0.8, 0.12)
	_marimba_into(buf, 0.11, _freq("F3"), 0.9, 0.16)
	return buf


## Skating over ice: a bright airy whoosh.
func _sfx_glide() -> PackedFloat32Array:
	var length: float = 0.5
	var buf: PackedFloat32Array = _buffer(length + 0.05)
	var low: float = 0.0
	var high: float = 0.0
	var a: float = _one_pole(5000.0)
	var b: float = _one_pole(1500.0)
	for i in int(length * _rate):
		var t: float = float(i) / _rate
		var white: float = _rng.randf_range(-1.0, 1.0)
		low += a * (white - low)
		high += b * (low - high)
		var envelope: float = sin(PI * pow(t / length, 0.7))
		buf[i] += (low - high) * envelope * envelope * 1.6
	_partial(buf, 0.05, 2637.0, 0.06, 0.2, 0.08)
	return buf


## Dry boards creaking under a step: stick-slip pulses through a woody body.
func _sfx_creak() -> PackedFloat32Array:
	var length: float = 0.38
	var buf: PackedFloat32Array = _buffer(length + 0.1)
	var t: float = 0.01
	while t < length:
		var progress: float = t / length
		_partial(buf, t, 310.0 + 90.0 * progress, 0.5 * sin(PI * progress), 0.006, 0.0005)
		_partial(buf, t, 760.0, 0.15 * sin(PI * progress), 0.004, 0.0005)
		t += lerpf(0.016, 0.007, progress) * _rng.randf_range(0.85, 1.15)
	return buf


## Boards dropping away: a hollow thud and a rattle of planks.
func _sfx_fall() -> PackedFloat32Array:
	var buf: PackedFloat32Array = _buffer(0.75)
	_sweep(buf, 0.0, 160.0, 70.0, 0.15, 0.9, 0.18)
	for k in 5:
		var at: float = 0.12 + k * 0.07 + _rng.randf_range(-0.01, 0.01)
		_noise(buf, at, 0.03, 0.4 * (1.0 - k * 0.15), 0.0005, 0.01, 3000.0, 400.0)
		_partial(buf, at, 520.0 + 70.0 * k, 0.2, 0.02, 0.0005)
	return buf


## The diorama assembling: a soft airy swell rising in pitch.
func _sfx_whoosh() -> PackedFloat32Array:
	var length: float = 0.9
	var buf: PackedFloat32Array = _buffer(length + 0.05)
	var low: float = 0.0
	var band: float = 0.0
	for i in int(length * _rate):
		var t: float = float(i) / _rate
		var white: float = _rng.randf_range(-1.0, 1.0)
		low += _one_pole(lerpf(600.0, 3500.0, t / length)) * (white - low)
		band += _one_pole(250.0) * (low - band)
		var envelope: float = sin(PI * t / length)
		buf[i] += (low - band) * envelope * envelope * 1.5
	return buf


## A spring throwing the courier: a soft thump into the pad and a bright
## boing that rises out of the squash with the coil's wobble on it.
func _sfx_bounce() -> PackedFloat32Array:
	var length: float = 0.55
	var buf: PackedFloat32Array = _buffer(length + 0.05)
	_sweep(buf, 0.0, 180.0, 90.0, 0.04, 0.5, 0.06)
	var phase: float = 0.0
	for i in int(length * _rate):
		var t: float = float(i) / _rate
		var freq: float = 520.0 - 300.0 * exp(-t / 0.06) + 60.0 * exp(-t / 0.18) * sin(TAU * 14.0 * t)
		phase += TAU * freq / _rate
		var envelope: float = minf(t / 0.005, 1.0) * exp(-t / 0.16)
		buf[i] += envelope * (0.6 * sin(phase) + 0.25 * sin(2.0 * phase) + 0.1 * sin(3.0 * phase))
	return buf


## Thin ice taking a step: a few glassy ticks and a soft groan under them.
func _sfx_crackle() -> PackedFloat32Array:
	var buf: PackedFloat32Array = _buffer(0.45)
	_sweep(buf, 0.0, 900.0, 520.0, 0.08, 0.25, 0.07, 0.01)
	var t: float = 0.02
	for k in 7:
		var bright: float = _rng.randf_range(2200.0, 4600.0)
		_noise(buf, t, 0.004, 0.35, 0.0003, 0.004, 9000.0, 1800.0)
		_partial(buf, t, bright, 0.3 * (1.0 - k * 0.1), 0.012, 0.0003)
		_partial(buf, t, bright * 1.53, 0.12, 0.008, 0.0003)
		t += _rng.randf_range(0.025, 0.05)
	return buf


## Thin ice breaking away: a sharp crack, a tinkle of shards and a soft
## plop as the slab drops.
func _sfx_shatter() -> PackedFloat32Array:
	var buf: PackedFloat32Array = _buffer(0.9)
	_noise(buf, 0.0, 0.01, 0.9, 0.0003, 0.02, 10000.0, 1500.0)
	_sweep(buf, 0.0, 1400.0, 600.0, 0.03, 0.35, 0.05)
	for k in 12:
		var at: float = 0.02 + k * 0.035 + _rng.randf_range(-0.012, 0.012)
		var freq: float = _rng.randf_range(2600.0, 6200.0)
		_partial(buf, at, freq, 0.28 * (1.0 - k * 0.06), 0.05, 0.0005)
		_partial(buf, at, freq * 1.41, 0.1, 0.03, 0.0005)
	_sweep(buf, 0.38, 420.0, 140.0, 0.06, 0.35, 0.09, 0.004)
	return buf


# --- Music -------------------------------------------------------------------

## The song (a _music_<n> function) each world plays.
const SONGS: Dictionary = {1: 1, 2: 2, 3: 3, 4: 4, 5: 6, 6: 7, 7: 5}

func _make_music() -> void:
	_rate = MUSIC_RATE
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT.path_join("music")))
	for world in range(1, 8):
		# Songs keep the numbers their worlds had when written: Frost Peaks
		# (song 5) moved to the end, so worlds 5-7 play songs 6, 7 and 5.
		var number: int = SONGS[world]
		_rng.seed = 1000 + number
		_notes.clear()
		var started: int = Time.get_ticks_msec()
		var song: Dictionary = call("_music_%d" % number)
		var buf: PackedFloat32Array = song["buffer"]
		buf = _reverb(buf, song["reverb"], song.get("room", 0.84))
		var length: int = int(song["length"] * _rate)
		for i in buf.size() - length:
			buf[i % length] += buf[length + i]
		buf.resize(length)
		_level(buf)
		_write_wav(OUT.path_join("music/world_%d.wav" % world), buf, _rate)
		print("make_audio: world %d, %.1f s loop, made in %.1f s"
			% [world, song["length"], (Time.get_ticks_msec() - started) / 1000.0])


## Meadow: C major pentatonic, a kalimba wandering over warm pads, a soft
## sine bass and the odd bird.
func _music_1() -> Dictionary:
	var beat: float = 60.0 / 72.0
	var length: float = 32.0 * beat
	var buf: PackedFloat32Array = _buffer(length + TAIL)
	var chords: Array = [["C3", "G3", "D4", "E4"], ["A2", "E3", "G3", "C4"], ["F2", "C3", "G3", "A3"], ["G2", "D3", "E3", "B3"]]
	_pads(buf, chords, 8.0 * beat, 0.11)
	for bar in 8:
		var root: String = chords[bar >> 1][0]
		_mix(buf, _note(&"bass", _freq(root)), bar * 4.0 * beat, 0.32)
		_mix(buf, _note(&"bass", _freq(root)), (bar * 4.0 + 2.5) * beat, 0.18)
	var scale: Array[String] = ["C5", "D5", "E5", "G5", "A5", "C6", "D6", "E6"]
	_melody(buf, scale, &"kalimba", beat, 32, 0.5, 0.26, [15, 31])
	for at: float in [5.3, 19.1]:
		_bird(buf, at * beat)
	return {"buffer": buf, "length": length, "reverb": 0.25}


## Harbour: G mixolydian, rolling marimba over a low pad, waves on the
## shingle and a far-off buoy bell.
func _music_2() -> Dictionary:
	var beat: float = 60.0 / 66.0
	var length: float = 32.0 * beat
	var buf: PackedFloat32Array = _buffer(length + TAIL)
	var chords: Array = [["G2", "D3", "B3"], ["F2", "C3", "A3"], ["C3", "G3", "E4"], ["G2", "D3", "B3"]]
	_pads(buf, chords, 8.0 * beat, 0.09)
	var arpeggios: Array = [["G4", "B4", "D5", "B4"], ["F4", "A4", "C5", "A4"], ["E4", "G4", "C5", "G4"], ["D4", "G4", "B4", "D5"]]
	for bar in 8:
		var notes: Array = arpeggios[bar >> 1]
		for k in 8:
			if _rng.randf() < (0.85 if k % 2 == 0 else 0.45):
				var note: String = notes[k % 4] if _rng.randf() < 0.8 else notes[(k + 2) % 4]
				_mix(buf, _note(&"marimba", _freq(note)), (bar * 4.0 + k * 0.5) * beat + _rng.randf_range(0.0, 0.012),
					_rng.randf_range(0.16, 0.24) * (1.0 if k % 4 == 0 else 0.75))
		_mix(buf, _note(&"bass", _freq(chords[bar >> 1][0])), bar * 4.0 * beat, 0.26)
	_mix(buf, _note(&"bell", _freq("G3")), 0.5 * beat, 0.08)
	_mix(buf, _note(&"bell", _freq("G3")), 16.5 * beat, 0.06)
	_waves(buf, length, 4)
	return {"buffer": buf, "length": length, "reverb": 0.3}


## Old town: raga Bhupali on D (D E F# A B), a tanpura drone cycling Pa,
## Sa, Sa, low Sa, and santoor phrases with tremolo on the long notes.
func _music_3() -> Dictionary:
	var beat: float = 60.0 / 60.0
	var length: float = 32.0 * beat
	var buf: PackedFloat32Array = _buffer(length + TAIL)
	var cycle: Array[String] = ["A2", "D3", "D3", "D2"]
	for k in 32:
		_mix(buf, _note(&"tanpura", _freq(cycle[k % 4])), k * beat, 0.16 if k % 4 != 3 else 0.2)
	var phrases: Array = [
		["D4", "E4", "F#4", "A4", "F#4"], ["A4", "B4", "D5", "B4", "A4"], ["F#4", "A4", "B4", "A4", "F#4", "E4"],
		["D5", "B4", "A4", "F#4", "E4", "D4"], ["E4", "F#4", "A4", "B4", "A4"], ["A4", "F#4", "E4", "D4"],
	]
	var at: float = 1.0
	var index: int = 0
	while at < 30.0:
		var phrase: Array = phrases[index % phrases.size()]
		index += 1 + (_rng.randi() % 2)
		for k in phrase.size():
			var last: bool = k == phrase.size() - 1
			var step: float = 2.0 if last else (0.5 if _rng.randf() < 0.7 else 1.0)
			var freq: float = _freq(phrase[k])
			_mix(buf, _note(&"santoor", freq), at * beat, 0.24)
			if last or step >= 1.0:
				# Tremolo: quick soft strokes on a held note.
				var strokes: int = int(step * 4.0) - 1
				for s in strokes:
					_mix(buf, _note(&"santoor", freq), (at + 0.25 * (s + 1)) * beat, 0.1 * (1.0 - float(s) / strokes))
			at += step
			if at >= 30.0:
				break
		at += 1.0
	return {"buffer": buf, "length": length, "reverb": 0.3}


## Orchard: F major, a finger-picked guitar over a warm pad, with a few
## melody notes up high.
func _music_4() -> Dictionary:
	var beat: float = 60.0 / 76.0
	var length: float = 32.0 * beat
	var buf: PackedFloat32Array = _buffer(length + TAIL)
	var chords: Array = [["F2", "C3", "F3", "A3"], ["D2", "A2", "D3", "F3"], ["A#1", "F2", "A#2", "D3"], ["C2", "G2", "C3", "E3"]]
	_pads(buf, chords, 8.0 * beat, 0.07)
	# Thumb on the root, fingers rolling through the upper notes.
	var pattern: Array[int] = [0, 2, 3, 1, 3, 2, 3, 1]
	for bar in 8:
		var chord: Array = chords[bar >> 1]
		for k in 8:
			var index: int = pattern[k]
			var note: String = chord[index]
			var freq: float = _freq(note) * (2.0 if index > 0 else 1.0)
			_mix(buf, _note(&"guitar", freq), (bar * 4.0 + k * 0.5) * beat + _rng.randf_range(0.0, 0.015),
				(0.3 if k == 0 else 0.17) * _rng.randf_range(0.85, 1.0))
	var scale: Array[String] = ["F5", "G5", "A5", "C6", "D6"]
	_melody(buf, scale, &"guitar", beat, 32, 0.22, 0.2, [7, 15, 23, 31])
	return {"buffer": buf, "length": length, "reverb": 0.22}


## Frost peaks: E minor, slow airy pads, sparse bells and the wind.
func _music_5() -> Dictionary:
	var beat: float = 60.0 / 56.0
	var length: float = 32.0 * beat
	var buf: PackedFloat32Array = _buffer(length + TAIL)
	var chords: Array = [["E2", "B2", "G3", "F#4"], ["C3", "G3", "B3", "E4"], ["G2", "D3", "B3", "D4"], ["F#2", "D3", "A3", "E4"]]
	_pads(buf, chords, 8.0 * beat, 0.12)
	var scale: Array[String] = ["E5", "G5", "A5", "B5", "D6", "E6"]
	_melody(buf, scale, &"bell", beat, 32, 0.3, 0.12, [14, 15, 30, 31])
	_wind(buf, length)
	return {"buffer": buf, "length": length, "reverb": 0.45, "room": 0.88}


## Blossom valley: D major, a music-box melody on bells over rippling
## marimba and light pads, with birds about in the blossom.
func _music_6() -> Dictionary:
	var beat: float = 60.0 / 80.0
	var length: float = 32.0 * beat
	var buf: PackedFloat32Array = _buffer(length + TAIL)
	var chords: Array = [["D3", "A3", "F#4"], ["B2", "F#3", "D4"], ["G2", "D3", "B3"], ["A2", "E3", "C#4"]]
	_pads(buf, chords, 8.0 * beat, 0.08)
	var arpeggios: Array = [["D4", "F#4", "A4", "F#4"], ["B3", "D4", "F#4", "D4"], ["G3", "B3", "D4", "B3"], ["A3", "C#4", "E4", "C#4"]]
	for bar in 8:
		var notes: Array = arpeggios[bar >> 1]
		for k in 8:
			if _rng.randf() < (0.8 if k % 2 == 0 else 0.35):
				_mix(buf, _note(&"marimba", _freq(notes[k % 4])), (bar * 4.0 + k * 0.5) * beat + _rng.randf_range(0.0, 0.01),
					_rng.randf_range(0.12, 0.18) * (1.0 if k % 4 == 0 else 0.7))
		_mix(buf, _note(&"bass", _freq(chords[bar >> 1][0])), bar * 4.0 * beat, 0.24)
	var scale: Array[String] = ["D5", "E5", "F#5", "A5", "B5", "D6", "E6"]
	_melody(buf, scale, &"bell", beat, 32, 0.35, 0.1, [7, 15, 23, 31])
	for at: float in [3.2, 11.6, 21.4, 27.8]:
		_bird(buf, at * beat)
	return {"buffer": buf, "length": length, "reverb": 0.28}


## Sunflower fields: A major, a bouncing bass and a sunny kalimba tune over
## a marimba ripple and warm pads, with birds about the field.
func _music_7() -> Dictionary:
	var beat: float = 60.0 / 84.0
	var length: float = 32.0 * beat
	var buf: PackedFloat32Array = _buffer(length + TAIL)
	var chords: Array = [["A2", "E3", "C#4"], ["F#2", "C#3", "A3"], ["D3", "A3", "F#4"], ["E2", "B2", "G#3"]]
	_pads(buf, chords, 8.0 * beat, 0.08)
	var arpeggios: Array = [["A3", "C#4", "E4", "C#4"], ["F#3", "A3", "C#4", "A3"], ["D4", "F#4", "A4", "F#4"], ["E3", "G#3", "B3", "G#3"]]
	for bar in 8:
		var chord: Array = chords[bar >> 1]
		var notes: Array = arpeggios[bar >> 1]
		for k in 8:
			if _rng.randf() < (0.75 if k % 2 == 0 else 0.3):
				_mix(buf, _note(&"marimba", _freq(notes[k % 4])), (bar * 4.0 + k * 0.5) * beat + _rng.randf_range(0.0, 0.01),
					_rng.randf_range(0.1, 0.15) * (1.0 if k % 4 == 0 else 0.7))
		# The bass bounces: root, fifth, then the root an octave up.
		_mix(buf, _note(&"bass", _freq(chord[0])), bar * 4.0 * beat, 0.26)
		_mix(buf, _note(&"bass", _freq(chord[1])), (bar * 4.0 + 1.5) * beat, 0.16)
		_mix(buf, _note(&"bass", _freq(chord[0]) * 2.0), (bar * 4.0 + 2.0) * beat, 0.14)
	var scale: Array[String] = ["A4", "B4", "C#5", "E5", "F#5", "A5", "B5"]
	_melody(buf, scale, &"kalimba", beat, 32, 0.45, 0.22, [7, 15, 23, 31])
	for at: float in [2.6, 13.4, 22.2]:
		_bird(buf, at * beat)
	return {"buffer": buf, "length": length, "reverb": 0.24}


## Soft detuned pads, one chord per [param span] seconds, overlapping a
## little into the next.
func _pads(buf: PackedFloat32Array, chords: Array, span: float, gain: float) -> void:
	for c in chords.size():
		for note: String in chords[c]:
			_pad_tone(buf, c * span, span + 1.8, _freq(note), gain)


## A wandering melody on [param scale]: on each beat (and sometimes the
## half beat after it) a note may sound, moving mostly by step; the beats in
## [param rests] stay quiet so phrases breathe.
func _melody(buf: PackedFloat32Array, scale: Array[String], instrument: StringName, beat: float, beats: int,
		density: float, gain: float, rests: Array) -> void:
	var index: int = scale.size() >> 1
	for k in beats:
		if rests.has(k):
			continue
		for half in 2:
			if _rng.randf() > (density if half == 0 else density * 0.4):
				continue
			index = clampi(index + [-2, -1, -1, 1, 1, 2, 0][_rng.randi() % 7], 0, scale.size() - 1)
			_mix(buf, _note(instrument, _freq(scale[index])), (k + half * 0.5) * beat + _rng.randf_range(0.0, 0.02),
				gain * _rng.randf_range(0.7, 1.0) * (1.0 if half == 0 else 0.7))


func _bird(buf: PackedFloat32Array, at: float) -> void:
	for k in 3:
		var start: float = at + k * 0.11
		var n: int = int(0.07 * _rate)
		var begin: int = int(start * _rate)
		var phase: float = 0.0
		for i in mini(n, buf.size() - begin):
			var t: float = float(i) / n
			phase += TAU * lerpf(3200.0, 4300.0, sin(PI * t)) / _rate
			buf[begin + i] += 0.035 * sin(PI * t) * sin(phase)


## Waves washing in [param swells] times per loop: low noise that swells
## and draws back, seamless across the loop.
func _waves(buf: PackedFloat32Array, length: float, swells: int) -> void:
	var low: float = 0.0
	var darker: float = 0.0
	var lower: float = 0.0
	var a: float = _one_pole(900.0)
	var b: float = _one_pole(450.0)
	var c: float = _one_pole(90.0)
	var n: int = int(length * _rate)
	for i in n + int(TAIL * _rate):
		var t: float = float(i) / _rate
		var white: float = _rng.randf_range(-1.0, 1.0)
		low += a * (white - low)
		darker += b * (low - darker)
		lower += c * (darker - lower)
		var phase: float = fmod(t / length * swells, 1.0)
		var swell: float = pow(sin(PI * phase), 3.0) * (0.6 + 0.4 * sin(PI * phase * 2.0 + 0.5))
		buf[i] += (darker - lower) * maxf(swell, 0.0) * 0.16 * _seam(i, n)


## Wind: noise through a slowly sweeping resonant band, seamless across the loop.
func _wind(buf: PackedFloat32Array, length: float) -> void:
	var low: float = 0.0
	var band: float = 0.0
	var smooth: float = 0.0
	var a: float = _one_pole(1400.0)
	var n: int = int(length * _rate)
	for i in n + int(TAIL * _rate):
		var t: float = float(i) / _rate
		var sweep: float = 0.5 + 0.5 * sin(TAU * t / length * 2.0) * sin(TAU * t / length + 1.0)
		var f: float = 2.0 * sin(PI * lerpf(300.0, 900.0, sweep) / _rate)
		var white: float = _rng.randf_range(-1.0, 1.0)
		# Chamberlin state-variable filter, a narrow band-pass that whistles.
		var high: float = white - low - 0.3 * band
		band += f * high
		low += f * band
		smooth += a * (band - smooth)
		buf[i] += smooth * (0.004 + 0.008 * sweep) * _seam(i, n)


## Equal-power crossfade weight for a continuous layer rendered past the
## loop end [param n]: it fades in over the first TAIL and out over the
## TAIL after the end, so folding the tail back keeps its level even.
func _seam(i: int, n: int) -> float:
	var span: float = TAIL * _rate
	if i < span:
		return sin(PI * 0.5 * i / span)
	if i >= n:
		return cos(PI * 0.5 * minf((i - n) / span, 1.0))
	return 1.0


# --- Instruments -------------------------------------------------------------

## A note of [param instrument] at unit level, rendered once per pitch.
func _note(instrument: StringName, freq: float) -> PackedFloat32Array:
	var key: String = "%s/%.2f" % [instrument, freq]
	if _notes.has(key):
		return _notes[key]
	var note: PackedFloat32Array
	match instrument:
		&"kalimba":
			note = _buffer(2.4)
			_kalimba_into(note, 0.0, freq, 1.0, 0.8)
		&"marimba":
			note = _buffer(1.6)
			_marimba_into(note, 0.0, freq, 1.0, 0.45)
		&"bell":
			note = _buffer(5.0)
			_bell_into(note, 0.0, freq, 1.0, 1.8)
		&"guitar":
			note = _buffer(3.0)
			_string_into(note, freq, 1.4, 0.18)
		&"santoor":
			note = _buffer(2.2)
			_string_into(note, freq, 0.8, 0.08)
			_string_into(note, freq * 1.0035, 0.8, 0.08, 0.6)
		&"bass":
			note = _buffer(2.5)
			_partial(note, 0.0, freq, 1.0, 0.9, 0.012)
			_partial(note, 0.0, freq * 2.0, 0.25, 0.4, 0.012)
		&"tanpura":
			note = _buffer(4.5)
			_tanpura_into(note, freq)
	# Whatever still rings at the end of the buffer fades rather than clicks.
	_fade_out(note, 0.3)
	_notes[key] = note
	return note


## Kalimba: a round fundamental with two quick inharmonic tine partials and
## a tiny click.
func _kalimba_into(buf: PackedFloat32Array, at: float, freq: float, amp: float, tau: float) -> void:
	_partial(buf, at, freq, amp, tau, 0.002)
	_partial(buf, at, freq * 5.4, amp * 0.18, tau * 0.12, 0.001)
	_partial(buf, at, freq * 13.3, amp * 0.06, tau * 0.04, 0.0005)
	_partial(buf, at, freq * 2.0, amp * 0.08, tau * 0.5, 0.002)


## Marimba: a woody fundamental and its tuned overtones dying fast.
func _marimba_into(buf: PackedFloat32Array, at: float, freq: float, amp: float, tau: float) -> void:
	_partial(buf, at, freq, amp, tau, 0.001)
	_partial(buf, at, freq * 3.93, amp * 0.3, tau * 0.18, 0.0007)
	_partial(buf, at, freq * 9.8, amp * 0.08, tau * 0.06, 0.0005)


## Bell: inharmonic partials (the hum below, the tierce and the higher ones)
## ringing on.
func _bell_into(buf: PackedFloat32Array, at: float, freq: float, amp: float, tau: float) -> void:
	_partial(buf, at, freq, amp, tau, 0.002)
	_partial(buf, at, freq * 0.5, amp * 0.18, tau * 1.6, 0.004)
	_partial(buf, at, freq * 2.76, amp * 0.42, tau * 0.55, 0.001)
	_partial(buf, at, freq * 5.4, amp * 0.2, tau * 0.3, 0.001)
	_partial(buf, at, freq * 8.93, amp * 0.1, tau * 0.16, 0.0007)


## A plucked string: harmonics shaped by where it is plucked, the high ones
## fading first.
func _string_into(buf: PackedFloat32Array, freq: float, tau: float, pluck: float, amp: float = 1.0) -> void:
	for n in range(1, 13):
		var h: float = freq * n
		if h > _rate * 0.45:
			break
		var weight: float = absf(sin(PI * n * pluck)) / n
		_partial(buf, 0.0, h, amp * weight, tau / (1.0 + 0.5 * pow(n - 1, 1.2)), 0.0015)


## Tanpura: a bright string whose harmonics bloom one after another (the
## jawari buzz) and beat gently.
func _tanpura_into(buf: PackedFloat32Array, freq: float) -> void:
	var length: int = buf.size()
	for n in range(1, 13):
		var h: float = freq * n * (1.0 + 0.0007 * n)
		if h > _rate * 0.45:
			break
		var weight: float = 1.0 / pow(n, 0.75)
		var bloom: float = 0.04 + 0.09 * n
		var w: float = TAU * h / _rate
		var decay: float = exp(-1.0 / (2.6 * _rate))
		var envelope: float = 1.0
		for i in length:
			var t: float = float(i) / _rate
			buf[i] += weight * (1.0 - exp(-t / bloom)) * envelope * sin(w * i) * (0.85 + 0.15 * sin(TAU * 0.7 * n * t))
			envelope *= decay


## A pad voice: two slightly detuned sines with a soft second harmonic,
## swelling in and out over [param duration].
func _pad_tone(buf: PackedFloat32Array, at: float, duration: float, freq: float, gain: float) -> void:
	var begin: int = int(at * _rate)
	var n: int = mini(int(duration * _rate), buf.size() - begin)
	var rise: float = 1.6 * _rate
	var fall: float = 2.0 * _rate
	var w1: float = TAU * freq * 0.9985 / _rate
	var w2: float = TAU * freq * 1.0015 / _rate
	var w3: float = TAU * freq * 2.0 / _rate
	for i in n:
		var envelope: float = minf(minf(i / rise, 1.0), minf((n - i) / fall, 1.0))
		envelope = envelope * envelope * (3.0 - 2.0 * envelope)
		buf[begin + i] += gain * envelope * (0.5 * sin(w1 * i) + 0.5 * sin(w2 * i + 1.3) + 0.12 * sin(w3 * i))


# --- Building blocks -------------------------------------------------------------

func _buffer(seconds: float) -> PackedFloat32Array:
	var buf := PackedFloat32Array()
	buf.resize(int(seconds * _rate))
	return buf


## Adds a sine at [param freq] that rises over [param attack] seconds and
## then decays with time constant [param tau].
func _partial(buf: PackedFloat32Array, at: float, freq: float, amp: float, tau: float, attack: float = 0.002) -> void:
	if freq >= _rate * 0.48:
		return
	var begin: int = int(at * _rate)
	var n: int = mini(int(tau * 8.0 * _rate), buf.size() - begin)
	var w: float = TAU * freq / _rate
	var decay: float = exp(-1.0 / (tau * _rate))
	var rise: float = maxf(attack * _rate, 1.0)
	var envelope: float = amp
	for i in n:
		buf[begin + i] += envelope * minf(i / rise, 1.0) * sin(w * i)
		envelope *= decay


## A sine gliding from [param from_hz] to [param to_hz] (time constant
## [param glide]) while it decays: thumps and pops.
func _sweep(buf: PackedFloat32Array, at: float, from_hz: float, to_hz: float, glide: float, amp: float, tau: float,
		attack: float = 0.001) -> void:
	var begin: int = int(at * _rate)
	var n: int = mini(int(tau * 8.0 * _rate), buf.size() - begin)
	var phase: float = 0.0
	var rise: float = maxf(attack * _rate, 1.0)
	for i in n:
		var t: float = float(i) / _rate
		phase += TAU * (to_hz + (from_hz - to_hz) * exp(-t / glide)) / _rate
		buf[begin + i] += amp * exp(-t / tau) * minf(i / rise, 1.0) * sin(phase)


## Band-limited noise (low-passed at [param low_hz], with what is below
## [param high_hz] taken out) with an attack and exponential decay.
func _noise(buf: PackedFloat32Array, at: float, duration: float, amp: float, attack: float, tau: float,
		low_hz: float, high_hz: float) -> void:
	var begin: int = int(at * _rate)
	var n: int = mini(int((duration + tau * 6.0) * _rate), buf.size() - begin)
	var a: float = _one_pole(low_hz)
	var b: float = _one_pole(high_hz)
	var low: float = 0.0
	var floor_part: float = 0.0
	var rise: float = maxf(attack * _rate, 1.0)
	var hold: int = int(duration * _rate)
	for i in n:
		var white: float = _rng.randf_range(-1.0, 1.0)
		low += a * (white - low)
		floor_part += b * (low - floor_part)
		var envelope: float = minf(i / rise, 1.0)
		if i > hold:
			envelope *= exp(-(i - hold) / (tau * _rate))
		buf[begin + i] += amp * envelope * (low - floor_part)


## Mixes [param note] into [param buf] at [param at] seconds.
func _mix(buf: PackedFloat32Array, note: PackedFloat32Array, at: float, gain: float) -> void:
	var begin: int = int(at * _rate)
	for i in mini(note.size(), buf.size() - begin):
		buf[begin + i] += note[i] * gain


## Coefficient of a one-pole low-pass at [param hz].
func _one_pole(hz: float) -> float:
	return 1.0 - exp(-TAU * hz / _rate)


## A small Schroeder reverb (four damped combs into two all-passes), mixed
## in at [param wet]; the result is longer by the reverb's tail.
func _reverb(dry: PackedFloat32Array, wet: float, room: float) -> PackedFloat32Array:
	var scale: float = _rate / 44100.0
	var comb_lengths: Array[int] = []
	for length: int in [1116, 1188, 1277, 1356]:
		comb_lengths.append(int(length * scale))
	var pass_lengths: Array[int] = [int(556 * scale), int(441 * scale)]
	var tail: int = int(2.5 * _rate)
	var out := PackedFloat32Array()
	out.resize(dry.size() + tail)
	var combs: Array[PackedFloat32Array] = []
	for length: int in comb_lengths:
		var line := PackedFloat32Array()
		line.resize(length)
		combs.append(line)
	var passes: Array[PackedFloat32Array] = []
	for length: int in pass_lengths:
		var line := PackedFloat32Array()
		line.resize(length)
		passes.append(line)
	var damp: float = 0.25
	var c0: PackedFloat32Array = combs[0]
	var c1: PackedFloat32Array = combs[1]
	var c2: PackedFloat32Array = combs[2]
	var c3: PackedFloat32Array = combs[3]
	var p0: PackedFloat32Array = passes[0]
	var p1: PackedFloat32Array = passes[1]
	var l0: int = c0.size()
	var l1: int = c1.size()
	var l2: int = c2.size()
	var l3: int = c3.size()
	var m0: int = p0.size()
	var m1: int = p1.size()
	var h0: float = 0.0
	var h1: float = 0.0
	var h2: float = 0.0
	var h3: float = 0.0
	for i in out.size():
		var x: float = (dry[i] if i < dry.size() else 0.0) * 0.12
		var y0: float = c0[i % l0]
		h0 = y0 * (1.0 - damp) + h0 * damp
		c0[i % l0] = x + h0 * room
		var y1: float = c1[i % l1]
		h1 = y1 * (1.0 - damp) + h1 * damp
		c1[i % l1] = x + h1 * room
		var y2: float = c2[i % l2]
		h2 = y2 * (1.0 - damp) + h2 * damp
		c2[i % l2] = x + h2 * room
		var y3: float = c3[i % l3]
		h3 = y3 * (1.0 - damp) + h3 * damp
		c3[i % l3] = x + h3 * room
		var s: float = y0 + y1 + y2 + y3
		var b0: float = p0[i % m0]
		p0[i % m0] = s + b0 * 0.5
		s = b0 - s
		var b1: float = p1[i % m1]
		p1[i % m1] = s + b1 * 0.5
		s = b1 - s
		out[i] = (dry[i] if i < dry.size() else 0.0) * (1.0 - wet * 0.5) + s * wet
	return out


func _fade_out(buf: PackedFloat32Array, seconds: float) -> void:
	var n: int = mini(int(seconds * _rate), buf.size())
	for i in n:
		buf[buf.size() - n + i] *= 1.0 - float(i) / n


## Cuts the near-silent end (below -60 dBFS) off a sound effect.
func _trim(buf: PackedFloat32Array) -> void:
	var last: int = buf.size() - 1
	while last > 0 and absf(buf[last]) < 0.001:
		last -= 1
	buf.resize(mini(last + int(0.01 * _rate), buf.size()))


func _scale_to_peak(buf: PackedFloat32Array, peak: float) -> void:
	var top: float = 0.0
	for x: float in buf:
		top = maxf(top, absf(x))
	if top > 0.0:
		for i in buf.size():
			buf[i] *= peak / top


## Brings a loop to the music level, rounding off the few peaks above
## MUSIC_PEAK.
func _level(buf: PackedFloat32Array) -> void:
	var sum: float = 0.0
	for x: float in buf:
		sum += x * x
	var rms: float = sqrt(sum / buf.size())
	var gain: float = MUSIC_RMS / maxf(rms, 1e-6)
	for i in buf.size():
		var x: float = buf[i] * gain
		var magnitude: float = absf(x)
		if magnitude > MUSIC_PEAK * 0.8:
			var knee: float = MUSIC_PEAK * 0.8
			magnitude = knee + (MUSIC_PEAK - knee) * tanh((magnitude - knee) / (MUSIC_PEAK - knee))
			x = signf(x) * magnitude
		buf[i] = x


## Frequency of a note name such as "C4", "F#3" or "A#1" (A4 = 440 Hz).
static func _freq(note: String) -> float:
	var names: Array[String] = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
	var sharp: bool = note.length() > 2 and note[1] == "#"
	var pitch: int = names.find(note.substr(0, 2 if sharp else 1))
	var octave: int = note.substr(2 if sharp else 1).to_int()
	return 440.0 * pow(2.0, (pitch + 12 * (octave + 1) - 69) / 12.0)


func _write_wav(path: String, samples: PackedFloat32Array, rate: int) -> void:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, clampi(roundi(samples[i] * 32767.0), -32768, 32767))
	var header := PackedByteArray()
	header.resize(44)
	header.encode_u32(0, 0x46464952)  # "RIFF"
	header.encode_u32(4, 36 + data.size())
	header.encode_u32(8, 0x45564157)  # "WAVE"
	header.encode_u32(12, 0x20746d66)  # "fmt "
	header.encode_u32(16, 16)
	header.encode_u16(20, 1)  # PCM
	header.encode_u16(22, 1)  # mono
	header.encode_u32(24, rate)
	header.encode_u32(28, rate * 2)
	header.encode_u16(32, 2)
	header.encode_u16(34, 16)
	header.encode_u32(36, 0x61746164)  # "data"
	header.encode_u32(40, data.size())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("make_audio: cannot write %s (%s)" % [path, error_string(FileAccess.get_open_error())])
		return
	file.store_buffer(header)
	file.store_buffer(data)
	file.close()
