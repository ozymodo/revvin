extends Node3D
## A destructible structure built from box cells ("voxels"): the mega-block
## buildings and crate stacks. Every cell is drawn through one MultiMesh per
## material and has its own box collider (grouped into chunk bodies so a
## change only rebuilds a small part).
##
## Cells break when the car drives into them fast enough for their material
## (glass and crates almost always, concrete only at speed), in explosions,
## and when enemies smash into them. A broken cell bursts into voxel debris.
## Cells left hanging with nothing under them and little beside them fall too.

signal emptied()                    # every cell broken (crate stacks)
signal cell_broken(at: Vector3, kind: int)

enum Kind { CONCRETE, GLASS, SLAB, CRATE, STEEL }
## [colour, car speed to break (m/s), blast power to break, debris colour, debris glow]
const KINDS := [
	[Color(0.44, 0.44, 0.42), 16.0, 3.0, Color(0.5, 0.5, 0.48), 0.0],
	[Color(0.5, 0.78, 0.95, 0.32), 1.5, 0.4, Color(0.6, 0.85, 1.0, 0.6), 0.0],
	[Color(0.3, 0.31, 0.33), 999.0, 5.0, Color(0.38, 0.38, 0.4), 0.0],
	[Color(0.6, 0.44, 0.24), 3.0, 0.6, Color(0.62, 0.46, 0.26), 0.0],
	[Color(0.2, 0.22, 0.26), 26.0, 4.5, Color(0.3, 0.32, 0.36), 0.0],
]
const CHUNK := 6

var debris: Node                    # world/debris.gd
var sub_cubes := 3                  # debris cubes per broken cell (max)

var grid := {}                      # Vector3i -> cell index
var pos := PackedVector3Array()     # cell centres, local
var size := PackedVector3Array()
var kind := PackedByteArray()
var alive := PackedByteArray()
var cell_grid: Array[Vector3i] = []
var _mm_index := PackedInt32Array()
var _shapes: Array[CollisionShape3D] = []
var _mms := {}                      # kind -> MultiMesh
var _bodies := {}
var _alive_count := 0
var _box_shapes := {}
var _lookup := {}                   # coarse spatial hash: Vector3i -> [cell indices]
const LOOKUP := 3.0
var aabb := AABB()
var _attached := {}                 # cell index -> [Node3D] that go when it breaks (lights, panels)

## Voxel look: every face gets a darker bevel line round its edges, and
## each instance a slight shade of its own, so walls read as stacked blocks.
const VOXEL_SHADER := """
shader_type spatial;
uniform vec4 albedo : source_color = vec4(0.5, 0.5, 0.5, 1.0);
uniform float roughness = 0.8;
uniform float metallic = 0.0;
uniform vec3 glow = vec3(0.0);
uniform float edge = 0.08;
varying vec3 lp;
varying vec3 sc;
varying float shade;
void vertex() {
	lp = VERTEX;
	sc = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	vec3 o = MODEL_MATRIX[3].xyz;
	shade = fract(sin(dot(o, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
}
void fragment() {
	vec3 d = (0.5 - abs(lp)) * sc;
	float mn = min(d.x, min(d.y, d.z));
	float mx = max(d.x, max(d.y, d.z));
	float mid = d.x + d.y + d.z - mn - mx;
	float e = 1.0 - smoothstep(edge * 0.4, edge, mid);
	ALBEDO = albedo.rgb * (0.88 + 0.2 * shade) * (1.0 - 0.38 * e);
	ROUGHNESS = roughness;
	METALLIC = metallic;
	EMISSION = glow;
}
"""


## Adds a cell at integer grid coords `g` (used for neighbours), centred at
## `centre` (local), of `extent` metres.
func add_cell(g: Vector3i, centre: Vector3, extent: Vector3, k: int) -> void:
	var i := pos.size()
	grid[g] = i
	cell_grid.append(g)
	pos.append(centre)
	size.append(extent)
	kind.append(k)
	alive.append(1)
	var lk := Vector3i(floori(centre.x / LOOKUP), floori(centre.y / LOOKUP), floori(centre.z / LOOKUP))
	if not _lookup.has(lk):
		_lookup[lk] = []
	_lookup[lk].append(i)


func finish() -> void:
	var counts := {}
	for k in kind:
		counts[k] = counts.get(k, 0) + 1
	for k in counts:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		var box := BoxMesh.new()
		box.size = Vector3.ONE
		mm.mesh = box
		mm.instance_count = counts[k]
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = _material(k)
		if k == Kind.GLASS:
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)
		_mms[k] = [mm, 0]
	_mm_index.resize(pos.size())
	for i in pos.size():
		var entry: Array = _mms[kind[i]]
		_mm_index[i] = entry[1]
		(entry[0] as MultiMesh).set_instance_transform(entry[1], Transform3D(Basis().scaled(size[i]), pos[i]))
		entry[1] += 1
		var g := cell_grid[i]
		var ck := Vector3i(floori(g.x / float(CHUNK)), floori(g.y / 2.0), floori(g.z / float(CHUNK)))
		if not _bodies.has(ck):
			var body := StaticBody3D.new()
			add_child(body)
			_bodies[ck] = body
		var cs := CollisionShape3D.new()
		cs.shape = _box(size[i])
		cs.position = pos[i]
		(_bodies[ck] as StaticBody3D).add_child(cs)
		_shapes.append(cs)
		aabb = AABB(pos[i], Vector3.ZERO) if i == 0 else aabb.expand(pos[i] - size[i] * 0.5).expand(pos[i] + size[i] * 0.5)
	_alive_count = pos.size()


func _box(s: Vector3) -> BoxShape3D:
	var key := s.snapped(Vector3.ONE * 0.01)
	if not _box_shapes.has(key):
		var b := BoxShape3D.new()
		b.size = s
		_box_shapes[key] = b
	return _box_shapes[key]


static var _mats := {}
static var _shader: Shader
static var _vmats := {}

## The blocky voxel material in colour `c` (shared, cached).
static func voxel_material(c: Color, rough := 0.8, metal := 0.0, glow := 0.0) -> ShaderMaterial:
	var key := "%s|%.2f|%.2f|%.1f" % [c.to_html(), rough, metal, glow]
	if _vmats.has(key):
		return _vmats[key]
	if _shader == null:
		_shader = Shader.new()
		_shader.code = VOXEL_SHADER
	var m := ShaderMaterial.new()
	m.shader = _shader
	m.set_shader_parameter("albedo", c)
	m.set_shader_parameter("roughness", rough)
	m.set_shader_parameter("metallic", metal)
	m.set_shader_parameter("glow", Vector3(c.r, c.g, c.b) * glow)
	_vmats[key] = m
	return m


static func _material(k: int) -> Material:
	if _mats.has(k):
		return _mats[k]
	var c: Color = KINDS[k][0]
	if k != Kind.GLASS:
		_mats[k] = voxel_material(c, 0.35 if k == Kind.STEEL else 0.85, 0.85 if k == Kind.STEEL else 0.0)
		return _mats[k]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.8
	match k:
		Kind.GLASS:
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.metallic = 0.7
			m.roughness = 0.05
			m.rim_enabled = true
			m.rim = 0.5
			m.emission_enabled = true
			m.emission = Color(0.2, 0.45, 0.7)
			m.emission_energy_multiplier = 0.25
		Kind.STEEL:
			m.metallic = 0.85
			m.roughness = 0.35
		Kind.CRATE:
			m.roughness = 0.9
	_mats[k] = m
	return m


## `node` (a child of this structure) goes when cell `i` breaks.
func attach(i: int, node: Node3D) -> void:
	if not _attached.has(i):
		_attached[i] = []
	_attached[i].append(node)


func world_aabb() -> AABB:
	return global_transform * aabb


## Live cells whose box comes within `r` of the world segment a-b, above
## world height `min_y` (so the floor under the car isn't counted).
func cells_on_segment(a: Vector3, b: Vector3, r: float, min_y: float) -> Array:
	var inv := global_transform.affine_inverse()
	var la := inv * a
	var lb := inv * b
	var out := []
	var lo := Vector3i(floori((minf(la.x, lb.x) - r - 2.0) / LOOKUP), floori((minf(la.y, lb.y) - r - 2.0) / LOOKUP), floori((minf(la.z, lb.z) - r - 2.0) / LOOKUP))
	var hi := Vector3i(floori((maxf(la.x, lb.x) + r + 2.0) / LOOKUP), floori((maxf(la.y, lb.y) + r + 2.0) / LOOKUP), floori((maxf(la.z, lb.z) + r + 2.0) / LOOKUP))
	for x in range(lo.x, hi.x + 1):
		for y in range(lo.y, hi.y + 1):
			for z in range(lo.z, hi.z + 1):
				var key := Vector3i(x, y, z)
				if not _lookup.has(key):
					continue
				for i in _lookup[key]:
					if alive[i] == 0:
						continue
					var c := pos[i]
					var half := size[i] * 0.5
					if (global_transform * (c + Vector3.UP * half.y)).y < min_y:
						continue
					var q := Geometry3D.get_closest_point_to_segment(c, la, lb)
					var d := (q - c).abs() - half
					if maxf(d.x, maxf(d.y, d.z)) < r:
						out.append(i)
	return out


## Live cells within `r` of a world point.
func cells_near(at: Vector3, r: float) -> Array:
	return cells_on_segment(at, at, r, -INF)


func break_cell(i: int, vel: Vector3) -> void:
	if alive[i] == 0:
		return
	alive[i] = 0
	_alive_count -= 1
	var entry: Array = _mms[kind[i]]
	(entry[0] as MultiMesh).set_instance_transform(_mm_index[i], Transform3D(Basis().scaled(Vector3.ZERO), pos[i]))
	_shapes[i].disabled = true
	var at := global_transform * pos[i]
	var k: Array = KINDS[kind[i]]
	if _attached.has(i):
		for n in _attached[i]:
			if is_instance_valid(n):
				(n as Node).queue_free()
		_attached.erase(i)
	if debris:
		var s := size[i]
		if kind[i] == Kind.GLASS:
			# Glass goes in a spray of small shards.
			debris.burst(at, sub_cubes * 2, 0.3, k[3], vel, 5.0, s * 0.45, k[4])
		else:
			var cube := minf(minf(s.x, s.y), s.z)
			cube = clampf(maxf(cube, maxf(s.x, maxf(s.y, s.z)) * 0.45), 0.25, 1.4)
			debris.burst(at, mini(sub_cubes, 1 + int(s.x * s.y * s.z / (cube * cube * cube))), cube, k[3], vel, 4.0, s * 0.35, k[4])
	cell_broken.emit(at, kind[i])
	if _alive_count <= 0:
		emptied.emit()


## Breaks the given cells with `vel`, then lets anything left hanging fall.
func break_cells(list: Array, vel: Vector3) -> void:
	var touched := []
	for i in list:
		if alive[i] == 1:
			break_cell(i, vel)
			touched.append(i)
	_settle(touched)


## Cells above a gap with almost nothing beside them come down too.
func _settle(broken: Array) -> void:
	var queue := broken.duplicate()
	var steps := 0
	while not queue.is_empty() and steps < 60:
		steps += 1
		var i: int = queue.pop_front()
		var g := cell_grid[i]
		for dy in [1, 2]:
			var above := g + Vector3i(0, dy, 0)
			if not grid.has(above):
				continue
			var j: int = grid[above]
			if alive[j] == 0 or kind[j] == Kind.SLAB:
				continue
			if _supported(cell_grid[j]):
				continue
			break_cell(j, Vector3.DOWN * 2.0)
			queue.append(j)


func _supported(g: Vector3i) -> bool:
	var below := g + Vector3i(0, -1, 0)
	if not grid.has(below) and g.y == 0:
		return true                  # on the ground
	if grid.has(below) and alive[grid[below]] == 1:
		return true
	var sides := 0
	for d in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
		var n: Vector3i = g + d
		if grid.has(n) and alive[grid[n]] == 1:
			sides += 1
	return sides >= 2


## A blast: cells within `r` break if the power reaching them beats their toughness.
func explode(at: Vector3, r: float, power: float) -> int:
	var hit := []
	for i in cells_near(at, r):
		var d := (global_transform * pos[i]).distance_to(at)
		if power * (1.0 - d / (r + 0.01)) >= KINDS[kind[i]][2]:
			hit.append(i)
	for i in hit:
		var dir := ((global_transform * pos[i]) - at).normalized()
		break_cell(i, dir * clampf(power * 2.0, 3.0, 14.0))
	_settle(hit)
	return hit.size()
