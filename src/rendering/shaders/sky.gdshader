// Ciel « physique simplifié » (équivalent PhysicalSkyMaterial piloté par DayNight/WeatherView) : dégradé zénith →
// horizon selon l'épaisseur d'air traversée (Rayleigh), diffusion avant autour du soleil (Mie, Henyey-Greenstein),
// disque solaire HDR (bloom), lune, étoiles, nuages volumiques approchés (bruit fBm lissé, bords doux, ombrage
// selon l'épaisseur). Les uniformes de teinte restent ceux de DayNight (cycle) et WeatherView (pluie, brouillard).
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
	f = f * f * (3.0 - 2.0 * f);   // interpolation lissée (plus de facettes)
	float a = h21(i), b = h21(i + vec2(1, 0)), c = h21(i + vec2(0, 1)), d = h21(i + vec2(1, 1));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void sky() {
	vec3 dir = EYEDIR;
	float y = dir.y;
	vec3 col;
	if (y >= 0.0) {
		// masse d'air relative (Kasten) : l'horizon traverse ~38× plus d'atmosphère que le zénith
		float airmass = 1.0 / (max(y, 0.0) + 0.15 * pow(93.885 - degrees(acos(clamp(y, 0.0, 1.0))), -1.253));
		float t = clamp(1.0 - log(airmass) / log(38.0), 0.0, 1.0);
		col = mix(horizon_color, top_color, pow(t, 0.8));
	} else {
		col = mix(horizon_color, ground_color, clamp(-y * 6.0, 0.0, 1.0));
	}
	// soleil / lune (lumière 0) : disque net + halo en 2 paliers
	if (LIGHT0_ENABLED) {
		float sd = dot(dir, LIGHT0_DIRECTION);
		float disk = smoothstep(0.99985, 0.99992, sd);
		// Mie (Henyey-Greenstein g = 0,76) : halo continu, pas de paliers
		float g = 0.76;
		float hg = (1.0 - g * g) / pow(1.0 + g * g - 2.0 * g * sd, 1.5) / (4.0 * PI);
		float halo = clamp(hg * 0.35, 0.0, 2.5);
		vec3 lc = mix(sun_glow, vec3(0.85, 0.9, 1.0), night);
		col += lc * halo * (1.0 - night * 0.6);
		// lune (la nuit, lumière 0 = lune) : mers sombres (bruit), terminateur de phase
		float mdisk = smoothstep(0.99990, 0.99995, sd);
		vec3 mlocal = dir - LIGHT0_DIRECTION * sd;
		float maria = vnoise(mlocal.xz * 300.0) * 0.6 + vnoise(mlocal.xz * 900.0 + 3.0) * 0.4;
		float phase = smoothstep(-0.004, 0.004, dot(mlocal, normalize(vec3(1.0, 0.2, 0.3))) + 0.003);
		vec3 moon = vec3(1.0, 0.98, 0.92) * mix(0.55, 1.0, smoothstep(0.35, 0.7, maria)) * mix(0.08, 1.0, phase) * 2.2;
		col = mix(col, lc * mix(16.0, 1.5, night), disk * (1.0 - night));
		col = mix(col, moon, max(mdisk, disk) * night);
		// rougeoiement de l'horizon côté soleil (lever / coucher)
		float side = clamp(dot(normalize(dir.xz + 1e-4), normalize(LIGHT0_DIRECTION.xz + 1e-4)) * 0.5 + 0.5, 0.0, 1.0);
		col += sun_glow * pow(side, 3.0) * (1.0 - smoothstep(0.0, 0.3, abs(y))) * 0.35 * (1.0 - night);
	}
	// étoiles : deux champs (brillantes rares, faibles nombreuses), teinte et scintillement par étoile, éteintes près
	// de l'horizon (pollution lumineuse) ; halo orangé de la ville à l'horizon la nuit ; ceinture de Vénus au crépuscule
	if (night > 0.0 && y > 0.0) {
		float vis = night * smoothstep(0.05, 0.35, y) * (1.0 - cloud_cover * 0.6);
		for (int k = 0; k < 2; k++) {
			float sc = k == 0 ? 60.0 : 150.0;
			vec2 sp = dir.xz / (y + 0.3) * sc;
			vec2 cell = floor(sp);
			float r = h21(cell + float(k) * 17.0);
			float thr = k == 0 ? 0.994 : 0.985;
			float tw = 0.75 + 0.25 * sin(TIME * (2.0 + 5.0 * h21(cell + 3.0)) + r * 40.0);
			float s = step(thr, r) * smoothstep(k == 0 ? 0.3 : 0.18, 0.0, length(fract(sp) - 0.5)) * tw;
			vec3 tint = mix(vec3(1.0, 0.85, 0.7), vec3(0.75, 0.85, 1.0), h21(cell + 9.0));
			col += tint * s * vis * (k == 0 ? 1.4 : 0.5);
		}
	}
	if (night > 0.0 && y > -0.05) col += vec3(0.32, 0.2, 0.1) * 0.12 * night * exp(-max(y, 0.0) * 9.0);
	if (LIGHT0_ENABLED && night > 0.05 && night < 0.95 && y > 0.0) {
		float anti = clamp(-dot(normalize(dir.xz + 1e-4), normalize(LIGHT0_DIRECTION.xz + 1e-4)), 0.0, 1.0);
		float band = exp(-pow((y - 0.08) / 0.07, 2.0)) * anti * (1.0 - abs(night - 0.5) * 2.0);
		col += vec3(0.55, 0.32, 0.42) * band * 0.25;
	}
	// nuages : plan à altitude fixe, fBm lissé, bords doux, ombrage par l'épaisseur
	if (y > 0.015) {
		vec2 uv = dir.xz / y * 0.55 + vec2(TIME * 0.004, TIME * 0.0015);
		float n = vnoise(uv * 1.3) * 0.6 + vnoise(uv * 2.9 + 7.0) * 0.3 + vnoise(uv * 6.1 + 3.0) * 0.1;
		n += (vnoise(uv * 13.0 + 1.7) - 0.5) * 0.06;
		float m = smoothstep(1.0 - cloud_cover, 1.0 - cloud_cover + 0.16, n);
		float lit = 1.0 - smoothstep(0.0, 0.3, n - (1.0 - cloud_cover));
		vec3 cc = mix(cloud_shade, cloud_light, lit);
		float fade = smoothstep(0.015, 0.12, y);
		col = mix(col, cc, m * fade * 0.92);
	}
	COLOR = col * energy;
}
