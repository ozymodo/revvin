extends Node3D
## Combat, first wave:
##   - the car's HULL (health). Enemies hurt it; at zero the car is WRECKED,
##     the chain is lost and it respawns (last SKYWAY checkpoint or the start)
##     with full hull and a moment of invulnerability.
##   - ramming: driving into an enemy hurts it by closing speed, Rocket League
##     style, and knocks it flying. Hitting it mid-flip (a dodge or any fast
##     rotation) doubles the damage; boosting adds a little more.
##   - the weapons (combat/arsenal.gd mounts them, combat/weapons.gd defines
##     them): their projectiles, instant hits, lightning chains and beams.
##   - enemy goo shots, floating damage numbers, scorch marks and debris
##     where enemies smash into the world.

signal player_hurt(amount: float)
signal player_wrecked()
signal enemy_killed(enemy: Node, how: String)
signal enemy_rammed(enemy: Node, damage: float, flip: bool)
signal player_dodged()

const Arsenal := preload("res://scripts/combat/arsenal.gd")
const Fx := preload("res://scripts/fx.gd")

const MAX_HP := 100.0
const INVULN_HIT := 0.6             # s after a hit before the next one counts
const INVULN_RESPAWN := 3.0
const WRECK_TIME := 2.2             # s from wrecked to respawn
const RAM_MIN := 6.0                # m/s closing speed before a ram hurts
const RAM_DMG := 4.0                # damage per m/s of closing speed
const BOOST_MULT := 1.4
## Rams: damage grows faster than linearly with closing speed (SPEED_CURVE
## m/s doubles the per-m/s rate), and a flip multiplies it by how fast the
## car is spinning: from ×1 at FLIP_SPIN_MIN rad/s up to ×FLIP_MULT_MAX at
## FLIP_SPIN_FULL. A dodge flip always counts as at least ×DODGE_MULT.
const SPEED_CURVE := 35.0
const FLIP_SPIN_MIN := 2.5
const FLIP_SPIN_FULL := 9.5
const FLIP_MULT_MAX := 3.5
const DODGE_MULT := 3.0
## Flip guard: spinning fast, the car shrugs off most of a hit.
const FLIP_GUARD := 0.4             # share of damage taken while flipping
## A dodge makes the car untouchable for its first moments (dodge attacks).
const DODGE_IFRAMES := 0.35
const GOO_COLOR := Color(0.35, 1.0, 0.3)
const BOLT_COLOR := Color(0.3, 1.0, 0.35)
const MAX_DECALS := 40

var car: RigidBody3D
var tricks: Node
var fx: Node
var sfx: Node
var hud: Node
var director: Node
var wrecking: Node                  # world/wrecking.gd: blasts and impacts break the world
var respawn := Callable()           # puts the car back after a wreck

var hp := MAX_HP
var invuln := 0.0
var wrecked := 0.0                  # > 0: counting down to the respawn
var kills := 0
var arsenal: Node3D                 # combat/arsenal.gd: the car's weapon mounts
var _beam_acc := {}

var _shots: Array = []
var _clock := 0.0
var _last_dodged := -10.0
var _was_dodging := false
var _decals: Array = []
var _env_cd := 0.0
var _bolt_mat: StandardMaterial3D
var _goo_mat: StandardMaterial3D
var _scorch_tex: Texture2D
var snare := 0.0                    # s left webbed (the car crawls)
var _web: MeshInstance3D


func _ready() -> void:
	arsenal = Arsenal.new()
	arsenal.name = "Arsenal"
	arsenal.combat = self
	arsenal.car = car
	car.add_child(arsenal)
	_bolt_mat = StandardMaterial3D.new()
	_bolt_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_bolt_mat.albedo_color = Color(0.35, 1.7, 0.45)      # bright, but still green under bloom
	_goo_mat = StandardMaterial3D.new()
	_goo_mat.albedo_color = Color(0.2, 0.7, 0.2)
	_goo_mat.emission_enabled = true
	_goo_mat.emission = GOO_COLOR
	_goo_mat.emission_energy_multiplier = 3.0
	_goo_mat.roughness = 0.1


## Live enemies (a killed one can linger in the list until the next frame).
func enemies() -> Array:
	if director == null:
		return []
	return director.enemies.filter(func(e) -> bool: return is_instance_valid(e) and not e.dead)


# ------------------------------------------------------------------ player

## How the car is flipping right now: 0 = not at all, 1 = flat out (a dodge
## counts as flat out).
func flip_amount() -> float:
	var spin := car.angular_velocity.length()
	var k := clampf((spin - FLIP_SPIN_MIN) / (FLIP_SPIN_FULL - FLIP_SPIN_MIN), 0.0, 1.0)
	return 1.0 if car._dodge_t > 0.0 else k


## In the first DODGE_IFRAMES of a dodge flip.
func dodging() -> bool:
	return car._dodge_t > car.DODGE_TIME - DODGE_IFRAMES


func damage_player(amount: float, from: Vector3, source: String) -> void:
	if invuln > 0.0 or wrecked > 0.0 or amount <= 0.0:
		return
	if dodging():
		_dodged(from)
		return
	var guard := flip_amount() > 0.3
	if guard:
		amount *= FLIP_GUARD
	hp = maxf(0.0, hp - amount)
	invuln = INVULN_HIT
	player_hurt.emit(amount)
	var at := car.global_position + Vector3.UP * 0.6
	fx.sparks(at + (from - at).normalized() * 1.0, Color(1.0, 0.35, 0.2), 0.5, (from - at).normalized(), car)
	fx.punch(clampf(amount / 25.0, 0.2, 0.7))
	sfx.hurt()
	if hud:
		hud.hurt(amount)
		if guard:
			hud.notify("FLIP GUARD  ·  -%d%% DAMAGE" % roundi((1.0 - FLIP_GUARD) * 100.0), Color(0.6, 0.85, 1.0))
	if hp <= 0.0:
		_wreck(source)


## An attack that met a dodge: nothing taken, a quick shimmer and a whoosh.
func _dodged(from: Vector3) -> void:
	if _clock - _last_dodged < 0.3:
		return
	_last_dodged = _clock
	player_dodged.emit()
	var at := car.global_position + Vector3.UP * 0.6
	fx.ring(at, Color(0.6, 0.9, 1.0), 4.0, 0.3, (from - at).normalized())
	fx.sweep(Color(0.6, 0.9, 1.0), false, 0.6)
	sfx.dodge()
	if hud:
		hud.notify("DODGED!", Color(0.6, 0.95, 1.0))
	if tricks:
		tricks.smash_points(150)


func _wreck(_source: String) -> void:
	wrecked = WRECK_TIME
	var at := car.global_position
	fx.explosion(at)
	_scorch(at + Vector3.UP * 0.2, Vector3.UP, 7.0)
	if wrecking:
		wrecking.explode(at, 7.0, 5.0)
	# The blast throws the wreck up and over.
	car.apply_central_impulse(Vector3.UP * car.mass * 7.0 + car.global_basis.x * car.mass * randf_range(-2.0, 2.0))
	car.apply_torque_impulse(Vector3(randf_range(-1, 1), randf_range(-0.5, 0.5), randf_range(-1, 1)).normalized() * car.mass * 6.0)
	sfx.wrecked()
	if tricks:
		tricks.wreck()
	player_wrecked.emit()


## A boss hit throws the car (velocity change in m/s). A dodge avoids it.
func knock_car(dv: Vector3) -> void:
	if dodging() or wrecked > 0.0:
		return
	car.apply_central_impulse(dv * car.mass)
	if tricks:
		tricks.ignore_crash(1.2)


## Webbed: the car crawls for `seconds` (wheels and jets fight the web).
func snare_car(seconds: float) -> void:
	if dodging():
		return
	snare = maxf(snare, seconds)
	if hud:
		hud.notify("WEBBED!", Color(0.85, 0.8, 1.0))


func _update_snare(delta: float) -> void:
	if snare <= 0.0:
		if _web and _web.visible:
			_web.visible = false
		return
	snare -= delta
	var k := exp(-2.6 * delta)
	var v := car.linear_velocity
	car.linear_velocity = Vector3(v.x * k, v.y * (k if v.y > 0.0 else 1.0), v.z * k)
	if _web == null:
		_web = MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 2.4
		sm.height = 3.0
		sm.radial_segments = 10
		sm.rings = 5
		_web.mesh = sm
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.9, 0.88, 1.0, 0.35)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.emission_enabled = true
		m.emission = Color(0.6, 0.5, 0.9)
		m.emission_energy_multiplier = 0.6
		_web.material_override = m
		_web.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_web)
	_web.visible = true
	_web.global_position = car.global_position + Vector3.UP * 0.6
	_web.scale = Vector3.ONE * (0.8 + 0.2 * clampf(snare, 0.0, 1.0))


func heal_full() -> void:
	hp = MAX_HP


## Tricks and drifts patch the hull up a little (tricks.gd). Returns the
## amount actually restored.
func heal(amount: float) -> float:
	if wrecked > 0.0 or hp >= MAX_HP:
		return 0.0
	var before := hp
	hp = minf(MAX_HP, hp + amount)
	if hud:
		hud.healed(hp - before)
	return hp - before


# ------------------------------------------------------------------ enemies

func on_enemy_spawned(e: Node) -> void:
	fx.spawn_portal(e.global_position, e.size)


## The car hit an enemy: Rocket League style, damage by closing speed.
func on_car_hit_enemy(e: Node, closing: float, dir: Vector3) -> void:
	if tricks:
		tricks.ignore_crash(0.5)        # a ram isn't a crash, however hard
	if closing < RAM_MIN:
		return
	# Faster = harder, more than linearly; a flip multiplies it by spin.
	var flip := flip_amount()
	var flipping := flip > 0.15
	var mult := lerpf(1.0, FLIP_MULT_MAX, flip)
	if car._dodge_t > 0.0:
		mult = maxf(mult, DODGE_MULT)
	if car.thrust_valve > 0.3 or car.pad_time > 0.0:
		mult *= BOOST_MULT
	var dmg := (closing - RAM_MIN * 0.5) * RAM_DMG * (1.0 + closing / SPEED_CURVE) * mult
	# Send it flying along the hit, a bit upward, harder off a flip. A boss
	# barely budges.
	var shove: float = minf(e.mass, 900.0) if e.boss else e.mass
	e.apply_central_impulse((dir + Vector3.UP * 0.35).normalized() * shove * closing * lerpf(0.35, 0.8, flip))
	var at: Vector3 = (car.global_position + e.global_position) * 0.5 + Vector3.UP * 0.5
	fx.sparks(at, Color(1.0, 0.85, 0.4), clampf(dmg / 80.0, 0.3, 1.2), dir)
	fx.ring(at, Color(1.0, 0.8, 0.4) * 0.8, 1.2 + minf(dmg * 0.01, 1.5), 0.25, Vector3.UP)
	fx.punch(clampf(dmg / 150.0, 0.15, 0.6))
	sfx.thunk(clampf(dmg / 120.0, 0.2, 1.0))
	number(at + Vector3.UP * 0.8, dmg, Color(1.0, 0.75, 0.25) if flipping else Color(1.0, 0.95, 0.8), flipping)
	enemy_rammed.emit(e, dmg, flipping)
	e.take_damage(dmg, "flip" if flipping else "ram")


func on_enemy_died(e: Node, how: String) -> void:
	kills += 1
	if e.boss:
		enemy_killed.emit(e, how)
		e.die_spectacular()
		return
	var at: Vector3 = e.global_position
	var s: float = e.size
	fx.debris(at, Color(0.4, 0.33, 0.26), GOO_COLOR, s)
	fx.burst(at, GOO_COLOR, 0.6 + s * 0.4, Vector3.UP)
	sfx.enemy_die(s)
	if tricks:
		tricks.combat_kill(e.points, how, e.kind)
	enemy_killed.emit(e, how)
	e.queue_free()


## A bee spits goo at the car.
func enemy_shoot(from: Vector3, aim: Vector3, speed: float, dmg: float, owner: Node) -> void:
	var node := Node3D.new()
	add_child(node)
	node.global_position = from
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.22
	sm.height = 0.44
	sm.radial_segments = 10
	sm.rings = 6
	mi.mesh = sm
	mi.material_override = _goo_mat
	node.add_child(mi)
	node.add_child(_trail(GOO_COLOR, 0.12))
	_shots.append({"node": node, "vel": (aim - from).normalized() * speed, "life": 3.0, "kind": "goo",
		"dmg": dmg, "grav": 4.0, "owner": owner})
	sfx.goo_spit(from)


## Player projectile speeds by kind (the arsenal leads targets with these).
const PROJECTILE_SPEED := {"bolt": 95.0, "frost": 70.0, "rocket": 45.0, "missile": 55.0, "saw": 40.0}


## Ray gun bolt.
func fire_bolt(from: Vector3, dir: Vector3, dmg: float, splash: float, color: Color) -> void:
	_launch(from, dir, "bolt", {"dmg": dmg, "splash": splash, "color": color})
	sfx.raygun()


## Cryo spiker: an ice shard; its burst chills (slows) what it catches.
func fire_frost(from: Vector3, dir: Vector3, dmg: float, splash: float) -> void:
	_launch(from, dir, "frost", {"dmg": dmg, "splash": splash, "color": Color(0.55, 0.9, 1.0)})
	sfx.frost()


## Thunderhead: one big slow rocket, a huge blast.
func fire_rocket(from: Vector3, dir: Vector3, dmg: float, splash: float) -> void:
	_launch(from, dir, "rocket", {"dmg": dmg, "splash": splash, "color": Color(1.0, 0.45, 0.15)})
	sfx.rocket_launch()


## Swarm pod: a homing missile; salvo index k fans them out of the pod.
func fire_missile(from: Vector3, dir: Vector3, target: Node, dmg: float, splash: float, k: int) -> void:
	var fan := dir.rotated(Vector3.UP, (k - 2.5) * 0.18) + Vector3.UP * 0.5
	_launch(from, fan.normalized(), "missile", {"dmg": dmg, "splash": splash, "color": Color(1.0, 0.55, 0.2), "target": target})
	if k == 0:
		sfx.missiles()


## Saw ripper: a blade that ricochets from enemy to enemy.
func fire_saw(from: Vector3, target: Node, dmg: float, bounces: int) -> void:
	var dir: Vector3 = (target.global_position - from).normalized()
	_launch(from, dir, "saw", {"dmg": dmg, "splash": 0.0, "color": Color(0.85, 0.9, 0.95), "target": target, "bounces": bounces, "hit": []})
	sfx.saw()


func _launch(from: Vector3, dir: Vector3, kind: String, extra: Dictionary) -> void:
	var node := Node3D.new()
	add_child(node)
	node.global_position = from
	node.add_child(_proj_visual(kind, extra.color))
	node.look_at(from + dir, Vector3.UP if absf(dir.y) < 0.98 else Vector3.RIGHT)
	var shot := {"node": node, "vel": dir * PROJECTILE_SPEED[kind] + car.linear_velocity * (0.0 if kind == "missile" else 1.0),
		"life": 3.0 if kind == "missile" or kind == "saw" else 1.8, "kind": kind, "grav": 0.0, "owner": car}
	shot.merge(extra)
	_shots.append(shot)


func _proj_visual(kind: String, c: Color) -> Node3D:
	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color = Color(c.r * 1.8, c.g * 1.8, c.b * 1.8)
	match kind:
		"bolt":
			var cm := CapsuleMesh.new()
			cm.radius = 0.09
			cm.height = 0.65
			mi.mesh = cm
			mi.rotation = Vector3(PI * 0.5, 0, 0)
			mi.material_override = _bolt_mat
		"frost":
			var pm := CylinderMesh.new()
			pm.top_radius = 0.0
			pm.bottom_radius = 0.09
			pm.height = 0.6
			pm.radial_segments = 5
			mi.mesh = pm
			mi.rotation = Vector3(-PI * 0.5, 0, 0)
			mi.material_override = glow
		"rocket", "missile":
			var big := kind == "rocket"
			var rm := CylinderMesh.new()
			rm.top_radius = 0.09 if big else 0.035
			rm.bottom_radius = rm.top_radius
			rm.height = 0.7 if big else 0.32
			rm.radial_segments = 10
			mi.mesh = rm
			mi.rotation = Vector3(PI * 0.5, 0, 0)
			var body := StandardMaterial3D.new()
			body.albedo_color = Color(0.3, 0.33, 0.25) if big else Color(0.75, 0.75, 0.72)
			body.metallic = 0.6
			mi.material_override = body
			var flame := _trail(Color(1.0, 0.55, 0.15), 0.3 if big else 0.14)
			flame.position = Vector3(0, 0, 0.4 if big else 0.18)
			root.add_child(flame)
			root.add_child(_smoke_trail(1.0 if big else 0.5))
		"saw":
			var sm := CylinderMesh.new()
			sm.top_radius = 0.22
			sm.bottom_radius = 0.22
			sm.height = 0.03
			sm.radial_segments = 16
			mi.mesh = sm
			var steel := StandardMaterial3D.new()
			steel.albedo_color = Color(0.75, 0.78, 0.82)
			steel.metallic = 1.0
			steel.roughness = 0.2
			mi.material_override = steel
			mi.name = "Blade"
	root.add_child(mi)
	if kind != "saw":
		root.add_child(_trail(c, 0.14))
		var light := OmniLight3D.new()
		light.light_color = c
		light.light_energy = 1.2
		light.omni_range = 3.5
		root.add_child(light)
	return root


func _physics_process(delta: float) -> void:
	_clock += delta
	invuln = maxf(0.0, invuln - delta)
	_update_snare(delta)
	fx.damage = 1.0 if wrecked > 0.0 else clampf(1.0 - hp / MAX_HP, 0.0, 1.0)
	# A shimmer over the car for the untouchable start of every dodge.
	var d := dodging()
	if d and not _was_dodging:
		fx.sweep(Color(0.6, 0.9, 1.0), false, 0.35)
	_was_dodging = d
	_env_cd -= delta
	if wrecked > 0.0:
		wrecked -= delta
		if wrecked <= 0.0:
			if respawn.is_valid():
				respawn.call()
			hp = MAX_HP
			invuln = INVULN_RESPAWN
	var space := get_world_3d().direct_space_state
	var keep: Array = []
	for s in _shots:
		var node: Node3D = s.node
		s.life -= delta
		s.vel += Vector3.DOWN * s.grav * delta
		if s.kind == "missile" or s.kind == "saw":
			_home(s, delta)
		var p0 := node.global_position
		var p1: Vector3 = p0 + s.vel * delta
		var done: bool = s.life <= 0.0
		if s.kind == "goo":
			done = done or _goo_step(s, p0, p1, space)
		else:
			done = done or _shot_step(s, p0, p1, space)
		if done:
			node.queue_free()
		else:
			node.global_position = p1
			if (s.vel as Vector3).length() > 0.1:
				node.look_at(p1 + s.vel, Vector3.UP if absf((s.vel as Vector3).normalized().y) < 0.98 else Vector3.RIGHT)
			if s.kind == "saw":
				var blade := node.find_child("Blade", true, false) as Node3D
				if blade:
					blade.rotate_object_local(Vector3.UP, delta * 40.0)
			keep.append(s)
	_shots = keep


## Missiles curve onto their target; saws fly straight at theirs.
func _home(s: Dictionary, delta: float) -> void:
	var t = s.get("target")
	if t == null or not is_instance_valid(t) or t.dead:
		return
	var speed: float = PROJECTILE_SPEED[s.kind]
	var want: Vector3 = ((t as Node3D).global_position - (s.node as Node3D).global_position).normalized() * speed
	var turn := 5.0 if s.kind == "missile" else 12.0
	s.vel = (s.vel as Vector3).lerp(want, 1.0 - exp(-turn * delta))


## Moves a player shot; true when it's finished.
func _shot_step(s: Dictionary, p0: Vector3, p1: Vector3, space: PhysicsDirectSpaceState3D) -> bool:
	for e in enemies():
		if s.kind == "saw" and (s.hit as Array).has(e):
			continue
		var c := Geometry3D.get_closest_point_to_segment(e.global_position, p0, p1)
		if c.distance_to(e.global_position) < e.radius + 0.45:
			return _impact(s, c, e)
	var q := PhysicsRayQueryParameters3D.create(p0, p1, 1, [car.get_rid()])
	var hit := space.intersect_ray(q)
	if not hit.is_empty():
		return _impact(s, hit.position, null)
	return false


func _impact(s: Dictionary, at: Vector3, direct: Node) -> bool:
	var c: Color = s.color
	var how := "gun"
	match s.kind:
		"bolt":
			fx.raygun_impact(at)
			sfx.zap(at)
		"frost":
			fx.frost_burst(at)
			sfx.zap(at)
		"missile":
			fx.burst(at, c, 0.45, Vector3.UP)
			sfx.crunch(at, 0.4)
		"rocket":
			fx.big_blast(at)
			sfx.boom(at)
		"saw":
			if direct == null:
				fx.sparks(at, Color(1.0, 0.8, 0.5), 0.4, Vector3.UP)
				if wrecking:
					wrecking.explode(at, 1.0, 0.8)
				return true
			_hurt_enemy(direct, s.dmg, at, how, c)
			fx.sparks(at, Color(1.0, 0.85, 0.6), 0.5, Vector3.UP)
			(s.hit as Array).append(direct)
			s.bounces -= 1
			var next: Node = null
			var best := 25.0
			for e in enemies():
				if (s.hit as Array).has(e):
					continue
				var dd: float = e.global_position.distance_to(at)
				if dd < best:
					best = dd
					next = e
			if s.bounces < 0 or next == null:
				return true
			s.target = next
			s.vel = (next.global_position - at).normalized() * PROJECTILE_SPEED.saw
			s.life = 2.0
			return false
	# Shots break the world too: glass and crates from anything, concrete
	# from rockets.
	if wrecking:
		match s.kind:
			"rocket":
				wrecking.explode(at, 7.0, 9.0)
			"missile":
				wrecking.explode(at, 2.6, 2.2)
			_:
				wrecking.explode(at, 1.2, 0.9)
	if direct:
		_hurt_enemy(direct, s.dmg, at, how, c)
		if s.kind == "frost":
			direct.chill = 2.5
	var splash: float = s.get("splash", 0.0)
	if splash > 0.0:
		for e in enemies():
			if e == direct:
				continue
			var d: float = e.global_position.distance_to(at) - e.radius
			if d < splash:
				_hurt_enemy(e, s.dmg * 0.6 * (1.0 - maxf(d, 0.0) / splash), at, how, c)
				if s.kind == "frost":
					e.chill = 2.0
	return true


## Instant hit with a tracer (sniper, deagle).
func hitscan(from: Vector3, target: Node, dmg: float, color: Color, heavy: bool) -> void:
	var at: Vector3 = target.global_position
	fx.tracer(from, at, color, 0.05 if heavy else 0.03, 0.25 if heavy else 0.12)
	fx.sparks(at, color, 0.6 if heavy else 0.3, (from - at).normalized())
	if heavy:
		sfx.sniper()
		fx.ring(at, color, 3.0, 0.25, (from - at).normalized())
	else:
		sfx.deagle()
	_hurt_enemy(target, dmg, at, "gun", color, heavy)


## Scatter cannon: a spread of pellets at the target; most of them land.
func pellets(from: Vector3, target: Node, dmg: float, n: int, color: Color) -> void:
	var at: Vector3 = target.global_position
	var total := 0.0
	for k in n:
		var off := Vector3(randf_range(-1, 1), randf_range(-0.6, 0.6), randf_range(-1, 1)) * (0.4 + from.distance_to(at) * 0.05)
		fx.tracer(from, at + off, color, 0.015, 0.08)
		if off.length() < target.radius + 0.6:
			total += dmg
	sfx.scatter()
	if total > 0.0:
		_hurt_enemy(target, total, at, "gun", color)


## Tesla coil: a lightning bolt that jumps on to nearby enemies.
func chain_lightning(from: Vector3, target: Node, dmg: float, chains: int, r: float, color: Color) -> void:
	var hit := [target]
	var a := from
	var cur: Node = target
	var d := dmg
	for k in chains + 1:
		var b: Vector3 = cur.global_position
		fx.lightning(a, b, color)
		_hurt_enemy(cur, d, b, "gun", color)
		var next: Node = null
		var best := r
		for e in enemies():
			if hit.has(e):
				continue
			var dd: float = e.global_position.distance_to(b)
			if dd < best:
				best = dd
				next = e
		if next == null:
			break
		hit.append(next)
		a = b
		cur = next
		d *= 0.8
	sfx.tesla()


## Plasma beam: continuous damage; the number shows a few times a second.
func beam_damage(target: Node, amount: float, at: Vector3, show: bool) -> void:
	var acc: float = _beam_acc.get(target, 0.0) + amount
	if show:
		number(at + Vector3.UP * (target.radius + 0.4), acc, Color(0.75, 0.5, 1.0), false)
		fx.sparks(at, Color(0.7, 0.4, 1.0), 0.15, Vector3.UP)
		acc = 0.0
	_beam_acc[target] = acc
	target.take_damage(amount, "gun")


func _hurt_enemy(e: Node, dmg: float, at: Vector3, how: String, color := Color(0.75, 1.0, 0.7), crit := false) -> void:
	var push: Vector3 = (e.global_position - at).normalized() + Vector3.UP * 0.3
	e.apply_central_impulse(push.normalized() * minf(e.mass, 600.0) * (0.3 if e.boss else 2.5))
	number(e.global_position + Vector3.UP * (e.radius + 0.4), dmg, color.lerp(Color.WHITE, 0.4), crit)
	e.take_damage(dmg, how)


func _goo_step(s: Dictionary, p0: Vector3, p1: Vector3, space: PhysicsDirectSpaceState3D) -> bool:
	var c := Geometry3D.get_closest_point_to_segment(car.global_position + Vector3.UP * 0.5, p0, p1)
	if c.distance_to(car.global_position + Vector3.UP * 0.5) < 1.7:
		fx.goo_splat(c, Vector3.UP)
		damage_player(s.dmg, p0, "goo")
		return true
	var q := PhysicsRayQueryParameters3D.create(p0, p1, 1, [car.get_rid()])
	var hit := space.intersect_ray(q)
	if not hit.is_empty():
		fx.goo_splat(hit.position, hit.normal)
		return true
	return false


func sfx_hop(pos: Vector3, size: float) -> void:
	sfx.hop(pos, size)


# ------------------------------------------------------------------ world damage

## An enemy smashed into the world: debris and a scorch mark.
func env_hit(at: Vector3, vel: Vector3, power: float) -> void:
	if _env_cd > 0.0:
		return
	_env_cd = 0.12
	var n := -vel.normalized() if vel.length() > 0.1 else Vector3.UP
	fx.debris(at, Color(0.35, 0.33, 0.3), Color(0.55, 0.5, 0.42), clampf(power * 0.6, 0.3, 1.2))
	fx.sparks(at, Color(1.0, 0.7, 0.35), clampf(power * 0.4, 0.2, 0.8), n)
	sfx.crunch(at, power)
	_scorch(at, n, 1.2 + power)
	if wrecking:
		wrecking.impact(at, vel, power)


func _scorch(at: Vector3, n: Vector3, size: float) -> void:
	if _scorch_tex == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
		g.colors = PackedColorArray([Color(0.02, 0.02, 0.02, 0.85), Color(0.05, 0.04, 0.03, 0.6), Color(0, 0, 0, 0)])
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		t.width = 128
		t.height = 128
		_scorch_tex = t
	var d := Decal.new()
	d.texture_albedo = _scorch_tex
	d.size = Vector3(size, 1.5, size)
	add_child(d)
	d.global_transform = Transform3D(Fx.basis_up(n), at)
	var tw := d.create_tween()
	tw.tween_interval(20.0)
	tw.tween_property(d, "modulate:a", 0.0, 3.0)
	tw.tween_callback(d.queue_free)
	# Marks free themselves once faded; drop those before trimming the oldest.
	_decals = _decals.filter(func(x) -> bool: return is_instance_valid(x))
	_decals.append(d)
	while _decals.size() > MAX_DECALS:
		_decals.pop_front().queue_free()


# ------------------------------------------------------------------ feedback

## Floating damage number (crits are bigger and gold).
func number(at: Vector3, value: float, color: Color, crit: bool) -> void:
	var l := Label3D.new()
	l.text = str(roundi(value))
	l.font_size = 64 if crit else 44
	l.pixel_size = 0.012
	l.outline_size = 12
	l.modulate = color
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.shaded = false
	l.top_level = true
	add_child(l)
	l.global_position = at + Vector3(randf_range(-0.3, 0.3), 0, randf_range(-0.3, 0.3))
	var tw := l.create_tween().set_parallel()
	tw.tween_property(l, "global_position", l.global_position + Vector3.UP * 1.6, 0.9).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(l, "modulate:a", 0.0, 0.9).set_delay(0.35)
	tw.tween_property(l, "scale", Vector3.ONE, 0.2).from(Vector3.ONE * (1.8 if crit else 1.4))
	tw.chain().tween_callback(l.queue_free)


## Grey smoke streaming behind rockets and missiles.
func _smoke_trail(size: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 30
	p.lifetime = 0.9
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-40, -40, -40), Vector3(80, 80, 80))
	var m := ParticleProcessMaterial.new()
	m.direction = Vector3.UP
	m.spread = 60.0
	m.initial_velocity_min = 0.2
	m.initial_velocity_max = 0.8
	m.gravity = Vector3(0, 0.6, 0)
	m.scale_min = 0.8 * size
	m.scale_max = 1.4 * size
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.4))
	curve.add_point(Vector2(1, 2.2))
	var ct := CurveTexture.new()
	ct.curve = curve
	m.scale_curve = ct
	m.color = Color(0.55, 0.55, 0.55, 0.5)
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	var gt := GradientTexture1D.new()
	gt.gradient = g
	m.color_ramp = gt
	p.process_material = m
	p.draw_pass_1 = Fx._soft_quad(0.5, false)
	return p


func _trail(color: Color, size: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 24
	p.lifetime = 0.25
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-40, -40, -40), Vector3(80, 80, 80))
	var m := ParticleProcessMaterial.new()
	m.direction = Vector3.ZERO
	m.spread = 180.0
	m.initial_velocity_min = 0.0
	m.initial_velocity_max = 0.6
	m.gravity = Vector3.ZERO
	m.scale_min = 0.6
	m.scale_max = 1.0
	m.color = Color(color.r * 2.0, color.g * 2.0, color.b * 2.0)
	var curve := Curve.new()
	curve.add_point(Vector2(0, 1.0))
	curve.add_point(Vector2(1, 0.1))
	var ct := CurveTexture.new()
	ct.curve = curve
	m.scale_curve = ct
	p.process_material = m
	p.draw_pass_1 = Fx.glow_quad(size, 1.0)
	return p
