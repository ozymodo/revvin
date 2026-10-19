extends Node3D
## Spawns enemies around the car over time, Vampire Survivors style: a new
## one every few seconds, more of them alive at once as the THREAT level
## climbs (one level per minute). Each comes in at a random size; bigger
## ones are tougher, hit harder and are worth more. Enemies that fall far
## behind are recycled.

const Bee := preload("res://scripts/enemies/bee.gd")
const Roller := preload("res://scripts/enemies/roller.gd")
const Hopper := preload("res://scripts/enemies/hopper.gd")

## [script, base health, base contact damage, points, weight]
const TYPES := {
	"bee": [Bee, 60.0, 14.0, 100, 0.35],
	"roller": [Roller, 140.0, 12.0, 150, 0.35],
	"hopper": [Hopper, 90.0, 16.0, 120, 0.3],
}
const SPAWN_MIN := 55.0
const SPAWN_MAX := 110.0
const DESPAWN := 240.0
const SIGHT_CHECK := 0.5
const RECYCLE_HIDDEN := 12.0        # s out of the car's sight before an enemy is recycled

var car: RigidBody3D
var combat: Node
var enabled := true
var threat := 1
var enemies: Array = []

var _time := 0.0
var _spawn_t := 3.0
var _sight_t := 0.0


func _physics_process(delta: float) -> void:
	enemies = enemies.filter(func(e) -> bool: return is_instance_valid(e) and not e.dead)
	_sight_t -= delta
	var check := _sight_t <= 0.0
	if check:
		_sight_t = SIGHT_CHECK
	for e in enemies:
		var d: float = e.global_position.distance_to(car.global_position)
		# Recycle ones far behind, fallen out of the world, or walled off out
		# of sight for a long time (a new one spawns somewhere better).
		if check:
			e.unseen = e.unseen + SIGHT_CHECK if d > 20.0 and not e.can_see_car() else 0.0
		if e.boss:
			continue
		if d > DESPAWN or e.global_position.y < -30.0 or e.unseen > RECYCLE_HIDDEN:
			e.queue_free()
	if not enabled:
		return
	_time += delta
	threat = 1 + int(_time / 60.0)
	_spawn_t -= delta
	var max_alive := mini(4 + threat * 3, 24)
	if _spawn_t <= 0.0 and enemies.size() < max_alive:
		_spawn_t = maxf(3.0 - threat * 0.3, 1.0)
		spawn_random()


func spawn_random() -> void:
	var r := randf()
	var kind := "hopper"
	for k in TYPES:
		r -= TYPES[k][4]
		if r <= 0.0:
			kind = k
			break
	# Mostly 0.7-1.3, sometimes a big one; everything grows a little with threat.
	var size := randf_range(0.7, 1.3) + (randf_range(0.5, 0.9) if randf() < 0.12 else 0.0) + (threat - 1) * 0.04
	var pos = _spawn_point(kind == "bee")
	if pos != null:
		spawn(kind, pos, size)


## Somewhere 55-110 m from the car, on open street (or in the air for bees).
func _spawn_point(flying: bool) -> Variant:
	var space := get_world_3d().direct_space_state
	for attempt in 12:
		var a := randf() * TAU
		var d := randf_range(SPAWN_MIN, SPAWN_MAX)
		var p := car.global_position + Vector3(cos(a), 0, sin(a)) * d
		if Vector2(p.x, p.z).length() > 570.0:     # inside the dome
			continue
		var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, 200.0, p.z), Vector3(p.x, -10.0, p.z), 1)
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			continue
		var y: float = hit.position.y
		if flying:
			return Vector3(p.x, y + randf_range(8.0, 14.0), p.z)
		if y < 3.0 and hit.normal.y > 0.8:
			return Vector3(p.x, y + 1.5, p.z)
	return null


## A beast boss (world/wildlife.gd): targetable like any enemy, never recycled.
func add_boss(b: RigidBody3D) -> void:
	add_child(b)
	enemies.append(b)


func spawn(kind: String, pos: Vector3, size: float) -> Node:
	var t: Array = TYPES[kind]
	var e: RigidBody3D = (t[0] as GDScript).new()
	e.size = size
	e.max_hp = t[1] * size * size * (1.0 + 0.15 * (threat - 1))
	e.contact_damage = t[2] * size
	e.points = int(t[3] * size * size)
	e.car = car
	e.combat = combat
	e.position = pos
	add_child(e)
	enemies.append(e)
	combat.on_enemy_spawned(e)
	return e
