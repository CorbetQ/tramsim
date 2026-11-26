class_name CityScene
extends Node3D
## Décor réel (BD TOPO IGN) d'une ville, chargé par tuiles autour de la caméra.
## Fichier : res://data/scenes/<ville>.bin (voir tools/import/ign_scene.py). Repère : celui de la ville ;
## le nœud est décalé pour se superposer au repère de la ligne affichée.

const L_MAJOR := 0
const L_ROAD := 1
const L_SMALL := 2
const L_PATH := 3
const L_RAIL := 10
const P_WATER := 1
const P_FOREST := 2
const P_GRASS := 3
const P_SPORT := 4
const P_CEMETERY := 5
const R := 6371008.8

var tile_m := 400.0
var _x_scale := 1.0
var buf: PackedByteArray
var table: Dictionary = {}      # Vector2i -> Vector2i(offset, taille)
var built: Dictionary = {}      # Vector2i -> Node3D
var queue: Array[Vector2i] = []
var radius := 650.0
## Vue lointaine (fond d'accueil, vue aérienne) : ni détails de façade, ni mobilier, ni étiquettes.
var lite := false
## Noms des monuments en 3D (Label3D) : seulement pour la carte et le mode Explorer (à activer par l'appelant).
static var show_labels := false
var _horizon_deferred := false
var style: Dictionary = {}
var city := ""
var stats := {"tiles": 0, "buildings": 0}
static var _styles: Dictionary = {}
var v2 := false
var v3 := false                 # TSC3 : toits, houppiers et sol vert analysés sur orthophotos IGN
var _ortho_tile := false
var _track_nat: Dictionary = {} # Vector2i (cellule) -> nature de plateforme (TrackView.BED_*)
var _track_cell := 8.0
# relief : data/scenes/<ville>_ground.bin (TGR1, TerrainView : maillage continu relief + voirie, tools/import/terrain_mesh.py),
# sinon ancien <ville>_terrain.bin (TTR1/TTR2 : grilles 41 x 41 par tuile), altitudes relatives à alt0
var has_terrain := false
var alt0 := 0.0
var min_height := 0.0
var _ter_float := false         # TTR2 : altitude float32 sans quantification par tuile
var _ter: PackedByteArray
var _ter_table: Dictionary = {}     # Vector2i -> offset de la tuile
var _ter_grid: Dictionary = {}      # Vector2i -> PackedFloat32Array (41 x 41, [iz * 41 + ix])
var _water_lv: Dictionary = {}      # Vector2i -> Array de Vector3 (x, niveau, z) repère tuile
var _decks: Array = []              # [type, largeur, PackedVector3Array repère ville, Vector2i tuile]
var _road_level_cells: Dictionary = {}
var _deck_cells: Dictionary = {}    # Vector2i (cellules de 32 m) -> Array de [pont, segment]
var terrain: TerrainView = null     # sol continu TGR1 (relief + voirie drapée, couronne lointaine), sinon grille TTR
var _file: PackedByteArray          # <ville>.bin ; TSC4 : tuiles compressées (Brotli), `buf` = tuile décompressée
var v4 := false
var _tsc_cs: Dictionary = {}        # TSC4 : Vector2i -> taille compressée
var _tsc_cur := Vector2i(1 << 30, 0)
const TG := 41
const TSTEP := 10.0
var debug_props := false        # tests : mémorise la position (repère ville) des arbres et lampadaires posés
var placed_props: Array[Vector2] = []
var placed_trees: Array[Vector2] = []
var _trees_cur: Array = []
var _D: _Arrays = null              # détails de façade de la tuile en cours (maillage LOD)
var _F: Dictionary = {}             # P3 : relief des façades sur rue, Vector2i (cellules Facades.CELL) -> _Arrays
var _Fcur: _Arrays = null           # cellule de relief du bâtiment en cours
var _fac_dist: Array = []           # P3 : quartiers de style (Facades.districts)
var facade_stats := {}              # P3 : bâtiments par style de façade (tests)
var _props: Array = []              # par modèle StreetProps : [transformations, couleurs] de la tuile en cours
var _decals: Array = []             # decals de voirie de la tuile en cours : [type RoadDecals, position, angle, taille]
var _street_keepout := TrackView.KeepOut.new()
var _authored_camera_blocks: Array = []
var _camera_boxes: Array = []    # obstacles caméra de la tuile : [0, emprise, y0, y1, Rect2] ou [1, centre, rayon, demi-hauteur]
var _portal_cut := TrackView.KeepOut.new()
var _hangar_footprints: Array[PackedVector2Array] = []
var _ornament_footprints: Array[PackedVector2Array] = []
const K_CHURCH := 1
const K_CATHEDRAL := 2
const K_CASTLE := 3
const K_CIVIC := 4
const K_STATION := 5
const K_SCHOOL := 6
const TREE_KINDS := 10

static func path_for(c: String) -> String:
	return "res://data/scenes/%s.bin" % c

static func available(c: String) -> bool:
	return c != "" and FileAccess.file_exists(path_for(c))

## Ouvre la scène d'une ville et la cale sur le repère de la ligne (origine lat/lon de la ligne).
func open(c: String, net_origin: Array) -> bool:
	city = c
	_file = CityDataStore.bytes(path_for(c))
	buf = _file
	var magic := _file.slice(0, 4).get_string_from_ascii() if _file.size() >= 8 else ""
	if magic not in ["TSC1", "TSC2", "TSC3", "TSC4"]:
		return false
	v4 = magic == "TSC4"
	v2 = magic != "TSC1"
	v3 = magic == "TSC3" or v4
	var meta = CityDataStore.document("res://data/scenes/%s.json" % c)
	tile_m = float(meta.tile_m)
	var n := _file.decode_u32(4)
	for i in n:
		var o := 8 + i * (20 if v4 else 16)
		var k := Vector2i(_file.decode_s32(o), _file.decode_s32(o + 4))
		if v4:   # [offset, taille compressée, taille] : table[k].y reste la taille du contenu
			table[k] = Vector2i(_file.decode_u32(o + 8), _file.decode_u32(o + 16)); _tsc_cs[k] = _file.decode_u32(o + 12)
		else:
			table[k] = Vector2i(_file.decode_u32(o + 8), _file.decode_u32(o + 12))
	align_to_origin(net_origin)
	_load_style(c)
	_load_track_nature(c)
	_load_terrain(c)
	_load_road_levels(c)
	return true

## Reuse prepared city bytes/terrain metadata in a different line coordinate system.
func align_to_origin(net_origin: Array) -> void:
	var meta: Dictionary = CityDataStore.document("res://data/scenes/%s.json" % city)
	if net_origin.size() < 2 or not (meta.get("origin") is Array) or (meta.origin as Array).size() < 2: return
	# origine de la ville exprimée dans le repère de la ligne
	var lat_n := float(net_origin[0]); var lon_n := float(net_origin[1])
	var lat_c := float(meta.origin[0]); var lon_c := float(meta.origin[1])
	position = Vector3(deg_to_rad(lon_c - lon_n) * R * cos(deg_to_rad(lat_n)), 0.0, -deg_to_rad(lat_c - lat_n) * R)
	_x_scale = cos(deg_to_rad(lat_n)) / cos(deg_to_rad(lat_c))
	scale.x = _x_scale
## Contenu d'une tuile de décor : `buf` et décalage de début (TSC4 : tuile décompressée, gardée jusqu'à la suivante).
func _tile_data(k: Vector2i) -> int:
	var e: Vector2i = table[k]
	if not v4: return e.x
	if _tsc_cur != k:
		buf = _file.slice(e.x, e.x + int(_tsc_cs[k])).decompress(e.y, FileAccess.COMPRESSION_BROTLI)
		_tsc_cur = k
	return 0

func _load_road_levels(c: String) -> void:
	var path:="res://data/scenes/%s_road_levels.json"%c
	if not FileAccess.file_exists(path):return
	var data:Dictionary=CityDataStore.document(path)
	for segment in data.get("segments",[]):
		var a:=Vector2(segment[0],segment[1]);var b:=Vector2(segment[2],segment[3])
		var count:=maxi(1,ceili(a.distance_to(b)/16.0))
		for i in count:
			var p:=a.lerp(b,float(i)/count);var q:=a.lerp(b,float(i+1)/count)
			for x in range(floori((minf(p.x,q.x)-2.0)/32.0),floori((maxf(p.x,q.x)+2.0)/32.0)+1):
				for z in range(floori((minf(p.y,q.y)-2.0)/32.0),floori((maxf(p.y,q.y)+2.0)/32.0)+1):
					var key:=Vector2i(x,z)
					if not _road_level_cells.has(key):_road_level_cells[key]=[]
					_road_level_cells[key].append([p,q,int(segment[4])])

func _known_road_level(p:Vector2,heading:Vector2)->int:
	var best:=1.8;var level:=99
	for item in _road_level_cells.get(Vector2i(floori(p.x/32.0),floori(p.y/32.0)),[]):
		var a:Vector2=item[0];var b:Vector2=item[1]
		if absf((b-a).normalized().dot(heading))<0.85:continue
		var distance_:=p.distance_to(Geometry2D.get_closest_point_to_segment(p,a,b))
		if distance_<best-0.12:best=distance_;level=int(item[2])
		elif absf(distance_-best)<0.12:level=mini(level,int(item[2]))
	return level

func _load_terrain(c: String) -> void:
	if TerrainView.available(c):
		var tv := TerrainView.new()
		if tv.open(c):
			terrain = tv
			add_child(tv)
			var meta = CityDataStore.document("res://data/scenes/%s_terrain.json" % c)
			if typeof(meta) == TYPE_DICTIONARY: alt0 = float(meta.get("alt0", 0.0))
			var d := tv.meta_bytes()
			var q := 0
			for k in tv.keys: q = _ter_records(k, d, q)
			min_height = tv.min_height
			has_terrain = not tv.table.is_empty()
			_seat_decks()
			return
		tv.free()
	var path := "res://data/scenes/%s_terrain.bin" % c
	if not FileAccess.file_exists(path): return
	_ter = CityDataStore.bytes(path)
	if _ter.size() < 8: return
	var magic := _ter.slice(0, 4).get_string_from_ascii()
	if magic not in ["TTR1", "TTR2"]: return
	_ter_float = magic == "TTR2"
	var meta = CityDataStore.document("res://data/scenes/%s_terrain.json" % c)
	if typeof(meta) == TYPE_DICTIONARY: alt0 = float(meta.get("alt0", 0.0))
	var n := _ter.decode_u32(4)
	min_height = INF
	for i in n:
		var o := 8 + i * 16
		var k := Vector2i(_ter.decode_s32(o), _ter.decode_s32(o + 4))
		var to := int(_ter.decode_u32(o + 8))
		_ter_table[k] = to
		if _ter_float:
			for j in TG * TG: min_height = minf(min_height, _ter.decode_float(to + j * 4))
		else: min_height = minf(min_height, _ter.decode_s16(to) * 0.1)
		_ter_records(k, _ter, to + (4 * TG * TG if _ter_float else 3 + TG * TG))
	has_terrain = not _ter_table.is_empty()
	if not has_terrain: min_height = 0.0

## Niveaux d'eau et tabliers de ponts d'une tuile (TTR1/2, méta TGR1) ; retourne le décalage suivant.
func _ter_records(k: Vector2i, d: PackedByteArray, q: int) -> int:
	var nw := d.decode_u8(q); q += 1
	var lv: Array = []
	for j in nw:
		lv.append(Vector3(d.decode_s16(q) * 0.1, d.decode_s16(q + 4) * 0.1, d.decode_s16(q + 2) * 0.1)); q += 6
	_water_lv[k] = lv
	var nd := d.decode_u16(q); q += 2
	for j in nd:
		var kd := d.decode_u8(q); var w := d.decode_u8(q + 1) / 5.0; var np := d.decode_u8(q + 2); q += 3
		var pl := PackedVector3Array()
		for m in np:
			pl.append(Vector3(k.x * tile_m + d.decode_s16(q) * 0.1, d.decode_s16(q + 4) * 0.1, k.y * tile_m + d.decode_s16(q + 2) * 0.1)); q += 6
		var di := _decks.size()
		_decks.append([kd, w, pl, k])
		for m in range(pl.size() - 1):
			var lo := Vector2(minf(pl[m].x, pl[m + 1].x), minf(pl[m].z, pl[m + 1].z)) - Vector2.ONE * w
			var hi := Vector2(maxf(pl[m].x, pl[m + 1].x), maxf(pl[m].z, pl[m + 1].z)) + Vector2.ONE * w
			for cx in range(floori(lo.x / 32.0), floori(hi.x / 32.0) + 1):
				for cz in range(floori(lo.y / 32.0), floori(hi.y / 32.0) + 1):
					var ck := Vector2i(cx, cz)
					if not _deck_cells.has(ck): _deck_cells[ck] = []
					_deck_cells[ck].append([di, m])
	return q

func _grid(k: Vector2i) -> PackedFloat32Array:
	if _ter_grid.has(k): return _ter_grid[k]
	var g := PackedFloat32Array()
	if _ter_table.has(k):
		var o: int = _ter_table[k]
		g.resize(TG * TG)
		if _ter_float:
			for i in TG * TG: g[i] = _ter.decode_float(o + i * 4)
		else:
			var base := _ter.decode_s16(o) * 0.1; var step := _ter.decode_u8(o + 2) * 0.01
			for i in TG * TG: g[i] = base + _ter.decode_u8(o + 3 + i) * step
	_ter_grid[k] = g
	return g

## Altitude du terrain (repère ville), interpolation sur les triangles du maillage (diagonale 00-11).
func height_city(x: float, z: float) -> float:
	if not has_terrain: return 0.0
	if terrain != null:   # maillage exact du sol (voirie comprise), sinon relief lointain (sous les tuiles)
		var h := terrain.height(x, z)
		return h if not is_nan(h) else terrain.far_tri(x, z)
	var k := Vector2i(floori(x / tile_m), floori(z / tile_m))
	var g := _grid(k)
	if g.is_empty(): return min_height
	var fx := clampf((x - k.x * tile_m) / TSTEP, 0.0, TG - 1.0001); var fz := clampf((z - k.y * tile_m) / TSTEP, 0.0, TG - 1.0001)
	var ix := mini(int(fx), TG - 2); var iz := mini(int(fz), TG - 2)
	var u := fx - ix; var v := fz - iz
	var h00 := g[iz * TG + ix]; var h10 := g[iz * TG + ix + 1]; var h01 := g[(iz + 1) * TG + ix]; var h11 := g[(iz + 1) * TG + ix + 1]
	if u >= v: return h00 + (h10 - h00) * u + (h11 - h10) * v
	return h00 + (h11 - h01) * u + (h01 - h00) * v

## Altitude du terrain sous un point du repère de la ligne.
func height_at(p_net: Vector3) -> float:
	return height_city((p_net.x - position.x) / _x_scale, p_net.z - position.z)

## Altitude d'un tablier de pont (route ou voie ferrée BD TOPO) au point (repère ville), NAN hors pont.
func deck_city(x: float, z: float, chosen: int = -1) -> float:
	var best := NAN
	var p := Vector2(x, z)
	for it in _deck_cells.get(Vector2i(floori(x / 32.0), floori(z / 32.0)), []):
		if chosen >= 0 and int(it[0]) != chosen: continue
		var d: Array = _decks[it[0]]
		var pl: PackedVector3Array = d[2]
		var a := Vector2(pl[it[1]].x, pl[it[1]].z); var b := Vector2(pl[it[1] + 1].x, pl[it[1] + 1].z)
		var ab := b - a
		var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		if (a + ab * t).distance_to(p) <= float(d[1]) * 0.5 + 0.4:
			var y := lerpf(pl[it[1]].y, pl[it[1] + 1].y, t)
			if is_nan(best) or y > best: best = y
	return best

## Sommets [i0, fin[ de S posés sur le terrain (repère tuile) ; `decks` : sur les tabliers de ponts s'il y en a.
func _drape(S: _Arrays, i0: int, chosen_deck: int = -1) -> void:
	if not has_terrain:
		for i in range(i0, S.v.size()): S.set_rel(i, S.v[i].y)
		return
	for i in range(i0, S.v.size()):
		var q := S.v[i]
		var x := q.x + _tile_origin.x; var z := q.z + _tile_origin.y
		var h := height_city(x, z)
		if chosen_deck >= 0:
			var dh := deck_city(x, z, chosen_deck)
			if not is_nan(dh): h = dh
			else: h = _bridge_approach(x,z,chosen_deck,h)
		S.v[i] = Vector3(q.x, q.y + h + 0.04, q.z)
		S.set_rel(i, q.y + 0.04)

## Vrai si un tablier d'ouvrage (BD TOPO, tools/import/bridges.py) porte la voie au point p (repère de la ligne,
## y = rail) : tablier parallèle, voie à l'intérieur de sa largeur, dessus à moins de 0,35 m de rail - 0,1. La voie
## n'a alors pas de dalle propre (LineView._structures) : un seul tablier par ouvrage.
func deck_carries(p_net: Vector3, dir: Vector2) -> bool:
	var c := Vector2((p_net.x - position.x) / _x_scale, p_net.z - position.z)
	for it in _deck_cells.get(Vector2i(floori(c.x / 32.0), floori(c.y / 32.0)), []):
		var d: Array = _decks[it[0]]
		var pl: PackedVector3Array = d[2]
		var a := Vector2(pl[it[1]].x, pl[it[1]].z); var b := Vector2(pl[it[1] + 1].x, pl[it[1] + 1].z)
		if (b - a).length() < 0.01 or absf((b - a).normalized().dot(dir.normalized())) < 0.9: continue
		var t := (c - a).dot(b - a) / (b - a).length_squared()
		if t < -0.01 or t > 1.01: continue
		if (a + (b - a) * clampf(t, 0, 1)).distance_to(c) > float(d[1]) * 0.5 - 1.2: continue
		if absf(lerpf(pl[it[1]].y, pl[it[1] + 1].y, clampf(t, 0, 1)) - (p_net.y - 0.1)) < 0.35: return true
	return false

## Tablier suivi par une route : même orientation et même type, jamais le pont qui la croise.
func _deck_for_line(raw_pts: PackedVector2Array, rail: bool) -> int:
	var pts:=PackedVector2Array()
	for i in raw_pts.size()-1:
		var count:=maxi(1,ceili(raw_pts[i].distance_to(raw_pts[i+1])/8.0))
		for j in count:pts.append(raw_pts[i].lerp(raw_pts[i+1],float(j)/count))
	if not raw_pts.is_empty():pts.append(raw_pts[-1])
	var votes := {}; var total := 0.0
	for i in range(pts.size() - 1):
		var vector := pts[i + 1] - pts[i]; var length_ := vector.length()
		if length_ < 0.01: continue
		total += length_
		var p := (pts[i] + pts[i + 1]) * 0.5 + _tile_origin
		if not rail and _known_road_level(p,vector.normalized())<=0:continue
		var found := -1; var best := INF
		for item in _deck_cells.get(Vector2i(floori(p.x / 32.0), floori(p.y / 32.0)), []):
			var d: Array = _decks[item[0]]
			if int(d[0]) != 2 and (int(d[0]) == 1) != rail: continue   # 2 : ouvrage mixte (route + rail)
			var line: PackedVector3Array = d[2]; var u: Vector3 = line[item[1]]; var v: Vector3 = line[item[1] + 1]
			var a := Vector2(u.x, u.z); var b := Vector2(v.x, v.z)
			if absf((b - a).normalized().dot(vector.normalized())) < 0.85: continue
			var distance_ := p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b))
			if distance_ < float(d[1]) * 0.5 + 0.4 and distance_ < best:
				best = distance_; found = int(item[0])
		if found >= 0: votes[found] = float(votes.get(found, 0.0)) + length_
	var choice := -1; var most := 0.0
	for id in votes:
		if float(votes[id]) > most: most = float(votes[id]); choice = int(id)
	return choice

func _bridge_approach(x: float,z: float,id: int,ground: float) -> float:
	var d:Array=_decks[id];var points:PackedVector3Array=d[2]
	if points.size()<2:return ground
	var p:=Vector2(x,z)
	for end in [0,points.size()-1]:
		var tip:Vector3=points[end];var inner:Vector3=points[1 if end==0 else end-1]
		var tangent:=Vector2(tip.x-inner.x,tip.z-inner.z).normalized()
		var delta:=p-Vector2(tip.x,tip.z);var along:=delta.dot(tangent)
		var reach:=clampf(absf(tip.y-ground)*14.0,24.0,90.0)
		if along>=0.0 and along<reach and absf(delta.cross(tangent))<float(d[1])*0.5+0.4:
			return lerpf(tip.y,ground,smoothstep(0.0,reach,along))
	return ground

## Segment de voie ferrée BD TOPO (repère tuile) longé par une voie du réseau (à moins de 12 m, parallèle : axe BD TOPO
## d'un faisceau décalé de l'axe OSM de la voie).
func _rail_drawn(a: Vector2, b: Vector2) -> bool:
	var d := (b - a).normalized()
	for f in [0.25, 0.75]:
		var dirs := []
		var near := _tracks_near(a.lerp(b, f) + _tile_origin, 12.0, dirs)
		var ok := false
		for i in near.size():
			if absf((dirs[i] as Vector2).dot(d)) > 0.9: ok = true; break
		if not ok: return false
	return true

func _lift(S: _Arrays, i0: int, dy: float) -> void:
	if dy == 0.0: return
	for i in range(i0, S.v.size()):
		S.v[i] += Vector3(0, dy, 0)

func _ground_h(p_tile: Vector2) -> float:
	return height_city(p_tile.x + _tile_origin.x, p_tile.y + _tile_origin.y)

## Nature des plateformes (data/scenes/<ville>_track.json, cellules de 8 m le long de l'axe des voies).
func _load_track_nature(c: String) -> void:
	_track_nat.clear()
	var path := "res://data/scenes/%s_track.json" % c
	if not FileAccess.file_exists(path): return
	var d = CityDataStore.document(path)
	if typeof(d) != TYPE_DICTIONARY: return
	_track_cell = float(d.get("cell_m", 8.0))
	for e in d.get("cells", []):
		_track_nat[Vector2i(int(e[0]), int(e[1]))] = int(e[2])

## Nature de la plateforme au point p (repère de la ligne) : TrackView.BED_*, 0 si inconnue.
func track_nature_at(p_net: Vector3) -> int:
	if _track_nat.is_empty(): return 0
	var c := p_net - position
	c.x /= _x_scale
	var k := Vector2i(floori(c.x / _track_cell), floori(c.z / _track_cell))
	if _track_nat.has(k): return _track_nat[k]
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if _track_nat.has(k + d): return _track_nat[k + d]
	return 0

func _load_style(c: String) -> void:
	if _styles.is_empty():
		_styles = CityDataStore.document("res://data/city_styles.json")
	var key: String = _styles.cities.get(c, "")
	style = _styles.styles.get(key, _styles.default).duplicate(true)
	var identities: Dictionary = CityDataStore.document("res://data/city_identity.json")
	style.merge(identities.get(c, {}), true)
	var smeta = CityDataStore.document("res://data/scenes/%s.json" % c)
	_fac_dist = Facades.districts(c, smeta.get("origin", []) if smeta is Dictionary else [])

func _pal(name: String, h: int) -> Color:
	var arr: Array = style.get(name, ["#cccccc"])
	return Color.from_string(str(arr[absi(h) % arr.size()]), Color.GRAY)

## Distance to the tile footprint, not its centre: a camera at a tile corner can
## see that tile even when its centre is farther than the small near-LOD radius.
func _tile_distance(k: Vector2i, center_in_tiles: Vector2) -> float:
	var nearest := Vector2(clampf(center_in_tiles.x, k.x, k.x + 1.0), clampf(center_in_tiles.y, k.y, k.y + 1.0))
	return center_in_tiles.distance_to(nearest) * tile_m

## À appeler à chaque image avec la position de la caméra (repère de la ligne).
func update(center_net: Vector3, budget_tiles: int = 1) -> void:
	_poll_lod_tile()
	var c := center_net - position
	c.x /= _x_scale
	var r := radius
	var t0 := Vector2i(floori((c.x - r) / tile_m), floori((c.z - r) / tile_m))
	var t1 := Vector2i(floori((c.x + r) / tile_m), floori((c.z + r) / tile_m))
	for tx in range(t0.x, t1.x + 1):
		for tz in range(t0.y, t1.y + 1):
			var k := Vector2i(tx, tz)
			if (table.has(k) or _ter_table.has(k) or (terrain != null and terrain.has_tile(k))) and not built.has(k) and not k in queue and not (_lod_task >= 0 and _lod_job.key == k):
				queue.append(k)
	var ctile := Vector2(c.x, c.z) / tile_m
	queue.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return (Vector2(a) + Vector2(0.5, 0.5)).distance_squared_to(ctile) < (Vector2(b) + Vector2(0.5, 0.5)).distance_squared_to(ctile))
	for k in built.keys():
		if _tile_distance(k, ctile) > r * 1.5:
			built[k].queue_free(); built.erase(k)
	queue = queue.filter(func(k: Vector2i) -> bool: return _tile_distance(k, ctile) <= r * 1.5)
	for i in budget_tiles:
		if queue.is_empty(): break
		if async_lod:
			if _lod_task < 0: _start_lod_tile(queue.pop_front())
			break
		var k: Vector2i = queue.pop_front()
		built[k] = _build_tile(k)
		add_child(built[k])
	if terrain != null and not _horizon_deferred: terrain.update_far(c, built)

## Independent builder owns all mutable terrain/decompression caches. Scene nodes are
## constructed off-tree and attached only after the worker has completed.
var async_lod := false
var _lod_task := -1
var _lod_job: Dictionary = {}
var _lod_builder: CityScene
static var retired_lod_jobs := 0

func enable_async_lod() -> void:
	async_lod = true

func lod_pending() -> bool:
	return not queue.is_empty() or _lod_task >= 0

func _start_lod_tile(k: Vector2i) -> void:
	if _lod_builder == null:
		_lod_builder = CityScene.new()
		# Metadata/files already cached at city selection; worker has its own mutable caches.
		var meta: Dictionary = CityDataStore.document("res://data/scenes/%s.json" % city)
		_lod_job = {"key": k, "city": city, "origin": meta.origin, "initialize": true, "profile": {}}
		for field in ["position", "scale", "_x_scale", "_keepout", "_portal_cut", "_hangar_footprints", "_ornament_footprints", "_track_pts", "_track_dirs", "_decks", "_deck_cells", "_road_level_cells", "_track_nat", "lite"]:
			_lod_job.profile[field] = get(field)
	else: _lod_job = {"key": k, "initialize": false}
	_lod_job.builder = _lod_builder
	if terrain != null: _lod_job.corridor = terrain.corridor_data()
	_lod_task = WorkerThreadPool.add_task(_build_lod_tile.bind(_lod_job), false, "city_detail_lod")

static func _build_lod_tile(job: Dictionary) -> void:
	# Static callable owns the independent builder, never the disappearing scene node.
	var builder: CityScene = job.builder
	if job.initialize:
		builder.open(job.city, job.origin)
		for field in job.profile: builder.set(field, job.profile[field])
	if builder.terrain != null and job.has("corridor") and not job.corridor.is_empty() and not is_same(builder.terrain.corridor_data()[0], job.corridor[0]):
		builder.terrain.set_corridor_data(job.corridor)
	job.node = builder._build_tile(job.key)

func _poll_lod_tile() -> void:
	if _lod_task < 0 or not WorkerThreadPool.is_task_completed(_lod_task): return
	WorkerThreadPool.wait_for_task_completion(_lod_task); _lod_task = -1
	var node: Node3D = _lod_job.node
	var k: Vector2i = _lod_job.key
	if built.has(k): node.free()
	else:
		built[k] = node; add_child(node)
		if _lod_builder._water_tiles.has(k): _water_tiles[k] = _lod_builder._water_tiles[k]
	_lod_job = {}

func _exit_tree() -> void:
	if _lod_task >= 0:
		# Tree removal holds Godot's tree lock. Joining here can deadlock an off-tree
		# builder doing add_child(). Reap on later frames, after that lock is released.
		retired_lod_jobs += 1
		get_tree().process_frame.connect(_reap_lod_task.bind(_lod_task, _lod_job), CONNECT_ONE_SHOT)
		_lod_task = -1; _lod_builder = null; _lod_job = {}
	elif is_instance_valid(_lod_builder): _lod_builder.free()

## Let the main loop release its scene-tree locks before joining orphaned work.
static func drain_background_jobs(tree: SceneTree) -> void:
	await tree.process_frame
	await tree.process_frame
	while retired_lod_jobs > 0 or not HomeBackground._orphans.is_empty():
		await tree.process_frame

static func _reap_lod_task(task: int, job: Dictionary) -> void:
	if not WorkerThreadPool.is_task_completed(task):
		(Engine.get_main_loop() as SceneTree).process_frame.connect(_reap_lod_task.bind(task, job), CONNECT_ONE_SHOT)
		return
	WorkerThreadPool.wait_for_task_completion(task)
	if job.has("node"): job.node.free()
	job.builder.free()
	retired_lod_jobs -= 1

## Construit toutes les tuiles proches d'un coup (chargement initial).
func warm(center_net: Vector3, cancellation = null) -> bool:
	if cancellation != null and cancellation.cancelled(): return false
	if _lod_task >= 0:
		# Ne pas joindre ici : _poll_lod_tile() joint lui-même la tâche (une double jointure
		# invalide l'identifiant et bloquait ensuite la récupération à la sortie de scène).
		while not WorkerThreadPool.is_task_completed(_lod_task): OS.delay_msec(1)
		_poll_lod_tile()
	var was_async := async_lod
	async_lod = false
	_horizon_deferred = true
	update(center_net, 0)
	while not queue.is_empty():
		if cancellation != null and cancellation.cancelled():
			_horizon_deferred = false
			async_lod = was_async
			return false
		update(center_net, 4)
	_horizon_deferred = false
	update(center_net, 0)
	async_lod = was_async
	return true

func _build_tile(k: Vector2i) -> Node3D:
	var node := Node3D.new()
	node.position = Vector3(k.x * tile_m, 0, k.y * tile_m)
	var S := _Arrays.new()
	var W := _Arrays.new()
	_trees_cur = []; _camera_boxes = []
	for i in TREE_KINDS: _trees_cur.append([])
	_D = _Arrays.new(); _props = []; _F = {}
	for i in StreetProps.KINDS: _props.append([[], []])
	_decals = []
	_bld_cells = {}; _old_town = 0.0
	_tile_origin = Vector2(k.x * tile_m, k.y * tile_m)
	var seed := hash(k)
	var ground := Color.from_string(str(style.get("ground", "#cfcac0")), Color.GRAY)
	# sol : maillage continu relief + voirie (TerrainView / RoadView), sinon grille de relief héritée
	var gmesh: ArrayMesh = null
	if terrain != null and terrain.has_tile(k): gmesh = RoadView.build(terrain, terrain.tile(k), k, style, _portal_cut)
	elif has_terrain and _ter_table.has(k): _terrain_mesh(S, k, ground)
	elif terrain != null and table.has(k): _far_ground(S, k, ground)   # décor lointain allégé (light_tiles)
	else: S.quad(Vector3(0, 0, 0), Vector3(tile_m, 0, 0), Vector3(tile_m, 0, tile_m), Vector3(0, 0, tile_m), ground, -1.0)
	for di in _decks.size():
		if _decks[di][3] == k:
			var i0 := S.count()
			_deck(S, _decks[di])
			# tablier : hors du sol pour le shader (ni teinte d'occupation du sol, ni masque de pelouse)
			for j in range(i0, S.count()): S.set_rel(j, 3.0)
	if not table.has(k):   # couronne de relief autour du décor
		var gi := MeshInstance3D.new(); gi.mesh = S.mesh(); gi.material_override = Materials.building()
		node.add_child(gi)
		if gmesh != null:
			var gr := MeshInstance3D.new(); gr.mesh = gmesh; gr.material_override = _ground_material(k, null, ground)
			node.add_child(gr)
		stats.tiles += 1
		return node
	var o := _tile_data(k)
	# 1re passe : lecture de la tuile
	var blds: Array = []
	var nb := buf.decode_u16(o); o += 2
	for b in nb:
		var n := buf.decode_u8(o); var cls := buf.decode_u8(o + 1); var h := buf.decode_u16(o + 2) * 0.1
		var kind := 0
		if v2: kind = buf.decode_u8(o + 4); o += 5
		else: o += 4
		var ring := PackedVector2Array(); ring.resize(n)
		for i in n:
			ring[i] = Vector2(buf.decode_s16(o) * 0.1, buf.decode_s16(o + 2) * 0.1); o += 4
		var nt := buf.decode_u8(o); o += 1
		blds.append([ring, buf.slice(o, o + nt * 3), cls, h, kind])
		o += nt * 3
		var bb := Rect2(ring[0], Vector2.ZERO)
		for q in ring: bb = bb.expand(q)
		for cx in range(floori(bb.position.x / 16.0), floori(bb.end.x / 16.0) + 1):
			for cz in range(floori(bb.position.y / 16.0), floori(bb.end.y / 16.0) + 1):
				var ck := Vector2i(cx, cz)
				if not _bld_cells.has(ck): _bld_cells[ck] = []
				_bld_cells[ck].append(ring)
		if cls == 0 and h <= 20.0: _old_town += 1.0
	_old_town /= maxf(1.0, float(nb))
	var polys_start := o
	var np := buf.decode_u16(o); o += 2
	_water_cur = []
	_water_tops = []
	for p in np:
		var nv := buf.decode_u16(o + 1); var ntr := buf.decode_u16(o + 3)
		if buf.decode_u8(o) == P_WATER:   # plans d'eau de la tuile : ni arbres ni herbe dedans
			var q := o + 5 + nv * 4
			for t in ntr:
				var tri := PackedVector2Array()
				for m in 3:
					var vi := buf.decode_u16(q + t * 6 + m * 2)
					tri.append(Vector2(buf.decode_s16(o + 5 + vi * 4) * 0.1, buf.decode_s16(o + 7 + vi * 4) * 0.1))
				_water_cur.append([tri, Rect2(tri[0], Vector2.ZERO).expand(tri[1]).expand(tri[2])])
		o += 5 + nv * 4 + ntr * 6
	var lines_start := o
	var nl := buf.decode_u16(o); o += 2
	_street_keepout=TrackView.KeepOut.new()
	var roads: Array = []
	for l in nl:
		var cls:=buf.decode_u8(o);var width_:=buf.decode_u8(o+1)/5.0;var count:=buf.decode_u16(o+2);o+=4
		var road:=PackedVector2Array()
		for j in count:
			road.append(Vector2(buf.decode_s16(o)*0.1,buf.decode_s16(o+2)*0.1));o+=4
		_street_keepout.add_polyline(road,maxf(width_*0.5,1.2)+0.35)
		roads.append([cls, width_, road])
	_nodes = _road_nodes(roads)
	var points: Array = []
	var labels: Array = []
	if v2:
		var npt := buf.decode_u16(o); o += 2
		for i in npt:
			points.append([buf.decode_u8(o), buf.decode_u16(o + 1) * 0.1, Vector2(buf.decode_s16(o + 3) * 0.1, buf.decode_s16(o + 5) * 0.1)]); o += 7
		var nlb := buf.decode_u16(o); o += 2
		for i in nlb:
			var kd := buf.decode_u8(o); var pos := Vector2(buf.decode_s16(o + 1) * 0.1, buf.decode_s16(o + 3) * 0.1); var ln := buf.decode_u8(o + 5)
			labels.append([kd, pos, buf.slice(o + 6, o + 6 + ln).get_string_from_utf8()]); o += 6 + ln
	var roofs := PackedInt32Array()
	var otrees: Array = []
	var runs: Array = []
	if v3:
		var nr := buf.decode_u16(o); o += 2
		for i in nr: roofs.append(buf.decode_u16(o + i * 2))
		o += nr * 2
		var ntr := buf.decode_u16(o); o += 2
		for i in ntr:
			otrees.append([Vector2(buf.decode_s16(o) * 0.1, buf.decode_s16(o + 2) * 0.1), buf.decode_u8(o + 4) * 0.1, buf.decode_u8(o + 5)]); o += 6
		var ng := buf.decode_u16(o); o += 2
		for i in ng:
			runs.append(Vector3i(buf.decode_u8(o), buf.decode_u8(o + 1), buf.decode_u8(o + 2))); o += 3
	_ortho_tile = not otrees.is_empty() or not runs.is_empty()
	# sol vert réel (cellules de 4 m, orthophoto) : masque de tuile filtré bilinéairement dans le shader du sol
	# (contours lissés, sans couche de quads en escalier ni z-fighting), jamais dans l'eau
	var meadow_rng:=RandomNumberGenerator.new();meadow_rng.seed=seed*43
	var meadow_count:=0
	# touffes d'herbe instanciées (P3) : denses en Forward+, clairsemées en Mobile/Compatibility (pelouse = texture)
	var meadow_cap:=128 if DayNight.low_quality or VisualEffects.renderer()=="gl_compatibility" else 700
	var veg: Image = null
	if not runs.is_empty():
		var cells := int(tile_m / 4.0)
		veg = Image.create(cells, cells, false, Image.FORMAT_L8)
	for r in runs:
		var z0: float = r.x * 4.0; var x0: float = r.y * 4.0; var x1: float = x0 + r.z * 4.0
		for cx in range(r.y, r.y + r.z):
			if cx < veg.get_width() and r.x < veg.get_height() and not _in_water(Vector2(cx * 4.0 + 2.0, z0 + 2.0)):
				veg.set_pixel(cx, r.x, Color.WHITE)
		for j in mini(int((x1-x0)/(8.0 if meadow_cap<=128 else 2.5)),6 if meadow_cap<=128 else 24):
			if meadow_count>=meadow_cap:break
			var q:=Vector2(meadow_rng.randf_range(x0,x1),z0+meadow_rng.randf_range(0.3,3.7))
			var inside:=false
			for building in blds:
				if Geometry2D.is_point_in_polygon(q,building[0]):inside=true;break
			if inside:continue
			_add_tree(8 if meadow_rng.randf()<0.7 else 9,Vector3(q.x,0.02,q.y),meadow_rng,0.8)
			meadow_count+=1
	# houppiers réels détectés (essence selon le style de la ville, taille selon le houppier)
	var trng := RandomNumberGenerator.new(); trng.seed = seed * 13
	for t in otrees:
		# essence d'alignement de la ville majoritaire, sinon mélange régional (t[2] = 1 : houppier sombre, non utilisé)
		var kind := int(style.get("trees", [0])[0]) if trng.randf() < 0.55 else _pick_tree(trng)
		var sc := clampf(float(t[1]) / CROWN_R[kind], 0.55, 2.0)
		# octet >= 12 : hauteur mesurée par le LiDAR HD (quarts de mètre), sinon houppier de l'orthophoto
		_add_tree(kind, Vector3(t[0].x, 0.02, t[0].y), trng, sc, true, float(t[2]) * 0.25 if int(t[2]) >= 12 else 0.0)
	# bâtiments
	for i in blds.size():
		var b: Array = blds[i]
		var replaced := false
		for footprint in _hangar_footprints:
			if Geometry2D.is_point_in_polygon(_tile_origin + _centroid(b[0]), footprint): replaced = true; break
		if replaced: continue
		if _keepout != null and _keepout.blocked(_tile_origin + _centroid(b[0])): continue
		var rc := Color(0, 0, 0, 0)
		if i < roofs.size() and roofs[i] & 0x8000:
			rc = _ortho_roof(roofs[i])
		var j0 := S.count(); var d0 := _D.count()
		var fk := Vector2i(floori(_centroid(b[0]).x / Facades.CELL), floori(_centroid(b[0]).y / Facades.CELL))
		if not _F.has(fk): _F[fk] = _Arrays.new()
		_Fcur = _F[fk]; var f0 := _Fcur.count()
		_building(S, b[0], b[1], b[2], b[3], b[4], seed + i, points, rc)
		if has_terrain:  # posé au sol : base à l'altitude minimale de l'emprise
			var base := INF
			for q in b[0]: base = minf(base, _ground_h(q))
			_lift(S, j0, base); _lift(_D, d0, base); _lift(_Fcur, f0, base)
		var bounds := AABB(S.v[j0], Vector3.ZERO)
		for j in range(j0, S.count()): bounds = bounds.expand(S.v[j])
		var rect := Rect2(b[0][0], Vector2.ZERO)
		for q in b[0]: rect = rect.expand(q)
		_camera_boxes.append([0, b[0], bounds.position.y - 0.3, bounds.end.y + 0.3, rect.grow(0.8)])
	stats.buildings += nb
	# surfaces
	o = polys_start
	np = buf.decode_u16(o); o += 2
	for p in np:
		var cls := buf.decode_u8(o); var nv := buf.decode_u16(o + 1); var ntr := buf.decode_u16(o + 3); o += 5
		var v := PackedVector2Array(); v.resize(nv)
		for i in nv:
			v[i] = Vector2(buf.decode_s16(o) * 0.1, buf.decode_s16(o + 2) * 0.1); o += 4
		var y: float = {P_WATER: 0.03, P_FOREST: 0.025, P_GRASS: 0.02, P_SPORT: 0.03, P_CEMETERY: 0.025}.get(cls, 0.02)
		# teintes apparentes relevées sur orthophoto IGN (sous-bois, pelouse, terrain de sport, cimetière)
		var col: Color = {P_FOREST: Color("#4d5f3d"), P_GRASS: Color("#71824c"), P_SPORT: Color("#7b8d4f"), P_CEMETERY: Color("#7c8669")}.get(cls, Color("#71824c"))
		col.a = 0.30
		var rng := RandomNumberGenerator.new(); rng.seed = seed * 31 + p
		if cls == P_WATER and has_terrain: y = _water_level(k, v) + 0.03
		if cls == P_WATER and gmesh == null and terrain != null:
			# décor lointain : le relief lointain (MNT) passe à la surface de l'eau ; plan d'eau posé au-dessus
			var top := _ground_h(_centroid(v))
			for q in v: top = maxf(top, _ground_h(q))
			for t in ntr:     # relief lointain sous l'intérieur du plan d'eau (facettes de 200 m) : grille de 50 m
				var ta := v[buf.decode_u16(o + t * 6)]; var tb := v[buf.decode_u16(o + t * 6 + 2)]; var tc := v[buf.decode_u16(o + t * 6 + 4)]
				var r := Rect2(ta, Vector2.ZERO).expand(tb).expand(tc)
				top = maxf(top, _ground_h((ta + tb + tc) / 3.0))
				for gx in range(ceili(r.position.x / 50.0), floori(r.end.x / 50.0) + 1):
					for gz in range(ceili(r.position.y / 50.0), floori(r.end.y / 50.0) + 1):
						var g := Vector2(gx * 50.0, gz * 50.0)
						if Geometry2D.point_is_inside_triangle(g, ta, tb, tc): top = maxf(top, _ground_h(g))
			y = top + 0.35
			var wr := Rect2(v[0], Vector2.ZERO)
			for q in v: wr = wr.expand(q)
			_water_tops.append([wr, y])
		# surface végétale dans l'eau (îlots des tuiles voisines) : point intérieur réel (1er triangle), pas le
		# centroïde (une forêt en croissant le long d'une rivière a son centroïde dans l'eau)
		if cls != P_WATER and ntr > 0:
			var inside := (v[buf.decode_u16(o)] + v[buf.decode_u16(o + 2)] + v[buf.decode_u16(o + 4)]) / 3.0
			if _in_water(inside): o += ntr * 6; continue
		var p0 := S.count()
		S.sub = TSTEP
		for t in ntr:
			var a := v[buf.decode_u16(o)]; var b := v[buf.decode_u16(o + 2)]; var c := v[buf.decode_u16(o + 4)]; o += 6
			if cls == P_WATER:
				if not _water_cut(a, b, c, y):
					W.tri(Vector3(a.x, y, a.y), Vector3(b.x, y, b.y), Vector3(c.x, y, c.y), Color.WHITE)
			else:
				if gmesh == null:   # surface déjà dans le maillage du sol sinon
					S.tri(Vector3(a.x, y, a.y), Vector3(b.x, y, b.y), Vector3(c.x, y, c.y), col, -1.0)
				if (cls == P_FOREST or cls == P_GRASS or cls == P_CEMETERY):
					var area := absf((b - a).cross(c - a)) * 0.5
					var dens := 85.0 if cls == P_FOREST else 180.0
					var count := mini(int(area / dens + rng.randf()), 40)
					for i in count:
						var r1 := sqrt(rng.randf()); var r2 := rng.randf()
						var q := a * (1.0 - r1) + b * (r1 * (1.0 - r2)) + c * (r1 * r2)
						var kind := 1 if (cls == P_CEMETERY and rng.randf() < 0.6) else (_pick_tree(rng) if rng.randf()<0.45 else 7+rng.randi_range(0,2))
						if _ortho_tile and kind < 7: kind = 7+rng.randi_range(0,2)
						_add_tree(kind, Vector3(q.x, y, q.y), rng)
		S.sub = 0.0
		_drape(S, p0)
	# lignes (routes avec arbres d'alignement, voies ferrées)
	o = lines_start
	nl = buf.decode_u16(o); o += 2
	for l in nl:
		var cls := buf.decode_u8(o); var w := buf.decode_u8(o + 1) / 5.0; var n := buf.decode_u16(o + 2); o += 4
		var pts := PackedVector2Array(); pts.resize(n)
		for i in n:
			pts[i] = Vector2(buf.decode_s16(o) * 0.1, buf.decode_s16(o + 2) * 0.1); o += 4
		var l0 := S.count()
		S.sub = TSTEP
		var deck := _deck_for_line(pts, cls == L_RAIL)
		if gmesh == null and terrain != null: _road_ribbon(S, pts, cls, w, deck)   # chaussées hors maillage du sol
		_line(S, pts, cls, w, seed + l, deck)
		S.sub = 0.0
		_drape(S, l0, deck)
	_crossroads(seed)
	# éléments ponctuels (clochers isolés, tours, cheminées)
	for p in points:
		var ornament_replaced := false
		for footprint in _ornament_footprints:
			if Geometry2D.is_point_in_polygon(_tile_origin + p[2], footprint): ornament_replaced = true; break
		if ornament_replaced: continue
		if p[0] == 1 and p.size() > 3: continue  # clocher déjà rattaché à une église
		if _keepout != null and _keepout.blocked(_tile_origin + p[2], 3.0): continue
		var q0 := S.count()
		_point(S, p[0], p[1], p[2])
		_lift(S, q0, _ground_h(p[2]) if has_terrain else 0.0)
	# maillages
	var mi := MeshInstance3D.new(); mi.mesh = S.mesh(); mi.material_override = _ground_material(k, veg, ground)
	node.add_child(mi)
	if gmesh != null:   # même matériau (masque de végétation de la tuile)
		var gm := MeshInstance3D.new(); gm.mesh = gmesh; gm.material_override = mi.material_override
		node.add_child(gm)
	if W.count() > 0:
		var wi := MeshInstance3D.new(); wi.mesh = W.mesh(); wi.material_override = Materials.water()
		node.add_child(wi)
	# détails de façade (balcons, stores, lucarnes, soubassements) : LOD par distance
	if _D.count() > 0 and not lite:
		var di := MeshInstance3D.new(); di.mesh = _D.mesh(); di.material_override = Materials.building()
		di.visibility_range_end = DETAIL_RANGE * (0.6 if DayNight.low_quality else 1.0)
		di.visibility_range_end_margin = 20.0
		if DayNight.low_quality: di.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(di)
	# P3 : relief des façades sur rue (Facades) : LOD proche par cellule (portée mesurée au centre de la cellule)
	for fk in _F:
		var fa: _Arrays = _F[fk]
		if fa.count() == 0 or lite: continue
		var fi := MeshInstance3D.new(); fi.mesh = fa.mesh(); fi.material_override = Materials.building()
		fi.name = "facade_relief_%d_%d" % [fk.x, fk.y]
		fi.visibility_range_end = Facades.near_range(); fi.visibility_range_end_margin = 12.0
		if DayNight.low_quality: fi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(fi)
		stats["facade_tris"] = int(stats.get("facade_tris", 0)) + fa.count() / 3
	_F = {}; _Fcur = null
	# mobilier, voitures en stationnement, halos : instances par modèle
	for kind in StreetProps.KINDS:
		if lite or _props[kind][0].is_empty(): continue
		stats["props_%d" % kind] = int(stats.get("props_%d" % kind, 0)) + _props[kind][0].size()
		# cellules de TREE_CELL m : portée de visibilité mesurée au centre de chaque cellule (LOD réel par distance)
		var pc := {}
		for i in _props[kind][0].size():
			var o3: Vector3 = (_props[kind][0][i] as Transform3D).origin
			var ck := Vector2i(floori(o3.x / TREE_CELL), floori(o3.z / TREE_CELL))
			if not pc.has(ck): pc[ck] = [[], []]
			pc[ck][0].append(_props[kind][0][i])
			if i < _props[kind][1].size(): pc[ck][1].append(_props[kind][1][i])
		for ck in pc:
			for pmi in StreetProps.instances_lod(kind, pc[ck][0], pc[ck][1]): node.add_child(pmi)
	if not lite and RoadDecals.enabled():
		for dc in _decals: node.add_child(RoadDecals.make(dc[0], dc[1], dc[2], dc[3]))
	_decals = []
	_D = null
	for v in TREE_KINDS:
		if _trees_cur[v].is_empty(): continue
		_add_trees(node, v, _trees_cur[v])
	# noms des monuments
	for lb in labels:
		if lite or not show_labels: break
		var l3 := Label3D.new(); l3.text = lb[2]
		l3.font_size = 72; l3.pixel_size = 0.03; l3.outline_size = 14
		l3.billboard = BaseMaterial3D.BILLBOARD_ENABLED; l3.no_depth_test = false
		l3.modulate = Color(1, 0.96, 0.85)
		l3.position = Vector3(lb[1].x, 34.0 + (_ground_h(lb[1]) if has_terrain else 0.0), lb[1].y)
		l3.visibility_range_end = 700.0
		node.add_child(l3)
	node.set_meta("camera_boxes", _camera_boxes.duplicate())
	stats.tiles += 1
	return node

## Sol d'une tuile de décor lointain (sans maillage TGR) : triangles du relief lointain (pas de 200 m, diagonale
## 00-11), exactement ceux de la couronne (TerrainView.update_far) ; teinte d'occupation du sol dans le shader.
func _far_ground(S: _Arrays, k: Vector2i, ground: Color) -> void:
	var st := TerrainView.FAR_STEP
	var n := int(tile_m / st)
	var col := ground; col.a = 1.0
	for iz in n:
		for ix in n:
			# cellule traversée par une voie au sol : maillage du corridor (plateforme au niveau du rail, talus)
			var ck := Vector2i(floori(_tile_origin.x / st) + ix, floori(_tile_origin.y / st) + iz)
			if terrain.is_corridor(ck):
				var ct := terrain.corridor_tris(ck, terrain.table)
				var o0 := Vector3(_tile_origin.x, 0, _tile_origin.y)
				for t in range(0, ct.size(), 3): S.tri(ct[t] - o0, ct[t + 1] - o0, ct[t + 2] - o0, col)
				continue
			var p := [Vector2(ix, iz), Vector2(ix + 1, iz), Vector2(ix + 1, iz + 1), Vector2(ix, iz + 1)]
			var q: Array[Vector3] = []
			for c in p:
				var x: float = c.x * st + _tile_origin.x; var z: float = c.y * st + _tile_origin.y
				q.append(Vector3(x, terrain.far_tri(x, z), z))
			# raccord exact aux tuiles de sol voisines (mêmes sommets de bord, comme la couronne lointaine)
			var rim: Array[Vector3] = []; var stitched := false
			for i in 4:
				rim.append(q[i])
				var pts := terrain._far_edge_points(q[i], q[(i + 1) % 4], terrain.table)
				if not pts.is_empty(): stitched = true; rim.append_array(pts)
			var o3 := Vector3(_tile_origin.x, 0, _tile_origin.y)
			if stitched:
				var ctr := (q[0] + q[1] + q[2] + q[3]) * 0.25
				for i in rim.size(): S.tri(ctr - o3, rim[i] - o3, rim[(i + 1) % rim.size()] - o3, col)
			else:
				S.tri(q[0] - o3, q[1] - o3, q[2] - o3, col); S.tri(q[0] - o3, q[2] - o3, q[3] - o3, col)

## Chaussée ou voie ferrée en ruban drapé (tuiles de décor lointain : la voirie n'est pas dans un maillage de sol).
func _road_ribbon(S: _Arrays, pts: PackedVector2Array, cls: int, w: float, deck: int = -1) -> void:
	if cls == L_PATH: return
	var col: Color = {L_MAJOR: Color("#6a6e72", 0.28), L_ROAD: Color("#575b60", 0.28), L_SMALL: Color("#5d6064", 0.28)}.get(cls, Color("#7f776c", 1.0))
	var half := maxf(w, 2.5) * 0.5 if cls != L_RAIL else 2.2
	var l0 := S.count()
	S.sub = TSTEP
	for i in pts.size() - 1:
		var a := pts[i]; var b := pts[i + 1]
		var d := b - a
		if d.length() < 0.05: continue
		d = d.normalized()
		if cls == L_RAIL and _rail_drawn(a, b): continue   # voie du réseau rendue (tram-train) : pas de second ruban
		var nrm := Vector2(-d.y, d.x) * half
		a -= d * half * 0.7; b += d * half * 0.7          # recouvrement aux jonctions
		S.quad(Vector3(a.x - nrm.x, 0.06, a.y - nrm.y), Vector3(b.x - nrm.x, 0.06, b.y - nrm.y),
			Vector3(b.x + nrm.x, 0.06, b.y + nrm.y), Vector3(a.x + nrm.x, 0.06, a.y + nrm.y), col, -1.0)
	S.sub = 0.0
	_drape(S, l0, deck)
	if deck < 0 and not _water_tops.is_empty():   # ponts hors maillage de sol : au-dessus des plans d'eau posés
		for i in range(l0, S.count()):
			var p := Vector2(S.v[i].x, S.v[i].z)
			if not _in_water(p): continue
			for wt in _water_tops:
				# plan d'eau voisin seulement (un niveau d'eau plus haut d'un autre bassin, rectangle englobant large,
				# soulevait des kilomètres de chaussée dans le ciel)
				if (wt[0] as Rect2).grow(1.0).has_point(p) and wt[1] + 0.6 - S.v[i].y < 2.5: S.v[i].y = maxf(S.v[i].y, wt[1] + 0.6)

## Matériau du décor d'une tuile : masque de pelouse (orthophoto, 4 m) et occupation du sol réelle (TerrainView,
## cellules de 25 m) ; matériau partagé sans l'un ni l'autre.
func _ground_material(k: Vector2i, veg: Image, ground: Color) -> ShaderMaterial:
	var land: Image = terrain.land_image(k, ground) if terrain != null else null
	if veg == null and land == null: return Materials.building()
	var tm: ShaderMaterial = Materials.building().duplicate()
	if veg != null:
		tm.set_shader_parameter("veg_mask", ImageTexture.create_from_image(veg))
		tm.set_shader_parameter("veg_inv_size", 1.0 / tile_m)
	if land != null:
		tm.set_shader_parameter("land_tint", ImageTexture.create_from_image(land))
		tm.set_shader_parameter("land_on", 1.0)
	return tm

## Le hangar détaillé remplace son extrusion de décor, afin de garder ses entrées ouvertes.
func replace_hangar(footprint_net: PackedVector2Array, remove_inferred_ornaments := false) -> void:
	var polygon := PackedVector2Array()
	for p in footprint_net: polygon.append(Vector2((p.x - position.x) / _x_scale, p.y - position.z))
	_hangar_footprints.append(polygon)
	if remove_inferred_ornaments: _ornament_footprints.append(polygon)

## Detailed station landmarks retain camera occlusion when their generic extrusion is removed.
## Depot halls are deliberately not registered as closed prisms: their rail portals remain open.
func add_building_obstacle(footprint_net: PackedVector2Array, base_y: float, height_: float) -> void:
	var poly := PackedVector2Array()
	for p in footprint_net: poly.append(Vector2((p.x - position.x) / _x_scale, p.y - position.z))
	var rect := Rect2(poly[0], Vector2.ZERO)
	for p in poly: rect = rect.expand(p)
	_authored_camera_blocks.append([poly, base_y, base_y + height_, rect.grow(.8)])

## Ouvrir le terrain aux portails documentés, sans découper le terrain au-dessus des tunnels profonds.
func add_portal_cut(a_net: Vector2, b_net: Vector2, width_: float = 2.8) -> void:
	var a := Vector2((a_net.x - position.x) / _x_scale, a_net.y - position.z)
	var b := Vector2((b_net.x - position.x) / _x_scale, b_net.y - position.z)
	_portal_cut.add_segment(a, b, width_)

func _portal_ground_tri(S: _Arrays, a: Vector3, b: Vector3, c: Vector3, color_: Color) -> void:
	var middle := (a + b + c) / 3.0
	if _portal_cut.blocked(_tile_origin + Vector2(middle.x, middle.z)): return
	S.tri(a, b, c, color_, -1.0)

## Sol en relief : grille de 10 m, facettes plates (low poly), teinte légèrement assombrie dans les pentes.
func _terrain_mesh(S: _Arrays, k: Vector2i, ground: Color) -> void:
	var g := _grid(k)
	var steep := ground.lerp(Color("#8d9a6a"), 0.45)
	for iz in TG - 1:
		for ix in TG - 1:
			var h00 := g[iz * TG + ix]; var h10 := g[iz * TG + ix + 1]; var h01 := g[(iz + 1) * TG + ix]; var h11 := g[(iz + 1) * TG + ix + 1]
			var x0 := ix * TSTEP; var z0 := iz * TSTEP
			var a := Vector3(x0, h00, z0); var b := Vector3(x0 + TSTEP, h10, z0)
			var c := Vector3(x0 + TSTEP, h11, z0 + TSTEP); var d := Vector3(x0, h01, z0 + TSTEP)
			var s1 := clampf((absf(h10 - h00) + absf(h11 - h10)) / TSTEP * 2.0 - 0.3, 0.0, 1.0)
			var s2 := clampf((absf(h11 - h01) + absf(h01 - h00)) / TSTEP * 2.0 - 0.3, 0.0, 1.0)
			if _portal_cut.blocked(_tile_origin + Vector2(x0 + 5.0, z0 + 5.0), 8.0):
				# Pas de 2,5 m uniquement autour des portails : entrée nette, coût borné.
				for dz in 4:
					for dx in 4:
						var points: Array[Vector3] = []
						for delta in [Vector2.ZERO, Vector2(2.5,0), Vector2(2.5,2.5), Vector2(0,2.5)]:
							var p: Vector2 = Vector2(x0 + dx * 2.5, z0 + dz * 2.5) + delta
							points.append(Vector3(p.x, height_city(p.x + _tile_origin.x, p.y + _tile_origin.y), p.y))
						_portal_ground_tri(S, points[0], points[1], points[2], ground)
						_portal_ground_tri(S, points[0], points[2], points[3], ground)
			else:
				S.tri(a, b, c, ground.lerp(steep, s1), -1.0)
				S.tri(a, c, d, ground.lerp(steep, s2), -1.0)

## Fraction [0, 1] du segment a→b (repère ville) libre d'obstacle : emprises réelles des bâtiments (polygones
## extrudés), houppiers (ellipsoïdes). 1.0 = libre.
func camera_clear(a: Vector3, b: Vector3) -> float:
	var best := 1.0
	var seg := Rect2(Vector2(a.x, a.z), Vector2.ZERO).expand(Vector2(b.x, b.z)).grow(1.0)
	var L := a.distance_to(b)
	if L < 0.01: return 1.0
	for k in built:
		var o := Vector2(k.x * tile_m, k.y * tile_m)
		if not Rect2(o, Vector2(tile_m, tile_m)).intersects(seg): continue
		var a2 := Vector2(a.x, a.z) - o; var b2 := Vector2(b.x, b.z) - o
		var seg_l := seg; seg_l.position -= o
		for ob in built[k].get_meta("camera_boxes", []):
			if ob is AABB: continue
			if int(ob[0]) == 0:
				if not (ob[4] as Rect2).intersects(seg_l): continue
				var ring: PackedVector2Array = ob[1]
				var y0: float = ob[2]; var y1: float = ob[3]
				if Geometry2D.is_point_in_polygon(b2, ring) and b.y > y0 and b.y < y1: best = minf(best, 0.999)
				for i in ring.size():
					var x = Geometry2D.segment_intersects_segment(a2, b2, ring[i], ring[(i + 1) % ring.size()])
					if x == null: continue
					var t: float = a2.distance_to(x) / maxf(a2.distance_to(b2), 0.001)
					var y := lerpf(a.y, b.y, t)
					if y > y0 and y < y1: best = minf(best, t)
			else:
				# ellipsoïde (rayon horizontal r, demi-hauteur hh) : entrée du segment
				var c: Vector3 = ob[1] + Vector3(o.x, 0, o.y)
				var r: float = ob[2]; var hh: float = ob[3]
				var sa := Vector3((a.x - c.x) / r, (a.y - c.y) / hh, (a.z - c.z) / r)
				var sb := Vector3((b.x - c.x) / r, (b.y - c.y) / hh, (b.z - c.z) / r)
				var d := sb - sa
				var qa := d.dot(d); var qb := 2.0 * sa.dot(d); var qc := sa.dot(sa) - 1.0
				var disc := qb * qb - 4.0 * qa * qc
				if disc < 0.0 or qa < 1e-6: continue
				var t0 := (-qb - sqrt(disc)) / (2.0 * qa); var t1 := (-qb + sqrt(disc)) / (2.0 * qa)
				if t1 < 0.0 or t0 > 1.0: continue
				best = minf(best, maxf(t0, 0.0))
	for ob in _authored_camera_blocks:
		if not (ob[3] as Rect2).intersects(seg): continue
		var poly: PackedVector2Array = ob[0]
		var pa := Vector2(a.x, a.z); var pb := Vector2(b.x, b.z)
		if Geometry2D.is_point_in_polygon(pb, poly) and b.y > ob[1] and b.y < ob[2]: best = minf(best, .999)
		for i in poly.size():
			var hit: Variant = Geometry2D.segment_intersects_segment(pa, pb, poly[i], poly[(i + 1) % poly.size()])
			if hit == null: continue
			var t := pa.distance_to(hit) / maxf(pa.distance_to(pb), .001)
			var y := lerpf(a.y, b.y, t)
			if y > ob[1] and y < ob[2]: best = minf(best, t)

	return best

var _cam_turn := 0.0   # dernière rotation d'orbite retenue (stabilité d'une image à l'autre)
const CAM_MIN := 6.0
const CAM_MARGIN := 1.2

## Position de caméra 3e personne qui ne traverse ni mur ni houppier : l'orbite tourne d'abord autour de la cible
## (rotation la plus faible, de préférence du côté déjà retenu), puis la caméra se rapproche sans descendre sous
## 6 m, enfin elle s'élève au-dessus de l'obstacle.
func avoid_camera(target_net: Vector3, desired_net: Vector3) -> Vector3:
	var a := Vector3((target_net.x - position.x) / _x_scale, target_net.y, target_net.z - position.z)
	var b := Vector3((desired_net.x - position.x) / _x_scale, desired_net.y, desired_net.z - position.z)
	var off := b - a
	var L := off.length()
	if L < 0.1: return desired_net
	var ext := (L + CAM_MARGIN) / L
	var angles := [0.0]
	for s in [0.25, 0.5, 0.75, 1.0, 1.3, 1.6, 2.0]:
		var first := signf(_cam_turn) if _cam_turn != 0.0 else 1.0
		angles.append(s * first); angles.append(-s * first)
	if _cam_turn != 0.0 and absf(_cam_turn) <= 2.0: angles.insert(1, _cam_turn)
	var result := Vector3.INF
	var best_t := -1.0; var best_ang := 0.0
	for ang in angles:
		var o2 := off.rotated(Vector3.UP, ang)
		var p := a + o2
		p.y = maxf(p.y, height_city(p.x, p.z) + 1.5)
		var t := camera_clear(a, a + (p - a) * ext)
		if t >= 0.999:
			result = p; _cam_turn = ang; break
		if t > best_t: best_t = t; best_ang = ang
	if result == Vector3.INF:
		_cam_turn = best_ang
		var o2 := off.rotated(Vector3.UP, best_ang)
		var dist := maxf(best_t * L * ext - CAM_MARGIN, CAM_MIN)
		result = a + o2 * (dist / L)
		# encore dans un obstacle (moins de 6 m dégagés) : s'élever au-dessus
		var lift := 0.0
		while lift < 40.0 and camera_clear(a, result + Vector3(0, lift, 0) + o2.normalized() * CAM_MARGIN) < 0.999:
			lift += 3.0
		result.y += lift
	result.y = maxf(result.y, height_city(result.x, result.z) + 1.5)
	return Vector3(result.x * _x_scale + position.x, result.y, result.z + position.z)

## Couleur de toit relevée sur l'orthophoto (RGB444). L'import (ign_scene.roof_rgb444) l'éclaircit (×1,12 + 0,05) et
## la sature (×1,3) pour l'ancienne double conversion gamma : on revient à la teinte apparente mesurée.
static func _ortho_roof(code: int) -> Color:
	var c := Color(((code >> 8) & 15) / 15.0, ((code >> 4) & 15) / 15.0, (code & 15) / 15.0)
	# moyenne orthophoto = pans au soleil ET à l'ombre (×0,9 sur la valeur) ; voile bleuté de l'ortho retiré
	# tuiles rouges/orangées : saturation modérée (centres anciens trop orangés en vue aérienne sinon)
	var sat := c.s / 1.3 * (0.45 if c.h > 0.5 and c.h < 0.85 else (0.75 if c.h < 0.12 or c.h > 0.94 else 1.0))
	return Color.from_hsv(c.h, sat, clampf((c.v - 0.05) / 1.12 * 0.9, 0.0, 1.0))

var _water_cur: Array = []          # triangles d'eau de la tuile en cours : [PackedVector2Array(3), Rect2]
var _water_tops: Array = []         # plans d'eau posés sur le relief lointain : [Rect2, niveau]
var _track_pts: Dictionary = {}     # Vector2i (cellules de 16 m) -> PackedVector3Array (voie, repère ville)

## Vrai si le point (repère tuile) est dans un plan d'eau de la tuile en cours.
func _in_water(p: Vector2) -> bool:
	for w in _water_cur:
		if (w[1] as Rect2).has_point(p) and Geometry2D.point_is_inside_triangle(p, w[0][0], w[0][1], w[0][2]): return true
	return false

## Profil 3D des voies (repère de la ligne) : découpe des plans d'eau là où la voie passe au niveau de l'eau.
func set_track_profile(pts_net: PackedVector3Array) -> void:
	_track_pts.clear(); _track_dirs.clear()
	var cs := PackedVector3Array()
	for q in pts_net: cs.append(Vector3((q.x - position.x) / _x_scale, q.y, q.z - position.z))
	for i in cs.size():
		var c := cs[i]
		# direction locale : voisins du même tronçon (points consécutifs à moins de 8 m)
		var a := cs[i - 1] if i > 0 and cs[i - 1].distance_to(c) < 8.0 else c
		var b := cs[i + 1] if i + 1 < cs.size() and cs[i + 1].distance_to(c) < 8.0 else c
		var d := Vector2(b.x - a.x, b.z - a.z).normalized()
		var ck := Vector2i(floori(c.x / 16.0), floori(c.z / 16.0))
		if not _track_pts.has(ck): _track_pts[ck] = PackedVector3Array(); _track_dirs[ck] = PackedVector2Array()
		_track_pts[ck].append(c); _track_dirs[ck].append(d)
	_fit_decks_to_tracks()

var _track_dirs: Dictionary = {}    # mêmes cellules que _track_pts : direction horizontale de la voie

## Points de voie (repère ville) à moins de r (horizontal) de p ; `dirs` reçoit leurs directions.
func _tracks_near(p: Vector2, r: float, dirs: Array = []) -> PackedVector3Array:
	var out := PackedVector3Array()
	for cx in range(floori((p.x - r) / 16.0), floori((p.x + r) / 16.0) + 1):
		for cz in range(floori((p.y - r) / 16.0), floori((p.y + r) / 16.0) + 1):
			var ck := Vector2i(cx, cz)
			var pts: PackedVector3Array = _track_pts.get(ck, PackedVector3Array())
			for i in pts.size():
				if Vector2(pts[i].x, pts[i].z).distance_to(p) <= r:
					out.append(pts[i]); dirs.append(_track_dirs[ck][i])
	return out

const GAUGE_H := 4.2       # gabarit de la rame : hauteur au-dessus du rail (caisse + pantographe abaissé + marge)
const GAUGE_HW := 3.1      # demi-largeur couverte autour de l'axe des voies (entraxe 3,5 m + demi-caisse 1,33 m)

## Tabliers BD TOPO et voie (tabliers rééchantillonnés tous les 5 m) : (1) tablier emprunté par la voie (route et
## tram sur le même pont, ex. pont Jeanne-d'Arc à Rouen) : calé sur le profil du rail ; (2) tablier qui franchit la
## voie dans le gabarit : relevé au-dessus (rampes à 8 %). Les piles dans le gabarit sont retirées (deck_piles).
func _fit_decks_to_tracks() -> void:
	if _track_pts.is_empty(): return
	var touched := false
	for di in _decks.size():
		var d: Array = _decks[di]
		var pl: PackedVector3Array = d[2]
		var hw := float(d[1]) * 0.5
		var lo := Vector2(INF, INF); var hi := -lo
		for q in pl: lo = lo.min(Vector2(q.x, q.z)); hi = hi.max(Vector2(q.x, q.z))
		if _tracks_near((lo + hi) * 0.5, (hi - lo).length() * 0.5 + hw + 8.0).is_empty(): continue
		var rs := PackedVector3Array()
		for m in range(pl.size() - 1):
			var n := maxi(1, ceili(Vector2(pl[m].x, pl[m].z).distance_to(Vector2(pl[m + 1].x, pl[m + 1].z)) / 5.0))
			for j in n: rs.append(pl[m].lerp(pl[m + 1], float(j) / n))
		rs.append(pl[pl.size() - 1])
		var fixed := PackedByteArray(); fixed.resize(rs.size())
		var changed := false
		for pass_ in 4:
			var moved := false
			var raise := PackedFloat32Array(); raise.resize(rs.size()); raise.fill(-INF)
			for j in rs.size():
				var c := _deck_conflict(rs, j, hw, pass_ == 0)
				# franchissement contre une partie portée (bretelle, courbe) : la rampe recouperait le gabarit, on porte
				if not is_nan(c.y) and is_nan(c.x) and pass_ > 0 and ((j > 0 and fixed[j - 1] == 1) or (j + 1 < rs.size() and fixed[j + 1] == 1)):
					c.x = c.y - GAUGE_H - 2.0 - 0.1
				if not is_nan(c.x) and (fixed[j] == 0 or rs[j].y > c.x):
					if absf(rs[j].y - c.x) > 0.01: rs[j].y = c.x; moved = true
					fixed[j] = 1
				elif not is_nan(c.y) and fixed[j] == 0: raise[j] = c.y
			for j in rs.size():
				if raise[j] == -INF: continue
				for k in rs.size():   # rampe à 8 % de part et d'autre (sauf sur la voie portée)
					var y := raise[j] - absf(float(k - j)) * 5.0 * 0.08
					if y > rs[k].y + 0.01 and fixed[k] == 0: rs[k].y = y; moved = true
			# raccord des parties libres à la voie portée : pente bornée à 8 % (pas de marche)
			for j in rs.size():
				if fixed[j] == 0: continue
				for k in rs.size():
					if fixed[k] == 1: continue
					var lim := absf(float(k - j)) * 5.0 * 0.08
					var y := clampf(rs[k].y, rs[j].y - lim, rs[j].y + lim)
					if absf(y - rs[k].y) > 0.01: rs[k].y = y; moved = true
			changed = changed or moved
			if not moved: break
		if changed:
			d[2] = rs; touched = true
	if touched: _index_decks()
	_enforce_gauge()
	_cut_conflicts()

## Dernier recours : segment de tablier qui reste dans le gabarit d'une voie (voie passant sous un tablier fusionné
## trop large, ou à la fois portée et franchie) retiré, le tablier étant scindé de part et d'autre (même règle que
## tests/test_clearance.gd : dessus à plus de 0,25 m au-dessus du rail et sous-face sous le gabarit).
func _cut_conflicts() -> void:
	var bad := {}   # tablier -> {segment: true}
	for q in _gauge_pts:
		var c := Vector2(q.x, q.z)
		for it in _deck_cells.get(Vector2i(floori(c.x / 32.0), floori(c.y / 32.0)), []):
			var d: Array = _decks[it[0]]
			var pl: PackedVector3Array = d[2]
			var m: int = it[1]
			var a := Vector2(pl[m].x, pl[m].z); var b := Vector2(pl[m + 1].x, pl[m + 1].z)
			var t := clampf((c - a).dot(b - a) / maxf((b - a).length_squared(), 1e-4), 0.0, 1.0)
			if (a + (b - a) * t).distance_to(c) > float(d[1]) * 0.5 + 1.6: continue   # demi-caisse (tests/test_clearance.gd)
			var y := lerpf(pl[m].y, pl[m + 1].y, t)
			if y > q.y + 0.22 and y - 1.1 < q.y + GAUGE_H + 0.05:
				if not bad.has(it[0]): bad[it[0]] = {}
				bad[it[0]][m] = true
	if bad.is_empty(): return
	var out: Array = []
	for di in _decks.size():
		var d: Array = _decks[di]
		if not bad.has(di): out.append(d); continue
		var pl: PackedVector3Array = d[2]
		var piece := PackedVector3Array()
		for m in pl.size():
			piece.append(pl[m])
			if m < pl.size() - 1 and bad[di].has(m):
				if piece.size() >= 2: out.append([d[0], d[1], piece, d[3]])
				piece = PackedVector3Array()
		if piece.size() >= 2: out.append([d[0], d[1], piece, d[3]])
	_decks.clear(); _decks.append_array(out)   # même tableau (partagé avec le constructeur de tuiles LOD)
	_index_decks()

## Dernier contrôle, point de voie par point de voie (mêmes règles que tests/test_clearance.gd) : un segment de
## tablier encore dans le gabarit est abaissé au rail (moins de 2,5 m au-dessus) ou relevé au-dessus du gabarit.
var _gauge_pts := PackedVector3Array()   # voie tous les 2 m sous ou près des tabliers (repère ville), bind_network

func _enforce_gauge() -> void:
	var pts := _gauge_pts
	if pts.is_empty():
		for ck in _track_pts: pts.append_array(_track_pts[ck])
	for it_ in 3:
		for q in pts:
			var c := Vector2(q.x, q.z)
			for it in _deck_cells.get(Vector2i(floori(c.x / 32.0), floori(c.y / 32.0)), []):
				var d: Array = _decks[it[0]]
				var pl: PackedVector3Array = d[2]
				var m: int = it[1]
				var a := Vector2(pl[m].x, pl[m].z); var b := Vector2(pl[m + 1].x, pl[m + 1].z)
				var t := (c - a).dot(b - a) / maxf((b - a).length_squared(), 1e-4)
				# projection hors du segment (extérieur d'un coude, extrémité) : segment translaté au droit du sommet
				var only := -1
				if t < 0.0: only = m
				elif t > 1.0: only = m + 1
				t = clampf(t, 0.0, 1.0)
				if (a + (b - a) * t).distance_to(c) > float(d[1]) * 0.5 + GAUGE_HW + 0.5: continue
				var y := lerpf(pl[m].y, pl[m + 1].y, t)
				if y <= q.y + 0.02 or y - 1.8 >= q.y + GAUGE_H: continue
				# segment translé verticalement (pente conservée) : au droit de la voie, tablier au rail - 0,1 m ou
				# au-dessus du gabarit
				var shift: float = (q.y - 0.1 - y) if y - q.y < 2.5 else (q.y + GAUGE_H + 2.0 - y)
				for e in ([only] if only >= 0 else [m, m + 1]):
					pl[e].y = minf(pl[e].y, pl[e].y + shift) if shift < 0.0 else maxf(pl[e].y, pl[e].y + shift)
				d[2] = pl

## Sommet j d'un tablier face aux voies : Vector2(altitude si la voie est portée (parallèle), altitude minimale
## si le tablier la franchit dans le gabarit) ; NAN sinon. `merge` : premier passage, la voie parallèle proche
## (jusqu'à 15 m en dessous : tablier BD TOPO mal calé) est considérée comme portée par le tablier.
func _deck_conflict(rs: PackedVector3Array, j: int, hw: float, merge: bool) -> Vector2:
	var a := rs[maxi(j - 1, 0)]; var b := rs[mini(j + 1, rs.size() - 1)]
	var sd := Vector2(b.x - a.x, b.z - a.z).normalized()
	var p := Vector2(rs[j].x, rs[j].z)
	var dirs := []
	var near := _tracks_near(p, hw + GAUGE_HW + 6.0, dirs)
	var ride := NAN; var top := NAN
	# voies portées : altitude de chaque voie interpolée au droit du sommet (points de part et d'autre, même
	# position latérale), tablier à la moyenne des voies portées moins 0,1 m (dévers de quelques cm entre voies)
	var lanes := {}   # position latérale (m) -> [along-, y-, along+, y+]
	for t in near.size():
		var dy := rs[j].y - near[t].y
		var rel := Vector2(near[t].x, near[t].z) - p
		if absf(rel.cross(sd)) > hw + GAUGE_HW + 0.5 or absf(rel.dot(sd)) > 6.0: continue
		var parallel := absf((dirs[t] as Vector2).dot(sd)) > 0.9
		if parallel and dy > (-6.0 if merge else 0.2) and dy < (15.0 if merge else GAUGE_H + 1.7):
			var key := roundi(rel.cross(sd))
			var al := rel.dot(sd)
			var l: Array = lanes.get(key, [-INF, NAN, INF, NAN])
			if al <= 0.0 and al > l[0]: l[0] = al; l[1] = near[t].y
			if al >= 0.0 and al < l[2]: l[2] = al; l[3] = near[t].y
			lanes[key] = l
		elif not parallel and dy > 0.2 and dy < GAUGE_H + 1.7:
			top = maxf(top, near[t].y + GAUGE_H + 2.0) if not is_nan(top) else near[t].y + GAUGE_H + 2.0
	if not lanes.is_empty():
		var acc := 0.0
		for l in lanes.values():
			if is_nan(l[1]): acc += l[3]
			elif is_nan(l[3]): acc += l[1]
			else: acc += lerpf(l[1], l[3], -l[0] / maxf(l[2] - l[0], 0.01))
		ride = acc / lanes.size() - 0.1
	return Vector2(ride, top)

## Culées posées sur le sol affiché (maillage de sol, qui peut différer du MNT de l'import) : extrémité de tablier à
## moins de 2,5 m du sol ramenée au sol, écart réparti linéairement le long du tablier (pente <= 4 %, 10 m au moins).
## Extrémités sur un autre tablier (ouvrages contigus) laissées telles quelles.
func _seat_decks() -> void:
	for di in _decks.size():
		var pl: PackedVector3Array = _decks[di][2]
		if pl.size() < 2: continue
		for end: int in [pl.size() - 1, 0]:   # fin d'abord : un prolongement au début ne décale rien d'autre
			var p := pl[end]
			var other := false
			for it in _deck_cells.get(Vector2i(floori(p.x / 32.0), floori(p.z / 32.0)), []):
				if int(it[0]) != di and absf(deck_city(p.x, p.z, int(it[0])) - p.y) < 0.5: other = true; break
			if other: continue
			var dy := p.y - height_city(p.x, p.z)
			if dy > 2.5:
				# extrémité en l'air : rampe dans l'axe (6 %) jusqu'au sol affiché, 90 m au plus
				var inner := p
				var ii: int = end
				while Vector2(inner.x - p.x, inner.z - p.z).length() < 3.0:
					ii += 1 if end == 0 else -1
					if ii < 0 or ii >= pl.size(): break
					inner = pl[ii]
				if Vector2(inner.x - p.x, inner.z - p.z).length() < 1.0: continue
				var tg := Vector3(p.x - inner.x, 0, p.z - inner.z).normalized()
				var ext := PackedVector3Array()
				var cur := p.y
				var g0 := height_city(p.x, p.z)
				for k in range(1, 19):
					var q := p + tg * 5.0 * k
					var g := height_city(q.x, q.z)
					if g < g0 - 1.0 or not is_nan(water_at(Vector2(q.x, q.z))):
						ext.clear(); break   # vallée ou plan d'eau : pas de rampe vers le fond
					cur -= 0.3
					if cur <= g + 0.05: ext.append(Vector3(q.x, g, q.z)); break
					ext.append(Vector3(q.x, cur, q.z))
				if end == 0:
					ext.reverse(); ext.append_array(pl); pl = ext
				else: pl.append_array(ext)
				continue
			if absf(dy) < 0.02 or absf(dy) > 2.5: continue
			var L := maxf(10.0, absf(dy) / 0.04)
			var acc := 0.0
			var j: int = end
			while true:
				var f := clampf(1.0 - acc / L, 0.0, 1.0)
				if f <= 0.0: break
				pl[j].y -= dy * f
				var nj: int = j + (1 if end == 0 else -1)
				if nj < 0 or nj >= pl.size(): break
				acc += Vector2(pl[nj].x - pl[j].x, pl[nj].z - pl[j].z).length()
				j = nj
		_decks[di][2] = pl
	_index_decks()
	_water_tiles.clear()   # plans d'eau évalués pendant la pose (water_at) : à recalculer avec les tabliers posés

## Index spatial des tabliers (cellules de 32 m).
func _index_decks() -> void:
	_deck_cells.clear()
	for di in _decks.size():
		var pl: PackedVector3Array = _decks[di][2]; var w: float = _decks[di][1]
		for m in range(pl.size() - 1):
			var lo := Vector2(minf(pl[m].x, pl[m + 1].x), minf(pl[m].z, pl[m + 1].z)) - Vector2.ONE * w
			var hi := Vector2(maxf(pl[m].x, pl[m + 1].x), maxf(pl[m].z, pl[m + 1].z)) + Vector2.ONE * w
			for cx in range(floori(lo.x / 32.0), floori(hi.x / 32.0) + 1):
				for cz in range(floori(lo.y / 32.0), floori(hi.y / 32.0) + 1):
					var ck := Vector2i(cx, cz)
					if not _deck_cells.has(ck): _deck_cells[ck] = []
					_deck_cells[ck].append([di, m])

## Piles d'un tablier (repère ville) : [position du sommet (x, y du tablier, z), altitude du sol]. Une pile tous les
## 28 m là où le tablier est à plus de 3 m du sol, jamais dans le gabarit d'une voie passant dessous.
func deck_piles(d: Array) -> Array:
	var out := []
	var pl: PackedVector3Array = d[2]
	var hw: float = float(d[1]) * 0.5
	var acc := 0.0
	for i in range(pl.size() - 1):
		var a := pl[i]; var b := pl[i + 1]
		var dir := Vector3(b.x - a.x, 0, b.z - a.z)
		var len := dir.length()
		if len < 0.05: continue
		dir /= len
		var n := Vector3(-dir.z, 0, dir.x) * hw
		var s := fposmod(-acc, 28.0)
		while s < len:
			var p := a + (b - a) * (s / len)
			var gh := height_city(p.x, p.z)
			if p.y - gh > 3.0:
				for side in ([-0.5, 0.5] if hw > 4.0 else [0.0]):
					var c: Vector3 = p + n * side
					var hit := false
					for q in _tracks_near(Vector2(c.x, c.z), GAUGE_HW + 3.5):
						if q.y > gh - 6.0 and q.y < p.y - 0.5: hit = true; break
					if not hit: out.append([c, gh])
			s += 28.0
		acc += len
	return out

## Triangle d'eau (repère tuile) à retirer : voie en trémie ou au niveau de l'eau dessous (zone couverte), ou
## tablier de pont plus bas que l'eau (données incohérentes).
func _water_cut(a: Vector2, b: Vector2, c: Vector2, y: float) -> bool:
	var r := Rect2(a, Vector2.ZERO).expand(b).expand(c).grow(4.0)
	r.position += _tile_origin
	for cx in range(floori(r.position.x / 16.0), floori(r.end.x / 16.0) + 1):
		for cz in range(floori(r.position.y / 16.0), floori(r.end.y / 16.0) + 1):
			for q in _track_pts.get(Vector2i(cx, cz), PackedVector3Array()):
				if q.y < y + 1.2 and q.y > y - 6.0 and r.has_point(Vector2(q.x, q.z)):
					# voie dans le triangle (grands triangles de fleuve : une voie de quai voisine ne le vide pas)
					var ql := Vector2(q.x, q.z) - _tile_origin
					if Geometry2D.point_is_inside_triangle(ql, a, b, c) or Geometry2D.get_closest_point_to_segment(ql, a, b).distance_to(ql) < 4.0 \
							or Geometry2D.get_closest_point_to_segment(ql, b, c).distance_to(ql) < 4.0 or Geometry2D.get_closest_point_to_segment(ql, c, a).distance_to(ql) < 4.0:
						return true
	var m := (a + b + c) / 3.0 + _tile_origin
	var dk := deck_city(m.x, m.y)
	return not is_nan(dk) and dk < y - 0.3   # tablier sous l'eau (données incohérentes) ; une culée au ras de l'eau ne vide pas le fleuve

## Niveau de l'eau affichée au point p (repère ville), NAN hors eau (mêmes règles que _build_tile ; tests).
var _water_tiles: Dictionary = {}   # Vector2i -> Array de [a, b, c, niveau] (repère tuile), triangles affichés
func water_at(p: Vector2) -> float:
	var k := Vector2i(floori(p.x / tile_m), floori(p.y / tile_m))
	if not table.has(k) or not has_terrain: return NAN
	if not _water_tiles.has(k):
		var keep := _tile_origin
		_tile_origin = Vector2(k.x * tile_m, k.y * tile_m)
		var list := []
		var o: int = _tile_data(k)
		var nb := buf.decode_u16(o); o += 2
		for b in nb:
			var n := buf.decode_u8(o); o += (5 if v2 else 4) + n * 4
			o += 1 + buf.decode_u8(o) * 3
		var np := buf.decode_u16(o); o += 2
		for pi in np:
			var cls := buf.decode_u8(o); var nv := buf.decode_u16(o + 1); var ntr := buf.decode_u16(o + 3); o += 5
			var v := PackedVector2Array(); v.resize(nv)
			for i in nv:
				v[i] = Vector2(buf.decode_s16(o) * 0.1, buf.decode_s16(o + 2) * 0.1); o += 4
			var tris := o; o += ntr * 6
			if cls != P_WATER: continue
			var y := _water_level(k, v) + 0.03
			for t in ntr:
				var a := v[buf.decode_u16(tris + t * 6)]; var b := v[buf.decode_u16(tris + t * 6 + 2)]; var c := v[buf.decode_u16(tris + t * 6 + 4)]
				if not _water_cut(a, b, c, y): list.append([a, b, c, y])
		_water_tiles[k] = list
		_tile_origin = keep
	var lp := p - Vector2(k.x * tile_m, k.y * tile_m)
	var res := NAN
	for w in _water_tiles[k]:
		if Geometry2D.point_is_inside_triangle(lp, w[0], w[1], w[2]):
			res = w[3] if is_nan(res) else maxf(res, w[3])
	return res

## Niveau d'un plan d'eau (repère tuile) : échantillon BD TOPO le plus proche, toujours SOUS la berge la plus
## basse (−0,15 m ; les échantillons BD TOPO sont souvent 1 m au-dessus du MNT, jusqu'à +30 m à Mulhouse), mais
## au-dessus du fond du lit (quartile bas du MNT dans le polygone) pour rester visible.
func _water_level(k: Vector2i, verts: PackedVector2Array) -> float:
	var c := Vector2.ZERO
	for q in verts: c += q
	c /= maxf(verts.size(), 1)
	var best := INF; var lv := NAN
	for w in _water_lv.get(k, []):
		var d := Vector2(w.x, w.z).distance_squared_to(c)
		if d < best: best = d; lv = w.y
	var bank := INF
	for q in verts: bank = minf(bank, _ground_h(q))
	var inner := PackedFloat32Array()
	for i in verts.size():
		inner.append(_ground_h(verts[i].lerp(c, 0.5)))
	inner.append(_ground_h(c))
	inner.sort()
	if is_nan(lv) and terrain != null:   # niveau inconnu (lacs) : le MNT donne la surface ; eau posée dessus
		return maxf(bank, inner[inner.size() - 1]) + 0.1
	var bed := inner[inner.size() / 4] + 0.05
	var y := minf(lv if not is_nan(lv) else bank, bank - 0.15)
	if y < bed: y = minf(bed, bank + 0.25)
	# lit non abaissé (grands plans d'eau couvrant la tuile) : l'eau ne passe pas sous le sol intérieur, sauf
	# écart important (bassin encaissé, voie en contrebas : le niveau mesuré prime)
	var top := inner[inner.size() - 1] + 0.05
	return top if top > y and top - y < 1.5 else y

## Tablier de pont BD TOPO (route ou voie ferrée) : dalle, garde-corps, piles jusqu'au sol (ou au lit de la rivière).
func _deck(S: _Arrays, d: Array) -> void:
	var pl: PackedVector3Array = d[2]
	var hw: float = float(d[1]) * 0.5
	var o := Vector3(_tile_origin.x, 0, _tile_origin.y)
	var concrete := Color("#b9b3a7"); var rail := Color("#d6d1c6")
	for i in range(pl.size() - 1):
		var a := pl[i] - o; var b := pl[i + 1] - o
		var dir := Vector3(b.x - a.x, 0, b.z - a.z)
		var len := dir.length()
		if len < 0.05: continue
		dir /= len
		var n := Vector3(-dir.z, 0, dir.x) * hw
		# épaisseur : dalle routière 1,2 m, tablier ferroviaire ou mixte 1,8 m (poutres), lisible de loin
		var dn := Vector3(0, -1.2 if int(d[0]) == 0 else -1.8, 0)
		# dalle : rives et sous-face
		S.quad(a + n, b + n, b + n + dn, a + n + dn, concrete, -1.0)
		S.quad(b - n, a - n, a - n + dn, b - n + dn, concrete, -1.0)
		S.quad(a + n + dn, b + n + dn, b - n + dn, a - n + dn, concrete.darkened(0.25), -1.0)
		S.quad(a - n, b - n, b + n, a + n, Color("#7d7f83"), -1.0)
		# corniche en saillie, bordure basse et garde-corps métallique (lisses, montants tous les ~2,5 m)
		var iron := Color("#4f5a61", SOLID_A)
		for side in [-1.0, 1.0]:
			var e: Vector3 = n * side
			var eo: Vector3 = n.normalized() * side * (hw + 0.18)
			S.quad(a + eo + Vector3(0, -0.5, 0), b + eo + Vector3(0, -0.5, 0), b + eo + Vector3(0, 0.3, 0), a + eo + Vector3(0, 0.3, 0), Color("#d9d3c6", SOLID_A), -1.0)
			S.quad(a + e * 0.96 + Vector3(0, 0.3, 0), b + e * 0.96 + Vector3(0, 0.3, 0), b + eo + Vector3(0, 0.3, 0), a + eo + Vector3(0, 0.3, 0), Color("#e2ddd2", SOLID_A), -1.0)
			S.quad(a + eo + Vector3(0, -0.5, 0), b + eo + Vector3(0, -0.5, 0), b + e + Vector3(0, -0.65, 0), a + e + Vector3(0, -0.65, 0), Color("#a9a396", SOLID_A), -1.0)
			S.quad(a + e * 0.96, b + e * 0.96, b + e * 0.96 + Vector3(0, 0.3, 0), a + e * 0.96 + Vector3(0, 0.3, 0), rail, -1.0)
			for yy in [0.62, 1.05]:
				var y3 := Vector3(0, yy, 0)
				S.quad(a + e * 0.98 + y3, b + e * 0.98 + y3, b + e * 0.98 + y3 + Vector3(0, 0.06, 0), a + e * 0.98 + y3 + Vector3(0, 0.06, 0), iron, -1.0)
			var posts := maxi(1, int(len / 2.5))
			for k in posts:
				var m := a.lerp(b, (k + 0.5) / posts) + e * 0.98
				S.box(m + Vector3(0, 0.7, 0), Vector3(0.05, 0.8, 0.05), iron)
	# about de tablier : face fermée aux extrémités (pas de vide entre la dalle et la culée)
	for end in [0, pl.size() - 1]:
		if pl.size() < 2: break
		var e0 := pl[end] - o; var e1 := pl[1 if end == 0 else end - 1] - o
		var dir2 := Vector3(e0.x - e1.x, 0, e0.z - e1.z).normalized()
		var n2 := Vector3(-dir2.z, 0, dir2.x) * hw
		var th2 := 1.2 if int(d[0]) == 0 else 1.8
		S.quad(e0 - n2, e0 + n2, e0 + n2 + Vector3(0, -th2, 0), e0 - n2 + Vector3(0, -th2, 0), Color("#b9b3a7"), -1.0)
		S.quad(e0 + n2, e0 - n2, e0 - n2 + Vector3(0, -th2, 0), e0 + n2 + Vector3(0, -th2, 0), Color("#b9b3a7"), -1.0)
	# piles (hors gabarit des voies)
	for pile in deck_piles(d):
		var c: Vector3 = pile[0] - o; var gh: float = pile[1]
		var th := 1.2 if int(d[0]) == 0 else 1.8
		var hgt: float = c.y - th - gh + 1.5
		S.box(Vector3(c.x, gh - 1.5 + hgt * 0.5, c.z), Vector3(1.5, hgt - 0.6, 1.5), concrete.darkened(0.08))
		S.box(Vector3(c.x, c.y - th - 0.3, c.z), Vector3(2.4, 0.6, 2.0), concrete.darkened(0.03))   # chevêtre

# ----------------------------------------------------------------------------------------------- bâtiments

const STONE := Color("#ddd3c0")
const SLATE := Color("#4b5057")   # ardoise : gris anthracite (orthophoto), plus de lavande
const ZINC := Color("#7e8a95")
const GLASS_SHOP := 0.45     # alpha des vitrines (éclairées la nuit)
const SOLID_A := 0.35        # alpha sans fenêtres

## Halle à voûte (gare) : rectangle orienté de l'emprise, murs bas en pierre claire, berceau vitré à 8 pans dans
## l'axe le plus long, arcs métalliques tous les 12 m, pignons vitrés.
func _vault(S: _Arrays, ring: PackedVector2Array, h: float) -> void:
	var best := INF; var ax := Vector2.RIGHT; var lo := Vector2.ZERO; var hi := Vector2.ZERO
	for i in ring.size():
		var d := (ring[(i + 1) % ring.size()] - ring[i]).normalized()
		if d.length_squared() < 0.5: continue
		var nn := Vector2(-d.y, d.x)
		var a := Vector2(INF, INF); var b := Vector2(-INF, -INF)
		for q in ring:
			var u := Vector2(q.dot(d), q.dot(nn)); a = a.min(u); b = b.max(u)
		var ar := (b.x - a.x) * (b.y - a.y)
		if ar < best: best = ar; ax = d; lo = a; hi = b
	var nrm := Vector2(-ax.y, ax.x)
	if hi.x - lo.x < hi.y - lo.y:   # axe long
		var t := ax; ax = nrm; nrm = -t
		var a2 := Vector2(INF, INF); var b2 := Vector2(-INF, -INF)
		for q in ring:
			var u := Vector2(q.dot(ax), q.dot(nrm)); a2 = a2.min(u); b2 = b2.max(u)
		lo = a2; hi = b2
	var w := hi.y - lo.y
	var wall_h := clampf(h * 0.35, 3.0, 8.0)
	var rise := clampf(w * 0.32, 4.0, maxf(4.0, h + 6.0 - wall_h))
	var P := func(u: float, v: float, y: float) -> Vector3:
		var q: Vector2 = ax * u + nrm * v
		return Vector3(q.x, y, q.y)
	var stone := Color("#d9d2c2", SOLID_A); var glass := Color("#9fb6c3", SOLID_A); var iron := Color("#4f5a61", SOLID_A)
	# murs bas
	var c4 := [Vector2(lo.x, lo.y), Vector2(hi.x, lo.y), Vector2(hi.x, hi.y), Vector2(lo.x, hi.y)]
	for i in 4:
		var a: Vector2 = c4[i]; var b: Vector2 = c4[(i + 1) % 4]
		S.quad(P.call(a.x, a.y, 0.0), P.call(b.x, b.y, 0.0), P.call(b.x, b.y, wall_h), P.call(a.x, a.y, wall_h), stone, -1.0)
	var seg := 8
	var prof: Array[Vector2] = []
	for k in seg + 1:
		var th := PI * float(k) / seg
		prof.append(Vector2(lo.y + w * 0.5 * (1.0 - cos(th)), wall_h + rise * sin(th)))
	for k in seg:
		var a: Vector2 = prof[k]; var b: Vector2 = prof[k + 1]
		S.quad(P.call(lo.x, a.x, a.y), P.call(hi.x, a.x, a.y), P.call(hi.x, b.x, b.y), P.call(lo.x, b.x, b.y), glass, -1.0)
	for u in [lo.x, hi.x]:   # pignons vitrés
		var mid: Vector3 = P.call(u, lo.y + w * 0.5, wall_h)
		for k in seg:
			S.tri(mid, P.call(u, prof[k].x, prof[k].y), P.call(u, prof[k + 1].x, prof[k + 1].y), glass)
	var u2 := lo.x
	while u2 <= hi.x:   # arcs métalliques
		for k in seg:
			var a: Vector2 = prof[k]; var b: Vector2 = prof[k + 1]
			S.quad(P.call(u2 - 0.3, a.x, a.y + 0.15), P.call(u2 + 0.3, a.x, a.y + 0.15), P.call(u2 + 0.3, b.x, b.y + 0.15), P.call(u2 - 0.3, b.x, b.y + 0.15), iron, -1.0)
		u2 += 12.0

func _wall_a(seed: int) -> float:
	return 0.52 + float(style.get("masonry",2))*0.1 + float(absi(seed)%97)*0.0008

func _centroid(ring: PackedVector2Array) -> Vector2:
	var c := Vector2.ZERO
	for p in ring: c += p
	return c / ring.size()

func _area(ring: PackedVector2Array) -> float:
	var a := 0.0
	for i in ring.size(): a += ring[i].cross(ring[(i + 1) % ring.size()]) * 0.5
	return absf(a)

## Murs entre y0 et y1 (UV = abscisse, hauteur : fenêtres procédurales si alpha > 0.5).
func _walls(S: _Arrays, ring: PackedVector2Array, y0: float, y1: float, col: Color, windows: bool = true) -> void:
	var u := 0.0
	for i in ring.size():
		var a := ring[i]; var b := ring[(i + 1) % ring.size()]
		var len := a.distance_to(b)
		if windows: S.wall(Vector3(a.x, y0, a.y), Vector3(b.x, y0, b.y), y1 - y0, col, u, u + len)
		else: S.wall(Vector3(a.x, y0, a.y), Vector3(b.x, y0, b.y), y1 - y0, col, 0.0, 0.0)
		u += len

func _flat_roof(S: _Arrays, ring: PackedVector2Array, idx: PackedByteArray, y: float, col: Color) -> void:
	col.a = SOLID_A
	for t in range(0, idx.size(), 3):
		var a := ring[idx[t]]; var b := ring[idx[t + 1]]; var c := ring[idx[t + 2]]
		S.tri(Vector3(a.x, y, a.y), Vector3(b.x, y, b.y), Vector3(c.x, y, c.y), col, -1.0)

func _hip_roof(S: _Arrays, ring: PackedVector2Array, y: float, rise: float, col: Color) -> void:
	var c := _centroid(ring)
	var apex := Vector3(c.x, y + rise, c.y)
	for i in ring.size():
		var a := ring[i]; var b := ring[(i + 1) % ring.size()]
		S.tri(Vector3(a.x, y, a.y), Vector3(b.x, y, b.y), apex, Color(col.r, col.g, col.b, SOLID_A), -1.0)

## Toit à deux pans (quadrilatère) : faîtage parallèle au grand côté, pignons maçonnés.
func _gable_roof(S: _Arrays, ring: PackedVector2Array, y: float, rise: float, col: Color, gable_col: Color) -> void:
	var a := ring[0]; var b := ring[1]; var c := ring[2]; var d := ring[3]
	if a.distance_to(b) < b.distance_to(c):
		var t := a; a = b; b = c; c = d; d = t
	var r1 := (d + a) * 0.5; var r2 := (b + c) * 0.5
	var R1 := Vector3(r1.x, y + rise, r1.y); var R2 := Vector3(r2.x, y + rise, r2.y)
	var A := Vector3(a.x, y, a.y); var B := Vector3(b.x, y, b.y); var C := Vector3(c.x, y, c.y); var D := Vector3(d.x, y, d.y)
	col.a = SOLID_A
	S.quad(A, B, R2, R1, col, -1.0)
	S.quad(C, D, R1, R2, Color(col.r * 0.88, col.g * 0.88, col.b * 0.88, SOLID_A), -1.0)
	gable_col.a = SOLID_A
	S.tri(D, A, R1, gable_col, -1.0); S.tri(B, C, R2, gable_col, -1.0)

## Mansarde parisienne : brisis en zinc à forte pente, terrasson presque plat.
func _mansard(S: _Arrays, ring: PackedVector2Array, y: float, col: Color, dormer_bay := 0.0, stone := Color("#ece4d2", SOLID_A)) -> void:
	var c := _centroid(ring)
	var inner := PackedVector2Array()
	for p in ring: inner.append(p + (c - p).limit_length(1.4))
	var u := 0.0
	for i in ring.size():
		var a := ring[i]; var b := ring[(i + 1) % ring.size()]; var ia := inner[i]; var ib := inner[(i + 1) % ring.size()]
		S.quad(Vector3(a.x, y, a.y), Vector3(b.x, y, b.y), Vector3(ib.x, y + 2.8, ib.y), Vector3(ia.x, y + 2.8, ia.y), Color(col.r, col.g, col.b, SOLID_A), -1.0)
		var L := a.distance_to(b)
		if dormer_bay > 0.0 and L > 4.0:
			# P3 : lucarnes au droit des travées (même trame que les baies), à fronton, dans le brisis
			var tt := (b - a) / L; var into := ((ia + ib) * 0.5 - (a + b) * 0.5).normalized()
			var t3 := Vector3(tt.x, 0, tt.y); var o3 := Vector3(-into.x, 0, -into.y)
			var k0 := ceili((u + 1.2) / dormer_bay - 0.5); var k1 := floori((u + L - 1.2) / dormer_bay - 0.5)
			for k in range(k0, mini(k1, k0 + 9) + 1):
				var x := (k + 0.5) * dormer_bay - u
				if (k + i) % 2 == 1 and dormer_bay < 3.0: continue
				var foot := a + tt * x + into * 1.0
				Facades.dormer_pediment(S, Vector3(foot.x, y + 0.3, foot.y), t3, o3, stone, Color(col.r, col.g, col.b, SOLID_A))
			u += L
			continue
		u += L
		# lucarnes
		if a.distance_to(b) > 5.0:
			var m := (a + b) * 0.5 + (c - (a + b) * 0.5).limit_length(0.6)
			S.box(Vector3(m.x, y + 1.4, m.y), Vector3(1.1, 1.3, 1.1), Color("#ece4d2", SOLID_A))
	var apex := Vector3(c.x, y + 3.3, c.y)
	for i in inner.size():
		var a := inner[i]; var b := inner[(i + 1) % inner.size()]
		S.tri(Vector3(a.x, y + 2.8, a.y), Vector3(b.x, y + 2.8, b.y), apex, Color(col.r * 0.92, col.g * 0.92, col.b * 0.92, SOLID_A), -1.0)

## Corniche / balcon filant à la hauteur y.
func _ledge(S: _Arrays, ring: PackedVector2Array, y: float, depth: float, col: Color) -> void:
	var c := _centroid(ring)
	col.a = SOLID_A
	for i in ring.size():
		var a := ring[i]; var b := ring[(i + 1) % ring.size()]
		var oa := a + (a - c).normalized() * depth; var ob := b + (b - c).normalized() * depth
		S.quad(Vector3(a.x, y, a.y), Vector3(b.x, y, b.y), Vector3(ob.x, y, ob.y), Vector3(oa.x, y, oa.y), col, -1.0)
		S.quad(Vector3(oa.x, y - 0.25, oa.y), Vector3(ob.x, y - 0.25, ob.y), Vector3(ob.x, y, ob.y), Vector3(oa.x, y, oa.y), col, -1.0)

## P3 : relief des faces sur rue d'un bâtiment courant (Facades.face_relief) dans la cellule de LOD proche.
func _facade_relief(ring: PackedVector2Array, h: float, fst: int, ftype: int, seed_: int, shop: bool, wall: Color, roof_kind: int) -> void:
	var n := ring.size()
	# près des voies seulement (réseau lié) : le relief se voit depuis la cabine et la vue extérieure
	if not _track_pts.is_empty() and _tracks_near(_tile_origin + _centroid(ring), Facades.TRACK_D).is_empty(): return
	var signed := 0.0
	for i in n: signed += ring[i].cross(ring[(i + 1) % n])
	var accent := Color.from_string(str(style.get("accent", "#44645f")), Color.GRAY)
	var code := float(roundi(wall.a * 1000.0)) if wall.a > 0.5 else float(500 + ftype * 50 + absi(seed_) % 50)
	var u := 0.0
	var faces := 0
	for i in n:
		var a := ring[i]; var b := ring[(i + 1) % n]
		var L := a.distance_to(b)
		if L >= 3.0 and faces < 4:
			var tt := (b - a) / L
			var out := Vector2(tt.y, -tt.x) if signed > 0.0 else Vector2(-tt.y, tt.x)
			if _faces_street((a + b) * 0.5, out):
				Facades.face_relief(_Fcur, a, b, out, u, h, fst, ftype, code, shop, wall, accent, seed_ + i, roof_kind)
				faces += 1
		u += L

## Vrai si une voie passe devant la face (milieu m, normale sortante out) à moins de Facades.STREET_D m.
func _faces_street(m: Vector2, out: Vector2) -> bool:
	var r := Facades.STREET_D
	for x in range(floori((m.x - r) / 16.0), floori((m.x + r) / 16.0) + 1):
		for z in range(floori((m.y - r) / 16.0), floori((m.y + r) / 16.0) + 1):
			for road in _street_keepout.cells.get(Vector2i(x, z), []):
				var q := Geometry2D.get_closest_point_to_segment(m, road[0], road[1])
				var d := q - m
				if d.length() < r and d.dot(out) > 0.5 * d.length() + 0.5: return true
	# plateforme du tramway (places et rues piétonnes traversées par la ligne)
	for q in _tracks_near(m + _tile_origin, r):
		var d := Vector2(q.x, q.z) - _tile_origin - m
		if d.dot(out) > 0.5 * d.length() + 0.5: return true
	return false

## P3 : souches de cheminée sur les pignons d'un toit à deux pans (même faîtage que _gable_roof).
func _gable_chimneys(S: _Arrays, ring: PackedVector2Array, y: float, rise: float, fst: int, wall: Color, seed_: int) -> void:
	var a := ring[0]; var b := ring[1]; var c := ring[2]; var d := ring[3]
	if a.distance_to(b) < b.distance_to(c):
		var t := a; a = b; b = c; c = d; d = t
	var col := Color(wall.r * 0.95, wall.g * 0.93, wall.b * 0.9, SOLID_A) if fst == Facades.ANJOU else Color(0.55, 0.33, 0.26, SOLID_A)
	Facades.gable_chimneys(S, (d + a) * 0.5, (b + c) * 0.5, y, rise, col, seed_)

## P3 : souches sur le terrasson d'un comble brisé (murs mitoyens : sommets de l'emprise les plus proches du centre).
func _roof_chimneys(S: _Arrays, ring: PackedVector2Array, y: float, fst: int, wall: Color, seed_: int) -> void:
	var c := _centroid(ring)
	var col := Color(0.55, 0.33, 0.26, SOLID_A) if fst == Facades.HAUSSMANN else Color(wall.r * 0.95, wall.g * 0.93, wall.b * 0.9, SOLID_A)
	var hs := absi(hash(seed_ * 5 + 3))
	for k in mini(ring.size(), 2 + hs % 2):
		var p := ring[(hs + k * 2) % ring.size()]
		var q := p + (c - p).limit_length(1.9)
		Facades.chimney(S, q, y - 0.3, y + 1.2, (c - p).normalized().orthogonal(), col)

## Tour carrée surmontée d'une flèche (clocher) ou d'un toit bas.
func _tower(S: _Arrays, p: Vector2, side: float, h: float, spire: float, wall: Color, roof: Color) -> void:
	S.box(Vector3(p.x, h * 0.5, p.y), Vector3(side, h, side), Color(wall.r, wall.g, wall.b, SOLID_A))
	S.box(Vector3(p.x, h - 2.5, p.y), Vector3(side * 1.02, 1.4, side * 1.02), Color(0.15, 0.15, 0.17, SOLID_A))  # abat-sons
	if spire > 0.0:
		S.cone(Vector3(p.x, h, p.y), side * 0.62, spire, 8, Color(roof.r, roof.g, roof.b, SOLID_A))

func _round_tower(S: _Arrays, p: Vector2, r: float, h: float, wall: Color, roof: Color, cap: bool, striped: bool) -> void:
	var sides := 10
	for i in sides:
		var a0 := TAU * i / sides; var a1 := TAU * (i + 1) / sides
		var A := p + Vector2(cos(a0), sin(a0)) * r; var B := p + Vector2(cos(a1), sin(a1)) * r
		var y := 0.0
		var band := 0
		while y < h:
			var y1 := minf(h, y + (1.0 if striped else h))     # Angers : bandes d'environ 1 m
			var col := wall
			if striped and band % 2 == 1: col = Color("#5a5d66")   # schiste gris-bleu (tuffeau crème : `wall`)
			S.wall(Vector3(A.x, y, A.y), Vector3(B.x, y, B.y), y1 - y, Color(col.r, col.g, col.b, SOLID_A), 0.0, 0.0)
			y = y1; band += 1
	if cap: S.cone(Vector3(p.x, h, p.y), r * 1.15, r * 2.2, sides, Color(roof.r, roof.g, roof.b, SOLID_A))
	else: S.cone(Vector3(p.x, h, p.y), r, 0.01, sides, Color(wall.r * 0.8, wall.g * 0.8, wall.b * 0.8, SOLID_A))

func _crenels(S: _Arrays, ring: PackedVector2Array, y: float, col: Color) -> void:
	var count := 0
	for i in ring.size():
		var a := ring[i]; var b := ring[(i + 1) % ring.size()]
		var n := int(a.distance_to(b) / 2.2)
		for k in n:
			if k % 2 == 0 and count < 120:
				var m := a.lerp(b, (k + 0.5) / n)
				S.box(Vector3(m.x, y + 0.55, m.y), Vector3(0.9, 1.1, 0.9), Color(col.r, col.g, col.b, SOLID_A))
				count += 1

func _building(S: _Arrays, ring: PackedVector2Array, idx: PackedByteArray, cls: int, h: float, kind_raw: int, seed: int, points: Array, roof_ortho: Color = Color(0, 0, 0, 0)) -> void:
	var principal := (kind_raw & 0x80) != 0
	var kind := kind_raw & 0x07
	# LiDAR HD (tools/import/lidar.py) : bit 6 = hauteur d'égout mesurée, bits 3-5 = hausse du toit (pas de 1,5 m)
	var lidar := (kind_raw & 0x40) != 0
	var lidar_rise := float((kind_raw >> 3) & 7) * 1.5
	var n := ring.size()
	var area := _area(ring)
	var c := _centroid(ring)
	var rng := RandomNumberGenerator.new(); rng.seed = seed
	var pitched := Color.from_string(str(style.get("pitched", "#a65e44")), Color.BROWN)
	var has_ortho := roof_ortho.a > 0.0   # couleur réelle du toit (orthophoto IGN)
	if has_ortho: pitched = roof_ortho
	match kind:
		K_CHURCH, K_CATHEDRAL:
			var stone := STONE.lerp(Color("#3b3a3c"), 0.85) if city == "clermont" else STONE  # Clermont : pierre de Volvic
			_walls(S, ring, 0.0, h, Color(stone.r, stone.g, stone.b, SOLID_A), false)
			var rise := clampf(sqrt(area) * 0.3, 3.0, 16.0)
			if n == 4: _gable_roof(S, ring, h, rise, SLATE, stone)
			else: _hip_roof(S, ring, h, rise, SLATE)
			if not principal and kind == K_CATHEDRAL:
				return  # volumes secondaires (bas-côtés, chapelles) : pas de tours
			# clocher réel (BD TOPO) le plus proche, sinon tour en façade
			var placed := false
			for p in points:
				if p[0] == 1 and p.size() == 3 and (p[2] as Vector2).distance_to(c) < sqrt(area) * 0.9 + 15.0:
					var ht: float = maxf(p[1], h + 12.0)
					_tower(S, p[2], clampf(sqrt(area) * 0.22, 5.0, 12.0), ht * 0.62, ht * 0.38, stone, SLATE)
					p.append(true); placed = true
			if not placed and principal:
				var a := ring[0]; var b := ring[1]
				var front := (a + b) * 0.5 + (c - (a + b) * 0.5).limit_length(3.0)
				if kind == K_CATHEDRAL:
					var dir := (b - a).normalized()
					for s in [-1.0, 1.0]:
						_tower(S, front + dir * s * minf(a.distance_to(b) * 0.33, 14.0), clampf(sqrt(area) * 0.16, 7.0, 14.0), h * 1.75, 6.0, stone, SLATE)
				else:
					_tower(S, front, clampf(sqrt(area) * 0.22, 4.0, 9.0), h + 10.0, 14.0, stone, SLATE)
			return
		K_CASTLE:
			var striped := city == "angers"   # château d'Angers : schiste et tuffeau en bandes
			var stone := Color("#d6ccb8")
			if striped:
				var y := 0.0; var band := 0
				while y < h:
					var y1 := minf(h, y + 1.0)
					_walls(S, ring, y, y1, Color("#5a5d66") if band % 2 == 1 else Color("#ddd3bf"), false)
					y = y1; band += 1
			else:
				_walls(S, ring, 0.0, h, Color(stone.r, stone.g, stone.b, SOLID_A), false)
			_flat_roof(S, ring, idx, h, Color("#8a8278"))
			_crenels(S, ring, h, stone)
			if area > 400.0 and (principal or area > 1500.0):
				for i in n:
					var p := ring[i]; var pa := ring[(i - 1 + n) % n]; var pb := ring[(i + 1) % n]
					if (pa - p).normalized().dot((pb - p).normalized()) > -0.4 and p.distance_to(pa) > 8.0:
						# tours nettement plus hautes que les courtines
						_round_tower(S, p, clampf(sqrt(area) * 0.08, 3.0, 7.0), h + (6.0 if striped else 3.0), Color("#ddd3bf") if striped else stone, SLATE, not striped, striped)
			return
		K_STATION:
			if area > 2500.0:   # grande halle voyageurs : voûte vitrée en long sur arcs métalliques
				_vault(S, ring, h)
				return
			_walls(S, ring, 0.0, h, Color("#e6dfcf", _wall_a(seed)))
			if n == 4: _gable_roof(S, ring, h, clampf(sqrt(area) * 0.18, 2.0, 9.0), Color("#a9c3d1"), Color("#e6dfcf"))
			else: _flat_roof(S, ring, idx, h, Color("#a9c3d1"))
			return
		K_CIVIC:
			var w := Color("#ece4d2"); w.a = _wall_a(seed)
			_walls(S, ring, 0.0, h, w)
			_ledge(S, ring, h - 0.2, 0.4, Color("#f2ebdb"))
			if n <= 8: _hip_roof(S, ring, h, clampf(sqrt(area) * 0.22, 2.5, 9.0), SLATE)
			else: _flat_roof(S, ring, idx, h, SLATE)
			# mât et drapeau tricolore
			S.box(Vector3(c.x, h + 4.0, c.y), Vector3(0.12, 8.0, 0.12), Color(0.85, 0.85, 0.85, SOLID_A))
			for k in 3:
				S.box(Vector3(c.x + 0.35 + k * 0.6, h + 7.2, c.y), Vector3(0.6, 1.2, 0.04), [Color("#1f3b8f"), Color("#f4f4f4"), Color("#d6282f")][k])
			return
		K_SCHOOL:
			var w := Color("#d9b9a0") if style.get("walls", [""])[0] == "#d98a6c" else Color("#e3dccb")
			w.a = _wall_a(seed)
			_walls(S, ring, 0.0, h, w)
			_flat_roof(S, ring, idx, h, Color("#8d8f91"))
			return
	# --- bâti courant : façade par époque et région (CityScene._facade_type), détails sur la façade sur rue
	var windows := cls == 0 or cls == 1 or cls == 4
	var ftype := _facade_type(seed, cls, h, area)
	# P3 : style de façade (quartier, usage, hauteur, emprise) puis appareil imposé par le style
	var fst := Facades.pick(city, _fac_dist, _tile_origin + c, cls, h, area, ftype, seed) if Facades.enabled() else Facades.GENERIC
	ftype = Facades.ftype_for(fst, ftype, seed)
	facade_stats[fst] = int(facade_stats.get(fst, 0)) + 1
	var old_town := fst == Facades.ANJOU or fst == Facades.NANTES_XVIII or fst == Facades.HAUSSMANN
	var wall: Color
	match cls:
		2: wall = Color("#c7c3ba").lerp(Color("#a9b0b5"), (seed % 7) / 7.0)
		3: wall = STONE
		4: wall = Color("#eee6d2")
		5: wall = Color("#b9b6ae")
		_: wall = _facade_color(ftype, seed)
	var paris: bool = style.get("pitched", "") == "#6f7a85" or (city == "idf" and ftype == F_PIERRE)
	var shop := (cls == 1 or (cls == 0 and h > (8.0 if old_town else 11.0) and rng.randf() < (0.7 if old_town else (0.6 if ftype == F_PIERRE or ftype == F_OCRE else 0.4)))) and h > 6.0 and ftype != F_VERRE and fst != Facades.ACTIVITE
	var mansard := (paris and cls == 0 and h > 13.0 and n <= 16) or (fst == Facades.HAUSSMANN and h > 12.0 and n <= 16) \
		or (fst == Facades.NANTES_XVIII and h > 10.0 and n <= 12 and absi(seed) % 2 == 0)
	var y0 := 0.0
	if shop:  # rez-de-chaussée commercial : piliers, vitrines, bandeau d'enseigne (éclairés le soir)
		_walls(S, ring, 0.0, 3.4, Color(wall.r * 0.92, wall.g * 0.92, wall.b * 0.92, GLASS_SHOP), true)
		y0 = 3.4
	if cls != 2: _facade_detail(_D, ring, h, seed, shop, ftype, wall, fst != Facades.GENERIC)
	wall.a = _wall_code(ftype, seed) if windows else SOLID_A
	_walls(S, ring, y0, h, wall, windows)
	if _Fcur != null and not lite and n <= 40 and (windows or fst == Facades.ACTIVITE) and Facades.enabled():
		_facade_relief(ring, h, fst, ftype, seed, shop, wall, 2 if mansard else 0)
	if windows and h > 5.0 and n <= 24:   # soubassement en saillie (pierre plus sombre)
		_plinth(_D, ring, 0.75 if not shop else 0.45, Color(wall.r * 0.72, wall.g * 0.71, wall.b * 0.7))
	if mansard:
		# immeuble haussmannien : balcons filants aux 2e et 5e étages, corniche, mansarde en zinc (relief proche :
		# Facades) ; Nantes XVIIIe : comble brisé en ardoise à lucarnes
		if fst == Facades.GENERIC:
			_ledge(_D, ring, 7.4, 0.8, Color("#e9e1cf"))
			if h > 18.0: _ledge(_D, ring, h - 3.6, 0.8, Color("#e9e1cf"))
		_ledge(_D, ring, h, 0.45, Color("#ece5d4"))
		var g := Facades.bays(ftype, _wall_code(ftype, seed) * 1000.0)
		_mansard(S, ring, h, SLATE if fst == Facades.NANTES_XVIII else ZINC, float(g.bay), Color(wall.r * 1.05, wall.g * 1.05, wall.b * 1.04, SOLID_A))
		_roof_chimneys(S, ring, h + 2.8, fst, wall, seed)
		return
	var sud := ftype == F_OCRE or str(style.get("pitched", "")) in ["#b76c47", "#ad6242", "#b16946", "#b16f4e"]
	# toit à pentes mesuré : emprises simples et moyennes seulement (une grande emprise n'est pas un toit unique),
	# hausse plafonnée par la largeur
	if lidar and lidar_rise > 0.0 and (area > 600.0 or n > 8): lidar_rise = 0.0
	lidar_rise = minf(lidar_rise, sqrt(area) * 0.35)
	if lidar and lidar_rise > 0.0 and n <= 8 and cls != 2:
		if n == 4: _gable_roof(S, ring, h, lidar_rise, pitched if has_ortho or sud else SLATE, wall)
		else: _hip_roof(S, ring, h, lidar_rise, pitched if has_ortho or sud else SLATE)
		if cls == 0 and not sud and h >= 6.0 and lidar_rise > 2.2 and n == 4: _dormers(_D, ring, h, lidar_rise, wall, seed, old_town)
		if n == 4 and fst != Facades.MODERNE and fst != Facades.ACTIVITE: _gable_chimneys(S, ring, h, lidar_rise, fst, wall, seed)
		return
	if lidar and lidar_rise == 0.0 and cls != 2:     # toit plat mesuré
		_flat_roof(S, ring, idx, h, roof_ortho if has_ortho else _pal("roofs", seed / 7))
		if h > 5.0 and n <= 16:
			_ledge(S, ring, h, 0.3, Color(wall.r * 1.08, wall.g * 1.08, wall.b * 1.06))
		return
	if cls == 0 and h <= 12.0 and area < 320.0 and n == 4:
		var rise := clampf(sqrt(area) * (0.22 if sud else 0.35), 1.2, 4.0)
		_gable_roof(S, ring, h, rise, pitched, wall)
		if not sud and h >= 6.0 and rise > 2.2: _dormers(_D, ring, h, rise, wall, seed, old_town)
		if rng.randf() < 0.5:  # cheminée
			_gable_chimneys(S, ring, h, rise, fst, wall, seed)
	elif cls == 0 and h <= 12.0 and n <= 8 and area < 320.0:
		_hip_roof(S, ring, h, clampf(sqrt(area) * (0.2 if sud else 0.3), 1.0, 3.5), pitched)
	elif cls == 0 and h <= 16.0 and n == 4 and area < 600.0 and (ftype == F_PIERRE or ftype == F_TUFFEAU or ftype == F_BRIQUE or ftype == F_ANDESITE or ftype == F_BRIQUE_PIERRE):
		# immeuble ancien de centre : toit à deux pans (ardoise ou tuile), lucarnes sur rue ; Anjou : forte pente
		var rise := clampf(sqrt(area) * (0.42 if fst == Facades.ANJOU else 0.28), 2.0, 6.5 if fst == Facades.ANJOU else 5.0)
		if fst == Facades.GENERIC: _ledge(_D, ring, h, 0.32, Color(wall.r * 1.06, wall.g * 1.06, wall.b * 1.05))
		_gable_roof(S, ring, h, rise, pitched if has_ortho or sud else SLATE, wall)
		if not sud: _dormers(_D, ring, h, rise, wall, seed, old_town)
		_gable_chimneys(S, ring, h, rise, fst, wall, seed)
	elif cls == 2 and area > 600.0:
		_flat_roof(S, ring, idx, h, roof_ortho if has_ortho else Color("#8e9296"))
		# lanterneaux vitrés (sheds)
		var a := ring[0]; var b := ring[1]
		var dir := (b - a).normalized(); var nrm := Vector2(-dir.y, dir.x)
		for k in range(-2, 3):
			var m := c + nrm * k * 6.0
			S.box(Vector3(m.x, h + 0.4, m.y), Vector3(0.1, 0.8, 0.1), Color("#8e9296", SOLID_A))
			S.quad(Vector3(m.x - dir.x * 10.0, h + 0.05, m.y - dir.y * 10.0), Vector3(m.x + dir.x * 10.0, h + 0.05, m.y + dir.y * 10.0),
				Vector3(m.x + dir.x * 10.0 + nrm.x * 2.0, h + 0.9, m.y + dir.y * 10.0 + nrm.y * 2.0), Vector3(m.x - dir.x * 10.0 + nrm.x * 2.0, h + 0.9, m.y - dir.y * 10.0 + nrm.y * 2.0),
				Color(0.55, 0.68, 0.75, SOLID_A), -1.0)
	else:
		var roof := roof_ortho if has_ortho else _pal("roofs", seed / 7)
		_flat_roof(S, ring, idx, h, roof)
		if h > 5.0 and n <= 16 and cls != 2:  # corniche : arête nette en tête de façade
			var stone_ := ftype == F_PIERRE or ftype == F_TUFFEAU or ftype == F_ANDESITE
			_ledge(S, ring, h, 0.42 if stone_ else 0.28, Color(wall.r * 1.08, wall.g * 1.08, wall.b * 1.06))
		if h > 12.0 and n <= 12:   # acrotère
			_walls(S, ring, h, h + 0.6, Color(roof.r * 1.1, roof.g * 1.1, roof.b * 1.1, SOLID_A), false)
		if h > 15.0 and rng.randf() < 0.6:  # édicule technique
			S.box(Vector3(c.x, h + 1.2, c.y), Vector3(3.0, 2.4, 3.0), Color("#b3b0a8", SOLID_A))

const F_ENDUIT := 0
const F_BRIQUE := 1
const F_PIERRE := 2
const F_ANDESITE := 3
const F_TUFFEAU := 4
const F_OCRE := 5
const F_BETON := 6
const F_GRAND_ENSEMBLE := 7
const F_BRIQUE_PIERRE := 8
const F_VERRE := 9
const FACADE_NAMES := ["enduit", "brique", "pierre", "andesite", "tuffeau", "ocre", "beton", "grand_ensemble", "brique_pierre", "verre"]
## Teintes apparentes par type de façade (surchargeables par ville : city_identity.json "facade_colors").
const FACADE_COLORS := [[], ["#9b5a45", "#8e4f3e", "#a8644c", "#7f4a3d"], ["#d9cdb4", "#d3c6aa", "#e0d5be", "#cfc2a6"],
	["#6a6866", "#5d5b5a", "#74716d"], ["#e9e1cc", "#e4dcc5", "#ede6d3"], ["#e0b98a", "#d9a877", "#e6c9a0", "#d79a6e", "#e8d2b0"],
	["#bdb7aa", "#b3ad9f", "#c4bfb3"], ["#e0dcd2", "#d6d0c3", "#cfc8b9", "#e3d9c4"], ["#9b5a45", "#8e4f3e", "#a8644c"], ["#9aa4ab", "#8c969c", "#a7aeb1"]]
const MASONRY_MIX := [{"pierre": 3, "enduit": 2}, {"brique": 5, "brique_pierre": 2, "enduit": 1}, {"enduit": 4, "pierre": 1}, {"andesite": 4, "enduit": 2}]

## Type de façade : époque (grands ensembles, tours de bureaux, béton de la reconstruction) puis matériau régional
## pondéré (city_identity.json "facades", sinon selon "masonry"). Stable pour une même graine.
func _facade_type(seed_: int, cls: int, h: float, area: float) -> int:
	var hs := absi(hash(seed_ * 31 + 7))
	var mix_: Dictionary = style.get("facades", MASONRY_MIX[clampi(int(style.get("masonry", 2)), 0, 3)])
	if h >= 30.0: return F_VERRE if (cls == 1 or hs % 3 == 0) else F_GRAND_ENSEMBLE
	if (h >= 15.0 and area >= 700.0) or h >= 24.0:
		return F_BETON if mix_.has("beton") and hs % 3 != 0 else F_GRAND_ENSEMBLE
	if cls == 1 and area > 1500.0 and h < 15.0: return F_VERRE if hs % 2 == 0 else F_BETON
	var total := 0.0
	for k in mix_: total += float(mix_[k])
	var r := float(hs % 1000) / 1000.0 * total
	for k in mix_:
		r -= float(mix_[k])
		if r < 0.0: return maxi(0, FACADE_NAMES.find(str(k)))
	return F_ENDUIT

func _facade_color(ftype: int, seed_: int) -> Color:
	var over: Dictionary = style.get("facade_colors", {})
	var arr: Array = over.get(FACADE_NAMES[ftype], FACADE_COLORS[ftype])
	if arr.is_empty(): return _pal("walls", seed_)
	return Color.from_string(str(arr[absi(seed_ / 3) % arr.size()]), Color.GRAY)

## Code de façade porté par l'alpha : graine 500 + type × 50 + variante (pbr_world.gdshader).
func _wall_code(ftype: int, seed_: int) -> float:
	return float(500 + ftype * 50 + absi(seed_) % 50) / 1000.0

## Soubassement : bandeau en légère saillie au pied des façades.
func _plinth(D: _Arrays, ring: PackedVector2Array, hgt: float, col: Color) -> void:
	var c := _centroid(ring)
	col.a = SOLID_A
	for i in ring.size():
		var a := ring[i]; var b := ring[(i + 1) % ring.size()]
		if a.distance_to(b) < 2.0: continue
		var oa := a + (a - c).normalized() * 0.07; var ob := b + (b - c).normalized() * 0.07
		D.quad(Vector3(oa.x, 0.0, oa.y), Vector3(ob.x, 0.0, ob.y), Vector3(ob.x, hgt, ob.y), Vector3(oa.x, hgt, oa.y), col, -1.0)
		D.quad(Vector3(oa.x, hgt, oa.y), Vector3(ob.x, hgt, ob.y), Vector3(b.x, hgt, b.y), Vector3(a.x, hgt, a.y), col, -1.0)

## Boîte orientée (repère : x = tangente, z = normale sortante).
func _obox(D: _Arrays, ctr: Vector3, size: Vector3, t: Vector3, o: Vector3, col: Color) -> void:
	var hx := t * size.x * 0.5; var hy := Vector3.UP * size.y * 0.5; var hz := o * size.z * 0.5
	var p := [ctr - hx - hy - hz, ctr + hx - hy - hz, ctr + hx + hy - hz, ctr - hx + hy - hz,
		ctr - hx - hy + hz, ctr + hx - hy + hz, ctr + hx + hy + hz, ctr - hx + hy + hz]
	for f in [[0, 1, 2, 3], [5, 4, 7, 6], [4, 0, 3, 7], [1, 5, 6, 2], [3, 2, 6, 7]]:
		D.quad(p[f[0]], p[f[1]], p[f[2]], p[f[3]], col, -1.0)

## Lucarnes sur le long pan d'un toit à deux pans (même convention que _gable_roof).
func _dormers(D: _Arrays, ring: PackedVector2Array, y: float, rise: float, wall: Color, seed_: int, pediment := false) -> void:
	var a := ring[0]; var b := ring[1]; var c := ring[2]; var d := ring[3]
	if a.distance_to(b) < b.distance_to(c):
		var t := a; a = b; b = c; c = d; d = t
	var L := a.distance_to(b)
	if L < 5.0: return
	var count := clampi(int(L / 4.5), 1, 4)
	var tan2 := (b - a).normalized()
	var depth := a.distance_to(d) * 0.5
	for side in [0, 1]:
		var e0 := a if side == 0 else c; var e1 := b if side == 0 else d
		var inward := ((d if side == 0 else b) - e0).normalized()
		if side == 1: tan2 = -tan2
		var out3 := Vector3(-inward.x, 0, -inward.y)
		for k in count:
			if posmod(seed_ + k + side, 4) == 3: continue
			var u := (k + 0.5) / count
			var foot := e0.lerp(e1, u) + inward * depth * 0.38
			var yy := y + rise * 0.38
			var ctr := Vector3(foot.x, yy + 0.55, foot.y)
			var w_ := Color(wall.r * 1.05, wall.g * 1.05, wall.b * 1.04, SOLID_A)
			if pediment:   # P3 : lucarne à fronton en tuffeau (Anjou, Nantes)
				Facades.dormer_pediment(D, Vector3(foot.x, yy - 0.2, foot.y), Vector3(tan2.x, 0, tan2.y), out3, w_, Color(SLATE.r, SLATE.g, SLATE.b, SOLID_A))
				continue
			_obox(D, ctr, Vector3(1.1, 1.3, 1.2), Vector3(tan2.x, 0, tan2.y), out3, w_)
			# fenêtre de lucarne et petit toit à deux pans
			var front := ctr + out3 * 0.61
			D.quad(front + Vector3(tan2.x, 0, tan2.y) * -0.32 + Vector3(0, -0.45, 0), front + Vector3(tan2.x, 0, tan2.y) * 0.32 + Vector3(0, -0.45, 0),
				front + Vector3(tan2.x, 0, tan2.y) * 0.32 + Vector3(0, 0.4, 0), front + Vector3(tan2.x, 0, tan2.y) * -0.32 + Vector3(0, 0.4, 0), Color("#2c343c", SOLID_A), -1.0)
			var ridge0 := ctr + Vector3(0, 0.95, 0) + out3 * 0.62; var ridge1 := ctr + Vector3(0, 0.95, 0) - out3 * 0.6
			var tv := Vector3(tan2.x, 0, tan2.y) * 0.65
			var rc := Color(SLATE.r, SLATE.g, SLATE.b, SOLID_A)
			D.quad(ridge0 - tv + Vector3(0, -0.4, 0), ridge0, ridge1, ridge1 - tv + Vector3(0, -0.4, 0), rc, -1.0)
			D.quad(ridge0, ridge0 + tv + Vector3(0, -0.4, 0), ridge1 + tv + Vector3(0, -0.4, 0), ridge1, rc, -1.0)

## Menuiseries, stores, enseignes et balcons en géométrie, sur la façade principale (côté rue) de l'emprise, selon le
## type de façade. Détails bornés par bâtiment, dans le maillage de détail de la tuile (LOD : masqué au loin).
func _facade_detail(S: _Arrays, ring: PackedVector2Array, height_: float, seed_: int, shop: bool, ftype: int = F_ENDUIT, wall: Color = STONE, awnings_only := false) -> void:
	if height_ < 3.5 or ring.size()<3: return
	var building_center:=_centroid(ring)
	var toward_street:=Vector2.ZERO;var nearest:=70.0
	for x in range(floori((building_center.x-70.0)/16.0),floori((building_center.x+70.0)/16.0)+1):
		for z in range(floori((building_center.y-70.0)/16.0),floori((building_center.y+70.0)/16.0)+1):
			for road in _street_keepout.cells.get(Vector2i(x,z),[]):
				var q:=Geometry2D.get_closest_point_to_segment(building_center,road[0],road[1])
				if q.distance_to(building_center)<nearest:
					nearest=q.distance_to(building_center);toward_street=(q-building_center).normalized()
	var longest:=0; var length_:=0.0;var best:=-1.0
	for i in ring.size():
		var l:=ring[i].distance_to(ring[(i+1)%ring.size()])
		var outward:=((ring[i]+ring[(i+1)%ring.size()])*0.5-building_center).normalized()
		var score:=l*(0.2+0.8*maxf(0.0,outward.dot(toward_street)))
		if score>best: longest=i; length_=l; best=score
	if length_<5.0: return
	var a:=ring[longest]; var b:=ring[(longest+1)%ring.size()]
	var tangent:=(b-a).normalized(); var normal:=Vector2(-tangent.y,tangent.x)
	if normal.dot((a+b)*0.5-_centroid(ring))<0.0:normal=-normal
	var accent:=Color.from_string(str(style.get("accent","#44645f")),Color.GRAY)
	accent.a=SOLID_A
	var iron := Color("#25292c", SOLID_A)
	var u0:=0.0
	for i in longest:u0+=ring[i].distance_to(ring[(i+1)%ring.size()])
	# même largeur de travée que les fenêtres du shader (graine de façade)
	var face_seed:=float(500 + ftype * 50 + absi(seed_) % 50)
	var bay:=lerpf(2.4,4.0,fposmod(face_seed*0.6180339,1.0))
	var fh := 3.3 if (ftype == F_PIERRE or ftype == F_TUFFEAU) else (2.75 if ftype == F_GRAND_ENSEMBLE else 3.0)
	var first_bay:=ceili((u0+1.25)/bay-0.5)
	var bays:=clampi(int(length_/bay),1,8)
	var t:=Vector3(tangent.x,0,tangent.y);var out:=Vector3(normal.x,0,normal.y)
	var floors := clampi(int((height_ - 3.4) / fh), 0, 7)
	var hs := absi(hash(seed_ * 17 + 3))
	# bandeaux d'étage (béton de la reconstruction) et cordon au-dessus du rez-de-chaussée (pierre)
	if awnings_only: pass   # P3 : bandeaux, balcons et loggias en relief (Facades)
	elif ftype == F_BETON:
		for fl in range(1, floors + 1):
			var yb := 0.4 + fl * fh
			if yb > height_ - 0.5: break
			_obox(S, Vector3((a.x+b.x)*0.5, yb, (a.y+b.y)*0.5) + out * 0.08, Vector3(length_, 0.14, 0.16), t, out, Color(wall.r*1.05, wall.g*1.05, wall.b*1.04, SOLID_A))
	elif (ftype == F_PIERRE or ftype == F_TUFFEAU or ftype == F_ANDESITE or ftype == F_BRIQUE_PIERRE) and height_ > 7.0:
		_obox(S, Vector3((a.x+b.x)*0.5, 3.45, (a.y+b.y)*0.5) + out * 0.08, Vector3(length_, 0.2, 0.16), t, out, Color(wall.r*1.08, wall.g*1.07, wall.b*1.05, SOLID_A))
	var awning_cols := [accent, Color("#7a2a2a", SOLID_A), Color("#2f4f3e", SOLID_A), Color("#c9bfa6", SOLID_A), Color("#2b3540", SOLID_A)]
	for i in bays:
		var along:=(first_bay+i+0.5)*bay-u0
		if along>length_-1.25:break
		var center:=a+tangent*along+normal*0.08
		var p:=Vector3(center.x,0,center.y)
		var bh := absi(hash(Vector2i(seed_, i)))
		if shop:
			if bh % 5 < 3:   # store banne (couleur par commerce)
				var ac: Color = awning_cols[(bh / 5) % awning_cols.size()]
				S.quad(p-t*1.25+Vector3.UP*2.9,p+t*1.25+Vector3.UP*2.9,p+t*1.25+out*0.9+Vector3.UP*2.55,p-t*1.25+out*0.9+Vector3.UP*2.55,ac,-1.0)
				S.quad(p-t*1.25+out*0.9+Vector3.UP*2.55,p+t*1.25+out*0.9+Vector3.UP*2.55,p+t*1.25+out*0.9+Vector3.UP*2.3,p-t*1.25+out*0.9+Vector3.UP*2.3,ac.darkened(0.12),-1.0)
			elif bh % 7 == 0:   # enseigne en drapeau (générique, sans marque)
				_obox(S, p + out * 0.45 + Vector3.UP * 3.75, Vector3(0.06, 0.6, 0.6), t, out, awning_cols[(bh / 7) % awning_cols.size()])
		elif i==0:
			S.quad(p-t*0.5,p+t*0.5,p+t*0.5+Vector3.UP*2.3,p-t*0.5+Vector3.UP*2.3,accent,-1.0)
		if floors < 1 or awnings_only: continue
		match ftype:
			F_PIERRE, F_TUFFEAU, F_OCRE, F_ANDESITE:
				# balconnets en fer forgé : 2e étage, et étages choisis selon la graine
				for fl in range(1, mini(floors, 5) + 1):
					if not (fl == 1 or (hs >> fl) % 3 == 0): continue
					var y := Vector3.UP * (3.4 + (fl - 1) * fh + (0.0 if shop else 0.2))
					if y.y > height_ - 1.5: break
					var dp := 0.55 if ftype == F_OCRE else 0.4
					S.quad(p-t*0.85+y,p+t*0.85+y,p+t*0.85+out*dp+y,p-t*0.85+out*dp+y,Color(wall.r*1.05,wall.g*1.05,wall.b*1.04,SOLID_A),-1.0)
					S.quad(p-t*0.85+out*dp+y,p+t*0.85+out*dp+y,p+t*0.85+out*dp+y+Vector3.UP*0.9,p-t*0.85+out*dp+y+Vector3.UP*0.9,iron,-1.0)
			F_GRAND_ENSEMBLE:
				# loggias : dalles en saillie et allèges pleines une travée sur deux
				if (first_bay + i) % 2 == 0:
					for fl in range(1, mini(floors, 7) + 1):
						var y := Vector3.UP * (0.4 + fl * fh)
						if y.y > height_ - 1.0: break
						S.quad(p-t*1.1+y,p+t*1.1+y,p+t*1.1+out*1.0+y,p-t*1.1+out*1.0+y,Color("#c9c4b8",SOLID_A),-1.0)
						S.quad(p-t*1.1+out*1.0+y,p+t*1.1+out*1.0+y,p+t*1.1+out*1.0+y+Vector3.UP*1.0,p-t*1.1+out*1.0+y+Vector3.UP*1.0,Color("#dcd6c8",SOLID_A).lerp(accent,0.25),-1.0)
			_:
				if height_>8.0 and posmod(seed_,3)==0:
					var y:=Vector3.UP*3.5
					S.quad(p-t*1.0+y,p+t*1.0+y,p+t*1.0+out*0.7+y,p-t*1.0+out*0.7+y,Color("#bdb7aa",SOLID_A),-1.0)
					S.quad(p-t+y+out*0.7,p+t+y+out*0.7,p+t+y+out*0.7+Vector3.UP*0.94,p-t+y+out*0.7+Vector3.UP*0.94,iron,-1.0)

func _point(S: _Arrays, kind: int, h: float, p: Vector2) -> void:
	match kind:
		1: _tower(S, p, 6.0, h * 0.62, h * 0.38, STONE, SLATE)
		2: _tower(S, p, 5.0, h, 0.0, STONE, SLATE)
		3: _round_tower(S, p, 2.5, h, Color("#f2f2f2"), Color("#c0392b"), true, false)
		4: S.cone(Vector3(p.x, 0, p.y), 1.6, h, 8, Color("#9c6a52", SOLID_A))

## Mobilier et plantations le long d'une route (la chaussée, les trottoirs, les marquages et les voies ferrées sont
## dans le maillage du sol : RoadView / TerrainView). Mobilier et voitures : instances (StreetProps).
func _line(S: _Arrays, pts: PackedVector2Array, cls: int, w: float, seed: int, deck: int = -1) -> void:
	if cls == L_RAIL or cls == L_PATH or cls == L_SMALL: return
	# arbres d'alignement (essence dominante de la ville), de part et d'autre des avenues
	if (cls == L_MAJOR or (cls == L_ROAD and w >= 7.0)) and not _ortho_tile and deck < 0:  # sinon arbres réels (orthophoto)
		var mix: Array = style.get("trees", [0])
		var kind := int(mix[0])
		var rng := RandomNumberGenerator.new(); rng.seed = seed * 7
		var acc3 := float(seed % 11)
		for i in range(pts.size() - 1):
			var a := pts[i]; var b := pts[i + 1]
			var len := a.distance_to(b)
			var d := (b - a) / maxf(len, 0.001)
			var nrm := Vector2(-d.y, d.x) * (w * 0.5 + 2.4)
			var s2 := fposmod(-acc3, 17.0)
			while s2 < len:
				for side in [-1.0, 1.0]:
					var p: Vector2 = a + d * s2 + nrm * side
					if p.x > 0.0 and p.y > 0.0 and p.x < tile_m and p.y < tile_m:
						_add_tree(kind, Vector3(p.x, 0.04, p.y), rng, 0.62)
				s2 += 17.0
			acc3 += len
	if not (cls == L_MAJOR or (cls == L_ROAD and w >= 6.0)): return
	var rng := RandomNumberGenerator.new(); rng.seed = seed * 131 + 5
	var low := DayNight.low_quality
	# lampadaires sur trottoir (émissifs la nuit) : crosse sur les avenues, lanterne de style dans les centres anciens,
	# en quinconce des deux côtés sur les voies larges ; halo projeté au sol
	var lamp_kind := StreetProps.LAMP_ARM if cls == L_MAJOR else (StreetProps.LAMP_OLD if _old_town > 0.55 and w < 10.0 else StreetProps.LAMP)
	var arm: float = [0.75, 2.4, 0.0][lamp_kind]
	var spacing := 30.0 if lamp_kind != StreetProps.LAMP_OLD else 22.0
	var both := w >= 13.0
	var acc2 := float(seed % 17)
	var acc_f := float(seed % 23)
	for i in range(pts.size() - 1):
		var a := pts[i]; var b := pts[i + 1]
		var len := a.distance_to(b)
		if len < 0.5: continue
		var d := (b - a) / len
		var n2 := Vector2(-d.y, d.x)
		var s := fposmod(-acc2, spacing)
		var k := int(acc2 / spacing)
		while s < len:
			var side := 1.0 if (not both or k % 2 == 0) else -1.0
			var p := a + d * s + n2 * side * (w * 0.5 + 1.2)
			var toward := -n2 * side
			if _free_spot(p, 0.4, true):
				var y := _prop_y(p, deck)
				_prop(lamp_kind, p, toward, y, true)
				var hp := p + toward * arm
				_prop(StreetProps.HALO, hp, d, _prop_y(hp, deck) + 0.1, false)
			s += spacing; k += 1
		acc2 += len
		if deck >= 0: continue
		# trottoir : bancs, corbeilles, arceaux vélos ; piétons sur les trottoirs des avenues
		if w >= (5.5 if cls == L_MAJOR else 7.0):
			var sf := fposmod(-acc_f, 41.0)
			while sf < len:
				var side := -1.0 if int((acc_f + sf) / 41.0) % 2 == 0 else 1.0
				var q := a + d * sf + n2 * side * (w * 0.5 + 2.1)
				var r := rng.randf()
				var kind := StreetProps.BENCH if r < 0.3 else (StreetProps.BIN if r < 0.62 else (StreetProps.BIKE if r < 0.82 else StreetProps.MUPI))
				if _free_spot(q, 0.8, true) and _far_from_nodes(q, 8.0):
					_prop(kind, q, d, _prop_y(q, -1), false, MUPI_COLORS[rng.randi() % MUPI_COLORS.size()] if kind == StreetProps.MUPI else Color(0.5, 0.5, 0.5))
					if kind == StreetProps.BENCH and _free_spot(q + d * 1.6, 0.4, true):
						_prop(StreetProps.BIN, q + d * 1.6, d, _prop_y(q + d * 1.6, -1), false)
				if (cls == L_MAJOR or w >= 9.0) and rng.randf() < (0.25 if low else 0.55):
					var pp := a + d * minf(sf + 9.0, len) - n2 * side * (w * 0.5 + rng.randf_range(1.4, 3.0))
					if _free_spot(pp, 0.5, true):
						var dir := d.rotated(rng.randf_range(-0.6, 0.6)) * (1.0 if rng.randf() < 0.5 else -1.0)
						_prop(StreetProps.PED if rng.randf() < 0.6 else StreetProps.PED_B, pp, dir, _prop_y(pp, -1), false, StreetProps.clothes_color(rng))
				sf += 41.0
		acc_f += len
		_road_decals(a, d, n2, len, w, rng)
		# voitures en stationnement le long des trottoirs (rues de desserte et avenues hors centre)
		if w >= 7.0 and w <= 16.0 and len > 12.0:
			for side in [-1.0, 1.0]:
				if rng.randf() < (0.25 if cls == L_MAJOR else 0.15): continue   # côté sans stationnement
				var sc := 3.0
				while sc < len - 3.0:
					var big := rng.randf() < 0.35
					var slot := 5.9 if big else 5.3
					if rng.randf() < (0.4 if low else 0.74):
						var c: Vector2 = a + d * (sc + slot * 0.5 + rng.randf_range(-0.25, 0.25)) + n2 * side * (w * 0.5 - 1.15)
						if _far_from_nodes(c, 11.0) and _free_spot(c, 1.6, false):
							var dir := d.rotated(rng.randf_range(-0.03, 0.03)) * (1.0 if side > 0.0 else -1.0)
							_prop(StreetProps.CAR_BIG if big else StreetProps.CAR, c, dir, _prop_y(c, -1), false, StreetProps.car_color(rng))
							if rng.randf() < 0.3: _decals.append([RoadDecals.OIL, Vector3(c.x, _prop_y(c, -1), c.y), rng.randf() * TAU, Vector2.ONE * rng.randf_range(0.8, 1.5)])
					sc += slot

const DETAIL_RANGE := 190.0
var _bld_cells: Dictionary = {}     # Vector2i (cellules de 16 m, repère tuile) -> emprises des bâtiments
var _old_town := 0.0                # part du bâti bas et résidentiel de la tuile (style des lampadaires)
var _nodes: Array = []              # carrefours de la tuile : [position, [[direction sortante, classe, largeur], ...]]

## Emplacement libre pour un objet (repère tuile) : dans la tuile, hors eau, voies tram, quais, bâtiments et, pour le
## mobilier de trottoir (`sidewalk`), hors chaussées.
func _free_spot(p: Vector2, r: float, sidewalk: bool) -> bool:
	if p.x < 0.0 or p.y < 0.0 or p.x >= tile_m or p.y >= tile_m: return false
	if _in_water(p): return false
	if _keepout != null and _keepout.blocked(_tile_origin + p, r): return false
	if sidewalk and _street_keepout.blocked(p, 0.15): return false
	for ring in _bld_cells.get(Vector2i(floori(p.x / 16.0), floori(p.y / 16.0)), []):
		if Geometry2D.is_point_in_polygon(p, ring): return false
	return true

func _far_from_nodes(p: Vector2, r: float) -> bool:
	for nd in _nodes:
		if (nd[0] as Vector2).distance_to(p) < r + float(nd[2]): return false
	return true

## Altitude d'un objet posé (repère tuile) : terrain, ou tablier suivi par la route.
func _prop_y(p: Vector2, deck: int) -> float:
	if not has_terrain: return 0.0
	var x := p.x + _tile_origin.x; var z := p.y + _tile_origin.y
	if deck >= 0:
		var dh := deck_city(x, z, deck)
		if not is_nan(dh): return dh
	return height_city(x, z)

## Ajoute une instance : `fwd` = avant du modèle (+Z local), `side_x` : +X local tourné vers `fwd` (lampadaires : la
## crosse vers la chaussée) au lieu de +Z.
func _prop(kind: int, p: Vector2, fwd: Vector2, y: float, side_x: bool, col: Color = Color(0.5, 0.5, 0.5)) -> void:
	var f := Vector3(fwd.x, 0, fwd.y).normalized()
	if f == Vector3.ZERO: f = Vector3.FORWARD
	if side_x: f = f.cross(Vector3.UP)
	var basis := Basis(Vector3.UP.cross(f), Vector3.UP, f)
	_props[kind][0].append(Transform3D(basis, Vector3(p.x, y, p.y)))
	_props[kind][1].append(col)
	if debug_props and kind != StreetProps.HALO: placed_props.append(_tile_origin + p)

## Carrefours de la tuile : extrémités communes d'au moins trois tronçons routiers (rues et avenues).
func _road_nodes(roads: Array) -> Array:
	var ends: Array = []   # [position, direction sortante, classe, largeur]
	for r in roads:
		var cls: int = r[0]; var pl: PackedVector2Array = r[2]
		if cls != L_MAJOR and cls != L_ROAD and cls != L_SMALL: continue
		if pl.size() < 2: continue
		for e in [0, 1]:
			var p := pl[0] if e == 0 else pl[pl.size() - 1]
			var q := pl[1] if e == 0 else pl[pl.size() - 2]
			if p.x < 1.0 or p.y < 1.0 or p.x > tile_m - 1.0 or p.y > tile_m - 1.0: continue
			ends.append([p, (q - p).normalized(), cls, float(r[1])])
	var used := {}
	var out: Array = []
	for i in ends.size():
		if used.has(i): continue
		var arms: Array = [[ends[i][1], ends[i][2], ends[i][3]]]
		var ctr: Vector2 = ends[i][0]
		for j in range(i + 1, ends.size()):
			if not used.has(j) and (ends[j][0] as Vector2).distance_to(ctr) < 2.0:
				used[j] = true; arms.append([ends[j][1], ends[j][2], ends[j][3]])
		if arms.size() >= 3:
			var r := 0.0
			for arm in arms: r = maxf(r, float(arm[2]) * 0.5)
			out.append([ctr, arms, r])
	return out

## Decals de voirie le long d'un tronçon (refonte P3) : plaques d'égout dans l'axe, salissures en pied de bordure,
## rapiéçages d'enrobé ; jamais sur la plateforme du tram. Mobile : moitié moins.
func _road_decals(a: Vector2, d: Vector2, n2: Vector2, len: float, w: float, rng: RandomNumberGenerator) -> void:
	if lite: return
	var step := 26.0 if not DayNight.low_quality else 52.0
	var s := rng.randf() * step
	while s < len:
		var r := rng.randf()
		var kind := RoadDecals.MANHOLE if r < 0.35 else (RoadDecals.GRIME if r < 0.8 else RoadDecals.PATCH)
		var off := rng.randf_range(-0.2, 0.2) * w if kind != RoadDecals.GRIME else (w * 0.5 - 0.6) * (1.0 if rng.randf() < 0.5 else -1.0)
		var p := a + d * s + n2 * off
		if not blocked(_tile_origin + p, 1.5):
			var sz := Vector2.ONE * 1.0 if kind == RoadDecals.MANHOLE else (Vector2(rng.randf_range(1.5, 3.0), rng.randf_range(2.0, 5.0)) if kind == RoadDecals.GRIME else Vector2(rng.randf_range(1.2, 2.4), rng.randf_range(1.5, 3.0)))
			var ang := atan2(d.x, d.y) + (rng.randf() * TAU if kind == RoadDecals.MANHOLE else rng.randf_range(-0.15, 0.15))
			_decals.append([kind, Vector3(p.x, _prop_y(p, -1), p.y), ang, sz])
		s += step * rng.randf_range(0.7, 1.3)

## Bandeaux des affiches génériques des « sucettes » (StreetProps.MUPI) : aucune marque.
const MUPI_COLORS := [Color("#1f5aa6"), Color("#c4262e"), Color("#2f7d4a"), Color("#e0a21b"), Color("#5a3c8c")]

## Feux tricolores aux carrefours d'avenues, panneaux et potelets ailleurs.
func _crossroads(seed_: int) -> void:
	var rng := RandomNumberGenerator.new(); rng.seed = seed_ * 7 + 99
	for nd in _nodes:
		var ctr: Vector2 = nd[0]; var arms: Array = nd[1]; var r: float = nd[2]
		var majors := 0; var wide := 0
		for arm in arms:
			if int(arm[1]) == L_MAJOR: majors += 1
			if float(arm[2]) >= 7.0: wide += 1
		var signals := majors >= 1 and wide >= 2
		var main_dir: Vector2 = arms[0][0]
		for arm in arms:
			if int(arm[1]) == L_MAJOR: main_dir = arm[0]; break
		var signed := false
		for arm in arms:
			var dir: Vector2 = arm[0]; var hw := float(arm[2]) * 0.5
			if int(arm[1]) == L_SMALL and not signals: continue
			var right := Vector2(dir.y, -dir.x)   # droite des véhicules qui arrivent au carrefour
			if signals and int(arm[1]) != L_SMALL:
				var p := ctr + dir * (r + 2.5) + right * (hw + 0.9)
				if _free_spot(p, 0.3, true):
					var green := absf(dir.dot(main_dir)) > 0.7
					_prop(StreetProps.LIGHTS_GREEN if green else StreetProps.LIGHTS_RED, p, dir, _prop_y(p, -1), false)
			elif not signed and int(arm[1]) == L_ROAD and rng.randf() < 0.45:
				signed = true
				var p := ctr + dir * (r + 3.0) + right * (hw + 0.7)
				if _free_spot(p, 0.3, true):
					var col := Color("#c4262e") if rng.randf() < 0.55 else Color("#1f5aa6")
					_prop(StreetProps.SIGN, p, dir, _prop_y(p, -1), false, col)
			# potelets au droit des passages piétons (angle de trottoir)
			for k in 3:
				var q := ctr + dir * (r + 1.0 + k * 1.4) + right * (hw + 0.45)
				if _free_spot(q, 0.2, true): _prop(StreetProps.BOLLARD, q, dir, _prop_y(q, -1), false)
				var q2 := ctr + dir * (r + 1.0 + k * 1.4) - right * (hw + 0.45)
				if _free_spot(q2, 0.2, true): _prop(StreetProps.BOLLARD, q2, dir, _prop_y(q2, -1), false)
			# barrières de trottoir au-delà des potelets (carrefours à feux)
			if signals:
				for kb in 2:
					var qb := ctr + dir * (r + 5.6 + kb * 1.3) - right * (hw + 0.45)
					if _free_spot(qb, 0.3, true): _prop(StreetProps.BARRIER, qb, dir, _prop_y(qb, -1), true)

## Essences : 0 feuillu rond, 1 conifère, 2 feuillu élancé, 3 pin parasol, 4 palmier, 5 peuplier, 6 platane.
func _pick_tree(rng: RandomNumberGenerator) -> int:
	var mix: Array = style.get("trees", [0, 2, 1])
	return int(mix[rng.randi() % mix.size()])

## Recherche d'un monument nommé (étiquette BD TOPO) : position dans le repère de la ligne, ou Vector3.INF.
func find_label(substr: String) -> Vector3:
	if not v2: return Vector3.INF
	var want := substr.to_lower()
	for k in table:
		for lb in _tile_labels(k):
			if str(lb[0]).to_lower().contains(want):
				var p: Vector2 = lb[1]
				return _to_net(k.x * tile_m + p.x, k.y * tile_m + p.y)
	return Vector3.INF

## Étiquettes d'une tuile [[nom, Vector2 repère tuile]], lecture bornée (tuile tronquée : liste partielle).
func _tile_labels(k: Vector2i) -> Array:
	var out: Array = []
	var o: int = _tile_data(k)
	var end := buf.size()
	if o + 2 > end: return out
	var nb := buf.decode_u16(o); o += 2
	for b in nb:
		if o + 5 > end: return out
		o += 5 + buf.decode_u8(o) * 4
		if o + 1 > end: return out
		o += 1 + buf.decode_u8(o) * 3
	if o + 2 > end: return out
	var np := buf.decode_u16(o); o += 2
	for p in np:
		if o + 5 > end: return out
		o += 5 + buf.decode_u16(o + 1) * 4 + buf.decode_u16(o + 3) * 6
	if o + 2 > end: return out
	var nl := buf.decode_u16(o); o += 2
	for l in nl:
		if o + 4 > end: return out
		o += 4 + buf.decode_u16(o + 2) * 4
	if o + 2 > end: return out
	var npt := buf.decode_u16(o); o += 2 + npt * 7
	if o + 2 > end: return out
	var nlb := buf.decode_u16(o); o += 2
	for i in nlb:
		if o + 6 > end: return out
		var ln := buf.decode_u8(o + 5)
		if o + 6 + ln > end: return out
		out.append([buf.slice(o + 6, o + 6 + ln).get_string_from_utf8(), Vector2(buf.decode_s16(o + 1) * 0.1, buf.decode_s16(o + 3) * 0.1)])
		o += 6 + ln
	return out

## Point du repère de la ville -> repère de la ligne affichée (altitude du sol si connue).
func _to_net(x: float, z: float) -> Vector3:
	return Vector3(position.x + x * _x_scale, height_city(x, z) if has_terrain else 0.0, position.z + z)

## Monuments emblématiques de la ville (data/landmarks.json) : [[nom, Vector3 repère de la ligne]], pour la liste
## « Aller à » du mode Explorer. Coordonnées WGS84 converties dans le repère de la scène.
func landmarks() -> Array:
	var out: Array = []
	if not FileAccess.file_exists("res://data/landmarks.json"): return out
	var d = CityDataStore.document("res://data/landmarks.json")
	var meta = CityDataStore.document("res://data/scenes/%s.json" % city)
	if not d is Dictionary or not meta is Dictionary: return out
	var lat0 := float(meta.origin[0]); var lon0 := float(meta.origin[1])
	for lm in d.get("cities", {}).get(city, []):
		var x := deg_to_rad(float(lm.lon) - lon0) * R * cos(deg_to_rad(lat0))
		var z := -deg_to_rad(float(lm.lat) - lat0) * R
		out.append([str(lm.name), _to_net(x, z)])
	return out

## Vérifie la structure d'une tuile (lecture complète des sections, taille exacte) : pour les tests.
func tile_ok(k: Vector2i) -> bool:
	if not table.has(k): return false
	var o: int = _tile_data(k)
	var end: int = o + table[k].y
	var nb := buf.decode_u16(o); o += 2
	for b in nb:
		var n := buf.decode_u8(o); o += (5 if v2 else 4) + n * 4
		o += 1 + buf.decode_u8(o) * 3
	var np := buf.decode_u16(o); o += 2
	for p in np: o += 5 + buf.decode_u16(o + 1) * 4 + buf.decode_u16(o + 3) * 6
	var nl := buf.decode_u16(o); o += 2
	for l in nl: o += 4 + buf.decode_u16(o + 2) * 4
	if v2:
		var npt := buf.decode_u16(o); o += 2 + npt * 7
		var nlb := buf.decode_u16(o); o += 2
		for i in nlb: o += 6 + buf.decode_u8(o + 5)
	if v3:
		var nr := buf.decode_u16(o); o += 2
		if nr != nb: return false
		o += nr * 2
		o += 2 + buf.decode_u16(o) * 6
		o += 2 + buf.decode_u16(o) * 3
	return o == end

## Nombre de bâtiments de la tuile contenant ce point (repère de la ligne) : indicateur de densité urbaine.
func density_at(p_net: Vector3) -> int:
	var c := p_net - position
	c.x /= _x_scale
	var k := Vector2i(floori(c.x / tile_m), floori(c.z / tile_m))
	return buf.decode_u16(_tile_data(k)) if table.has(k) else 0

## Zones interdites au décor (repère ville) : plateformes de tram (axe ± TRACK_KEEP) et quais.
## Arbres, lampadaires, éléments ponctuels et bâtiments n'y sont pas posés.
const TRACK_KEEP := 4.2
var _keepout: TrackView.KeepOut = null
var _tile_origin := Vector2.ZERO
## Rayon de houppier des modèles d'arbres (échelle 1), par essence.
const CROWN_R := [2.6, 2.3, 1.9, 3.4, 3.0, 1.1, 3.6, 1.4, 0.5, 0.5]

## Cale le décor sur un réseau : découpe du terrain aux portails de tunnels peu profonds, plateformes (pas d'arbre
## ni de bâtiment dessus), profil 3D des voies (eau, tabliers et piles hors gabarit). Utilisé par LineView et par
## tests/test_clearance.gd (même état que le jeu).
func bind_network(net: NetworkLoader) -> void:
	_gauge_pts = PackedVector3Array()
	var polys: Array = []
	var cor_p := PackedVector3Array(); var cor_d := PackedVector2Array()
	var prof := PackedVector3Array()
	for id in net.edge_info:
		var info: Dictionary = net.edge_info[id]
		var pl := PackedVector2Array()
		var arc := 0.0
		for i in info.pts.size():
			if i > 0:
				arc += info.pts[i - 1].distance_to(info.pts[i])
				var middle: float = (arc - info.pts[i - 1].distance_to(info.pts[i]) * 0.5) * net.graph.edges[id].length / maxf(info.arc[-1], 0.01)
				if NetworkLoader.in_spans(info.tunnel, middle):
					var q := net.point_on(id, middle)
					if height_at(Vector3(q.p.x, q.y, q.p.y)) - q.y < 6.0:
						add_portal_cut(info.pts[i - 1], info.pts[i])
			if NetworkLoader.in_spans(info.tunnel, arc):
				if pl.size() >= 2: polys.append(pl)
				pl = PackedVector2Array()
			else: pl.append(info.pts[i])
		if pl.size() >= 2: polys.append(pl)
		var L: float = net.graph.edges[id].length
		var n := maxi(1, ceili(L / 6.0))
		var axis := PackedVector2Array(); var buried := []
		for i in n + 1:
			var q := net.point_on(id, L * i / n)
			prof.append(Vector3(q.p.x, q.y, q.p.y))
			axis.append(q.p)
			# trémie ou tranchée hors tunnel : le terrain qui recouvrirait la voie est ouvert (jamais de voie enterrée)
			var side := Vector2(-q.dir.y, q.dir.x) * 1.75
			var top := maxf(height_at(Vector3(q.p.x, 0, q.p.y)), maxf(height_at(Vector3(q.p.x + side.x, 0, q.p.y + side.y)), height_at(Vector3(q.p.x - side.x, 0, q.p.y - side.y))))
			buried.append(not NetworkLoader.in_spans(info.tunnel, L * i / n) and top > q.y + 0.3)
		# voie dense (2 m) près des tabliers : contrôle du gabarit au pas de tests/test_clearance.gd
		var n2 := maxi(1, ceili(L / 2.0))
		for i in n2 + 1:
			var q3 := net.point_on(id, L * i / n2)
			for lo in ([0.0] if info.raw or info.get("physical", false) else [-1.75, 1.75]):   # axe de chaque sens
				var cc := Vector2((q3.p.x - q3.dir.y * lo - position.x) / _x_scale, q3.p.y + q3.dir.x * lo - position.z)
				if _deck_cells.has(Vector2i(floori(cc.x / 32.0), floori(cc.y / 32.0))): _gauge_pts.append(Vector3(cc.x, q3.y, cc.y))
		for i in buried.size():
			if buried[i]: add_portal_cut(axis[maxi(i - 1, 0)], axis[mini(i + 1, axis.size() - 1)], 3.6)
		# axe au sol (hors ponts et tunnels) : corridors du relief lointain
		var cor_s: Array = []
		for i in n + 1: cor_s.append(L * i / n)
		for sp in info.tunnel + info.get("bridge", []):   # aux bords des ouvrages : corridor jusqu'à la culée / au portail
			for e in [float(sp[0]) - 0.5, float(sp[1]) + 0.5]:
				if e > 0.0 and e < L: cor_s.append(e)
		for s_ in cor_s:
			if NetworkLoader.in_spans(info.tunnel, s_) or NetworkLoader.in_spans(info.get("bridge", []), s_): continue
			var q2 := net.point_on(id, s_)
			cor_p.append(Vector3((q2.p.x - position.x) / _x_scale, q2.y, q2.p.y - position.z)); cor_d.append(q2.dir)
	if terrain != null: terrain.set_corridor(cor_p, cor_d)
	set_tracks(polys)
	set_track_profile(prof)

func set_tracks(polylines: Array) -> void:
	if _keepout == null: _keepout = TrackView.KeepOut.new()
	var off := Vector2(position.x, position.z)
	for poly in polylines:
		var pl := PackedVector2Array()
		for q in poly: pl.append(Vector2((q.x - off.x) / _x_scale, q.y - off.y))
		_keepout.add_polyline(pl, TRACK_KEEP)

## Segment interdit supplémentaire (repère de la ligne), ex. quai de station.
func add_keepout(a_net: Vector2, b_net: Vector2, clearance: float) -> void:
	if _keepout == null: _keepout = TrackView.KeepOut.new()
	var off := Vector2(position.x, position.z)
	_keepout.add_segment(Vector2((a_net.x - off.x) / _x_scale, a_net.y - off.y), Vector2((b_net.x - off.x) / _x_scale, b_net.y - off.y), clearance)

## Vrai si le point (repère ville) est sur une plateforme ou un quai (marge `extra`).
func blocked(p_city: Vector2, extra: float = 0.0) -> bool:
	return _keepout != null and _keepout.blocked(p_city, extra)

func _add_tree(kind: int, pos: Vector3, rng: RandomNumberGenerator, scale: float = 1.0, exact: bool = false, height: float = 0.0) -> void:
	var local_ := Vector2(pos.x,pos.z)
	if _street_keepout.blocked(local_,0.3):return
	if _in_water(local_): return
	var w := _tile_origin + local_
	var sc := scale if exact else rng.randf_range(0.85, 1.3) * scale
	var crown: float = CROWN_R[kind] * sc
	if _keepout != null:
		if _keepout.blocked(w, 0.6): return
		# houppier : ne déborde pas sur la plateforme (réduit, sinon arbre omis)
		var lim := crown
		while lim > 1.2 and _keepout.blocked(w, lim * 0.8): lim *= 0.8
		if lim <= 1.2 and _keepout.blocked(w, lim * 0.8): return
		sc *= lim / crown
	var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * sc)
	if height > 0.0:   # hauteur mesurée (LiDAR HD, MNH) : étirement vertical seul, houppier au rayon mesuré
		var top := _tree_mesh(kind).get_aabb().end.y
		if top > 0.5: b = Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(sc, clampf(height / top, 0.4, 3.0), sc))
	if has_terrain: pos.y += _ground_h(Vector2(pos.x, pos.z))
	_trees_cur[kind].append(Transform3D(b, pos))
	var crown_pos := pos + Vector3(0, 5.0 * sc, 0)
	var radius: float = CROWN_R[kind] * sc
	if kind < 7: _camera_boxes.append([1, crown_pos, radius + 0.5, 2.4 * sc + 0.5])
	if debug_props: placed_trees.append(w)

## Végétation réaliste (refonte P3, Vegetation / vegetation.gdshader), par tuile et par essence :
## - arbres (essences 0 à 6, le type 0 partagé entre tilleul et marronnier) : imposteurs de toute la tuile (une
##   instance, sans ombre) + arbres complets (tronc, charpentières, cartes de rameaux) par cellule de TREE_VEG_CELL m,
##   visibles jusqu'à `near` m. La bascule maillage/imposteur est faite PAR INSTANCE dans le shader à
##   `lod` = near - demi-diagonale de cellule : tout arbre plus proche est dans une cellule affichée ;
## - arbustes, graminées, vivaces (7 à 9) : cartes, une instance par cellule, visibles jusqu'à `small` m.
const TREE_CELL := 100.0
const TREE_VEG_CELL := 70.0
static func tree_ranges() -> Dictionary:
	var near := 110.0 if DayNight.low_quality else 230.0
	return {"near": near, "small": 60.0 if DayNight.low_quality else 120.0, "lod": near - TREE_VEG_CELL * 0.71}

static func _mm(mesh: Mesh, xfs: Array, mat: Material = null) -> MultiMeshInstance3D:
	var mm := MultiMesh.new(); mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh; mm.instance_count = xfs.size()
	for i in xfs.size(): mm.set_instance_transform(i, xfs[i])
	var mmi := MultiMeshInstance3D.new(); mmi.multimesh = mm
	mmi.material_override = mat if mat != null else Vegetation.material()
	return mmi

func _add_trees(node: Node3D, v: int, xfs: Array) -> void:
	var r := tree_ranges()
	Vegetation.set_mobile(DayNight.low_quality)
	Vegetation.set_lod_distance(r.lod)
	# type 0 : tilleul ou marronnier (une instance sur deux, selon la position)
	var groups := {v: xfs}
	if v == 0:
		groups = {0: [], Vegetation.MARRONNIER: []}
		for x in xfs:
			var o := (x as Transform3D).origin
			groups[0 if fposmod(floorf(o.x * 0.37) + floorf(o.z * 0.53), 2.0) < 1.0 else Vegetation.MARRONNIER].append(x)
	for kind in groups:
		var list: Array = groups[kind]
		if list.is_empty(): continue
		if v < 7 and Vegetation.has_impostor(kind):
			var far := _mm(Vegetation.impostor_mesh(kind), list, Vegetation.impostor_material())
			far.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			far.name = "veg_far_%d" % kind
			node.add_child(far)
		# cellules : la portée de visibilité se mesure au centre de la boîte englobante (pas à celui de la tuile)
		var cells := {}
		for x in list:
			var c := Vector2i(floori((x as Transform3D).origin.x / TREE_VEG_CELL), floori((x as Transform3D).origin.z / TREE_VEG_CELL))
			if not cells.has(c): cells[c] = []
			cells[c].append(x)
		for c in cells:
			var near := _mm(Vegetation.mesh(kind), cells[c])
			near.visibility_range_end = r.near if v < 7 else r.small
			near.visibility_range_end_margin = 15.0
			if v >= 7: near.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			near.name = ("veg_near_%d" if v < 7 else "veg_small_%d") % kind
			node.add_child(near)

## Maillage complet d'une essence (hauteur et houppier servent à l'étirement LiDAR de _add_tree).
static func _tree_mesh(v: int) -> Mesh:
	return Vegetation.mesh(v)

## Accumulateur de triangles (sommets, couleurs, UV). UV.y < 0 : pas de fenêtres.
class _Arrays:
	var v := PackedVector3Array()
	var c := PackedColorArray()
	var uv := PackedVector2Array()
	var rel := PackedFloat32Array()   # hauteur au-dessus du terrain (couches de sol drapées), 0 par défaut
	var sub := 0.0     # > 0 : triangles coupés (bissection du plus grand côté) jusqu'à cette taille, pour le drapé

	func count() -> int:
		return v.size()

	## Hauteur de la couche au-dessus du terrain (sommet i) : décalage de profondeur relatif au sol.
	func set_rel(i: int, h: float) -> void:
		if rel.size() <= i: rel.resize(v.size())
		rel[i] = h

	## Identifiant de matériau (UV2.x, voir pbr_world.gdshader) déduit de l'alpha de la couleur de sommet.
	static func mat_id(a: float) -> float:
		if a < 0.25: return 1.0
		if a > 0.275 and a < 0.285: return 2.0
		if a > 0.285 and a < 0.295: return 3.0
		if a > 0.295 and a < 0.305: return 4.0
		if a > 0.305 and a < 0.315: return 10.0  # dalle béton de plateforme (P1)
		if a > 0.315 and a < 0.325: return 11.0  # ballast
		if a > 0.325 and a < 0.335: return 12.0  # pavés granit
		if a > 0.385 and a < 0.395: return 13.0  # granit (bordures, trottoirs)
		if a > 0.395 and a < 0.405: return 14.0  # béton banché (trémies, soutènements)
		if a > 0.405 and a < 0.415: return 15.0  # métal peint
		if a > 0.34 and a < 0.36: return 5.0
		if a > 0.365 and a < 0.375: return 9.0   # métal (rails, aiguilles)
		if a > 0.42 and a < 0.48: return 6.0
		if a > 0.5 and a < 0.999: return 7.0 + float(roundi(a * 1000.0)) / 1024.0
		return 8.0

	func tri(a: Vector3, b: Vector3, d: Vector3, col: Color, _u: float = -1.0) -> void:
		# garde-fou : triangle de décor démesuré et très incliné (sommet aberrant des données : « nappe » tendue dans le
		# ciel au-dessus des voies) ; le sol lointain (200 m) et l'eau (plane) n'atteignent pas ces seuils
		var big := maxf(Vector2(a.x - b.x, a.z - b.z).length_squared(), maxf(Vector2(b.x - d.x, b.z - d.z).length_squared(), Vector2(d.x - a.x, d.z - a.z).length_squared()))
		if big > (14400.0 if col.a < 0.99 else 90000.0) and maxf(a.y, maxf(b.y, d.y)) - minf(a.y, minf(b.y, d.y)) > (10.0 if col.a < 0.99 else 15.0): return
		if sub > 0.0:
			var lab := Vector2(a.x - b.x, a.z - b.z).length_squared()
			var lbd := Vector2(b.x - d.x, b.z - d.z).length_squared()
			var lda := Vector2(d.x - a.x, d.z - a.z).length_squared()
			var m := maxf(lab, maxf(lbd, lda))
			if m > sub * sub:
				if m == lab:
					var q := (a + b) * 0.5; tri(a, q, d, col); tri(q, b, d, col)
				elif m == lbd:
					var q := (b + d) * 0.5; tri(a, b, q, col); tri(a, q, d, col)
				else:
					var q := (d + a) * 0.5; tri(a, b, q, col); tri(q, b, d, col)
				return
		v.append(a); v.append(b); v.append(d)
		c.append(col); c.append(col); c.append(col)
		uv.append(Vector2(-1, -1)); uv.append(Vector2(-1, -1)); uv.append(Vector2(-1, -1))

	func quad(a: Vector3, b: Vector3, d: Vector3, e: Vector3, col: Color, u: float) -> void:
		tri(a, b, d, col, u); tri(a, d, e, col, u)

	## Mur vertical avec UV (abscisse le long des façades, hauteur) pour les fenêtres procédurales.
	func wall(a: Vector3, b: Vector3, h: float, col: Color, u0: float, u1: float) -> void:
		var a2 := a + Vector3(0, h, 0); var b2 := b + Vector3(0, h, 0)
		var y0 := a.y
		for p in [[a, Vector2(u0, y0)], [b, Vector2(u1, y0)], [b2, Vector2(u1, y0 + h)], [a, Vector2(u0, y0)], [b2, Vector2(u1, y0 + h)], [a2, Vector2(u0, y0 + h)]]:
			v.append(p[0]); c.append(col); uv.append(p[1] if u1 > u0 else Vector2(-1, -1))

	func box(ctr: Vector3, s: Vector3, col: Color) -> void:
		var h := s * 0.5
		var p := [ctr + Vector3(-h.x, -h.y, -h.z), ctr + Vector3(h.x, -h.y, -h.z), ctr + Vector3(h.x, h.y, -h.z), ctr + Vector3(-h.x, h.y, -h.z),
			ctr + Vector3(-h.x, -h.y, h.z), ctr + Vector3(h.x, -h.y, h.z), ctr + Vector3(h.x, h.y, h.z), ctr + Vector3(-h.x, h.y, h.z)]
		for f in [[0, 1, 2, 3], [5, 4, 7, 6], [4, 0, 3, 7], [1, 5, 6, 2], [3, 2, 6, 7]]:
			quad(p[f[0]], p[f[1]], p[f[2]], p[f[3]], col, -1.0)

	func cone(base: Vector3, r: float, h: float, sides: int, col: Color) -> void:
		var tip := base + Vector3(0, h, 0)
		for i in sides:
			var a0 := TAU * i / sides; var a1 := TAU * (i + 1) / sides
			tri(base + Vector3(cos(a0) * r, 0, sin(a0) * r), base + Vector3(cos(a1) * r, 0, sin(a1) * r), tip, col)

	## Tronc prismatique effilé.
	func trunk(base: Vector3, r: float, h: float, sides: int, col: Color) -> void:
		for i in sides:
			var a0 := TAU * i / sides; var a1 := TAU * (i + 1) / sides
			var p0 := Vector3(cos(a0), 0, sin(a0)); var p1 := Vector3(cos(a1), 0, sin(a1))
			quad(base + p0 * r, base + p1 * r, base + p1 * r * 0.65 + Vector3(0, h, 0), base + p0 * r * 0.65 + Vector3(0, h, 0), col, -1.0)

	## Ellipsoïde low poly (houppier) : 3 parallèles décalés d'un demi-pas (facettes triangulaires régulières),
	## léger relief déterministe ; teinte claire au-dessus, foncée dessous.
	func blob(ctr: Vector3, rad: Vector3, sides: int, top: Color, bottom: Color, seed: int) -> void:
		var lats := [-0.55, 0.0, 0.5]
		var rings: Array = []
		for j in lats.size():
			var ring: Array = []
			var lat: float = lats[j] * PI * 0.5
			for i in sides:
				var ang := TAU * (i + 0.5 * float(j % 2)) / sides
				var jit := 1.0 + 0.09 * sin(float(i * 7 + j * 3 + seed * 5) * 1.7)
				ring.append(ctr + Vector3(cos(ang) * cos(lat) * rad.x * jit, sin(lat) * rad.y, sin(ang) * cos(lat) * rad.z * jit))
			rings.append(ring)
		var bot := ctr + Vector3(0, -rad.y * 0.85, 0); var tp := ctr + Vector3(0, rad.y, 0)
		var ymid := ctr.y
		var shade := func(p: Vector3) -> Color: return top if p.y > ymid + rad.y * 0.05 else bottom
		for i in sides:
			var i1 := (i + 1) % sides
			tri(rings[0][i1], rings[0][i], bot, bottom)
			tri(rings[2][i], rings[2][i1], tp, top)
			for j in range(lats.size() - 1):
				var lo: Array = rings[j]; var hi: Array = rings[j + 1]
				if j % 2 == 0:  # parallèle supérieur décalé de +1/2 pas
					var c1: Vector3 = (lo[i] + lo[i1] + hi[i]) / 3.0
					tri(lo[i], lo[i1], hi[i], shade.call(c1))
					var c2: Vector3 = (lo[i1] + hi[i1] + hi[i]) / 3.0
					tri(lo[i1], hi[i1], hi[i], shade.call(c2))
				else:
					var c1: Vector3 = (lo[i] + lo[i1] + hi[i1]) / 3.0
					tri(lo[i], lo[i1], hi[i1], shade.call(c1))
					var c2: Vector3 = (lo[i] + hi[i1] + hi[i]) / 3.0
					tri(lo[i], hi[i1], hi[i], shade.call(c2))

	func mesh() -> ArrayMesh:
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = v
		arr[Mesh.ARRAY_COLOR] = c
		arr[Mesh.ARRAY_TEX_UV] = uv
		if rel.size() < v.size(): rel.resize(v.size())
		var uv2 := PackedVector2Array(); uv2.resize(v.size())
		var last_a := -1.0; var last_id := 8.0
		for i in v.size():
			var a := c[i].a
			if a != last_a: last_a = a; last_id = mat_id(a)
			uv2[i] = Vector2(last_id, rel[i])
		arr[Mesh.ARRAY_TEX_UV2] = uv2
		# normales de facette : servent au biais normal des ombres (anti-acné), l'éclairage les recalcule au pixel
		var nr := PackedVector3Array(); nr.resize(v.size())
		for i in range(0, v.size() - 2, 3):
			var fn := (v[i + 2] - v[i]).cross(v[i + 1] - v[i]).normalized()
			if fn.y < -0.01: fn = -fn   # faces vues des deux côtés : normale vers le ciel
			nr[i] = fn; nr[i + 1] = fn; nr[i + 2] = fn
		arr[Mesh.ARRAY_NORMAL] = nr
		var m := ArrayMesh.new()
		if v.size() > 0:
			m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		return m
