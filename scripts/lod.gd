extends Node
## Dynamic level of detail (autoload "Lod"). The world gets cheaper the
## further it is from the camera, and a governor trades detail for frame
## rate when the frame budget runs out.
##
## What registers here:
##   draw distances   visibility ranges and light fades (draw_distance)
##   LOD tiers        near/far versions of the same chunk (city.scatter)
##   grass            per-chunk density that thins with distance (add_grass)
##   agents           animals, drones, flocks and signs update less often
##                    the further away they are (add_agent)
##   shaders          read the global `lod_detail` and drop their fine
##                    detail (cracks, veins, vines) sooner when it's low
##
## Every distance is multiplied by scale() = quality (the "Level of detail"
## setting) * detail (the governor, MIN_DETAIL..1). With "Dynamic detail"
## on, the governor lowers `detail` when frames run over budget and raises
## it again when there's headroom, aiming for target_fps: 120 on desktop,
## 60 on phones, tablets and handhelds (and never above the refresh rate or
## the frame rate limit).

signal detail_changed

## Setting "lod" (Low, Medium, High, Ultra) -> distance multiplier.
const QUALITY := [0.6, 0.8, 1.0, 1.35]
## Setting "lod" -> base mesh LOD threshold (pixels of error allowed).
const LOD_THRESHOLD := [4.0, 2.0, 1.0, 0.5]
const MIN_DETAIL := 0.5
const STEP_UP := 0.05
const APPLY_PER_FRAME := 500        # registered nodes re-applied per frame after a change
const FAR_SHADER := preload("res://scripts/world/far.gdshader")

var quality := 1.0
var detail := 1.0
var dynamic := true
var target_fps := 120.0
## Camera position this frame (agents and managers use it for distance checks).
var cam_pos := Vector3.ZERO
## Off in scripted tests: every agent runs every frame, as it always did.
var sim_lod := true

var _lod_index := 2
var _shadow_base := 0.0
var _sun: DirectionalLight3D

var _ranges: Array = []             # [node, end, begin, min_end, min_begin]
var _agents: Array = []             # [node, accumulated delta, near distance]
var _grass: Array = []              # [MultiMesh, centre, full count, shown]
var _grass_cursor := 0
var _far_cache := {}                # Mesh -> its far stand-in
var _far_mat: ShaderMaterial
var _applied := -1.0
var _applying := -1.0
var _cursor := 0

# governor
var _warmup := 3.0
var _win_t := 0.0
var _win_n := 0
var _win_sum := 0.0
var _win_slow := 0
var _good := 0
var _ceiling := 1.0
var _ceiling_t := 0.0
var _raised_t := 99.0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--test="):
			sim_lod = false
	RenderingServer.global_shader_parameter_set("lod_detail", 1.0)


## Forgets every registered node (the scene is about to be rebuilt).
func reset() -> void:
	_ranges.clear()
	_agents.clear()
	_grass.clear()
	_grass_cursor = 0
	_cursor = 0
	_applying = -1.0
	_sun = null
	_warmup = 3.0


func scale() -> float:
	return quality * detail


## The "Level of detail" setting (0 Low .. 3 Ultra) and "Dynamic detail".
func configure(lod_index: int, dynamic_on: bool) -> void:
	_lod_index = clampi(lod_index, 0, QUALITY.size() - 1)
	quality = QUALITY[_lod_index]
	dynamic = dynamic_on
	if not dynamic:
		detail = 1.0
	_ceiling = 1.0
	_refresh()


## Shadow distance from the shadow-quality setting; the governor shortens it
## a little when detail drops.
func set_sun(sun: DirectionalLight3D, max_distance: float) -> void:
	_sun = sun
	_shadow_base = max_distance
	_refresh()


# ------------------------------------------------------------------ registry

## Draws `node` out to `end` metres (and from `begin`, for the far tier of a
## LOD pair), scaled by scale() but never under `min_end` (things the player
## steers by) or `min_begin` (the near tier's own floor, so the pair never
## leaves a gap). A light fades out instead. Anything else applies to every
## GeometryInstance3D and light under it. Distances are measured from the
## node's origin, so a MultiMesh should sit in the middle of its instances.
func draw_distance(node: Node, end: float, begin := 0.0, min_end := 0.0, min_begin := 0.0) -> void:
	if node is GeometryInstance3D or node is Light3D:
		_ranges.append([node, end, begin, min_end, min_begin])
		_apply_range(node, end, begin, min_end, min_begin, scale())
	else:
		for n in node.find_children("*", "", true, false):
			if n is GeometryInstance3D or n is Light3D:
				draw_distance(n, end, begin, min_end, min_begin)


## Animals, drones and the like: Lod calls the node's _process itself, every
## frame within `near` metres of the camera and less often further out. A
## node can define lod_awake() -> bool to ask for every frame regardless
## (an animal mid-fight).
func add_agent(node: Node, near := 60.0) -> void:
	if not sim_lod:
		return
	node.set_process(false)
	_agents.append([node, randf() * 0.1, near])


## A grass chunk: shows fewer clumps the further away it is. The clumps
## must be in random order, so any prefix is an even thinning.
func add_grass(mmi: MultiMeshInstance3D, centre: Vector3) -> void:
	var mm := mmi.multimesh
	_grass.append([mm, centre, mm.instance_count, -2])


## True within `r` metres (times scale(), at least `min_end`) of the camera:
## managers skip the animation of things too far away to see.
func near(pos: Vector3, r: float, min_end := 0.0) -> bool:
	var k := maxf(r * scale(), min_end)
	return pos.distance_squared_to(cam_pos) < k * k


# ------------------------------------------------------------------ meshes

## A cheap stand-in for `mesh` at a distance: every surface merged into one
## (each material's colour and glow baked into the vertices, so it's one
## draw call), then simplified to roughly `keep` of its triangles. The
## world's materials are all flat colours, so from afar it looks the same.
func far_mesh(mesh: Mesh, keep := 0.4) -> ArrayMesh:
	if _far_cache.has(mesh):
		return _far_cache[mesh]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tris := 0
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		var c := _bake_color(mesh.surface_get_material(s))
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] else PackedInt32Array(range(verts.size()))
		for i in idx:
			st.set_color(c)
			st.set_normal(norms[i])
			st.add_vertex(verts[i])
		tris += idx.size() / 3
	st.index()
	var arr := st.commit_to_arrays()
	# Simplify: the LOD closest to `keep` of the triangles.
	var im := ImporterMesh.new()
	im.add_surface(Mesh.PRIMITIVE_TRIANGLES, arr)
	im.generate_lods(60.0, 60.0, [])
	var best := -1
	for l in im.get_surface_lod_count(0):
		if im.get_surface_lod_indices(0, l).size() / 3 >= tris * keep:
			best = l
	if best >= 0:
		arr[Mesh.ARRAY_INDEX] = im.get_surface_lod_indices(0, best)
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	if _far_mat == null:
		_far_mat = ShaderMaterial.new()
		_far_mat.shader = FAR_SHADER
	out.surface_set_material(0, _far_mat)
	_far_cache[mesh] = out
	return out


## sRGB albedo in rgb, glow in alpha (see far.gdshader).
static func _bake_color(m: Material) -> Color:
	var alb := Color(0.5, 0.5, 0.5)
	var glow := 0.0
	if m is BaseMaterial3D:
		var b := m as BaseMaterial3D
		alb = b.albedo_color
		if b.emission_enabled:
			var e := b.emission.srgb_to_linear() * b.emission_energy_multiplier
			glow = e.get_luminance() / maxf(alb.srgb_to_linear().get_luminance(), 0.02)
	elif m is ShaderMaterial:
		var v: Variant = (m as ShaderMaterial).get_shader_parameter("albedo")
		if v is Color:
			alb = v
	return Color(alb.r, alb.g, alb.b, clampf(glow / 16.0, 0.0, 1.0))


# ------------------------------------------------------------------ per frame

func _process(delta: float) -> void:
	var vp := get_viewport()
	var cam := vp.get_camera_3d()
	if cam:
		cam_pos = cam.global_position
	_govern(delta)
	_update_agents(delta)
	_update_grass()
	_apply_some()


func _update_agents(delta: float) -> void:
	var s := scale()
	var i := 0
	while i < _agents.size():
		var a: Array = _agents[i]
		# Check before the typed assignment: a freed object can't be assigned to Node3D.
		if not is_instance_valid(a[0]):
			_agents.remove_at(i)
			continue
		var n: Node3D = a[0]
		i += 1
		if not n.is_inside_tree() or not n.can_process():
			continue
		a[1] += delta
		var d := n.global_position.distance_to(cam_pos)
		var near_d: float = a[2] * maxf(s, 0.6)
		# Every frame up close, then 30, 12 and 4 updates a second.
		var period := 0.0
		if d > near_d * 5.0:
			period = 0.25
		elif d > near_d * 2.5:
			period = 1.0 / 12.0
		elif d > near_d:
			period = 1.0 / 30.0
		if period > 0.0 and n.has_method("lod_awake") and n.lod_awake():
			period = 0.0
		if a[1] >= period:
			var dt: float = minf(a[1], 0.25)
			a[1] = 0.0
			n.call(&"_process", dt)


## Thins grass with distance: full density close by, a third at the edge.
## A slice of chunks per frame; it only touches a chunk when its count moves.
func _update_grass() -> void:
	if _grass.is_empty():
		return
	var s := scale()
	var full_r := 40.0 * s
	var end_r := 150.0 * s
	var cam2 := Vector2(cam_pos.x, cam_pos.z)
	for k in mini(60, _grass.size()):
		_grass_cursor = (_grass_cursor + 1) % _grass.size()
		var g: Array = _grass[_grass_cursor]
		var c: Vector3 = g[1]
		var d := Vector2(c.x, c.z).distance_to(cam2)
		var f := 1.0 - 0.67 * clampf((d - full_r) / maxf(end_r - full_r, 1.0), 0.0, 1.0)
		var shown := int(ceil(g[2] * snappedf(f, 0.1)))
		if shown != g[3]:
			g[3] = shown
			(g[0] as MultiMesh).visible_instance_count = shown


# ------------------------------------------------------------------ applying

func _refresh() -> void:
	var s := scale()
	RenderingServer.global_shader_parameter_set("lod_detail", s)
	var vp := get_viewport()
	if vp:
		vp.mesh_lod_threshold = LOD_THRESHOLD[_lod_index] / detail
	if _sun and _sun.shadow_enabled:
		_sun.directional_shadow_max_distance = _shadow_base * lerpf(0.7, 1.0, inverse_lerp(MIN_DETAIL, 1.0, detail))
	# Ranges: re-applied a slice per frame (thousands of nodes).
	if absf(s - _applied) > 0.001:
		_applying = s
		_cursor = 0
	detail_changed.emit()


func _apply_some() -> void:
	if _applying < 0.0:
		return
	var s := _applying
	var stop := mini(_cursor + APPLY_PER_FRAME, _ranges.size())
	while _cursor < stop:
		var r: Array = _ranges[_cursor]
		if is_instance_valid(r[0]):
			_apply_range(r[0], r[1], r[2], r[3], r[4], s)
		_cursor += 1
	if _cursor >= _ranges.size():
		_applied = s
		_applying = -1.0
		_ranges = _ranges.filter(func(r: Array) -> bool: return is_instance_valid(r[0]))


static func _apply_range(n: Node, end: float, begin: float, min_end: float, min_begin: float, s: float) -> void:
	var e := maxf(end * s, min_end)
	if n is Light3D:
		var l := n as Light3D
		l.distance_fade_enabled = true
		l.distance_fade_begin = e * 0.8
		l.distance_fade_length = e * 0.2
		l.distance_fade_shadow = e * 0.5
		return
	var g := n as GeometryInstance3D
	g.visibility_range_end = e
	g.visibility_range_end_margin = e * 0.08
	if begin > 0.0:
		var b := maxf(begin * s, min_begin)
		g.visibility_range_begin = b
		g.visibility_range_begin_margin = b * 0.08


# ------------------------------------------------------------------ governor

## Windows of one second: over budget (or too many slow frames) steps detail
## down at once; a run of good windows steps it back up. A step up that
## brings the slow frames back sets a ceiling for a while, so it doesn't
## keep bouncing. Frames far over budget (loading, shader compiles) are
## ignored.
func _govern(delta: float) -> void:
	if not dynamic or not sim_lod:
		return
	if _warmup > 0.0:
		_warmup -= delta
		return
	var budget := 1.0 / target_fps
	if delta > budget * 4.0 and delta > 0.1:
		return
	_raised_t += delta
	if _ceiling_t > 0.0:
		_ceiling_t -= delta
		if _ceiling_t <= 0.0:
			_ceiling = 1.0
	_win_t += delta
	_win_n += 1
	_win_sum += delta
	if delta > budget * 1.25:
		_win_slow += 1
	if _win_t < 1.0:
		return
	var avg := _win_sum / _win_n
	var slow := float(_win_slow) / _win_n
	_win_t = 0.0
	_win_n = 0
	_win_sum = 0.0
	_win_slow = 0
	if avg > budget * 1.06 or slow > 0.08:
		_good = 0
		if detail > MIN_DETAIL:
			if _raised_t < 4.0:
				_ceiling = detail - 0.001
				_ceiling_t = 30.0
			var over := avg / budget - 1.0
			_set_detail(maxf(MIN_DETAIL, detail - clampf(over * 0.6, 0.05, 0.2)))
	elif avg < budget * 1.02 and slow < 0.02:
		_good += 1
		var need := 2 if avg < budget * 0.8 else 5
		if _good >= need and detail < 1.0 and detail + STEP_UP <= _ceiling:
			_good = 0
			_raised_t = 0.0
			_set_detail(minf(1.0, detail + STEP_UP))
	else:
		_good = 0


func _set_detail(d: float) -> void:
	detail = snappedf(d, 0.01)
	_refresh()
