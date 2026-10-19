extends Node3D
## Entry point: sets up input, builds the level, spawns the car, camera,
## HUD and audio.
##
## Test mode (no window needed for logs, window needed for screenshots):
##   godot --path . -- --test=<scenario> [--shots=/some/dir] [--trim=thrust]
## Scenarios: drag, flip, loop, inverted, halfpipe, jump. Each spawns the car
## at its feature, drives a scripted input plan, prints telemetry, then quits.

const Car := preload("res://scripts/car.gd")
const Level := preload("res://scripts/level.gd")
const ChaseCamera := preload("res://scripts/chase_camera.gd")
const Hud := preload("res://scripts/hud.gd")
const CarAudio := preload("res://scripts/car_audio.gd")
const SkidMarks := preload("res://scripts/skid_marks.gd")
const GooTrail := preload("res://scripts/goo_trail.gd")
const Spores := preload("res://scripts/world/spores.gd")
const Ambience := preload("res://scripts/world/ambience.gd")
const Course := preload("res://scripts/track/course.gd")
const Tricks := preload("res://scripts/tricks.gd")
const Fx := preload("res://scripts/fx.gd")
const Sfx := preload("res://scripts/sfx.gd")
const AirPickups := preload("res://scripts/world/air_pickups.gd")
const Combat := preload("res://scripts/combat/combat.gd")
const Director := preload("res://scripts/enemies/director.gd")
const PauseMenu := preload("res://scripts/ui/pause_menu.gd")
const TouchControls := preload("res://scripts/ui/touch_controls.gd")
const Mag := preload("res://scripts/mag.gd")
const Bench := preload("res://scripts/bench.gd")
const WeaponCases := preload("res://scripts/world/weapon_cases.gd")
const Weapons := preload("res://scripts/combat/weapons.gd")
const Wildlife := preload("res://scripts/world/wildlife.gd")

var car: Car
var hud: Hud
var course: Course
var tricks: Tricks
var pickups: AirPickups
var fx: Fx
var sfx: Sfx
var cam: ChaseCamera
var combat: Combat
var director: Director
var cases: WeaponCases
var wildlife: Wildlife
var _boss_attack := ""
var _boss: Node = null
var _view_cam: Camera3D
var _show_at := Vector3.INF
var _scr_worst := 0.0

var _test := ""
var _start_thrust_trim := false
var _start_body := 0
var _start_infinite := false
var _force_pickups := false
var _jets_arg := -1
var _grind_rail_added := false
var _flip_at := -1.0
var _level: Node3D
var _menu: PauseMenu
var _shots_dir := ""
var _t := 0.0
var _next_log := 0.0
var _hit_100 := false
var _launched := false
var _loop_th := 0.0

# name: [spawn position, yaw (radians), duration (s), screenshot times]
const TESTS := {
	"drag": [Vector3(0, 0.6, 0), 0.0, 4.0, [1.2]],
	"flip": [Vector3(-120, 0.6, -300), 0.0, 11.0, [1.5, 2.6, 3.0, 5.0, 9.0]],
	"loop": [Vector3(150, 0.6, 140), 0.0, 9.0, [4.0, 4.6, 5.2]],
	"inverted": [Vector3(230, 0.6, 175), 0.0, 13.0, [3.9, 4.6, 5.4, 6.5, 8.0]],
	"halfpipe": [Vector3(-115, 0.6, 65), -PI / 2, 8.0, [3.5, 5.0]],
	# Flat out along the half-pipe, then hard into the wall: up it and out
	# into the air. Checks the camera keeps the car framed (scr = where the
	# car is on screen, 0,0 = centre, ±1 = edge).
	"halfpipe_air": [Vector3(-115, 0.6, 65), -PI / 2, 9.0, [3.4, 3.8, 4.2, 4.6, 5.0, 5.6, 6.4]],
	"jump": [Vector3(300, 0.6, 30), 0.0, 9.0, [3.0, 3.8, 4.6]],
	"drift": [Vector3(-300, 0.6, 200), -PI / 2, 14.0, [5.0, 6.5, 8.0]],
	"swap": [Vector3(0, 0.6, 0), 0.0, 6.0, [5.5]],
	"sidejet": [Vector3(-300, 0.6, 200), -PI / 2, 9.0, [4.0]],
	"fullair": [Vector3(-120, 0.6, -300), 0.0, 9.0, [3.0]],
	# Straight at the base of a tower: the curved bank should take the car
	# up the wall (a WALL RIDE).
	"wallride": [Vector3.ZERO, 0.0, 7.0, [1.6, 2.0, 2.4]],
	# A bush, rock and tree close by, then a rock and a tree further on,
	# hit at rising speeds.
	"megablock": [Vector3(72, 0.6, 287), 0.0, 8.0, [0.05, 1.4, 1.9, 2.3, 2.9, 3.6, 4.6]],
	# Explosions against a mega-block, then a tower brought down.
	"blast": [Vector3(80, 0.6, 290), 0.0, 8.0, [0.6, 1.2, 2.2, 3.0, 4.5, 6.5]],
	# Runs over a gorilla, spider and rex for biofuel, bounces off an
	# elephant too slowly, then flattens another at speed.
	"animals": [Vector3(-300, 0.6, 200), -PI / 2, 14.0, [2.3, 3.4, 4.6, 6.0, 12.0]],
	# A beast boss (BOSS=gorilla|rex|spider|elephant) against a fully armed
	# car circling it; logs its attacks, the hits and its health.
	"boss": [Vector3(-170, 0.6, 205), PI / 2, 45.0, [3.0, 6.0, 10.0, 15.0, 20.0, 26.0, 32.0, 40.0]],
	# Showcase: the four bosses and their animals lined up, a camera on each.
	"beasts": [Vector3(-120, 0.6, 205), PI / 2, 9.5, [2.0, 3.6, 5.1, 6.6, 8.1]],
	# Tyre trail (--car=bio|phantom, default Neon): speeds up from ~30 to
	# ~220 km/h in a wide arc, then a camera looks down on the whole trail.
	"trails": [Vector3(-300, 0.6, 200), -PI / 2, 9.0, [2.6, 4.6, 6.8, 7.8]],
	# Weapon cases hit slowly: at 8, 15 and 25 km/h, each should burst open.
	"cases": [Vector3(-300, 0.6, 200), -PI / 2, 18.0, []],
	"smash": [Vector3(-300, 0.6, 200), -PI / 2, 13.0, [2.2, 3.85, 6.55, 10.05, 11.3, 11.8]],
	# Hull stepped down (smoke, sparks, fire), then wrecked.
	"damage": [Vector3(-300, 0.6, 200), -PI / 2, 9.0, [1.8, 3.8, 5.8, 6.6, 6.9, 7.6]],
	# Teleports round the new world for screenshots (no driving).
	"tour": [Vector3(-300, 0.6, 200), -PI / 2, 15.5, [1.4, 2.9, 4.4, 5.9, 7.4, 8.9, 10.4, 11.9, 13.4, 14.9]],
	# Forward for 4 s, stop, then reverse for 4 s: reverse should match forward.
	"reverse": [Vector3(-300, 0.6, 200), -PI / 2, 14.0, []],
	# Jump onto a rail laid along the lane: nose grind, switch to tail, then
	# bluntslide, ride it off the end.
	"grind": [Vector3(-300, 0.6, 200), -PI / 2, 9.0, [3.3, 4.0, 4.9, 6.0, 6.5]],
	# Battery low, then a battery cell and an air canister down the lane.
	"battery": [Vector3(-300, 0.6, 200), -PI / 2, 9.0, [2.76, 2.86, 3.0, 3.4, 4.2, 5.6, 5.7, 5.95]],
	# Flat out into a kicker and over a speed bump run (should never crash),
	# with a chain going.
	"ramp": [Vector3(0, 0.6, -120), 0.0, 12.0, [2.0]],
	"flipkicker": [Vector3(40, 0.6, 10), 0.0, 12.0, [2.0]],
	# Flat out at a street kicker 20° off its axis (start placed in _ready).
	"streetramp": [Vector3.ZERO, 0.0, 9.0, [2.0]],
	# Parked with only the gun while the director spawns waves (soak test).
	"horde": [Vector3(-200, 0.6, 200), -PI / 2, 100.0, [30.0, 60.0, 90.0]],
	# Every weapon on the car (corners, seats, a few levelled), enemies all
	# round; the car drives a slow circle. Also drives through a weapon case.
	"arsenal": [Vector3(-200, 0.6, 200), -PI / 2, 14.0, [2.0, 4.0, 5.5, 7.0, 9.0, 11.0, 13.0]],
	# Enemies (BREAKUP=bee|roller|hopper, default all three) come at the
	# parked car through its guns: parts shot off, how they carry on.
	"breakup": [Vector3(-300, 0.6, 200), -PI / 2, 14.0, [3.0, 4.5, 6.0, 7.5, 9.0, 10.5, 12.0]],
	# One of each enemy ahead of the car; drive at them slowly, then stop.
	"enemies": [Vector3(-300, 0.6, 200), -PI / 2, 16.0, [1.0, 2.0, 3.0, 4.0, 5.5, 6.6, 7.2, 8.5, 9.5]],
	# A straight ram into one dummy, then a dodge front-flip into a second;
	# hits fired at the car mid-dodge (should be dodged) and later in the
	# flip (should be cut by the flip guard).
	"flipram": [Vector3(-300, 0.6, 200), -PI / 2, 10.0, [3.0, 6.0]],
	# A chain going, then flat out into the mesa wall: a severe crash ends it.
	"crash": [Vector3(65, 0.6, -150), 0.0, 5.0, [2.0]],
	# Flying (jump held), then the left stick forward: a front flip mid-flight.
	"flystick": [Vector3(-120, 0.6, -300), 0.0, 9.0, [2.5, 3.0]],
	# MAG: fly up ~30 m, then pull down onto three enemies (a slam), then a
	# small hop with MAG on (too low and slow to slam).
	"mag": [Vector3(-300, 0.6, 200), -PI / 2, 12.0, [4.7, 5.2, 5.5, 5.75, 5.85, 5.95, 6.15]],
	# MAG from 12 m off a tower wall, wheels toward it: pulled on, then clings.
	"magwall": [Vector3.ZERO, 0.0, 5.0, [0.4, 1.0, 2.0, 4.5]],
	# Jump at speed, a dodge front flip, then a jump + double jump.
	"hop": [Vector3(-300, 0.6, 200), -PI / 2, 10.0, [2.3, 4.6, 4.8, 7.6]],
	# Rocket League bindings: W held through a jump (no pitch), a fresh W in
	# the air (pitch), air roll, an A/D sideflip, and infinite air.
	"aircontrol": [Vector3(-300, 0.6, 200), -PI / 2, 13.0, [7.45]],
	"refill": [Vector3(-350, 0.6, 300), -PI / 2, 40.0, [6.0, 9.0]],
	# A dodge backflip, then a double jump with a barrel roll, then an air
	# tank pickup down the lane. Prints each trick, its grade and refill.
	"tricks": [Vector3(-300, 0.6, 200), -PI / 2, 12.0, [2.6, 4.35, 4.85, 5.3, 6.5, 8.9, 10.7]],
	# Spawns on the SKYWAY start line; an autopilot drives the full lap.
	"course": [Vector3.ZERO, 0.0, 150.0, [1.5, 10.6, 15.2, 16.0, 21.5, 25.0, 30.0, 38.0, 50.0, 55.0, 62.8, 68.0, 72.0]],
}
var _ap_idx := -1
var _air_t := 0.0
var _air_peak := 0.0
var _shot_times := []


func _init() -> void:
	_setup_input()
	Settings.init_bindings()
	# Scripted tests drive the car through Input.action_press only: unbind
	# every device, so a controller left plugged in (or keys pressed in
	# another window) can't nudge a test and make it unrepeatable.
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--test="):
			for action in InputMap.get_actions():
				if not String(action).begins_with("ui_"):
					InputMap.action_erase_events(action)


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--test="):
			_test = arg.trim_prefix("--test=")
			assert(TESTS.has(_test), "unknown test " + _test)
		elif arg == "--car=bio":
			_start_body = 1
		elif arg == "--car=phantom":
			_start_body = 2
		elif arg == "--trim=thrust":
			_start_thrust_trim = true
		elif arg == "--infinite":
			_start_infinite = true
		elif arg == "--pickups":
			_force_pickups = true
		elif arg.begins_with("--jets="):
			_jets_arg = ["auto", "hybrid", "full"].find(arg.trim_prefix("--jets="))
		elif arg.begins_with("--shots="):
			_shots_dir = arg.trim_prefix("--shots=")

	var level := Level.new()
	add_child(level)
	_level = level
	course = level.course

	car = Car.new()
	car.name = "Car"
	car.body_index = _start_body
	# Free roam starts on the SKYWAY start line.
	car.transform = course.start_xform()
	if _test != "":
		if _test != "course":
			car.transform = Transform3D(Basis(Vector3.UP, TESTS[_test][1]), TESTS[_test][0])
		_shot_times = TESTS[_test][3].duplicate()
	if _test == "wallride" or _test == "magwall":
		# The tallest tower with open ground in front of one of its faces.
		var best: Array = []
		for tw in level.city.towers:
			var r: Rect2 = tw[0]
			if tw[1] > 40.0 and r.size.x > 20.0:
				var c := Vector3(r.get_center().x, 0, r.get_center().y)
				var start := c + Vector3(r.size.x * 0.5 + 45.0, 0.6, 0)
				var q := PhysicsRayQueryParameters3D.create(start + Vector3.UP, c + Vector3(r.size.x * 0.5 + 6.0, 1.0, 0), 1)
				if level.get_world_3d().direct_space_state.intersect_ray(q).is_empty():
					best = [start, c]
					break
		if not best.is_empty() and _test == "magwall":
			# 12 m out from the face and 15 m up, wheels toward the wall.
			var face: Vector3 = best[0] - Vector3(45.0, 0.6, 0)
			car.transform = Transform3D(Basis(Vector3.UP, Vector3.RIGHT, Vector3.FORWARD), face + Vector3(12.0, 15.0, 0))
		elif not best.is_empty():
			car.transform = Transform3D(Basis(Vector3.UP, PI * 0.5), best[0])
	if _test == "streetramp":
		var rs: Array = level.ramp_spots[3]
		var dir := Basis(Vector3.UP, rs[1] + deg_to_rad(20.0)) * Vector3.FORWARD
		var at: Vector3 = rs[0] - dir * 70.0
		car.transform = Transform3D(Basis(Vector3.UP, rs[1] + deg_to_rad(20.0)), Vector3(at.x, 0.6, at.z))
	add_child(car)
	course.car = car
	car.respawn_hook = _respawn
	if _start_thrust_trim:
		car.apply_trim(Car.Trim.THRUST)
	car.infinite_air = _start_infinite
	if _test != "":
		car.jet_mode = Car.JetMode.AUTO   # the scripted scenarios were written for the flight computer
	if _jets_arg >= 0:
		car.jet_mode = _jets_arg as Car.JetMode
	if _test == "" and not Settings.bench and not DisplayServer.get_name() == "headless" and not OS.has_feature("web"):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED   # mouse looks around; Esc frees it

	var skids := SkidMarks.new()
	add_child(skids)
	car.skids = skids
	var goo := GooTrail.new()
	add_child(goo)
	car.goo = goo

	cam = ChaseCamera.new()
	cam.target = car
	add_child(cam)

	tricks = Tricks.new()
	tricks.car = car
	tricks.course = course
	add_child(tricks)
	pickups = AirPickups.new()
	pickups.car = car
	add_child(pickups)
	if _test == "" or _force_pickups:
		pickups.place_all(level)       # tests keep their lanes and tank readings clean
	fx = Fx.new()
	fx.car = car
	fx.tricks = tricks
	fx.camera = cam
	add_child(fx)
	sfx = Sfx.new()
	sfx.car = car
	add_child(sfx)

	var layer := CanvasLayer.new()
	add_child(layer)
	hud = Hud.new()
	hud.car = car
	hud.course = course
	hud.tricks = tricks
	layer.add_child(hud)
	hud.visible = Settings.get_value("show_hud") and OS.get_environment("NOHUD") != "1"   # NOHUD=1: clean screenshots
	Settings.changed.connect(_on_setting)
	_menu = PauseMenu.new()
	_menu.restart_run = func() -> void: course.restart()
	_menu.recover_car = _respawn
	add_child(_menu)
	var touch_layer := CanvasLayer.new()
	touch_layer.layer = 10
	add_child(touch_layer)
	var touch := TouchControls.new()
	touch.car = car
	touch.cam = cam
	touch.open_menu = _menu.open
	touch_layer.add_child(touch)
	_connect_style()

	combat = Combat.new()
	combat.car = car
	combat.tricks = tricks
	combat.fx = fx
	combat.sfx = sfx
	combat.hud = hud
	combat.respawn = _respawn
	add_child(combat)
	director = Director.new()
	director.car = car
	director.combat = combat
	director.enabled = _test == "" or _test == "horde"   # other scripted tests stay enemy-free
	add_child(director)
	combat.director = director
	tricks.combat = combat
	if _test == "tricks" or _test == "drift":
		combat.hp = 50.0                    # so the heal from tricks shows
	level.destruction.setup(level.city)
	level.destruction.setup_entries(level.course.destructibles)
	level.destruction.debris = level.wrecking.debris
	level.wrecking.car = car
	level.wrecking.debris.car = car
	level.wrecking.tricks = tricks
	level.wrecking.fx = fx
	level.wrecking.sfx = sfx
	level.wrecking.pickups = pickups
	level.wrecking.destruction = level.destruction
	combat.wrecking = level.wrecking
	var mag := Mag.new()
	mag.car = car
	mag.fx = fx
	mag.sfx = sfx
	mag.combat = combat
	mag.tricks = tricks
	mag.wrecking = level.wrecking
	add_child(mag)
	hud.mag = mag
	level.destruction.car = car
	level.destruction.tricks = tricks
	level.destruction.fx = fx
	level.destruction.sfx = sfx
	hud.combat = combat
	hud.director = director

	# Weapon cases round the world (free play; tests that want them place their own).
	cases = WeaponCases.new()
	cases.name = "WeaponCases"
	cases.car = car
	cases.arsenal = combat.arsenal
	cases.fx = fx
	cases.sfx = sfx
	cases.hud = hud
	cases.tricks = tricks
	cases.debris = level.wrecking.debris
	add_child(cases)
	if _test == "" or _force_pickups:
		cases.place_all(level)
	level.wrecking.tower_down.connect(cases.drop_in)

	# Animals in their territories, and the beast bosses that rule them
	# (free play; the boss and animals tests set up their own).
	wildlife = Wildlife.new()
	wildlife.name = "Wildlife"
	wildlife.car = car
	wildlife.combat = combat
	wildlife.director = director
	wildlife.fx = fx
	wildlife.sfx = sfx
	wildlife.hud = hud
	wildlife.tricks = tricks
	wildlife.cases = cases
	wildlife.debris = level.wrecking.debris
	add_child(wildlife)
	if _test == "":
		wildlife.setup(level)
	else:
		wildlife.city = level.city
		wildlife.spawn_bosses = false
		wildlife.set_physics_process(_test == "animals" or _test == "boss")
		if _test == "animals" or _test == "boss":
			wildlife.biofuel.connect(func(k: String, a: float) -> void: print(">>> t=%.2f BIOFUEL %s +%.0f%%  battery %.1f%%  at %.0f km/h" % [_t, k, a * 100.0, car.battery * 100.0, car.linear_velocity.length() * 3.6]))
			wildlife.boss_down.connect(func(b: Node) -> void: print(">>> t=%.2f BOSS DOWN %s  (+%d)" % [_t, b.boss_name, b.points]))

	# The skatepark world: grinds drive the car on rails, hoops score.
	level.grinds.setup(car, tricks, fx, sfx)
	level.park.car = car
	level.park.tricks = tricks
	level.park.fx = fx
	level.park.sfx = sfx
	if _test == "" or _force_pickups:
		for spot in level.park.pickup_spots:
			pickups.spawn(spot[0] + Vector3.UP * 1.2, spot[1])
		for spot in level.wrecking.pickup_spots:
			pickups.spawn(spot[0], spot[1])
	if _test != "":
		combat.player_hurt.connect(func(a: float) -> void: print(">>> t=%.2f HURT %.0f  hull %.0f" % [_t, a, combat.hp]))
		combat.enemy_killed.connect(func(e: Node, how: String) -> void: print(">>> t=%.2f KILL %s (size %.2f) by %s  kills %d" % [_t, e.kind, e.size, how, combat.kills]))
		cases.opened.connect(func(id: String, slot: String, lvl: int, rep: String) -> void: print(">>> t=%.2f CASE %s -> %s level %d %s" % [_t, id, slot, lvl, rep]))
		combat.player_wrecked.connect(func() -> void: print(">>> t=%.2f WRECKED" % _t))
		combat.part_lost.connect(func(e: Node, tag: String) -> void: print(">>> t=%.2f PART %s lost a %s  (hp %.0f/%.0f, %d parts left)" % [_t, e.kind, tag, e.hp, e.max_hp, e.parts.size()]))
		level.grinds.grind_started.connect(func(st: int) -> void: print(">>> t=%.2f GRIND START %s  v=%.0f km/h  at %s on a %s (%d points)" % [_t, level.grinds.NAMES[st], car.speed * 3.6,
			car.global_position.snapped(Vector3.ONE * 0.1), level.grinds._rail.kind, level.grinds._rail.pts.size()]))
		level.grinds.grind_switched.connect(func(st: int) -> void: print(">>> t=%.2f GRIND SWITCH %s" % [_t, level.grinds.NAMES[st]]))
		level.grinds.grind_ended.connect(func(tm: float, ln: float) -> void: print(">>> t=%.2f GRIND END %.2f s %.0f m" % [_t, tm, ln]))
		level.wrecking.smashed.connect(func(w: String, at: Vector3) -> void: print(">>> t=%.2f WRECK %s at %s  v=%.0f km/h" % [_t, w, at.snapped(Vector3.ONE * 0.1), car.linear_velocity.length() * 3.6]))
		level.destruction.smashed_object.connect(func(k: String, o: String, sp: float) -> void: print(">>> t=%.2f SMASH %s %s at %.0f km/h" % [_t, k, o, sp * 3.6]))
		combat.enemy_rammed.connect(func(e: Node, d: float, f: bool) -> void: print(">>> t=%.2f %s %s for %.0f  (at %.0f km/h, spin %.1f rad/s)" % [_t, "FLIP HIT" if f else "RAM", e.kind, d, car.linear_velocity.length() * 3.6, car.angular_velocity.length()]))
		combat.player_dodged.connect(func() -> void: print(">>> t=%.2f DODGED" % _t))
		car.mag_slam.connect(func(at: Vector3, _n: Vector3, pw: float, r: float) -> void: print(">>> t=%.2f MAG SLAM power %.2f radius %.1f m at %s" % [_t, pw, r, at.snapped(Vector3.ONE * 0.1)]))

	var audio := CarAudio.new()
	audio.car = car
	add_child(audio)

	var spores := Spores.new()
	spores.target = car
	add_child(spores)
	add_child(Ambience.new())
	if Settings.bench:
		var bench := Bench.new()
		bench.main = self
		add_child(bench)


## Pickups and tricks drive the effects, sounds and HUD pop-ups.
func _connect_style() -> void:
	pickups.collected.connect(func(kind: int, amount: float, _pos: Vector3, airborne: bool) -> void:
		var what: String = AirPickups.NAMES[kind] + " AIR"
		if kind == AirPickups.Kind.ROCKET and car.trim != Car.Trim.ROCKET:
			what = "THRUST AIR"
			amount *= 0.5
		elif kind == AirPickups.Kind.BATTERY:
			what = "BATTERY"
		var c: Color = AirPickups.COLORS[kind]
		fx.pickup_absorb(kind, c)
		if kind == AirPickups.Kind.BATTERY:
			sfx.charge()
		else:
			sfx.pickup(kind == AirPickups.Kind.ROCKET)
		hud.notify("+%d%% %s%s" % [roundi(amount * 100.0), what, "   ·   MID-AIR GRAB" if airborne else ""], c.lightened(0.3))
		tricks.on_grab())
	tricks.trick_landed.connect(func(t: Dictionary) -> void:
		sfx.landed(t.grade, t.points)
		if t.grade <= 1 or t.points >= 1500:
			hud.flash(Tricks.GRADES[t.grade][3], clampf(0.4 + t.points / 4000.0, 0.4, 1.0)))
	tricks.rotation_done.connect(func(_kind: String, count: int) -> void: sfx.rotation(count))
	tricks.bailed.connect(func(_reason: String) -> void:
		sfx.bail()
		if tricks.last.get("chain_lost", false):
			hud.flash(Color(1.0, 0.3, 0.25), 0.5))
	if _test != "":
		tricks.touchdown.connect(func(g: int, q: float) -> void:
			print(">>> t=%.2f TOUCHDOWN %s (%.2f)" % [_t, Tricks.GRADES[g][1], q]))
		tricks.trick_landed.connect(func(t: Dictionary) -> void:
			print(">>> t=%.2f TRICK %s  %s  +%d  q=%.2f  refill %d%%  chain x%.2f  speed x%.2f  heal +%.1f -> hull %.0f" % [_t, t.name, Tricks.GRADES[t.grade][1],
				t.points, t.quality, roundi(t.refill * 100.0), t.chain, t.speed, t.get("heal", 0.0), combat.hp]))
		tricks.bailed.connect(func(r: String) -> void: print(">>> t=%.2f %s  chain %s" % [_t, r,
			"LOST" if tricks.last.get("chain_lost", false) else "kept"]))
		pickups.collected.connect(func(kind: int, _a: float, _p: Vector3, _air: bool) -> void:
			print(">>> t=%.2f PICKUP %s  thrust %d%%  rocket %d%%  battery %d%%" % [_t, AirPickups.NAMES[kind], car.thrust_tank * 100, car.rocket_tank * 100, car.battery * 100]))
	if _test == "tricks":
		car.thrust_tank = 0.5
		car.rocket_tank = 0.5


func _process(_delta: float) -> void:
	# Grass bends away from the car.
	RenderingServer.global_shader_parameter_set("car_pos", car.get_global_transform_interpolated().origin)


func _on_setting(key: String) -> void:
	match key:
		"show_hud":
			hud.visible = Settings.get_value("show_hud")
		"show_help":
			hud.show_help = Settings.get_value("show_help")
		"camera":
			cam.preset = Settings.get_value("camera")


func level_grinds() -> Node:
	return _level.grinds


## Backspace: back to the last checkpoint during a run, else to the start line.
func _respawn() -> void:
	car.request_reset_to(course.respawn_xform())


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE:
		# Esc: pause menu (resume, settings, quit).
		get_viewport().set_input_as_handled()
		_menu.open()
	elif event is InputEventMouseButton and event.pressed and _test == "" and not Settings.touch_mode and not Settings.bench:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event.is_action_pressed("restart_run"):
		course.restart()
	elif event.is_action_pressed("help"):
		hud.show_help = not hud.show_help
	elif event is InputEventKey and event.pressed and event.physical_keycode == KEY_F11:
		Settings.toggle_fullscreen()


# ------------------------------------------------------------------ input map

func _setup_input() -> void:
	# Rocket League layout. Controller: RT/LT drive, left stick steers (and
	# pitches/yaws in the air), A jump, B boost, X powerslide + air roll,
	# LB/RB air roll, right stick looks around, R3 looks back, Y camera.
	# Keyboard + mouse: WASD, Space/RMB jump, LMB/Ctrl boost, Shift
	# powerslide + air roll, Q/E air roll, mouse looks around.
	_action("throttle", [KEY_W], [], [[JOY_AXIS_TRIGGER_RIGHT, 1.0]])
	_action("brake", [KEY_S], [], [[JOY_AXIS_TRIGGER_LEFT, 1.0]])
	_action("steer_left", [KEY_A], [], [[JOY_AXIS_LEFT_X, -1.0]])
	_action("steer_right", [KEY_D], [], [[JOY_AXIS_LEFT_X, 1.0]])
	# Air pitch: left stick (push forward = nose down), W/S on the keyboard.
	_action("air_nose_down", [], [], [[JOY_AXIS_LEFT_Y, -1.0]])
	_action("air_nose_up", [], [], [[JOY_AXIS_LEFT_Y, 1.0]])
	_action("kb_nose_down", [KEY_W], [])
	_action("kb_nose_up", [KEY_S], [])
	_action("air_roll_left", [KEY_Q], [JOY_BUTTON_LEFT_SHOULDER])
	_action("air_roll_right", [KEY_E], [JOY_BUTTON_RIGHT_SHOULDER])
	# Arrows: the old flip stick (pitch/roll in the air; side push, press
	# down and hop on the road). Still there for anyone who likes it.
	_action("flip_forward", [KEY_UP], [])
	_action("flip_back", [KEY_DOWN], [])
	_action("roll_left", [KEY_LEFT], [])
	_action("roll_right", [KEY_RIGHT], [])
	_action("lift", [KEY_SPACE], [JOY_BUTTON_A], [], [MOUSE_BUTTON_RIGHT])
	_action("boost", [KEY_CTRL], [JOY_BUTTON_B], [], [MOUSE_BUTTON_LEFT])
	_action("handbrake", [KEY_SHIFT, KEY_C], [JOY_BUTTON_X])
	_action("jet_assist", [KEY_Z], [JOY_BUTTON_LEFT_STICK])
	# Look back stays on the keyboard and mouse; on a controller the right
	# stick pulled down already looks behind, and R3 is MAG.
	_action("look_back", [KEY_B], [], [], [MOUSE_BUTTON_MIDDLE])
	_action("mag", [KEY_M], [JOY_BUTTON_RIGHT_STICK], [], [MOUSE_BUTTON_XBUTTON1])
	_action("look_left", [], [], [[JOY_AXIS_RIGHT_X, -1.0]])
	_action("look_right", [], [], [[JOY_AXIS_RIGHT_X, 1.0]])
	_action("look_up", [], [], [[JOY_AXIS_RIGHT_Y, -1.0]])
	_action("look_down", [], [], [[JOY_AXIS_RIGHT_Y, 1.0]])
	_action("camera", [KEY_V], [JOY_BUTTON_Y])
	_action("assist_tc", [KEY_1], [])
	_action("assist_abs", [KEY_2], [])
	_action("assist_esc", [KEY_3], [])
	_action("assist_drift", [KEY_4], [])
	_action("fans", [KEY_F], [])
	_action("swap_trim", [KEY_T], [JOY_BUTTON_DPAD_LEFT])
	_action("swap_car", [KEY_G], [JOY_BUTTON_BACK])
	_action("xray", [KEY_X], [])
	_action("jet_mode", [KEY_TAB], [JOY_BUTTON_DPAD_UP])
	_action("infinite_air", [KEY_I], [JOY_BUTTON_DPAD_RIGHT])
	_action("reset", [KEY_R], [JOY_BUTTON_START])
	_action("respawn", [KEY_BACKSPACE], [JOY_BUTTON_DPAD_DOWN])
	_action("restart_run", [KEY_ENTER, KEY_KP_ENTER], [JOY_BUTTON_MISC1])
	_action("help", [KEY_F1, KEY_H], [])


func _action(action: String, keys: Array, buttons: Array, axes: Array = [], mouse: Array = []) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.15)
	for k in keys:
		var e := InputEventKey.new()
		e.physical_keycode = k
		InputMap.action_add_event(action, e)
	for btn in buttons:
		var e := InputEventJoypadButton.new()
		e.button_index = btn
		InputMap.action_add_event(action, e)
	for ax in axes:
		var e := InputEventJoypadMotion.new()
		e.axis = ax[0]
		e.axis_value = ax[1]
		InputMap.action_add_event(action, e)
	for mb in mouse:
		var e := InputEventMouseButton.new()
		e.button_index = mb
		InputMap.action_add_event(action, e)


# ------------------------------------------------------------------ test scenarios

func _plan(t: float) -> Dictionary:
	var v: float = car.speed * 3.6
	var airborne: bool = car.grounded_wheels == 0
	match _test:
		"drag":
			return {"throttle": 1.0 if t > 0.5 else 0.0, "boost": 1.0 if t > 0.5 else 0.0}
		"flip":
			# Pop up, front flip, barrel roll, then let it come down on its own.
			return {
				"lift": 1.0 if t > 0.5 and t < 1.6 else (0.5 if t < 6.0 and t > 0.5 else 0.0),
				"flip_forward": 1.0 if t > 1.8 and t < 3.0 else 0.0,
				"roll_right": 1.0 if t > 4.2 and t < 5.0 else 0.0,
			}
		"loop":
			# Corkscrew loop (r 10, start z 40, drifts 10.5 m to +X per turn):
			# steer to follow its centre line, as a driver would.
			var p: Vector3 = car.global_position
			var steer := 0.0
			if p.z < 40.0 or _loop_th > 0.0:
				_loop_th = maxf(_loop_th, fposmod(atan2(40.0 - p.z, 10.0 - p.y), TAU) if _loop_th < TAU - 0.3 else TAU)
				var target_x := 150.0 + 10.5 * _loop_th / TAU
				var vel: Vector3 = car.linear_velocity
				var want_vx := 10.5 / (TAU * 10.0) * vel.length() if _loop_th < TAU - 0.2 else 0.0
				steer = clampf(0.4 * (target_x - p.x) + 2.0 * (want_vx - vel.x) / maxf(vel.length(), 1.0), -1.0, 1.0)
			return {"throttle": 1.0 if v < 95.0 else 0.4, "steer_right": maxf(steer, 0.0), "steer_left": maxf(-steer, 0.0)}
		"inverted":
			# Full send up the inverted ramp, then hands off: jets right the car.
			if airborne and car.global_position.y > 4.0:
				_launched = true
			return {"throttle": 0.0 if _launched else 1.0, "boost": 1.0 if not _launched and v < 150.0 else 0.0}
		"halfpipe":
			return {"throttle": 1.0 if v < 70.0 else 0.3, "steer_left": 0.45 if t > 2.0 and t < 3.2 else 0.0}
		"drift":
			# Build speed, flick in with the handbrake, then hold the drift
			# on throttle while the drift assist counter-steers.
			return {
				"throttle": 1.0 if t < 3.0 else (0.0 if t < 4.0 else 0.7),
				"steer_left": 1.0 if t > 3.4 and t < 4.0 else (0.3 if t > 4.0 and t < 10.0 else 0.0),
				"handbrake": 1.0 if t > 3.5 and t < 3.9 else 0.0,
			}
		"swap":
			# Switch body while parked, then drive off and slide a little.
			return {"swap_car": 1.0 if t > 1.0 and t < 1.05 else 0.0, "throttle": 1.0 if t > 1.5 else 0.0,
				"steer_left": 0.6 if t > 3.5 else 0.0}
		"sidejet":
			# Cruise, then fire the right side jets, then press down with the jets.
			return {"throttle": 1.0 if v < 90.0 else 0.4, "roll_right": 1.0 if t > 3.0 and t < 4.5 else 0.0,
				"flip_back": 1.0 if t > 5.5 and t < 7.0 else 0.0}
		"flipram":
			if t > 0.3 and t - get_physics_process_delta_time() <= 0.3:
				for x in [-240.0, -150.0]:
					var e: Node = director.spawn("roller", Vector3(x, 1.3, 200), 1.2)
					e.ai = false                        # a dummy: no AI, just a body
					e.max_hp = 5000.0
					e.hp = 5000.0
			combat.arsenal.enabled = false
			var px: float = car.global_position.x
			if _flip_at < 0.0 and px > -150.0 - 13.0:
				_flip_at = t
			var out := {"throttle": 1.0 if v < 70.0 else 0.2}
			if _flip_at > 0.0:
				var ft := t - _flip_at
				out["lift"] = 1.0 if ft < 0.05 or (ft > 0.14 and ft < 0.19) else 0.0
				out["flip_forward"] = 1.0 if ft > 0.12 and ft < 0.3 else 0.0
				if ft > 0.24 and ft - get_physics_process_delta_time() <= 0.24:
					var before: float = combat.hp
					combat.invuln = 0.0
					combat.damage_player(20.0, car.global_position + Vector3.FORWARD * 3.0, "test")
					print(">>> t=%.2f hit 20 mid-dodge: hull %.0f -> %.0f" % [t, before, combat.hp])
				if ft > 0.62 and ft - get_physics_process_delta_time() <= 0.62:
					var before2: float = combat.hp
					combat.invuln = 0.0
					combat.damage_player(20.0, car.global_position + Vector3.FORWARD * 3.0, "test")
					print(">>> t=%.2f hit 20 late in the flip (spin %.1f rad/s, flip %.2f, dodging %s, dodge_t %.2f): hull %.0f -> %.0f" % [t, car.angular_velocity.length(), combat.flip_amount(), combat.dodging(), car._dodge_t, before2, combat.hp])
			return out
		"arsenal":
			if t > 0.2 and t - get_physics_process_delta_time() <= 0.2:
				car.apply_trim(Car.Trim.THRUST)          # both seats: six mounts
				for id in ["tesla", "plasma", "swarm", "rocket", "sniper", "deagle", "tesla"]:
					var res: Array = combat.arsenal.add_weapon(id)
					print(">>> %s -> %s  level %d%s" % [id, res[0], res[1], "  (replaced %s)" % res[2] if res[2] != "" else ""])
				cases.add_case(car.global_position - car.global_basis.z * 30.0 + Vector3(0, -0.6, 0), "large", false)
			if t > 1.0 and fmod(t, 2.0) < get_physics_process_delta_time() and director.enemies.size() < 10:
				for k in 3:
					var a := randf() * TAU
					director.spawn(["bee", "roller", "hopper"][k], car.global_position + Vector3(cos(a), 0, sin(a)) * randf_range(25.0, 40.0) + Vector3.UP * (8.0 if k == 0 else 1.0), randf_range(0.9, 1.4))
			combat.invuln = 1.0
			if OS.has_environment("CLOSEUP"):
				cam.preset = 1                         # close chase view for a look at the mounts
				cam._look = Vector2(2.4, 0.35)
				cam._mouse_look = Vector2(2.4, 0.35)
				cam._mouse_idle = 0.0
				return {}
			return {"throttle": 1.0 if v < 30.0 else 0.0, "steer_left": 0.35 if t > 3.0 else 0.0}
		"enemies":
			if t > 0.4 and t - get_physics_process_delta_time() <= 0.4:
				var fwd: Vector3 = -car.global_basis.z
				var side: Vector3 = car.global_basis.x
				var p0: Vector3 = car.global_position
				director.spawn("bee", p0 + fwd * 35.0 + Vector3.UP * 8.0, 1.0)
				director.spawn("roller", p0 + fwd * 50.0 + side * 4.0 + Vector3.UP * 1.5, 1.2)
				director.spawn("hopper", p0 + fwd * 28.0 - side * 6.0 + Vector3.UP * 0.5, 1.0)
				director.spawn("hopper", p0 + fwd * 60.0 + Vector3.UP * 0.5, 1.5)
			# Gun off for the first 6 s: let them come, ram what's ahead.
			combat.arsenal.enabled = t > 6.0
			return {"throttle": 1.0 if v < 60.0 and t < 9.0 else 0.0, "brake": 1.0 if t > 9.0 else 0.0}
		"breakup":
			if t > 0.4 and t - get_physics_process_delta_time() <= 0.4:
				var fwd: Vector3 = -car.global_basis.z
				var side: Vector3 = car.global_basis.x
				var p0: Vector3 = car.global_position
				var kinds := OS.get_environment("BREAKUP").split(",") if OS.has_environment("BREAKUP") else PackedStringArray(["bee", "roller", "hopper"])
				for i in kinds.size():
					var k := kinds[i]
					var e: Node = director.spawn(k, p0 + fwd * (30.0 + i * 6.0) + side * (i - 1) * 7.0 + Vector3.UP * (7.0 if k == "bee" else 1.0), 1.4)
					e.max_hp *= 4.0                    # tough, so there's time to shoot bits off
					e.hp = e.max_hp
			combat.invuln = 1.0
			# A camera off to the side on the first one still going.
			if not director.enemies.is_empty():
				if _view_cam == null:
					_view_cam = Camera3D.new()
					_view_cam.fov = 50.0
					add_child(_view_cam)
					_view_cam.current = true
				var ep: Vector3 = director.enemies[0].global_position
				var cp: Vector3 = car.global_position
				var across := (ep - cp).cross(Vector3.UP).normalized()
				var eye := ep.lerp(cp, 0.35) + across * (6.0 + ep.distance_to(cp) * 0.4) + Vector3.UP * 3.0
				_view_cam.global_position = _view_cam.global_position.lerp(eye, 0.1) if _view_cam.global_position != Vector3.ZERO else eye
				_view_cam.look_at(ep.lerp(cp, 0.2) + Vector3.UP)
			if fmod(t, 2.0) < get_physics_process_delta_time():
				for e in director.enemies:
					print(">>> t=%.1f %s hp %.0f/%.0f  lost %s  v %.1f m/s  y %.1f" % [t, e.kind, e.hp, e.max_hp, e._lost, e.linear_velocity.length(), e.global_position.y])
			return {}
		"smash":
			if t < 0.05 and not _grind_rail_added:
				_grind_rail_added = true
				var city = _level.city
				var d = _level.destruction
				# [kind, model, x, scale, z]; the slow tree is just off the line so
				# the car clips it (a shake) and carries on.
				for o in [["bush", "bush.glb", -282.0, 1.2, 200.0], ["rock", "rubble.glb", -268.0, 1.4, 200.0],
						["tree", "tree_broad.glb", -245.0, 1.1, 201.5], ["rock", "rubble.glb", -200.0, 1.4, 200.0],
						["tree", "tree_tall.glb", -160.0, 1.2, 200.0]]:
					d.add_object(o[0], city.merged_mesh("res://assets/world/" + o[1], 8.0),
						Transform3D(Basis().scaled(Vector3.ONE * o[3]), Vector3(o[2], 0, o[4])))
				# Then a weapon case and a crate stack to burst through at speed.
				cases.add_case(Vector3(-125, 0, 200), "medium", false)
				_level.wrecking._crate_stack(Vector3(-100, 0, 200), 2, 2)
			# Hold ~30 km/h for the bush, ~40 for the first rock, ~22 for the
			# first tree (it should only shake), then flat out.
			var x: float = car.global_position.x
			var want := 999.0
			if x < -276.0:
				want = 30.0
			elif x < -258.0:
				want = 40.0
			elif x < -238.0:
				want = 22.0
			# Back onto the line after the clipped tree (rubble nudges the car).
			var dz: float = car.global_position.z - 200.0 if x > -236.0 else 0.0
			return {"throttle": 1.0 if v < want else 0.0, "brake": clampf((v - want) / 20.0, 0.0, 1.0),
				"steer_left": clampf(dz * 0.4, 0.0, 1.0), "steer_right": clampf(-dz * 0.4, 0.0, 1.0)}
		"blast":
			var w = _level.wrecking
			var dt := get_physics_process_delta_time()
			for at: float in [0.5, 1.0, 1.5, 2.0]:
				if t >= at and t - dt < at:
					var p := Vector3(72.0 + (at - 0.5) * 8.0, 2.5 + (at - 0.5) * 4.0, 245.5)
					fx.big_blast(p)
					w.explode(p, 7.0, 9.0)
			if t >= 2.5 and t - dt < 2.5:
				# The nearest tower: hammered until it comes down.
				var best: Node = null
				var bd := INF
				for k in w._towers:
					var r: Rect2 = w._towers[k].rect
					var dd := Vector2(80, 290).distance_to(r.get_center())
					if dd < bd:
						bd = dd
						best = k
				print(">>> tower at %.0f m, hp %.0f" % [bd, w._towers[best].hp])
				for n in 5:
					w.damage_tower(best, 700.0, (best as Node3D).global_position, Vector3.UP * 4.0)
			return {}
		"animals":
			if t < 0.05 and not _grind_rail_added:
				_grind_rail_added = true
				for o in [["gorilla", -282.0, 200.0], ["spider", -268.0, 200.5], ["rex", -254.0, 199.5],
						["elephant", -238.0, 201.0], ["elephant", -165.0, 195.0]]:
					var c := wildlife.spawn_critter(o[0], Vector3(o[1], 0, o[2]))
					c.set_process(false)           # hold still for the test
					c.rotation.y = PI * 0.5
				car.battery = 0.3                  # so the biofuel shows
			var x: float = car.global_position.x
			if car.linear_velocity.x < -1.0 and _flip_at < 0.0:
				_flip_at = t                       # bounced off the elephant
			if _flip_at > 0.0 and t < _flip_at + 1.6:
				return {"brake": 1.0}              # back off to go round it
			var want := 32.0 if x < -232.0 and _flip_at < 0.0 else 999.0
			var lane := 200.0 if _flip_at < 0.0 else 195.0
			var dz: float = car.global_position.z - lane
			return {"throttle": 1.0 if v < want else 0.0, "brake": clampf((v - want) / 20.0, 0.0, 1.0),
				"steer_left": clampf(dz * 0.4, 0.0, 1.0), "steer_right": clampf(-dz * 0.4, 0.0, 1.0)}
		"cases":
			if t < 0.05 and not _grind_rail_added:
				_grind_rail_added = true
				for o in [[-285.0, "small"], [-262.0, "medium"], [-235.0, "large"]]:
					cases.add_case(Vector3(o[0], 0, 200), o[1], false)
			var cx: float = car.global_position.x
			var want := 8.0 if cx < -282.0 else (15.0 if cx < -258.0 else 25.0)
			return {"throttle": 1.0 if v < want else 0.0, "brake": clampf((v - want) / 10.0, 0.0, 1.0)}
		"trails":
			# 40 km/h, then 100, then flat out, weaving gently down the open
			# lane, filmed from the side by a camera tracking just behind.
			var x: float = car.global_position.x
			if _view_cam == null:
				_view_cam = Camera3D.new()
				_view_cam.fov = 60.0
				_view_cam.far = 2000.0
				add_child(_view_cam)
				_view_cam.current = true
			var cp: Vector3 = car.global_position
			_view_cam.look_at_from_position(Vector3(cp.x - 12.0, 13.0, cp.z - 7.0), Vector3(cp.x - 13.0, 0.0, cp.z))
			if x > -40.0:
				return {"brake": 1.0}
			var want := 40.0 if x < -262.0 else (100.0 if x < -200.0 else 999.0)
			var weave := sin(t * 1.6) * 0.18
			var dz: float = cp.z - 200.0
			var st := weave - dz * 0.08
			return {"throttle": 1.0 if v < want else 0.0, "brake": clampf((v - want) / 30.0, 0.0, 0.6),
				"steer_left": clampf(-st, 0.0, 1.0), "steer_right": clampf(st, 0.0, 1.0),
				"boost": 1.0 if want > 500.0 else 0.0}
		"beasts":
			var dt := get_physics_process_delta_time()
			var kinds := ["gorilla", "rex", "spider", "elephant"]
			if t >= 0.1 and t - dt < 0.1:
				# Open sky over a 60 x 120 m patch of flat ground for the line-up.
				var space := get_world_3d().direct_space_state
				for cx in range(-360, 361, 40):
					for cz in range(-360, 361, 40):
						var ok := true
						for ox in [-30, 0, 30]:
							for oz in [-60, -30, 0, 30, 60]:
								var p := Vector3(cx + ox, 0.5, cz + oz)
								if not space.intersect_ray(PhysicsRayQueryParameters3D.create(p, p + Vector3.UP * 120.0)).is_empty():
									ok = false
								var g := space.intersect_ray(PhysicsRayQueryParameters3D.create(p + Vector3.UP * 3.0, p + Vector3.DOWN * 3.0))
								if g.is_empty() or absf(g.position.y) > 0.3:
									ok = false
						if ok and _show_at == Vector3.INF:
							_show_at = Vector3(cx, 0, cz)
				print(">>> line-up at ", _show_at)
				_level.destruction.remove_in(Rect2(_show_at.x - 40.0, _show_at.z - 80.0, 70.0, 150.0), -1.0)
				for i in 4:
					var z := _show_at.z - 45.0 + i * 30.0
					var b := wildlife.spawn_boss(kinds[i], Vector3(_show_at.x - 15.0, 0, z))
					b.ai = false
					b.rotation.y = -PI * 0.5
					for k in 3:
						var c := wildlife.spawn_critter(kinds[i], Vector3(_show_at.x + 3.0 + k * 4.0, 0, z + 6.0 + k * 2.0))
						c.set_process(false)
						c.rotation.y = -PI * 0.5
				_view_cam = Camera3D.new()
				_view_cam.fov = 55.0
				_view_cam.far = 2000.0
				add_child(_view_cam)
				_view_cam.current = true
			if _view_cam:
				# First all of them, then each boss in turn, 3/4 front view.
				var k := floori((t - 2.2) / 1.5)
				var o := _show_at
				if k < 0:
					_view_cam.look_at_from_position(o + Vector3(45, 24, -70), o + Vector3(-10, 3, 0))
				else:
					var z := o.z - 45.0 + mini(k, 3) * 30.0
					_view_cam.look_at_from_position(Vector3(o.x + 4.0, 6.0, z - 9.0), Vector3(o.x - 15.0, 4.0, z + 1.0))
			return {}
		"boss":
			var dt := get_physics_process_delta_time()
			if t >= 0.1 and t - dt < 0.1:
				var kind := OS.get_environment("BOSS") if OS.has_environment("BOSS") else "gorilla"
				_boss = wildlife.spawn_boss(kind, Vector3(-250, 0, 205))
				for id in ["rocket", "plasma", "tesla", "swarm", "sniper"]:
					combat.arsenal.add_weapon(id)
				if OS.has_environment("BOSS_HP"):
					_boss.max_hp = float(OS.get_environment("BOSS_HP"))
					_boss.hp = _boss.max_hp
				print(">>> %s spawned, hp %.0f" % [_boss.boss_name, _boss.max_hp])
			if is_instance_valid(_boss) and _boss != null:
				if _boss._attack != _boss_attack:
					_boss_attack = _boss._attack
					if _boss_attack != "":
						print(">>> t=%.2f %s: %s  (car at %.0f m)" % [t, _boss.boss_name, _boss_attack.to_upper(), _boss.global_position.distance_to(car.global_position)])
				# BOSSCAM=1: a camera circling the boss instead of the chase view.
				if OS.has_environment("BOSSCAM"):
					if _view_cam == null:
						_view_cam = Camera3D.new()
						_view_cam.fov = 55.0
						_view_cam.far = 2000.0
						add_child(_view_cam)
						_view_cam.current = true
					var bp: Vector3 = _boss.global_position
					var a := t * 0.25
					_view_cam.look_at_from_position(bp + Vector3(cos(a) * 24.0, 9.0, sin(a) * 24.0), bp + Vector3.UP * 3.0)
				if fmod(t, 3.0) < dt:
					print(">>> t=%.1f boss hp %.0f/%.0f  engaged %s  pos %s" % [t, _boss.hp, _boss.max_hp, _boss.engaged, _boss.global_position.snapped(Vector3.ONE * 0.1)])
			if combat.hp < 30.0 and combat.wrecked <= 0.0:
				combat.hp = 100.0
				print(">>> t=%.2f (test refills the hull)" % t)
			return {"throttle": 1.0 if v < 60.0 else 0.0, "steer_left": 0.45, "boost": 1.0 if fmod(t, 6.0) < 1.0 else 0.0}
		"megablock":
			if t < 0.02:
				car.linear_velocity = Vector3(0, 0, -30)     # rolling start down the avenue
			# Off the kicker, through the first-floor windows, across the deck.
			return {"throttle": 1.0 if t < 5.5 else 0.0, "brake": 1.0 if t > 5.5 else 0.0, "boost": 1.0 if t < 1.0 else 0.0}
		"damage":
			if t < 0.05:
				combat.hp = 65.0
			elif t > 2.0 and t < 2.05:
				combat.hp = 35.0
			elif t > 4.0 and t < 4.05:
				combat.hp = 12.0
			elif t > 6.4 and t < 6.45:
				combat.damage_player(100.0, car.global_position + Vector3.FORWARD, "test")
			return {}
		"wallride":
			return {"throttle": 1.0, "boost": 1.0 if t < 1.0 else 0.0}
		"tour":
			# [car position, heading (rad)] every 1.5 s.
			var spots := [[Vector3(560, 0.6, 210), 0.0], [Vector3(470, 86, 30), PI * 0.6], [Vector3(-150, 0.6, -400), -PI / 2],
				[Vector3(0, 0.6, -500), 0.0], [Vector3(-420, 0.6, 0), PI * 0.5], [Vector3(-60, 0.6, 430), PI],
				[Vector3(-150, 0.6, 470), PI], [Vector3(0, 0.6, -160), 0.0], [Vector3(450, 0.6, -300), -PI * 0.75],
				[Vector3(300, 0.6, 300), -PI * 0.25]]
			var k := int(t / 1.5)
			if k < spots.size() and fmod(t, 1.5) < get_physics_process_delta_time():
				car.request_reset_to(Transform3D(Basis(Vector3.UP, spots[k][1]), spots[k][0]))
				cam.snap()
			return {}
		"reverse":
			for k in [1, 2, 3, 4]:
				for start: float in [0.5, 8.0]:
					var at: float = start + k
					if t >= at and t - get_physics_process_delta_time() < at:
						print(">>> %s %d s: %.0f km/h" % ["forward" if start < 1.0 else "reverse", k, car.speed * 3.6])
			if t < 0.5:
				return {}
			if t < 4.5:
				return {"throttle": 1.0}
			if t < 8.0:
				return {"brake": 1.0 if car.speed > 0.3 else 0.0}
			return {"brake": 1.0}
		"grind":
			if t < 0.05 and level_grinds().rails.size() > 0 and not _grind_rail_added:
				_grind_rail_added = true
				level_grinds().add_rail(PackedVector3Array([Vector3(-262, 0.9, 200), Vector3(-222, 0.9, 200), Vector3(-205, 2.2, 200)]), "rail", true)
			var tap := func(at: float) -> float: return 1.0 if t > at and t < at + 0.06 else 0.0
			var g: Node = level_grinds()
			if not g.active:
				# Pop just before the rail starts (x = -262) so the car comes down on it.
				if _flip_at < 0.0 and car.global_position.x > -276.0:
					_flip_at = t
				var pop := 1.0 if _flip_at > 0.0 and t - _flip_at < 0.06 else 0.0
				return {"throttle": 1.0 if v < 50.0 else 0.4, "lift": pop}
			# On the rail: tilt the nose up (tail), turn across (bluntslide),
			# turn back, dip the nose (nose grind).
			var gt: float = g.grind_time
			return {"flip_back": 1.0 if gt > 0.3 and gt < 0.6 else 0.0, "steer_right": 1.0 if gt > 1.0 and gt < 1.65 else 0.0,
				"steer_left": 1.0 if gt > 2.0 and gt < 2.65 else 0.0, "flip_forward": 1.0 if gt > 2.9 and gt < 3.5 else 0.0}
		"battery":
			if t < 0.05:
				car.battery = 0.2
				car.thrust_tank = 0.4
			return {"throttle": 1.0 if v < 60.0 else 0.3}
		"ramp", "flipkicker", "streetramp":
			if t < 0.05:
				tricks.chain = 3
				tricks.chain_mult = 1.5
				tricks.chain_left = 30.0
			return {"throttle": 1.0, "boost": 1.0}
		"crash":
			if t < 0.05:
				tricks.chain = 3
				tricks.chain_mult = 1.5
				tricks.chain_left = 30.0
			return {"throttle": 1.0, "boost": 1.0}
		"flystick":
			return {"lift": 1.0 if t > 0.5 and t < 1.6 else (0.5 if t > 0.5 and t < 5.5 else 0.0),
				"air_nose_down": 1.0 if t > 2.0 and t < 3.25 else 0.0}
		"fullair":
			# FULL mode: lift raw, then a back flip with no flight computer to help.
			if t < 0.1:
				car.jet_mode = car.JetMode.FULL
			return {"lift": 0.75 if t > 0.5 and t < 4.0 else (0.55 if t < 8.0 and t > 0.5 else 0.0),
				"flip_back": 1.0 if t > 2.0 and t < 2.35 else 0.0, "flip_forward": 1.0 if t > 3.3 and t < 3.65 else 0.0}
		"refill":
			# Empty the thrust tank, cruise, brake hard (regen), then sit parked.
			return {
				"throttle": 1.0 if t < 3.0 else 0.0,
				"boost": 1.0 if t > 0.5 and t < 3.0 else 0.0,
				"brake": 1.0 if t > 5.0 and car.speed > 0.5 else 0.0,
			}
		"jump":
			return {"throttle": 1.0 if v < 112.0 and not airborne else 0.0}
		"magwall":
			return {"mag": 1.0, "throttle": 1.0 if t > 2.5 else 0.0}
		"mag":
			var tap := func(at: float) -> float: return 1.0 if t > at and t < at + 0.06 else 0.0
			if t >= 4.0 and t - get_physics_process_delta_time() < 4.0:
				var g := Vector3(car.global_position.x, 0.0, car.global_position.z)
				director.spawn("roller", g + Vector3(0, 1.3, 7), 1.2)
				director.spawn("hopper", g + Vector3(-4, 0.5, 8), 1.0)
				director.spawn("hopper", g + Vector3(0, 0.5, -18), 1.0)
			return {"infinite_air": tap.call(0.2),
				"lift": 1.0 if t > 0.5 and t < 4.2 else tap.call(8.0),
				"mag": 1.0 if (t > 4.4 and t < 7.0) or (t > 8.25 and t < 9.5) else 0.0}
		"hop":
			var tap := func(at: float) -> float: return 1.0 if t > at and t < at + 0.06 else 0.0
			return {"throttle": 1.0 if v < 110.0 else 0.3,
				"lift": maxf(maxf(tap.call(2.0), tap.call(4.2)), maxf(tap.call(4.55), maxf(tap.call(7.0), tap.call(7.45)))),
				"flip_forward": 1.0 if t > 4.5 and t < 4.62 else 0.0}
		"aircontrol":
			var tap := func(at: float) -> float: return 1.0 if t > at and t < at + 0.06 else 0.0
			var w := 1.0 if t < 4.55 or (t > 4.7 and t < 5.0) else 0.0
			var out := {"throttle": w if v < 90.0 else 0.0, "kb_nose_down": w,
				"lift": maxf(maxf(tap.call(2.0), tap.call(4.5)), maxf(tap.call(7.0), maxf(tap.call(10.0), tap.call(10.3)))),
				"air_roll_right": 1.0 if t > 7.2 and t < 7.5 else 0.0,
				"steer_right": 1.0 if t > 10.25 and t < 10.4 else 0.0,
				"infinite_air": tap.call(0.5)}
			if t > 4.55 and t < 4.7 or t > 5.0 and t < 6.5:
				out["throttle"] = 0.0
			return out
		"tricks":
			var tap := func(at: float) -> float: return 1.0 if t > at and t < at + 0.06 else 0.0
			return {"throttle": 1.0 if v < 70.0 else 0.3,
				"lift": maxf(maxf(tap.call(2.0), tap.call(2.3)), maxf(tap.call(5.5), tap.call(5.75))),
				"flip_back": 1.0 if t > 2.25 and t < 2.4 else 0.0,
				"air_roll_right": 1.0 if t > 5.9 and t < 6.95 else 0.0}
		"halfpipe_air":
			return {"throttle": 1.0, "boost": 1.0 if t < 2.4 else 0.0, "steer_left": 1.0 if t > 1.7 and t < 2.4 else 0.0}
		"course":
			return _autopilot()
	return {}


## Follows the course centre line: steer at a point ahead, hold the
## route's design speed (looking ahead for slow sections).
func _autopilot() -> Dictionary:
	var tr := course.track
	_ap_idx = tr.nearest(car.global_position, _ap_idx, 80)
	var n := tr.pts.size()
	var v: float = car.speed
	# Stanley controller: line up with the road's heading a little ahead,
	# plus a pull toward the centre line. Uses the road's own frames, so it
	# works up walls and round loops too.
	var lead := int(clampf(absf(v) * 0.25, 3.0, 14.0))
	var tng := -tr.sample_xform((_ap_idx + lead) % n).basis.z
	var tl := car.global_basis.transposed() * tng
	var heading_err := atan2(tl.x, -tl.z)
	var off := tr.sample_xform(_ap_idx).affine_inverse() * car.global_position
	var steer := clampf((heading_err + atan(-0.8 * off.x / maxf(absf(v), 5.0))) * 1.6, -1.0, 1.0)
	var want := INF
	for k in range(_ap_idx, _ap_idx + int(maxf(v, 10.0) * 2.0)):
		want = minf(want, tr.speeds[k % n])
	var airborne: bool = car.grounded_wheels == 0
	var out := {"steer_right": maxf(steer, 0.0), "steer_left": maxf(-steer, 0.0)}
	if airborne:
		out["steer_right"] = 0.0
		out["steer_left"] = 0.0
	if v < want - 1.0:
		out["throttle"] = 1.0
	elif v > want + 4.0:
		out["brake"] = clampf((v - want) / 10.0, 0.2, 1.0)
	else:
		out["throttle"] = 0.35
	return out


func _physics_process(delta: float) -> void:
	if _test == "":
		return
	_t += delta
	var plan := _plan(_t)
	for a in ["throttle", "brake", "steer_left", "steer_right", "boost", "lift", "jet_assist",
			"flip_forward", "flip_back", "roll_left", "roll_right", "handbrake", "swap_car",
			"kb_nose_down", "air_roll_right", "infinite_air", "air_nose_down", "mag"]:
		if plan.get(a, 0.0) > 0.0:
			Input.action_press(a, plan[a])
		else:
			Input.action_release(a)

	if _test == "horde" and int(_t * 120) % 1200 == 0:
		var info := []
		for e in director.enemies:
			info.append("%s@%.0fm v%.0f" % [e.kind, e.global_position.distance_to(car.global_position), e.linear_velocity.length()])
		print(">>> t=%.0f threat %d alive %d: %s" % [_t, director.threat, director.enemies.size(), ", ".join(info)])
	if _test == "battery":
		for at: float in [2.0, 5.0]:
			if _t >= at and _t - delta < at:
				pickups.spawn(car.global_position - car.global_basis.z * 18.0 + Vector3.UP * 0.9,
					AirPickups.Kind.BATTERY if at < 3.0 else AirPickups.Kind.THRUST)
	if _test == "tricks" and _t >= 9.0 and _t - delta < 9.0:
		pickups.spawn(car.global_position - car.global_basis.z * 40.0 + Vector3.UP * 0.9, AirPickups.Kind.THRUST)
	if _test == "aircontrol":
		for at: float in [3.0, 5.05, 7.5, 10.55, 12.9]:
			if _t >= at and _t - delta < at:
				var b: Basis = car.global_basis
				print(">>> t=%.2f nose %+.0f°  roll %+.0f°  airborne %s  rocket %d%%  thrust %d%%  infinite %s" % [_t,
					rad_to_deg(asin(clampf(-b.z.y, -1, 1))), rad_to_deg(asin(clampf(b.x.y, -1, 1))),
					car.grounded_wheels == 0, car.rocket_tank * 100, car.thrust_tank * 100, car.infinite_air])
	if _test == "hop":
		if car.grounded_wheels == 0:
			if _air_t == 0.0:
				_air_peak = 0.0
			_air_t += delta
			_air_peak = maxf(_air_peak, car.altitude)
		elif _air_t > 0.05:
			print(">>> air %.2f s  peak %.1f m  landed at %.0f km/h  up=%s  rocket=%d%%" % [_air_t, _air_peak, car.speed * 3.6,
				car.global_basis.y.snapped(Vector3.ONE * 0.01), car.rocket_tank * 100])
			_air_t = 0.0
		else:
			_air_t = 0.0
	if not _hit_100 and car.speed * 3.6 >= 100.0:
		_hit_100 = true
		print(">>> 0-100 km/h in %.2f s" % (_t - 0.5))
	if _test == "course" and _t >= _next_log:
		print("t=%5.1f  idx=%4d/%d  d=%6.0f  v=%5.1f km/h  wheels=%d  up=%s  pos=%s  cp=%d  lap=%s  hoops=%d" % [
			_t, _ap_idx, course.track.pts.size(), course.track.dists[maxi(_ap_idx, 0)], car.speed * 3.6, car.grounded_wheels,
			car.global_basis.y.snapped(Vector3.ONE * 0.01), car.global_position.snapped(Vector3.ONE * 0.1),
			course.next_cp - 1, "%.2f" % course.lap_time if course.running else "-", course.hoops_hit])
		_next_log += 1.0
		if course.last_lap < INF:
			print(">>> LAP %.3f  hoops %d/%d" % [course.last_lap, course.last_lap_hoops, course.hoop_count])
			get_tree().quit()
	if _test != "course":
		var vs := get_viewport().get_visible_rect().size
		var sp := (cam.unproject_position(car.global_position) / vs - Vector2(0.5, 0.5)) * 2.0
		var off := maxf(absf(sp.x), absf(sp.y)) if not cam.is_position_behind(car.global_position) else 9.0
		if off > _scr_worst:
			_scr_worst = off
	if _t >= _next_log and _test != "course":
		var vs2 := get_viewport().get_visible_rect().size
		print("    scr=%s  cam_dist=%.1f  worst=%.2f" % [((cam.unproject_position(car.global_position) / vs2 - Vector2(0.5, 0.5)) * 2.0).snapped(Vector2.ONE * 0.01),
			cam.global_position.distance_to(car.global_position), _scr_worst])
	if _test == "course":
		pass
	elif _t >= _next_log:
		_next_log += 0.25
		print("t=%5.2f  v=%6.1f km/h  alt=%5.1f  wheels=%d  up=%s  pos=%s  jets=%.2f  rocket=%3d%%  thrust=%3d%%  comp=%.1f%s  batt=%.2f%%  slip=%5.1f°  drift=%d x%d (total %d)" % [
			_t, car.speed * 3.6, car.altitude, car.grounded_wheels, car.global_basis.y.snapped(Vector3.ONE * 0.01),
			car.global_position.snapped(Vector3.ONE * 0.1), car.jet_output, car.rocket_tank * 100, car.thrust_tank * 100,
			car.compressor_lps, "R" if car.regen else "", car.battery * 100,
			rad_to_deg(car.slip_angle), car.drift_points, car.drift_combo, car.drift_total])

	if _shots_dir != "" and not _shot_times.is_empty() and _t >= _shot_times[0]:
		_shot_times.pop_front()
		var img := get_viewport().get_texture().get_image()
		img.save_png(_shots_dir.path_join("%s_%04.1f.png" % [_test, _t]))
	if _t > TESTS[_test][2]:
		get_tree().quit()
