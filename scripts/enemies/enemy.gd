extends RigidBody3D
## Base for the scrap-and-goo creatures. They are physics bodies, so the
## car can knock them about like a Rocket League ball, and they bump into
## the world and each other.
##
## Collision: enemies live on layer 3 and collide with the world (layer 1)
## and each other. The car's suspension, altitude and camera rays only scan
## layer 1, so the car never "drives on" an enemy and the camera doesn't
## pull in behind one.
##
## Subclasses override _build() (shape + model) and _think(delta).
##
## Breakable parts (add_part in _build): legs, wheels, wings, armour. Each
## has its own health, a share of the enemy's; a hit lands on the part
## nearest to where it struck. At half health a part is knocked askew, at
## zero it tears off and tumbles away as a physics chunk carrying the
## enemy's motion (world/debris.gd). The machine fights on without it:
## _part_lost() is where a subclass changes how it moves and attacks.
## Stumps spit sparks, and a badly hurt machine smokes.

const Models := preload("res://scripts/enemies/enemy_models.gd")
const LAYER := 4                    # physics layer 3

const BAR_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
instance uniform float frac = 1.0;
instance uniform float alpha = 1.0;
void vertex() {
	// Billboard: keep the bar facing the camera.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX[0] *= length(MODEL_MATRIX[0].xyz);
	MODELVIEW_MATRIX[1] *= length(MODEL_MATRIX[1].xyz);
}
void fragment() {
	bool filled = UV.x < frac;
	float edge = step(0.06, UV.y) * step(UV.y, 0.94) * step(0.015, UV.x) * step(UV.x, 0.985);
	vec3 fill = mix(vec3(1.0, 0.25, 0.15), vec3(0.35, 1.0, 0.35), frac);
	ALBEDO = edge > 0.5 ? (filled ? fill * 1.6 : vec3(0.08)) : vec3(0.0);
	ALPHA = alpha * (edge > 0.5 ? (filled ? 1.0 : 0.6) : 0.85);
}
"""

var combat: Node                    # combat/combat.gd
var car: RigidBody3D
var kind := ""
var size := 1.0                     # scales model, mass, health and damage
var max_hp := 100.0
var hp := 100.0
var contact_damage := 10.0
var points := 100
var radius := 1.0                   # rough size for targeting and splash
var dead := false
var visual: Node3D

var _prev_v := Vector3.ZERO
var _car_prev_v := Vector3.ZERO
var _hit_cd := 0.0                  # this enemy can hurt the player again after this
var _rammed_cd := 0.0
var _bar: MeshInstance3D
var _bar_show := 0.0
var _flash := 0.0
var _flash_meshes: Array[MeshInstance3D] = []
var _grow := 0.0                    # spawn-in scale
var _t := 0.0
var chill := 0.0                    # > 0: frozen by the cryo spiker (slowed, tinted blue)
var boss := false                   # a beast boss (enemies/boss.gd): never recycled
var ai := true                     # false: a test dummy (physics only, no steering or attacks)
var unseen := 0.0                   # s the car hasn't been able to see this one (recycling)
var parts: Array = []               # {node, tag, share, hp, centre (in the node's space), loose}
var part_mult := 1.0                # parts take this times the damage (big machines with many parts)

var _lost := {}                     # tag -> how many have come off
var _stumps: Array = []             # [where it hung, in visual space, tag]
var _spark_t := 0.0
var _smoke: GPUParticles3D

static var _bar_mat: ShaderMaterial
static var _flash_mat: StandardMaterial3D
static var _chill_mat: StandardMaterial3D


func _ready() -> void:
	collision_layer = LAYER
	collision_mask = 1 | LAYER
	contact_monitor = true
	max_contacts_reported = 4
	can_sleep = false
	continuous_cd = true
	body_entered.connect(_on_body_entered)
	hp = max_hp
	_build()
	for mi in visual.find_children("*", "MeshInstance3D", true, false):
		_flash_meshes.append(mi)
	for p in parts:
		p.hp = max_hp * p.share
		p.centre = _local_centre(p.node)
	visual.scale = Vector3.ONE * 0.01
	_make_bar()


## Override: add the collision shape and set `visual`.
func _build() -> void:
	pass


## Override: steering, attacks.
func _think(_delta: float) -> void:
	pass


## Override: part `node` (tagged `tag`) has just come off. Drop any
## references to it; the node is about to leave the enemy.
func _part_lost(_tag: String, _node: Node3D) -> void:
	pass


## Override: how fast a part that's a wheel is spinning about its local X
## (rad/s), so it rolls on when it comes off.
func _wheel_spin(_node: Node3D) -> float:
	return 0.0


## A breakable part: `share` of max_hp breaks it off.
func add_part(node: Node3D, tag: String, share: float) -> void:
	parts.append({"node": node, "tag": tag, "share": share, "hp": 0.0, "centre": Vector3.ZERO, "loose": false})


## How many parts tagged `tag` have come off.
func lost(tag: String) -> int:
	return _lost.get(tag, 0)


## The middle of a part's meshes, in its own space.
func _local_centre(node: Node3D) -> Vector3:
	var inv := node.global_transform.affine_inverse()
	var box := AABB()
	var first := true
	for mi in _meshes_of(node):
		var a: AABB = (inv * mi.global_transform) * mi.get_aabb()
		box = a if first else box.merge(a)
		first = false
	return box.get_center()


func _meshes_of(node: Node3D) -> Array:
	var out: Array = node.find_children("*", "GeometryInstance3D", true, false)
	if node is GeometryInstance3D:
		out.append(node)
	return out


## Which part a hit at `at` lands on (null: the body took it). A hit with
## no real position (beams, hitscan aimed at the middle) lands anywhere.
func _part_at(at: Vector3) -> Variant:
	if parts.is_empty():
		return null
	if at == Vector3.INF or at.distance_to(global_position) < radius * 0.3:
		return parts.pick_random()
	var best: Variant = null
	var bd := INF
	for p in parts:
		var d: float = ((p.node as Node3D).global_transform * (p.centre as Vector3)).distance_to(at)
		if d < bd:
			bd = d
			best = p
	return best if bd < radius + 1.0 else null


## Knocked askew: bent and hanging off at an angle.
func _loosen(p: Dictionary) -> void:
	p.loose = true
	var node: Node3D = p.node
	var k := 0.2 if p.tag == "wheel" else 0.3
	node.rotation += Vector3(randf_range(-1, 1), randf_range(-0.5, 0.5), randf_range(-1, 1)) * k
	if p.tag != "wheel":
		node.position += Vector3(randf_range(-1, 1), randf_range(-1, 0.3), randf_range(-1, 1)) * 0.04 * radius
	var at := node.global_transform * (p.centre as Vector3)
	if Lod.near(at, 90.0):
		combat.fx.sparks(at, Color(1.0, 0.65, 0.3), 0.25, (at - global_position).normalized())


## Tears a part off. `kick` scales how hard it's thrown.
func break_part(p: Dictionary, at := Vector3.INF, kick := 1.0) -> void:
	if not parts.has(p):
		return
	parts.erase(p)
	_lost[p.tag] = lost(p.tag) + 1
	var node: Node3D = p.node
	var pos := node.global_transform * (p.centre as Vector3)
	_stumps.append([visual.to_local(node.global_position), p.tag])
	for mi in _meshes_of(node):
		if mi is MeshInstance3D:
			_flash_meshes.erase(mi)
		(mi as GeometryInstance3D).material_overlay = null
	var wheel: bool = p.tag == "wheel"
	var spin_rate := _wheel_spin(node) if wheel else 0.0
	_part_lost(p.tag, node)
	# It carries on with the enemy's motion, kicked away from the hit.
	var r := pos - global_position
	var vel := linear_velocity + angular_velocity.cross(r)
	var away := pos - at if at != Vector3.INF and pos.distance_to(at) > 0.1 else r
	away = (away.normalized() + r.normalized() * 0.6 + Vector3.UP * 0.7).normalized()
	vel += away * randf_range(3.0, 7.0) * kick
	var spin := angular_velocity + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 5.0 * kick
	if wheel:
		spin = node.global_basis.x.normalized() * spin_rate + spin * 0.15
	var debris: Node = combat.wrecking.debris if combat.wrecking else null
	if debris and Lod.near(pos, 160.0):
		debris.chunk(node, vel, spin, wheel)
	else:
		node.queue_free()
	combat.part_broken(self, pos, p.tag, vel)


## Dying: what's left comes apart.
func shatter(at: Vector3, most := 4) -> void:
	var left := parts.duplicate()
	left.shuffle()
	for i in mini(most, left.size()):
		break_part(left[i], at, 1.8)


func _physics_process(delta: float) -> void:
	if dead:
		return
	_t += delta
	_hit_cd -= delta
	_rammed_cd -= delta
	if _grow < 1.0:
		_grow = minf(1.0, _grow + delta * 2.5)
		var k := 1.0 - pow(1.0 - _grow, 3.0)
		visual.scale = Vector3.ONE * size * maxf(k * (1.0 + 0.25 * sin(_grow * PI)), 0.01)
	if chill > 0.0:
		chill -= delta
		linear_velocity *= exp(-4.0 * delta)
		angular_velocity *= exp(-4.0 * delta)
	if ai and (chill <= 0.0 or Engine.get_physics_frames() % 3 == 0):
		_think(delta)
	_prev_v = linear_velocity
	_car_prev_v = car.linear_velocity


func _process(delta: float) -> void:
	if _flash > 0.0:
		_flash -= delta
		if _flash <= 0.0:
			for mi in _flash_meshes:
				mi.material_overlay = _chill_mat if chill > 0.0 else null
	elif chill > 0.0 and _flash_meshes.size() > 0 and _flash_meshes[0].material_overlay != _chill_mat:
		for mi in _flash_meshes:
			mi.material_overlay = _chill_mat
	elif chill <= 0.0 and _flash_meshes.size() > 0 and _flash_meshes[0].material_overlay == _chill_mat:
		for mi in _flash_meshes:
			mi.material_overlay = null
	_damaged(delta)
	_bar_show -= delta
	_bar.visible = _bar_show > 0.0 and not dead
	if _bar.visible:
		_bar.global_position = global_position + Vector3.UP * (radius + 0.6)
		_bar.set_instance_shader_parameter("frac", clampf(hp / max_hp, 0.0, 1.0))
		_bar.set_instance_shader_parameter("alpha", clampf(_bar_show, 0.0, 1.0))


## Sparks spitting from the stumps; smoke once it's badly hurt.
func _damaged(delta: float) -> void:
	if dead:
		return
	if _smoke == null and hp < max_hp * 0.45 and Lod.near(global_position, 120.0):
		_smoke = combat._smoke_trail(clampf(radius * 0.7, 0.6, 3.0))
		add_child(_smoke)
		_smoke.position = Vector3.UP * radius * 0.6
		_smoke.emitting = true
	if _stumps.is_empty():
		return
	_spark_t -= delta
	if _spark_t > 0.0:
		return
	var s: Array = _stumps.pick_random()
	var at := visual.to_global(s[0])
	var near := Lod.near(at, 70.0)
	_spark_t = randf_range(0.3, 1.0) * (1.0 if near else 4.0)
	if near:
		combat.fx.sparks(at, Color(1.0, 0.6, 0.25), clampf(0.12 * radius, 0.1, 0.4), (at - global_position).normalized())


func _make_bar() -> void:
	if _bar_mat == null:
		var sh := Shader.new()
		sh.code = BAR_SHADER
		_bar_mat = ShaderMaterial.new()
		_bar_mat.shader = sh
		_flash_mat = StandardMaterial3D.new()
		_flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_flash_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_flash_mat.albedo_color = Color(1.0, 1.0, 1.0, 0.7)
		_chill_mat = _flash_mat.duplicate()
		_chill_mat.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
		_chill_mat.albedo_color = Color(0.6, 0.9, 1.0, 0.45)
	_bar = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(1.0, 0.12)
	_bar.mesh = q
	_bar.material_override = _bar_mat
	_bar.top_level = true
	_bar.scale = Vector3.ONE * clampf(size, 0.8, 2.0)
	_bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bar.visible = false
	add_child(_bar)


## Damage from the ray gun, a ram or a splash, landing at `at` (INF: no
## particular spot). Returns true if it killed.
func take_damage(amount: float, how: String, at := Vector3.INF) -> bool:
	if dead:
		return false
	# Every armour plate gone leaves more of the insides open.
	amount *= 1.0 + 0.05 * minf(lost("plate"), 6)
	var p: Variant = _part_at(at)
	if p != null:
		p.hp -= amount * part_mult
		if not p.loose and p.hp < max_hp * p.share * 0.5:
			_loosen(p)
		if p.hp <= 0.0:
			break_part(p, at)
	hp -= amount
	_bar_show = 3.0
	_flash = 0.08
	for mi in _flash_meshes:
		mi.material_overlay = _flash_mat
	if hp <= 0.0:
		dead = true
		combat.on_enemy_died(self, how)
		return true
	return false


func _on_body_entered(body: Node) -> void:
	if dead:
		return
	if body == car:
		_car_contact()
	elif body is RigidBody3D and not body.has_method("take_damage"):
		_bump_prop(body as RigidBody3D)
	elif body is StaticBody3D:
		_bump_world()


## The car hit us (ram, flip hit) and/or we hit the car (attack).
func _car_contact() -> void:
	var to_me := global_position - car.global_position
	var dir := to_me.normalized() if to_me.length() > 0.01 else Vector3.UP
	if _rammed_cd <= 0.0:
		_rammed_cd = 0.45
		combat.on_car_hit_enemy(self, (_car_prev_v - _prev_v).dot(dir), dir)
	if not dead and _hit_cd <= 0.0 and _attack_speed(dir) > 0.0:
		_hit_cd = 0.9
		combat.damage_player(contact_damage, global_position, kind)


## How hard we were coming at the car when we touched (> 0 = an attack).
func _attack_speed(dir_to_me: Vector3) -> float:
	return _prev_v.dot(-dir_to_me) - 4.0


## Knocking world props about (crates, cones, wrecked cars).
func _bump_prop(body: RigidBody3D) -> void:
	var v := _prev_v.length()
	if v > 4.0:
		body.apply_central_impulse(_prev_v.normalized() * mass * v * 0.3)
		combat.env_hit(global_position, _prev_v, size * 0.6)


## Hitting walls, kerbs, ramps hard enough leaves a mark.
func _bump_world() -> void:
	pass


## Steer toward a desired velocity with a capped force.
func steer(v_des: Vector3, gain: float, max_accel: float) -> void:
	var f := (v_des - linear_velocity) * gain
	apply_central_force(f.limit_length(max_accel) * mass)


func ground_below(from: Vector3, dist: float) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * dist, 1)
	return get_world_3d().direct_space_state.intersect_ray(q)


func can_see_car() -> bool:
	var q := PhysicsRayQueryParameters3D.create(global_position, car.global_position + Vector3.UP * 0.6, 1, [car.get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()
