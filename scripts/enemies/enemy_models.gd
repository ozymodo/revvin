extends RefCounted
## Procedural models for the enemies, built at unit size (the enemy scales
## them). Meshes and materials are shared between instances.
##   bee     scrap-metal bee with goo stripes, red eyes and flapping wings
##   roller  a spherical tyre: knobbly tread, metal hubs, a glowing goo seam
##   hopper  a simplified mechanical frog with big glowing eyes and folding legs

static var _mats := {}
static var _meshes := {}


static func mat(key: String) -> Material:
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	match key:
		"scrap":
			m.albedo_color = Color(0.42, 0.3, 0.22)
			m.metallic = 0.75
			m.roughness = 0.55
		"dark":
			m.albedo_color = Color(0.13, 0.13, 0.15)
			m.metallic = 0.7
			m.roughness = 0.45
		"steel":
			m.albedo_color = Color(0.55, 0.57, 0.6)
			m.metallic = 0.9
			m.roughness = 0.3
		"rubber":
			m.albedo_color = Color(0.07, 0.07, 0.08)
			m.roughness = 0.95
		"frog":
			m.albedo_color = Color(0.32, 0.42, 0.3)
			m.metallic = 0.6
			m.roughness = 0.45
		"goo":
			m.albedo_color = Color(0.15, 0.6, 0.2)
			m.emission_enabled = true
			m.emission = Color(0.25, 1.0, 0.35)
			m.emission_energy_multiplier = 2.5
			m.roughness = 0.15
		"eye_red":
			m.albedo_color = Color(0.4, 0.02, 0.02)
			m.emission_enabled = true
			m.emission = Color(1.0, 0.15, 0.1)
			m.emission_energy_multiplier = 4.0
		"eye_yellow":
			m.albedo_color = Color(0.5, 0.45, 0.05)
			m.emission_enabled = true
			m.emission = Color(1.0, 0.85, 0.2)
			m.emission_energy_multiplier = 3.0
		"pupil":
			m.albedo_color = Color(0.02, 0.02, 0.02)
			m.roughness = 0.2
		"wing":
			m.albedo_color = Color(0.6, 0.85, 0.75, 0.35)
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
			m.metallic = 0.4
			m.roughness = 0.1
			m.emission_enabled = true
			m.emission = Color(0.2, 0.6, 0.35)
			m.emission_energy_multiplier = 0.4
	_mats[key] = m
	return m


static func _sphere(r: float, segs := 16) -> SphereMesh:
	var key := "sphere_%.3f_%d" % [r, segs]
	if not _meshes.has(key):
		var s := SphereMesh.new()
		s.radius = r
		s.height = r * 2.0
		s.radial_segments = segs
		s.rings = segs / 2
		_meshes[key] = s
	return _meshes[key]


static func _box(size: Vector3) -> BoxMesh:
	var key := "box_%s" % size
	if not _meshes.has(key):
		var b := BoxMesh.new()
		b.size = size
		_meshes[key] = b
	return _meshes[key]


static func _cyl(top: float, bottom: float, h: float, segs := 10) -> CylinderMesh:
	var key := "cyl_%.3f_%.3f_%.3f" % [top, bottom, h]
	if not _meshes.has(key):
		var c := CylinderMesh.new()
		c.top_radius = top
		c.bottom_radius = bottom
		c.height = h
		c.radial_segments = segs
		_meshes[key] = c
	return _meshes[key]


static func _torus(inner: float, outer: float) -> TorusMesh:
	var key := "torus_%.3f_%.3f" % [inner, outer]
	if not _meshes.has(key):
		var t := TorusMesh.new()
		t.inner_radius = inner
		t.outer_radius = outer
		t.rings = 24
		t.ring_segments = 8
		_meshes[key] = t
	return _meshes[key]


static func _part(parent: Node3D, mesh: Mesh, material: String, pos: Vector3, rot := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat(material)
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	parent.add_child(mi)
	return mi


## Scrap bee. Faces -Z. Returns the root; wing pivots are named Wing_*.
## Breakable bits: Wing_*, Stinger, Plate_*, Leg_*.
static func bee() -> Node3D:
	var root := Node3D.new()
	_part(root, _sphere(0.35), "dark", Vector3.ZERO)                                 # thorax
	_part(root, _sphere(0.45), "scrap", Vector3(0, -0.05, 0.6), Vector3.ZERO, Vector3(1, 0.9, 1.3))  # abdomen
	for z in [0.45, 0.72]:
		_part(root, _torus(0.38, 0.47), "goo", Vector3(0, -0.05, z), Vector3(PI * 0.5, 0, 0), Vector3(1, 1, 0.95))
	_part(root, _sphere(0.26), "scrap", Vector3(0, 0.05, -0.45))                    # head
	for x in [-0.13, 0.13]:
		_part(root, _sphere(0.1, 10), "eye_red", Vector3(x, 0.12, -0.62))
	_part(root, _cyl(0.0, 0.09, 0.4), "steel", Vector3(0, -0.1, 1.15), Vector3(-PI * 0.5, 0, 0)).name = "Stinger"
	# Scrap plates bolted on at odd angles.
	var plates := [[Vector3(0.18, 0.28, 0.05), Vector3(0.3, 0.2, 0.4)], [Vector3(-0.22, 0.22, 0.45), Vector3(-0.2, 0.5, -0.3)],
		[Vector3(0.0, 0.3, 0.75), Vector3(0.6, 0.0, 0.2)]]
	for i in plates.size():
		_part(root, _box(Vector3(0.28, 0.04, 0.24)), "steel", plates[i][0], plates[i][1]).name = "Plate_%d" % i
	# Antennae
	for x in [-0.1, 0.1]:
		_part(root, _cyl(0.01, 0.015, 0.4, 6), "dark", Vector3(x, 0.32, -0.6), Vector3(-0.6, 0, x * 3.0))
	# Legs dangling
	for z in [-0.1, 0.15]:
		for x in [-1.0, 1.0]:
			_part(root, _cyl(0.015, 0.02, 0.45, 6), "dark", Vector3(x * 0.2, -0.38, z), Vector3(0.3, 0, x * 0.4)).name = "Leg_%d_%d" % [int(x), int(z * 10)]
	# Wings on pivots so they can flap.
	for side in [-1.0, 1.0]:
		for k in 2:
			var pivot := Node3D.new()
			pivot.name = "Wing_%d_%d" % [int(side), k]
			pivot.position = Vector3(side * 0.15, 0.3, -0.1 + k * 0.28)
			root.add_child(pivot)
			_part(pivot, _box(Vector3(0.75, 0.015, 0.32 - k * 0.06)), "wing", Vector3(side * 0.4, 0, 0))
	return root


## Spherical tyre, radius 1. The body rolls, so the model just rides along.
## Breakable bits: the tread in four patches (Tread_*), the hubs (Hub_L/R).
static func roller() -> Node3D:
	var root := Node3D.new()
	_part(root, _sphere(0.9, 24), "rubber", Vector3.ZERO)
	# Knobbly tread: rows of blocks over the sphere, in four patches round
	# the axle (a MultiMesh each) so it can lose a patch at a time.
	var patches: Array = [[], [], [], []]
	for row in range(-3, 4):
		var lat := row * 0.36
		var n := int(round(14 * cos(lat))) + 2
		for i in n:
			var lon := (i + (0.5 if row % 2 != 0 else 0.0)) * TAU / n
			var dir := Vector3(cos(lat) * cos(lon), sin(lat), cos(lat) * sin(lon))
			var b := Basis.looking_at(dir.cross(Vector3.UP).normalized() if absf(dir.y) < 0.98 else Vector3.RIGHT, dir)
			# Patches split by the angle round the X axle (the hubs' axis).
			var k := int(fposmod(atan2(dir.z, dir.y), TAU) / (TAU / 4.0)) % 4
			patches[k].append(Transform3D(b, dir * 0.93))
	for k in 4:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _box(Vector3(0.24, 0.13, 0.2))
		mm.instance_count = patches[k].size()
		for i in patches[k].size():
			mm.set_instance_transform(i, patches[k][i])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Tread_%d" % k
		mmi.multimesh = mm
		mmi.material_override = mat("rubber")
		root.add_child(mmi)
	# Metal hubs at the poles, one with a glowing eye; a goo seam round the middle.
	for sgn in [-1.0, 1.0]:
		var hub := Node3D.new()
		hub.name = "Hub_" + ("L" if sgn < 0 else "R")
		root.add_child(hub)
		_part(hub, _cyl(0.35, 0.35, 0.12, 16), "steel", Vector3(sgn * 0.88, 0, 0), Vector3(0, 0, PI * 0.5))
		for k in 5:
			var a := k * TAU / 5.0
			_part(hub, _cyl(0.04, 0.04, 0.14, 6), "dark", Vector3(sgn * 0.92, cos(a) * 0.22, sin(a) * 0.22), Vector3(0, 0, PI * 0.5))
		if sgn > 0:
			_part(hub, _cyl(0.12, 0.12, 0.05, 12), "eye_red", Vector3(0.96, 0, 0), Vector3(0, 0, PI * 0.5))
	_part(root, _torus(0.86, 0.94), "goo", Vector3.ZERO, Vector3(0, 0, PI * 0.5))
	return root


## Mechanical frog, about 1.3 m long at unit size, sitting on y = 0.
## Faces -Z. Back-leg pivots are named Thigh_L / Thigh_R.
## Breakable bits: Thigh_L/R, Arm_L/R (front legs), Eye_L/R, HeadPlate.
static func hopper() -> Node3D:
	var root := Node3D.new()
	_part(root, _sphere(0.5), "frog", Vector3(0, 0.45, 0), Vector3(0.15, 0, 0), Vector3(1.1, 0.7, 1.3))   # body
	_part(root, _box(Vector3(0.72, 0.22, 0.42)), "dark", Vector3(0, 0.62, -0.42), Vector3(0.25, 0, 0)).name = "HeadPlate"
	_part(root, _sphere(0.2), "goo", Vector3(0, 0.32, -0.55)).name = "Throat"                         # throat sac
	for x in [-0.27, 0.27]:
		var eye := Node3D.new()
		eye.name = "Eye_" + ("L" if x < 0 else "R")
		eye.position = Vector3(x, 0.86, -0.42)
		root.add_child(eye)
		_part(eye, _sphere(0.18), "eye_yellow", Vector3.ZERO)
		_part(eye, _sphere(0.08, 8), "pupil", Vector3(0, 0.02, -0.16))
		_part(eye, _torus(0.16, 0.21), "steel", Vector3(0, 0, -0.01), Vector3(PI * 0.5, 0, 0))     # eye rims
	# Front legs
	for x in [-0.3, 0.3]:
		var arm := Node3D.new()
		arm.name = "Arm_" + ("L" if x < 0 else "R")
		arm.position = Vector3(x, 0.2, -0.42)
		root.add_child(arm)
		_part(arm, _cyl(0.05, 0.06, 0.42, 8), "steel", Vector3.ZERO, Vector3(0.2, 0, x * 0.5))
		_part(arm, _box(Vector3(0.18, 0.04, 0.16)), "dark", Vector3(x * 0.15, -0.18, -0.08))
	# Back legs on pivots: thigh, shin, foot.
	for side in [-1.0, 1.0]:
		var thigh := Node3D.new()
		thigh.name = "Thigh_" + ("L" if side < 0 else "R")
		thigh.position = Vector3(side * 0.45, 0.42, 0.3)
		root.add_child(thigh)
		_part(thigh, _box(Vector3(0.16, 0.16, 0.6)), "frog", Vector3(0, 0, 0.28))
		_part(thigh, _cyl(0.06, 0.06, 0.2, 8), "steel", Vector3(0, 0, 0), Vector3(0, 0, PI * 0.5))     # hip joint
		var shin := Node3D.new()
		shin.name = "Shin"
		shin.position = Vector3(0, 0, 0.56)
		thigh.add_child(shin)
		_part(shin, _box(Vector3(0.1, 0.5, 0.1)), "steel", Vector3(0, -0.22, 0))
		_part(shin, _cyl(0.035, 0.035, 0.45, 6), "goo", Vector3(0.07, -0.2, 0))                          # piston
		_part(shin, _box(Vector3(0.24, 0.04, 0.36)), "dark", Vector3(0, -0.46, -0.12))                  # foot
	return root
