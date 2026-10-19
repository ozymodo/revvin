extends Node3D
## A deer that grazes, wanders near its herd's home, and bolts from the car.
## Purely visual (no physics); legs and head are animated procedurally.

const MODEL := preload("res://assets/world/deer.glb")

enum { GRAZE, WALK, FLEE }

var city: Node                      # city.gd, for keeping out of buildings
var home := Vector3.ZERO
## Run-over rules (world/wildlife.gd): biofuel when hit fast enough.
var kind := "deer"
var radius := 0.7
var height := 1.6
var dead := false
var respawn_t := 0.0

var _state := GRAZE
var _timer := 0.0
var _target := Vector3.ZERO
var _dir := Vector3.FORWARD
var _speed := 0.0
var _phase := 0.0
var _hop := 0.0
var _head_pitch := 0.0
var _model: Node3D
var _legs := {}
var _head: Node3D
var _car: RigidBody3D
var _face := Vector3.FORWARD
var _size := 1.0


func _ready() -> void:
	_model = MODEL.instantiate()
	add_child(_model)
	for n in ["Leg_FL", "Leg_FR", "Leg_BL", "Leg_BR"]:
		_legs[n] = _model.find_child(n, true, false)
	_head = _model.find_child("Head", true, false)
	_timer = randf_range(1.0, 6.0)
	_dir = Vector3.FORWARD.rotated(Vector3.UP, randf() * TAU)
	_size = randf_range(0.9, 1.15)
	_face = _dir
	basis = Basis.looking_at(_face, Vector3.UP).scaled(Vector3.ONE * _size)
	add_to_group("critters")


func _process(delta: float) -> void:
	if dead:
		return
	if _car == null:
		_car = get_tree().get_first_node_in_group("player_car")
		if _car == null:
			return
	var away := global_position - _car.global_position
	away.y = 0.0
	var dist := away.length()
	var car_speed := _car.linear_velocity.length()
	if dist < 9.0 or (dist < 32.0 and car_speed > 3.0):
		if _state != FLEE:
			_hop = 0.5                  # startle jump
		_state = FLEE
		_timer = randf_range(3.0, 5.0)
		_dir = _dir.lerp(away.normalized(), 0.15).normalized()

	var want_speed := 0.0
	match _state:
		GRAZE:
			_timer -= delta
			if _timer <= 0.0:
				_state = WALK
				_target = home + Vector3(randf_range(-22, 22), 0, randf_range(-22, 22))
		WALK:
			want_speed = 1.5
			var to := _target - global_position
			to.y = 0.0
			if to.length() < 1.5:
				_state = GRAZE
				_timer = randf_range(3.0, 9.0)
			else:
				_dir = _dir.lerp(to.normalized(), 2.0 * delta).normalized()
		FLEE:
			want_speed = 13.0
			_timer -= delta
			if _timer <= 0.0 and dist > 40.0:
				_state = WALK
				_target = home + Vector3(randf_range(-15, 15), 0, randf_range(-15, 15))

	# Steer around buildings and stay inside the walls.
	var ahead := global_position + _dir * 4.0
	if city and (city.in_building(ahead.x, ahead.z, 1.0) or absf(ahead.x) > 390.0 or absf(ahead.z) > 390.0):
		_dir = _dir.rotated(Vector3.UP, PI * 0.5 * (1.0 if randf() < 0.5 else -1.0))

	_speed = lerpf(_speed, want_speed, 1.0 - exp(-3.0 * delta))
	global_position += _dir * _speed * delta
	global_position.y = 0.0
	if _speed > 0.2:
		_face = _face.lerp(_dir, 1.0 - exp(-6.0 * delta)).normalized()
		basis = Basis.looking_at(_face, Vector3.UP).scaled(Vector3.ONE * _size)

	# Legs: walk is a 4-beat gait, flight is a bounding gallop.
	var galloping := _speed > 6.0
	_phase += delta * (2.0 + _speed * 0.9)
	var amp := clampf(_speed / 2.0, 0.0, 1.0) * (0.75 if galloping else 0.4)
	for n in _legs:
		var off := 0.0
		if galloping:
			off = 0.0 if n.ends_with("FL") or n.ends_with("FR") else PI
		else:
			off = {"Leg_FL": 0.0, "Leg_BR": PI * 0.5, "Leg_FR": PI, "Leg_BL": PI * 1.5}[n]
		(_legs[n] as Node3D).rotation.x = sin(_phase + off) * amp
	_hop = maxf(_hop - delta, 0.0)
	_model.position.y = (absf(sin(_phase)) * 0.35 if galloping else 0.0) + sin(_hop * PI * 2.0) * 0.6 * float(_hop > 0.0)
	_head_pitch = lerpf(_head_pitch, -0.9 if _state == GRAZE else (0.25 if _state == FLEE else 0.0), 1.0 - exp(-3.0 * delta))
	if _head:
		_head.rotation.x = _head_pitch
