// Contours encrés en post-traitement (quadrilatère plein écran, compatible renderer Compatibility) :
// détection sur la profondeur linéarisée. Silhouettes = saut de profondeur relatif ; arêtes vives (angles
// des bâtiments, toits) = rupture de pente de 1/z (nul sur un plan, donc pas de bruit sur le sol).
// Estompé avec la distance pour éviter le fourmillement des détails lointains.
shader_type spatial;
render_mode unshaded, depth_test_disabled, depth_draw_never, cull_disabled, blend_mix, fog_disabled, shadows_disabled;

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform vec4 ink : source_color = vec4(0.10, 0.09, 0.12, 1.0);
uniform float strength = 0.62;
uniform float silhouette = 0.035;   // saut relatif de profondeur
uniform float crease = 0.0035;      // rupture de pente relative de 1/z
uniform float fade_start = 90.0;
uniform float fade_end = 420.0;
uniform float thickness = 1.0;      // en pixels

void vertex() {
	POSITION = vec4(VERTEX.xy * 2.0, 0.0, 1.0);
}

float lin(vec2 uv, mat4 inv_proj) {
	float d = textureLod(depth_tex, uv, 0.0).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 ndc = vec3(uv * 2.0 - 1.0, d * 2.0 - 1.0);
#else
	vec3 ndc = vec3(uv * 2.0 - 1.0, d);
#endif
	vec4 v = inv_proj * vec4(ndc, 1.0);
	return -v.z / v.w;
}

void fragment() {
	vec2 px = thickness / VIEWPORT_SIZE;
	float c = lin(SCREEN_UV, INV_PROJECTION_MATRIX);
	float l = lin(SCREEN_UV - vec2(px.x, 0.0), INV_PROJECTION_MATRIX);
	float r = lin(SCREEN_UV + vec2(px.x, 0.0), INV_PROJECTION_MATRIX);
	float u = lin(SCREEN_UV - vec2(0.0, px.y), INV_PROJECTION_MATRIX);
	float d = lin(SCREEN_UV + vec2(0.0, px.y), INV_PROJECTION_MATRIX);
	// silhouette : tracée sur l'objet le plus proche
	float far_n = max(max(l, r), max(u, d));
	float sil = smoothstep(silhouette, silhouette * 2.0, (far_n - c) / c);
	// arête vive : laplacien de 1/z, relatif
	float ic = 1.0 / c;
	float lap = abs(1.0 / l + 1.0 / r - 2.0 * ic) + abs(1.0 / u + 1.0 / d - 2.0 * ic);
	float cr = smoothstep(crease, crease * 2.5, lap / ic) * (1.0 - smoothstep(0.25, 0.5, (far_n - c) / c));
	float e = max(sil, cr * 0.75);
	float fade = 1.0 - smoothstep(fade_start, fade_end, c);
	ALBEDO = ink.rgb;
	ALPHA = clamp(e * fade * strength, 0.0, 1.0);
}
