extends Node3D
## Grinding, skateboard style. Every rail, ledge coping, barrier top and
## road edge in the world is registered here as a polyline. Jump (or fly)
## onto one and the car rides it, and you keep control of the car: steer
## turns it round on the rail, the stick tilts the nose. The trick is the
## pose you hold:
##   NOSE GRIND   lined up with the rail, nose dipped
##   TAIL GRIND   lined up, nose up
##   BLUNTSLIDE   turned across the rail (more than 55 degrees)
## Change pose mid-grind for a combo. Jump to pop off (steer held: off to
## that side; you still have your double jump / dodge), or ride it off the end.
##
## The catch is light: it reaches about a metre, with a small nudge toward
## the rail in the last couple of metres, and the car keeps the pose it
## landed in. On the rail the only help is balance (no rolling off).
##
## While grinding this node drives the car directly (car.gd hands over its
## _integrate_forces step through grind_hook).

signal grind_started(style: int)
signal grind_switched(style: int)
signal grind_ended(time: float, length: float)

enum Style { NOSE, TAIL, BLUNT }
const NAMES := ["NOSE GRIND", "TAIL GRIND", "BLUNTSLIDE"]
const STYLE_COLORS := [Color(1.0, 0.7, 0.25), Color(0.4, 0.85, 1.0), Color(1.0, 0.35, 0.75)]

const CELL := 16.0
const SNAP_SIDE := 1.0              # m sideways the catch reaches
const SNAP_ABOVE := 1.5             # m above the rail
const SNAP_BELOW := 0.4             # m below (coming in a touch low still catches)
const MAGNET_SIDE := 2.2            # m: a light nudge toward the rail starts this close
const MAGNET_ABOVE := 3.0
const MAGNET_MAX := 5.0             # m/s² at most (a nudge, not a pull)
const YAW_RATE := 2.6               # rad/s you can turn the car on the rail (A/D, stick)
const PITCH_RATE := 1.8             # rad/s you can tilt the nose (stick, W/S, arrows)
const MAX_TILT := 0.6               # rad: tilt the nose further and it's held there
const BLUNT_ANGLE := deg_to_rad(55.0)   # turned this far across the rail = bluntslide
const SIDE_POP := 4.0               # m/s sideways when you jump off with steering held
const MIN_SPEED := 4.0              # m/s along the rail to catch or keep grinding
const MAX_CATCH_ANGLE := deg_to_rad(70.0)   # travel vs rail, in plan
const FRICTION := 0.9               # m/s² lost while grinding
const BOOST_ACCEL := 9.0            # m/s² from the thrusters on a grind
const POP_UP := 6.5                 # m/s up when you jump off
const COOLDOWN := 0.35              # s after leaving before another catch

## A grindable line. `ups` (optional, per point) is the surface's up, so
## banked barrier tops lean the car with them.
class Rail:
	var pts: PackedVector3Array
	var ups: PackedVector3Array
	var kind := "rail"
	var loop := false


var car: RigidBody3D
var tricks: Node
var fx: Node
var sfx: Node
var rails: Array[Rail] = []
var active := false
var style := Style.NOSE
var grind_time := 0.0
var grind_len := 0.0

var _grid := {}
var _rail: Rail
var _seg := 0
var _t := 0.0                       # 0..1 along the segment
var _dir := 1                       # +1 = toward higher indices
var _speed := 0.0
var _cool := 0.0
var _pop := false
var _contact := Vector3.ZERO
var _sparks: GPUParticles3D
var _spark_mat: ParticleProcessMaterial
var _glow: OmniLight3D
var _heat: ImmediateMesh
var _heat_mat: StandardMaterial3D
var _heat_pts: Array[Vector3] = []
var _rail_mat: StandardMaterial3D
var _rail_glow_mat: StandardMaterial3D


## Hooked up by main once the car exists (the rails are built with the level).
func setup(the_car: RigidBody3D, the_tricks: Node, the_fx: Node, the_sfx: Node) -> void:
	car = the_car
	tricks = the_tricks
	fx = the_fx
	sfx = the_sfx
	car.grind_hook = _integrate


func _ready() -> void:
	_rail_mat = StandardMaterial3D.new()
	_rail_mat.albedo_color = Color(0.62, 0.64, 0.68)
	_rail_mat.metallic = 0.95
	_rail_mat.roughness = 0.22
	_rail_glow_mat = StandardMaterial3D.new()
	_rail_glow_mat.albedo_color = Color(0.1, 0.3, 0.5)
	_rail_glow_mat.emission_enabled = true
	_rail_glow_mat.emission = Color(0.25, 0.7, 1.0)
	_rail_glow_mat.emission_energy_multiplier = 2.0
	_build_fx()


# ------------------------------------------------------------------ registry

## Registers a grindable line. kind "rail" also builds a visible rail tube
## (with posts down to the ground when `posts`); "edge" is an existing
## edge (coping, barrier top, ledge) and gets a thin glowing grind strip.
func add_rail(pts: PackedVector3Array, kind := "rail", posts := true, ups := PackedVector3Array(), loop := false, post_len := -1.0) -> void:
	if pts.size() < 2:
		return
	var r := Rail.new()
	r.pts = pts
	r.ups = ups
	r.kind = kind
	r.loop = loop
	rails.append(r)
	var idx := rails.size() - 1
	var n := pts.size() - 1 + (1 if loop else 0)
	for i in n:
		var a := pts[i]
		var b := pts[(i + 1) % pts.size()]
		var c0 := Vector2i(floori(minf(a.x, b.x) / CELL), floori(minf(a.z, b.z) / CELL))
		var c1 := Vector2i(floori(maxf(a.x, b.x) / CELL), floori(maxf(a.z, b.z) / CELL))
		for cx in range(c0.x, c1.x + 1):
			for cz in range(c0.y, c1.y + 1):
				var key := Vector2i(cx, cz)
				if not _grid.has(key):
					_grid[key] = []
				_grid[key].append([idx, i])
	if kind == "rail":
		_rail_mesh(r, posts, post_len)
	elif kind == "edge":
		_edge_strip(r)


## Every edge of a track (track/track.gd) becomes grindable: barrier tops
## where it has barriers, the road's own edge where it doesn't. Loops are
## left out.
func add_track_edges(t: Node) -> void:
	for side in [-1.0, 1.0]:
		var flag: int = t.F_RAIL_L if side < 0 else t.F_RAIL_R
		var pts := PackedVector3Array()
		var ups := PackedVector3Array()
		var last_kind := -1
		var last_group := -1
		for i in range(0, t.pts.size(), 2):
			var f: int = t.flags[i]
			var kind := -1 if f & t.F_NO_PILLAR else (1 if f & flag else 0)
			if kind != last_kind or t.groups[i] != last_group:
				if pts.size() > 3:
					add_rail(pts, "edge", false, ups)
				pts = PackedVector3Array()
				ups = PackedVector3Array()
				last_kind = kind
				last_group = t.groups[i]
			if kind < 0:
				continue
			var hw: float = t.widths[i] * 0.5
			var up: Vector3 = t.ups[i]
			var p: Vector3 = t.pts[i] + t.rights[i] * side * (hw + (t.RAIL_W * 0.5 if kind == 1 else 0.0))
			p += up * (t.RAIL_H if kind == 1 else 0.02)
			pts.append(p)
			ups.append(up)
		if pts.size() > 3:
			add_rail(pts, "edge", false, ups)


func _seg_count(r: Rail) -> int:
	return r.pts.size() - 1 + (1 if r.loop else 0)


func _seg_pts(r: Rail, i: int) -> Array:
	return [r.pts[i], r.pts[(i + 1) % r.pts.size()]]


func _up_at(r: Rail, i: int, t: float) -> Vector3:
	if r.ups.is_empty():
		return Vector3.UP
	return r.ups[i].lerp(r.ups[(i + 1) % r.ups.size()], t).normalized()


## Nearest rail point to p within the given reach. Returns {} or
## {rail, seg, t, point, side_dist, height}.
## Edges (barrier tops, copings, road edges) only count once you've
## jumped (`edges`), so driving off a drop beside one doesn't grab it;
## dedicated rails always do.
func _nearest(p: Vector3, side_reach: float, above: float, below: float, edges := true) -> Dictionary:
	var best := {}
	var best_score := INF
	var c := Vector2i(floori(p.x / CELL), floori(p.z / CELL))
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var key := c + Vector2i(dx, dz)
			if not _grid.has(key):
				continue
			for entry in _grid[key]:
				var r: Rail = rails[entry[0]]
				if r.kind != "rail" and not edges:
					continue
				var sp := _seg_pts(r, entry[1])
				var a: Vector3 = sp[0]
				var b: Vector3 = sp[1]
				var ab := b - a
				var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
				var q := a + ab * t
				var up := _up_at(r, entry[1], t)
				var d := p - q
				var h := d.dot(up)
				var side := (d - up * h).length()
				if side > side_reach or h > above or h < -below:
					continue
				var score := side + absf(h) * 0.4
				if score < best_score:
					best_score = score
					best = {"rail": r, "seg": entry[1], "t": t, "point": q, "side": side, "height": h, "up": up}
	return best


# ------------------------------------------------------------------ catching

func _physics_process(delta: float) -> void:
	if car == null:
		return
	_cool -= delta
	if active:
		grind_time += delta
		if Input.is_action_just_pressed("lift"):
			_pop = true
		_update_style()
		_update_fx(true)
		return
	_update_fx(false)
	if _cool > 0.0 or car.grounded_wheels > 0 or car.flight_mode:
		return
	# Coming down near a rail: draw the car toward its line (the assist).
	var probe: Vector3 = car.global_position
	var near := _nearest(probe, MAGNET_SIDE, MAGNET_ABOVE, SNAP_BELOW, car._jumps > 0)
	if near.is_empty():
		return
	var tng := _tangent(near.rail, near.seg)
	var v: Vector3 = car.linear_velocity
	if absf(v.dot(tng)) < MIN_SPEED or _plan_angle(v, tng) > MAX_CATCH_ANGLE:
		return
	var up: Vector3 = near.up
	var off: Vector3 = probe - near.point
	var lateral: Vector3 = off - up * off.dot(up) - tng * off.dot(tng)
	if near.side > SNAP_SIDE or near.height > SNAP_ABOVE:
		if v.dot(up) < 1.0:
			car.apply_central_force(-lateral.normalized() * car.mass * minf(lateral.length() * 3.0, MAGNET_MAX))
		return
	# Only on its wheels-side: a car coming down sideways or upside down misses.
	if car.global_basis.y.dot(up) < 0.4:
		return
	# Close enough: catch it, unless still rising hard through it from below.
	if near.height < 0.2 and v.dot(up) > 2.0:
		return
	_begin(near, tng, v)


static func _plan_angle(v: Vector3, tng: Vector3) -> float:
	var a := Vector2(v.x, v.z)
	var b := Vector2(tng.x, tng.z)
	if a.length() < 0.5 or b.length() < 0.1:
		return 0.0
	var c := absf(a.normalized().dot(b.normalized()))
	return acos(clampf(c, 0.0, 1.0))


func _tangent(r: Rail, i: int) -> Vector3:
	var sp := _seg_pts(r, i)
	return ((sp[1] as Vector3) - (sp[0] as Vector3)).normalized()


func _begin(near: Dictionary, tng: Vector3, v: Vector3) -> void:
	_rail = near.rail
	_seg = near.seg
	_t = near.t
	_dir = 1 if v.dot(tng) >= 0.0 else -1
	_speed = absf(v.dot(tng))
	var fwd: Vector3 = -car.global_basis.z
	var along := tng * _dir
	# The style is whatever pose the car came down in (and is held in).
	var yaw_err := _plan_angle(fwd, along)
	style = _style_for(car.global_basis, along, near.up, Style.NOSE)
	active = true
	grind_time = 0.0
	grind_len = 0.0
	_heat_pts.clear()
	car._jumps = 2                      # the jump button pops off the rail instead
	car.grinding = true
	if tricks:
		tricks.grind_begin(NAMES[style], yaw_err if style != Style.BLUNT else 0.0)
	sfx.grind_catch()
	fx.punch(0.2)
	fx.sparks(near.point, STYLE_COLORS[style], 0.6, near.up)
	grind_started.emit(style)


## The style follows the pose you hold on the rail: turned across it is a
## bluntslide, nose dipped a nose grind, nose up a tail grind (level keeps
## whatever it was).
static func _style_for(b: Basis, along: Vector3, up: Vector3, current: int) -> int:
	var fwd := -b.z
	if _plan_angle(fwd, along) > BLUNT_ANGLE:
		return Style.BLUNT
	var tilt := fwd.dot(up)
	if tilt < -0.07:
		return Style.NOSE
	if tilt > 0.07:
		return Style.TAIL
	return Style.NOSE if current == Style.BLUNT else current


func _update_style() -> void:
	var want := _style_for(car.global_basis, _tangent(_rail, _seg) * _dir, _up_at(_rail, _seg, _t), style)
	if want != style:
		style = want
		if tricks:
			tricks.grind_switch(NAMES[style])
		sfx.grind_catch()
		grind_switched.emit(style)


# ------------------------------------------------------------------ riding

## Called from car._integrate_forces. Returns true while it drives the car.
func _integrate(state: PhysicsDirectBodyState3D) -> bool:
	if active and not car.grinding:
		cancel()                        # the car was reset or respawned
	if not active:
		return false
	var dt := state.step
	var r := _rail
	var tng := _tangent(r, _seg) * _dir
	# Gravity along the rail, friction, and the thrusters if boosting.
	_speed += -9.8 * tng.y * dt - FRICTION * dt
	if Input.is_action_pressed("boost") and car.thrust_tank > 0.0:
		_speed += BOOST_ACCEL * dt
		car.thrust_tank = maxf(0.0, car.thrust_tank - dt / car.THRUST_TANK_SECONDS)
	if _pop or _speed < 2.0:
		return _leave(state, tng, POP_UP if _pop else 0.0)
	# Advance along the polyline.
	var move := _speed * dt
	grind_len += move
	while move > 0.0:
		var sp := _seg_pts(r, _seg)
		var seg_len: float = (sp[1] as Vector3).distance_to(sp[0])
		var left := (1.0 - _t) * seg_len if _dir > 0 else _t * seg_len
		if move < left:
			_t += move / seg_len * _dir
			move = 0.0
		else:
			move -= left
			var next := _seg + _dir
			if r.loop:
				next = posmod(next, _seg_count(r))
			if next < 0 or next >= _seg_count(r):
				return _leave(state, tng, 1.0)      # ran off the end
			_seg = next
			_t = 0.0 if _dir > 0 else 1.0
	var sp2 := _seg_pts(r, _seg)
	var p: Vector3 = (sp2[0] as Vector3).lerp(sp2[1], _t)
	var up := _up_at(r, _seg, _t)
	tng = _tangent(r, _seg) * _dir
	_contact = p
	# The car is yours on the rail: steer turns it round the rail's up (bring
	# it across for a bluntslide, or all the way round), the stick tilts the
	# nose (nose or tail grind). The only help: it stays balanced (no roll)
	# and a tilt past MAX_TILT is held there.
	var b := state.transform.basis.orthonormalized()
	b = Basis(up, -car._steer * YAW_RATE * dt) * b
	b = Basis(b.x.normalized(), -car._spin.x * PITCH_RATE * dt) * b
	var fwd := -b.z
	var roll := b.x.dot(up)                         # right side up/down
	b = Basis(fwd.normalized(), roll * minf(1.0, 10.0 * dt)) * b
	var tilt := asin(clampf((-b.z).dot(up), -1.0, 1.0))
	if absf(tilt) > MAX_TILT:
		b = Basis(b.x.normalized(), -(absf(tilt) - MAX_TILT) * signf(tilt)) * b
	b = b.orthonormalized()
	# Tilted, the dipped end rests on the rail, so the car rides higher.
	var h := 0.5 + 1.5 * absf((-b.z).dot(up)) * (0.0 if _plan_angle(-b.z, tng) > BLUNT_ANGLE else 1.0)
	state.transform = Transform3D(b, p + up * h)
	state.linear_velocity = tng * _speed
	state.angular_velocity = Vector3.ZERO
	car.grounded_wheels = 0
	car.jet_output = 0.0
	for w in car.wheels:                 # no tyre smoke or skids off a rail
		w.grounded = false
		w.slip = 0.0
	return true


func _leave(state: PhysicsDirectBodyState3D, tng: Vector3, up_v: float) -> bool:
	var up := _up_at(_rail, _seg, _t)
	state.linear_velocity = tng * maxf(_speed, 0.0) + up * up_v
	if _pop:
		# Jumping off with steering held hops you off to that side.
		state.linear_velocity += tng.cross(up).normalized() * car._steer * SIDE_POP
	state.angular_velocity = Vector3.ZERO
	var popped := _pop
	_pop = false
	active = false
	car.grinding = false
	_cool = COOLDOWN
	# A pop counts as the first jump: the second tap still double jumps or dodges.
	car._jumps = 1 if popped else 0
	car._since_jump = 0.0
	if tricks:
		tricks.grind_end(grind_time, grind_len, _speed)
	if popped:
		sfx.grind_catch()
		fx.sparks(_contact, STYLE_COLORS[style], 0.4, up)
	grind_ended.emit(grind_time, grind_len)
	return false


## Respawn, wreck: drop the grind without scoring.
func cancel() -> void:
	if active:
		active = false
		car.grinding = false
		_cool = COOLDOWN
		if tricks:
			tricks.grind_end(0.0, 0.0, 0.0)


# ------------------------------------------------------------------ looks

func _build_fx() -> void:
	_sparks = GPUParticles3D.new()
	_sparks.amount = 140
	_sparks.lifetime = 0.45
	_sparks.local_coords = false
	_sparks.emitting = false
	_sparks.visibility_aabb = AABB(Vector3(-20, -20, -20), Vector3(40, 40, 40))
	_spark_mat = ParticleProcessMaterial.new()
	_spark_mat.direction = Vector3(0, 0.6, 1)
	_spark_mat.spread = 35.0
	_spark_mat.initial_velocity_min = 4.0
	_spark_mat.initial_velocity_max = 11.0
	_spark_mat.gravity = Vector3(0, -14, 0)
	_spark_mat.scale_min = 0.7
	_spark_mat.scale_max = 1.4
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	grad.colors = PackedColorArray([Color(3, 2.6, 2, 1), Color(2.4, 1.2, 0.4, 0.9), Color(1.2, 0.3, 0.1, 0)])
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	_spark_mat.color_ramp = gt
	_sparks.process_material = _spark_mat
	_sparks.draw_pass_1 = preload("res://scripts/fx.gd").glow_quad(0.11, 1.5)
	add_child(_sparks)
	_glow = OmniLight3D.new()
	_glow.light_color = Color(1.0, 0.6, 0.25)
	_glow.omni_range = 4.0
	_glow.light_energy = 0.0
	add_child(_glow)
	# A hot streak left on the rail behind the car.
	_heat = ImmediateMesh.new()
	_heat_mat = StandardMaterial3D.new()
	_heat_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_heat_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_heat_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_heat_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_heat_mat.vertex_color_use_as_albedo = true
	_heat_mat.albedo_color = Color(2.5, 2.5, 2.5)
	var mi := MeshInstance3D.new()
	mi.mesh = _heat
	mi.top_level = true
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _update_fx(on: bool) -> void:
	_sparks.emitting = on
	if sfx:
		sfx.grind_level = clampf(_speed / 25.0, 0.3, 1.2) if on else 0.0
	if on:
		var back := -car.linear_velocity.normalized() if car.linear_velocity.length() > 0.5 else Vector3.BACK
		_sparks.global_transform = Transform3D(Basis.looking_at(-back, Vector3.UP) if absf(back.y) < 0.98 else Basis(), _contact)
		_sparks.amount_ratio = clampf(_speed / 25.0, 0.3, 1.0)
		var c: Color = STYLE_COLORS[style]
		_spark_mat.color = c.lerp(Color.WHITE, 0.5)
		_glow.global_position = _contact + Vector3.UP * 0.3
		_glow.light_color = c
		_glow.light_energy = 2.0 + randf() * 1.5
		if _heat_pts.is_empty() or _heat_pts[-1].distance_to(_contact) > 0.4:
			_heat_pts.append(_contact)
			if _heat_pts.size() > 40:
				_heat_pts.pop_front()
	else:
		_glow.light_energy = move_toward(_glow.light_energy, 0.0, 0.5)
		if not _heat_pts.is_empty() and Engine.get_physics_frames() % 3 == 0:
			_heat_pts.pop_front()
	_draw_heat()


func _draw_heat() -> void:
	_heat.clear_surfaces()
	var n := _heat_pts.size()
	if n < 2:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var c: Color = STYLE_COLORS[style]
	_heat.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP, _heat_mat)
	for i in n:
		var p := _heat_pts[i] + Vector3.UP * 0.04
		var nxt := _heat_pts[mini(i + 1, n - 1)]
		var prv := _heat_pts[maxi(i - 1, 0)]
		var side := (nxt - prv).cross(cam.global_position - p).normalized() * 0.06
		var a := float(i) / (n - 1)
		_heat.surface_set_color(Color(c.r, c.g, c.b, a * a * 0.9))
		_heat.surface_add_vertex(p + side)
		_heat.surface_set_color(Color(c.r, c.g, c.b, a * a * 0.9))
		_heat.surface_add_vertex(p - side)
	_heat.surface_end()


## A visible rail: a steel tube with a glowing top strip, on posts.
func _rail_mesh(r: Rail, posts: bool, post_len := -1.0) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sides := 8
	var rad := 0.07
	var n := r.pts.size() + (1 if r.loop else 0)
	var rings: Array = []
	for i in n:
		var p := r.pts[i % r.pts.size()]
		var a := r.pts[maxi(i - 1, 0) % r.pts.size()] if i > 0 or r.loop else p
		var b := r.pts[mini(i + 1, n - 1) % r.pts.size()]
		var t := (b - a).normalized() if (b - a).length() > 0.001 else Vector3.FORWARD
		var x := t.cross(Vector3.UP).normalized() if absf(t.y) < 0.99 else Vector3.RIGHT
		var y := x.cross(t).normalized()
		var ring := []
		for k in sides:
			var ang := TAU * k / sides
			ring.append([p + (x * cos(ang) + y * sin(ang)) * rad, (x * cos(ang) + y * sin(ang))])
		rings.append(ring)
	for i in n - 1:
		for k in sides:
			var k2 := (k + 1) % sides
			for v in [rings[i][k], rings[i + 1][k], rings[i + 1][k2], rings[i][k], rings[i + 1][k2], rings[i][k2]]:
				st.set_normal(v[1])
				st.add_vertex(v[0])
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _rail_mat
	add_child(mi)
	_edge_strip(r)
	if not posts:
		return
	var post_mesh := CylinderMesh.new()
	post_mesh.top_radius = 0.05
	post_mesh.bottom_radius = 0.06
	post_mesh.radial_segments = 6
	post_mesh.height = 1.0
	var run := 0.0
	for i in r.pts.size():
		if i > 0:
			run += r.pts[i].distance_to(r.pts[i - 1])
		if i > 0 and i < r.pts.size() - 1 and run < 5.0:
			continue
		run = 0.0
		# Posts run down to the ground (y = 0) unless the rail gives a length
		# (rails over hills and on top of boxes).
		var top := r.pts[i]
		var h: float = top.y if post_len < 0.0 else post_len
		if h < 0.15:
			continue
		var post := MeshInstance3D.new()
		post.mesh = post_mesh
		post.material_override = _rail_mat
		post.scale = Vector3(1, h, 1)
		post.position = top - Vector3.UP * h * 0.5
		add_child(post)


## A thin glowing strip along the line, so grindable edges read at a glance.
func _edge_strip(r: Rail) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := r.pts.size() + (1 if r.loop else 0)
	for i in n - 1:
		var a := r.pts[i % r.pts.size()]
		var b := r.pts[(i + 1) % r.pts.size()]
		var ua := _up_at(r, i % r.pts.size(), 0.0)
		var t := (b - a).normalized()
		var x := t.cross(ua).normalized() * 0.035
		var lift := ua * (0.075 if r.kind == "rail" else 0.02)
		for v in [a + lift - x, b + lift - x, b + lift + x, a + lift - x, b + lift + x, a + lift + x]:
			st.set_normal(ua)
			st.add_vertex(v)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _rail_glow_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
