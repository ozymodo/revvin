extends AudioStreamPlayer
## Procedural sound: electric motor whine, compressed-air hiss from the
## thrusters/jets, suction fan hum, the onboard compressor, tyre screech and wind. No audio files needed.

const RATE := 44100.0

var car: RigidBody3D

var _pb: AudioStreamGeneratorPlayback
var _ph := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
var _lp := [0.0, 0.0, 0.0, 0.0, 0.0]
var _freq := 80.0
var _motor := 0.0
var _hiss := 0.0
var _fan := 0.0
var _wind := 0.0
var _comp := 0.0
var _squeal := 0.0
var _svf := [0.0, 0.0, 0.0, 0.0]       # two resonant noise bands: low, band, low, band
var _flutter := 0.0
var _flutter_to := 0.0
var _flutter_n := 0
var _scrub_lp := 0.0
var _comp_rate := 1.0


func _ready() -> void:
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = RATE
	gen.buffer_length = 0.08
	stream = gen
	volume_db = -8.0
	bus = &"Vehicle"
	play()
	_pb = get_stream_playback()


func _process(_delta: float) -> void:
	if _pb == null:
		return
	var spd: float = absf(car.speed)
	var ml: float = (car.motor_load[0] + car.motor_load[1] + car.motor_load[2]) / 3.0
	var t_freq := 70.0 + spd * 16.0
	var t_motor := 0.04 + 0.16 * ml + clampf(spd / 60.0, 0.0, 1.0) * 0.05
	var t_hiss: float = (car.thrust_valve * (0.5 + 0.5 * car.thrust_tank) * 0.55 + car.jet_output * 0.7) * Settings.air_gain()
	var t_fan: float = car.fan_spin * 0.10
	var t_comp: float = 0.07 if car.compressor_lps > 0.0 else 0.0
	var t_comp_rate: float = 1.6 if car.regen else 1.0
	var t_squeal: float = car.tyre_squeal * 0.16
	var t_wind := clampf(spd / 70.0, 0.0, 1.0) ** 2 * 0.25

	var n := _pb.get_frames_available()
	if n <= 0:
		return
	var buf := PackedVector2Array()
	buf.resize(n)
	var s := 1.0 / n
	for i in n:
		# Ease parameters across the buffer to avoid zipper noise.
		_freq += (t_freq - _freq) * s
		_motor += (t_motor - _motor) * s
		_hiss += (t_hiss - _hiss) * s
		_fan += (t_fan - _fan) * s
		_wind += (t_wind - _wind) * s
		_comp += (t_comp - _comp) * s
		_squeal += (t_squeal - _squeal) * s
		_comp_rate += (t_comp_rate - _comp_rate) * s

		_ph[0] = fmod(_ph[0] + TAU * _freq / RATE, TAU)
		_ph[1] = fmod(_ph[1] + TAU * _freq * 2.02 / RATE, TAU)
		_ph[2] = fmod(_ph[2] + TAU * (38.0 + _fan * 300.0) / RATE, TAU)
		var motor: float = (sin(_ph[0]) * 0.6 + sin(_ph[1]) * 0.25 + sin(_ph[0] * 3.0) * 0.08) * _motor

		var noise := randf() * 2.0 - 1.0
		_lp[0] += (noise - _lp[0]) * 0.55     # bright hiss
		_lp[1] += (noise - _lp[1]) * 0.06     # fan rumble
		_lp[2] += (noise - _lp[2]) * 0.02     # wind
		var hiss: float = (_lp[0] - _lp[1]) * _hiss
		var fan: float = (sin(_ph[2]) * 0.5 + _lp[1] * 1.5) * _fan
		var wind: float = _lp[2] * 3.0 * _wind
		# Compressor: piston chug (amplitude-modulated) over a motor whine.
		_ph[3] = fmod(_ph[3] + TAU * 22.0 * _comp_rate / RATE, TAU)
		_ph[4] = fmod(_ph[4] + TAU * 420.0 * _comp_rate / RATE, TAU)
		var chug := pow(0.5 + 0.5 * sin(_ph[3]), 3.0)
		var comp: float = (chug * (_lp[1] * 2.0 + sin(_ph[4] * 0.25) * 0.4) + sin(_ph[4]) * 0.12) * _comp

		# Tyre screech: white noise through two resonant band-passes (rubber
		# squeal is noisy, not a pure tone), a random flutter on level and
		# pitch as the tread grips and lets go, and a low rubber scrub.
		_flutter_n -= 1
		if _flutter_n <= 0:
			_flutter_n = randi_range(900, 2600)       # 20-60 ms
			_flutter_to = randf() * 2.0 - 1.0
		_flutter += (_flutter_to - _flutter) * 0.002
		var fl := 1.0 + _flutter * 0.05
		var sq_a := _svf_step(0, noise, 1150.0 * fl, 0.09)
		var sq_b := _svf_step(2, noise, 2350.0 * fl, 0.12)
		_scrub_lp += (noise - _scrub_lp) * 0.04
		var squeal: float = (sq_a * 3.0 + sq_b * 1.0 + _scrub_lp * 1.5) * _squeal * (0.8 + _flutter * 0.25)

		var v: float = clampf(motor + hiss + fan + wind + comp + squeal, -1.0, 1.0)
		buf[i] = Vector2(v, v)
	_pb.push_buffer(buf)


## Chamberlin state-variable filter; returns the band-pass output. `damp`
## is 1/Q (smaller = narrower, more tonal).
func _svf_step(k: int, x: float, fc: float, damp: float) -> float:
	var f := 2.0 * sin(PI * fc / RATE)
	_svf[k] += f * _svf[k + 1]
	var high: float = x - _svf[k] - damp * _svf[k + 1]
	_svf[k + 1] += f * high
	return _svf[k + 1] * damp * 2.0
