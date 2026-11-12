shader_type canvas_item;
render_mode unshaded;
uniform float speed = 0.0;
uniform sampler2D world_color : hint_screen_texture, repeat_disable, filter_nearest;
global uniform float night;
void fragment() {
	vec2 p = UV - vec2(0.5, 0.47);
	p.x *= 1.7;
	float radius = length(p);
	float edge = smoothstep(0.38, 0.9, radius);
	float angle = atan(p.y, p.x);
	float bands = pow(max(0.0, sin(angle * 83.0 + sin(angle * 19.0) * 4.0)), 28.0);
	float flow = pow(max(0.0, sin(radius * 43.0 - TIME * (12.0 + speed))), 8.0);
	float amount = smoothstep(7.0, 23.0, speed);
	// Courbe de contraste douce, appliquée au monde avant le HUD. Pas de
	// noirs coupés ; atténuation la nuit pour préserver la lisibilité.
	vec3 color = texture(world_color, SCREEN_UV).rgb;
	vec3 bounded = clamp(color, vec3(0.0), vec3(1.0));
	vec3 curve = bounded * bounded * (3.0 - 2.0 * bounded);
	color = mix(color, curve, 0.30 * (1.0 - night));
	float streak = edge * bands * flow * amount * 0.08;
	COLOR = vec4(mix(color, vec3(0.78, 0.88, 0.94), streak), 1.0);
}
