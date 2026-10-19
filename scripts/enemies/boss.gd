extends "res://scripts/enemies/enemy.gd"
## Base for the four beast bosses (gorilla, rex, spider, elephant), each a
## high-tech monster-truck version of its animal (enemies/beast_models.gd).
##
## A boss lives in its territory (wildlife.gd puts herds of its animal all
## round it, which is how you find it). It prowls until the car comes
## within AGGRO or hurts it, then hunts: it drives at the car and picks
## attacks from its own repertoire (the subclass's _choose_attack and
## _run_attack). It tears through the world as it goes: everything in front
## of it is smashed (world/wrecking.gd), and its attacks blow holes in
## buildings. Its hits are huge. Leave its territory far enough behind and
## it gives up and goes home.
##
## Helpers for the subclasses: drive(), face(), lob(), shoot(), shockwave(),
## melee(), hazard(), leap().

signal defeated(boss: Node)

const Beasts := preload("res://scripts/enemies/beast_models.gd")
const AGGRO := 100.0
const LEASH := 3.2                  # x territory radius: past this (and far off) it goes home
const GRAVITY := 20.0               # for its own projectiles

var boss_name := ""
var title := ""
var accent := Color.WHITE
var territory := Vector3.ZERO
var territory_r := 80.0
var engaged := false
var level := 1
var wildlife: Node                  # world/wildlife.gd (brood, rewards)

var top_speed := 16.0
var turn_rate := 1.4                # rad/s
var accel := 9.0                    # m/s²
var front := 5.0                    # nose distance from centre
var sweep_r := 3.5                  # what it smashes in front of it
var sweep_power := 6.0

var _yaw := 0.0
var _want_dir := Vector3.ZERO
var _want_speed := 0.0
var _speed_mult := 1.0
var _attack := ""
var _attack_t := 0.0
var _attack_cd := 3.0
var _did := {}                      # one-shot flags inside an attack
var _wheels: Array[Node3D] = []
var _wheel_r: Array[float] = []
var _core: Node3D
var _head: Node3D
var _jaw: Node3D
var _sweep_t := 0.0
var _stuck_t := 0.0
var _shots: Array = []              # {node, vel, grav, life, r, hit: Callable}
var _hazards: Array = []            # {node, at, r, dps, life, tick}
var _wander := Vector3.ZERO
var _wander_t := 0.0
var _hurt_t := 0.0
var _airborne_t := 0.0
var _leaping := false
var _grounded := true
var _shake := 0.0
var _spin := 0.0                    # rad/s: spinning on the spot (overrides steering)


## Subclass sets kind, numbers, shape. Call from _build().
func setup_body(shape_size: Vector3, shape_y: float, body_mass: float) -> void:
	boss = true
	mass = body_mass
	radius = maxf(shape_size.x, shape_size.z) * 0.5
	axis_lock_angular_x = true
	axis_lock_angular_z = true
	linear_damp = 0.2
	angular_damp = 4.0
	continuous_cd = false
	var pm := PhysicsMaterial.new()
	pm.friction = 0.25
	pm.bounce = 0.0
	physics_material_override = pm
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = shape_size
	cs.shape = bs
	cs.position.y = shape_y
	add_child(cs)
	visual = Beasts.mech(kind)
	add_child(visual)
	accent = Beasts.ACCENT[kind]
	for w in visual.find_children("Wheel_*", "", true, false):
		_wheels.append(w as Node3D)
		var tyre := (w as Node3D).get_child(0) as MeshInstance3D
		_wheel_r.append((tyre.mesh as CylinderMesh).top_radius if tyre and tyre.mesh is CylinderMesh else 1.0)
	_core = visual.find_child("Core", true, false)
	_head = visual.find_child("Head", true, false)
	_jaw = visual.find_child("Jaw", true, false)


var fx: Node


func _ready() -> void:
	fx = combat.fx
	super()
	_yaw = rotation.y
	_bar.scale = Vector3.ZERO          # the HUD shows a boss bar instead


## Override: name of the next attack for this distance, or "" to keep chasing.
func _choose_attack(_d: float) -> String:
	return ""


## Override: run attack `name` at time t into it; return true when it's over.
func _run_attack(_name: String, _t: float, _delta: float, _d: float) -> bool:
	return true


## Override: extra animation (arms, tail, legs...).
func _animate_extra(_delta: float) -> void:
	pass


func take_damage(amount: float, how: String) -> bool:
	_hurt_t = 6.0
	if not engaged:
		engage()
	return super(amount, how)


func engage() -> void:
	if engaged:
		return
	engaged = true
	_attack_cd = 1.5
	if wildlife:
		wildlife.boss_engaged(self)


func _think(delta: float) -> void:
	var to := car.global_position - global_position
	to.y = 0.0
	var d := to.length()
	_hurt_t -= delta
	_update_shots(delta)
	_update_hazards(delta)
	var g := ground_below(global_position + Vector3.UP * 1.0, 1.8)
	_grounded = not g.is_empty()
	if not engaged:
		if d < AGGRO and combat.wrecked <= 0.0:
			engage()
		elif d > 450.0:
			linear_velocity.x *= 0.9
			linear_velocity.z *= 0.9
			return
		_prowl(delta)
	else:
		var from_home := Vector2(car.global_position.x - territory.x, car.global_position.z - territory.z).length()
		if (from_home > territory_r * LEASH and d > 140.0) or combat.wrecked > 0.0 and d > 60.0:
			engaged = false
			_attack = ""
			hp = minf(max_hp, hp + (max_hp - hp) * 0.5)
			if wildlife:
				wildlife.boss_disengaged(self)
		elif _attack == "":
			_want_dir = to.normalized() if d > 0.1 else _want_dir
			_want_speed = top_speed * _speed_mult * (0.0 if d < front + 3.0 else 1.0)
			_attack_cd -= delta
			if _attack_cd <= 0.0:
				_attack = _choose_attack(d)
				_attack_t = 0.0
				_did = {}
				if _attack == "":
					_attack_cd = 0.5
		else:
			_attack_t += delta
			if _run_attack(_attack, _attack_t, delta, d):
				_attack = ""
				_leaping = false
				_spin = 0.0
				_attack_cd = randf_range(1.6, 3.0) / (1.0 + 0.15 * (level - 1))
	_drive(delta)
	_smash(delta)


func _prowl(delta: float) -> void:
	_wander_t -= delta
	if _wander_t <= 0.0 or global_position.distance_to(_wander) < 6.0:
		_wander_t = randf_range(6.0, 12.0)
		var a := randf() * TAU
		_wander = territory + Vector3(cos(a), 0, sin(a)) * randf_range(0.0, territory_r * 0.6)
	var to := _wander - global_position
	to.y = 0.0
	_want_dir = to.normalized() if to.length() > 0.1 else _want_dir
	_want_speed = 4.5


## Turn toward _want_dir (vehicle-like), drive forward at _want_speed.
func _drive(delta: float) -> void:
	if _leaping:
		return
	if _spin != 0.0:
		angular_velocity.y = _spin
	elif _want_dir.length() > 0.1:
		var target := atan2(-_want_dir.x, -_want_dir.z)
		var diff := wrapf(target - rotation.y, -PI, PI)
		angular_velocity.y = clampf(diff * 3.0, -turn_rate, turn_rate)
	else:
		angular_velocity.y = 0.0
	if not _grounded:
		return
	var fwd := -global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	# Mostly along its nose (it drives, it doesn't strafe).
	var lined := clampf(fwd.dot(_want_dir), 0.0, 1.0) if _want_dir.length() > 0.1 else 0.0
	var v_des := fwd * _want_speed * (0.35 + 0.65 * lined)
	var flat := Vector3(linear_velocity.x, 0, linear_velocity.z)
	var dv := (v_des - flat).limit_length(accel * delta)
	linear_velocity += dv


## Smashing through: everything just in front of it breaks. Stuck against
## something it can't break: rip into it harder, then hop.
func _smash(delta: float) -> void:
	var flat := Vector3(linear_velocity.x, 0, linear_velocity.z)
	var spd := flat.length()
	_sweep_t -= delta
	if _sweep_t <= 0.0 and (engaged or spd > 6.0):
		_sweep_t = 0.15
		var fwd := -global_basis.z
		combat.wrecking.explode(global_position + fwd * front + Vector3.UP * 2.0, sweep_r, sweep_power)
	if engaged and _want_speed > 3.0 and spd < 1.5 and _grounded and not _leaping:
		_stuck_t += delta
		if _stuck_t > 0.8 and fmod(_stuck_t, 0.6) < delta:
			var fwd2 := -global_basis.z
			combat.wrecking.explode(global_position + fwd2 * (front + 1.5) + Vector3.UP * 2.5, sweep_r * 2.0, 10.0)
			fx.punch(0.15)
		if _stuck_t > 3.0:
			_stuck_t = 0.0
			apply_central_impulse((Vector3.UP * 9.0 - global_basis.z * 4.0) * mass)
	else:
		_stuck_t = 0.0


func _process(delta: float) -> void:
	super(delta)
	if dead:
		return
	var flat := Vector3(linear_velocity.x, 0, linear_velocity.z)
	var fwd_speed := flat.dot(-global_basis.z)
	for i in _wheels.size():
		_wheels[i].rotation.x -= fwd_speed / _wheel_r[i] * delta
	if _core:
		var pulse := 1.0 + 0.12 * sin(_t * 5.0) + (0.5 * minf(_attack_t, 1.0) if _attack != "" and _attack_t < 1.2 else 0.0)
		_core.scale = _core.scale.lerp(Vector3.ONE * pulse, 1.0 - exp(-8.0 * delta))
	_animate_extra(delta)


# ------------------------------------------------------------------ helpers

## Where the car will be in `t` seconds (roughly).
func predict(t: float) -> Vector3:
	var p := car.global_position + car.linear_velocity * t
	p.y = car.global_position.y
	return p


func face(dir: Vector3) -> void:
	dir.y = 0.0
	if dir.length() > 0.1:
		_want_dir = dir.normalized()


func nose() -> Vector3:
	return global_position - global_basis.z * front


## Jumps on a ballistic arc to land on `to` after `t` seconds.
func leap(to: Vector3, t: float) -> void:
	var from := global_position
	var v := (to - from) / t + Vector3.UP * 0.5 * 9.8 * gravity_scale * t
	linear_velocity = v
	_leaping = true
	_airborne_t = 0.0


## True once a leap has landed.
func landed(delta: float) -> bool:
	_airborne_t += delta
	return _airborne_t > 0.35 and _grounded and linear_velocity.y < 1.0


## A blast at `at`: breaks the world round it and hits the car if it's
## near the ground within `r` (falling off with distance).
func shockwave(at: Vector3, r: float, dmg: float, knock: float) -> void:
	fx.ring(at + Vector3.UP * 0.3, accent, r * 1.6, 0.55, Vector3.UP)
	fx.ring(at + Vector3.UP * 0.5, Color(1.0, 0.9, 0.7), r * 0.9, 0.35, Vector3.UP)
	fx.dust(at, clampf(r / 8.0, 1.0, 3.0))
	fx.big_blast(at + Vector3.UP * 0.5)
	combat.sfx.boom(at)
	combat.wrecking.explode(at + Vector3.UP * 1.5, r * 0.6, 9.0)
	var cd := Vector2(car.global_position.x - at.x, car.global_position.z - at.z).length()
	fx.punch(clampf(1.0 - cd / (r * 4.0), 0.2, 1.0))
	if cd < r and car.global_position.y < at.y + 4.0:
		var k := 1.0 - 0.6 * cd / r
		combat.damage_player(dmg * k, at, kind)
		var away := car.global_position - at
		away.y = 0.0
		combat.knock_car((away.normalized() + Vector3.UP * 0.8).normalized() * knock * k)


## A close hit (swipe, bite, tusk): damage and a shove if the car is within r of at.
func melee(at: Vector3, r: float, dmg: float, push: Vector3) -> bool:
	if car.global_position.distance_to(at) > r:
		return false
	combat.damage_player(dmg, at, kind)
	combat.knock_car(push)
	fx.sparks(car.global_position + Vector3.UP * 0.8, accent, 1.0, (car.global_position - at).normalized())
	return true


## A lobbed projectile that lands on `to` after `t` seconds.
func lob(from: Vector3, to: Vector3, t: float, size: float, color: Color, on_hit: Callable) -> void:
	var v := (to - from) / t + Vector3.UP * 0.5 * GRAVITY * t
	_spawn_shot(from, v, GRAVITY, size, color, on_hit, t + 2.0)


## A straight(ish) fast projectile.
func shoot(from: Vector3, vel: Vector3, grav: float, size: float, color: Color, on_hit: Callable) -> void:
	_spawn_shot(from, vel, grav, size, color, on_hit, 4.0)


func _spawn_shot(from: Vector3, vel: Vector3, grav: float, size: float, color: Color, on_hit: Callable, life: float) -> void:
	var node := Node3D.new()
	get_parent().add_child(node)
	node.global_position = from
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = size
	sm.height = size * 2.0
	sm.radial_segments = 12
	sm.rings = 6
	mi.mesh = sm
	mi.material_override = Beasts.mat(color, 0.0, 0.3, 4.0)
	node.add_child(mi)
	var l := OmniLight3D.new()
	l.light_color = color
	l.omni_range = size * 6.0
	l.light_energy = 2.0
	node.add_child(l)
	_shots.append({"node": node, "vel": vel, "grav": grav, "life": life, "r": size, "hit": on_hit})


func _update_shots(delta: float) -> void:
	var keep: Array = []
	var space := get_world_3d().direct_space_state
	for s in _shots:
		var node: Node3D = s.node
		if not is_instance_valid(node):
			continue
		s.life -= delta
		s.vel += Vector3.DOWN * s.grav * delta
		var p0 := node.global_position
		var p1: Vector3 = p0 + s.vel * delta
		var at := Vector3.INF
		var c := Geometry3D.get_closest_point_to_segment(car.global_position + Vector3.UP * 0.5, p0, p1)
		if c.distance_to(car.global_position + Vector3.UP * 0.5) < s.r + 1.6:
			at = c
		else:
			var q := PhysicsRayQueryParameters3D.create(p0, p1, 1, [get_rid(), car.get_rid()])
			var hit := space.intersect_ray(q)
			if not hit.is_empty():
				at = hit.position
		if at == Vector3.INF and s.life <= 0.0:
			at = p1
		if at != Vector3.INF:
			node.queue_free()
			(s.hit as Callable).call(at)
			continue
		node.global_position = p1
		keep.append(s)
	_shots = keep


## A damaging patch on the ground (acid, fire) for `life` seconds.
func hazard(at: Vector3, r: float, dps: float, life: float, color: Color) -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = 0.08
	cm.radial_segments = 20
	mi.mesh = cm
	var m := Beasts.mat(color, 0.0, 0.2, 2.5).duplicate() as StandardMaterial3D
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color.a = 0.7
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_parent().add_child(mi)
	mi.global_position = at + Vector3.UP * 0.06
	_hazards.append({"node": mi, "mat": m, "at": at, "r": r, "dps": dps, "life": life, "max": life, "tick": 0.0})


func _update_hazards(delta: float) -> void:
	var keep: Array = []
	for h in _hazards:
		h.life -= delta
		var node: MeshInstance3D = h.node
		if h.life <= 0.0 or not is_instance_valid(node):
			if is_instance_valid(node):
				node.queue_free()
			continue
		(h.mat as StandardMaterial3D).albedo_color.a = 0.7 * clampf(h.life / 1.0, 0.0, 1.0)
		h.tick -= delta
		var at: Vector3 = h.at
		if h.tick <= 0.0 and car.global_position.distance_to(at) < h.r + 1.0 and car.global_position.y < at.y + 2.0:
			h.tick = 0.5
			combat.damage_player(h.dps * 0.5, at, kind)
		keep.append(h)
	_hazards = keep


## Its end: a chain of explosions, a storm of armour voxels, a crater.
func die_spectacular() -> void:
	var at := global_position + Vector3.UP * 3.0
	fx.explosion(at)
	fx.big_blast(at + Vector3.UP * 2.0)
	fx.ring(at, accent, 30.0, 0.8, Vector3.UP)
	fx.dust(global_position, 3.0)
	fx.punch(1.0)
	combat.sfx.boom(at)
	combat.sfx.wrecked()
	combat.wrecking.explode(at, 14.0, 10.0)
	var d: Node = combat.wrecking.debris
	d.burst(at, 30, 0.9, Color(0.17, 0.18, 0.2), Vector3.UP * 6.0, 16.0, Vector3(3, 2, 4))
	d.burst(at, 14, 0.6, accent, Vector3.UP * 8.0, 18.0, Vector3(3, 2, 3), 3.0)
	d.burst(at, 10, 0.7, Color(0.2, 0.34, 0.12), Vector3.UP * 5.0, 12.0, Vector3(3, 2, 3))
	for s in _shots:
		if is_instance_valid(s.node):
			(s.node as Node).queue_free()
	for h in _hazards:
		if is_instance_valid(h.node):
			(h.node as Node).queue_free()
	defeated.emit(self)
	queue_free()


## Shared: an attack's one-shot trigger at time `at` (true exactly once).
func once(key: String, t: float, at: float) -> bool:
	if t >= at and not _did.has(key):
		_did[key] = true
		return true
	return false
