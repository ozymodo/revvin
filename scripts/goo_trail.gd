extends MultiMeshInstance3D
## Tyre trails for every car, laid behind the rear tyres: the Symbiote's
## goo and vines, the Neon's light ribbon, the Phantom's spectral mist
## (goo_trail.gdshader). One MultiMesh ring buffer; each segment carries
## the time it was laid, the car's style and its speed, so the shader can
## grow, animate and fade it, and the look changes with speed along the
## trail. Segments get longer at speed so the buffer covers the same time.

const MAX_SEGMENTS := 3000
const SEGMENT := 0.35
const WIDTH := 1.2                   # the shader draws narrower trails inside it
const SHADER := preload("res://scripts/goo_trail.gdshader")

var _next := 0
var _mat: ShaderMaterial
var _last := {}
var _dist := {}


func _ready() -> void:
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	plane.material = mat
	_mat = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = plane
	mm.instance_count = MAX_SEGMENTS
	mm.visible_instance_count = 0
	multimesh = mm
	custom_aabb = AABB(Vector3(-2000, -200, -2000), Vector3(4000, 400, 4000))


func _process(_delta: float) -> void:
	_mat.set_shader_parameter("now", Time.get_ticks_msec() / 1000.0)


## Speed share 0..1 at which the trail is "flat out" (~250 km/h).
const FULL_SPEED := 70.0


func add_point(trail: int, pos: Vector3, normal: Vector3, intensity: float, style := 0, speed := 0.0) -> void:
	if intensity <= 0.0:
		_last.erase(trail)
		return
	if not _last.has(trail):
		_last[trail] = pos
		return
	var prev: Vector3 = _last[trail]
	var d := pos - prev
	if d.length() < maxf(SEGMENT, speed * 0.012):
		return
	if d.length() > 3.0:
		_last[trail] = pos
		return
	var y := normal.normalized()
	var x := y.cross(d).normalized() * WIDTH
	var xf := Transform3D(Basis(x, y, d), (pos + prev) * 0.5 + y * 0.025)
	var along: float = _dist.get(trail, 0.0)
	_dist[trail] = along + d.length()
	var now := Time.get_ticks_msec() / 1000.0
	multimesh.set_instance_transform(_next, xf)
	multimesh.set_instance_custom_data(_next, Color(now, style + randf() * 0.99, along, clampf(speed / FULL_SPEED, 0.0, 1.0)))
	_next = (_next + 1) % MAX_SEGMENTS
	multimesh.visible_instance_count = maxi(multimesh.visible_instance_count, _next if _next > 0 else MAX_SEGMENTS)
	_last[trail] = pos
