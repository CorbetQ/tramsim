shader_type spatial;
render_mode cull_disabled;
#include "res://src/rendering/shaders/pbr_common.gdshaderinc"
varying vec3 world_pos;
varying vec4 base_color;
void vertex() { world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; base_color = COLOR; POSITION = pbr_layer_clip(VERTEX, UV2.y, MODELVIEW_MATRIX, PROJECTION_MATRIX); }
void fragment() {
	// Reconstruct a camera-facing flat normal, as the shared city shader does.
	// Polygon triangulators can use either winding; double-sided ground must stay lit.
	NORMAL = normalize(cross(dFdy(VERTEX), dFdx(VERTEX)));
	// Metric paving, antialiased at distance: no stretched bitmap or swimming grain.
	vec2 p = world_pos.xz / vec2(0.6, 0.3);
	p.x += mod(floor(p.y), 2.0) * 0.5;
	vec2 edge = min(fract(p), 1.0 - fract(p));
	vec2 aa = max(fwidth(p), vec2(0.002));
	vec2 joint = 1.0 - smoothstep(vec2(0.008) - aa, vec2(0.008) + aa, edge);
	float visible = 1.0 - smoothstep(0.3, 0.8, max(aa.x, aa.y));
	float mortar = max(joint.x, joint.y) * visible;
	float variation = fract(sin(dot(floor(p), vec2(12.9898, 78.233))) * 43758.5453);
	ALBEDO = base_color.rgb * 0.79 * mix(0.95, 1.035, variation * visible) * (1.0 - mortar * 0.17);
	ROUGHNESS = mix(0.82, 0.95, mortar); SPECULAR = 0.45;
	ALBEDO = pbr_albedo(ALBEDO, OUTPUT_IS_SRGB);
	EMISSION = pbr_emission(EMISSION, OUTPUT_IS_SRGB);
}
