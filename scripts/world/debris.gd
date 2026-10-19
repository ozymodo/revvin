extends Node3D
## Voxel debris: everything that breaks throws real tumbling cubes, for a
## chunky 3D-pixel look. Cubes are physics bodies on their own layer (they
## hit the world, the car's body and each other, but the car's suspension
## rays don't stand on them, so rubble can't flip you). The newest MAX
## stay; the rest fade out after LIFE seconds.

const Voxels := preload("res://scripts/world/voxels.gd")

const LAYER := 8
const MAX := 320
const LIFE := 9.0

## Fresh cubes pass through the car for a moment (so smashing through
## something doesn't mean ramming its own rubble), then hit it as usual.
const CAR_GRACE := 0.6

var car: PhysicsBody3D
var _bodies: Array = []             # [body, age, passing the car]
var _meshes := {}
var _mats := {}
var _shapes := {}
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 909


## Throws `n` cubes of edge `size` from around `at` (spread over `extent`),
## moving with `vel` plus a random burst of up to `burst` m/s.
func burst(at: Vector3, n: int, size: float, color: Color, vel: Vector3, burst_speed: float, extent := Vector3.ONE * 0.5, glow := 0.0) -> void:
	for k in n:
		var s := size * _rng.randf_range(0.75, 1.15)
		var p := at + Vector3(_rng.randf_range(-1, 1) * extent.x, _rng.randf_range(-1, 1) * extent.y, _rng.randf_range(-1, 1) * extent.z)
		var dir := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(0.2, 1.2), _rng.randf_range(-1, 1)).normalized()
		cube(p, Vector3.ONE * s, color, vel + dir * _rng.randf_range(0.3, 1.0) * burst_speed, glow)


## One cube (or brick, with a non-uniform size).
func cube(at: Vector3, size: Vector3, color: Color, vel: Vector3, glow := 0.0) -> RigidBody3D:
	var body := RigidBody3D.new()
	body.collision_layer = LAYER
	body.collision_mask = 1 | 4 | LAYER
	# Light, so rubble you drive into skitters away instead of steering you.
	body.mass = clampf(size.x * size.y * size.z * 150.0, 2.0, 300.0)
	var key := size.snapped(Vector3.ONE * 0.05)
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh(key)
	mi.material_override = _mat(color, glow)
	body.add_child(mi)
	var cs := CollisionShape3D.new()
	cs.shape = _shape(key)
	body.add_child(cs)
	add_child(body)
	body.global_transform = Transform3D(Basis.from_euler(Vector3(_rng.randf() * 0.4, _rng.randf() * TAU, _rng.randf() * 0.4)), at)
	body.linear_velocity = vel
	body.angular_velocity = Vector3(_rng.randf_range(-6, 6), _rng.randf_range(-6, 6), _rng.randf_range(-6, 6))
	var grace := car != null and is_instance_valid(car)
	if grace:
		body.add_collision_exception_with(car)
	_bodies.append([body, 0.0, grace])
	while _bodies.size() > MAX:
		var old: Array = _bodies.pop_front()
		if is_instance_valid(old[0]):
			(old[0] as Node).queue_free()
	return body


func _mesh(size: Vector3) -> BoxMesh:
	if not _meshes.has(size):
		var b := BoxMesh.new()
		b.size = size
		_meshes[size] = b
	return _meshes[size]


func _shape(size: Vector3) -> BoxShape3D:
	if not _shapes.has(size):
		var b := BoxShape3D.new()
		b.size = size
		_shapes[size] = b
	return _shapes[size]


func _mat(c: Color, glow: float) -> Material:
	var key := "%s|%.1f" % [c.to_html(), glow]
	if not _mats.has(key) and c.a >= 1.0:
		_mats[key] = Voxels.voxel_material(c, 0.8, 0.0, glow)
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = 0.75
		if c.a < 1.0:
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.metallic = 0.5
			m.roughness = 0.1
		if glow > 0.0:
			m.emission_enabled = true
			m.emission = Color(c.r, c.g, c.b)
			m.emission_energy_multiplier = glow
		_mats[key] = m
	return _mats[key]


func _physics_process(delta: float) -> void:
	var keep: Array = []
	for b in _bodies:
		var body: RigidBody3D = b[0]
		if not is_instance_valid(body):
			continue
		b[1] += delta
		if b[2] and b[1] > CAR_GRACE:
			b[2] = false
			if is_instance_valid(car):
				body.remove_collision_exception_with(car)
		if b[1] > LIFE:
			body.queue_free()
			continue
		if b[1] > LIFE - 1.0:
			(body.get_child(0) as Node3D).scale = Vector3.ONE * maxf(LIFE - b[1], 0.05)
		keep.append(b)
	_bodies = keep
