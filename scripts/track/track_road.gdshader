shader_type spatial;
// Stunt-course road surface. UV.x runs 0..1 across the road, UV.y is the
// distance along it in metres. COLOR.r = how hard the road is turning
// (red-orange kerbs), COLOR.g = boost pad, COLOR.b = start/checkpoint line.
//
// Dark grippy panels with glowing blue edge lines, moss creeping in from
// the edges and the seams: old maglev deck, still powered.

#include "res://scripts/world/noise.gdshaderinc"

global uniform float lod_detail;
uniform vec3 edge_color : source_color = vec3(0.15, 0.45, 1.0);
uniform vec3 kerb_color : source_color = vec3(1.0, 0.32, 0.08);
uniform vec3 pad_color : source_color = vec3(0.1, 0.95, 0.35);

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float width_m = COLOR.a * 32.0;
	float u = UV.x;
	float v = UV.y;
	float across = (u - 0.5) * width_m;          // metres from the centre line
	float edge_d = (0.5 - abs(u - 0.5)) * width_m;  // metres to the nearest edge
	float detail = 1.0 - smoothstep(60.0 * lod_detail, 220.0 * lod_detail, length(VERTEX));

	// Panels 4 m long with a slight tint each.
	float panel_id = floor(v / 4.0);
	float tint = hash21(vec2(panel_id, floor(u * 4.0)));
	vec3 col = vec3(0.075, 0.08, 0.09) * (0.85 + 0.3 * tint);
	if (detail > 0.0) {
		col += (vnoise(vec2(across, v) * 3.0) - 0.5) * 0.02 * detail;
	}
	float seam = 1.0 - smoothstep(0.02, 0.06 + fwidth(v), abs(fract(v / 4.0 + 0.5) - 0.5) * 4.0);
	col *= 1.0 - seam * 0.35 * detail;

	// Moss in from the edges and along the seams.
	float n = fbm(vec2(across * 0.6, v * 0.25));
	float moss = (1.0 - smoothstep(0.2, 1.4 + n * 1.5, edge_d)) * smoothstep(0.35, 0.6, n);
	moss = max(moss, seam * smoothstep(0.55, 0.75, n) * 0.8);
	col = mix(col, mix(vec3(0.12, 0.22, 0.06), vec3(0.22, 0.32, 0.1), vnoise(vec2(across, v) * 1.3)), moss * 0.85);

	// Edge lines and a dashed centre line.
	float line_w = 0.18 + fwidth(across);
	float edge_line = 1.0 - smoothstep(0.0, line_w, abs(edge_d - 0.9));
	float centre = (1.0 - smoothstep(0.0, line_w, abs(across))) * step(0.55, fract(v / 6.0));
	vec3 emit = edge_color * edge_line * 2.2 + vec3(0.7, 0.75, 0.8) * centre * 0.25;
	col = mix(col, vec3(0.6, 0.65, 0.7), centre * 0.5);

	// Kerbs on turns: red-orange / dark stripes along the edges.
	float kerb = COLOR.r * (1.0 - smoothstep(0.0, 0.1, edge_d - 1.1 + 0.0)) * step(edge_d, 1.2);
	float stripe = step(0.5, fract(v / 2.0));
	col = mix(col, mix(kerb_color, vec3(0.08), stripe), kerb);
	emit += kerb_color * kerb * (1.0 - stripe) * 0.6;

	// Boost pads: chevrons pointing forward, scrolling.
	float chev = fract((v - abs(across) * 0.6) / 3.0 + TIME * 1.5);
	float pad = COLOR.g * step(abs(across), width_m * 0.3) * smoothstep(0.55, 0.6, chev) * (1.0 - smoothstep(0.85, 0.9, chev));
	col = mix(col, pad_color * 0.4, COLOR.g * step(abs(across), width_m * 0.3) * 0.5);
	emit += pad_color * pad * 3.0;

	// Start / checkpoint line: chequers.
	vec2 ch = floor(vec2(across, v) / 1.0);
	float chk = mod(ch.x + ch.y, 2.0);
	col = mix(col, vec3(chk * 0.85 + 0.05), COLOR.b);
	emit += edge_color * COLOR.b * chk * 0.4;

	ALBEDO = col;
	ROUGHNESS = mix(0.55, 0.95, moss);
	METALLIC = 0.15 * (1.0 - moss);
	EMISSION = emit;
}
