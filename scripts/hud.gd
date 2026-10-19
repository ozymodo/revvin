extends Control
## Heads-up display, all drawn in _draw(). Includes a live top-down
## schematic of the car (same layout as the design drawing) showing which
## motors, fans and nozzles are working.

const Car := preload("res://scripts/car.gd")
const Tricks := preload("res://scripts/tricks.gd")
const Weapons := preload("res://scripts/combat/weapons.gd")

const C_PANEL := Color(0.07, 0.07, 0.08, 0.72)
const C_TEXT := Color(0.88, 0.88, 0.86)
const C_DIM := Color(0.55, 0.55, 0.55)
const C_MOTOR := Color(0.55, 0.47, 1.0)
const C_TANK := Color(0.33, 0.55, 0.95)
const C_FAN := Color(0.33, 0.75, 0.58)
const C_THRUST := Color(0.95, 0.65, 0.25)
const C_JET := Color(0.9, 0.38, 0.26)
const C_WARN := Color(1.0, 0.45, 0.35)

var car: RigidBody3D
var course: Node                    # track/course.gd
var tricks: Tricks
var combat: Node                    # combat/combat.gd
var director: Node                  # enemies/director.gd
var boss: Node                      # the beast boss hunting us (world/wildlife.gd), or null
var _boss_shown := 1.0
var show_help: bool = Settings.get_value("show_help")

var _font: Font
var _panel: StyleBoxFlat
var _body: StyleBoxFlat
var _time := 0.0
var _fps := 60.0
var _ui := 1.0
var _toasts: Array = []             # [text, colour, time]
var _flash := 0.0
var _flash_color := Color.WHITE
var _tank_glow := Vector2.ZERO      # thrust, rocket: air arriving from a pickup or trick
var _batt_glow := 0.0               # charge arriving from a battery pickup
var _hurt := 0.0                    # red flash on the hull bar after a hit
var _heal := 0.0                    # green glow on the hull bar while patching up
var _hull_shown := 100.0            # trailing "damage taken" segment


const HELP_KBM := [
	["W / S", "drive · brake / reverse   (air: pitch)"],
	["A / D", "steer   (air: yaw)"],
	["Space / RMB", "jump · again in air: double jump"],
	["+ W A S D", "second jump with a direction: dodge flip"],
	["hold Space", "fly · W/S travel · stick/arrows still flip"],
	["LMB / Ctrl", "boost (rear thrusters)"],
	["Shift", "powerslide · in air: hold + A/D to roll"],
	["Q / E", "air roll left / right · road: side jets"],
	["Mouse", "look around · MMB / B: look back"],
	["Arrows", "flip stick (old style) · ↓ road: press down"],
	["W+S", "at a stop: launch control / burnout"],
	["Tab / Z", "jets AUTO/HYBRID/FULL · jet assist"],
	["1-4 / F", "assists · suction fans"],
	["T / G / X", "swap trim / car (stopped) · x-ray"],
	["V", "camera (chase / close / far / hood)"],
	["I", "EXPERIMENTAL: infinite air on/off"],
	["R / Bksp", "recover · respawn at checkpoint"],
	["Enter", "restart the SKYWAY lap"],
	["Esc / F1", "pause menu, settings · help"],
]
const HELP_PAD := [
	["RT / LT", "drive · brake / reverse"],
	["L stick", "steer · air: pitch + yaw"],
	["A", "jump · again in air: double jump"],
	["A + stick", "second jump with a direction: dodge flip"],
	["hold A", "fly · RT/LT travel · L stick still flips"],
	["B", "boost (rear thrusters)"],
	["X", "powerslide · in air: hold + stick to roll"],
	["LB / RB", "air roll left / right · road: side jets"],
	["R stick", "look around · R3: look back"],
	["Y", "camera (chase / close / far / hood)"],
	["L3", "jet assist: stop + turn / descend"],
	["D-pad ↑", "jets AUTO / HYBRID / FULL"],
	["D-pad →", "EXPERIMENTAL: infinite air on/off"],
	["D-pad ← / View", "swap trim / car (when stopped)"],
	["Menu / D-pad ↓", "recover · respawn at checkpoint"],
]

var _pad := false                   # last input came from a controller: show its help


func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf(event.axis_value) > 0.4):
		_pad = true
	elif event is InputEventKey or event is InputEventMouseButton:
		_pad = false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font
	_panel = StyleBoxFlat.new()
	_panel.bg_color = C_PANEL
	_panel.set_corner_radius_all(10)
	_body = StyleBoxFlat.new()
	_body.bg_color = Color(0.27, 0.27, 0.28, 0.9)
	_body.border_color = Color(0.6, 0.6, 0.6, 0.6)
	_body.set_border_width_all(1)
	_body.set_corner_radius_all(26)


func _process(delta: float) -> void:
	_time += delta
	_fps = lerpf(_fps, 1.0 / maxf(delta, 0.001), 0.05)
	_flash = maxf(0.0, _flash - delta * 1.8)
	if car:
		var due: Vector2 = car._air_due
		_tank_glow.x = 1.0 if due.x > 0.001 else maxf(0.0, _tank_glow.x - delta * 1.5)
		_tank_glow.y = 1.0 if due.y > 0.001 else maxf(0.0, _tank_glow.y - delta * 1.5)
		_batt_glow = 1.0 if car._charge_due > 0.001 else maxf(0.0, _batt_glow - delta * 1.5)
	queue_redraw()


## Tricks or a drift patched the hull up.
func healed(amount: float) -> void:
	if amount > 0.0:
		_heal = 1.0


## The car's weapon mounts, bottom of the list upward, above the status panel.
func _arsenal_panel(bottom_left: Vector2) -> void:
	var slots: Array = combat.arsenal.slots
	var h := 30.0 + slots.size() * 21.0
	var r := Rect2(bottom_left - Vector2(0, h), Vector2(330, h))
	_panel.draw(get_canvas_item(), r)
	_text(r.position + Vector2(16, 22), "ARSENAL", 12, C_DIM)
	_text(r.position + Vector2(0, 22), "%d mounts" % slots.size(), 11, C_DIM, HORIZONTAL_ALIGNMENT_RIGHT, 314)
	for i in slots.size():
		var s = slots[i]
		var y := r.position.y + 44 + i * 21
		_text(Vector2(r.position.x + 16, y), s.name, 12, C_DIM)
		if s.id == "":
			_text(Vector2(r.position.x + 110, y), "— empty —", 13, Color(1, 1, 1, 0.25))
			continue
		var tc: Color = Weapons.TIER_COLORS[Weapons.DEFS[s.id].tier - 1]
		_text(Vector2(r.position.x + 110, y), Weapons.DEFS[s.id].name, 13, tc.lightened(0.2))
		_text(Vector2(r.position.x, y), "★".repeat(s.level), 12, Color(1.0, 0.8, 0.3), HORIZONTAL_ALIGNMENT_RIGHT, 314)
		if s.target != null:
			draw_circle(Vector2(r.position.x + 102, y - 5), 3.0, Color(Weapons.DEFS[s.id].color, 0.6 + 0.4 * sin(_time * 12.0)))


## The hull took a hit.
func hurt(amount: float) -> void:
	_hurt = 1.0
	flash(Color(1.0, 0.15, 0.1), clampf(0.35 + amount / 40.0, 0.35, 0.9))


func _hull_panel(r: Rect2) -> void:
	var hp: float = combat.hp
	var frac: float = hp / combat.MAX_HP
	_hull_shown = move_toward(_hull_shown, hp, get_process_delta_time() * 30.0) if _hull_shown > hp else hp
	_hurt = maxf(0.0, _hurt - get_process_delta_time() * 2.5)
	_heal = maxf(0.0, _heal - get_process_delta_time() * 1.2)
	_panel.draw(get_canvas_item(), r)
	var shake := Vector2(sin(_time * 90.0), cos(_time * 77.0)) * 3.0 * _hurt
	var p := r.position + Vector2(16, 22) + shake
	_text(p, "HULL", 13, C_TEXT if frac > 0.3 else C_WARN)
	if combat.invuln > 0.0 and combat.wrecked <= 0.0:
		_text(p + Vector2(50, 0), "SHIELDED", 11, Color(0.5, 0.85, 1.0, 0.6 + 0.4 * sin(_time * 10.0)))
	_text(p, "%d" % ceili(hp), 13, C_TEXT, HORIZONTAL_ALIGNMENT_RIGHT, 298)
	var bar := Rect2(p + Vector2(0, 10), Vector2(298, 12))
	draw_rect(bar, Color(1, 1, 1, 0.08))
	# Damage just taken shows as a pale segment that drains away.
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * _hull_shown / combat.MAX_HP, bar.size.y)), Color(1.0, 0.85, 0.7, 0.6))
	var c := Color(0.35, 0.95, 0.45).lerp(C_WARN, clampf(1.0 - frac * 1.6, 0.0, 1.0))
	if frac < 0.3 and int(_time * 4.0) % 2 == 0:
		c = c.lightened(0.3)
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * frac, bar.size.y)), c.lerp(Color.WHITE, _hurt * 0.6))
	if _heal > 0.0:
		draw_rect(bar.grow(3.0), Color(0.4, 1.0, 0.5, 0.6 * _heal), false, 2.0)
		_text(p + Vector2(110, 0), "+HULL", 13, Color(0.5, 1.0, 0.6, _heal))
	for i in range(1, 10):                  # segment ticks
		var x := bar.position.x + bar.size.x * i / 10.0
		draw_line(Vector2(x, bar.position.y), Vector2(x, bar.end.y), Color(0, 0, 0, 0.35), 1.0)


## A short message that rises over the speedo and fades (pickups etc.).
func notify(text: String, color: Color) -> void:
	_toasts.push_front([text, color, _time])
	if _toasts.size() > 4:
		_toasts.pop_back()


## Edge-of-screen glow for a big landing.
func flash(color: Color, strength: float) -> void:
	_flash = maxf(_flash, strength)
	_flash_color = color


func _text(pos: Vector2, s: String, size: int, color := C_TEXT, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	draw_string(_font, pos, s, align, width, size, color)


func _bar(rect: Rect2, frac: float, color: Color) -> void:
	draw_rect(rect, Color(1, 1, 1, 0.08))
	draw_rect(Rect2(rect.position, Vector2(rect.size.x * clampf(frac, 0.0, 1.0), rect.size.y)), color)


func _draw() -> void:
	if car == null:
		return
	# Lay out on a virtual 1500x850 canvas so the HUD scales with the window.
	var ui_scale := clampf(minf(size.x / 1500.0, size.y / 850.0), 0.55, 2.0)
	_ui = ui_scale
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE * ui_scale)
	var vp := size / ui_scale
	if _flash > 0.0:
		_edge_flash(vp)
	var rocket: bool = car.trim == Car.Trim.ROCKET

	# ---------------- speed + motors (bottom centre)
	var sc := Vector2(vp.x * 0.5, vp.y - 40)
	_panel.draw(get_canvas_item(), Rect2(sc.x - 150, sc.y - 120, 300, 140))
	var mph: bool = Settings.get_value("units") == 1
	_text(Vector2(sc.x - 150, sc.y - 52), "%d" % roundi(absf(car.speed) * (2.23694 if mph else 3.6)), 64, C_TEXT, HORIZONTAL_ALIGNMENT_CENTER, 300)
	_text(Vector2(sc.x - 150, sc.y - 30), "mph" if mph else "km/h", 14, C_DIM, HORIZONTAL_ALIGNMENT_CENTER, 300)
	var labels := ["F", "RL", "RR"]
	for i in 3:
		var x := sc.x - 130 + i * 90
		_text(Vector2(x, sc.y - 4), labels[i], 12, C_DIM)
		_bar(Rect2(x + 22, sc.y - 13, 56, 8), car.motor_load[i], C_MOTOR)

	# ---------------- tanks, compressor, battery (bottom left)
	var tl := Vector2(24, vp.y - 40)
	var rows := 2 if rocket else 1
	var tank_h := 52.0 * rows + 100.0
	_panel.draw(get_canvas_item(), Rect2(tl.x, tl.y - tank_h + 20, 330, tank_h))
	if combat:
		_hull_panel(Rect2(tl.x, tl.y - tank_h + 20 - 62, 330, 54))
	var y := tl.y - tank_h + 48
	_tank_row(Vector2(tl.x + 16, y), "THRUST  200 L AIR", car.thrust_tank, car.thrust_pressure_bar(), C_THRUST,
		car.thrust_valve > 0.05, car.compressor_target == "thrust", _tank_glow.x)
	if rocket:
		_tank_row(Vector2(tl.x + 16, y + 52), "ROCKET  400 L AIR", car.rocket_tank, car.rocket_pressure_bar(), C_JET,
			car.jet_output > 0.02, car.compressor_target == "rocket", _tank_glow.y)
	var cy := y + 52.0 * rows
	_text(Vector2(tl.x + 16, cy), "COMPRESSOR", 13, C_DIM)
	var comp_txt := "IDLE · tanks full"
	var comp_col := C_DIM
	if car.compressor_lps > 0.0:
		comp_txt = "%.1f L/s → %s%s" % [car.compressor_lps, car.compressor_target.to_upper(), "  · REGEN" if car.regen else ""]
		comp_col = C_FAN
	elif car.battery <= 0.02:
		comp_txt = "NO POWER"
		comp_col = C_WARN
	elif car.thrust_tank < 1.0 or (rocket and car.rocket_tank < 1.0):
		comp_txt = "PAUSED · venting"
	_text(Vector2(tl.x + 16, cy), comp_txt, 13, comp_col, HORIZONTAL_ALIGNMENT_RIGHT, 298)
	_text(Vector2(tl.x + 16, cy + 30), "BATTERY  200 kWh", 13, C_DIM)
	_text(Vector2(tl.x + 16, cy + 30), "%d%%" % roundi(car.battery * 100.0), 13, C_TEXT, HORIZONTAL_ALIGNMENT_RIGHT, 298)
	var bc := C_FAN if car.battery > 0.15 else C_WARN
	if car.battery < 0.15 and _batt_glow <= 0.0 and int(_time * 3.0) % 2 == 0:
		bc = C_WARN.lightened(0.3)
	var br_rect := Rect2(tl.x + 16, cy + 40, 298, 8)
	_bar(br_rect, car.battery, bc.lerp(Color(0.6, 0.9, 1.0), _batt_glow * 0.6))
	if _batt_glow > 0.0:
		draw_rect(br_rect.grow(3.0), Color(0.5, 0.85, 1.0, 0.55 * _batt_glow), false, 2.0)
		var sx := br_rect.position.x + fmod(_time * 420.0, br_rect.size.x * clampf(car.battery, 0.05, 1.0))
		draw_rect(Rect2(sx - 10, br_rect.position.y, 10, br_rect.size.y), Color(1, 1, 1, 0.6 * _batt_glow))
		_text(Vector2(tl.x + 166, cy + 30), "+CHARGE", 13, Color(0.6, 0.9, 1.0, _batt_glow))

	# ---------------- status + schematic (bottom right)
	var br := Vector2(vp.x - 24, vp.y - 40)
	_panel.draw(get_canvas_item(), Rect2(br.x - 330, br.y - 320, 330, 340))
	if combat and combat.arsenal:
		_arsenal_panel(Vector2(br.x - 330, br.y - 332))
	_schematic(Vector2(br.x - 85, br.y - 150), 52.0)
	var sx := br.x - 314
	var sy := br.y - 290
	_text(Vector2(sx, sy), "TRIM", 12, C_DIM)
	_text(Vector2(sx + 90, sy), Car.BODIES[car.body_index].name, 12, Car.BODIES[car.body_index].accent)
	_text(Vector2(sx, sy + 22), "ROCKET" if rocket else "THRUST", 22, C_JET if rocket else C_THRUST)
	_text(Vector2(sx, sy + 58), "SUCTION FANS", 12, C_DIM)
	var fan_kn: float = Car.FAN_DOWNFORCE * car.fan_spin / 1000.0
	var fan_txt := "OFF"
	if car.fans_on:
		fan_txt = "PAUSED (flight)" if car.flight_mode else "ON  %.1f kN" % fan_kn
	_text(Vector2(sx, sy + 80), fan_txt, 18, C_FAN if car.fans_on else C_DIM)
	_text(Vector2(sx, sy + 116), "JETS", 12, C_DIM)
	var jet_state := "—"
	var jet_col := C_DIM
	if rocket:
		if car.rocket_tank <= 0.0:
			jet_state = "EMPTY"
			jet_col = C_WARN
		elif car.flight_mode:
			jet_state = "FLIGHT"
			jet_col = C_JET
		elif car.grounded_wheels == 0:
			jet_state = "STABILISE"
			jet_col = C_JET
		elif car.jet_output > 0.02:
			jet_state = "ASSIST"
			jet_col = C_JET
		else:
			jet_state = "READY"
			jet_col = C_TEXT
	_text(Vector2(sx, sy + 138), jet_state, 18, jet_col)
	_text(Vector2(sx, sy + 174), "ALTITUDE", 12, C_DIM)
	_text(Vector2(sx, sy + 196), "%.1f m" % maxf(car.altitude, 0.0), 18)
	_text(Vector2(sx, sy + 232), "GRIP", 12, C_DIM)
	_bar(Rect2(sx, sy + 242, 120, 8), 1.0 - car.tyre_slip, C_FAN if car.tyre_slip < 0.3 else C_WARN)

	# ---------------- centre prompts
	var msg := ""
	var msg2 := ""
	if combat and combat.wrecked > 0.0:
		msg = "WRECKED"
		msg2 = "respawning…"
	elif car.battery < Car.LIMP_BELOW:
		msg = "BATTERY FLAT — motors limping"
		msg2 = "grab a BATTERY pickup (cyan) · brake or coast to regen"
	elif car.upside_down_time > 1.5:
		msg = "Upside down — press %s to recover" % ("Menu" if _pad else "R")
	elif car.burnout:
		msg = "BURNOUT"
		msg2 = "release the brake to launch"
	elif car.launch_ready:
		msg = "LAUNCH CONTROL ARMED"
		msg2 = "release the brake to launch"
	elif car.thrust_tank <= 0.0 and Input.is_action_pressed("boost"):
		msg = "Thrust tank empty — compressor refilling"
		msg2 = "brake to boost the compressor with regen"
	elif rocket and car.rocket_tank <= 0.0 and Input.is_action_pressed("lift"):
		msg = "Rocket tank empty — compressor refilling"
		msg2 = "brake to boost the compressor with regen"
	elif car.can_swap_trim() and not Input.is_action_pressed("throttle"):
		msg = "Stopped"
		msg2 = "T  %s trim    ·    G  switch car" % ("THRUST" if rocket else "ROCKET")
	if msg != "":
		var w := 560.0
		_panel.draw(get_canvas_item(), Rect2(vp.x * 0.5 - w * 0.5, 132, w, 72 if msg2 != "" else 46))
		_text(Vector2(vp.x * 0.5 - w * 0.5, 162), msg, 20, C_TEXT, HORIZONTAL_ALIGNMENT_CENTER, w)
		if msg2 != "":
			_text(Vector2(vp.x * 0.5 - w * 0.5, 190), msg2, 16, C_THRUST, HORIZONTAL_ALIGNMENT_CENTER, w)

	if course:
		_course_panel(vp)
	if boss != null and is_instance_valid(boss) and not boss.dead:
		_boss_bar(vp)

	# ---------------- drift meter (upper centre; under the STYLE panel when
	# trick scoring is on, see _trick_display)
	var dy := 230.0
	if car.drift_points > 0.0 and tricks == null:
		_drift_meter(vp.x * 0.5, dy)
	elif tricks == null:
		var since: float = car._clock - car.drift_last_time
		if since < 2.0:
			var c := Color(C_FAN, 1.0 - since / 2.0)
			_text(Vector2(vp.x * 0.5 - 200, dy + 40 - since * 20.0), "+" + _thousands(int(car.drift_last)), 36, c, HORIZONTAL_ALIGNMENT_CENTER, 400)

	# ---------------- assists + drift totals (top right)
	var ax := vp.x - 300
	var chips := [["TC", car.tc_on, "1"], ["ABS", car.abs_on, "2"], ["ESC", car.esc_on, "3"], ["DRIFT", car.drift_assist, "4"]]
	# Thruster control mode, left of the assists.
	var jm: int = car.jet_mode
	var jr := Rect2(ax - 128, 44, 116, 26)
	var jc: Color = [C_FAN, C_THRUST, C_WARN][jm]
	draw_rect(jr, Color(jc, 0.22))
	draw_rect(jr, jc, false, 1.0)
	_text(jr.position + Vector2(0, 18), "JETS " + Car.JET_MODE_NAMES[jm], 13, C_TEXT, HORIZONTAL_ALIGNMENT_CENTER, jr.size.x)
	_text(Vector2(ax - 128, 88), "Tab", 11, C_DIM)
	for i in chips.size():
		var on: bool = chips[i][1]
		var r := Rect2(ax + i * 68, 44, 62, 26)
		draw_rect(r, Color(C_FAN, 0.25) if on else Color(1, 1, 1, 0.05))
		draw_rect(r, C_FAN if on else Color(1, 1, 1, 0.2), false, 1.0)
		_text(r.position + Vector2(0, 18), chips[i][0], 13, C_TEXT if on else C_DIM, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	_text(Vector2(ax, 88), "assists  1-4", 11, C_DIM)
	if car.infinite_air:
		var ir := Rect2(ax - 128, 98, 116, 22)
		var pulse := 0.6 + 0.4 * sin(car._clock * 4.0)
		draw_rect(ir, Color(C_JET, 0.2 * pulse))
		draw_rect(ir, C_JET, false, 1.0)
		_text(ir.position + Vector2(0, 16), "∞ AIR  (EXP)", 12, C_TEXT, HORIZONTAL_ALIGNMENT_CENTER, ir.size.x)
	if car.drift_total > 0.0:
		_text(Vector2(ax, 108), "DRIFT TOTAL %s   BEST %s" % [_thousands(int(car.drift_total)), _thousands(int(car.drift_best))], 12, C_DIM)

	if tricks:
		_style_panel(vp)
		_trick_display(vp)
	_draw_toasts(vp)

	# ---------------- help (top left)
	if show_help:
		var lines := HELP_PAD if _pad else HELP_KBM
		_panel.draw(get_canvas_item(), Rect2(20, 20, 440, 30 + lines.size() * 21))
		for i in lines.size():
			_text(Vector2(36, 46 + i * 21), lines[i][0], 14, C_THRUST)
			_text(Vector2(140, 46 + i * 21), lines[i][1], 14, C_TEXT)
	if Settings.get_value("show_fps"):
		_text(Vector2(vp.x - 90, 30), "%d fps" % roundi(_fps), 12, C_DIM)


static func _laptime(t: float) -> String:
	if t == INF:
		return "-:--.---"
	var m := int(t / 60.0)
	return "%d:%06.3f" % [m, t - m * 60.0]


## The boss's name and health under the lap timer.
func _boss_bar(vp: Vector2) -> void:
	var w := 520.0
	var x := vp.x * 0.5 - w * 0.5
	var frac: float = clampf(boss.hp / boss.max_hp, 0.0, 1.0)
	_boss_shown = move_toward(_boss_shown, frac, get_process_delta_time() * 0.25) if _boss_shown > frac else frac
	var c: Color = boss.accent
	_text(Vector2(x, 112), boss.boss_name, 18, c)
	_text(Vector2(x + 150, 112), "%s  ·  LV %d" % [String(boss.title).to_upper(), boss.level], 12, C_DIM)
	_text(Vector2(x, 112), "%d / %d" % [ceili(boss.hp), roundi(boss.max_hp)], 12, C_TEXT, HORIZONTAL_ALIGNMENT_RIGHT, w)
	var bar := Rect2(x, 118, w, 12)
	draw_rect(bar.grow(2.0), Color(0, 0, 0, 0.55))
	draw_rect(Rect2(bar.position, Vector2(w * _boss_shown, bar.size.y)), Color(1.0, 0.9, 0.8, 0.5))
	draw_rect(Rect2(bar.position, Vector2(w * frac, bar.size.y)), c.lerp(Color.WHITE, 0.15 + 0.1 * sin(_time * 6.0)))
	for i in range(1, 10):
		var tx := x + w * i / 10.0
		draw_line(Vector2(tx, bar.position.y), Vector2(tx, bar.end.y), Color(0, 0, 0, 0.4), 1.0)


## SKYWAY lap timer (top centre) and its pop-ups.
func _course_panel(vp: Vector2) -> void:
	var w := 470.0
	var x := vp.x * 0.5 - w * 0.5
	_panel.draw(get_canvas_item(), Rect2(x, 18, w, 76))
	var n_cp: int = course.route.checkpoints.size() - 1
	if course.running:
		_text(Vector2(x, 66), _laptime(course.lap_time), 40, C_TEXT, HORIZONTAL_ALIGNMENT_CENTER, w)
		_text(Vector2(x + 18, 44), "SKYWAY", 13, C_TANK)
		_text(Vector2(x + 18, 66), "CP %d/%d" % [course.next_cp - 1, n_cp], 16, C_TEXT)
		_text(Vector2(x + 18, 84), "HOOPS %d/%d" % [course.hoops_hit, course.hoop_count], 12, C_FAN)
	else:
		_text(Vector2(x, 52), "SKYWAY", 26, C_TANK, HORIZONTAL_ALIGNMENT_CENTER, w)
		_text(Vector2(x, 78), "drive through the START gate  ·  Enter: go to start", 13, C_DIM, HORIZONTAL_ALIGNMENT_CENTER, w)
	_text(Vector2(x, 44), "BEST", 11, C_DIM, HORIZONTAL_ALIGNMENT_RIGHT, w - 18)
	_text(Vector2(x, 62), _laptime(course.best_lap), 16, C_THRUST, HORIZONTAL_ALIGNMENT_RIGHT, w - 18)
	if course.last_lap < INF:
		_text(Vector2(x, 82), "LAST " + _laptime(course.last_lap), 11, C_DIM, HORIZONTAL_ALIGNMENT_RIGHT, w - 18)

	var age: float = course.event_age()
	if age < 2.0:
		var a := clampf(2.0 - age, 0.0, 1.0)
		var ev: String = course.last_event
		var col := Color(C_FAN, a)
		var txt := ev
		if ev.begins_with("CP") and course.last_split_delta < INF:
			var d: float = course.last_split_delta
			txt = "%s   %s%.3f" % [ev, "-" if d < 0 else "+", absf(d)]
			col = Color(C_FAN if d < 0 else C_WARN, a)
		elif ev == "FINISH":
			txt = "FINISH  " + _laptime(course.last_lap) + ("   NEW BEST" if course.last_lap <= course.best_lap else "")
			col = Color(C_THRUST, a)
		elif ev == "TURBO":
			col = Color(0.3, 1.0, 0.5, a)
		_text(Vector2(x - 100, 126 - age * 6.0), txt, 26, col, HORIZONTAL_ALIGNMENT_CENTER, w + 200)


static func _thousands(n: int) -> String:
	var t := str(absi(n))
	var out := ""
	while t.length() > 3:
		out = "," + t.substr(t.length() - 3) + out
		t = t.substr(0, t.length() - 3)
	return t + out


func _tank_row(pos: Vector2, label: String, frac: float, bar_p: float, color: Color, active: bool, filling: bool, gain := 0.0) -> void:
	var c := color
	if frac < 0.2 and int(_time * 4.0) % 2 == 0 and gain <= 0.0:
		c = C_WARN
	_text(pos, label + ("  ▲" if filling else ""), 13, C_TEXT if active or filling else C_DIM)
	_text(pos + Vector2(200, 0), "%3d bar" % roundi(bar_p), 13, C_TEXT, HORIZONTAL_ALIGNMENT_RIGHT, 98)
	var r := Rect2(pos + Vector2(0, 10), Vector2(298, 12))
	_bar(r, frac, c.lerp(Color.WHITE, gain * 0.45))
	if gain > 0.0:
		# Air arriving from a pickup or a trick: the bar glows and a sheen sweeps along it.
		var g := Rect2(r.position - Vector2(3, 3), r.size + Vector2(6, 6))
		draw_rect(g, Color(color.lightened(0.4), 0.55 * gain), false, 2.0)
		var sx := r.position.x + fmod(_time * 420.0, r.size.x * clampf(frac, 0.05, 1.0))
		draw_rect(Rect2(sx - 10, r.position.y, 10, r.size.y), Color(1, 1, 1, 0.6 * gain))
		_text(pos + Vector2(150, 0), "+AIR", 13, Color(color.lightened(0.5), gain))
	if filling:
		# Pulse at the fill line while the compressor feeds this tank.
		var x := r.position.x + r.size.x * frac
		draw_rect(Rect2(x - 4, r.position.y, 4, r.size.y), Color(1, 1, 1, 0.4 + 0.4 * sin(_time * 10.0)))


## Top-down schematic, front up. Car body space (x, z) metres -> pixels.
func _schematic(center: Vector2, s: float) -> void:
	var ci := get_canvas_item()
	var rocket: bool = car.trim == Car.Trim.ROCKET
	var p := func(x: float, z: float) -> Vector2: return center + Vector2(x, z) * s

	# wheels
	for w in car.wheels:
		var wc: Vector2 = p.call(w.mount.x, w.mount.z)
		var col := Color(0.3, 0.3, 0.32) if w.grounded else Color(0.2, 0.2, 0.2, 0.5)
		if w.slip > 0.2:
			col = C_WARN
		draw_rect(Rect2(wc - Vector2(0.13, 0.34) * s, Vector2(0.26, 0.68) * s), col)
	_body.draw(ci, Rect2(p.call(-0.935, -2.4), Vector2(1.87, 4.8) * s))

	var mot := [[0.0, -1.83, 0.67], [-0.29, 1.49, 0.48], [0.29, 1.49, 0.48]]
	for i in 3:
		var m: Array = mot[i]
		var r := Rect2(p.call(m[0] - m[2] * 0.5, m[1] - 0.17), Vector2(m[2], 0.34) * s)
		draw_rect(r, C_MOTOR.darkened(0.55).lerp(C_MOTOR, car.motor_load[i]))

	# tanks: outline + fill level
	if rocket:
		var tr := Rect2(p.call(0.08, -1.06), Vector2(0.56, 1.29) * s)
		draw_rect(tr, C_TANK.darkened(0.6))
		var fh: float = tr.size.y * car.rocket_tank
		draw_rect(Rect2(tr.position + Vector2(0, tr.size.y - fh), Vector2(tr.size.x, fh)), C_TANK)
		draw_rect(Rect2(p.call(-0.64, -0.75), Vector2(0.56, 0.75) * s), Color(0.6, 0.6, 0.6), false, 1.0)
	else:
		for sx in [-0.64, 0.08]:
			draw_rect(Rect2(p.call(sx, -0.75), Vector2(0.56, 0.75) * s), Color(0.6, 0.6, 0.6), false, 1.0)
	var tt := Rect2(p.call(-0.645, 0.4), Vector2(1.29, 0.32) * s)
	draw_rect(tt, C_TANK.darkened(0.6))
	draw_rect(Rect2(tt.position, Vector2(tt.size.x * car.thrust_tank, tt.size.y)), C_TANK)

	for fx in [-0.43, 0.43]:
		var fc: Vector2 = p.call(fx, 1.05)
		draw_circle(fc, 0.15 * s, C_FAN.darkened(0.6).lerp(C_FAN, car.fan_spin))
		var a: float = _time * 25.0 * car.fan_spin
		draw_line(fc - Vector2(cos(a), sin(a)) * 0.13 * s, fc + Vector2(cos(a), sin(a)) * 0.13 * s, Color(0, 0, 0, 0.4), 2.0)

	if rocket:
		for n in car.jets:
			_nozzle_dot(p.call(n.pos.x, n.pos.z), n, C_JET, s)
	for n in car.thrusters:
		_nozzle_dot(p.call(n.pos.x, n.pos.z), n, C_THRUST, s)


func _nozzle_dot(pos: Vector2, n, color: Color, s: float) -> void:
	var k: float = clampf(n.intensity, 0.0, 1.0)
	draw_circle(pos, 0.07 * s, color.darkened(0.5).lerp(color, minf(1.0, k * 3.0)))
	if k > 0.04:
		# Plume in the exhaust direction, projected onto the ground plane.
		var d := Vector2(n.exhaust.x, n.exhaust.z)
		var down: float = maxf(0.0, -n.exhaust.y)
		draw_circle(pos, (0.07 + 0.1 * down * k) * s, Color(color, 0.35 * k), false, 2.0)
		if d.length() > 0.2:
			draw_line(pos, pos + d.normalized() * (0.1 + 0.4 * k) * s * d.length(), Color(1, 1, 1, 0.7), 2.0)


# ------------------------------------------------------------------ style

## Session style score and the chain (top right, under the assists).
func _style_panel(vp: Vector2) -> void:
	var r := Rect2(vp.x - 428, 128, 404, 74)
	_panel.draw(get_canvas_item(), r)
	_text(r.position + Vector2(16, 24), "STYLE", 12, C_DIM)
	_text(r.position + Vector2(16, 46), _thousands(tricks.score), 30, C_TEXT)
	if tricks.chain > 0:
		var c := Color.from_hsv(fmod(0.52 + 0.09 * tricks.chain, 1.0), 0.6, 1.0)
		_text(r.position + Vector2(0, 26), "CHAIN  x%.2f" % tricks.chain_mult, 16, c, HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 16)
		_bar(Rect2(r.position + Vector2(r.size.x - 160, 34), Vector2(144, 5)), tricks.chain_left / Tricks.CHAIN_WINDOW, c)
	if tricks.best_trick > 0:
		_text(r.position + Vector2(0, 64), "BEST  %s  %s" % [tricks.best_trick_name, _thousands(tricks.best_trick)], 11, C_DIM,
			HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 16)
	var counts := "%d tricks" % tricks.tricks_landed
	if combat:
		counts += "   ·   %d kills" % combat.kills
	if director and director.enabled:
		counts += "   ·   THREAT %d" % director.threat
	_text(r.position + Vector2(16, 64), counts, 11, C_DIM)


## What you're doing right now, then the landing grade and the pop-up.
## Live drift: points, combo and slide angle.
func _drift_meter(cx: float, dy: float) -> void:
	var ang: float = absf(rad_to_deg(car.slip_angle))
	_text(Vector2(cx - 200, dy), "DRIFT", 16, C_DIM, HORIZONTAL_ALIGNMENT_CENTER, 400)
	_text(Vector2(cx - 200, dy + 44), _thousands(int(car.drift_points)), 44, C_TEXT, HORIZONTAL_ALIGNMENT_CENTER, 400)
	if car.drift_combo > 1:
		_text(Vector2(cx + 110, dy + 40), "x%d" % car.drift_combo, 28, Color.from_hsv(0.85 - car.drift_combo * 0.08, 0.7, 1.0))
	_bar(Rect2(cx - 120, dy + 58, 240, 6), ang / 90.0, C_THRUST)
	_text(Vector2(cx - 200, dy + 80), "%d°" % roundi(ang), 13, C_DIM, HORIZONTAL_ALIGNMENT_CENTER, 400)


## Under the STYLE panel (top right): the live drift meter, what you're
## doing right now, then the landing grade and the rating pop-up.
func _trick_display(vp: Vector2) -> void:
	var cx := vp.x - 226.0                  # centre of the STYLE panel's column
	var y := 262.0
	var col_w := 400.0
	if car.drift_points > 0.0:
		_drift_meter(cx, 236.0)
		y += 100.0
	var age: float = tricks.clock - tricks.last_time
	if tricks.live_name != "" and (tricks.in_air or tricks.live_points > 0) and not tricks.judging:
		var pulse := 0.85 + 0.15 * sin(_time * 12.0)
		_shadow_text(Vector2(cx, y), tricks.live_name, 22, Color(1, 1, 1, pulse), 1.0, col_w)
		var sub := "+" + _thousands(tricks.live_points)
		if tricks.in_air:
			sub += "    %.1f s" % tricks.air_time
		_shadow_text(Vector2(cx, y + 26), sub, 16, Color(C_TEXT, 0.7), 1.0, col_w)
		return
	if tricks.judging:
		var g: Array = Tricks.GRADES[tricks.landing_grade]
		_shadow_text(Vector2(cx, y), g[1] + " LANDING", 26, g[3], 1.0 + 0.08 * sin(_time * 20.0), col_w)
		return
	if tricks.last.is_empty() or age > 2.8:
		return
	var t: Dictionary = tricks.last
	var a := clampf((2.8 - age) / 0.6, 0.0, 1.0)
	var pop := 1.0 + 0.4 * exp(-age * 9.0)
	if t.bail:
		_shadow_text(Vector2(cx, y + 6), t.name, 36, Color(C_WARN, a), pop, col_w)
		_shadow_text(Vector2(cx, y + 34), "chain lost" if t.chain_lost else "chain kept · get back on your wheels",
			15, Color(C_DIM, a), 1.0, col_w)
		return
	var g: Array = Tricks.GRADES[t.grade]
	_shadow_text(Vector2(cx, y + 6), g[1], 36, Color(g[3], a), pop, col_w)
	_shadow_text(Vector2(cx, y + 34), t.name, 18, Color(C_TEXT, a), 1.0, col_w)
	var line := "+" + _thousands(t.points)
	if t.refill > 0.0:
		line += "    +%d%% AIR" % roundi(t.refill * 100.0)
	_shadow_text(Vector2(cx, y + 68), line, 28, Color(1.0, 0.95, 0.8, a), 1.0 + 0.2 * exp(-age * 7.0), col_w)
	var extras: Array[String] = []
	if t.get("heal", 0.0) >= 0.5:
		extras.append("+%d HULL" % roundi(t.heal))
	if t.get("speed", 1.0) > 1.01:
		var mph: bool = Settings.get_value("units") == 1
		extras.append("SPEED x%.2f  (%d %s)" % [t.speed, roundi(t.kmh / 1.609344 if mph else t.kmh), "mph" if mph else "km/h"])
	if t.chain > 1.0:
		extras.append("CHAIN x%.2f" % t.chain)
	if t.note != "":
		extras.append(t.note)
	if t.repeat:
		extras.append("repeat")
	if not extras.is_empty():
		_shadow_text(Vector2(cx, y + 92), "  ·  ".join(extras), 14, Color(C_THRUST, a), 1.0, col_w)


## Centred text with a drop shadow, scaled about its own centre (and
## shrunk to fit `max_w` if given).
func _shadow_text(center: Vector2, s: String, font_size: int, color: Color, scale_k: float, max_w := 0.0) -> void:
	if max_w > 0.0:
		var sw := _font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x * scale_k
		if sw > max_w:
			scale_k *= max_w / sw
	draw_set_transform(center * _ui, 0.0, Vector2.ONE * _ui * scale_k)
	var w := 1400.0
	draw_string(_font, Vector2(-w * 0.5 + 2, 2), s, HORIZONTAL_ALIGNMENT_CENTER, w, font_size, Color(0, 0, 0, color.a * 0.6))
	draw_string(_font, Vector2(-w * 0.5, 0), s, HORIZONTAL_ALIGNMENT_CENTER, w, font_size, color)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE * _ui)


func _draw_toasts(vp: Vector2) -> void:
	var i := 0
	for t in _toasts:
		var age: float = _time - t[2]
		if age > 2.5:
			continue
		var a := clampf((2.5 - age) / 0.5, 0.0, 1.0)
		var pop := 1.0 + 0.3 * exp(-age * 10.0)
		_shadow_text(Vector2(vp.x * 0.5, vp.y - 200 - i * 30 - age * 12.0), t[0], 20, Color(t[1], a), pop)
		i += 1


func _edge_flash(vp: Vector2) -> void:
	var d := minf(140.0, minf(vp.x, vp.y) * 0.3)
	if d < 4.0:
		return
	var c := Color(_flash_color, 0.45 * _flash)
	var c0 := Color(_flash_color, 0.0)
	var o := [Vector2(0, 0), Vector2(vp.x, 0), Vector2(vp.x, vp.y), Vector2(0, vp.y)]
	var n := [Vector2(d, d), Vector2(vp.x - d, d), Vector2(vp.x - d, vp.y - d), Vector2(d, vp.y - d)]
	for k in 4:
		var k2 := (k + 1) % 4
		draw_polygon(PackedVector2Array([o[k], o[k2], n[k2], n[k]]), PackedColorArray([c, c, c0, c0]))
