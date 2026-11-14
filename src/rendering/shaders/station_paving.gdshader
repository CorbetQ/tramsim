shader_type spatial;
render_mode cull_disabled;
#include "res://src/rendering/shaders/cel.gdshaderinc"
varying vec3 world_pos;
varying vec4 base_color;
void vertex() { world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; base_color = COLOR; POSITION = cel_layer_clip(VERTEX, UV2.y, MODELVIEW_MATRIX, PROJECTION_MATRIX); }
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
	ROUGHNESS = 0.86; SPECULAR = 0.18;
}

void light() {
	vec3 styled = cel_light(NORMAL, LIGHT, VIEW, LIGHT_COLOR, ATTENUATION, LIGHT_IS_DIRECTIONAL, 0.20, 1.0, 0.04);
	vec3 soft = LIGHT_COLOR * max(dot(NORMAL, LIGHT), 0.0) * ATTENUATION / PI;
	DIFFUSE_LIGHT += mix(styled, soft, LIGHT_IS_DIRECTIONAL ? 0.55 : 0.25);
}
