extends "res://scripts/enemies/boss.gd"
## SILVERBACK: the gorilla. A monster-truck torso with huge piston arms.
##   swipe   close in: a backhand that sends the car flying sideways
##   slam    leaps at the car and pounds the ground on landing (shockwave)
##   throw   rips out a chunk of the city and hurls it
##   rage    beats its chest and roars: faster and angrier for a while

var _arms: Array[Node3D] = []
var _rage := 0.0


func _build() -> void:
	kind = "gorilla"
	boss_name = "SILVERBACK"
	title = "Gorilla Prime"
	setup_body(Vector3(5.6, 5.0, 6.0), 2.5, 9000.0)
	top_speed = 17.0
	turn_rate = 1.6
	front = 3.6
	sweep_r = 4.0
	for n in ["Arm_L", "Arm_R"]:
		_arms.append(visual.get_node(n))


func _choose_attack(d: float) -> String:
	if _rage <= 0.0 and randf() < 0.18:
		return "rage"
	if d < 11.0:
		return "swipe"
	if d < 50.0 and randf() < 0.55:
		return "slam"
	if d < 95.0:
		return "throw" if randf() < 0.6 else "slam"
	return ""


func _think(delta: float) -> void:
	_rage -= delta
	_speed_mult = 1.45 if _rage > 0.0 else 1.0
	super(delta)


func _run_attack(name: String, t: float, delta: float, d: float) -> bool:
	match name:
		"swipe":
			_want_speed = 4.0
			face(car.global_position - global_position)
			if once("hit", t, 0.45):
				var side := global_basis.x * (1.0 if randf() < 0.5 else -1.0)
				if melee(nose() + Vector3.UP * 1.0, 7.5, 30.0, side * 12.0 + Vector3.UP * 7.0 - global_basis.z * 6.0):
					combat.sfx.thunk(1.0)
				combat.wrecking.explode(nose() + Vector3.UP * 1.5, 5.0, 8.0)
			return t > 1.0
		"slam":
			if once("jump", t, 0.0):
				leap(predict(1.1), 1.1)
				combat.sfx.hop(global_position, 3.0)
			if t > 0.2 and landed(delta):
				shockwave(global_position, 18.0, 38.0, 15.0)
				return true
			return t > 3.0
		"throw":
			_want_speed = 0.0
			face(car.global_position - global_position)
			if once("rip", t, 0.15):
				combat.wrecking.explode(nose() + Vector3.UP * 0.5, 4.0, 9.0)
			if once("throw", t, 0.75):
				var from := global_position + Vector3.UP * 7.5
				var target := predict(1.4)
				lob(from, target, 1.4, 1.6, Color(0.5, 0.45, 0.4), _boulder_hit)
			return t > 1.3
		"rage":
			_want_speed = 0.0
			if once("roar", t, 0.2):
				combat.sfx.roar(global_position, 0.8)
				fx.ring(global_position + Vector3.UP * 4.0, accent, 20.0, 0.6, Vector3.UP)
				if wildlife:
					wildlife.hud_toast("%s IS ENRAGED" % boss_name, accent)
			if t > 1.6:
				_rage = 8.0
				return true
			return false
	return true


func _boulder_hit(at: Vector3) -> void:
	combat.wrecking.debris.burst(at, 12, 0.9, Color(0.45, 0.43, 0.4), Vector3.UP * 4.0, 10.0, Vector3.ONE)
	shockwave(at, 8.0, 30.0, 10.0)


func _animate_extra(delta: float) -> void:
	var spd := Vector2(linear_velocity.x, linear_velocity.z).length()
	for i in _arms.size():
		var arm := _arms[i]
		var sgn := 1.0 if i == 0 else -1.0
		var want := sin(_t * (2.0 + spd * 0.25) + i * PI) * clampf(spd / 10.0, 0.0, 0.5)
		match _attack:
			"swipe":
				want = -1.4 + clampf((_attack_t - 0.35) * 8.0, 0.0, 2.2) if i == 0 else 0.2
			"throw":
				want = -2.4 + clampf((_attack_t - 0.6) * 10.0, 0.0, 2.6)
			"rage":
				want = -1.0 + sin(_t * 18.0 + i * PI) * 0.5
			"slam":
				want = -2.0 if not _grounded else 0.5
		arm.rotation.x = lerpf(arm.rotation.x, want, 1.0 - exp(-10.0 * delta))
		arm.rotation.z = lerpf(arm.rotation.z, sgn * (0.5 if _attack == "slam" and not _grounded else 0.0), 1.0 - exp(-6.0 * delta))
	if _jaw:
		_jaw.rotation.x = lerpf(_jaw.rotation.x, 0.6 if _attack == "rage" else 0.0, 1.0 - exp(-8.0 * delta))
