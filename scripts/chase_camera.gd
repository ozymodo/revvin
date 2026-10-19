extends Camera3D
## Chase camera. Follows the car's interpolated transform every rendered
## frame so it stays smooth at any frame rate. Heading leans toward the
## direction of travel, so drifts read clearly.

const PRESETS := [Vector2(7.0, 2.3), Vector2(4.6, 1.6), Vector2(12.0, 4.5), Vector2.ZERO]   # distance, height
const HOOD := 3                     # last preset: cockpit view

var target: RigidBody3D
var preset := 0

var _dir := Vector3.FORWARD
var _ref_h := 0.0
var _up := Vector3.UP
var _wall := 0.0
var _dist := 7.0
var _clear := 99.0                  # free distance behind the car before geometry (wall pull-in)
var _shake := 0.0
var _punch := 0.0                   # FOV kick + shake for big moments (tricks, pickups)
var _punch_fov := 0.0
var _t := 0.0
## Free look (mouse / right stick): yaw and pitch offsets from the chase view.
var _look := Vector2.ZERO
var _mouse_look := Vector2.ZERO
var _mouse_idle := 99.0

const MOUSE_SENS := Vector2(0.004, 0.003)
const MAX_LAG := 0.5                # m the view may trail the car's height
const LOOK_RETURN_AFTER := 1.0      # s after the mouse stops before the view swings back


func _ready() -> void:
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	fov = Settings.get_value("fov")
	preset = Settings.get_value("camera")
	near = 0.1
	far = 2000.0
	current = true
	snap()


func snap() -> void:
	var xf := target.get_global_transform_interpolated()
	_dir = _flat(-xf.basis.z, Vector3.FORWARD)
	_ref_h = xf.origin.y
	_dist = PRESETS[preset].x
	_place(xf, 0.0)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("camera"):
		preset = (preset + 1) % PRESETS.size()
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var rel: Vector2 = event.relative * float(Settings.get_value("mouse_sens"))
		if Settings.get_value("invert_mouse_y"):
			rel.y = -rel.y
		_mouse_look.x = wrapf(_mouse_look.x - rel.x * MOUSE_SENS.x, -PI, PI)
		_mouse_look.y = clampf(_mouse_look.y - rel.y * MOUSE_SENS.y, -0.35, 1.0)
		_mouse_idle = 0.0


## Right stick: points the camera that way round the car (down = behind),
## like Rocket League. Mouse: orbits freely, swings back once left alone.
func _update_look(delta: float) -> void:
	_mouse_idle += delta
	if _mouse_idle > LOOK_RETURN_AFTER:
		_mouse_look = _mouse_look.lerp(Vector2.ZERO, 1.0 - exp(-3.0 * delta))
	var stick := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	var target := _mouse_look
	if stick.length() > 0.2:
		target = Vector2(-atan2(stick.x, -stick.y) * clampf(stick.length(), 0.0, 1.0), 0.0)
	# Ease toward the target the short way round.
	var k := 1.0 - exp(-12.0 * delta)
	_look.x += wrapf(target.x - _look.x, -PI, PI) * k
	_look.y = lerpf(_look.y, target.y, k)


func _process(delta: float) -> void:
	_t += delta
	_update_look(delta)
	fov -= _punch_fov
	_place(target.get_global_transform_interpolated(), delta)
	_punch = move_toward(_punch, 0.0, delta * 2.2)
	var shake: float = Settings.get_value("shake")
	_punch_fov = 9.0 * _punch * _punch * minf(shake, 1.0)
	fov += _punch_fov
	h_offset += sin(_t * 47.0) * _punch * 0.07 * shake
	v_offset += cos(_t * 41.0) * _punch * 0.07 * shake


## A quick FOV kick and shake (0..1).
func punch(strength: float) -> void:
	_punch = maxf(_punch, clampf(strength, 0.0, 1.0))


func _place(xf: Transform3D, delta: float) -> void:
	var look_back := Input.is_action_pressed("look_back")
	if preset == HOOD:
		# Cockpit view, locked to the car (it follows rolls and flips).
		global_transform = Transform3D(xf.basis, xf * Vector3(0.0, 0.98, -0.2))
		rotate_object_local(Vector3.UP, PI if look_back else _look.x)
		rotate_object_local(Vector3.RIGHT, -_look.y * 0.6)
		fov = lerpf(fov, float(Settings.get_value("fov")) + 8.0 + clampf(target.linear_velocity.length() * 0.12, 0.0, 14.0), 1.0 - exp(-4.0 * delta) if delta > 0.0 else 1.0)
		h_offset = 0.0
		v_offset = 0.0
		return

	var k_dir := 1.0 - exp(-4.5 * delta) if delta > 0.0 else 1.0
	var vel := target.linear_velocity
	var car_up := xf.basis.y

	# Reference "up": world up normally, the car's up while it is driving on
	# a wall or through a loop, so the view follows it round.
	var on_wall: bool = target.grounded_wheels > 0 and car_up.y < 0.85
	_wall = lerpf(_wall, 1.0 if on_wall else 0.0, 1.0 - exp(-3.0 * delta) if delta > 0.0 else 1.0)
	var ref_up := _blend(Vector3.UP, car_up, _wall)
	_up = _blend(_up, ref_up, k_dir)

	# Heading. On the road: the car's nose, leaning toward the direction of
	# travel so drifts read clearly. In the air: the direction of travel, so
	# flips and rolls (where the nose points anywhere) don't swing the view.
	var airborne: bool = target.grounded_wheels == 0
	var flat_v := vel - _up * vel.dot(_up)
	var heading := _project(-xf.basis.z, _up, Vector3.ZERO)
	var dir := Vector3.ZERO
	if airborne:
		if flat_v.length() > 3.0:
			dir = flat_v.normalized()
		elif car_up.dot(_up) > 0.6:
			dir = heading
	else:
		dir = heading
		if heading != Vector3.ZERO and flat_v.length() > 4.0 and flat_v.dot(heading) > 0.0:
			dir = heading.lerp(flat_v.normalized(), 0.4).normalized()
	if dir != Vector3.ZERO:
		_dir = _blend(_dir, dir, k_dir)
	# Keep the heading level with the reference up. Coming off a wall ride
	# the old heading can point straight along the new up (straight up a
	# half-pipe), so fall back to whatever horizontal direction is left.
	var fallback := _project(flat_v, _up, Vector3.ZERO)
	if fallback == Vector3.ZERO:
		fallback = _project(-xf.basis.z, _up, Vector3.ZERO)
	if fallback == Vector3.ZERO:
		fallback = _project(-car_up, _up, Vector3.ZERO)
	_dir = _project(_dir, _up, fallback if fallback != Vector3.ZERO else _project(Vector3.FORWARD, _up, Vector3.RIGHT))

	var height := xf.origin.dot(_up)
	# Soak up suspension bounce and small hops on flat ground, but never fall
	# more than a little behind: launches and drops at speed stay framed.
	if _wall > 0.05 or delta == 0.0:
		_ref_h = height
	else:
		_ref_h = clampf(lerpf(_ref_h, height, 1.0 - exp(-10.0 * delta)), height - MAX_LAG, height + MAX_LAG)
	var spd := vel.length()
	var p: Vector2 = PRESETS[preset]
	_dist = lerpf(_dist, p.x + clampf(spd * 0.03, 0.0, 3.0), 1.0 - exp(-3.0 * delta) if delta > 0.0 else 1.0)
	var focus := xf.origin + _up * (_ref_h - height + 0.9)
	var view := _dir.rotated(_up, _look.x)
	var pos := focus - view * _dist * cos(_look.y) + _up * (p.y - 0.9 + _dist * sin(_look.y))

	# Don't let the camera dip below the ground or into walls and ramps: pull
	# in at once when something is in the way, ease back out once it's clear,
	# so passing a wall doesn't make the view pop in and out.
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(focus, pos, 1, [target.get_rid()])
	var hit := space.intersect_ray(q)
	var want := focus.distance_to(pos)
	var free := want
	if hit:
		free = maxf(focus.distance_to(hit.position) - 0.35, 0.5)
	_clear = free if free < _clear or delta == 0.0 else lerpf(_clear, free, 1.0 - exp(-4.0 * delta))
	if _clear < want:
		pos = focus + (pos - focus) * (_clear / want)

	if look_back:
		pos = focus + _dir * _dist + _up * (p.y - 0.9)
	global_position = pos
	# Aim a little ahead of a fast climb or fall so the car stays centred.
	var lead := _up * clampf(vel.dot(_up) * 0.04, -1.2, 1.2) if airborne else Vector3.ZERO
	look_at((focus - _dir * 3.0 if look_back else focus + view * 3.0) + lead, _up)

	var boost: float = target.thrust_valve
	var target_fov := float(Settings.get_value("fov")) - 2.0 + clampf(spd * 0.15, 0.0, 20.0) + boost * 8.0
	fov = lerpf(fov, target_fov, 1.0 - exp(-4.0 * delta) if delta > 0.0 else 1.0)

	_shake = lerpf(_shake, boost * 0.04 + target.jet_output * 0.03, 1.0 - exp(-8.0 * delta) if delta > 0.0 else 1.0)
	h_offset = sin(_t * 61.0) * _shake * float(Settings.get_value("shake"))
	v_offset = cos(_t * 53.0) * _shake * float(Settings.get_value("shake"))


## Normalised lerp; safe for opposite vectors, unlike Vector3.slerp.
static func _blend(a: Vector3, b: Vector3, t: float) -> Vector3:
	var r := a.lerp(b, t)
	return r.normalized() if r.length() > 0.01 else b


static func _project(v: Vector3, n: Vector3, fallback: Vector3) -> Vector3:
	v -= n * v.dot(n)
	return v.normalized() if v.length() > 0.05 else fallback


static func _flat(v: Vector3, fallback: Vector3) -> Vector3:
	v.y = 0.0
	return v.normalized() if v.length() > 0.05 else fallback
