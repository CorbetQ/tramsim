class_name TerrainView
extends Node3D
## Sol continu d'une ville (data/scenes/<ville>_ground.bin, format TGR1, tools/import/terrain_mesh.py).
##
## Une triangulation contrainte par tuile de 400 m porte à la fois le relief et la voirie (chaussées, carrefours,
## trottoirs, îlots, plateforme tram, eau, végétation) : la voirie est drapée exactement sur le terrain, sans couche
## superposée. Les sommets des bords de tuile sont communs aux tuiles voisines (raccords sans déchirure).
## - height(x, z) : altitude exacte du maillage (barycentrique sur le triangle, index de cellules de 8 m, tuiles
##   décodées gardées dans un petit cache) ;
## - tile(k) : tuile décodée pour RoadView.build ;
## - couronne lointaine (grille de 100 m sur l'emprise + 8 km) : maillage de 8 km autour de la caméra (pas de 250 m,
##   reconstruit tous les FAR_REBUILD m). Au-delà de FAR_NEAR m, un shader rapproche les sommets de la caméra le
##   long de la ligne de visée (angle conservé) pour rester dans son plan lointain (1,6 km) : silhouette du relief
##   régional jusqu'à l'horizon, sans parallaxe faussée.
## Coordonnées : repère de la ville (CityScene), altitudes relatives à alt0.

const Q := 64.0
const CELL := 8.0
const MAX_CACHE := 40
const FAR_RADIUS := 8000.0
const FAR_STEP := 200.0       # divise exactement les tuiles de 400 m
const FAR_NEAR := 1150.0       # m : au-delà, rapprochement radial vers [FAR_NEAR, FAR_NEAR + 380 m]
const FAR_REBUILD := 1000.0

class Tile:
	var pos := PackedVector3Array()     # repère tuile (y : altitude relative à alt0)
	var tri := PackedInt32Array()       # 3 indices par triangle (a < b < c, orientation à recalculer)
	var mat := PackedByteArray()        # matériau (bits 0-4) | bordures (bits 5-7)
	var lines: Array = []               # décalques linéaires [type, PackedVector2Array (repère tuile), phase]
	var rects: Array = []               # décalques [type, centre Vector2, direction Vector2, largeur, longueur]
	var cell_start := PackedInt32Array()
	var cell_tris := PackedInt32Array()

var ok := false
var tile_m := 400.0
var min_height := 0.0
var table: Dictionary = {}          # Vector2i -> [offset, taille compressée, taille]
var ymin: Dictionary = {}           # Vector2i -> altitude minimale de la tuile
var keys: Array[Vector2i] = []      # ordre de la table (enregistrements de méta)
var _buf: PackedByteArray
var _wide_height := false
var _cache: Dictionary = {}
var _lru: Array[Vector2i] = []
var _meta := PackedByteArray()
# couronne lointaine
var _far_h := PackedFloat32Array()
var _far_x0 := 0.0
var _far_z0 := 0.0
var _far_step := 100.0
var _far_nx := 0
var _far_nz := 0
var _far_mesh: MeshInstance3D = null
var _far_at := Vector3(INF, INF, INF)
var _far_loaded := 0
var color := Color("#a9ab98")
# occupation du sol réelle (data/scenes/<ville>_land.bin, TLC1, tools/import/landcover.py) : classes par cellule
var land_ok := false
var land_colors: Array[Color] = []
var land_flags := PackedByteArray()
var _land: Array = []               # [détail (25 m), lointain (100 m)] : [x0, z0, pas, nx, nz, PackedByteArray]

static func path_for(c: String) -> String:
	return "res://data/scenes/%s_ground.bin" % c

static func available(c: String) -> bool:
	return FileAccess.file_exists(path_for(c))

func open(c: String) -> bool:
	_buf = CityDataStore.bytes(path_for(c))
	if _buf.size() < 40: return false
	var magic := _buf.slice(0, 4).get_string_from_ascii()
	if magic not in ["TGR1", "TGR2"]: return false
	_wide_height = magic == "TGR2"
	tile_m = _buf.decode_float(8)
	var n := _buf.decode_u32(12)
	var far_off := _buf.decode_u32(16); var far_cs := _buf.decode_u32(20); var far_raw := _buf.decode_u32(24)
	var meta_off := _buf.decode_u32(28); var meta_cs := _buf.decode_u32(32); var meta_raw := _buf.decode_u32(36)
	min_height = INF
	for i in n:
		var o := 40 + i * 24
		var k := Vector2i(_buf.decode_s32(o), _buf.decode_s32(o + 4))
		table[k] = [_buf.decode_u32(o + 8), _buf.decode_u32(o + 12), _buf.decode_u32(o + 16)]
		ymin[k] = _buf.decode_float(o + 20)
		min_height = minf(min_height, ymin[k])
		keys.append(k)
	if n == 0: min_height = 0.0
	_meta = _buf.slice(meta_off, meta_off + meta_cs).decompress(meta_raw, FileAccess.COMPRESSION_BROTLI)
	var far := _buf.slice(far_off, far_off + far_cs).decompress(far_raw, FileAccess.COMPRESSION_BROTLI)
	if far.size() >= 16:
		_far_x0 = far.decode_float(0); _far_z0 = far.decode_float(4); _far_step = far.decode_float(8)
		_far_nx = far.decode_u16(12); _far_nz = far.decode_u16(14)
		_far_h.resize(_far_nx * _far_nz)
		for i in _far_nx * _far_nz: _far_h[i] = far.decode_s16(16 + i * 2) * 0.1
	_load_land(c)
	ok = true
	return true

func _load_land(c: String) -> void:
	var path := "res://data/scenes/%s_land.bin" % c
	if not FileAccess.file_exists(path): return
	var b := CityDataStore.bytes(path)
	if b.size() < 9 or b.slice(0, 4).get_string_from_ascii() != "TLC1": return
	var n := b.decode_u8(8); var o := 9
	for i in n:
		land_colors.append(Color8(b[o], b[o + 1], b[o + 2])); land_flags.append(b[o + 3]); o += 4
	for r in 2:
		if o + 20 > b.size(): return
		var nx := b.decode_u16(o + 12); var nz := b.decode_u16(o + 14); var cs := b.decode_u32(o + 16)
		var raw := b.slice(o + 20, o + 20 + cs).decompress(nx * nz, FileAccess.COMPRESSION_BROTLI)
		if raw.size() != nx * nz: return
		_land.append([b.decode_float(o), b.decode_float(o + 4), b.decode_float(o + 8), nx, nz, raw])
		o += 20 + cs
	land_ok = true

## Classe d'occupation du sol au point (repère de la ville) : raster de détail, sinon lointain ; -1 si inconnue.
func land_class(x: float, z: float, far_only: bool = false) -> int:
	for r in range(1 if far_only else 0, _land.size()):
		var L: Array = _land[r]
		var ix := floori((x - L[0]) / L[2]); var iz := floori((z - L[1]) / L[2])
		if ix < 0 or iz < 0 or ix >= L[3] or iz >= L[4]: continue
		var c: int = L[5][iz * L[3] + ix]
		if c < land_colors.size(): return c
	return -1

## Teinte d'occupation du sol d'une tuile (18 x 18 : cellules de 25 m et une cellule de bord ; A = sillons),
## pour le shader du sol (land_tint). null sans données.
func land_image(k: Vector2i, fallback: Color) -> Image:
	if not land_ok: return null
	var img := Image.create(18, 18, false, Image.FORMAT_RGBA8)
	var ox := k.x * tile_m; var oz := k.y * tile_m
	for iz in 18:
		for ix in 18:
			var c := land_class(ox + (ix - 1) * 25.0 + 12.5, oz + (iz - 1) * 25.0 + 12.5)
			var col: Color = land_colors[c] if c >= 0 else fallback
			col.a = 1.0 if c >= 0 and land_flags[c] & 1 else 0.0
			img.set_pixel(ix, iz, col)
	return img

## Niveaux d'eau et tabliers (format des enregistrements TTR2), dans l'ordre de `keys`.
func meta_bytes() -> PackedByteArray:
	return _meta

func has_tile(k: Vector2i) -> bool:
	return table.has(k)

## Tuile décodée (cache LRU).
func tile(k: Vector2i) -> Tile:
	if _cache.has(k):
		return _cache[k]
	if not table.has(k): return null
	var e: Array = table[k]
	var d := _buf.slice(e[0], e[0] + e[1]).decompress(e[2], FileAccess.COMPRESSION_BROTLI)
	var t := Tile.new()
	var base := d.decode_float(0); var nv := d.decode_u32(4); var nt := d.decode_u32(8)
	var ox := 12; var oz := ox + nv * 2; var oy := oz + nv * 2
	t.pos.resize(nv)
	var x := 0; var z := 0; var y := 0
	for i in nv:
		x += d.decode_s16(ox + i * 2); z += d.decode_s16(oz + i * 2)
		y += d.decode_s32(oy + i * 4) if _wide_height else d.decode_s16(oy + i * 2)
		t.pos[i] = Vector3(x / Q, base + y * 0.01, z / Q)
	var oa := oy + nv * (4 if _wide_height else 2); var ob := oa + nt * 2; var oc := ob + nt * 2
	t.tri.resize(nt * 3)
	var a := 0
	for i in nt:
		a += d.decode_s16(oa + i * 2)
		var b := a + d.decode_s16(ob + i * 2)
		t.tri[i * 3] = a; t.tri[i * 3 + 1] = b; t.tri[i * 3 + 2] = b + d.decode_s16(oc + i * 2)
	var o := oc + nt * 2
	t.mat = d.slice(o, o + nt); o += nt
	if not _cor_pts.is_empty(): _clamp_tracks(t, k)
	if o + 2 <= d.size():
		var nl := d.decode_u16(o); o += 2
		for i in nl:
			var kind := d.decode_u8(o); var np := d.decode_u8(o + 1); var phase := d.decode_u16(o + 2) * 0.1; o += 4
			var pl := PackedVector2Array(); pl.resize(np)
			for j in np:
				pl[j] = Vector2(d.decode_s16(o) * 0.1, d.decode_s16(o + 2) * 0.1); o += 4
			t.lines.append([kind, pl, phase])
		var nr := d.decode_u16(o); o += 2
		for i in nr:
			var ang := d.decode_u16(o + 5) / 65535.0 * TAU
			t.rects.append([d.decode_u8(o), Vector2(d.decode_s16(o + 1) * 0.1, d.decode_s16(o + 3) * 0.1), Vector2(cos(ang), sin(ang)),
				d.decode_u8(o + 7) * 0.1, d.decode_u8(o + 8) * 0.1])
			o += 9
	_cache[k] = t
	_lru.append(k)
	if _lru.size() > MAX_CACHE:
		_cache.erase(_lru.pop_front())
	return t

## Sol des tuiles détaillées sous les voies au sol : sommets à moins de COR_CLAMP_R m d'un axe abaissés à
## COR_CLAMP m sous l'axe du rail jusqu'à 2,6 m (plateforme), puis pente douce de 12 % (rails visibles même là où le profil des voies diffère du sol nivelé à l'import) ;
## écarts de plus de 0,6 m laissés aux découpes de portail (trémies).
const COR_CLAMP_R := 8.0
const COR_CLAMP := 0.03
func _clamp_tracks(t: Tile, k: Vector2i) -> void:
	var ox := k.x * tile_m; var oz := k.y * tile_m
	for i in t.pos.size():
		var v := t.pos[i]
		var x := v.x + ox; var z := v.z + oz
		var lim := INF
		for cx in range(floori((x - COR_CLAMP_R) / 16.0), floori((x + COR_CLAMP_R) / 16.0) + 1):
			for cz in range(floori((z - COR_CLAMP_R) / 16.0), floori((z + COR_CLAMP_R) / 16.0) + 1):
				for q in _cor_pts.get(Vector2i(cx, cz), PackedVector3Array()):
					if absf(q.x - x) > COR_CLAMP_R or absf(q.z - z) > COR_CLAMP_R: continue
					var dq := Vector2(q.x - x, q.z - z).length()
					if dq <= COR_CLAMP_R: lim = minf(lim, q.y - COR_CLAMP + maxf(0.0, dq - 2.6) * 0.12)
		if v.y > lim and v.y - lim < 0.6: t.pos[i].y = lim
	_split_tracks(t, k)

## Triangles étirés de l'import traversés par une voie (sommets loin de l'axe) : points de l'axe (et à ± 1,75 m,
## voies d'une ligne à double voie) insérés à l'intérieur des triangles dont la surface passe au-dessus du rail
## (éventail : les arêtes partagées avec les triangles voisins sont inchangées, pas de fissure).
func _split_tracks(t: Tile, k: Vector2i) -> void:
	var ox := k.x * tile_m; var oz := k.y * tile_m
	var cand := {}   # triangle -> Array de Vector3 (repère tuile, y = plafond)
	_index(t)
	var nc := int(ceil(tile_m / CELL))
	for cx in range(floori(ox / 16.0) - 1, floori((ox + tile_m) / 16.0) + 1):
		for cz in range(floori(oz / 16.0) - 1, floori((oz + tile_m) / 16.0) + 1):
			var ck := Vector2i(cx, cz)
			if not _cor_pts.has(ck): continue
			var pts: PackedVector3Array = _cor_pts[ck]; var dirs: PackedVector2Array = _cor_dirs[ck]
			for j in pts.size():
				var n := Vector2(-dirs[j].y, dirs[j].x)
				for o: float in [0.0, -1.75, 1.75]:
					var px := pts[j].x + n.x * o - ox; var pz := pts[j].z + n.y * o - oz
					if px <= 0.05 or pz <= 0.05 or px >= tile_m - 0.05 or pz >= tile_m - 0.05: continue
					var lim := pts[j].y - COR_CLAMP
					var c := clampi(floori(pz / CELL), 0, nc - 1) * nc + clampi(floori(px / CELL), 0, nc - 1)
					for jj in range(t.cell_start[c], t.cell_start[c + 1]):
						var i := t.cell_tris[jj]
						var a := t.pos[t.tri[i * 3]]; var b := t.pos[t.tri[i * 3 + 1]]; var d := t.pos[t.tri[i * 3 + 2]]
						if not Geometry2D.point_is_inside_triangle(Vector2(px, pz), Vector2(a.x, a.z), Vector2(b.x, b.z), Vector2(d.x, d.z)): continue
						var v0x := b.x - a.x; var v0z := b.z - a.z; var v1x := d.x - a.x; var v1z := d.z - a.z
						var den := v0x * v1z - v1x * v0z
						if absf(den) < 1e-9: break
						var u := ((px - a.x) * v1z - v1x * (pz - a.z)) / den; var w := (v0x * (pz - a.z) - (px - a.x) * v0z) / den
						var h := a.y + (b.y - a.y) * u + (d.y - a.y) * w
						if h > lim + 0.005 and h - lim < 1.0:
							if not cand.has(i): cand[i] = []
							cand[i].append(Vector3(px, lim, pz))
						break
	if cand.is_empty(): return
	for i in cand:
		# sous-triangles du triangle i (indices de sommets), insertion successive des points
		# [a, b, c, bordures] : bit e = bordure sur l'arête (e, e+1) ; les arêtes intérieures n'en ont pas
		var subs: Array = [[t.tri[i * 3], t.tri[i * 3 + 1], t.tri[i * 3 + 2], t.mat[i] >> 5]]
		for q: Vector3 in cand[i]:
			for si in subs.size():
				var s3: Array = subs[si]
				var a := t.pos[s3[0]]; var b := t.pos[s3[1]]; var d := t.pos[s3[2]]
				if not Geometry2D.point_is_inside_triangle(Vector2(q.x, q.z), Vector2(a.x, a.z), Vector2(b.x, b.z), Vector2(d.x, d.z)): continue
				if minf(Vector2(q.x - a.x, q.z - a.z).length(), minf(Vector2(q.x - b.x, q.z - b.z).length(), Vector2(q.x - d.x, q.z - d.z).length())) < 0.3: break
				var vi := t.pos.size(); t.pos.append(q)
				var bits: int = s3[3]
				subs[si] = [s3[0], s3[1], vi, bits & 1]
				subs.append([s3[1], s3[2], vi, (bits >> 1) & 1]); subs.append([s3[2], s3[0], vi, (bits >> 2) & 1])
				break
		var m := t.mat[i] & 31
		t.tri[i * 3] = subs[0][0]; t.tri[i * 3 + 1] = subs[0][1]; t.tri[i * 3 + 2] = subs[0][2]
		t.mat[i] = m | (int(subs[0][3]) << 5)
		for si in range(1, subs.size()):
			t.tri.append_array(PackedInt32Array([subs[si][0], subs[si][1], subs[si][2]])); t.mat.append(m | (int(subs[si][3]) << 5))
	t.cell_start = PackedInt32Array(); t.cell_tris = PackedInt32Array()

func _index(t: Tile) -> void:
	var nc := int(ceil(tile_m / CELL))
	var count := PackedInt32Array(); count.resize(nc * nc + 1)
	var nt := t.tri.size() / 3
	var boxes := PackedInt32Array(); boxes.resize(nt * 4)
	for i in nt:
		var a := t.pos[t.tri[i * 3]]; var b := t.pos[t.tri[i * 3 + 1]]; var c := t.pos[t.tri[i * 3 + 2]]
		var x0 := clampi(floori(minf(a.x, minf(b.x, c.x)) / CELL), 0, nc - 1); var x1 := clampi(floori(maxf(a.x, maxf(b.x, c.x)) / CELL), 0, nc - 1)
		var z0 := clampi(floori(minf(a.z, minf(b.z, c.z)) / CELL), 0, nc - 1); var z1 := clampi(floori(maxf(a.z, maxf(b.z, c.z)) / CELL), 0, nc - 1)
		boxes[i * 4] = x0; boxes[i * 4 + 1] = x1; boxes[i * 4 + 2] = z0; boxes[i * 4 + 3] = z1
		for cz in range(z0, z1 + 1):
			for cx in range(x0, x1 + 1): count[cz * nc + cx + 1] += 1
	for i in nc * nc: count[i + 1] += count[i]
	t.cell_start = count.duplicate()
	t.cell_tris.resize(count[nc * nc])
	for i in nt:
		for cz in range(boxes[i * 4 + 2], boxes[i * 4 + 3] + 1):
			for cx in range(boxes[i * 4], boxes[i * 4 + 1] + 1):
				var c := cz * nc + cx
				t.cell_tris[count[c]] = i; count[c] += 1

## Altitude du maillage du sol au point (x, z) du repère de la ville ; NAN hors des tuiles.
func height(x: float, z: float) -> float:
	var k := Vector2i(floori(x / tile_m), floori(z / tile_m))
	var t := tile(k)
	if t == null: return NAN
	return tile_height(t, x - k.x * tile_m, z - k.y * tile_m)

## Altitude dans une tuile décodée (repère tuile).
func tile_height(t: Tile, px: float, pz: float) -> float:
	if t.cell_start.is_empty(): _index(t)
	var nc := int(ceil(tile_m / CELL))
	var c := clampi(floori(pz / CELL), 0, nc - 1) * nc + clampi(floori(px / CELL), 0, nc - 1)
	var best := INF; var hb := NAN
	for j in range(t.cell_start[c], t.cell_start[c + 1]):
		var i := t.cell_tris[j]
		var a := t.pos[t.tri[i * 3]]; var b := t.pos[t.tri[i * 3 + 1]]; var d := t.pos[t.tri[i * 3 + 2]]
		var v0x := b.x - a.x; var v0z := b.z - a.z; var v1x := d.x - a.x; var v1z := d.z - a.z
		var den := v0x * v1z - v1x * v0z
		if absf(den) < 1e-9: continue
		var wx := px - a.x; var wz := pz - a.z
		var u := (wx * v1z - v1x * wz) / den; var v := (v0x * wz - wx * v0z) / den
		var out := maxf(maxf(-u, -v), u + v - 1.0)
		if out <= 1e-5: return a.y + (b.y - a.y) * u + (d.y - a.y) * v
		if out < best:   # point sur une arête (arrondis) : triangle le plus proche
			best = out; hb = a.y + (b.y - a.y) * clampf(u, 0, 1) + (d.y - a.y) * clampf(v, 0, 1)
	return hb

# ------------------------------------------------------------------------------------------- couronne lointaine
## Altitude de la grille lointaine (bilinéaire), repère de la ville.
func far_height(x: float, z: float) -> float:
	if _far_nx < 2: return min_height
	var fx := clampf((x - _far_x0) / _far_step, 0.0, _far_nx - 1.001); var fz := clampf((z - _far_z0) / _far_step, 0.0, _far_nz - 1.001)
	var ix := int(fx); var iz := int(fz); var u := fx - ix; var v := fz - iz
	var h00 := _far_h[iz * _far_nx + ix]; var h10 := _far_h[iz * _far_nx + ix + 1]
	var h01 := _far_h[(iz + 1) * _far_nx + ix]; var h11 := _far_h[(iz + 1) * _far_nx + ix + 1]
	return lerpf(lerpf(h00, h10, u), lerpf(h01, h11, u), v)

## Relief lointain tel que maillé par la couronne (grille de FAR_STEP m, diagonale 00-11, 1,5 m sous le MNT) :
## sol des tuiles de décor lointain (CityScene._far_ground) et altitude hors des tuiles de sol. Les cellules
## traversées par une voie au sol sont remaillées en corridor (plateforme au niveau du rail, talus) : voir _cor_cell.
func far_tri(x: float, z: float) -> float:
	if not _cor_cells.is_empty():
		var k := Vector2i(floori(x / FAR_STEP), floori(z / FAR_STEP))
		if _cor_cells.has(k):
			var h := _cor_height(_cor_cell(k), x, z)
			if not is_nan(h): return h
	return _far_coarse(x, z)

func _far_coarse(x: float, z: float) -> float:
	var ix := floorf(x / FAR_STEP); var iz := floorf(z / FAR_STEP)
	var u := x / FAR_STEP - ix; var v := z / FAR_STEP - iz
	var x0 := ix * FAR_STEP; var z0 := iz * FAR_STEP
	var h00 := far_height(x0, z0); var h10 := far_height(x0 + FAR_STEP, z0)
	var h01 := far_height(x0, z0 + FAR_STEP); var h11 := far_height(x0 + FAR_STEP, z0 + FAR_STEP)
	var h := h00 + (h10 - h00) * u + (h11 - h10) * v if u >= v else h00 + (h11 - h01) * u + (h01 - h00) * v
	return h - 1.5

# ------------------------------------------------------------------------- corridors des voies au sol
## Le relief lointain (MNT à 100 m, maillé à 200 m) ignore tranchées et remblais : sans correction il recouvre les
## voies (tram-trains et périphérie hors tuiles de sol, ou tuiles de sol pas encore chargées). Chaque cellule de
## FAR_STEP m à moins de COR_R m d'une voie au sol est remaillée (Delaunay) : plateforme à COR_BED m sous le rail
## sur ± COR_FLAT m, talus de pente COR_SLOPE au-delà (tranchée ou remblai), bords échantillonnés tous les
## COR_EDGE m (raccords exacts aux cellules voisines, remaillées ou non).
const COR_FLAT := 5.0
const COR_SLOPE := 0.6
const COR_R := 24.0
const COR_BED := 0.3
const COR_EDGE := 10.0
const COR_FILL := 2.0
const COR_SHOW_M := 3000.0     # m : rayon d'affichage des corridors dans la couronne
var _cor_pts: Dictionary = {}       # Vector2i (cellule 16 m) -> PackedVector3Array (axe des voies au sol, repère ville)
var _cor_dirs: Dictionary = {}      # mêmes cellules : direction horizontale
var _cor_cells: Dictionary = {}     # Vector2i (cellule FAR_STEP) -> true si remaillée
var _cor_cache: Dictionary = {}     # Vector2i -> [PackedVector3Array triangles, Dictionary index (cellule 20 m -> PackedInt32Array)]

## Axe des voies au sol (hors ponts et tunnels), repère de la ville, points espacés de ~6 m.
func set_corridor(pts: PackedVector3Array, dirs: PackedVector2Array) -> void:
	_cor_pts.clear(); _cor_dirs.clear(); _cor_cells.clear(); _cor_cache.clear()
	for i in pts.size():
		var c := pts[i]
		var ck := Vector2i(floori(c.x / 16.0), floori(c.z / 16.0))
		if not _cor_pts.has(ck): _cor_pts[ck] = PackedVector3Array(); _cor_dirs[ck] = PackedVector2Array()
		_cor_pts[ck].append(c); _cor_dirs[ck].append(dirs[i])
		for ix in range(floori((c.x - COR_R) / FAR_STEP), floori((c.x + COR_R) / FAR_STEP) + 1):
			for iz in range(floori((c.z - COR_R) / FAR_STEP), floori((c.z + COR_R) / FAR_STEP) + 1):
				_cor_cells[Vector2i(ix, iz)] = true
	_far_at = Vector3(INF, INF, INF)
	_cache.clear(); _lru.clear()

func corridor_data() -> Array:
	return [_cor_pts, _cor_dirs, _cor_cells]

func set_corridor_data(d: Array) -> void:
	_cor_pts = d[0]; _cor_dirs = d[1]; _cor_cells = d[2]; _cor_cache.clear(); _cache.clear(); _lru.clear()

func is_corridor(k: Vector2i) -> bool:
	return _cor_cells.has(k)

## Altitude du sol corrigée au point p : relief lointain borné par les talus des voies voisines.
func _cor_value(x: float, z: float, base: float) -> float:
	var lo := -INF; var hi := INF
	for cx in range(floori((x - COR_R) / 16.0), floori((x + COR_R) / 16.0) + 1):
		for cz in range(floori((z - COR_R) / 16.0), floori((z + COR_R) / 16.0) + 1):
			var pts: PackedVector3Array = _cor_pts.get(Vector2i(cx, cz), PackedVector3Array())
			for q in pts:
				var d := Vector2(q.x - x, q.z - z).length()
				if d > COR_R: continue
				var dev := maxf(0.0, d - COR_FLAT) * COR_SLOPE
				var t := q.y - COR_BED
				hi = minf(hi, t + dev); lo = maxf(lo, t - dev)
	# remblai borné à COR_FILL m au-dessus du relief : une voie sur un viaduc non décrit (fleuve, vallée) ne doit pas
	# combler la vallée ; la tranchée, elle, est toujours ouverte (rails jamais recouverts)
	lo = minf(lo, base + COR_FILL)
	if lo > hi: return hi
	return clampf(base, lo, hi)

## Triangles (repère ville) de la cellule remaillée k ; `loaded` : tuiles de sol affichées (bords raccordés à leurs
## sommets exacts, résultat non mis en cache).
func _cor_cell(k: Vector2i, loaded: Dictionary = {}) -> Array:
	var stitched := false
	var x0 := k.x * FAR_STEP; var z0 := k.y * FAR_STEP
	if not loaded.is_empty():
		for c in [Vector2(x0 + 1, z0 - 1), Vector2(x0 + 1, z0 + FAR_STEP + 1), Vector2(x0 - 1, z0 + 1), Vector2(x0 + FAR_STEP + 1, z0 + 1),
				Vector2(x0 - 1, z0 - 1), Vector2(x0 + FAR_STEP + 1, z0 - 1), Vector2(x0 - 1, z0 + FAR_STEP + 1), Vector2(x0 + FAR_STEP + 1, z0 + FAR_STEP + 1)]:
			if loaded.has(Vector2i(floori(c.x / tile_m), floori(c.y / tile_m))): stitched = true
	if not stitched and _cor_cache.has(k): return _cor_cache[k]
	var P := PackedVector2Array(); var H := PackedFloat32Array()
	var seen := {}
	var add := func(x: float, z: float, h: float) -> void:
		var key := Vector2i(roundi(x * 2.0), roundi(z * 2.0))
		if seen.has(key): return
		seen[key] = true; P.append(Vector2(x, z)); H.append(h)
	var corr := func(x: float, z: float) -> float:
		return _cor_value(x, z, _far_coarse(x, z))
	# bords : tous les COR_EDGE m (sommets exacts des tuiles de sol affichées le long des côtés qui les touchent)
	var corners := [Vector2(x0, z0), Vector2(x0 + FAR_STEP, z0), Vector2(x0 + FAR_STEP, z0 + FAR_STEP), Vector2(x0, z0 + FAR_STEP)]
	var ne := int(FAR_STEP / COR_EDGE)
	for i in 4:
		var a: Vector2 = corners[i]; var b: Vector2 = corners[(i + 1) % 4]
		var outside := (a + b) * 0.5 + Vector2(b.y - a.y, -(b.x - a.x)).normalized() * 0.01
		var side_loaded := stitched and loaded.has(Vector2i(floori(outside.x / tile_m), floori(outside.y / tile_m)))
		if side_loaded:
			var ha := _loaded_height(a, loaded); var hb := _loaded_height(b, loaded)
			add.call(a.x, a.y, ha if not is_nan(ha) else corr.call(a.x, a.y))
			for q in _far_edge_points(Vector3(a.x, 0, a.y), Vector3(b.x, 0, b.y), loaded): add.call(q.x, q.z, q.y)
		else:
			for j in ne:
				var q := a.lerp(b, float(j) / ne)
				var hl := _loaded_height(q, loaded) if stitched else NAN
				add.call(q.x, q.y, hl if not is_nan(hl) else corr.call(q.x, q.y))
	# intérieur : grille de 25 m hors plateforme, rangées parallèles aux voies (axe, ± COR_FLAT, ± 12 m)
	var near := func(x: float, z: float, r: float) -> bool:
		for cx in range(floori((x - r) / 16.0), floori((x + r) / 16.0) + 1):
			for cz in range(floori((z - r) / 16.0), floori((z + r) / 16.0) + 1):
				for q in _cor_pts.get(Vector2i(cx, cz), PackedVector3Array()):
					if Vector2(q.x - x, q.z - z).length() < r: return true
		return false
	for iz in range(1, 8):
		for ix in range(1, 8):
			var x := x0 + ix * 25.0; var z := z0 + iz * 25.0
			if not near.call(x, z, COR_FLAT + 4.0): add.call(x, z, corr.call(x, z))
	for cx in range(floori((x0 - COR_R) / 16.0), floori((x0 + FAR_STEP + COR_R) / 16.0) + 1):
		for cz in range(floori((z0 - COR_R) / 16.0), floori((z0 + FAR_STEP + COR_R) / 16.0) + 1):
			var ck := Vector2i(cx, cz)
			if not _cor_pts.has(ck): continue
			var pts: PackedVector3Array = _cor_pts[ck]; var dirs: PackedVector2Array = _cor_dirs[ck]
			for i in pts.size():
				var n := Vector2(-dirs[i].y, dirs[i].x)
				for o: float in [0.0, -COR_FLAT, COR_FLAT, -12.0, 12.0]:
					var q := Vector2(pts[i].x, pts[i].z) + n * o
					if q.x <= x0 + 1.0 or q.x >= x0 + FAR_STEP - 1.0 or q.y <= z0 + 1.0 or q.y >= z0 + FAR_STEP - 1.0: continue
					add.call(q.x, q.y, corr.call(q.x, q.y))
	var idx := Geometry2D.triangulate_delaunay(P)
	var T := PackedVector3Array()
	for t in range(0, idx.size(), 3):
		var a := P[idx[t]]; var b := P[idx[t + 1]]; var c := P[idx[t + 2]]
		var cr := (b - a).cross(c - a)
		if absf(cr) < 0.05: continue
		var ib := idx[t + 1]; var ic := idx[t + 2]
		if cr < 0.0: ib = idx[t + 2]; ic = idx[t + 1]
		T.append(Vector3(a.x, H[idx[t]], a.y)); T.append(Vector3(P[ib].x, H[ib], P[ib].y)); T.append(Vector3(P[ic].x, H[ic], P[ic].y))
	# index : cellules de 20 m -> triangles
	var index := {}
	for t in range(0, T.size(), 3):
		var lo := Vector2(minf(T[t].x, minf(T[t + 1].x, T[t + 2].x)), minf(T[t].z, minf(T[t + 1].z, T[t + 2].z)))
		var hi := Vector2(maxf(T[t].x, maxf(T[t + 1].x, T[t + 2].x)), maxf(T[t].z, maxf(T[t + 1].z, T[t + 2].z)))
		for ix in range(floori((lo.x - x0) / 20.0), floori((hi.x - x0) / 20.0) + 1):
			for iz in range(floori((lo.y - z0) / 20.0), floori((hi.y - z0) / 20.0) + 1):
				var ik := Vector2i(ix, iz)
				if not index.has(ik): index[ik] = PackedInt32Array()
				index[ik].append(t)
	var out := [T, index, Vector2(x0, z0)]
	if not stitched: _cor_cache[k] = out
	return out

## Altitude exacte du sol affiché (tuiles de sol chargées) au point q, NAN hors de ces tuiles.
func _loaded_height(q: Vector2, loaded: Dictionary) -> float:
	for off in [Vector2i.ZERO, Vector2i(-1, 0), Vector2i(0, -1), Vector2i(-1, -1)]:
		var kk: Vector2i = Vector2i(floori(q.x / tile_m), floori(q.y / tile_m)) + off
		if not loaded.has(kk): continue
		var local := Vector2(q.x - kk.x * tile_m, q.y - kk.y * tile_m)
		if local.x < -0.01 or local.y < -0.01 or local.x > tile_m + 0.01 or local.y > tile_m + 0.01: continue
		var t := tile(kk)
		if t != null: return tile_height(t, clampf(local.x, 0, tile_m), clampf(local.y, 0, tile_m))
	return NAN

## Altitude dans une cellule remaillée (barycentrique), NAN hors triangles.
func _cor_height(cell: Array, x: float, z: float) -> float:
	var T: PackedVector3Array = cell[0]
	var o: Vector2 = cell[2]
	var ik := Vector2i(floori((x - o.x) / 20.0), floori((z - o.y) / 20.0))
	var best := INF; var hb := NAN
	for t in cell[1].get(ik, PackedInt32Array()):
		var a := T[t]; var b := T[t + 1]; var d := T[t + 2]
		var v0x := b.x - a.x; var v0z := b.z - a.z; var v1x := d.x - a.x; var v1z := d.z - a.z
		var den := v0x * v1z - v1x * v0z
		if absf(den) < 1e-9: continue
		var wx := x - a.x; var wz := z - a.z
		var u := (wx * v1z - v1x * wz) / den; var v := (v0x * wz - wx * v0z) / den
		var out := maxf(maxf(-u, -v), u + v - 1.0)
		if out <= 1e-5: return a.y + (b.y - a.y) * u + (d.y - a.y) * v
		if out < best:
			best = out; hb = a.y + (b.y - a.y) * clampf(u, 0, 1) + (d.y - a.y) * clampf(v, 0, 1)
	return hb

## Triangles du sol lointain d'une cellule remaillée (vide si la cellule n'est pas un corridor).
func corridor_tris(k: Vector2i, loaded: Dictionary = {}) -> PackedVector3Array:
	if not _cor_cells.has(k): return PackedVector3Array()
	return _cor_cell(k, loaded)[0]

## Rapprochement radial (angle de vue conservé) au-delà de `near` : relief lointain dans le plan lointain de la caméra.
const FAR_SHADER := """
shader_type spatial;
render_mode world_vertex_coords, cull_disabled, specular_disabled;
uniform float near_m = 1150.0;
uniform float span_m = 380.0;
void vertex() {
	vec3 rel = VERTEX - CAMERA_POSITION_WORLD;
	float d = length(rel.xz);
	if (d > near_m && PROJECTION_MATRIX[3][3] < 0.5) {
		float r = near_m + span_m * (1.0 - exp(-(d - near_m) / 2500.0));
		VERTEX = CAMERA_POSITION_WORLD + rel * (r / d);
	}
}
void fragment() {
	ALBEDO = COLOR.rgb * 0.8;
	ROUGHNESS = 1.0;
}
"""

## Points intermédiaires du bord d'une tuile réellement affichée, dans l'ordre a -> b.
## Le bord du terrain lointain suit ainsi le profil complet, pas seulement les coins espacés de 200 m.
func _far_edge_points(a: Vector3, b: Vector3, loaded: Dictionary) -> Array[Vector3]:
	var result: Array[Vector3] = []
	var start := Vector2(a.x, a.z); var edge := Vector2(b.x - a.x, b.z - a.z)
	var outside := (start + Vector2(b.x, b.z)) * 0.5 + Vector2(edge.y, -edge.x).normalized() * 0.01
	var key := Vector2i(floori(outside.x / tile_m), floori(outside.y / tile_m))
	if not loaded.has(key): return result
	var detail := tile(key)
	if detail == null: return result
	var origin := Vector2(key.x, key.y) * tile_m
	var length2 := edge.length_squared()
	for local in detail.pos:
		var q := Vector2(local.x, local.z) + origin
		var fraction := (q - start).dot(edge) / length2
		if fraction <= 0.000001 or fraction >= 0.999999: continue
		if absf(edge.cross(q - start)) > 0.001 * sqrt(length2): continue
		result.append(Vector3(q.x, local.y, q.y))
	result.sort_custom(func(p: Vector3, q: Vector3): return Vector2(p.x - a.x, p.z - a.z).dot(edge) < Vector2(q.x - a.x, q.z - a.z).dot(edge))
	return result

## Met à jour la couronne lointaine autour de la caméra (repère de la ville, parent = CityScene).
func update_far(cam_city: Vector3, loaded: Dictionary = {}) -> void:
	if _far_nx < 2: return
	var signature := loaded.keys().hash()
	if signature == _far_loaded and Vector2(cam_city.x - _far_at.x, cam_city.z - _far_at.z).length() < FAR_REBUILD: return
	_far_at = cam_city
	_far_loaded = signature
	var n := int(FAR_RADIUS * 2.0 / FAR_STEP) + 1
	var x0 := snappedf(cam_city.x, FAR_STEP) - FAR_RADIUS; var z0 := snappedf(cam_city.z, FAR_STEP) - FAR_RADIUS
	var P := PackedVector3Array(); P.resize(n * n)
	for iz in n:
		for ix in n:
			var x := x0 + ix * FAR_STEP; var z := z0 + iz * FAR_STEP
			var h := far_height(x, z) - 1.5
			# Les arêtes de raccord utilisent les vraies altitudes des tuiles affichées.
			var k := Vector2i(floori(x / tile_m), floori(z / tile_m))
			for offset in [Vector2i.ZERO, Vector2i(-1, 0), Vector2i(0, -1), Vector2i(-1, -1)]:
				var candidate: Vector2i = k + offset
				if not loaded.has(candidate): continue
				var local := Vector2(x - candidate.x * tile_m, z - candidate.y * tile_m)
				if local.x < 0 or local.y < 0 or local.x > tile_m or local.y > tile_m: continue
				var detail := tile(candidate)
				if detail != null: h = tile_height(detail, local.x, local.y)
				break
			P[iz * n + ix] = Vector3(x, h, z)
	var V := PackedVector3Array(); var C := PackedColorArray(); var N := PackedVector3Array()
	for iz in n - 1:
		for ix in n - 1:
			var cx := x0 + (ix + 0.5) * FAR_STEP; var cz := z0 + (iz + 0.5) * FAR_STEP
			if loaded.has(Vector2i(floori(cx / tile_m), floori(cz / tile_m))): continue
			var ck := Vector2i(floori(cx / FAR_STEP), floori(cz / FAR_STEP))
			if _cor_cells.has(ck) and Vector2(cx - cam_city.x, cz - cam_city.z).length() < COR_SHOW_M:
				var ct := corridor_tris(ck, loaded)
				for t in range(0, ct.size(), 3):
					var tri3 := [ct[t], ct[t + 1], ct[t + 2]]
					var fn3: Vector3 = (tri3[2] - tri3[0]).cross(tri3[1] - tri3[0]).normalized()
					if fn3.y < 0.0: fn3 = -fn3
					var k3 := clampf((1.0 - fn3.y) * 5.0, 0.0, 1.0)
					for q in tri3:
						var col3 := color
						if land_ok:
							var lc3 := land_class(q.x, q.z, true)
							if lc3 >= 0: col3 = land_colors[lc3]
						V.append(q); N.append(fn3); C.append(col3.lerp(col3.darkened(0.2), k3))
				continue
			var a := P[iz * n + ix]; var b := P[iz * n + ix + 1]; var c := P[(iz + 1) * n + ix + 1]; var d := P[(iz + 1) * n + ix]
			var corners := [a, b, c, d]
			var rim: Array[Vector3] = []; var stitched := false
			for i in 4:
				rim.append(corners[i])
				var points := _far_edge_points(corners[i], corners[(i + 1) % 4], loaded)
				if not points.is_empty(): stitched = true; rim.append_array(points)
			var triangles: Array = []
			if stitched:
				var center := (a + b + c + d) * 0.25
				for i in rim.size(): triangles.append([center, rim[i], rim[(i + 1) % rim.size()]])
			else: triangles = [[a, b, c], [a, c, d]]
			for tri in triangles:
				var fn: Vector3 = (tri[2] - tri[0]).cross(tri[1] - tri[0]).normalized()
				if fn.length_squared() < 0.5: continue
				if fn.y < 0.0: fn = -fn
				var k_steep := clampf((1.0 - fn.y) * 5.0, 0.0, 1.0)
				for q in tri:
					var col := color
					if land_ok:   # occupation du sol régionale (cellules de 100 m), interpolée entre sommets
						var lc := land_class(q.x, q.z, true)
						if lc >= 0: col = land_colors[lc]
					V.append(q); N.append(fn); C.append(col.lerp(col.darkened(0.2), k_steep))
	if _far_mesh == null:
		_far_mesh = MeshInstance3D.new()
		_far_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var sh := Shader.new(); sh.code = FAR_SHADER
		var mat := ShaderMaterial.new(); mat.shader = sh
		mat.set_shader_parameter("near_m", FAR_NEAR)
		_far_mesh.material_override = mat
		add_child(_far_mesh)
	var arr := []; arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = V; arr[Mesh.ARRAY_NORMAL] = N; arr[Mesh.ARRAY_COLOR] = C
	var m := ArrayMesh.new()
	if V.size() > 0: m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	_far_mesh.mesh = m
	# boîte englobante : le maillage est rapproché par le shader, ne jamais l'écarter du rendu
	_far_mesh.custom_aabb = AABB(Vector3(x0, -5000, z0), Vector3(FAR_RADIUS * 2.0, 10000, FAR_RADIUS * 2.0))
