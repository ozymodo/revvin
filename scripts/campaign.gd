extends Node
## The run, free play: LIVES, GAME OVER and the way out.
##   - LIVES: four of them. Every wreck costs one; the last one is GAME OVER
##     and any key starts the whole run over (the scene is rebuilt).
##   - The win: every beast boss beaten at least once (world/wildlife.gd)
##     and GOAL_SCORE style points. That sets off the NUKE ALARM: sirens and
##     a ten-second countdown, then the detonation. A fireball and mushroom
##     cloud ahead of the camera, a shockwave that rolls out over the city
##     blowing up everything it reaches and bringing the towers down, a
##     white-out in slow motion, a fade to black and MAX REVVIN flashing
##     red, yellow and white like a nuclear alarm.
##
## Draws its own overlay (above the HUD and touch controls) and makes its
## own sound: a wailing air-raid siren, countdown beeps and the blast.

signal life_lost(left: int)
signal alarm_started()
signal detonated(at: Vector3)

const LIVES := 4
const BOSSES := 4
const GOAL_SCORE := 4_000_000
const COUNTDOWN := 10.0
## The detonation (game seconds after zero, except where noted).
const GZ_AHEAD := 280.0             # m ahead of the camera: ground zero
const WAVE_SPEED := 190.0           # m/s the shockwave rolls out
const WAVE_REACH := 700.0           # the whole city
const SLOWMO := 0.35                # time scale through the white-out
const SLOWMO_REAL := 1.8            # real seconds of slow motion, then easing back
const BLACK_FROM := 4.2             # real seconds after zero: fade to black...
const BLACK_TIME := 2.4             # ...over this long, then the title
const PROMPT_DELAY := 2.5           # real s before a key restarts
const RATE := 22050.0

enum State { PLAYING, ALARM, BLAST, ENDED, GAME_OVER }
## The nuclear alarm: hard cuts between these.
const ALARM_COLORS := [Color(1.0, 0.12, 0.08), Color(1.0, 0.85, 0.1), Color(1.0, 1.0, 1.0)]
## The cloud: churning noise, lumpy, burning `hot` where it's still on fire
## (`heat` is the share of the surface) and dirty `smoke` everywhere else.
const CLOUD_SHADER := """
shader_type spatial;
render_mode unshaded, cull_back, fog_disabled, shadows_disabled;
uniform vec4 hot : source_color = vec4(1.0, 0.6, 0.2, 1.0);
uniform vec4 smoke : source_color = vec4(0.3, 0.25, 0.22, 1.0);
uniform float glow = 4.0;
uniform float heat = 1.0;
uniform float alpha = 1.0;
uniform float bump = 0.12;
uniform float churn = 0.35;
varying vec3 p;

float hash(vec3 q) {
	q = fract(q * 0.3183099 + 0.1);
	q *= 17.0;
	return fract(q.x * q.y * q.z * (q.x + q.y + q.z));
}
float noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x), mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x), mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}
float fbm(vec3 x) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * noise(x);
		x *= 2.03;
		a *= 0.5;
	}
	return v;
}
void vertex() {
	p = VERTEX * 3.0 + vec3(0.0, -TIME * churn, 0.0);
	VERTEX += NORMAL * (fbm(p) - 0.5) * bump * 2.0;
}
void fragment() {
	float n = fbm(p * 1.7 + vec3(TIME * churn * 0.5));
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	float burn = smoothstep(1.0 - heat - 0.12, 1.0 - heat + 0.12, n);
	vec3 c = mix(smoke.rgb * (0.5 + 0.8 * n), hot.rgb * glow * (0.6 + 0.8 * n), burn);
	ALBEDO = c * (1.0 - fres * 0.45);
	ALPHA = alpha * (1.0 - fres * 0.5);
}
"""

var car: RigidBody3D
var combat: Node
var tricks: Node
var wildlife: Node
var wrecking: Node
var fx: Node
var hud: Control
var cam: Camera3D
var world: Node3D                   # where the mushroom cloud goes

var lives := LIVES
var restart_on_input := true        # off in scripted tests (a stray pad press would reload)
var beaten := {}                    # boss kind -> true, once each is down
var state := State.PLAYING

var _t := 0.0                       # real seconds in this state
var _bt := 0.0                      # game seconds since detonation
var _left := COUNTDOWN
var _gz := Vector3.ZERO
var _wave := 0.0
var _wave_cd := 0.0
var _car_hit := false
var _overlay: Control
var _font: Font
var _ui := 1.0
var _nuke: Node3D
var _fireball: MeshInstance3D
var _stem: MeshInstance3D
var _cap: MeshInstance3D
var _skirt: MeshInstance3D
var _light: OmniLight3D
var _cloud_shader: Shader

# sound
var _pb: AudioStreamGeneratorPlayback
var _siren := 0.0                   # amplitude, eased toward _siren_to
var _siren_to := 0.0
var _siren_period := 2.4
var _siren_t := 0.0
var _ph := Vector3.ZERO             # siren voices, beep
var _beep := 0.0
var _beep_f := 1046.0
var _rumble := 0.0
var _crack := 0.0
var _lp := 0.0
var _lp2 := 0.0
var _thump_ph := 0.0


func _ready() -> void:
	Engine.time_scale = 1.0
	_font = ThemeDB.fallback_font
	var layer := CanvasLayer.new()
	layer.layer = 50
	add_child(layer)
	_overlay = Control.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_draw_overlay)
	layer.add_child(_overlay)
	var player := AudioStreamPlayer.new()
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = RATE
	gen.buffer_length = 0.1
	player.stream = gen
	player.volume_db = -3.0
	player.bus = &"Effects"
	add_child(player)
	player.play()
	_pb = player.get_stream_playback()
	combat.player_wrecked.connect(_on_wrecked)
	if wildlife:
		wildlife.boss_down.connect(_on_boss_down)


func won_conditions() -> bool:
	return beaten.size() >= BOSSES and tricks.score >= GOAL_SCORE


func _on_boss_down(b: Node) -> void:
	if state != State.PLAYING or beaten.has(b.kind):
		return
	beaten[b.kind] = true
	if hud:
		var left := BOSSES - beaten.size()
		if left > 0:
			hud.notify("BOSSES %d/%d  ·  %d to go" % [beaten.size(), BOSSES, left], Color(1.0, 0.85, 0.4))
		elif tricks.score < GOAL_SCORE:
			hud.notify("EVERY BOSS DOWN  ·  now %s STYLE" % _short(GOAL_SCORE), Color(1.0, 0.85, 0.4))


func _on_wrecked() -> void:
	if state != State.PLAYING:
		return
	lives -= 1
	if lives <= 0:
		_enter(State.GAME_OVER)
		combat.wrecked = 1e9        # no respawn: the wreck stays where it fell
	life_lost.emit(lives)


func _enter(s: State) -> void:
	state = s
	_t = 0.0
	match s:
		State.ALARM:
			_left = COUNTDOWN
			_siren_to = 1.0
			_siren_period = 2.4
			_siren_t = 0.0
			alarm_started.emit()
			if hud:
				hud.flash(ALARM_COLORS[0], 1.0)
		State.BLAST:
			_detonate()
		State.ENDED:
			Engine.time_scale = 1.0
			_siren_to = 0.45
			_siren_period = 3.6
		State.GAME_OVER:
			_siren_to = 0.0


func _process(delta: float) -> void:
	var real := delta / maxf(Engine.time_scale, 0.01)
	_t += real
	match state:
		State.PLAYING:
			if won_conditions() and combat.wrecked <= 0.0:
				_enter(State.ALARM)
		State.ALARM:
			combat.invuln = maxf(combat.invuln, 0.5)
			var before := ceili(_left)
			_left -= real
			if ceili(_left) != before or _t <= real:
				_tick(maxi(ceili(_left), 0))
			if _left <= 0.0:
				_enter(State.BLAST)
		State.BLAST:
			combat.invuln = maxf(combat.invuln, 0.5)
			_bt += delta
			_update_blast(delta)
			# Slow motion through the white-out, then easing back to speed.
			Engine.time_scale = SLOWMO if _t < SLOWMO_REAL else lerpf(SLOWMO, 1.0, clampf((_t - SLOWMO_REAL) / 1.5, 0.0, 1.0))
			if _t >= BLACK_FROM + BLACK_TIME:
				_enter(State.ENDED)
		State.ENDED:
			combat.invuln = maxf(combat.invuln, 0.5)
		State.GAME_OVER:
			if hud and _t > 2.2:
				hud.visible = false
	if state != State.PLAYING:
		_overlay.queue_redraw()
	_mix()


## A second gone on the clock: beep, flash, and the HUD edge glows red.
func _tick(n: int) -> void:
	_beep = 0.18 if n > 3 else 0.32
	_beep_f = 1046.0 if n > 3 else 1397.0
	if hud and n > 0:
		hud.flash(ALARM_COLORS[n % 3], 0.9)
		hud.notify("NUKE  ·  T-MINUS %d" % n, ALARM_COLORS[n % 3])
	if fx:
		fx.punch(0.15 + (0.25 if n <= 3 else 0.0))


func _input(event: InputEvent) -> void:
	if not restart_on_input or (state != State.ENDED and state != State.GAME_OVER):
		return
	if _t < PROMPT_DELAY + (1.2 if state == State.GAME_OVER else 0.0):
		return
	var go := false
	if event is InputEventKey:
		go = event.pressed and not event.echo
	elif event is InputEventJoypadButton or event is InputEventMouseButton or event is InputEventScreenTouch:
		go = event.pressed
	if go:
		get_viewport().set_input_as_handled()
		restart()


## From scratch: a new city, full lives, no score.
func restart() -> void:
	Engine.time_scale = 1.0
	get_tree().paused = false
	Lod.reset()
	get_tree().reload_current_scene()


# ------------------------------------------------------------------ the bomb

func _detonate() -> void:
	var fwd := -cam.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.1 else Vector3.FORWARD
	_gz = cam.global_position + fwd * GZ_AHEAD
	if Vector2(_gz.x, _gz.z).length() > 520.0:
		var v := Vector2(_gz.x, _gz.z).limit_length(520.0)
		_gz = Vector3(v.x, 0.0, v.y)
	_gz.y = 0.0
	_bt = 0.0
	_wave = 0.0
	_car_hit = false
	_siren_to = 0.0
	_siren = 0.0
	_crack = 1.0
	_rumble = 1.0
	if hud:
		hud.visible = false
	_build_cloud()
	fx.ring(_gz + Vector3.UP * 2.0, Color(1.0, 0.85, 0.6), WAVE_REACH * 0.6, 5.0, Vector3.UP)
	fx.explosion(_gz + Vector3.UP * 4.0)
	fx.punch(1.0)
	wrecking.explode(_gz, 60.0, 30.0)
	detonated.emit(_gz)


func _update_blast(delta: float) -> void:
	_animate_cloud()
	# The shockwave: a ring of blasts rolling out, everything it passes
	# comes apart, and the towers come down as it reaches them.
	if _wave < WAVE_REACH:
		_wave += WAVE_SPEED * delta
		wrecking.flatten(_gz, _wave, 3)
		_wave_cd -= delta
		if _wave_cd <= 0.0:
			_wave_cd = 0.07
			for k in 3:
				var a := randf() * TAU
				var p := _gz + Vector3(cos(a), 0.0, sin(a)) * _wave
				if Vector2(p.x, p.z).length() > 560.0:
					continue
				p.y = randf_range(0.5, 6.0)
				wrecking.explode(p, 26.0, 9.0)
				# Fireballs only where they'd be seen, to keep it smooth.
				if k == 0 and p.distance_to(cam.global_position) < 260.0:
					fx.explosion(p)
	var d := Vector2(car.global_position.x - _gz.x, car.global_position.z - _gz.z).length()
	if not _car_hit and _wave >= d:
		_car_hit = true
		var away := (car.global_position - _gz)
		away.y = 0.0
		away = away.normalized() if away.length() > 0.1 else Vector3.BACK
		var k := clampf(1.0 - d / WAVE_REACH, 0.35, 1.0)
		car.apply_central_impulse((away * 22.0 + Vector3.UP * 12.0) * k * car.mass)
		car.apply_torque_impulse(Vector3(randf_range(-1, 1), randf_range(-0.4, 0.4), randf_range(-1, 1)).normalized() * car.mass * 5.0)
		fx.punch(1.0)
		_crack = maxf(_crack, 0.6)
		if tricks:
			tricks.ignore_crash(6.0)


func _part(mesh: Mesh, smoke: Color, bump: float) -> MeshInstance3D:
	if _cloud_shader == null:
		_cloud_shader = Shader.new()
		_cloud_shader.code = CLOUD_SHADER
	var m := ShaderMaterial.new()
	m.shader = _cloud_shader
	m.set_shader_parameter("smoke", smoke)
	m.set_shader_parameter("bump", bump)
	m.set_shader_parameter("alpha", 0.0)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_nuke.add_child(mi)
	return mi


func _build_cloud() -> void:
	_nuke = Node3D.new()
	_nuke.name = "Nuke"
	world.add_child(_nuke)
	_nuke.global_position = _gz
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 32
	sphere.rings = 16
	_fireball = _part(sphere, Color(0.32, 0.24, 0.2), 0.12)
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.55
	cyl.bottom_radius = 1.0
	cyl.height = 1.0
	cyl.radial_segments = 24
	cyl.cap_top = false
	_stem = _part(cyl, Color(0.36, 0.28, 0.23), 0.1)
	var torus := TorusMesh.new()
	torus.inner_radius = 0.55
	torus.outer_radius = 1.0
	torus.rings = 32
	torus.ring_segments = 16
	_cap = _part(torus, Color(0.34, 0.26, 0.22), 0.14)
	var skirt := TorusMesh.new()
	skirt.inner_radius = 0.8
	skirt.outer_radius = 1.0
	skirt.rings = 48
	skirt.ring_segments = 8
	_skirt = _part(skirt, Color(0.62, 0.52, 0.42), 0.08)
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.8, 0.55)
	_light.omni_range = 1200.0
	_light.omni_attenuation = 0.6
	_light.light_energy = 60.0
	_nuke.add_child(_light)


## Fireball swells and climbs on a stem, a ring of cloud rolls round its
## crown, a skirt of dust runs out along the ground; white-hot to orange to
## dirty brown.
func _animate_cloud() -> void:
	var b := _bt
	var r := 70.0 * (1.0 - exp(-b * 2.0))
	var rise := 150.0 * smoothstep(0.4, 9.0, b)
	_fireball.scale = Vector3(1.0, 0.85, 1.0) * maxf(r, 0.1)
	_fireball.position = Vector3(0, r * 0.7 + rise, 0)
	# White-hot, then orange, then burning out to smoke from the outside in.
	var hot := Color(1.0, 0.95, 0.8).lerp(Color(1.0, 0.45, 0.12), smoothstep(0.0, 1.2, b))
	_cloud(_fireball, hot, lerpf(6.0, 2.5, smoothstep(0.0, 1.5, b)), lerpf(1.0, 0.3, smoothstep(0.5, 7.0, b)), 1.0)
	var top := _fireball.position.y - r * 0.5
	_stem.scale = Vector3(r * 0.32, maxf(top, 0.1), r * 0.32)
	_stem.position = Vector3(0, top * 0.5, 0)
	_cloud(_stem, Color(1.0, 0.5, 0.15), 2.0, lerpf(0.55, 0.1, smoothstep(1.0, 7.0, b)), 0.95 * smoothstep(0.6, 2.0, b))
	var ca := smoothstep(0.8, 2.4, b)
	_cap.scale = Vector3(r * 1.25, r * 0.55, r * 1.25) * (0.6 + 0.4 * ca)
	_cap.position = _fireball.position + Vector3.DOWN * r * 0.15
	_cap.rotation.y = b * 0.3
	_cloud(_cap, Color(1.0, 0.5, 0.15), 2.2, lerpf(0.6, 0.12, smoothstep(1.0, 7.0, b)), 0.95 * ca)
	var sk := minf(_wave, WAVE_REACH) * 0.9
	_skirt.scale = Vector3(sk, 8.0 + b * 3.0, sk)
	_skirt.position = Vector3(0, 3.0, 0)
	_cloud(_skirt, Color(1.0, 0.6, 0.3), 1.5, 0.15, 0.6 * (1.0 - smoothstep(2.0, 7.0, b)))
	_light.position = _fireball.position
	_light.light_energy = 60.0 * exp(-b * 0.6)


func _cloud(mi: MeshInstance3D, hot: Color, glow: float, heat: float, alpha: float) -> void:
	var m := mi.material_override as ShaderMaterial
	m.set_shader_parameter("hot", hot)
	m.set_shader_parameter("glow", glow)
	m.set_shader_parameter("heat", heat)
	m.set_shader_parameter("alpha", alpha)


# ------------------------------------------------------------------ overlay

func _draw_overlay() -> void:
	var o := _overlay
	_ui = clampf(minf(o.size.x / 1500.0, o.size.y / 850.0), 0.55, 2.0)
	o.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE * _ui)
	var vp := o.size / _ui
	match state:
		State.ALARM:
			_draw_alarm(vp)
		State.BLAST:
			_draw_blast(vp)
		State.ENDED:
			_draw_title(vp)
		State.GAME_OVER:
			_draw_game_over(vp)


func _alarm_color(rate := 6.0) -> Color:
	return ALARM_COLORS[int(_t * rate) % ALARM_COLORS.size()]


func _draw_alarm(vp: Vector2) -> void:
	var pulse := 0.5 + 0.5 * sin(_t * TAU / _siren_period * 2.0)
	_vignette(vp, Color(1.0, 0.08, 0.05, 0.25 + 0.35 * pulse), 220.0)
	_stripes(Rect2(0, 0, vp.x, 22), _t)
	_stripes(Rect2(0, vp.y - 22, vp.x, 22), -_t)
	var n := maxi(ceili(_left), 0)
	var c := _alarm_color()
	var frac := _left - floorf(_left)              # 1 -> 0 through each second
	_center(Vector2(vp.x * 0.5, 170), "☢  NUCLEAR ALARM  ☢", 34, c)
	_center(Vector2(vp.x * 0.5, 210), "EVERY BOSS DOWN  ·  %s STYLE  ·  DETONATION IN" % _short(GOAL_SCORE), 15, Color(1, 1, 1, 0.85))
	var k := 1.0 + 0.35 * pow(frac, 3.0)           # each number punches in
	_center(Vector2(vp.x * 0.5, 360), str(n), int(170 * k), c, 10)


func _draw_blast(vp: Vector2) -> void:
	# The white-out, burning down to orange...
	var w := clampf(1.0 - _t / 1.6, 0.0, 1.0)
	if w > 0.0:
		var c := Color(1.0, 1.0, 1.0).lerp(Color(1.0, 0.6, 0.25), 1.0 - w)
		c.a = pow(w, 0.6)
		_overlay.draw_rect(Rect2(Vector2.ZERO, vp), c)
	var tint := clampf(1.0 - absf(_t - 2.0) / 2.0, 0.0, 1.0) * 0.25
	if tint > 0.0:
		_overlay.draw_rect(Rect2(Vector2.ZERO, vp), Color(1.0, 0.45, 0.15, tint))
	# ...then the slow fade to black.
	var black := clampf((_t - BLACK_FROM) / BLACK_TIME, 0.0, 1.0)
	if black > 0.0:
		_overlay.draw_rect(Rect2(Vector2.ZERO, vp), Color(0, 0, 0, smoothstep(0.0, 1.0, black)))


func _draw_title(vp: Vector2) -> void:
	_overlay.draw_rect(Rect2(Vector2.ZERO, vp), Color.BLACK)
	var c := _alarm_color(5.0)
	var mid := Vector2(vp.x * 0.5, vp.y * 0.47)
	# A slow pulse of the alarm colour behind it, and the trefoil.
	var pulse := 0.5 + 0.5 * sin(_t * 5.0)
	for i in 6:
		_overlay.draw_circle(mid, 420.0 - i * 60.0, Color(c, 0.025 + 0.02 * pulse))
	_trefoil(mid, 300.0, _t * 0.25, Color(c, 0.12 + 0.05 * pulse))
	_stripes(Rect2(0, 0, vp.x, 34), _t * 1.5)
	_stripes(Rect2(0, vp.y - 34, vp.x, 34), -_t * 1.5)
	var pop := 1.0 + 0.6 * exp(-_t * 5.0)
	var a := clampf(_t / 0.35, 0.0, 1.0)
	_center(mid, "MAX REVVIN", int(150 * pop), Color(c, a), 14, 1400.0)
	var sub := Color(1, 1, 1, clampf((_t - 0.8) / 0.6, 0.0, 1.0) * 0.85)
	_center(mid + Vector2(0, 112), "THE CITY IS GONE  ·  YOU WIN", 22, sub)
	_center(mid + Vector2(0, 148), "FINAL STYLE %s   ·   BOSSES %d/%d   ·   LIVES LEFT %d" % [
		_thousands(tricks.score), beaten.size(), BOSSES, lives], 16, Color(sub, sub.a * 0.8))
	if _t > PROMPT_DELAY:
		_center(Vector2(vp.x * 0.5, vp.y - 70), "press any key to play again", 16, Color(1, 1, 1, 0.45 + 0.35 * sin(_t * 4.0)))


func _draw_game_over(vp: Vector2) -> void:
	# The wreck burns a moment, then the screen goes dark red.
	var a := clampf((_t - 1.2) / 1.0, 0.0, 1.0)
	if a <= 0.0:
		return
	_overlay.draw_rect(Rect2(Vector2.ZERO, vp), Color(0.08, 0.0, 0.0, 0.82 * a))
	_vignette(vp, Color(0.9, 0.05, 0.03, 0.5 * a), 260.0)
	var t := _t - 1.2
	var flick := 1.0 if fmod(t, 1.6) > 0.08 else 0.4
	var pop := 1.0 + 0.4 * exp(-t * 6.0)
	var mid := Vector2(vp.x * 0.5, vp.y * 0.45)
	_center(mid, "GAME OVER", int(120 * pop), Color(1.0, 0.18, 0.12, a * flick), 12)
	_center(mid + Vector2(0, 84), "OUT OF LIVES", 22, Color(1, 1, 1, a * 0.85))
	_center(mid + Vector2(0, 120), "STYLE %s   ·   BOSSES %d/%d   ·   GOAL: EVERY BOSS + %s" % [
		_thousands(tricks.score), beaten.size(), BOSSES, _short(GOAL_SCORE)], 15, Color(1, 1, 1, a * 0.6))
	if _t > PROMPT_DELAY + 1.2:
		_center(Vector2(vp.x * 0.5, vp.y - 80), "press any key to start over", 16, Color(1, 1, 1, 0.45 + 0.35 * sin(_t * 4.0)))


## Centred text with a dark outline.
func _center(at: Vector2, s: String, size: int, c: Color, outline := 6, max_w := 0.0) -> void:
	var w := _font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var k := 1.0
	if max_w > 0.0 and w > max_w:
		k = max_w / w
	_overlay.draw_set_transform(at * _ui, 0.0, Vector2.ONE * _ui * k)
	var pos := Vector2(-w * 0.5, size * 0.35)
	if outline > 0:
		_overlay.draw_string_outline(_font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, outline, Color(0, 0, 0, c.a * 0.8))
	_overlay.draw_string(_font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, c)
	_overlay.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE * _ui)


## Black and yellow hazard stripes across `r`, scrolling with `t`.
func _stripes(r: Rect2, t: float) -> void:
	_overlay.draw_rect(r, Color(0.05, 0.05, 0.05, 0.9))
	var step := r.size.y * 2.0
	var x := r.position.x - step * 2.0 + fposmod(t * 80.0, step)
	var h := r.size.y
	while x < r.end.x + step:
		_overlay.draw_colored_polygon(PackedVector2Array([
			Vector2(x, r.end.y), Vector2(x + h, r.position.y), Vector2(x + h + step * 0.5, r.position.y), Vector2(x + step * 0.5, r.end.y)]),
			Color(1.0, 0.82, 0.1, 0.9))
		x += step


func _vignette(vp: Vector2, c: Color, d: float) -> void:
	d = minf(d, minf(vp.x, vp.y) * 0.4)
	var c0 := Color(c, 0.0)
	var o := [Vector2(0, 0), Vector2(vp.x, 0), Vector2(vp.x, vp.y), Vector2(0, vp.y)]
	var n := [Vector2(d, d), Vector2(vp.x - d, d), Vector2(vp.x - d, vp.y - d), Vector2(d, vp.y - d)]
	for k in 4:
		var k2 := (k + 1) % 4
		_overlay.draw_polygon(PackedVector2Array([o[k], o[k2], n[k2], n[k]]), PackedColorArray([c, c, c0, c0]))


## The radiation symbol: three blades round a hub.
func _trefoil(at: Vector2, r: float, rot: float, c: Color) -> void:
	_overlay.draw_circle(at, r * 0.15, c)
	for i in 3:
		var a0 := rot + i * TAU / 3.0 - PI / 6.0
		var pts := PackedVector2Array()
		for s in 13:
			var a := a0 + PI / 3.0 * s / 12.0
			pts.append(at + Vector2(cos(a), sin(a)) * r)
		for s in 13:
			var a := a0 + PI / 3.0 * (12 - s) / 12.0
			pts.append(at + Vector2(cos(a), sin(a)) * r * 0.25)
		_overlay.draw_colored_polygon(pts, c)


static func _short(n: int) -> String:
	return "%dM" % roundi(n / 1e6) if n % 1000000 == 0 else "%.1fM" % (n / 1e6)


static func _thousands(n: int) -> String:
	var t := str(absi(n))
	var out := ""
	while t.length() > 3:
		out = "," + t.substr(t.length() - 3) + out
		t = t.substr(0, t.length() - 3)
	return t + out


# ------------------------------------------------------------------ sound

## Air-raid siren (two horn voices a fifth apart, wailing up and down),
## countdown beeps, and the blast: a crack, a thump and a long low rumble.
func _mix() -> void:
	if _pb == null:
		return
	var n := _pb.get_frames_available()
	if n <= 0:
		return
	var silent := _siren < 0.001 and _siren_to <= 0.0 and _beep <= 0.0 and _rumble < 0.001 and _crack < 0.001
	var buf := PackedVector2Array()
	buf.resize(n)
	if silent:
		_pb.push_buffer(buf)
		return
	var dt := 1.0 / RATE
	for i in n:
		var out := 0.0
		var noise := randf() * 2.0 - 1.0
		_siren += (_siren_to - _siren) * dt * 1.5
		if _siren > 0.001:
			_siren_t += dt
			var sweep := 0.5 - 0.5 * cos(TAU * _siren_t / _siren_period)
			var f := lerpf(280.0, 860.0, sweep)
			_ph.x = fmod(_ph.x + TAU * f * dt, TAU)
			_ph.y = fmod(_ph.y + TAU * f * 1.498 * dt, TAU)
			var horn := sin(_ph.x) * 0.6 + sin(_ph.x * 2.0) * 0.25 + sin(_ph.x * 3.0) * 0.12
			horn += (sin(_ph.y) * 0.5 + sin(_ph.y * 2.0) * 0.15) * 0.5
			out += horn * _siren * 0.18 * (0.6 + 0.4 * sweep)
		if _beep > 0.0:
			_beep -= dt
			_ph.z = fmod(_ph.z + TAU * _beep_f * dt, TAU)
			out += signf(sin(_ph.z)) * 0.12 * minf(_beep / 0.03, 1.0)
		if _crack > 0.001:
			_crack *= 1.0 - dt * 4.0
			_thump_ph = fmod(_thump_ph + TAU * (38.0 + 40.0 * _crack) * dt, TAU)
			out += noise * _crack * _crack * 0.7 + sin(_thump_ph) * _crack * 0.6
		if _rumble > 0.001:
			_rumble *= 1.0 - dt * 0.28
			_lp += (noise - _lp) * 0.02
			_lp2 += (_lp - _lp2) * 0.02
			out += _lp2 * 9.0 * _rumble * (0.8 + 0.2 * sin(_siren_t * 7.0 + _rumble * 30.0))
		buf[i] = Vector2.ONE * clampf(out, -1.0, 1.0)
	_pb.push_buffer(buf)
