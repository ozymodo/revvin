extends Control
## On-screen controls for phones and tablets, all drawn in _draw().
##
##   left thumb   floating stick: steer · in the air, pitch and yaw
##   right thumb  GAS, BRAKE (reverse), JUMP (hold to fly), BOOST, DRIFT
##   top left     pause menu, camera, recover, fullscreen
##   the car      grab it and drag: it tips the way you drag (up = front
##                flip, down = back flip, sideways = barrel roll, diagonals
##                mix). Hold still to hold the angle, let go mid-swipe to
##                flick it spinning. A second finger twisting round the
##                first spins it flat. On the road the first drag jumps.
##   anywhere else  drag to look around
##
## Shows itself on phones/tablets, or on any device at its first touch, and
## hides again when a key or controller button is pressed.

const Car := preload("res://scripts/car.gd")

const C_FILL := Color(0.07, 0.07, 0.08, 0.38)
const C_EDGE := Color(1, 1, 1, 0.32)
const C_TEXT := Color(0.92, 0.92, 0.9, 0.9)
const C_HELD := Color(1.0, 0.62, 0.22)
const C_GRAB := Color(0.45, 0.85, 1.0)

const DESIGN_H := 400.0             # layout unit: 1/400 of the screen height
const STICK_R := 58.0
const DRAG_RATE := PI / 2.0         # radians per quarter screen height dragged
const FLICK_WINDOW := 0.1           # s of finger motion averaged into a flick

var car: Car
var cam: Camera3D
var open_menu := Callable()

var _u := 1.0
## [id, action, label, anchor (0..1 of the screen), offset (units), radius (units), colour]
var _buttons := [
	["gas", "throttle", "GAS", Vector2(1, 1), Vector2(-62, -66), 44.0, Color(0.33, 0.75, 0.58)],
	["brake", "brake", "BRAKE", Vector2(1, 1), Vector2(-156, -44), 32.0, Color(1.0, 0.45, 0.35)],
	["jump", "lift", "JUMP", Vector2(1, 1), Vector2(-74, -170), 36.0, Color(0.9, 0.38, 0.26)],
	["boost", "boost", "BOOST", Vector2(1, 1), Vector2(-164, -132), 32.0, Color(0.95, 0.65, 0.25)],
	["drift", "handbrake", "DRIFT", Vector2(1, 1), Vector2(-238, -48), 26.0, Color(0.55, 0.47, 1.0)],
	["menu", "", "II", Vector2(0, 0), Vector2(28, 28), 20.0, Color.WHITE],
	["camera", "camera", "CAM", Vector2(0, 0), Vector2(76, 28), 20.0, Color.WHITE],
	["reset", "reset", "", Vector2(0, 0), Vector2(124, 28), 20.0, Color.WHITE],
	["full", "", "", Vector2(0, 0), Vector2(172, 28), 20.0, Color.WHITE],
]
var _held := {}                     # button id -> touch index

var _stick_idx := -1
var _stick_base := Vector2.ZERO
var _stick_vec := Vector2.ZERO      # -1..1, y down

var _grab_idx := -1
var _grab_pos := Vector2.ZERO
var _grab_travel := 0.0
var _grab_hopped := false
var _twist_idx := -1
var _twist_pos := Vector2.ZERO
var _samples: Array = []            # [time, world rotation vector]

var _look := {}                     # touch index -> last position
var _hint := 1.0                    # "grab the car" hint fades after the first grab
var _mouse_binds := {}              # action -> mouse events taken off it while touch is on


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	if Settings.is_mobile():
		_activate.call_deferred()


func _activate() -> void:
	if visible:
		return
	visible = true
	Settings.touch_mode = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# Touches also arrive as emulated left clicks (that's how the pause menu
	# gets them): keep those off boost and jump.
	for a in ["boost", "lift", "look_back"]:
		for e in InputMap.action_get_events(a):
			if e is InputEventMouseButton:
				InputMap.action_erase_event(a, e)
				_mouse_binds[a] = _mouse_binds.get(a, []) + [e]
	# Lay the menus and HUD out for a small screen.
	var w := get_tree().root
	w.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	w.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	w.content_scale_size = Vector2i(1280, 720)


func _deactivate() -> void:
	_release_all()
	visible = false
	Settings.touch_mode = false
	for a in _mouse_binds:
		for e in _mouse_binds[a]:
			InputMap.action_add_event(a, e)
	_mouse_binds.clear()
	var w := get_tree().root
	w.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		if not visible:
			_activate()
		if get_tree().paused:
			return                      # the pause menu takes its taps as clicks
		if event is InputEventScreenTouch:
			_touch(event)
		else:
			_drag(event)
		get_viewport().set_input_as_handled()
	elif visible and not Settings.is_mobile() and (event is InputEventKey or event is InputEventJoypadButton) and event.pressed:
		_deactivate()


func _process(delta: float) -> void:
	if not visible:
		return
	# Anchors don't follow a content-scale change made at runtime: track
	# the visible rect directly.
	var vr := get_viewport_rect()
	if size != vr.size:
		position = Vector2.ZERO
		size = vr.size
	_u = size.y / DESIGN_H
	# The menu pauses the game; drop whatever was held so nothing sticks.
	if get_tree().paused and (not _held.is_empty() or _stick_idx >= 0 or _grab_idx >= 0):
		_release_all()
	if _grab_idx >= 0 and car and not car.touch_held:
		_grab_idx = -1                  # the car was reset under the finger
		_twist_idx = -1
	if _grab_idx < 0 and _hint < 1.0:
		_hint = maxf(0.0, _hint - delta)
	queue_redraw()


# ------------------------------------------------------------------ touches

func _touch(e: InputEventScreenTouch) -> void:
	if e.pressed:
		var b := _button_at(e.position)
		if b != "":
			_press(b, e.index)
		elif _grab_idx >= 0 and _twist_idx < 0:
			_twist_idx = e.index        # second finger while holding the car: twist to spin it
			_twist_pos = e.position
		elif _grab_idx < 0 and _on_car(e.position):
			_grab_idx = e.index
			_grab_pos = e.position
			_grab_travel = 0.0
			_grab_hopped = false
			_samples.clear()
			_hint = 0.999
			car.touch_grab()
		elif _stick_idx < 0 and e.position.x < size.x * 0.45:
			_stick_idx = e.index
			var m := (STICK_R + 16.0) * _u
			_stick_base = e.position.clamp(Vector2(m, m), size - Vector2(m, m))
			_stick_vec = Vector2.ZERO
			_stick_apply()
		else:
			_look[e.index] = e.position
		return
	# Released.
	for id in _held.keys():
		if _held[id] == e.index:
			_release(id)
	if e.index == _stick_idx:
		_stick_idx = -1
		_stick_vec = Vector2.ZERO
		_stick_apply()
	elif e.index == _grab_idx:
		_let_go()
	elif e.index == _twist_idx:
		_twist_idx = -1
	_look.erase(e.index)


func _drag(e: InputEventScreenDrag) -> void:
	if e.index == _stick_idx:
		_stick_vec = ((e.position - _stick_base) / (STICK_R * _u)).limit_length(1.0)
		_stick_apply()
	elif e.index == _grab_idx:
		_grab_drag(e.position)
	elif e.index == _twist_idx:
		_twist_drag(e.position)
	elif _look.has(e.index):
		cam.touch_look((e.position - _look[e.index]) / _u)
		_look[e.index] = e.position
	else:
		# A finger that slid onto a button from elsewhere doesn't press it,
		# but one that slides off a button lets it go.
		for id in _held.keys():
			if _held[id] == e.index and _button_at(e.position) != id:
				_release(id)


func _release_all() -> void:
	for id in _held.keys():
		_release(id)
	_stick_idx = -1
	_stick_vec = Vector2.ZERO
	_stick_apply()
	if _grab_idx >= 0:
		car.touch_release()
	_grab_idx = -1
	_twist_idx = -1
	_look.clear()


# ------------------------------------------------------------------ buttons

func _button_at(p: Vector2) -> String:
	for b in _buttons:
		# A little slack round each button: thumbs are imprecise.
		if p.distance_to(_button_pos(b)) < (b[5] + 10.0) * _u:
			return b[0]
	return ""


func _button_pos(b: Array) -> Vector2:
	return size * (b[3] as Vector2) + (b[4] as Vector2) * _u


func _find(id: String) -> Array:
	for b in _buttons:
		if b[0] == id:
			return b
	return []


func _press(id: String, index: int) -> void:
	_held[id] = index
	var action: String = _find(id)[1]
	if action != "":
		_act(action, true)
	match id:
		"menu":
			if open_menu.is_valid():
				open_menu.call()
		"full":
			Settings.toggle_fullscreen()


func _release(id: String) -> void:
	_held.erase(id)
	var action: String = _find(id)[1]
	if action != "":
		_act(action, false)


## Sent as events, not Input.action_press, so _unhandled_input handlers
## (camera, menu) see them as well as the polling code.
func _act(action: String, pressed: bool, strength := 1.0) -> void:
	var e := InputEventAction.new()
	e.action = action
	e.pressed = pressed
	e.strength = strength
	Input.parse_input_event(e)


# ------------------------------------------------------------------ stick

## Steering on x; in the air, y pitches like a controller's left stick
## (push up = nose down).
func _stick_apply() -> void:
	var v := _stick_vec
	_axis("steer_left", "steer_right", v.x)
	_axis("air_nose_down", "air_nose_up", v.y)


func _axis(neg: String, pos: String, x: float) -> void:
	x = signf(x) * clampf((absf(x) - 0.12) / 0.88, 0.0, 1.0)     # small dead zone
	if x < 0.0:
		_act(neg, true, -x)
		_act(pos, false)
	elif x > 0.0:
		_act(pos, true, x)
		_act(neg, false)
	else:
		_act(neg, false)
		_act(pos, false)


# ------------------------------------------------------------------ the car

## Car's centre on screen and a grab radius from its size there.
func _car_circle() -> Array:
	if car == null or cam == null:
		return []
	var c := car.get_global_transform_interpolated().origin
	if cam.is_position_behind(c):
		return []
	var p := cam.unproject_position(c)
	var edge := cam.unproject_position(c + cam.global_basis.x * 2.2)
	return [p, maxf(p.distance_to(edge), 46.0 * _u)]


func _on_car(p: Vector2) -> bool:
	var c := _car_circle()
	return not c.is_empty() and p.distance_to(c[0]) < c[1]


## The car tips the way the finger moves, as if pushing its roof: up turns
## the nose down (front flip), right rolls it right. Axes come from the
## camera, so it matches the screen whatever the car is doing.
func _grab_drag(p: Vector2) -> void:
	var d := p - _grab_pos
	_grab_pos = p
	_grab_travel += d.length()
	if not _grab_hopped and _grab_travel > 14.0 * _u:
		_grab_hopped = true
		if car.grounded_wheels > 0:
			car.touch_hop()
	var k := DRAG_RATE / (size.y * 0.25)
	var b := cam.global_basis
	_turn(-b.x * (-d.y * k) - b.z * (d.x * k))


## Second finger circling the first: spins the car flat (clockwise on
## screen turns the nose right).
func _twist_drag(p: Vector2) -> void:
	var a0 := (_twist_pos - _grab_pos).angle()
	var a1 := (p - _grab_pos).angle()
	_twist_pos = p
	_turn(-cam.global_basis.y * wrapf(a1 - a0, -PI, PI) * 1.3)


func _turn(rotvec: Vector3) -> void:
	car.touch_rotate(rotvec)
	var now := Time.get_ticks_msec() / 1000.0
	_samples.append([now, rotvec])
	while _samples.size() > 1 and now - _samples[0][0] > FLICK_WINDOW:
		_samples.pop_front()


## A finger that was still moving when it lifted leaves the car spinning.
func _let_go() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	var sum := Vector3.ZERO
	var t0 := now
	for s in _samples:
		if now - s[0] <= FLICK_WINDOW:
			sum += s[1]
			t0 = minf(t0, s[0])
	var spin := sum / maxf(now - t0, 1.0 / 60.0) if not sum.is_zero_approx() else Vector3.ZERO
	car.touch_release(spin if spin.length() > 3.0 else Vector3.ZERO)
	_grab_idx = -1
	_twist_idx = -1


# ------------------------------------------------------------------ drawing

func _draw() -> void:
	var font := get_theme_default_font()
	# Stick: where the thumb is, or a faint marker where it can go.
	var base := _stick_base if _stick_idx >= 0 else Vector2(110, size.y / _u - 96) * _u
	var a := 1.0 if _stick_idx >= 0 else 0.45
	draw_circle(base, STICK_R * _u, Color(C_FILL, C_FILL.a * a))
	draw_arc(base, STICK_R * _u, 0, TAU, 48, Color(C_EDGE, C_EDGE.a * a), 2.0 * _u)
	draw_circle(base + _stick_vec * STICK_R * _u, 24 * _u, Color(1, 1, 1, 0.35 * a))
	if _stick_idx < 0:
		_label(font, base + Vector2(0, (STICK_R + 14) * _u), "STEER", 11, Color(C_TEXT, 0.5))

	for b in _buttons:
		var p := _button_pos(b)
		var r: float = b[5] * _u
		var held := _held.has(b[0])
		var col: Color = b[6]
		draw_circle(p, r, Color(col, 0.55) if held else C_FILL)
		draw_arc(p, r, 0, TAU, 40, Color(col, 0.9) if held else Color(col, 0.5), 2.0 * _u)
		_label(font, p + Vector2(0, 5 * _u), b[2], 15 if r > 22 * _u else 14, C_TEXT)
		match b[0]:
			"reset":                    # recover: a circular arrow
				var k := 9.0 * _u
				draw_arc(p, k, -PI * 0.35, PI * 1.35, 24, C_TEXT, 2.0 * _u)
				var tip := p + Vector2.from_angle(-PI * 0.35) * k
				draw_colored_polygon(PackedVector2Array([tip + Vector2(-5, -5) * _u, tip + Vector2(5, -2) * _u, tip + Vector2(-2, 5) * _u]), C_TEXT)
			"full":                     # fullscreen: four corner brackets
				var k := 8.0 * _u
				var l := 4.0 * _u
				for sx in [-1.0, 1.0]:
					for sy in [-1.0, 1.0]:
						var c := p + Vector2(sx, sy) * k
						draw_line(c, c - Vector2(sx * l, 0), C_TEXT, 2.0 * _u)
						draw_line(c, c - Vector2(0, sy * l), C_TEXT, 2.0 * _u)

	# The car: a ring while held, and a hint until it's been grabbed once.
	var c := _car_circle()
	if not c.is_empty():
		if _grab_idx >= 0:
			draw_arc(c[0], c[1], 0, TAU, 48, Color(C_GRAB, 0.7), 2.5 * _u)
			draw_line(c[0], _grab_pos, Color(C_GRAB, 0.5), 2.0 * _u)
		elif _hint > 0.0:
			var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 300.0)
			draw_arc(c[0], c[1], 0, TAU, 48, Color(C_GRAB, (0.25 + 0.25 * pulse) * _hint), 2.0 * _u)
			_label(font, c[0] + Vector2(0, -c[1] - 8 * _u), "drag the car to flip it", 13, Color(C_GRAB, _hint))


func _label(font: Font, at: Vector2, s: String, px: int, col: Color) -> void:
	var fs := int(px * _u)
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(font, at - Vector2(w * 0.5, 0), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
