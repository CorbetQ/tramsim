class_name TrackView
extends RefCounted
## Plateforme de tram : rubans à jonctions en onglet (sommets partagés), nature réelle de la plateforme
## (gazon / enrobé / pavés-béton, analysée sur les orthophotos IGN, voir tools/import/ign_scene.py)
## et zones interdites au décor (KeepOut : voies, quais).

const BED_TOP_M := 0.09
const RAIL_TOP_M := 0.17
const APS_TOP_M := BED_TOP_M + 0.015
const BED_UNKNOWN := 0
const BED_GRASS := 1
const BED_ROAD := 2
const BED_PAVED := 3
const MAX_SEG := 8.0          # m : subdivision pour suivre les changements de nature
const GRASS := Color("#79a35a")
const ASPHALT := Color("#5f6268")
const SLEEPER := Color("#b3b1aa")
const RAIL := Color("#8f959c", 0.9)
const RAIL_TOP := Color("#c9ccd0", 0.9)

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

## Plateforme d'une voie (axe `pts`, décalage `o` vers la droite) : lit coloré par tronçon (nature lissée), bordures
## de plateforme côté extérieur (gazon) ou caniveau (enrobé, pavés), longrines si gazon, rails noyés sinon.
static func build(g, axis: Array, o: float, nature_fn: Callable, fallback: Color, paved: Color, gauge_m: float = 1.435) -> void:
	var pts := densify(axis)
	if pts.size() < 2: return
	var nrm := miter_normals(pts)
	var raw: Array = []; var lens: Array = []
	for i in range(pts.size() - 1):
		raw.append(nature_fn.call((pts[i] + pts[i + 1]) * 0.5))
		lens.append(pts[i].distance_to(pts[i + 1]))
	var kinds := smooth_kinds(raw, lens)
	var bed: Array = []
	for k in kinds:
		match int(k):
			BED_GRASS: bed.append(GRASS)
			BED_ROAD: bed.append(ASPHALT)
			BED_PAVED: bed.append(paved)
			_: bed.append(fallback)
	ribbon(g, pts, nrm, 3.5, BED_TOP_M, bed, o)
	# bordures (gazon : bordure béton surélevée) ou caniveau (enrobé, pavés) sur le(s) côté(s) extérieur(s)
	var edge_cols: Array = []
	for i in kinds.size():
		var grassy: bool = int(kinds[i]) == BED_GRASS or (int(kinds[i]) == BED_UNKNOWN and fallback == GRASS)
		edge_cols.append(CURB if grassy else GUTTER)
	for side in [-1.0, 1.0]:
		if o != 0.0 and signf(o) != side: continue
		ribbon(g, pts, nrm, 0.22, BED_TOP_M + 0.035, edge_cols, o + side * 1.64)
	var sl: Array = []
	for i in kinds.size():
		var grassy: bool = int(kinds[i]) == BED_GRASS or (int(kinds[i]) == BED_UNKNOWN and fallback == GRASS)
		sl.append(SLEEPER if grassy else Color(bed[i]).darkened(0.12))
	var rails: Array = []
	rails.resize(kinds.size()); rails.fill(RAIL)
	for off in [-gauge_m * 0.5, gauge_m * 0.5]:
		ribbon(g, pts, nrm, 0.42, 0.11, sl, o + off)
		ribbon(g, pts, nrm, 0.08, RAIL_TOP_M, rails, o + off)

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
