extends "res://scripts/enemies/enemy.gd"
## Floater: a scrap-metal bee. Hovers a few metres up, circling the car at
## range and spitting goo at it; when the car is close it dives straight at
## it, then climbs away to recover.
##
## Shot up, it flies worse: every wing lost costs lift, so it sags, slows
## and wobbles, banking toward the side that's missing wings. With no
## wings on one side it spirals; with one wing or none left it drops out
## of the sky and scuttles along the road after the car instead, still
## spitting goo and lunging at it. Without its stinger its dives hurt less.

enum State { HOVER, DIVE, RECOVER }

const ORBIT_R := 22.0
const SHOOT_RANGE := 55.0
const DIVE_RANGE := 16.0
const DIVE_SPEED := 30.0
const GOO_SPEED := 38.0

var _state := State.HOVER
var _state_t := 0.0
var _shoot_cd := 2.0
var _dive_cd := 3.0
var _orbit := 0.0
var _height := 8.0
var _wings: Array[Node3D] = []
var _face := Basis.IDENTITY
var _lift := 1.0                    # what's left of the wings (1: all four)
var _list := 0.0                    # -1..1: fewer wings on the left (-) or right (+); it dips that way
var _hop_cd := 0.0


func _build() -> void:
	kind = "bee"
	gravity_scale = 0.0
	linear_damp = 0.6
	axis_lock_angular_x = true
	axis_lock_angular_y = true
	axis_lock_angular_z = true
	mass = 60.0 * size * size * size
	radius = 0.7 * size
	var cs := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = 0.6 * size
	cs.shape = sh
	cs.position = Vector3(0, 0, 0.15 * size)
	add_child(cs)
	visual = Models.bee()
	add_child(visual)
	for n in visual.get_children():
		if n.name.begins_with("Wing_"):
			_wings.append(n)
	for n in visual.get_children():
		var nm := String(n.name)
		if nm.begins_with("Wing_"):
			add_part(n, "wing", 0.15)
		elif nm == "Stinger":
			add_part(n, "stinger", 0.25)
		elif nm.begins_with("Plate_"):
			add_part(n, "plate", 0.1)
		elif nm.begins_with("Leg_"):
			add_part(n, "leg", 0.08)
	_orbit = randf() * TAU
	_height = randf_range(6.0, 10.0)
	_shoot_cd = randf_range(1.5, 3.0)


func _part_lost(tag: String, node: Node3D) -> void:
	match tag:
		"wing":
			_wings.erase(node)
			var l := 0
			var r := 0
			for w in _wings:
				if w.name.begins_with("Wing_1"):
					r += 1
				else:
					l += 1
			_lift = (l + r) / 4.0
			_list = (l - r) / 2.0
			# Lopsided: no wings on one side at all is far worse.
			if l == 0 or r == 0:
				_lift *= 0.55
			if _lift < 0.3:
				gravity_scale = 1.0
				linear_damp = 0.3
				_state = State.HOVER
		"stinger":
			contact_damage *= 0.6


## Flying but hurt: sags under gravity it can't fully hold off, and wobbles.
func _limp(delta: float) -> void:
	if _lift >= 1.0:
		return
	var k := 1.0 - _lift
	apply_central_force((Vector3.DOWN * 9.8 * k * 0.6 + Vector3(sin(_t * 7.3), sin(_t * 11.0) * 0.6, cos(_t * 5.1)) * k * 9.0) * mass)
	# Pulled round toward the side with fewer wings.
	_orbit += delta * k * 1.2


## No wings left to speak of: down on the road, scuttling after the car.
func _crawl(delta: float) -> void:
	_hop_cd -= delta
	_shoot_cd -= delta
	var target := car.global_position + Vector3.UP * 0.5
	var to := target - global_position
	var flat := Vector3(to.x, 0, to.z)
	var grounded := not ground_below(global_position, radius + 0.3).is_empty()
	if grounded:
		steer(flat.normalized() * 9.0, 3.0, 18.0)
		# Lunge at the car when it's close, little skips otherwise.
		if _hop_cd <= 0.0:
			var lunge := flat.length() < 10.0
			_hop_cd = randf_range(0.6, 1.4) if not lunge else 2.0
			apply_central_impulse((flat.normalized() * (9.0 if lunge else 3.0) + Vector3.UP * (5.0 if lunge else 2.5)) * mass)
	if _shoot_cd <= 0.0 and to.length() < SHOOT_RANGE * 0.7 and can_see_car():
		_shoot_cd = randf_range(2.5, 4.0)
		combat.enemy_shoot(global_position + Vector3.UP * 0.3 * size, target + car.linear_velocity * (to.length() / GOO_SPEED), GOO_SPEED, 7.0 * size, self)
	if flat.length() > 0.1:
		var want := Basis.looking_at(flat.normalized(), Vector3.UP)
		_face = _face.slerp(want, 1.0 - exp(-8.0 * delta)).orthonormalized()
	visual.basis = _face.scaled(Vector3.ONE * visual.scale.x)
	var flap := sin(_t * TAU * 30.0) * 0.9
	for w in _wings:
		w.rotation.z = flap * (1.0 if w.name.begins_with("Wing_1") else -1.0)


func _think(delta: float) -> void:
	if _lift < 0.3:
		_crawl(delta)
		return
	_limp(delta)
	_state_t += delta
	_shoot_cd -= delta
	_dive_cd -= delta
	var target := car.global_position + Vector3.UP * 0.5
	var to := target - global_position
	var d := to.length()
	var face := to
	match _state:
		State.HOVER:
			_orbit += delta * 0.35
			var ground := target.y
			var spot := target + Vector3(cos(_orbit), 0, sin(_orbit)) * ORBIT_R
			spot.y = ground + _height * (0.4 + 0.6 * _lift) + sin(_t * 1.3) * 0.8
			steer((spot - global_position).limit_length(14.0 * (0.5 + 0.5 * _lift)), 2.0, 22.0)
			if _shoot_cd <= 0.0 and d < SHOOT_RANGE and can_see_car():
				_shoot_cd = randf_range(1.8, 3.2) / clampf(size, 0.8, 1.5)
				combat.enemy_shoot(global_position + (-visual.global_basis.z) * 0.6 * size, target + car.linear_velocity * (d / GOO_SPEED), GOO_SPEED, 7.0 * size, self)
			if d < DIVE_RANGE + 6.0 and _dive_cd <= 0.0:
				_state = State.DIVE
				_state_t = 0.0
		State.DIVE:
			# Lead the car a little and go straight for it.
			var aim := target + car.linear_velocity * clampf(d / DIVE_SPEED, 0.0, 0.6) - global_position
			steer(aim.normalized() * DIVE_SPEED * (0.6 + 0.4 * _lift), 4.0, 60.0)
			face = linear_velocity
			if _state_t > 1.6:
				_end_dive()
		State.RECOVER:
			steer(Vector3(0, 9.0, 0) - to.normalized() * 6.0, 2.0, 25.0)
			if _state_t > 1.5:
				_state = State.HOVER
				_state_t = 0.0
	# Face where it's heading (or the car), bank into turns, flap.
	if face.length() > 0.1 and absf(face.normalized().y) < 0.98:
		var want := Basis.looking_at(face.normalized(), Vector3.UP)
		_face = _face.slerp(want, 1.0 - exp(-6.0 * delta)).orthonormalized()
	var bank := Basis(Vector3.FORWARD, _list * 0.5 + sin(_t * 9.0) * 0.25 * (1.0 - _lift)) if _lift < 1.0 else Basis.IDENTITY
	visual.basis = (_face * bank).scaled(Vector3.ONE * visual.scale.x)
	var flap := sin(_t * TAU * 22.0) * 0.7
	for w in _wings:
		var side := 1.0 if w.name.begins_with("Wing_1") else -1.0
		w.rotation.z = flap * side


func _end_dive() -> void:
	_state = State.RECOVER
	_state_t = 0.0
	_dive_cd = randf_range(3.0, 5.0)


func _car_contact() -> void:
	super()
	if _state == State.DIVE:
		_end_dive()


## Only a dive (or flying into the car) hurts.
func _attack_speed(dir_to_me: Vector3) -> float:
	if _lift < 0.3:
		return _prev_v.dot(-dir_to_me) - 4.0
	return _prev_v.dot(-dir_to_me) - (6.0 if _state == State.DIVE else 14.0)
