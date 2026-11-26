class_name Vegetation
extends RefCounted
## Végétation réaliste (refonte P3, docs/CDC_REFONTE_VISUELLE.md §6) : essences urbaines françaises décrites dans
## data/vegetation_species.json (tilleul, marronnier, platane, érable, peuplier, conifère, pin parasol, palmier ; massifs,
## graminées, vivaces). Maillages générés une fois par essence et partagés (MultiMesh) :
## - LOD0 « maillage » : tronc conique, charpentières et rameaux en tubes, feuillage en cartes de rameaux alpha (atlas
##   assets/textures/vegetation/foliage_*.png, feuilles scannées CC0 ambientCG) à normales sphériques (éclairage de
##   volume), translucidité (BACKLIGHT), vent léger et variation de teinte par instance (vegetation.gdshader) ;
## - LOD1 « imposteur » : quad tourné vers la caméra principale (axe vertical), silhouette pré-calculée de l'essence
##   (impostors_*.png). La bascule se fait **par instance** dans le shader (distance à la caméra principale, valable
##   aussi dans les passes d'ombre) : maillage < `lod_near` ≤ imposteur, sans dépendre du découpage en cellules.
## Les cellules de CityScene ne servent plus qu'à borner le rendu (portées de visibilité).
## Couleur de sommet : rgb = teinte ; a = 0 écorce, 0,25 écorce desquamée (platane), 1 feuillage.
## UV2 : x = hauteur relative (amplitude du vent), y = phase de frémissement.

const SPECIES_PATH := "res://data/vegetation_species.json"
const MARRONNIER := 10
const FOLIAGE_CELLS := Vector2(4, 2)
const IMPOSTOR_CELLS := Vector2(4, 2)
const SHADER := "res://src/rendering/shaders/vegetation.gdshader"

static var _species: Array = []
static var _meshes: Dictionary = {}
static var _impostors: Dictionary = {}
static var _mat: ShaderMaterial = null
static var _mat_imp: ShaderMaterial = null
static var _mobile := false

static func species() -> Array:
	if _species.is_empty():
		var d = JSON.parse_string(FileAccess.get_file_as_string(SPECIES_PATH))
		_species = d.species if d is Dictionary else []
	return _species

static func spec(kind: int) -> Dictionary:
	return species()[kind]

## Profil Mobile : atlas 1024 px et imposteurs 512 px (appelé par CityScene selon DayNight.low_quality).
static func set_mobile(on: bool) -> void:
	if on == _mobile and _mat != null: return
	_mobile = on
	if _mat != null: _mat.set_shader_parameter("foliage_tex", load(_tex("foliage")))
	if _mat_imp != null: _mat_imp.set_shader_parameter("foliage_tex", load(_tex("impostors")))

static func _tex(n: String) -> String:
	var big := {"foliage": "2k", "impostors": "1k"}; var small := {"foliage": "1k", "impostors": "512"}
	return "res://assets/textures/vegetation/%s_%s.png" % [n, small[n] if _mobile else big[n]]

static func material() -> ShaderMaterial:
	if _mat == null:
		_mat = ShaderMaterial.new(); _mat.shader = load(SHADER)
		_mat.set_shader_parameter("foliage_tex", load(_tex("foliage")))
		_mat.set_shader_parameter("impostor", false)
		_apply_entry(_mat)
	return _mat

static func impostor_material() -> ShaderMaterial:
	if _mat_imp == null:
		_mat_imp = ShaderMaterial.new(); _mat_imp.shader = load(SHADER)
		_mat_imp.set_shader_parameter("foliage_tex", load(_tex("impostors")))
		_mat_imp.set_shader_parameter("impostor", true)
		_apply_entry(_mat_imp)
	return _mat_imp

## Fiche data/materials/vegetation_cartes.json : rugosité, spéculaire, translucidité.
static func _apply_entry(m: ShaderMaterial) -> void:
	var e := PbrMaterials.entry("vegetation_cartes")
	m.set_shader_parameter("leaf_roughness", float(e.get("roughness", 0.72)))
	m.set_shader_parameter("leaf_specular", float(e.get("specular", 0.35)))
	m.set_shader_parameter("translucency", float(e.get("translucency", 0.5)))

## Distance de bascule maillage → imposteur (m) : la même pour les deux matériaux.
static func set_lod_distance(d: float) -> void:
	material().set_shader_parameter("lod_near", d)
	impostor_material().set_shader_parameter("lod_near", d)

static func mesh(kind: int) -> Mesh:
	if not _meshes.has(kind): _meshes[kind] = _build(kind)
	return _meshes[kind]

static func has_impostor(kind: int) -> bool:
	return int(spec(kind).imp) >= 0

## Côté (m) du carré de l'imposteur (même formule que tools/models/props/build_vegetation_textures.py).
static func impostor_side(kind: int) -> float:
	var c: Array = spec(kind).crown
	return maxf(float(c[0]) + float(c[2]), 2.0 * float(c[1])) * 1.15

static func impostor_mesh(kind: int) -> Mesh:
	if _impostors.has(kind): return _impostors[kind]
	var s := impostor_side(kind); var k := int(spec(kind).imp)
	var cell := Vector2(k % 4, k / 4)
	var u0 := cell / IMPOSTOR_CELLS; var u1 := (cell + Vector2.ONE) / IMPOSTOR_CELLS
	var inset := Vector2(0.5, 0.5) / Vector2(1024, 512)
	u0 += inset; u1 -= inset
	var v := PackedVector3Array([Vector3(-s / 2, 0, 0), Vector3(s / 2, 0, 0), Vector3(s / 2, s, 0), Vector3(-s / 2, s, 0)])
	var uv := PackedVector2Array([Vector2(u0.x, u1.y), Vector2(u1.x, u1.y), Vector2(u1.x, u0.y), Vector2(u0.x, u0.y)])
	var arr := []; arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v; arr[Mesh.ARRAY_TEX_UV] = uv
	arr[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.BACK, Vector3.BACK, Vector3.BACK, Vector3.BACK])
	arr[Mesh.ARRAY_COLOR] = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 1)])
	arr[Mesh.ARRAY_TEX_UV2] = PackedVector2Array([Vector2(0, 0), Vector2(0, 0), Vector2(1, 0), Vector2(1, 0)])
	arr[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 2, 1, 0, 3, 2])
	var m := ArrayMesh.new(); m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	# boîte englobante : le quad tourne autour de l'axe vertical
	m.custom_aabb = AABB(Vector3(-s / 2, 0, -s / 2), Vector3(s, s, s))
	_impostors[kind] = m
	return m

# ------------------------------------------------------------------------------------------------- construction

class _B:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var top := 1.0

	func vert(p: Vector3, nn: Vector3, col: Color, t: Vector2, ph: float) -> void:
		v.append(p); n.append(nn); c.append(col); uv.append(t)
		uv2.append(Vector2(clampf(p.y / top, 0.0, 1.0), ph))

	## Tube conique (écorce) de a vers b, `sides` côtés.
	func tube(a: Vector3, b: Vector3, r0: float, r1: float, sides: int, col: Color) -> void:
		var d := (b - a).normalized()
		var x := d.cross(Vector3.FORWARD if absf(d.y) > 0.9 else Vector3.UP).normalized()
		var z := d.cross(x)
		var L := a.distance_to(b)
		for i in sides:
			var a0 := TAU * i / sides; var a1 := TAU * (i + 1) / sides
			var e0 := x * cos(a0) + z * sin(a0); var e1 := x * cos(a1) + z * sin(a1)
			var u0 := float(i) / sides; var u1 := float(i + 1) / sides
			var p := [a + e0 * r0, a + e1 * r0, b + e1 * r1, b + e0 * r1]
			var ns := [e0, e1, e1, e0]
			var ts := [Vector2(u0, 0), Vector2(u1, 0), Vector2(u1, L), Vector2(u0, L)]
			for k in [0, 2, 1, 0, 3, 2]: vert(p[k], ns[k], col, ts[k], 0.0)

	## Carte de rameau : base en `base`, axe du rameau `up`, largeur selon `side` ; normales sphériques (centre `ctr`).
	func card(base: Vector3, up: Vector3, side: Vector3, size: float, cell: int, ctr: Vector3, squash: Vector3, col: Color, ph: float, bend: float = 0.0) -> void:
		var cl := Vector2(cell % 4, cell / 4)
		var u0 := cl / Vector2(4, 2); var u1 := (cl + Vector2.ONE) / Vector2(4, 2)
		var h := side * size * 0.5
		var mid := base + up * size * 0.5 - Vector3.UP * bend * 0.3
		var tip := base + up * size - Vector3.UP * bend
		var p := [base - h, base + h, mid + h, mid - h, tip + h, tip - h]
		var t := [Vector2(u0.x, u1.y), Vector2(u1.x, u1.y), Vector2(u1.x, (u0.y + u1.y) * 0.5), Vector2(u0.x, (u0.y + u1.y) * 0.5), Vector2(u1.x, u0.y), Vector2(u0.x, u0.y)]
		var fn := up.cross(side).normalized()
		var ns := []
		for q in p:
			var s: Vector3 = ((q - ctr) / squash).normalized()
			ns.append((s * 0.8 + fn * 0.2 * signf(fn.dot(s) + 1e-3)).normalized())
		for k in [0, 1, 2, 0, 2, 3, 3, 2, 4, 3, 4, 5]: vert(p[k], ns[k], col, t[k], ph)

	func mesh() -> ArrayMesh:
		var arr := []; arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = v; arr[Mesh.ARRAY_NORMAL] = n; arr[Mesh.ARRAY_COLOR] = c
		arr[Mesh.ARRAY_TEX_UV] = uv; arr[Mesh.ARRAY_TEX_UV2] = uv2
		var m := ArrayMesh.new(); m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		return m

static func _rand_perp(d: Vector3, rng: RandomNumberGenerator) -> Vector3:
	var a := d.cross(Vector3.UP if absf(d.y) < 0.95 else Vector3.RIGHT).normalized()
	var b := d.cross(a)
	var t := rng.randf() * TAU
	return (a * cos(t) + b * sin(t)).normalized()

static func _build(kind: int) -> Mesh:
	var s: Dictionary = spec(kind)
	var rng := RandomNumberGenerator.new(); rng.seed = 4242 + kind * 97
	var B := _B.new()
	var cr: Array = s.crown
	var ctr := Vector3(0, float(cr[0]), 0)
	var squash := Vector3(float(cr[1]), float(cr[2]), float(cr[1]))
	B.top = maxf(0.5, float(cr[0]) + float(cr[2]))
	var th := float(s.trunk[0]); var tr := float(s.trunk[1])
	var bark := Color(s.bark); bark.a = 0.25 if s.get("patch", false) else 0.0
	var leaf := Color(s.leaf); leaf.a = 1.0
	var cell := int(s.cell); var size := float(s.card); var n := int(s.cards)
	match str(s.shape):
		"round", "umbrella":
			# tronc légèrement incliné, charpentières vers la périphérie du houppier, rameaux secondaires
			var lean := Vector3(rng.randf_range(-0.12, 0.12), 0, rng.randf_range(-0.12, 0.12))
			var crotch := Vector3(0, th, 0) + lean
			B.tube(Vector3.ZERO, crotch * 0.5, tr * 1.15, tr * 0.95, 8, bark)
			B.tube(crotch * 0.5, crotch, tr * 0.95, tr * 0.8, 8, bark)
			var umbrella := str(s.shape) == "umbrella"
			var tips: Array[Vector3] = []
			for i in int(s.limbs):
				var a := TAU * (i + rng.randf_range(-0.2, 0.2)) / int(s.limbs)
				var out := Vector3(cos(a), 0, sin(a))
				var rise := rng.randf_range(0.35, 0.8) if not umbrella else rng.randf_range(0.1, 0.25)
				var end := ctr + Vector3(out.x * squash.x * 0.62, (rise - 0.3) * squash.y * (1.0 if not umbrella else 2.0), out.z * squash.z * 0.62)
				if umbrella: end.y = ctr.y + rng.randf_range(-0.2, 0.25)
				var mid := crotch.lerp(end, 0.5) + Vector3(0, 0.25 * (end.y - crotch.y), 0)
				B.tube(crotch, mid, tr * 0.5, tr * 0.32, 5, bark)
				B.tube(mid, end, tr * 0.32, tr * 0.12, 5, bark)
				tips.append(end)
				# rameaux : de la charpentière vers la périphérie
				for j in 2:
					var o2 := (out + _rand_perp(out, rng) * 0.6 + Vector3.UP * rng.randf_range(0.0, 0.6)).normalized()
					var e2 := ctr + Vector3(o2.x * squash.x * 0.85, o2.y * squash.y * 0.75, o2.z * squash.z * 0.85)
					B.tube(mid.lerp(end, 0.4), e2, tr * 0.12, tr * 0.04, 3, bark)
					tips.append(e2)
			if not umbrella:   # flèche
				B.tube(crotch, ctr + Vector3(0, squash.y * 0.55, 0), tr * 0.5, tr * 0.12, 5, bark)
			for i in n:
				# point sur la coque du houppier (rayon relatif 0,55-1), biaisé vers les extrémités des rameaux
				var d := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1))
				if umbrella: d.y *= 0.45
				if d.length() < 0.2: d = Vector3.UP
				d = d.normalized()
				if i % 3 == 0 and not tips.is_empty():
					var tp: Vector3 = tips[i % tips.size()]
					d = ((tp - ctr) / squash).normalized().lerp(d, 0.35).normalized()
				var rr := rng.randf_range(0.6, 0.95) if i % 4 != 0 else rng.randf_range(0.25, 0.55)
				var p := ctr + d * squash * rr
				var up := (d * Vector3(1, 0.7, 1) + Vector3.UP * 0.25).normalized()
				var base := p - up * size * 0.45
				B.card(base, up, _rand_perp(up, rng), size * rng.randf_range(0.8, 1.15), cell, ctr, squash, leaf, rng.randf())
		"cone":
			B.tube(Vector3.ZERO, Vector3(0, float(cr[0]) + float(cr[2]), 0), tr * 1.2, 0.03, 7, bark)
			var y0 := float(cr[0]) - float(cr[2]); var y1 := float(cr[0]) + float(cr[2])
			for i in n:
				var t := float(i) / n
				var y := lerpf(y0, y1 - 0.4, t) + rng.randf_range(-0.2, 0.2)
				var rad := float(cr[1]) * (1.0 - (y - y0) / (y1 - y0)) + 0.25
				var a := i * 2.399 + rng.randf() * 0.4
				var out := Vector3(cos(a), 0, sin(a))
				var up := (out + Vector3.DOWN * 0.25).normalized()
				var base := Vector3(0, y, 0) + out * 0.08
				B.card(base, up, _rand_perp(up, rng), maxf(0.7, rad * rng.randf_range(0.95, 1.15)), cell, ctr, squash, leaf, rng.randf(), 0.2)
		"palm":
			# stipe annelé légèrement courbe, couronne de palmes retombantes (cartes pliées)
			var top := Vector3(0.35, th, 0.1)
			var segs := 6
			for i in segs:
				var a := Vector3.ZERO.lerp(top, float(i) / segs) + Vector3(sin(float(i) / segs * 2.0) * 0.15, 0, 0)
				var b := Vector3.ZERO.lerp(top, float(i + 1) / segs) + Vector3(sin(float(i + 1) / segs * 2.0) * 0.15, 0, 0)
				B.tube(a, b, tr * (1.0 - 0.25 * i / segs) * 1.08, tr * (1.0 - 0.25 * (i + 1) / segs), 7, bark)
			var crown_top := top + Vector3(sin(2.0) * 0.15, 0, 0)
			for i in n:
				var a := TAU * i / n + rng.randf_range(-0.15, 0.15)
				var out := Vector3(cos(a), rng.randf_range(0.1, 0.65), sin(a)).normalized()
				B.card(crown_top, out, out.cross(Vector3.UP).normalized(), size * rng.randf_range(0.85, 1.1), cell, crown_top, Vector3(3, 1.2, 3), leaf, rng.randf(), size * 0.35)
		"shrub":
			for i in n:
				var d := Vector3(rng.randf_range(-1, 1), rng.randf_range(0.1, 1), rng.randf_range(-1, 1)).normalized()
				var p := ctr + d * squash * 0.55
				var up := (d + Vector3.UP * 0.5).normalized()
				B.card(p - up * size * 0.5, up, _rand_perp(up, rng), size * rng.randf_range(0.85, 1.2), cell, ctr - Vector3(0, 0.4, 0), squash, leaf, rng.randf())
		"tuft":
			for i in n:
				var a := PI * i / n + rng.randf() * 0.3
				var side := Vector3(cos(a), 0, sin(a))
				B.card(Vector3(0, -0.02, 0), Vector3.UP, side, size, cell, Vector3(0, -0.3, 0), Vector3.ONE, leaf, rng.randf())
	return B.mesh()
