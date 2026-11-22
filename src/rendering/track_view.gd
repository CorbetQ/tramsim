class_name TrackView
extends RefCounted
## Plateforme de tram : rubans à jonctions en onglet (sommets partagés), nature réelle de la plateforme
## (gazon / enrobé / pavés ou béton désactivé, analysée sur les orthophotos IGN, voir tools/import/ign_scene.py)
## et zones interdites au décor (KeepOut : voies, quais).
## Rendu (matériau pbr_world, identifiant de matériau dans l'alpha des couleurs : textures procédurales
## métriques nettes, cohérentes avec la chaussée de la ville) :
## - lit : gazon (M_VEG), enrobé (M_ASPHALT), pavés (M_PAVING) ou béton désactivé (granulats apparents, joints de
##   dalle tous les SLAB_M) ; bordures béton (gazon) ou caniveau (chaussée) ;
## - rails à gorge (Ri 60) : champignon poli, gorge sombre côté intérieur ; noyés à fleur dans la chaussée (joint
##   bitumineux de part et d'autre), sur longrines béton à 3 cm au-dessus du gazon ;
## - contre-rail sur le rail intérieur des courbes de rayon < GUARD_R_M ;
## - appareils de voie (détectés aux extrémités d'arêtes confondues) : aiguilles polies effilées, coupons de
##   joints au talon et au cœur, cœur de croisement, moteur d'aiguillage.

const BED_TOP_M := 0.09
const RAIL_TOP_M := BED_TOP_M + 0.03     # champignon au-dessus du gazon
const EMBED_TOP_M := BED_TOP_M + 0.014   # rail noyé : à fleur (léger relief pour la profondeur)
const APS_TOP_M := BED_TOP_M + 0.015
const BED_UNKNOWN := 0
const BED_GRASS := 1
const BED_ROAD := 2
const BED_PAVED := 3
const MAX_SEG := 8.0          # m : subdivision pour suivre les changements de nature
const GRASS := Color("#79a35a")
const ASPHALT := Color("#5f6268")
const CONCRETE := Color("#b4ada1")     # béton désactivé (granulats apparents)
const SLEEPER := Color("#b3b1aa")
const RAIL := Color("#8f959c")
const RAIL_TOP := Color(0.812, 0.827, 0.843, A_METAL)   # #cfd3d7, acier (M_METAL)
const RAIL_SIDE := Color("#4a4440")    # âme du rail (rouille sombre)
const GROOVE := Color("#26282b")
const BLADE := Color(0.894, 0.910, 0.918, A_METAL)      # #e4e8ea
const JOINT := Color("#1d1e20")
const GUARD_R_M := 50.0       # contre-rail en deçà de ce rayon
const SLAB_M := 6.0           # pas des joints de dalle béton
## Identifiants de matériau du shader pbr_world (CityScene._Arrays.mat_id : alpha des couleurs de sommets).
const A_ASPHALT := 0.28
const A_PAVING := 0.29
const A_VEG := 0.30
const A_METAL := 0.37

static func _mat(c: Color, a: float) -> Color:
	return Color(c.r, c.g, c.b, a)

## Polyligne resserrée (segments <= MAX_SEG), extrémités prolongées de `ext` pour fermer les jonctions.
static func densify(pts: Array, ext: float = 0.15) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for i in pts.size():
		var p: Vector3 = pts[i]
		if i > 0:
			var a: Vector3 = pts[i - 1]
			var n := int(ceil(a.distance_to(p) / MAX_SEG))
			for k in range(1, n):
				out.append(a.lerp(p, float(k) / n))
		if out.is_empty() or out[-1].distance_to(p) > 0.02:
			out.append(p)
	if out.size() >= 2 and ext > 0.0:
		out[0] -= (out[1] - out[0]).normalized() * ext
		out[-1] += (out[-1] - out[-2]).normalized() * ext
	return out

## Normales en onglet (longueur 1/cos(demi-angle), bornée) aux sommets de la polyligne.
static func miter_normals(pts: Array[Vector3]) -> PackedVector3Array:
	var n := PackedVector3Array(); n.resize(pts.size())
	for i in pts.size():
		var d0 := (pts[i] - pts[maxi(i - 1, 0)]).normalized() if i > 0 else Vector3.ZERO
		var d1 := (pts[mini(i + 1, pts.size() - 1)] - pts[i]).normalized() if i < pts.size() - 1 else Vector3.ZERO
		var d := (d0 + d1).normalized()
		if d == Vector3.ZERO: d = d0 if d0 != Vector3.ZERO else d1
		var nrm := Vector3(-d.z, 0, d.x)
		var seg := d1 if d1 != Vector3.ZERO else d0
		var c := nrm.dot(Vector3(-seg.z, 0, seg.x))
		n[i] = nrm / clampf(c, 0.5, 1.0)
	return n

## Ruban continu : quads par segment partageant leurs sommets ; `cols` = une couleur par segment.
static func ribbon(g, pts: Array[Vector3], nrm: PackedVector3Array, w: float, y: float, cols: Array, offset: float = 0.0) -> void:
	var up := Vector3(0, y, 0)
	var hw := w * 0.5
	for i in range(pts.size() - 1):
		var a := pts[i] + nrm[i] * offset + up; var b := pts[i + 1] + nrm[i + 1] * offset + up
		g.quad(a - nrm[i] * hw, a + nrm[i] * hw, b + nrm[i + 1] * hw, b - nrm[i + 1] * hw, cols[i])

const SMOOTH_WIN := 12.0      # m : demi-fenêtre du vote majoritaire le long de la voie
const MIN_RUN := 30.0         # m : longueur minimale d'un tronçon de même nature (sinon fondu dans le voisin)
const CURB := Color("#c9c5bb")
const GUTTER := Color("#6e7176")

## Nature de plateforme lissée le long de la voie (pas de damier gazon / enrobé / pavés) : natures inconnues comblées
## par la plus proche connue, vote majoritaire pondéré par la longueur sur ± SMOOTH_WIN, puis fusion des tronçons
## plus courts que MIN_RUN dans le voisin le plus long. `lens` : longueur de chaque segment.
static func smooth_kinds(kinds: Array, lens: Array) -> Array:
	var n := kinds.size()
	var k := kinds.duplicate()
	if n == 0: return k
	# 1. inconnues : plus proche connue (le long de la voie)
	var last := -1
	for i in n:
		if int(k[i]) != BED_UNKNOWN: last = i
		elif last >= 0: k[i] = k[last]
	last = -1
	for i in range(n - 1, -1, -1):
		if int(kinds[i]) != BED_UNKNOWN: last = i
		elif int(k[i]) == BED_UNKNOWN and last >= 0: k[i] = k[last]
	# 2. vote majoritaire
	var pos: Array = []; var acc := 0.0
	for i in n: pos.append(acc + float(lens[i]) * 0.5); acc += float(lens[i])
	var voted := k.duplicate()
	var j0 := 0
	for i in n:
		var votes := {}
		while float(pos[j0]) < float(pos[i]) - SMOOTH_WIN: j0 += 1
		var j := j0
		while j < n and float(pos[j]) <= float(pos[i]) + SMOOTH_WIN:
			votes[k[j]] = float(votes.get(k[j], 0.0)) + float(lens[j]); j += 1
		var best: int = int(k[i]); var bv := -1.0
		for key in votes:
			if float(votes[key]) > bv or (float(votes[key]) == bv and int(key) == int(k[i])): bv = float(votes[key]); best = int(key)
		voted[i] = best
	k = voted
	# 3. longueur minimale de tronçon
	for _pass in 8:
		var runs: Array = []   # [début, fin (exclue), nature, longueur]
		var s0 := 0
		for i in range(1, n + 1):
			if i == n or int(k[i]) != int(k[s0]):
				var L := 0.0
				for q in range(s0, i): L += float(lens[q])
				runs.append([s0, i, int(k[s0]), L]); s0 = i
		if runs.size() < 2: break
		var shortest := -1; var sl := MIN_RUN
		for r in runs.size():
			if float(runs[r][3]) < sl: sl = float(runs[r][3]); shortest = r
		if shortest < 0: break
		var left: Array = runs[shortest - 1] if shortest > 0 else []
		var right: Array = runs[shortest + 1] if shortest < runs.size() - 1 else []
		var into: int = int(left[2]) if right.is_empty() or (not left.is_empty() and float(left[3]) >= float(right[3])) else int(right[2])
		for q in range(int(runs[shortest][0]), int(runs[shortest][1])): k[q] = into
	return k

## Plateforme d'une voie (axe `pts`, décalage `o` vers la droite) : lit texturé par tronçon (nature lissée), bordures
## de plateforme côté extérieur (gazon) ou caniveau (enrobé, pavés, béton), rails à gorge, contre-rails en courbe
## serrée, appareils de voie aux extrémités partagées avec une autre voie.
static func build(g, axis: Array, o: float, nature_fn: Callable, fallback: Color, paved: Color, gauge_m: float = 1.435, no_skirt: Callable = Callable(), ground: Callable = Callable()) -> void:
	var pts := densify(axis)
	if pts.size() < 2: return
	var nrm := miter_normals(pts)
	var raw: Array = []; var lens: Array = []
	for i in range(pts.size() - 1):
		raw.append(nature_fn.call((pts[i] + pts[i + 1]) * 0.5))
		lens.append(pts[i].distance_to(pts[i + 1]))
	var kinds := smooth_kinds(raw, lens)
	# pavés (teinte chaude des centres anciens) ou béton désactivé pour la nature « pavés / béton »
	var setts := paved.r > paved.b + 0.06
	var fb_kind := BED_GRASS if fallback == GRASS else (BED_ROAD if fallback == ASPHALT else BED_PAVED)
	var bed: Array = []; var grassy: Array = []
	for k in kinds:
		var kk := int(k) if int(k) != BED_UNKNOWN else fb_kind
		grassy.append(kk == BED_GRASS)
		match kk:
			BED_GRASS: bed.append(_mat(GRASS, A_VEG))
			BED_ROAD: bed.append(_mat(ASPHALT, A_ASPHALT))
			_:
				var base := paved if int(k) != BED_UNKNOWN else fallback
				bed.append(_mat(base, A_PAVING) if setts and int(k) != BED_UNKNOWN else _mat(base.lerp(CONCRETE, 0.55), A_ASPHALT))
	ribbon(g, pts, nrm, 3.5, BED_TOP_M, bed, o)
	# bordures (gazon : bordure béton surélevée) ou caniveau (chaussée) sur le(s) côté(s) extérieur(s)
	var edge_cols: Array = []
	for i in kinds.size(): edge_cols.append(CURB if grassy[i] else GUTTER)
	for side in [-1.0, 1.0]:
		if o != 0.0 and signf(o) != side: continue
		ribbon(g, pts, nrm, 0.22, BED_TOP_M + 0.035, edge_cols, o + side * 1.64)
		_skirt(g, pts, nrm, o + side * 1.75, side, kinds, grassy, no_skirt, ground)
	_slab_joints(g, pts, nrm, o, kinds, grassy, setts)
	var curv := curvature(pts)
	var hw := gauge_m * 0.5
	for side in [-1.0, 1.0]:
		_rail(g, pts, nrm, o + side * hw, side, grassy, curv, bed)
	_switch_ends(g, pts, nrm, o, gauge_m, grassy)

## Talus de plateforme (« jupe ») : ferme la fente entre le bord de la plateforme et le terrain. `ground` (Vector3 ->
## altitude du sol, LineView.ground_at) : talus de terre/ballast de pente 2/3 jusqu'au sol quand la plateforme est à moins
## de SKIRT_DEPTH m au-dessus, mur de soutènement vertical (béton) jusqu'au sol au-delà (remblai d'approche de pont,
## relief plus bas) ; sans `ground` : talus fixe de SKIRT_DEPTH m. Enterré sans effet quand le sol est au niveau.
const SKIRT_DEPTH := 2.2
const SKIRT := Color("#8f8372")
const WALL := Color("#a8a397")
static func skirt_drop(bed_top: float, ground_h: float) -> float:
	return clampf(bed_top - ground_h + 0.4, 0.45, 30.0)   # pied enterré de 0,4 m (sol irrégulier)

static func _skirt(g, pts: Array[Vector3], nrm: PackedVector3Array, off: float, side: float, kinds: Array, grassy: Array, no_skirt: Callable, ground: Callable = Callable()) -> void:
	var top := Vector3(0, BED_TOP_M - 0.005, 0)
	for i in range(pts.size() - 1):
		if no_skirt.is_valid() and no_skirt.call((pts[i] + pts[i + 1]) * 0.5): continue   # pont, tunnel
		var a := pts[i] + nrm[i] * off + top; var b := pts[i + 1] + nrm[i + 1] * off + top
		var da := SKIRT_DEPTH; var db := SKIRT_DEPTH
		if ground.is_valid():
			da = skirt_drop(a.y, ground.call(a + nrm[i] * side * 0.6))
			db = skirt_drop(b.y, ground.call(b + nrm[i + 1] * side * 0.6))
		var col: Color = SKIRT if grassy[i] else GUTTER.darkened(0.1)
		if maxf(da, db) > SKIRT_DEPTH:   # mur de soutènement vertical
			var a2 := a + Vector3(0, -da, 0); var b2 := b + Vector3(0, -db, 0)
			g.quad(a, b, b2, a2, WALL); g.quad(b, a, a2, b2, WALL)
		else:
			var a2 := a + nrm[i] * side * da * 1.5 + Vector3(0, -da, 0); var b2 := b + nrm[i + 1] * side * db * 1.5 + Vector3(0, -db, 0)
			g.quad(a, b, b2, a2, col); g.quad(b, a, a2, b2, col)   # deux faces (vue de dessus et de sous un pont)

## Courbure signée par sommet (1/m, > 0 : virage vers la droite de la voie), lissée sur ± 4 m.
static func curvature(pts: Array[Vector3]) -> PackedFloat32Array:
	var n := pts.size()
	var k := PackedFloat32Array(); k.resize(n)
	for i in range(1, n - 1):
		var a := Vector2(pts[i].x - pts[i - 1].x, pts[i].z - pts[i - 1].z)
		var b := Vector2(pts[i + 1].x - pts[i].x, pts[i + 1].z - pts[i].z)
		var l := (a.length() + b.length()) * 0.5
		if l > 0.001: k[i] = a.angle_to(b) / l
	var out := PackedFloat32Array(); out.resize(n)
	var s := PackedFloat32Array(); s.resize(n)
	for i in range(1, n): s[i] = s[i - 1] + pts[i].distance_to(pts[i - 1])
	var j0 := 0
	for i in n:
		while s[j0] < s[i] - 4.0: j0 += 1
		var acc := 0.0; var w := 0.0; var j := j0
		while j < n and s[j] <= s[i] + 4.0:
			acc += k[j]; w += 1.0; j += 1
		out[i] = acc / maxf(w, 1.0)
	return out

## Rail à gorge à l'abscisse latérale `off` (côté `side` : -1 gauche, +1 droite ; la gorge est côté intérieur).
static func _rail(g, pts: Array[Vector3], nrm: PackedVector3Array, off: float, side: float, grassy: Array, curv: PackedFloat32Array, bed: Array) -> void:
	var n := pts.size() - 1
	var top: Array = []; var groove: Array = []; var filler: Array = []; var guard: Array = []
	for i in n:
		top.append(RAIL_TOP); groove.append(GROOVE)
		var bc: Color = bed[i]
		filler.append(SLEEPER if grassy[i] else Color(bc.r, bc.g, bc.b).darkened(0.38))
	# longrine béton (gazon) ou joint bitumineux (chaussée) sous/autour du rail
	_ribbon_w(g, pts, nrm, func(i): return 0.30 if grassy[i] else 0.18, func(i): return BED_TOP_M + (0.012 if grassy[i] else 0.006), filler, off)
	_ribbon_y(g, pts, nrm, 0.072, func(i): return RAIL_TOP_M if grassy[i] else EMBED_TOP_M, top, off + side * 0.012)
	_ribbon_y(g, pts, nrm, 0.036, func(i): return (RAIL_TOP_M if grassy[i] else EMBED_TOP_M) - 0.001, groove, off - side * 0.042)
	# flancs du champignon au-dessus du gazon (silhouette nette)
	for i in n:
		if not grassy[i]: continue
		for e in [-1.0, 1.0]:
			var x: float = off + side * 0.012 + e * 0.036
			var a: Vector3 = pts[i] + nrm[i] * x; var b: Vector3 = pts[i + 1] + nrm[i + 1] * x
			g.quad(a + Vector3(0, RAIL_TOP_M, 0), b + Vector3(0, RAIL_TOP_M, 0), b + Vector3(0, BED_TOP_M + 0.012, 0), a + Vector3(0, BED_TOP_M + 0.012, 0), RAIL_SIDE)
	# contre-rail : rail intérieur des courbes serrées (le centre de courbure est du côté du rail)
	for i in n:
		var k := (curv[i] + curv[i + 1]) * 0.5
		if absf(k) < 1.0 / GUARD_R_M or signf(k) != side: continue
		var y := (RAIL_TOP_M if grassy[i] else EMBED_TOP_M) + 0.012
		var x: float = off - side * 0.085
		var a: Vector3 = pts[i] + nrm[i] * x; var b: Vector3 = pts[i + 1] + nrm[i + 1] * x
		var w := nrm[i] * 0.025; var w2 := nrm[i + 1] * 0.025
		g.quad(a - w + Vector3(0, y, 0), a + w + Vector3(0, y, 0), b + w2 + Vector3(0, y, 0), b - w2 + Vector3(0, y, 0), BLADE.darkened(0.12))
		g.quad(a - w * side + Vector3(0, y, 0), b - w2 * side + Vector3(0, y, 0), b - w2 * side + Vector3(0, y - 0.03, 0), a - w * side + Vector3(0, y - 0.03, 0), RAIL_SIDE)

## Ruban à hauteur variable par segment (y_fn : index de segment -> hauteur).
static func _ribbon_y(g, pts: Array[Vector3], nrm: PackedVector3Array, w: float, y_fn: Callable, cols: Array, offset: float) -> void:
	var hw := w * 0.5
	for i in range(pts.size() - 1):
		var up := Vector3(0, float(y_fn.call(i)), 0)
		var a := pts[i] + nrm[i] * offset + up; var b := pts[i + 1] + nrm[i + 1] * offset + up
		g.quad(a - nrm[i] * hw, a + nrm[i] * hw, b + nrm[i + 1] * hw, b - nrm[i + 1] * hw, cols[i])

## Ruban à largeur et hauteur variables par segment.
static func _ribbon_w(g, pts: Array[Vector3], nrm: PackedVector3Array, w_fn: Callable, y_fn: Callable, cols: Array, offset: float) -> void:
	for i in range(pts.size() - 1):
		var hw := float(w_fn.call(i)) * 0.5
		var up := Vector3(0, float(y_fn.call(i)), 0)
		var a := pts[i] + nrm[i] * offset + up; var b := pts[i + 1] + nrm[i + 1] * offset + up
		g.quad(a - nrm[i] * hw, a + nrm[i] * hw, b + nrm[i + 1] * hw, b - nrm[i + 1] * hw, cols[i])

## Joints transversaux de la dalle en béton désactivé (tous les SLAB_M), nets à toute distance.
static func _slab_joints(g, pts: Array[Vector3], nrm: PackedVector3Array, o: float, kinds: Array, grassy: Array, setts: bool) -> void:
	var acc := 0.0; var next := SLAB_M
	for i in range(pts.size() - 1):
		var L := pts[i].distance_to(pts[i + 1])
		var concrete: bool = int(kinds[i]) != BED_ROAD and not grassy[i] and not (setts and int(kinds[i]) == BED_PAVED)
		while next <= acc + L:
			if concrete:
				var t := (next - acc) / maxf(L, 0.001)
				var p := pts[i].lerp(pts[i + 1], t); var nn := nrm[i].lerp(nrm[i + 1], t)
				var d := (pts[i + 1] - pts[i]).normalized() * 0.018
				var c := p + nn * o + Vector3(0, BED_TOP_M + 0.004, 0)
				g.quad(c - nn * 1.6 - d, c + nn * 1.6 - d, c + nn * 1.6 + d, c - nn * 1.6 + d, Color("#7d786f"))
			next += SLAB_M
		acc += L

## Appareils de voie : extrémités d'arêtes construites dans la même passe (même image) et confondues, de caps voisins.
static var _sw_frame := -1
static var _sw_ends: Dictionary = {}   # Vector2i (cellule 0,5 m) -> Array de [Vector2 cap sortant, Array[Vector3] axe depuis l'extrémité]

static func _switch_ends(g, pts: Array[Vector3], nrm: PackedVector3Array, o: float, gauge_m: float, grassy: Array) -> void:
	var frame := Engine.get_process_frames()
	if frame != _sw_frame:
		_sw_frame = frame; _sw_ends.clear()
	var center: Array[Vector3] = []
	for i in pts.size(): center.append(pts[i] + nrm[i] * o)
	var embed: bool = not grassy[0]
	for end in [0, 1]:
		var line: Array[Vector3] = []
		var acc := 0.0
		var idx := range(center.size()) if end == 0 else range(center.size() - 1, -1, -1)
		for i in idx:
			if not line.is_empty(): acc += line[-1].distance_to(center[i])
			line.append(center[i])
			if acc > 30.0: break
		if line.size() < 2: continue
		var u := Vector2(line[1].x - line[0].x, line[1].z - line[0].z).normalized()
		var key := Vector2i(roundi(line[0].x * 2.0), roundi(line[0].z * 2.0))
		for dx in [-1, 0, 1]:
			for dz in [-1, 0, 1]:
				for other in _sw_ends.get(key + Vector2i(dx, dz), []):
					var ol: Array[Vector3] = other[1]
					if ol[0].distance_to(line[0]) > 0.4: continue
					var ang := absf(u.angle_to(other[0]))
					if ang > deg_to_rad(0.3) and ang < deg_to_rad(30.0):
						draw_switch(g, line, ol, gauge_m, embed)
		if not _sw_ends.has(key): _sw_ends[key] = []
		_sw_ends[key].append([u, line])

## Point d'une polyligne à l'abscisse s, et repère (tangente, normale droite).
static func _at(line: Array[Vector3], s: float) -> Array:
	var acc := 0.0
	for i in range(line.size() - 1):
		var L := line[i].distance_to(line[i + 1])
		if acc + L >= s or i == line.size() - 2:
			var t := clampf((s - acc) / maxf(L, 0.001), 0.0, 1.0)
			var d := (line[i + 1] - line[i]); d.y = 0.0; d = d.normalized()
			return [line[i].lerp(line[i + 1], t), d, Vector3(-d.z, 0, d.x)]
		acc += L
	return [line[-1], Vector3.FORWARD, Vector3.RIGHT]

## Aiguillage entre les voies `a` et `b` (axes depuis la pointe) : aiguilles effilées polies le long des rails,
## joints au talon et au cœur, cœur de croisement, moteur d'aiguillage côté extérieur.
static func draw_switch(g, a: Array[Vector3], b: Array[Vector3], gauge_m: float, embed: bool) -> void:
	var hw := gauge_m * 0.5
	var y := (EMBED_TOP_M if embed else RAIL_TOP_M) + 0.006
	const BLADE_M := 7.0
	var steps := 14
	for line in [a, b]:
		for side in [-1.0, 1.0]:
			for k in steps:
				var s0 := BLADE_M * k / steps; var s1 := BLADE_M * (k + 1) / steps
				var f0 := _at(line, s0); var f1 := _at(line, s1)
				var w0 := lerpf(0.012, 0.05, float(k) / steps); var w1 := lerpf(0.012, 0.05, float(k + 1) / steps)
				var x0: Vector3 = f0[2] * (side * (hw - 0.07) ); var x1: Vector3 = f1[2] * (side * (hw - 0.07))
				var c0: Vector3 = f0[0] + x0 + Vector3(0, y, 0); var c1: Vector3 = f1[0] + x1 + Vector3(0, y, 0)
				g.quad(c0 - f0[2] * w0, c0 + f0[2] * w0, c1 + f1[2] * w1, c1 - f1[2] * w1, BLADE)
			# joint (coupon isolant) au talon de l'aiguille
			var fh := _at(line, BLADE_M)
			var p: Vector3 = fh[0] + fh[2] * (side * hw) + Vector3(0, y + 0.001, 0)
			g.quad(p - fh[2] * 0.06 - fh[1] * 0.02, p + fh[2] * 0.06 - fh[1] * 0.02, p + fh[2] * 0.06 + fh[1] * 0.02, p - fh[2] * 0.06 + fh[1] * 0.02, JOINT)
	# cœur : là où les rails intérieurs se croisent (écart des axes = écartement)
	var s := 4.0; var la := _length(a); var hit := -1.0
	while s < la:
		var fa := _at(a, s)
		var q := _closest(b, fa[0])
		if (fa[0] as Vector3).distance_to(q) >= gauge_m:
			hit = s; break
		s += 0.5
	if hit > 0.0:
		var fa := _at(a, hit); var fb := _at(b, hit)
		var c: Vector3 = ((fa[0] as Vector3) + _closest(b, fa[0])) * 0.5 + Vector3(0, y - 0.004, 0)
		var d: Vector3 = ((fa[1] as Vector3) + (fb[1] as Vector3)).normalized(); var nn := Vector3(-d.z, 0, d.x)
		g.quad(c - nn * 0.22 - d * 1.4, c + nn * 0.22 - d * 1.4, c + nn * 0.22 + d * 1.6, c - nn * 0.22 + d * 1.6, Color("#55585c"))
		g.quad(c - nn * 0.03 - d * 1.2 + Vector3(0, 0.002, 0), c + nn * 0.03 - d * 1.2 + Vector3(0, 0.002, 0), c + nn * 0.03 + d * 1.4 + Vector3(0, 0.002, 0), c - nn * 0.03 + d * 1.4 + Vector3(0, 0.002, 0), BLADE)
		for e in [-1.6, 1.8]:
			var j: Vector3 = c + d * e + Vector3(0, 0.003, 0)
			g.quad(j - nn * 0.3 - d * 0.02, j + nn * 0.3 - d * 0.02, j + nn * 0.3 + d * 0.02, j - nn * 0.3 + d * 0.02, JOINT)
	# moteur d'aiguillage (boîtier) à l'extérieur, côté opposé à la déviation
	var f := _at(a, 0.8); var fb2 := _at(b, 6.0)
	var away := -1.0 if ((fb2[0] as Vector3) - (f[0] as Vector3)).dot(f[2]) > 0.0 else 1.0
	if g.has_method("box_basis"):
		var bas := Basis.looking_at(f[1], Vector3.UP)
		g.box_basis(f[0] + f[2] * (away * (hw + 0.55)) + Vector3(0, BED_TOP_M + 0.08, 0), Vector3(0.38, 0.16, 0.9), bas, Color("#5f6b63"))

static func _length(line: Array[Vector3]) -> float:
	var L := 0.0
	for i in range(line.size() - 1): L += line[i].distance_to(line[i + 1])
	return L

static func _closest(line: Array[Vector3], p: Vector3) -> Vector3:
	var best := line[0]; var bd := INF
	for i in range(line.size() - 1):
		var q := Geometry3D.get_closest_point_to_segment(p, line[i], line[i + 1])
		var d := q.distance_squared_to(p)
		if d < bd: bd = d; best = q
	return best

## Zones interdites au décor : segments (repère libre) avec distance minimale, index spatial à cellules de 16 m.
class KeepOut:
	const CELL := 16.0
	var cells: Dictionary = {}   # Vector2i -> Array de [a, b, clearance]
	var max_clear := 0.0

	func add_segment(a: Vector2, b: Vector2, clearance: float) -> void:
		max_clear = maxf(max_clear, clearance)
		var item := [a, b, clearance]
		var lo := Vector2(minf(a.x, b.x), minf(a.y, b.y)) - Vector2.ONE * clearance
		var hi := Vector2(maxf(a.x, b.x), maxf(a.y, b.y)) + Vector2.ONE * clearance
		for cx in range(floori(lo.x / CELL), floori(hi.x / CELL) + 1):
			for cz in range(floori(lo.y / CELL), floori(hi.y / CELL) + 1):
				var k := Vector2i(cx, cz)
				if not cells.has(k): cells[k] = []
				cells[k].append(item)

	func add_polyline(pts: PackedVector2Array, clearance: float) -> void:
		for i in range(pts.size() - 1):
			var n := maxi(1, ceili(pts[i].distance_to(pts[i + 1]) / CELL))
			for k in n:
				add_segment(pts[i].lerp(pts[i + 1], float(k) / n), pts[i].lerp(pts[i + 1], float(k + 1) / n), clearance)

	## Vrai si p est à moins de (clearance + extra) d'un segment.
	func blocked(p: Vector2, extra: float = 0.0) -> bool:
		var r := extra
		for cx in range(floori((p.x - r) / CELL), floori((p.x + r) / CELL) + 1):
			for cz in range(floori((p.y - r) / CELL), floori((p.y + r) / CELL) + 1):
				for it in cells.get(Vector2i(cx, cz), []):
					var q := Geometry2D.get_closest_point_to_segment(p, it[0], it[1])
					if q.distance_to(p) < float(it[2]) + extra: return true
		return false

static var _net_keepout: Dictionary = {}

## Zone interdite des voies d'un réseau (axe ± clearance), mise en cache par réseau.
static func keepout_for(net: NetworkLoader, clearance: float = 4.2) -> KeepOut:
	var key := net.get_instance_id()
	if not _net_keepout.has(key):
		var ko := KeepOut.new()
		for id in net.edge_info:
			var pts: PackedVector2Array = net.edge_info[id].pts
			ko.add_polyline(pts, clearance)
		_net_keepout.clear()
		_net_keepout[key] = ko
	return _net_keepout[key]
