extends Node3D
## Proving ground, built in code: grid tarmac, cone slalom, kickers, a jump
## over a gap, a tall mesa that only the Rocket trim can reach, crates to
## knock over, and suction-fan tests: a wall of death, a
## half-pipe, a loop, a replica of the reveal's inverted ramp, and a jump
## over parked cars and a Semi. All of it sits in the ruins of an
## overgrown city (world/city.gd).

const GROUND_SHADER := preload("res://scripts/world/ground.gdshader")
const ROAD_SHADER := preload("res://scripts/track/track_road.gdshader")
const City := preload("res://scripts/world/city.gd")
const Course := preload("res://scripts/track/course.gd")

const ROAD_HALF := 11.0             # carriageway half-width on the avenues
const WALK_OUT := 16.5              # sidewalk outer edge from the avenue centre
const KERB := 0.12

## Areas the city must leave clear: stunt features, their run-ups and
## landing zones, and the test-scenario lanes. Rect2(x, z, width, depth).
const RESERVED: Array[Rect2] = [
	Rect2(-20, -290, 40, 310),       # spawn, slalom, kicker
	Rect2(-72, -190, 24, 115),       # gap jump
	Rect2(-34, -50, 18, 20),         # crates
	Rect2(56, -224, 48, 82),         # mesa + ramp
	Rect2(30, -168, 20, 118),        # flip kicker, speed bumps
	Rect2(180, -390, 40, 262),       # mega ramp + landing
	Rect2(-234, -184, 68, 68),       # wall of death
	Rect2(-180, -162, 44, 24),       # its entrance
	Rect2(-130, 48, 180, 34),        # half-pipe
	Rect2(136, 25, 30, 135),         # loop + run-up
	Rect2(216, 25, 30, 215),         # inverted ramp + run-up/landing
	Rect2(282, -132, 46, 172),       # car jump
	Rect2(-312, 140, 282, 125),      # drift, side-jet and hop test lane
	Rect2(-362, 283, 335, 34),       # refill test
	Rect2(-137, -317, 34, 34),       # flip test
]

const Grinds := preload("res://scripts/world/grinds.gd")
const StuntPark := preload("res://scripts/world/stunt_park.gd")
const Dome := preload("res://scripts/world/dome.gd")
const Destruction := preload("res://scripts/world/destruction.gd")
const Wrecking := preload("res://scripts/world/wrecking.gd")

var city: Node3D
var course: Course
var grinds: Grinds
var park: StuntPark
var destruction: Destruction
var wrecking: Wrecking
## Footprints kept clear beyond RESERVED (the mega-blocks).
var extra_reserved: Array[Rect2] = []
## Street kickers: [base, yaw, length, height] (air pickups sit over them).
var ramp_spots: Array = []

var _mats := {}


func _ready() -> void:
	_environment()
	_ground()

	# Cone slalom straight ahead
	for i in 10:
		_cone(Vector3(3.5 if i % 2 == 0 else -3.5, 0, -50.0 - i * 18.0))

	# Kicker at the end of the slalom
	wedge(Vector3(0, 0, -260), 0.0, 8.0, 9.0, 1.8, "ramp")

	# Gap jump: launch ramp, landing deck, ramp back down
	wedge(Vector3(-60, 0, -90), 0.0, 10.0, 20.0, 4.0, "ramp")
	box(Vector3(-60, 2, -142), Vector3(16, 4, 40), "deck")
	wedge(Vector3(-60, 0, -172), PI, 16.0, 20.0, 4.0, "ramp")

	# Mesa: 12 m up. Ramp gets you part of the way; the jets do the rest.
	box(Vector3(80, 6, -200), Vector3(36, 12, 36), "mesa")
	wedge(Vector3(80, 0, -168), 0.0, 10.0, 24.0, 6.0, "ramp")
	_sign(Vector3(80, 1.5, -150), "MESA  ·  12 m\nrocket trim only")

	# Crate pyramid
	var size := 1.2
	for row in 4:
		for i in 4 - row:
			_crate(Vector3(-25 + (i - (3 - row) * 0.5) * size * 1.02, size * 0.5 + row * size, -40), size)

	_suction_course()
	_stunt_course()

	# No boundary walls any more: the dome (world/dome.gd) encloses the
	# world, with the stunt parks between the city and its wall.

	# The SKYWAY stunt course threads through the city; the city keeps
	# its footprint clear.
	course = Course.new()
	course.name = "Course"
	add_child(course)
	course.build(RESERVED)

	# Mega-blocks take whole city blocks: pick them first, keep the city off them.
	wrecking = Wrecking.new()
	wrecking.name = "Wrecking"
	add_child(wrecking)
	extra_reserved = wrecking.plan_megablocks(self, course.footprint())
	var zones: Array[Rect2] = []
	zones.append_array(RESERVED)
	zones.append_array(extra_reserved)
	city = City.new()
	add_child(city)
	city.build(zones, course.footprint())
	_feature_vines()
	_roads()
	_street_ramps()
	destruction = Destruction.new()
	destruction.name = "Destruction"
	add_child(destruction)
	grinds = Grinds.new()
	grinds.name = "Grinds"
	add_child(grinds)
	park = StuntPark.new()
	park.name = "StuntPark"
	add_child(park)
	park.build(self)
	wrecking.build(self)
	var dome := Dome.new()
	dome.name = "Dome"
	dome.grinds = grinds
	add_child(dome)
	dome.build()


## Vines hanging off the tops of the big structures.
func _feature_vines() -> void:
	var list := []
	var r := RandomNumberGenerator.new()
	r.seed = 99
	var add := func(p: Vector3) -> void:
		list.append(Transform3D(Basis(Vector3.UP, r.randf() * TAU).scaled(Vector3(1, r.randf_range(1.5, 7.0), 1)), p))
	for i in 140:                                   # half-pipe wall tops
		var x := r.randf_range(-118, 38)
		add.call(Vector3(x, 13.0, 76.8 if i % 2 == 0 else 53.2))
	for i in 160:                                   # wall of death rim
		var a := r.randf_range(deg_to_rad(18), deg_to_rad(342))
		add.call(Vector3(-200 + cos(a) * 25.8, 16.0, -150 + sin(a) * 25.8))
	for i in 90:                                    # mesa edges
		var t := r.randf_range(-17.5, 17.5)
		var side := i % 4
		var p: Vector3 = [Vector3(80 + t, 12, -181.8), Vector3(80 + t, 12, -218.2), Vector3(61.8, 12, -200 + t), Vector3(98.2, 12, -200 + t)][side]
		add.call(p)
	city.scatter(city.vine_mesh(), list, 100.0, 400.0, false)


func _environment() -> void:
	# Late golden hour in a city gone quiet: low warm sun, green-gold haze,
	# volumetric light through the towers, glow on whatever still has power.
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.2, 0.33, 0.45)
	sky_mat.sky_horizon_color = Color(0.86, 0.7, 0.48)
	sky_mat.sky_curve = 0.12
	sky_mat.ground_horizon_color = Color(0.45, 0.42, 0.3)
	sky_mat.ground_bottom_color = Color(0.12, 0.14, 0.1)
	sky_mat.sun_angle_max = 20.0
	var sky := Sky.new()
	sky.sky_material = sky_mat

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.75
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_bloom = 0.08
	env.glow_hdr_threshold = 0.9
	env.ssao_enabled = true
	env.ssao_intensity = 1.6
	env.fog_enabled = true
	env.fog_light_color = Color(0.66, 0.62, 0.48)
	env.fog_density = 0.0028
	env.fog_sun_scatter = 0.35
	env.fog_sky_affect = 0.25
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.005
	env.volumetric_fog_albedo = Color(0.85, 0.88, 0.76)
	env.volumetric_fog_anisotropy = 0.55
	env.volumetric_fog_length = 140.0
	env.volumetric_fog_sky_affect = 0.2
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.08
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-22, -58, 0)
	sun.light_color = Color(1.0, 0.8, 0.58)
	sun.light_energy = 1.5
	sun.light_volumetric_fog_energy = 1.4
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 220.0
	sun.directional_shadow_blend_splits = true
	add_child(sun)
	# Player graphics settings (shadows, SSAO, fog...) apply to these.
	Settings.environment = env
	Settings.sun = sun
	Settings.apply_graphics()


func _material(kind: String) -> Material:
	if _mats.has(kind):
		return _mats[kind]
	var m: Material
	match kind:
		"ground", "lane":
			var g := ShaderMaterial.new()
			g.shader = GROUND_SHADER
			m = g
		"ramp":          # cracked concrete slabs
			m = City.overgrown(Color(0.46, 0.44, 0.4), 0.5, 0.35, 2.0, 0.0)
		"deck":          # old transit deck
			m = City.overgrown(Color(0.28, 0.3, 0.33), 0.6, 0.5, 4.0, 0.5)
		"mesa":          # stump of a fallen arcology
			m = City.overgrown(Color(0.38, 0.37, 0.35), 0.75, 0.6, 3.5, 0.1)
		"wall_ride":     # dark tech panels, veins glowing in the seams
			m = City.overgrown(Color(0.12, 0.14, 0.16), 0.35, 0.6, 2.5, 0.7, Color(0.15, 0.45, 1.0))
		_:               # the old city barrier
			m = City.overgrown(Color(0.34, 0.34, 0.33), 0.8, 0.3, 4.0, 0.1)
	_mats[kind] = m
	return m


func _ground() -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = WorldBoundaryShape3D.new()
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(2000, 2000)
	plane.subdivide_width = 40
	plane.subdivide_depth = 40
	mesh.mesh = plane
	mesh.material_override = _material("ground")
	body.add_child(mesh)
	add_child(body)


func box(center: Vector3, size: Vector3, kind: String) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = center
	var shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	shape.shape = bs
	body.add_child(shape)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _material(kind)
	body.add_child(mi)
	add_child(body)
	return body


## Curved kicker: a smooth concave ramp (no hard crease at the bottom)
## centred on `base`, rising toward local -Z to `height`, with a lip
## steepening to about 35 degrees. Sides and back are closed.
func kicker(base: Vector3, yaw: float, width: float, length: float, height: float, kind: String) -> void:
	var s := Surface.new(self, _material(kind))
	var b := Basis(Vector3.UP, yaw)
	var fwd := b * Vector3.FORWARD
	var right := b * Vector3.RIGHT
	var hw := width * 0.5
	var rows := 16
	var top := []
	var nrm := []
	var start := base - fwd * length * 0.5
	for i in rows + 1:
		var u := float(i) / rows
		var y := height * u * u
		var slope := 2.0 * height * u / length
		var p := start + fwd * length * u + Vector3.UP * y
		top.append([p - right * hw, p + right * hw])
		nrm.append((Vector3.UP - fwd * slope).normalized())
	s.grid(top, nrm)
	for side in [-1.0, 1.0]:
		var wall := []
		var wn := []
		for i in rows + 1:
			var p: Vector3 = top[i][0 if side < 0 else 1]
			wall.append([Vector3(p.x, base.y, p.z), p])
			wn.append(right * side)
		s.grid(wall, wn)
	var e: Array = top[rows]
	s.grid([[e[0], e[1]], [Vector3(e[0].x, base.y, e[0].z), Vector3(e[1].x, base.y, e[1].z)]], [fwd, fwd])
	s.finish()


## Ramp whose base is centred on `base`, rising toward local -Z.
func wedge(base: Vector3, yaw: float, width: float, length: float, height: float, kind: String) -> StaticBody3D:
	var hw := width * 0.5
	var hl := length * 0.5
	var a := Vector3(-hw, 0, hl)
	var b := Vector3(hw, 0, hl)
	var c := Vector3(-hw, 0, -hl)
	var d := Vector3(hw, 0, -hl)
	var e := Vector3(-hw, height, -hl)
	var f := Vector3(hw, height, -hl)
	var mid := (a + b + c + d + e + f) / 6.0

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for quad in [[a, b, f, e], [c, d, b, a], [e, f, d, c]]:
		_tri(st, quad[0], quad[1], quad[2], mid)
		_tri(st, quad[0], quad[2], quad[3], mid)
	_tri(st, a, e, c, mid)
	_tri(st, b, d, f, mid)

	var body := StaticBody3D.new()
	body.position = base
	body.rotation.y = yaw
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _material(kind)
	body.add_child(mi)
	var shape := CollisionShape3D.new()
	var cs := ConvexPolygonShape3D.new()
	cs.points = PackedVector3Array([a, b, c, d, e, f])
	shape.shape = cs
	body.add_child(shape)
	add_child(body)
	return body


## Adds a triangle facing away from `inside`. Godot treats clockwise
## winding (seen from the front) as the front face.
func _tri(st: SurfaceTool, p0: Vector3, p1: Vector3, p2: Vector3, inside: Vector3) -> void:
	var n := (p1 - p0).cross(p2 - p0)
	var outward := (p0 + p1 + p2) / 3.0 - inside
	if n.dot(outward) > 0.0:
		var t := p1
		p1 = p2
		p2 = t
		n = -n
	st.set_normal(-n.normalized())
	st.add_vertex(p0)
	st.add_vertex(p1)
	st.add_vertex(p2)


func _sign(pos: Vector3, text: String) -> void:
	var label := Label3D.new()
	label.text = text
	label.font_size = 80
	label.pixel_size = 0.01
	label.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	label.position = pos
	label.outline_size = 10
	add_child(label)


func _cone(pos: Vector3) -> void:
	var body := RigidBody3D.new()
	body.mass = 4.0
	body.position = pos + Vector3.UP * 0.36
	var shape := CollisionShape3D.new()
	var cs := CylinderShape3D.new()
	cs.radius = 0.2
	cs.height = 0.7
	shape.shape = cs
	body.add_child(shape)
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.03
	cm.bottom_radius = 0.24
	cm.height = 0.7
	mi.mesh = cm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(1.0, 0.42, 0.1)
	mi.material_override = m
	body.add_child(mi)
	add_child(body)


func _crate(pos: Vector3, size: float) -> void:
	var body := RigidBody3D.new()
	body.mass = 30.0
	body.position = pos
	var shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3.ONE * size
	shape.shape = bs
	body.add_child(shape)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE * size
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.62, 0.48, 0.3)
	m.roughness = 0.9
	mi.material_override = m
	body.add_child(mi)
	add_child(body)


# ------------------------------------------------------------------ roads

func _reserved(x: float, z: float, margin := 0.0) -> bool:
	for r in RESERVED:
		if r.grow(margin).has_point(Vector2(x, z)):
			return true
	for r in extra_reserved:
		if r.grow(margin).has_point(Vector2(x, z)):
			return true
	return false


## A Surface (smooth drivable triangle mesh) in one of the level materials.
func surface(kind: String) -> Surface:
	return Surface.new(self, _material(kind))


## Proper roads on the avenues: a smooth carriageway with glowing lane
## lines, raised kerbs and sidewalks broken at the junctions. One mesh and
## one collision shape for the lot, so wheels hit it exactly (and skid
## marks sit on it, not under it).
func _roads() -> void:
	var road := SurfaceTool.new()
	var walk := SurfaceTool.new()
	road.begin(Mesh.PRIMITIVE_TRIANGLES)
	walk.begin(Mesh.PRIMITIVE_TRIANGLES)
	var faces := PackedVector3Array()
	var lim := City.PLAY
	var col := Color(0, 0, 0, ROAD_HALF * 2.0 / 32.0)
	var y := 0.03
	for a: float in City.AVENUES:
		# North-south carriageway, full length (it owns the junctions).
		_road_quad(road, faces, Vector3(a - ROAD_HALF, y, -lim), Vector3(a + ROAD_HALF, y, -lim),
			Vector3(a + ROAD_HALF, y, lim), Vector3(a - ROAD_HALF, y, lim), -lim, lim, col, false)
		# East-west, between the north-south roads.
		var xs := [-lim]
		for b: float in City.AVENUES:
			xs.append(b - ROAD_HALF)
			xs.append(b + ROAD_HALF)
		xs.append(lim)
		for k in range(0, xs.size(), 2):
			_road_quad(road, faces, Vector3(xs[k], y, a + ROAD_HALF), Vector3(xs[k], y, a - ROAD_HALF),
				Vector3(xs[k + 1], y, a - ROAD_HALF), Vector3(xs[k + 1], y, a + ROAD_HALF), xs[k], xs[k + 1], col, true)
		# Sidewalks, 4 m pieces, both sides of both directions.
		for axis in 2:
			for side: float in [-1.0, 1.0]:
				var t := -lim
				while t < lim:
					var t1 := minf(t + 4.0, lim)
					var mid := (t + t1) * 0.5
					var off := a + side * (ROAD_HALF + WALK_OUT) * 0.5
					var x := off if axis == 0 else mid
					var z := mid if axis == 0 else off
					var junction := false
					for b: float in City.AVENUES:
						if absf(mid - b) < WALK_OUT + 2.0:
							junction = true
					if not junction and not _reserved(x, z, 2.0):
						_sidewalk(walk, faces, a, side, axis, t, t1)
					t = t1
	var body := StaticBody3D.new()
	body.name = "Roads"
	var road_mat := ShaderMaterial.new()
	road_mat.shader = ROAD_SHADER
	road_mat.set_shader_parameter("edge_color", Color(0.15, 0.45, 1.0) * 0.6)
	for pair in [[road, road_mat], [walk, City.overgrown(Color(0.42, 0.41, 0.38), 0.7, 0.25, 2.0, 0.0)]]:
		var mi := MeshInstance3D.new()
		mi.mesh = (pair[0] as SurfaceTool).commit()
		mi.material_override = pair[1]
		body.add_child(mi)
	var cs := CollisionShape3D.new()
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	cs.shape = shape
	body.add_child(cs)
	add_child(body)


## A road quad (a, b across the start; c, d across the end). UV.x 0..1
## across, UV.y metres along, as the track shader expects.
func _road_quad(st: SurfaceTool, faces: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		v0: float, v1: float, col: Color, _ew: bool) -> void:
	var uv := [Vector2(0, v0), Vector2(1, v0), Vector2(1, v1), Vector2(0, v1)]
	var q := [a, b, c, d]
	for tri in [[0, 1, 2], [0, 2, 3]]:
		var p0: Vector3 = q[tri[0]]
		var p1: Vector3 = q[tri[1]]
		var p2: Vector3 = q[tri[2]]
		var order: Array = tri if (p1 - p0).cross(p2 - p0).y < 0.0 else [tri[0], tri[2], tri[1]]
		for k in order:
			st.set_normal(Vector3.UP)
			st.set_uv(uv[k])
			st.set_color(col)
			st.add_vertex(q[k])
			faces.append(q[k])


func _sidewalk(st: SurfaceTool, faces: PackedVector3Array, a: float, side: float, axis: int, t0: float, t1: float) -> void:
	var inner := a + side * ROAD_HALF
	var outer := a + side * WALK_OUT
	var h := KERB
	var P := func(across: float, along: float, y: float) -> Vector3:
		return Vector3(across, y, along) if axis == 0 else Vector3(along, y, across)
	var top := [P.call(inner, t0, h), P.call(outer, t0, h), P.call(outer, t1, h), P.call(inner, t1, h)]
	var kerb := [P.call(inner, t0, 0.0), P.call(inner, t0, h), P.call(inner, t1, h), P.call(inner, t1, 0.0)]
	var kn: Vector3 = P.call(-side, 0.0, 0.0)
	_flat_quad(st, faces, top, Vector3.UP)
	_flat_quad(st, faces, kerb, kn)


func _flat_quad(st: SurfaceTool, faces: PackedVector3Array, q: Array, n: Vector3) -> void:
	for tri in [[0, 1, 2], [0, 2, 3]]:
		var p0: Vector3 = q[tri[0]]
		var p1: Vector3 = q[tri[1]]
		var p2: Vector3 = q[tri[2]]
		var order: Array = tri if (p1 - p0).cross(p2 - p0).dot(n) < 0.0 else [tri[0], tri[2], tri[1]]
		for k in order:
			st.set_normal(n)
			st.add_vertex(q[k])
			faces.append(q[k])


## Kickers dotted along the avenues, alternating lanes and directions:
## something to launch off wherever you are.
func _street_ramps() -> void:
	var r := RandomNumberGenerator.new()
	r.seed = 404
	var count := 0
	for a: float in City.AVENUES:
		for axis in 2:
			var t := -360.0 + r.randf_range(0, 40)
			while t < 360.0:
				var lane := 5.5 if (count % 2 == 0) else -5.5
				var x: float = (a + lane) if axis == 0 else t
				var z: float = t if axis == 0 else (a + lane)
				var junction := false
				for b: float in City.AVENUES:
					if absf(t - b) < WALK_OUT + 14.0:
						junction = true
				if not junction and not _reserved(x, z, 12.0) and not city.is_reserved(x, z, 0.0):
					# Ramp faces down the lane its side drives on.
					var yaw := (0.0 if lane > 0 else PI) if axis == 0 else (PI * 0.5 if lane > 0 else -PI * 0.5)
					var h := r.randf_range(1.0, 2.6)
					kicker(Vector3(x, 0.03, z), yaw, 7.0, h * 4.0 + 3.0, h, "ramp")
					ramp_spots.append([Vector3(x, 0.03, z), yaw, h * 4.0 + 3.0, h])
					count += 1
				t += r.randf_range(70, 120)


# ------------------------------------------------------------------ suction + stunt course

func _suction_course() -> void:
	# Wall of death: 20 m flat floor, 6 m quarter-pipe, 10 m vertical wall.
	# The fans hold the car on the wall even at low speed. Open to the east.
	var wod := Surface.new(self, _material("wall_ride"))
	var centre := Vector3(-200, 0, -150)
	wod.ring_wall(centre, 20.0, 6.0, 10.0, deg_to_rad(16.0), deg_to_rad(344.0), 120)
	wod.finish()
	_sign(centre + Vector3(30, 2, 0), "WALL OF DEATH\nfans on · drive onto the wall")

	# Half-pipe along X: 14 m flat between two curved 5 m + 8 m walls.
	var hp := Surface.new(self, _material("wall_ride"))
	for side in [1.0, -1.0]:
		var o := Vector3(0, 0, side)
		hp.wall_profile(Vector3(-40, 0, 65 + side * 7.0), o, Vector3.RIGHT, 160.0, 5.0, 8.0)
	hp.finish()
	_sign(Vector3(48, 2, 65), "HALF-PIPE  ·  suction wall ride")

	# Corkscrew loop, 10 m radius, entered heading north (-Z).
	var loop := Surface.new(self, _material("wall_ride"))
	loop.arc(Vector3(150, 0, 40), 10.0, 9.0, 10.5, TAU, 200)
	loop.finish()
	_sign(Vector3(150, 2, 70), "LOOP  ·  10 m")
	box(Vector3(150, 0.02, 100), Vector3(9, 0.04, 110), "lane")

	# Speed bumps to feel the suspension and suction together.
	for i in 12:
		box(Vector3(40, 0.07, -100 - i * 5.0), Vector3(10, 0.14, 0.7), "ramp")


func _stunt_course() -> void:
	# Replica of the reveal stunt: an inverted ramp that curls 150 degrees and
	# throws the car off upside down. Flip it with the arrows, or let the
	# jets right it and land.
	var inv := Surface.new(self, _material("wall_ride"))
	inv.arc(Vector3(230, 0, 40), 9.0, 9.0, 0.0, deg_to_rad(150.0), 90)
	inv.finish()
	_sign(Vector3(230, 2, 75), "INVERTED RAMP\nreveal stunt · 35+ m/s")
	box(Vector3(230, 0.02, 110), Vector3(9, 0.04, 140), "lane")

	# Jump the line-up: five cars and a Semi, then a landing ramp.
	wedge(Vector3(300, 0, -58), 0.0, 12.0, 16.0, 4.0, "ramp")
	for i in 5:
		_vehicle(Vector3(300, 0, -72.0 - i * 2.6), Vector3(4.7, 1.4, 1.95), Color.from_hsv(i * 0.17, 0.5, 0.7), 1900.0)
	_semi(Vector3(300, 0, -88.5))
	wedge(Vector3(300, 0, -110), PI, 14.0, 16.0, 4.0, "ramp")
	_sign(Vector3(312, 2, -40), "JUMP THE LINE-UP\n5 cars + Semi")

	# Steep flip kicker and a mega ramp for big air.
	wedge(Vector3(40, 0, -60), 0.0, 8.0, 6.0, 3.5, "ramp")
	_sign(Vector3(40, 5, -52), "FLIP KICKER")
	wedge(Vector3(200, 0, -150), 0.0, 14.0, 40.0, 14.0, "ramp")
	_sign(Vector3(200, 2, -122), "MEGA RAMP  ·  14 m")


func _vehicle(base: Vector3, size: Vector3, color: Color, mass: float) -> void:
	var body := RigidBody3D.new()
	body.mass = mass
	body.position = base + Vector3.UP * (size.y * 0.5 + 0.15)
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = 0.4
	m.roughness = 0.35
	var parts := [[Vector3.ZERO, size]]
	if mass < 5000.0:    # cars get a cabin
		parts.append([Vector3(0.3, size.y * 0.75, 0), Vector3(size.x * 0.5, size.y * 0.5, size.z * 0.9)])
	for part in parts:
		var shape := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = part[1]
		shape.shape = bs
		shape.position = part[0]
		body.add_child(shape)
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = part[1]
		mi.mesh = bm
		mi.position = part[0]
		mi.material_override = m
		body.add_child(mi)
	add_child(body)


func _semi(base: Vector3) -> void:
	_vehicle(base, Vector3(14.0, 3.0, 2.6), Color(0.85, 0.85, 0.88), 9000.0)
	_vehicle(base + Vector3(8.6, 0, 0), Vector3(2.6, 2.0, 2.6), Color(0.2, 0.22, 0.25), 8000.0)


## A smooth curved surface (loop, quarter-pipe, wall) built as one
## triangle mesh with a matching concave collision shape. One continuous
## surface avoids the "ghost" bumps a car gets from the seams between
## separate boxes, which matters at loop speeds.
class Surface:
	var st := SurfaceTool.new()
	var faces := PackedVector3Array()
	var _mat: Material
	var _parent: Node3D

	func _init(parent: Node3D, mat: Material) -> void:
		_parent = parent
		_mat = mat
		st.begin(Mesh.PRIMITIVE_TRIANGLES)

	## pts[i][j] is a grid of points; nrm[i] is the drivable-side normal for row i
	## (or nrm[i][j] when it is an array).
	func grid(pts: Array, nrm: Array) -> void:
		for i in pts.size() - 1:
			for j in pts[i].size() - 1:
				var a: Vector3 = pts[i][j]
				var b: Vector3 = pts[i + 1][j]
				var c: Vector3 = pts[i + 1][j + 1]
				var d: Vector3 = pts[i][j + 1]
				var na: Vector3 = nrm[i][j] if nrm[i] is Array else nrm[i]
				var nb: Vector3 = nrm[i + 1][j] if nrm[i + 1] is Array else nrm[i + 1]
				var nc: Vector3 = nrm[i + 1][j + 1] if nrm[i + 1] is Array else nrm[i + 1]
				var nd: Vector3 = nrm[i][j + 1] if nrm[i] is Array else nrm[i]
				_tri(a, b, c, na, nb, nc)
				_tri(a, c, d, na, nc, nd)

	func _tri(a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3) -> void:
		# Godot's front faces wind clockwise as seen from the front.
		if (b - a).cross(c - a).dot(na + nb + nc) > 0.0:
			var t := b
			b = c
			c = t
			var tn := nb
			nb = nc
			nc = tn
		for v in [[a, na], [b, nb], [c, nc]]:
			st.set_normal(v[1])
			st.add_vertex(v[0])
			faces.append(v[0])

	## Quarter-pipe profile of radius r rising toward o, topped by a vertical
	## wall of wall_h. Returns [points, normals] relative to the profile base.
	static func _profile(o: Vector3, r: float, wall_h: float) -> Array:
		var pts := []
		var nrm := []
		var steps := maxi(16, int(r * 4.0))
		for k in steps + 1:
			var a := float(k) / steps * PI * 0.5
			pts.append(o * (r * sin(a)) + Vector3.UP * (r - r * cos(a)))
			nrm.append(Vector3.UP * cos(a) - o * sin(a))
		if wall_h > 0.0:
			pts.append(o * r + Vector3.UP * (r + wall_h))
			nrm.append(-o)
		return [pts, nrm]

	## Straight quarter-pipe + wall, extruded `along` metres in direction t.
	func wall_profile(base: Vector3, o: Vector3, t: Vector3, along: float, r: float, wall_h: float) -> void:
		var prof := _profile(o, r, wall_h)
		var pts := []
		for p in prof[0]:
			pts.append([base + p - t * along * 0.5, base + p + t * along * 0.5])
		grid(pts, prof[1])

	## Quarter-pipe + wall swept round a circle of radius r0 (a bowl / wall of
	## death) between angles phi0 and phi1.
	func ring_wall(centre: Vector3, r0: float, r: float, wall_h: float, phi0: float, phi1: float, segs: int) -> void:
		var pts := []
		var nrm := []
		var n_rows := 0
		for j in segs + 1:
			var phi := lerpf(phi0, phi1, float(j) / segs)
			var o := Vector3(cos(phi), 0, sin(phi))
			var prof := _profile(o, r, wall_h)
			n_rows = prof[0].size()
			for i in n_rows:
				if j == 0:
					pts.append([])
					nrm.append([])
				pts[i].append(centre + o * r0 + prof[0][i])
				nrm[i].append(prof[1][i])
		grid(pts, nrm)

	## Vertical arc (loop) starting flat at `start` heading -Z, sweeping
	## `sweep` radians and drifting `shift` metres sideways per full turn.
	func arc(start: Vector3, r: float, width: float, shift: float, sweep: float, steps: int) -> void:
		var pts := []
		var nrm := []
		for i in steps + 1:
			var th := float(i) / steps * sweep
			var p := start + Vector3(shift * th / TAU, r - r * cos(th), -r * sin(th))
			var n := Vector3(0, cos(th), sin(th))
			var tng := Vector3(shift / TAU, r * sin(th), -r * cos(th)).normalized()
			var x := tng.cross(n).normalized()
			pts.append([p - x * width * 0.5, p + x * width * 0.5])
			nrm.append(n)
		grid(pts, nrm)

	func finish() -> void:
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		mi.material_override = _mat
		var body := StaticBody3D.new()
		body.add_child(mi)
		var shape := CollisionShape3D.new()
		var cps := ConcavePolygonShape3D.new()
		cps.set_faces(faces)
		cps.backface_collision = true
		shape.shape = cps
		body.add_child(shape)
		_parent.add_child(body)
