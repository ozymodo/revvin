extends Node3D
## Effects for the style, air and battery systems:
##   - bursts (sparks, glitter, a shockwave ring and a flash of light) for
##     landed tricks and completed flips
##   - pickups are absorbed by the car itself: a band of light sweeps along
##     the bodywork and its edges glow (the car being rejuvenated), with a
##     small vortex of air drawn into the tank being refilled
##   - battery pickups send an electrical pulse along the ground under the
##     car, then leave it crackling: arcs over the body and a jittering
##     electric trail behind the rear wheels for a few seconds
##   - glowing ribbon trails off the rear corners while a trick is under way
##     or a chain is alive, coloured by the chain
##   - a camera punch on big moments

const RING_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
instance uniform vec4 tint : source_color = vec4(1.0);
instance uniform float fade = 1.0;
instance uniform float electric = 0.0;
void fragment() {
	float r = length(UV - 0.5) * 2.0;
	// Electric: the ring's edge jitters and flickers like an arc.
	float a = atan(UV.y - 0.5, UV.x - 0.5);
	float cell = floor(a * 9.0 + floor(TIME * 30.0) * 7.0);
	r += (fract(sin(cell * 91.7) * 43758.5) - 0.5) * 0.09 * electric;
	float band = smoothstep(0.78, 0.94, r) * (1.0 - smoothstep(0.96, 1.0, r));
	float fill = (1.0 - smoothstep(0.0, 0.95, r)) * 0.12;
	ALBEDO = tint.rgb * 3.0;
	ALPHA = (band + fill) * fade;
}
"""
## Overlay for the car's own meshes: a band of light that sweeps from nose
## to tail plus a rim glow, so a pickup reads as the car being rejuvenated.
## `electric` adds crackling filaments across the bodywork.
const SWEEP_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_back, shadows_disabled, fog_disabled;
uniform vec4 tint : source_color = vec4(1.0);
uniform float progress = 0.0;
uniform float strength = 0.0;
uniform float rim_strength = 0.0;
uniform float electric = 0.0;
uniform vec4 etint : source_color = vec4(0.35, 0.82, 1.0, 1.0);
uniform float damage = 0.0;          // 0 = pristine, 1 = wrecked
uniform mat4 car_inv;
varying vec3 local_pos;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float hash3(vec3 p) { return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453); }
float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash3(i), hash3(i + vec3(1, 0, 0)), f.x), mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), f.x), mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}
void vertex() {
	local_pos = (car_inv * MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	// Glow: a band sweeping nose to tail and an edge glow (pickups), plus
	// crackling filaments (battery charge).
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	float centre = mix(-2.9, 2.9, progress);
	float band = exp(-pow((local_pos.z - centre) / 0.35, 2.0));
	vec3 glow = tint.rgb * (band * strength + rim * rim_strength);
	if (electric > 0.0) {
		float t = floor(TIME * 16.0);
		float wave = sin((local_pos.x * 1.3 + local_pos.y * 2.1 + local_pos.z) * 9.0 + hash(vec2(t, 3.0)) * 6.283);
		float patch = step(0.72, hash(floor(local_pos.xz * 2.5) + t));
		glow += etint.rgb * smoothstep(0.985, 1.0, abs(wave)) * patch * electric * 1.6;
	}
	// Damage: soot and scorch spreading over the bodywork as the hull drops,
	// with glowing embers in it once it's badly hurt.
	float n = vnoise(local_pos * 2.2) * 0.6 + vnoise(local_pos * 6.5) * 0.4;
	float scorch = damage > 0.0 ? smoothstep(1.0 - damage * 0.85, 1.0 - damage * 0.85 + 0.1, n) : 0.0;
	float ember = smoothstep(0.55, 1.0, damage) * smoothstep(0.9, 0.97, vnoise(local_pos * 9.0 + vec3(0.0, TIME * 0.4, 0.0)));
	glow += vec3(1.0, 0.35, 0.05) * ember * scorch * 2.0;
	// Mix mode: soot darkens, glow brightens (as a bright colour over it).
	float gl = clamp(max(glow.r, max(glow.g, glow.b)), 0.0, 1.0);
	float a = max(scorch * 0.88, gl);
	vec3 gcol = glow / max(gl, 0.001) * 1.7;
	ALBEDO = mix(vec3(0.02, 0.018, 0.016), gcol, clamp(gl / max(a, 0.001), 0.0, 1.0));
	ALPHA = a;
}
"""
const AirPickups := preload("res://scripts/world/air_pickups.gd")
const SWEEP_TIME := 0.55                    # s for the band to run nose to tail
const CHARGE_TIME := 4.0                    # s the car crackles after a battery
const TRAIL_REACH := 3.0                    # m of electric trail behind each rear wheel
const TRAIL_LEN := 14                       # samples (every other physics step, ~0.25 s)
const TRAIL_POINTS := [Vector3(-0.86, 0.55, 2.25), Vector3(0.86, 0.55, 2.25)]

var car: RigidBody3D
var tricks: Node                            # tricks.gd
var camera: Camera3D                        # chase_camera.gd

var _ring_mat: ShaderMaterial
var _swirl: GPUParticles3D
var _swirl_mat: ParticleProcessMaterial
var _swirl_light: OmniLight3D
var _trail_mesh: ImmediateMesh
var _trail_mat: StandardMaterial3D
var _trail: Array = [[], []]                # per corner: [[pos, up], ...]
var _trail_level := 0.0
var _trail_color := Color(0.4, 0.9, 1.0)
var _tick := 0
var _sweep_mat: ShaderMaterial
## Hull damage 0..1, set by combat.gd: soot on the body, then smoke, sparks
## and finally fire as it climbs.
var damage := 0.0
var _dmg_smoke: GPUParticles3D
var _dmg_smoke_mat: ParticleProcessMaterial
var _dmg_fire: GPUParticles3D
var _dmg_light: OmniLight3D
var _spark_t := 0.0
var _sweep_t := -1.0                        # time since the sweep started, < 0 when off
var _sweep_k := 1.0                         # sweep brightness
var _sweep_meshes: Array[MeshInstance3D] = []
var _charge_t := 0.0                        # electric crackle time left
var _charge_color := Color(0.35, 0.82, 1.0)
var _arc_mesh: ImmediateMesh
var _arcs: Array = []                       # polylines: [points, alpha, width]
var _wheel_hist: Array = []                 # rear contact points, newest last
var _arc_mat: StandardMaterial3D


func _ready() -> void:
	var sh := Shader.new()
	sh.code = RING_SHADER
	_ring_mat = ShaderMaterial.new()
	_ring_mat.shader = sh

	_swirl = _make_swirl()
	car.add_child(_swirl)
	_swirl_light = OmniLight3D.new()
	_swirl_light.omni_range = 3.5
	_swirl_light.light_energy = 0.0
	_swirl_light.position = Vector3(0, 0.8, 0)
	car.add_child(_swirl_light)

	_trail_mesh = ImmediateMesh.new()
	_trail_mat = StandardMaterial3D.new()
	_trail_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_trail_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_trail_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_trail_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_trail_mat.vertex_color_use_as_albedo = true
	_trail_mat.no_depth_test = false
	var mi := MeshInstance3D.new()
	mi.mesh = _trail_mesh
	mi.top_level = true
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

	var arc_mi := MeshInstance3D.new()
	_arc_mesh = ImmediateMesh.new()
	arc_mi.mesh = _arc_mesh
	arc_mi.top_level = true
	arc_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(arc_mi)
	# Arcs: vertex colour carries the hue (vertex colours clamp at 1), the
	# material's albedo boosts it into the glow range.
	_arc_mat = _trail_mat.duplicate()
	_arc_mat.albedo_color = Color(2.6, 2.6, 2.6)
	var ssh := Shader.new()
	ssh.code = SWEEP_SHADER
	_sweep_mat = ShaderMaterial.new()
	_sweep_mat.shader = ssh

	_dmg_smoke = _make_damage_smoke()
	add_child(_dmg_smoke)
	_dmg_fire = _make_damage_fire()
	add_child(_dmg_fire)
	_dmg_light = OmniLight3D.new()
	_dmg_light.light_color = Color(1.0, 0.5, 0.15)
	_dmg_light.omni_range = 5.0
	_dmg_light.light_energy = 0.0
	add_child(_dmg_light)

	car.air_added.connect(_on_air_added)
	if tricks:
		tricks.trick_landed.connect(_on_trick)
		tricks.touchdown.connect(_on_touchdown)
		tricks.rotation_done.connect(_on_rotation)
		tricks.bailed.connect(_on_bail)


# ------------------------------------------------------------------ hooks

func _on_air_added(t: float, r: float, color: Color) -> void:
	_swirl_mat.color = Color(color.r * 1.8, color.g * 1.8, color.b * 1.8)
	_swirl_light.light_color = color
	# Draw the air into whichever tank it's going to.
	var at: Vector3 = AirPickups.INTAKE[AirPickups.Kind.ROCKET if r > t else AirPickups.Kind.THRUST]
	_swirl.position = at
	_swirl_light.position = at + Vector3.UP * 0.3


func _on_trick(t: Dictionary) -> void:
	var pts: float = t.points
	var power := clampf(0.4 + pts / 3000.0, 0.4, 2.2)
	var c: Color = tricks.GRADES[t.grade][3]
	burst(car.global_position + car.global_basis.y * 0.6, c, power, car.ground_normal(), car)
	punch(clampf(pts / 2500.0, 0.15, 1.0))
	if t.refill > 0.0:
		sweep(c, false, 0.5)                # a softer version of a pickup's refresh


func _on_touchdown(grade: int, _q: float) -> void:
	# Sparks off each tyre as it lands, in the grade's colour.
	var c: Color = tricks.GRADES[grade][3]
	for w in car.wheels:
		if w.grounded:
			sparks(w.contact + w.normal * 0.1, c, 0.35, w.normal)


func _on_rotation(_kind: String, count: int) -> void:
	ring(car.global_position, Color(0.6, 0.9, 1.0), 2.5 + count * 0.8, 0.35, car.global_basis.y, car)


func _on_bail(_reason: String) -> void:
	sparks(car.global_position, Color(1.0, 0.35, 0.25), 0.6, Vector3.UP)


## A pickup shrinks into the car (air_pickups.gd); the car answers: a
## sweep of light along the bodywork, a puff of sparks where it went in, a
## soft glow. Air also gets a faint pressure ring around the body; a
## battery sends an electrical pulse across the ground under the car and
## leaves it crackling for a few seconds. Everything rides with the car.
func pickup_absorb(kind: int, color: Color) -> void:
	var xf := car.global_transform
	var intake: Vector3 = xf * AirPickups.INTAKE[kind]
	var up := xf.basis.y
	sparks(intake, color, 0.25, up, car)
	_flash(intake + up * 0.3, color, 1.6, 4.5, 0.5, car)
	if kind == AirPickups.Kind.BATTERY:
		sweep(color, true, 1.0)
		var n: Vector3 = car.ground_normal()
		var under := xf.origin
		var touching := 0
		for w in car.wheels:
			if w.grounded:
				under = w.contact if touching == 0 else under + w.contact
				touching += 1
		under = (under / touching if touching > 0 else xf.origin - xf.basis.y * 0.4) + n * 0.06
		ring(under, color * 0.75, 7.0, 0.6, n, car, 1.0)
		ring(under, color.lerp(Color.WHITE, 0.4), 3.5, 0.4, n, car, 1.0)
		_sweep_mat.set_shader_parameter("etint", color)
		_flash(xf.origin - up * 0.2, color, 3.0, 7.0, 0.7, car)
		_charge_t = CHARGE_TIME
		_charge_color = color
		_wheel_hist.clear()
	else:
		sweep(color, false, 1.0)
		ring(intake, color * 0.6, 3.0, 0.45, up, car)
	punch(0.18)


## Light sweeps along the car's bodywork from nose to tail, and its edges
## glow, fading over about a second. `strength` scales it (tricks use less).
func sweep(color: Color, electric: bool, strength: float) -> void:
	_apply_overlay()
	_sweep_mat.set_shader_parameter("tint", color)
	_sweep_mat.set_shader_parameter("electric", 0.0)
	_sweep_t = 0.0
	_sweep_k = strength
	if electric:
		_charge_color = color


func _flash(pos: Vector3, color: Color, energy: float, size: float, time: float, follow: Node3D) -> void:
	var light := OmniLight3D.new()
	light.light_color = color
	light.omni_range = size
	follow.add_child(light)
	light.global_position = pos
	var tw := light.create_tween()
	tw.tween_property(light, "light_energy", 0.0, time).from(energy).set_ease(Tween.EASE_OUT)
	tw.tween_callback(light.queue_free)


func punch(strength: float) -> void:
	if camera and camera.has_method("punch"):
		camera.punch(strength)


# ------------------------------------------------------------------ per-frame

func _physics_process(_delta: float) -> void:
	_tick += 1
	if _charge_t > 0.0 and _tick % 2 == 0:
		for i in [2, 3]:
			var w = car.wheels[i]
			var p: Vector3 = w.contact + w.normal * 0.06 if w.grounded else car.global_transform * Vector3(w.mount.x, 0.05, w.mount.z)
			_wheel_hist.append([i, p])
		while _wheel_hist.size() > 16:
			_wheel_hist.pop_front()
	if _tick % 2 == 0:
		var xf := car.global_transform
		for k in 2:
			var pts: Array = _trail[k]
			pts.append([xf * TRAIL_POINTS[k], xf.basis.y])
			if pts.size() > TRAIL_LEN:
				pts.pop_front()


func _process(delta: float) -> void:
	# Intake vortex while air flows in.
	var inflow: float = car.air_inflow
	_swirl.emitting = inflow > 0.05
	_swirl.amount_ratio = clampf(inflow, 0.3, 1.0)
	_swirl_light.light_energy = inflow * (1.4 + 0.4 * sin(Time.get_ticks_msec() * 0.02))

	# Trails: on during a trick in the air, while a chain is alive, and flat out.
	var target := 0.0
	if tricks:
		if tricks.in_air and tricks.live_points > 0:
			target = 1.0
		elif tricks.chain > 0:
			target = clampf(0.35 + 0.15 * tricks.chain, 0.0, 0.9) * clampf(tricks.chain_left / 1.5, 0.0, 1.0)
		var hue := fmod(0.52 + 0.09 * tricks.chain, 1.0)
		_trail_color = _trail_color.lerp(Color.from_hsv(hue, 0.7, 1.0), 1.0 - exp(-3.0 * delta))
	target = maxf(target, clampf((car.linear_velocity.length() - 55.0) / 25.0, 0.0, 0.7))
	_trail_level = move_toward(_trail_level, target, delta * (3.0 if target > _trail_level else 1.2))
	_draw_trails()
	_update_sweep(delta)
	_update_charge(delta)
	_update_damage(delta)


## Smoke from the bonnet past 30% damage (grey, then black), sparks
## crackling off the body past 50%, flames past 70%.
func _update_damage(delta: float) -> void:
	var xf := car.get_global_transform_interpolated()
	var hood := xf * Vector3(0.0, 0.75, -1.3)
	var smoke := smoothstep(0.3, 0.6, damage)
	_dmg_smoke.emitting = smoke > 0.0
	if smoke > 0.0:
		_dmg_smoke.global_position = hood
		_dmg_smoke.amount_ratio = clampf(0.25 + smoke * 0.75, 0.0, 1.0)
		var grey := lerpf(0.55, 0.06, smoothstep(0.4, 0.85, damage))
		_dmg_smoke_mat.color = Color(grey, grey, grey * 1.02, 0.55 + 0.35 * smoke)
	var fire := smoothstep(0.7, 0.9, damage)
	_dmg_fire.emitting = fire > 0.0
	_dmg_light.light_energy = fire * (1.5 + randf() * 1.5)
	if fire > 0.0:
		_dmg_fire.global_position = hood
		_dmg_fire.amount_ratio = clampf(0.3 + fire * 0.7, 0.0, 1.0)
		_dmg_light.global_position = hood + Vector3.UP * 0.5
	if damage > 0.5:
		_spark_t -= delta
		if _spark_t <= 0.0:
			_spark_t = randf_range(0.4, 1.4) * (1.5 - damage)
			var at := xf * Vector3(randf_range(-0.9, 0.9), randf_range(0.3, 0.9), randf_range(-2.0, 2.0))
			sparks(at, Color(1.0, 0.6, 0.2), 0.12, xf.basis.y, car)


func _update_sweep(delta: float) -> void:
	var damaged := damage > 0.02
	if _sweep_t < 0.0 and _charge_t <= 0.0 and not damaged:
		if not _sweep_meshes.is_empty():
			_clear_overlay()
		return
	_apply_overlay()
	_sweep_mat.set_shader_parameter("damage", damage)
	_sweep_mat.set_shader_parameter("car_inv", Projection(car.get_global_transform_interpolated().affine_inverse()))
	var band := 0.0
	var rim := 0.0
	if _sweep_t >= 0.0:
		_sweep_t += delta
		var k := _sweep_t / SWEEP_TIME
		band = clampf(1.0 - (k - 1.0) * 3.0, 0.0, 1.0) * 1.0 * _sweep_k
		rim = clampf(1.0 - _sweep_t / (SWEEP_TIME + 0.7), 0.0, 1.0) * 0.45 * _sweep_k
		_sweep_mat.set_shader_parameter("progress", clampf(k, 0.0, 1.2))
		if _sweep_t > SWEEP_TIME + 0.7:
			_sweep_t = -1.0
	# While charged the bodywork keeps a faint crackle and edge glow.
	var charge := clampf(_charge_t / 1.5, 0.0, 1.0)
	_sweep_mat.set_shader_parameter("strength", band)
	_sweep_mat.set_shader_parameter("rim_strength", maxf(rim, charge * 0.18))
	_sweep_mat.set_shader_parameter("electric", charge * 0.45)


## The overlay goes on every visible mesh of the current body (re-applied if
## the car is swapped).
func _apply_overlay() -> void:
	if not _sweep_meshes.is_empty() and is_instance_valid(_sweep_meshes[0]) and _sweep_meshes[0].is_inside_tree():
		return
	_sweep_meshes.clear()
	for mi in car.model.find_children("*", "MeshInstance3D", true, false):
		if mi.visible:
			mi.material_overlay = _sweep_mat
			_sweep_meshes.append(mi)


func _clear_overlay() -> void:
	for mi in _sweep_meshes:
		if is_instance_valid(mi):
			mi.material_overlay = null
	_sweep_meshes.clear()


## After a battery: a few arcs flicker over the body and a jittering
## electric trail follows the rear wheels, fading over CHARGE_TIME.
func _update_charge(delta: float) -> void:
	_arc_mesh.clear_surfaces()
	if _charge_t <= 0.0:
		return
	_charge_t -= delta
	var k := clampf(_charge_t / 1.5, 0.0, 1.0)
	if _tick % 3 == 0 or _arcs.is_empty():
		_arcs.clear()
		var xf := car.get_global_transform_interpolated()
		# Arcs over the body, fewer as the charge fades.
		for i in int(1 + 2 * k + randf()):
			var a := xf * Vector3(randf_range(-0.9, 0.9), randf_range(0.35, 0.9), randf_range(-2.1, 2.1))
			var b := xf * Vector3(randf_range(-0.9, 0.9), randf_range(0.35, 0.9), randf_range(-2.1, 2.1))
			var zz := _zigzag(a, b, 7, 0.12)
			var ones: Array = []
			ones.resize(zz.size())
			ones.fill(1.0)
			_arcs.append([zz, 0.9, 0.012, ones])
		# The trail: each rear wheel's recent path, re-jittered every flicker.
		# Only the last TRAIL_REACH metres behind each wheel, fading with distance.
		for wheel in [2, 3]:
			var w = car.wheels[wheel]
			var here: Vector3 = xf * Vector3(w.mount.x, 0.05, w.mount.z)
			var pts: Array = []
			var fades: Array = []
			for h in _wheel_hist:
				var d := (h[1] as Vector3).distance_to(here)
				if h[0] == wheel and d < TRAIL_REACH:
					pts.append((h[1] as Vector3) + Vector3(randf_range(-0.12, 0.12), randf_range(0.0, 0.12), randf_range(-0.12, 0.12)))
					fades.append(pow(1.0 - d / TRAIL_REACH, 2.0))
			if pts.size() > 2:
				_arcs.append([pts, 0.6, 0.01, fades])
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var eye := cam.global_position
	var c := _charge_color
	_arc_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _arc_mat)
	for arc in _arcs:
		var pts: Array = arc[0]
		var n := pts.size()
		var fades: Array = arc[3]
		for i in n - 1:
			if fades[i] < 0.99 and randf() < 0.2:
				continue                    # the trail is broken, crackling rather than a solid line
			var p0: Vector3 = pts[i]
			var p1: Vector3 = pts[i + 1]
			var s0: float = fades[i]
			var s1: float = fades[i + 1]
			var dir := (p1 - p0).cross(eye - p0).normalized()
			# A thin bright core and a soft glow either side.
			for pass_ in [[float(arc[2]), 1.0], [float(arc[2]) * 3.0, 0.14]]:
				var side: Vector3 = dir * pass_[0]
				var c0 := Color(c.r, c.g, c.b, arc[1] * k * s0 * pass_[1])
				var c1 := Color(c.r, c.g, c.b, arc[1] * k * s1 * pass_[1])
				for v in [[p0 - side, c0], [p0 + side, c0], [p1 + side, c1], [p0 - side, c0], [p1 + side, c1], [p1 - side, c1]]:
					_arc_mesh.surface_set_color(v[1])
					_arc_mesh.surface_add_vertex(v[0])
	_arc_mesh.surface_end()


static func _zigzag(a: Vector3, b: Vector3, segs: int, amp: float) -> Array:
	var out: Array = [a]
	for i in range(1, segs):
		var t := float(i) / segs
		out.append(a.lerp(b, t) + Vector3(randf_range(-amp, amp), randf_range(-amp, amp), randf_range(-amp, amp)))
	out.append(b)
	return out


func _draw_trails() -> void:
	_trail_mesh.clear_surfaces()
	if _trail_level < 0.02:
		return
	var c := _trail_color * 1.3
	for k in 2:
		var pts: Array = _trail[k]
		var n := pts.size()
		if n < 3:
			continue
		_trail_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP, _trail_mat)
		for i in n:
			var s := float(i) / float(n - 1)            # 0 = oldest, 1 = at the car
			var a := s * s * s * _trail_level * 0.8
			var half := 0.07 * (0.2 + 0.8 * s)
			var p: Vector3 = pts[i][0]
			var u: Vector3 = pts[i][1]
			_trail_mesh.surface_set_color(Color(c.r, c.g, c.b, a))
			_trail_mesh.surface_add_vertex(p + u * half)
			_trail_mesh.surface_set_color(Color(c.r, c.g, c.b, a))
			_trail_mesh.surface_add_vertex(p - u * half)
		_trail_mesh.surface_end()


# ------------------------------------------------------------------ one-shots

## Sparks, glitter, a shockwave ring and a flash. `power` ~0.4..2.
## `follow` carries the effect along with a moving node (the car).
func burst(pos: Vector3, color: Color, power := 1.0, normal := Vector3.UP, follow: Node3D = null) -> void:
	sparks(pos, color, power, normal, follow)
	_glitter(pos, color, power, follow)
	ring(pos - normal * 0.4, color, minf(3.5 + 3.0 * power, 8.0), 0.55, normal, follow)
	ring(pos, Color.WHITE.lerp(color, 0.5), 2.0 + 1.5 * power, 0.35, normal, follow)
	var light := OmniLight3D.new()
	light.light_color = color
	light.omni_range = 6.0 + 5.0 * power
	(follow if follow else self).add_child(light)
	light.global_position = pos + normal * 0.8
	var tw := light.create_tween()
	tw.tween_property(light, "light_energy", 0.0, 0.45).from(2.0 + 1.5 * power).set_ease(Tween.EASE_OUT)
	tw.tween_callback(light.queue_free)


func sparks(pos: Vector3, color: Color, power: float, normal: Vector3, follow: Node3D = null) -> void:
	var p := GPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.95
	p.amount = int(24 + 60 * power)
	p.lifetime = 0.8
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-15, -15, -15), Vector3(30, 30, 30))
	var m := ParticleProcessMaterial.new()
	m.direction = Vector3.UP
	m.spread = 75.0
	m.initial_velocity_min = 4.0
	m.initial_velocity_max = 8.0 + 9.0 * power
	m.gravity = Vector3(0, -14, 0)
	m.damping_min = 1.5
	m.damping_max = 3.0
	m.scale_min = 0.5
	m.scale_max = 1.2
	m.color = Color(color.r * 2.2, color.g * 2.2, color.b * 2.2)
	m.color_ramp = _fade_ramp()
	p.process_material = m
	p.draw_pass_1 = glow_quad(0.09, 1.0)
	_fire(p, pos, normal, follow)


func _glitter(pos: Vector3, color: Color, power: float, follow: Node3D = null) -> void:
	var p := GPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.8
	p.amount = int(12 + 18 * power)
	p.lifetime = 1.6
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-15, -15, -15), Vector3(30, 30, 30))
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	m.emission_sphere_radius = 0.8
	m.direction = Vector3.UP
	m.spread = 180.0
	m.initial_velocity_min = 0.8
	m.initial_velocity_max = 2.0 + 1.5 * power
	m.gravity = Vector3(0, 0.6, 0)
	m.damping_min = 1.0
	m.damping_max = 2.0
	m.scale_min = 0.6
	m.scale_max = 1.4
	m.color = Color(color.r * 2.0, color.g * 2.0, color.b * 2.0)
	m.color_ramp = _fade_ramp()
	p.process_material = m
	p.draw_pass_1 = glow_quad(0.1, 1.0)
	_fire(p, pos, Vector3.UP, follow)


func _fire(p: GPUParticles3D, pos: Vector3, normal: Vector3, follow: Node3D) -> void:
	p.local_coords = follow != null
	(follow if follow else self).add_child(p)
	p.global_transform = Transform3D(_basis_up(normal), pos)
	p.emitting = true
	get_tree().create_timer(p.lifetime + 0.3).timeout.connect(p.queue_free)


## Expanding shockwave disc facing `normal`.
func ring(pos: Vector3, color: Color, size: float, time: float, normal: Vector3, follow: Node3D = null, electric := 0.0) -> void:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.orientation = PlaneMesh.FACE_Y
	q.size = Vector2(2, 2)
	mi.mesh = q
	mi.material_override = _ring_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	(follow if follow else self).add_child(mi)
	mi.global_transform = Transform3D(_basis_up(normal).scaled(Vector3.ONE * 0.4), pos)
	mi.set_instance_shader_parameter("tint", color)
	mi.set_instance_shader_parameter("electric", electric)
	var tw := mi.create_tween().set_parallel()
	tw.tween_property(mi, "scale", Vector3.ONE * size, time).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_method(func(f: float) -> void: mi.set_instance_shader_parameter("fade", f), 1.0, 0.0, time)
	tw.chain().tween_callback(mi.queue_free)


# ------------------------------------------------------------------ weapons

## A tracer line (sniper, deagle, pellets) that fades in `time`.
func tracer(a: Vector3, b: Vector3, color: Color, width: float, time: float) -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = width
	cm.bottom_radius = width
	cm.height = 1.0
	cm.radial_segments = 6
	cm.rings = 1
	mi.mesh = cm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = Color(color.r * 2.5, color.g * 2.5, color.b * 2.5, 1.0)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	var d := b - a
	if d.length() < 0.01:
		mi.queue_free()
		return
	mi.global_transform = Transform3D(Basis.looking_at(d, Vector3.UP if absf(d.normalized().y) < 0.98 else Vector3.RIGHT) * Basis(Vector3.RIGHT, PI * 0.5), (a + b) * 0.5)
	mi.scale = Vector3(1, d.length(), 1)
	var tw := mi.create_tween()
	tw.tween_property(m, "albedo_color:a", 0.0, time)
	tw.tween_callback(mi.queue_free)


## A lightning bolt between two points (tesla coil): a jagged bright line
## with a soft glow, flickering out.
func lightning(a: Vector3, b: Vector3, color: Color) -> void:
	var im := ImmediateMesh.new()
	var mi := MeshInstance3D.new()
	mi.mesh = im
	mi.top_level = true
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := _arc_mat.duplicate() as StandardMaterial3D
	mi.material_override = m
	add_child(mi)
	var pts := _zigzag(a, b, maxi(6, int(a.distance_to(b) / 1.5)), clampf(a.distance_to(b) * 0.06, 0.2, 1.0))
	var cam := get_viewport().get_camera_3d()
	var eye: Vector3 = cam.global_position if cam else a + Vector3.UP * 10.0
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in pts.size() - 1:
		var p0: Vector3 = pts[i]
		var p1: Vector3 = pts[i + 1]
		var side := (p1 - p0).cross(eye - p0).normalized()
		for w in [[0.05, 1.0], [0.2, 0.3]]:
			var sv: Vector3 = side * w[0]
			var col := Color(color.r, color.g, color.b, w[1])
			for v in [p0 - sv, p0 + sv, p1 + sv, p0 - sv, p1 + sv, p1 - sv]:
				im.surface_set_color(col)
				im.surface_add_vertex(v)
	im.surface_end()
	_flash(b, color, 3.0, 6.0, 0.2, self)
	sparks(b, color, 0.35, Vector3.UP)
	var tw := mi.create_tween()
	tw.tween_property(m, "albedo_color", Color(0, 0, 0), 0.22)
	tw.tween_callback(mi.queue_free)


## Cryo spiker impact: shards of ice and a cold ring.
func frost_burst(pos: Vector3) -> void:
	var c := Color(0.6, 0.92, 1.0)
	sparks(pos, c, 0.5, Vector3.UP)
	ring(pos, c, 4.5, 0.4, Vector3.UP)
	_glitter(pos, c, 0.4)


## Thunderhead impact: a proper explosion, smaller than the car's wreck.
func big_blast(pos: Vector3) -> void:
	burst(pos, Color(1.0, 0.55, 0.2), 1.8, Vector3.UP)
	ring(pos + Vector3.UP * 0.3, Color(1.0, 0.7, 0.4), 14.0, 0.5, Vector3.UP)
	debris(pos, Color(0.25, 0.22, 0.2), Color(1.0, 0.5, 0.15), 1.0)
	dust(pos, 1.0)
	punch(0.45)


# ------------------------------------------------------------------ destruction

## Leaves bursting off a tree or bush. `drift` carries them along with a hit.
func leaves(pos: Vector3, color: Color, power: float, drift: Vector3) -> void:
	var p := GPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.9
	p.amount = int(16 + 50 * power)
	p.lifetime = 2.4
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-30, -30, -30), Vector3(60, 60, 60))
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	m.emission_sphere_radius = 1.2 + power
	m.direction = (Vector3.UP * 2.0 + drift.normalized()).normalized() if drift.length() > 0.5 else Vector3.UP
	m.spread = 70.0
	m.initial_velocity_min = 1.0
	m.initial_velocity_max = 3.0 + 4.0 * power + drift.length() * 0.3
	m.gravity = Vector3(0, -3.0, 0)
	m.damping_min = 1.5
	m.damping_max = 3.0
	m.angular_velocity_min = -360.0
	m.angular_velocity_max = 360.0
	m.scale_min = 0.6
	m.scale_max = 1.3
	m.color = color
	m.color_ramp = _fade_ramp()
	p.process_material = m
	var q := QuadMesh.new()
	q.size = Vector2(0.16, 0.11)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.roughness = 0.8
	q.material = mat
	p.draw_pass_1 = q
	_fire(p, pos, Vector3.UP, null)


## A cloud of dust and grit (smashed rock).
func dust(pos: Vector3, power: float) -> void:
	var p := GPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.85
	p.amount = int(12 + 20 * power)
	p.lifetime = 2.2
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-30, -30, -30), Vector3(60, 60, 60))
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	m.emission_sphere_radius = 0.8
	m.direction = Vector3.UP
	m.spread = 80.0
	m.initial_velocity_min = 1.0
	m.initial_velocity_max = 3.0 + 3.0 * power
	m.gravity = Vector3(0, 0.3, 0)
	m.damping_min = 1.5
	m.damping_max = 2.5
	m.scale_min = 1.0
	m.scale_max = 2.0
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.5))
	curve.add_point(Vector2(1, 2.4))
	var ct := CurveTexture.new()
	ct.curve = curve
	m.scale_curve = ct
	m.color = Color(0.62, 0.58, 0.5, 0.5)
	m.color_ramp = _fade_ramp()
	p.process_material = m
	p.draw_pass_1 = _soft_quad(1.4, false)
	_fire(p, pos, Vector3.UP, null)


## The car blowing up: a flash, a fireball, a shockwave, burning debris
## thrown out (real tumbling pieces trailing fire) and a column of black
## smoke that hangs in the air.
func explosion(pos: Vector3) -> void:
	_flash(pos + Vector3.UP, Color(1.0, 0.7, 0.35), 14.0, 28.0, 0.9, self)
	# Fireball
	var fb := GPUParticles3D.new()
	fb.one_shot = true
	fb.explosiveness = 0.92
	fb.amount = 70
	fb.lifetime = 1.1
	fb.local_coords = false
	fb.visibility_aabb = AABB(Vector3(-30, -30, -30), Vector3(60, 60, 60))
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	m.emission_sphere_radius = 1.4
	m.direction = Vector3.UP
	m.spread = 180.0
	m.initial_velocity_min = 3.0
	m.initial_velocity_max = 11.0
	m.gravity = Vector3(0, 4.0, 0)
	m.damping_min = 5.0
	m.damping_max = 8.0
	m.scale_min = 1.5
	m.scale_max = 3.0
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.4))
	curve.add_point(Vector2(0.3, 1.0))
	curve.add_point(Vector2(1, 1.5))
	var ct := CurveTexture.new()
	ct.curve = curve
	m.scale_curve = ct
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.15, 0.45, 0.75, 1.0])
	g.colors = PackedColorArray([Color(4, 3.6, 2.6, 1), Color(3, 1.8, 0.5, 1), Color(2.2, 0.7, 0.12, 0.9), Color(0.5, 0.12, 0.04, 0.5), Color(0.05, 0.03, 0.02, 0)])
	var gt := GradientTexture1D.new()
	gt.gradient = g
	m.color_ramp = gt
	fb.process_material = m
	fb.draw_pass_1 = _soft_quad(1.6, true)
	_fire(fb, pos + Vector3.UP * 0.6, Vector3.UP, null)
	# Smoke column
	var sm := GPUParticles3D.new()
	sm.one_shot = true
	sm.explosiveness = 0.5
	sm.amount = 40
	sm.lifetime = 5.0
	sm.local_coords = false
	sm.visibility_aabb = AABB(Vector3(-40, -10, -40), Vector3(80, 80, 80))
	var sm_m := ParticleProcessMaterial.new()
	sm_m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	sm_m.emission_sphere_radius = 1.5
	sm_m.direction = Vector3.UP
	sm_m.spread = 25.0
	sm_m.initial_velocity_min = 3.0
	sm_m.initial_velocity_max = 7.0
	sm_m.gravity = Vector3(0, 1.0, 0)
	sm_m.damping_min = 0.8
	sm_m.damping_max = 1.5
	sm_m.scale_min = 2.0
	sm_m.scale_max = 3.5
	var sc := Curve.new()
	sc.add_point(Vector2(0, 0.5))
	sc.add_point(Vector2(1, 3.0))
	var sct := CurveTexture.new()
	sct.curve = sc
	sm_m.scale_curve = sct
	sm_m.color = Color(0.08, 0.07, 0.07, 0.75)
	sm_m.color_ramp = _fade_ramp()
	sm.process_material = sm_m
	sm.draw_pass_1 = _soft_quad(2.0, false)
	_fire(sm, pos + Vector3.UP * 1.0, Vector3.UP, null)
	# Shockwaves, sparks, scrap
	ring(pos + Vector3.UP * 0.2, Color(1.0, 0.6, 0.25), 16.0, 0.6, Vector3.UP)
	ring(pos + Vector3.UP * 1.0, Color(1.0, 0.85, 0.6), 9.0, 0.4, Vector3.UP)
	sparks(pos + Vector3.UP, Color(1.0, 0.6, 0.2), 2.2, Vector3.UP)
	debris(pos + Vector3.UP, Color(0.18, 0.18, 0.2), Color(1.0, 0.45, 0.1), 1.8)
	# Burning pieces: real bodies trailing fire.
	for k in 7:
		var body := RigidBody3D.new()
		body.mass = 25.0
		body.collision_layer = 0
		body.collision_mask = 1
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(randf_range(0.3, 0.8), randf_range(0.08, 0.2), randf_range(0.3, 0.9))
		mi.mesh = bm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.1, 0.1, 0.11)
		mat.metallic = 0.7
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.35, 0.05)
		mat.emission_energy_multiplier = 0.25
		mi.material_override = mat
		body.add_child(mi)
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = bm.size
		cs.shape = bs
		body.add_child(cs)
		var trail := _make_damage_fire()
		trail.emitting = true
		trail.amount_ratio = 0.6
		body.add_child(trail)
		add_child(body)
		body.global_position = pos + Vector3(randf_range(-1, 1), 1.0, randf_range(-1, 1))
		body.linear_velocity = Vector3(randf_range(-1, 1), randf_range(0.8, 1.6), randf_range(-1, 1)).normalized() * randf_range(9.0, 17.0)
		body.angular_velocity = Vector3(randf_range(-10, 10), randf_range(-10, 10), randf_range(-10, 10))
		get_tree().create_timer(4.0).timeout.connect(body.queue_free)
	punch(1.0)


func _make_damage_smoke() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 40
	p.lifetime = 1.8
	p.local_coords = false
	p.emitting = false
	p.visibility_aabb = AABB(Vector3(-20, -5, -20), Vector3(40, 30, 40))
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	m.emission_sphere_radius = 0.35
	m.direction = Vector3.UP
	m.spread = 20.0
	m.initial_velocity_min = 1.5
	m.initial_velocity_max = 3.0
	m.gravity = Vector3(0, 0.8, 0)
	m.damping_min = 0.5
	m.damping_max = 1.0
	m.scale_min = 0.6
	m.scale_max = 1.0
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.4))
	curve.add_point(Vector2(1, 2.6))
	var ct := CurveTexture.new()
	ct.curve = curve
	m.scale_curve = ct
	m.color_ramp = _fade_ramp()
	p.process_material = m
	_dmg_smoke_mat = m
	p.draw_pass_1 = _soft_quad(0.9, false)
	return p


func _make_damage_fire() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 36
	p.lifetime = 0.45
	p.local_coords = false
	p.emitting = false
	p.visibility_aabb = AABB(Vector3(-20, -5, -20), Vector3(40, 30, 40))
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	m.emission_sphere_radius = 0.3
	m.direction = Vector3.UP
	m.spread = 15.0
	m.initial_velocity_min = 2.0
	m.initial_velocity_max = 4.0
	m.gravity = Vector3(0, 3.0, 0)
	m.scale_min = 0.5
	m.scale_max = 1.0
	var curve := Curve.new()
	curve.add_point(Vector2(0, 1.0))
	curve.add_point(Vector2(1, 0.2))
	var ct := CurveTexture.new()
	ct.curve = curve
	m.scale_curve = ct
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
	g.colors = PackedColorArray([Color(3.2, 2.4, 1.0, 1), Color(2.4, 0.8, 0.15, 0.9), Color(0.6, 0.1, 0.02, 0)])
	var gt := GradientTexture1D.new()
	gt.gradient = g
	m.color_ramp = gt
	p.process_material = m
	p.draw_pass_1 = _soft_quad(0.45, true)
	return p


## Soft round billboard: additive (fire, light) or alpha-blended (smoke, dust).
static func _soft_quad(size: float, additive: bool) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if additive:
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = _dot()
	q.material = mat
	return q


static func basis_up(n: Vector3) -> Basis:
	return _basis_up(n)


# ------------------------------------------------------------------ combat

## An enemy oozes in: a goo ring on the ground and a splash of drops.
func spawn_portal(pos: Vector3, size: float) -> void:
	var c := Color(0.35, 1.0, 0.35)
	ring(pos, c * 0.8, 3.0 + size * 2.0, 0.6, Vector3.UP)
	sparks(pos, c, 0.3 + size * 0.2, Vector3.UP)
	_flash(pos + Vector3.UP, c, 2.0, 6.0, 0.5, self)


## The ray gun bolt hits: a tight green blast.
func raygun_impact(pos: Vector3) -> void:
	var c := Color(0.35, 1.0, 0.4)
	sparks(pos, c, 0.45, Vector3.UP)
	ring(pos, c, 3.2, 0.3, Vector3.UP)
	ring(pos, c.lerp(Color.WHITE, 0.5), 1.8, 0.22, (pos - car.global_position).normalized())
	_flash(pos, c, 3.0, 6.0, 0.3, self)


## A goo shot splatters on something.
func goo_splat(pos: Vector3, normal: Vector3) -> void:
	var c := Color(0.45, 1.0, 0.3)
	sparks(pos, c, 0.3, normal)
	ring(pos + normal * 0.05, c * 0.7, 1.6, 0.35, normal)


## Scrap and goo flying off a dead enemy, or chunks knocked off the world.
func debris(pos: Vector3, chunk: Color, accent: Color, power: float) -> void:
	var p := GPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.95
	p.amount = int(10 + 22 * power)
	p.lifetime = 1.4
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-20, -20, -20), Vector3(40, 40, 40))
	var m := ParticleProcessMaterial.new()
	m.direction = Vector3.UP
	m.spread = 70.0
	m.initial_velocity_min = 3.0
	m.initial_velocity_max = 6.0 + 6.0 * power
	m.gravity = Vector3(0, -15, 0)
	m.angular_velocity_min = -500.0
	m.angular_velocity_max = 500.0
	m.scale_min = 0.6 * power
	m.scale_max = 1.4 * power
	m.color = chunk
	p.process_material = m
	var box := BoxMesh.new()
	box.size = Vector3(0.18, 0.1, 0.14)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.metallic = 0.6
	mat.roughness = 0.5
	box.material = mat
	p.draw_pass_1 = box
	_fire(p, pos, Vector3.UP, null)
	sparks(pos, accent, 0.3 + power * 0.3, Vector3.UP)


static func _basis_up(n: Vector3) -> Basis:
	n = n.normalized() if n.length() > 0.01 else Vector3.UP
	var side := Vector3.RIGHT if absf(n.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD
	var x := side.cross(n).normalized()
	return Basis(x, n, x.cross(n))


# ------------------------------------------------------------------ builders

func _make_swirl() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 60
	p.lifetime = 0.45
	p.local_coords = true                   # spirals into the car wherever it goes
	p.emitting = false
	p.position = Vector3(0, 0.6, 0)
	p.visibility_aabb = AABB(Vector3(-5, -3, -5), Vector3(10, 6, 10))
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	m.emission_ring_axis = Vector3.UP
	m.emission_ring_radius = 1.9
	m.emission_ring_inner_radius = 1.3
	m.emission_ring_height = 0.7
	m.direction = Vector3.UP
	m.spread = 10.0
	m.initial_velocity_min = 0.5
	m.initial_velocity_max = 1.5
	m.gravity = Vector3.ZERO
	m.radial_accel_min = -24.0
	m.radial_accel_max = -18.0
	m.tangential_accel_min = 10.0
	m.tangential_accel_max = 15.0
	m.scale_min = 0.4
	m.scale_max = 0.8
	var curve := Curve.new()
	curve.add_point(Vector2(0, 1.0))
	curve.add_point(Vector2(1, 0.2))
	var ct := CurveTexture.new()
	ct.curve = curve
	m.scale_curve = ct
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.25, 0.8, 1.0])
	grad.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 0.8), Color(1, 1, 1, 0)])
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	m.color_ramp = gt
	m.color = Color(3, 3, 3)
	p.process_material = m
	_swirl_mat = m
	p.draw_pass_1 = glow_quad(0.14, 1.0)
	return p


static var _ramp: GradientTexture1D
static func _fade_ramp() -> GradientTexture1D:
	if _ramp == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.6, 1.0])
		g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.7), Color(1, 1, 1, 0)])
		_ramp = GradientTexture1D.new()
		_ramp.gradient = g
	return _ramp


## Additive soft glowing dot, for particles. `boost` scales its brightness.
static func glow_quad(size: float, boost: float) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color(boost, boost, boost)
	mat.albedo_texture = _dot()
	q.material = mat
	return q


static var _dot_tex: Texture2D
static func _dot() -> Texture2D:
	if _dot_tex == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.25, 1.0])
		g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.6), Color(1, 1, 1, 0)])
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		t.width = 64
		t.height = 64
		_dot_tex = t
	return _dot_tex
