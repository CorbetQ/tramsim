// Low poly + cel shading : facettes plates (normales recalculées), éclairage en paliers, liseré de lumière.
// Couleur = couleur de sommet. COLOR.a < 0.75 : vitrage (éclairé de l'intérieur la nuit).
shader_type spatial;
render_mode cull_disabled;

global uniform float night;          // 0 = jour, 1 = nuit (piloté par DayNight)
uniform float bands : hint_range(2.0, 5.0) = 3.0;
uniform float shade_floor : hint_range(0.0, 1.0) = 0.42;
uniform float rim_strength : hint_range(0.0, 1.0) = 0.18;
uniform vec3 glass_glow = vec3(1.0, 0.86, 0.6);
uniform float glow_strength = 0.55;

vec3 to_linear(vec3 c) { return pow(c, vec3(2.2)); }

void fragment() {
	NORMAL = normalize(cross(dFdy(VERTEX), dFdx(VERTEX)));
	vec3 base = to_linear(COLOR.rgb);
	ALBEDO = base;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	if (COLOR.a < 0.75) {
		ALBEDO = mix(base, base * 0.5, night);
		EMISSION = glass_glow * glow_strength * night;
	}
	if (COLOR.a < 0.25) {  // feux / girouettes : toujours lumineux, plus forts la nuit
		EMISSION = base * (0.6 + 2.0 * night);
	}
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float lit = clamp(ndl, 0.0, 1.0) * ATTENUATION;
	float stepped = floor(lit * bands + 0.5) / bands;
	stepped = LIGHT_IS_DIRECTIONAL ? mix(shade_floor, 1.0, stepped) : lit;
	DIFFUSE_LIGHT += LIGHT_COLOR * stepped / PI;
	float rim = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	DIFFUSE_LIGHT += LIGHT_COLOR * rim_strength * step(0.72, rim) * clamp(ndl + 0.3, 0.0, 1.0) * ATTENUATION / PI;
}
