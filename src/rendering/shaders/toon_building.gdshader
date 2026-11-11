// Bâtiments low poly : murs à fenêtres procédurales (UV = abscisse le long du mur, hauteur), toits unis.
// La nuit, une partie des fenêtres s'allume (tirage stable par fenêtre).
shader_type spatial;
render_mode cull_disabled;

global uniform float night;
uniform float bands = 3.0;
uniform float shade_floor = 0.45;
uniform vec3 window_day = vec3(0.32, 0.4, 0.48);
uniform vec3 window_night = vec3(1.0, 0.82, 0.5);
uniform float floor_h = 3.0;
uniform float bay_w = 3.2;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

vec3 to_linear(vec3 c) { return pow(c, vec3(2.2)); }

void fragment() {
	NORMAL = normalize(cross(dFdy(VERTEX), dFdx(VERTEX)));
	vec3 base = to_linear(COLOR.rgb);
	ALBEDO = base;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	if (COLOR.a < 0.25) {  // lampadaires, feux : lumineux, surtout la nuit
		EMISSION = base * (0.3 + 2.2 * night);
	}
	if (UV.y > 1.0 && COLOR.a > 0.5) {  // murs (hors rez-de-chaussée bas) des bâtiments à fenêtres
		vec2 cell = vec2(UV.x / bay_w, (UV.y - 0.4) / floor_h);
		vec2 f = fract(cell);
		float win = step(0.28, f.x) * step(f.x, 0.72) * step(0.3, f.y) * step(f.y, 0.8);
		if (win > 0.5) {
			float on = step(0.55, hash(floor(cell) + vec2(COLOR.a * 97.0, 13.0)));
			ALBEDO = mix(ALBEDO * 0.45 + to_linear(window_day) * 0.55, to_linear(window_day) * 0.25, night);
			EMISSION = window_night * on * night * 1.6;
		}
	}
}

void light() {
	float lit = clamp(dot(NORMAL, LIGHT), 0.0, 1.0) * ATTENUATION;
	float stepped = LIGHT_IS_DIRECTIONAL ? mix(shade_floor, 1.0, floor(lit * bands + 0.5) / bands) : lit;
	DIFFUSE_LIGHT += LIGHT_COLOR * stepped / PI;
}
