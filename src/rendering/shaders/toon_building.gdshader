// Décor low poly (bâtiments, sol, voies, routes) : cel shading en paliers (cel.gdshaderinc), facettes plates.
// Identifiant de matériau : UV2.x (partie entière ; partie fractionnaire × 1024 = graine de façade), hauteur
// au-dessus du terrain : UV2.y (CityScene._Arrays.mesh, LineView._add_geo). Sans UV2 (maillages hérités), repli
// sur COLOR.a : < 0.25 lumineux, 0.28 enrobé, 0.29 dallage, 0.30 sol végétal, 0.35 uni/toit, 0.42-0.48 vitrines,
// 0.5-0.9 façade (graine), sinon uni.
// Détail procédural stable : bruit métrique triplanaire à 3 octaves (≈ 8 m, 1 m, 10 cm), chaque octave fondue vers
// sa moyenne selon l'empreinte du pixel (dérivées calculées une seule fois : ni aplat de près, ni moiré au loin),
// masques d'usure (taches, reprises d'enrobé, coulures et soubassements, mousse des toits), sol végétal lissé
// (masque par tuile filtré bilinéairement). Couleurs : restituées telles quelles en Compatibility (pas de gamma).
shader_type spatial;
render_mode cull_disabled;

#include "res://src/rendering/shaders/cel.gdshaderinc"

uniform float bands = 3.0;            // conservé (compatibilité)
uniform float shade_floor = 0.18;
uniform float rim_strength = 0.08;
uniform vec3 window_day : source_color = vec3(0.24, 0.30, 0.36);
uniform vec3 window_night : source_color = vec3(1.0, 0.78, 0.45);
uniform float floor_h = 3.0;
uniform float bay_w = 3.2;
uniform float color_gamma = 1.0;      // 1.0 : une seule chaîne de couleur (mesuré en Compatibility)
uniform float saturation = 1.0;
uniform float detail = 1.0;           // amplitude globale du détail procédural
// Les palettes (city_styles.json, toits issus de l'orthophoto) sont des teintes APPARENTES (mesurées éclairées,
// comme les livrées des rames) : soleil + ciel ≈ 1,27 sur une face au soleil, d'où l'albédo = teinte × 0,79.
uniform float albedo_scale = 0.79;
// Masque de végétation au sol (tuile de décor) : R = part végétale, filtré bilinéairement.
uniform sampler2D veg_mask : filter_linear, repeat_disable, hint_default_black;
uniform float veg_inv_size = 0.0;     // 1 / taille de tuile (m) ; 0 = pas de masque
uniform vec3 veg_color : source_color = vec3(0.34, 0.39, 0.23);   // albédo (teinte apparente ≈ #6c7c4a)

varying vec3 v_world;
varying vec2 v_local;
varying float v_h;
varying flat float mat_id;
varying flat float facade_seed;

const float M_LIGHT = 1.0;
const float M_ASPHALT = 2.0;
const float M_PAVING = 3.0;
const float M_VEG = 4.0;
const float M_SOLID = 5.0;
const float M_SHOP = 6.0;
const float M_FACADE = 7.0;
const float M_PLAIN = 8.0;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

vec3 to_linear(vec3 c) {
	vec3 l = pow(max(c, vec3(0.0)), vec3(color_gamma));
	float g = dot(l, vec3(0.2126, 0.7152, 0.0722));
	return max(mix(vec3(g), l, saturation), vec3(0.0));
}

// Créneau anti-crénelé : 1 entre a et b (largeur de transition = taille d'un pixel).
float band(float x, float a, float b, float w) {
	return smoothstep(a - w, a + w, x) * (1.0 - smoothstep(b - w, b + w, x));
}

float legacy_id(float a) {
	if (a < 0.25) return M_LIGHT;
	if (a > 0.275 && a < 0.285) return M_ASPHALT;
	if (a > 0.285 && a < 0.295) return M_PAVING;
	if (a > 0.295 && a < 0.305) return M_VEG;
	if (a > 0.34 && a < 0.36) return M_SOLID;
	if (a > 0.42 && a < 0.48) return M_SHOP;
	if (a > 0.5 && a < 0.999) return M_FACADE;
	return M_PLAIN;
}

void vertex() {
	if (UV2.x >= 0.5) {
		mat_id = floor(UV2.x);
		facade_seed = floor(fract(UV2.x) * 1024.0 + 0.5);
	} else {
		mat_id = legacy_id(COLOR.a);
		facade_seed = floor(COLOR.a * 1000.0 + 0.5);
	}
	v_h = UV2.y;
	v_local = VERTEX.xz;
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	POSITION = cel_layer_clip(VERTEX, UV2.y, MODELVIEW_MATRIX, PROJECTION_MATRIX);
}

float noise2(vec2 p) {
	vec2 i = floor(p), f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1)), f.x), f.y);
}
// Octave centrée (moyenne 0) fondue vers 0 quand une cellule couvre moins de ~1,5 pixel.
float oct(vec2 p, float s, float px) {
	return (noise2(mod(p * s, 4096.0)) - 0.5) * (1.0 - smoothstep(0.3, 0.75, px * s));
}
float oct3(vec2 p, vec3 amp, float px) {
	return amp.x * oct(p, 0.125, px) + amp.y * oct(p, 1.0, px) + amp.z * oct(p, 10.0, px);
}
// Triplanaire métrique (projections pondérées par la normale monde).
float tri3(vec3 p, vec3 n, vec3 amp, float px) {
	vec3 w = pow(abs(n), vec3(4.0)); w /= (w.x + w.y + w.z + 1e-4);
	return w.x * oct3(p.zy, amp, px) + w.y * oct3(p.xz, amp, px) + w.z * oct3(p.xy + 17.0, amp, px);
}

void fragment() {
	// Dérivées hors de toute branche (contrôle de flot non uniforme sinon).
	vec3 dpx = dFdx(v_world), dpy = dFdy(v_world);
	float px = max(length(dpx), length(dpy));           // mètres par pixel
	vec2 fw_uv = fwidth(UV);
	NORMAL = normalize(cross(dFdy(VERTEX), dFdx(VERTEX)));
	vec3 base = to_linear(COLOR.rgb) * albedo_scale;
	vec3 wn = (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz;
	float vertical = 1.0 - abs(wn.y);
	vec2 xz = v_world.xz;
	float id = mat_id;
	ROUGHNESS = 0.88;
	SPECULAR = 0.0;
	// Détail macro/méso/micro commun (aucun aplat de près ni de loin).
	float d3 = tri3(v_world, wn, vec3(0.10, 0.06, 0.05) * detail, px);
	if (id == M_ASPHALT) {
		float agg = oct3(xz, vec3(0.10, 0.07, 0.16) * detail, px);
		float stain = smoothstep(0.66, 0.80, noise2(xz * 0.21 + 3.7)) * (1.0 - smoothstep(0.3, 0.75, px * 0.21));
		float repair = smoothstep(0.70, 0.76, noise2(floor(xz * 0.25) * 0.37 + 11.0)) * smoothstep(0.62, 0.70, noise2(xz * 0.045));
		ALBEDO = base * (1.0 + agg - stain * 0.14 - repair * 0.10);
		ROUGHNESS = 0.83;
	} else if (id == M_PAVING) {
		vec2 tile = xz * vec2(1.6, 2.4);
		tile.x += step(0.5, fract(floor(tile.y) * 0.5)) * 0.5;
		vec2 f = fract(tile), fw = max(px * vec2(1.6, 2.4), vec2(0.001));
		float joint = 1.0 - band(f.x, 0.018, 0.982, fw.x) * band(f.y, 0.025, 0.975, fw.y);
		float near_k = 1.0 - smoothstep(0.12, 0.45, max(fw.x, fw.y));   // fondu des carreaux vers leur teinte moyenne
		float tiles = mix(0.0, (0.12 * hash(floor(tile)) - 0.06) - 0.25 * joint + 0.012, near_k);
		ALBEDO = base * (0.99 + tiles + oct3(xz, vec3(0.09, 0.04, 0.0) * detail, px));
	} else if (id == M_VEG) {
		float n = oct3(xz, vec3(0.30, 0.16, 0.14) * detail, px);
		float dry = smoothstep(0.55, 0.8, noise2(xz * 0.07 + 5.0));
		ALBEDO = mix(base, base * vec3(1.12, 1.06, 0.82), dry * 0.5) * (1.0 + n);
	} else if (id == M_SOLID && vertical < 0.8) {
		// Ardoises et tuiles métriques sur les toitures, détails estompés au loin ; mousse/encrassement en macro.
		vec2 roof = xz * vec2(3.2, 4.5);
		roof.x += mod(floor(roof.y), 2.0) * 0.5;
		vec2 f = fract(roof), fw = max(px * vec2(3.2, 4.5), vec2(0.001));
		float joints = 1.0 - band(f.x, 0.018, 0.982, fw.x) * band(f.y, 0.035, 0.965, fw.y);
		float near_k = 1.0 - smoothstep(0.1, 0.45, max(fw.x, fw.y));
		float grime = smoothstep(0.5, 0.85, noise2(xz * 0.16 + 9.0));
		ALBEDO = base * (1.0 + d3 - (joints - 0.06) * near_k * 0.12 - grime * 0.08);
	} else if (id == M_FACADE && vertical > 0.8) {
		// Enduit, briques ou pierre selon la graine propre au bâtiment ; coulures sous les appuis, soubassement.
		float typ = floor((facade_seed - 519.0) / 100.0);
		vec2 ms = typ < 0.5 ? vec2(1.1, 2.0) : vec2(2.7, 4.5);
		vec2 masonry = UV * ms;
		masonry.x += mod(floor(masonry.y), 2.0) * 0.5;
		vec2 f = fract(masonry), fw = max(fw_uv * ms, vec2(0.001));
		float mortar = 1.0 - band(f.x, 0.02, 0.98, fw.x) * band(f.y, 0.04, 0.96, fw.y);
		float near_k = 1.0 - smoothstep(0.12, 0.45, max(fw.x, fw.y));
		float mort_k = typ < 0.5 ? 0.07 : (typ < 1.5 ? 0.16 : 0.02);
		float streak = smoothstep(0.55, 0.9, noise2(vec2(UV.x * 1.3, UV.y * 0.09 + facade_seed))) * (1.0 - smoothstep(0.3, 0.8, px * 1.3));
		float socle = 1.0 - smoothstep(0.55, 0.8, UV.y);
		if (UV.y < 0.0) { mortar = 0.08; streak = 0.0; socle = 0.0; }   // murs sans UV (aveugles)
		base *= 1.0 + d3 - (mortar - 0.08) * near_k * mort_k - streak * 0.07 - socle * 0.2;
		ALBEDO = base;
	} else if (id == M_PLAIN || id == M_SOLID) {
		float g = d3;
		if (vertical < 0.5 && v_h < 0.6) {   // sol non classé : taches, terre/gravier en macro
			g = oct3(xz, vec3(0.14, 0.07, 0.10) * detail, px);
			g -= smoothstep(0.7, 0.85, noise2(xz * 0.18 + 1.3)) * 0.08 * (1.0 - smoothstep(0.3, 0.75, px * 0.18));
		}
		ALBEDO = base * (1.0 + g);
	} else {
		ALBEDO = base * (1.0 + d3 * 0.6);
	}
	// Sol végétal lissé : masque de tuile filtré + contour irrégulier (bruit métrique), sur le sol nu seulement.
	if (veg_inv_size > 0.0 && vertical < 0.5 && v_h < 0.6 && (id == M_PLAIN || id == M_VEG)) {
		float m = texture(veg_mask, v_local * veg_inv_size).r;
		float edge = (noise2(xz * 0.6) - 0.5) * 0.25 + (noise2(xz * 0.13) - 0.5) * 0.2;
		float k = smoothstep(0.38, 0.62, m + edge);
		vec3 grass = veg_color * (1.0 + oct3(xz, vec3(0.28, 0.16, 0.14) * detail, px));
		ALBEDO = mix(ALBEDO, grass, k);
	}
	if (id == M_LIGHT) {  // lampadaires, feux : lumineux, surtout la nuit
		EMISSION = base * (0.25 + 3.2 * night);
	}
	if (id == M_SHOP) {  // vitrines de rez-de-chaussée : reflet le jour, éclairées le soir
		float sky = smoothstep(0.0, 3.4, UV.y >= 0.0 ? UV.y : 1.7);
		ALBEDO = mix(base * 0.6 + vec3(0.05, 0.08, 0.12) * (0.5 + sky), base * 0.3, night);
		EMISSION = vec3(1.0, 0.72, 0.4) * 1.6 * night;
	}
	if (UV.y > 1.0 && id == M_FACADE) {  // murs (hors rez-de-chaussée bas) des bâtiments à fenêtres
		float variant = fract(facade_seed * 0.6180339);
		float bay = mix(2.4, 4.0, variant);
		vec2 cell = vec2(UV.x / bay, (UV.y - 0.4) / floor_h);
		vec2 f = fract(cell);
		vec2 fw = max(fw_uv / vec2(bay, floor_h), vec2(1e-4));
		float detail_k = 1.0 - smoothstep(0.12, 0.3, max(fw.x, fw.y)); // estompe au-delà de ~5 px par cellule
		float width_ = mix(0.17, 0.29, variant);
		float win = band(f.x, 0.5 - width_, 0.5 + width_, fw.x) * band(f.y, 0.24, 0.80, fw.y);
		float frame = band(f.x, 0.26, 0.74, fw.x) * band(f.y, 0.26, 0.84, fw.y) - win;
		float sill = band(f.x, 0.25, 0.75, fw.x) * band(f.y, 0.22, 0.28, fw.y);
		float course = band(f.y, 0.0, 0.035, fw.y);           // bandeau d'étage
		float on = step(0.55, hash(floor(cell) + vec2(facade_seed * 0.097, 13.0)));
		float lvl = mix(0.45, 1.0, hash(floor(cell) + vec2(2.1, facade_seed * 0.013)));   // intensités variées
		float warm = hash(floor(cell) + vec2(5.3, facade_seed * 0.031));
		vec3 glass = mix(to_linear(window_day) * mix(0.8, 1.15, f.y), to_linear(window_day) * 0.18, night);
		vec3 lit_col = window_night * mix(vec3(1.0), vec3(1.0, 0.92, 1.12), step(0.7, warm));
		vec3 near_col = ALBEDO;
		near_col = mix(near_col, ALBEDO * 1.12, clamp(frame + sill, 0.0, 1.0) * 0.8);
		near_col = mix(near_col, ALBEDO * 0.8, course * 0.6);
		float mullion = band(f.x, 0.49, 0.51, fw.x) * win;
		float shutter = (band(f.x, 0.12, 0.24, fw.x) + band(f.x, 0.76, 0.88, fw.x)) * band(f.y, 0.25, 0.8, fw.y) * step(variant, 0.36);
		near_col = mix(near_col, base * vec3(0.34, 0.45, 0.41), shutter);
		// rideaux : partie haute de la baie plus claire, variable
		float curtain = step(0.5, hash(floor(cell) + 7.7)) * smoothstep(0.62, 0.66, f.y);
		near_col = mix(near_col, glass * (0.75 + 0.25 * smoothstep(0.2, 0.8, f.y)) + curtain * 0.05, win);
		near_col = mix(near_col, base * 0.65, mullion);
		ROUGHNESS = mix(0.9, 0.18, win * detail_k);
		SPECULAR = win * detail_k * 0.5;
		vec3 far_col = mix(ALBEDO, glass, 0.2);
		ALBEDO = mix(far_col, near_col, detail_k);
		vec3 em_near = lit_col * on * lvl * win * (1.0 - curtain * 0.5) * night * 1.5;
		vec3 em_far = window_night * 0.45 * 0.2 * 0.75 * night * 1.5;
		EMISSION = mix(em_far, em_near, detail_k);
	}
}

void light() {
	vec3 styled = cel_light(NORMAL, LIGHT, VIEW, LIGHT_COLOR, ATTENUATION, LIGHT_IS_DIRECTIONAL, shade_floor, 1.0, rim_strength);
	vec3 soft = LIGHT_COLOR * max(dot(NORMAL, LIGHT), 0.0) * ATTENUATION / PI;
	DIFFUSE_LIGHT += mix(styled, soft, LIGHT_IS_DIRECTIONAL ? 0.55 : 0.25);
}
