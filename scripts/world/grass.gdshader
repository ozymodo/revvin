shader_type spatial;
render_mode cull_disabled;
// Grass clumps: blade height in UV.y, a per-blade "bioluminescent tip" flag
// in COLOR.g. Sways in the wind and bends away from the car.

global uniform vec3 car_pos;
uniform vec3 base_col : source_color = vec3(0.1, 0.18, 0.05);
uniform vec3 tip_col : source_color = vec3(0.42, 0.5, 0.18);
uniform vec3 glow_col : source_color = vec3(0.2, 0.95, 0.35);

void vertex() {
	float h = UV.y * UV.y;
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float t = TIME * 1.8 + w.x * 0.15 + w.z * 0.11;
	vec3 push = vec3(sin(t) * 0.14, 0.0, cos(t * 0.7) * 0.09) * h;
	vec3 away = w - car_pos;
	away.y = 0.0;
	float d = length(away);
	float flat_k = (1.0 - smoothstep(1.2, 3.2, d)) * step(abs(w.y - car_pos.y), 3.0);
	push += normalize(away + vec3(0.001)) * flat_k * 0.6 * UV.y;
	push.y -= flat_k * 0.4 * UV.y;
	VERTEX += (inverse(MODEL_MATRIX) * vec4(push, 0.0)).xyz;
}

void fragment() {
	ALBEDO = mix(base_col, tip_col, UV.y) * (0.75 + 0.5 * COLOR.r);
	ROUGHNESS = 0.9;
	BACKLIGHT = tip_col * 0.3;
	EMISSION = glow_col * COLOR.g * UV.y * UV.y * 1.8;
}
