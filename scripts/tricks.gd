extends Node
## Style scoring. Air tricks (flips, barrel rolls, spins, big air, hang
## time, hoops and mid-air grabs), wall and loop rides, banked drifts and
## fast SKYWAY splits all score points.
##
## An air trick is graded on its landing: upright, soft, square to the
## direction of travel and no longer rotating. It is then graded on the
## ride-out just after: does the car stay on its wheels and settled? The
## grade scales the points, and so does how much the flight computer
## helped (AUTO < HYBRID < FULL). Tricks landed close together chain into
## a multiplier, and repeating the same trick pays less each time.
##
## Every banked trick refills the air tanks in proportion to its score.

signal rotation_done(kind: String, count: int)      # mid-air: a flip, roll or half-spin completed
signal touchdown(grade: int, quality: float)        # wheels down after a trick, before the ride-out
signal trick_landed(trick: Dictionary)
signal bailed(reason: String)

const Car := preload("res://scripts/car.gd")

## [min quality, name, points multiplier, colour]
const GRADES := [
	[0.84, "PERFECT", 1.5, Color(1.0, 0.84, 0.3)],
	[0.66, "GREAT", 1.25, Color(0.35, 1.0, 0.55)],
	[0.45, "CLEAN", 1.0, Color(0.45, 0.8, 1.0)],
	[0.25, "SKETCHY", 0.75, Color(1.0, 0.6, 0.3)],
	[0.0, "ROUGH", 0.55, Color(1.0, 0.42, 0.35)],
]
const NEUTRAL_Q := 0.5                  # grade for banked drifts, hoops and laps (CLEAN)
## A crash only counts (and ends the chain) when it's severe: this much
## speed lost within CRASH_WINDOW, measured along the ground so a landing
## soaking up a fall, or a quarter-pipe turning speed into height, doesn't
## count. ~16 m/s in 0.3 s is a 5 g stop: hitting a wall, not a hard brake.
const CRASH_LOSS := 16.0
const CRASH_WINDOW := 0.3
## Speed bonus for stunts: ×1 up to SPEED_FROM km/h, rising to ×SPEED_MAX at
## SPEED_TO km/h (top speed is ~400 km/h). Uses the fastest the car went
## during the trick or ride. Drifts already score by speed.
const SPEED_FROM := 60.0
const SPEED_TO := 300.0
const SPEED_MAX := 2.0
const CONTROL_MULT := [1.0, 1.25, 1.6]  # by JetMode: AUTO, HYBRID, FULL
const CHAIN_WINDOW := 4.0               # s on the ground before a chain drops
const CHAIN_STEP := 0.25
const CHAIN_MAX := 3.0
const RIDE_OUT := 0.45                  # s after touchdown the landing is still being judged
const MIN_AIR := 0.35                   # s off the ground before it counts as air
const ROT_SLACK := 0.5                  # rad short of a full turn that still counts
const REFILL_PER_POINT := 1.0 / 9000.0  # tank fraction per point
const REFILL_MIN_POINTS := 300.0
const REFILL_MAX := 0.3
const HEAL_PER_POINT := 1.0 / 450.0      # hull points restored per trick point
const HEAL_MAX := 8.0                   # most a single trick restores

var car: Car
var course: Node                        # track/course.gd, optional
var combat: Node                        # combat/combat.gd: tricks and drifts patch the hull up

# Session totals (read by the HUD)
var score := 0
var best_trick := 0
var best_trick_name := ""
var tricks_landed := 0
var chain := 0
var chain_mult := 1.0
var chain_left := 0.0

# Live state (read by the HUD)
var in_air := false
var air_time := 0.0
var peak := 0.0
var live_name := ""
var live_points := 0
var judging := false                    # in the ride-out after a touchdown
var landing_grade := 0
var last: Dictionary = {}               # last banked (or bailed) trick, for the pop-up
var last_time := -10.0
var clock := 0.0

var _off := 0.0                         # s since the wheels left the ground
var _rot := Vector3.ZERO                # body-frame rotation since takeoff, rad
var _count := Vector3i.ZERO             # completed flips (x), half-spins (y), rolls (z)
var _flight := 0.0
var _mode_min := 2
var _hoops := 0
var _grabs := 0
var _roof := 0.0
var _start_y := 0.0
var _inv_launch := false                # left the ground upside down (the inverted ramp)
var _land := {}
var _ride := 0.0
var _ride_inv := false
var _ride_off := 0.0
var _ride_slip := 0.0
var _ride_lost := 0.0
var _recent: Array[String] = []
var _drift_seen := -10.0
var _prev_pos := Vector3.ZERO
var _vel_hist: Array = []               # [time, velocity] over the last CRASH_WINDOW
var _resets := 0
var _no_crash_until := -1.0             # rams aren't crashes
var grinding := false
var _grind_parts: Array[String] = []
var _grind_t := 0.0
var _air_speed := 0.0                   # fastest during the air phase, m/s
var _ride_speed := 0.0                  # fastest during a wall ride, m/s
var _touch := 0.0                       # s with a single wheel down
var _locked := false                    # after a bail, until the car is back on its wheels


func _ready() -> void:
	_prev_pos = car.global_position
	_drift_seen = car.drift_last_time
	if course:
		course.hoop_hit.connect(_on_hoop)
		course.checkpoint_hit.connect(_on_checkpoint)
		course.lap_finished.connect(_on_lap)


static func grade_for(q: float) -> int:
	for i in GRADES.size():
		if q >= GRADES[i][0]:
			return i
	return GRADES.size() - 1


## Pickups grabbed in the air count toward the trick.
func on_grab() -> void:
	if car.grounded_wheels == 0:
		_grabs += 1


func _physics_process(delta: float) -> void:
	clock += delta
	var pos := car.global_position
	# Respawn or recover teleports the car: drop whatever was in progress.
	if pos.distance_to(_prev_pos) > 12.0 or car.resets != _resets:
		_resets = car.resets
		_reset_air()
		_land = {}
		judging = false
		_ride = 0.0
		_locked = false
		_vel_hist.clear()
	_prev_pos = pos
	if _severe_crash():
		_crash()

	if grinding:
		# On a rail: no air phase, no crash checks (the rail sets the speed).
		_no_crash_until = clock + 0.3
		_grind_t += delta
		in_air = false
		live_name = " → ".join(_grind_parts)
		live_points = int(_grind_points(_grind_t, 0.0))
		return

	var airborne := car.grounded_wheels == 0
	if not in_air and _ride <= 0.0 and car.drift_points <= 0.0 and not judging:
		chain_left -= delta
		if chain_left <= 0.0 and chain > 0:
			chain = 0
			chain_mult = 1.0
	_check_drift()

	if not _land.is_empty():
		_ride_out(delta)
	if _locked:
		if car.grounded_wheels >= 3:
			_locked = false
			_reset_air()
		return

	if airborne:
		_touch = 0.0
		_air(delta)
	elif in_air:
		# One wheel brushing the ground mid-roll isn't a landing yet.
		_touch += delta
		if car.grounded_wheels >= 2 or _touch > 0.1:
			_touchdown()
	else:
		_reset_air()
		_ground_ride(delta)


## Speed lost over the last CRASH_WINDOW, measured along the road surface
## (the old velocity projected onto it too) or, in the air, horizontally,
## so a landing or a quarter-pipe turning speed into height doesn't count.
func _severe_crash() -> bool:
	var v := car.linear_velocity
	if clock < _no_crash_until:
		_vel_hist.clear()
		_vel_hist.append([clock, v])
		return false
	_vel_hist.append([clock, v])
	while _vel_hist.size() > 2 and clock - _vel_hist[0][0] > CRASH_WINDOW:
		_vel_hist.pop_front()
	var old: Vector3 = _vel_hist[0][1]
	# In the air (or the instant of touching down) only horizontal speed
	# counts: hitting a wall kills it, landing from any height doesn't.
	var n := Vector3.UP
	if car.grounded_wheels >= 1:
		n = car.ground_normal()
	var along := (old - n * old.dot(n)).length() - (v - n * v.dot(n)).length()
	# A real impact also loses total speed. Hitting a ramp, a kerb or a
	# wheel catching a ramp's edge swings the measured road surface about
	# (so the along-the-road figure jumps) but keeps the car's speed.
	var loss := minf(along, old.length() - v.length())
	return loss > CRASH_LOSS

func _reset_air() -> void:
	in_air = false
	_off = 0.0
	_rot = Vector3.ZERO
	_count = Vector3i.ZERO
	_flight = 0.0
	_hoops = 0
	_grabs = 0
	_roof = 0.0
	_inv_launch = false
	_air_speed = 0.0
	air_time = 0.0
	peak = 0.0
	live_name = ""
	live_points = 0
	_mode_min = car.jet_mode


func _air(delta: float) -> void:
	if _ride > 0.0:
		_end_ride()                     # launched off a wall or quarter-pipe
	var b := car.global_basis
	if _off == 0.0:
		_inv_launch = b.y.y < -0.3
		_start_y = car.global_position.y
	_off += delta
	_rot += b.transposed() * car.angular_velocity * delta
	_mode_min = mini(_mode_min, car.jet_mode)
	_air_speed = maxf(_air_speed, car.linear_velocity.length())
	if car.flight_mode:
		_flight += delta
	peak = maxf(peak, car.global_position.y - _start_y)      # height above the takeoff
	if _off < MIN_AIR:
		return
	in_air = true
	air_time = _off
	var flips := int((absf(_rot.x) + ROT_SLACK) / TAU)
	var rolls := int((absf(_rot.z) + ROT_SLACK) / TAU)
	var halves := int((absf(_rot.y) + ROT_SLACK * 0.7) / PI)
	if flips > _count.x:
		rotation_done.emit("FLIP", flips)
	if rolls > _count.z:
		rotation_done.emit("ROLL", rolls)
	if halves > _count.y and halves >= 2:
		rotation_done.emit("SPIN", halves)
	_count = Vector3i(flips, halves, rolls)
	var t := _describe(false)
	live_name = t.name
	live_points = int(t.points)
	if live_name == "AIR":
		# Nothing complete yet: show the rotation under way.
		var part := Vector3(absf(_rot.x) - _count.x * TAU, absf(_rot.y) - _count.y * PI, absf(_rot.z) - _count.z * TAU)
		if maxf(part.x, part.z) > 0.8 or part.y > 0.8:
			var axis := "FLIPPING" if part.x >= part.z else "ROLLING"
			var ang := maxf(part.x, part.z)
			if part.y > ang:
				axis = "SPINNING"
				ang = part.y
			live_name = "%s  %d°" % [axis, roundi(rad_to_deg(ang))]
		elif live_points < 100:
			live_name = ""

	# Down on its roof or side with the wheels in the air: that's a bail.
	# (Judged from the height under the car: turning on body contact
	# reporting changes how Jolt resolves contacts, and so the handling.)
	if b.y.y < 0.3 and car.altitude < 0.9:
		_roof += delta
		if _roof > 0.15 or (absf(car.speed) < 1.5 and _roof > 0.05):
			_bail("BAILED")
	else:
		_roof = 0.0


## Names and base points for what's been done in the air so far. At the
## landing `landing` adds the wall-landing and fakie bonuses.
func _describe(landing: bool, n := Vector3.UP, fakie := false) -> Dictionary:
	var parts: Array[String] = []
	var pts := 0.0
	var mult_words := ["", "DOUBLE ", "TRIPLE ", "QUAD "]
	var f := _count.x
	var r := _count.z
	var h := _count.y
	if f > 0:
		parts.append((mult_words[f - 1] if f <= 4 else "%dx " % f) + ("FRONTFLIP" if _rot.x < 0.0 else "BACKFLIP"))
		pts += f * 600.0 * (1.0 + 0.25 * (f - 1))
	if r > 0:
		parts.append((mult_words[r - 1] if r <= 4 else "%dx " % r) + "BARREL ROLL")
		pts += r * 500.0 * (1.0 + 0.25 * (r - 1))
	if h >= 2:
		parts.append(str(h * 180))
		pts += h * 220.0
	if f > 0 and r > 0:
		parts.append("CORKSCREW")
		pts += 400.0
	if (f > 0 or r > 0) and h >= 2:
		parts.append("TWISTER")
		pts += 300.0
	var hang := _off - _flight
	if hang > 1.5:
		pts += (hang - 1.5) * 150.0
	if peak > 4.0:
		pts += (minf(peak, 60.0) - 4.0) * 35.0
	if peak > 20.0:
		parts.append("HUGE AIR")
	elif peak > 8.0:
		parts.append("BIG AIR")
	elif hang > 3.0:
		parts.append("HANG TIME")
	if _inv_launch:
		parts.append("INVERTED LAUNCH")
		pts += 700.0
	if _hoops > 0:
		parts.append("THREAD THE HOOP" + (" x%d" % _hoops if _hoops > 1 else ""))
		pts += 500.0 * _hoops
	if _grabs > 0:
		parts.append("MID-AIR GRAB" + (" x%d" % _grabs if _grabs > 1 else ""))
		pts += 300.0 * _grabs
	if landing and n.y < 0.5:
		parts.append("WALL LANDING")
		pts += 400.0
	if landing and fakie:
		parts.append("FAKIE")
		pts += 200.0
	if parts.is_empty():
		parts.append("AIR")
	return {"name": " + ".join(parts), "points": pts}


func _touchdown() -> void:
	var b := car.global_basis
	var n := car.ground_normal()
	var v := car.linear_velocity
	var upright := b.y.dot(n)
	if upright < 0.2:
		_bail("BAILED")                 # came down on its side or roof
		return
	# Forgiving: up to ~25° off level, a solid thump and a little leftover
	# spin still land PERFECT.
	var q_up := smoothstep(0.45, 0.9, upright)
	var q_soft := 1.0 - smoothstep(9.0, 24.0, maxf(-v.dot(n), 0.0))
	var w := b.transposed() * car.angular_velocity
	var q_rot := 1.0 - smoothstep(2.0, 7.0, Vector2(w.x, w.z).length())
	var q_head := 1.0
	var fakie := false
	var flat := v - n * v.dot(n)
	if flat.length() > 3.0:
		var fwd := -b.z
		fwd = (fwd - n * fwd.dot(n)).normalized()
		var d := fwd.dot(flat.normalized())
		fakie = d < -0.5 and flat.length() > 5.0
		q_head = 1.0 - smoothstep(0.35, 1.1, acos(clampf(absf(d), 0.0, 1.0)))
	var q := 0.35 * q_up + 0.25 * q_soft + 0.2 * q_rot + 0.2 * q_head
	var t := _describe(true, n, fakie)
	var air_pts: float = _describe(false).points
	var mode := _mode_min
	var top := _air_speed
	_reset_air()
	if air_pts < 120.0:
		return                          # just a hop (or a bounce)
	_land = {"q": q, "trick": t, "mode": mode, "t": 0.0, "slip": 0.0, "lost": 0.0, "speed": top}
	judging = true
	landing_grade = grade_for(q)
	touchdown.emit(landing_grade, q)


## The ride-out: does the car stay on its wheels and pointing where it's going?
func _ride_out(delta: float) -> void:
	_land.t += delta
	if car.grounded_wheels < 3:
		_land.lost += delta
	_land.slip = maxf(_land.slip, absf(car.slip_angle))
	if car.global_basis.y.dot(car.ground_normal()) < 0.0:
		_land = {}
		judging = false
		_bail("BAILED", true)           # rolled over after touching down
		return
	if _land.t < RIDE_OUT:
		return
	var control := 1.0 - 0.4 * clampf(_land.lost / 0.6, 0.0, 1.0) - 0.4 * smoothstep(0.5, 1.2, _land.slip)
	var q: float = _land.q * 0.75 + control * 0.25
	var t: Dictionary = _land.trick
	var mode: int = _land.mode
	var top: float = _land.speed
	_land = {}
	judging = false
	_bank(t.name, t.points * CONTROL_MULT[mode], q, 1.0, ["", "HYBRID CONTROL", "FULL CONTROL"][mode], top)


## Wall rides and loops: scored while the car is on its wheels with its
## roof pointing sideways or down, banked once it's back on the level.
func _ground_ride(delta: float) -> void:
	var up_y := car.global_basis.y.y
	var on_wall := car.grounded_wheels >= 3 and absf(car.speed) > 8.0 and up_y < 0.5
	if on_wall:
		_ride += delta
		_ride_off = 0.0
		_ride_inv = _ride_inv or up_y < -0.3
		_ride_slip = maxf(_ride_slip, absf(car.slip_angle))
		_ride_speed = maxf(_ride_speed, car.linear_velocity.length())
		if car.grounded_wheels < 4:
			_ride_lost += delta
		if _ride > 0.6:
			live_name = "LOOP" if _ride_inv else "WALL RIDE"
			live_points = int(_ride_points())
	elif _ride > 0.0:
		_ride_off += delta
		if _ride_off > 0.25 or up_y > 0.8:
			_end_ride()


func _ride_points() -> float:
	return _ride * (400.0 if _ride_inv else 300.0) + (600.0 if _ride_inv else 0.0)


func _end_ride() -> void:
	if _ride > 0.8:
		var q := 1.0 - 0.4 * smoothstep(0.4, 1.0, _ride_slip) - 0.25 * clampf(_ride_lost / 0.8, 0.0, 1.0)
		_bank("LOOP" if _ride_inv else "WALL RIDE", _ride_points(), q, 0.6, "", _ride_speed)
	_ride = 0.0
	_ride_speed = 0.0
	_ride_inv = false
	_ride_slip = 0.0
	_ride_lost = 0.0
	live_name = ""
	live_points = 0


## The car banks a drift after a short pause; count it here too.
func _check_drift() -> void:
	if car.drift_last_time != _drift_seen:
		_drift_seen = car.drift_last_time
		if car.drift_last >= 150.0:
			_bank("DRIFT", car.drift_last, NEUTRAL_Q, 0.6)


func _on_hoop(_count_hit: int) -> void:
	if in_air or car.grounded_wheels == 0:
		_hoops += 1
	else:
		_bank("HOOP", 250.0, NEUTRAL_Q, 1.0)


func _on_checkpoint(_k: int, _split: float) -> void:
	var d: float = course.last_split_delta
	if d < 0.0:
		_bank("FAST SPLIT  -%.2f" % absf(d), 300.0 + minf(-d, 5.0) * 200.0, NEUTRAL_Q, 1.0)


func _on_lap(_time: float, best: bool) -> void:
	_bank("NEW BEST LAP" if best else "LAP", 2500.0 if best else 1000.0, NEUTRAL_Q, 1.0)


## Adds a trick to the score and the chain, and refills the tanks.
static func speed_mult(speed: float) -> float:
	return lerpf(1.0, SPEED_MAX, clampf((speed * 3.6 - SPEED_FROM) / (SPEED_TO - SPEED_FROM), 0.0, 1.0))


func _bank(trick_name: String, base: float, quality: float, refill_scale: float, note := "", speed := 0.0) -> void:
	var g := grade_for(quality)
	var fast := speed_mult(speed)
	base *= fast
	var repeats := _recent.count(trick_name)
	var fresh := maxf(pow(0.75, repeats), 0.3)
	chain += 1
	chain_mult = minf(1.0 + CHAIN_STEP * (chain - 1), CHAIN_MAX)
	chain_left = CHAIN_WINDOW
	var pts := roundi(base * GRADES[g][2] * fresh * chain_mult)
	var refill := 0.0
	if pts >= REFILL_MIN_POINTS:
		refill = clampf(pts * REFILL_PER_POINT * refill_scale, 0.0, REFILL_MAX)
		car.add_air(refill, refill, GRADES[g][3])
	var healed := 0.0
	if combat and pts > 0:
		healed = combat.heal(clampf(pts * HEAL_PER_POINT, 1.0, HEAL_MAX))
	score += pts
	tricks_landed += 1
	if pts > best_trick:
		best_trick = pts
		best_trick_name = trick_name
	_recent.append(trick_name)
	if _recent.size() > 5:
		_recent.pop_front()
	last = {"name": trick_name, "points": pts, "grade": g, "quality": quality, "refill": refill,
		"chain": chain_mult, "repeat": repeats > 0, "note": note, "bail": false, "chain_lost": false,
		"speed": fast, "kmh": speed * 3.6, "heal": healed}
	last_time = clock
	trick_landed.emit(last)


## Grinds (world/grinds.gd). Catching a rail lands whatever was going on
## in the air (the rail is the landing, graded by how lined up the car was);
## the grind itself banks when you leave it: points for time, length and
## every switch between nose grind, tail grind and bluntslide.
func grind_begin(style_name: String, align_err: float) -> void:
	var q := 1.0 - 0.5 * smoothstep(0.15, 1.0, align_err)
	if in_air:
		var t := _describe(false)
		var mode := _mode_min
		var top := _air_speed
		_reset_air()
		if t.points >= 120.0:
			_bank(t.name + " TO GRIND", t.points * CONTROL_MULT[mode], q, 1.0, "", top)
	else:
		_reset_air()
	_land = {}
	judging = false
	grinding = true
	_grind_parts = [style_name]
	_grind_t = 0.0


func grind_switch(style_name: String) -> void:
	if _grind_parts.size() < 5:
		_grind_parts.append(style_name)


func grind_end(time: float, length: float, speed: float) -> void:
	grinding = false
	live_name = ""
	live_points = 0
	_reset_air()
	if time < 0.15:
		return
	var pts := _grind_points(time, length)
	var name := " → ".join(_grind_parts)
	if length > 60.0:
		name += "  ·  LONG GRIND"
	# Longer grinds grade higher; a quick touch is CLEAN.
	_bank(name, pts, 0.6 + minf(time / 4.0, 0.35), 0.8, "%.1f s · %d m" % [time, roundi(length)], speed)


func _grind_points(time: float, length: float) -> float:
	var pts := time * 400.0 + length * 6.0 + (_grind_parts.size() - 1) * 300.0
	if _grind_parts.has("BLUNTSLIDE"):
		pts *= 1.2
	return pts


## Hitting an enemy is a ram, not a crash, however much speed it costs.
func ignore_crash(seconds: float) -> void:
	_no_crash_until = maxf(_no_crash_until, clock + seconds)


## Smashing scenery (world/destruction.gd): a few points, keeps a chain alive.
func smash_points(points: int) -> void:
	score += points
	if chain > 0:
		chain_left = maxf(chain_left, CHAIN_WINDOW * 0.5)


## A kill. Ram and flip kills are stunts: they bank like a trick (pop-up,
## chain, refill). Ray gun kills just add their points and keep the chain alive.
func combat_kill(points: int, how: String, kind: String) -> void:
	if how == "ram" or how == "flip":
		_bank("FLIP SMASH" if how == "flip" else "RAM KILL", points * 4.0, NEUTRAL_Q if how == "ram" else 0.85, 0.8,
			kind.to_upper(), car.linear_velocity.length())
	else:
		score += points
		if chain > 0:
			chain_left = maxf(chain_left, CHAIN_WINDOW * 0.5)


## The car was wrecked: like a crash, the chain is lost.
func wreck() -> void:
	_crash()
	_announce("WRECKED", true)


## A bail (down on the roof or side) loses the trick in progress but not
## the chain: its timer keeps running, so getting back on the wheels
## quickly keeps the streak alive.
func _bail(reason: String, announce := false) -> void:
	var had := in_air and live_points > 0
	_reset_air()
	_locked = true
	if had or announce:
		_announce(reason, false)


## A severe crash ends everything: the trick, the ride-out and the chain.
func _crash() -> void:
	var had := (in_air and live_points > 0) or judging or _ride > 0.6 or chain > 0
	_reset_air()
	_land = {}
	judging = false
	_ride = 0.0
	_ride_inv = false
	_locked = car.grounded_wheels < 3
	_vel_hist.clear()
	chain = 0
	chain_mult = 1.0
	chain_left = 0.0
	if had:
		_announce("CRASHED", true)


func _announce(reason: String, chain_lost: bool) -> void:
	last = {"name": reason, "points": 0, "grade": GRADES.size() - 1, "bail": true, "refill": 0.0, "chain": 1.0,
		"chain_lost": chain_lost}
	last_time = clock
	bailed.emit(reason)
