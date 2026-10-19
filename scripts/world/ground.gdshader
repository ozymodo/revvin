shader_type spatial;
// The city floor: cracked asphalt avenues every 150 m, fading into
// overgrown blocks of soil, moss and grass. Grass fills the cracks, old
// lane paint has nearly gone, and faint bioluminescent veins (the city's
// old data lines, colonised by fungus) pulse through the ground.

#include "res://scripts/world/noise.gdshaderinc"

global uniform float lod_detail;
uniform float avenue_spacing = 150.0;
uniform float avenue_half = 14.0;
uniform vec3 vein_color : source_color = vec3(0.08, 0.85, 0.32);

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wpos.xz;
	float dist = length(VERTEX);
	// Fine detail (grain, cracks) fades out with distance; lod_detail
	// (world LOD, lod.gd) pulls that distance in when frames run long.
	float detail = 1.0 - smoothstep(80.0 * lod_detail, 260.0 * lod_detail, dist);
	// Derivatives first: they're undefined inside the branches below.
	float fw = fwidth(p.x * 0.32) + 0.01;
	float vfw = fwidth(p.x * 0.07) + 0.004;

	float dx = abs(mod(p.x + avenue_spacing * 0.5, avenue_spacing) - avenue_spacing * 0.5);
	float dz = abs(mod(p.y + avenue_spacing * 0.5, avenue_spacing) - avenue_spacing * 0.5);
	float d_road = min(dx, dz);
	float road = 1.0 - smoothstep(avenue_half - 2.0, avenue_half + 3.0, d_road + (vnoise(p * 0.2) - 0.5) * 4.0);

	float big = fbm(p * 0.025 + 3.1);
	float fine = detail > 0.0 ? vnoise(p * 2.7) : 0.5;
	vec3 asphalt = vec3(0.12, 0.125, 0.13) * (0.8 + 0.35 * fbm(p * 0.18)) + (fine - 0.5) * 0.03 * detail;
	vec3 soil = vec3(0.15, 0.12, 0.085);
	vec3 grass = mix(vec3(0.13, 0.22, 0.07), vec3(0.25, 0.32, 0.11), vnoise(p * 0.4));
	vec3 moss = vec3(0.2, 0.3, 0.1);

	float over = mix(0.9, 0.18, road) * (0.45 + 0.75 * big);
	float g = smoothstep(0.35, 0.75, over + (fine - 0.5) * 0.35 * detail);
	vec3 col = mix(asphalt, mix(soil, mix(grass, moss, vnoise(p * 0.09)), 0.75), g);

	// Cracks with grass growing in them (close up only).
	if (detail > 0.0) {
		float e = voronoi_edge(p * 0.32);
		float crack = (1.0 - smoothstep(0.0, 0.035 + fw, e)) * detail * (1.0 - g * 0.6);
		col = mix(col, vec3(0.1, 0.19, 0.06), crack * 0.85);
	}

	// Faded lane paint: dashed centre line, solid edge lines.
	float along = dx < dz ? p.y : p.x;
	float centre = (1.0 - smoothstep(0.12, 0.2, d_road)) * step(0.5, fract(along / 9.0));
	float edge = 1.0 - smoothstep(0.1, 0.18, abs(d_road - (avenue_half - 1.5)));
	float paint = (centre + edge * 0.8) * road * (1.0 - g) * smoothstep(0.3, 0.6, vnoise(p * 0.3 + 5.0));
	col = mix(col, vec3(0.62, 0.55, 0.32), paint * 0.6);

	// Bio-luminescent veins in the overgrown areas.
	// The mask first: the cells are only worked out where veins can show.
	float vein = smoothstep(0.55, 0.72, fbm(p * 0.04 + 21.0)) * (1.0 - road * 0.7);
	if (vein > 0.0) {
		float ve = voronoi_edge(p * 0.07 + 7.0);
		vein *= 1.0 - smoothstep(0.0, 0.02 + vfw, ve);
	}
	float pulse = 0.55 + 0.45 * sin(TIME * 1.4 - length(p) * 0.06);

	ALBEDO = col;
	ROUGHNESS = mix(0.82, 0.97, g);
	EMISSION = vein_color * vein * pulse * 1.3 * (0.3 + 0.7 * detail);
}
