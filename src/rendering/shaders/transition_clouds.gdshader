shader_type canvas_item;
render_mode unshaded;
uniform float strength = 0.0;
uniform float travel = 0.0;
// Baked once during city selection; avoid millions of procedural sin() calls per frame.
uniform sampler2D cloud_noise : repeat_enable, filter_linear_mipmap;
void fragment() {
	vec2 p = (UV - 0.5) * (1.0 + travel * 0.12) + vec2(travel * 0.025, -travel * 0.04);
	float clouds = texture(cloud_noise, p).r;
	COLOR = vec4(mix(vec3(0.65,0.74,0.8), vec3(0.96,0.98,1.0), clouds), smoothstep(0.25,0.72,clouds) * strength);
}
