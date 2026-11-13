shader_type canvas_item;
render_mode unshaded;
uniform float strength = 0.0;
uniform float travel = 0.0;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p), f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1,0)), f.x), mix(hash(i + vec2(0,1)), hash(i + vec2(1,1)), f.x), f.y);
}
void fragment() {
	vec2 p = (UV - 0.5) * (3.0 + travel * 0.35) + vec2(travel * 0.08, -travel * 0.12);
	float clouds = noise(p) * 0.6 + noise(p * 2.1) * 0.28 + noise(p * 4.3) * 0.12;
	COLOR = vec4(mix(vec3(0.65,0.74,0.8), vec3(0.96,0.98,1.0), clouds), smoothstep(0.25,0.72,clouds) * strength);
}
