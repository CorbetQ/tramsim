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
const KINDS := 16

const TINT := Color(1.0, 0.0, 1.0, 1.0)     # sentinelle : remplacée par la couleur de l'instance
const A := 1.0                              # alpha : matériau uni (M_PLAIN)
const LIT := 0.1                            # alpha : lumineux (M_LIGHT)
## Portée de rendu (m) par modèle ; mobile : réduite (DayNight.low_quality).
const RANGE := [260.0, 300.0, 220.0, 220.0, 220.0, 110.0, 120.0, 110.0, 120.0, 200.0, 200.0, 160.0, 140.0, 140.0, 140.0, 240.0]

static var _meshes: Array = []
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
static func instances(kind: int, xf: Array, colors: Array = []) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.use_colors = true
	mm.mesh = mesh(kind)
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
	if kind == HALO or kind == BOLLARD or kind == SIGN or kind == INFO or low or kind == PED or kind == PED_B:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi

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
