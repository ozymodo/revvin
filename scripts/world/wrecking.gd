extends Node3D
## Semi-destruction for the whole world:
##   MEGA-BLOCKS  big voxel parking structures, five floors of open decks
##                behind huge glass window bands, ramps up through the
##                floors to the roof. Crash through the glass, drive every
##                floor, blast holes in the concrete (world/voxels.gd).
##   CRATES       stacks of breakable crates all over the place (some hide
##                an air or battery pickup).
##   TOWERS       the city's towers chip and crack where they're hit (car,
##                explosions, enemies); take enough out of one and it comes
##                down in a cloud of dust and tumbling voxels.
## Trees, rocks, bushes, lamps, pylons and SKYWAY pillars are in
## world/destruction.gd; this forwards blasts and impacts to it too.
##
## Breaking through things is never a crash: smashing costs a little speed.

signal smashed(what: String, at: Vector3)
signal tower_down(rect: Rect2)      # whatever stood on its roof comes down with it

const Voxels := preload("res://scripts/world/voxels.gd")
const Debris := preload("res://scripts/world/debris.gd")
const City := preload("res://scripts/world/city.gd")

const CELL := 2.5                   # mega-block grid
const NX := 24
const NZ := 16
const FLOORS := 5
const FLOOR_H := 6.0
const SLOW := [0.03, 0.003, 0.0, 0.0015, 0.05]    # share of speed lost per cell, by voxel kind
const TOWER_HP_BASE := 1500.0
const TOWER_HP_PER_M := 30.0

var debris: Debris
var car: RigidBody3D
var tricks: Node
var fx: Node
var sfx: Node
var destruction: Node
var pickups: Node
var city: Node3D
var structures: Array = []          # voxels.gd nodes
var megablocks: Array[Rect2] = []   # footprints (x, z, w, d)
var mega_spots: Array = []          # [centre] picked before the city is built
var case_spots: Array = []          # weapon cases on the roofs: [pos, size]
var pickup_spots: Array = []        # [pos, air_pickups kind] on the floors
var _towers := {}                   # body -> {rect, h, hp, max, body, cd}
var _collapsing: Array = []
var _panel_mesh: BoxMesh
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	debris = Debris.new()
	debris.name = "Debris"
	add_child(debris)
	_rng.seed = 5150


# ------------------------------------------------------------------ building the world

## Before the city is built: picks blocks for the mega-blocks (clear of the
## stunt features and the SKYWAY) and returns their footprints to keep free.
func plan_megablocks(level: Node3D, course_rects: Array[Rect2], count := 3) -> Array[Rect2]:
	var out: Array[Rect2] = []
	var w := NX * CELL
	var d := NZ * CELL
	for cx in [75.0, -75.0, 225.0, -225.0]:
		for cz in [-75.0, 225.0, 75.0, -225.0]:
			if out.size() >= count:
				break
			var r := Rect2(cx - w * 0.5 - 12.0, cz - d * 0.5 - 18.0, w + 24.0, d + 36.0)
			var ok := true
			for q in level.RESERVED:
				if r.intersects(q):
					ok = false
			for q in course_rects:
				if r.intersects(q):
					ok = false
			for q in out:
				if r.intersects(q):
					ok = false
			if ok:
				out.append(r)
				mega_spots.append(Vector3(cx, 0, cz))
	megablocks = out
	return out


func build(level: Node3D) -> void:
	city = level.city
	for c in mega_spots:
		_megablock(level, c)
	_crates(level)
	for tw in level.city.towers:
		if tw.size() > 2 and tw[2] != null:
			var hp: float = TOWER_HP_BASE + tw[1] * TOWER_HP_PER_M
			_towers[tw[2]] = {"rect": tw[0], "h": tw[1], "hp": hp, "max": hp, "body": tw[2], "cd": 0.0}


## A five-storey voxel parking structure, NX x NZ cells of CELL metres.
func _megablock(level: Node3D, centre: Vector3) -> void:
	var v := Voxels.new()
	v.debris = debris
	v.position = centre - Vector3(NX * CELL * 0.5, 0, NZ * CELL * 0.5)
	add_child(v)
	var ramps := []                 # [floor, k0, i_start, i_end]
	for f in FLOORS:
		if f % 2 == 0:
			ramps.append([f, 2, 3, 11])
		else:
			ramps.append([f, NZ - 4, 20, 12])
	var hole := func(f: int, i: int, k: int) -> bool:
		# Holes in the slab of floor f above the ramp coming up from f-1.
		for r in ramps:
			if r[0] != f - 1 or k < r[1] or k > r[1] + 1:
				continue
			var lo: int = mini(r[2], r[3])
			var hi: int = maxi(r[2], r[3])
			if i < lo or i >= hi:
				continue
			var s: float = (float(i) + 0.5 - r[2]) / (r[3] - r[2])
			var ys := (f - 1) * FLOOR_H + (0.8 if f - 1 > 0 else 0.0)
			var ye := f * FLOOR_H + 0.8
			if lerpf(ys, ye, clampf(s, 0.0, 1.0)) > f * FLOOR_H - 2.2:
				return true
		return false
	var on_ramp_band := func(f: int, k: int) -> bool:
		for r in ramps:
			if r[0] == f and k >= r[1] and k <= r[1] + 1:
				return true
		return false
	for f in FLOORS + 1:
		var y0 := f * FLOOR_H
		for i in NX:
			for k in NZ:
				var x := (i + 0.5) * CELL
				var z := (k + 0.5) * CELL
				var edge := i == 0 or i == NX - 1 or k == 0 or k == NZ - 1
				if f > 0 and not hole.call(f, i, k):
					var ci: int = v.pos.size()
					v.add_cell(Vector3i(i, f * 3, k), Vector3(x, y0 + 0.4, z), Vector3(CELL, 0.8, CELL), Voxels.Kind.SLAB)
					# Strip lights under the deck light the floor below (and go with it).
					if i % 8 == 4 and (k == 5 or k == NZ - 6):
						_ceiling_light(v, ci, Vector3(x, y0 - 0.05, z), f < FLOORS)
				if f == FLOORS:
					if edge and (i + k) % 3 != 0:      # roof parapet with gaps
						v.add_cell(Vector3i(i, f * 3 + 1, k), Vector3(x, y0 + 1.3, z), Vector3(CELL, 1.0, CELL), Voxels.Kind.CONCRETE)
					continue
				var pillar := false
				if edge:
					pillar = (k % 4 == 0) if (i == 0 or i == NX - 1) else (i % 4 == 0)
				elif i % 6 == 3 and k % 5 == 2 and not on_ramp_band.call(f, k):
					pillar = true
				var entrance := f == 0 and edge and ((k == 0 or k == NZ - 1) and i >= 10 and i <= 13 or (i == 0 or i == NX - 1) and k >= 6 and k <= 9)
				# Two wall rows between this deck and the next slab.
				var base := y0 + (0.8 if f > 0 else 0.0)
				var row_h := (FLOOR_H - (base - y0)) * 0.5
				for row in 2:
					var cy := base + row_h * (row + 0.5)
					var g := Vector3i(i, f * 3 + 1 + row, k)
					if pillar:
						var w := CELL if edge else CELL * 0.6
						v.add_cell(g, Vector3(x, cy, z), Vector3(w, row_h, w), Voxels.Kind.CONCRETE)
					elif edge and not entrance:
						# Big windows: a glass pane in the wall plane.
						var thin := Vector3(CELL, row_h, 0.25) if (k == 0 or k == NZ - 1) else Vector3(0.25, row_h, CELL)
						v.add_cell(g, Vector3(x, cy, z), thin, Voxels.Kind.GLASS)
	v.finish()
	structures.append(v)
	# The ramps between floors (solid), from each floor's deck to the next.
	var s = level.surface("deck")
	for r in ramps:
		var f: int = r[0]
		var ys := f * FLOOR_H + (0.8 if f > 0 else 0.0)
		var ye := (f + 1) * FLOOR_H + 0.8
		var x0: float = v.position.x + r[2] * CELL
		var x1: float = v.position.x + r[3] * CELL
		var z0: float = v.position.z + r[1] * CELL
		var z1: float = z0 + 2.0 * CELL
		var a := Vector3(x0, ys, z0)
		var b := Vector3(x1, ye, z0)
		var n := (Vector3(x1 - x0, ye - ys, 0).cross(Vector3(0, 0, 1)) * signf(x1 - x0)).normalized()
		if n.y < 0.0:
			n = -n
		s.grid([[a, Vector3(x0, ys, z1)], [b, Vector3(x1, ye, z1)]], [n, n])
		s.grid([[a - Vector3.UP * 0.3, Vector3(x0, ys - 0.3, z1)], [b - Vector3.UP * 0.3, Vector3(x1, ye - 0.3, z1)]], [-n, -n])
	s.finish()
	# A kicker aimed at the second-floor windows, a weapon case on the roof,
	# crates and a pickup inside.
	level.kicker(centre + Vector3(0, 0.02, NZ * CELL * 0.5 + 22.0), 0.0, 10.0, 16.0, 3.4, "ramp")
	case_spots.append([centre + Vector3(NX * CELL * 0.25, FLOORS * FLOOR_H + 0.8, 0), "large"])
	for f in [1, 3]:
		_crate_stack(centre + Vector3(-NX * CELL * 0.25, f * FLOOR_H + 0.8, 4.0), 3, 2)
	for f in FLOORS:
		pickup_spots.append([centre + Vector3(NX * CELL * 0.2 * (1 if f % 2 == 0 else -1), f * FLOOR_H + (0.8 if f > 0 else 0.0) + 1.2, 3.0), f % 3])
	_label(centre + Vector3(0, FLOORS * FLOOR_H + 6.0, 0), "MEGA-BLOCK")


func _ceiling_light(v: Node3D, cell: int, at: Vector3, lamp: bool) -> void:
	if _panel_mesh == null:
		_panel_mesh = BoxMesh.new()
		_panel_mesh.size = Vector3(2.0, 0.08, 0.5)
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(1.0, 0.95, 0.85)
		m.emission_enabled = true
		m.emission = Color(1.0, 0.9, 0.75)
		m.emission_energy_multiplier = 3.0
		_panel_mesh.material = m
	var panel := MeshInstance3D.new()
	panel.mesh = _panel_mesh
	panel.position = at
	panel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	v.add_child(panel)
	v.attach(cell, panel)
	if lamp:
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.88, 0.7)
		l.light_energy = 1.6
		l.omni_range = 16.0
		l.position = at + Vector3.DOWN * 0.4
		v.add_child(l)
		Lod.draw_distance(l, 150.0)
		v.attach(cell, l)


func _label(at: Vector3, text: String) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = 140
	l.pixel_size = 0.02
	l.outline_size = 16
	l.modulate = Color(1.0, 0.75, 0.35)
	l.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	l.shaded = false
	l.position = at
	add_child(l)


## Crate stacks along the sidewalks and round the parks.
func _crates(level: Node3D) -> void:
	var city = level.city
	var n := 0
	for attempt in 300:
		if n >= 40:
			break
		var a: float = City.AVENUES[_rng.randi() % City.AVENUES.size()]
		var t := _rng.randf_range(-370.0, 370.0)
		var side := 1.0 if _rng.randf() < 0.5 else -1.0
		var axis := _rng.randi() % 2
		var off := a + side * _rng.randf_range(9.0, 13.0)
		var p := Vector3(off, 0, t) if axis == 0 else Vector3(t, 0, off)
		if level._reserved(p.x, p.z, 4.0) or city.masked(p.x, p.z) or city.in_building(p.x, p.z, 2.0):
			continue
		_crate_stack(p, _rng.randi_range(1, 3), _rng.randi_range(1, 3))
		n += 1
	for spot in [Vector3(30, 0, 470), Vector3(-30, 0, 470), Vector3(120, 0, 540), Vector3(-200, 0, 450),
			Vector3(470, 0, 140), Vector3(-430, 0, 60), Vector3(100, 0, -420), Vector3(-100, 0, -470)]:
		_crate_stack(spot, 3, 3)


## A stack of `w` x `w` crates, `h` high. Each crate is 2x2x2 voxels.
func _crate_stack(at: Vector3, w: int, h: int) -> void:
	var v := Voxels.new()
	v.debris = debris
	v.sub_cubes = 1
	v.position = at - Vector3(w * 0.6, 0, w * 0.6)
	add_child(v)
	var cell := 0.6
	for x in w * 2:
		for z in w * 2:
			for y in h * 2:
				# Pyramid-ish: upper crates only over the middle.
				var level_up := y / 2
				var cx := x / 2
				var cz := z / 2
				if level_up > 0 and (cx < level_up / 2 or cz < level_up / 2 or cx >= w - level_up / 2 or cz >= w - level_up / 2) and w > 1:
					continue
				v.add_cell(Vector3i(x, y, z), Vector3((x + 0.5) * cell, (y + 0.5) * cell, (z + 0.5) * cell), Vector3.ONE * (cell - 0.02), Voxels.Kind.CRATE)
	v.finish()
	structures.append(v)
	# Some hide a pickup (state in a dictionary: lambdas capture by value).
	var loot := {"left": _rng.randf() < 0.3, "kind": _rng.randi() % 3}
	v.cell_broken.connect(func(at2: Vector3, _k: int) -> void:
		if loot.left and pickups:
			loot.left = false
			pickups.spawn(at2 + Vector3.UP * 1.2, loot.kind)
			smashed.emit("loot", at2))


# ------------------------------------------------------------------ smashing

func _physics_process(delta: float) -> void:
	_update_collapses(delta)
	if car == null:
		return
	for k in _towers:
		_towers[k].cd -= delta
	var v: Vector3 = car.linear_velocity
	var speed := v.length()
	if speed < 1.5 or car.grinding:
		return
	# The car as a capsule from tail to just ahead of the nose.
	var p0: Vector3 = car.global_position
	var fwd: Vector3 = -car.global_basis.z
	var tail := p0 - fwd * 2.2 + Vector3.UP * 0.6
	var nose := p0 + fwd * 2.4 + Vector3.UP * 0.6 + v * delta * 3.0
	var box := AABB(p0, Vector3.ZERO).grow(6.0 + speed * delta * 3.0)
	var slow := 0.0
	for s in structures:
		if not is_instance_valid(s) or not s.world_aabb().grow(1.0).intersects(box):
			continue
		var hits: Array = s.cells_on_segment(tail, nose, 0.95, p0.y + 0.25)
		var broke := []
		for i in hits:
			var k: int = s.kind[i]
			if speed >= Voxels.KINDS[k][1]:
				broke.append(i)
				slow += SLOW[k]
		if not broke.is_empty():
			s.break_cells(broke, v * 1.05 + Vector3.UP * 3.0)     # flung ahead, not rammed through
			_smash_feedback(car.global_position + fwd * 2.4 + Vector3.UP * 0.6, broke.size(), s.kind[broke[0]])
	if slow > 0.0:
		car.linear_velocity *= 1.0 - minf(slow, 0.15)
		if tricks:
			tricks.ignore_crash(0.4)
	# Towers: hitting one hard chips it (and wears it down).
	if speed > 14.0:
		var q := PhysicsRayQueryParameters3D.create(p0 + Vector3.UP * 0.6, p0 + Vector3.UP * 0.6 + v.normalized() * (speed * delta * 3.0 + 2.6), 1, [car.get_rid()])
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		if not hit.is_empty() and _towers.has(hit.collider) and _towers[hit.collider].cd <= 0.0:
			_towers[hit.collider].cd = 0.6
			damage_tower(hit.collider, (speed - 10.0) * (speed - 10.0) * 1.2, hit.position, -v.normalized() * 6.0)


func _smash_feedback(at: Vector3, n: int, k: int) -> void:
	if k == Voxels.Kind.GLASS:
		sfx.glass(at, clampf(n * 0.3, 0.4, 1.0))
	else:
		sfx.crunch(at, clampf(n * 0.2, 0.3, 1.0))
	fx.punch(clampf(n * 0.05, 0.08, 0.35))
	if tricks:
		tricks.smash_points(10 * n)
	smashed.emit(["concrete", "glass", "slab", "crate", "steel"][k], at)


## Blasts: everything in range takes it (voxels, towers, trees and props).
func explode(at: Vector3, radius: float, power: float) -> void:
	for s in structures:
		if is_instance_valid(s) and s.world_aabb().grow(radius).has_point(at):
			var n: int = s.explode(at, radius, power)
			if n > 0:
				smashed.emit("blast x%d" % n, at)
	for k in _towers:
		var t: Dictionary = _towers[k]
		var r: Rect2 = t.rect
		var c := Vector2(clampf(at.x, r.position.x, r.end.x), clampf(at.z, r.position.y, r.end.y))
		var d := Vector2(at.x, at.z).distance_to(c)
		if d < radius and at.y < t.h:
			damage_tower(k, power * 90.0 * (1.0 - d / radius), Vector3(c.x, maxf(at.y, 1.0), c.y), (Vector3(c.x, at.y, c.y) - at).normalized() * 5.0)
	if destruction:
		destruction.blast(at, radius, power)


## An enemy (or anything) slamming into the world.
func impact(at: Vector3, _vel: Vector3, power: float) -> void:
	explode(at, 1.5 + power, power * 2.2)


# ------------------------------------------------------------------ towers

func damage_tower(body: Node, amount: float, at: Vector3, push: Vector3) -> void:
	if not _towers.has(body):
		return
	var t: Dictionary = _towers[body]
	t.hp -= amount
	# Chips fly off where it was hit, and a scorch mark.
	var n := clampi(int(amount / 120.0), 2, 14)
	debris.burst(at, n, _rng.randf_range(0.5, 1.1), Color(0.42, 0.42, 0.4), push, 5.0, Vector3.ONE * 0.8)
	fx.dust(at, clampf(amount / 800.0, 0.4, 1.4))
	sfx.crunch(at, clampf(amount / 600.0, 0.3, 1.0))
	if t.hp <= 0.0:
		_collapse(t)
	else:
		smashed.emit("tower hit", at)


## The nuke's shockwave: brings down up to `max_n` of the standing towers
## whose footprint it has reached (`r` m from `at`), nearest first.
## Returns how many came down.
func flatten(at: Vector3, r: float, max_n: int) -> int:
	var hit: Array = []
	for k in _towers:
		var t: Dictionary = _towers[k]
		var c: Vector2 = (t.rect as Rect2).get_center()
		var d := Vector2(at.x, at.z).distance_to(c)
		if d < r:
			hit.append([d, t])
	hit.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for i in mini(hit.size(), max_n):
		_collapse(hit[i][1])
	return mini(hit.size(), max_n)


## Down it comes: it sinks into its own dust, shedding voxels, and is gone.
func _collapse(t: Dictionary) -> void:
	var body: Node3D = t.body
	_towers.erase(body)
	for c in body.get_children():
		if c is CollisionShape3D:
			(c as CollisionShape3D).set_deferred("disabled", true)
	_collapsing.append({"body": body, "h": t.h, "rect": t.rect, "t": 0.0, "y0": body.position.y, "spawn": 0.0,
		"tilt": Vector3(_rng.randf_range(-0.1, 0.1), 0, _rng.randf_range(-0.1, 0.1))})
	var r: Rect2 = t.rect
	var c3 := Vector3(r.get_center().x, 2.0, r.get_center().y)
	# Its holo sign goes too; rooftop trees and cases are handled by listeners.
	if city:
		for n in city.get_children():
			if n is Label3D and r.grow(1.5).has_point(Vector2((n as Node3D).position.x, (n as Node3D).position.z)):
				n.queue_free()
	if destruction:
		destruction.remove_in(r, 2.0)
	tower_down.emit(r)
	fx.dust(c3, 2.5)
	fx.punch(0.8 if car and car.global_position.distance_to(c3) < 120.0 else 0.2)
	sfx.boom(c3)
	if tricks:
		tricks.smash_points(2000)
	smashed.emit("tower down", c3)


func _update_collapses(delta: float) -> void:
	var keep: Array = []
	for c in _collapsing:
		var body: Node3D = c.body
		if not is_instance_valid(body):
			continue
		c.t += delta
		var dur := 3.5
		var k := clampf(c.t / dur, 0.0, 1.0)
		body.position.y = c.y0 - c.h * k * k
		body.rotation = c.tilt * k
		c.spawn -= delta
		if c.spawn <= 0.0:
			c.spawn = 0.12
			var r: Rect2 = c.rect
			var ground := Vector3(_rng.randf_range(r.position.x, r.end.x), 1.0, _rng.randf_range(r.position.y, r.end.y))
			debris.burst(ground, 4, _rng.randf_range(1.2, 2.2), Color(0.45, 0.45, 0.43), Vector3.UP * 4.0, 7.0, Vector3(r.size.x * 0.3, 1.0, r.size.y * 0.3))
			if _rng.randf() < 0.4:
				fx.dust(ground, 1.2)
		if c.t < dur:
			keep.append(c)
		else:
			body.queue_free()
	_collapsing = keep
