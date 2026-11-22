// Surface PBR d'un matériau de la bibliothèque (refonte P1) pour les maillages dédiés (stations, trémies, monuments,
// mobilier : scènes de l'agent modélisateur) : PbrMaterials.surface(id). Textures réelles par couche
// (pbr_textures.gdshaderinc), projection métrique par facette en espace monde (aucune UV1 requise : l'UV2 reste
// libre pour les lightmaps LightmapGI), teinte = albedo_tint (fiche) × couleur de sommet (option) × rapport de texture.
// Repli (pas de texture, pbr_tex_quality = 0) : teinte unie + scalaires de la fiche.
shader_type spatial;
render_mode cull_back;

#include "res://src/rendering/shaders/pbr_common.gdshaderinc"
#include "res://src/rendering/shaders/pbr_textures.gdshaderinc"

uniform vec3 albedo_tint = vec3(0.6);        // teinte d'affichage (sRGB), convertie une seule fois en fin de fragment
uniform bool use_vertex_color = false;
uniform int layer = -1;
uniform float surface_roughness : hint_range(0.0, 1.0) = 0.8;
uniform float surface_metallic : hint_range(0.0, 1.0) = 0.0;
uniform float surface_specular : hint_range(0.0, 1.0) = 0.5;
uniform float uv_scale_mul = 1.0;            // > 1 : motif agrandi
uniform bool local_space = false;            // objets mobiles : projection dans le repère de l'objet
uniform float macro_variation = 0.08;        // variation de teinte basse fréquence (anti-répétition, ≈ 9 m)

varying vec3 v_pos;
varying vec3 v_nrm;

void vertex() {
	v_pos = local_space ? VERTEX : (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_nrm = local_space ? NORMAL : normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 wn = normalize(v_nrm);
	vec3 T, B;
	vec2 uvm = pbr_planar(v_pos, wn, T, B) / uv_scale_mul;
	vec2 gx = dFdx(uvm), gy = dFdy(uvm);
	vec3 base = albedo_tint * (use_vertex_color ? COLOR.rgb : vec3(1.0));
	float macro = (pbr_tnoise(v_pos.xz * 0.11 + v_pos.y * 0.07) - 0.5) * 2.0 * macro_variation;
	ROUGHNESS = surface_roughness;
	METALLIC = surface_metallic;
	SPECULAR = surface_specular;
	vec3 ratio = vec3(1.0);
	if (pbr_tex_quality > 0 && layer >= 0) {
		vec3 nts, orm;
		pbr_tex_sample(layer, uvm, gx, gy, ratio, nts, orm);
		vec4 li = pbr_layer_info[layer];
		ROUGHNESS = clamp(surface_roughness + (orm.g - li.y), 0.04, 1.0);
		AO = clamp(orm.r / max(li.z, 0.05), 0.0, 1.0);
		vec3 n = pbr_tex_normal(nts, T, B, wn, VIEW_MATRIX);
		NORMAL = local_space ? normalize((VIEW_MATRIX * MODEL_MATRIX * vec4(T * nts.x + B * nts.y + wn * nts.z, 0.0)).xyz) : n;
	}
	ALBEDO = pbr_albedo(base * ratio * (1.0 + macro), OUTPUT_IS_SRGB);
}
