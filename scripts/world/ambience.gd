extends AudioStreamPlayer
## Procedural ambience for the overgrown city: wind through the towers,
## birdsong, insects, and the faint electrical hum of tech still running.

const RATE := 44100.0

var _pb: AudioStreamGeneratorPlayback
var _lp := [0.0, 0.0]
var _wind_mod := 0.0
var _hum_ph := 0.0
var _cricket_ph := 0.0
var _chirps := []                   # active chirps: [phase, freq, sweep, time_left, length, amp, pan]
var _t := 0.0


func _ready() -> void:
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = RATE
	gen.buffer_length = 0.15
	stream = gen
	volume_db = -10.0
	bus = &"Ambience"
	play()
	_pb = get_stream_playback()


func _process(delta: float) -> void:
	if _pb == null:
		return
	# Start a new bird call now and then: a short run of rising/falling notes.
	if randf() < delta * 0.9:
		var base := randf_range(2200.0, 4200.0)
		var pan := randf_range(-0.8, 0.8)
		var notes := randi_range(2, 6)
		for i in notes:
			_chirps.append([0.0, base * randf_range(0.9, 1.15), randf_range(-1.0, 1.5) * 900.0, -i * 0.11, 0.07, randf_range(0.03, 0.06), pan])
	var n := _pb.get_frames_available()
	if n <= 0:
		return
	var buf := PackedVector2Array()
	buf.resize(n)
	var dt := 1.0 / RATE
	for i in n:
		_t += dt
		var noise := randf() * 2.0 - 1.0
		_lp[0] += (noise - _lp[0]) * 0.015
		_lp[1] += (_lp[0] - _lp[1]) * 0.02
		_wind_mod = 0.6 + 0.4 * sin(_t * 0.23) * sin(_t * 0.071 + 1.0)
		var wind: float = _lp[1] * 9.0 * _wind_mod

		_hum_ph = fmod(_hum_ph + TAU * 57.0 * dt, TAU)
		var hum := (sin(_hum_ph) + 0.4 * sin(_hum_ph * 3.0)) * 0.012 * (0.7 + 0.3 * sin(_t * 0.5))

		_cricket_ph = fmod(_cricket_ph + TAU * 4400.0 * dt, TAU)
		var gate: float = pow(maxf(sin(_t * TAU * 28.0), 0.0), 4.0) * (1.0 if fmod(_t * 0.8, 1.0) > 0.55 else 0.0)
		var cricket: float = sin(_cricket_ph) * gate * 0.018

		var l: float = wind + hum + cricket
		var r: float = wind * 0.9 + hum + cricket * 0.6
		var k := 0
		while k < _chirps.size():
			var c: Array = _chirps[k]
			c[3] += dt
			if c[3] > c[4]:
				_chirps.remove_at(k)
				continue
			if c[3] >= 0.0:
				var env := sin(c[3] / c[4] * PI)
				c[0] = fmod(c[0] + TAU * (c[1] + c[2] * c[3] / c[4]) * dt, TAU)
				var v: float = sin(c[0]) * env * c[5]
				l += v * (1.0 - c[6]) * 0.7
				r += v * (1.0 + c[6]) * 0.7
			k += 1
		buf[i] = Vector2(clampf(l, -1.0, 1.0), clampf(r, -1.0, 1.0))
	_pb.push_buffer(buf)
