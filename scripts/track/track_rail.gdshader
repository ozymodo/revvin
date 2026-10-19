shader_type spatial;
// Course barriers. UV.x: 0..1 inner face (bottom to top), 1..2 top cap.
// UV.y: metres along the track. COLOR.r: how hard the road turns; turns get
// red-orange chevrons pointing the way, straights a calm blue light strip.

#include "res://scripts/world/noise.gdshaderinc"

uniform vec3 strip_color : source_color = vec3(0.15, 0.45, 1.0);
uniform vec3 turn_color : source_color = vec3(1.0, 0.32, 0.08);
uniform vec3 vine_color : source_color = vec3(0.08, 0.85, 0.32);

void fragment() {
	float h = UV.x;
	float v = UV.y;
	float detail = 1.0 - smoothstep(60.0, 220.0, length(VERTEX));
	vec3 col = vec3(0.14, 0.15, 0.17) * (0.85 + 0.25 * hash21(vec2(floor(v / 3.0), 1.0)));
	float seam = 1.0 - smoothstep(0.02, 0.05 + fwidth(v), abs(fract(v / 3.0 + 0.5) - 0.5) * 3.0);
	col *= 1.0 - seam * 0.4 * detail;

	// Light strip near the top of the inner face; chevrons on turns.
	float strip = step(h, 1.0) * (1.0 - smoothstep(0.0, 0.06, abs(h - 0.72)));
	float turn = COLOR.r;
	float chev = step(0.5, fract(v / 2.5 + abs(h - 0.5) * 0.6));
	float chev_band = step(h, 1.0) * step(0.15, h) * step(h, 0.6) * turn * chev;
	vec3 emit = strip_color * strip * 2.0 * (1.0 - turn * 0.6) + turn_color * chev_band * 1.4;
	col = mix(col, turn_color * 0.5, chev_band);

	// Vines over the top and down the face.
	float n = fbm(vec2(v * 0.3, h * 2.0));
	float vine = smoothstep(0.58, 0.7, n) * (h > 1.0 ? 1.0 : smoothstep(0.2, 0.9, h));
	col = mix(col, vec3(0.15, 0.27, 0.08), vine * 0.9);
	float glow = (1.0 - smoothstep(0.0, 0.02, abs(n - 0.64))) * vine;
	emit += vine_color * glow * 0.8 * detail;

	ALBEDO = col;
	ROUGHNESS = mix(0.45, 0.9, vine);
	METALLIC = 0.4 * (1.0 - vine);
	EMISSION = emit;
}
