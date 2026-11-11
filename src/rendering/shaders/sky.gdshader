// Ciel stylisé : dégradé en 3 teintes (zénith, horizon, sol), soleil et halo, lune, étoiles,
// nuages low poly (masses posterisées en 2 tons, déplacées lentement).
shader_type sky;
render_mode use_debanding;

uniform vec3 top_color : source_color = vec3(0.25, 0.5, 0.85);
uniform vec3 horizon_color : source_color = vec3(0.75, 0.85, 0.95);
uniform vec3 ground_color : source_color = vec3(0.35, 0.38, 0.42);
uniform vec3 sun_glow : source_color = vec3(1.0, 0.8, 0.55);
uniform vec3 cloud_light : source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 cloud_shade : source_color = vec3(0.7, 0.75, 0.85);
uniform float cloud_cover = 0.45;
uniform float night = 0.0;
uniform float energy = 1.0;

float h21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	// interpolation linéaire : facettes franches (aspect low poly)
	float a = h21(i), b = h21(i + vec2(1, 0)), c = h21(i + vec2(0, 1)), d = h21(i + vec2(1, 1));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void sky() {
	vec3 dir = EYEDIR;
	float y = dir.y;
	vec3 col;
	if (y >= 0.0) {
		float t = pow(clamp(y, 0.0, 1.0), 0.55);
		col = mix(horizon_color, top_color, t);
	} else {
		col = mix(horizon_color, ground_color, clamp(-y * 6.0, 0.0, 1.0));
	}
	// soleil / lune (lumière 0) : disque net + halo en 2 paliers
	if (LIGHT0_ENABLED) {
		float sd = dot(dir, LIGHT0_DIRECTION);
		float disk = smoothstep(0.9993, 0.9996, sd);
		float halo = smoothstep(0.96, 0.99, sd) * 0.35 + smoothstep(0.75, 1.0, sd) * 0.25;
		vec3 lc = mix(sun_glow, vec3(0.85, 0.9, 1.0), night);
		col += lc * halo * (1.0 - night * 0.6);
		col = mix(col, lc * mix(3.0, 1.2, night), disk);
		// rougeoiement de l'horizon côté soleil (lever / coucher)
		float side = clamp(dot(normalize(dir.xz + 1e-4), normalize(LIGHT0_DIRECTION.xz + 1e-4)) * 0.5 + 0.5, 0.0, 1.0);
		col += sun_glow * pow(side, 3.0) * (1.0 - smoothstep(0.0, 0.3, abs(y))) * 0.35 * (1.0 - night);
	}
	// étoiles
	if (night > 0.0 && y > 0.0) {
		vec2 sp = dir.xz / (y + 0.3) * 60.0;
		float s = step(0.996, h21(floor(sp))) * smoothstep(0.35, 0.15, length(fract(sp) - 0.5));
		col += vec3(0.9, 0.92, 1.0) * s * night * smoothstep(0.05, 0.3, y);
	}
	// nuages : plan à altitude fixe, masses posterisées
	if (y > 0.015) {
		vec2 uv = dir.xz / y * 0.55 + vec2(TIME * 0.004, TIME * 0.0015);
		float n = vnoise(uv * 1.3) * 0.6 + vnoise(uv * 2.9 + 7.0) * 0.3 + vnoise(uv * 6.1 + 3.0) * 0.1;
		float m = smoothstep(1.0 - cloud_cover, 1.0 - cloud_cover + 0.03, n);
		float lit = smoothstep(0.025, 0.04, n - (1.0 - cloud_cover) + (vnoise(uv * 2.9 + 7.3) - 0.5) * 0.04);
		vec3 cc = mix(cloud_shade, cloud_light, lit);
		float fade = smoothstep(0.015, 0.12, y);
		col = mix(col, cc, m * fade * 0.92);
	}
	COLOR = col * energy;
}
