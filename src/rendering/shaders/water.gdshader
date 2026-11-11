// Eau low poly : ondulations facettées animées, reflets en paliers.
shader_type spatial;
render_mode cull_disabled;

global uniform float night;
uniform vec3 deep = vec3(0.16, 0.42, 0.55);
uniform vec3 shallow = vec3(0.3, 0.62, 0.7);

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.y += 0.12 * sin(w.x * 0.15 + TIME * 0.9) + 0.1 * cos(w.z * 0.13 + TIME * 0.7);
}

void fragment() {
	NORMAL = normalize(cross(dFdy(VERTEX), dFdx(VERTEX)));
	vec3 w = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float t = 0.5 + 0.5 * sin(w.x * 0.05 + w.z * 0.04 + TIME * 0.3);
	ALBEDO = pow(mix(deep, shallow, step(0.5, t) * 0.6), vec3(2.2)) * mix(1.0, 0.45, night);
	ROUGHNESS = 0.2;
	SPECULAR = 0.6;
}

void light() {
	float lit = clamp(dot(NORMAL, LIGHT), 0.0, 1.0) * ATTENUATION;
	DIFFUSE_LIGHT += LIGHT_COLOR * mix(0.5, 1.0, step(0.5, lit)) / PI;
	vec3 h = normalize(LIGHT + VIEW);
	SPECULAR_LIGHT += LIGHT_COLOR * step(0.985, dot(NORMAL, h)) * 0.8;
}
