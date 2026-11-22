// Eau PBR : ondulations animées, teinte vert-brun (rivières françaises vues sur orthophoto), reflet du ciel borné
// (Fresnel) en appoint du reflet PBR du moteur (rugosité faible, sondes/ciel), reflets chauds des lumières la nuit.
// Teintes d'affichage, conversion unique en fin de fragment() (pbr_common).
shader_type spatial;
render_mode cull_disabled;

#include "res://src/rendering/shaders/pbr_common.gdshaderinc"

uniform vec3 deep = vec3(0.20, 0.27, 0.25);
uniform vec3 shallow = vec3(0.30, 0.37, 0.32);
uniform vec3 sky_day = vec3(0.55, 0.66, 0.76);
uniform vec3 sky_night = vec3(0.07, 0.09, 0.16);

varying vec3 v_world;
varying vec3 v_n;

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float t = TIME;
	VERTEX.y += 0.05 * sin(w.x * 0.15 + t * 0.9) + 0.04 * cos(w.z * 0.13 + t * 0.7);
	// normale analytique des ondulations (lisse), plus une houle courte
	vec3 n = vec3(-0.0075 * cos(w.x * 0.15 + t * 0.9), 1.0, 0.0052 * sin(w.z * 0.13 + t * 0.7));
	v_n = normalize(n);
	v_world = w;
	POSITION = pbr_layer_clip(VERTEX, 9.0, MODELVIEW_MATRIX, PROJECTION_MATRIX);
}

float h2(vec2 p) { return fract(sin(dot(p, vec2(12.9, 78.2))) * 43758.5); }
float n2(vec2 p) { vec2 i = floor(p), f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h2(i), h2(i + vec2(1, 0)), f.x), mix(h2(i + vec2(0, 1)), h2(i + vec2(1)), f.x), f.y); }

varying float v_top;

void fragment() {
	float px = max(length(dFdx(v_world)), length(dFdy(v_world)));
	// rides fines (fondues au loin pour éviter le scintillement)
	vec2 q = v_world.xz * 0.9 + vec2(TIME * 0.35, TIME * 0.2);
	float fade = 1.0 - smoothstep(0.3, 0.8, px * 0.9);
	vec3 nw = normalize(v_n + vec3(n2(q) - 0.5, 0.0, n2(q + 31.0) - 0.5) * 0.12 * fade);
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
	// teinte : variation douce par taches (bruit métrique ~40 m), sans bandes (rayons en éventail en perspective)
	float t = n2(v_world.xz * 0.025 + vec2(TIME * 0.01, 0.0));
	vec3 water = mix(deep, shallow, t * 0.35);
	// vue plongeante (aérienne) : ni reflet du ciel ni tache spéculaire sur toute la surface
	v_top = smoothstep(0.85, 0.97, abs(dot(VIEW, (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz)));
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	vec3 sky = mix(sky_day, sky_night, night);
	// reflet d'appoint continu, borné : l'eau garde sa teinte même en vue rasante
	float refl = 0.04 + 0.3 * fres;
	ALBEDO = mix(water * mix(1.0, 0.5, night), sky, refl);
	float glint = step(0.93, fract(sin(dot(floor(v_world.xz * vec2(0.6, 0.15)), vec2(12.9, 78.2))) * 43758.5));
	EMISSION = vec3(1.0, 0.75, 0.4) * glint * night * 0.5 * (0.5 + 0.5 * sin(TIME * 2.0 + v_world.x));
	ROUGHNESS = mix(0.06, 0.5, v_top);   // vue aérienne : pas de plan miroir saturé
	METALLIC = 0.0;
	SPECULAR = 0.5;
	ALBEDO = pbr_albedo(ALBEDO, OUTPUT_IS_SRGB);
	EMISSION = pbr_emission(EMISSION, OUTPUT_IS_SRGB);
}
