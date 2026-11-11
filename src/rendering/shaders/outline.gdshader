// Contour encré (coque inversée) : les sommets sont poussés depuis l'axe de la caisse.
shader_type spatial;
render_mode cull_front, unshaded;

uniform float width = 0.045;
uniform vec3 axis_center = vec3(0.0, 1.7, 0.0);
uniform vec4 ink : source_color = vec4(0.07, 0.07, 0.09, 1.0);

void vertex() {
	vec3 d = VERTEX - vec3(axis_center.x, axis_center.y, VERTEX.z);
	VERTEX += normalize(d + vec3(0.0001)) * width;
}

void fragment() {
	ALBEDO = ink.rgb;
}
