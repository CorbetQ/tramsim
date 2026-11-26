// Commun aux shaders PBR (décor, rames, eau) : paramètre global `night`, chaîne de couleur unique et décalage de
// profondeur des couches de sol (anti z-fighting). L'éclairage est celui du moteur (BRDF PBR Burley/GGX) :
// aucun `light()` personnalisé, aucun palier ni contour (refonte P0, docs/CDC_REFONTE_VISUELLE.md).
global uniform float night;          // 0 = jour, 1 = nuit (piloté par DayNight)

// Chaîne de couleur : les palettes (couleurs de sommet, JSON) sont des teintes sRGB d'affichage. Le renderer
// Compatibility restitue l'albédo tel quel (OUTPUT_IS_SRGB, mesuré : 0,5 → 0,502) ; Forward+ et Mobile travaillent
// en linéaire (0,5 non converti → 0,737) : conversion sRGB → linéaire exacte, une seule fois, en fin de fragment()
// (tous les calculs de teinte restent en espace d'affichage ; aucune uniforme `source_color` sur les teintes).
vec3 pbr_srgb_to_linear(vec3 c) {
	c = max(c, vec3(0.0));
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}
vec3 pbr_albedo(vec3 srgb, bool output_is_srgb) {
	return output_is_srgb ? srgb : pbr_srgb_to_linear(srgb);
}
// Émission : teinte convertie, intensité (> 1 pour le bloom) conservée linéairement.
vec3 pbr_emission(vec3 e, bool output_is_srgb) {
	float k = max(max(e.r, e.g), max(e.b, 1.0));
	return output_is_srgb ? e : pbr_srgb_to_linear(e / k) * k;
}

// Décalage de profondeur des couches de sol (rubans posés à quelques cm) : la surface est rapprochée de la
// caméra en proportion de sa hauteur AU-DESSUS DU TERRAIN `h` (≤ 0,36 % de la distance), sans déplacement à
// l'écran ; nul au-dessus de 2,5 m. `h` vient de l'attribut UV2.y (CityScene._Arrays, LineView._add_geo), donc
// valable à toute altitude (Angers à −17 m, Grenoble, Saint-Étienne…). Désactivé en projection orthogonale.
vec4 pbr_layer_clip(vec3 vtx, float h, mat4 modelview, mat4 proj) {
	vec4 vp = modelview * vec4(vtx, 1.0);
	if (proj[3][3] < 0.5) {
		float k = 0.03 * clamp(h, 0.0, 0.12) * (1.0 - smoothstep(1.5, 2.5, h));
		vp.xyz *= 1.0 - k;
	}
	return proj * vp;
}

// Météo (lot P4 « ambiance ») : `wet` = humidité de la chaussée (WeatherView ← WeatherState.wetness, réduite sous
// abri / en tunnel), `snow` = couverture neigeuse légère (0 hors neige). Appliqués aux surfaces tournées vers le ciel :
// assombrissement par porosité, rugosité basse (reflets du ciel et, en Ultra, SSR), flaques à normale plane (bruit
// métrique stable) avec ronds de pluie, puis neige poudreuse (albédo clair, rugosité haute) sur les faces horizontales.
global uniform float wet;
global uniform float snow;
float pbr_wh(vec2 p) { return fract(sin(dot(p, vec2(41.31, 289.17))) * 43758.5453); }
float pbr_wn(vec2 p) {
	vec2 i = floor(p), f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(pbr_wh(i), pbr_wh(i + vec2(1, 0)), f.x), mix(pbr_wh(i + vec2(0, 1)), pbr_wh(i + vec2(1, 1)), f.x), f.y);
}
// up : composante verticale de la normale monde ; porous : 0 (métal, verre) … 1 (enrobé) ; puddles : 0/1 (flaques
// admises : chaussées, dalles, sols nus) ; xz : position monde ; up_view : normale « ciel » en espace vue.
void pbr_weather(inout vec3 albedo, inout float rough, inout float spec, inout vec3 normal_v, float up, float porous,
		float puddles, vec2 xz, vec3 up_view, float time) {
	float face = smoothstep(0.55, 0.9, up);
	float w = clamp(wet, 0.0, 1.0) * face;
	if (w > 0.001) {
		albedo *= 1.0 - w * porous * 0.38;                         // matériau imbibé : plus sombre
		rough = mix(rough, mix(0.08, 0.28, porous), w * 0.85);      // film d'eau : brillant
		spec = mix(spec, 0.5, w);
		float n = pbr_wn(xz * 0.31) * 0.7 + pbr_wn(xz * 1.9 + 3.7) * 0.3;
		float pud = smoothstep(0.66 - 0.12 * w, 0.72 - 0.12 * w, n) * puddles * smoothstep(0.35, 0.8, w);
		if (pud > 0.001) {
			// ronds de pluie : anneaux qui s'élargissent sur une grille de 0,6 m (phase aléatoire par cellule)
			vec2 g = xz / 0.6, c = floor(g);
			float ph = fract(time * 0.9 + pbr_wh(c) * 7.0);
			float r = length(fract(g) - 0.5 - (vec2(pbr_wh(c + 1.3), pbr_wh(c + 2.7)) - 0.5) * 0.4);
			float ring = smoothstep(0.05, 0.0, abs(r - ph * 0.45)) * (1.0 - ph) * step(0.3, wet);
			albedo *= 1.0 - pud * 0.25;
			rough = mix(rough, 0.02, pud);
			spec = mix(spec, 0.6, pud);
			normal_v = normalize(mix(normal_v, up_view, pud) + vec3(ring * 0.08 * pud));
		}
	}
	float s = clamp(snow, 0.0, 1.0) * face;
	if (s > 0.001) {
		float cov = smoothstep(0.25, 0.75, pbr_wn(xz * 0.8 + 11.0) * 0.6 + pbr_wn(xz * 5.0) * 0.4 + s - 0.5);
		cov *= s;
		albedo = mix(albedo, vec3(0.82, 0.84, 0.88), cov);
		rough = mix(rough, 0.75, cov);
		normal_v = normalize(mix(normal_v, up_view, cov * 0.6));
	}
}
