shader_type spatial;
render_mode cull_disabled;
#include "res://src/rendering/shaders/cel.gdshaderinc"
uniform sampler2D base_texture : source_color, hint_default_white, filter_linear_mipmap_anisotropic;
uniform bool use_texture = false;
uniform bool vertex_palette = false;
uniform vec4 base_color : source_color = vec4(1.0);
uniform int seat_palette = 0;
uniform float surface_roughness = 0.58;
uniform float surface_metallic = 0.0;
uniform vec3 emission_color : source_color = vec3(0.0);
varying float material_tag;
void vertex() { material_tag = UV.x; }
vec3 display_srgb(vec3 c) {
	return mix(c*12.92,1.055*pow(max(c,vec3(0.0)),vec3(1.0/2.4))-0.055,step(vec3(0.0031308),c));
}
void fragment() {
	vec3 color = base_color.rgb;
	// glTF vertex colours are linear. Compatibility expects display albedo;
	// Forward+ keeps linear albedo. Match the engine's source_color handling.
	if (vertex_palette) { color = OUTPUT_IS_SRGB ? display_srgb(COLOR.rgb) : COLOR.rgb; }
	if (use_texture) { color *= texture(base_texture,UV).rgb; }
	if (seat_palette == 1 && color.g > color.b * 1.8 && color.g > color.r * 1.05) {
		color = vec3(0.52,0.65,0.16) * clamp(color.g,0.65,1.0);
	} else if (seat_palette == 2 && min(color.r,min(color.g,color.b)) > 0.48) {
		color *= vec3(0.86,0.77,0.61);
	} else if (seat_palette > 0) {
		color *= 0.85;
	}
	ALBEDO = color * mix(0.8,0.95,night);
	ROUGHNESS = surface_roughness;
	METALLIC = surface_metallic;
	EMISSION = emission_color;
	if (vertex_palette) {
		float tag = UV.x;
		ROUGHNESS = (tag > 0.4 && tag < 0.6) ? 0.18 : 0.58;
		METALLIC = (tag > 0.4 && tag < 0.6) ? 0.35 : ((tag > 0.8 && tag < 0.9) ? 0.7 : 0.0);
		if (tag < 0.2) { EMISSION = color * (0.25+night*0.9); }
	}
}
void light() {
	DIFFUSE_LIGHT += cel_light(NORMAL,LIGHT,VIEW,LIGHT_COLOR,ATTENUATION,
		LIGHT_IS_DIRECTIONAL,0.18,0.88,0.08);
	float gloss = vertex_palette ? ((material_tag>0.4 && material_tag<0.6) ? 0.24 : 0.025) : (1.0-surface_roughness)*0.12;
	vec3 half_vector = normalize(LIGHT+VIEW);
	SPECULAR_LIGHT += LIGHT_COLOR * ATTENUATION * pow(max(dot(NORMAL,half_vector),0.0),48.0) * gloss;
}
