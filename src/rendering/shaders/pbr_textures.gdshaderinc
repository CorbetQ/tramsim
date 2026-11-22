// Textures PBR réelles (refonte P1) : bibliothèque data/materials (PbrMaterials), une couche par matériau dans trois
// Texture2DArray (albédo sRGB, normale OpenGL, ORM = AO/rugosité/métal), 2048² (PC) ou 1024² (Mobile, Repli),
// importées en VRAM compressée (S3TC/BPTC, ETC2/ASTC), mipmaps + filtrage anisotrope.
// Projection métrique sans UV : sol (normale proche de la verticale) en plan XZ monde ; murs et pentes en projection
// plane par facette (axe horizontal de la face, hauteur) ; gradients explicites (textureGrad) calculés hors branches.
// L'albédo MODULE la teinte de l'appelant (palette, couleur de sommet) : rapport texture / moyenne de la couche
// (pbr_layer_mean), donc la teinte moyenne calibrée (photos, orthophotos) est conservée et la texture n'apporte que le
// détail. Anti-répétition (pbr_tex_quality = 2) : second échantillon tourné à une autre échelle, mélangé par un bruit
// macro (≈ 12 m) ; Mobile (= 1) : un échantillon. 0 ou couche < 0 : repli procédural (aucun échantillonnage).
uniform sampler2DArray pbr_albedo_tex : filter_linear_mipmap_anisotropic, repeat_enable, hint_default_white;
uniform sampler2DArray pbr_normal_tex : filter_linear_mipmap_anisotropic, repeat_enable, hint_default_white;
uniform sampler2DArray pbr_orm_tex : filter_linear_mipmap_anisotropic, repeat_enable, hint_default_white;
uniform int pbr_tex_quality = 0;
uniform float pbr_tex_contrast = 1.0;      // amplitude du détail d'albédo (1 = texture telle quelle)
uniform float pbr_normal_strength = 1.0;
// Par couche (index = PbrMaterials layer) : moyenne d'albédo (sRGB), rugosité et AO moyens, taille du motif (m).
uniform vec3 pbr_layer_mean[16];
uniform vec4 pbr_layer_info[16];           // x = taille du motif (m), y = rugosité moyenne, z = AO moyen, w = force normale

float pbr_thash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float pbr_tnoise(vec2 p) {
	vec2 i = floor(p), f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(pbr_thash(i), pbr_thash(i + vec2(1, 0)), f.x), mix(pbr_thash(i + vec2(0, 1)), pbr_thash(i + vec2(1)), f.x), f.y);
}

// Repère de projection (monde) d'une facette de normale monde `wn` : T (u croissant), B (haut de l'image), N.
// uv métrique en sortie. Sol : XZ ; murs/pentes : axe horizontal de la face et hauteur.
vec2 pbr_planar(vec3 p, vec3 wn, out vec3 T, out vec3 B) {
	vec3 h = vec3(wn.z, 0.0, -wn.x);
	float hl = length(h);
	bool ground = abs(wn.y) > 0.6 || hl < 1e-3;
	vec3 t = ground ? vec3(1.0, 0.0, 0.0) : h / max(hl, 1e-3);
	T = t;
	B = ground ? vec3(0.0, 0.0, -1.0) : normalize(cross(wn, t));   // N = T × B (repère direct)
	return ground ? p.xz : vec2(dot(p, t), -dot(p, B));
}

// Échantillonne la couche `layer` ; uv métrique `uvm`, gradients `gx`, `gy` (dFdx/dFdy de uvm, pris hors branches).
// Sorties : rapport d'albédo (≈ 1 en moyenne), normale tangente (x, y, z), ORM brut.
void pbr_tex_sample(int layer, vec2 uvm, vec2 gx, vec2 gy, out vec3 ratio, out vec3 nts, out vec3 orm) {
	vec4 info = pbr_layer_info[layer];
	float s = 1.0 / max(info.x, 0.05);
	vec3 uv = vec3(uvm * s, float(layer));
	vec2 dx = gx * s, dy = gy * s;
	vec3 a = textureGrad(pbr_albedo_tex, uv, dx, dy).rgb;
	vec3 n = textureGrad(pbr_normal_tex, uv, dx, dy).rgb;
	vec3 o = textureGrad(pbr_orm_tex, uv, dx, dy).rgb;
	if (pbr_tex_quality >= 2) {
		// second échantillon : rotation 37°, échelle 0,71, décalage ; poids par bruit macro (≈ 12 m)
		const float C = 0.7986, S = 0.6018;
		mat2 r = mat2(vec2(C, S), vec2(-S, C)) * 0.71;
		vec3 uv2 = vec3(r * uv.xy + vec2(0.37, 0.61), uv.z);
		float w = smoothstep(0.32, 0.68, pbr_tnoise(uvm * 0.083 + float(layer) * 3.1));
		vec2 dx2 = r * dx, dy2 = r * dy;
		a = mix(a, textureGrad(pbr_albedo_tex, uv2, dx2, dy2).rgb, w);
		vec3 n2 = textureGrad(pbr_normal_tex, uv2, dx2, dy2).rgb;
		// normale du second échantillon tournée dans le repère du premier
		vec2 n2xy = transpose(mat2(vec2(C, S), vec2(-S, C))) * (n2.xy * 2.0 - 1.0);
		n = mix(n, vec3(n2xy * 0.5 + 0.5, n2.z), w);
		o = mix(o, textureGrad(pbr_orm_tex, uv2, dx2, dy2).rgb, w);
	}
	ratio = clamp(a / max(pbr_layer_mean[layer], vec3(0.02)), vec3(0.25), vec3(2.2));
	ratio = mix(vec3(1.0), ratio, pbr_tex_contrast);
	vec2 nxy = (n.xy * 2.0 - 1.0) * info.w * pbr_normal_strength;
	nts = vec3(nxy, sqrt(max(1.0 - dot(nxy, nxy), 0.05)));
	orm = o;
}

// Normale monde perturbée (repère T, B, N) -> normale vue.
vec3 pbr_tex_normal(vec3 nts, vec3 T, vec3 B, vec3 wn, mat4 view) {
	vec3 nw = normalize(T * nts.x + B * nts.y + wn * nts.z);
	return normalize((view * vec4(nw, 0.0)).xyz);
}
