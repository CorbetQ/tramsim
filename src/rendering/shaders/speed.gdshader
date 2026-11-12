shader_type canvas_item;
render_mode unshaded;
uniform float speed = 0.0;
void fragment() {
	vec2 p = UV - vec2(0.5, 0.47);
	p.x *= 1.7;
	float radius = length(p);
	float edge = smoothstep(0.38, 0.9, radius);
	float angle = atan(p.y, p.x);
	float bands = pow(max(0.0, sin(angle * 83.0 + sin(angle * 19.0) * 4.0)), 28.0);
	float flow = pow(max(0.0, sin(radius * 43.0 - TIME * (12.0 + speed))), 8.0);
	float amount = smoothstep(7.0, 23.0, speed);
	COLOR = vec4(vec3(0.78, 0.88, 0.94), edge * bands * flow * amount * 0.08);
}
