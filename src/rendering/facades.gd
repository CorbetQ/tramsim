class_name Facades
extends RefCounted
## Grammaire de façades par styles régionaux (refonte P3, docs/CDC_REFONTE_VISUELLE.md §4.4).
## Appliquée par CityScene._building aux emprises BD TOPO (hauteur LiDAR) :
## - choix du style : quartier (data/facade_styles.json, cercles WGS84 par ville), puis usage BD TOPO (classe),
##   hauteur, emprise et appareil régional (CityScene._facade_type) ;
## - relief des façades sur rue (encadrements, appuis, clés, garde-corps, balcons, bandeaux, corniches moulurées,
##   chaînes d'angle, piliers et bandeau de vitrine), dans un maillage de LOD proche par cellule (FacadeCells) ;
## - toitures (brisis à la Mansart, lucarnes à fronton, souches de cheminée) dans le maillage de base.
## Le relief reprend exactement la trame des baies du shader (pbr_world.gdshader, bloc M_FACADE : travée, hauteur
## d'étage, proportions par type d'appareil) : au-delà de la portée du LOD proche, les baies restent peintes.
## Aucun état : fonctions statiques, sorties dans des CityScene._Arrays (mêmes conventions d'alpha / matériau).

const GENERIC := 0
const ANJOU := 1          # Angers / Anjou : tuffeau, ardoise à forte pente, lucarnes à fronton, chaînes d'angle
const NANTES_XVIII := 2   # Nantes XVIIIe (île Feydeau, quai de la Fosse) : tuffeau, balcons en fer forgé, agrafes, Mansart
const HAUSSMANN := 3      # immeuble de rapport XIXe : pierre de taille, balcons filants (2e, 5e), brisis en zinc
const MODERNE := 4        # béton, enduit (après 1950) : nez de dalle, loggias, garde-corps vitrés, toiture-terrasse
const PAVILLON := 5       # pavillonnaire : enduit, encadrements simples, toit à pentes, cheminée
const ACTIVITE := 6       # zones d'activités : bardage métallique nervuré, bandeau vitré, portes sectionnelles
const NAMES := ["generic", "anjou", "nantes_xviii", "haussmann", "moderne", "pavillon", "activite"]
const DATA := "res://data/facade_styles.json"
const SOLID_A := 0.35
const PAINT_A := 0.41     # métal peint (garde-corps, ferronneries)

## Portée du LOD proche (relief) : PC / Mobile. Cellules de CELL m (portée mesurée au centre de la cellule).
const NEAR_PC := 150.0
const NEAR_MOBILE := 70.0
const CELL := 48.0
## Relief seulement sur les faces tournées vers une voie à moins de STREET_D m.
const STREET_D := 22.0
## Relief seulement pour les bâtiments à moins de TRACK_D m d’une voie du réseau (quand un réseau est lié).
const TRACK_D := 80.0

static var _doc: Dictionary = {}

static func doc() -> Dictionary:
	if _doc.is_empty() and FileAccess.file_exists(DATA):
		var d = JSON.parse_string(FileAccess.get_file_as_string(DATA))
		if d is Dictionary: _doc = d
	return _doc

## Bascule A/B (planches avant/après, diagnostic) : TRAMSIM_FACADES=0 rend le bâti générique d'avant P3.
static func enabled() -> bool:
	return OS.get_environment("TRAMSIM_FACADES") != "0"

static func near_range() -> float:
	return NEAR_MOBILE if DayNight.low_quality else NEAR_PC

static func style_id(name_: String) -> int:
	return maxi(0, NAMES.find(name_))

## Quartiers de la ville en repère de la ville : [[centre, rayon, style]] (premier cercle contenant le point).
static func districts(city: String, origin: Array) -> Array:
	var out: Array = []
	if origin.size() < 2: return out
	var lat0 := float(origin[0]); var lon0 := float(origin[1])
	for d in doc().get("cities", {}).get(city, {}).get("districts", []):
		var x := deg_to_rad(float(d.lon) - lon0) * CityScene.R * cos(deg_to_rad(lat0))
		var z := -deg_to_rad(float(d.lat) - lat0) * CityScene.R
		out.append([Vector2(x, z), float(d.r), style_id(str(d.style))])
	return out

## Style d'un bâtiment courant. p : centre de l'emprise (repère de la ville), cls : classe BD TOPO (0 résidentiel,
## 1 commerces/services, 2 activités, 5 construction légère), ftype : appareil régional (CityScene.F_*).
static func pick(city: String, dist: Array, p: Vector2, cls: int, h: float, area: float, ftype: int, seed_: int) -> int:
	var cfg: Dictionary = doc().get("cities", {}).get(city, {})
	if cls == 2 or (cls == 1 and area > 2500.0 and h < 14.0): return ACTIVITE
	if cls == 5: return GENERIC
	var hs := absi(hash(seed_ * 7 + 11))
	var zone := -1
	for d in dist:
		if p.distance_to(d[0]) <= float(d[1]): zone = int(d[2]); break
	if ftype == CityScene.F_VERRE: return MODERNE
	if zone >= 0:
		# quartier ancien : les immeubles de grande hauteur ou très massifs restent modernes (reconstruction, ZAC)
		if (h >= 24.0 and zone != HAUSSMANN) or (h >= 15.0 and area >= 1800.0): return MODERNE
		if zone == NANTES_XVIII and h >= 17.0 and hs % 3 == 0: return HAUSSMANN
		if zone == ANJOU and h >= 16.0 and hs % 2 == 0: return HAUSSMANN
		if h <= 7.0 and area < 160.0 and zone != HAUSSMANN: return zone if hs % 4 != 0 else PAVILLON
		return zone
	if ftype == CityScene.F_BETON or ftype == CityScene.F_GRAND_ENSEMBLE or h >= 15.0: return MODERNE
	if cls == 0 and h <= 9.5 and area < 260.0: return PAVILLON
	var old := str(cfg.get("old_style", ""))
	if old != "" and (ftype == CityScene.F_TUFFEAU or ftype == CityScene.F_PIERRE): return style_id(old)
	if ftype == CityScene.F_PIERRE and h >= 13.0: return HAUSSMANN
	return GENERIC

## Appareil imposé par le style (même graine : stable), sinon l'appareil régional.
static func ftype_for(st: int, ftype: int, seed_: int) -> int:
	var hs := absi(hash(seed_ * 13 + 5))
	match st:
		ANJOU: return CityScene.F_TUFFEAU if hs % 5 != 0 else CityScene.F_ENDUIT
		NANTES_XVIII: return CityScene.F_TUFFEAU
		HAUSSMANN: return CityScene.F_PIERRE
		MODERNE:
			if ftype == CityScene.F_VERRE or ftype == CityScene.F_GRAND_ENSEMBLE or ftype == CityScene.F_BETON: return ftype
			return CityScene.F_BETON if hs % 2 == 0 else CityScene.F_GRAND_ENSEMBLE
		PAVILLON: return CityScene.F_ENDUIT if ftype != CityScene.F_BRIQUE else ftype
	return ftype

## Trame des baies du shader (pbr_world.gdshader, bloc M_FACADE) pour un code de façade (CityScene._wall_code × 1000).
static func bays(ftype: int, code: float) -> Dictionary:
	var variant := fposmod(code * 0.6180339, 1.0)
	var bay := lerpf(2.4, 4.0, variant)
	var fh := 3.0; var w := lerpf(0.17, 0.29, variant); var wy0 := 0.24; var wy1 := 0.80
	match ftype:
		1, 8: w = lerpf(0.15, 0.2, variant); wy0 = 0.2; wy1 = 0.8
		2, 4: fh = 3.3; w = lerpf(0.17, 0.21, variant); wy0 = 0.12; wy1 = 0.84
		3: w = 0.18; wy0 = 0.16; wy1 = 0.82
		5: w = lerpf(0.15, 0.2, variant); wy0 = 0.18; wy1 = 0.8
		6: w = 0.2; wy0 = 0.08; wy1 = 0.84
		7: fh = 2.75; w = lerpf(0.3, 0.4, variant); wy0 = 0.3; wy1 = 0.82
		9: fh = 3.6; w = 0.47; wy0 = 0.05; wy1 = 0.95
	return {"bay": bay, "fh": fh, "hw": w * bay, "y0": wy0 * fh, "y1": wy1 * fh}

## Vitrines du shader (bloc M_SHOP) : largeur de cellule (graine de façade nulle pour les vitrines).
const SHOP_W := 4.2

# ------------------------------------------------------------------------------------------------ primitives

## Boîte orientée (t : tangente, o : normale sortante) ; faces : 1 avant, 2 dessus, 4 dessous, 8 gauche, 16 droite.
static func obox(S, ctr: Vector3, size: Vector3, t: Vector3, o: Vector3, col: Color, faces: int = 31) -> void:
	var hx := t * size.x * 0.5; var hy := Vector3.UP * size.y * 0.5; var hz := o * size.z * 0.5
	var p := [ctr - hx - hy - hz, ctr + hx - hy - hz, ctr + hx + hy - hz, ctr - hx + hy - hz,
		ctr - hx - hy + hz, ctr + hx - hy + hz, ctr + hx + hy + hz, ctr - hx + hy + hz]
	if faces & 1: S.quad(p[4], p[5], p[6], p[7], col, -1.0)
	if faces & 2: S.quad(p[3], p[2], p[6], p[7], col, -1.0)
	if faces & 4: S.quad(p[0], p[1], p[5], p[4], col, -1.0)
	if faces & 8: S.quad(p[0], p[4], p[7], p[3], col, -1.0)
	if faces & 16: S.quad(p[1], p[5], p[6], p[2], col, -1.0)

## Repère d'une face : point (x le long de la face depuis a, y hauteur, d saillie).
class Face:
	var a: Vector3
	var t: Vector3
	var o: Vector3
	var L: float
	func _init(a2: Vector2, b2: Vector2, out2: Vector2) -> void:
		a = Vector3(a2.x, 0.0, a2.y); var tt := (b2 - a2).normalized(); t = Vector3(tt.x, 0.0, tt.y)
		o = Vector3(out2.x, 0.0, out2.y); L = a2.distance_to(b2)
	func P(x: float, y: float, d: float) -> Vector3:
		return a + t * x + Vector3.UP * y + o * d

## Encadrement saillant (chambranle) : face avant, tableau intérieur (embrasure) et retours extérieurs.
static func frame(S, f: Face, x0: float, x1: float, y0: float, y1: float, s: float, d: float, col: Color) -> void:
	var X0 := x0 - s; var X1 := x1 + s; var Y0 := y0 - s * 0.6; var Y1 := y1 + s
	# avant (4 montants)
	S.quad(f.P(X0, Y0, d), f.P(x0, Y0, d), f.P(x0, Y1, d), f.P(X0, Y1, d), col, -1.0)
	S.quad(f.P(x1, Y0, d), f.P(X1, Y0, d), f.P(X1, Y1, d), f.P(x1, Y1, d), col, -1.0)
	S.quad(f.P(x0, y1, d), f.P(x1, y1, d), f.P(x1, Y1, d), f.P(x0, Y1, d), col, -1.0)
	S.quad(f.P(x0, Y0, d), f.P(x1, Y0, d), f.P(x1, y0, d), f.P(x0, y0, d), col, -1.0)
	# embrasure (tableaux, voussure, appui intérieur)
	var shade := Color(col.r * 0.8, col.g * 0.8, col.b * 0.8, col.a)
	S.quad(f.P(x0, y0, 0.0), f.P(x0, y0, d), f.P(x0, y1, d), f.P(x0, y1, 0.0), shade, -1.0)
	S.quad(f.P(x1, y0, d), f.P(x1, y0, 0.0), f.P(x1, y1, 0.0), f.P(x1, y1, d), shade, -1.0)
	S.quad(f.P(x0, y1, d), f.P(x1, y1, d), f.P(x1, y1, 0.0), f.P(x0, y1, 0.0), shade, -1.0)
	# retour supérieur (les retours latéraux, minces, sont omis : 14 triangles par baie)
	S.quad(f.P(X0, Y1, d), f.P(X1, Y1, d), f.P(X1, Y1, 0.0), f.P(X0, Y1, 0.0), col, -1.0)

## Garde-corps : lisses haute et basse, barreaux (quads vus des deux côtés : le matériau est sans culling).
static func railing(S, f: Face, x0: float, x1: float, y: float, d: float, hgt: float, pitch: float, col: Color, glass: bool = false) -> void:
	var xm := (x0 + x1) * 0.5; var w := x1 - x0
	obox(S, f.P(xm, y + hgt, d), Vector3(w, 0.05, 0.05), f.t, f.o, col, 1 | 2 | 4)
	if glass:   # garde-corps vitré : panneau vitrage (alpha de vitrine)
		S.quad(f.P(x0, y + 0.08, d), f.P(x1, y + 0.08, d), f.P(x1, y + hgt - 0.03, d), f.P(x0, y + hgt - 0.03, d), Color(0.42, 0.5, 0.55, 0.45), -1.0)
		return
	obox(S, f.P(xm, y + 0.1, d), Vector3(w, 0.04, 0.04), f.t, f.o, col, 1 | 2)
	var n := maxi(2, int(w / maxf(pitch, 0.16)))
	for i in range(n + 1):
		var x := x0 + w * float(i) / n
		S.quad(f.P(x - 0.012, y + 0.1, d), f.P(x + 0.012, y + 0.1, d), f.P(x + 0.012, y + hgt, d), f.P(x - 0.012, y + hgt, d), col, -1.0)

## Corniche moulurée : profil à 3 ressauts (larmier en saillie) sur la longueur de la face.
static func cornice(S, f: Face, y: float, depth: float, col: Color) -> void:
	var lite := Color(minf(col.r * 1.06, 1.0), minf(col.g * 1.06, 1.0), minf(col.b * 1.05, 1.0), col.a)
	var xm := f.L * 0.5
	obox(S, f.P(xm, y - 0.42, depth * 0.18), Vector3(f.L, 0.16, depth * 0.36), f.t, f.o, col, 1 | 4 | 8 | 16)
	obox(S, f.P(xm, y - 0.27, depth * 0.33), Vector3(f.L + depth * 0.3, 0.14, depth * 0.66), f.t, f.o, lite, 1 | 4 | 8 | 16)
	obox(S, f.P(xm, y - 0.1, depth * 0.5), Vector3(f.L + depth * 0.6, 0.2, depth), f.t, f.o, col, 31)

# ------------------------------------------------------------------------------------------------ façades

## Relief d'une face sur rue. ring/i : arête, out : normale sortante, u0 : abscisse cumulée (UV.x des murs),
## h : hauteur d'égout, shop : rez-de-chaussée commercial (vitrines du shader de 0 à 3,4 m), wall : teinte + code.
static func face_relief(S, a2: Vector2, b2: Vector2, out2: Vector2, u0: float, h: float, st: int, ftype: int,
		code: float, shop: bool, wall: Color, accent: Color, seed_: int, roof_kind: int) -> void:
	var f := Face.new(a2, b2, out2)
	if f.L < 3.0 or h < 3.0: return
	var stone := Color(minf(wall.r * 1.07, 1.0), minf(wall.g * 1.07, 1.0), minf(wall.b * 1.05, 1.0), code / 1000.0)
	var iron := Color("#23272b"); iron.a = PAINT_A
	if st == ACTIVITE:
		_activity(S, f, h, wall, accent, seed_)
		return
	var hs := absi(hash(seed_ * 29 + 1))
	var g := bays(ftype, code)
	var bay: float = g.bay; var fh: float = g.fh; var hw: float = g.hw
	# éléments par style : [chambranle (largeur, saillie), appui, clé, garde-corps, bandeaux, corniche, chaînes]
	var fs := 0.0; var fd := 0.0; var sill := true; var key := false; var rails := false
	var courses := false; var corn := 0.0; var quoins := false
	match st:
		ANJOU: fs = 0.16; fd = 0.07; courses = hs % 2 == 0; corn = 0.42; quoins = true; rails = g.y0 < 0.5
		NANTES_XVIII: fs = 0.19; fd = 0.09; key = true; rails = true; courses = true; corn = 0.55
		HAUSSMANN: fs = 0.15; fd = 0.07; key = true; rails = true; courses = true; corn = 0.62
		MODERNE: sill = ftype != CityScene.F_VERRE; corn = 0.0
		PAVILLON: fs = 0.09; fd = 0.04
		_: fs = 0.11; fd = 0.05; corn = 0.3 if (ftype == CityScene.F_PIERRE or ftype == CityScene.F_TUFFEAU or ftype == CityScene.F_ANDESITE) else 0.0
	var ground_top := 3.4 if shop else 0.0
	# rez-de-chaussée commercial : piliers (trame des vitrines du shader), bandeau d'enseigne et corniche de devanture
	if shop:
		var k0 := ceili(u0 / SHOP_W); var k1 := floori((u0 + f.L) / SHOP_W)
		var pier := Color(wall.r * 0.9, wall.g * 0.9, wall.b * 0.88, code / 1000.0)
		for k in range(k0, k1 + 1):
			var x := k * SHOP_W - u0
			if x < 0.35 or x > f.L - 0.35: continue
			obox(S, f.P(x, 1.65, 0.07), Vector3(0.6, 3.3, 0.14), f.t, f.o, pier, 1 | 8 | 16)
		obox(S, f.P(f.L * 0.5, 3.4, 0.11), Vector3(f.L, 0.2, 0.22), f.t, f.o, stone, 31)
	# rangées de baies (mêmes cellules que le shader : origine 0,4 m)
	var rows: Array = []
	for fl in range(0, 40):
		var base := 0.4 + fl * fh
		var y0: float = base + g.y0; var y1: float = base + g.y1
		if y1 > h - (0.55 if corn > 0.0 else 0.25): break
		if y0 < maxf(ground_top + 0.3, 0.9): continue
		rows.append([fl, y0, y1, base])
	var kb0 := ceili((u0 + hw + fs + 0.3) / bay - 0.5); var kb1 := floori((u0 + f.L - hw - fs - 0.3) / bay - 0.5)
	var cols: Array = []
	for k in range(kb0, kb1 + 1):
		cols.append((k + 0.5) * bay - u0)
	if cols.size() > 10: cols = cols.slice(0, 10)   # garde-fou (très longues façades : une partie en relief)
	var bal_rows: Array = []    # rangées à balcon filant (haussmannien : 2e et 5e étages ; Nantes : étage noble)
	if st == HAUSSMANN and rows.size() >= 2:
		bal_rows = [1, 4] if rows.size() >= 5 else [1]
	var noble := 0 if not shop else 0
	for ri in rows.size():
		var r: Array = rows[ri]
		var y0: float = r[1]; var y1: float = r[2]
		var filant := ri in bal_rows
		if filant:   # balcon filant : dalle sur consoles, garde-corps en fonte sur toute la longueur
			var yb := y0 - 0.04
			obox(S, f.P(f.L * 0.5, yb - 0.09, 0.42), Vector3(f.L - 0.2, 0.18, 0.84), f.t, f.o, stone, 31)
			for x in cols:
				obox(S, f.P(x, yb - 0.38, 0.22), Vector3(0.18, 0.4, 0.44), f.t, f.o, stone, 1 | 4 | 8 | 16)
			railing(S, f, 0.15, f.L - 0.15, yb, 0.8, 0.95, 0.16, iron)
		if courses and r[0] > 0:   # bandeau d'étage (cordon) au niveau du plancher
			obox(S, f.P(f.L * 0.5, float(r[3]) + 0.05, 0.04), Vector3(f.L, 0.16, 0.08), f.t, f.o, stone, 1 | 2 | 4)
		for ci in cols.size():
			var x: float = cols[ci]
			var x0 := x - hw; var x1 := x + hw
			if fs > 0.0: frame(S, f, x0, x1, y0, y1, fs, fd, stone)
			if sill:
				obox(S, f.P(x, y0 - 0.04, 0.07), Vector3(hw * 2.0 + fs * 2.0 + 0.1, 0.08, 0.14), f.t, f.o, stone, 1 | 2 | 4)
			if key:   # clé (agrafe) au droit du linteau
				obox(S, f.P(x, y1 + fs * 0.5, fd + 0.03), Vector3(0.24, fs + 0.14, 0.06), f.t, f.o, stone, 1 | 4 | 8 | 16)
			if filant: continue
			if st == NANTES_XVIII and ri == noble and (hs + ci) % 4 != 0:
				# balconnet de l'étage noble : dalle galbée sur deux consoles, ferronnerie
				obox(S, f.P(x, y0 - 0.1, 0.3), Vector3(hw * 2.0 + 0.6, 0.14, 0.6), f.t, f.o, stone, 31)
				obox(S, f.P(x - hw, y0 - 0.38, 0.18), Vector3(0.14, 0.4, 0.34), f.t, f.o, stone, 1 | 4 | 8 | 16)
				obox(S, f.P(x + hw, y0 - 0.38, 0.18), Vector3(0.14, 0.4, 0.34), f.t, f.o, stone, 1 | 4 | 8 | 16)
				railing(S, f, x0 - 0.28, x1 + 0.28, y0 - 0.03, 0.58, 0.9, 0.12, iron)
			elif st == MODERNE and ftype != CityScene.F_VERRE and (hs + ci) % 3 == 0:
				# balcon de béton (une travée sur trois) : dalle et garde-corps vitré ou métallique
				var yb := float(r[3]) + 0.02
				obox(S, f.P(x, yb, 0.6), Vector3(bay * 0.92, 0.16, 1.2), f.t, f.o, Color(0.78, 0.77, 0.74, SOLID_A), 31)
				railing(S, f, x - bay * 0.46, x + bay * 0.46, yb + 0.08, 1.18, 1.0, 0.11, iron, hs % 2 == 0)
			elif rails and g.y0 < 0.5:   # porte-fenêtre : barre d'appui
				railing(S, f, x0 - 0.02, x1 + 0.02, y0, 0.05, 0.9, 0.11, iron)
	# nez de dalle (immeubles modernes) : un bandeau par plancher
	if st == MODERNE and ftype != CityScene.F_VERRE:
		for fl in range(1, 40):
			var y := 0.4 + fl * fh - 0.02
			if y > h - 0.5: break
			obox(S, f.P(f.L * 0.5, y, 0.05), Vector3(f.L, 0.22, 0.1), f.t, f.o, Color(wall.r * 1.05, wall.g * 1.05, wall.b * 1.04, SOLID_A), 1 | 2 | 4)
		# acrotère en saillie
		obox(S, f.P(f.L * 0.5, h + 0.3, 0.08), Vector3(f.L, 0.6, 0.16), f.t, f.o, Color(wall.r * 0.95, wall.g * 0.95, wall.b * 0.95, SOLID_A), 31)
	# chaînes d'angle harpées (tuffeau) aux deux extrémités
	if quoins:
		var yq := ground_top + 0.2; var alt := 0
		while yq < h - 0.6:
			var w := 0.55 if alt % 2 == 0 else 0.35
			obox(S, f.P(w * 0.5, yq + 0.17, 0.035), Vector3(w, 0.32, 0.07), f.t, f.o, stone, 1 | 2 | 4 | 16)
			obox(S, f.P(f.L - w * 0.5, yq + 0.17, 0.035), Vector3(w, 0.32, 0.07), f.t, f.o, stone, 1 | 2 | 4 | 8)
			yq += 0.36; alt += 1
	if corn > 0.0 and roof_kind != 2:   # corniche (le brisis haussmannien porte la sienne)
		cornice(S, f, h + 0.03, corn, stone)
	elif corn > 0.0:
		cornice(S, f, h + 0.03, corn * 0.8, stone)

## Bâtiment d'activités : bardage nervuré (nervures tous les 1 m), bandeau vitré haut, portes sectionnelles.
static func _activity(S, f: Face, h: float, wall: Color, accent: Color, seed_: int) -> void:
	var rib := Color(wall.r * 0.92, wall.g * 0.92, wall.b * 0.93, PAINT_A)
	var n := mini(int(f.L / 1.0), 60)
	for i in range(1, n):
		var x := f.L * float(i) / n
		obox(S, f.P(x, h * 0.5, 0.025), Vector3(0.09, h - 0.1, 0.05), f.t, f.o, rib, 1 | 8 | 16)
	if h > 5.0:
		S.quad(f.P(0.4, h - 1.6, 0.06), f.P(f.L - 0.4, h - 1.6, 0.06), f.P(f.L - 0.4, h - 0.8, 0.06), f.P(0.4, h - 0.8, 0.06), Color(0.35, 0.42, 0.47, 0.45), -1.0)
	var hs := absi(hash(seed_ * 3 + 17))
	var doors := clampi(int(f.L / 22.0), 0, 3)
	for d in doors:
		var x := f.L * (float(d) + 0.5) / doors
		var dc := Color(accent.r, accent.g, accent.b, PAINT_A) if hs % 2 == 0 else Color(0.62, 0.64, 0.66, PAINT_A)
		obox(S, f.P(x, 2.0, 0.07), Vector3(4.2, 4.0, 0.06), f.t, f.o, dc, 1)
		frame(S, f, x - 2.1, x + 2.1, 0.0, 4.0, 0.14, 0.12, Color(0.5, 0.52, 0.54, PAINT_A))
	obox(S, f.P(f.L * 0.5, h - 0.15, 0.08), Vector3(f.L, 0.3, 0.16), f.t, f.o, Color(wall.r * 0.85, wall.g * 0.85, wall.b * 0.86, PAINT_A), 31)

# ------------------------------------------------------------------------------------------------ toitures

## Souche de cheminée (brique ou maçonnerie enduite) avec couronnement et mitrons.
static func chimney(S, p: Vector2, y0: float, y1: float, along: Vector2, col: Color) -> void:
	var t := Vector3(along.x, 0.0, along.y); var o := Vector3(-along.y, 0.0, along.x)
	var hgt := maxf(y1 - y0, 0.8)
	obox(S, Vector3(p.x, y0 + hgt * 0.5, p.y), Vector3(1.3, hgt, 0.55), t, o, col, 31)
	var cap := Color(col.r * 1.12, col.g * 1.1, col.b * 1.08, col.a)
	obox(S, Vector3(p.x, y1 + 0.06, p.y), Vector3(1.45, 0.12, 0.7), t, o, cap, 31)
	for k in [-0.35, 0.0, 0.35]:
		obox(S, Vector3(p.x, y1 + 0.27, p.y) + t * k, Vector3(0.18, 0.3, 0.18), t, o, Color(0.62, 0.36, 0.28, SOLID_A), 1 | 2 | 8 | 16)

## Souches sur les pignons (toit à deux pans, faîtage r1-r2 à y + rise) : une ou deux selon la graine.
static func gable_chimneys(S, r1: Vector2, r2: Vector2, y: float, rise: float, col: Color, seed_: int) -> void:
	var ax := (r2 - r1).normalized()
	var hs := absi(hash(seed_ * 41 + 9))
	if hs % 3 == 2: return
	chimney(S, r1 + ax * 0.5, y + rise - 0.6, y + rise + 1.0, ax, col)
	if hs % 3 == 0: chimney(S, r2 - ax * 0.5, y + rise - 0.6, y + rise + 1.0, ax, col)

## Lucarne à fronton (Anjou, Nantes XVIIIe) : jouées en tuffeau, fronton triangulaire, croupe d'ardoise.
static func dormer_pediment(S, foot: Vector3, t: Vector3, o: Vector3, stone: Color, slate: Color) -> void:
	var w := 1.25
	obox(S, foot + Vector3.UP * 0.75, Vector3(w, 1.5, 1.3), t, o, stone, 1 | 8 | 16)
	var f0 := foot + o * 0.65
	S.quad(f0 - t * 0.38 + Vector3.UP * 0.15, f0 + t * 0.38 + Vector3.UP * 0.15, f0 + t * 0.38 + Vector3.UP * 1.3, f0 - t * 0.38 + Vector3.UP * 1.3, Color(0.17, 0.2, 0.23, 0.45), -1.0)
	var top := foot + Vector3.UP * 1.5
	var apex := top + Vector3.UP * 0.75
	S.tri(top - t * (w * 0.5 + 0.08) + o * 0.67, top + t * (w * 0.5 + 0.08) + o * 0.67, apex + o * 0.67, stone, -1.0)
	S.quad(top - t * (w * 0.5 + 0.1) + o * 0.7, apex + o * 0.7, apex - o * 0.7, top - t * (w * 0.5 + 0.1) - o * 0.7, slate, -1.0)
	S.quad(apex + o * 0.7, top + t * (w * 0.5 + 0.1) + o * 0.7, top + t * (w * 0.5 + 0.1) - o * 0.7, apex - o * 0.7, slate, -1.0)
