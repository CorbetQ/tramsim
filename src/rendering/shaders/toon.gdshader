// Low poly + cel shading : facettes plates (normales recalculées), éclairage en paliers, liseré de lumière.
// Couleur = couleur de sommet. COLOR.a < 0.75 : vitrage (éclairé de l'intérieur la nuit).
// Paramètres `tram_*` : réservés aux rames (Materials.tram) ; valeurs par défaut neutres pour les autres objets.
// Rames : UV = (abscisse de caisse le long de la rame, hauteur) en m ; UV2.x = 1 sur la peinture (motifs de livrée).
shader_type spatial;
render_mode cull_disabled;

#include "res://src/rendering/shaders/cel.gdshaderinc"
uniform float wind_strength = 0.0;
uniform bool passenger_shell = false;

uniform float bands : hint_range(2.0, 5.0) = 3.0;   // conservé (compatibilité) : paliers fixés par cel.gdshaderinc
uniform float shade_floor : hint_range(0.0, 1.0) = 0.18;
uniform float rim_strength : hint_range(0.0, 1.0) = 0.3;
uniform vec3 glass_glow = vec3(1.0, 0.86, 0.6);
uniform float glow_strength = 0.55;
// Rendu Compatibility : couleurs de sommet et ALBEDO sont restitués tels quels (mesuré : ALBEDO 0,5 non éclairé
// → pixel 0,5). Aucune reconversion sRGB→linéaire : 1.0 partout (une seule chaîne de couleur, décor et rames).
uniform float color_gamma = 1.0;
uniform float saturation = 1.0;          // rames : 1,12 (Materials.TRAM_TONE)
uniform vec3 albedo_mul = vec3(1.0);     // végétation : teinte de houppier calée sur l'orthophoto (Materials.foliage)

// --- rames : exposition (couleurs mesurées sur photos = teinte éclairée, pas albédo pur)
uniform float tram_albedo_day = 1.0;     // facteur d'albédo de jour (soleil + ambiance ≈ 1 sur la face éclairée)
uniform float tram_albedo_night = 1.0;   // facteur d'albédo de nuit
uniform float tram_sun = 1.0;            // part du soleil (paliers)
// --- rames : motif procédural de livrée (0 = aucun)
// 1 hirondelles, 2 fleurs, 3 vagues marines, 4 dorures, 5 bandes miroir, 6 feuilles
uniform int tram_pattern = 0;
uniform vec4 tram_pat_c0 : source_color = vec4(1.0);
uniform vec4 tram_pat_c1 : source_color = vec4(1.0);
uniform vec4 tram_pat_c2 : source_color = vec4(1.0);
uniform vec4 tram_pat_c3 : source_color = vec4(1.0);
uniform vec4 tram_pat_box = vec4(0.45, 3.0, 1.0, 0.6);   // y0, y1, échelle (m), densité 0..1
uniform float tram_pat_seed = 0.0;
uniform float tram_pat_glass = 0.0;      // opacité du motif sur les baies latérales (vitrophanie)

varying float v_paint;
varying float v_glass;

vec3 to_linear(vec3 c) {
	vec3 linear = pow(c, vec3(color_gamma));
	float grey = dot(linear, vec3(0.2126, 0.7152, 0.0722));
	return max(mix(vec3(grey), linear, saturation), vec3(0.0));
}

float h21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7)) + tram_pat_seed * 17.13) * 43758.5453); }
vec2 h22(vec2 p) { return vec2(h21(p), h21(p + vec2(41.3, 7.7))); }
vec2 rot(vec2 p, float a) { float c = cos(a), s = sin(a); return vec2(c * p.x - s * p.y, s * p.x + c * p.y); }
vec3 pcol(float k) {
	return k < 0.25 ? tram_pat_c0.rgb : (k < 0.5 ? tram_pat_c1.rgb : (k < 0.75 ? tram_pat_c2.rgb : tram_pat_c3.rgb));
}
float aa(float d) { return 1.0 - smoothstep(-0.006, 0.006, d); }

// Silhouette d'hirondelle (vue de dessous, ailes en faucille, queue fourchue), unité ~1.
float sd_swallow(vec2 p) {
	p.x = abs(p.x);
	// aile en faucille : arc de cercle qui s'affine du corps vers la pointe
	vec2 c = vec2(0.45, -0.55);
	float r = length(p - c);
	float ang = atan(p.y - c.y, p.x - c.x);
	float t = clamp((2.22 - ang) / 1.62, 0.0, 1.0);
	float wing = abs(r - 0.75) - mix(0.11, 0.015, t);
	wing = max(wing, max(ang - 2.22, 0.6 - ang));
	float body = length(vec2(p.x * 1.9, p.y + 0.05)) - 0.17;
	float head = length(p - vec2(0.0, 0.2)) - 0.09;
	// queue fourchue
	vec2 q = p - vec2(0.0, -0.18);
	vec2 dir = normalize(vec2(0.28, -1.0));
	float tl = clamp(dot(q, dir), 0.0, 0.42);
	float tail = length(q - dir * tl) - mix(0.06, 0.012, tl / 0.42);
	return min(min(wing, body), min(head, tail));
}

float sd_flower(vec2 p, float petals) {
	float a = atan(p.y, p.x);
	float r = length(p);
	return r - (0.28 + 0.2 * pow(abs(cos(a * petals * 0.5)), 0.7));
}

// Motif : renvoie (couleur, couverture).
vec4 tram_motif(vec2 uv) {
	float y0 = tram_pat_box.x, y1 = tram_pat_box.y, sc = tram_pat_box.z, dens = tram_pat_box.w;
	if (uv.y < y0 || uv.y > y1) return vec4(0.0);
	float edge = min(uv.y - y0, y1 - uv.y);
	vec2 p = uv / sc;
	if (tram_pattern == 1) {            // hirondelles : vol en nuée, tailles et caps variés
		float best = 0.0;
		for (int k = 0; k < 2; k++) {
			vec2 g = p * (k == 0 ? 1.0 : 1.7) + vec2(float(k) * 3.7, float(k) * 1.3);
			vec2 id = floor(g); vec2 f = fract(g) - 0.5;
			vec2 rnd = h22(id + float(k) * 13.0);
			if (rnd.x > dens) continue;
			vec2 off = (h22(id + 5.0) - 0.5) * 0.16;
			float s = mix(0.3, 0.4, rnd.y) * (k == 0 ? 1.0 : 0.8);
			vec2 q = rot(f - off, (rnd.y - 0.5) * 1.2 + 0.25) / s;
			best = max(best, aa(sd_swallow(q) * s * sc / (k == 0 ? 1.0 : 1.7)));
		}
		return vec4(tram_pat_c0.rgb, best * step(0.03, edge));
	}
	if (tram_pattern == 2) {            // fleurs : corolles 5-6 pétales, cœur contrasté
		vec2 id = floor(p); vec2 f = fract(p) - 0.5;
		vec2 rnd = h22(id);
		if (rnd.x > dens) return vec4(0.0);
		f = f - (h22(id + 3.0) - 0.5) * 0.14;
		float s = mix(0.6, 0.85, rnd.y);
		vec2 q = rot(f, rnd.x * 6.28) / s;
		float d = sd_flower(q, rnd.y > 0.5 ? 5.0 : 6.0) * s * sc;
		float heart = (length(q) - 0.14) * s * sc;
		vec3 c = pcol(h21(id + 9.0));
		vec3 hc = pcol(fract(h21(id + 9.0) + 0.5));
		return vec4(heart < 0.0 ? hc : c, aa(d));
	}
	if (tram_pattern == 3) {            // vagues marines : houle en filets ondulés + écume pointillée
		float w = p.y + 0.18 * sin(p.x * 2.2 + 1.3 * sin(p.x * 0.7)) + 0.07 * sin(p.x * 5.3 + p.y * 2.0);
		float band = fract(w * 2.0);
		float line = abs(band - 0.5);
		vec3 c = mod(floor(w * 2.0), 2.0) < 0.5 ? tram_pat_c0.rgb : tram_pat_c1.rgb;
		float cov = aa(line - 0.07 * dens - 0.03);
		vec2 g = vec2(p.x * 3.0, w * 6.0);
		vec2 id = floor(g); vec2 f = fract(g) - 0.5;
		float dot_ = aa((length(f) - 0.18) / 3.0 * sc) * step(h21(id), 0.35 * dens);
		return vec4(dot_ > cov ? tram_pat_c2.rgb : c, max(cov, dot_));
	}
	if (tram_pattern == 4) {            // dorures : rinceaux (volutes) et médaillons sur un treillis losangé
		vec2 g = vec2(p.x + p.y, p.x - p.y) * 0.7071;
		vec2 f = fract(g) - 0.5;
		float lattice = min(abs(f.x), abs(f.y)) * 0.7071 * sc - 0.008;
		vec2 c2 = fract(p) - 0.5;
		float ring = abs(length(c2) - 0.26) * sc - 0.012;
		float a = atan(c2.y, c2.x);
		float curl = abs(length(c2) - (0.1 + 0.03 * a)) * sc - 0.01;
		float dotc = (length(c2) - 0.05) * sc;
		float d = min(min(lattice, ring), min(curl, dotc));
		float filet = min(abs(uv.y - y0 - 0.06), abs(y1 - uv.y - 0.06)) - 0.012;
		d = min(d, filet);
		return vec4(tram_pat_c0.rgb, aa(d) * dens + aa(filet) * (1.0 - dens));
	}
	if (tram_pattern == 5) {            // bandes miroir : reflets de ciel en bandes horizontales biseautées
		float t = (uv.y - y0) / max(y1 - y0, 0.01);
		float k = floor(t * 5.0); float ft = fract(t * 5.0);
		float sky = smoothstep(0.0, 1.0, ft) * (0.55 + 0.45 * h21(vec2(k, 0.0)));
		vec3 c = mix(tram_pat_c1.rgb, tram_pat_c0.rgb, sky * mix(0.4, 1.0, t));
		float streak = 0.5 + 0.5 * sin(uv.x * 0.9 + uv.y * 2.0);
		c = mix(c, tram_pat_c2.rgb, 0.18 * streak * t);
		return vec4(c, 1.0);
	}
	if (tram_pattern == 6) {            // feuilles
		vec2 id = floor(p); vec2 f = fract(p) - 0.5;
		vec2 rnd = h22(id);
		if (rnd.x > dens) return vec4(0.0);
		vec2 q = rot(f, rnd.y * 3.0 - 1.5);
		float d = length(vec2(q.x * 0.55, q.y * 1.6)) - 0.22;
		return vec4(pcol(h21(id + 4.0)), aa(d * sc * 0.6));
	}
	return vec4(0.0);
}

void vertex() {
	if (wind_strength > 0.0) {
		vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
		float weight = smoothstep(2.0, 6.0, VERTEX.y);
		VERTEX.x += sin(TIME * 1.1 + world.x * 0.07 + world.z * 0.04) * weight * wind_strength;
		VERTEX.z += sin(TIME * 0.8 + world.z * 0.08) * weight * wind_strength * 0.6;
	}
	v_paint = UV2.x;
	v_glass = COLOR.a;
	POSITION = cel_layer_clip(VERTEX, 9.0, MODELVIEW_MATRIX, PROJECTION_MATRIX);  // objets en volume : pas de décalage
}

void fragment() {
	// Boarded variant replaces opaque painted glass with transparent interior glazing.
	if (passenger_shell && (!FRONT_FACING || (COLOR.a > 0.25 && COLOR.a < 0.75))) { discard; }
	NORMAL = normalize(cross(dFdy(VERTEX), dFdx(VERTEX)));
	vec3 base = to_linear(COLOR.rgb) * albedo_mul;
	float pat_glass = 0.0;
	if (tram_pattern > 0 && v_paint > 0.25) {
		vec4 m = tram_motif(UV);
		if (v_paint > 0.75 && COLOR.a > 0.9) base = mix(base, to_linear(m.rgb), clamp(m.a, 0.0, 1.0));
		else if (v_paint <= 0.75 && COLOR.a < 0.75 && COLOR.a > 0.25) pat_glass = clamp(m.a, 0.0, 1.0) * tram_pat_glass;
		if (pat_glass > 0.0) base = mix(base, to_linear(m.rgb) * 0.85, pat_glass);
	}
	ALBEDO = base * mix(tram_albedo_day, tram_albedo_night, night);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	if (COLOR.a < 0.75) {
		ALBEDO = mix(base, base * 0.5, night) * mix(1.0, tram_albedo_day, pat_glass);
		// Reflet stylisé du ciel : dépend du regard, suit les normales des vitres.
		vec3 reflected = reflect(-VIEW, NORMAL);
		float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
		vec3 sky_reflection = mix(vec3(0.13, 0.22, 0.30), vec3(0.58, 0.76, 0.86), smoothstep(-0.15, 0.65, reflected.y));
		float cloud_band = smoothstep(0.88, 0.96, sin(reflected.x * 10.0 + reflected.y * 17.0));
		sky_reflection += vec3(0.10) * cloud_band;
		ALBEDO = mix(ALBEDO, sky_reflection * mix(1.0, 0.12, night), 0.25 + fresnel * 0.45);
		ROUGHNESS = 0.2; SPECULAR = 0.65;
		EMISSION = glass_glow * glow_strength * night;
	}
	if (COLOR.a < 0.25) {  // feux / girouettes : toujours lumineux, plus forts la nuit
		EMISSION = base * (0.6 + 2.0 * night);
	}
}

void light() {
	if (v_glass > 0.25 && v_glass < 0.75) {
		vec3 halfway = normalize(LIGHT + VIEW);
		SPECULAR_LIGHT += LIGHT_COLOR * ATTENUATION * pow(max(dot(NORMAL, halfway), 0.0), 64.0) * 0.6;
	}
	DIFFUSE_LIGHT += cel_light(NORMAL, LIGHT, VIEW, LIGHT_COLOR, ATTENUATION, LIGHT_IS_DIRECTIONAL,
		shade_floor, tram_sun, rim_strength);
}
