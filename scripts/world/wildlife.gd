extends Node3D
## The beasts of the city: four territories, one per animal (gorilla,
## T. rex, spider, elephant), each ruled by its boss, a high-tech monster
## truck of the same animal (enemies/boss_*.gd).
##
## Herds of the living animal (world/critter.gd) roam the territory, and a
## few stray further out, so the animals you see point the way to their
## boss: lots of gorillas, the SILVERBACK is near. Deer roam everywhere.
##
## Run any animal over fast enough and it's converted into BIOFUEL: a burst
## of glowing goo flows into the battery. Too slow and it just gets angry,
## and the fighters hit back (weakly). An elephant needs real speed; bump it
## slowly and the car bounces off.
##
## A boss stays home until you come close or shoot it, then hunts you. Beat
## it for a big score, a full battery, some hull back and a large weapon
## case. It comes back stronger a while later.

signal biofuel(kind: String, amount: float)
signal boss_down(boss: Node)

const Critter := preload("res://scripts/world/critter.gd")
const BOSSES := {
	"gorilla": preload("res://scripts/enemies/boss_gorilla.gd"),
	"rex": preload("res://scripts/enemies/boss_rex.gd"),
	"spider": preload("res://scripts/enemies/boss_spider.gd"),
	"elephant": preload("res://scripts/enemies/boss_elephant.gd"),
}
const KINDS := ["gorilla", "rex", "spider", "elephant"]
const BOSS_HP := {"gorilla": 4500.0, "rex": 5000.0, "spider": 3800.0, "elephant": 7000.0}
const BOSS_CONTACT := 25.0
const BOSS_POINTS := 5000
const BOSS_RESPAWN := 150.0
const TERRITORY_R := 85.0
const HERDS := 4                    # herds inside each territory
const STRAYS := 3                   # small herds further out, on the way in
const HERD_SIZE := {"gorilla": [3, 5], "rex": [2, 3], "spider": [5, 8], "elephant": [3, 4]}
const REVIVE := 60.0
const BIO_COLOR := Color(0.45, 1.0, 0.3)
## Deer aren't critter.gd but share the run-over rules: [kill speed, biofuel, points, colour]
const DEER := [4.0, 0.03, 40, Color(0.55, 0.38, 0.22)]

var car: RigidBody3D
var combat: Node
var director: Node
var fx: Node
var sfx: Node
var hud: Node
var tricks: Node
var cases: Node
var city: Node
var debris: Node
var spawn_bosses := true
var territories: Array = []         # [kind, centre]
var bosses := {}                    # kind -> boss (or null while it's down)
var kills := 0
var fuel_total := 0.0

var _boss_timer := {}
var _boss_level := {}
var _engaged: Node = null
var _brood: Array = []
var _rng := RandomNumberGenerator.new()
var _territory_shown := ""
var _toast_cd := 0.0
var _fuel_toast := 0.0
var _fuel_kind := ""


func setup(level: Node3D) -> void:
	city = level.city
	_rng.seed = 2468
	_pick_territories()
	print("Beast territories: ", ", ".join(territories.map(func(t) -> String: return "%s at (%d, %d)" % [t[0], t[1].x, t[1].z])))
	for t in territories:
		var kind: String = t[0]
		var c: Vector3 = t[1]
		_boss_level[kind] = 1
		_boss_timer[kind] = 0.0
		bosses[kind] = null
		for h in HERDS:
			_herd(kind, c, TERRITORY_R * 0.3, TERRITORY_R * 1.3)
		for h in STRAYS:
			_herd(kind, c, TERRITORY_R * 1.6, TERRITORY_R * 2.8, 2)


## One territory per quadrant, as far into open ground as possible.
func _pick_territories() -> void:
	var quads := [Vector2(1, 1), Vector2(-1, 1), Vector2(-1, -1), Vector2(1, -1)]
	for qi in 4:
		var q: Vector2 = quads[qi]
		var best := Vector3.ZERO
		var best_m := -1.0
		var x := 90.0
		while x <= 360.0:
			var z := 90.0
			while z <= 360.0:
				var p := Vector3(x * q.x, 0, z * q.y)
				var m := 0.0
				for margin in [8.0, 16.0, 24.0, 32.0]:
					if city.is_wild(p.x, p.z, margin):
						m = margin
				if m > best_m:
					best_m = m
					best = p
				z += 15.0
			x += 15.0
		territories.append([KINDS[qi], best])


func _herd(kind: String, centre: Vector3, r0: float, r1: float, max_n := 99) -> void:
	for attempt in 30:
		var a := _rng.randf() * TAU
		var home := centre + Vector3(cos(a), 0, sin(a)) * _rng.randf_range(r0, r1)
		if not city.is_wild(home.x, home.z, 6.0):
			continue
		var n := mini(_rng.randi_range(HERD_SIZE[kind][0], HERD_SIZE[kind][1]), max_n)
		for i in n:
			spawn_critter(kind, home + Vector3(_rng.randf_range(-6, 6), 0, _rng.randf_range(-6, 6)))
		return


func spawn_critter(kind: String, at: Vector3, hunter := false) -> Node3D:
	var c := Critter.new()
	c.kind = kind
	c.city = city
	c.home = at
	c.hunter = hunter
	add_child(c)
	c.global_position = Vector3(at.x, 0, at.z)
	return c


## A boss calling up its brood: hunters that go for the car.
func spawn_brood(kind: String, at: Vector3) -> void:
	var c := spawn_critter(kind, at, true)
	_brood.append(c)
	fx.dust(at, 0.6)


func brood_count() -> int:
	_brood = _brood.filter(func(c) -> bool: return is_instance_valid(c) and not c.dead)
	return _brood.size()


func spawn_boss(kind: String, at: Vector3) -> Node:
	var script: GDScript = BOSSES[kind]
	var b: RigidBody3D = script.new()
	var lvl: int = _boss_level.get(kind, 1)
	b.level = lvl
	b.max_hp = BOSS_HP[kind] * (1.0 + 0.3 * (lvl - 1))
	b.contact_damage = BOSS_CONTACT * (1.0 + 0.15 * (lvl - 1))
	b.points = BOSS_POINTS * lvl
	b.territory = at
	b.territory_r = TERRITORY_R
	b.wildlife = self
	b.car = car
	b.combat = combat
	var space := get_world_3d().direct_space_state
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(at + Vector3.UP * 100.0, at + Vector3.DOWN * 20.0, 1))
	b.position = (hit.position if not hit.is_empty() else at) + Vector3.UP * 0.6
	b.rotation.y = _rng.randf() * TAU
	director.add_boss(b)
	b.defeated.connect(_on_boss_defeated)
	bosses[kind] = b
	return b


# ------------------------------------------------------------------ per frame

func _physics_process(delta: float) -> void:
	if car == null:
		return
	_toast_cd -= delta
	_fuel_toast -= delta
	if spawn_bosses:
		for t in territories:
			var kind: String = t[0]
			if bosses[kind] == null or not is_instance_valid(bosses[kind]):
				bosses[kind] = null
				_boss_timer[kind] -= delta
				if _boss_timer[kind] <= 0.0 and car.global_position.distance_to(t[1]) > 160.0:
					spawn_boss(kind, t[1])
	_territory_hint()
	var p := car.global_position
	var v := car.linear_velocity
	var speed := v.length()
	for c in get_tree().get_nodes_in_group("critters"):
		var n := c as Node3D
		if c.dead:
			_revive(n, delta)
			continue
		var d := Vector2(n.global_position.x - p.x, n.global_position.z - p.z).length()
		var r: float = c.radius
		if d > r + 3.5 or p.y > n.global_position.y + c.height + 0.8:
			continue
		var is_deer := not (c is Critter)
		var kill_speed: float = DEER[0] if is_deer else Critter.KINDS[c.kind][4]
		if d < r + 1.3:
			if speed >= kill_speed:
				_convert(n, v)
				continue
			elif not is_deer and speed > 1.5:
				c.provoke()
				if c.kind == "elephant":
					# Too slow to flatten an elephant: bounce off it.
					var away := (p - n.global_position)
					away.y = 0.0
					car.linear_velocity = away.normalized() * maxf(speed * 0.5, 3.0) + Vector3.UP * 1.5
					combat.damage_player(4.0, n.global_position, "elephant")
		if not is_deer and c.try_hit(d):
			combat.damage_player(c.bite_damage(), n.global_position + Vector3.UP, c.kind)
			fx.sparks(p + Vector3.UP * 0.6, Color(1.0, 0.6, 0.3), 0.3, (n.global_position - p).normalized())


## Run over: the animal becomes biofuel and flows into the battery.
func _convert(c: Node3D, v: Vector3) -> void:
	var is_deer := not (c is Critter)
	var kind: String = "deer" if is_deer else c.kind
	var amount: float = DEER[1] if is_deer else Critter.KINDS[kind][8]
	var pts: int = DEER[2] if is_deer else Critter.KINDS[kind][9]
	var col: Color = DEER[3] if is_deer else Critter.KINDS[kind][10]
	c.dead = true
	c.visible = false
	c.respawn_t = REVIVE
	var at := c.global_position + Vector3.UP * 0.8
	var size: float = c.height / 2.0
	fx.burst(at, BIO_COLOR, 0.6 + size * 0.4, Vector3.UP)
	fx.goo_splat(c.global_position + Vector3.UP * 0.05, Vector3.UP)
	fx.sparks(at, BIO_COLOR, 0.5, Vector3.UP)
	if debris:
		debris.burst(at, 3 + int(size * 4.0), clampf(0.25 * size, 0.2, 0.6), col, v * 0.5 + Vector3.UP * 3.0, 5.0, Vector3.ONE * 0.5 * size)
		debris.burst(at, 2 + int(size * 2.0), 0.25, BIO_COLOR, v * 0.4 + Vector3.UP * 4.0, 4.0, Vector3.ONE * 0.4, 2.5)
	sfx.crunch(at, clampf(size, 0.4, 1.0))
	sfx.charge()
	fx.punch(clampf(0.1 + size * 0.1, 0.1, 0.4))
	car.add_charge(amount, BIO_COLOR)
	if tricks:
		tricks.ignore_crash(0.5)
		tricks.smash_points(pts)
	if kind == "elephant":
		car.linear_velocity *= 0.85
	kills += 1
	fuel_total += amount
	biofuel.emit(kind, amount)
	if hud and (_fuel_toast <= 0.0 or _fuel_kind != kind):
		_fuel_toast = 0.8
		_fuel_kind = kind
		hud.notify("+BIOFUEL  ·  %s  +%d%% BATTERY" % [kind.to_upper(), roundi(amount * 100.0)], BIO_COLOR)
	if _brood.has(c):
		_brood.erase(c)
		c.queue_free()


func _revive(c: Node3D, delta: float) -> void:
	if c.get("hunter"):
		return
	c.respawn_t -= delta
	if c.respawn_t > 0.0:
		return
	if c.home.distance_to(car.global_position) < 90.0:
		c.respawn_t = 5.0
		return
	c.global_position = c.home + Vector3(_rng.randf_range(-5, 5), 0, _rng.randf_range(-5, 5))
	c.dead = false
	c.visible = true


## Entering a territory: a hint about what lives here.
func _territory_hint() -> void:
	var here := ""
	for t in territories:
		if car.global_position.distance_to(t[1]) < TERRITORY_R * 1.4:
			here = t[0]
	if here != _territory_shown:
		_territory_shown = here
		if here != "" and hud and bosses.get(here) != null and not bosses[here].engaged:
			hud_toast("%s TERRITORY  ·  %s is near" % [here.to_upper(), bosses[here].boss_name], BOSSES_ACCENT(here))


static func BOSSES_ACCENT(kind: String) -> Color:
	return preload("res://scripts/enemies/beast_models.gd").ACCENT[kind]


func hud_toast(text: String, color: Color) -> void:
	if hud:
		hud.notify(text, color)


# ------------------------------------------------------------------ bosses

func boss_engaged(b: Node) -> void:
	_engaged = b
	if hud:
		hud.boss = b
		hud_toast("⚠  %s  ·  %s" % [b.boss_name, b.title.to_upper()], b.accent)
	sfx.roar(b.global_position, 0.9)
	fx.punch(0.5)


func boss_disengaged(b: Node) -> void:
	if _engaged == b:
		_engaged = null
		if hud:
			hud.boss = null
			hud_toast("%s lost interest" % b.boss_name, Color(0.8, 0.8, 0.8))


func _on_boss_defeated(b: Node) -> void:
	var kind: String = b.kind
	_boss_level[kind] = int(b.level) + 1
	_boss_timer[kind] = BOSS_RESPAWN
	bosses[kind] = null
	if _engaged == b:
		_engaged = null
	if hud:
		hud.boss = null
		hud_toast("%s DESTROYED  ·  +%d" % [b.boss_name, b.points], b.accent)
	if tricks:
		tricks.smash_points(b.points)
	car.add_charge(1.0, b.accent)
	combat.heal(50.0)
	if cases:
		var at: Vector3 = b.global_position
		cases.add_case(Vector3(at.x, maxf(at.y - 3.0, 0.0), at.z), "large", false)
	boss_down.emit(b)
