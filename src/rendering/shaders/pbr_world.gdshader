// Décor (bâtiments, sol, voies, routes) en PBR : éclairage du moteur (pbr_common.gdshaderinc), facettes plates,
// rugosité / métal / spéculaire par identifiant de matériau (tableaux `mat_*`, alimentés par PbrMaterials depuis
// data/materials/world.json).
// Identifiant de matériau : UV2.x (partie entière ; partie fractionnaire × 1024 = graine de façade), hauteur
// au-dessus du terrain : UV2.y (CityScene._Arrays.mesh, LineView._add_geo). Sans UV2 (maillages hérités), repli
// sur COLOR.a : < 0.25 lumineux, 0.28 enrobé, 0.29 dallage, 0.30 sol végétal, 0.35 uni/toit, 0.42-0.48 vitrines,
// 0.5-0.9 façade (graine), 0.365-0.375 métal (rails, aiguilles), sinon uni.
// Détail procédural stable : bruit métrique triplanaire à 3 octaves (≈ 8 m, 1 m, 10 cm), chaque octave fondue vers
// sa moyenne selon l'empreinte du pixel (dérivées calculées une seule fois : ni aplat de près, ni moiré au loin),
// masques d'usure (taches, reprises d'enrobé, coulures et soubassements, mousse des toits), sol végétal lissé
// (masque par tuile filtré bilinéairement). Couleurs : calculs en teintes d'affichage, conversion unique en fin de
// fragment() (pbr_albedo : identité en Compatibility, sRGB → linéaire en Forward+/Mobile).
shader_type spatial;
render_mode cull_disabled;

#include "res://src/rendering/shaders/pbr_common.gdshaderinc"
#include "res://src/rendering/shaders/pbr_textures.gdshaderinc"

// PBR par identifiant de matériau (index = M_*), posés par PbrMaterials.apply_world depuis data/materials/*.json
// (champ world_id) ; Godot n'accepte pas de valeur par défaut sur un tableau d'uniformes.
uniform float mat_roughness[16];
uniform float mat_metallic[16];
uniform float mat_specular[16];
// Textures réelles (P1, pbr_textures.gdshaderinc) : couche de la bibliothèque par identifiant de matériau (-1 = repli
// procédural) et, pour les façades, par type d'appareil (CityScene._wall_code : 0 enduit … 9 mur-rideau).
uniform int mat_layer[16];
uniform int facade_layer[10];
uniform vec3 window_day = vec3(0.24, 0.30, 0.36);      // teintes d'affichage (pas de source_color : conversion unique)
uniform vec3 window_night = vec3(1.0, 0.78, 0.45);
uniform float floor_h = 3.0;
uniform float bay_w = 3.2;
uniform float color_gamma = 1.0;      // 1.0 : une seule chaîne de couleur (pbr_common)
uniform float saturation = 1.0;
uniform float detail = 1.0;           // amplitude globale du détail procédural
// Mobilier en instances (StreetProps) : les sommets de couleur sentinelle magenta prennent INSTANCE_CUSTOM.rgb.
uniform bool instance_tint = false;
// Les palettes (city_styles.json, toits issus de l'orthophoto) sont des teintes APPARENTES (mesurées éclairées,
// comme les livrées des rames) : soleil + ciel ≈ 1,27 sur une face au soleil, d'où l'albédo = teinte × 0,79.
uniform float albedo_scale = 0.79;
// Masque de végétation au sol (tuile de décor) : R = part végétale, filtré bilinéairement.
uniform sampler2D veg_mask : filter_linear, repeat_disable, hint_default_black;
uniform float veg_inv_size = 0.0;     // 1 / taille de tuile (m) ; 0 = pas de masque
uniform vec3 veg_color = vec3(0.34, 0.39, 0.23);   // albédo (teinte apparente ≈ #6c7c4a)
// Occupation du sol réelle (TerrainView.land_image, tools/import/landcover.py) : RGB = teinte apparente de la classe
// (cellules de 25 m, une cellule de bord), A = culture à sillons. Sol nu seulement (matériau GROUND).
uniform sampler2D land_tint : filter_linear, repeat_disable, hint_default_white;
uniform float land_on = 0.0;
uniform float land_cell = 25.0;
uniform float land_px = 18.0;

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
const float M_METAL = 9.0;
// P1 : plateforme et voirie (alpha des couleurs de sommet, CityScene._Arrays.mat_id)
const float M_CONCRETE = 10.0;   // dalle béton de plateforme (0.31)
const float M_BALLAST = 11.0;    // ballast (0.32)
const float M_SETTS = 12.0;      // pavés granit (0.33)
const float M_GRANITE = 13.0;    // bordures, trottoirs granit (0.39)
const float M_FORMED = 14.0;     // béton banché des trémies, soutènements (0.40)
const float M_PAINT = 15.0;      // métal peint (mobilier, garde-corps) (0.41)

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
	if (a > 0.305 && a < 0.315) return M_CONCRETE;
	if (a > 0.315 && a < 0.325) return M_BALLAST;
	if (a > 0.325 && a < 0.335) return M_SETTS;
	if (a > 0.385 && a < 0.395) return M_GRANITE;
	if (a > 0.395 && a < 0.405) return M_FORMED;
	if (a > 0.405 && a < 0.415) return M_PAINT;
	if (a > 0.34 && a < 0.36) return M_SOLID;
	if (a > 0.365 && a < 0.375) return M_METAL;
	if (a > 0.42 && a < 0.48) return M_SHOP;
	if (a > 0.5 && a < 0.999) return M_FACADE;
	return M_PLAIN;
}

void vertex() {
	if (instance_tint && COLOR.r > 0.99 && COLOR.g < 0.01 && COLOR.b > 0.99) COLOR.rgb = INSTANCE_CUSTOM.rgb;
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
	POSITION = pbr_layer_clip(VERTEX, UV2.y, MODELVIEW_MATRIX, PROJECTION_MATRIX);
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
	int mi = clamp(int(id), 0, 15);
	ROUGHNESS = mat_roughness[mi];
	METALLIC = mat_metallic[mi];
	SPECULAR = mat_specular[mi];
	// Textures réelles (P1) : couche par matériau, repère de projection et gradients hors branches.
	vec3 tT, tB;
	vec2 tuv = pbr_planar(v_world, wn, tT, tB);
	vec2 tgx = dFdx(tuv), tgy = dFdy(tuv);
	int layer = mat_layer[mi];
	if (id == M_FACADE) layer = vertical > 0.8 ? facade_layer[clamp(int(floor((facade_seed - 500.0) / 50.0)), 0, 9)] : mat_layer[5];
	if ((id == M_SOLID && vertical >= 0.8) || (id == M_PLAIN && !(vertical < 0.5 && v_h < 0.6 && facade_seed < 0.5))) layer = -1;   // sol nu seulement (pas les marquages)
	bool tex = pbr_tex_quality > 0 && layer >= 0;
	vec3 t_ratio = vec3(1.0), t_nts = vec3(0.0, 0.0, 1.0), t_orm = vec3(1.0);
	if (tex) {
		pbr_tex_sample(layer, tuv, tgx, tgy, t_ratio, t_nts, t_orm);
		vec4 li = pbr_layer_info[layer];
		ROUGHNESS = clamp(ROUGHNESS + (t_orm.g - li.y), 0.04, 1.0);
		AO = clamp(t_orm.r / max(li.z, 0.05), 0.0, 1.0);
	}
	float tk = tex ? 0.0 : 1.0;      // micro-détail procédural seulement en repli (la texture le remplace)
	// Détail macro/méso/micro commun (aucun aplat de près ni de loin).
	float d3 = tri3(v_world, wn, vec3(0.10, 0.06, 0.05) * detail, px);
	vec3 land_rgb = vec3(-1.0);
	if (land_on > 0.5) {
		// contour irrégulier (≈ 20 m puis 5 m) : pas de losanges du filtrage bilinéaire ni de bords de cellule
		vec2 jit = vec2(noise2(xz * 0.045), noise2(xz * 0.045 + 7.3)) - 0.5;
		jit += (vec2(noise2(xz * 0.21 + 3.1), noise2(xz * 0.21 + 9.7)) - 0.5) * 0.4;
		vec4 lt = texture(land_tint, (v_local / land_cell + 1.0 + jit * 0.9) / land_px);
		land_rgb = to_linear(lt.rgb) * albedo_scale;
		if (id == M_PLAIN && facade_seed < 0.5 && vertical < 0.5 && v_h < 0.6) {
			base = to_linear(lt.rgb) * albedo_scale;
			// sillons des cultures : orientation par parcelle (≈ 160 m), pas de 3 m, fondus au loin
			float ang = hash(floor(xz / 160.0) + 0.5) * 3.14159;
			float f = dot(xz, vec2(cos(ang), sin(ang))) / 3.0;
			float fade = 1.0 - smoothstep(0.25, 0.8, px / 3.0);
			base *= 1.0 - lt.a * 0.11 * band(fract(f), 0.05, 0.5, max(px / 3.0, 0.002)) * fade;
		}
	}
	if (id == M_ASPHALT) {
		float agg = oct3(xz, vec3(0.10, 0.07 * tk, 0.16 * tk) * detail, px);
		float stain = smoothstep(0.66, 0.80, noise2(xz * 0.21 + 3.7)) * (1.0 - smoothstep(0.3, 0.75, px * 0.21));
		float repair = smoothstep(0.70, 0.76, noise2(floor(xz * 0.25) * 0.37 + 11.0)) * smoothstep(0.62, 0.70, noise2(xz * 0.045));
		ALBEDO = base * (1.0 + agg - stain * 0.14 - repair * 0.10);
	} else if (id == M_PAVING) {
		vec2 tile = xz * vec2(1.6, 2.4);
		tile.x += step(0.5, fract(floor(tile.y) * 0.5)) * 0.5;
		vec2 f = fract(tile), fw = max(px * vec2(1.6, 2.4), vec2(0.001));
		float joint = 1.0 - band(f.x, 0.018, 0.982, fw.x) * band(f.y, 0.025, 0.975, fw.y);
		float near_k = 1.0 - smoothstep(0.12, 0.45, max(fw.x, fw.y));   // fondu des carreaux vers leur teinte moyenne
		float tiles = mix(0.0, (0.12 * hash(floor(tile)) - 0.06) - 0.25 * joint + 0.012, near_k) * tk;
		ALBEDO = base * (0.99 + tiles + oct3(xz, vec3(0.09, 0.04, 0.0) * detail, px));
	} else if (id == M_VEG) {
		float n = oct3(xz, vec3(0.30, 0.16 * tk, 0.14 * tk) * detail, px);
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
		ALBEDO = base * (1.0 + d3 - (joints - 0.06) * near_k * 0.12 * tk - grime * 0.08);
	} else if (id == M_FACADE && vertical > 0.8) {
		// Appareil selon le type de façade (graine = 500 + type × 50 + variante, CityScene._wall_code) :
		// 0 enduit, 1 brique, 2 pierre de taille, 3 andésite, 4 tuffeau, 5 enduit du Sud, 6 béton (Perret),
		// 7 grand ensemble (panneaux), 8 brique et pierre, 9 mur-rideau. Coulures sous les appuis, soubassement.
		float typ = floor((facade_seed - 500.0) / 50.0);
		float bay0 = mix(2.4, 4.0, fract(facade_seed * 0.6180339));
		vec2 ms = vec2(1.1, 2.0); float mort_k = 0.03; float stag = 0.5;
		if (typ == 1.0 || typ == 8.0) { ms = vec2(3.6, 7.5); mort_k = -0.16; }
		else if (typ == 2.0) { ms = vec2(1.45, 2.4); mort_k = 0.06; }
		else if (typ == 3.0) { ms = vec2(1.6, 2.5); mort_k = -0.12; }
		else if (typ == 4.0) { ms = vec2(1.25, 2.2); mort_k = 0.05; }
		else if (typ == 6.0) { ms = vec2(1.0 / bay0, 1.0); mort_k = 0.09; stag = 0.0; }
		else if (typ == 7.0) { ms = vec2(0.5 / bay0, 1.0 / 2.75); mort_k = 0.10; stag = 0.0; }
		else if (typ == 9.0) { ms = vec2(1.0 / bay0, 1.0 / 3.6); mort_k = 0.2; stag = 0.0; }
		vec2 masonry = UV * ms;
		masonry.x += mod(floor(masonry.y), 2.0) * stag;
		vec2 f = fract(masonry), fw = max(fw_uv * ms, vec2(0.001));
		float mortar = 1.0 - band(f.x, 0.02, 0.98, fw.x) * band(f.y, 0.04, 0.96, fw.y);
		float near_k = 1.0 - smoothstep(0.12, 0.45, max(fw.x, fw.y));
		if (typ == 0.0 || typ == 5.0 || tex) mortar = 0.08;    // enduits : pas de joints ; texture : joints réels
		float streak = smoothstep(0.55, 0.9, noise2(vec2(UV.x * 1.3, UV.y * 0.09 + facade_seed))) * (1.0 - smoothstep(0.3, 0.8, px * 1.3));
		float socle = 1.0 - smoothstep(0.55, 0.8, UV.y);
		if (UV.y < 0.0) { mortar = 0.08; streak = 0.0; socle = 0.0; }   // murs sans UV (aveugles)
		float k_streak = typ == 6.0 || typ == 7.0 ? 0.13 : 0.07;
		// brique et pierre : chaînages et bandeaux d'étage en pierre claire
		float stone_band = 0.0;
		if (typ == 8.0 && UV.y > 0.0) {
			float fy = fract((UV.y - 0.4) / 3.0);
			stone_band = band(fy, 0.0, 0.09, fw_uv.y / 3.0) + band(fract(UV.x / (bay0 * 2.0)), 0.0, 0.07, fw_uv.x / (bay0 * 2.0));
			stone_band = clamp(stone_band, 0.0, 1.0);
		}
		base *= 1.0 + d3 - (mortar - 0.08) * near_k * mort_k - streak * k_streak - socle * 0.2;
		base = mix(base, vec3(0.62, 0.58, 0.52), stone_band * 0.85);
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
	ALBEDO *= t_ratio;
	vec3 flat_n = NORMAL;
	if (tex) NORMAL = pbr_tex_normal(t_nts, tT, tB, wn, VIEW_MATRIX);
	// Sol végétal lissé : masque de tuile filtré + contour irrégulier (bruit métrique), sur le sol nu seulement.
	if (veg_inv_size > 0.0 && vertical < 0.5 && v_h < 0.6 && (id == M_PLAIN || id == M_VEG)) {
		float m = texture(veg_mask, v_local * veg_inv_size).r;
		float edge = (noise2(xz * 0.6) - 0.5) * 0.25 + (noise2(xz * 0.13) - 0.5) * 0.2;
		float k = smoothstep(0.38, 0.62, m + edge);
		// pelouse de l'orthophoto teintée par l'occupation du sol (sous-bois sombre, prairie, culture) : pas de
		// rupture de teinte entre tuiles avec et sans masque
		vec3 vc = land_rgb.r >= 0.0 && land_rgb.g > land_rgb.r ? mix(veg_color, land_rgb, 0.85) : veg_color;
		vec3 grass = vc * (1.0 + oct3(xz, vec3(0.28, 0.16, 0.14) * detail, px));
		ALBEDO = mix(ALBEDO, grass, k);
	}
	if (id == M_LIGHT) {  // lampadaires, feux : lumineux, surtout la nuit
		EMISSION = base * (0.25 + 3.2 * night);
	}
	if (id == M_SHOP) {  // rez-de-chaussée commercial : piliers, vitrines, bandeau d'enseigne, allège ; éclairé le soir
		vec2 fws = max(fw_uv, vec2(0.001));
		float y = UV.y >= 0.0 ? UV.y : 1.7;
		float shop_w = mix(4.2, 6.5, fract(facade_seed * 0.371));
		float cx = UV.x / shop_w; float fx = fract(cx); float cell = floor(cx);
		float h1 = hash(vec2(cell, facade_seed * 0.11));
		float pier = 1.0 - band(fx, 0.07, 0.93, fws.x / shop_w);
		float glass = band(y, 0.45, 2.75, fws.y) * (1.0 - pier) * (1.0 - band(fx, 0.44, 0.56, fws.x / shop_w) * step(0.6, h1));
		float fascia = band(y, 2.82, 3.3, fws.y) * (1.0 - pier);
		float far_k = 1.0 - smoothstep(0.05, 0.25, fws.x / shop_w);
		vec3 sign_col = vec3(0.13, 0.17, 0.22);   // enseignes génériques (sans marque) : sombre, bordeaux, vert, bleu, crème
		if (h1 > 0.2) sign_col = vec3(0.32, 0.08, 0.08);
		if (h1 > 0.4) sign_col = vec3(0.10, 0.22, 0.15);
		if (h1 > 0.6) sign_col = vec3(0.12, 0.18, 0.36);
		if (h1 > 0.8) sign_col = vec3(0.62, 0.56, 0.44);
		vec3 day_glass = vec3(0.05, 0.07, 0.09) + vec3(0.06, 0.08, 0.10) * smoothstep(0.4, 2.7, y);
		float open_ = step(0.3, hash(vec2(cell, 3.1 + facade_seed)));
		vec3 night_glass = vec3(0.10, 0.08, 0.06);
		vec3 gl = mix(day_glass, night_glass, night);
		vec3 near_col = mix(base * 0.9, gl, glass);
		near_col = mix(near_col, sign_col, fascia);
		ALBEDO = mix(mix(base, gl, 0.55), near_col, far_k);
		vec3 lit = mix(vec3(1.0, 0.74, 0.45), vec3(0.85, 0.9, 1.0), step(0.75, h1)) * mix(0.9, 1.9, hash(vec2(cell, 7.7)));
		EMISSION = (lit * glass * open_ * far_k + lit * 0.45 * (1.0 - far_k) + sign_col * fascia * 0.8 * far_k) * night;
	}
	if (UV.y > 1.0 && id == M_FACADE) {  // murs (hors rez-de-chaussée bas) des bâtiments à fenêtres
		float typ = floor((facade_seed - 500.0) / 50.0);
		float variant = fract(facade_seed * 0.6180339);
		float bay = mix(2.4, 4.0, variant);
		// proportions des baies par type : demi-largeur, appui, linteau (fraction d'étage), hauteur d'étage
		float fh = floor_h; float width_ = mix(0.17, 0.29, variant); float wy0 = 0.24; float wy1 = 0.80;
		float shut_p = 0.36; float surround = 0.8; float lit_thr = mix(0.45, 0.72, hash(vec2(facade_seed, 1.3)));
		if (typ == 1.0 || typ == 8.0) { width_ = mix(0.15, 0.2, variant); wy0 = 0.2; wy1 = 0.8; shut_p = 0.0; surround = 1.6; }
		else if (typ == 2.0 || typ == 4.0) { fh = 3.3; width_ = mix(0.17, 0.21, variant); wy0 = 0.12; wy1 = 0.84; shut_p = typ == 4.0 ? 0.25 : 0.0; surround = 1.2; }
		else if (typ == 3.0) { width_ = 0.18; wy0 = 0.16; wy1 = 0.82; shut_p = 0.2; surround = 1.4; }
		else if (typ == 5.0) { width_ = mix(0.15, 0.2, variant); wy0 = 0.18; wy1 = 0.8; shut_p = 1.0; surround = 0.5; }
		else if (typ == 6.0) { width_ = 0.2; wy0 = 0.08; wy1 = 0.84; shut_p = 0.0; surround = 0.4; }
		else if (typ == 7.0) { fh = 2.75; width_ = mix(0.3, 0.4, variant); wy0 = 0.3; wy1 = 0.82; shut_p = 0.0; surround = 0.2; }
		else if (typ == 9.0) { fh = 3.6; width_ = 0.47; wy0 = 0.05; wy1 = 0.95; shut_p = 0.0; surround = 0.0; lit_thr = 0.8; }
		vec2 cell = vec2(UV.x / bay, (UV.y - 0.4) / fh);
		vec2 f = fract(cell);
		vec2 fw = max(fw_uv / vec2(bay, fh), vec2(1e-4));
		float detail_k = 1.0 - smoothstep(0.12, 0.3, max(fw.x, fw.y)); // estompe au-delà de ~5 px par cellule
		float win = band(f.x, 0.5 - width_, 0.5 + width_, fw.x) * band(f.y, wy0, wy1, fw.y);
		// encadrement (pierre ou enduit plus clair), appui, linteau
		float frame = band(f.x, 0.5 - width_ - 0.06, 0.5 + width_ + 0.06, fw.x) * band(f.y, wy0 - 0.03, wy1 + 0.06, fw.y) - win;
		float sill = band(f.x, 0.5 - width_ - 0.08, 0.5 + width_ + 0.08, fw.x) * band(f.y, wy0 - 0.05, wy0, fw.y);
		float course = band(f.y, 0.0, 0.035, fw.y);           // bandeau d'étage
		// éclairage nocturne cohérent : par logement (2 ou 3 baies d'un même étage), part allumée propre au bâtiment
		float apt = floor(cell.x / (2.0 + step(0.5, variant)));
		float on = step(lit_thr, hash(vec2(apt, floor(cell.y)) + vec2(facade_seed * 0.097, 13.0)));
		float lvl = mix(0.55, 1.0, hash(vec2(apt, floor(cell.y)) + vec2(2.1, facade_seed * 0.013)));
		float warm = hash(vec2(apt, floor(cell.y)) + vec2(5.3, facade_seed * 0.031));
		vec3 glass = mix(to_linear(window_day) * mix(0.8, 1.15, f.y), to_linear(window_day) * 0.18, night);
		if (typ == 9.0) glass = mix(vec3(0.20, 0.27, 0.32) * mix(0.85, 1.2, f.y), vec3(0.03, 0.04, 0.05), night);
		vec3 lit_col = window_night * mix(vec3(1.0), vec3(0.86, 0.92, 1.12), step(0.72, warm));
		vec3 near_col = ALBEDO;
		vec3 surround_col = (typ == 1.0 || typ == 8.0) ? vec3(0.6, 0.57, 0.52) : ALBEDO * 1.12;
		near_col = mix(near_col, surround_col, clamp((frame + sill) * surround, 0.0, 1.0) * 0.8);
		near_col = mix(near_col, ALBEDO * 0.8, course * 0.6);
		float mullion = band(f.x, 0.49, 0.51, fw.x) * win;
		float shutter = (band(f.x, 0.5 - width_ - 0.13, 0.5 - width_ - 0.01, fw.x) + band(f.x, 0.5 + width_ + 0.01, 0.5 + width_ + 0.13, fw.x))
			* band(f.y, wy0, wy1, fw.y) * step(fract(variant * 7.31), shut_p);
		vec3 shut_col = vec3(0.30, 0.40, 0.36);
		float sv = fract(facade_seed * 0.213);
		if (sv > 0.4) shut_col = vec3(0.32, 0.38, 0.46);
		if (sv > 0.7) shut_col = vec3(0.45, 0.33, 0.24);
		if (typ == 4.0 || typ == 0.0) shut_col = mix(shut_col, vec3(0.75, 0.74, 0.70), step(0.5, sv));
		near_col = mix(near_col, shut_col, shutter);
		// rideaux : partie haute de la baie plus claire, variable
		float curtain = step(0.5, hash(floor(cell) + 7.7)) * smoothstep(0.62, 0.66, f.y);
		near_col = mix(near_col, glass * (0.75 + 0.25 * smoothstep(0.2, 0.8, f.y)) + curtain * 0.05, win);
		near_col = mix(near_col, base * 0.65, mullion);
		ROUGHNESS = mix(ROUGHNESS, 0.08, win * detail_k);
		NORMAL = normalize(mix(NORMAL, flat_n, clamp(win * detail_k, 0.0, 1.0)));
		AO = mix(AO, 1.0, win * detail_k);
		SPECULAR = mix(SPECULAR, typ == 9.0 ? 0.8 : 0.6, win * detail_k);
		float glass_part = clamp(width_ * 2.0 * (wy1 - wy0), 0.05, 0.9);
		vec3 far_col = mix(ALBEDO, glass, glass_part * 0.6);
		ALBEDO = mix(far_col, near_col, detail_k);
		vec3 em_near = lit_col * on * lvl * win * (1.0 - curtain * 0.5) * night * 1.5;
		vec3 em_far = window_night * glass_part * (1.0 - lit_thr) * 0.55 * night * 1.5;
		EMISSION = mix(em_far, em_near, detail_k);
	}
	// chaîne de couleur unique (pbr_common)
	ALBEDO = pbr_albedo(ALBEDO, OUTPUT_IS_SRGB);
	EMISSION = pbr_emission(EMISSION, OUTPUT_IS_SRGB);
}
