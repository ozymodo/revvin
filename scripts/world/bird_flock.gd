extends Node3D
## A flock circling over the ruins. Birds flap, glide, and scatter upward
## when the car comes through fast or fires its jets beneath them.

const MODEL := preload("res://assets/world/bird.glb")

var count := 10
var radius := 18.0

var _birds := []
var _scatter := 0.0
var _car: RigidBody3D


func _ready() -> void:
	for i in count:
		var b: Node3D = MODEL.instantiate()
		b.scale = Vector3.ONE * 2.2
		add_child(b)
		_birds.append({
			"node": b,
			"wl": b.find_child("Wing_L", true, false),
			"wr": b.find_child("Wing_R", true, false),
			"angle": randf() * TAU,
			"r": radius * randf_range(0.6, 1.3),
			"h": randf_range(-4.0, 4.0),
			"spd": randf_range(0.35, 0.6) * (1.0 if randf() < 0.85 else -1.0),
			"phase": randf() * TAU,
		})


func _process(delta: float) -> void:
	if _car == null:
		_car = get_tree().get_first_node_in_group("player_car")
	if _car:
		var d := global_position - _car.global_position
		var flat := Vector2(d.x, d.z).length()
		if flat < 45.0 and (_car.linear_velocity.length() > 18.0 or _car.jet_output > 0.05 or absf(d.y) < 10.0):
			_scatter = 1.0
	_scatter = maxf(_scatter - delta * 0.12, 0.0)
	var s := smoothstep(0.0, 1.0, _scatter)
	var t := Time.get_ticks_msec() * 0.001
	for b in _birds:
		b.angle += b.spd * delta * (1.0 + s * 1.5)
		var r: float = b.r * (1.0 + s * 1.8)
		var pos := Vector3(cos(b.angle) * r, b.h + s * 30.0 + sin(b.angle * 2.0 + b.phase) * 1.5, sin(b.angle) * r)
		var node: Node3D = b.node
		var vel := pos - node.position
		node.position = pos
		if vel.length() > 0.001:
			node.basis = Basis.looking_at(vel.normalized(), Vector3.UP).scaled(Vector3.ONE * 2.2)
		# Flap in bursts, glide in between (always flapping while scattering).
		var gliding := sin(t * 0.7 + b.phase) > 0.4 and s < 0.1
		var flap := 0.15 if gliding else sin(t * (11.0 + s * 6.0) + b.phase) * 0.8
		if b.wl:
			b.wl.rotation.z = flap
		if b.wr:
			b.wr.rotation.z = -flap
