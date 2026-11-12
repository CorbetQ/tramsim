// Décor low poly (bâtiments, sol, voies, routes) : cel shading en paliers (cel.gdshaderinc), facettes plates.
// Murs à fenêtres procédurales (UV = abscisse le long du mur, hauteur ; alpha > 0.5 = graine de façade) :
// encadrements, bandeaux d'étage, soubassement ; détails estompés vers leur teinte moyenne avec la distance
// (pas de moiré). La nuit, une partie des fenêtres s'allume (tirage stable par fenêtre).
// Alpha : < 0.25 lumineux (lampadaires, feux), 0.42-0.48 vitrines, 0.35 surfaces unies.
shader_type spatial;
render_mode cull_disabled;

#include "res://src/rendering/shaders/cel.gdshaderinc"

uniform float bands = 3.0;            // conservé (compatibilité)
uniform float shade_floor = 0.18;
uniform float rim_strength = 0.22;
uniform vec3 window_day : source_color = vec3(0.30, 0.40, 0.50);
uniform vec3 window_night : source_color = vec3(1.0, 0.78, 0.45);
uniform float floor_h = 3.0;
uniform float bay_w = 3.2;
// Les couleurs de sommets sont converties en linéaire ici (palette en sRGB).
uniform float color_gamma = 2.2;
uniform float saturation = 1.16;       // ravive les teintes (couleurs moins délavées)

varying vec3 v_world;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

vec3 to_linear(vec3 c) {
	vec3 l = pow(c, vec3(color_gamma));
	float g = dot(l, vec3(0.2126, 0.7152, 0.0722));
	return max(mix(vec3(g), l, saturation), vec3(0.0));
}

// Créneau anti-crénelé : 1 entre a et b (largeur de transition = taille d'un pixel).
float band(float x, float a, float b, float w) {
	return smoothstep(a - w, a + w, x) * (1.0 - smoothstep(b - w, b + w, x));
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	POSITION = cel_layer_clip(VERTEX, MODEL_MATRIX, MODELVIEW_MATRIX, PROJECTION_MATRIX);
}

void fragment() {
	NORMAL = normalize(cross(dFdy(VERTEX), dFdx(VERTEX)));
	vec3 base = to_linear(COLOR.rgb);
	vec3 wn = (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz;
	float vertical = 1.0 - abs(wn.y);
	// soubassement assombri au pied des murs (bâtiments)
	if (vertical > 0.8 && COLOR.a > 0.3 && v_world.y < 0.75 && v_world.y > -0.05)
		base *= 0.78;
	ALBEDO = base;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	if (COLOR.a < 0.25) {  // lampadaires, feux : lumineux, surtout la nuit
		EMISSION = base * (0.25 + 3.2 * night);
	}
	if (COLOR.a > 0.42 && COLOR.a < 0.48) {  // vitrines de rez-de-chaussée : reflet le jour, éclairées le soir
		float sky = smoothstep(0.0, 3.4, v_world.y);
		ALBEDO = mix(base * 0.6 + vec3(0.05, 0.08, 0.12) * (0.5 + sky), base * 0.3, night);
		EMISSION = vec3(1.0, 0.72, 0.4) * 1.6 * night;
	}
	if (UV.y > 1.0 && COLOR.a > 0.5) {  // murs (hors rez-de-chaussée bas) des bâtiments à fenêtres
		vec2 cell = vec2(UV.x / bay_w, (UV.y - 0.4) / floor_h);
		vec2 f = fract(cell);
		vec2 fw = max(fwidth(cell), vec2(1e-4));
		float detail = 1.0 - smoothstep(0.12, 0.3, max(fw.x, fw.y)); // estompe au-delà de ~5 px par cellule
		float win = band(f.x, 0.3, 0.7, fw.x) * band(f.y, 0.3, 0.8, fw.y);
		float frame = band(f.x, 0.26, 0.74, fw.x) * band(f.y, 0.26, 0.84, fw.y) - win;
		float sill = band(f.x, 0.25, 0.75, fw.x) * band(f.y, 0.22, 0.28, fw.y);
		float course = band(f.y, 0.0, 0.035, fw.y);           // bandeau d'étage
		float on = step(0.55, hash(floor(cell) + vec2(COLOR.a * 97.0, 13.0)));
		float warm = hash(floor(cell) + vec2(5.3, COLOR.a * 31.0));
		vec3 glass = mix(to_linear(window_day) * mix(0.8, 1.15, f.y), to_linear(window_day) * 0.18, night);
		vec3 lit_col = window_night * mix(vec3(1.0), vec3(1.0, 0.92, 1.12), step(0.7, warm));
		// détail complet de près, teinte moyenne au loin
		vec3 near_col = base;
		near_col = mix(near_col, base * 1.12, clamp(frame + sill, 0.0, 1.0) * 0.8);
		near_col = mix(near_col, base * 0.8, course * 0.6);
		near_col = mix(near_col, glass, win);
		vec3 far_col = mix(base, glass, 0.2);
		ALBEDO = mix(far_col, near_col, detail);
		vec3 em_near = lit_col * on * win * night * 1.9;
		vec3 em_far = window_night * 0.45 * 0.2 * night * 1.9;
		EMISSION = mix(em_far, em_near, detail);
	}
}

void light() {
	DIFFUSE_LIGHT += cel_light(NORMAL, LIGHT, VIEW, LIGHT_COLOR, ATTENUATION, LIGHT_IS_DIRECTIONAL,
		shade_floor, 1.0, rim_strength);
}
