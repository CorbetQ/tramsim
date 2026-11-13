// Halo de lampadaire projeté au sol : disque additif à décroissance douce, visible la nuit seulement (bon marché :
// un quad par lampadaire, en instances, sans lumière dynamique).
shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

global uniform float night;
uniform vec3 tint : source_color = vec3(1.0, 0.78, 0.5);
uniform float strength = 0.34;

void fragment() {
	float d = length(UV * 2.0 - 1.0);
	float k = pow(clamp(1.0 - d, 0.0, 1.0), 1.8);
	ALBEDO = tint * strength;
	ALPHA = k * smoothstep(0.25, 0.8, night);
}
