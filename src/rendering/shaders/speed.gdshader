shader_type canvas_item;
render_mode unshaded;
uniform float speed = 0.0;
uniform float bloom_amount = 0.0;
uniform float motion_amount = 0.0;
uniform vec2 camera_motion = vec2(0.0);
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
	// Camera-direction blur, not per-object motion vectors. Always before the HUD.
	if (motion_amount > 0.0 && length(camera_motion) > 0.00001) {
		vec3 accumulation = color;
		for (int i = 1; i < 5; i++) {
			vec2 uv = clamp(SCREEN_UV + camera_motion * (float(i) / 4.0 - 0.5), SCREEN_PIXEL_SIZE, vec2(1.0) - SCREEN_PIXEL_SIZE);
			accumulation += texture(world_color, uv).rgb;
		}
		color = mix(color, accumulation / 5.0, motion_amount);
	}
	// Small LDR highlight halo for Compatibility, not an HDR bloom substitute.
	if (bloom_amount > 0.0) {
		vec3 halo = vec3(0.0);
		for (int i = 0; i < 4; i++) {
			vec2 axis = i == 0 ? vec2(1,0) : (i == 1 ? vec2(-1,0) : (i == 2 ? vec2(0,1) : vec2(0,-1)));
			vec3 light = texture(world_color, clamp(SCREEN_UV + axis * SCREEN_PIXEL_SIZE * 3.0, SCREEN_PIXEL_SIZE, vec2(1.0)-SCREEN_PIXEL_SIZE)).rgb;
			halo += max(light - vec3(0.87), vec3(0.0));
		}
		color += halo * bloom_amount * 0.25;
	}
	vec3 bounded = clamp(color, vec3(0.0), vec3(1.0));
	vec3 curve = bounded * bounded * (3.0 - 2.0 * bounded);
	color = mix(color, curve, 0.30 * (1.0 - night));
	float streak = edge * bands * flow * amount * 0.08;
	COLOR = vec4(mix(color, vec3(0.78, 0.88, 0.94), streak), 1.0);
}
