extends "res://scripts/enemies/boss.gd"
## WIDOWMAKER: the spider. Eight legs, each ending in a spinning wheel.
##   web     spits a web that snares the car (it crawls for a few seconds)
##   pounce  leaps high and lands on the car
##   acid    lobs venom that leaves burning pools on the road
##   brood   calls up spiders out of the ground to hunt the car
## Its legs come off one by one: it slows and lists toward the gaps, and
## with half of them gone it can't pounce. Without its fangs, no acid.

var _legs: Array[Node3D] = []


func _build() -> void:
	kind = "spider"
	boss_name = "WIDOWMAKER"
	title = "Spider Prime"
	setup_body(Vector3(7.0, 4.5, 8.0), 2.25, 6000.0)
	top_speed = 21.0
	turn_rate = 2.2
	front = 4.0
	sweep_r = 4.5
	for n in visual.find_children("Leg_*", "", true, false):
		_legs.append(n as Node3D)
		add_drive(n, "leg", 0.07)
	add_parts("Band_", "plate", 0.03)
	add_parts("Fang_", "fang", 0.05)


func _part_lost(tag: String, node: Node3D) -> void:
	super(tag, node)
	_legs.erase(node)


func _choose_attack(d: float) -> String:
	var r := randf()
	if wildlife and wildlife.brood_count() < 3 and r < 0.2:
		return "brood"
	if d > 25.0 and r < 0.5:
		return "web"
	if d < 55.0 and r < 0.75 and lost("leg") < 4:
		return "pounce"
	if d < 70.0 and lost("fang") < 2:
		return "acid"
	return "web" if d < 100.0 else ""


func _run_attack(name: String, t: float, delta: float, _d: float) -> bool:
	match name:
		"web":
			_want_speed = 0.0
			face(car.global_position - global_position)
			if once("spit", t, 0.5):
				var from := nose() + Vector3.UP * 2.0
				var target := predict(from.distance_to(car.global_position) / 70.0) + Vector3.UP * 0.5
				shoot(from, (target - from).normalized() * 70.0, 4.0, 0.7, Color(0.9, 0.85, 1.0), _web_hit)
				combat.sfx.goo_spit(from)
			return t > 0.9
		"pounce":
			if once("jump", t, 0.0):
				leap(predict(1.4), 1.4)
				linear_velocity.y += 4.0
				combat.sfx.hop(global_position, 3.0)
			if t > 0.2 and landed(delta):
				shockwave(global_position, 13.0, 35.0, 12.0)
				return true
			return t > 3.5
		"acid":
			_want_speed = 0.0
			face(car.global_position - global_position)
			for k in 3:
				if once("glob%d" % k, t, 0.4 + k * 0.2):
					var from := nose() + Vector3.UP * 1.5
					var target := predict(1.0) + Vector3(randf_range(-6, 6), 0, randf_range(-6, 6))
					lob(from, target, 1.0, 0.5, Color(0.45, 1.0, 0.25), _acid_hit)
					combat.sfx.goo_spit(from)
			return t > 1.2
		"brood":
			_want_speed = 0.0
			if once("call", t, 0.3):
				combat.sfx.roar(global_position, 2.0)
				if wildlife:
					for k in 4:
						var a := k * TAU / 4.0 + randf()
						wildlife.spawn_brood("spider", global_position + Vector3(cos(a), 0, sin(a)) * 7.0)
			return t > 1.0
	return true


func _web_hit(at: Vector3) -> void:
	fx.ring(at, Color(0.9, 0.85, 1.0), 6.0, 0.4, Vector3.UP)
	if car.global_position.distance_to(at) < 4.0:
		combat.damage_player(12.0, at, kind)
		combat.snare_car(3.0)


func _acid_hit(at: Vector3) -> void:
	fx.goo_splat(at, Vector3.UP)
	hazard(Vector3(at.x, at.y, at.z), 4.0, 16.0, 5.0, Color(0.4, 1.0, 0.2))
	if car.global_position.distance_to(at) < 3.0:
		combat.damage_player(10.0, at, kind)


func _animate_extra(delta: float) -> void:
	var spd := Vector2(linear_velocity.x, linear_velocity.z).length()
	for i in _legs.size():
		var leg := _legs[i]
		var n := String(leg.name)
		var off := PI * float((i + (1 if n.ends_with("R") else 0)) % 2)
		var amp := clampf(spd / 12.0, 0.1, 0.4)
		leg.rotation.y = sin(_t * (3.0 + spd * 0.4) + off) * amp
		leg.rotation.z = lerpf(leg.rotation.z, (0.35 if not _grounded else 0.0) * (1.0 if n.ends_with("L") else -1.0), 1.0 - exp(-6.0 * delta))
	if _jaw:
		_jaw.rotation.x = lerpf(_jaw.rotation.x, 0.4 if _attack == "web" or _attack == "acid" else sin(_t * 3.0) * 0.08, 1.0 - exp(-8.0 * delta))
