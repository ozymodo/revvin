extends AudioStreamPlayer
## Procedural sound effects for the style and air systems (no audio files):
## a rising arpeggio when you grab a tank, a blip that climbs with each
## completed flip, a chord on landing that brightens with the grade, a
## thud when you bail, and a filling whoosh while air flows into the tanks.

const RATE := 22050.0

var car: RigidBody3D

var _pb: AudioStreamGeneratorPlayback
var _voices: Array = []                 # [freq, end freq, delay, length, amp, age, phase, noise]
var _fill := 0.0
var _fill_ph := 0.0
var _lp := 0.0
var _lp2 := 0.0
var _hum := 0.0
var _hum_ph := 0.0
var grind_level := 0.0              # set by world/grinds.gd: 0 off, ~1 grinding fast
var _grind := 0.0
var _grind_ph := 0.0
var _glp := 0.0


func _ready() -> void:
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = RATE
	gen.buffer_length = 0.1
	stream = gen
	volume_db = -6.0
	bus = &"Effects"
	play()
	_pb = get_stream_playback()


func _note(semitones: float, base: float, delay: float, length: float, amp: float, slide := 0.0, noise := false) -> void:
	var f := base * pow(2.0, semitones / 12.0)
	_voices.append([f, f * pow(2.0, slide / 12.0), delay, length, amp, 0.0, 0.0, noise])


func pickup(rocket: bool) -> void:
	var base := 523.0 if rocket else 659.0
	for i in 4:
		_note([0, 4, 7, 12][i], base, i * 0.055, 0.32, 0.22)
	_note(24, base, 0.22, 0.5, 0.08)
	_note(0, 900.0, 0.0, 0.35, 0.18, 24.0, true)     # air rushing in


## Battery: a crackle and a rising charge-up whine, then a bright ping.
func charge() -> void:
	for i in 6:
		_note(0, 2000.0 + i * 300.0, i * 0.035 + randf() * 0.02, 0.05, 0.12, -12.0, true)
	_note(0, 180.0, 0.0, 0.55, 0.14, 26.0)
	_note(0, 360.0, 0.0, 0.55, 0.06, 26.0)
	_note(19, 523.0, 0.42, 0.4, 0.12)


# ------------------------------------------------------------------ combat

## Volume for a sound at `pos`: full nearby, gone by ~90 m.
func _near(pos: Vector3) -> float:
	if car == null:
		return 1.0
	return clampf(1.0 - car.global_position.distance_to(pos) / 90.0, 0.0, 1.0)


## The ray gun: a warbling falling zap, like the COD Ray Gun.
func raygun() -> void:
	_note(0, 1400.0, 0.0, 0.16, 0.13, -14.0)
	_note(0, 2100.0, 0.0, 0.1, 0.06, -10.0)
	_note(0, 600.0, 0.0, 0.08, 0.05, -12.0, true)


func zap(pos: Vector3) -> void:
	var v := _near(pos)
	if v > 0.0:
		_note(0, 300.0, 0.0, 0.18, 0.12 * v, -10.0, true)
		_note(0, 900.0, 0.0, 0.12, 0.07 * v, -12.0)


func goo_spit(pos: Vector3) -> void:
	var v := _near(pos)
	if v > 0.0:
		_note(0, 260.0, 0.0, 0.14, 0.12 * v, 7.0)
		_note(0, 500.0, 0.02, 0.1, 0.06 * v, -5.0, true)


func hop(pos: Vector3, size: float) -> void:
	var v := _near(pos)
	if v > 0.0:
		_note(0, 340.0 / size, 0.0, 0.16, 0.1 * v, 10.0)
		_note(0, 180.0 / size, 0.0, 0.08, 0.06 * v, 0.0, true)


## A ram: a heavy thump.
func thunk(k: float) -> void:
	_note(0, 110.0, 0.0, 0.25, 0.25 * k + 0.1, -10.0)
	_note(0, 400.0, 0.0, 0.12, 0.15 * k + 0.05, -14.0, true)


func crunch(pos: Vector3, power: float) -> void:
	var v := _near(pos) * clampf(power, 0.3, 1.0)
	if v > 0.0:
		_note(0, 700.0, 0.0, 0.2, 0.14 * v, -20.0, true)
		_note(0, 90.0, 0.0, 0.2, 0.12 * v, -6.0)


## Glass going: a bright crash and a tinkle of falling shards.
func glass(pos: Vector3, power: float) -> void:
	var v := _near(pos) * clampf(power, 0.3, 1.0)
	if v > 0.0:
		_note(0, 2400.0, 0.0, 0.18, 0.12 * v, -10.0, true)
		_note(19, 880.0, 0.03, 0.12, 0.05 * v)
		_note(24, 880.0, 0.09, 0.1, 0.04 * v)
		_note(28, 880.0, 0.16, 0.1, 0.03 * v)


## A beast boss roars: low growl under a noisy bellow (`pitch` < 1 deeper).
func roar(pos: Vector3, pitch: float) -> void:
	var v := maxf(_near(pos), 0.25)
	_note(0, 85.0 * pitch, 0.0, 1.3, 0.32 * v, -8.0, true)
	_note(0, 110.0 * pitch, 0.02, 1.1, 0.22 * v, -6.0)
	_note(0, 55.0 * pitch, 0.05, 1.2, 0.25 * v, -5.0)
	_note(7, 160.0 * pitch, 0.1, 0.8, 0.1 * v, -10.0, true)


func enemy_die(size: float) -> void:
	_note(0, 500.0 / size, 0.0, 0.35, 0.16, -20.0, true)
	_note(0, 220.0 / size, 0.0, 0.3, 0.14, -12.0)
	_note(7, 660.0, 0.08, 0.2, 0.07)


func hurt() -> void:
	_note(0, 160.0, 0.0, 0.3, 0.3, -8.0)
	_note(0, 900.0, 0.0, 0.15, 0.12, -18.0, true)


func wrecked() -> void:
	_note(0, 140.0, 0.0, 1.2, 0.35, -24.0)
	_note(0, 600.0, 0.0, 0.9, 0.25, -30.0, true)
	_note(0, 70.0, 0.1, 1.0, 0.3, -12.0)


## Locking onto (or switching on) a rail: a bright metal clank.
func grind_catch() -> void:
	_note(0, 1900.0, 0.0, 0.12, 0.16, -5.0)
	_note(0, 2900.0, 0.0, 0.08, 0.08, -3.0)
	_note(0, 800.0, 0.0, 0.1, 0.12, -10.0, true)


## A dodge that slipped an attack: an airy whoosh and a light ping.
func dodge() -> void:
	_note(0, 500.0, 0.0, 0.25, 0.14, 14.0, true)
	_note(12, 880.0, 0.06, 0.2, 0.08)


# ------------------------------------------------------------------ weapons

func frost() -> void:
	_note(0, 2400.0, 0.0, 0.15, 0.07, -12.0, true)
	_note(19, 900.0, 0.0, 0.2, 0.06, -5.0)


func rocket_launch() -> void:
	_note(0, 400.0, 0.0, 0.5, 0.18, -10.0, true)
	_note(0, 90.0, 0.0, 0.3, 0.14, -4.0)


func missiles() -> void:
	for k in 6:
		_note(0, 900.0, k * 0.04, 0.12, 0.06, -8.0, true)


func saw() -> void:
	_note(0, 1300.0, 0.0, 0.3, 0.06, 3.0)
	_note(0, 2600.0, 0.0, 0.3, 0.03, 3.0)


func sniper() -> void:
	_note(0, 160.0, 0.0, 0.4, 0.3, -14.0)
	_note(0, 3000.0, 0.0, 0.25, 0.14, -24.0, true)


func deagle() -> void:
	_note(0, 220.0, 0.0, 0.18, 0.22, -12.0)
	_note(0, 2000.0, 0.0, 0.12, 0.1, -20.0, true)


func scatter() -> void:
	_note(0, 120.0, 0.0, 0.25, 0.25, -8.0)
	_note(0, 1600.0, 0.0, 0.18, 0.16, -20.0, true)


func tesla() -> void:
	for k in 5:
		_note(0, 3000.0 + randf() * 2000.0, k * 0.025, 0.05, 0.08, -10.0, true)
	_note(0, 60.0, 0.0, 0.3, 0.1, 0.0)


func boom(pos: Vector3) -> void:
	var v := _near(pos)
	if v > 0.0:
		_note(0, 70.0, 0.0, 0.8, 0.35 * v, -20.0)
		_note(0, 500.0, 0.0, 0.6, 0.25 * v, -30.0, true)


## MAG switching on: a rising electric whine.
func mag_on() -> void:
	_note(0, 110.0, 0.0, 0.25, 0.16, 19.0)
	_note(0, 2400.0, 0.0, 0.12, 0.05, -12.0, true)


## MAG holding: short bursts of static, `k` 0.5..1.5 with the pull.
func mag_crackle(k: float) -> void:
	_note(0, randf_range(1800.0, 4200.0), 0.0, randf_range(0.02, 0.05), 0.04 * k, 0.0, true)
	if randf() < 0.35:
		_note(0, 98.0, 0.0, 0.12, 0.05 * k, 0.0)


## MAG slam: a deep thump, a crack of discharge and the static after it.
func mag_slam(power: float) -> void:
	_note(0, lerpf(70.0, 45.0, power), 0.0, 0.6 + power * 0.5, 0.35 + power * 0.15, -14.0)
	_note(0, 900.0, 0.0, 0.35, 0.22 + power * 0.1, -24.0, true)
	_note(0, 3000.0, 0.03, 0.25 + power * 0.3, 0.1, -8.0, true)
	_note(7, 220.0, 0.05, 0.4, 0.08, 12.0)


func rotation(count: int) -> void:
	_note(minf(count * 3.0, 15.0), 880.0, 0.0, 0.09, 0.14, 2.0)


func landed(grade: int, points: int) -> void:
	var chords := [[0, 4, 7, 12, 16], [0, 4, 7, 12], [0, 7, 12], [0, 3], [0]]
	var base: float = [523.0, 494.0, 440.0, 330.0, 262.0][grade]
	var big := clampf(points / 3000.0, 0.0, 1.0)
	var notes: Array = chords[grade]
	for i in notes.size():
		_note(notes[i], base, i * 0.04, 0.55 + big * 0.4, 0.16 + big * 0.06)
	if grade == 0:
		_note(28, base, 0.18, 0.6, 0.07)


func bail() -> void:
	_note(0, 180.0, 0.0, 0.45, 0.35, -18.0)
	_note(0, 300.0, 0.0, 0.25, 0.25, -12.0, true)


func chime() -> void:
	_note(7, 660.0, 0.0, 0.25, 0.14)
	_note(12, 660.0, 0.07, 0.35, 0.14)


func _process(_delta: float) -> void:
	if _pb == null:
		return
	var n := _pb.get_frames_available()
	if n <= 0:
		return
	var t_fill: float = car.air_inflow * Settings.air_gain() if car else 0.0
	var t_hum: float = car.charge_inflow if car else 0.0
	var buf := PackedVector2Array()
	buf.resize(n)
	var dt := 1.0 / RATE
	var s := 1.0 / n
	for i in n:
		var out := 0.0
		var noise := randf() * 2.0 - 1.0
		for v in _voices:
			if v[2] > 0.0:
				v[2] -= dt
				continue
			var k: float = v[5] / v[3]
			v[5] += dt
			if k >= 1.0:
				continue
			var f: float = lerpf(v[0], v[1], k)
			v[6] = fmod(v[6] + TAU * f * dt, TAU)
			var env := minf(v[5] / 0.006, 1.0) * pow(1.0 - k, 2.0)
			if v[7]:
				out += noise * env * v[4] * (0.3 + 0.7 * sin(v[6]) * sin(v[6]))
			else:
				out += (sin(v[6]) * 0.8 + sin(v[6] * 2.0) * 0.15) * env * v[4]
		# Air filling: band-limited noise whose pitch rises with the flow.
		_fill += (t_fill - _fill) * s * 0.5
		if _fill > 0.002:
			_lp += (noise - _lp) * (0.08 + _fill * 0.25)
			_lp2 += (_lp - _lp2) * 0.05
			_fill_ph = fmod(_fill_ph + TAU * (300.0 + _fill * 500.0) * dt, TAU)
			out += ((_lp - _lp2) * 1.6 + sin(_fill_ph) * 0.05) * _fill * 0.4
		# Charging: a soft electrical hum.
		_hum += (t_hum - _hum) * s * 0.5
		if _hum > 0.002:
			_hum_ph = fmod(_hum_ph + TAU * 110.0 * dt, TAU)
			out += (sin(_hum_ph) * 0.5 + sin(_hum_ph * 3.0) * 0.25 + noise * 0.1) * _hum * 0.08
		# Grinding: a ringing metal scrape (noise ring-modulated by two
		# inharmonic tones) over a low rumble, louder and brighter with speed.
		_grind += (grind_level - _grind) * s * 0.3
		if _grind > 0.002:
			_grind_ph = fmod(_grind_ph + TAU * (1700.0 + _grind * 900.0) * dt, TAU)
			_glp += (noise - _glp) * 0.1
			var ring := sin(_grind_ph) * 0.6 + sin(_grind_ph * 2.76) * 0.4
			out += (noise * ring * 0.5 + _glp * 0.8) * minf(_grind, 1.0) * 0.16
		buf[i] = Vector2.ONE * clampf(out, -1.0, 1.0)
	_pb.push_buffer(buf)
	_voices = _voices.filter(func(v: Array) -> bool: return v[2] > 0.0 or v[5] < v[3])
