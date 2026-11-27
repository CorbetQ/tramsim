// Gouttes sur le pare-brise (vue cabine, lot P4 « ambiance ») : gouttes procédurales en espace écran (trois grilles
// d'échelles différentes, une goutte possible par cellule, naissance périodique décalée), lentille inversée sur l'image
// déjà rendue (texture d'écran : fonctionne dans les trois renderers), liseré sombre et reflet. Le balai efface ce
// qu'il balaie : `clear_t[bin]` = dernier passage du balai dans le secteur angulaire `bin` (WindscreenRain), une goutte
// n'est visible que si elle est née après. Masque : partie haute de l'écran (pare-brise), pas le pupitre.
shader_type spatial;
render_mode unshaded, blend_mix, depth_test_disabled, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform float rain = 0.0;          // 0..1 : densité des gouttes
uniform float now = 0.0;           // horloge (s), la même que clear_t
uniform float clear_t[16];         // dernier passage du balai par secteur (s)
uniform vec2 pivot = vec2(0.5, 0.66);   // axe du balai (UV d'écran)
uniform float reach = 0.62;        // longueur du balai (hauteur d'écran)
uniform float glass_bottom = 0.60; // bas du pare-brise (UV d'écran, 0 = haut)
uniform float speed = 0.0;         // m/s : les gouttes filent vers le haut à vitesse
uniform float night = 0.0;

float h1(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }

vec4 layer(vec2 p, float scale, float seed, float aspect, inout vec2 refr) {
	vec2 g = p * scale;
	vec2 c = floor(g);
	float r0 = h1(c + seed);
	if (r0 > rain * 0.45) return vec4(0.0);
	float period = mix(5.0, 14.0, h1(c + seed + 1.7)) / max(rain, 0.15);
	float phase = h1(c + seed + 3.1);
	float birth = (floor(now / period - phase) + phase) * period;
	vec2 ctr = c + 0.25 + 0.5 * vec2(h1(c + seed + 5.3), h1(c + seed + 7.9));
	// secteur du balai qui couvre la goutte
	vec2 uv = vec2(ctr.x / scale / aspect, ctr.y / scale);
	vec2 v = (uv - pivot) * vec2(aspect, 1.0);
	float phi = atan(-v.y, -v.x);
	float cleared = -1e6;
	if (length(v) < reach && phi >= 0.0 && phi <= 3.1416) cleared = clear_t[clamp(int(phi / 3.1416 * 16.0), 0, 15)];
	if (birth <= cleared) return vec4(0.0);
	float age = now - birth;
	// les grosses gouttes coulent un peu ; à vitesse, elles filent vers le haut
	// une goutte sur cinq coule (filet au-dessus d'elle) ; à vitesse, les gouttes filent vers le haut en s'étirant
	float runner = step(0.8, h1(c + seed + 9.1));
	ctr.y += runner * min(age * 0.06, 0.45) - min(age * speed * 0.004, 0.3);
	float rad = mix(0.07, 0.17, pow(h1(c + seed + 11.3), 2.0));
	vec2 d = (g - ctr) / rad;
	float trail = runner * smoothstep(0.0, -2.5, d.y) * step(abs(d.x), 0.35);
	d.y *= mix(1.0, 0.55, clamp(speed / 15.0, 0.0, 1.0));
	if (trail > 0.0 && length(d) > 1.0) { refr += vec2(0.0, 0.002); return vec4(0.0, 0.0, 0.35 * trail * (1.0 + d.y / 3.0), 1.0); }
	float l = length(d);
	if (l > 1.0) return vec4(0.0);
	float a = smoothstep(1.0, 0.55, l) * 0.85;
	refr += -d * rad / scale * 0.45;
	float rim = smoothstep(0.75, 1.0, l) * 0.35;
	float hi = smoothstep(0.25, 0.0, length(d - vec2(-0.3, -0.35))) * 0.6;
	return vec4(rim, hi, a, 1.0);
}

void fragment() {
	vec2 suv = SCREEN_UV;
	float mask = 1.0 - smoothstep(glass_bottom - 0.08, glass_bottom, suv.y);
	float aspect = VIEWPORT_SIZE.x / max(VIEWPORT_SIZE.y, 1.0);
	vec2 p = vec2(suv.x * aspect, suv.y);
	vec2 refr = vec2(0.0);
	vec4 acc = vec4(0.0);
	vec4 l1 = layer(p, 14.0, 0.0, aspect, refr);
	vec4 l2 = layer(p, 24.0, 31.0, aspect, refr);
	vec4 l3 = layer(p, 40.0, 67.0, aspect, refr);
	acc = max(max(l1, l2), l3);
	float alpha = acc.z * mask;
	if (alpha < 0.002) discard;
	vec3 seen = textureLod(screen_tex, clamp(suv + refr * vec2(1.0 / aspect, 1.0), vec2(0.001), vec2(0.999)), 2.5).rgb;
	vec3 col = seen * (1.0 - acc.x * 0.3) + vec3(0.9, 0.95, 1.0) * acc.y * mix(0.35, 0.15, night);
	ALBEDO = col;
	ALPHA = alpha * 0.92;
}
