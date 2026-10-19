shader_type spatial;
render_mode cull_disabled;
// Far-away stand-ins (lod.gd far_mesh): one surface, the original
// materials baked into the vertex colour. COLOR.rgb = sRGB albedo,
// COLOR.a = glow (emission / albedo, divided by 16).

void fragment() {
	vec3 c = COLOR.rgb;
	ALBEDO = mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c));
	ROUGHNESS = 0.85;
	BACKLIGHT = ALBEDO * 0.3;           // as the foliage shader, so leaves don't darken at the swap
	EMISSION = ALBEDO * COLOR.a * 16.0;
}
