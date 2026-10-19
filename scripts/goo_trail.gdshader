shader_type spatial;
render_mode cull_disabled, depth_draw_never;
// Tyre trails for every car, laid by goo_trail.gd behind the rear wheels.
// Each segment remembers which car laid it and how fast it was going, so
// the trail changes along its length as you speed up and slow down.
//   style 0  SYMBIOTE  glowing green ooze, vines growing across it, dirt.
//            Faster: the ooze stretches thin and bright, and pulses of
//            bioluminescence race down it.
//   style 1  NEON      a light ribbon. Slow: a dashed neon line. Faster: a
//            solid glowing ribbon with chevrons streaming down it. Flat
//            out: a white-hot core in a cyan plasma sheath with arcs of
//            electricity crackling along it.
//   style 2  PHANTOM   spectral mist. Slow: faint ghostly tyre prints.
//            Faster: wisps of green ghost-light curling off. Flat out: a
//            bright spectral streak with flickering runes in it.
// INSTANCE_CUSTOM.x = time laid, .y = style + random fraction (seed),
// .z = distance along the trail, .w = speed share 0..1 (~250 km/h = 1).
// `now` is set every frame by goo_trail.gd from the same clock as the laid
// time (the built-in TIME starts later, which hid new segments for seconds).

uniform float now = 0.0;
uniform vec3 neon_color = vec3(0.55, 0.45, 1.0);
uniform vec3 phantom_color = vec3(0.17, 1.0, 0.48);

varying float age;
varying float seed;
varying float along;
varying float spd;
varying float style;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void vertex() {
	age = now - INSTANCE_CUSTOM.x;
	style = floor(INSTANCE_CUSTOM.y + 0.001);
	seed = fract(INSTANCE_CUSTOM.y) * 10.0;
	along = INSTANCE_CUSTOM.z;
	spd = INSTANCE_CUSTOM.w;
}

void fragment() {
	// The strip is 1.2 m wide: the goo and neon styles use the middle 0.6 m
	// (x2 in [-0.5, 0.5]), the phantom's mist spreads over all of it.
	float x = UV.x - 0.5;
	float x2 = x * 2.0;
	float y = along + UV.y * 0.35;           // continuous coordinate down the trail
	vec3 albedo = vec3(0.0);
	vec3 emission = vec3(0.0);
	float alpha = 0.0;
	float rough = 0.9;
	float metal = 0.0;

	if (style < 0.5) {
		// ---------------- SYMBIOTE: goo and vines
		float lifetime = 14.0;
		float fade = 1.0 - smoothstep(lifetime * 0.5, lifetime, age);
		float grow = smoothstep(0.0, 0.5, age);
		float fresh = 1.0 - smoothstep(0.0, 4.0, age);
		float thin = mix(1.0, 0.6, smoothstep(0.3, 1.0, spd));       // stretched thin at speed
		float x = x2;
		float wob = (sin(y * 2.3 + seed) * 0.08 + sin(y * 5.1) * 0.04) * thin;
		float goo = 1.0 - smoothstep(0.16 * thin, 0.3 * thin, abs(x - wob));
		goo *= 0.75 + 0.25 * sin(y * 9.0 + TIME * 3.0);
		float v1 = 1.0 - smoothstep(0.015, 0.045, abs(x - 0.32 * sin(y * 1.7 + 1.3)));
		float v2 = 1.0 - smoothstep(0.012, 0.04, abs(x + 0.3 * sin(y * 2.2 + 0.4)));
		float reach = step(abs(x), 0.5 * grow);
		float vines = max(v1, v2) * reach * (1.0 - 0.6 * spd);
		float leaf = step(0.82, hash(floor(vec2(x * 10.0, y * 6.0)))) * reach * (1.0 - goo) * (1.0 - spd);
		float dirt = step(0.6, hash(floor(vec2(x * 22.0, y * 14.0)))) * (1.0 - smoothstep(0.35, 0.5, abs(x)));
		// Bioluminescent pulses racing down the trail, faster and brighter with speed.
		float pulse = pow(max(sin(y * 0.6 - now * mix(3.0, 16.0, spd)), 0.0), 6.0) * smoothstep(0.2, 0.55, spd) * goo;
		// Flat out the goo boils: bright bubbles pop along its core.
		float boil = step(0.8, hash(floor(vec2(x * 12.0, y * 5.0 - now * 4.0)))) * goo * smoothstep(0.45, 0.8, spd);
		vec3 goo_col = mix(vec3(0.12, 0.55, 0.18), vec3(0.3, 0.85, 0.35), spd);
		vec3 col = vec3(0.17, 0.12, 0.06);
		col = mix(col, goo_col, goo);
		col = mix(col, vec3(0.06, 0.26, 0.05), max(vines, leaf));
		albedo = col;
		rough = mix(0.95, 0.15, goo);
		metal = goo * 0.2;
		emission = vec3(0.15, 1.0, 0.32) * (goo * (0.25 + 1.4 * fresh) * (1.0 + 1.2 * spd) + vines * 0.25 * fresh)
			+ vec3(0.6, 1.0, 0.5) * (pulse * 5.0 + boil * 3.0) * fade;
		alpha = clamp(max(max(goo * 0.9, vines), max(dirt * 0.55, leaf * 0.9)), 0.0, 1.0) * fade;
	} else if (style < 1.5) {
		// ---------------- NEON: light ribbon -> chevrons -> plasma
		float life = mix(4.0, 8.0, spd);
		float fade = 1.0 - smoothstep(life * 0.25, life, age);
		float fresh = 1.0 - smoothstep(0.0, life * 0.4, age);
		float x = x2 * 0.5;                  // the neon may use the whole strip at speed
		float w = mix(0.04, 0.24, smoothstep(0.0, 0.75, spd));
		float ax = abs(x);
		float core = 1.0 - smoothstep(w * 0.25, w * 0.6, ax);
		float glow = 1.0 - smoothstep(w * 0.4, min(w * 1.6 + 0.05, 0.5), ax);
		float dash = mix(step(0.45, fract(y * 0.9)), 1.0, smoothstep(0.12, 0.3, spd));
		float chev = smoothstep(0.55, 1.0, sin((y + ax * 3.0) * 2.0 - now * mix(6.0, 26.0, spd))) * smoothstep(0.2, 0.4, spd) * glow;
		float arc_on = smoothstep(0.45, 0.7, spd);
		float flick = floor(now * 18.0 + seed);
		float arc = (1.0 - smoothstep(0.0, 0.015, abs(x - 0.3 * sin(y * 6.0 + flick * 2.7) * (0.6 + 0.4 * hash(vec2(flick, floor(y)))))))
			* step(0.35, hash(vec2(floor(y * 0.7), flick))) * arc_on;
		vec3 base = mix(neon_color, vec3(0.35, 0.95, 1.0), smoothstep(0.4, 0.8, spd));
		vec3 col = mix(base, vec3(1.0), core * smoothstep(0.4, 0.9, spd) * 0.7);
		albedo = col * 0.3;
		rough = 0.2;
		emission = (col * (core * mix(1.2, 2.6, spd) + glow * 1.1 + chev * 2.2) * dash + vec3(0.7, 0.95, 1.0) * arc * 4.0)
			* (0.35 + 1.3 * fresh) * (0.6 + 0.7 * spd);
		alpha = clamp((core * 0.9 + glow * 0.5 + chev * 0.5) * dash + arc, 0.0, 1.0) * fade;
	} else {
		// ---------------- PHANTOM: ghost prints -> wisps -> spectral streak
		float life = mix(3.0, 6.0, spd);
		float fade = 1.0 - smoothstep(life * 0.3, life, age);
		float fresh = 1.0 - smoothstep(0.0, life * 0.5, age);
		float ax = abs(x);
		float spread = 1.0 + age * 0.6;                                // mist drifts outward as it ages
		// Ghostly tread prints (slow).
		float tread = step(0.55, fract(y * 3.2)) * (1.0 - smoothstep(0.28, 0.38, ax)) * (1.0 - smoothstep(0.2, 0.5, spd));
		// Mist and wisps.
		float n = vnoise(vec2(x * 5.0 / spread, y * 1.2 - now * 0.8 + seed));
		float mist = (1.0 - smoothstep(0.1, 0.48, ax / spread)) * smoothstep(0.35, 0.8, n);
		float w1 = 1.0 - smoothstep(0.02, 0.09, abs(x - 0.22 * spread * sin(y * 1.4 + now * 1.7 + seed)));
		float w2 = 1.0 - smoothstep(0.02, 0.08, abs(x + 0.2 * spread * sin(y * 1.9 - now * 1.3)));
		float wisps = max(w1, w2) * smoothstep(0.1, 0.35, spd) * (0.5 + 0.5 * n);
		// Spectral streak and runes (fast).
		float streak = (1.0 - smoothstep(0.03, 0.12, ax)) * smoothstep(0.35, 0.7, spd) * (0.7 + 0.3 * sin(y * 3.0 - now * 20.0));
		vec2 cell = floor(vec2(x * 7.0, y * 2.5));
		float rune = step(0.86, hash(cell + floor(now * 6.0))) * (1.0 - smoothstep(0.3, 0.45, ax)) * smoothstep(0.45, 0.8, spd);
		vec3 col = mix(phantom_color, vec3(0.75, 1.0, 0.95), smoothstep(0.45, 0.9, spd) * 0.6);
		albedo = col * 0.1;
		rough = 0.5;
		emission = col * (tread * 0.6 + mist * 0.7 + wisps * 1.8 + streak * 3.5 + rune * 2.5) * (0.4 + 1.2 * fresh);
		alpha = clamp(tread * 0.35 + mist * 0.45 + wisps * 0.7 + streak * 0.8 + rune * 0.8, 0.0, 1.0) * fade;
	}
	ALBEDO = albedo;
	EMISSION = emission;
	ROUGHNESS = rough;
	METALLIC = metal;
	ALPHA = alpha;
}
