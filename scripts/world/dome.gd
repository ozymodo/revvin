extends Node3D
## The dome over the world. Its base curves up out of the ground like a
## giant quarter-pipe (radius TRANSITION) into a vertical wall, then arcs
## overhead to the apex, so the whole inside is drivable: ride up the wall
## on the fans, carve round it, launch off it. Low down it's solid tech
## panelling; higher up it fades to a faint energy lattice you can see the
## sky through. A rail runs round the foot of the wall (one endless grind).

const R0 := 600.0                   # where the ground starts curving up
const TRANSITION := 45.0            # radius of the curve into the wall
const APEX := 300.0                 # height of the top
const SEGS := 160                   # around
const SHADER := """
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, specular_schlick_ggx;
uniform vec3 panel : source_color = vec3(0.13, 0.15, 0.18);
uniform vec3 glow : source_color = vec3(0.2, 0.55, 1.0);
varying vec3 wp;
void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
float hexgrid(vec2 p) {
	p.y *= 1.1547;
	p.x += mod(floor(p.y), 2.0) * 0.5;
	vec2 f = abs(fract(p) - 0.5);
	return max(f.x * 1.5 + f.y, f.y * 2.0);
}
void fragment() {
	float h = wp.y;
	float ang = atan(wp.z, wp.x);
	vec2 uv = vec2(ang * 600.0 / 14.0, h / 12.0);
	// Panel seams low down, a hex lattice higher up.
	float seam = max(step(0.97, fract(uv.x)), step(0.96, fract(uv.y)));
	float hex = smoothstep(0.88, 0.96, hexgrid(vec2(ang * 600.0 / 40.0, h / 34.0)));
	float solid = 1.0 - smoothstep(70.0, 150.0, h);
	float pulse = 0.6 + 0.4 * sin(TIME * 0.8 - h * 0.05);
	ALBEDO = panel;
	METALLIC = 0.6;
	ROUGHNESS = 0.4;
	EMISSION = glow * (seam * solid * 2.0 + hex * (1.0 - solid) * 1.4 * pulse);
	ALPHA = mix(0.18 + hex * 0.6, 1.0, solid);
}
"""

var grinds: Node


func build() -> void:
	var profile := _profile()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var faces := PackedVector3Array()
	var rows := profile.size()
	for j in SEGS:
		var a0 := TAU * j / SEGS
		var a1 := TAU * (j + 1) / SEGS
		for i in rows - 1:
			var q := [_pt(profile[i], a0), _pt(profile[i + 1], a0), _pt(profile[i + 1], a1), _pt(profile[i], a1)]
			var nq := [_nrm(profile[i], a0), _nrm(profile[i + 1], a0), _nrm(profile[i + 1], a1), _nrm(profile[i], a1)]
			for k in [0, 1, 2, 0, 2, 3]:
				st.set_normal(nq[k])
				st.add_vertex(q[k])
				faces.append(q[k])
	var mat := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SHADER
	mat.shader = sh
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var body := StaticBody3D.new()
	body.add_child(mi)
	var cs := CollisionShape3D.new()
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(faces)
	cs.shape = shape
	body.add_child(cs)
	add_child(body)
	# The endless rail round the foot of the wall.
	if grinds:
		var ring := PackedVector3Array()
		for j in 240:
			var a := TAU * j / 240.0
			ring.append(Vector3(cos(a) * (R0 - 6.0), 0.95, sin(a) * (R0 - 6.0)))
		grinds.add_rail(ring, "rail", true, PackedVector3Array(), true)


## [radius, height, inward normal radial part, normal up part] up the wall.
func _profile() -> Array:
	var out := []
	for k in 20:                                    # the curve out of the ground
		var a := float(k) / 19.0 * PI * 0.5
		out.append([R0 + TRANSITION * sin(a), TRANSITION * (1.0 - cos(a)), -sin(a), cos(a)])
	var rw := R0 + TRANSITION
	for k in range(1, 41):                          # the wall arcing over to the apex
		var phi := float(k) / 40.0 * PI * 0.5
		var r := rw * cos(phi)
		var y := TRANSITION + (APEX - TRANSITION) * sin(phi)
		# Inward normal of the ellipse (r/rw)^2 + ((y - T)/(A - T))^2 = 1.
		var n := Vector2(-cos(phi) / rw, -sin(phi) / (APEX - TRANSITION)).normalized()
		out.append([r, y, n.x, n.y])
	return out


static func _pt(p: Array, a: float) -> Vector3:
	return Vector3(cos(a) * p[0], p[1], sin(a) * p[0])


static func _nrm(p: Array, a: float) -> Vector3:
	return Vector3(cos(a) * p[2], p[3], sin(a) * p[2]).normalized()
