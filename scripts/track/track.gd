extends Node3D
## Spline-free "turtle" track builder for the stunt course.
##
## A turtle walks forward in 1 m steps; each command (straight, turn,
## climb, bank, loop, gap) changes its heading, grade and bank smoothly, so
## pieces always join without kinks. Every step leaves a sample (position +
## frame); the samples are then swept into one road mesh with barriers and
## a deck underneath, and one concave collision shape (a single shape means
## no ghost bumps at the joins, which matters at 300 km/h and in loops).
##
## Frames: x = right, y = road normal, z = back (forward is -z).

const ROAD_SHADER := preload("res://scripts/track/track_road.gdshader")
const RAIL_SHADER := preload("res://scripts/track/track_rail.gdshader")
const City := preload("res://scripts/world/city.gd")

const STEP := 1.0
const DECK := 0.9                   # deck thickness under the road
const RAIL_H := 1.1                 # barrier height
const RAIL_W := 0.5
const CHUNK := 140                  # samples per render chunk

# Sample flags
const F_RAIL_L := 1
const F_RAIL_R := 2
const F_PAD := 4                    # boost pad markings
const F_LINE := 8                   # start/finish or checkpoint stripe
const F_NO_PILLAR := 16
const F_RAILS := F_RAIL_L | F_RAIL_R

# Turtle state
var pos := Vector3.ZERO
var yaw := 0.0
var grade := 0.0                    # dy / dx_horizontal
var bank := 0.0                     # rad, + = right side up (left turn)
var width := 16.0
var dist := 0.0
var rails := F_RAILS
var group := 0                      # samples join only within a group

# Samples
var pts := PackedVector3Array()
var rights := PackedVector3Array()
var ups := PackedVector3Array()
var widths := PackedFloat32Array()
var dists := PackedFloat32Array()
var curv := PackedFloat32Array()    # yaw rate, rad/m (kerb paint)
var flags := PackedInt32Array()
var groups := PackedInt32Array()
var speeds := PackedFloat32Array()  # suggested speed (m/s) for the autopilot

var target_speed := 60.0
var _pending_flag := 0
var _pending_flag_len := 0.0


func start(p: Vector3, heading: float, w := 16.0) -> void:
	pos = p
	yaw = heading
	grade = 0.0
	bank = 0.0
	width = w
	_emit(0.0, 0)


func forward() -> Vector3:
	return Vector3(-sin(yaw), 0, -cos(yaw))


func frame() -> Basis:
	return Basis.from_euler(Vector3(atan(grade), yaw, bank))


## The main primitive: `length` m (horizontal), turning `turn_deg` (+ = left),
## climbing `rise` m with grade eased from the current value to `end_grade`,
## and banking from the current bank to `bank_deg`.
func seg(length: float, turn_deg := 0.0, rise := 0.0, end_grade := 0.0, bank_deg := 0.0, w := -1.0) -> void:
	var n := maxi(2, ceili(length / STEP))
	var yaw0 := yaw
	var bank0 := bank
	var w0 := width
	var w1 := width if w < 0.0 else w
	var y0 := pos.y
	var m0 := grade * length
	var m1 := end_grade * length
	var turn := deg_to_rad(turn_deg)
	var bank1 := deg_to_rad(bank_deg)
	var flat0 := Vector3(pos.x, 0, pos.z)
	var flat := flat0
	for k in range(1, n + 1):
		var s := float(k) / n
		var s_mid := (k - 0.5) / n
		var h := length / n
		flat += Vector3(-sin(yaw0 + turn * s_mid), 0, -cos(yaw0 + turn * s_mid)) * h
		yaw = yaw0 + turn * s
		# Cubic Hermite for height: continuous grade at both ends.
		var s2 := s * s
		var s3 := s2 * s
		var y := y0 + (-2 * s3 + 3 * s2) * rise + (s3 - 2 * s2 + s) * m0 + (s3 - s2) * m1
		var dy := (-6 * s2 + 6 * s) * rise + (3 * s2 - 4 * s + 1) * m0 + (3 * s2 - 2 * s) * m1
		grade = dy / length
		# Cosine ease for the bank: lowest peak roll acceleration, so the
		# road never drops away from a car riding high on the outside.
		var e := 0.5 - 0.5 * cos(PI * s)
		bank = lerpf(bank0, bank1, e)
		width = lerpf(w0, w1, e)
		pos = Vector3(flat.x, y, flat.z)
		_emit(turn / length, 0)


func straight(length: float, rise := 0.0, end_grade := 0.0) -> void:
	seg(length, 0.0, rise, end_grade, 0.0)


## Smooth connector to a target point and heading (degrees, 0 = north,
## 90 = west): a cubic Bezier in plan view, height eased like seg(), and
## banking worked out from the curvature at the current target speed, so
## turns lean the way a fast driver wants them to.
func to(target: Vector3, heading_deg: float, end_grade := 0.0, end_bank_deg := 0.0, k := 0.4, max_bank_deg := 38.0) -> void:
	var p0 := Vector2(pos.x, pos.z)
	var p1 := Vector2(target.x, target.z)
	var h1 := deg_to_rad(heading_deg)
	var d0 := Vector2(-sin(yaw), -cos(yaw))
	var d1 := Vector2(-sin(h1), -cos(h1))
	var chord := p0.distance_to(p1)
	var c0 := p0 + d0 * chord * k
	var c1 := p1 - d1 * chord * k
	var dense: Array[Vector2] = []
	var acc: Array[float] = [0.0]
	for i in 801:
		var t := i / 800.0
		var u := 1.0 - t
		dense.append(p0 * u * u * u + c0 * 3 * u * u * t + c1 * 3 * u * t * t + p1 * t * t * t)
		if i > 0:
			acc.append(acc[i - 1] + dense[i].distance_to(dense[i - 1]))
	var length := acc[800]
	var n := maxi(2, ceili(length / STEP))
	# Resample at even spacing; yaw from the tangent, curvature from yaw.
	var flats: Array[Vector2] = []
	var yaws: Array[float] = []
	var j := 0
	var prev_yaw := yaw
	for kk in range(1, n + 1):
		var s := length * kk / n
		while j < 799 and acc[j + 1] < s:
			j += 1
		var f := (s - acc[j]) / maxf(acc[j + 1] - acc[j], 1e-6)
		var p := dense[j].lerp(dense[j + 1], f)
		var tng := dense[j + 1] - dense[j]
		var y := atan2(-tng.x, -tng.y)
		y = prev_yaw + wrapf(y - prev_yaw, -PI, PI)
		prev_yaw = y
		flats.append(p)
		yaws.append(y)
	# Banking: lean into the curve, smoothed, eased in from the current bank
	# and out to the end bank.
	var h := length / n
	var want: Array[float] = []
	for i in n:
		var kappa := (yaws[mini(i + 1, n - 1)] - yaws[maxi(i - 1, 0)]) / (h * (mini(i + 1, n - 1) - maxi(i - 1, 0)))
		var b := atan(target_speed * target_speed * kappa / 9.8) * 0.75
		want.append(clampf(b, -deg_to_rad(max_bank_deg), deg_to_rad(max_bank_deg)))
	var win := int(12.0 / h)
	var bank0 := bank
	var bank1 := deg_to_rad(end_bank_deg)
	var y0 := pos.y
	var rise := target.y - pos.y
	var m0 := grade * length
	var m1 := end_grade * length
	for i in n:
		var sum := 0.0
		var cnt := 0
		for q in range(maxi(0, i - win), mini(n, i + win + 1)):
			sum += want[q]
			cnt += 1
		var b := sum / cnt
		var s := float(i + 1) / n
		var ease_in := smoothstep(0.0, minf(25.0 / length, 0.3), s)
		var ease_out := smoothstep(1.0, 1.0 - minf(25.0 / length, 0.3), s)
		b = lerpf(bank0, b, ease_in)
		b = lerpf(bank1, b, ease_out)
		var s2 := s * s
		var s3 := s2 * s
		var yy := y0 + (-2 * s3 + 3 * s2) * rise + (s3 - 2 * s2 + s) * m0 + (s3 - s2) * m1
		var dy := (-6 * s2 + 6 * s) * rise + (3 * s2 - 4 * s + 1) * m0 + (3 * s2 - 2 * s) * m1
		grade = dy / length
		var prev := yaw
		yaw = yaws[i]
		bank = b
		pos = Vector3(flats[i].x, yy, flats[i].y)
		_emit((yaw - prev) / h, 0)


## Vertical loop of radius r, drifting sideways (`side` = +1 right) so the
## exit runs beside the entry. Must be entered flat.
func loop(r: float, side := 1.0) -> void:
	var p0 := pos
	var b := frame()
	var fw := -b.z
	var upv := b.y
	var rt := b.x
	var shift := (width + 4.0) * side
	var n := ceili(TAU * r / 0.7)
	var old_rails := rails
	rails = 0
	for k in range(1, n + 1):
		var th := float(k) / n * TAU
		# Sideways drift eased so the loop starts and ends straight.
		var sh := (th - sin(th)) / TAU
		var dsh := (1.0 - cos(th)) / TAU
		pos = p0 + rt * shift * sh + upv * (r - r * cos(th)) + fw * (r * sin(th))
		var tng := (rt * shift * dsh + upv * r * sin(th) + fw * r * cos(th)).normalized()
		var nrm := upv * cos(th) - fw * sin(th)
		var right := tng.cross(nrm).normalized()
		nrm = right.cross(tng).normalized()
		_emit_frame(pos, right, nrm, 0.0, F_NO_PILLAR)
	rails = old_rails
	pos = p0 + rt * shift
	grade = 0.0
	bank = 0.0
	_emit(0.0, 0)


## A gap: the road stops and resumes `length` m ahead, `drop` m lower, at
## grade `land_grade`. The kicker before it is up to the caller.
func gap(length: float, drop: float, land_grade := 0.0) -> void:
	group += 1
	pos += forward() * length + Vector3.DOWN * drop
	grade = land_grade
	_emit(0.0, 0)


## Marks the next `length` m with a flag (boost pad, line).
func mark(flag: int, length: float) -> void:
	_pending_flag = flag
	_pending_flag_len = length


func _emit(yaw_rate: float, extra: int) -> void:
	var b := frame()
	_emit_frame(pos, b.x, b.y, yaw_rate, extra)


func _emit_frame(p: Vector3, right: Vector3, up: Vector3, yaw_rate: float, extra: int) -> void:
	if not pts.is_empty() and groups[groups.size() - 1] == group:
		dist += p.distance_to(pts[pts.size() - 1])
	var f := rails | extra
	if _pending_flag_len > 0.0:
		f |= _pending_flag
		_pending_flag_len -= STEP
	pts.append(p)
	rights.append(right)
	ups.append(up)
	widths.append(width)
	dists.append(dist)
	curv.append(yaw_rate)
	flags.append(f)
	groups.append(group)
	speeds.append(target_speed)


func sample_xform(i: int) -> Transform3D:
	var up := ups[i]
	var right := rights[i]
	return Transform3D(Basis(right, up, right.cross(up)), pts[i])


# ------------------------------------------------------------------ geometry

var road_mat: ShaderMaterial
var rail_mat: ShaderMaterial
var deck_mat: Material


func build_geometry() -> void:
	road_mat = ShaderMaterial.new()
	road_mat.shader = ROAD_SHADER
	rail_mat = ShaderMaterial.new()
	rail_mat.shader = RAIL_SHADER
	deck_mat = City.overgrown(Color(0.3, 0.31, 0.33), 0.6, 0.6, 4.0, 0.4, Color(0.15, 0.45, 1.0))

	var faces := PackedVector3Array()
	var start := 0
	while start < pts.size() - 1:
		var end := mini(start + CHUNK, pts.size() - 1)
		_build_chunk(start, end, faces)
		start = end

	var body := StaticBody3D.new()
	body.name = "TrackBody"
	var cs := CollisionShape3D.new()
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(faces)
	cs.shape = shape
	body.add_child(cs)
	add_child(body)


## Local cross-section offsets → world points for sample i.
func _p(i: int, x: float, y: float) -> Vector3:
	return pts[i] + rights[i] * x + ups[i] * y


func _build_chunk(i0: int, i1: int, faces: PackedVector3Array) -> void:
	var road := SurfaceTool.new()
	var rail := SurfaceTool.new()
	var deck := SurfaceTool.new()
	for st in [road, rail, deck]:
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(i0, i1):
		var j := i + 1
		if groups[i] != groups[j]:
			_caps(i, j, deck, faces)
			continue
		if i == 0 or groups[i - 1] != groups[i]:
			_cap(i, true, deck, faces)
		if j == pts.size() - 1:
			_cap(j, false, deck, faces)
		var hw_i := widths[i] * 0.5
		var hw_j := widths[j] * 0.5
		var col_i := _col(i)
		var col_j := _col(j)
		# Road top, split in strips so the up vector interpolates well.
		var strips := 4
		for k in strips:
			var u0 := float(k) / strips
			var u1 := float(k + 1) / strips
			var a := _p(i, lerpf(-hw_i, hw_i, u0), 0)
			var b := _p(i, lerpf(-hw_i, hw_i, u1), 0)
			var c := _p(j, lerpf(-hw_j, hw_j, u1), 0)
			var d := _p(j, lerpf(-hw_j, hw_j, u0), 0)
			_quad(road, faces, [a, b, c, d], [ups[i], ups[i], ups[j], ups[j]],
				[Vector2(u0, dists[i]), Vector2(u1, dists[i]), Vector2(u1, dists[j]), Vector2(u0, dists[j])],
				[col_i, col_i, col_j, col_j])
		# Sides: barrier or bare deck edge, then the underside.
		for side: float in [-1.0, 1.0]:
			var flag := F_RAIL_L if side < 0 else F_RAIL_R
			var has_i := flags[i] & flag != 0
			var has_j := flags[j] & flag != 0
			var ri := hw_i
			var rj := hw_j
			if has_i and has_j:
				var prof := [[0.0, 0.0], [0.0, RAIL_H], [RAIL_W, RAIL_H], [RAIL_W, -DECK]]
				var nrm := [Vector2(-1, 0), Vector2(0, 1), Vector2(1, 0)]
				for k in 3:
					var p0: Array = prof[k]
					var p1: Array = prof[k + 1]
					var n2: Vector2 = nrm[k]
					var ni := rights[i] * n2.x * side + ups[i] * n2.y
					var nj := rights[j] * n2.x * side + ups[j] * n2.y
					var q := [_p(i, side * (ri + p0[0]), p0[1]), _p(i, side * (ri + p1[0]), p1[1]),
						_p(j, side * (rj + p1[0]), p1[1]), _p(j, side * (rj + p0[0]), p0[1])]
					var st: SurfaceTool = rail if k < 2 else deck
					_quad(st, faces, q, [ni, ni, nj, nj],
						[Vector2(k, dists[i]), Vector2(k + 1, dists[i]), Vector2(k + 1, dists[j]), Vector2(k, dists[j])],
						[col_i, col_i, col_j, col_j])
				ri += RAIL_W
				rj += RAIL_W
			else:
				var ni := rights[i] * side
				var nj := rights[j] * side
				var q := [_p(i, side * ri, 0), _p(i, side * ri, -DECK), _p(j, side * rj, -DECK), _p(j, side * rj, 0)]
				_quad(deck, faces, q, [ni, ni, nj, nj], [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO], [col_i, col_i, col_j, col_j])
		var wl_i := hw_i + (RAIL_W if flags[i] & F_RAIL_L else 0.0)
		var wr_i := hw_i + (RAIL_W if flags[i] & F_RAIL_R else 0.0)
		var wl_j := hw_j + (RAIL_W if flags[j] & F_RAIL_L else 0.0)
		var wr_j := hw_j + (RAIL_W if flags[j] & F_RAIL_R else 0.0)
		var q := [_p(i, -wl_i, -DECK), _p(i, wr_i, -DECK), _p(j, wr_j, -DECK), _p(j, -wl_j, -DECK)]
		_quad(deck, faces, q, [-ups[i], -ups[i], -ups[j], -ups[j]], [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO],
			[col_i, col_i, col_j, col_j])

	for pair in [[road, road_mat, true], [rail, rail_mat, true], [deck, deck_mat, true]]:
		var st: SurfaceTool = pair[0]
		var mesh := st.commit()
		if mesh.get_surface_count() == 0:
			continue
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = pair[1]
		add_child(mi)


## Vertex colour for the road shader: r = turn, g = pad, b = line, a = width / 32.
func _col(i: int) -> Color:
	return Color(clampf(absf(curv[i]) * 40.0, 0, 1), 1.0 if flags[i] & F_PAD else 0.0,
		1.0 if flags[i] & F_LINE else 0.0, widths[i] / 32.0)


## End caps where the road stops (gap or track end).
func _caps(i: int, j: int, deck: SurfaceTool, faces: PackedVector3Array) -> void:
	_cap(i, false, deck, faces)
	_cap(j, true, deck, faces)


func _cap(i: int, is_start: bool, deck: SurfaceTool, faces: PackedVector3Array) -> void:
	var hw := widths[i] * 0.5
	var wl := hw + (RAIL_W if flags[i] & F_RAIL_L else 0.0)
	var wr := hw + (RAIL_W if flags[i] & F_RAIL_R else 0.0)
	var top_l := RAIL_H if flags[i] & F_RAIL_L else 0.0
	var top_r := RAIL_H if flags[i] & F_RAIL_R else 0.0
	var back := rights[i].cross(ups[i])
	var n := back if is_start else -back
	var poly := [_p(i, -wl, -DECK), _p(i, wr, -DECK), _p(i, wr, top_r), _p(i, hw, 0), _p(i, -hw, 0), _p(i, -wl, top_l)]
	var c := Color(0, 0, 0)
	_quad(deck, faces, [poly[0], poly[1], poly[3], poly[4]], [n, n, n, n], [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO], [c, c, c, c])
	_quad(deck, faces, [poly[1], poly[2], poly[3], poly[3]], [n, n, n, n], [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO], [c, c, c, c])
	_quad(deck, faces, [poly[0], poly[4], poly[5], poly[5]], [n, n, n, n], [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO], [c, c, c, c])


## Quad a-b-c-d; front face follows the given normals.
func _quad(st: SurfaceTool, faces: PackedVector3Array, q: Array, n: Array, uv: Array, col: Array) -> void:
	for tri in [[0, 1, 2], [0, 2, 3]]:
		var a: Vector3 = q[tri[0]]
		var b: Vector3 = q[tri[1]]
		var c: Vector3 = q[tri[2]]
		if a.is_equal_approx(b) or b.is_equal_approx(c) or a.is_equal_approx(c):
			continue
		var order: Array = tri
		var nn: Vector3 = n[tri[0]] + n[tri[1]] + n[tri[2]]
		# Godot's front faces wind clockwise seen from the front.
		if (b - a).cross(c - a).dot(nn) > 0.0:
			order = [tri[0], tri[2], tri[1]]
		for k in order:
			st.set_normal(n[k])
			st.set_uv(uv[k])
			st.set_color(col[k])
			st.add_vertex(q[k])
			faces.append(q[k])


# ------------------------------------------------------------------ queries

## Index of the sample nearest to p, searching around `hint` first (the
## course is a closed lap, so the search wraps round).
func nearest(p: Vector3, hint := -1, window := 60) -> int:
	var n := pts.size()
	var best := -1
	var best_d := INF
	if hint < 0:
		for i in n:
			var d := pts[i].distance_squared_to(p)
			if d < best_d:
				best_d = d
				best = i
		return best
	for k in range(-window, window + 1):
		var i := posmod(hint + k, n)
		var d := pts[i].distance_squared_to(p)
		if d < best_d:
			best_d = d
			best = i
	return best
