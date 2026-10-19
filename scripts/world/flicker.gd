extends Label3D
## Failing holographic sign: a slow shimmer plus random dropouts.

var _off := 0.0
var _base: Color


func _ready() -> void:
	_base = modulate


func _process(delta: float) -> void:
	_off -= delta
	if _off <= 0.0 and randf() < 0.012:
		_off = randf_range(0.04, 0.35)
	var a := 0.0 if _off > 0.0 and fmod(_off, 0.08) < 0.04 else 0.75 + 0.25 * sin(Time.get_ticks_msec() * 0.004 + position.x)
	modulate = Color(_base, a)
