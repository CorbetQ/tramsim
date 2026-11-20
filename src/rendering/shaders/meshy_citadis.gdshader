shader_type spatial;
render_mode cull_disabled;
#include "res://src/rendering/shaders/cel.gdshaderinc"
uniform sampler2D base_texture : source_color, hint_default_white, filter_linear_mipmap_anisotropic;
uniform vec4 base_color : source_color = vec4(1.0);
uniform int seat_palette = 0;
void fragment() {
	vec3 color = texture(base_texture,UV).rgb * base_color.rgb;
	if (seat_palette == 1 && color.g > color.b * 1.8 && color.g > color.r * 1.05) {
		color = vec3(0.52,0.65,0.16) * clamp(color.g,0.65,1.0);
	} else if (seat_palette == 2 && min(color.r,min(color.g,color.b)) > 0.48) {
		color *= vec3(0.86,0.77,0.61);
	} else if (seat_palette > 0) {
		color *= 0.85;
	}
	ALBEDO = color;
	ROUGHNESS = 0.58;
}
void light() {
	DIFFUSE_LIGHT += cel_light(NORMAL,LIGHT,VIEW,LIGHT_COLOR,ATTENUATION,
		LIGHT_IS_DIRECTIONAL,0.22,1.0,0.08);
}
