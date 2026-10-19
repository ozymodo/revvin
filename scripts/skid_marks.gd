extends MultiMeshInstance3D
## Skid marks: one thin quad per segment, drawn from a ring buffer in a
## single MultiMesh so thousands of marks cost one draw call. Marks follow
## the surface normal, so they work on walls and loops too.

const MAX_SEGMENTS := 4096
const SEGMENT_MIN := 0.3        # metres between points
const WIDTH := 0.24

var _next := 0
var _last := {}                 # wheel index -> last point (Vector3)


func _ready() -> void:
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.03, 0.03, 0.035)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	plane.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = plane
	mm.instance_count = MAX_SEGMENTS
	mm.visible_instance_count = 0
	multimesh = mm
	custom_aabb = AABB(Vector3(-2000, -200, -2000), Vector3(4000, 400, 4000))


## Called every physics tick per wheel. intensity 0 ends the current mark.
func add_point(wheel: int, pos: Vector3, normal: Vector3, intensity: float) -> void:
	if intensity <= 0.0:
		_last.erase(wheel)
		return
	if not _last.has(wheel):
		_last[wheel] = pos
		return
	var prev: Vector3 = _last[wheel]
	var d := pos - prev
	if d.length() < SEGMENT_MIN:
		return
	if d.length() > 3.0:            # teleport or jump: start a fresh mark
		_last[wheel] = pos
		return
	var z := d
	var x := normal.cross(z).normalized() * WIDTH
	var y := normal.normalized()
	var xf := Transform3D(Basis(x, y, z), (pos + prev) * 0.5 + y * 0.02)
	multimesh.set_instance_transform(_next, xf)
	multimesh.set_instance_color(_next, Color(1, 1, 1, clampf(intensity, 0.3, 0.85)))
	_next = (_next + 1) % MAX_SEGMENTS
	multimesh.visible_instance_count = maxi(multimesh.visible_instance_count, _next if _next > 0 else MAX_SEGMENTS)
	_last[wheel] = pos
