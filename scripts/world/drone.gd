extends Node3D
## A dormant security drone still hovering on standby. It bobs, slowly
## turns, and when the car comes close it tracks it with its red eye.

const MODEL := preload("res://assets/world/drone.glb")

var _eye_mat: StandardMaterial3D
var _base := Vector3.ZERO
var _t := 0.0
var _car: Node3D


func _ready() -> void:
	var m: Node3D = MODEL.instantiate()
	add_child(m)
	_base = position
	_t = randf() * 10.0
	rotation.y = randf() * TAU
	for mi in m.find_children("*", "MeshInstance3D", true, false):
		for s in mi.mesh.get_surface_count():
			var mat: Material = mi.mesh.surface_get_material(s)
			if mat and mat.resource_name == "DroneEye":
				_eye_mat = mat.duplicate()
				mi.set_surface_override_material(s, _eye_mat)
	Lod.add_agent(self, 40.0)


func _process(delta: float) -> void:
	_t += delta
	position = _base + Vector3(sin(_t * 0.3) * 0.6, sin(_t * 1.1) * 0.35, cos(_t * 0.27) * 0.6)
	if _car == null:
		_car = get_tree().get_first_node_in_group("player_car")
	var watching := false
	if _car:
		var to := _car.global_position - global_position
		if to.length() < 30.0:
			watching = true
			var flat := Vector3(to.x, 0, to.z)
			if flat.length() > 0.5:
				var want := atan2(-flat.x, -flat.z)      # the eye is on the drone's -Z side
				rotation.y = lerp_angle(rotation.y, want, 1.0 - exp(-3.0 * delta))
	if not watching:
		rotation.y += delta * 0.15
	if _eye_mat:
		var blink := 1.0 if fmod(_t, 2.6) > 0.15 else 0.1
		_eye_mat.emission_energy_multiplier = (14.0 if watching else 5.0) * blink
