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
