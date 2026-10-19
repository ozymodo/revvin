shader_type spatial;
render_mode cull_disabled;
// Overgrown tech surfaces (ramps, walls, the loop, the half-pipe): panelled
// material with moss on anything facing up, moss creeping up from the
// ground, and glowing veins running through the panel seams, where the
// old circuitry has been taken over by something living.

#include "res://scripts/world/noise.gdshaderinc"

uniform vec3 base_color : source_color = vec3(0.4, 0.4, 0.38);
uniform float panel = 3.0;
uniform float moss_amount = 0.55;
uniform vec3 vein_color : source_color = vec3(0.08, 0.85, 0.32);
uniform float vein_amount = 0.5;
uniform float metallic = 0.2;

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

vec2 plane_uv(vec3 w) {
	vec3 a = abs(wnrm);
	if (a.y > a.x && a.y > a.z) return w.xz;
	if (a.x > a.z) return w.zy;
	return w.xy;
}

void fragment() {
	vec2 uv = plane_uv(wpos);
	float detail = 1.0 - smoothstep(80.0, 250.0, length(VERTEX));

	vec2 cell = abs(fract(uv / panel - 0.5) - 0.5) * panel;
	float fw = fwidth(uv.x) + 0.005;
	float seam = (1.0 - smoothstep(0.03, 0.06 + fw, min(cell.x, cell.y))) * detail;
	float tint = hash21(floor(uv / panel));
	vec3 col = base_color * (0.85 + 0.25 * tint) * (1.0 - seam * 0.5);

	float n = fbm(uv * 0.35 + wpos.y * 0.1);
	float top = smoothstep(0.35, 0.85, wnrm.y);
	float base = 1.0 - smoothstep(0.0, 2.5 + n * 2.0, wpos.y);
	float moss = clamp(top * 0.95 + base, 0.0, 1.0) * smoothstep(0.62 - moss_amount, 0.9 - moss_amount, n);
	col = mix(col, mix(vec3(0.17, 0.27, 0.08), vec3(0.3, 0.38, 0.12), vnoise(uv * 1.7)), moss);

	// Vines streaking down vertical faces.
	float vertical = 1.0 - abs(wnrm.y);
	float column = vnoise(vec2(uv.x * 1.3, 3.0));
	float leafy = vnoise(uv * vec2(5.0, 3.0));
	float vines = vertical * step(0.62, column) * smoothstep(0.35, 0.6, leafy) * smoothstep(0.3, 0.6, fbm(vec2(uv.x * 0.5, uv.y * 0.12)));
	col = mix(col, vec3(0.14, 0.26, 0.09), vines * moss_amount * 1.4);

	float ve = voronoi_edge(uv * 0.22 + 3.0);
	float vein = (1.0 - smoothstep(0.0, 0.008 + fwidth(uv.x * 0.22), ve)) * smoothstep(1.0 - vein_amount, 1.05 - vein_amount * 0.6, fbm(uv * 0.08 + 9.0));
	vein = max(vein, seam * step(0.9, tint) * vein_amount * 0.6);
	float pulse = 0.55 + 0.45 * sin(TIME * 1.7 - (wpos.x + wpos.y + wpos.z) * 0.12);

	ALBEDO = col;
	METALLIC = metallic * (1.0 - moss);
	ROUGHNESS = mix(0.55, 0.95, moss);
	EMISSION = vein_color * vein * pulse * 1.1 * (1.0 - moss * 0.7);
}
