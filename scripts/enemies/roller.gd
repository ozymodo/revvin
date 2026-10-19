extends "res://scripts/enemies/enemy.gd"
## Roller: a living spherical tyre. Rolls itself along by torque (so it
## really rolls, bounces and ricochets), wanders when the car is far off and
## hunts it when close, trying to bump into it or roll right over it.
## It smashes into the world as it goes: props get knocked flying, and
## hard hits on walls and kerbs leave scorch marks and throw debris.

const HUNT_RANGE := 110.0
const ROLL_OVER_DPS := 0.8          # share of contact damage per second while on top of the car

var _speed := 20.0
var _wander := Vector3.ZERO
var _wander_t := 0.0
var _on_top_t := 0.0
var _stuck_t := 0.0
var _detour := Vector3.ZERO
var _detour_t := 0.0


func _build() -> void:
	kind = "roller"
	mass = 220.0 * size * size * size
	radius = 1.0 * size
	angular_damp = 0.05
	linear_damp = 0.05
	var pm := PhysicsMaterial.new()
	pm.friction = 1.0
	pm.bounce = 0.35
	physics_material_override = pm
	var cs := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = 1.0 * size
	cs.shape = sh
	add_child(cs)
	visual = Models.roller()
	add_child(visual)
	_speed = randf_range(17.0, 26.0) / pow(size, 0.3)


func _think(delta: float) -> void:
	var to := car.global_position - global_position
	to.y = 0.0
	var d := to.length()
	var dir: Vector3
	if d < HUNT_RANGE:
		# Aim a little ahead of the car.
		var lead := car.linear_velocity * clampf(d / maxf(_speed, 1.0), 0.0, 1.2)
		lead.y = 0.0
		dir = (to + lead).normalized()
	else:
		_wander_t -= delta
		if _wander_t <= 0.0 or _wander == Vector3.ZERO:
			_wander_t = randf_range(3.0, 6.0)
			var a := randf() * TAU
			_wander = Vector3(cos(a), 0, sin(a))
		dir = _wander
	# Stuck against a wall: swing off sideways for a moment, and hop if
	# that doesn't free it.
	var flat_speed := Vector2(linear_velocity.x, linear_velocity.z).length()
	_stuck_t = _stuck_t + delta if flat_speed < 2.5 else 0.0
	if _stuck_t > 1.2 and _detour_t <= 0.0:
		_detour_t = randf_range(1.5, 2.5)
		_detour = dir.rotated(Vector3.UP, PI * 0.5 * (1.0 if randf() < 0.5 else -1.0))
		if _stuck_t > 3.0:
			apply_central_impulse(Vector3.UP * mass * 6.0 - dir * mass * 3.0)
	if _detour_t > 0.0:
		_detour_t -= delta
		dir = (_detour * 0.8 + dir * 0.2).normalized()
	# Spin up toward the rolling speed for that direction, with a little
	# push so it can climb kerbs and ramps.
	var w_des := Vector3.UP.cross(dir) * (_speed / radius)
	var w_err := w_des - angular_velocity
	var inertia_k := 0.4 * mass * radius * radius
	apply_torque((w_err * inertia_k * 4.0).limit_length(mass * radius * 30.0))
	var flat_v := Vector3(linear_velocity.x, 0, linear_velocity.z)
	if flat_v.length() < _speed:
		apply_central_force(dir * mass * 4.0)

	# Rolling over the car: grinding damage while on top of it.
	if get_colliding_bodies().has(car) and global_position.y > car.global_position.y + 0.5:
		_on_top_t += delta
		if _on_top_t > 0.25:
			_on_top_t = 0.0
			combat.damage_player(contact_damage * ROLL_OVER_DPS * 0.25, global_position, "roller")
	else:
		_on_top_t = 0.0


## Hitting walls, kerbs and ramps hard: scorch mark and debris.
## Only real impacts count (it lost a lot of its horizontal speed), not
## every bounce on the road.
func _bump_world() -> void:
	var before := Vector2(_prev_v.x, _prev_v.z)
	var after := Vector2(linear_velocity.x, linear_velocity.z)
	if before.length() > 8.0 and before.length() - after.length() > 5.0:
		var dir := Vector3(before.x, 0, before.y).normalized()
		combat.env_hit(global_position + dir * radius, _prev_v, size)
