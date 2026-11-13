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
var style: Dictionary = {}
var city := ""
var stats := {"tiles": 0, "buildings": 0}
static var _styles: Dictionary = {}
static var _trees: Array[Mesh] = []
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
var _street_keepout := TrackView.KeepOut.new()
var _camera_boxes: Array = []    # obstacles caméra de la tuile : [0, emprise, y0, y1, Rect2] ou [1, centre, rayon, demi-hauteur]
var _portal_cut := TrackView.KeepOut.new()
var _hangar_footprints: Array[PackedVector2Array] = []
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
	_file = FileAccess.get_file_as_bytes(path_for(c))
	buf = _file
	var magic := _file.slice(0, 4).get_string_from_ascii() if _file.size() >= 8 else ""
	if magic not in ["TSC1", "TSC2", "TSC3", "TSC4"]:
		return false
	v4 = magic == "TSC4"
	v2 = magic != "TSC1"
	v3 = magic == "TSC3" or v4
	var meta = JSON.parse_string(FileAccess.get_file_as_string("res://data/scenes/%s.json" % c))
	tile_m = float(meta.tile_m)
	var n := _file.decode_u32(4)
	for i in n:
		var o := 8 + i * (20 if v4 else 16)
		var k := Vector2i(_file.decode_s32(o), _file.decode_s32(o + 4))
		if v4:   # [offset, taille compressée, taille] : table[k].y reste la taille du contenu
			table[k] = Vector2i(_file.decode_u32(o + 8), _file.decode_u32(o + 16)); _tsc_cs[k] = _file.decode_u32(o + 12)
		else:
			table[k] = Vector2i(_file.decode_u32(o + 8), _file.decode_u32(o + 12))
	# origine de la ville exprimée dans le repère de la ligne
	var lat_n := float(net_origin[0]); var lon_n := float(net_origin[1])
	var lat_c := float(meta.origin[0]); var lon_c := float(meta.origin[1])
	position = Vector3(deg_to_rad(lon_c - lon_n) * R * cos(deg_to_rad(lat_n)), 0.0, -deg_to_rad(lat_c - lat_n) * R)
	_x_scale = cos(deg_to_rad(lat_n)) / cos(deg_to_rad(lat_c))
	scale.x = _x_scale
	_load_style(c)
	_load_track_nature(c)
	_load_terrain(c)
	_load_road_levels(c)
	return true

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
	var data:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(path))
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
			var meta = JSON.parse_string(FileAccess.get_file_as_string("res://data/scenes/%s_terrain.json" % c))
			if typeof(meta) == TYPE_DICTIONARY: alt0 = float(meta.get("alt0", 0.0))
			var d := tv.meta_bytes()
			var q := 0
			for k in tv.keys: q = _ter_records(k, d, q)
			min_height = tv.min_height
			has_terrain = not tv.table.is_empty()
			return
		tv.free()
	var path := "res://data/scenes/%s_terrain.bin" % c
	if not FileAccess.file_exists(path): return
	_ter = FileAccess.get_file_as_bytes(path)
	if _ter.size() < 8: return
	var magic := _ter.slice(0, 4).get_string_from_ascii()
	if magic not in ["TTR1", "TTR2"]: return
	_ter_float = magic == "TTR2"
	var meta = JSON.parse_string(FileAccess.get_file_as_string("res://data/scenes/%s_terrain.json" % c))
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
		return h if not is_nan(h) else terrain.far_height(x, z) - 1.5
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
			if (int(d[0]) == 1) != rail: continue
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
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
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
		_styles = JSON.parse_string(FileAccess.get_file_as_string("res://data/city_styles.json"))
	var key: String = _styles.cities.get(c, "")
	style = _styles.styles.get(key, _styles.default).duplicate(true)
	var identities: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/city_identity.json"))
	style.merge(identities.get(c, {}), true)

func _pal(name: String, h: int) -> Color:
	var arr: Array = style.get(name, ["#cccccc"])
	return Color.from_string(str(arr[absi(h) % arr.size()]), Color.GRAY)

## À appeler à chaque image avec la position de la caméra (repère de la ligne).
func update(center_net: Vector3, budget_tiles: int = 1) -> void:
	var c := center_net - position
	c.x /= _x_scale
	var r := radius
	var t0 := Vector2i(floori((c.x - r) / tile_m), floori((c.z - r) / tile_m))
	var t1 := Vector2i(floori((c.x + r) / tile_m), floori((c.z + r) / tile_m))
	for tx in range(t0.x, t1.x + 1):
		for tz in range(t0.y, t1.y + 1):
			var k := Vector2i(tx, tz)
			if (table.has(k) or _ter_table.has(k) or (terrain != null and terrain.has_tile(k))) and not built.has(k) and not k in queue:
				queue.append(k)
	if terrain != null: terrain.update_far(c)
	var ctile := Vector2(c.x, c.z) / tile_m
	queue.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return (Vector2(a) + Vector2(0.5, 0.5)).distance_squared_to(ctile) < (Vector2(b) + Vector2(0.5, 0.5)).distance_squared_to(ctile))
	for k in built.keys():
		if (Vector2(k) + Vector2(0.5, 0.5)).distance_to(ctile) * tile_m > r * 1.5:
			built[k].queue_free(); built.erase(k)
	queue = queue.filter(func(k: Vector2i) -> bool: return (Vector2(k) + Vector2(0.5, 0.5)).distance_to(ctile) * tile_m <= r * 1.5)
	for i in budget_tiles:
		if queue.is_empty(): break
		var k: Vector2i = queue.pop_front()
		built[k] = _build_tile(k)
		add_child(built[k])

## Construit toutes les tuiles proches d'un coup (chargement initial).
func warm(center_net: Vector3) -> void:
	update(center_net, 0)
	while not queue.is_empty():
		update(center_net, 4)

func _build_tile(k: Vector2i) -> Node3D:
	var node := Node3D.new()
	node.position = Vector3(k.x * tile_m, 0, k.y * tile_m)
	var S := _Arrays.new()
	var W := _Arrays.new()
	_trees_cur = []; _camera_boxes = []
	for i in TREE_KINDS: _trees_cur.append([])
	_tile_origin = Vector2(k.x * tile_m, k.y * tile_m)
	var seed := hash(k)
	var ground := Color.from_string(str(style.get("ground", "#cfcac0")), Color.GRAY)
	# sol : maillage continu relief + voirie (TerrainView / RoadView), sinon grille de relief héritée
	var gmesh: ArrayMesh = null
	if terrain != null and terrain.has_tile(k): gmesh = RoadView.build(terrain, terrain.tile(k), k, style, _portal_cut)
	elif has_terrain and _ter_table.has(k): _terrain_mesh(S, k, ground)
	else: S.quad(Vector3(0, 0, 0), Vector3(tile_m, 0, 0), Vector3(tile_m, 0, tile_m), Vector3(0, 0, tile_m), ground, -1.0)
	for di in _decks.size():
		if _decks[di][3] == k: _deck(S, _decks[di])
	if not table.has(k):   # couronne de relief autour du décor
		var gi := MeshInstance3D.new(); gi.mesh = S.mesh(); gi.material_override = Materials.building()
		node.add_child(gi)
		if gmesh != null:
			var gr := MeshInstance3D.new(); gr.mesh = gmesh; gr.material_override = Materials.building()
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
	var polys_start := o
	var np := buf.decode_u16(o); o += 2
	_water_cur = []
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
	for l in nl:
		var cls:=buf.decode_u8(o);var width_:=buf.decode_u8(o+1)/5.0;var count:=buf.decode_u16(o+2);o+=4
		var road:=PackedVector2Array()
		for j in count:
			road.append(Vector2(buf.decode_s16(o)*0.1,buf.decode_s16(o+2)*0.1));o+=4
		_street_keepout.add_polyline(road,maxf(width_*0.5,1.2)+0.35)
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
	var veg: Image = null
	if not runs.is_empty():
		var cells := int(tile_m / 4.0)
		veg = Image.create(cells, cells, false, Image.FORMAT_L8)
	for r in runs:
		var z0: float = r.x * 4.0; var x0: float = r.y * 4.0; var x1: float = x0 + r.z * 4.0
		for cx in range(r.y, r.y + r.z):
			if cx < veg.get_width() and r.x < veg.get_height() and not _in_water(Vector2(cx * 4.0 + 2.0, z0 + 2.0)):
				veg.set_pixel(cx, r.x, Color.WHITE)
		for j in mini(int((x1-x0)/8.0),6):
			if meadow_count>=128:break
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
		_add_tree(kind, Vector3(t[0].x, 0.02, t[0].y), trng, sc, true)
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
		var j0 := S.count()
		_building(S, b[0], b[1], b[2], b[3], b[4], seed + i, points, rc)
		if has_terrain:  # posé au sol : base à l'altitude minimale de l'emprise
			var base := INF
			for q in b[0]: base = minf(base, _ground_h(q))
			_lift(S, j0, base)
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
		if cls != P_WATER and _in_water(_centroid(v)): o += ntr * 6; continue
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
		_line(S, pts, cls, w, seed + l)
		S.sub = 0.0
		_drape(S, l0, _deck_for_line(pts, cls == L_RAIL))
	# éléments ponctuels (clochers isolés, tours, cheminées)
	for p in points:
		if p[0] == 1 and p.size() > 3: continue  # clocher déjà rattaché à une église
		if _keepout != null and _keepout.blocked(_tile_origin + p[2], 3.0): continue
		var q0 := S.count()
		_point(S, p[0], p[1], p[2])
		_lift(S, q0, _ground_h(p[2]) if has_terrain else 0.0)
	# maillages
	var mi := MeshInstance3D.new(); mi.mesh = S.mesh(); mi.material_override = Materials.building()
	if veg != null:
		var tm: ShaderMaterial = Materials.building().duplicate()
		tm.set_shader_parameter("veg_mask", ImageTexture.create_from_image(veg))
		tm.set_shader_parameter("veg_inv_size", 1.0 / tile_m)
		mi.material_override = tm
	node.add_child(mi)
	if gmesh != null:   # même matériau (masque de végétation de la tuile)
		var gm := MeshInstance3D.new(); gm.mesh = gmesh; gm.material_override = mi.material_override
		node.add_child(gm)
	if W.count() > 0:
		var wi := MeshInstance3D.new(); wi.mesh = W.mesh(); wi.material_override = Materials.water()
		node.add_child(wi)
	for v in TREE_KINDS:
		if _trees_cur[v].is_empty(): continue
		var mm := MultiMesh.new(); mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _tree_mesh(v); mm.instance_count = _trees_cur[v].size()
		for i in _trees_cur[v].size(): mm.set_instance_transform(i, _trees_cur[v][i])
		var mmi := MultiMeshInstance3D.new(); mmi.multimesh = mm; mmi.material_override = Materials.foliage()
		node.add_child(mmi)
	# noms des monuments
	for lb in labels:
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

## Le hangar détaillé remplace son extrusion de décor, afin de garder ses entrées ouvertes.
func replace_hangar(footprint_net: PackedVector2Array) -> void:
	var polygon := PackedVector2Array()
	for p in footprint_net: polygon.append(Vector2((p.x - position.x) / _x_scale, p.y - position.z))
	_hangar_footprints.append(polygon)

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
	var sat := c.s / 1.3 * (0.45 if c.h > 0.5 and c.h < 0.85 else 1.0)
	return Color.from_hsv(c.h, sat, clampf((c.v - 0.05) / 1.12 * 0.9, 0.0, 1.0))

var _water_cur: Array = []          # triangles d'eau de la tuile en cours : [PackedVector2Array(3), Rect2]
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

## Dernier contrôle, point de voie par point de voie (mêmes règles que tests/test_clearance.gd) : un segment de
## tablier encore dans le gabarit est abaissé au rail (moins de 2,5 m au-dessus) ou relevé au-dessus du gabarit.
func _enforce_gauge() -> void:
	for it_ in 2:
		for ck in _track_pts:
			for q in _track_pts[ck]:
				var c := Vector2(q.x, q.z)
				for it in _deck_cells.get(Vector2i(floori(c.x / 32.0), floori(c.y / 32.0)), []):
					var d: Array = _decks[it[0]]
					var pl: PackedVector3Array = d[2]
					var m: int = it[1]
					var a := Vector2(pl[m].x, pl[m].z); var b := Vector2(pl[m + 1].x, pl[m + 1].z)
					var t := clampf((c - a).dot(b - a) / maxf((b - a).length_squared(), 1e-4), 0.0, 1.0)
					if (a + (b - a) * t).distance_to(c) > float(d[1]) * 0.5 + GAUGE_HW + 0.5: continue
					var y := lerpf(pl[m].y, pl[m + 1].y, t)
					if y <= q.y + 0.2 or y - 1.1 >= q.y + GAUGE_H: continue
					for e in [m, m + 1]:
						pl[e].y = minf(pl[e].y, q.y - 0.1) if y - q.y < 2.5 else maxf(pl[e].y, q.y + GAUGE_H + 1.5)
					d[2] = pl

## Sommet j d'un tablier face aux voies : Vector2(altitude si la voie est portée (parallèle), altitude minimale
## si le tablier la franchit dans le gabarit) ; NAN sinon. `merge` : premier passage, la voie parallèle proche
## (jusqu'à 15 m en dessous) est considérée comme portée par le tablier (fusion route + tram).
func _deck_conflict(rs: PackedVector3Array, j: int, hw: float, merge: bool) -> Vector2:
	var a := rs[maxi(j - 1, 0)]; var b := rs[mini(j + 1, rs.size() - 1)]
	var sd := Vector2(b.x - a.x, b.z - a.z).normalized()
	var p := Vector2(rs[j].x, rs[j].z)
	var dirs := []
	var near := _tracks_near(p, hw + GAUGE_HW + 6.0, dirs)
	var ride := NAN; var top := NAN
	for t in near.size():
		var dy := rs[j].y - near[t].y
		var rel := Vector2(near[t].x, near[t].z) - p
		if absf(rel.cross(sd)) > hw + GAUGE_HW + 0.5 or absf(rel.dot(sd)) > 6.0: continue
		var parallel := absf((dirs[t] as Vector2).dot(sd)) > 0.9
		if parallel and dy > (-6.0 if merge else 0.2) and dy < (15.0 if merge else GAUGE_H + 1.7):
			ride = near[t].y - 0.1 if is_nan(ride) else minf(ride, near[t].y - 0.1)
		elif not parallel and dy > 0.2 and dy < GAUGE_H + 1.7:
			top = maxf(top, near[t].y + GAUGE_H + 2.0) if not is_nan(top) else near[t].y + GAUGE_H + 2.0
	return Vector2(ride, top)

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
				if q.y < y + 1.2 and q.y > y - 6.0 and r.has_point(Vector2(q.x, q.z)): return true
	var m := (a + b + c) / 3.0 + _tile_origin
	var dk := deck_city(m.x, m.y)
	return not is_nan(dk) and dk < y + 1.5

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
	var bed := inner[inner.size() / 4] + 0.05
	var y := minf(lv if not is_nan(lv) else bank, bank - 0.15)
	if y < bed: y = minf(bed, bank + 0.25)
	return y

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
		var dn := Vector3(0, -1.1, 0)
		# dalle : rives et sous-face
		S.quad(a + n, b + n, b + n + dn, a + n + dn, concrete, -1.0)
		S.quad(b - n, a - n, a - n + dn, b - n + dn, concrete, -1.0)
		S.quad(a + n + dn, b + n + dn, b - n + dn, a - n + dn, concrete.darkened(0.25), -1.0)
		S.quad(a - n, b - n, b + n, a + n, Color("#7d7f83"), -1.0)
		# garde-corps
		for side in [-1.0, 1.0]:
			var e: Vector3 = n * side * 0.97
			var up := Vector3(0, 1.05, 0)
			S.quad(a + e, b + e, b + e + up, a + e + up, rail, -1.0)
			S.quad(b + e * 0.94, a + e * 0.94, a + e * 0.94 + up, b + e * 0.94 + up, rail, -1.0)
			S.quad(a + e + up, b + e + up, b + e * 0.94 + up, a + e * 0.94 + up, rail.lightened(0.1), -1.0)
	# piles (hors gabarit des voies)
	for pile in deck_piles(d):
		var c: Vector3 = pile[0] - o; var gh: float = pile[1]
		var hgt: float = c.y - 1.1 - gh + 1.5
		S.box(Vector3(c.x, gh - 1.5 + hgt * 0.5, c.z), Vector3(1.3, hgt, 1.3), concrete.darkened(0.08))

# ----------------------------------------------------------------------------------------------- bâtiments

const STONE := Color("#ddd3c0")
const SLATE := Color("#4b5057")   # ardoise : gris anthracite (orthophoto), plus de lavande
const ZINC := Color("#7e8a95")
const GLASS_SHOP := 0.45     # alpha des vitrines (éclairées la nuit)
const SOLID_A := 0.35        # alpha sans fenêtres

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
func _mansard(S: _Arrays, ring: PackedVector2Array, y: float, col: Color) -> void:
	var c := _centroid(ring)
	var inner := PackedVector2Array()
	for p in ring: inner.append(p + (c - p).limit_length(1.4))
	for i in ring.size():
		var a := ring[i]; var b := ring[(i + 1) % ring.size()]; var ia := inner[i]; var ib := inner[(i + 1) % ring.size()]
		S.quad(Vector3(a.x, y, a.y), Vector3(b.x, y, b.y), Vector3(ib.x, y + 2.8, ib.y), Vector3(ia.x, y + 2.8, ia.y), Color(col.r, col.g, col.b, SOLID_A), -1.0)
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
			var y1 := minf(h, y + (1.6 if striped else h))
			var col := wall
			if striped and band % 2 == 1: col = Color("#3e3b3d")
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
	var kind := kind_raw & 0x7f
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
					var y1 := minf(h, y + 1.6)
					_walls(S, ring, y, y1, Color("#3e3b3d") if band % 2 == 1 else Color("#d8cfbd"), false)
					y = y1; band += 1
			else:
				_walls(S, ring, 0.0, h, Color(stone.r, stone.g, stone.b, SOLID_A), false)
			_flat_roof(S, ring, idx, h, Color("#8a8278"))
			_crenels(S, ring, h, stone)
			if area > 400.0 and (principal or area > 1500.0):
				for i in n:
					var p := ring[i]; var pa := ring[(i - 1 + n) % n]; var pb := ring[(i + 1) % n]
					if (pa - p).normalized().dot((pb - p).normalized()) > -0.4 and p.distance_to(pa) > 8.0:
						_round_tower(S, p, clampf(sqrt(area) * 0.08, 3.0, 7.0), h + 3.0, stone, SLATE, not striped, striped)
			return
		K_STATION:
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
	# --- bâti courant
	var wall: Color
	match cls:
		2: wall = Color("#c7c3ba").lerp(Color("#a9b0b5"), (seed % 7) / 7.0)
		3: wall = STONE
		4: wall = Color("#eee6d2")
		5: wall = Color("#b9b6ae")
		_: wall = _pal("walls", seed)
	var windows := cls == 0 or cls == 1 or cls == 4
	var paris: bool = style.get("pitched", "") == "#6f7a85"
	var shop := (cls == 1 or (cls == 0 and h > 11.0 and rng.randf() < 0.45)) and h > 6.0
	var y0 := 0.0
	if shop:  # rez-de-chaussée commercial : vitrines (éclairées le soir)
		_walls(S, ring, 0.0, 3.4, Color(0.2, 0.24, 0.27, GLASS_SHOP), false)
		y0 = 3.4
	if cls != 2: _facade_detail(S,ring,h,seed,shop)
	wall.a = _wall_a(seed) if windows else SOLID_A
	_walls(S, ring, y0, h, wall, windows)
	if paris and cls == 0 and h > 13.0 and n <= 16:
		# immeuble haussmannien : balcons filants aux 2e et 5e étages, mansarde en zinc
		_ledge(S, ring, 7.4, 0.8, Color("#e9e1cf"))
		if h > 18.0: _ledge(S, ring, h - 3.6, 0.8, Color("#e9e1cf"))
		_mansard(S, ring, h, ZINC)
		return
	if cls == 0 and h <= 12.0 and area < 320.0 and n == 4:
		_gable_roof(S, ring, h, clampf(sqrt(area) * 0.35, 1.5, 4.0), pitched, wall)
		if rng.randf() < 0.5:  # cheminée
			var p := ring[0].lerp(ring[2], 0.3)
			S.box(Vector3(p.x, h + 2.2, p.y), Vector3(0.6, 1.6, 0.6), Color("#9c6a52", SOLID_A))
	elif cls == 0 and h <= 12.0 and n <= 8 and area < 320.0:
		_hip_roof(S, ring, h, clampf(sqrt(area) * 0.3, 1.2, 3.5), pitched)
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
			_ledge(S, ring, h, 0.28, Color(wall.r * 1.08, wall.g * 1.08, wall.b * 1.06))
		if h > 12.0 and n <= 12:
			_walls(S, ring, h, h + 0.6, Color(roof.r * 1.1, roof.g * 1.1, roof.b * 1.1, SOLID_A), false)
		if h > 15.0 and rng.randf() < 0.6:  # édicule technique
			S.box(Vector3(c.x, h + 1.2, c.y), Vector3(3.0, 2.4, 3.0), Color("#b3b0a8", SOLID_A))

## Menuiseries et balcons en géométrie, sur la façade principale de l'emprise.
## Détails bornés par bâtiment ; toutes les pièces restent dans le maillage de tuile.
func _facade_detail(S: _Arrays, ring: PackedVector2Array, height_: float, seed_: int, shop: bool) -> void:
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
	var u0:=0.0
	for i in longest:u0+=ring[i].distance_to(ring[(i+1)%ring.size()])
	var face_seed:=floorf(_wall_a(seed_)*1000.0+0.5)
	var bay:=lerpf(2.4,4.0,fposmod(face_seed*0.6180339,1.0))
	var first_bay:=ceili((u0+1.25)/bay-0.5)
	var bays:=clampi(int(length_/bay),1,8)
	for i in bays:
		var along:=(first_bay+i+0.5)*bay-u0
		if along>length_-1.25:break
		var center:=a+tangent*along+normal*0.08
		var p:=Vector3(center.x,0,center.y);var t:=Vector3(tangent.x,0,tangent.y);var out:=Vector3(normal.x,0,normal.y)
		if shop:
			S.quad(p-t*1.25+Vector3.UP*2.9,p+t*1.25+Vector3.UP*2.9,p+t*1.25+out*0.9+Vector3.UP*2.65,p-t*1.25+out*0.9+Vector3.UP*2.65,accent,-1.0)
			S.quad(p-t*1.25+out*0.9+Vector3.UP*2.65,p+t*1.25+out*0.9+Vector3.UP*2.65,p+t*1.25+out*0.9+Vector3.UP*2.4,p-t*1.25+out*0.9+Vector3.UP*2.4,accent.darkened(0.12),-1.0)
		elif i==0:
			S.quad(p-t*0.5,p+t*0.5,p+t*0.5+Vector3.UP*2.3,p-t*0.5+Vector3.UP*2.3,accent,-1.0)
		if height_>8.0 and posmod(seed_,3)==0:
			var y:=Vector3.UP*3.5
			S.quad(p-t*1.0+y,p+t*1.0+y,p+t*1.0+out*0.7+y,p-t*1.0+out*0.7+y,Color("#bdb7aa",SOLID_A),-1.0)
			for j in 7:
				var x:=p+t*(j/3.0-1.0)+out*0.7+y
				S.box(x+Vector3.UP*0.45,Vector3(0.035,0.9,0.035),accent)
			S.quad(p-t+y+out*0.7+Vector3.UP*0.87,p+t+y+out*0.7+Vector3.UP*0.87,p+t+y+out*0.7+Vector3.UP*0.94,p-t+y+out*0.7+Vector3.UP*0.94,accent,-1.0)

func _point(S: _Arrays, kind: int, h: float, p: Vector2) -> void:
	match kind:
		1: _tower(S, p, 6.0, h * 0.62, h * 0.38, STONE, SLATE)
		2: _tower(S, p, 5.0, h, 0.0, STONE, SLATE)
		3: _round_tower(S, p, 2.5, h, Color("#f2f2f2"), Color("#c0392b"), true, false)
		4: S.cone(Vector3(p.x, 0, p.y), 1.6, h, 8, Color("#9c6a52", SOLID_A))

## Mobilier et plantations le long d'une route (la chaussée, les trottoirs, les marquages et les voies ferrées sont
## dans le maillage du sol : RoadView / TerrainView).
func _line(S: _Arrays, pts: PackedVector2Array, cls: int, w: float, seed: int) -> void:
	if cls == L_RAIL or cls == L_PATH or cls == L_SMALL: return
	# arbres d'alignement (essence dominante de la ville), de part et d'autre des avenues
	if (cls == L_MAJOR or (cls == L_ROAD and w >= 7.0)) and not _ortho_tile:  # sinon arbres réels (orthophoto)
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
	# lampadaires sur trottoir (émissifs la nuit)
	if cls == L_MAJOR or (cls == L_ROAD and w >= 6.0):
		var acc2 := float(seed % 17)
		for i in range(pts.size() - 1):
			var a := pts[i]; var b := pts[i + 1]
			var len := a.distance_to(b)
			var d := (b - a) / maxf(len, 0.001)
			var nrm := Vector2(-d.y, d.x) * (w * 0.5 + 1.2)
			var s := fposmod(-acc2, 32.0)
			while s < len:
				var p := a + d * s + nrm
				if _keepout != null and _keepout.blocked(_tile_origin + p, 0.4):
					s += 32.0; continue
				S.box(Vector3(p.x, 3.0, p.y), Vector3(0.18, 6.0, 0.18), Color("#4a4d52", 0.4))
				if debug_props: placed_props.append(_tile_origin + p)
				S.box(Vector3(p.x, 6.05, p.y), Vector3(0.5, 0.18, 0.5), Color(1.0, 0.86, 0.55, 0.1))
				s += 32.0
			acc2 += len

## Essences : 0 feuillu rond, 1 conifère, 2 feuillu élancé, 3 pin parasol, 4 palmier, 5 peuplier, 6 platane.
func _pick_tree(rng: RandomNumberGenerator) -> int:
	var mix: Array = style.get("trees", [0, 2, 1])
	return int(mix[rng.randi() % mix.size()])

## Recherche d'un monument nommé (étiquette BD TOPO) : position dans le repère de la ligne, ou Vector3.INF.
func find_label(substr: String) -> Vector3:
	if not v2: return Vector3.INF
	for k in table:
		var o: int = _tile_data(k)
		var nb := buf.decode_u16(o); o += 2
		for b in nb:
			var n := buf.decode_u8(o); o += 5 + n * 4
			o += 1 + buf.decode_u8(o) * 3
		var np := buf.decode_u16(o); o += 2
		for p in np: o += 5 + buf.decode_u16(o + 1) * 4 + buf.decode_u16(o + 3) * 6
		var nl := buf.decode_u16(o); o += 2
		for l in nl: o += 4 + buf.decode_u16(o + 2) * 4
		var npt := buf.decode_u16(o); o += 2 + npt * 7
		var nlb := buf.decode_u16(o); o += 2
		for i in nlb:
			var ln := buf.decode_u8(o + 5)
			var name := buf.slice(o + 6, o + 6 + ln).get_string_from_utf8()
			if name.to_lower().contains(substr.to_lower()):
				return position + Vector3(k.x * tile_m + buf.decode_s16(o + 1) * 0.1, 0, k.y * tile_m + buf.decode_s16(o + 3) * 0.1)
			o += 6 + ln
	return Vector3.INF

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
	var polys: Array = []
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
		for i in buried.size():
			if buried[i]: add_portal_cut(axis[maxi(i - 1, 0)], axis[mini(i + 1, axis.size() - 1)], 3.6)
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

func _add_tree(kind: int, pos: Vector3, rng: RandomNumberGenerator, scale: float = 1.0, exact: bool = false) -> void:
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
	if has_terrain: pos.y += _ground_h(Vector2(pos.x, pos.z))
	_trees_cur[kind].append(Transform3D(b, pos))
	var crown_pos := pos + Vector3(0, 5.0 * sc, 0)
	var radius: float = CROWN_R[kind] * sc
	if kind < 7: _camera_boxes.append([1, crown_pos, radius + 0.5, 2.4 * sc + 0.5])
	if debug_props: placed_trees.append(w)

static func _tree_mesh(v: int) -> Mesh:
	if _trees.size() == TREE_KINDS:
		return _trees[v]
	_trees.clear()
	# houppiers en volumes facettés (ellipsoïdes low poly), 2 tons : dessus clair, dessous ombré
	for k in TREE_KINDS:
		var A := _Arrays.new()
		var trunk := Color("#6b4f3a", 0.9)
		match k:
			0:  # feuillu rond (tilleul, chêne) : masse principale + 2 grappes
				A.trunk(Vector3.ZERO, 0.22, 3.2, 5, trunk)
				A.blob(Vector3(0, 4.1, 0), Vector3(2.5, 2.0, 2.5), 10, Color("#6aa84a", 0.9), Color("#3f7a37", 0.9), 1)
				A.blob(Vector3(1.3, 3.5, 0.6), Vector3(1.4, 1.2, 1.4), 6, Color("#6aa84a", 0.9), Color("#3f7a37", 0.9), 2)
				A.blob(Vector3(-1.0, 3.7, -0.9), Vector3(1.3, 1.1, 1.3), 6, Color("#6aa84a", 0.9), Color("#3f7a37", 0.9), 3)
			1:  # conifère : 3 étages
				A.trunk(Vector3.ZERO, 0.2, 2.0, 5, trunk)
				A.cone(Vector3(0, 1.4, 0), 2.3, 2.8, 7, Color("#2f6e46", 0.9))
				A.cone(Vector3(0, 2.9, 0), 1.8, 2.6, 7, Color("#367a4c", 0.9))
				A.cone(Vector3(0, 4.4, 0), 1.2, 2.6, 7, Color("#3e8653", 0.9))
			2:  # feuillu élancé : ovoïde haut
				A.trunk(Vector3.ZERO, 0.18, 3.4, 5, trunk)
				A.blob(Vector3(0, 5.0, 0), Vector3(1.9, 2.8, 1.9), 10, Color("#7cb24c", 0.9), Color("#4d8a3a", 0.9), 4)
			3:  # pin parasol : tronc haut, houppier plat
				A.trunk(Vector3.ZERO, 0.24, 5.4, 5, Color("#7a5a44", 0.9))
				A.blob(Vector3(0, 5.8, 0), Vector3(3.4, 1.0, 3.4), 12, Color("#4f8a42", 0.9), Color("#2f5f30", 0.9), 5)
			4:  # palmier
				A.cone(Vector3(0, 0, 0), 0.35, 7.5, 6, Color("#8b7355", 0.9))
				for i in 7:
					var ang := TAU * i / 7.0
					var d := Vector3(cos(ang), 0, sin(ang))
					A.tri(Vector3(0, 7.3, 0), Vector3(0, 7.3, 0) + d * 3.0 + Vector3(0, -1.2, 0) + d.cross(Vector3.UP) * 0.6,
						Vector3(0, 7.3, 0) + d * 3.0 + Vector3(0, -1.2, 0) - d.cross(Vector3.UP) * 0.6, Color("#4f8f3c", 0.9))
			5:  # peuplier : fuseau
				A.trunk(Vector3.ZERO, 0.16, 1.6, 5, trunk)
				A.blob(Vector3(0, 5.6, 0), Vector3(1.1, 4.6, 1.1), 6, Color("#79aa45", 0.9), Color("#4e8236", 0.9), 6)
			6:  # platane : grand houppier clair, tronc tacheté
				A.trunk(Vector3.ZERO, 0.3, 3.8, 6, Color("#a39a7f", 0.9))
				A.blob(Vector3(0, 5.6, 0), Vector3(3.5, 2.3, 3.5), 12, Color("#8cbc58", 0.9), Color("#58893d", 0.9), 7)
				A.blob(Vector3(1.6, 5.0, -1.0), Vector3(1.8, 1.4, 1.8), 6, Color("#8cbc58", 0.9), Color("#58893d", 0.9), 8)
			7: # massif d'arbustes : feuillage bas dense
				for j in 3:
					A.blob(Vector3((j-1)*0.6,0.65,0),Vector3(0.8,0.65,0.8),7,Color("#6e9450",0.9),Color("#355a3a",0.9),j+14)
			8: # touffe de graminées, feuilles en rubans opaques
				for j in 9:
					var angle:=j*2.399
					var d:=Vector3(cos(angle),0,sin(angle))*0.45
					A.tri(Vector3.ZERO,d+Vector3(0,0.75+0.2*sin(j),0),d*0.5+Vector3(0.12,0,0),Color("#879856",0.9))
			9: # vivaces fleuries / biodiversité ornementale
				for j in 6:
					var p:=Vector3(cos(j*2.4)*0.35,0,sin(j*2.4)*0.35)
					A.trunk(p,0.025,0.65,4,Color("#63854b",0.9))
					A.blob(p+Vector3.UP*0.65,Vector3(0.12,0.13,0.12),5,Color("#d4afc6",0.9),Color("#886ba2",0.9),j+10)

		_trees.append(A.mesh())
	return _trees[v]

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

	## Identifiant de matériau (UV2.x, voir toon_building.gdshader) déduit de l'alpha de la couleur de sommet.
	static func mat_id(a: float) -> float:
		if a < 0.25: return 1.0
		if a > 0.275 and a < 0.285: return 2.0
		if a > 0.285 and a < 0.295: return 3.0
		if a > 0.295 and a < 0.305: return 4.0
		if a > 0.34 and a < 0.36: return 5.0
		if a > 0.42 and a < 0.48: return 6.0
		if a > 0.5 and a < 0.999: return 7.0 + float(roundi(a * 1000.0)) / 1024.0
		return 8.0

	func tri(a: Vector3, b: Vector3, d: Vector3, col: Color, _u: float = -1.0) -> void:
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
