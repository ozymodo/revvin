extends Node3D
## The skatepark world, in the spirit of Skate and TrackMania: ramps, rails,
## hills, curves, walls and hoops everywhere, and lots of vertical stunts.
##
## Outside the city, between it and the dome wall, four parks:
##   EAST   THE SPIRE   a banked road spiralling 84 m up a tower (its inner
##                      edge is one long grind), a drop-in off the top into a
##                      kicker and a gap, and a carve toward the dome wall
##   NORTH  BIG AIR     a mega ramp (climb, banked U-turn, 42 m drop-in,
##                      kicker, gap with a hoop, landing), a giant half-pipe,
##                      and a rising line of hoops to fly through
##   WEST   THE HILLS   rolling hills with rails riding over them, kickers
##   SOUTH  THE PLAZA   a bowl, a spine, ledges, stairs with a handrail, a
##                      funbox and a full pipe
## In the city: curved banks round every tower's base (ride up the walls),
## curved banks up all four sides of the mesa, rails along the sidewalks,
## grindable copings on the half-pipe, wall of death, mesa and every SKYWAY
## barrier, and hoops floating over the avenues.

const Level := preload("res://scripts/level.gd")
const Track := preload("res://scripts/track/track.gd")
const City := preload("res://scripts/world/city.gd")

var level: Node3D
var grinds: Node
var hoops: Array = []               # [centre, axis, radius, mesh, cooldown]
var pickup_spots: Array = []        # [position, kind] for the air/battery pickups
var case_spots: Array = []          # [position, size] for the weapon cases
var car: RigidBody3D
var tricks: Node
var fx: Node
var sfx: Node

var _rng := RandomNumberGenerator.new()
var _hoop_mat: StandardMaterial3D
var _hoop_hit_mat: StandardMaterial3D
var _prev_car := Vector3.ZERO


func build(lvl: Node3D) -> void:
	level = lvl
	grinds = lvl.grinds
	_rng.seed = 8080
	_hoop_mat = _glow(Color(0.15, 0.95, 0.4), 3.0)
	_hoop_hit_mat = _glow(Color(1.0, 0.5, 0.1), 4.5)
	_spire()
	_big_air()
	_hills()
	_plaza()
	_city_banks()
	_mesa_banks()
	_copings()
	_sidewalk_rails()
	_city_hoops()
	if lvl.course:
		grinds.add_track_edges(lvl.course.track)


func _mat(kind: String) -> Material:
	return level._material(kind)


static func _glow(c: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c * 0.3
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	return m


# ------------------------------------------------------------------ EAST: the spire

func _spire() -> void:
	var c := Vector3(505, 0, 60)
	var t := Track.new()
	t.name = "Spire"
	add_child(t)
	t.rails = Track.F_RAIL_R                       # barrier on the outside only
	t.start(Vector3(550, 0.12, 140), 0.0, 14.0)
	t.straight(80)
	# Three banked turns climbing 84 m round the tower (radius 45).
	var turn_len := TAU * 45.0
	t.seg(turn_len * 0.5, 180, 14, 84.0 / (turn_len * 3.0), 16)
	t.seg(turn_len * 2.0, 720, 56, 84.0 / (turn_len * 3.0), 16)
	t.seg(turn_len * 0.5, 180, 14, 0, 0)
	t.straight(20)
	case_spots.append([t.pts[t.pts.size() - 8] + Vector3.UP * 0.2, "large"])     # top of the spire
	# Drop-in off the top, kicker, gap, landing, and a carve toward the dome.
	t.rails = Track.F_RAILS
	t.seg(150, 0, -82, 0)
	t.straight(30)
	var kick_i := t.pts.size()
	t.seg(18, 0, 3.5, 0.55)
	t.gap(36, 0, -0.45)
	t.seg(26, 0, -3.6, 0)
	t.seg(60, 60, 0, 0, 18)
	t.build_geometry()
	grinds.add_track_edges(t)
	_ballistic_hoop(t, kick_i + 17, 36.0, 34.0)
	# The tower the road wraps round, with spokes holding up the deck.
	_column(c, 32.0, 92.0)
	for i in range(80, t.pts.size(), 45):
		var p := t.pts[i]
		var flat := Vector3(p.x - c.x, 0, p.z - c.z)
		if flat.length() > 52.0 or p.y < 3.0:
			continue
		var dir := flat.normalized()
		var a := c + dir * 31.0
		var b := c + dir * (flat.length() - 6.0)
		_beam(Vector3(a.x, p.y - 1.3, a.z), Vector3(b.x, p.y - 1.3, b.z), 1.2)
	pickup_spots.append([Vector3(505, 94, 60), 1])
	pickup_spots.append([t.pts[t.pts.size() / 2], 2])


func _column(base: Vector3, r: float, h: float) -> void:
	var body := StaticBody3D.new()
	body.position = base + Vector3.UP * h * 0.5
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r * 1.05
	cm.height = h
	cm.radial_segments = 48
	mi.mesh = cm
	mi.material_override = _mat("wall_ride")
	body.add_child(mi)
	var cs := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.radius = r
	sh.height = h
	cs.shape = sh
	body.add_child(cs)
	add_child(body)


func _beam(a: Vector3, b: Vector3, thick: float) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(thick, thick, a.distance_to(b))
	mi.mesh = bm
	mi.material_override = _mat("deck")
	add_child(mi)
	mi.global_transform = Transform3D(Basis.looking_at(b - a, Vector3.UP), (a + b) * 0.5)


## A hoop where a car leaving kicker sample `i` at `v` m/s is mid-gap.
func _ballistic_hoop(t: Track, i: int, gap: float, v: float) -> void:
	i = clampi(i, 0, t.pts.size() - 1)
	var fw := -t.sample_xform(i).basis.z
	var theta := asin(clampf(fw.y, -1.0, 1.0))
	var flat := Vector3(fw.x, 0, fw.z).normalized()
	var x := gap * 0.5
	var tt := x / (v * cos(theta))
	var y := v * sin(theta) * tt - 4.9 * tt * tt + 0.7
	add_hoop(t.pts[i] + flat * x + Vector3.UP * y, flat, 6.5)


# ------------------------------------------------------------------ NORTH: big air

func _big_air() -> void:
	var t := Track.new()
	t.name = "MegaRamp"
	add_child(t)
	t.rails = Track.F_RAILS
	t.start(Vector3(-230, 0.12, -440), -PI / 2, 16.0)
	t.straight(20)
	t.seg(170, 0, 48, 0)
	t.straight(15)
	t.seg(55, 180, 0, 0, 25)
	t.straight(10)
	case_spots.append([t.pts[t.pts.size() - 5] + Vector3.UP * 0.2, "large"])     # top of the mega ramp
	t.seg(75, 0, -42, -0.5)
	var kick_i := t.pts.size()
	t.seg(18, 0, 2.5, 0.5)
	t.gap(38, 0, -0.4)
	t.seg(30, 0, -8.4, 0)
	t.straight(25)
	t.build_geometry()
	grinds.add_track_edges(t)
	_ballistic_hoop(t, kick_i + 17, 38.0, 27.0)
	# Pillars under the climb and the platform.
	for i in range(30, t.pts.size(), 18):
		var p := t.pts[i]
		if p.y > 4.0 and t.groups[i] == 0:
			_pillar(Vector3(p.x, 0, p.z), p.y - 0.9)
	pickup_spots.append([t.pts[int(t.pts.size() * 0.45)] + Vector3.UP * 1.5, 1])

	# The canyon: a giant half-pipe, coping on both rims.
	var s := Level.Surface.new(self, _mat("wall_ride"))
	var cz := -540.0
	for side in [1.0, -1.0]:
		var o := Vector3(0, 0, side)
		s.wall_profile(Vector3(0, 0, cz + side * 8.0), o, Vector3.RIGHT, 300.0, 8.0, 6.0)
		_back_wall(s, Vector3(0, 0, cz + side * 16.3), o, Vector3.RIGHT, 300.0, 14.0)
		grinds.add_rail(_line(Vector3(-150, 14.0, cz + side * 16.0), Vector3(150, 14.0, cz + side * 16.0), 2.0), "edge", false)
	s.finish()
	_sign(Vector3(0, 16, cz), "THE CANYON")
	# A rising line of hoops to fly through, and hoops over the canyon.
	for k in 6:
		add_hoop(Vector3(40 + k * 32, 6 + k * 5, -430 - k * 6), Vector3(1, 0, -0.2).normalized(), 6.0)
	for k in 3:
		add_hoop(Vector3(-90 + k * 90, 20, cz), Vector3.RIGHT, 7.0)
	pickup_spots.append([Vector3(0, 1.5, cz), 0])
	case_spots.append([Vector3(60, 0.0, cz), "medium"])
	case_spots.append([Vector3(150, 24.0, -458), "large"])                       # in the air, off the end of the hoop line


func _pillar(base: Vector3, h: float) -> void:
	if h < 1.0:
		return
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 1.0
	cm.bottom_radius = 1.3
	cm.height = h
	cm.radial_segments = 12
	mi.mesh = cm
	mi.material_override = _mat("deck")
	mi.position = base + Vector3.UP * h * 0.5
	add_child(mi)


# ------------------------------------------------------------------ WEST: the hills

const HILLS := [
	[-470.0, -170.0, 9.0, 22.0], [-520.0, -110.0, 13.0, 30.0], [-460.0, -40.0, 7.0, 18.0],
	[-540.0, 10.0, 11.0, 26.0], [-480.0, 70.0, 14.0, 28.0], [-530.0, 140.0, 8.0, 20.0],
	[-455.0, 170.0, 6.0, 16.0], [-560.0, -60.0, 6.0, 15.0], [-500.0, 210.0, 10.0, 24.0],
]


func _hill_h(x: float, z: float) -> float:
	var h := 0.0
	for b: Array in HILLS:
		var bx: float = b[0]
		var bz: float = b[1]
		var amp: float = b[2]
		var sig: float = b[3]
		var d2 := (x - bx) * (x - bx) + (z - bz) * (z - bz)
		h += amp * exp(-d2 / (2.0 * sig * sig))
	# A long low ridge, and fade out at the city edge and the dome.
	h += 4.0 * exp(-pow((x + 505.0) / 14.0, 2.0)) * smoothstep(-240.0, -150.0, z) * (1.0 - smoothstep(150.0, 240.0, z))
	h *= smoothstep(-405.0, -430.0, x)
	h *= 1.0 - smoothstep(570.0, 595.0, Vector2(x, z).length())
	return h


func _hills() -> void:
	var s := Level.Surface.new(self, _mat("ground"))
	var step := 3.0
	var pts := []
	var nrm := []
	var x0 := -600.0
	var z0 := -270.0
	var nx := int(200.0 / step)
	var nz := int(540.0 / step)
	for i in nz + 1:
		var row := []
		var nrow := []
		for j in nx + 1:
			var x := x0 + j * step
			var z := z0 + i * step
			var h := _hill_h(x, z)
			row.append(Vector3(x, h + 0.01, z))
			var hx := _hill_h(x + 0.5, z) - _hill_h(x - 0.5, z)
			var hz := _hill_h(x, z + 0.5) - _hill_h(x, z - 0.5)
			nrow.append(Vector3(-hx, 1.0, -hz).normalized())
		pts.append(row)
		nrm.append(nrow)
	s.grid(pts, nrm)
	s.finish()
	# Rails that ride over the hills.
	for x in [-470.0, -512.0, -548.0]:
		var line := PackedVector3Array()
		var z := -230.0
		while z <= 230.0:
			if Vector2(x, z).length() < 585.0:
				line.append(Vector3(x, _hill_h(x, z) + 0.9, z))
			z += 2.0
		grinds.add_rail(line, "rail", true, PackedVector3Array(), false, 0.9)
	for k in 4:
		var z := -150.0 + k * 100.0
		level.kicker(Vector3(-430, 0.0, z), PI * 0.5, 8.0, 12.0, 2.5, "ramp")
	_sign(Vector3(-420, 3, -250), "THE HILLS")
	for k in 4:
		add_hoop(Vector3(-500, _hill_h(-500, -150 + k * 100) + 9.0, -150 + k * 100), Vector3.BACK, 6.0)
	pickup_spots.append([Vector3(-520, _hill_h(-520, -110) + 2.0, -110), 2])
	pickup_spots.append([Vector3(-480, _hill_h(-480, 70) + 2.0, 70), 0])
	case_spots.append([Vector3(-480, _hill_h(-480, 70), 70), "medium"])          # on a hilltop
	case_spots.append([Vector3(-520, _hill_h(-520, -110) + 12.0, -110), "medium"])  # in the air over a hill


# ------------------------------------------------------------------ SOUTH: the plaza

func _plaza() -> void:
	var s := Level.Surface.new(self, _mat("wall_ride"))
	# Bowl, open toward the city.
	var bowl := Vector3(-150, 0, 500)
	s.ring_wall(bowl, 18.0, 6.0, 2.0, deg_to_rad(-70.0), deg_to_rad(250.0), 96)
	_ring_back(s, bowl, 24.3, 8.0, deg_to_rad(-70.0), deg_to_rad(250.0), 96)
	var arc := PackedVector3Array()
	for k in 97:
		var a := lerpf(deg_to_rad(-70.0), deg_to_rad(250.0), k / 96.0)
		arc.append(bowl + Vector3(cos(a) * 24.0, 8.0, sin(a) * 24.0))
	grinds.add_rail(arc, "edge", false)
	# Spine: two quarter-pipes back to back, coping on the peak.
	var sp := Vector3(0, 0, 470)
	for side in [1.0, -1.0]:
		var o := Vector3(0, 0, -side)
		s.wall_profile(sp + Vector3(0, 0, side * 5.0), o, Vector3.RIGHT, 120.0, 5.0, 0.0)
	grinds.add_rail(_line(sp + Vector3(-60, 5.05, 0), sp + Vector3(60, 5.05, 0), 2.0), "rail", false)
	# Full pipe along X: inside and out.
	_full_pipe(s, Vector3(0, 0, 548), 8.0, 50.0)
	s.finish()
	# Ledges with copings, a funbox, stairs with a handrail.
	for k in 4:
		var c := Vector3(60 + k * 34, 0.5, 515 + (k % 2) * 10)
		level.box(c, Vector3(24, 1.0, 2.5), "deck")
		for e in [-1.25, 1.25]:
			grinds.add_rail(_line(c + Vector3(-12, 0.52, e), c + Vector3(12, 0.52, e), 2.0), "edge", false)
	var fb := Vector3(-60, 0.6, 520)
	level.box(fb, Vector3(8, 1.2, 14), "deck")
	level.kicker(fb + Vector3(0, -0.6, 10.5), 0.0, 8.0, 7.0, 1.2, "ramp")
	level.kicker(fb + Vector3(0, -0.6, -10.5), PI, 8.0, 7.0, 1.2, "ramp")
	grinds.add_rail(_line(fb + Vector3(0, 1.5, -6.5), fb + Vector3(0, 1.5, 6.5), 1.0), "rail", true, PackedVector3Array(), false, 0.9)
	_stairs(Vector3(150, 0, 470))
	_sign(Vector3(0, 9, 455), "THE PLAZA")
	add_hoop(Vector3(0, 12, 470), Vector3.BACK, 6.0)
	add_hoop(Vector3(-150, 16, 500), Vector3.BACK, 6.0)
	pickup_spots.append([bowl + Vector3(0, 1.5, 0), 2])
	case_spots.append([bowl, "medium"])
	case_spots.append([Vector3(60, 1.0, 515), "small"])                          # on a ledge
	case_spots.append([Vector3(0, 9.0, 470), "medium"])                          # in the air over the spine
	pickup_spots.append([Vector3(0, 1.5, 548), 1])


## Five steps up to a platform, a bank beside them, a handrail down the steps.
func _stairs(at: Vector3) -> void:
	for k in 5:
		level.box(at + Vector3(0, 0.2 + k * 0.2, -k * 1.2 - 0.6), Vector3(10, 0.4 + k * 0.4, 1.2), "deck")
	level.box(at + Vector3(0, 1.0, -12), Vector3(10, 2.0, 12), "deck")
	level.wedge(at + Vector3(9, 0, -3), 0.0, 8.0, 6.0, 2.0, "ramp")
	var rail := _line(at + Vector3(-3.5, 1.2, 0.8), at + Vector3(-3.5, 2.9, -6.0), 1.0)
	rail.append_array(_line(at + Vector3(-3.5, 2.9, -7.0), at + Vector3(-3.5, 2.9, -10.0), 1.0))
	grinds.add_rail(rail, "rail", true)


func _full_pipe(s, centre: Vector3, r: float, length: float) -> void:
	var segs := 48
	for outer in [false, true]:
		var pts := []
		var nrm := []
		for k in segs + 1:
			var a := TAU * k / segs
			var off := Vector3(0, r - r * cos(a), r * sin(a))
			var n := Vector3(0, cos(a), -sin(a))
			if outer:
				off = Vector3(0, r - (r + 0.4) * cos(a), (r + 0.4) * sin(a))
				n = -n
			pts.append([centre + off - Vector3.RIGHT * length * 0.5, centre + off + Vector3.RIGHT * length * 0.5])
			nrm.append(n)
		s.grid(pts, nrm)


## Back face of a quarter-pipe (so it isn't invisible from behind).
func _back_wall(s, base: Vector3, o: Vector3, t: Vector3, along: float, h: float) -> void:
	var a := base - t * along * 0.5
	var b := base + t * along * 0.5
	s.grid([[a, b], [a + Vector3.UP * h, b + Vector3.UP * h]], [o, o])


func _ring_back(s, centre: Vector3, r: float, h: float, phi0: float, phi1: float, segs: int) -> void:
	var lo := []
	var hi := []
	var nlo := []
	for j in segs + 1:
		var phi := lerpf(phi0, phi1, float(j) / segs)
		var o := Vector3(cos(phi), 0, sin(phi))
		lo.append(centre + o * r)
		hi.append(centre + o * r + Vector3.UP * h)
		nlo.append(o)
	s.grid([lo, hi], [nlo, nlo])


# ------------------------------------------------------------------ the city

## Curved banks round the base of every upright tower: ride up the walls.
func _city_banks() -> void:
	var city = level.city
	var s := Level.Surface.new(self, _mat("wall_ride"))
	var r := 5.0
	for tw in city.towers:
		var rect: Rect2 = tw[0]
		if tw[1] < 10.0:
			continue
		var c := Vector3(rect.get_center().x, 0, rect.get_center().y)
		var hx := rect.size.x * 0.5
		var hz := rect.size.y * 0.5
		for f in [[Vector3(1, 0, 0), hx, hz], [Vector3(-1, 0, 0), hx, hz], [Vector3(0, 0, 1), hz, hx], [Vector3(0, 0, -1), hz, hx]]:
			var n: Vector3 = f[0]
			var face := c + n * float(f[1])
			var along: float = f[2] * 2.0 - 1.0
			if along < 4.0:
				continue
			# The bank curves up from r metres out to meet the wall r metres up.
			s.wall_profile(face + n * r, -n, Vector3(n.z, 0, -n.x), along, r, 0.0)
	s.finish()


## Curved banks up all four sides of the 12 m mesa, and its rim to grind.
func _mesa_banks() -> void:
	var s := Level.Surface.new(self, _mat("wall_ride"))
	var c := Vector3(80, 0, -200)
	var r := 12.0
	for n in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, -1)]:
		s.wall_profile(c + n * (18.0 + r), -n, Vector3(n.z, 0, -n.x), 34.0, r, 0.0)
	s.finish()
	var rim := PackedVector3Array([c + Vector3(-18, 12.02, -18), c + Vector3(18, 12.02, -18), c + Vector3(18, 12.02, 18),
		c + Vector3(-18, 12.02, 18)])
	grinds.add_rail(_densify(rim, 2.0, true), "edge", false, PackedVector3Array(), true)


## Copings on the existing suction features.
func _copings() -> void:
	# Half-pipe rims (walls end 13 m up at z = 65 ± 12).
	for z in [53.0, 77.0]:
		grinds.add_rail(_line(Vector3(-120, 13.0, z), Vector3(40, 13.0, z), 2.0), "edge", false)
	# Wall of death rim.
	var rim := PackedVector3Array()
	for k in 81:
		var a := lerpf(deg_to_rad(16.0), deg_to_rad(344.0), k / 80.0)
		rim.append(Vector3(-200 + cos(a) * 26.0, 16.0, -150 + sin(a) * 26.0))
	grinds.add_rail(rim, "edge", false)


## Rails along the sidewalks, one stretch per block side, here and there.
func _sidewalk_rails() -> void:
	var city = level.city
	for a: float in City.AVENUES:
		for axis in 2:
			for side in [-1.0, 1.0]:
				for bi in City.AVENUES.size() + 1:
					if _rng.randf() > 0.55:
						continue
					var lo: float = -380.0 if bi == 0 else City.AVENUES[bi - 1] + 30.0
					var hi: float = 380.0 if bi == City.AVENUES.size() else City.AVENUES[bi] - 30.0
					if hi - lo < 30.0:
						continue
					var len := minf(_rng.randf_range(25.0, 55.0), hi - lo)
					var t0 := _rng.randf_range(lo, hi - len)
					var off: float = a + side * 14.0
					var p0 := Vector3(off, 0.9, t0) if axis == 0 else Vector3(t0, 0.9, off)
					var p1 := Vector3(off, 0.9, t0 + len) if axis == 0 else Vector3(t0 + len, 0.9, off)
					var mid := (p0 + p1) * 0.5
					if level._reserved(mid.x, mid.z, 6.0) or city.masked(p0.x, p0.z) or city.masked(p1.x, p1.z):
						continue
					grinds.add_rail(_line(p0, p1, 2.0), "rail", true, PackedVector3Array(), false, 0.9)


## Hoops floating over the avenues.
func _city_hoops() -> void:
	var city = level.city
	var n := 0
	for attempt in 80:
		if n >= 18:
			break
		var a: float = City.AVENUES[_rng.randi() % City.AVENUES.size()]
		var t := _rng.randf_range(-360.0, 360.0)
		var axis := _rng.randi() % 2
		var p := Vector3(a, _rng.randf_range(4.0, 12.0), t) if axis == 0 else Vector3(t, _rng.randf_range(4.0, 12.0), a)
		if level._reserved(p.x, p.z, 10.0) or city.masked(p.x, p.z):
			continue
		var near_junction := false
		for b: float in City.AVENUES:
			if absf(t - b) < 25.0:
				near_junction = true
		if near_junction:
			continue
		add_hoop(p, Vector3.BACK if axis == 0 else Vector3.RIGHT, 5.5)
		n += 1


# ------------------------------------------------------------------ hoops

## A floating hoop: fly or jump through it for points (part of an air
## trick if airborne) and a small turbo shove.
func add_hoop(centre: Vector3, axis: Vector3, r: float) -> void:
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = r
	tm.outer_radius = r + 0.55
	tm.rings = 48
	tm.ring_segments = 10
	ring.mesh = tm
	ring.material_override = _hoop_mat
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
	var ax := axis.normalized()
	var side := ax.cross(Vector3.UP).normalized() if absf(ax.y) < 0.95 else Vector3.RIGHT
	ring.global_transform = Transform3D(Basis(side, ax, side.cross(ax)), centre)
	hoops.append([centre, ax, r, ring, 0.0])


func _physics_process(delta: float) -> void:
	if car == null:
		return
	var p: Vector3 = car.global_position + car.global_basis.y * 0.5
	for h in hoops:
		h[4] = maxf(0.0, h[4] - delta)
		if h[4] > 0.0:
			continue
		var c: Vector3 = h[0]
		var ax: Vector3 = h[1]
		var s0 := (_prev_car - c).dot(ax)
		var s1 := (p - c).dot(ax)
		if s0 * s1 > 0.0 or _prev_car.distance_to(p) > 20.0:
			continue
		var lateral := (p - c) - ax * s1
		if lateral.length() < h[2]:
			h[4] = 3.0
			(h[3] as MeshInstance3D).material_override = _hoop_hit_mat
			var ring: MeshInstance3D = h[3]
			get_tree().create_timer(3.0).timeout.connect(func() -> void: ring.material_override = _hoop_mat)
			car.pad_boost(0.4)
			if tricks:
				tricks._on_hoop(0)
			if fx:
				fx.ring(c, Color(0.3, 1.0, 0.5), h[2] * 1.6, 0.4, ax)
			if sfx:
				sfx.chime()
	_prev_car = p


# ------------------------------------------------------------------ helpers

static func _line(a: Vector3, b: Vector3, step: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	var n := maxi(1, ceili(a.distance_to(b) / step))
	for k in n + 1:
		out.append(a.lerp(b, float(k) / n))
	return out


static func _densify(pts: PackedVector3Array, step: float, closed: bool) -> PackedVector3Array:
	var out := PackedVector3Array()
	var n := pts.size() if closed else pts.size() - 1
	for i in n:
		var seg := _line(pts[i], pts[(i + 1) % pts.size()], step)
		for k in seg.size() - 1:
			out.append(seg[k])
	if not closed:
		out.append(pts[pts.size() - 1])
	return out


func _sign(pos: Vector3, text: String) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = 160
	l.pixel_size = 0.02
	l.outline_size = 18
	l.modulate = Color(0.5, 0.9, 1.0)
	l.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	l.shaded = false
	l.position = pos
	add_child(l)
