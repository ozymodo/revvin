extends "res://scripts/enemies/enemy.gd"
## Hopper: a mechanical frog. Sits, crouches, then leaps on a ballistic arc
## aimed to come down on the car (leading it). Stronger (bigger) frogs jump
## higher. Landing on the car is a stomp; it bounces off and goes again.
##
## Its back legs do the jumping: lose one and it leaps low and short,
## slewing off toward the lame side and tumbling round in the air; lose
## both and it drags itself along on its front legs in little lunges. A
## front leg gone and it lands badly (nose down, slow to go again); an eye
## gone and its aim wanders.

const HUNT_RANGE := 140.0          # covers the whole spawn ring
const MAX_HOP_SPEED := 38.0

var _jump_cd := 1.0
var _crouch := 0.0                  # 0..1 wind-up before a jump
var _air := false
var _apex := 4.0
var _thighs: Array[Node3D] = []
var _throat: Node3D
var _yaw := 0.0
var _lame := 0.0                    # -1..1: the back leg missing (left -, right +)
var _tumble := 0.0                  # extra spin in the air off a lopsided kick


func _build() -> void:
	kind = "hopper"
	mass = 140.0 * size * size * size
	radius = 0.8 * size
	axis_lock_angular_x = true
	axis_lock_angular_z = true
	axis_lock_angular_y = true
	var pm := PhysicsMaterial.new()
	pm.friction = 0.9
	pm.bounce = 0.1
	physics_material_override = pm
	var cs := CollisionShape3D.new()
	var sh := CapsuleShape3D.new()
	sh.radius = 0.45 * size
	sh.height = 1.3 * size
	cs.shape = sh
	cs.rotation = Vector3(PI * 0.5, 0, 0)
	cs.position = Vector3(0, 0.45 * size, 0)
	add_child(cs)
	visual = Models.hopper()
	add_child(visual)
	for n in ["Thigh_L", "Thigh_R"]:
		_thighs.append(visual.get_node(n))
	_throat = visual.get_node("Throat")
	for n in _thighs:
		add_part(n, "leg", 0.28)
	for n in ["Arm_L", "Arm_R"]:
		add_part(visual.get_node(n), "arm", 0.15)
	for n in ["Eye_L", "Eye_R"]:
		add_part(visual.get_node(n), "eye", 0.1)
	add_part(visual.get_node("HeadPlate"), "plate", 0.15)
	# Stronger frogs jump higher: 3.5 m for the smallest, ~11 m for big ones.
	_apex = 3.5 + 6.0 * clampf(size - 0.7, 0.0, 1.3)
	_jump_cd = randf_range(0.5, 2.0)


func _part_lost(tag: String, node: Node3D) -> void:
	if tag == "leg":
		_thighs.erase(node)
		_lame = 0.0 if _thighs.size() != 1 else (1.0 if _thighs[0].name == "Thigh_L" else -1.0)


func _think(delta: float) -> void:
	var grounded := not ground_below(global_position + Vector3.UP * 0.3, 0.55).is_empty() and linear_velocity.y < 1.0
	var to := car.global_position - global_position
	var flat := Vector3(to.x, 0, to.z)
	if grounded:
		if _air:
			_air = false
			_tumble = 0.0
			_jump_cd = randf_range(0.5, 1.2) + 0.45 * lost("arm")
		# Sit still (friction) and wind up.
		linear_velocity.x *= 0.8
		linear_velocity.z *= 0.8
		_jump_cd -= delta
		if flat.length() > 0.5:
			_yaw = lerp_angle(_yaw, atan2(-flat.x, -flat.z), 1.0 - exp(-6.0 * delta))
		if _jump_cd < 0.35:
			_crouch = minf(1.0, _crouch + delta * 4.0)
		if _jump_cd <= 0.0:
			_jump(to)
	else:
		_air = true
		_crouch = maxf(0.0, _crouch - delta * 6.0)
	# Legs: folded when sitting, kicked out on take-off, trailing in the air.
	var leg := -0.9 - _crouch * 0.5
	if _air:
		leg = 0.5 if linear_velocity.y > 0.0 else -0.3
	for th in _thighs:
		th.rotation.x = lerpf(th.rotation.x, leg, 1.0 - exp(-14.0 * delta))
		(th.get_node("Shin") as Node3D).rotation.x = -leg * 1.2
	_throat.scale = Vector3.ONE * (1.0 + 0.25 * sin(_t * 7.0) + _crouch * 0.3)
	var lean := clampf(linear_velocity.y * 0.04, -0.4, 0.4) if _air else -_crouch * 0.15
	# Lame: sits slumped toward the missing leg, nose down without front legs.
	if not _air:
		lean -= 0.18 * lost("arm") + (0.15 if _thighs.is_empty() else 0.0)
	else:
		_yaw += _tumble * delta
	var roll := -_lame * 0.3
	visual.basis = Basis.from_euler(Vector3(lean, _yaw, roll)).scaled(Vector3.ONE * visual.scale.x)


## Leap to land on the car (leading it), or a wander hop when it's far off.
func _jump(to: Vector3) -> void:
	_jump_cd = 99.0
	_crouch = 0.0
	var g := 9.8 * gravity_scale
	var legs := _thighs.size()
	var apex: float = _apex * [0.12, 0.5, 1.0][legs]
	var reach: float = MAX_HOP_SPEED * [0.25, 0.6, 1.0][legs]
	var target := car.global_position + Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)) * 4.0 * lost("eye")
	if to.length() > HUNT_RANGE:
		var a := randf() * TAU
		target = global_position + Vector3(cos(a), 0, sin(a)) * randf_range(4.0, 10.0)
		apex = _apex * 0.5
	var vy := sqrt(2.0 * g * apex)
	var dy := target.y - global_position.y
	var t_flight := vy / g + sqrt(maxf(2.0 * (apex - dy) / g, 0.0))
	# Lead the car by where it'll be on landing.
	if to.length() <= HUNT_RANGE:
		target += car.linear_velocity * t_flight
	var flat := Vector3(target.x - global_position.x, 0, target.z - global_position.z)
	var vh := (flat / maxf(t_flight, 0.1)).limit_length(reach)
	# One leg: the kick is lopsided, it slews off toward the lame side and
	# spins round in the air.
	if legs == 1:
		vh += vh.cross(Vector3.UP).normalized() * _lame * vh.length() * 0.35
		_tumble = _lame * randf_range(3.0, 6.0)
	linear_velocity = vh + Vector3.UP * vy
	combat.sfx_hop(global_position, size)


## A stomp: coming down onto the car.
func _attack_speed(dir_to_me: Vector3) -> float:
	var falling := -_prev_v.y
	if dir_to_me.y > 0.2 and falling > 2.0:
		return falling
	return _prev_v.dot(-dir_to_me) - 10.0


func _car_contact() -> void:
	super()
	# Bounce off the roof and get ready to go again.
	if global_position.y > car.global_position.y + 0.4:
		linear_velocity = Vector3(randf_range(-4, 4), 7.0, randf_range(-4, 4))
		_jump_cd = 0.6
