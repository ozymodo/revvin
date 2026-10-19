extends Node3D
## Floating pickups. Amber THRUST canisters refill the rear-thruster tank,
## red ROCKET canisters (longer, with fins) refill the jets' tank, and
## cyan BATTERY cells recharge the pack.
## They sit along the avenues, on the SKYWAY, inside its hoops, over the
## street kickers and on the stunt features. Drive or fly through one to
## grab it: within a few metres it is pulled toward the car, then shrinks
## into it (into the tank it refills, or under the floor for the battery)
## and comes back after RESPAWN seconds. A tall beacon marks each one from
## a distance.

signal collected(kind: int, amount: float, pos: Vector3, airborne: bool)

const Fx := preload("res://scripts/fx.gd")
const City := preload("res://scripts/world/city.gd")

enum Kind { THRUST, ROCKET, BATTERY }
const AMOUNT := [0.4, 0.35, 0.35]           # share of a full tank / pack
const COLORS := [Color(1.0, 0.6, 0.15), Color(1.0, 0.2, 0.32), Color(0.35, 0.82, 1.0)]
const NAMES := ["THRUST", "ROCKET", "BATTERY"]
## Where each kind goes into the car (body space): the thrust tank across
## the rear, the rocket tank in the passenger seat, the pack under the floor.
const INTAKE := [Vector3(0, 0.5, 0.56), Vector3(0.36, 0.6, -0.4), Vector3(0, 0.25, 0.0)]
const ABSORB_TIME := 0.14
const RESPAWN := 25.0
const GRAB_R := 2.6
const MAGNET_R := 7.5

const BEACON_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_back, depth_draw_never, shadows_disabled, fog_disabled;
uniform vec4 color : source_color;
void fragment() {
	// UV.y runs 0 at the top to 1 at the bottom of the cylinder. Brightest
	// down the middle of the column, soft at its sides, fading upward, with
	// a slow pulse rising up it.
	float fade = pow(UV.y, 1.8);
	float core = pow(abs(dot(NORMAL, VIEW)), 2.0);
	float pulse = 0.8 + 0.2 * sin(TIME * 2.5 + UV.y * 6.0);
	ALBEDO = color.rgb * 1.6;
	ALPHA = fade * core * pulse * 0.5;
}
"""


## Draw distance of a pickup (scaled by the world LOD, never under DRAW_MIN).
const DRAW := 220.0
const DRAW_MIN := 110.0

class Pickup:
	var kind := 0
	var home := Vector3.ZERO
	var root: Node3D                       # moves toward the car when it's close
	var spin: Node3D                       # bobs and turns
	var ring: Node3D
	var beacon: GeometryInstance3D
	var light: OmniLight3D
	var active := true
	var absorbing := -1.0                  # >= 0 while it shrinks into the car
	var absorb_from := Vector3.ZERO
	var timer := 0.0
	var grow := 1.0
	var phase := 0.0


var car: RigidBody3D
var items: Array[Pickup] = []
var _clock := 0.0
var _mats := {}
var _meshes := {}


func _ready() -> void:
	_build_assets()


## Places the full set: avenues, SKYWAY, hoops, street kickers and the
## stunt features. `level` is level.gd (its reserved test lanes are kept clear).
func place_all(level: Node3D) -> void:
	var city: Node3D = level.city
	var course: Node = level.course
	var ramps: Array = level.ramp_spots
	var r := RandomNumberGenerator.new()
	r.seed = 2718

	# Avenues: low canisters on the lanes, away from junctions and kickers.
	var n := 0
	for a: float in City.AVENUES:
		for axis in 2:
			var t := -340.0 + r.randf_range(0.0, 50.0)
			while t < 340.0:
				var lane := 5.5 if n % 2 == 0 else -5.5
				var x: float = (a + lane) if axis == 0 else t
				var z: float = t if axis == 0 else (a + lane)
				var ok: bool = not level._reserved(x, z, 8.0) and not city.masked(x, z)
				for b: float in City.AVENUES:
					if absf(t - b) < 24.0:
						ok = false
				for rs in ramps:
					if Vector2(x - rs[0].x, z - rs[0].z).length() < 30.0:
						ok = false
				if ok:
					spawn(Vector3(x, 1.5, z), n % 3)
					n += 1
				t += r.randf_range(85.0, 130.0)

	# Over the street kickers, where a launch at speed carries the car.
	for k in ramps.size():
		var base: Vector3 = ramps[k][0]
		var yaw: float = ramps[k][1]
		var length: float = ramps[k][2]
		var h: float = ramps[k][3]
		var dir := Basis(Vector3.UP, yaw) * Vector3.FORWARD
		var lip := base + dir * length * 0.5
		var p := lip + dir * (10.0 + h * 3.0) + Vector3.UP * (h + 2.2 + h * 0.6)
		if not level._reserved(p.x, p.z, 4.0):
			spawn(p, Kind.ROCKET if k % 3 != 2 else Kind.THRUST)

	# SKYWAY: one every ~230 m on the road, plus one inside every hoop.
	if course:
		var tr = course.track
		var next := 150.0
		var side := 1.0
		for i in tr.pts.size():
			if tr.dists[i] < next:
				continue
			next += 230.0
			var near_jump := false
			for j in course.route.jumps:
				if absi(i - int(j[0])) < 40:
					near_jump = true
			if near_jump:
				continue
			var xf: Transform3D = tr.sample_xform(i)
			spawn(xf.origin + xf.basis.y * 1.4 + xf.basis.x * 3.5 * side, [Kind.THRUST, Kind.ROCKET, Kind.BATTERY][n % 3])
			n += 1
			side = -side
		for c: Vector3 in course.hoop_centres:
			spawn(c, Kind.ROCKET)

	# Stunt features.
	spawn(Vector3(80, 13.8, -200), Kind.ROCKET)        # on the mesa
	spawn(Vector3(200, 20.0, -186), Kind.ROCKET)       # off the mega ramp
	spawn(Vector3(-224.4, 8.0, -150), Kind.THRUST)     # on the wall of death
	spawn(Vector3(-60, 7.5, -111), Kind.THRUST)        # over the gap jump
	spawn(Vector3(40, 9.0, -76), Kind.ROCKET)          # off the flip kicker
	spawn(Vector3(-40, 13.0, 65), Kind.ROCKET)         # high over the half-pipe
	spawn(Vector3(150, 1.5, 85), Kind.BATTERY)         # on the loop's run-up
	spawn(Vector3(-200, 1.5, -150), Kind.BATTERY)      # in the wall of death


func spawn(pos: Vector3, kind: int) -> Pickup:
	var p := Pickup.new()
	p.kind = kind
	p.home = pos
	p.phase = randf() * TAU
	p.root = Node3D.new()
	p.root.position = pos
	add_child(p.root)
	p.spin = Node3D.new()
	p.root.add_child(p.spin)

	var cap_y := 0.6
	if kind == Kind.BATTERY:
		_battery_cell(p)
		cap_y = 0.55
	else:
		cap_y = _canister(p, kind)

	p.ring = _mesh_instance(_meshes.ring, _mats["halo_%d" % kind])
	p.root.add_child(p.ring)
	var label := Label3D.new()
	label.text = NAMES[kind] if kind == Kind.BATTERY else NAMES[kind] + " AIR"
	label.font_size = 40
	label.pixel_size = 0.012
	label.outline_size = 10
	label.modulate = COLORS[kind].lightened(0.35)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.shaded = false
	label.position.y = cap_y + 1.0
	label.visibility_range_end = 70.0
	p.spin.add_child(label)

	p.beacon = _mesh_instance(_meshes.beacon, _mats["beacon_%d" % kind])
	p.beacon.position.y = 30.0
	p.beacon.visibility_range_begin = 12.0
	p.beacon.visibility_range_end = 600.0
	p.root.add_child(p.beacon)

	p.light = OmniLight3D.new()
	p.light.light_color = COLORS[kind]
	p.light.light_energy = 2.2
	p.light.omni_range = 7.0
	p.light.distance_fade_enabled = true
	p.light.distance_fade_begin = 70.0
	p.light.distance_fade_length = 20.0
	p.root.add_child(p.light)

	var motes := _motes(COLORS[kind])
	p.root.add_child(motes)
	# Draw distances follow the world LOD (the beacon keeps its 600 m).
	Lod.draw_distance(p.spin, DRAW, 0.0, DRAW_MIN)
	Lod.draw_distance(p.ring, DRAW, 0.0, DRAW_MIN)
	Lod.draw_distance(motes, 90.0)
	Lod.draw_distance(p.light, 90.0, 0.0, 50.0)
	items.append(p)
	return p


## Air canister (thrust: short and fat; rocket: long with fins). Returns the
## height of its top cap.
func _canister(p: Pickup, kind: int) -> float:
	var long := kind == Kind.ROCKET
	var body := _mesh_instance(_meshes["body_rocket" if long else "body_thrust"], _mats.metal)
	p.spin.add_child(body)
	for y in ([-0.42, 0.0, 0.42] if long else [-0.25, 0.25]):
		var band := _mesh_instance(_meshes.band, _mats["glow_%d" % kind])
		band.position.y = y
		p.spin.add_child(band)
	var cap_y := 0.85 if long else 0.6
	for sgn in [1.0, -1.0]:
		var cap := _mesh_instance(_meshes.cap, _mats.metal)
		cap.position.y = cap_y * sgn
		cap.scale.y = sgn
		p.spin.add_child(cap)
	var valve := _mesh_instance(_meshes.valve, _mats.brass)
	valve.position.y = cap_y + 0.32
	p.spin.add_child(valve)
	if long:
		for k in 3:
			var fin := _mesh_instance(_meshes.fin, _mats["glow_%d" % kind])
			fin.rotation.y = k * TAU / 3.0
			fin.position = Basis(Vector3.UP, k * TAU / 3.0) * Vector3(0.52, -0.75, 0)
			p.spin.add_child(fin)
	return cap_y


## Battery cell: a dark slab with glowing cyan seams and two terminals.
func _battery_cell(p: Pickup) -> void:
	p.spin.add_child(_mesh_instance(_meshes.cell, _mats.cell))
	for y in [-0.3, 0.0, 0.3]:
		var seam := _mesh_instance(_meshes.seam, _mats["glow_%d" % Kind.BATTERY])
		seam.position.y = y
		p.spin.add_child(seam)
	for x in [-0.2, 0.2]:
		var post := _mesh_instance(_meshes.terminal, _mats.brass)
		post.position = Vector3(x, 0.56, 0)
		p.spin.add_child(post)
	var bolt := Label3D.new()
	bolt.text = "⚡"
	bolt.font_size = 64
	bolt.pixel_size = 0.008
	bolt.modulate = Color(0.7, 0.95, 1.0)
	bolt.shaded = false
	bolt.position = Vector3(0, 0.05, 0.27)
	bolt.outline_size = 0
	p.spin.add_child(bolt)
	var back := bolt.duplicate() as Label3D
	back.position.z = -0.27
	back.rotation.y = PI
	p.spin.add_child(back)


func _physics_process(delta: float) -> void:
	_clock += delta
	if car == null:
		return
	var car_pos := car.global_position + car.global_basis.y * 0.5
	for p in items:
		if p.absorbing >= 0.0:
			_absorb(p, delta)
			continue
		if not p.active:
			p.timer -= delta
			if p.timer <= 0.0:
				p.active = true
				p.grow = 0.0
				p.root.position = p.home
				p.root.visible = true
		if not p.active:
			continue
		p.grow = minf(1.0, p.grow + delta * 1.6)
		var k := p.grow
		var pop := 1.0 + 0.25 * sin(k * PI) if k < 1.0 else 1.0       # overshoots as it reappears
		p.spin.scale = Vector3.ONE * maxf(k * pop, 0.01)
		var pos := p.root.position
		var d := car_pos.distance_to(pos)
		if d < MAGNET_R and k >= 1.0:
			# Reel in toward the car, faster the closer it gets.
			var pull := clampf(1.0 - d / MAGNET_R, 0.0, 1.0)
			p.root.position = pos.move_toward(car_pos, delta * (6.0 + 40.0 * pull * pull))
		elif pos.distance_to(p.home) > 0.01:
			p.root.position = pos.move_toward(p.home, delta * 4.0)
		if car_pos.distance_to(p.root.position) < GRAB_R and k >= 1.0:
			_collect(p)


func _process(delta: float) -> void:
	for p in items:
		if not p.active or not Lod.near(p.home, DRAW, DRAW_MIN):
			continue
		var t := _clock + p.phase
		p.spin.position.y = sin(t * 1.8) * 0.25
		p.spin.rotate_y(delta * 1.4)
		p.ring.rotation = Vector3(0.5 + sin(t * 0.7) * 0.3, t * 2.2, 0.0)
		p.light.light_energy = 1.8 + 0.6 * sin(t * 4.0)


func _collect(p: Pickup) -> void:
	p.active = false
	p.timer = RESPAWN
	p.absorbing = 0.0
	p.absorb_from = p.root.global_position
	var amount: float = AMOUNT[p.kind]
	match p.kind:
		Kind.THRUST:
			car.add_air(amount, 0.0, COLORS[p.kind])
		Kind.ROCKET:
			car.add_air(0.0, amount, COLORS[p.kind])
		Kind.BATTERY:
			car.add_charge(amount, COLORS[p.kind])
	collected.emit(p.kind, amount, p.root.global_position, car.grounded_wheels == 0)


## The pickup shrinks into the car where it's going: the tank it refills,
## or under the floor for the battery. It tracks the car as it goes.
func _absorb(p: Pickup, delta: float) -> void:
	p.absorbing += delta
	var k := clampf(p.absorbing / ABSORB_TIME, 0.0, 1.0)
	var to: Vector3 = car.global_transform * INTAKE[p.kind]
	p.root.global_position = p.absorb_from.lerp(to, k * k)
	p.spin.scale = Vector3(1.0 - k * 0.7, 1.0 - k, 1.0 - k * 0.7).maxf(0.01)
	if k >= 1.0:
		p.absorbing = -1.0
		p.root.visible = false


# ------------------------------------------------------------------ assets

func _mesh_instance(mesh: Mesh, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = DRAW
	return mi


func _build_assets() -> void:
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.32, 0.34, 0.38)
	metal.metallic = 0.85
	metal.roughness = 0.28
	_mats.metal = metal
	var brass := StandardMaterial3D.new()
	brass.albedo_color = Color(0.85, 0.62, 0.28)
	brass.metallic = 0.9
	brass.roughness = 0.3
	_mats.brass = brass
	var beacon_shader := Shader.new()
	beacon_shader.code = BEACON_SHADER
	for kind in 3:
		var c: Color = COLORS[kind]
		var glow := StandardMaterial3D.new()
		glow.albedo_color = c * 0.4
		glow.emission_enabled = true
		glow.emission = c
		glow.emission_energy_multiplier = 4.0
		_mats["glow_%d" % kind] = glow
		var halo := StandardMaterial3D.new()
		halo.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		halo.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		halo.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		halo.albedo_color = Color(c.r * 2.5, c.g * 2.5, c.b * 2.5, 0.8)
		_mats["halo_%d" % kind] = halo
		var beacon := ShaderMaterial.new()
		beacon.shader = beacon_shader
		beacon.set_shader_parameter("color", c)
		_mats["beacon_%d" % kind] = beacon

	for key in ["body_thrust", "body_rocket"]:
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.45 if key == "body_thrust" else 0.38
		cyl.bottom_radius = cyl.top_radius
		cyl.height = 1.2 if key == "body_thrust" else 1.7
		cyl.radial_segments = 20
		_meshes[key] = cyl
	var cell_mat := StandardMaterial3D.new()
	cell_mat.albedo_color = Color(0.08, 0.1, 0.13)
	cell_mat.metallic = 0.6
	cell_mat.roughness = 0.35
	_mats.cell = cell_mat
	var cell := BoxMesh.new()
	cell.size = Vector3(0.75, 1.0, 0.5)
	_meshes.cell = cell
	var seam := BoxMesh.new()
	seam.size = Vector3(0.79, 0.05, 0.54)
	_meshes.seam = seam
	var terminal := CylinderMesh.new()
	terminal.top_radius = 0.07
	terminal.bottom_radius = 0.09
	terminal.height = 0.14
	terminal.radial_segments = 10
	_meshes.terminal = terminal
	var cap := SphereMesh.new()
	cap.radius = 0.44
	cap.height = 0.5
	cap.is_hemisphere = true
	cap.radial_segments = 20
	cap.rings = 6
	_meshes.cap = cap
	var band := CylinderMesh.new()
	band.top_radius = 0.47
	band.bottom_radius = 0.47
	band.height = 0.08
	band.radial_segments = 20
	_meshes.band = band
	var valve := CylinderMesh.new()
	valve.top_radius = 0.1
	valve.bottom_radius = 0.14
	valve.height = 0.22
	valve.radial_segments = 10
	_meshes.valve = valve
	var fin := PrismMesh.new()
	fin.size = Vector3(0.35, 0.5, 0.04)
	_meshes.fin = fin
	var ring := TorusMesh.new()
	ring.inner_radius = 1.25
	ring.outer_radius = 1.33
	ring.rings = 40
	ring.ring_segments = 6
	_meshes.ring = ring
	var beacon := CylinderMesh.new()
	beacon.top_radius = 0.35
	beacon.bottom_radius = 0.6
	beacon.height = 60.0
	beacon.radial_segments = 16
	beacon.rings = 1
	beacon.cap_top = false
	beacon.cap_bottom = false
	_meshes.beacon = beacon


## A few glowing motes drifting up around a canister.
func _motes(c: Color) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 14
	p.lifetime = 1.8
	p.visibility_range_end = 90.0
	p.visibility_aabb = AABB(Vector3(-3, -2, -3), Vector3(6, 7, 6))
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	m.emission_sphere_radius = 1.3
	m.direction = Vector3.UP
	m.spread = 20.0
	m.initial_velocity_min = 0.3
	m.initial_velocity_max = 0.9
	m.gravity = Vector3(0, 0.4, 0)
	m.scale_min = 0.5
	m.scale_max = 1.0
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.3, 1.0])
	grad.colors = PackedColorArray([Color(c, 0.0), Color(c, 1.0), Color(c, 0.0)])
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	m.color_ramp = gt
	p.process_material = m
	p.draw_pass_1 = Fx.glow_quad(0.14, 3.0)
	return p
