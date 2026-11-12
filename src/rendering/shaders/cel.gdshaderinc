// Éclairage cel shading commun (décor, rames, eau) : paliers nets anti-crénelés, ombre portée intégrée
// aux paliers, ombre teintée froide, liseré de lumière (rim) côté contre-jour, et décalage de profondeur
// des couches de sol (anti z-fighting).
global uniform float night;          // 0 = jour, 1 = nuit (piloté par DayNight)

// Paliers : 3 niveaux (ombre, mi-teinte, plein soleil) ; `floor_` = part du soleil dans l'ombre.
float cel_steps(float lit, float floor_) {
	float e = 0.025;
	float t1 = smoothstep(0.16 - e, 0.16 + e, lit);
	float t2 = smoothstep(0.58 - e, 0.58 + e, lit);
	return mix(floor_, 1.0, t1 * 0.6 + t2 * 0.4);
}

// Teinte froide des ombres (lumière du ciel), plus bleutée la nuit.
vec3 cel_shadow_tint() {
	return mix(vec3(0.66, 0.79, 1.08), vec3(0.7, 0.8, 1.15), night);
}

// Contribution d'une lumière : soleil/lune en paliers, lumières ponctuelles (phares, lampes) en 2 paliers.
vec3 cel_light(vec3 n, vec3 l, vec3 v, vec3 lcol, float atten, bool directional, float floor_, float sun_k, float rim_k) {
	float ndl = dot(n, l);
	float lit = clamp(ndl, 0.0, 1.0) * atten;
	vec3 d;
	if (directional) {
		float s = cel_steps(lit, floor_);
		vec3 tint = mix(cel_shadow_tint(), vec3(1.0), smoothstep(floor_, 1.0, s));
		d = lcol * s * tint * sun_k;
		// liseré : bord de silhouette, renforcé à contre-jour
		float fres = 1.0 - clamp(dot(n, v), 0.0, 1.0);
		float back = 0.45 + 0.55 * clamp(-dot(v, l) * 0.5 + 0.5, 0.0, 1.0);
		d += lcol * rim_k * smoothstep(0.66, 0.74, fres) * back * clamp(ndl + 0.35, 0.0, 1.0) * mix(0.6, 1.0, atten);
	} else {
		d = lcol * (smoothstep(0.02, 0.06, lit) * 0.55 + smoothstep(0.3, 0.36, lit) * 0.45) * min(atten * 2.0, 1.0);
	}
	return d / PI;
}

// Décalage de profondeur des couches de sol (rubans posés à quelques cm) : la surface est rapprochée de la
// caméra en proportion de sa hauteur (≤ 0,36 % de la distance), sans déplacement à l'écran ; nul au-dessus
// de 2,5 m. Désactivé en projection orthogonale (ombres du soleil).
vec4 cel_layer_clip(vec3 vtx, mat4 model, mat4 modelview, mat4 proj) {
	vec4 vp = modelview * vec4(vtx, 1.0);
	if (proj[3][3] < 0.5) {
		float y = (model * vec4(vtx, 1.0)).y;
		float k = 0.03 * clamp(y, 0.0, 0.12) * (1.0 - smoothstep(1.5, 2.5, y));
		vp.xyz *= 1.0 - k;
	}
	return proj * vp;
}
