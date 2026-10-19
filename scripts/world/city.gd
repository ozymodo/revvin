extends Node3D
## The overgrown city around the proving ground: a street grid of ruined
## arcology towers, a skyline beyond the walls, levitating maglev beams,
## forests and grass in the blocks, lingering tech (lamps, pylons, drones,
## holo signs, wrecked hover-cars) and wildlife.
##
## Everything keeps out of `reserved` (the stunt features and test lanes,
## set by level.gd) and off the avenues, so the course stays drivable.
## Scattered meshes use MultiMesh, chunked so distant chunks cull, with a
## one-draw-call stand-in further out (lod.gd); every draw distance scales
## with the world's level of detail.

const AVENUES := [-300.0, -150.0, 0.0, 150.0, 300.0]
const AVENUE_HALF := 14.0
const PLAY := 395.0                 # inside the boundary walls

const BUILDING_SHADER := preload("res://scripts/world/building.gdshader")
const FOLIAGE_SHADER := preload("res://scripts/world/foliage.gdshader")
## Scattered things (trees, bushes, lamps, rubble) never draw closer in
## than this share of their full-detail distances, however low the Level of
## detail setting and the governor go.
const NEAR_FLOOR := 0.6
const GRASS_SHADER := preload("res://scripts/world/grass.gdshader")
const OVERGROWN_SHADER := preload("res://scripts/world/overgrown.gdshader")
const DEER := preload("res://scripts/world/deer.gd")
const BIRDS := preload("res://scripts/world/bird_flock.gd")
const DRONE := preload("res://scripts/world/drone.gd")
const FLICKER := preload("res://scripts/world/flicker.gd")

const SIGNS := ["VERDANT//SYS", "ARCOLOGY 07", "BIO-SYNC ONLINE", "NEON BLOOM", "REWILD PROTOCOL",
	"AIR LINE 4", "ECHO ROOT", "SYSTEM DORMANT", "LAST SIGNAL", "PHOTON GARDEN", "SECTOR 9 // OPEN",
	"MYCELIA NET", "HELIX TRANSIT", "GROWTH > 100%", "DO NOT FEED THE DRONES"]

var reserved: Array[Rect2] = []
var rng := RandomNumberGenerator.new()
var _footprints: Array[Rect2] = []
## Upright collidable towers: [footprint Rect2, height] (the stunt park
## puts curved banks round their bases so you can ride up the walls).
var towers: Array = []
## Smashable vegetation and rubble (world/destruction.gd): one entry per
## instance, [MultiMesh, index, Transform3D, kind, trunk CollisionShape3D or null].
var destructibles: Array = []
var _noise := FastNoiseLite.new()
var _trunks: StaticBody3D
var _mats := {}


func build(reserved_zones: Array[Rect2], course_rects: Array[Rect2] = []) -> void:
	reserved = reserved_zones
	_mask.resize(MASK_N * MASK_N)
	_mask.fill(0)
	for r in course_rects:
		_mask_add(r)
	rng.seed = 7741
	_noise.seed = 31
	_noise.frequency = 0.012
	_trunks = StaticBody3D.new()
	add_child(_trunks)
	_buildings()
	_skyline()
	_maglev()
	_vegetation()
	_grass()
	_props()
	_wildlife()


# ------------------------------------------------------------------ queries

## The stunt course's footprint, rasterised: hundreds of small rects are
## too slow to test one by one for every tree and grass clump.
const MASK_CELL := 4.0
const MASK_N := 200
var _mask := PackedByteArray()


func _mask_add(r: Rect2) -> void:
	var x0 := clampi(floori((r.position.x + PLAY + 5.0) / MASK_CELL), 0, MASK_N - 1)
	var x1 := clampi(floori((r.end.x + PLAY + 5.0) / MASK_CELL), 0, MASK_N - 1)
	var z0 := clampi(floori((r.position.y + PLAY + 5.0) / MASK_CELL), 0, MASK_N - 1)
	var z1 := clampi(floori((r.end.y + PLAY + 5.0) / MASK_CELL), 0, MASK_N - 1)
	for z in range(z0, z1 + 1):
		for x in range(x0, x1 + 1):
			_mask[z * MASK_N + x] = 1


func masked(x: float, z: float) -> bool:
	var cx := floori((x + PLAY + 5.0) / MASK_CELL)
	var cz := floori((z + PLAY + 5.0) / MASK_CELL)
	if cx < 0 or cz < 0 or cx >= MASK_N or cz >= MASK_N:
		return false
	return _mask[cz * MASK_N + cx] == 1


func _rect_masked(r: Rect2) -> bool:
	var x := r.position.x
	while x <= r.end.x + MASK_CELL:
		var z := r.position.y
		while z <= r.end.y + MASK_CELL:
			if masked(minf(x, r.end.x), minf(z, r.end.y)):
				return true
			z += MASK_CELL
		x += MASK_CELL
	return false


func on_avenue(x: float, z: float, margin := 0.0) -> bool:
	for a in AVENUES:
		if absf(x - a) < AVENUE_HALF + margin or absf(z - a) < AVENUE_HALF + margin:
			return true
	return false


func is_reserved(x: float, z: float, margin := 0.0) -> bool:
	if masked(x, z):
		return true
	for r in reserved:
		if r.grow(margin).has_point(Vector2(x, z)):
			return true
	return false


func in_building(x: float, z: float, margin := 0.0) -> bool:
	for r in _footprints:
		if r.grow(margin).has_point(Vector2(x, z)):
			return true
	return false


## Open ground for scatter: not a street, feature, building or out of bounds.
func is_wild(x: float, z: float, margin := 2.0) -> bool:
	return absf(x) < PLAY and absf(z) < PLAY and not on_avenue(x, z, margin) \
		and not is_reserved(x, z, margin) and not in_building(x, z, margin)


func _rect_free(r: Rect2) -> bool:
	if absf(r.position.x) > PLAY or absf(r.end.x) > PLAY or absf(r.position.y) > PLAY or absf(r.end.y) > PLAY:
		return false
	for a in AVENUES:
		var band_x := Rect2(a - AVENUE_HALF - 3.0, -1000, (AVENUE_HALF + 3.0) * 2.0, 2000)
		var band_z := Rect2(-1000, a - AVENUE_HALF - 3.0, 2000, (AVENUE_HALF + 3.0) * 2.0)
		if r.intersects(band_x) or r.intersects(band_z):
			return false
	for q in reserved:
		if r.intersects(q.grow(6.0)):
			return false
	for q in _footprints:
		if r.intersects(q.grow(5.0)):
			return false
	return not _rect_masked(r)


# ------------------------------------------------------------------ materials

func _building_mat() -> ShaderMaterial:
	if not _mats.has("building"):
		var m := ShaderMaterial.new()
		m.shader = BUILDING_SHADER
		_mats["building"] = m
	return _mats["building"]


static func overgrown(base: Color, moss := 0.55, veins := 0.5, panel := 3.0, metallic := 0.2, vein_color := Color(0.08, 0.85, 0.32)) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = OVERGROWN_SHADER
	m.set_shader_parameter("base_color", base)
	m.set_shader_parameter("moss_amount", moss)
	m.set_shader_parameter("vein_amount", veins)
	m.set_shader_parameter("panel", panel)
	m.set_shader_parameter("metallic", metallic)
	m.set_shader_parameter("vein_color", vein_color)
	return m


## Flattens an imported .glb into one ArrayMesh (for MultiMesh), swapping
## Leaf* materials for the wind-sway foliage shader.
func merged_mesh(path: String, sway_height: float, sway := 0.25) -> ArrayMesh:
	var key := path + str(sway_height)
	if _mats.has(key):
		return _mats[key]
	var root: Node3D = load(path).instantiate()
	var out := ArrayMesh.new()
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var xf := Transform3D.IDENTITY
		var n: Node = mi
		while n != root:
			xf = (n as Node3D).transform * xf
			n = n.get_parent()
		for s in mi.mesh.get_surface_count():
			var st := SurfaceTool.new()
			st.append_from(mi.mesh, s, xf)
			st.commit(out)
			var src: Material = mi.mesh.surface_get_material(s)
			out.surface_set_material(out.get_surface_count() - 1, _foliage_for(src, sway_height, sway))
	root.free()
	_mats[key] = out
	return out


func _foliage_for(src: Material, sway_height: float, sway: float) -> Material:
	if src == null or not src.resource_name.begins_with("Leaf") or src.resource_name == "LeafPanel":
		return src
	var m := ShaderMaterial.new()
	m.shader = FOLIAGE_SHADER
	m.set_shader_parameter("albedo", (src as BaseMaterial3D).albedo_color)
	m.set_shader_parameter("sway_height", sway_height)
	m.set_shader_parameter("sway", sway)
	return m


## MultiMesh instances, grouped into square chunks that cull with distance.
## With a `kind`, every instance is also registered as smashable;
## `trunks` (parallel to xforms) gives a tree's collider. With `near_end`,
## each chunk swaps to a simplified one-surface copy (Lod.far_mesh) past
## that distance; destruction.gd keeps the copy in step via the "lod_twin"
## meta.
func scatter(mesh: Mesh, xforms: Array, chunk: float, vis_end: float, shadows := true, kind := "", trunks: Array = [], near_end := 0.0) -> void:
	var far: Mesh = Lod.far_mesh(mesh) if near_end > 0.0 else null
	var groups := {}
	for n in xforms.size():
		var xf: Transform3D = xforms[n]
		var key := Vector2i(floori(xf.origin.x / chunk), floori(xf.origin.z / chunk))
		if not groups.has(key):
			groups[key] = []
		groups[key].append(n)
	for key in groups:
		var list: Array = groups[key]
		# The chunk sits at its own centre: visibility ranges are measured
		# from the node, so one at the world origin would show or hide its
		# trees by how far the camera is from the middle of the map.
		var centre := Vector3((key.x + 0.5) * chunk, 0.0, (key.y + 0.5) * chunk)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = list.size()
		mm.set_meta("offset", centre)
		for i in list.size():
			var xf: Transform3D = xforms[list[i]]
			mm.set_instance_transform(i, xf.translated(-centre))
			if kind != "":
				destructibles.append([mm, i, xf, kind, trunks[list[i]] if list[i] < trunks.size() else null])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.position = centre
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)
		if far == null:
			Lod.draw_distance(mmi, vis_end, 0.0, vis_end * NEAR_FLOOR)
			continue
		# Full detail never closer than most of near_end, whatever the
		# setting or governor: the stand-in only ever shows past the point
		# where its simplification can't be seen.
		var near_min := near_end * NEAR_FLOOR
		Lod.draw_distance(mmi, near_end, 0.0, near_min)
		var fmm := MultiMesh.new()
		fmm.transform_format = MultiMesh.TRANSFORM_3D
		fmm.mesh = far
		fmm.instance_count = list.size()
		for i in list.size():
			fmm.set_instance_transform(i, (xforms[list[i]] as Transform3D).translated(-centre))
		mm.set_meta("lod_twin", fmm)
		var fmmi := MultiMeshInstance3D.new()
		fmmi.multimesh = fmm
		fmmi.position = centre
		fmmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		fmmi.cast_shadow = mmi.cast_shadow
		add_child(fmmi)
		Lod.draw_distance(fmmi, vis_end, near_end, vis_end * NEAR_FLOOR, near_min)


func _trunk(pos: Vector3, radius: float, height: float) -> CollisionShape3D:
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	cs.shape = shape
	cs.position = pos + Vector3.UP * height * 0.5
	_trunks.add_child(cs)
	return cs


# ------------------------------------------------------------------ buildings

func _block_ranges() -> Array:
	var edges := [-PLAY]
	for a in AVENUES:
		edges.append(a - AVENUE_HALF - 3.0)
		edges.append(a + AVENUE_HALF + 3.0)
	edges.append(PLAY)
	var out := []
	for i in range(0, edges.size(), 2):
		out.append(Vector2(edges[i], edges[i + 1]))
	return out


var roof_spots: Array = []          # Vector3 roof positions for rooftop trees


func _buildings() -> void:
	var blocks := _block_ranges()
	for bx in blocks:
		for bz in blocks:
			for attempt in 14:
				var w := rng.randf_range(14, 36)
				var d := rng.randf_range(14, 36)
				var x := rng.randf_range(bx.x + w * 0.5 + 3, bx.y - w * 0.5 - 3)
				var z := rng.randf_range(bz.x + d * 0.5 + 3, bz.y - d * 0.5 - 3)
				if bx.y - bx.x < w + 6 or bz.y - bz.x < d + 6:
					continue
				var r := Rect2(x - w * 0.5, z - d * 0.5, w, d)
				if not _rect_free(r):
					continue
				var roll := rng.randf()
				var h := rng.randf_range(12, 38) if roll < 0.55 else (rng.randf_range(38, 85) if roll < 0.9 else rng.randf_range(85, 140))
				_footprints.append(r)
				var leaning := rng.randf() < 0.15
				var body := _tower(Vector3(x, 0, z), Vector3(w, h, d), leaning, true)
				if not leaning:
					towers.append([r, h, body])


func _tower(base: Vector3, size: Vector3, leaning: bool, collide: bool) -> Node3D:
	var body: Node3D = StaticBody3D.new() if collide else Node3D.new()
	body.position = base + Vector3.UP * size.y * 0.5
	if leaning:
		body.rotation = Vector3(rng.randf_range(-0.06, 0.06), rng.randf_range(0, TAU), rng.randf_range(-0.06, 0.06))
	add_child(body)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _building_mat()
	mi.set_instance_shader_parameter("roof_h", size.y)
	mi.set_instance_shader_parameter("seed", rng.randf() * 100.0)
	mi.set_instance_shader_parameter("base_y", base.y)
	body.add_child(mi)
	if collide:
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		cs.shape = shape
		body.add_child(cs)
		# A broken-off top section on some towers.
		if size.y > 30.0 and rng.randf() < 0.3:
			var top := MeshInstance3D.new()
			var tm := BoxMesh.new()
			tm.size = Vector3(size.x * 0.5, size.y * 0.15, size.z * 0.6)
			top.mesh = tm
			top.material_override = _building_mat()
			top.set_instance_shader_parameter("roof_h", size.y * 1.15)
			top.set_instance_shader_parameter("seed", rng.randf() * 100.0)
			top.set_instance_shader_parameter("base_y", base.y + size.y)
			top.position = Vector3(size.x * 0.15, size.y * 0.55, 0)
			top.rotation = Vector3(0.12, 0, -0.25)
			body.add_child(top)
		if not leaning and rng.randf() < 0.55:
			for i in rng.randi_range(1, 3):
				roof_spots.append(base + Vector3(rng.randf_range(-0.3, 0.3) * size.x, size.y, rng.randf_range(-0.3, 0.3) * size.z))
		if not leaning and rng.randf() < 0.22:
			_holo_sign(base, size)
	return body


func _holo_sign(base: Vector3, size: Vector3) -> void:
	# Faces whichever side of the tower is closest to an avenue.
	var best := Vector3.FORWARD
	var best_d := INF
	for dir in [Vector3.FORWARD, Vector3.BACK, Vector3.LEFT, Vector3.RIGHT]:
		var p: Vector3 = base + dir * Vector3(size.x, 0, size.z) * 0.5
		for a in AVENUES:
			var dd := minf(absf(p.x - a), absf(p.z - a))
			if dd < best_d:
				best_d = dd
				best = dir
	var label := Label3D.new()
	label.text = SIGNS[rng.randi() % SIGNS.size()]
	label.font_size = 220
	label.pixel_size = 0.02
	label.outline_size = 0
	label.modulate = [Color(0.25, 0.55, 1.0), Color(0.2, 0.95, 0.4), Color(0.25, 0.55, 1.0), Color(1.0, 0.4, 0.12)][rng.randi() % 4]
	label.shaded = false
	label.double_sided = false
	label.position = base + best * (Vector3(size.x, 0, size.z) * 0.5 + Vector3.ONE * 0.3) + Vector3.UP * rng.randf_range(8, minf(size.y - 4, 30))
	label.basis = Basis.looking_at(-best, Vector3.UP)
	label.set_script(FLICKER)
	add_child(label)
	Lod.draw_distance(label, 400.0)


func _skyline() -> void:
	# Towers beyond the dome, for a city that goes on into the haze. All
	# one mesh (one draw call): the building shader reads each tower's roof
	# height and seed from UV2 instead of instance uniforms.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var box := BoxMesh.new()
	var arrays := box.get_mesh_arrays()
	var bv: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bn: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var bi: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	for i in 120:
		var a := rng.randf() * TAU
		var r := rng.randf_range(700, 1000)
		var pos := Vector3(cos(a) * r, 0, sin(a) * r)
		var size := Vector3(rng.randf_range(20, 50), rng.randf_range(40, 220), rng.randf_range(20, 50))
		var basis := Basis()
		if rng.randf() < 0.2:
			basis = Basis.from_euler(Vector3(rng.randf_range(-0.06, 0.06), rng.randf_range(0, TAU), rng.randf_range(-0.06, 0.06)))
		var xf := Transform3D(basis, pos + Vector3.UP * size.y * 0.5)
		var uv2 := Vector2(size.y, rng.randf() * 100.0)
		for k in bi:
			st.set_uv2(uv2)
			st.set_normal(basis * bn[k])
			st.add_vertex(xf * (bv[k] * size))
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var mat := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = BUILDING_SHADER.code.replace("instance uniform float roof_h = 40.0;", "varying flat float roof_h;") \
		.replace("instance uniform float seed = 0.0;", "varying flat float seed;") \
		.replace("instance uniform float base_y = 0.0;", "const float base_y = 0.0;") \
		.replace("void vertex() {", "void vertex() {\n\troof_h = UV2.x;\n\tseed = UV2.y;")
	mat.shader = sh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _maglev() -> void:
	# Levitating transit beams, still floating in segments over two avenues.
	var mat := overgrown(Color(0.22, 0.24, 0.27), 0.45, 0.8, 4.0, 0.6, Color(0.15, 0.45, 1.0))
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color(0.15, 0.45, 1.0)
	glow.emission_enabled = true
	glow.emission = Color(0.15, 0.45, 1.0)
	glow.emission_energy_multiplier = 3.0
	var vines: Array = []
	for line in [[Vector3(-380, 24, 150), Vector3(380, 24, 150)], [Vector3(-150, 30, -380), Vector3(-150, 30, 380)]]:
		var a: Vector3 = line[0]
		var b: Vector3 = line[1]
		var n := int(a.distance_to(b) / 40.0)
		for i in n:
			var p0 := a.lerp(b, float(i) / n)
			var p1 := a.lerp(b, float(i + 1) / n)
			var mid := (p0 + p1) * 0.5 + Vector3.UP * sin(i * 1.7) * 0.6
			if masked(mid.x, mid.z) or masked(p0.x, p0.z) or masked(p1.x, p1.z):
				continue          # the skyway took this span
			var length := p0.distance_to(p1) - 2.0
			var along := (p1 - p0).normalized()
			var body := StaticBody3D.new()
			body.position = mid
			body.basis = Basis.looking_at(along, Vector3.UP)
			add_child(body)
			var mi := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(4.5, 1.4, length)
			mi.mesh = bm
			mi.material_override = mat
			body.add_child(mi)
			var strip := MeshInstance3D.new()
			var sm := BoxMesh.new()
			sm.size = Vector3(0.4, 0.06, length * 0.96)
			strip.mesh = sm
			strip.position.y = -0.72
			strip.material_override = glow
			body.add_child(strip)
			var cs := CollisionShape3D.new()
			var shape := BoxShape3D.new()
			shape.size = bm.size
			cs.shape = shape
			body.add_child(cs)
			for k in 8:
				var off := along * rng.randf_range(-length * 0.45, length * 0.45) + body.basis.x * rng.randf_range(-2.0, 2.0)
				vines.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(1, rng.randf_range(2.0, 9.0), 1)), mid + off + Vector3.DOWN * 0.7))
	scatter(vine_mesh(), vines, 120.0, 500.0, false)


## Hanging vine: a thin ribbon with leaves, 1 m long, hanging down from the
## origin (scale Y to set the length).
func vine_mesh() -> ArrayMesh:
	if _mats.has("vine"):
		return _mats["vine"]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := 8
	for i in segs:
		var y0 := -float(i) / segs
		var y1 := -float(i + 1) / segs
		var x0 := sin(i * 1.3) * 0.04
		var x1 := sin((i + 1) * 1.3) * 0.04
		for q in [[Vector3(x0 - 0.025, y0, 0), Vector3(x0 + 0.025, y0, 0), Vector3(x1 + 0.025, y1, 0)],
				[Vector3(x0 - 0.025, y0, 0), Vector3(x1 + 0.025, y1, 0), Vector3(x1 - 0.025, y1, 0)]]:
			for v in q:
				st.set_normal(Vector3.BACK)
				st.add_vertex(v)
		var side := 1.0 if i % 2 == 0 else -1.0
		var c := Vector3(x0 + side * 0.09, (y0 + y1) * 0.5, 0.02)
		for v in [c + Vector3(-0.07, 0.03, 0), c + Vector3(0.07, 0.03, 0), c + Vector3(0, -0.05, 0.02)]:
			st.set_normal(Vector3.BACK)
			st.add_vertex(v)
	var mesh := st.commit()
	var m := ShaderMaterial.new()
	m.shader = FOLIAGE_SHADER
	m.set_shader_parameter("albedo", Color(0.2, 0.36, 0.14))
	m.set_shader_parameter("hanging", true)
	m.set_shader_parameter("sway", 0.35)
	m.set_shader_parameter("sway_height", 1.0)
	mesh.surface_set_material(0, m)
	_mats["vine"] = mesh
	return mesh


# ------------------------------------------------------------------ vegetation

func _vegetation() -> void:
	var trees := {"tree_broad": [], "tree_tall": [], "tree_tech": []}
	var trunks := {"tree_broad": [], "tree_tall": [], "tree_tech": []}
	var bushes := []
	var ferns := []
	var rubble := []
	for i in 3200:
		var x := rng.randf_range(-PLAY, PLAY)
		var z := rng.randf_range(-PLAY, PLAY)
		var wild := _noise.get_noise_2d(x, z) * 0.5 + 0.5
		if not is_wild(x, z, 3.0) or rng.randf() > wild * 1.3:
			continue
		var roll := rng.randf()
		var kind := "tree_broad" if roll < 0.45 else ("tree_tall" if roll < 0.75 else "tree_tech")
		var s := rng.randf_range(0.8, 1.5)
		trees[kind].append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), Vector3(x, 0, z)))
		trunks[kind].append(_trunk(Vector3(x, 0, z), 0.45 * s, 6.0 * s))
	for p in roof_spots:
		trees["tree_broad" if rng.randf() < 0.6 else "tree_tech"].append(
			Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.7, 1.1)), p))
	for i in 9000:
		var x := rng.randf_range(-PLAY, PLAY)
		var z := rng.randf_range(-PLAY, PLAY)
		var wild := _noise.get_noise_2d(x, z) * 0.5 + 0.5
		var street := on_avenue(x, z, 0.0)
		if is_reserved(x, z, 2.0) or in_building(x, z, 1.0) or absf(x) > PLAY or absf(z) > PLAY:
			continue
		if street and (rng.randf() > 0.06 or minf(_dist_to_avenue(x), 99.0) < AVENUE_HALF - 4.0):
			continue      # the odd bush at the kerb, never in the lanes
		var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.7, 1.6)), Vector3(x, 0, z))
		var r := rng.randf() * (0.4 + wild)
		if r < 0.35:
			ferns.append(xf)
		elif r < 0.75:
			bushes.append(xf)
		elif rng.randf() < 0.3:
			rubble.append(xf)
	# Roof-garden trees (no trunk collider) come after the street trees in
	# each list, so the trunk arrays line up with the first entries.
	# Full trees out to 120 m, one-draw-call stand-ins beyond.
	scatter(merged_mesh("res://assets/world/tree_broad.glb", 8.0, 0.35), trees["tree_broad"], 80.0, 600.0, true, "tree", trunks["tree_broad"], 120.0)
	scatter(merged_mesh("res://assets/world/tree_tall.glb", 12.0, 0.5), trees["tree_tall"], 80.0, 600.0, true, "tree", trunks["tree_tall"], 120.0)
	scatter(merged_mesh("res://assets/world/tree_tech.glb", 9.0, 0.2), trees["tree_tech"], 80.0, 600.0, true, "tree", trunks["tree_tech"], 120.0)
	scatter(merged_mesh("res://assets/world/bush.glb", 1.2, 0.1), bushes, 60.0, 220.0, true, "bush", [], 70.0)
	scatter(merged_mesh("res://assets/world/fern.glb", 0.6, 0.12), ferns, 50.0, 140.0, false, "fern")
	scatter(merged_mesh("res://assets/world/rubble.glb", 1.0), rubble, 60.0, 250.0, true, "rock", [], 70.0)


func _dist_to_avenue(x: float) -> float:
	var d := INF
	for a in AVENUES:
		d = minf(d, absf(x - a))
	return d


func _grass() -> void:
	var clump := _grass_clump()
	var chunk := 40.0
	var cx := -PLAY
	while cx < PLAY:
		var cz := -PLAY
		while cz < PLAY:
			var list := []
			# Random order (Lod thins a chunk by showing a prefix of it).
			for i in 220:
				var x := cx + rng.randf() * chunk
				var z := cz + rng.randf() * chunk
				var wild := _noise.get_noise_2d(x * 1.7, z * 1.7) * 0.5 + 0.5
				var p := wild
				if on_avenue(x, z):
					p = 0.08              # grass in the cracks
				if rng.randf() > p or is_reserved(x, z, 1.0) or in_building(x, z, 0.5):
					continue
				list.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.7, 1.5)), Vector3(x, 0, z)))
			if not list.is_empty():
				var mm := MultiMesh.new()
				mm.transform_format = MultiMesh.TRANSFORM_3D
				mm.mesh = clump
				mm.instance_count = list.size()
				var centre := Vector3(cx + chunk * 0.5, 0, cz + chunk * 0.5)
				for i in list.size():
					mm.set_instance_transform(i, (list[i] as Transform3D).translated(-centre))
				var mmi := MultiMeshInstance3D.new()
				mmi.multimesh = mm
				mmi.position = centre           # see scatter
				mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
				mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				add_child(mmi)
				Lod.draw_distance(mmi, 150.0)
				Lod.add_grass(mmi, centre)
			cz += chunk
		cx += chunk


## One clump: 16 tapered blades. UV.y = height along the blade, COLOR.r =
## brightness variation, COLOR.g = bioluminescent tip (1 in ~12 blades).
func _grass_clump() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var r := RandomNumberGenerator.new()
	r.seed = 3
	for b in 16:
		var base := Vector3(r.randf_range(-0.5, 0.5), 0, r.randf_range(-0.5, 0.5))
		var h := r.randf_range(0.35, 0.95)
		var yaw := r.randf() * TAU
		var side := Vector3(cos(yaw), 0, sin(yaw)) * 0.035
		var lean := Vector3(r.randf_range(-0.2, 0.2), 0, r.randf_range(-0.2, 0.2)) * h
		var c := Color(r.randf(), 1.0 if r.randf() < 0.08 else 0.0, 0)
		var pts := [base - side, base + side, base + side * 0.5 + Vector3.UP * h * 0.55 + lean * 0.4,
			base - side * 0.5 + Vector3.UP * h * 0.55 + lean * 0.4, base + Vector3.UP * h + lean]
		var uvs := [0.0, 0.0, 0.55, 0.55, 1.0]
		var n := side.cross(Vector3.UP).normalized()
		for tri in [[0, 1, 2], [0, 2, 3], [3, 2, 4]]:
			for k in tri:
				st.set_color(c)
				st.set_uv(Vector2(0, uvs[k]))
				st.set_normal((n + Vector3.UP * 0.6).normalized())
				st.add_vertex(pts[k])
	var mesh := st.commit()
	var m := ShaderMaterial.new()
	m.shader = GRASS_SHADER
	mesh.surface_set_material(0, m)
	return mesh


# ------------------------------------------------------------------ lingering tech

func _props() -> void:
	# Streetlamps along both sides of every avenue, still burning.
	var lamps := []
	var lamp_trunks := []
	for a in AVENUES:
		var t := -PLAY + 10.0
		while t < PLAY - 10.0:
			for side in [-1.0, 1.0]:
				for axis in 2:
					var off: float = a + side * (AVENUE_HALF + 1.5)
					var x: float = off if axis == 0 else t
					var z: float = t if axis == 0 else off
					if is_reserved(x, z, 3.0) or _cross_near(x, z):
						continue
					# Arm points across the road.
					var arm := Vector3(-side, 0, 0) if axis == 0 else Vector3(0, 0, -side)
					lamps.append(Transform3D(Basis(Vector3.UP, atan2(-arm.z, arm.x)), Vector3(x, 0, z)))
					lamp_trunks.append(_trunk(Vector3(x, 0, z), 0.18, 6.5))
			t += 38.0
	scatter(merged_mesh("res://assets/world/lamp.glb", 7.0, 0.05), lamps, 120.0, 450.0, true, "lamp", lamp_trunks, 130.0)

	# Wrecked hover-cars at the kerbs.
	var wreck_mesh := merged_mesh("res://assets/world/wreck.glb", 2.0, 0.1)
	for i in 70:
		var a: float = AVENUES[rng.randi() % AVENUES.size()]
		var t := rng.randf_range(-PLAY + 10, PLAY - 10)
		var off := a + (rng.randf_range(7.0, 11.0) * (1.0 if rng.randf() < 0.5 else -1.0))
		var along_x := rng.randf() < 0.5
		var pos := Vector3(t, 0, off) if along_x else Vector3(off, 0, t)
		if is_reserved(pos.x, pos.z, 4.0) or _cross_near(pos.x, pos.z):
			continue
		var body := StaticBody3D.new()
		body.position = pos
		body.rotation.y = (0.0 if along_x else PI * 0.5) + rng.randf_range(-0.5, 0.5) + (PI if rng.randf() < 0.5 else 0.0)
		var mi := MeshInstance3D.new()
		mi.mesh = wreck_mesh
		body.add_child(mi)
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(1.9, 1.2, 4.4)
		cs.shape = shape
		cs.position.y = 0.6
		body.add_child(cs)
		add_child(body)
		Lod.draw_distance(mi, 260.0)

	# Energy pylons at some intersections.
	var pylon_scene := load("res://assets/world/pylon.glb") as PackedScene
	for ax in AVENUES:
		for az in AVENUES:
			if rng.randf() > 0.45:
				continue
			var pos := Vector3(ax + AVENUE_HALF + 7.0, 0, az + AVENUE_HALF + 7.0)
			if is_reserved(pos.x, pos.z, 6.0) or in_building(pos.x, pos.z, 3.0):
				continue
			var p := pylon_scene.instantiate() as Node3D
			p.position = pos
			p.rotation.y = rng.randf() * TAU
			add_child(p)
			destructibles.append([p, 0, p.transform, "pylon", _trunk(pos, 1.1, 28.0)])

	# Dormant drones still on station.
	for i in 22:
		var x := rng.randf_range(-PLAY + 20, PLAY - 20)
		var z := rng.randf_range(-PLAY + 20, PLAY - 20)
		if in_building(x, z, 4.0):
			continue
		var d := DRONE.new()
		d.position = Vector3(x, rng.randf_range(5.0, 14.0), z)
		add_child(d)
		Lod.draw_distance(d, 260.0)


## Near an intersection: keeps lamps and wrecks out of the crossings.
func _cross_near(x: float, z: float) -> bool:
	for a in AVENUES:
		for b in AVENUES:
			if absf(x - a) < AVENUE_HALF + 4.0 and absf(z - b) < AVENUE_HALF + 4.0:
				return true
	return false


# ------------------------------------------------------------------ wildlife

func _wildlife() -> void:
	var herds := 0
	var tries := 0
	while herds < 7 and tries < 400:
		tries += 1
		var home := Vector3(rng.randf_range(-PLAY + 30, PLAY - 30), 0, rng.randf_range(-PLAY + 30, PLAY - 30))
		if not is_wild(home.x, home.z, 12.0):
			continue
		herds += 1
		for i in rng.randi_range(3, 6):
			var deer := DEER.new()
			deer.city = self
			deer.home = home
			deer.position = home + Vector3(rng.randf_range(-8, 8), 0, rng.randf_range(-8, 8))
			add_child(deer)
	for i in 8:
		var flock := BIRDS.new()
		flock.position = Vector3(rng.randf_range(-PLAY, PLAY), rng.randf_range(18, 45), rng.randf_range(-PLAY, PLAY))
		flock.count = rng.randi_range(7, 14)
		flock.radius = rng.randf_range(10, 25)
		add_child(flock)
