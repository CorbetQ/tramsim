// Végétation réaliste (refonte P3, src/rendering/vegetation.gd) : écorce procédurale + cartes de feuillage alpha
// (atlas de rameaux CC0) ou imposteur (silhouette pré-calculée tournée vers la caméra principale).
// Éclairage PBR du moteur (aucun light()) ; feuillage : normales sphériques, translucidité (BACKLIGHT), découpe
// alpha (ALPHA_SCISSOR : identique Forward+/Mobile/Compatibility). Vent léger, frémissement des feuilles,
// variation de teinte et de saison par instance (hachage de la position). Bascule LOD par instance à la distance
// de la caméra PRINCIPALE (MAIN_CAM_INV_VIEW_MATRIX : identique dans les passes d'ombre) :
// maillage si d < lod_near + lod_overlap, imposteur si d ≥ lod_near.
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;

#include "res://src/rendering/shaders/pbr_common.gdshaderinc"

// Atlas en espace d'affichage (sRGB) : converti une seule fois par pbr_albedo, comme les couleurs de sommet.
uniform sampler2D foliage_tex : filter_linear_mipmap_anisotropic, repeat_disable;
uniform bool impostor = false;
uniform float lod_near = 230.0;
uniform float lod_overlap = 6.0;
uniform float wind_strength = 0.14;
uniform float wind_speed = 1.1;
uniform vec2 wind_dir = vec2(0.8, 0.6);
uniform float translucency : hint_range(0.0, 1.0) = 0.5;
uniform float hue_variation : hint_range(0.0, 1.0) = 0.22;
uniform float season : hint_range(0.0, 1.0) = 0.0;   // 0 été ; 1 automne (jaunissement échelonné par instance)
uniform float alpha_cut : hint_range(0.0, 1.0) = 0.42;
uniform float leaf_roughness = 0.72;
uniform float leaf_specular = 0.35;
uniform vec3 albedo_mul = vec3(0.74, 0.76, 0.64);   // calage sur la canopée des orthophotos IGN (comme Materials.foliage)

varying float v_var;
varying float v_kind;     // 0 écorce, 0,25 écorce desquamée, 1 feuillage
varying vec3 v_obj;

float h11(float p) { return fract(sin(p * 91.345) * 47453.5453); }
float h21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1, 0)), f.x), mix(h21(i + vec2(0, 1)), h21(i + vec2(1, 1)), f.x), f.y);
}

void vertex() {
	vec3 org = MODEL_MATRIX[3].xyz;
	vec3 cam = MAIN_CAM_INV_VIEW_MATRIX[3].xyz;
	float d = distance(org.xz, cam.xz);
	v_var = h21(org.xz * 0.37);
	v_kind = COLOR.a;
	v_obj = VERTEX;
	bool hide = impostor ? (d < lod_near) : (d > lod_near + lod_overlap);
	if (hide) {
		VERTEX = vec3(0.0);
	} else if (impostor) {
		// quad vertical tourné vers la caméra principale autour de l'axe de l'instance
		float sx = length(MODEL_MATRIX[0].xyz); float sy = length(MODEL_MATRIX[1].xyz);
		vec3 to_cam = cam - org; to_cam.y = 0.0;
		vec3 f = length(to_cam) > 0.01 ? normalize(to_cam) : vec3(0.0, 0.0, 1.0);
		vec3 r = normalize(cross(vec3(0.0, 1.0, 0.0), f));
		vec3 w = org + r * VERTEX.x * sx + vec3(0.0, VERTEX.y * sy, 0.0);
		float sway = wind_strength * 0.5 * sin(TIME * wind_speed + v_var * 6.28) * UV2.x;
		w.xz += wind_dir * sway;
		VERTEX = (inverse(MODEL_MATRIX) * vec4(w, 1.0)).xyz;
		// normale de volume : sphère approchée (bords tournés vers l'extérieur, dessus vers le ciel)
		vec3 nw = normalize(f * 0.75 + vec3(0.0, 0.45, 0.0) + r * (VERTEX.x > 0.0 ? 0.35 : -0.35));
		NORMAL = normalize(transpose(mat3(MODEL_MATRIX)) * nw);
	} else {
		// vent : balancement de l'ensemble (∝ hauteur²) + frémissement des cartes
		float h = UV2.x;
		float t = TIME * wind_speed + v_var * 6.28;
		vec3 sway = vec3(wind_dir.x, 0.0, wind_dir.y) * (sin(t) * 0.6 + sin(t * 2.3 + 1.7) * 0.25) * wind_strength * h * h;
		if (COLOR.a > 0.5) {
			sway += vec3(sin(TIME * 5.3 + UV2.y * 40.0), sin(TIME * 4.1 + UV2.y * 23.0) * 0.6, cos(TIME * 6.1 + UV2.y * 31.0)) * 0.035 * wind_strength / 0.14 * h;
		}
		VERTEX += (inverse(mat3(MODEL_MATRIX)) * sway);
	}
}

void fragment() {
	vec3 col;
	float rough = leaf_roughness;
	if (v_kind < 0.5) {
		// écorce : sillons verticaux (bruit étiré), plaques desquamées du platane
		float n = vnoise(vec2(UV.x * 16.0, UV.y * 1.2)) * 0.55 + vnoise(vec2(UV.x * 40.0, UV.y * 6.0)) * 0.3 + vnoise(UV * vec2(9.0, 3.0)) * 0.15;
		col = COLOR.rgb * (0.5 + 0.75 * n);
		if (v_kind > 0.1) {
			float pl = smoothstep(0.45, 0.55, vnoise(vec2(UV.x * 5.0, UV.y * 2.2) + v_var * 9.0));
			col = mix(col * 0.82, vec3(0.80, 0.78, 0.62), pl * 0.6);
		}
		rough = 0.9;
		ALPHA = 1.0;
		SPECULAR = 0.3;
	} else {
		vec4 t = texture(foliage_tex, UV);
		ALPHA = t.a;
		col = t.rgb * COLOR.rgb;
		// variation par instance : teinte (jaune-vert / bleu-vert) et clarté
		float k = (v_var - 0.5) * 2.0 * hue_variation;
		col *= vec3(1.0 + k * 0.35, 1.0 + k * 0.12, 1.0 - k * 0.45) * (1.0 - abs(k) * 0.15);
		// saison : jaunissement échelonné (les instances n'y passent pas toutes ensemble)
		float aut = clamp(season * 1.6 - v_var * 0.6, 0.0, 1.0);
		float lum = dot(col, vec3(0.3, 0.59, 0.11));
		col = mix(col, vec3(lum * 1.55, lum * 1.05, lum * 0.35), aut);
		col *= albedo_mul;
		if (impostor) col *= 0.78;   // silhouette pré-éclairée : pas de double éclaircissement
		if (!FRONT_FACING && !impostor) NORMAL = -NORMAL;   // normales sphériques : pas de retournement face arrière
		BACKLIGHT = pbr_albedo(col, OUTPUT_IS_SRGB) * translucency;
		SPECULAR = leaf_specular;
	}
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;
	ALBEDO = pbr_albedo(col, OUTPUT_IS_SRGB);
	ROUGHNESS = rough;
	METALLIC = 0.0;
}
