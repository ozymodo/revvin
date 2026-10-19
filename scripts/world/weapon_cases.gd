extends Node3D
## Weapon cases: hexagonal glass enclosures, each holding one power weapon
## floating inside. Small cases hold everyday weapons, large ones the heavy
## hitters (tier colours on the frame: white, blue, purple, gold). They sit
## along the avenues, on rooftops, on top of the Spire and the mega ramp,
## in the parks, and some float in the air. They're solid: crash into one
## (anything faster than a crawl) and it bursts apart in a shower of glass and
## metal voxels as the weapon goes onto the car (arsenal.gd). Creep into
## it and you just bump it. A case refills with a new weapon after RESPAWN
## seconds.

signal opened(id: String, slot: String, level: int, replaced: String)

const Weapons := preload("res://scripts/combat/weapons.gd")
const City := preload("res://scripts/world/city.gd")

const RESPAWN := 60.0
const BREAK_SPEED := 1.5            # m/s into the case (barely more than a nudge)
const REACH := 2.8                  # car centre to nose, plus a little
## size: [radius, height, lowest tier, highest tier]
const SIZES := {"small": [1.2, 1.9, 1, 2], "medium": [1.6, 2.4, 2, 3], "large": [2.1, 3.0, 3, 4]}

class Case:
	var root: Node3D
	var size := "small"
	var id := ""
	var r := 1.2
	var h := 2.0
	var floating := false
	var display: Node3D
	var label: Label3D
	var trims: Array[MeshInstance3D] = []
	var light: OmniLight3D
	var collider: CollisionShape3D
	var active := true
	var timer := 0.0
	var phase := 0.0

var car: RigidBody3D
var arsenal: Node
var fx: Node
var sfx: Node
var hud: Node
var tricks: Node
var debris: Node                    # world/debris.gd
var cases: Array[Case] = []
var _rng := RandomNumberGenerator.new()
var _glass: StandardMaterial3D
var _metal: StandardMaterial3D
var _clock := 0.0


func _ready() -> void:
	_glass = StandardMaterial3D.new()
	_glass.albedo_color = Color(0.7, 0.9, 1.0, 0.12)
	_glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_glass.metallic = 0.6
	_glass.roughness = 0.05
	_glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	_glass.rim_enabled = true
	_glass.rim = 0.6
	_metal = StandardMaterial3D.new()
	_metal.albedo_color = Color(0.14, 0.15, 0.17)
	_metal.metallic = 0.85
	_metal.roughness = 0.3


## Spreads cases over the city and the parks.
func place_all(level: Node3D) -> void:
	_rng.seed = 6161
	var city = level.city
	# Along the avenues: a few on the road, a few hanging in the air above it.
	var n := 0
	for attempt in 200:
		if n >= 16:
			break
		var a: float = City.AVENUES[_rng.randi() % City.AVENUES.size()]
		var t := _rng.randf_range(-360.0, 360.0)
		var lane := _rng.randf_range(-7.0, 7.0)
		var axis := _rng.randi() % 2
		var x := a + lane if axis == 0 else t
		var z := t if axis == 0 else a + lane
		if level._reserved(x, z, 8.0) or city.masked(x, z):
			continue
		var near := false
		for b: float in City.AVENUES:
			if absf(t - b) < 20.0:
				near = true
		for c in cases:
			if c.root.position.distance_to(Vector3(x, 0, z)) < 60.0:
				near = true
		if near:
			continue
		var air := n % 4 == 3
		add_case(Vector3(x, _rng.randf_range(7.0, 13.0) if air else 0.0, z), ["small", "small", "medium"][n % 3] if not air else "medium", air)
		n += 1
	# Rooftops: ride up a tower's wall to reach them.
	var roofs: Array = city.roof_spots.duplicate()
	var placed := 0
	for p in roofs:
		if placed >= 6:
			break
		if (p as Vector3).y < 25.0 or _rng.randf() < 0.5:
			continue
		add_case(p, "large" if placed % 2 == 0 else "medium", false)
		placed += 1
	# The stunt parks (spots recorded by stunt_park.gd).
	for spot in level.park.case_spots:
		add_case(spot[0], spot[1], (spot[0] as Vector3).y > 4.0 and spot[1] != "large" or (spot[0] as Vector3).y > 15.0)
	# Mega-block roofs.
	for spot in level.wrecking.case_spots:
		add_case(spot[0], spot[1], false)


func add_case(pos: Vector3, size: String, floating: bool) -> Case:
	var c := Case.new()
	c.size = size
	c.r = SIZES[size][0]
	c.h = SIZES[size][1]
	c.floating = floating
	c.phase = _rng.randf() * TAU
	c.root = Node3D.new()
	c.root.position = pos
	add_child(c.root)
	_build(c)
	_fill(c)
	cases.append(c)
	return c


## Hex base and lid, glass walls, glowing edges in the tier colour.
func _build(c: Case) -> void:
	var hexp := func(r: float, h: float) -> CylinderMesh:
		var m := CylinderMesh.new()
		m.top_radius = r
		m.bottom_radius = r
		m.height = h
		m.radial_segments = 6
		m.rings = 1
		return m
	for y in [0.12, c.h + 0.32]:
		var plate := MeshInstance3D.new()
		plate.mesh = hexp.call(c.r * 1.08, 0.24)
		plate.material_override = _metal
		plate.position.y = y
		c.root.add_child(plate)
	var glass := MeshInstance3D.new()
	glass.mesh = hexp.call(c.r, c.h)
	glass.material_override = _glass
	glass.position.y = 0.24 + c.h * 0.5
	glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	c.root.add_child(glass)
	var post := BoxMesh.new()
	post.size = Vector3(0.07, c.h, 0.07)
	var beam := BoxMesh.new()
	beam.size = Vector3(0.06, 0.06, c.r)
	for k in 6:
		# CylinderMesh hexagons have a vertex at angle 0 (on +X).
		var a := k * TAU / 6.0
		var v := Vector3(cos(a), 0, sin(a)) * c.r
		var p := MeshInstance3D.new()
		p.mesh = post
		p.position = v + Vector3.UP * (0.24 + c.h * 0.5)
		c.root.add_child(p)
		c.trims.append(p)
		var a2 := (k + 1) * TAU / 6.0
		var v2 := Vector3(cos(a2), 0, sin(a2)) * c.r
		for y in [0.25, c.h + 0.22]:
			var e := MeshInstance3D.new()
			e.mesh = beam
			c.root.add_child(e)
			e.transform = Transform3D(Basis.looking_at(v2 - v, Vector3.UP), (v + v2) * 0.5 + Vector3.UP * y)
			c.trims.append(e)
	c.light = OmniLight3D.new()
	c.light.omni_range = c.r * 3.5
	c.light.position.y = c.h * 0.6
	c.light.distance_fade_enabled = true
	c.light.distance_fade_begin = 80.0
	c.light.distance_fade_length = 20.0
	c.root.add_child(c.light)
	# Solid: a hexagonal prism collider.
	var body := StaticBody3D.new()
	c.root.add_child(body)
	c.collider = CollisionShape3D.new()
	var hull := ConvexPolygonShape3D.new()
	var pts := PackedVector3Array()
	for k in 6:
		var a := k * TAU / 6.0
		for y in [0.0, c.h + 0.44]:
			pts.append(Vector3(cos(a) * c.r * 1.08, y, sin(a) * c.r * 1.08))
	hull.points = pts
	c.collider.shape = hull
	body.add_child(c.collider)
	c.label = Label3D.new()
	c.label.font_size = 44
	c.label.pixel_size = 0.012
	c.label.outline_size = 10
	c.label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	c.label.shaded = false
	c.label.position.y = c.h + 1.0
	c.label.visibility_range_end = 90.0
	c.root.add_child(c.label)


## Puts a random weapon of the case's size class inside.
func _fill(c: Case) -> void:
	var pool: Array = Weapons.ids_of_tier(SIZES[c.size][2], SIZES[c.size][3])
	c.id = pool[_rng.randi() % pool.size()]
	var tier: int = Weapons.DEFS[c.id].tier
	var tc: Color = Weapons.TIER_COLORS[tier - 1]
	var trim := StandardMaterial3D.new()
	trim.albedo_color = tc * 0.3
	trim.emission_enabled = true
	trim.emission = tc
	trim.emission_energy_multiplier = 2.5
	for t in c.trims:
		t.material_override = trim
	c.light.light_color = tc
	c.light.light_energy = 1.5
	c.label.text = Weapons.DEFS[c.id].name
	c.label.modulate = tc.lightened(0.3)
	if c.display:
		c.display.queue_free()
	c.display = Weapons.model(c.id)
	c.display.scale = Vector3.ONE * (2.2 + c.r * 0.5)
	c.display.position.y = c.h * 0.45
	c.root.add_child(c.display)
	c.root.visible = true
	c.active = true
	c.collider.set_deferred("disabled", false)


func _physics_process(delta: float) -> void:
	_clock += delta
	if car == null:
		return
	var p: Vector3 = car.global_position + car.global_basis.y * 0.5
	var v: Vector3 = car.linear_velocity
	# Looking a few steps ahead, so a fast car smashes it before the
	# collider stops it dead.
	var ahead := p + v * delta * 6.0
	for c in cases:
		if not c.active:
			c.timer -= delta
			if c.timer <= 0.0 and c.root.global_position.distance_to(p) > c.r + 4.0:
				_fill(c)
			continue
		var o := c.root.global_position
		var mid := o + Vector3.UP * (c.h * 0.5 + 0.2)
		var q := Geometry3D.get_closest_point_to_segment(mid, p, ahead)
		var flat := Vector2(q.x - o.x, q.z - o.z).length()
		# Measured from the car's centre, so the zone reaches out by the car's
		# half-length: the nose touching the glass counts.
		if flat < c.r + REACH and q.y > o.y - 1.5 and q.y < o.y + c.h + 2.0:
			var into := v.dot((mid - p).normalized())
			if into >= BREAK_SPEED or flat < c.r * 0.8:
				_open(c)


func _process(delta: float) -> void:
	for c in cases:
		if not c.active:
			continue
		var t := _clock + c.phase
		c.display.rotate_y(delta * 1.2)
		c.display.position.y = c.h * 0.45 + sin(t * 1.6) * 0.12
		if c.floating:
			c.root.position.y += sin(t * 0.9) * 0.15 * delta


## Smash the glass, hand the weapon to the car.
func _open(c: Case) -> void:
	c.active = false
	c.timer = RESPAWN
	c.root.visible = false
	c.collider.set_deferred("disabled", true)
	var at := c.root.global_position + Vector3.UP * c.h * 0.5
	var tc: Color = Weapons.TIER_COLORS[Weapons.DEFS[c.id].tier - 1]
	fx.debris(at, Color(0.75, 0.9, 1.0), tc, 0.6 + c.r * 0.3)
	# It bursts: glass, frame and glowing trim voxels, flung along with the car.
	var v: Vector3 = car.linear_velocity
	if debris:
		var ext := Vector3(c.r, c.h * 0.5, c.r) * 0.8
		debris.burst(at, 10 + int(c.r * 6.0), 0.32, Color(0.7, 0.9, 1.0, 0.5), v * 1.05, 8.0, ext)
		debris.burst(at, 5 + int(c.r * 3.0), 0.28, Color(0.15, 0.16, 0.18), v * 1.0, 7.0, ext)
		debris.burst(at, 4 + int(c.r * 2.0), 0.22, tc, v * 0.95, 9.0, ext, 2.5)
	car.linear_velocity = v * 0.97
	if tricks:
		tricks.ignore_crash(0.5)
		tricks.smash_points(100)
	fx.punch(0.25)
	sfx.glass(at, 1.0)
	fx.ring(at, tc, c.r * 3.0, 0.4, Vector3.UP)
	fx.sparks(at, tc, 0.6, Vector3.UP)
	fx.sweep(tc, false, 0.8)
	sfx.crunch(at, 0.6)
	sfx.pickup(true)
	var res: Array = arsenal.add_weapon(c.id)
	var name: String = Weapons.DEFS[c.id].name
	var msg := "%s  ·  %s" % [name, res[0]]
	if res[1] > 1 and res[2] == "":
		msg = "%s  LEVEL %d  ·  %s" % [Weapons.DEFS[arsenal_weapon(res[0])].name, res[1], res[0]]
	elif res[2] != "":
		msg += "  (replaces %s)" % Weapons.DEFS[res[2]].name
	if hud:
		hud.notify(msg, tc.lightened(0.3))
	opened.emit(c.id, res[0], res[1], res[2])


## A tower came down: cases on its roof fall with it to the ground.
func drop_in(r: Rect2) -> void:
	for c in cases:
		var p := c.root.position
		if p.y > 1.0 and r.grow(1.0).has_point(Vector2(p.x, p.z)):
			c.floating = false
			var tw := create_tween()
			tw.tween_property(c.root, "position:y", 0.0, 3.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


func arsenal_weapon(slot_name: String) -> String:
	for s in arsenal.slots:
		if s.name == slot_name:
			return s.id
	return ""
