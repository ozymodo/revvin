extends RefCounted
## Procedural models for the four beasts, built at real size in metres,
## facing -Z, standing on y = 0.
##
##   animal(kind)  the living animal: gorilla, rex (a young T. rex), spider
##                 or elephant. Natural colours, a few moving pivots.
##   mech(kind)    its boss: the same animal rebuilt as a high-tech monster
##                 truck. Gunmetal armour over living parts (moss, bark,
##                 hide), glowing veins in the boss colour, and big knobbly
##                 wheels where it needs to move. Wheel pivots are named
##                 Wheel_*, and spin about their local X.
##
## Named pivots the scripts animate: Leg_* (legs), Arm_L/R, Head, Jaw,
## Tail, Trunk, Ear_L/R, Core (the glowing heart, flashes on attacks).

## Boss accent colours (veins, eyes, cores).
const ACCENT := {
	"gorilla": Color(1.0, 0.5, 0.12),
	"rex": Color(1.0, 0.18, 0.12),
	"spider": Color(0.72, 0.3, 1.0),
	"elephant": Color(0.2, 0.9, 1.0),
}

static var _mats := {}
static var _meshes := {}


static func mat(c: Color, metal := 0.0, rough := 0.8, glow := 0.0) -> StandardMaterial3D:
	var key := "%s|%.2f|%.2f|%.2f" % [c.to_html(), metal, rough, glow]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metal
	m.roughness = rough
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = glow
	_mats[key] = m
	return m


# Material palette.
static func ARMOR() -> Material: return mat(Color(0.17, 0.18, 0.2), 0.85, 0.35)
static func PLATE() -> Material: return mat(Color(0.42, 0.44, 0.47), 0.8, 0.4)
static func MOSS() -> Material: return mat(Color(0.2, 0.34, 0.12), 0.0, 0.95)
static func BARK() -> Material: return mat(Color(0.27, 0.19, 0.12), 0.0, 0.9)
static func TIRE() -> Material: return mat(Color(0.06, 0.06, 0.07), 0.0, 0.95)
static func CHROME() -> Material: return mat(Color(0.7, 0.72, 0.75), 1.0, 0.18)
static func IVORY() -> Material: return mat(Color(0.88, 0.84, 0.72), 0.0, 0.5)
static func GLOW(kind: String, k := 4.0) -> Material: return mat(ACCENT[kind], 0.0, 0.3, k)


static func _sphere(r: float) -> SphereMesh:
	var key := "s%.3f" % r
	if not _meshes.has(key):
		var s := SphereMesh.new()
		s.radius = r
		s.height = r * 2.0
		s.radial_segments = 14
		s.rings = 8
		_meshes[key] = s
	return _meshes[key]


static func _box(s: Vector3) -> BoxMesh:
	var key := "b%s" % s
	if not _meshes.has(key):
		var b := BoxMesh.new()
		b.size = s
		_meshes[key] = b
	return _meshes[key]


static func _cyl(top: float, bottom: float, h: float, segs := 10) -> CylinderMesh:
	var key := "c%.3f_%.3f_%.3f_%d" % [top, bottom, h, segs]
	if not _meshes.has(key):
		var c := CylinderMesh.new()
		c.top_radius = top
		c.bottom_radius = bottom
		c.height = h
		c.radial_segments = segs
		c.rings = 1
		_meshes[key] = c
	return _meshes[key]


static func _torus(inner: float, outer: float) -> TorusMesh:
	var key := "t%.3f_%.3f" % [inner, outer]
	if not _meshes.has(key):
		var t := TorusMesh.new()
		t.inner_radius = inner
		t.outer_radius = outer
		t.rings = 20
		t.ring_segments = 8
		_meshes[key] = t
	return _meshes[key]


static func part(parent: Node3D, mesh: Mesh, m: Material, pos: Vector3, rot := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	parent.add_child(mi)
	return mi


static func pivot(parent: Node3D, name: String, pos: Vector3) -> Node3D:
	var p := Node3D.new()
	p.name = name
	p.position = pos
	parent.add_child(p)
	return p


## A box of `thick` running from a to b (local to parent).
static func strut(parent: Node3D, a: Vector3, b: Vector3, thick: float, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var len := a.distance_to(b)
	mi.mesh = _box(Vector3(thick, thick, len).snapped(Vector3.ONE * 0.01))
	mi.material_override = m
	parent.add_child(mi)
	var up := Vector3.UP if absf((b - a).normalized().y) < 0.95 else Vector3.RIGHT
	mi.transform = Transform3D(Basis.looking_at(b - a, up), (a + b) * 0.5)
	return mi


## A monster-truck wheel: knobbly tyre, chrome rim, glowing hub ring.
## Rolls about its local X axis.
static func wheel(parent: Node3D, name: String, pos: Vector3, r: float, w: float, kind: String) -> Node3D:
	var p := pivot(parent, name, pos)
	part(p, _cyl(r, r, w, 18), TIRE(), Vector3.ZERO, Vector3(0, 0, PI * 0.5))
	for k in 10:
		var a := k * TAU / 10.0
		part(p, _box(Vector3(w * 1.04, r * 0.22, r * 0.3)), TIRE(), Vector3(0, cos(a), sin(a)) * r * 0.98, Vector3(a, 0, 0))
	for sgn in [-1.0, 1.0]:
		part(p, _cyl(r * 0.55, r * 0.55, 0.06, 14), CHROME(), Vector3(sgn * w * 0.5, 0, 0), Vector3(0, 0, PI * 0.5))
		part(p, _torus(r * 0.22, r * 0.3), GLOW(kind, 3.0), Vector3(sgn * (w * 0.5 + 0.04), 0, 0), Vector3(0, 0, PI * 0.5))
	return p


## Tufts of moss / leaves clinging to the armour: the "natural" half.
static func moss(parent: Node3D, at: Vector3, spread: float, n: int, seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	for i in n:
		var o := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.3, 0.4), rng.randf_range(-1, 1)) * spread
		part(parent, _sphere(rng.randf_range(0.2, 0.45) * spread), MOSS(), at + o, Vector3.ZERO, Vector3(1.0, 0.45, 1.0))


static func _visible_range(root: Node3D, end: float) -> void:
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).visibility_range_end = end
		(mi as MeshInstance3D).visibility_range_end_margin = end * 0.1
		(mi as MeshInstance3D).visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF


# ================================================================== animals

static func animal(kind: String) -> Node3D:
	var root := Node3D.new()
	match kind:
		"gorilla":
			var fur := mat(Color(0.1, 0.1, 0.11), 0.0, 0.95)
			var skin := mat(Color(0.2, 0.18, 0.17), 0.0, 0.7)
			part(root, _sphere(0.5), fur, Vector3(0, 1.05, 0.05), Vector3(0.35, 0, 0), Vector3(1.5, 1.6, 1.25))
			part(root, _box(Vector3(0.75, 0.25, 0.7)), mat(Color(0.55, 0.55, 0.56), 0.0, 0.9), Vector3(0, 1.32, 0.35), Vector3(0.35, 0, 0))   # silver back
			var head := pivot(root, "Head", Vector3(0, 1.55, -0.45))
			part(head, _sphere(0.26), fur, Vector3.ZERO, Vector3.ZERO, Vector3(1, 1.1, 1))
			part(head, _box(Vector3(0.36, 0.12, 0.14)), skin, Vector3(0, 0.08, -0.2))             # brow
			part(head, _sphere(0.15), skin, Vector3(0, -0.1, -0.2), Vector3.ZERO, Vector3(1.2, 0.8, 0.8))   # muzzle
			for sx in [-1.0, 1.0]:
				var arm := pivot(root, "Leg_F" + ("L" if sx < 0 else "R"), Vector3(sx * 0.55, 1.4, -0.25))
				part(arm, _cyl(0.13, 0.17, 1.35), fur, Vector3(0, -0.62, -0.15), Vector3(-0.2, 0, 0))
				part(arm, _sphere(0.15), skin, Vector3(0, -1.32, -0.3))
				var leg := pivot(root, "Leg_B" + ("L" if sx < 0 else "R"), Vector3(sx * 0.35, 0.75, 0.45))
				part(leg, _cyl(0.14, 0.16, 0.75), fur, Vector3(0, -0.38, 0))
				part(leg, _box(Vector3(0.18, 0.08, 0.32)), skin, Vector3(0, -0.74, -0.08))
		"rex":
			var hide := mat(Color(0.33, 0.37, 0.2), 0.0, 0.8)
			var belly := mat(Color(0.62, 0.58, 0.4), 0.0, 0.8)
			part(root, _sphere(0.8), hide, Vector3(0, 1.9, 0.1), Vector3(-0.15, 0, 0), Vector3(1.0, 1.1, 1.9))
			part(root, _sphere(0.6), belly, Vector3(0, 1.6, -0.2), Vector3(-0.15, 0, 0), Vector3(0.95, 0.9, 1.6))
			var tail := pivot(root, "Tail", Vector3(0, 2.0, 1.3))
			part(tail, _cyl(0.08, 0.55, 2.8), hide, Vector3(0, -0.25, 1.35), Vector3(PI * 0.5 + 0.18, 0, 0))
			var head := pivot(root, "Head", Vector3(0, 2.65, -1.2))
			part(head, _box(Vector3(0.62, 0.58, 1.15)), hide, Vector3(0, 0.1, -0.45))
			part(head, _box(Vector3(0.5, 0.06, 0.95)), mat(Color(0.95, 0.92, 0.8)), Vector3(0, -0.2, -0.5))   # teeth
			var jaw := pivot(head, "Jaw", Vector3(0, -0.2, 0.0))
			part(jaw, _box(Vector3(0.55, 0.18, 1.0)), belly, Vector3(0, -0.08, -0.48))
			for sx in [-1.0, 1.0]:
				part(head, _sphere(0.06), mat(Color(0.9, 0.7, 0.1), 0.0, 0.3, 1.0), Vector3(sx * 0.3, 0.3, -0.3))
				part(root, _cyl(0.04, 0.06, 0.4), hide, Vector3(sx * 0.35, 1.9, -0.95), Vector3(0.8, 0, 0))     # tiny arm
				var leg := pivot(root, "Leg_B" + ("L" if sx < 0 else "R"), Vector3(sx * 0.55, 1.75, 0.25))
				part(leg, _box(Vector3(0.38, 1.0, 0.55)), hide, Vector3(0, -0.4, 0.05))
				part(leg, _cyl(0.1, 0.14, 0.9), hide, Vector3(0, -1.2, 0.15))
				part(leg, _box(Vector3(0.36, 0.1, 0.6)), belly, Vector3(0, -1.68, -0.12))
		"spider":
			var chitin := mat(Color(0.07, 0.06, 0.07), 0.3, 0.45)
			part(root, _sphere(0.24), chitin, Vector3(0, 0.45, -0.15), Vector3.ZERO, Vector3(1.0, 0.7, 1.1))
			part(root, _sphere(0.34), chitin, Vector3(0, 0.55, 0.4), Vector3.ZERO, Vector3(1.0, 0.85, 1.2))
			part(root, _box(Vector3(0.12, 0.02, 0.2)), mat(Color(0.8, 0.1, 0.05), 0.0, 0.4, 0.6), Vector3(0, 0.83, 0.4))   # red mark
			for sx in [-1.0, 1.0]:
				part(root, _sphere(0.05), mat(Color(0.5, 0.05, 0.05), 0.0, 0.2, 0.8), Vector3(sx * 0.07, 0.55, -0.36))
				for i in 4:
					var z := -0.3 + i * 0.12
					var leg := pivot(root, "Leg_%d%s" % [i, "L" if sx < 0 else "R"], Vector3(sx * 0.15, 0.48, z))
					var knee := Vector3(sx * 0.45, 0.35, (z + 0.05) * 1.6)
					var foot := Vector3(sx * 0.75, -0.48, (z + 0.05) * 2.6)
					strut(leg, Vector3.ZERO, knee, 0.05, chitin)
					strut(leg, knee, foot, 0.04, chitin)
		"elephant":
			var skin := mat(Color(0.42, 0.4, 0.38), 0.0, 0.9)
			part(root, _sphere(1.0), skin, Vector3(0, 2.1, 0.1), Vector3.ZERO, Vector3(1.4, 1.35, 1.95))
			var head := pivot(root, "Head", Vector3(0, 2.55, -1.75))
			part(head, _sphere(0.75), skin, Vector3.ZERO, Vector3.ZERO, Vector3(1.0, 1.05, 0.95))
			for sx in [-1.0, 1.0]:
				var ear := pivot(head, "Ear_" + ("L" if sx < 0 else "R"), Vector3(sx * 0.6, 0.1, 0.25))
				part(ear, _cyl(0.75, 0.75, 0.06, 14), mat(Color(0.47, 0.42, 0.4), 0.0, 0.9), Vector3(sx * 0.55, -0.1, 0), Vector3(0, 0, PI * 0.5))
				var tusk := part(head, _cyl(0.02, 0.08, 0.9), IVORY(), Vector3(sx * 0.3, -0.5, -0.65), Vector3(-1.2, 0, 0))
				tusk.name = "Tusk"
				var leg := pivot(root, "Leg_" + ("F" if sx < 0 else "F") + ("L" if sx < 0 else "R"), Vector3(sx * 0.8, 1.6, -0.9))
				part(leg, _cyl(0.33, 0.36, 1.6), skin, Vector3(0, -0.8, 0))
				var leg2 := pivot(root, "Leg_B" + ("L" if sx < 0 else "R"), Vector3(sx * 0.8, 1.6, 1.1))
				part(leg2, _cyl(0.33, 0.36, 1.6), skin, Vector3(0, -0.8, 0))
			var trunk := pivot(head, "Trunk", Vector3(0, -0.2, -0.65))
			part(trunk, _cyl(0.12, 0.24, 1.0), skin, Vector3(0, -0.45, -0.1), Vector3(0.2, 0, 0))
			part(trunk, _cyl(0.09, 0.12, 0.9), skin, Vector3(0, -1.25, -0.15), Vector3(-0.1, 0, 0))
	_visible_range(root, 260.0)
	return root


# ================================================================== bosses

static func mech(kind: String) -> Node3D:
	var root := Node3D.new()
	match kind:
		"gorilla":
			_mech_gorilla(root)
		"rex":
			_mech_rex(root)
		"spider":
			_mech_spider(root)
		"elephant":
			_mech_elephant(root)
	return root


## SILVERBACK: a monster-truck chassis with a hulking gorilla torso riding
## on it, huge piston arms that knuckle down to the road on armoured fists.
static func _mech_gorilla(root: Node3D) -> void:
	var k := "gorilla"
	var fur := mat(Color(0.16, 0.14, 0.13), 0.25, 0.8)
	part(root, _box(Vector3(3.8, 1.0, 5.2)), ARMOR(), Vector3(0, 1.9, 0.3))
	part(root, _box(Vector3(3.2, 0.12, 4.6)), GLOW(k, 2.5), Vector3(0, 1.38, 0.3))       # under-glow strip
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			wheel(root, "Wheel_%d%d" % [int(sx), int(sz)], Vector3(sx * 2.25, 1.35, 0.3 + sz * 1.85), 1.35, 1.1, k)
			part(root, _box(Vector3(1.3, 0.25, 2.2)), PLATE(), Vector3(sx * 2.25, 2.85, 0.3 + sz * 1.85), Vector3(0, 0, sx * 0.15))   # fenders
	# Torso: dark fibre muscle with plate armour, a silver saddle and a core.
	part(root, _sphere(1.0), fur, Vector3(0, 4.0, 0.0), Vector3(0.35, 0, 0), Vector3(2.3, 2.1, 1.9))
	part(root, _box(Vector3(2.6, 0.5, 2.0)), PLATE(), Vector3(0, 5.3, 0.8), Vector3(0.4, 0, 0))     # silver back
	part(root, _box(Vector3(2.4, 1.6, 0.4)), ARMOR(), Vector3(0, 3.9, -1.75), Vector3(-0.2, 0, 0))   # chest plate
	var core := part(root, _sphere(0.45), GLOW(k, 5.0), Vector3(0, 4.0, -1.95))
	core.name = "Core"
	for i in 4:
		part(root, _box(Vector3(2.2 - i * 0.3, 0.06, 0.05)), GLOW(k, 3.0), Vector3(0, 4.6 - i * 0.35, -1.98), Vector3(-0.2, 0, 0))  # ribs
	moss(root, Vector3(0, 5.5, 0.7), 1.3, 9, 11)
	for sx in [-1.0, 1.0]:
		part(root, _cyl(0.22, 0.28, 1.6), CHROME(), Vector3(sx * 0.9, 6.0, 1.6), Vector3(-0.2, 0, 0))     # exhaust stacks
		part(root, _cyl(0.24, 0.24, 0.12), GLOW(k, 6.0), Vector3(sx * 0.9, 6.8, 1.75), Vector3(-0.2, 0, 0))
	# Head: thrust forward between the shoulders, a heavy armoured brow
	# over glowing eyes, a big plated muzzle.
	var head := pivot(root, "Head", Vector3(0, 5.5, -2.0))
	part(head, _sphere(1.0), fur, Vector3(0, 0.2, 0.1), Vector3.ZERO, Vector3(1.05, 1.0, 1.0))
	part(head, _sphere(0.6), fur, Vector3(0, 1.0, 0.3), Vector3.ZERO, Vector3(1.2, 0.8, 1.3))       # crest
	part(head, _box(Vector3(2.0, 0.42, 0.7)), PLATE(), Vector3(0, 0.55, -0.75), Vector3(0.25, 0, 0))   # brow
	for sx in [-1.0, 1.0]:
		part(head, _sphere(0.17), GLOW(k, 7.0), Vector3(sx * 0.42, 0.25, -0.92))                     # eyes
	part(head, _box(Vector3(1.0, 0.1, 0.06)), GLOW(k, 4.0), Vector3(0, 0.05, -1.05))
	var jaw := pivot(head, "Jaw", Vector3(0, -0.25, -0.5))
	part(jaw, _box(Vector3(1.5, 0.75, 1.0)), PLATE(), Vector3(0, -0.2, -0.45))                       # muzzle
	part(jaw, _box(Vector3(1.2, 0.08, 0.06)), GLOW(k, 3.0), Vector3(0, -0.1, -0.97))
	for sx in [-1.0, 1.0]:
		part(jaw, _cyl(0.0, 0.08, 0.35, 5), CHROME(), Vector3(sx * 0.45, 0.1, -0.9))                     # fangs
	# Arms: shoulder ball, piston upper arm, forearm, big fist.
	for sx in [-1.0, 1.0]:
		var arm := pivot(root, "Arm_" + ("L" if sx < 0 else "R"), Vector3(sx * 2.35, 4.8, -0.6))
		part(arm, _sphere(0.95), PLATE(), Vector3.ZERO)
		part(arm, _torus(0.8, 1.0), GLOW(k, 3.0), Vector3(sx * 0.15, 0, 0), Vector3(0, 0, PI * 0.5))
		strut(arm, Vector3.ZERO, Vector3(sx * 0.6, -2.0, -1.0), 0.75, fur)
		strut(arm, Vector3(sx * 0.6, -2.0, -1.0), Vector3(sx * 0.7, -3.6, -2.1), 0.85, ARMOR())
		part(arm, _cyl(0.12, 0.12, 2.0), CHROME(), Vector3(sx * 0.9, -1.0, -0.4), Vector3(-0.45, 0, 0))   # piston
		part(arm, _box(Vector3(1.3, 1.0, 1.4)), PLATE(), Vector3(sx * 0.7, -3.85, -2.3))                # fist
		part(arm, _box(Vector3(1.32, 0.12, 1.42)), GLOW(k, 3.0), Vector3(sx * 0.7, -3.5, -2.3))
		moss(arm, Vector3(sx * 0.3, 0.6, 0.2), 0.7, 3, 20 + int(sx))


## TYRANT: a T. rex on two giant drive wheels for legs, balanced by a long
## tail that ends in a trailing wheel. Huge jaws, plasma throat.
static func _mech_rex(root: Node3D) -> void:
	var k := "rex"
	var hide := mat(Color(0.26, 0.3, 0.17), 0.1, 0.85)
	part(root, _sphere(1.0), ARMOR(), Vector3(0, 4.3, 0.5), Vector3(-0.15, 0, 0), Vector3(2.0, 2.1, 3.6))
	part(root, _sphere(1.0), hide, Vector3(0, 3.8, 0.0), Vector3(-0.15, 0, 0), Vector3(1.8, 1.7, 3.0))     # belly hide
	var core := part(root, _sphere(0.5), GLOW(k, 5.0), Vector3(0, 3.5, -1.9))
	core.name = "Core"
	for i in 7:                                                                                      # dorsal plates
		part(root, _box(Vector3(0.12, 0.9 - absf(i - 3) * 0.12, 0.7)), GLOW(k, 2.5), Vector3(0, 6.3 - absf(i - 3) * 0.15, -1.2 + i * 0.7), Vector3(0, 0, 0))
	moss(root, Vector3(0, 5.6, 1.4), 1.2, 7, 31)
	for sx in [-1.0, 1.0]:
		strut(root, Vector3(sx * 1.4, 4.3, 0.6), Vector3(sx * 2.0, 2.2, 0.9), 1.1, PLATE())           # thighs
		wheel(root, "Wheel_" + ("L" if sx < 0 else "R"), Vector3(sx * 2.15, 2.1, 0.9), 2.1, 1.3, k)
		part(root, _cyl(0.08, 0.12, 1.2), ARMOR(), Vector3(sx * 0.8, 3.7, -2.4), Vector3(1.0, 0, 0))   # tiny arms
		part(root, _box(Vector3(0.1, 0.1, 0.4)), CHROME(), Vector3(sx * 0.8, 3.2, -2.95), Vector3(0.4, 0, 0))
	var tail := pivot(root, "Tail", Vector3(0, 4.4, 3.4))
	strut(tail, Vector3.ZERO, Vector3(0, -0.8, 2.8), 1.4, ARMOR())
	strut(tail, Vector3(0, -0.8, 2.8), Vector3(0, -2.2, 5.6), 0.9, hide)
	for i in 4:
		part(tail, _box(Vector3(0.1, 0.5, 0.5)), GLOW(k, 2.5), Vector3(0, 0.6 - i * 0.55, 0.8 + i * 1.3))
	wheel(tail, "Wheel_Tail", Vector3(0, -3.1, 6.0), 0.9, 0.7, k)
	# Head on a thick neck, jaw on a hinge.
	var head := pivot(root, "Head", Vector3(0, 6.0, -2.8))
	strut(root, Vector3(0, 5.0, -1.6), Vector3(0, 6.0, -2.8), 1.3, hide)
	part(head, _box(Vector3(1.8, 1.4, 3.0)), ARMOR(), Vector3(0, 0.2, -1.2))
	part(head, _box(Vector3(1.85, 0.3, 2.2)), PLATE(), Vector3(0, 0.95, -1.4))                      # skull plate
	part(head, _box(Vector3(1.35, 1.0, 1.1)), ARMOR(), Vector3(0, 0.05, -3.1))                      # snout
	part(head, _box(Vector3(1.0, 0.08, 0.06)), GLOW(k, 5.0), Vector3(0, 0.35, -3.66))                  # nostril vent
	head.rotation.x = -0.12
	for sx in [-1.0, 1.0]:
		part(head, _box(Vector3(0.1, 0.18, 0.45)), GLOW(k, 7.0), Vector3(sx * 0.93, 0.6, -0.7))       # eyes
		part(head, _box(Vector3(0.12, 0.3, 0.7)), PLATE(), Vector3(sx * 0.93, 0.85, -0.7), Vector3(0, 0, sx * 0.3))   # eye ridge
		for i in 6:                                                                                  # upper teeth
			part(head, _cyl(0.0, 0.07, 0.35, 5), CHROME(), Vector3(sx * 0.75, -0.65, -0.4 - i * 0.42), Vector3(PI, 0, 0))
	var jaw := pivot(head, "Jaw", Vector3(0, -0.5, -0.1))
	part(jaw, _box(Vector3(1.6, 0.5, 2.6)), PLATE(), Vector3(0, -0.2, -1.2))
	part(jaw, _box(Vector3(1.2, 0.1, 2.3)), GLOW(k, 4.0), Vector3(0, 0.08, -1.2))                    # plasma throat
	for sx in [-1.0, 1.0]:
		for i in 5:
			part(jaw, _cyl(0.0, 0.06, 0.3, 5), CHROME(), Vector3(sx * 0.65, 0.2, -0.5 - i * 0.42))


## WIDOWMAKER: an armoured spider whose eight legs end in spinning wheels.
## A glowing hourglass on the abdomen, a cluster of eyes, venom fangs.
static func _mech_spider(root: Node3D) -> void:
	var k := "spider"
	var chitin := mat(Color(0.06, 0.05, 0.07), 0.5, 0.35)
	part(root, _sphere(1.0), ARMOR(), Vector3(0, 3.2, -1.0), Vector3.ZERO, Vector3(2.2, 1.3, 2.3))
	part(root, _sphere(1.0), chitin, Vector3(0, 4.0, 2.6), Vector3(0.2, 0, 0), Vector3(3.0, 2.5, 3.6))
	var core := part(root, _box(Vector3(0.9, 0.12, 1.6)), GLOW(k, 6.0), Vector3(0, 6.35, 2.4), Vector3(0.2, 0, 0))   # hourglass
	core.name = "Core"
	part(root, _box(Vector3(0.5, 0.13, 0.5)), GLOW(k, 6.0), Vector3(0, 6.3, 2.4), Vector3(0.2, PI * 0.25, 0))
	for i in 6:                                                                                      # armour bands
		part(root, _torus(2.4 - absf(i - 2.5) * 0.35, 2.6 - absf(i - 2.5) * 0.35), PLATE(), Vector3(0, 4.0, 1.2 + i * 0.55), Vector3(PI * 0.5 + 0.2, 0, 0), Vector3(1.0, 1.0, 0.75))
	moss(root, Vector3(0, 5.6, 3.6), 1.1, 6, 41)
	var head := pivot(root, "Head", Vector3(0, 3.3, -3.0))
	for i in 8:
		var row := i / 4
		var col := i % 4
		part(head, _sphere(0.16 + (0.1 if row == 0 and (col == 1 or col == 2) else 0.0)), GLOW(k, 7.0), Vector3((col - 1.5) * 0.42, 0.45 - row * 0.35, -0.1))
	var jaw := pivot(head, "Jaw", Vector3(0, -0.4, -0.1))
	for sx in [-1.0, 1.0]:
		part(jaw, _cyl(0.0, 0.22, 1.2, 6), CHROME(), Vector3(sx * 0.45, -0.5, -0.2), Vector3(PI - 0.3, 0, sx * 0.2))   # fangs
		part(jaw, _sphere(0.12), mat(Color(0.4, 1.0, 0.3), 0.0, 0.2, 4.0), Vector3(sx * 0.45, -1.05, -0.38))          # venom drops
		for i in 4:
			var z := -2.2 + i * 0.95
			var leg := pivot(root, "Leg_%d%s" % [i, "L" if sx < 0 else "R"], Vector3(sx * 1.6, 3.2, z))
			var knee := Vector3(sx * 3.2, 3.4, (z + 0.6) * 0.6)
			var foot := Vector3(sx * 5.0, -2.5, (z + 0.6) * 1.15)
			strut(leg, Vector3.ZERO, knee, 0.55, chitin)
			strut(leg, knee, foot, 0.42, ARMOR())
			part(leg, _sphere(0.4), PLATE(), knee)
			part(leg, _torus(0.3, 0.45), GLOW(k, 3.0), knee, Vector3(0, 0, PI * 0.5))
			wheel(leg, "Wheel_%d%s" % [i, "L" if sx < 0 else "R"], foot + Vector3(0, 0.15, 0), 0.75, 0.5, k)


## MAMMOTH: an elephant built as a six-wheeled tank. Ear shields, ivory
## tusk rams, and a trunk that ends in a plasma cannon.
static func _mech_elephant(root: Node3D) -> void:
	var k := "elephant"
	var skin := mat(Color(0.36, 0.35, 0.34), 0.25, 0.75)
	part(root, _sphere(1.0), skin, Vector3(0, 4.7, 0.5), Vector3.ZERO, Vector3(2.6, 2.3, 4.0))
	part(root, _box(Vector3(5.6, 1.4, 8.0)), ARMOR(), Vector3(0, 2.4, 0.5))                          # chassis
	part(root, _box(Vector3(5.0, 0.12, 7.6)), GLOW(k, 2.5), Vector3(0, 1.66, 0.5))
	for i in 5:                                                                                      # back armour plates
		part(root, _box(Vector3(4.4 - absf(i - 2) * 0.6, 0.35, 1.3)), PLATE(), Vector3(0, 6.7 - absf(i - 2) * 0.35, -1.9 + i * 1.3), Vector3(0, 0, 0))
		part(root, _box(Vector3(0.1, 0.4, 1.32)), GLOW(k, 3.0), Vector3(0, 6.85 - absf(i - 2) * 0.35, -1.9 + i * 1.3))
	moss(root, Vector3(0, 6.9, 1.0), 1.8, 10, 51)
	var core := part(root, _sphere(0.55), GLOW(k, 5.0), Vector3(0, 3.6, -3.3))
	core.name = "Core"
	for sx in [-1.0, 1.0]:
		for i in 3:
			var z := -2.4 + i * 2.9
			wheel(root, "Wheel_%d%d" % [int(sx), i], Vector3(sx * 2.85, 1.6, z), 1.6, 1.2, k)
			part(root, _box(Vector3(1.5, 0.3, 2.4)), BARK(), Vector3(sx * 2.85, 3.35, z), Vector3(0, 0, sx * 0.2))   # bark fenders
	var head := pivot(root, "Head", Vector3(0, 5.6, -3.9))
	part(head, _sphere(1.0), skin, Vector3.ZERO, Vector3.ZERO, Vector3(1.6, 1.6, 1.4))
	part(head, _box(Vector3(2.2, 0.4, 1.4)), PLATE(), Vector3(0, 1.1, -0.3), Vector3(-0.3, 0, 0))
	for sx in [-1.0, 1.0]:
		part(head, _box(Vector3(0.45, 0.15, 0.1)), GLOW(k, 7.0), Vector3(sx * 0.75, 0.3, -1.33))       # eyes
		var ear := pivot(head, "Ear_" + ("L" if sx < 0 else "R"), Vector3(sx * 1.3, 0.1, 0.3))
		part(ear, _cyl(1.8, 1.8, 0.2, 16), ARMOR(), Vector3(sx * 1.4, -0.3, 0.2), Vector3(0, 0.25 * sx, PI * 0.5))
		part(ear, _torus(1.7, 1.85), GLOW(k, 3.0), Vector3(sx * 1.45, -0.3, 0.2), Vector3(0, 0.25 * sx, PI * 0.5))
		part(ear, _cyl(1.3, 1.3, 0.22, 16), BARK(), Vector3(sx * 1.5, -0.3, 0.2), Vector3(0, 0.25 * sx, PI * 0.5))
		# Tusks: ivory rams, chrome tipped.
		strut(head, Vector3(sx * 0.7, -0.8, -0.9), Vector3(sx * 0.9, -1.8, -2.6), 0.35, IVORY())
		strut(head, Vector3(sx * 0.9, -1.8, -2.6), Vector3(sx * 0.9, -1.2, -3.8), 0.26, IVORY())
		part(head, _cyl(0.0, 0.16, 0.5, 6), CHROME(), Vector3(sx * 0.9, -1.0, -4.05), Vector3(-1.2, 0, 0))
	var trunk := pivot(head, "Trunk", Vector3(0, -0.6, -1.3))
	var prev := Vector3.ZERO
	for i in 5:
		var nxt := prev + Vector3(0, -0.85, -0.25 + i * 0.05)
		strut(trunk, prev, nxt, 0.75 - i * 0.1, skin if i % 2 == 0 else ARMOR())
		part(trunk, _torus(0.3 - i * 0.03, 0.42 - i * 0.04), GLOW(k, 2.5), nxt, Vector3(0.2, 0, 0))
		prev = nxt
	var muzzle := part(trunk, _cyl(0.32, 0.25, 0.5), GLOW(k, 6.0), prev + Vector3(0, -0.2, 0))
	muzzle.name = "Muzzle"
