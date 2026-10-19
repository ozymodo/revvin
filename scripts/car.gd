extends RigidBody3D
## Mag Revvin.
##
## Raycast-suspension EV with three motors (one front, two rear with torque
## vectoring), under-floor suction fans, four rear compressed-air thrusters
## fed by a 200 L tank, and, on the Rocket trim, six gimballed perimeter
## jets fed by a 400 L tank. The jets are driven by a small flight
## controller ("fine control") that keeps the car level in the air.
##
## All forces are applied in _integrate_forces. Input and visuals are handled
## in _physics_process, which runs just before each physics step.

signal trim_changed(trim: int)
## Air from a pickup or a landed trick has started flowing into the tanks.
signal air_added(thrust: float, rocket: float, color: Color)
## Charge from a battery pickup has started flowing into the pack.
signal charge_added(amount: float, color: Color)

enum Trim { THRUST, ROCKET }
## How much the flight computer helps with the jets.
##   AUTO   self-levels, holds hover, cushions landings (as before)
##   HYBRID only damps rotation: the car holds whatever attitude you leave it in
##   FULL   nothing automatic: arrows are raw torque, lift is raw thrust
enum JetMode { AUTO, HYBRID, FULL }
const JET_MODE_NAMES := ["AUTO", "HYBRID", "FULL"]

## Interchangeable bodies. Same layout and physics; different look and effects.
const BODIES := [
	{"name": "NEON", "scene": preload("res://assets/car.glb"), "trail": false, "tire_trail": 1, "motor_glow": Color(0.55, 0.45, 1.0), "accent": Color(0.55, 0.45, 1.0)},
	{"name": "SYMBIOTE", "scene": preload("res://assets/car_bio.glb"), "trail": true, "tire_trail": 0, "motor_glow": Color(0.2, 1.0, 0.4), "accent": Color(0.3, 0.95, 0.45)},
	{"name": "PHANTOM", "scene": preload("res://assets/car_roadster.glb"), "trail": false, "tire_trail": 2, "motor_glow": Color(0.17, 1.0, 0.48), "accent": Color(0.17, 1.0, 0.48)},
]

# Numbers follow Tesla's Oct 2026 reveal where published (0-100 km/h in
# ~0.81 s with thrusters, ~250 mph top speed, ~600 L of cold gas over ten
# nozzles) and are estimates elsewhere (mass, motor split, fan downforce).

# Chassis
const COM := Vector3(0, 0.18, 0)
const WHEEL_RADIUS := 0.34
const MOUNT_HEIGHT := 0.5           # suspension ray origin, body space
const SUSP_TRAVEL := 0.42
const SPRING_K := 45000.0
const DAMP_BUMP := 5000.0
const DAMP_REBOUND := 6500.0
const ANTI_ROLL := 18000.0
const BUMP_START := 0.2
const BUMP_K := 6.0e6
const DRAG := 0.36                  # 0.5 * rho * Cd * A
const ROLLING := 12.0

# Tyres. Lateral force follows a simplified Pacejka curve of slip angle:
# grip rises steeply, peaks near TYRE_PEAK and falls to ~80% once the
# tyre is sliding, which is what makes slides catchable and drifts hold.
const GRIP_FRONT := 1.60
const GRIP_REAR := 1.70
const TYRE_B := 12.0
const TYRE_C := 1.25                # low = grip plateaus instead of falling away
const TYRE_PEAK := 0.22             # rad, roughly where grip peaks (effects start)
const LAT_RESPONSE := 0.5           # low-speed model: share of slip cancelled per step
const LOCKED_LAT_GRIP := 0.45       # lateral grip of a locked (handbraked) wheel
const SPIN_LAT_GRIP := 0.55         # lateral grip of a spinning wheel
const KINETIC_GRIP := 0.85          # longitudinal grip while locked or spinning
const BRAKE_BIAS_FRONT := 0.6
const COAST_REGEN_G := 0.12         # lift-off regen decel, EV style
const PAD_ACCEL := 16.0             # m/s² from a boost pad
const WHEELBASE := 3.07

# Driver assists (toggle in game)
const ESC_GAIN := 3.0
const COUNTER_STEER := 0.75         # drift assist: share of body slip fed into steering
const DRIFT_REAR_GRIP := 0.55       # drift assist: rear lateral grip at full throttle mid-drift
const HANDBRAKE_DECEL := 0.5        # share of grip the locked rears use to slow the car

# Motors (force at the contact patch), ~1 MW combined
const FRONT_MOTOR_FORCE := 11000.0
const FRONT_MOTOR_POWER := 320000.0
const REAR_MOTOR_FORCE := 9500.0
const REAR_MOTOR_POWER := 360000.0
const MOTOR_TOP_SPEED := 112.0      # ~250 mph
const TORQUE_VECTORING := 0.35
const REVERSE_SCALE := 1.0          # reverse mirrors forward (same motor force and top speed)
const BRAKE_FORCE := 12000.0       # per wheel at full pedal, before bias
const MAX_STEER := 0.6
const STEER_SPEED_FALLOFF := 0.045

# Suction fans: enough to hold the car on a vertical wall when stopped.
const FAN_DOWNFORCE := 15000.0
const FAN_SPOOL := 1.0

# Compressed air
const THRUSTER_FORCE := 10000.0     # each, four of them
const THRUST_TANK_SECONDS := 6.0    # 200 L at full boost
const JET_FORCE := 9000.0           # each, six of them (thrust/weight ~2.9)
const ROCKET_TANK_SECONDS := 8.0    # 400 L with all six jets at full force
const TANK_BAR := 440.0             # reported COPV working pressure
const THRUST_TANK_L := 200.0
const ROCKET_TANK_L := 400.0

# Onboard electric compressor: draws outside air and repressurises the
# tanks from the main battery, faster when regenerative braking has spare
# power. Reports put a real refill at hours; it is sped up here to stay
# playable (~35 s for the 200 L tank, ~70 s for the 400 L).
const COMPRESSOR_LPS := 5.8         # litres of tank volume refilled per second
const COMPRESSOR_KW := 40.0
const REGEN_BOOST := 2.5            # compressor speed-up while regen braking
const REGEN_EFFICIENCY := 0.65
const BATTERY_KWH := 200.0
const MOTOR_EFFICIENCY := 0.92
# Gameplay drain on top of the motors' real draw (which alone would last a
# very long session): driving and stunts slowly flatten the pack, and the
# battery pickups in the world top it back up. Flat out with stunts this is
# roughly 0.35 %/s, so a full pack lasts about five minutes of hard play.
const DRAIN_MOVING := 0.0015        # share of the pack per second at 30+ m/s
const DRAIN_STUNT := 0.0025         # per second with the jets/thrusters at full
const DRAIN_AIR := 0.001            # per second airborne
const LIMP_BELOW := 0.03            # under this charge the motors limp along
const LIMP_POWER := 0.3
const THRUSTER_GIMBAL := deg_to_rad(12.0)
const JET_YAW_ASSIST := 16000.0

# Flight controller ("fine control")
const CLIMB_RATE := 12.0            # m/s with lift fully held
const VY_GAIN := 6.0
const LEVEL_KP := 30.0
const LEVEL_KD := 11.0
const FLIP_RATE_PITCH := 5.0        # rad/s, about one flip in 1.3 s
const FLIP_RATE_ROLL := 7.0
const RATE_GAIN := 14.0
const MANUAL_ACCEL := Vector3(12.0, 6.0, 26.0)   # FULL mode: rad/s^2 per full stick (pitch, yaw, roll)
const SIDE_PUSH := 0.5              # ground: share of total jet force for a side push
const PRESS_DOWN := 0.6             # ground: share of jet force pressing the car into the road
const HOP := 0.85                   # ground: share of jet force for a hop

# Jump (tap E), Rocket League style: the six jets fire one short burst with
# the valves wide open (~2.4x their rated force for 0.12 s), straight up the
# car's own axis, so it pops off the road, a wall or a loop. A second tap
# in the air does a double jump, or a dodge flip with the arrows held.
const JUMP_DV := 7.0                # m/s from a jump
const DOUBLE_DV := 5.0              # m/s from the double jump
const BURST_TIME := 0.12            # s the valves stay open
const DODGE_DV := 6.0               # m/s shove in the dodge direction
const DODGE_SPIN := 9.5             # rad/s: one flip in ~0.65 s
const DODGE_TIME := 0.6             # flight computer stands back this long
const DOUBLE_WINDOW := 1.6          # s after a jump the second tap counts
const HOLD_TO_FLY := 0.22           # s of holding E before it becomes sustained lift
const LIP_HOLD := 1.0               # share of ramp-lip pitch/roll spin removed at takeoff

const MASS := {Trim.THRUST: 1800.0, Trim.ROCKET: 1900.0}
const INERTIA_PER_KG := Vector3(1.95, 2.15, 0.43)

const WHEEL_KEYS := ["FL", "FR", "RL", "RR"]
const JET_KEYS := ["FL", "FR", "ML", "MR", "RL", "RR"]


class Wheel:
	var node: Node3D
	var mount: Vector3
	var front: bool
	var left: bool
	var grounded := false
	var compression := 0.0
	var was_grounded := false
	var comp_vel := 0.0
	var contact := Vector3.ZERO
	var normal := Vector3.UP
	var normal_load := 0.0
	var slip := 0.0                 # 0..1, how hard the tyre is sliding (effects)
	var slip_speed := 0.0           # m/s of sliding at the contact patch
	var locked := false
	var spinning := false
	var spin_speed := 0.0
	var spin := 0.0


class Nozzle:
	var node: Node3D
	var pos: Vector3                # body space, from origin
	var rest_dir: Vector3           # exhaust direction when idle
	var exhaust := Vector3.DOWN     # current exhaust direction (visual)
	var intensity := 0.0
	var fx: GPUParticles3D
	var rest_basis: Basis


var trim := Trim.ROCKET
var thrust_tank := 1.0
var rocket_tank := 1.0
var fans_on := true
var xray := false

# Read by HUD / audio / camera
var speed := 0.0                    # forward, m/s
var fan_spin := 1.0                 # fans are already running at spawn
var thrust_valve := 0.0
var jet_output := 0.0               # 0..1 share of total jet force
var motor_load := [0.0, 0.0, 0.0]   # front, rear left, rear right
var grounded_wheels := 0
var altitude := 0.0
var flight_mode := false
var battery := 1.0                  # state of charge 0..1
var compressor_lps := 0.0           # current refill rate (0 when idle)
var compressor_target := ""         # "thrust" or "rocket"
var regen := false                  # regen braking is boosting the compressor
var upside_down_time := 0.0
var tyre_slip := 0.0
var tyre_squeal := 0.0              # 0..1 for audio

# Assists
var tc_on := true
var abs_on := true
var esc_on := false
var drift_assist := true
var jet_mode := JetMode.FULL         # FULL by default: the player flies the jets directly

# Drift and handling telemetry
var slip_angle := 0.0               # body slip angle, rad (+ = sliding right)
var launch_ready := false
var burnout := false
var drift_points := 0.0
var drift_combo := 1
var drift_total := 0.0
var drift_best := 0.0
var drift_last := 0.0               # last banked drift, for the HUD pop-up
var drift_last_time := -10.0
var _drift_time := 0.0
var in_drift := false               # sustained-slide state used by drift assist
var _drift_idle := 0.0
var _prev_speed := 0.0
var _clock := 0.0
var _rumble_t := 0.0
var _air_vy := 0.0

var skids: Node                     # skid_marks.gd, set by main
var goo: Node                       # goo_trail.gd, set by main
var body_index := 0
var _shape: CollisionShape3D
var _pilot: Node3D
var _pilot_eye: Node3D
var _tendrils: Array[Node3D] = []
var _bio_mats: Array[StandardMaterial3D] = []
var _bio_t := 0.0
var _trail_fx: Array[GPUParticles3D] = []
var _trail_sparks: Array[GPUParticles3D] = []    # per rear wheel: the Neon's sparks, the Phantom's ghost motes
var _goo_light: OmniLight3D
var _smoke: Array[GPUParticles3D] = []

var model: Node3D
var wheels: Array[Wheel] = []
var jets: Array[Nozzle] = []
var thrusters: Array[Nozzle] = []
var _fans: Array[Node3D] = []
var _motor_mats: Array[StandardMaterial3D] = []
var _shell_mat: StandardMaterial3D
var _shell_xray_mat: StandardMaterial3D
var _trim_nodes := {}

# Controls (set in _physics_process, used in _integrate_forces)
var _throttle := 0.0
var _throttle_in := 0.0
var _brake_in := 0.0
var _brake := 0.0
var _drive := 0.0
var _steer := 0.0
var _steer_angle := 0.0
var _lift := 0.0
var _lift_held := 0.0               # s the lift button has been held
var _burst_t := 0.0                 # jump burst time left
var _burst_dv := 0.0
var _jumps := 0                     # 0 on the ground, 1 after a jump, 2 after the second
var _since_jump := 99.0
var _dodge_t := 0.0
var _pending_dodge := Vector3.ZERO  # x = flip forward/back, z = roll right/left (stick at the tap)
var jump_flash := 0.0               # for HUD / audio
var _spin := Vector2.ZERO           # air stick: x = pitch nose-down (front flip), y = roll right
var _dodge_dir := Vector2.ZERO      # direction a dodge would go right now (x = forward, y = right)
var _kb_pitch_armed := false        # W/S pitch in the air only after a fresh press (see below)
## Experimental: tanks and battery never run down.
var infinite_air := false
var _jet_assist := false
var _handbrake := false
var _ground_time := 0.0

var _jet_forces: Array[Vector3] = []
var _thrust_dir := Vector3.FORWARD
var _jet_r: Array[Vector3] = []
var _jet_alloc_inv := Basis()
var _jet_z_mean := 0.0
var _jet_z_var := 1.0
var _inertia := Vector3.ONE
var _pending_reset: Variant = null
var resets := 0                     # counts applied resets/respawns (trick scoring ignores the stop)
var _spawn := Transform3D.IDENTITY
var pad_time := 0.0                 # s of boost-pad turbo left
# Air from pickups and tricks flows in over a moment rather than appearing.
var air_inflow := 0.0               # 0..1, for the refill effects and HUD
var inflow_color := Color.WHITE
var _air_due := Vector2.ZERO        # tank fractions still to arrive (thrust, rocket)
var charge_inflow := 0.0            # 0..1 while a battery pickup flows into the pack
var _charge_due := 0.0
## Set by main when the stunt course is loaded: respawn goes to its last checkpoint.
var respawn_hook := Callable()
## Set by world/grinds.gd: while it returns true it drives the car (a grind).
var grind_hook := Callable()
var grinding := false


func _ready() -> void:
	_spawn = global_transform
	add_to_group("player_car")
	can_sleep = false
	continuous_cd = true               # thin track surfaces at 400 km/h
	center_of_mass_mode = CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = COM
	var pm := PhysicsMaterial.new()
	pm.friction = 0.1                  # body scraping shouldn't act as a brake
	pm.bounce = 0.05
	physics_material_override = pm
	angular_damp = 0.4

	_shape = CollisionShape3D.new()
	add_child(_shape)
	for i in 4:
		var p := _make_smoke()
		add_child(p)
		_smoke.append(p)
	for i in 2:
		_trail_fx.append(_make_dirt())
		_trail_fx.append(_make_goo_drops())
	for p in _trail_fx:
		add_child(p)
	for i in 2:
		var sp := GPUParticles3D.new()
		sp.top_level = true
		sp.local_coords = false
		sp.emitting = false
		sp.visibility_aabb = AABB(Vector3(-8, -3, -8), Vector3(16, 8, 16))
		add_child(sp)
		_trail_sparks.append(sp)
	_goo_light = OmniLight3D.new()
	_goo_light.light_color = Color(0.2, 1.0, 0.35)
	_goo_light.light_energy = 1.6
	_goo_light.omni_range = 3.5
	_goo_light.position = Vector3(0, 0.05, 0.6)
	add_child(_goo_light)
	load_body(body_index)


## Swaps the car's body (model, nozzles, glow materials). Physics state and
## trim carry over.
func load_body(index: int) -> void:
	body_index = index
	var xray_was := xray
	if model:
		model.queue_free()
	wheels.clear()
	jets.clear()
	thrusters.clear()
	_jet_forces.clear()
	_motor_mats.clear()
	_trim_nodes.clear()
	_tendrils.clear()
	_bio_mats.clear()
	var body: Dictionary = BODIES[index]
	model = (body.scene as PackedScene).instantiate()
	add_child(model)
	_find("Collider").visible = false
	_shape.shape = (_find("Collider") as MeshInstance3D).mesh.create_convex_shape(true, true)

	for key in WHEEL_KEYS:
		var w := Wheel.new()
		w.node = _find("Wheel_" + key)
		w.mount = Vector3(w.node.position.x, MOUNT_HEIGHT, w.node.position.z)
		w.front = key[0] == "F"
		w.left = key[1] == "L"
		wheels.append(w)

	for key in JET_KEYS:
		jets.append(_make_nozzle(_find("Jet_" + key), Vector3.DOWN, 1.0))
		_jet_forces.append(Vector3.ZERO)
	for i in 4:
		thrusters.append(_make_nozzle(_find("Thruster_%d" % i), Vector3.BACK, 1.2))

	_fans = [_find("Fan_L"), _find("Fan_R")]
	for node_name in ["Motor_F", "Motor_RL", "Motor_RR"]:
		var mi := _find(node_name) as MeshInstance3D
		var mat := (mi.get_active_material(0) as StandardMaterial3D).duplicate() as StandardMaterial3D
		mat.emission_enabled = true
		mat.emission = body.motor_glow
		mat.emission_energy_multiplier = 0.0
		mi.material_override = mat
		_motor_mats.append(mat)

	var shell := _find("Shell") as MeshInstance3D
	_shell_mat = shell.get_active_material(0)
	_shell_xray_mat = _shell_mat.duplicate()
	_shell_xray_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_shell_xray_mat.albedo_color.a = 0.14
	_shell_xray_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	# The Symbiote's pilot and its glowing nerve tissue, if this body has them.
	_pilot = model.find_child("Pilot", true, false) as Node3D
	_pilot_eye = model.find_child("Pilot_Eye", true, false) as Node3D
	for n in model.find_children("Tendril_*", "Node3D", true, false):
		_tendrils.append(n)
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		for si in mi.mesh.get_surface_count():
			var m: Material = mi.mesh.surface_get_material(si)
			if m and m.resource_name == "BioGlow":
				var dup := (m as StandardMaterial3D).duplicate() as StandardMaterial3D
				mi.set_surface_override_material(si, dup)
				_bio_mats.append(dup)
	_goo_light.visible = true
	_goo_light.light_color = body.accent
	for sp in _trail_sparks:
		_style_sparks(sp, body.tire_trail, body.accent)
	# Tyre smoke: grey for the Neon, a green spore haze for the Symbiote.
	for p in _smoke:
		var ramp := ((p.process_material as ParticleProcessMaterial).color_ramp as GradientTexture1D).gradient
		var c := Color(0.55, 0.85, 0.5) if body.trail else Color(0.85, 0.85, 0.88)
		ramp.set_color(0, Color(c, 0.32))
		ramp.set_color(1, Color(c.lightened(0.1), 0.0))
	set_xray(xray_was)

	for node_name in ["Tank_Rocket", "Seat_Passenger"] + JET_KEYS.map(func(k): return "Jet_" + k):
		_trim_nodes[node_name] = _find(node_name)
	apply_trim(trim)


func _find(node_name: String) -> Node3D:
	var n := model.find_child(node_name, true, false) as Node3D
	assert(n != null, "Car model is missing node " + node_name)
	return n


# ------------------------------------------------------------------ trims

func apply_trim(t: int) -> void:
	trim = t as Trim
	var rocket := trim == Trim.ROCKET
	mass = MASS[trim]
	_inertia = INERTIA_PER_KG * mass
	inertia = _inertia
	_trim_nodes["Tank_Rocket"].visible = rocket
	_trim_nodes["Seat_Passenger"].visible = not rocket
	for k in JET_KEYS:
		_trim_nodes["Jet_" + k].visible = rocket
	flight_mode = false

	# Precompute the jet allocation. Each jet's vertical force f_i must add up
	# to the collective C and the pitch/roll torques: sum(f) = C,
	# sum(-z*f) = tau_x, sum(x*f) = tau_z. The minimum-norm solution is
	# f = A^T (A A^T)^-1 b with rows a_i = (1, -z_i, x_i).
	_jet_r.clear()
	var m := [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
	_jet_z_mean = 0.0
	for j in jets:
		var r := j.pos - COM
		_jet_r.append(r)
		var a := Vector3(1.0, -r.z, r.x)
		m[0] += a * a.x
		m[1] += a * a.y
		m[2] += a * a.z
		_jet_z_mean += r.z / jets.size()
	_jet_alloc_inv = Basis(m[0], m[1], m[2]).inverse()
	_jet_z_var = 0.0
	for r in _jet_r:
		_jet_z_var += (r.z - _jet_z_mean) ** 2
	trim_changed.emit(trim)


func set_xray(on: bool) -> void:
	xray = on
	(_find("Shell") as MeshInstance3D).material_override = _shell_xray_mat if on else null


func jets_available() -> bool:
	return trim == Trim.ROCKET and rocket_tank > 0.0


func thrust_pressure_bar() -> float:
	return thrust_tank * TANK_BAR


func rocket_pressure_bar() -> float:
	return rocket_tank * TANK_BAR


func request_reset(to_spawn := false) -> void:
	var t := _spawn
	if not to_spawn:
		var f := -global_basis.z
		f.y = 0.0
		if f.length() < 0.1:
			f = global_basis.y
			f.y = 0.0
		t = Transform3D(Basis.looking_at(f.normalized(), Vector3.UP), global_position + Vector3.UP * 1.2)
	_pending_reset = t


func request_reset_to(t: Transform3D) -> void:
	_pending_reset = t


## Tops the tanks up from a pickup or a landed trick (fractions of a full
## tank). It flows in over about half a second. On the Thrust trim, with no
## rocket tank, half of the rocket share goes to the thrust tank instead.
func add_air(thrust: float, rocket: float, color := Color.WHITE) -> void:
	if trim != Trim.ROCKET:
		thrust += rocket * 0.5
		rocket = 0.0
	_air_due += Vector2(thrust, rocket)
	inflow_color = color
	air_added.emit(thrust, rocket, color)


func _flow_air(delta: float) -> void:
	var due := _air_due.x + _air_due.y
	if due <= 0.0:
		air_inflow = move_toward(air_inflow, 0.0, delta * 3.0)
		return
	var k := minf(1.0, delta * 5.0)
	var dt := maxf(_air_due.x * k, minf(_air_due.x, 0.25 * delta))
	var dr := maxf(_air_due.y * k, minf(_air_due.y, 0.25 * delta))
	_air_due -= Vector2(dt, dr)
	if _air_due.length() < 0.002:
		_air_due = Vector2.ZERO
	thrust_tank = minf(1.0, thrust_tank + dt)
	rocket_tank = minf(1.0, rocket_tank + dr)
	air_inflow = move_toward(air_inflow, clampf(0.4 + due * 4.0, 0.0, 1.0), delta * 8.0)


## Tops the battery up from a pickup; it flows in like air does.
func add_charge(amount: float, color := Color.WHITE) -> void:
	_charge_due += amount
	charge_added.emit(amount, color)


func _flow_charge(delta: float) -> void:
	if _charge_due <= 0.0:
		charge_inflow = move_toward(charge_inflow, 0.0, delta * 2.5)
		return
	var d := maxf(_charge_due * minf(1.0, delta * 3.5), minf(_charge_due, 0.2 * delta))
	_charge_due -= d
	if _charge_due < 0.002:
		_charge_due = 0.0
	battery = minf(1.0, battery + d)
	charge_inflow = move_toward(charge_inflow, 1.0, delta * 8.0)


## Driving and stunts slowly flatten the pack (see DRAIN_*).
func _gameplay_drain(delta: float) -> void:
	var moving := clampf(absf(speed) / 30.0, 0.0, 1.5)
	var stunt := jet_output + thrust_valve * 0.5
	var air := 1.0 if grounded_wheels == 0 else 0.0
	battery = maxf(0.0, battery - delta * (DRAIN_MOVING * moving + DRAIN_STUNT * stunt + DRAIN_AIR * air))


## Motor power left: full until the pack is nearly flat, then limp mode.
func power_scale() -> float:
	return lerpf(LIMP_POWER, 1.0, clampf(battery / LIMP_BELOW, 0.0, 1.0))


## Average normal under the wheels that are touching, else the car's up.
func ground_normal() -> Vector3:
	var n := Vector3.ZERO
	for w in wheels:
		if w.grounded:
			n += w.normal
	return n.normalized() if n.length() > 0.1 else global_basis.y


## Boost pads and hoops: a shove along the car's nose, TrackMania style.
func pad_boost(seconds: float) -> void:
	pad_time = maxf(pad_time, seconds)


# ------------------------------------------------------------------ input + visuals

func _physics_process(delta: float) -> void:
	_clock += delta
	# Pedals ramp in (a keyboard tap becomes a squeeze); analog triggers
	# pass through nearly unchanged.
	var t_raw := Input.get_action_strength("throttle")
	var b_raw := Input.get_action_strength("brake")
	_throttle_in = move_toward(_throttle_in, t_raw, delta * (6.0 if t_raw > _throttle_in else 12.0))
	_brake_in = move_toward(_brake_in, b_raw, delta * (8.0 if b_raw > _brake_in else 14.0))
	var t_in := _throttle_in
	var b_in := _brake_in
	var s_in := Input.get_axis("steer_left", "steer_right")
	var analog := absf(s_in) > 0.0 and absf(s_in) < 0.999
	if analog:
		s_in = signf(s_in) * pow(absf(s_in), 1.4)     # finer control near centre
	_throttle = t_in
	_brake = 0.0
	_handbrake = Input.is_action_pressed("handbrake")
	_jet_assist = Input.is_action_pressed("jet_assist")
	_lift = Input.get_action_strength("lift")
	_lift_held = _lift_held + delta if _lift > 0.1 else 0.0
	_read_air_controls(s_in)
	if grounded_wheels == 0 and _handbrake:
		s_in = 0.0                      # air roll held: left/right rolls instead of yawing

	# On a rail (bluntslides go sideways) the readout is the grind speed.
	speed = linear_velocity.length() if grinding else linear_velocity.dot(-global_basis.z)
	# Both pedals at a standstill: launch control (TC on) or a burnout (TC off).
	launch_ready = absf(speed) < 1.0 and t_raw > 0.5 and b_raw > 0.5 and grounded_wheels >= 3
	burnout = launch_ready and not tc_on
	if launch_ready:
		_drive = 0.0
		_brake = 1.0
	elif speed > 1.0:
		_drive = t_in
		_brake = b_in
	elif speed < -1.0:
		_drive = -b_in * REVERSE_SCALE
		_brake = t_in
	else:
		_drive = t_in - b_in * REVERSE_SCALE

	# Body slip angle: how far the car is pointing away from where it's going.
	var vl := global_basis.transposed() * linear_velocity
	slip_angle = atan2(vl.x, absf(vl.z)) if Vector2(vl.x, vl.z).length() > 4.0 else 0.0

	# Steering. Keyboard: slower turn-in at speed, quick return to centre.
	# Analog: follows the stick closely. Lock reduces with speed, but opens
	# back up while sliding so there's room to counter-steer.
	var spd := absf(speed)
	var rate := 15.0 if analog else lerpf(6.5, 2.8, clampf(spd / 60.0, 0.0, 1.0))
	if absf(s_in) < absf(_steer) or signf(s_in) != signf(_steer):
		rate = maxf(rate, 9.0)
	_steer = move_toward(_steer, s_in, rate * delta)
	var lock := MAX_STEER / (1.0 + spd * STEER_SPEED_FALLOFF)
	lock = lerpf(lock, MAX_STEER, clampf(absf(slip_angle) / 0.35, 0.0, 1.0))
	_steer_angle = _steer * lock
	if drift_assist and grounded_wheels >= 3 and absf(slip_angle) > 0.05:
		_steer_angle += slip_angle * COUNTER_STEER    # point the front wheels where the car is going
	_steer_angle = clampf(_steer_angle, -MAX_STEER, MAX_STEER)

	if Input.is_action_just_pressed("assist_tc"):
		tc_on = not tc_on
	if Input.is_action_just_pressed("assist_abs"):
		abs_on = not abs_on
	if Input.is_action_just_pressed("assist_esc"):
		esc_on = not esc_on
	if Input.is_action_just_pressed("assist_drift"):
		drift_assist = not drift_assist
	if Input.is_action_just_pressed("jet_mode"):
		jet_mode = ((jet_mode + 1) % 3) as JetMode
	_update_drift(delta)
	_update_rumble(delta)

	var boost := Input.is_action_pressed("boost") and thrust_tank > 0.0
	thrust_valve = move_toward(thrust_valve, 1.0 if boost else 0.0, delta / 0.08)

	if Input.is_action_just_pressed("fans"):
		fans_on = not fans_on
	if Input.is_action_just_pressed("xray"):
		set_xray(not xray)
	if Input.is_action_just_pressed("reset"):
		request_reset()
	if Input.is_action_just_pressed("respawn"):
		if respawn_hook.is_valid():
			respawn_hook.call()
		else:
			request_reset(true)

	_update_jump(delta)

	# Flight mode: entered by holding lift (a tap is just a jump), left once
	# the car has settled.
	if not jets_available():
		flight_mode = false
	elif _lift_held > HOLD_TO_FLY:
		flight_mode = true
	_ground_time = _ground_time + delta if grounded_wheels >= 3 else 0.0
	if flight_mode and _lift < 0.1 and _ground_time > 0.25:
		flight_mode = false

	var jumping := _jumps > 0 and grounded_wheels < 3
	var fan_target := 1.0 if fans_on and not flight_mode and not jumping else 0.0
	# Fans cut almost instantly on lift-off so they don't fight the jets.
	fan_spin = move_toward(fan_spin, fan_target, delta / (0.12 if flight_mode or jumping else FAN_SPOOL))

	_run_compressor(delta)
	_gameplay_drain(delta)
	_flow_air(delta)
	_flow_charge(delta)
	if Input.is_action_just_pressed("infinite_air"):
		infinite_air = not infinite_air
	if infinite_air:
		thrust_tank = 1.0
		rocket_tank = 1.0
		battery = 1.0

	# Trim change (a garage job on the real car) whenever the car is stopped.
	if Input.is_action_just_pressed("swap_trim") and can_swap_trim():
		apply_trim(Trim.THRUST if trim == Trim.ROCKET else Trim.ROCKET)
	if Input.is_action_just_pressed("swap_car") and can_swap_trim():
		load_body((body_index + 1) % BODIES.size())

	upside_down_time = upside_down_time + delta if global_basis.y.y < 0.3 and linear_velocity.length() < 3.0 else 0.0

	_update_visuals(delta)


## Rocket League style air controls.
##   pitch  left stick up/down, or W/S (W = nose down), or Up/Down arrows
##   yaw    left stick left/right, A/D
##   roll   LB/RB or Q/E; or hold powerslide (X / Shift) and steer
## W/S also drive, so on the keyboard they only pitch once pressed afresh in
## the air: holding W off a ramp won't nose the car into the ground.
## On the road the roll buttons fire the side jets instead (catch a slide).
func _read_air_controls(steer_in: float) -> void:
	var airborne := grounded_wheels == 0
	var kb_pitch := Input.get_axis("kb_nose_up", "kb_nose_down")
	if not airborne:
		_kb_pitch_armed = false
	elif kb_pitch == 0.0:
		_kb_pitch_armed = true
	var stick_pitch := Input.get_axis("air_nose_up", "air_nose_down")
	var pitch := Input.get_axis("flip_back", "flip_forward")
	var roll := Input.get_axis("roll_left", "roll_right") + Input.get_axis("air_roll_left", "air_roll_right")
	if airborne and _handbrake:
		roll += steer_in
	# The stick pitches and flips the car in the air whether or not jump is
	# held (flying), so you can flip mid-flight. Flying forward and back is
	# on the pedals (RT/LT, W/S), which is why W/S don't also pitch in flight.
	if airborne or flight_mode:
		pitch += stick_pitch
		if not flight_mode and _kb_pitch_armed:
			pitch += kb_pitch
	_spin = Vector2(clampf(pitch, -1.0, 1.0), clampf(roll, -1.0, 1.0))
	# Dodge direction reads the raw stick/keys, so holding W and double
	# tapping jump front-flips even if W was held from the ground.
	var side := _spin.y if absf(_spin.y) > 0.1 else steer_in
	_dodge_dir = Vector2(clampf(_spin.x + (kb_pitch if not _kb_pitch_armed else 0.0), -1.0, 1.0), side)


## Tap jump. In the air within DOUBLE_WINDOW: double jump, or a dodge
## flip toward the arrows if they're held.
func _update_jump(delta: float) -> void:
	_since_jump += delta
	_dodge_t = maxf(0.0, _dodge_t - delta)
	jump_flash = maxf(0.0, jump_flash - delta * 3.0)
	if _jumps > 0 and _since_jump > 0.25 and grounded_wheels >= 3:
		_jumps = 0
	if not Input.is_action_just_pressed("lift") or not jets_available() or rocket_tank < 0.02:
		return
	if grounded_wheels >= 2 and _jumps == 0:
		_burst_dv = JUMP_DV
		_burst_t = BURST_TIME
		_jumps = 1
		_since_jump = 0.0
		fan_spin = 0.0                  # fans let go at once or they'd hold it down
		jump_flash = 1.0
	elif grounded_wheels == 0 and _jumps == 1 and _since_jump < DOUBLE_WINDOW:
		_jumps = 2
		jump_flash = 1.0
		if _dodge_dir.length() > 0.3:
			_pending_dodge = Vector3(_dodge_dir.x, 0.0, _dodge_dir.y)
			_dodge_t = DODGE_TIME
		else:
			_burst_dv = DOUBLE_DV
			_burst_t = BURST_TIME
	elif grounded_wheels == 0 and _jumps == 0:
		# Already airborne off a ramp: one jump left.
		_jumps = 1
		_since_jump = 0.0
		_burst_dv = DOUBLE_DV
		_burst_t = BURST_TIME
		jump_flash = 1.0


func can_swap_trim() -> bool:
	return absf(speed) < 1.0 and grounded_wheels >= 3


## Fills whichever tank is emptier (by fraction), skipping a tank that is
## venting at that moment. Energy comes out of the battery.
func _run_compressor(delta: float) -> void:
	compressor_lps = 0.0
	compressor_target = ""
	regen = grounded_wheels > 0 and absf(speed) > 3.0 and (_brake > 0.05 or _handbrake)
	if battery <= 0.02:
		return
	var thrust_need := 1.0 - thrust_tank if thrust_valve < 0.05 else 0.0
	var rocket_need := 1.0 - rocket_tank if trim == Trim.ROCKET and jet_output < 0.02 else 0.0
	if thrust_need <= 0.0 and rocket_need <= 0.0:
		return
	compressor_lps = COMPRESSOR_LPS * (REGEN_BOOST if regen else 1.0)
	if thrust_need >= rocket_need:
		compressor_target = "thrust"
		thrust_tank = minf(1.0, thrust_tank + compressor_lps * delta / THRUST_TANK_L)
	else:
		compressor_target = "rocket"
		rocket_tank = minf(1.0, rocket_tank + compressor_lps * delta / ROCKET_TANK_L)
	# Regen pays for the compressor while braking; otherwise the pack does.
	if not regen:
		_drain_battery(COMPRESSOR_KW * 1000.0, delta)


func _drain_battery(watts: float, dt: float) -> void:
	battery = clampf(battery - watts * dt / (BATTERY_KWH * 3.6e6), 0.0, 1.0)


## Drift scoring: points for angle x speed while sliding, with a combo
## that grows the longer the drift is held. Banked after a short pause,
## lost on a crash.
func _update_drift(delta: float) -> void:
	var ang := absf(rad_to_deg(slip_angle))
	if grounded_wheels < 3 or absf(speed) < 5.0 or ang < 5.0:
		in_drift = false
	elif ang > 17.0 or (_handbrake and ang > 8.0):
		in_drift = true
	var drifting := grounded_wheels >= 3 and absf(speed) > 8.0 and ang > 12.0 and ang < 110.0
	# Only a real impact loses the drift: total speed (not speed along the
	# nose, which swings about in a slide) dropping at well over 5 g.
	var total := linear_velocity.length()
	var crashed := (_prev_speed - total) / delta > 60.0 and _brake < 0.5
	_prev_speed = total
	if crashed and drift_points > 0.0:
		drift_points = 0.0
		_drift_time = 0.0
		drift_combo = 1
	if drifting:
		_drift_time += delta
		_drift_idle = 0.0
		drift_combo = mini(1 + int(_drift_time / 2.0), 5)
		drift_points += ang * absf(speed) * delta * 0.25 * drift_combo
	elif drift_points > 0.0:
		_drift_idle += delta
		if _drift_idle > 1.2:
			drift_total += drift_points
			drift_best = maxf(drift_best, drift_points)
			drift_last = drift_points
			drift_last_time = _clock
			drift_points = 0.0
			_drift_time = 0.0
			drift_combo = 1


## Controller rumble: tyre slip and thrust as a buzz, landings as a thump.
func _update_rumble(delta: float) -> void:
	if grounded_wheels == 0:
		_air_vy = minf(_air_vy, linear_velocity.y)
	var landing := 0.0
	if grounded_wheels > 0 and _air_vy < -3.0:
		landing = clampf(-_air_vy / 12.0, 0.2, 1.0)
		_air_vy = 0.0
	elif grounded_wheels > 0:
		_air_vy = 0.0
	_rumble_t -= delta
	if Input.get_connected_joypads().is_empty() or (_rumble_t > 0.0 and landing == 0.0):
		return
	_rumble_t = 0.06
	var weak := clampf(tyre_squeal * 0.7 + thrust_valve * 0.35 + jet_output * 0.3, 0.0, 1.0)
	for d in Input.get_connected_joypads():
		if landing > 0.0:
			Input.start_joy_vibration(d, 0.3, landing, 0.25)
		elif weak > 0.05:
			Input.start_joy_vibration(d, weak, 0.0, 0.08)


func _update_visuals(delta: float) -> void:
	for i in wheels.size():
		var w := wheels[i]
		var travel := SUSP_TRAVEL - w.compression if w.grounded else SUSP_TRAVEL
		if not w.grounded:
			w.spin_speed = lerpf(w.spin_speed, _drive * 30.0, 1.0 - exp(-1.5 * delta))
		# Skid marks and tyre smoke where the tyre is sliding.
		var marking := w.grounded and w.slip > 0.25 and w.slip_speed > 2.0
		if skids:
			skids.add_point(i, w.contact, w.normal, w.slip if marking else 0.0)
		var smoke := _smoke[i]
		smoke.global_position = w.contact + w.normal * 0.15
		var puff := clampf((w.slip - 0.35) * 1.6, 0.0, 1.0) * clampf(w.slip_speed / 8.0, 0.0, 1.0) if marking else 0.0
		smoke.emitting = puff > 0.05
		smoke.amount_ratio = maxf(puff, 0.2)
		w.spin = wrapf(w.spin - w.spin_speed * delta, -PI, PI)
		var steer := -_steer_angle if w.front else 0.0
		w.node.transform = Transform3D(
			Basis(Vector3.UP, steer) * Basis(Vector3.RIGHT, w.spin),
			Vector3(w.mount.x, MOUNT_HEIGHT - travel, w.mount.z))

	for f in _fans:
		f.rotate_y(fan_spin * 70.0 * delta)
	_update_trail(delta)
	_animate_pilot(delta)

	for i in 3:
		_motor_mats[i].emission_energy_multiplier = motor_load[i] * 2.5

	var steer_k := 1.0 - exp(-30.0 * delta)        # electric actuator response
	for i in jets.size():
		var f := _jet_forces[i]
		var mag := f.length()
		var target := -f / mag if mag > 60.0 else jets[i].rest_dir
		_aim_nozzle(jets[i], target, mag / JET_FORCE, steer_k)
	for n in thrusters:
		_aim_nozzle(n, -_thrust_dir, thrust_valve * (0.5 + 0.5 * thrust_tank), steer_k)


## Tyre trails, laid by the rear tyres (goo_trail.gd), each car its own:
## the Symbiote's goo and vines (with dirt clods and goo drops flung off
## behind), the Neon's light ribbon (and sparks at speed), the Phantom's
## spectral mist (and ghost motes rising off it). They all change with
## speed: see goo_trail.gdshader.
func _update_trail(_delta: float) -> void:
	var on: bool = BODIES[body_index].trail
	var style: int = BODIES[body_index].tire_trail
	var spd := absf(speed)
	var hot := clampf((spd - 12.0) / 45.0, 0.0, 1.0)      # 0 at ~45 km/h, 1 at ~200
	for k in 2:
		var w := wheels[2 + k]
		var laying := w.grounded and spd > 1.5
		if goo:
			goo.add_point(k, w.contact, w.normal, 1.0 if laying else 0.0, style, spd)
		var sp := _trail_sparks[k]
		sp.global_transform = Transform3D(global_basis, w.contact + w.normal * 0.08 if w.grounded else global_transform * Vector3(w.mount.x, 0.0, w.mount.z))
		sp.emitting = style != 0 and laying and hot > 0.02
		sp.amount_ratio = clampf(hot, 0.1, 1.0)
		var dirt := _trail_fx[k * 2]
		var drops := _trail_fx[k * 2 + 1]
		var at := (w.contact + w.normal * 0.1) if w.grounded else global_transform * Vector3(w.mount.x, 0.0, w.mount.z)
		for p in [dirt, drops]:
			p.global_transform = Transform3D(global_basis, at)
		var kick := clampf(spd / 25.0, 0.0, 1.0) + w.slip * 0.6
		dirt.emitting = laying and kick > 0.08
		dirt.amount_ratio = clampf(kick, 0.15, 1.0)
		drops.emitting = on and spd > 3.0
		drops.amount_ratio = clampf(kick * 0.8 + (0.4 if not w.grounded else 0.0), 0.15, 1.0)
	# A glow under the tail in the trail's colour, brighter the faster you go.
	var grounded := wheels[2].grounded or wheels[3].grounded
	var k_glow := (0.3 + clampf(spd / 30.0, 0.0, 1.0) + hot) if grounded else 0.2
	if style == 0:
		_goo_light.light_energy = 1.2 + 0.8 * sin(_clock * 4.0) * 0.5 + clampf(spd / 30.0, 0.0, 1.0)
	else:
		_goo_light.light_energy = lerpf(_goo_light.light_energy, k_glow * 1.4, 0.2)
		_goo_light.light_color = (BODIES[body_index].accent as Color).lerp(Color(0.7, 0.95, 1.0) if style == 1 else Color(0.8, 1.0, 0.95), hot * 0.6)


## The pilot breathes, its heart (and every nerve-vein) beats faster under
## boost, jets and speed, its eye follows the steering and its tendrils
## work the controls.
func _animate_pilot(delta: float) -> void:
	if _pilot == null:
		return
	var rate := 1.1 + absf(speed) * 0.015 + thrust_valve * 1.6 + jet_output * 2.0 + tyre_slip * 0.8
	_bio_t += delta * rate
	var beat := pow(maxf(sin(_bio_t * TAU), 0.0), 8.0) + 0.5 * pow(maxf(sin(_bio_t * TAU - 0.6), 0.0), 8.0)
	_pilot.scale = Vector3.ONE * (1.0 + 0.035 * sin(_clock * 1.6) + 0.04 * beat)
	if _pilot_eye:
		var look := Vector3(_brake_in * 0.2 - _throttle * 0.12 + (0.25 if grounded_wheels == 0 else 0.0), -_steer * 0.6, 0.0)
		_pilot_eye.rotation = _pilot_eye.rotation.lerp(look, 1.0 - exp(-8.0 * delta))
	for i in _tendrils.size():
		var t := _clock * (1.5 + i * 0.2) + i * 1.7
		_tendrils[i].rotation = Vector3(sin(t) * 0.05 + _throttle * 0.04, -_steer * 0.12 + sin(t * 1.3) * 0.04, cos(t * 0.9) * 0.04)
	for m in _bio_mats:
		m.emission_energy_multiplier = 1.6 + 4.0 * beat


func _aim_nozzle(n: Nozzle, exhaust: Vector3, intensity: float, k: float) -> void:
	var e := n.exhaust.lerp(exhaust, k)
	n.exhaust = e.normalized() if e.length() > 0.01 else exhaust
	# Nozzle meshes exhaust along local -Y.
	var b := Basis(_arc(Vector3.DOWN, n.exhaust))
	n.node.transform = Transform3D(b, n.pos)
	n.intensity = intensity
	n.fx.emitting = intensity > 0.04 and n.node.is_visible_in_tree()
	n.fx.amount_ratio = clampf(intensity, 0.15, 1.0)


static func _arc(from: Vector3, to: Vector3) -> Quaternion:
	if from.dot(to) < -0.9999:
		return Quaternion(Vector3.RIGHT, PI)
	return Quaternion(from, to)


func _make_nozzle(node: Node3D, rest: Vector3, size: float) -> Nozzle:
	var n := Nozzle.new()
	n.node = node
	n.pos = node.position
	n.rest_dir = rest
	n.exhaust = rest
	n.fx = _make_exhaust(size)
	node.add_child(n.fx)
	return n


func _make_exhaust(size: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 40
	p.lifetime = 0.22
	p.fixed_fps = 0
	p.interpolate = true
	p.local_coords = true             # fixed-length plume that stays on the nozzle
	p.emitting = false
	p.position = Vector3(0, -0.16 * size, 0)
	p.visibility_aabb = AABB(Vector3(-6, -6, -6), Vector3(12, 12, 12))

	var m := ParticleProcessMaterial.new()
	m.direction = Vector3.DOWN
	m.spread = 6.0
	m.initial_velocity_min = 8.0 * size
	m.initial_velocity_max = 12.0 * size
	m.gravity = Vector3.ZERO
	m.damping_min = 18.0
	m.damping_max = 26.0
	m.scale_min = 0.35
	m.scale_max = 0.6
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.25))
	curve.add_point(Vector2(1, 1.3))
	var ct := CurveTexture.new()
	ct.curve = curve
	m.scale_curve = ct
	var grad := Gradient.new()
	grad.set_color(0, Color(0.85, 0.93, 1.0, 0.3))
	grad.set_color(1, Color(1, 1, 1, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	m.color_ramp = gt
	p.process_material = m

	var quad := QuadMesh.new()
	quad.size = Vector2(0.4, 0.4) * size
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = _soft_dot()
	quad.material = mat
	p.draw_pass_1 = quad
	return p


func _make_smoke() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.top_level = true
	p.amount = 40
	p.lifetime = 1.6
	p.local_coords = false
	p.emitting = false
	p.visibility_aabb = AABB(Vector3(-8, -2, -8), Vector3(16, 8, 16))
	var m := ParticleProcessMaterial.new()
	m.direction = Vector3.UP
	m.spread = 60.0
	m.initial_velocity_min = 0.5
	m.initial_velocity_max = 2.0
	m.gravity = Vector3(0, 0.6, 0)
	m.damping_min = 1.0
	m.damping_max = 2.0
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	m.emission_sphere_radius = 0.2
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.4))
	curve.add_point(Vector2(1, 2.6))
	var ct := CurveTexture.new()
	ct.curve = curve
	m.scale_curve = ct
	var grad := Gradient.new()
	grad.set_color(0, Color(0.85, 0.85, 0.88, 0.32))
	grad.set_color(1, Color(0.9, 0.9, 0.92, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	m.color_ramp = gt
	p.process_material = m
	var quad := QuadMesh.new()
	quad.size = Vector2(1.2, 1.2)
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = _soft_dot()
	quad.material = mat
	p.draw_pass_1 = quad
	return p


func _make_dirt() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.top_level = true
	p.amount = 60
	p.lifetime = 0.9
	p.local_coords = false
	p.emitting = false
	p.visibility_aabb = AABB(Vector3(-6, -3, -6), Vector3(12, 8, 12))
	var m := ParticleProcessMaterial.new()
	m.direction = Vector3(0, 0.7, 1)            # up and back, in car space
	m.spread = 25.0
	m.initial_velocity_min = 3.0
	m.initial_velocity_max = 7.0
	m.gravity = Vector3(0, -12, 0)
	m.scale_min = 0.5
	m.scale_max = 1.3
	m.angular_velocity_min = -400
	m.angular_velocity_max = 400
	var grad := Gradient.new()
	grad.set_color(0, Color(0.24, 0.17, 0.09, 1.0))
	grad.set_color(1, Color(0.18, 0.13, 0.07, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	m.color_ramp = gt
	p.process_material = m
	var box_mesh := BoxMesh.new()
	box_mesh.size = Vector3(0.07, 0.05, 0.06)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 1.0
	box_mesh.material = mat
	p.draw_pass_1 = box_mesh
	return p


## Speed particles off the rear tyres: the Neon throws hot sparks that
## streak back and bounce; the Phantom sheds ghost motes that drift up.
func _style_sparks(p: GPUParticles3D, style: int, accent: Color) -> void:
	var m := ParticleProcessMaterial.new()
	var grad := Gradient.new()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.emission_enabled = true
	mat.emission_energy_multiplier = 4.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var sm := SphereMesh.new()
	sm.radial_segments = 6
	sm.rings = 3
	if style == 2:
		p.amount = 36
		p.lifetime = 1.4
		m.direction = Vector3(0, 1, 0.6)
		m.spread = 40.0
		m.initial_velocity_min = 0.4
		m.initial_velocity_max = 1.6
		m.gravity = Vector3(0, 1.4, 0)
		m.damping_min = 0.5
		m.damping_max = 1.0
		m.scale_min = 0.8
		m.scale_max = 1.8
		grad.set_color(0, Color(accent.lightened(0.3), 0.8))
		grad.set_color(1, Color(accent, 0.0))
		sm.radius = 0.07
		sm.height = 0.14
		mat.emission = accent
		mat.emission_energy_multiplier = 2.5
	else:
		p.amount = 48
		p.lifetime = 0.45
		m.direction = Vector3(0, 0.35, 1)
		m.spread = 25.0
		m.initial_velocity_min = 2.0
		m.initial_velocity_max = 7.0
		m.gravity = Vector3(0, -14.0, 0)
		m.scale_min = 0.5
		m.scale_max = 1.2
		m.collision_mode = ParticleProcessMaterial.COLLISION_RIGID
		m.collision_bounce = 0.4
		grad.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
		grad.set_color(1, Color(accent.lerp(Color(0.4, 0.9, 1.0), 0.5), 0.0))
		sm.radius = 0.025
		sm.height = 0.12
		mat.emission = accent.lerp(Color(0.6, 0.9, 1.0), 0.4)
		p.collision_base_size = 0.02
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	m.color_ramp = gt
	p.process_material = m
	sm.material = mat
	p.draw_pass_1 = sm


func _make_goo_drops() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.top_level = true
	p.amount = 40
	p.lifetime = 1.1
	p.local_coords = false
	p.emitting = false
	p.visibility_aabb = AABB(Vector3(-6, -3, -6), Vector3(12, 8, 12))
	var m := ParticleProcessMaterial.new()
	m.direction = Vector3(0, 0.5, 1)
	m.spread = 35.0
	m.initial_velocity_min = 1.5
	m.initial_velocity_max = 4.5
	m.gravity = Vector3(0, -9.8, 0)
	m.scale_min = 0.6
	m.scale_max = 1.4
	var curve := Curve.new()
	curve.add_point(Vector2(0, 1.0))
	curve.add_point(Vector2(0.8, 0.8))
	curve.add_point(Vector2(1, 0.0))
	var ct := CurveTexture.new()
	ct.curve = curve
	m.scale_curve = ct
	var grad := Gradient.new()
	grad.set_color(0, Color(0.35, 1.0, 0.45, 1.0))
	grad.set_color(1, Color(0.1, 0.7, 0.25, 0.6))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	m.color_ramp = gt
	p.process_material = m
	var sm := SphereMesh.new()
	sm.radius = 0.045
	sm.height = 0.07
	sm.radial_segments = 8
	sm.rings = 4
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.emission_enabled = true
	mat.emission = Color(0.15, 0.9, 0.3)
	mat.emission_energy_multiplier = 2.5
	mat.roughness = 0.1
	mat.metallic = 0.2
	sm.material = mat
	p.draw_pass_1 = sm
	return p


static var _dot_tex: Texture2D
static func _soft_dot() -> Texture2D:
	if _dot_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		t.width = 64
		t.height = 64
		_dot_tex = t
	return _dot_tex


# ------------------------------------------------------------------ physics

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if _pending_reset != null:
		state.transform = _pending_reset
		state.linear_velocity = Vector3.ZERO
		state.angular_velocity = Vector3.ZERO
		_pending_reset = null
		resets += 1
		grinding = false
		thrust_valve = 0.0
		flight_mode = false
		pad_time = 0.0
		_burst_t = 0.0
		_dodge_t = 0.0
		_pending_dodge = Vector3.ZERO
		_jumps = 0
		reset_physics_interpolation.call_deferred()
		return

	if grind_hook.is_valid() and grind_hook.call(state):
		return

	var dt := state.step
	var xf := state.transform
	var b := xf.basis
	var up := b.y
	var space := state.get_space_state()
	var g := state.total_gravity.length()

	var had_wheels := grounded_wheels > 0
	_suspension_and_tyres(state, space, xf, dt)
	if had_wheels and grounded_wheels == 0:
		_lip_takeoff(state, b)

	# Altitude above whatever is under the centre of mass.
	var com_world := xf * COM
	var q := PhysicsRayQueryParameters3D.create(com_world, com_world + Vector3.DOWN * 60.0, collision_mask, [get_rid()])
	var hit := space.intersect_ray(q)
	altitude = (com_world.distance_to(hit.position) - 0.32) if hit else 60.0

	# Suction fans pull the car onto the road; useless once off the ground.
	var ground_factor := 1.0 if grounded_wheels > 0 else clampf(1.0 - altitude / 1.2, 0.0, 1.0)
	state.apply_central_force(-up * FAN_DOWNFORCE * fan_spin * ground_factor)

	var v := state.linear_velocity
	state.apply_central_force(-v * v.length() * DRAG)

	if _pending_dodge != Vector3.ZERO:
		_start_dodge(state, b)

	if pad_time > 0.0:
		pad_time -= dt
		state.apply_central_force(-b.z * mass * PAD_ACCEL)

	_rear_thrusters(state, b, dt)
	_perimeter_jets(state, b, g, dt)


func _suspension_and_tyres(state: PhysicsDirectBodyState3D, space: PhysicsDirectSpaceState3D, xf: Transform3D, dt: float) -> void:
	var up := xf.basis.y
	var fwd := -xf.basis.z
	var ray_len := SUSP_TRAVEL + WHEEL_RADIUS
	grounded_wheels = 0
	for w in wheels:
		var from := xf * w.mount
		var q := PhysicsRayQueryParameters3D.create(from, from - up * ray_len, collision_mask, [get_rid()])
		var hit := space.intersect_ray(q)
		var prev_compression := w.compression
		w.was_grounded = w.grounded
		w.grounded = not hit.is_empty()
		if not w.grounded:
			w.compression = 0.0
			w.normal_load = 0.0
			w.slip = 0.0
			continue
		grounded_wheels += 1
		w.contact = hit.position
		w.normal = hit.normal
		w.compression = clampf(ray_len - from.distance_to(hit.position), 0.0, SUSP_TRAVEL)
		# Compression speed from the change in travel, so curved surfaces
		# (loops, quarter-pipes) don't read as the wheel lifting off. On the
		# first contact use the body's approach speed instead.
		if w.was_grounded:
			# Light filter: track facets make the raw rate spiky.
			w.comp_vel = lerpf(w.comp_vel, (w.compression - prev_compression) / dt, 0.35)
		else:
			w.comp_vel = -state.get_velocity_at_local_position(w.contact - xf.origin).dot(up)
		var comp_vel := w.comp_vel
		var damp := DAMP_BUMP if comp_vel > 0.0 else DAMP_REBOUND
		w.normal_load = SPRING_K * w.compression + damp * comp_vel
		# Progressive bump stop: keeps the floor off the track at loop-level g.
		if w.compression > BUMP_START:
			w.normal_load += (w.compression - BUMP_START) ** 2 * BUMP_K

	# Anti-roll bars.
	for pair in [[0, 1], [2, 3]]:
		var l := wheels[pair[0]]
		var r := wheels[pair[1]]
		if l.grounded and r.grounded:
			var d := (l.compression - r.compression) * ANTI_ROLL
			l.normal_load += d
			r.normal_load -= d

	# Motor forces. Front motor drives both front wheels; each rear motor
	# drives its own wheel, which allows torque vectoring.
	var v_fwd := state.linear_velocity.dot(fwd)
	var limp := power_scale()
	var front := _motor_force(FRONT_MOTOR_FORCE, FRONT_MOTOR_POWER, v_fwd) * _drive * limp
	var rear := _motor_force(REAR_MOTOR_FORCE, REAR_MOTOR_POWER, v_fwd) * _drive * limp
	var tv := TORQUE_VECTORING * _steer if _drive > 0.0 else 0.0
	var drive := [front * 0.5, front * 0.5, rear * (1.0 + tv), rear * (1.0 - tv)]
	motor_load[0] = absf(front) / FRONT_MOTOR_FORCE
	motor_load[1] = absf(drive[2]) / REAR_MOTOR_FORCE
	motor_load[2] = absf(drive[3]) / REAR_MOTOR_FORCE

	var corner_mass := mass * 0.25
	var motor_w := 0.0
	var regen_w := 0.0
	var coast := absf(_drive) < 0.01 and _brake < 0.01 and not _handbrake
	tyre_slip = 0.0
	tyre_squeal = 0.0
	for i in wheels.size():
		var w := wheels[i]
		if not w.grounded:
			w.locked = false
			w.spinning = false
			continue
		var n := w.normal
		var fz := maxf(w.normal_load, 0.0)
		state.apply_force(up * fz, w.contact - xf.origin)

		var steer := -_steer_angle if w.front else 0.0
		var wf := fwd.rotated(up, steer)
		wf = (wf - n * n.dot(wf)).normalized()
		var wr := wf.cross(n)
		var hub := w.contact + n * WHEEL_RADIUS
		var v_pt := state.get_velocity_at_local_position(hub - xf.origin)
		var v_long := v_pt.dot(wf)
		var v_lat := v_pt.dot(wr)
		var limit := (GRIP_FRONT if w.front else GRIP_REAR) * fz
		var stop_force := absf(v_long) * corner_mass / dt * 0.5
		var handbraked := _handbrake and not w.front
		w.locked = false
		w.spinning = false

		# ---- lateral first: slip-angle tyre curve (blended to a stable
		# velocity-cancelling model at walking pace).
		var lat_scale := 1.0
		if handbraked and absf(v_long) > 0.5:
			lat_scale = LOCKED_LAT_GRIP
		elif burnout and not w.front:
			lat_scale = SPIN_LAT_GRIP
		elif in_drift and drift_assist and not w.front:
			# Arcade drift balance: throttle keeps the rear loose, lifting off
			# lets it grip and straighten. Looser at low speed, steadier fast.
			var loose := lerpf(DRIFT_REAR_GRIP, 0.8, clampf((absf(v_long) - 15.0) / 30.0, 0.0, 1.0))
			lat_scale = lerpf(0.9, loose, _throttle)
		var alpha := atan2(v_lat, maxf(absf(v_long), 0.5))
		var hi := clampf((absf(v_long) - 3.0) / 4.0, 0.0, 1.0)
		var lat_cap := limit * lat_scale
		var f_cancel := -v_lat * corner_mass / dt * LAT_RESPONSE
		var f_lat := lerpf(f_cancel, -lat_cap * sin(TYRE_C * atan(TYRE_B * alpha)), hi)
		var max_cancel := absf(v_lat) * corner_mass / dt      # never overshoot in one step
		f_lat = clampf(f_lat, -minf(max_cancel, lat_cap), minf(max_cancel, lat_cap))
		# Grip left over for drive and braking once cornering has its share.
		# TC and ABS work inside this, so they never steal the steering.
		var avail := sqrt(maxf(limit * limit - f_lat * f_lat, (0.3 * limit) ** 2))

		# ---- longitudinal: drive, brakes, regen, handbrake
		var f_drive: float = drive[i]
		if handbraked:
			f_drive = 0.0                    # rear motors declutch while the handbrake is on
		var f_long := f_drive - v_long * ROLLING
		var brake_req := _brake * BRAKE_FORCE * 2.0 * (BRAKE_BIAS_FRONT if w.front else 1.0 - BRAKE_BIAS_FRONT)
		if burnout and not w.front:
			f_long = 0.0                     # rears spin up against the held fronts
			brake_req = 0.0
			w.spinning = true
		if handbraked:
			f_long = -signf(v_long) * minf(limit * HANDBRAKE_DECEL, stop_force)
			w.locked = absf(v_long) > 0.5
		elif brake_req > 0.0:
			var bf := minf(brake_req, stop_force)
			if abs_on:
				bf = minf(bf, avail * 0.97)      # ABS holds the tyre just under lock-up
			elif brake_req > avail and absf(v_long) > 0.5:
				w.locked = true
				bf = minf(limit * KINETIC_GRIP, stop_force)
			f_long -= signf(v_long) * bf
			regen_w += bf * absf(v_long) * REGEN_EFFICIENCY
		elif coast and absf(v_long) > 1.0:
			var r := minf(COAST_REGEN_G * corner_mass * 9.81, stop_force)
			f_long -= signf(v_long) * r
			regen_w += r * absf(v_long) * REGEN_EFFICIENCY
		elif absf(_drive) < 0.01 and absf(v_long) < 0.4:
			f_long -= signf(v_long) * minf(BRAKE_FORCE, stop_force)    # hold on slopes
		if absf(f_long) > avail and not w.locked:
			if tc_on or absf(f_drive) < 1.0:
				f_long = signf(f_long) * avail * 0.97     # traction control trims torque
			else:
				w.spinning = true                       # wheelspin
				f_long = signf(f_long) * limit * KINETIC_GRIP
		if lat_scale == 1.0 and (w.locked or w.spinning):
			f_lat *= LOCKED_LAT_GRIP if w.locked else SPIN_LAT_GRIP
		if Vector2(f_lat, f_long).length() > limit:     # friction ellipse
			f_lat = signf(f_lat) * sqrt(maxf(limit * limit - f_long * f_long, 0.0))

		# ---- effects bookkeeping
		var slide := clampf((absf(alpha) - TYRE_PEAK) / 0.25, 0.0, 1.0) * hi
		w.slip = maxf(slide, 1.0 if (w.locked or w.spinning) else 0.0)
		w.slip_speed = absf(v_lat) + (absf(v_long) if w.locked else 0.0) + (10.0 if w.spinning else 0.0)
		if w.locked:
			w.spin_speed = 0.0
		elif w.spinning:
			w.spin_speed = v_long / WHEEL_RADIUS + signf(f_drive if f_drive != 0.0 else 1.0) * 40.0
		else:
			w.spin_speed = v_long / WHEEL_RADIUS
		tyre_slip = maxf(tyre_slip, w.slip)
		tyre_squeal = maxf(tyre_squeal, w.slip * clampf(w.slip_speed / 6.0, 0.0, 1.0))

		motor_w += absf(f_drive * v_long)
		state.apply_force(wr * f_lat + wf * f_long, hub - xf.origin)

	_stability_control(state, xf, fwd)
	_drain_battery(motor_w / MOTOR_EFFICIENCY - regen_w, dt)


## Stability control (ESC) nudges the yaw rate toward what the steering
## asks for (real systems brake single wheels; a yaw torque is the same
## net effect). Drift assist only catches spins past ~40 degrees.
func _stability_control(state: PhysicsDirectBodyState3D, xf: Transform3D, fwd: Vector3) -> void:
	if grounded_wheels < 3 or _handbrake:
		return
	var v_fwd := state.linear_velocity.dot(fwd)
	if absf(v_fwd) < 5.0:
		return
	var yaw := (xf.basis.transposed() * state.angular_velocity).y
	var tau := 0.0
	if esc_on:
		var max_rate := GRIP_FRONT * 9.81 / absf(v_fwd)
		var want := clampf(-v_fwd * tan(_steer_angle) / WHEELBASE, -max_rate, max_rate)
		if absf(yaw - want) > 0.12:
			tau = -_inertia.y * ESC_GAIN * (yaw - want)
	elif drift_assist and absf(slip_angle) > 0.45 and signf(yaw) == signf(slip_angle):
		# Yawing further into the slide past ~25 degrees: catch the spin.
		tau = -_inertia.y * 7.0 * yaw * minf(absf(slip_angle) - 0.45, 0.5)
	if tau != 0.0:
		state.apply_torque(xf.basis.y * clampf(tau, -20000.0, 20000.0))


func _motor_force(max_force: float, power: float, v: float) -> float:
	var f := minf(max_force, power / maxf(absf(v), 1.0))
	return f * clampf((MOTOR_TOP_SPEED - absf(v)) / 6.0, 0.0, 1.0)


func _local_angular(state: PhysicsDirectBodyState3D) -> Vector3:
	return state.transform.basis.transposed() * state.angular_velocity


## Body-space rotation vector (axis * angle) that would turn the car's up
## vector onto a target up tilted by pitch_fwd (nose down) and roll_right.
## Uses the full angle, so the correction stays strong when upside down.
func _attitude_error(b: Basis, pitch_fwd: float, roll_right: float) -> Vector3:
	var f := -b.z
	f.y = 0.0
	if f.length() < 0.05:
		f = b.y if b.y.y < 0.0 else -b.y      # nose straight up/down: use the roof direction
		f.y = 0.0
	f = f.normalized() if f.length() > 0.05 else Vector3.FORWARD
	var r := f.cross(Vector3.UP)
	var target := (Vector3.UP + f * tan(pitch_fwd) + r * tan(roll_right)).normalized()
	var c := b.y.cross(target)
	var s := c.length()
	var d := b.y.dot(target)
	if s < 1e-4:
		if d > 0.0:
			return Vector3.ZERO
		c = b.z                               # fully inverted: roll upright (lowest inertia)
		s = 1.0
	return b.transposed() * (c / s * atan2(s, d))


## Leaving a ramp lip, the front wheels lose the road first while the rear
## suspension is still pushing up, which kicks the nose down; with no flight
## computer (FULL) the car would slowly front-flip through every fast jump
## and land on its roof. On a natural takeoff (not a jump or dodge) drop
## that pitch and roll spin and keep the yaw, so the car holds the angle it
## left the ramp at, like Rocket League. Stick input after takeoff is untouched.
func _lip_takeoff(state: PhysicsDirectBodyState3D, b: Basis) -> void:
	if _jumps > 0 or _burst_t > 0.0 or _dodge_t > 0.0 or _pending_dodge != Vector3.ZERO:
		return
	var w := b.transposed() * state.angular_velocity
	state.angular_velocity = b * Vector3(w.x * (1.0 - LIP_HOLD), w.y, w.z * (1.0 - LIP_HOLD))


## Dodge: a sideways/forward shove toward the arrows and a snap flip the
## same way (front flip, back flip, barrel roll, or a diagonal mix).
func _start_dodge(state: PhysicsDirectBodyState3D, b: Basis) -> void:
	var d := _pending_dodge          # x = forward/back flip, z = roll right/left
	_pending_dodge = Vector3.ZERO
	var fwd := -b.z
	fwd.y = 0.0
	var right := b.x
	right.y = 0.0
	var push := fwd.normalized() * d.x + right.normalized() * d.z
	if push.length() > 0.01:
		state.linear_velocity += push.normalized() * DODGE_DV
	# Kill most of the fall so the flip happens in the air, like RL.
	state.linear_velocity.y = maxf(state.linear_velocity.y, 1.5)
	var rate := Vector3(-d.x, 0.0, -d.z).normalized() * DODGE_SPIN
	state.angular_velocity = b * rate
	rocket_tank = maxf(0.0, rocket_tank - 0.02)


func _rear_thrusters(state: PhysicsDirectBodyState3D, b: Basis, dt: float) -> void:
	if thrust_valve <= 0.001 or thrust_tank <= 0.0:
		_thrust_dir = Vector3.FORWARD
		return
	var total := 4.0 * THRUSTER_FORCE * thrust_valve * lerpf(0.5, 1.0, thrust_tank)
	var arm := thrusters[0].pos.z - COM.z
	var gimbal_yaw := 0.0
	var gimbal_pitch := 0.0
	if grounded_wheels > 0:
		gimbal_yaw = -_steer * deg_to_rad(5.0)
	else:
		# In the air the actuators vector the thrust: AUTO holds the nose
		# level, HYBRID only damps rotation, FULL takes the stick directly.
		var w := _local_angular(state)
		var tau_x := 0.0
		var tau_y := 0.0
		match jet_mode:
			JetMode.AUTO:
				var err := _attitude_error(b, 0.0, 0.0)
				tau_x = _inertia.x * (8.0 * err.x - 4.0 * w.x)
				tau_y = _inertia.y * (-2.5 * w.y - 1.5 * _steer)
			JetMode.HYBRID:
				tau_x = _inertia.x * (-4.0 * w.x - 6.0 * _spin.x)
				tau_y = _inertia.y * (-2.5 * w.y - 1.5 * _steer)
			JetMode.FULL:
				tau_x = -_inertia.x * MANUAL_ACCEL.x * _spin.x
				tau_y = -_inertia.y * MANUAL_ACCEL.y * _steer
		gimbal_pitch = asin(clampf(-tau_x / arm / total, -sin(THRUSTER_GIMBAL), sin(THRUSTER_GIMBAL)))
		gimbal_yaw = asin(clampf(tau_y / arm / total, -sin(THRUSTER_GIMBAL), sin(THRUSTER_GIMBAL)))
	_thrust_dir = Vector3(sin(gimbal_yaw) * cos(gimbal_pitch), sin(gimbal_pitch), -cos(gimbal_yaw) * cos(gimbal_pitch))
	var pos := Vector3(0.0, thrusters[0].pos.y, thrusters[0].pos.z)
	if grounded_wheels == 0:
		# In the air the thrust acts at the centre of mass's height: the
		# nozzles sit above it, and untrimmed, boosting off a ramp (in FULL,
		# with nothing levelling the car) pitched it onto its roof. Gimbal
		# steering still turns the car, through the nozzles' distance behind it.
		pos.y = COM.y
	state.apply_force(b * (_thrust_dir * total), b * pos)
	thrust_tank = maxf(0.0, thrust_tank - thrust_valve * dt / THRUST_TANK_SECONDS)


func _perimeter_jets(state: PhysicsDirectBodyState3D, b: Basis, g: float, dt: float) -> void:
	for i in _jet_forces.size():
		_jet_forces[i] = Vector3.ZERO
	jet_output = 0.0
	if not jets_available():
		return

	var w := _local_angular(state)
	var v := state.linear_velocity
	var up := b.y
	var airborne := grounded_wheels == 0
	var collective := 0.0
	var tau := Vector3.ZERO
	var side := 0.0                     # net sideways push (body +X)
	var brake := 0.0
	var max_f := JET_FORCE * lerpf(0.6, 1.0, rocket_tank)
	var all_jets := 6.0 * max_f
	var stick := _spin.length() > 0.1

	if _burst_t > 0.0:
		# Jump burst: valves wide open, straight up the car's axis (plus
		# holding up its weight meanwhile), split so it adds no torque.
		_burst_t -= dt
		collective = mass * (_burst_dv / BURST_TIME + g * maxf(up.y, 0.0))
		max_f = collective / 6.0 * 1.15
	elif _dodge_t > 0.0:
		# Dodge in progress: hands off, let it flip.
		pass
	elif not airborne and not flight_mode:
		# On the road, in every mode: the arrows fire the jets directly.
		#   left/right  side jets push the car sideways (catch a slide)
		#   down        all jets fire upward, pressing the tyres into the road
		#   up          hop
		side = _spin.y * SIDE_PUSH * all_jets
		if _spin.x < -0.1:
			collective = _spin.x * PRESS_DOWN * all_jets
		elif _spin.x > 0.1:
			collective = _spin.x * HOP * all_jets
		if _jet_assist:
			if speed > 0.5:
				brake = 2.0 * max_f
			tau.y = -_steer * JET_YAW_ASSIST
	elif jet_mode == JetMode.FULL:
		# No flight computer: stick and lift go straight to the nozzles.
		tau.x = -_spin.x * MANUAL_ACCEL.x * _inertia.x
		tau.z = -_spin.y * MANUAL_ACCEL.z * _inertia.z
		tau.y = -_steer * MANUAL_ACCEL.y * _inertia.y
		collective = _lift * all_jets
		if _jet_assist:
			collective = -0.5 * all_jets
	else:
		# AUTO and HYBRID. Holding the flip stick commands body rates.
		var pitch_in := _spin.x
		if jet_mode == JetMode.HYBRID and flight_mode:
			pitch_in = clampf(pitch_in + (_throttle - Input.get_action_strength("brake")) * 0.5, -1.0, 1.0)
		if stick or (jet_mode == JetMode.HYBRID):
			# HYBRID with the stick centred: rates go to zero, so the car
			# holds its attitude rather than levelling itself.
			var rate := Vector3(-pitch_in * FLIP_RATE_PITCH, 0.0, -_spin.y * FLIP_RATE_ROLL)
			tau.x = _inertia.x * RATE_GAIN * (rate.x - w.x)
			tau.z = _inertia.z * RATE_GAIN * (rate.z - w.z)
		else:
			var pitch := 0.0
			var roll := 0.0
			if flight_mode:
				var fwd_in := clampf(_throttle - Input.get_action_strength("brake"), -1.0, 1.0)
				# Sticks centred: tilt against any drift so the car holds a hover.
				var vl := b.transposed() * v
				# Only near a hover: when moving, keep the momentum (lifting
				# off at speed shouldn't stand the car on its tail to brake).
				var hold := 1.0 - smoothstep(6.0, 16.0, Vector2(v.x, v.z).length())
				var hold_pitch := clampf(vl.z * 0.06, -0.3, 0.3) * hold
				var hold_roll := clampf(-vl.x * 0.06, -0.3, 0.3) * hold
				pitch = fwd_in * deg_to_rad(20.0) if absf(fwd_in) > 0.05 else hold_pitch
				roll = _steer * deg_to_rad(15.0) if absf(_steer) > 0.05 else hold_roll
			var err := _attitude_error(b, pitch, roll)
			tau.x = _inertia.x * (LEVEL_KP * err.x - LEVEL_KD * w.x)
			tau.z = _inertia.z * (LEVEL_KP * err.z - LEVEL_KD * w.z)
		tau.y = _inertia.y * 5.0 * (-_steer * 1.8 - w.y)

		# Vertical: climb-rate control in flight, landing cushion otherwise.
		var vy_target := NAN
		if flight_mode:
			# Released: descend, quickly up high and gently near the ground.
			vy_target = CLIMB_RATE * _lift if _lift > 0.05 else -clampf(altitude * 0.6 + 1.0, 1.5, 8.0)
			if _jet_assist:
				vy_target = -10.0
		elif v.y < -5.0 and altitude < 12.0 and up.y > 0.5:
			vy_target = -3.0
		if not is_nan(vy_target):
			var f_req := mass * (g + VY_GAIN * (vy_target - v.y))
			# Jets push along the car's up axis; regularised so this stays
			# smooth through knife-edge and works (gimballed) when inverted.
			collective = f_req * up.y / (up.y * up.y + 0.05)

	if collective == 0.0 and tau == Vector3.ZERO and brake == 0.0 and side == 0.0:
		return

	collective = clampf(collective, -6.0 * max_f, 6.0 * max_f)
	if _dodge_t > 0.0 and _burst_t <= 0.0:
		return
	var lam := _jet_alloc_inv * Vector3(collective, tau.x, tau.z)
	var total := 0.0
	for i in jets.size():
		var r := _jet_r[i]
		var f_up := lam.x - r.z * lam.y + r.x * lam.z
		# Sideways share: net push `side` plus yaw torque, solved together so a
		# side push doesn't also twist the car (jets sit ahead of the COM).
		var f_side := side / 6.0 + (tau.y - side * _jet_z_mean) * (r.z - _jet_z_mean) / _jet_z_var
		var f_back := brake * 0.5 if i < 2 else 0.0
		var f := Vector3(f_side, f_up, f_back).limit_length(max_f)
		_jet_forces[i] = f
		state.apply_force(b * f, b * jets[i].pos)
		total += f.length()
	jet_output = total / (6.0 * JET_FORCE)
	rocket_tank = maxf(0.0, rocket_tank - jet_output * dt / ROCKET_TANK_SECONDS)
