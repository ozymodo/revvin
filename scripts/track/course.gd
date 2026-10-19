extends Node3D
## The SKYWAY stunt course: builds the track from course_route.gd, then
## dresses it (pillars, hover emitters, checkpoint gates, boost pads,
## hoops, signs) and runs the lap timer.
##
## Checkpoints must be taken in order; crossing the start line after the
## last one finishes the lap. Respawn (Backspace) puts the car back on the
## last checkpoint it crossed, standing still, like a time-trial game.

signal checkpoint_hit(index: int, split: float)
signal lap_finished(time: float, best: bool)
signal hoop_hit(count: int)
signal pad_hit()

const Track := preload("res://scripts/track/track.gd")
const Route := preload("res://scripts/track/course_route.gd")
const City := preload("res://scripts/world/city.gd")

const PAD_TIME := 1.1               # s of turbo per pad
const HOOP_TIME := 0.5

var track: Track
var route: Route
var car: RigidBody3D

# Lap state (read by the HUD)
var running := false
var lap_time := 0.0
var next_cp := 1
var last_cp := -1
var best_lap := INF
var last_lap := INF
var best_splits: Array[float] = []
var splits: Array[float] = []
var last_split_delta := INF         # vs best, for the HUD pop-up
var last_event_time := -10.0
var last_event := ""
var hoops_hit := 0
var hoop_count := 0
var last_lap_hoops := 0
var _hoops_taken := {}
var _clock := 0.0

var _hoop_nodes: Array[MeshInstance3D] = []
var hoop_centres: Array[Vector3] = []
## Smashable pillars for world/destruction.gd: [MultiMesh, index, xf, "pillar", collider].
var destructibles: Array = []
var _hoop_mat: StandardMaterial3D
var _hoop_hit_mat: StandardMaterial3D


func build(reserved: Array[Rect2]) -> void:
	track = Track.new()
	track.name = "Track"
	add_child(track)
	route = Route.new()
	route.build(track)
	track.build_geometry()
	_pillars(reserved)
	_gates()
	_pads()
	_hoops()
	best_splits.resize(route.checkpoints.size())
	best_splits.fill(INF)


## Footprint of the course for the city to keep clear: one rect per 8 m of
## track, padded. Returned as Rect2(x, z, w, d).
func footprint() -> Array[Rect2]:
	var out: Array[Rect2] = []
	var i := 0
	while i < track.pts.size():
		var p := track.pts[i]
		var r := track.widths[i] * 0.5 + 8.0
		out.append(Rect2(p.x - r, p.z - r, r * 2.0, r * 2.0))
		i += 8
	return out


# ------------------------------------------------------------------ dressing

func _pillars(reserved: Array[Rect2]) -> void:
	var pillar_xf := []
	var pillar_cs := []
	var emitter_xf := []
	var body := StaticBody3D.new()
	add_child(body)
	var last_d := -100.0
	for i in track.pts.size():
		if track.dists[i] - last_d < 22.0 and track.groups[i] == track.groups[maxi(i - 1, 0)]:
			continue
		var p := track.pts[i]
		var up := track.ups[i]
		if up.y < 0.9 or p.y < 3.0 or track.flags[i] & Track.F_NO_PILLAR:
			continue
		last_d = track.dists[i]
		var under := p - up * Track.DECK
		var blocked := _on_avenue(p.x, p.z) or _in_rects(reserved, p.x, p.z, 3.0) or _track_below(i)
		if blocked:
			# No room for a pillar: the deck floats on a maglev emitter.
			emitter_xf.append(Transform3D(Basis(), under + Vector3.DOWN * 0.15))
			continue
		var h := under.y + 0.5
		pillar_xf.append(Transform3D(Basis().scaled(Vector3(1, h, 1)), Vector3(p.x, h * 0.5 - 0.5, p.z)))
		var cs := CollisionShape3D.new()
		var shape := CylinderShape3D.new()
		shape.radius = 1.1
		shape.height = h
		cs.shape = shape
		cs.position = Vector3(p.x, h * 0.5 - 0.5, p.z)
		body.add_child(cs)
		pillar_cs.append(cs)

	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.0
	cyl.bottom_radius = 1.3
	cyl.height = 1.0
	cyl.radial_segments = 12
	cyl.material = City.overgrown(Color(0.33, 0.34, 0.33), 0.75, 0.5, 3.0, 0.2)
	var pm := _multimesh(cyl, pillar_xf)
	for i in pillar_xf.size():
		destructibles.append([pm, i, pillar_xf[i], "pillar", pillar_cs[i]])

	var disc := CylinderMesh.new()
	disc.top_radius = 1.6
	disc.bottom_radius = 1.1
	disc.height = 0.3
	disc.radial_segments = 20
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color(0.05, 0.08, 0.12)
	glow.emission_enabled = true
	glow.emission = Color(0.15, 0.45, 1.0)
	glow.emission_energy_multiplier = 1.4
	disc.material = glow
	_multimesh(disc, emitter_xf)


func _multimesh(mesh: Mesh, xforms: Array) -> MultiMesh:
	if xforms.is_empty():
		return null
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	add_child(mmi)
	return mm


func _on_avenue(x: float, z: float) -> bool:
	for a: float in City.AVENUES:
		if absf(x - a) < City.AVENUE_HALF + 1.0 or absf(z - a) < City.AVENUE_HALF + 1.0:
			return true
	return false


func _in_rects(rects: Array[Rect2], x: float, z: float, margin: float) -> bool:
	for r in rects:
		if r.grow(margin).has_point(Vector2(x, z)):
			return true
	return false


## Another stretch of track underneath this point (the helix, loops).
func _track_below(i: int) -> bool:
	var p := track.pts[i]
	for j in range(0, track.pts.size(), 2):
		if absi(j - i) < 30:
			continue
		var q := track.pts[j]
		if q.y < p.y - 2.0 and Vector2(q.x - p.x, q.z - p.z).length() < track.widths[j] * 0.5 + 3.0:
			return true
	return false


## Box Area3D aligned with sample i's frame.
func _area(i: int, size: Vector3, offset: Vector3, cb: Callable) -> Area3D:
	var area := Area3D.new()
	area.transform = track.sample_xform(i).translated_local(offset)
	area.monitorable = false
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	area.add_child(cs)
	area.body_entered.connect(cb)
	add_child(area)
	return area


func _glow_mat(c: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c * 0.3
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	return m


func _gates() -> void:
	var frame_mat := City.overgrown(Color(0.16, 0.17, 0.19), 0.45, 0.7, 2.0, 0.6, Color(0.15, 0.45, 1.0))
	for k in route.checkpoints.size():
		var i: int = route.checkpoints[k]
		var xf := track.sample_xform(i)
		var hw := track.widths[i] * 0.5 + Track.RAIL_W + 0.6
		var start := k == 0
		var color := Color(1.0, 0.32, 0.08) if start else Color(0.15, 0.45, 1.0)
		var gate := Node3D.new()
		gate.transform = xf
		add_child(gate)
		for side in [-1.0, 1.0]:
			var post := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.9, 8.0, 0.9)
			post.mesh = bm
			post.material_override = frame_mat
			post.position = Vector3(side * hw, 4.0, 0)
			gate.add_child(post)
			var strip := MeshInstance3D.new()
			var sm := BoxMesh.new()
			sm.size = Vector3(0.12, 7.0, 0.95)
			strip.mesh = sm
			strip.material_override = _glow_mat(color, 3.0)
			strip.position = Vector3(side * (hw - 0.45), 4.0, 0)
			gate.add_child(strip)
		var beam := MeshInstance3D.new()
		var bb := BoxMesh.new()
		bb.size = Vector3(hw * 2.0 + 0.9, 1.4, 1.0)
		beam.mesh = bb
		beam.material_override = frame_mat
		beam.position = Vector3(0, 8.4, 0)
		gate.add_child(beam)
		var under := MeshInstance3D.new()
		var ub := BoxMesh.new()
		ub.size = Vector3(hw * 2.0 - 0.9, 0.12, 1.05)
		under.mesh = ub
		under.material_override = _glow_mat(color, 3.0)
		under.position = Vector3(0, 7.66, 0)
		gate.add_child(under)
		for face in [1.0, -1.0]:
			var label := Label3D.new()
			label.text = ("START / FINISH" if start else "CP %d  ·  %s" % [k, route.names[k]]) if face > 0 else "SKYWAY"
			label.font_size = 96
			label.pixel_size = 0.012
			label.modulate = color.lightened(0.4)
			label.outline_size = 12
			label.shaded = false
			label.double_sided = false
			label.position = Vector3(0, 8.4, 0.52 * face)
			label.rotation.y = 0.0 if face > 0 else PI
			gate.add_child(label)
		_area(i, Vector3(hw * 2.0, 8.0, 3.0), Vector3(0, 4.0, 0), _on_checkpoint.bind(k))


func _pads() -> void:
	for i in route.pads:
		var j := mini(i + 7, track.pts.size() - 1)
		_area(j, Vector3(track.widths[j] * 0.6, 2.0, 14.0), Vector3(0, 1.0, 0), _on_pad)


func _hoops() -> void:
	_hoop_mat = _glow_mat(Color(0.1, 0.95, 0.35), 3.5)
	_hoop_hit_mat = _glow_mat(Color(1.0, 0.4, 0.1), 4.5)
	var vine_mat := StandardMaterial3D.new()
	vine_mat.albedo_color = Color(0.14, 0.26, 0.09)
	vine_mat.roughness = 0.9
	for jump in route.jumps:
		var i: int = jump[0]
		var gap: float = jump[1]
		var v: float = jump[2]
		# Where the car is at mid-gap when it leaves the kicker at the design
		# speed: x along the ground, y up from the lip (plus ride height).
		var fw := -track.sample_xform(i).basis.z
		var theta := asin(clampf(fw.y, -1.0, 1.0))
		var flat := Vector3(fw.x, 0, fw.z).normalized()
		var x := gap * 0.5
		var t := x / (v * cos(theta))
		var y := v * sin(theta) * t - 4.9 * t * t + 0.7
		var centre := track.pts[i] + flat * x + Vector3.UP * y
		var r := 6.5
		var ring := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = r
		tm.outer_radius = r + 0.7
		tm.rings = 48
		tm.ring_segments = 10
		ring.mesh = tm
		ring.material_override = _hoop_mat
		ring.basis = Basis.looking_at(flat, Vector3.UP) * Basis(Vector3.RIGHT, PI * 0.5)
		ring.position = centre
		add_child(ring)
		hoop_centres.append(centre)
		var wrap := MeshInstance3D.new()
		var wm := TorusMesh.new()
		wm.inner_radius = r + 0.15
		wm.outer_radius = r + 0.95
		wm.rings = 24
		wm.ring_segments = 6
		wrap.mesh = wm
		wrap.material_override = vine_mat
		wrap.transform = ring.transform.scaled_local(Vector3(1, 0.4, 1))
		add_child(wrap)
		_hoop_nodes.append(ring)
		var idx := _hoop_nodes.size() - 1
		var area := Area3D.new()
		area.transform = ring.transform
		area.monitorable = false
		var cs := CollisionShape3D.new()
		var shape := CylinderShape3D.new()
		shape.radius = r
		shape.height = 3.0
		cs.shape = shape
		area.add_child(cs)
		area.body_entered.connect(_on_hoop.bind(idx))
		add_child(area)
	hoop_count = _hoop_nodes.size()


# ------------------------------------------------------------------ gameplay

func _physics_process(delta: float) -> void:
	_clock += delta
	if running:
		lap_time += delta


func _is_car(body: Node) -> bool:
	return body == car


func _on_checkpoint(body: Node, k: int) -> void:
	if not _is_car(body):
		return
	if k == 0:
		if running and next_cp >= route.checkpoints.size():
			_finish_lap()
		_start_lap()
		return
	if not running or k != next_cp:
		return
	splits.append(lap_time)
	var best: float = best_splits[k]
	last_split_delta = lap_time - best if best < INF else INF
	last_cp = k
	next_cp += 1
	_event("CP %d" % k)
	checkpoint_hit.emit(k, lap_time)


func _start_lap() -> void:
	running = true
	lap_time = 0.0
	next_cp = 1
	last_cp = 0
	splits.clear()
	_hoops_taken.clear()
	hoops_hit = 0
	for ring in _hoop_nodes:
		ring.material_override = _hoop_mat


func _finish_lap() -> void:
	last_lap = lap_time
	last_lap_hoops = hoops_hit
	var is_best := lap_time < best_lap
	if is_best:
		best_lap = lap_time
		for k in splits.size():
			best_splits[k + 1] = splits[k]
	last_split_delta = INF
	_event("FINISH")
	lap_finished.emit(lap_time, is_best)


func _on_pad(body: Node) -> void:
	if not _is_car(body):
		return
	car.pad_boost(PAD_TIME)
	_event("TURBO")
	pad_hit.emit()


func _on_hoop(body: Node, idx: int) -> void:
	if not _is_car(body) or _hoops_taken.has(idx):
		return
	_hoops_taken[idx] = true
	hoops_hit += 1
	_hoop_nodes[idx].material_override = _hoop_hit_mat
	car.pad_boost(HOOP_TIME)
	_event("HOOP %d/%d" % [hoops_hit, hoop_count])
	hoop_hit.emit(hoops_hit)


func _event(text: String) -> void:
	last_event = text
	last_event_time = _clock


func event_age() -> float:
	return _clock - last_event_time


## Where respawn puts the car: on the last checkpoint, facing down the track.
func respawn_xform() -> Transform3D:
	var k := last_cp if running and last_cp >= 0 else -1
	if k < 0:
		return start_xform()
	var i: int = route.checkpoints[k]
	return _car_xform(mini(i + 3, track.pts.size() - 1))


## Just behind the start line, so the lap starts on the first metre.
func start_xform() -> Transform3D:
	return _car_xform(track.pts.size() - 12)


func _car_xform(i: int) -> Transform3D:
	var xf := track.sample_xform(i)
	return Transform3D(xf.basis, xf.origin + xf.basis.y * 0.7)


func restart() -> void:
	running = false
	lap_time = 0.0
	next_cp = 1
	last_cp = -1
	car.request_reset_to(start_xform())
