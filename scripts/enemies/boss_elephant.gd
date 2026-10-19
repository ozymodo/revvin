extends "res://scripts/enemies/boss.gd"
## MAMMOTH: the elephant, a six-wheeled tank. Slow, enormous, the toughest.
##   trample  a straight-line charge that flattens everything in its path
##   cannon   the trunk swings up and fires plasma shells
##   quake    rears up and stamps: a huge shockwave
##   toss     catches the car on its tusks and throws it

var _trunk: Node3D
var _ears: Array[Node3D] = []
var _charge_dir := Vector3.ZERO


func _build() -> void:
	kind = "elephant"
	boss_name = "MAMMOTH"
	title = "Elephant Prime"
	setup_body(Vector3(6.2, 6.5, 9.5), 3.25, 14000.0)
	top_speed = 13.0
	turn_rate = 1.0
	front = 5.5
	sweep_r = 5.0
	sweep_power = 8.0
	_trunk = visual.find_child("Trunk", true, false)
	for n in ["Ear_L", "Ear_R"]:
		_ears.append(visual.find_child(n, true, false))


func _choose_attack(d: float) -> String:
	var ahead := (car.global_position - global_position).normalized().dot(-global_basis.z) > 0.6
	if d < 10.0 and ahead:
		return "toss"
	if d > 22.0 and d < 90.0 and randf() < 0.4:
		return "trample"
	if d < 45.0 and randf() < 0.45:
		return "quake"
	return "cannon" if d < 110.0 else ""


func _run_attack(name: String, t: float, _delta: float, _d: float) -> bool:
	match name:
		"trample":
			if t < 0.9:
				_want_speed = 0.0
				face(car.global_position - global_position)
				if once("trumpet", t, 0.1):
					combat.sfx.roar(global_position, 0.6)
				_charge_dir = (predict(1.0) - global_position)
				_charge_dir.y = 0.0
				_charge_dir = _charge_dir.normalized()
				return false
			face(_charge_dir)
			_want_speed = 28.0
			accel = 16.0
			if fmod(t, 0.1) < get_physics_process_delta_time():
				combat.wrecking.explode(nose() + Vector3.UP * 2.5, 7.0, 9.5)
			if not _did.has("hit") and car.global_position.distance_to(nose() + Vector3.UP) < 7.0:
				_did["hit"] = true
				melee(nose(), 8.0, 45.0, _charge_dir * 18.0 + Vector3.UP * 8.0)
			var past := (car.global_position - global_position).dot(_charge_dir) < -25.0
			if t > 4.8 or past:
				accel = 9.0
				return true
			return false
		"cannon":
			_want_speed = 0.0
			face(car.global_position - global_position)
			for k in 3:
				if once("shot%d" % k, t, 0.8 + k * 0.4):
					var muzzle := visual.find_child("Muzzle", true, false) as Node3D
					var from: Vector3 = muzzle.global_position if muzzle else nose() + Vector3.UP * 4.0
					var target := predict(from.distance_to(car.global_position) / 55.0)
					shoot(from, (target - from).normalized() * 55.0 + Vector3.UP * 4.0, 6.0, 0.8, accent, _shell_hit)
					combat.sfx.rocket_launch()
			return t > 2.2
		"quake":
			_want_speed = 0.0
			if once("stomp", t, 1.0):
				shockwave(global_position - global_basis.z * 3.0, 26.0, 42.0, 13.0)
				combat.wrecking.explode(global_position, 14.0, 10.0)
			return t > 1.8
		"toss":
			_want_speed = 3.0
			if once("toss", t, 0.4):
				if melee(nose() + Vector3.UP * 0.5, 9.0, 30.0, -global_basis.z * 6.0 + Vector3.UP * 16.0):
					combat.sfx.thunk(1.0)
			return t > 1.0
	return true


func _shell_hit(at: Vector3) -> void:
	shockwave(at, 7.0, 24.0, 9.0)


func _animate_extra(delta: float) -> void:
	# Rearing up for the quake: the whole body tips back, then slams down.
	var rear := 0.0
	if _attack == "quake":
		rear = clampf(_attack_t / 0.9, 0.0, 1.0) * 0.32 if _attack_t < 1.0 else 0.0
	visual.rotation.x = lerpf(visual.rotation.x, rear, 1.0 - exp(-(25.0 if rear == 0.0 else 4.0) * delta))
	if _trunk:
		var want := sin(_t * 1.3) * 0.25
		if _attack == "cannon":
			want = -1.3
		elif _attack == "toss":
			want = -0.6
		_trunk.rotation.x = lerpf(_trunk.rotation.x, want, 1.0 - exp(-5.0 * delta))
	for i in _ears.size():
		if _ears[i]:
			var sgn := -1.0 if i == 0 else 1.0
			var flare := 0.6 if _attack == "trample" or _attack == "quake" else 0.0
			_ears[i].rotation.y = sgn * (sin(_t * 1.5) * 0.12 + flare)
