// Fils de caténaire (refonte P3, ElectrificationView.Wires) : chaque segment est un ruban tourné vers la caméra,
// de largeur réelle (rayon du fil, UV.y) mais jamais plus fin que `min_px` pixels ; au-delà, l'opacité baisse en
// proportion (couverture conservée : pas de scintillement ni de pointillés au loin). NORMAL = tangente du fil,
// UV.x = côté (±1). Éclairage PBR du moteur (métal patiné), aucune écriture de profondeur.
shader_type spatial;
render_mode skip_vertex_transform, cull_disabled, depth_draw_never, blend_mix;

#include "res://src/rendering/shaders/pbr_common.gdshaderinc"

uniform float min_px = 1.15;
uniform float max_alpha = 0.95;
varying float v_cov;

void vertex() {
	vec3 p = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 t = normalize(mat3(MODELVIEW_MATRIX) * NORMAL);
	vec3 side = cross(t, normalize(p));
	side = length(side) > 1e-4 ? normalize(side) : vec3(1.0, 0.0, 0.0);
	float r = UV.y;
	// taille d'un pixel à cette profondeur (perspective) ; orthogonale : constante
	float px = PROJECTION_MATRIX[3][3] < 0.5 ? (-p.z) * 2.0 / (PROJECTION_MATRIX[1][1] * VIEWPORT_SIZE.y) : 2.0 / (PROJECTION_MATRIX[1][1] * VIEWPORT_SIZE.y);
	float w = max(r, 0.5 * min_px * px);
	v_cov = clamp(r / w, 0.12, 1.0);
	VERTEX = p + side * w * UV.x;
	NORMAL = normalize(cross(side, t));
	if (dot(NORMAL, -p) < 0.0) NORMAL = -NORMAL;
	NORMAL = normalize(NORMAL + vec3(0.0, 0.6, 0.0));
}

void fragment() {
	ALBEDO = pbr_albedo(COLOR.rgb, OUTPUT_IS_SRGB);
	ALPHA = max_alpha * v_cov;
	ROUGHNESS = 0.55;
	METALLIC = 0.6;
}
