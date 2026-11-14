class_name RoadView
extends RefCounted
## Voirie et sol d'une tuile : maillage unique (TerrainView.Tile, tools/import/terrain_mesh.py + road_mesh.py).
##
## ENCODAGE DES SOMMETS (pour toon_building.gdshader) :
## - UV2.x : identifiant de matériau du shader (partie entière : 2 enrobé, 3 dallage, 4 sol végétal, 8 uni, voir
##   toon_building.gdshader) + identifiant de surface de voirie / 1024 (partie fractionnaire, MAT ci-dessous :
##   matériau précis, par ex. chaussée, trottoir, plateforme gazon, marquage) ;
## - UV2.y : hauteur au-dessus du terrain (m) : 0 pour le sol et la chaussée (drapés exactement), BORDURE pour le
##   dessus des trottoirs et îlots surélevés, DECAL pour les marquages (décalage de profondeur de cel_layer_clip) ;
## - UV : coordonnées métriques (repère de la ville, m) ; COLOR.rgb : teinte apparente ; COLOR.a : ancien code de
##   matériau (0,28 enrobé, 0,29 dallage, 0,30 végétal, 1 uni), conservé pour les shaders sans UV2.
## Les faces verticales des bordures (BORDURE = 15 cm) sont générées le long des arêtes marquées par l'import entre une
## surface surélevée (trottoir, îlot) et une surface au niveau de la chaussée. Les marquages (axes discontinus,
## rives, passages piétons, lignes d'arrêt) sont des décalques posés sur le maillage (altitude exacte du triangle).

const BORDURE := 0.15
const DECAL := 0.03
# identifiants de surface (tools/import/road_mesh.py MAT)
const GROUND := 0
const ASPHALT := 1
const SIDEWALK := 2
const GRASS := 3
const FOREST := 4
const SPORT := 5
const CEMETERY := 6
const WATERBED := 7
const TRAM_GRASS := 8
const TRAM_ASPHALT := 9
const TRAM_PAVED := 10
const PAINT := 11
const ISLAND := 12
const ISLAND_GRASS := 13
const PATH := 14
const BALLAST := 15
const RAIL := 16
const LAWN := 17
const ASPHALT_MAJOR := 18
const CURB := 19
const RAISED := [SIDEWALK, ISLAND, ISLAND_GRASS]
# identifiants de matériau du shader (toon_building.gdshader)
const M_ASPHALT := 2.0
const M_PAVING := 3.0
const M_VEG := 4.0
const M_PLAIN := 8.0

## Teintes (apparentes) et matériau du shader par surface.
static func palette(style: Dictionary) -> Array:
	var ground := Color.from_string(str(style.get("ground", "#8b8986")), Color.GRAY)
	var paving := Color.from_string(str(style.get("paving", "#b9b3a8")), Color.GRAY)
	var p: Array = []
	p.resize(CURB + 1)
	p[GROUND] = [ground, M_PLAIN]
	p[ASPHALT] = [Color("#4c5054"), M_ASPHALT]
	p[ASPHALT_MAJOR] = [Color("#5f6368"), M_ASPHALT]   # grands axes : enrobé clair (lisibles en vue aérienne)
	p[SIDEWALK] = [paving, M_PAVING]
	p[GRASS] = [Color("#71824c"), M_VEG]
	p[LAWN] = [Color("#71824c"), M_VEG]
	p[FOREST] = [Color("#4d5f3d"), M_VEG]
	p[SPORT] = [Color("#7b8d4f"), M_VEG]
	p[CEMETERY] = [Color("#7c8669"), M_VEG]
	p[WATERBED] = [Color("#4f5346"), M_PLAIN]
	p[TRAM_GRASS] = [TrackView.GRASS.darkened(0.08), M_VEG]
	p[TRAM_ASPHALT] = [TrackView.ASPHALT, M_ASPHALT]
	p[TRAM_PAVED] = [paving.darkened(0.06), M_PAVING]
	p[PAINT] = [Color("#e6e5df"), M_PLAIN]
	p[ISLAND] = [paving.darkened(0.04), M_PAVING]
	p[ISLAND_GRASS] = [Color("#6f8249"), M_VEG]
	p[PATH] = [Color("#b8a988"), M_PLAIN]
	p[BALLAST] = [Color("#7f776c"), M_PLAIN]
	p[RAIL] = [Color("#9a9ea3"), M_PLAIN]
	p[CURB] = [paving.darkened(0.18), M_PAVING]
	return p

static func _legacy_a(m: float) -> float:
	if m == M_ASPHALT: return 0.28
	if m == M_PAVING: return 0.29
	if m == M_VEG: return 0.30
	return 1.0

class _Out:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var origin := Vector2.ZERO
	var cut: TrackView.KeepOut
	var openings := {}

	func emit_triangle(p: Vector3, q: Vector3, r: Vector3, nrm: Vector3, col: Color, id: Vector2) -> void:
		var fn := (r - p).cross(q - p)
		if fn.length_squared() < 1e-12: return
		if fn.dot(nrm) < 0.0:
			var temp := q; q = r; r = temp
		add(p, nrm, col, id); add(q, nrm, col, id); add(r, nrm, col, id)

	func triangle(a: Vector3, b: Vector3, d: Vector3, nrm: Vector3, col: Color, id: Vector2) -> void:
		if cut == null or cut.cells.is_empty():
			emit_triangle(a, b, d, nrm, col, id)
			return
		var polygons: Array = [PackedVector3Array([a, b, d])]
		if cut != null and not cut.cells.is_empty():
			var lo := Vector2(minf(a.x, minf(b.x, d.x)), minf(a.z, minf(b.z, d.z))) + origin
			var hi := Vector2(maxf(a.x, maxf(b.x, d.x)), maxf(a.z, maxf(b.z, d.z))) + origin
			var visited := {}
			for x in range(floori(lo.x / cut.CELL), floori(hi.x / cut.CELL) + 1):
				for z in range(floori(lo.y / cut.CELL), floori(hi.y / cut.CELL) + 1):
					for segment in cut.cells.get(Vector2i(x, z), []):
						if visited.has(segment): continue
						visited[segment] = true
						var bounds := Rect2(segment[0], Vector2.ZERO).expand(segment[1]).grow(float(segment[2]) + 0.04)
						if not bounds.intersects(Rect2(lo, hi - lo), true): continue
						if not openings.has(segment): openings[segment] = TerrainClip.capsule(segment[0] - origin, segment[1] - origin, segment[2])
						var next: Array = []
						for polygon in polygons: next.append_array(TerrainClip.subtract(polygon, openings[segment]))
						polygons = next
						if polygons.is_empty(): return
		for polygon: PackedVector3Array in polygons:
			for j in range(1, polygon.size() - 1):
				emit_triangle(polygon[0], polygon[j], polygon[j + 1], nrm, col, id)

	func add(p: Vector3, nrm: Vector3, col: Color, id: Vector2) -> void:
		v.append(p); n.append(nrm); c.append(col); uv.append(Vector2(p.x + origin.x, p.z + origin.y)); uv2.append(id)

	func mesh() -> ArrayMesh:
		var arr := []; arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = v; arr[Mesh.ARRAY_NORMAL] = n; arr[Mesh.ARRAY_COLOR] = c
		arr[Mesh.ARRAY_TEX_UV] = uv; arr[Mesh.ARRAY_TEX_UV2] = uv2
		var m := ArrayMesh.new()
		if v.size() > 0: m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		return m

## Maillage du sol d'une tuile (repère tuile). `cut` : zones sans sol (portails de tunnel), repère de la ville.
static func build(tv: TerrainView, t: TerrainView.Tile, k: Vector2i, style: Dictionary, cut: TrackView.KeepOut) -> ArrayMesh:
	var pal := palette(style)
	var out := _Out.new()
	var origin := Vector2(k.x, k.y) * tv.tile_m
	out.origin = origin
	out.cut = cut
	var cols: Array[Color] = []; var ids: Array[Vector2] = []
	for i in pal.size():
		var e: Array = pal[i]
		var col: Color = e[0]; col.a = _legacy_a(e[1])
		cols.append(col); ids.append(Vector2(float(e[1]) + float(i) / 1024.0, 0.0))
	var nt := t.mat.size()
	for i in nt:
		var code := t.mat[i]
		var m := code & 31
		if m >= CURB: m = GROUND
		var a := t.pos[t.tri[i * 3]]; var b := t.pos[t.tri[i * 3 + 1]]; var c := t.pos[t.tri[i * 3 + 2]]
		var raised := m in RAISED
		var lift := BORDURE if raised else 0.0
		var up := Vector3(0, lift, 0)
		var fn := (c - a).cross(b - a)
		if fn.y < 0.0: fn = -fn
		fn = fn.normalized()
		var id := ids[m]
		if raised: id.y = BORDURE
		out.triangle(a + up, b + up, c + up, fn, cols[m], id)
		var curb := code >> 5
		if raised and curb != 0:
			var corners := [a, b, c]
			var ctr := (a + b + c) / 3.0
			for e in 3:
				if curb & (1 << e) == 0: continue
				var p: Vector3 = corners[e]; var q: Vector3 = corners[(e + 1) % 3]
				var nrm := Vector3(q.z - p.z, 0, p.x - q.x).normalized()
				if nrm.dot(Vector3(p.x - ctr.x, 0, p.z - ctr.z)) < 0.0: nrm = -nrm   # vers la chaussée
				var cid := ids[CURB]
				out.triangle(p, q, q + up, nrm, cols[CURB], cid)
				out.triangle(p, q + up, p + up, nrm, cols[CURB], cid)
	_decals(out, tv, t, k, cols[PAINT], Vector2(M_PLAIN + float(PAINT) / 1024.0, DECAL))
	return out.mesh()

## Quadrilatère de marquage découpé en morceaux d'au plus `step` m, posé sur le maillage (+DECAL).
static func _strip(out: _Out, tv: TerrainView, t: TerrainView.Tile, a: Vector2, b: Vector2, half: Vector2, col: Color, id: Vector2, step: float = 1.5) -> void:
	var n := maxi(1, ceili(a.distance_to(b) / step))
	var prev_l := Vector3.ZERO; var prev_r := Vector3.ZERO
	for j in n + 1:
		var p := a.lerp(b, float(j) / n)
		var l := p - half; var r := p + half
		var hl := tv.tile_height(t, l.x, l.y); var hr := tv.tile_height(t, r.x, r.y)
		if is_nan(hl) or is_nan(hr):
			var other := tv.height(l.x + out.origin.x, l.y + out.origin.y)
			hl = other if not is_nan(other) else 0.0
			other = tv.height(r.x + out.origin.x, r.y + out.origin.y)
			hr = other if not is_nan(other) else hl
		var L := Vector3(l.x, hl + DECAL, l.y); var Rr := Vector3(r.x, hr + DECAL, r.y)
		if j > 0:
			out.triangle(prev_l, prev_r, Rr, Vector3.UP, col, id)
			out.triangle(prev_l, Rr, L, Vector3.UP, col, id)
		prev_l = L; prev_r = Rr

static func _decals(out: _Out, tv: TerrainView, t: TerrainView.Tile, k: Vector2i, col: Color, id: Vector2) -> void:
	for ln in t.lines:
		var pl: PackedVector2Array = ln[1]
		var dashed: bool = int(ln[0]) == 0
		var hw := 0.07 if dashed else 0.08
		var s := float(ln[2])            # abscisse du tronçon BD TOPO au premier point
		for i in pl.size() - 1:
			var a := pl[i]; var b := pl[i + 1]
			var L := a.distance_to(b)
			if L < 0.01: continue
			var d := (b - a) / L
			var half := Vector2(-d.y, d.x) * hw
			if not dashed:
				_strip(out, tv, t, a, b, half, col, id, 2.0)
			else:   # tirets de 3 m tous les 10 m, à partir de 2 m (phase commune aux tuiles voisines)
				var u := 0.0
				while u < L:
					var ph := fposmod(s + u - 2.0, 10.0)
					if ph < 3.0:
						var e := minf(L, u + maxf(3.0 - ph, 0.05))
						_strip(out, tv, t, a + d * u, a + d * e, half, col, id)
						u = e
					else:
						u += maxf(10.0 - ph, 0.05)
			s += L
	for r in t.rects:
		var c: Vector2 = r[1]; var d: Vector2 = r[2]; var w: float = r[3]; var l: float = r[4]
		var nrm := Vector2(-d.y, d.x)
		if int(r[0]) == 0:   # passage piéton : bandes de 0,5 m parallèles à la chaussée, espacées de 0,5 m
			var off := -w * 0.5 + 0.25
			while off <= w * 0.5 - 0.25:
				var m := c + nrm * off
				_strip(out, tv, t, m - d * l * 0.5, m + d * l * 0.5, nrm * 0.25, col, id)
				off += 1.0
		else:                # ligne d'arrêt
			_strip(out, tv, t, c - nrm * w * 0.5, c + nrm * w * 0.5, d * l * 0.5, col, id, 2.0)
