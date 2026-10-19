extends Node3D
## A living animal (gorilla, young T. rex, spider or elephant), in herds
## round its boss's territory (world/wildlife.gd). Like the deer: no
## physics, it grazes, wanders near its herd's home and reacts to the car.
## Fast cars scare it off. A slow car close by gets it angry, and the
## fighters (gorillas, rexes, spiders, and elephants once provoked) charge
## in and hit it, weakly. Run one over fast enough and it's biofuel
## (wildlife.gd does the hit test and the conversion).

const Beasts := preload("res://scripts/enemies/beast_models.gd")

enum { GRAZE, WALK, FLEE, ANGRY }

## kind: [radius, height, walk speed, run speed, kill speed (m/s), bite damage,
##        anger range, fights? (0 no, 1 yes, 2 only when provoked), biofuel, points, colour]
const KINDS := {
	"gorilla": [0.9, 1.9, 1.3, 9.0, 6.0, 3.0, 13.0, 1, 0.04, 60, Color(0.12, 0.12, 0.13)],
	"rex": [1.2, 3.0, 1.8, 12.0, 8.0, 5.0, 20.0, 1, 0.05, 90, Color(0.33, 0.37, 0.2)],
	"spider": [0.6, 0.9, 1.6, 8.5, 2.5, 2.0, 9.0, 1, 0.02, 30, Color(0.08, 0.07, 0.08)],
	"elephant": [1.7, 3.3, 1.2, 7.5, 13.0, 6.0, 8.0, 2, 0.08, 120, Color(0.42, 0.4, 0.38)],
}

var kind := "gorilla"
var city: Node
var home := Vector3.ZERO
var hunter := false                 # brood spawned by a boss: always hunts the car
var dead := false
var respawn_t := 0.0

var radius := 1.0
var height := 2.0
var _p: Array
var _state := GRAZE
var _timer := 0.0
var _target := Vector3.ZERO
var _dir := Vector3.FORWARD
var _face := Vector3.FORWARD
var _speed := 0.0
var _phase := 0.0
var _model: Node3D
var _legs: Array[Node3D] = []
var _head: Node3D
var _jaw: Node3D
var _tail: Node3D
var _trunk: Node3D
var _ears: Array[Node3D] = []
var _bite_cd := 0.0
var _provoked := 0.0
var _size := 1.0
var _hop := 0.0
var _car: RigidBody3D
var _far := 0.0                     # skips animation when far away


func _ready() -> void:
	_p = KINDS[kind]
	_size = randf_range(0.85, 1.15)
	radius = _p[0] * _size
	height = _p[1] * _size
	_model = Beasts.animal(kind)
	add_child(_model)
	for n in _model.find_children("Leg_*", "", true, false):
		_legs.append(n as Node3D)
	_head = _model.find_child("Head", true, false)
	_jaw = _model.find_child("Jaw", true, false)
	_tail = _model.find_child("Tail", true, false)
	_trunk = _model.find_child("Trunk", true, false)
	for n in ["Ear_L", "Ear_R"]:
		var e := _model.find_child(n, true, false)
		if e:
			_ears.append(e as Node3D)
	_timer = randf_range(1.0, 6.0)
	_dir = Vector3.FORWARD.rotated(Vector3.UP, randf() * TAU)
	_face = _dir
	_phase = randf() * TAU
	basis = Basis.looking_at(_face, Vector3.UP).scaled(Vector3.ONE * _size)
	add_to_group("critters")
	Lod.add_agent(self)


## Lod: every frame while hunting or fighting, whatever the distance.
func lod_awake() -> bool:
	return hunter or _state == ANGRY


## Something hurt us without killing us (a slow bump): get angry.
func provoke() -> void:
	_provoked = 8.0


## Whether it's up for a fight with the car right now.
func fighting() -> bool:
	return _state == ANGRY


## wildlife.gd asks each frame: true when this one lands a hit (bite/punch).
func try_hit(dist: float) -> bool:
	if _state != ANGRY or _bite_cd > 0.0 or dist > radius + 2.2:
		return false
	_bite_cd = 1.3
	_hop = 0.35
	return true


func bite_damage() -> float:
	return _p[5] * _size


func _process(delta: float) -> void:
	if dead:
		return
	if _car == null:
		_car = get_tree().get_first_node_in_group("player_car")
		if _car == null:
			return
	_bite_cd -= delta
	_provoked -= delta
	var to_car := _car.global_position - global_position
	to_car.y = 0.0
	var dist := to_car.length()
	# Far away: tick slowly, no animation.
	if dist > 260.0:
		_far += delta
		if _far < 0.5:
			return
		delta = _far
		_far = 0.0
	var car_speed := _car.linear_velocity.length()
	var fights: int = _p[7]
	var angry_range: float = _p[6]
	var wants_fight := hunter or (fights == 1 and dist < angry_range and car_speed < 9.0) or (fights == 2 and _provoked > 0.0)
	if wants_fight and dist < angry_range * (3.0 if hunter else 1.6):
		_state = ANGRY
		_dir = to_car.normalized() if dist > 0.1 else _dir
	elif _state == ANGRY:
		_state = WALK
		_target = home
	elif dist < 10.0 or (dist < 34.0 and car_speed > 3.0):
		_state = FLEE
		_timer = randf_range(3.0, 5.0)
		_dir = _dir.lerp(-to_car.normalized(), 0.15).normalized()

	var want_speed := 0.0
	match _state:
		GRAZE:
			_timer -= delta
			if _timer <= 0.0:
				_state = WALK
				_target = home + Vector3(randf_range(-25, 25), 0, randf_range(-25, 25))
		WALK:
			want_speed = _p[2]
			var to := _target - global_position
			to.y = 0.0
			if to.length() < 2.0:
				_state = GRAZE
				_timer = randf_range(3.0, 9.0)
			else:
				_dir = _dir.lerp(to.normalized(), 2.0 * delta).normalized()
		FLEE:
			want_speed = _p[3]
			_timer -= delta
			if _timer <= 0.0 and dist > 40.0:
				_state = WALK
				_target = home + Vector3(randf_range(-15, 15), 0, randf_range(-15, 15))
		ANGRY:
			want_speed = _p[3] * (0.0 if dist < radius + 1.6 else 1.0)

	# Keep out of buildings and the stunt features, inside the play area.
	var ahead := global_position + _dir * (3.0 + radius)
	if city and _state != ANGRY and (city.in_building(ahead.x, ahead.z, 1.0) or city.is_reserved(ahead.x, ahead.z, 1.0) \
			or absf(ahead.x) > 390.0 or absf(ahead.z) > 390.0):
		_dir = _dir.rotated(Vector3.UP, PI * 0.5 * (1.0 if randf() < 0.5 else -1.0))

	_speed = lerpf(_speed, want_speed, 1.0 - exp(-3.0 * delta))
	global_position += _dir * _speed * delta
	global_position.y = 0.0
	if _speed > 0.2 or _state == ANGRY:
		_face = _face.lerp(_dir, 1.0 - exp(-6.0 * delta)).normalized()
		basis = Basis.looking_at(_face, Vector3.UP).scaled(Vector3.ONE * _size)
	if dist < 260.0:
		_animate(delta)


func _animate(delta: float) -> void:
	var fast := _speed > 4.0
	_phase += delta * (2.0 + _speed * (0.9 if kind != "spider" else 2.2))
	var amp := clampf(_speed / 2.0, 0.0, 1.0) * (0.6 if fast else 0.35)
	for i in _legs.size():
		var leg := _legs[i]
		var n := String(leg.name)
		var off := 0.0
		if kind == "spider":
			# Alternating tetrapod gait, legs sweep forward and back.
			off = PI * float((i + (1 if n.ends_with("R") else 0)) % 2)
			leg.rotation.y = sin(_phase + off) * amp * 0.6
			leg.rotation.z = maxf(0.0, cos(_phase + off)) * amp * 0.3 * (1.0 if n.ends_with("L") else -1.0)
			continue
		if fast:
			off = 0.0 if n.contains("_F") else PI
		else:
			off = {"Leg_FL": 0.0, "Leg_BR": PI * 0.5, "Leg_FR": PI, "Leg_BL": PI * 1.5}.get(n, 0.0)
		leg.rotation.x = sin(_phase + off) * amp
	_hop = maxf(_hop - delta, 0.0)
	_model.position.y = (absf(sin(_phase)) * 0.12 * height if fast else 0.0) + sin(_hop / 0.35 * PI) * 0.4 * float(_hop > 0.0)
	var angry := _state == ANGRY
	if _head:
		_head.rotation.x = lerpf(_head.rotation.x, -0.5 if _state == GRAZE else (0.3 if angry else 0.0), 1.0 - exp(-3.0 * delta))
	if _jaw:
		_jaw.rotation.x = lerpf(_jaw.rotation.x, 0.5 if angry and fmod(_phase, 2.0) < 1.0 else 0.0, 1.0 - exp(-10.0 * delta))
	if _tail:
		_tail.rotation.y = sin(_phase * 0.5) * 0.25
	if _trunk:
		_trunk.rotation.x = sin(_phase * 0.4) * 0.25 + (-0.8 if angry else 0.0)
	for e in _ears:
		e.rotation.y = sin(_phase * 0.7) * 0.25 * (1.0 if e.name == "Ear_L" else -1.0) + (0.4 if angry else 0.0) * (1.0 if e.name == "Ear_L" else -1.0)
