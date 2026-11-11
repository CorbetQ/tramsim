// Eau low poly : ondulations facettées animées, teinte en paliers, reflet doux du ciel (Fresnel) et
// scintillement en paliers du soleil / des lumières de la ville la nuit.
shader_type spatial;
render_mode cull_disabled;

#include "res://src/rendering/shaders/cel.gdshaderinc"

uniform vec3 deep : source_color = vec3(0.14, 0.38, 0.52);
uniform vec3 shallow : source_color = vec3(0.32, 0.62, 0.70);
uniform vec3 sky_day : source_color = vec3(0.62, 0.78, 0.92);
uniform vec3 sky_night : source_color = vec3(0.10, 0.13, 0.25);

varying vec3 v_world;

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.y += 0.12 * sin(w.x * 0.15 + TIME * 0.9) + 0.1 * cos(w.z * 0.13 + TIME * 0.7);
	v_world = w;
	POSITION = cel_layer_clip(VERTEX, MODEL_MATRIX, MODELVIEW_MATRIX, PROJECTION_MATRIX);
}

void fragment() {
	NORMAL = normalize(cross(dFdy(VERTEX), dFdx(VERTEX)));
	float t = 0.5 + 0.5 * sin(v_world.x * 0.05 + v_world.z * 0.04 + TIME * 0.3);
	vec3 water = pow(mix(deep, shallow, step(0.5, t) * 0.6), vec3(2.2));
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	vec3 sky = pow(mix(sky_day, sky_night, night), vec3(2.2));
	// reflet en 2 paliers (style), plus marqué en vue rasante
	float refl = 0.15 + 0.45 * smoothstep(0.25, 0.32, fres) + 0.25 * smoothstep(0.6, 0.66, fres);
	ALBEDO = mix(water * mix(1.0, 0.5, night), sky, refl * 0.7);
	// reflets des lumières de la ville la nuit : traits verticaux chauds
	float glint = step(0.93, fract(sin(dot(floor(v_world.xz * vec2(0.6, 0.15)), vec2(12.9, 78.2))) * 43758.5));
	EMISSION = vec3(1.0, 0.75, 0.4) * glint * night * 0.5 * (0.5 + 0.5 * sin(TIME * 2.0 + v_world.x));
	ROUGHNESS = 1.0;
}

void light() {
	float lit = clamp(dot(NORMAL, LIGHT), 0.0, 1.0) * ATTENUATION;
	DIFFUSE_LIGHT += LIGHT_COLOR * mix(0.55, 1.0, smoothstep(0.45, 0.55, lit)) / PI;
	vec3 h = normalize(LIGHT + VIEW);
	float nh = dot(NORMAL, h);
	SPECULAR_LIGHT += LIGHT_COLOR * (smoothstep(0.975, 0.98, nh) * 0.9 + smoothstep(0.93, 0.935, nh) * 0.25) * ATTENUATION;
}
