extends "res://scripts/enemies/boss.gd"
## TYRANT: the T. rex. Two giant drive wheels, a tail with a trailing wheel.
## The fastest boss.
##   charge  crouches, then sprints at the car jaws open: a bite throws it
##   tail    spins on the spot: the tail sweeps everything round it away
##   roar    charges its plasma throat and roars a beam down a cone,
##           cutting through whatever's in the way
## It drives on two wheels, so losing one is crippling: it limps and drags
## round on the stump. Without its tail it can't spin-sweep, and pitches
## forward off balance.

var _tail: Node3D
var _charge_dir := Vector3.ZERO


func _build() -> void:
	kind = "rex"
	boss_name = "TYRANT"
	title = "Rex Prime"
	setup_body(Vector3(4.6, 6.0, 9.0), 3.0, 8000.0)
	top_speed = 23.0
	turn_rate = 1.5
	front = 5.5
	sweep_r = 3.5
	_tail = visual.get_node("Tail")
	for n in ["Wheel_L", "Wheel_R"]:
		add_drive(visual.get_node(n), "wheel", 0.15)
	add_part(_tail, "tail", 0.14)
	add_parts("Arm_", "arm", 0.03)
	add_parts("Dorsal_", "plate", 0.02)
	add_parts("SkullPlate", "plate", 0.05)
	add_part(_jaw, "jaw", 0.07)


func _part_lost(tag: String, node: Node3D) -> void:
	super(tag, node)
	if node == _tail:
		_tail = null
		_lean = -0.12


func _choose_attack(d: float) -> String:
	if d < 15.0 and randf() < 0.6 and _tail:
		return "tail"
	if d < 75.0 and randf() < 0.5:
		return "charge"
	if d < 55.0:
		return "roar"
	return "charge" if d < 110.0 else ""


func _run_attack(name: String, t: float, _delta: float, d: float) -> bool:
	match name:
		"charge":
			if t < 0.6:
				_want_speed = 0.0
				face(car.global_position - global_position)
				if once("snarl", t, 0.0):
					combat.sfx.roar(global_position, 1.3)
				return false
			# Sprint, steering a little after the car.
			var to := predict(0.3) - global_position
			face(to)
			_want_speed = 34.0
			turn_rate = 0.9
			var mouth := nose() + Vector3.UP * 1.0
			if not _did.has("bite") and car.global_position.distance_to(mouth) < 6.5:
				_did["bite"] = true
				melee(mouth, 7.0, 42.0, -global_basis.z * 10.0 + Vector3.UP * 9.0)
				combat.sfx.thunk(1.0)
			if t > 3.5 or _did.has("bite"):
				turn_rate = 1.5
				return true
			return false
		"tail":
			_want_speed = 0.0
			_spin = TAU / 0.9 if t < 0.9 else 0.0
			if once("sweep", t, 0.35):
				var at := global_position
				var dd := Vector2(car.global_position.x - at.x, car.global_position.z - at.z).length()
				if dd < 15.0:
					var away := (car.global_position - at)
					away.y = 0.0
					combat.damage_player(32.0, at, kind)
					combat.knock_car(away.normalized() * 16.0 + Vector3.UP * 6.0)
					combat.sfx.thunk(1.0)
			if once("ring", t, 0.5):
				for k in 6:
					var a := k * TAU / 6.0
					combat.wrecking.explode(global_position + Vector3(cos(a), 0.4, sin(a)) * 8.0, 4.0, 7.0)
				fx.ring(global_position + Vector3.UP, accent, 22.0, 0.4, Vector3.UP)
			return t > 1.1
		"roar":
			_want_speed = 0.0
			if t < 0.9:
				face(car.global_position - global_position)
				return false
			if once("roar", t, 0.9):
				combat.sfx.roar(global_position, 1.0)
				_charge_dir = (car.global_position + Vector3.UP * 0.5 - (nose() + Vector3.UP * 2.0)).normalized()
			# The beam: a cone out of the jaws, blasting the length of it.
			var mouth := nose() + Vector3.UP * 2.0 + Vector3.UP * 0.5
			if fmod(t, 0.1) < get_physics_process_delta_time():
				var reach := 46.0
				var spread := Vector3(randf_range(-1, 1), randf_range(-0.3, 0.3), randf_range(-1, 1)) * 0.12
				var dir := (_charge_dir + spread).normalized()
				var q := PhysicsRayQueryParameters3D.create(mouth, mouth + dir * reach, 1, [get_rid(), car.get_rid()])
				var hit := get_world_3d().direct_space_state.intersect_ray(q)
				var end: Vector3 = hit.position if not hit.is_empty() else mouth + dir * reach
				fx.tracer(mouth, end, accent, 0.5, 0.15)
				combat.wrecking.explode(end, 4.0, 8.0)
			if not _did.has("burned"):
				var to_car := car.global_position + Vector3.UP * 0.5 - mouth
				if to_car.length() < 48.0 and to_car.normalized().dot(_charge_dir) > 0.9 and can_see_car():
					_did["burned"] = true
					combat.damage_player(34.0, mouth, kind)
					combat.knock_car(_charge_dir * 12.0 + Vector3.UP * 3.0)
			return t > 1.8
	return true


func _animate_extra(delta: float) -> void:
	if _tail:
		_tail.rotation.y = sin(_t * 2.0) * 0.25 + (0.6 if _attack == "tail" else 0.0) * sin(_t * 9.0)
	var open := 0.0
	match _attack:
		"charge":
			open = 0.6
		"roar":
			open = 0.8 if _attack_t > 0.5 else _attack_t
	if _jaw:
		_jaw.rotation.x = lerpf(_jaw.rotation.x, open, 1.0 - exp(-10.0 * delta))
	if _head:
		_head.rotation.x = lerpf(_head.rotation.x, -0.3 if _attack == "charge" and _attack_t < 0.6 else 0.0, 1.0 - exp(-6.0 * delta))
