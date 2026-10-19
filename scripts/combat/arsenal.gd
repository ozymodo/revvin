extends Node3D
## The car's weapon mounts and their auto-fire. Vampire Survivors style:
## every weapon picks its own target and fires on its own; you just drive.
##
## Mounts: one on each corner (on the fenders) and one on the roof above
## every seat, so more seats means more weapons. The Rocket trim's tank
## takes the passenger seat (5 mounts); the Thrust trim has both seats (6).
## Each mount is a low pod in the car's own body paint with a ring in its
## accent glow, so the guns look built in rather than bolted on; an empty
## mount is just the closed pod.
##
## Weapons come from the hex cases in the world (world/weapon_cases.gd):
## a new weapon takes an empty mount; the same weapon again levels it up
## (to 5); with every mount full a better weapon replaces the weakest.

const Weapons := preload("res://scripts/combat/weapons.gd")

const SCAN := 0.15                  # s between target scans

class Slot:
	var name := ""
	var seat := false
	var local := Vector3.ZERO       # car space
	var pod: Node3D
	var yaw: Node3D
	var pitch: Node3D
	var gun: Node3D                 # the weapon model (null when empty)
	var muzzle: Node3D
	var id := ""
	var level := 1
	var cd := 0.0
	var scan := 0.0
	var target: Node
	var recoil := 0.0
	var flash: OmniLight3D
	var beam: MeshInstance3D
	var beam_core: MeshInstance3D
	var beam_tick := 0.0

var combat: Node
var car: RigidBody3D
var enabled := true
var slots: Array[Slot] = []
var _stash := {}                    # weapons on a seat mount that vanished with a trim change
var _pod_mesh: SphereMesh
var _ring_mesh: TorusMesh
var _beam_mat: StandardMaterial3D
var _beam_core_mat: StandardMaterial3D


func _ready() -> void:
	_pod_mesh = SphereMesh.new()
	_pod_mesh.radius = 0.5
	_pod_mesh.height = 1.0
	_pod_mesh.radial_segments = 16
	_pod_mesh.rings = 8
	_ring_mesh = TorusMesh.new()
	_ring_mesh.inner_radius = 0.1
	_ring_mesh.outer_radius = 0.125
	_ring_mesh.rings = 24
	_ring_mesh.ring_segments = 6
	_beam_mat = StandardMaterial3D.new()
	_beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_beam_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_beam_mat.albedo_color = Color(1.2, 0.5, 3.0, 0.8)
	_beam_core_mat = _beam_mat.duplicate()
	_beam_core_mat.albedo_color = Color(2.5, 2.2, 3.5, 1.0)
	rebuild()
	add_weapon("raygun")
	car.trim_changed.connect(func(_t: int) -> void: rebuild())


## (Re)builds the mounts for the current body and trim, keeping weapons.
func rebuild() -> void:
	var held := {}
	for s in slots:
		if s.id != "":
			held[s.name] = [s.id, s.level]
		s.pod.queue_free()
	held.merge(_stash)
	_stash.clear()
	slots.clear()
	var shell := car.model.find_child("Shell", true, false) as MeshInstance3D
	var box: AABB = (car.global_transform.affine_inverse() * shell.global_transform) * shell.get_aabb()
	var hx := box.size.x * 0.5 - 0.42
	var front := box.position.z + 0.8
	var rear := box.end.z - 0.65
	var mounts := [["FRONT L", Vector3(-hx, 0, front), false], ["FRONT R", Vector3(hx, 0, front), false],
		["REAR L", Vector3(-hx, 0, rear), false], ["REAR R", Vector3(hx, 0, rear), false],
		["DRIVER", Vector3(-0.36, 0, -0.1), true]]
	if car._trim_nodes.has("Seat_Passenger") and car._trim_nodes["Seat_Passenger"].visible:
		mounts.append(["PASSENGER", Vector3(0.36, 0, -0.1), true])
	for m in mounts:
		var s := Slot.new()
		s.name = m[0]
		s.seat = m[2]
		var p: Vector3 = m[1]
		s.local = Vector3(p.x, _surface_at(shell, p.x, p.z), p.z)
		_build_pod(s)
		slots.append(s)
	for s in slots:
		if held.has(s.name):
			_equip(s, held[s.name][0], held[s.name][1])
			held.erase(s.name)
	for k in held:                    # a seat that's gone: keep its weapon for later
		_stash[k] = held[k]


## Height of the body shell's surface at (x, z), car space: a ray straight
## down onto the shell mesh itself (so wings, mirrors and the like don't
## lift the mount off the body). Falls back to the bounding-box search.
func _surface_at(shell: MeshInstance3D, x: float, z: float) -> float:
	var tm := shell.mesh.generate_triangle_mesh()
	var to_shell := shell.global_transform.affine_inverse() * car.global_transform
	var from := to_shell * Vector3(x, 4.0, z)
	var dir := (to_shell.basis * Vector3.DOWN).normalized()
	var hit: Dictionary = tm.intersect_ray(from, dir)
	if hit.is_empty():
		return _top_at(x, z)
	var p: Vector3 = car.global_transform.affine_inverse() * (shell.global_transform * (hit.position as Vector3))
	return p.y - 0.02


## Highest point of the bodywork above (x, z), car space.
func _top_at(x: float, z: float) -> float:
	var top := 0.9
	var found := false
	var inv := car.global_transform.affine_inverse()
	for mi in car.model.find_children("*", "MeshInstance3D", true, false):
		if not mi.is_visible_in_tree() or mi.name == "Collider" or mi.name.begins_with("Wheel") or mi.name.begins_with("Jet"):
			continue
		var b: AABB = (inv * mi.global_transform) * mi.get_aabb()
		if b.position.x <= x and b.end.x >= x and b.position.z <= z and b.end.z >= z:
			top = b.end.y if not found else maxf(top, b.end.y)
			found = true
	return top


func _build_pod(s: Slot) -> void:
	s.pod = Node3D.new()
	s.pod.position = s.local
	add_child(s.pod)
	# A low dome in the car's own paint, with a ring in its accent glow.
	var dome := MeshInstance3D.new()
	dome.mesh = _pod_mesh
	dome.material_override = car._shell_mat
	dome.scale = Vector3(0.3, 0.09, 0.34)
	s.pod.add_child(dome)
	var ring := MeshInstance3D.new()
	ring.mesh = _ring_mesh
	var glow := StandardMaterial3D.new()
	var accent: Color = car.BODIES[car.body_index].accent
	glow.albedo_color = accent * 0.3
	glow.emission_enabled = true
	glow.emission = accent
	glow.emission_energy_multiplier = 2.2
	ring.material_override = glow
	ring.position.y = 0.02
	s.pod.add_child(ring)
	s.yaw = Node3D.new()
	s.yaw.position.y = 0.03
	s.pod.add_child(s.yaw)
	s.pitch = Node3D.new()
	s.yaw.add_child(s.pitch)
	s.flash = OmniLight3D.new()
	s.flash.omni_range = 3.0
	s.flash.light_energy = 0.0
	s.pitch.add_child(s.flash)


func _equip(s: Slot, id: String, level: int) -> void:
	if s.gun:
		s.gun.queue_free()
	_clear_beam(s)
	s.id = id
	s.level = level
	s.cd = randf() * 0.3
	s.gun = Weapons.model(id)
	s.pitch.add_child(s.gun)
	s.muzzle = s.gun.get_node("Muzzle")
	s.flash.light_color = Weapons.DEFS[id].color
	s.flash.position = s.muzzle.position


## Picks up a weapon. Returns [slot name, level, replaced id or ""].
func add_weapon(id: String) -> Array:
	for s in slots:                                 # same weapon: level it up
		if s.id == id and s.level < Weapons.MAX_LEVEL:
			s.level += 1
			return [s.name, s.level, ""]
	# Empty mount: corners first, then seats.
	for want_seat in [false, true]:
		for s in slots:
			if s.id == "" and s.seat == want_seat:
				_equip(s, id, 1)
				return [s.name, 1, ""]
	# Full: replace the weakest if this is at least as good.
	var weakest: Slot = null
	for s in slots:
		if weakest == null or _power(s.id, s.level) < _power(weakest.id, weakest.level):
			weakest = s
	if weakest and Weapons.DEFS[id].tier >= Weapons.DEFS[weakest.id].tier:
		var old := weakest.id
		_equip(weakest, id, 1)
		return [weakest.name, 1, old]
	# Otherwise it tops up the weakest weapon instead.
	weakest.level = mini(weakest.level + 1, Weapons.MAX_LEVEL)
	return [weakest.name, weakest.level, ""]


static func _power(id: String, level: int) -> float:
	return Weapons.DEFS[id].tier * 2.0 + level


# ------------------------------------------------------------------ firing

func _physics_process(delta: float) -> void:
	if not enabled or combat.wrecked > 0.0:
		for s in slots:
			_clear_beam(s)
		return
	for s in slots:
		if s.id == "":
			continue
		var d: Dictionary = Weapons.DEFS[s.id]
		s.cd -= delta
		s.scan -= delta
		if s.scan <= 0.0:
			s.scan = SCAN
			s.target = _pick(s, d)
		if s.target == null or not is_instance_valid(s.target) or s.target.dead:
			s.target = null
			_clear_beam(s)
			_aim(s, s.pod.global_position - car.global_basis.z * 10.0, delta)
			continue
		var muzzle: Vector3 = s.muzzle.global_position
		var tp: Vector3 = s.target.global_position
		var aim: Vector3 = tp
		if d.kind == "bolt" or d.kind == "frost" or d.kind == "rocket":
			var speed: float = combat.PROJECTILE_SPEED[d.kind]
			aim = tp + (s.target.linear_velocity - car.linear_velocity) * (muzzle.distance_to(tp) / speed)
		var err := _aim(s, aim, delta)
		if d.kind == "beam":
			_beam(s, d, delta)
			continue
		if s.cd > 0.0 or err > deg_to_rad(14.0):
			continue
		s.cd = Weapons.stat(s.id, "interval", s.level)
		s.recoil = 1.0
		s.flash.light_energy = 3.0
		_fire(s, d, muzzle, aim)


func _fire(s: Slot, d: Dictionary, muzzle: Vector3, aim: Vector3) -> void:
	var dmg := Weapons.stat(s.id, "dmg", s.level)
	var dir := (aim - muzzle).normalized()
	var c: Color = d.color
	match d.kind:
		"bolt":
			combat.fire_bolt(muzzle, dir, dmg, d.splash, c)
		"frost":
			combat.fire_frost(muzzle, dir, dmg, d.splash)
		"rocket":
			combat.fire_rocket(muzzle, dir, dmg, d.splash)
		"hitscan":
			combat.hitscan(muzzle, s.target, dmg, c, s.id == "sniper")
		"pellets":
			combat.pellets(muzzle, s.target, dmg, int(d.pellets), c)
		"missiles":
			var targets := _nearest_list(s.muzzle.global_position, d.range, int(d.count))
			for k in int(d.count):
				var t: Node = targets[k % targets.size()] if not targets.is_empty() else s.target
				combat.fire_missile(muzzle, dir, t, dmg, d.splash, k)
		"chain":
			combat.chain_lightning(muzzle, s.target, dmg, int(d.chains), d.chain_r, c)
		"saw":
			combat.fire_saw(muzzle, s.target, dmg, int(d.bounces))


## Plasma: a continuous beam onto the target, damage per second.
func _beam(s: Slot, d: Dictionary, delta: float) -> void:
	if s.beam == null:
		s.beam = _beam_mesh(0.05, _beam_mat)
		s.beam_core = _beam_mesh(0.018, _beam_core_mat)
	var a: Vector3 = s.muzzle.global_position
	var b: Vector3 = s.target.global_position
	for m in [s.beam, s.beam_core]:
		m.visible = true
		var len := a.distance_to(b)
		var flick := 1.0 + 0.25 * sin(Time.get_ticks_msec() * 0.06)
		m.global_transform = Transform3D(Basis.looking_at(b - a, Vector3.UP if absf((b - a).normalized().y) < 0.98 else Vector3.RIGHT) * Basis(Vector3.RIGHT, PI * 0.5), (a + b) * 0.5)
		m.scale = Vector3(flick, len, flick)
	s.flash.light_energy = 2.0 + randf()
	s.beam_tick -= delta
	combat.beam_damage(s.target, Weapons.stat(s.id, "dmg", s.level) * delta, b, s.beam_tick <= 0.0)
	if s.beam_tick <= 0.0:
		s.beam_tick = 0.12


func _beam_mesh(r: float, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = 1.0
	cm.radial_segments = 8
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = m
	mi.top_level = true
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


func _clear_beam(s: Slot) -> void:
	if s.beam:
		s.beam.visible = false
		s.beam_core.visible = false


func _process(delta: float) -> void:
	for s in slots:
		if s.gun == null:
			continue
		s.recoil = move_toward(s.recoil, 0.0, delta * 7.0)
		s.gun.position.z = s.recoil * 0.06
		if s.beam == null or not s.beam.visible:
			s.flash.light_energy = move_toward(s.flash.light_energy, 0.0, delta * 20.0)
		var spin := s.gun.get_node_or_null("Spin")
		if spin:
			(spin as Node3D).rotate_y(delta * 20.0)


## Nearest visible enemy in range (the sniper takes the toughest instead).
func _pick(s: Slot, d: Dictionary) -> Node:
	var from: Vector3 = s.muzzle.global_position
	var best: Node = null
	var best_score := INF
	var space := get_world_3d().direct_space_state
	var rng: float = d.range
	for e in combat.enemies():
		var dist := from.distance_to(e.global_position)
		if dist > rng:
			continue
		var score: float = -e.hp if d.get("toughest", false) else dist
		if score >= best_score:
			continue
		var q := PhysicsRayQueryParameters3D.create(from, e.global_position, 1, [car.get_rid()])
		if space.intersect_ray(q).is_empty():
			best = e
			best_score = score
	return best


func _nearest_list(from: Vector3, rng: float, n: int) -> Array:
	var list: Array = combat.enemies().filter(func(e) -> bool: return from.distance_to(e.global_position) < rng)
	list.sort_custom(func(a, b) -> bool: return from.distance_to(a.global_position) < from.distance_to(b.global_position))
	return list.slice(0, n)


## Turns a mount toward a world point; returns the remaining aim error.
func _aim(s: Slot, point: Vector3, delta: float) -> float:
	var local := s.pod.global_transform.affine_inverse() * point
	var want_yaw := atan2(-local.x, -local.z)
	var want_pitch := clampf(atan2(local.y, Vector2(local.x, local.z).length()), -0.4, 1.2)
	var k := 1.0 - exp(-16.0 * delta)
	s.yaw.rotation.y = lerp_angle(s.yaw.rotation.y, want_yaw, k)
	s.pitch.rotation.x = lerp_angle(s.pitch.rotation.x, want_pitch, k)
	if s.muzzle == null:
		return PI
	return (-s.pitch.global_basis.z).angle_to(point - s.muzzle.global_position)
