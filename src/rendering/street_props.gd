class_name StreetProps
extends RefCounted
## Mobilier urbain et vie de la rue en instances (MultiMesh) : lampadaires (3 modèles), feux tricolores, panneaux,
## potelets, bancs, corbeilles, arceaux vélos, voitures en stationnement, piétons, halos de lampadaires au sol.
## Un maillage low poly par modèle (repère local : sol en y = 0, avant = +Z, côté chaussée = +X), partagé par toutes
## les tuiles ; une MultiMeshInstance3D par modèle et par tuile, bornée en distance (LOD). Les parties en couleur
## TINT prennent la couleur de l'instance (INSTANCE_CUSTOM : carrosseries, vêtements, plaques de panneaux).

const LAMP := 0          # mât droit, lanterne en tête (rues)
const LAMP_ARM := 1      # mât à crosse au-dessus de la chaussée (avenues)
const LAMP_OLD := 2      # lanterne de style sur mât vert (centres anciens)
const CAR := 3           # citadine
const CAR_BIG := 4       # berline / break
const BOLLARD := 5
const BENCH := 6
const BIN := 7
const BIKE := 8
const LIGHTS_GREEN := 9  # feu tricolore (vert allumé)
const LIGHTS_RED := 10   # feu tricolore (rouge allumé)
const SIGN := 11         # panneau rond générique (plaque teintée)
const PED := 12          # piéton
const PED_B := 13        # piéton (silhouette longue : manteau)
const INFO := 14         # poteau d'information voyageurs (quais)
const HALO := 15         # halo de lampadaire au sol (additif, nuit)
const MUPI := 16         # « sucette » d'information / publicité rétroéclairée (affiche générique, sans marque)
const BARRIER := 17      # barrière de trottoir (croix de Saint-André)
const KINDS := 18

const TINT := Color(1.0, 0.0, 1.0, 1.0)     # sentinelle : remplacée par la couleur de l'instance
const A := 1.0                              # alpha : matériau uni (M_PLAIN)
const LIT := 0.1                            # alpha : lumineux (M_LIGHT)
## Portée de rendu (m) par modèle ; mobile : réduite (DayNight.low_quality).
const RANGE := [260.0, 300.0, 220.0, 220.0, 220.0, 110.0, 120.0, 110.0, 120.0, 200.0, 200.0, 160.0, 140.0, 140.0, 140.0, 240.0, 160.0, 110.0]
## LOD (refonte P3) : modèle détaillé jusqu'à NEAR m (centre de cellule), modèle simple au-delà ; les deux portées
## sont mesurées au même centre : exactement un des deux est affiché, sans draw call supplémentaire.
const NEAR := 75.0
const NEAR_MOBILE := 40.0
const M_PAINT := 0.41                       # alpha : métal peint (texture « métal peint » du décor, M_PAINTED = 15)

static var _meshes: Array = []
static var _detail: Dictionary = {}
static var _mat_props: ShaderMaterial = null
static var _mat_halo: ShaderMaterial = null

## Couleurs de carrosserie (parc français : blanc, gris, noir, bleu, rouge dominent).
const CAR_COLORS := ["#e9e9e6", "#e4e4e0", "#9a9ea2", "#7d8287", "#2b2e33", "#1f2328", "#33496b", "#8c2a2a", "#b8b0a0", "#56606a", "#cfcfc9", "#5b2f2a"]
const CLOTHES := ["#2f3a4f", "#3b3b3e", "#6b5844", "#8a2f35", "#2f5246", "#b8a68a", "#4d5f7a", "#d9d4c9", "#1f2124", "#7a6b9a"]

static func mesh(kind: int) -> Mesh:
	if _meshes.is_empty():
		for k in KINDS: _meshes.append(_build(k))
	return _meshes[kind]

static func material(kind: int) -> ShaderMaterial:
	if kind == HALO:
		if _mat_halo == null:
			_mat_halo = ShaderMaterial.new(); _mat_halo.shader = load("res://src/rendering/shaders/halo.gdshader")
		return _mat_halo
	if _mat_props == null:
		_mat_props = Materials.building().duplicate()
		_mat_props.set_shader_parameter("instance_tint", true)
	return _mat_props

## Instances d'un modèle : transformations (repère du parent) et couleurs facultatives (parties TINT).
static func instances(kind: int, xf: Array, colors: Array = [], detail := false) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.use_colors = true
	mm.mesh = detail_mesh(kind) if detail else mesh(kind)
	mm.instance_count = xf.size()
	for i in xf.size():
		mm.set_instance_transform(i, xf[i])
		var c: Color = colors[i] if i < colors.size() else Color(0.5, 0.5, 0.5, 1.0)
		mm.set_instance_custom_data(i, c)
		mm.set_instance_color(i, Color.WHITE)
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = material(kind)
	var low := DayNight.low_quality
	mi.visibility_range_end = RANGE[kind] * (0.6 if low else 1.0)
	mi.visibility_range_end_margin = 20.0
	mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
	if kind == HALO or kind == BOLLARD or kind == SIGN or kind == INFO or low or kind == PED or kind == PED_B or kind == BARRIER:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi

## Instances avec LOD : modèle détaillé proche + modèle simple au-delà (mêmes cellules), ou simple seul.
static func instances_lod(kind: int, xf: Array, colors: Array = []) -> Array:
	if not has_detail(kind): return [instances(kind, xf, colors)]
	var near := NEAR_MOBILE if DayNight.low_quality else NEAR
	var d := instances(kind, xf, colors, true)
	d.visibility_range_end = near; d.visibility_range_end_margin = 0.0
	d.name = "prop_hd_%d" % kind
	var f := instances(kind, xf, colors)
	f.visibility_range_begin = near; f.visibility_range_begin_margin = 0.0
	return [d, f]

static func has_detail(kind: int) -> bool:
	return kind != HALO and kind != PED and kind != PED_B

static func detail_mesh(kind: int) -> Mesh:
	if not has_detail(kind): return mesh(kind)
	if not _detail.has(kind): _detail[kind] = _build_detail(kind)
	return _detail[kind]

static func car_color(rng: RandomNumberGenerator) -> Color:
	return Color(CAR_COLORS[rng.randi() % CAR_COLORS.size()])

static func clothes_color(rng: RandomNumberGenerator) -> Color:
	return Color(CLOTHES[rng.randi() % CLOTHES.size()])

# --------------------------------------------------------------------------------------------- modèles

static func _c(hex: String, a: float = A) -> Color:
	var c := Color(hex); c.a = a
	return c

## Prisme à `sides` côtés (cylindre low poly) de rayon r entre y0 et y1.
static func _prism(S, ctr: Vector3, r: float, y0: float, y1: float, sides: int, col: Color, r_top: float = -1.0) -> void:
	var rt := r if r_top < 0.0 else r_top
	for i in sides:
		var a0 := TAU * i / sides; var a1 := TAU * (i + 1) / sides
		var p0 := Vector3(cos(a0), 0, sin(a0)); var p1 := Vector3(cos(a1), 0, sin(a1))
		S.quad(ctr + p0 * r + Vector3(0, y0, 0), ctr + p1 * r + Vector3(0, y0, 0), ctr + p1 * rt + Vector3(0, y1, 0), ctr + p0 * rt + Vector3(0, y1, 0), col, -1.0)
		S.tri(ctr + Vector3(0, y1, 0), ctr + p1 * rt + Vector3(0, y1, 0), ctr + p0 * rt + Vector3(0, y1, 0), col)

static func _bx(S, ctr: Vector3, s: Vector3, col: Color) -> void:
	S.box(ctr, s, col)

static func _build(kind: int) -> Mesh:
	var S := CityScene._Arrays.new()
	var pole := _c("#4a4d52"); var dark := _c("#2f3236")
	if kind == MUPI or kind == BARRIER: return _build_detail(kind)
	match kind:
		LAMP:
			_prism(S, Vector3.ZERO, 0.11, 0.0, 6.0, 6, pole, 0.07)
			_bx(S, Vector3(0.35, 6.0, 0), Vector3(0.8, 0.12, 0.12), pole)
			_bx(S, Vector3(0.75, 5.92, 0), Vector3(0.55, 0.16, 0.32), _c("#3a3d42"))
			_bx(S, Vector3(0.75, 5.82, 0), Vector3(0.45, 0.05, 0.24), Color(1.0, 0.86, 0.6, LIT))
		LAMP_ARM:
			_prism(S, Vector3.ZERO, 0.14, 0.0, 8.5, 8, pole, 0.08)
			# crosse : deux tronçons vers la chaussée
			S.quad(Vector3(0, 8.3, -0.05), Vector3(1.2, 8.75, -0.05), Vector3(1.2, 8.85, 0.05), Vector3(0, 8.4, 0.05), pole, -1.0)
			S.quad(Vector3(0, 8.4, 0.05), Vector3(1.2, 8.85, 0.05), Vector3(1.2, 8.85, -0.05), Vector3(0, 8.4, -0.05), pole, -1.0)
			_bx(S, Vector3(1.85, 8.8, 0), Vector3(1.4, 0.1, 0.12), pole)
			_bx(S, Vector3(2.4, 8.72, 0), Vector3(0.8, 0.2, 0.4), _c("#3a3d42"))
			_bx(S, Vector3(2.4, 8.6, 0), Vector3(0.7, 0.05, 0.3), Color(1.0, 0.9, 0.7, LIT))
		LAMP_OLD:
			var green := _c("#2e3b33")
			_prism(S, Vector3.ZERO, 0.16, 0.0, 0.6, 8, green, 0.12)
			_prism(S, Vector3.ZERO, 0.08, 0.6, 3.9, 6, green, 0.06)
			_prism(S, Vector3(0, 3.9, 0), 0.12, 0.0, 0.12, 6, green, 0.22)
			_prism(S, Vector3(0, 4.02, 0), 0.22, 0.0, 0.55, 6, Color(1.0, 0.84, 0.55, LIT), 0.27)
			_prism(S, Vector3(0, 4.57, 0), 0.30, 0.0, 0.28, 6, green, 0.04)
		CAR, CAR_BIG:
			var big := kind == CAR_BIG
			var L := 4.55 if big else 3.95; var W := 1.80 if big else 1.72
			var glass := _c("#262c33"); var tyre := _c("#1c1d1f")
			_bx(S, Vector3(0, 0.62, 0), Vector3(W, 0.62, L), TINT)
			# habitacle : pavillon et vitrages inclinés
			var hz := L * (0.27 if big else 0.25); var y0 := 0.93; var y1 := 1.42 if big else 1.48
			var fz := hz + (0.75 if big else 0.6); var rz := -hz - (0.5 if big else 0.35)
			var wi := W * 0.5 - 0.06; var wt := W * 0.5 - 0.16
			var p := [Vector3(-wi, y0, rz), Vector3(wi, y0, rz), Vector3(wi, y0, fz), Vector3(-wi, y0, fz),
				Vector3(-wt, y1, -hz), Vector3(wt, y1, -hz), Vector3(wt, y1, hz * 0.8), Vector3(-wt, y1, hz * 0.8)]
			S.quad(p[3], p[2], p[6], p[7], glass, -1.0)     # pare-brise
			S.quad(p[1], p[0], p[4], p[5], glass, -1.0)     # lunette
			S.quad(p[2], p[1], p[5], p[6], glass, -1.0)     # côtés
			S.quad(p[0], p[3], p[7], p[4], glass, -1.0)
			S.quad(p[4], p[7], p[6], p[5], TINT, -1.0)      # pavillon
			for sx in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					_bx(S, Vector3(sx * (W * 0.5 - 0.12), 0.31, sz * L * 0.32), Vector3(0.24, 0.62, 0.62), tyre)
			_bx(S, Vector3(0, 0.66, L * 0.5 + 0.01), Vector3(W * 0.8, 0.12, 0.02), _c("#d8d8d2"))     # phares
			_bx(S, Vector3(0, 0.74, -L * 0.5 - 0.01), Vector3(W * 0.8, 0.1, 0.02), _c("#8a2020"))    # feux
		BOLLARD:
			_prism(S, Vector3.ZERO, 0.07, 0.0, 0.85, 6, _c("#33413a"), 0.06)
			_prism(S, Vector3.ZERO, 0.075, 0.68, 0.76, 6, _c("#cfcfc8"), 0.075)
		BENCH:
			var wood := _c("#7a5a3c"); var metal := _c("#3b3f44")
			_bx(S, Vector3(0, 0.44, 0), Vector3(0.45, 0.06, 1.8), wood)
			S.quad(Vector3(-0.24, 0.48, -0.9), Vector3(-0.24, 0.48, 0.9), Vector3(-0.3, 0.9, 0.9), Vector3(-0.3, 0.9, -0.9), wood, -1.0)
			for z in [-0.75, 0.75]:
				_bx(S, Vector3(0, 0.22, z), Vector3(0.42, 0.44, 0.05), metal)
		BIN:
			_prism(S, Vector3(0, 0, 0), 0.06, 0.0, 0.95, 4, _c("#3b3f44"))
			_prism(S, Vector3(0.25, 0.25, 0), 0.22, 0.0, 0.6, 8, _c("#2f4a3b"), 0.24)
		BIKE:
			var steel := _c("#8b9096")
			for z in [-1.2, 0.0, 1.2]:
				for x in [-0.35, 0.35]:
					_bx(S, Vector3(x, 0.4, z), Vector3(0.05, 0.8, 0.05), steel)
				_bx(S, Vector3(0, 0.8, z), Vector3(0.75, 0.05, 0.05), steel)
		LIGHTS_GREEN, LIGHTS_RED:
			_prism(S, Vector3.ZERO, 0.07, 0.0, 3.1, 6, dark)
			_bx(S, Vector3(0, 2.75, 0.12), Vector3(0.32, 0.95, 0.22), dark)
			var on_r := kind == LIGHTS_RED
			var lamps := [[3.04, Color(1.0, 0.15, 0.1, LIT) if on_r else _c("#4a1c1a")], [2.75, _c("#4a3a1a")],
				[2.46, Color(0.2, 1.0, 0.5, LIT) if not on_r else _c("#1a3a26")]]
			for l in lamps:
				_bx(S, Vector3(0, l[0], 0.24), Vector3(0.2, 0.2, 0.03), l[1])
			_bx(S, Vector3(0, 1.1, 0.08), Vector3(0.14, 0.24, 0.1), dark)     # bouton piéton
		SIGN:
			_prism(S, Vector3.ZERO, 0.035, 0.0, 2.55, 4, _c("#8b9096"))
			var c := Vector3(0, 2.3, 0.05); var r := 0.33
			for i in 8:
				var a0 := TAU * (i + 0.5) / 8.0; var a1 := TAU * (i + 1.5) / 8.0
				S.tri(c, c + Vector3(cos(a0) * r, sin(a0) * r, 0), c + Vector3(cos(a1) * r, sin(a1) * r, 0), TINT)
				S.tri(c + Vector3(0, 0, -0.02), c + Vector3(cos(a1) * r, sin(a1) * r, -0.02), c + Vector3(cos(a0) * r, sin(a0) * r, -0.02), _c("#9a9da0"))
			_bx(S, c + Vector3(0, 0, 0.012), Vector3(0.42, 0.1, 0.01), _c("#f2f2ee"))
		PED, PED_B:
			var skin := _c("#c9a083"); var legs := _c("#2c3038"); var shoe := _c("#1f1f22")
			var coat := kind == PED_B
			_bx(S, Vector3(-0.1, 0.42, 0), Vector3(0.13, 0.84 if not coat else 0.6, 0.16), legs)
			_bx(S, Vector3(0.1, 0.42, 0.03), Vector3(0.13, 0.84 if not coat else 0.6, 0.16), legs)
			_bx(S, Vector3(0, 0.03, 0.04), Vector3(0.36, 0.06, 0.26), shoe)
			if coat:
				_prism(S, Vector3(0, 0.0, 0), 0.25, 0.55, 1.45, 6, TINT, 0.2)
			else:
				_bx(S, Vector3(0, 1.13, 0), Vector3(0.42, 0.6, 0.24), TINT)
			_bx(S, Vector3(-0.27, 1.1, 0), Vector3(0.1, 0.55, 0.12), TINT)
			_bx(S, Vector3(0.27, 1.1, 0), Vector3(0.1, 0.55, 0.12), TINT)
			_bx(S, Vector3(0, 1.48, 0), Vector3(0.1, 0.1, 0.1), skin)
			_prism(S, Vector3(0, 1.52, 0), 0.11, 0.0, 0.22, 6, skin, 0.1)
			_prism(S, Vector3(0, 1.70, -0.01), 0.115, 0.0, 0.06, 6, _c("#3a2c22"), 0.08)
		INFO:
			_prism(S, Vector3.ZERO, 0.06, 0.0, 2.6, 6, _c("#3d4a57"))
			_bx(S, Vector3(0, 2.75, 0), Vector3(0.12, 0.4, 0.9), _c("#2a3038"))
			_bx(S, Vector3(0.065, 2.75, 0), Vector3(0.01, 0.28, 0.8), Color(1.0, 0.7, 0.25, LIT))
			_bx(S, Vector3(-0.065, 2.75, 0), Vector3(0.01, 0.28, 0.8), Color(1.0, 0.7, 0.25, LIT))
		HALO:
			var m := ArrayMesh.new()
			var arr := []; arr.resize(Mesh.ARRAY_MAX)
			var r := 5.5
			arr[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(-r, 0, -r), Vector3(r, 0, -r), Vector3(r, 0, r), Vector3(-r, 0, -r), Vector3(r, 0, r), Vector3(-r, 0, r)])
			arr[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 0), Vector2(1, 1), Vector2(0, 1)])
			arr[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP])
			m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
			return m
	return S.mesh()

# ------------------------------------------------------------------------------------------- modèles détaillés (P3)

## Tube (facettes) d'axe quelconque de a vers b.
static func _tube(S, a: Vector3, b: Vector3, r0: float, r1: float, sides: int, col: Color) -> void:
	var d := (b - a).normalized()
	var x := d.cross(Vector3.FORWARD if absf(d.y) > 0.9 else Vector3.UP).normalized()
	var z := d.cross(x)
	for i in sides:
		var a0 := TAU * i / sides; var a1 := TAU * (i + 1) / sides
		var e0 := x * cos(a0) + z * sin(a0); var e1 := x * cos(a1) + z * sin(a1)
		S.quad(a + e0 * r0, b + e0 * r1, b + e1 * r1, a + e1 * r0, col, -1.0)

## Profil de révolution (rayon, hauteur) autour de l'axe vertical en `ctr`.
static func _lathe(S, ctr: Vector3, prof: Array, sides: int, col: Color) -> void:
	for k in prof.size() - 1:
		var p0: Vector2 = prof[k]; var p1: Vector2 = prof[k + 1]
		_prism(S, ctr, p0.x, p0.y, p1.y, sides, col, p1.x)

## Tube courbe le long d'une polyligne.
static func _bent(S, pts: Array, r: float, sides: int, col: Color) -> void:
	for i in pts.size() - 1: _tube(S, pts[i], pts[i + 1], r, r, sides, col)

static func _wheel(S, ctr: Vector3, r: float, w: float) -> void:
	_tube(S, ctr - Vector3(w * 0.5, 0, 0), ctr + Vector3(w * 0.5, 0, 0), r, r, 12, _c("#1a1b1d"))
	var hub := ctr + Vector3(signf(ctr.x) * (w * 0.5 + 0.005), 0, 0)
	for i in 12:   # jante alliage
		var a0 := TAU * i / 12.0; var a1 := TAU * (i + 1) / 12.0
		S.tri(hub, hub + Vector3(0, cos(a0), sin(a0)) * r * 0.62, hub + Vector3(0, cos(a1), sin(a1)) * r * 0.62, _c("#9ea3a8") if i % 2 == 0 else _c("#5d6266"))

static func _build_detail(kind: int) -> Mesh:
	var S := CityScene._Arrays.new()
	var steel := _c("#5a5f63", M_PAINT); var anth := _c("#3a3e42", M_PAINT)
	match kind:
		LAMP:   # mât cylindro-conique, luminaire LED plat sur crosse courte
			_lathe(S, Vector3.ZERO, [Vector2(0.15, 0), Vector2(0.15, 0.35), Vector2(0.11, 0.42), Vector2(0.065, 6.0)], 12, anth)
			_tube(S, Vector3(0, 5.85, 0), Vector3(0.55, 6.02, 0), 0.04, 0.035, 6, anth)
			_bx(S, Vector3(0.82, 6.02, 0), Vector3(0.62, 0.07, 0.26), anth)
			_bx(S, Vector3(0.82, 6.08, 0), Vector3(0.5, 0.05, 0.2), anth)
			_bx(S, Vector3(0.84, 5.98, 0), Vector3(0.5, 0.012, 0.2), Color(1.0, 0.9, 0.72, LIT))
			_bx(S, Vector3(0, 1.0, 0.07), Vector3(0.1, 0.36, 0.03), _c("#2a2d30"))   # trappe de visite
		LAMP_ARM:   # mât de 8,5 m, crosse cintrée, lanterne routière
			_lathe(S, Vector3.ZERO, [Vector2(0.2, 0), Vector2(0.2, 0.45), Vector2(0.15, 0.55), Vector2(0.075, 8.4)], 12, steel)
			var arc := []
			for i in 7:
				var t := i / 6.0
				arc.append(Vector3(t * 2.0, 8.4 + sin(t * PI * 0.5) * 0.55 - t * t * 0.1, 0))
			_bent(S, arc, 0.05, 6, steel)
			_bx(S, Vector3(2.35, 8.82, 0), Vector3(0.85, 0.12, 0.36), steel)
			_bx(S, Vector3(2.35, 8.9, 0), Vector3(0.7, 0.06, 0.28), steel)
			_bx(S, Vector3(2.38, 8.755, 0), Vector3(0.66, 0.012, 0.26), Color(1.0, 0.9, 0.72, LIT))
		LAMP_OLD:   # candélabre de style : fût cannelé, lanterne à 4 faces vitrées, chapeau, pointe
			var green := _c("#2b3a31", M_PAINT)
			_lathe(S, Vector3.ZERO, [Vector2(0.24, 0), Vector2(0.24, 0.12), Vector2(0.17, 0.2), Vector2(0.15, 0.75), Vector2(0.11, 0.85),
				Vector2(0.075, 1.0), Vector2(0.06, 3.6), Vector2(0.09, 3.7), Vector2(0.06, 3.85)], 10, green)
			for a in 4:
				var e := Vector3(cos(a * PI * 0.5), 0, sin(a * PI * 0.5))
				_tube(S, Vector3(0, 3.5, 0), Vector3(0, 3.95, 0) + e * 0.2, 0.015, 0.015, 4, green)
			_prism(S, Vector3(0, 3.9, 0), 0.14, 0.0, 0.08, 4, green, 0.2)
			_prism(S, Vector3(0, 3.98, 0), 0.2, 0.0, 0.5, 4, Color(1.0, 0.84, 0.55, LIT), 0.26)
			for a in 4:
				var e := Vector3(cos(a * PI * 0.5 + PI * 0.25), 0, sin(a * PI * 0.5 + PI * 0.25))
				_tube(S, Vector3(0, 3.98, 0) + e * 0.2, Vector3(0, 4.48, 0) + e * 0.26, 0.012, 0.012, 4, green)
			_prism(S, Vector3(0, 4.48, 0), 0.32, 0.0, 0.06, 4, green, 0.3)
			_prism(S, Vector3(0, 4.54, 0), 0.3, 0.0, 0.26, 4, green, 0.03)
			_lathe(S, Vector3(0, 4.8, 0), [Vector2(0.03, 0), Vector2(0.05, 0.05), Vector2(0.0, 0.18)], 6, green)
		CAR, CAR_BIG:
			var big := kind == CAR_BIG
			var L := 4.55 if big else 3.95; var W := 1.80 if big else 1.72
			var glass := _c("#1d232a", 0.6); var plastic := _c("#1e2023")
			var hw := W * 0.5
			# caisse : profil latéral extrudé (capot, pare-brise, pavillon, lunette, coffre), flancs galbés
			var prof := [Vector2(-L / 2, 0.32), Vector2(-L / 2 - 0.02, 0.62), Vector2(-L / 2 + 0.08, 0.9), Vector2(-L * (0.33 if big else 0.36), 0.98),
				Vector2(-L * 0.22, 1.42 if big else 1.48), Vector2(L * 0.12, 1.45 if big else 1.5), Vector2(L * 0.28, 0.98), Vector2(L / 2 - 0.06, 0.86),
				Vector2(L / 2 + 0.02, 0.6), Vector2(L / 2, 0.32)]
			for i in prof.size() - 1:
				var p0: Vector2 = prof[i]; var p1: Vector2 = prof[i + 1]
				var inset0 := 0.16 if p0.y > 1.0 else 0.0; var inset1 := 0.16 if p1.y > 1.0 else 0.0
				var col := glass if (i == 3 or i == 5) else TINT
				S.quad(Vector3(-hw + inset0, p0.y, p0.x), Vector3(hw - inset0, p0.y, p0.x), Vector3(hw - inset1, p1.y, p1.x), Vector3(-hw + inset1, p1.y, p1.x), col, -1.0)
			# flancs : bas de caisse (TINT) puis vitrages latéraux
			for sx in [-1.0, 1.0]:
				var x: float = sx * hw
				S.quad(Vector3(x, 0.32, -L / 2), Vector3(x, 0.32, L / 2), Vector3(x, 0.98, L * 0.28), Vector3(x, 0.98, -L * (0.33 if big else 0.36)), TINT, -1.0)
				S.tri(Vector3(x, 0.98, L * 0.28), Vector3(x, 0.32, L / 2), Vector3(x, 0.86, L / 2 - 0.06), TINT)
				S.tri(Vector3(x, 0.98, -L * (0.33 if big else 0.36)), Vector3(x, 0.32, -L / 2), Vector3(x, 0.9, -L / 2 + 0.08), TINT)
				var xi: float = sx * (hw - 0.16)
				S.quad(Vector3(x, 0.98, -L * (0.33 if big else 0.36)), Vector3(x, 0.98, L * 0.28), Vector3(xi, 1.45 if big else 1.5, L * 0.12), Vector3(xi, 1.42 if big else 1.48, -L * 0.22), glass, -1.0)
				_bx(S, Vector3(sx * (hw + 0.08), 1.02, L * 0.22), Vector3(0.14, 0.09, 0.05), TINT)        # rétroviseur
				_bx(S, Vector3(sx * (hw + 0.005), 0.4, 0), Vector3(0.02, 0.1, L * 0.55), plastic)           # bas de caisse
				for sz in [-1.0, 1.0]:
					_wheel(S, Vector3(sx * (hw - 0.13), 0.31, sz * L * 0.32), 0.31, 0.21)
			_bx(S, Vector3(0, 0.38, L / 2 + 0.03), Vector3(W * 0.96, 0.18, 0.08), plastic)       # boucliers
			_bx(S, Vector3(0, 0.38, -L / 2 - 0.03), Vector3(W * 0.96, 0.18, 0.08), plastic)
			for sx in [-1.0, 1.0]:
				_bx(S, Vector3(sx * hw * 0.68, 0.72, L / 2 + 0.01), Vector3(0.32, 0.1, 0.03), _c("#e4e6e2"))   # optiques
				_bx(S, Vector3(sx * hw * 0.72, 0.8, -L / 2 - 0.01), Vector3(0.3, 0.12, 0.03), _c("#9a1b1b"))
			_bx(S, Vector3(0, 0.5, L / 2 + 0.075), Vector3(0.52, 0.11, 0.01), _c("#f1f1ee"))      # plaques (blanches)
			_bx(S, Vector3(0, 0.62, -L / 2 - 0.075), Vector3(0.52, 0.11, 0.01), _c("#f1f1ee"))
			_bx(S, Vector3(-0.23, 0.5, L / 2 + 0.08), Vector3(0.05, 0.11, 0.01), _c("#2b4aa0"))   # bande bleue UE
			_bx(S, Vector3(-0.23, 0.62, -L / 2 - 0.08), Vector3(0.05, 0.11, 0.01), _c("#2b4aa0"))
		BOLLARD:   # potelet de ville tourné (fonte), bague réfléchissante
			var cast := _c("#2f3a33", M_PAINT)
			_lathe(S, Vector3.ZERO, [Vector2(0.085, 0), Vector2(0.085, 0.06), Vector2(0.06, 0.1), Vector2(0.055, 0.7), Vector2(0.07, 0.76),
				Vector2(0.075, 0.86), Vector2(0.05, 0.92), Vector2(0.0, 0.95)], 10, cast)
			_prism(S, Vector3.ZERO, 0.057, 0.64, 0.7, 10, _c("#e8e8e2"), 0.057)
		BENCH:   # banc à lattes de bois, piètement et accoudoirs en fonte
			var wood := _c("#80603f", 0.27); var iron := _c("#2c3034", M_PAINT)
			for k in 4:
				_bx(S, Vector3(-0.2 + k * 0.12, 0.45, 0), Vector3(0.09, 0.035, 1.9), wood)
			for k in 3:
				var y := 0.6 + k * 0.13
				_bx(S, Vector3(-0.27 - k * 0.025, y, 0), Vector3(0.03, 0.09, 1.9), wood)
			for z in [-0.82, 0.0, 0.82]:
				_bx(S, Vector3(-0.02, 0.21, z), Vector3(0.05, 0.42, 0.05), iron)
				_bx(S, Vector3(-0.02, 0.43, z), Vector3(0.48, 0.04, 0.05), iron)
				_tube(S, Vector3(-0.22, 0.43, z), Vector3(-0.32, 0.95, z), 0.025, 0.025, 4, iron)
			for z in [-0.95, 0.95]:
				_bx(S, Vector3(0.0, 0.66, z), Vector3(0.42, 0.04, 0.06), iron)
				_bx(S, Vector3(0.18, 0.55, z), Vector3(0.04, 0.22, 0.05), iron)
		BIN:   # corbeille « Vigipirate » : cerclage sur poteau, sac translucide vert, couvercle
			_lathe(S, Vector3.ZERO, [Vector2(0.05, 0), Vector2(0.04, 0.05), Vector2(0.035, 1.05)], 8, steel)
			var c := Vector3(0.26, 0, 0)
			var ring := []
			for i in 13:
				var a := TAU * i / 12.0
				ring.append(c + Vector3(cos(a) * 0.23, 0.92, sin(a) * 0.23))
			_bent(S, ring, 0.012, 4, steel)
			_tube(S, Vector3(0.03, 0.92, 0), c + Vector3(-0.23, 0.92, 0), 0.012, 0.012, 4, steel)
			_lathe(S, c, [Vector2(0.12, 0.32), Vector2(0.2, 0.42), Vector2(0.23, 0.9), Vector2(0.24, 0.93)], 12, _c("#5f8a5a"))
			_lathe(S, c, [Vector2(0.25, 0.95), Vector2(0.25, 0.99), Vector2(0.06, 1.05), Vector2(0.0, 1.06)], 12, steel)
		BIKE:   # arceaux en U renversé (tube inox)
			var inox := _c("#a4a9ad", 0.41)
			for z in [-1.2, 0.0, 1.2]:
				var pts := [Vector3(-0.35, 0, z)]
				for i in 7:
					var a := PI - PI * i / 6.0
					pts.append(Vector3(cos(a) * 0.35, 0.62 + sin(a) * 0.2, z))
				pts.append(Vector3(0.35, 0, z))
				_bent(S, pts, 0.03, 6, inox)
				_bx(S, Vector3(0, 0.35, z), Vector3(0.66, 0.025, 0.012), inox)
		LIGHTS_GREEN, LIGHTS_RED:   # feu R11 sur support, visières, panneau de contraste, feu piéton R12, bouton
			var dark := _c("#25282b", M_PAINT)
			_lathe(S, Vector3.ZERO, [Vector2(0.09, 0), Vector2(0.07, 0.1), Vector2(0.055, 3.25)], 8, dark)
			_bx(S, Vector3(0, 2.72, 0.13), Vector3(0.3, 0.92, 0.2), dark)
			_bx(S, Vector3(0, 2.72, 0.02), Vector3(0.52, 1.12, 0.02), _c("#111214"))       # panneau de contraste
			_bx(S, Vector3(0, 2.72, 0.008), Vector3(0.55, 1.15, 0.01), _c("#e9e9e4"))      # liseré blanc
			var on_r := kind == LIGHTS_RED
			var lamps := [[3.0, Color(1.0, 0.15, 0.1, LIT) if on_r else _c("#3a1715")], [2.72, _c("#3a2e15")],
				[2.44, Color(0.2, 1.0, 0.5, LIT) if not on_r else _c("#15301f")]]
			for l in lamps:
				_prism(S, Vector3(0, l[0], 0.235), 0.1, 0.0, 0.01, 10, l[1], 0.1)
				# visière
				S.quad(Vector3(-0.12, l[0] + 0.12, 0.235), Vector3(0.12, l[0] + 0.12, 0.235), Vector3(0.12, l[0] + 0.1, 0.42), Vector3(-0.12, l[0] + 0.1, 0.42), dark, -1.0)
			# feu piéton (R12) et boîtier d'appel
			_bx(S, Vector3(0, 1.95, -0.1), Vector3(0.24, 0.48, 0.16), dark)
			_bx(S, Vector3(0, 2.07, -0.185), Vector3(0.16, 0.16, 0.01), Color(1.0, 0.15, 0.1, LIT) if not on_r else _c("#3a1715"))
			_bx(S, Vector3(0, 1.83, -0.185), Vector3(0.16, 0.16, 0.01), Color(0.2, 1.0, 0.5, LIT) if on_r else _c("#15301f"))
			_bx(S, Vector3(0, 1.1, 0.08), Vector3(0.12, 0.22, 0.09), _c("#d9c33a"))
		SIGN:   # panneau de police : support galvanisé, disque à liseré blanc, dos gris, attaches
			_lathe(S, Vector3.ZERO, [Vector2(0.03, 0), Vector2(0.03, 2.6), Vector2(0.0, 2.62)], 8, _c("#9aa0a4", 0.41))
			var c := Vector3(0, 2.3, 0.05)
			for i in 20:
				var a0 := TAU * i / 20.0; var a1 := TAU * (i + 1) / 20.0
				S.tri(c, c + Vector3(cos(a0), sin(a0), 0) * 0.3, c + Vector3(cos(a1), sin(a1), 0) * 0.3, TINT)
				S.quad(c + Vector3(cos(a0), sin(a0), 0) * 0.3, c + Vector3(cos(a0), sin(a0), 0) * 0.35, c + Vector3(cos(a1), sin(a1), 0) * 0.35, c + Vector3(cos(a1), sin(a1), 0) * 0.3, _c("#f2f2ee"), -1.0)
				S.tri(c + Vector3(0, 0, -0.015), c + Vector3(cos(a1), sin(a1), 0) * 0.35 + Vector3(0, 0, -0.015), c + Vector3(cos(a0), sin(a0), 0) * 0.35 + Vector3(0, 0, -0.015), _c("#8d9194"))
			_bx(S, c + Vector3(0, 0, 0.004), Vector3(0.4, 0.09, 0.006), _c("#f2f2ee"))
			for y in [2.12, 2.48]: _bx(S, Vector3(0, y, 0.02), Vector3(0.08, 0.03, 0.05), _c("#9aa0a4", 0.41))
		INFO:   # totem d'information voyageurs : écran double face, casquette
			_bx(S, Vector3(0, 1.3, 0), Vector3(0.1, 2.6, 0.18), _c("#2f3a44", M_PAINT))
			_bx(S, Vector3(0, 2.75, 0), Vector3(0.14, 0.46, 0.96), _c("#252b32", M_PAINT))
			_bx(S, Vector3(0, 3.0, 0), Vector3(0.2, 0.04, 1.02), _c("#252b32", M_PAINT))
			_bx(S, Vector3(0.072, 2.75, 0), Vector3(0.01, 0.3, 0.84), Color(1.0, 0.7, 0.25, LIT))
			_bx(S, Vector3(-0.072, 2.75, 0), Vector3(0.01, 0.3, 0.84), Color(1.0, 0.7, 0.25, LIT))
		MUPI:   # « sucette » 120 x 176 : pied, caisson à cadre, deux affiches rétroéclairées génériques
			var frame := _c("#3b4046", M_PAINT)
			_bx(S, Vector3(0, 0.03, 0), Vector3(0.5, 0.06, 0.3), frame)
			_bx(S, Vector3(0, 0.3, 0), Vector3(0.16, 0.5, 0.12), frame)
			_bx(S, Vector3(0, 1.45, 0), Vector3(1.32, 1.9, 0.16), frame)
			for sz in [-1.0, 1.0]:
				var z: float = sz * 0.082
				_bx(S, Vector3(0, 1.45, z), Vector3(1.18, 1.74, 0.006), Color(0.96, 0.94, 0.88, LIT))   # affiche (fond clair)
				_bx(S, Vector3(0, 1.0, z * 1.05), Vector3(1.18, 0.5, 0.006), TINT)                       # bandeau de couleur
				_bx(S, Vector3(-0.2, 1.75, z * 1.05), Vector3(0.5, 0.5, 0.006), _c("#8c3a2c"))           # visuel générique
		BARRIER:   # barrière de trottoir 1,2 m (croix de Saint-André), vert fonte
			var g := _c("#2d3b33", M_PAINT)
			for x in [-0.6, 0.6]: _lathe(S, Vector3(x, 0, 0), [Vector2(0.035, 0), Vector2(0.035, 0.95), Vector2(0.05, 1.0), Vector2(0.0, 1.06)], 6, g)
			_tube(S, Vector3(-0.6, 0.95, 0), Vector3(0.6, 0.95, 0), 0.022, 0.022, 5, g)
			_tube(S, Vector3(-0.6, 0.3, 0), Vector3(0.6, 0.3, 0), 0.018, 0.018, 5, g)
			_tube(S, Vector3(-0.58, 0.32, 0), Vector3(0.58, 0.93, 0), 0.016, 0.016, 4, g)
			_tube(S, Vector3(-0.58, 0.93, 0), Vector3(0.58, 0.32, 0), 0.016, 0.016, 4, g)
	return S.mesh()
