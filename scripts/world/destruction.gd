extends Node3D
## Smashable trees, bushes, ferns and rubble rocks. How much damage a hit
## does depends on how fast the car is going:
##   trees   slow: the tree shakes and drops leaves (enough knocks break it)
##           TREE_SNAP+: it snaps at the base and topples, leaving a stump
##           TREE_FLING+: it's torn out and flung along with you
##   bushes  slow: flattened; BUSH_SHRED+: shredded into a spray of leaves
##   rocks   slow: chips fly off; ROCK_CRACK+: it cracks into a few chunks;
##           ROCK_SHATTER+: it bursts into many, flung hard, in a cloud of dust
## Broken pieces are real physics bodies (they tumble, and the car can knock
## them about) that fade after a while. Nature grows back after REGROW
## seconds, once you're away.
##
##   poles   lamps (LAMP_SNAP+), energy pylons (PYLON_SNAP+) and SKYWAY
##           pillars (PILLAR_SNAP+) snap off and come down as a column of
##           voxel blocks; slower knocks just shake them
## Blasts (blast()) break everything in range by power.
##
## Hits are found ahead of the car each step, so a fast car breaks a tree
## before slamming into its trunk (the trunk collider is switched off)
## instead of stopping dead: smashing through is never a crash.

const CELL := 12.0
const CAR_HALF_W := 1.0             # the car is checked as a capsule along its length
const CAR_REAR := 2.2
const CAR_NOSE := 2.4
const TREE_SNAP := 9.0              # m/s
const TREE_FLING := 22.0
const ROCK_CRACK := 6.0
const ROCK_SHATTER := 16.0
const BUSH_SHRED := 14.0
const LAMP_SNAP := 6.0
const PYLON_SNAP := 18.0
const PILLAR_SNAP := 22.0
const POLES := {"lamp": [LAMP_SNAP, 0.25, 6.5, 1.0, Color(0.22, 0.24, 0.27)],
	"pylon": [PYLON_SNAP, 1.1, 28.0, 3.0, Color(0.3, 0.33, 0.38)],
	"pillar": [PILLAR_SNAP, 1.1, 0.0, 4.0, Color(0.36, 0.37, 0.36)]}   # [snap speed, radius, height, blast power, colour]
const REGROW := 120.0
const PIECE_LIFE := 10.0
const MAX_PIECES := 50
## Broken pieces live on their own physics layer: they collide with the
## world, the car's body and each other, but the car's suspension rays
## (layer 1 only) don't stand on them, so rubble can't flip the car.
const PIECE_LAYER := 8
const SMASH_POINTS := {"tree": 60, "rock": 40, "bush": 10, "fern": 5, "lamp": 30, "pylon": 150, "pillar": 200}

enum State { INTACT, DAMAGED, GONE }

signal smashed_object(kind: String, outcome: String, speed: float)

var car: RigidBody3D
var tricks: Node
var fx: Node
var sfx: Node
var smashed := 0
var debris: Node                    # world/debris.gd (voxel cubes)

## [mm (or a Node3D), index, xf (at its base), kind, trunk, state, timer, hp,
##  radius, height, stump, cooldown, original instance transform]
var _entries: Array = []
var _grid := {}
var _pieces: Array = []             # [body, age]
var _wobble: Array = []             # [entry, t, axis]
var _grow: Array = []               # [entry, t]
var _broken: Array = []             # entries waiting to regrow
## Seeded, so smashing plays out the same every run (pieces can hit the
## car, and the scripted tests must stay repeatable).
var _rng := RandomNumberGenerator.new()
var _stump_mesh: CylinderMesh
var _bark: StandardMaterial3D


func setup(city: Node) -> void:
	_rng.seed = 4242
	setup_entries(city.destructibles)
	_stump_mesh = CylinderMesh.new()
	_stump_mesh.top_radius = 0.4
	_stump_mesh.bottom_radius = 0.5
	_stump_mesh.height = 0.7
	_stump_mesh.radial_segments = 8
	_bark = StandardMaterial3D.new()
	_bark.albedo_color = Color(0.3, 0.22, 0.14)
	_bark.roughness = 0.95


func setup_entries(list: Array) -> void:
	for d in list:
		var xf: Transform3D = d[2]
		var s := xf.basis.x.length()
		var kind: String = d[3]
		var r: float
		var h: float
		if POLES.has(kind):
			r = POLES[kind][1]
			h = POLES[kind][2] if kind != "pillar" else xf.basis.y.length()
			if kind == "pillar":
				xf = Transform3D(Basis(), xf.origin - Vector3.UP * h * 0.5)   # its base
		else:
			r = {"tree": 0.5, "bush": 0.8, "fern": 0.55, "rock": 0.75}[kind] * s
			h = {"tree": 7.0, "bush": 1.6, "fern": 1.0, "rock": 1.1}[kind] * s
		var hp: float = 30.0 if kind == "tree" else 15.0
		var e := [d[0], d[1], xf, kind, d[4], State.INTACT, 0.0, hp, r, h, null, 0.0, d[2]]
		_entries.append(e)
		var key := Vector2i(floori(xf.origin.x / CELL), floori(xf.origin.z / CELL))
		if not _grid.has(key):
			_grid[key] = []
		_grid[key].append(e)


func _physics_process(delta: float) -> void:
	if car == null:
		return
	_age_pieces(delta)
	_regrow(delta)
	var v: Vector3 = car.linear_velocity
	var speed := v.length()
	if speed < 2.0 or car.grinding:
		return
	# The car as a capsule from its tail to just ahead of its nose (looking a
	# little ahead at speed, so a tree breaks before the trunk stops you).
	var p0: Vector3 = car.global_position
	var fwd: Vector3 = -car.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.1 else Vector3.FORWARD
	var tail := p0 - fwd * CAR_REAR
	var nose := p0 + fwd * CAR_NOSE + v * delta * 3.0
	var c := Vector2i(floori(p0.x / CELL), floori(p0.z / CELL))
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var key := c + Vector2i(dx, dz)
			if not _grid.has(key):
				continue
			for e in _grid[key]:
				if e[5] == State.GONE:
					continue
				e[11] -= delta
				var o: Vector3 = (e[2] as Transform3D).origin
				# (A pillar's top holds up the SKYWAY deck: driving on the deck
				# over it must not count.)
				if p0.y > o.y + e[9] - (2.5 if e[3] == "pillar" else 0.0) or p0.y < o.y - 1.5:
					continue
				var q := Geometry3D.get_closest_point_to_segment(Vector3(o.x, p0.y, o.z), tail, nose)
				if Vector2(q.x - o.x, q.z - o.z).length() < CAR_HALF_W + e[8] and e[11] <= 0.0:
					e[11] = 0.5
					_hit(e, v, speed)


## Places one extra smashable object (tests): its own one-instance MultiMesh,
## and a trunk collider for a tree.
func add_object(kind: String, mesh: Mesh, xf: Transform3D) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = 1
	mm.set_instance_transform(0, xf)
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	add_child(mmi)
	var trunk: CollisionShape3D = null
	if kind == "tree":
		var body := StaticBody3D.new()
		trunk = CollisionShape3D.new()
		var sh := CylinderShape3D.new()
		var s := xf.basis.x.length()
		sh.radius = 0.45 * s
		sh.height = 6.0 * s
		trunk.shape = sh
		trunk.position = xf.origin + Vector3.UP * 3.0 * s
		body.add_child(trunk)
		add_child(body)
	setup_entries([[mm, 0, xf, kind, trunk]])


func _hit(e: Array, v: Vector3, speed: float) -> void:
	var o: Vector3 = (e[2] as Transform3D).origin
	var dir := Vector3(v.x, 0, v.z).normalized() if Vector2(v.x, v.z).length() > 0.5 else Vector3.FORWARD
	match e[3]:
		"tree":
			e[7] -= speed * 1.5
			if speed >= TREE_SNAP or e[7] <= 0.0:
				_break_tree(e, v, speed, dir)
			else:
				_wobble.append([e, 0.0, Vector3.UP.cross(dir)])
				fx.leaves(o + Vector3.UP * e[9] * 0.7, _leaf_color(e), 0.3, Vector3.ZERO)
				sfx.thunk(0.25)
				smashed_object.emit("tree", "shaken", speed)
		"bush", "fern":
			if speed >= BUSH_SHRED or (e[5] == State.DAMAGED and speed > 8.0):
				_set_instance(e, Transform3D(Basis().scaled(Vector3.ZERO), o))
				e[5] = State.GONE
				e[6] = REGROW
				_mark_broken(e)
				fx.leaves(o + Vector3.UP * 0.6, _leaf_color(e), clampf(speed / 18.0, 0.5, 1.4), v * 0.5)
				_scored(e)
				smashed_object.emit(e[3], "shredded", speed)
			else:
				# Flattened: squashed down and spread out.
				var xf: Transform3D = e[2]
				_set_instance(e, Transform3D(xf.basis.scaled(Vector3(1.3, 0.25, 1.3)), o))
				e[5] = State.DAMAGED
				e[6] = REGROW
				e[11] = 2.5                     # a fresh hit is needed to shred it
				_mark_broken(e)
				fx.leaves(o + Vector3.UP * 0.5, _leaf_color(e), 0.35, v * 0.2)
				smashed_object.emit(e[3], "flattened", speed)
		"lamp", "pylon", "pillar":
			if speed >= POLES[e[3]][0]:
				_topple(e, v * 0.5, dir)
				car.linear_velocity *= 0.92 if e[3] == "lamp" else 0.8
				if tricks:
					tricks.ignore_crash(0.6)
				smashed_object.emit(e[3], "snapped", speed)
			else:
				_wobble.append([e, 0.0, Vector3.UP.cross(dir) * 0.3])
				if e[3] != "lamp":
					_chip(o + Vector3.UP * 1.0 + dir * -e[8], e, 3)
				sfx.thunk(0.3)
				smashed_object.emit(e[3], "shaken", speed)
		"rock":
			if speed < ROCK_CRACK:
				fx.debris(o + Vector3.UP * 0.5, Color(0.42, 0.4, 0.37), Color(0.7, 0.65, 0.55), 0.3)
				sfx.crunch(o, 0.3)
				smashed_object.emit("rock", "chipped", speed)
				return
			var shatter := speed >= ROCK_SHATTER
			_set_instance(e, Transform3D(Basis().scaled(Vector3.ZERO), o))
			e[5] = State.GONE
			e[6] = REGROW
			_mark_broken(e)
			_rock_chunks(e, v, shatter)
			if debris:
				debris.burst(o + Vector3.UP * 0.6, 8 if shatter else 4, 0.35 * xf_scale(e), Color(0.42, 0.4, 0.37), v * 0.4, 6.0 if shatter else 3.0)
			fx.dust(o + Vector3.UP * 0.6, 1.4 if shatter else 0.7)
			fx.debris(o + Vector3.UP * 0.6, Color(0.42, 0.4, 0.37), Color(0.75, 0.7, 0.6), 1.2 if shatter else 0.6)
			sfx.crunch(o, 1.0 if shatter else 0.6)
			fx.punch(0.25 if shatter else 0.12)
			# Rocks are hard: they cost a little speed.
			car.linear_velocity *= 0.95 if shatter else 0.9
			_scored(e)
			smashed_object.emit("rock", "shattered" if shatter else "cracked", speed)


func _break_tree(e: Array, v: Vector3, speed: float, dir: Vector3, by_car := true) -> void:
	var xf: Transform3D = e[2]
	var o := xf.origin
	var s := xf.basis.x.length()
	var fling := speed >= TREE_FLING
	_set_instance(e, Transform3D(Basis().scaled(Vector3.ZERO), o))
	e[5] = State.GONE
	e[6] = REGROW
	_mark_broken(e)
	if e[4]:
		(e[4] as CollisionShape3D).set_deferred("disabled", true)
	if tricks and by_car:
		tricks.ignore_crash(0.6)
	# The tree itself becomes a physics body and goes over.
	var body := RigidBody3D.new()
	body.mass = 250.0 * s
	body.collision_layer = PIECE_LAYER
	body.collision_mask = 1 | 4 | PIECE_LAYER
	var mi := MeshInstance3D.new()
	mi.mesh = (e[0] as MultiMesh).mesh
	mi.scale = Vector3.ONE * s
	body.add_child(mi)
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.45 * s
	cap.height = 6.0 * s
	cs.shape = cap
	cs.position = Vector3.UP * 3.2 * s
	body.add_child(cs)
	body.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	body.center_of_mass = Vector3.UP * 2.5 * s
	add_child(body)
	# Snapped: lifted off the stump a touch and tipped over; flung: thrown.
	body.global_transform = Transform3D(xf.basis.orthonormalized(), o + Vector3.UP * (0.8 if not fling else 1.2))
	body.linear_velocity = v * (0.75 if fling else 0.3) + Vector3.UP * (5.0 if fling else 0.5)
	body.angular_velocity = Vector3.UP.cross(dir) * (3.5 if fling else 1.2) + Vector3(_rng.randf_range(-0.5, 0.5), _rng.randf_range(-1, 1), _rng.randf_range(-0.5, 0.5))
	_add_piece(body)
	# A stump stays where it stood.
	var stump := MeshInstance3D.new()
	stump.mesh = _stump_mesh
	stump.material_override = _bark
	stump.scale = Vector3(s, s * (0.6 if fling else 1.0), s)
	stump.position = o + Vector3.UP * 0.35 * s
	add_child(stump)
	e[10] = stump
	fx.leaves(o + Vector3.UP * 4.5 * s, _leaf_color(e), 1.4 if fling else 0.9, v * 0.4)
	if debris:
		debris.burst(o + Vector3.UP * 4.5 * s, 7 if fling else 4, 0.5 * s, _leaf_color(e), v * 0.3, 4.0, Vector3.ONE * 1.4 * s)
		debris.burst(o + Vector3.UP * 0.6, 2, 0.3 * s, Color(0.36, 0.25, 0.15), v * 0.4, 3.0)
	fx.debris(o + Vector3.UP * 0.8, Color(0.36, 0.25, 0.15), Color(0.55, 0.42, 0.25), 0.8 if fling else 0.5)
	sfx.crunch(o, 1.0)
	sfx.thunk(0.6)
	fx.punch(0.35 if fling else 0.2)
	if by_car:
		car.linear_velocity *= 0.93 if fling else 0.85
	_scored(e)
	smashed_object.emit("tree", "flung" if fling else "snapped", speed)


## A pole snaps off and comes down as a column of voxel blocks.
func _topple(e: Array, v: Vector3, dir: Vector3) -> void:
	var o: Vector3 = (e[2] as Transform3D).origin
	_hide(e)
	e[5] = State.GONE
	e[6] = REGROW
	_mark_broken(e)
	if e[4]:
		(e[4] as CollisionShape3D).set_deferred("disabled", true)
	var h: float = e[9]
	var r: float = e[8]
	var col: Color = POLES[e[3]][4]
	if debris:
		var block := clampf(r * 1.4, 0.35, 1.8)
		var n := clampi(int(h / block), 3, 16)
		for k in n:
			var y := (k + 0.5) * h / n
			# Higher blocks topple further, away from the hit.
			var tip := dir * (1.0 + y * 0.35) + Vector3.UP * (1.0 - y / h) * 2.0
			debris.cube(o + Vector3.UP * y, Vector3(block, h / n, block), col, v * (0.3 + 0.4 * (1.0 - y / h)) + tip, 0.0)
		if e[3] == "lamp":
			debris.cube(o + Vector3.UP * h, Vector3.ONE * 0.4, Color(1.0, 0.85, 0.5), v * 0.5 + dir * 3.0, 3.0)
	fx.dust(o + Vector3.UP * 0.8, 0.6 + r)
	fx.debris(o + Vector3.UP * 1.0, col, Color(0.8, 0.8, 0.75), 0.5 + r * 0.4)
	if e[3] != "lamp":
		fx.sparks(o + Vector3.UP * 1.0, Color(0.6, 0.85, 1.0), 0.6, Vector3.UP)
	sfx.crunch(o, 0.7 + r * 0.25)
	fx.punch(0.1 + r * 0.15)
	var stump := MeshInstance3D.new()
	var sm := CylinderMesh.new()
	sm.top_radius = r
	sm.bottom_radius = r * 1.1
	sm.height = 0.6
	sm.radial_segments = 8
	stump.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	stump.material_override = mat
	stump.position = o + Vector3.UP * 0.3
	add_child(stump)
	e[10] = stump
	_scored(e)


## A few voxel chips knocked off.
func _chip(at: Vector3, e: Array, n: int) -> void:
	if debris:
		debris.burst(at, n, 0.3, _leaf_color(e) if POLES.has(e[3]) else Color(0.42, 0.4, 0.37), Vector3.UP * 2.0, 3.0)


## Explosions: everything within `radius` that the blast is strong enough for.
func blast(at: Vector3, radius: float, power: float) -> void:
	var c := Vector2i(floori(at.x / CELL), floori(at.z / CELL))
	var reach := ceili(radius / CELL)
	for dx in range(-reach, reach + 1):
		for dz in range(-reach, reach + 1):
			var key := c + Vector2i(dx, dz)
			if not _grid.has(key):
				continue
			for e in _grid[key].duplicate():
				if e[5] == State.GONE:
					continue
				var o: Vector3 = (e[2] as Transform3D).origin
				var d: float = Vector2(o.x - at.x, o.z - at.z).length() - e[8]
				if d > radius or at.y < o.y - 3.0 or at.y > o.y + e[9] + 3.0:
					continue
				var p := power * (1.0 - maxf(d, 0.0) / radius)
				var away := Vector3(o.x - at.x, 0, o.z - at.z).normalized()
				var v := away * p * 4.0 + Vector3.UP * p
				match e[3]:
					"tree":
						if p > 1.0:
							_break_tree(e, v, 8.0 + p * 6.0, away, false)
					"bush", "fern":
						if p > 0.4:
							_hide(e)
							e[5] = State.GONE
							e[6] = REGROW
							_mark_broken(e)
							fx.leaves(o + Vector3.UP * 0.6, _leaf_color(e), 0.8, v)
							_scored(e)
					"rock":
						if p > 1.2:
							_hide(e)
							e[5] = State.GONE
							e[6] = REGROW
							_mark_broken(e)
							_rock_chunks(e, v, true)
							if debris:
								debris.burst(o + Vector3.UP * 0.6, 6, 0.35 * xf_scale(e), Color(0.42, 0.4, 0.37), v, 6.0)
							_scored(e)
					_:
						if p >= POLES[e[3]][3]:
							_topple(e, v, away)
						elif p > 0.5:
							_chip(o + Vector3.UP * minf(at.y - o.y, e[9]), e, 2)


## Everything inside `r` standing higher than `min_y` is gone for good (a
## tower came down under it).
func remove_in(r: Rect2, min_y: float) -> void:
	for e in _entries:
		var o: Vector3 = (e[2] as Transform3D).origin
		if o.y > min_y and r.grow(1.0).has_point(Vector2(o.x, o.z)) and e[5] != State.GONE:
			_hide(e)
			e[5] = State.GONE
			e[6] = INF
			if e[4]:
				(e[4] as CollisionShape3D).set_deferred("disabled", true)


func _rock_chunks(e: Array, v: Vector3, shatter: bool) -> void:
	var xf: Transform3D = e[2]
	var o := xf.origin
	var s := xf.basis.x.length()
	var n := _rng.randi_range(6, 9) if shatter else _rng.randi_range(3, 4)
	for k in n:
		var body := RigidBody3D.new()
		var cs_scale := s * (0.32 if shatter else 0.48) * _rng.randf_range(0.7, 1.2)
		body.mass = 60.0 * cs_scale
		body.collision_layer = PIECE_LAYER
		body.collision_mask = 1 | 4 | PIECE_LAYER
		var mi := MeshInstance3D.new()
		mi.mesh = (e[0] as MultiMesh).mesh
		mi.scale = Vector3.ONE * cs_scale
		body.add_child(mi)
		var cs := CollisionShape3D.new()
		var sh := SphereShape3D.new()
		sh.radius = 0.5 * cs_scale
		cs.shape = sh
		cs.position = Vector3.UP * 0.4 * cs_scale
		body.add_child(cs)
		add_child(body)
		var off := Vector3(_rng.randf_range(-0.6, 0.6), _rng.randf_range(0.2, 0.9), _rng.randf_range(-0.6, 0.6)) * s
		body.global_transform = Transform3D(Basis.from_euler(Vector3(_rng.randf() * TAU, _rng.randf() * TAU, _rng.randf() * TAU)), o + off)
		var spread := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(0.4, 1.2), _rng.randf_range(-1, 1))
		body.linear_velocity = v * (0.55 if shatter else 0.25) + spread * (7.0 if shatter else 2.5)
		body.angular_velocity = Vector3(_rng.randf_range(-8, 8), _rng.randf_range(-8, 8), _rng.randf_range(-8, 8))
		_add_piece(body)


func _mark_broken(e: Array) -> void:
	if not _broken.has(e):
		_broken.append(e)


func _scored(e: Array) -> void:
	smashed += 1
	if tricks:
		tricks.smash_points(SMASH_POINTS.get(e[3], 10))


func _add_piece(body: RigidBody3D) -> void:
	_pieces.append([body, 0.0])
	while _pieces.size() > MAX_PIECES:
		var old: Array = _pieces.pop_front()
		if is_instance_valid(old[0]):
			(old[0] as Node).queue_free()


## Pieces fade out (shrink away) at the end of their life.
func _age_pieces(delta: float) -> void:
	var keep: Array = []
	for pc in _pieces:
		var body: RigidBody3D = pc[0]
		if not is_instance_valid(body):
			continue
		pc[1] += delta
		if pc[1] > PIECE_LIFE:
			body.queue_free()
			continue
		if pc[1] > PIECE_LIFE - 1.0:
			var k := maxf(PIECE_LIFE - pc[1], 0.02)
			for child in body.get_children():
				if child is MeshInstance3D:
					(child as MeshInstance3D).transparency = 1.0 - k
		keep.append(pc)
	_pieces = keep


func _regrow(delta: float) -> void:
	var waiting: Array = []
	for e in _broken:
		if e[5] == State.INTACT:
			continue
		e[6] -= delta
		waiting.append(e)
		if e[6] > 0.0:
			continue
		var o: Vector3 = (e[2] as Transform3D).origin
		if o.distance_to(car.global_position) < 60.0:
			e[6] = 10.0
			continue
		waiting.erase(e)
		e[5] = State.INTACT
		e[7] = 30.0 if e[3] == "tree" else 15.0
		if e[4]:
			(e[4] as CollisionShape3D).set_deferred("disabled", false)
		if e[10]:
			(e[10] as Node).queue_free()
			e[10] = null
		_grow.append([e, 0.0])
		if e[0] is Node3D:
			(e[0] as Node3D).visible = true
	_broken = waiting


func _process(delta: float) -> void:
	# Shaken trees sway back to rest; regrowing things grow back in.
	var keep: Array = []
	for w in _wobble:
		w[1] += delta
		var e: Array = w[0]
		if e[5] == State.GONE:
			continue
		var xf: Transform3D = e[12]
		var ang := sin(w[1] * 11.0) * exp(-w[1] * 3.0) * 0.14
		var o: Vector3 = (e[2] as Transform3D).origin
		var rot := Transform3D(Basis(w[2].normalized(), ang * w[2].length()), Vector3.ZERO)
		_set_instance(e, Transform3D(Basis(), o) * rot * Transform3D(Basis(), -o) * xf)
		if w[1] < 2.0:
			keep.append(w)
		else:
			_set_instance(e, xf)
	_wobble = keep
	var growing: Array = []
	for g in _grow:
		g[1] += delta
		var e: Array = g[0]
		var xf: Transform3D = e[12]
		var o: Vector3 = (e[2] as Transform3D).origin
		var k := smoothstep(0.0, 2.5, g[1])
		_set_instance(e, Transform3D(Basis().scaled(Vector3.ONE * maxf(k, 0.01)), o) * Transform3D(Basis(), -o) * xf)
		if g[1] < 2.5:
			growing.append(g)
	_grow = growing


static func _set_instance(e: Array, xf: Transform3D) -> void:
	if e[0] is MultiMesh:
		(e[0] as MultiMesh).set_instance_transform(e[1], xf)
	elif e[0] is Node3D:
		var n := e[0] as Node3D
		n.visible = xf.basis.x.length() > 0.001
		if n.visible:
			n.transform = xf


static func xf_scale(e: Array) -> float:
	return (e[12] as Transform3D).basis.x.length()


static func _hide(e: Array) -> void:
	_set_instance(e, Transform3D(Basis().scaled(Vector3.ZERO), (e[2] as Transform3D).origin))


static func _leaf_color(e: Array) -> Color:
	if e[3] == "fern":
		return Color(0.25, 0.55, 0.2)
	if POLES.has(e[3]):
		return POLES[e[3]][4]
	return Color(0.22, 0.45, 0.14) if e[3] != "tree" else Color(0.28, 0.5, 0.16)
