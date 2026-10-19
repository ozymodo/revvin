extends Node3D
## MAG, the look and sound of it, and what a slam does to the world.
## The physics (the pull, the cling, spotting a slam) is in car.gd; this
## node draws the electromagnet in the floor pan, the field reaching down
## to the surface, the lock-on mark there, and the shockwave when the car
## comes down hard.
##
##   coil     two rings under the car, dim when idle, white-hot when on
##   field    jagged arcs from the coil to the surface, with rings of field
##            sliding down them, faster the harder it's pulling
##   lock-on  a reticle on the surface; it turns orange once the approach
##            is fast or long enough to slam
##   slam     electric shockwave ring sized to the slam, lightning forking
##            out across the ground, sparks, dust, a camera kick; enemies
##            in the radius take damage and get thrown, the scenery breaks

const Car := preload("res://scripts/car.gd")

const MAG_COLOR := Color(0.42, 0.78, 1.0)
const SLAM_COLOR := Color(1.0, 0.62, 0.25)
const FIELD_RINGS := 5
const SLAM_DAMAGE := Vector2(25.0, 160.0)    # at the centre of the weakest / strongest slam

var car: Car
var fx: Node
var sfx: Node
var combat: Node
var tricks: Node
var wrecking: Node

var _coil: Array[MeshInstance3D] = []
var _coil_mat: StandardMaterial3D
var _light: OmniLight3D
var _arcs: ImmediateMesh
var _arc_mat: StandardMaterial3D
var _rings: Array[MeshInstance3D] = []
var _ring_mat: StandardMaterial3D
var _reticle: MeshInstance3D
var _reticle_mat: StandardMaterial3D
var _glow := 0.0                    # 0..1, eases in and out with the magnet
var _phase := 0.0
var _crackle_t := 0.0
var _was_on := false


func _ready() -> void:
	_coil_mat = _glow_mat(MAG_COLOR)
	for r in [[0.62, 0.7], [0.36, 0.42]]:
		var t := TorusMesh.new()
		t.inner_radius = r[0]
		t.outer_radius = r[1]
		t.rings = 24
		t.ring_segments = 6
		var mi := MeshInstance3D.new()
		mi.mesh = t
		mi.material_override = _coil_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = Vector3(0, 0.02, 0.05)
		car.add_child(mi)
		_coil.append(mi)
	_light = OmniLight3D.new()
	_light.light_color = MAG_COLOR
	_light.omni_range = 4.0
	_light.light_energy = 0.0
	_light.position = Vector3(0, -0.1, 0)
	car.add_child(_light)

	_arc_mat = _glow_mat(Color.WHITE)
	_arc_mat.vertex_color_use_as_albedo = true
	_arc_mat.albedo_color = Color(1.7, 1.7, 1.7)
	_arc_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_arcs = ImmediateMesh.new()
	var ami := MeshInstance3D.new()
	ami.mesh = _arcs
	ami.top_level = true
	ami.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ami.material_override = _arc_mat
	add_child(ami)

	_ring_mat = _glow_mat(MAG_COLOR)
	for i in FIELD_RINGS:
		var t := TorusMesh.new()
		t.inner_radius = 0.92
		t.outer_radius = 1.0
		t.rings = 32
		t.ring_segments = 4
		var mi := MeshInstance3D.new()
		mi.mesh = t
		mi.material_override = _ring_mat
		mi.top_level = true
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false
		add_child(mi)
		_rings.append(mi)

	_reticle_mat = _glow_mat(MAG_COLOR)
	_reticle = MeshInstance3D.new()
	var rt := TorusMesh.new()
	rt.inner_radius = 0.9
	rt.outer_radius = 1.0
	rt.rings = 48
	rt.ring_segments = 4
	_reticle.mesh = rt
	_reticle.material_override = _reticle_mat
	_reticle.top_level = true
	_reticle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_reticle.visible = false
	add_child(_reticle)

	car.mag_slam.connect(_on_slam)


static func _glow_mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = c
	return m


## The approach is going to slam (same test as car.gd's _land_slam).
func slam_ready() -> bool:
	if not car.mag_locked or car.grounded_wheels > 0:
		return false
	var into: float = -car.linear_velocity.dot(car.mag_normal)
	return into > Car.SLAM_MIN_SPEED or car._mag_from > Car.SLAM_MIN_DROP


func _process(delta: float) -> void:
	var on: bool = car.mag_on
	_glow = move_toward(_glow, 1.0 if on else 0.0, delta * (8.0 if on else 3.0))
	_phase += delta * lerpf(1.2, 4.0, car.mag_charge)
	var ready := slam_ready()
	var hot: Color = SLAM_COLOR if ready else MAG_COLOR

	# Coil: always faintly lit (it's part of the car), spinning up when on.
	var pulse := 0.5 + 0.5 * sin(_phase * TAU * 2.0)
	_coil_mat.albedo_color = Color(hot * (0.35 + _glow * (1.6 + pulse * 0.8)), 0.25 + 0.75 * _glow)
	_coil[0].rotate_y(delta * (0.6 + _glow * 14.0))
	_coil[1].rotate_y(-delta * (0.8 + _glow * 18.0))
	_light.light_color = hot
	_light.light_energy = _glow * (2.0 + pulse)

	_arcs.clear_surfaces()
	var locked: bool = on and car.mag_locked and car.grounded_wheels == 0
	for r in _rings:
		r.visible = locked
	_reticle.visible = on and car.mag_locked
	if not on:
		_was_on = false
		return
	if not _was_on:
		_was_on = true
		if sfx:
			sfx.mag_on()
	_crackle_t -= delta
	if _crackle_t <= 0.0 and sfx:
		_crackle_t = randf_range(0.06, 0.14)
		sfx.mag_crackle(0.5 + car.mag_charge)
	var xf: Transform3D = car.get_global_transform_interpolated()
	var from: Vector3 = xf * Vector3(0, 0.02, 0.05)
	var cam := get_viewport().get_camera_3d()
	var eye: Vector3 = cam.global_position if cam else from + Vector3.UP * 10.0
	_arcs.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	_bolt(_zigzag(from, from + xf.basis.y * -0.35, 2, 0.08), eye, hot, 0.8)    # never an empty surface
	# The coil charging the chassis: short arcs crawling out to the wheel
	# hubs, which is what shows from the chase camera.
	for w in car.wheels:
		if randf() < 0.75:
			var hub: Vector3 = xf * (w.mount + Vector3(0, -0.25, 0))
			_bolt(_zigzag(from, hub, 5, 0.12), eye, hot, 0.6 + 0.4 * _glow)
	if car.mag_locked:
		_field(from, eye, hot, pulse)
	_arcs.surface_end()


func _field(from: Vector3, eye: Vector3, hot: Color, pulse: float) -> void:
	var to: Vector3 = car.mag_point
	var n: Vector3 = car.mag_normal

	# Lock-on mark on the surface: wide when far, tight when close.
	var size := clampf(car.mag_dist * 0.12, 1.4, 7.0)
	_reticle.global_transform = Transform3D(_basis_up(n) * Basis(Vector3.UP, _phase * 1.5), to + n * 0.06).scaled_local(Vector3(size, 1.0, size))
	_reticle_mat.albedo_color = Color(hot * (1.2 + pulse), 0.9)

	if car.grounded_wheels > 0:
		return
	# Field rings sliding from the coil to the surface.
	for i in FIELD_RINGS:
		var t := fmod(_phase + float(i) / FIELD_RINGS, 1.0)
		var p := from.lerp(to, t)
		var r := lerpf(0.9, size * 0.6, t)
		_rings[i].global_transform = Transform3D(_basis_up(n), p).scaled_local(Vector3(r, 1.0, r))
	_ring_mat.albedo_color = Color(hot * 1.4, 0.5 * (1.0 - 0.5 * pulse))

	# Arcs down to the surface: redrawn every frame so they crawl and flicker.
	var dist := from.distance_to(to)
	for k in 3:
		var side_off := _basis_up(n) * Vector3(randf_range(-0.5, 0.5), 0.0, randf_range(-0.7, 0.7))
		var end := to + _basis_up(n) * Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)) * size * 0.5
		_bolt(_zigzag(from + side_off, end, maxi(6, int(dist / 1.2)), clampf(dist * 0.03, 0.12, 0.9)), eye, hot, 0.7 + 0.3 * car.mag_charge)


## A lightning stroke: a thin hot core, a coloured sheath and a faint halo.
func _bolt(pts: Array, eye: Vector3, c: Color, a: float) -> void:
	_ribbon(pts, eye, c.lerp(Color.WHITE, 0.55), 0.018, a)
	_ribbon(pts, eye, c, 0.055, 0.55 * a)
	_ribbon(pts, eye, c, 0.16, 0.12 * a)


func _ribbon(pts: Array, eye: Vector3, c: Color, w: float, a: float) -> void:
	var col := Color(c.r, c.g, c.b, a)
	for i in pts.size() - 1:
		var p0: Vector3 = pts[i]
		var p1: Vector3 = pts[i + 1]
		var sv := (p1 - p0).cross(eye - p0).normalized() * w
		for v in [p0 - sv, p0 + sv, p1 + sv, p0 - sv, p1 + sv, p1 - sv]:
			_arcs.surface_set_color(col)
			_arcs.surface_add_vertex(v)


static func _zigzag(a: Vector3, b: Vector3, segs: int, amp: float) -> Array:
	var out: Array = [a]
	for i in range(1, segs):
		out.append(a.lerp(b, float(i) / segs) + Vector3(randf_range(-amp, amp), randf_range(-amp, amp), randf_range(-amp, amp)))
	out.append(b)
	return out


## A basis whose Y axis is `n` (for rings lying on a surface).
static func _basis_up(n: Vector3) -> Basis:
	var x := n.cross(Vector3.FORWARD if absf(n.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	return Basis(x, n, x.cross(n))


# ------------------------------------------------------------------ slam

func _on_slam(at: Vector3, n: Vector3, power: float, radius: float) -> void:
	var c := MAG_COLOR.lerp(Color.WHITE, 0.3)
	if fx:
		fx.ring(at + n * 0.15, c, radius, 0.55 + 0.25 * power, n, null, 1.0)
		fx.ring(at + n * 0.25, Color.WHITE, radius * 0.45, 0.35, n, null, 1.0)
		fx.ring(at + n * 0.1, SLAM_COLOR, radius * 0.75, 0.45 + 0.2 * power, n, null, 0.6)
		fx.burst(at + n * 0.3, c, 0.8 + 1.4 * power, n)
		fx.dust(at, 0.4 + power)
		fx.sweep(MAG_COLOR, true, 0.6 + 0.4 * power)
		fx.punch(0.25 + 0.55 * power)
		# Lightning forking out across the surface to the shockwave's edge.
		var b := _basis_up(n)
		var bolts := 4 + int(power * 8.0)
		var space := get_world_3d().direct_space_state
		for i in bolts:
			var ang := TAU * (float(i) + randf() * 0.6) / bolts
			var reach := radius * randf_range(0.55, 1.0)
			var tip := at + b * Vector3(cos(ang) * reach, 0.0, sin(ang) * reach)
			# Hug the ground: drop the tip onto whatever is there.
			var q := PhysicsRayQueryParameters3D.create(tip + n * 4.0, tip - n * 6.0, 1, [car.get_rid()])
			var hit := space.intersect_ray(q)
			if not hit.is_empty():
				tip = hit.position + n * 0.1
			fx.lightning(at + n * 0.4, tip, c)
	if sfx:
		sfx.mag_slam(power)
	if combat:
		combat.slam(at, radius, lerpf(SLAM_DAMAGE.x, SLAM_DAMAGE.y, power))
	if wrecking:
		wrecking.explode(at, lerpf(2.0, 7.0, power), lerpf(1.5, 9.0, power))
	if tricks:
		tricks.mag_slam(power, radius)
