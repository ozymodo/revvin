shader_type spatial;
// Ruined arcology towers. Window grid: most panes dead or broken, a few
// still lit and flickering. Vines hang from the roofline, moss climbs
// from the street, roofs have gone green. Per-building variety comes from
// instance uniforms set in city.gd.

#include "res://scripts/world/noise.gdshaderinc"

instance uniform float roof_h = 40.0;
instance uniform float seed = 0.0;
instance uniform float base_y = 0.0;
global uniform float lod_detail;
uniform vec3 vein_color : source_color = vec3(0.08, 0.85, 0.32);

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float detail = 1.0 - smoothstep(120.0 * lod_detail, 420.0 * lod_detail, length(VERTEX));
	vec3 concrete = mix(vec3(0.36, 0.36, 0.35), vec3(0.42, 0.4, 0.36), hash21(vec2(seed, 1.0)));
	concrete *= 0.8 + 0.3 * hash21(vec2(seed, 7.0));
	float h = wpos.y - base_y;

	if (wnrm.y > 0.6) {
		// Roof: gone to grass and moss.
		float n = fbm(wpos.xz * 0.3);
		ALBEDO = mix(vec3(0.16, 0.25, 0.08), vec3(0.28, 0.33, 0.12), n);
		ROUGHNESS = 0.95;
	} else {
		float u = abs(wnrm.x) > abs(wnrm.z) ? wpos.z : wpos.x;
		float vfw = fwidth(u * 0.18);
		vec2 grid = vec2(u / 3.2, h / 3.6);
		vec2 cell = floor(grid);
		vec2 f = fract(grid);
		float win = step(0.14, f.x) * step(f.x, 0.86) * step(0.22, f.y) * step(f.y, 0.78) * step(1.0, cell.y);
		float r = hash21(cell + seed * 13.1);
		vec3 col = concrete * (0.85 + 0.2 * vnoise(vec2(u, h) * 0.3));
		vec3 glass = vec3(0.05, 0.07, 0.08);
		float broken = step(r, 0.25);
		float lit = step(0.955, r);
		col = mix(col, broken > 0.5 ? vec3(0.02) : glass, win);

		// A few windows still lit: amber, cyan or magenta, some flickering.
		// Deep green, vibrant blue, or red-orange for the occasional flare.
		vec3 lc = r > 0.985 ? vec3(1.0, 0.36, 0.1) : (r > 0.97 ? vec3(0.18, 0.45, 1.0) : vec3(0.2, 0.9, 0.35));
		float flick = r > 0.975 ? step(0.25, fract(sin(TIME * (3.0 + r * 9.0) + r * 40.0) * 43758.5)) : 1.0;
		vec3 emis = lc * win * lit * flick * 2.2;

		// Vines hanging from the roofline in ragged curtains.
		float colv = vnoise(vec2(u * 0.45 + seed * 5.0, 1.0));
		float length_v = roof_h * (0.15 + 0.75 * vnoise(vec2(u * 0.12 + seed, 4.0)));
		float vine = smoothstep(0.42, 0.5, colv) * step(roof_h - h, length_v);
		if (vine > 0.0) {
			vine *= smoothstep(0.35, 0.6, vnoise(vec2(u * 7.0, h * 5.0)) * 0.6 + vnoise(vec2(u * 2.0, h * 0.6)) * 0.5);
		}
		// Moss climbing from the street (never above 9 m).
		float moss = 0.0;
		if (h < 9.0) {
			moss = 1.0 - smoothstep(0.0, 3.0 + 6.0 * fbm(vec2(u * 0.1, seed)), h);
			moss *= smoothstep(0.35, 0.55, vnoise(vec2(u, h) * 2.5) * 0.5 + vnoise(vec2(u, h) * 0.6) * 0.5);
		}
		float green = clamp(vine + moss, 0.0, 1.0);
		if (green > 0.0) {
			col = mix(col, mix(vec3(0.1, 0.19, 0.06), vec3(0.24, 0.32, 0.11), vnoise(vec2(u, h) * 4.0)), green);
		}
		emis *= 1.0 - green;

		// Glowing veins in the concrete near the base, on half the towers.
		float vein = (1.0 - smoothstep(4.0, 18.0, h)) * step(0.5, hash21(vec2(seed, 3.0))) * (1.0 - green);
		if (vein > 0.0) {
			float ve = voronoi_edge(vec2(u, h) * 0.18 + seed);
			vein *= 1.0 - smoothstep(0.0, 0.03 + vfw, ve);
		}
		emis += vein_color * vein * (0.5 + 0.5 * sin(TIME * 1.3 + h * 0.4)) * 1.4;

		ALBEDO = col;
		ROUGHNESS = mix(0.9, 0.25, win * (1.0 - broken)) ;
		METALLIC = win * 0.5;
		EMISSION = emis * (0.4 + 0.6 * detail);
	}
}
