shader_type spatial;
render_mode cull_disabled;
// Leaves and vines: wind sway that grows with height, soft backlight.
// Set hanging = true for vines that hang down from their origin.

uniform vec4 albedo : source_color = vec4(0.2, 0.4, 0.15, 1.0);
uniform float sway = 0.25;
uniform float sway_height = 6.0;
uniform bool hanging = false;
uniform vec3 emission_color : source_color = vec3(0.0);
uniform float emission_energy = 0.0;

varying float tint;

void vertex() {
	vec3 o = MODEL_MATRIX[3].xyz;
	float y = hanging ? -VERTEX.y : VERTEX.y;
	float h = clamp(y / sway_height, 0.0, 1.5);
	float t = TIME * 1.2 + o.x * 0.07 + o.z * 0.05;
	float w = sway * h * h;
	VERTEX.x += sin(t + VERTEX.y * 0.3) * w;
	VERTEX.z += cos(t * 0.8 + VERTEX.x * 0.3) * w * 0.6;
	tint = fract(sin(dot(o.xz, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	ALBEDO = albedo.rgb * (0.82 + 0.3 * tint);
	ROUGHNESS = 0.8;
	BACKLIGHT = albedo.rgb * 0.35;
	EMISSION = emission_color * emission_energy;
}
