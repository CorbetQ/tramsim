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
var debug_props := false        # tests : mémorise la position (repère ville) des arbres et lampadaires posés
var placed_props: Array[Vector2] = []
var placed_trees: Array[Vector2] = []
var _trees_cur: Array = []
const K_CHURCH := 1
const K_CATHEDRAL := 2
const K_CASTLE := 3
const K_CIVIC := 4
const K_STATION := 5
const K_SCHOOL := 6
const TREE_KINDS := 7

static func path_for(c: String) -> String:
	return "res://data/scenes/%s.bin" % c

static func available(c: String) -> bool:
	return c != "" and FileAccess.file_exists(path_for(c))

## Ouvre la scène d'une ville et la cale sur le repère de la ligne (origine lat/lon de la ligne).
func open(c: String, net_origin: Array) -> bool:
	city = c
	buf = FileAccess.get_file_as_bytes(path_for(c))
	var magic := buf.slice(0, 4).get_string_from_ascii() if buf.size() >= 8 else ""
	if magic != "TSC1" and magic != "TSC2" and magic != "TSC3":
		return false
	v2 = magic == "TSC2" or magic == "TSC3"
	v3 = magic == "TSC3"
	var meta = JSON.parse_string(FileAccess.get_file_as_string("res://data/scenes/%s.json" % c))
	tile_m = float(meta.tile_m)
	var n := buf.decode_u32(4)
	for i in n:
		var o := 8 + i * 16
		table[Vector2i(buf.decode_s32(o), buf.decode_s32(o + 4))] = Vector2i(buf.decode_u32(o + 8), buf.decode_u32(o + 12))
	# origine de la ville exprimée dans le repère de la ligne
	var lat_n := float(net_origin[0]); var lon_n := float(net_origin[1])
	var lat_c := float(meta.origin[0]); var lon_c := float(meta.origin[1])
	position = Vector3(deg_to_rad(lon_c - lon_n) * R * cos(deg_to_rad(lat_n)), 0.0, -deg_to_rad(lat_c - lat_n) * R)
	_load_style(c)
	_load_track_nature(c)
	return true

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
	var k := Vector2i(floori(c.x / _track_cell), floori(c.z / _track_cell))
	if _track_nat.has(k): return _track_nat[k]
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if _track_nat.has(k + d): return _track_nat[k + d]
	return 0

func _load_style(c: String) -> void:
	if _styles.is_empty():
		_styles = JSON.parse_string(FileAccess.get_file_as_string("res://data/city_styles.json"))
	var key: String = _styles.cities.get(c, "")
	style = _styles.styles.get(key, _styles.default)

func _pal(name: String, h: int) -> Color:
	var arr: Array = style.get(name, ["#cccccc"])
	return Color.from_string(str(arr[absi(h) % arr.size()]), Color.GRAY)

## À appeler à chaque image avec la position de la caméra (repère de la ligne).
func update(center_net: Vector3, budget_tiles: int = 1) -> void:
	var c := center_net - position
	var r := radius
	var t0 := Vector2i(floori((c.x - r) / tile_m), floori((c.z - r) / tile_m))
	var t1 := Vector2i(floori((c.x + r) / tile_m), floori((c.z + r) / tile_m))
	for tx in range(t0.x, t1.x + 1):
		for tz in range(t0.y, t1.y + 1):
			var k := Vector2i(tx, tz)
			if table.has(k) and not built.has(k) and not k in queue:
				queue.append(k)
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
	var e: Vector2i = table[k]
	var o := e.x
	var S := _Arrays.new()
	var W := _Arrays.new()
	_trees_cur = []
	for i in TREE_KINDS: _trees_cur.append([])
	_tile_origin = Vector2(k.x * tile_m, k.y * tile_m)
	var seed := hash(k)
	S.quad(Vector3(0, 0, 0), Vector3(tile_m, 0, 0), Vector3(tile_m, 0, tile_m), Vector3(0, 0, tile_m), Color.from_string(str(style.get("ground", "#cfcac0")), Color.GRAY), -1.0)
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
	for p in np:
		var nv := buf.decode_u16(o + 1); var ntr := buf.decode_u16(o + 3); o += 5 + nv * 4 + ntr * 6
	var lines_start := o
	var nl := buf.decode_u16(o); o += 2
	for l in nl:
		o += 4 + buf.decode_u16(o + 2) * 4
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
	# sol vert réel (cellules de 4 m, orthophoto), sous les surfaces BD TOPO et les routes
	var lawn := Color("#8db463")
	for r in runs:
		var z0: float = r.x * 4.0; var x0: float = r.y * 4.0; var x1: float = x0 + r.z * 4.0
		S.quad(Vector3(x0, 0.012, z0), Vector3(x1, 0.012, z0), Vector3(x1, 0.012, z0 + 4.0), Vector3(x0, 0.012, z0 + 4.0), lawn, -1.0)
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
		if _keepout != null and _keepout.blocked(_tile_origin + _centroid(b[0])): continue
		var rc := Color(0, 0, 0, 0)
		if i < roofs.size() and roofs[i] & 0x8000:
			rc = Color(((roofs[i] >> 8) & 15) / 15.0, ((roofs[i] >> 4) & 15) / 15.0, (roofs[i] & 15) / 15.0)
		_building(S, b[0], b[1], b[2], b[3], b[4], seed + i, points, rc)
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
		var col: Color = {P_FOREST: Color("#5e9448"), P_GRASS: Color("#8cbd5b"), P_SPORT: Color("#a9cf6c"), P_CEMETERY: Color("#9cb487")}.get(cls, Color("#8cbd5b"))
		var rng := RandomNumberGenerator.new(); rng.seed = seed * 31 + p
		for t in ntr:
			var a := v[buf.decode_u16(o)]; var b := v[buf.decode_u16(o + 2)]; var c := v[buf.decode_u16(o + 4)]; o += 6
			if cls == P_WATER:
				W.tri(Vector3(a.x, y, a.y), Vector3(b.x, y, b.y), Vector3(c.x, y, c.y), Color.WHITE)
			else:
				S.tri(Vector3(a.x, y, a.y), Vector3(b.x, y, b.y), Vector3(c.x, y, c.y), col, -1.0)
				if (cls == P_FOREST or cls == P_GRASS or cls == P_CEMETERY) and not _ortho_tile:
					var area := absf((b - a).cross(c - a)) * 0.5
					var dens := 110.0 if cls == P_FOREST else 700.0
					var count := mini(int(area / dens + rng.randf()), 40)
					for i in count:
						var r1 := sqrt(rng.randf()); var r2 := rng.randf()
						var q := a * (1.0 - r1) + b * (r1 * (1.0 - r2)) + c * (r1 * r2)
						var kind := 1 if (cls == P_CEMETERY and rng.randf() < 0.6) else _pick_tree(rng)
						_add_tree(kind, Vector3(q.x, y, q.y), rng)
	# lignes (routes avec arbres d'alignement, voies ferrées)
	o = lines_start
	nl = buf.decode_u16(o); o += 2
	for l in nl:
		var cls := buf.decode_u8(o); var w := buf.decode_u8(o + 1) / 5.0; var n := buf.decode_u16(o + 2); o += 4
		var pts := PackedVector2Array(); pts.resize(n)
		for i in n:
			pts[i] = Vector2(buf.decode_s16(o) * 0.1, buf.decode_s16(o + 2) * 0.1); o += 4
		_line(S, pts, cls, w, seed + l)
	# éléments ponctuels (clochers isolés, tours, cheminées)
	for p in points:
		if p[0] == 1 and p.size() > 3: continue  # clocher déjà rattaché à une église
		if _keepout != null and _keepout.blocked(_tile_origin + p[2], 3.0): continue
		_point(S, p[0], p[1], p[2])
	# maillages
	var mi := MeshInstance3D.new(); mi.mesh = S.mesh(); mi.material_override = Materials.building()
	node.add_child(mi)
	if W.count() > 0:
		var wi := MeshInstance3D.new(); wi.mesh = W.mesh(); wi.material_override = Materials.water()
		node.add_child(wi)
	for v in TREE_KINDS:
		if _trees_cur[v].is_empty(): continue
		var mm := MultiMesh.new(); mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _tree_mesh(v); mm.instance_count = _trees_cur[v].size()
		for i in _trees_cur[v].size(): mm.set_instance_transform(i, _trees_cur[v][i])
		var mmi := MultiMeshInstance3D.new(); mmi.multimesh = mm; mmi.material_override = Materials.toon()
		node.add_child(mmi)
	# noms des monuments
	for lb in labels:
		var l3 := Label3D.new(); l3.text = lb[2]
		l3.font_size = 72; l3.pixel_size = 0.03; l3.outline_size = 14
		l3.billboard = BaseMaterial3D.BILLBOARD_ENABLED; l3.no_depth_test = false
		l3.modulate = Color(1, 0.96, 0.85)
		l3.position = Vector3(lb[1].x, 34.0, lb[1].y)
		l3.visibility_range_end = 700.0
		node.add_child(l3)
	stats.tiles += 1
	return node

# ----------------------------------------------------------------------------------------------- bâtiments

const STONE := Color("#ddd3c0")
const SLATE := Color("#4c5562")
const ZINC := Color("#7e8a95")
const GLASS_SHOP := 0.45     # alpha des vitrines (éclairées la nuit)
const SOLID_A := 0.35        # alpha sans fenêtres

func _wall_a(seed: int) -> float:
	return 0.5 + 0.49 * float(absi(seed * 2654435761) % 1000) / 1000.0

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
		var sh := 0.9 + 0.1 * float(i % 2)
		S.tri(Vector3(a.x, y, a.y), Vector3(b.x, y, b.y), apex, Color(col.r * sh, col.g * sh, col.b * sh, SOLID_A), -1.0)

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
		if h > 12.0 and n <= 12:
			_walls(S, ring, h, h + 0.6, Color(roof.r * 1.1, roof.g * 1.1, roof.b * 1.1, SOLID_A), false)
		if h > 15.0 and rng.randf() < 0.6:  # édicule technique
			S.box(Vector3(c.x, h + 1.2, c.y), Vector3(3.0, 2.4, 3.0), Color("#b3b0a8", SOLID_A))

func _point(S: _Arrays, kind: int, h: float, p: Vector2) -> void:
	match kind:
		1: _tower(S, p, 6.0, h * 0.62, h * 0.38, STONE, SLATE)
		2: _tower(S, p, 5.0, h, 0.0, STONE, SLATE)
		3: _round_tower(S, p, 2.5, h, Color("#f2f2f2"), Color("#c0392b"), true, false)
		4: S.cone(Vector3(p.x, 0, p.y), 1.6, h, 8, Color("#9c6a52", SOLID_A))

func _line(S: _Arrays, pts: PackedVector2Array, cls: int, w: float, seed: int) -> void:
	var asphalt := Color("#5b5f66") if cls == L_MAJOR else Color("#63666c")
	match cls:
		L_RAIL:
			_ribbon(S, pts, 3.2, 0.035, Color("#8d8174"))
			for off in [-0.72, 0.72]:
				_ribbon(S, pts, 0.09, 0.12, Color("#b9bcc0"), off)
			return
		L_PATH:
			_ribbon(S, pts, maxf(w, 1.5), 0.04, Color("#d2c3a1")); return
		L_SMALL:
			_ribbon(S, pts, maxf(w, 2.5), 0.045, Color("#9b9385")); return
	# trottoirs + chaussée + marquage central pointillé
	_ribbon(S, pts, w + 3.6, 0.035, Color("#bdb8ae"))
	_ribbon(S, pts, w, 0.055, asphalt)
	if w >= 5.5:
		var acc := 0.0
		for i in range(pts.size() - 1):
			var a := pts[i]; var b := pts[i + 1]
			var len := a.distance_to(b)
			var d := (b - a) / maxf(len, 0.001)
			var s := fposmod(-acc, 9.0)
			while s + 3.0 <= len:
				_ribbon(S, PackedVector2Array([a + d * s, a + d * (s + 3.0)]), 0.15, 0.07, Color("#ecebe6"))
				s += 9.0
			acc += len
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

func _ribbon(S: _Arrays, pts: PackedVector2Array, w: float, y: float, col: Color, offset: float = 0.0) -> void:
	for i in range(pts.size() - 1):
		var a := pts[i]; var b := pts[i + 1]
		var d := (b - a).normalized()
		var nrm := Vector2(-d.y, d.x)
		var a2 := a - d * (w * 0.5) + nrm * offset
		var b2 := b + d * (w * 0.5) + nrm * offset
		var hw := nrm * (w * 0.5)
		S.quad(Vector3(a2.x - hw.x, y, a2.y - hw.y), Vector3(a2.x + hw.x, y, a2.y + hw.y),
			Vector3(b2.x + hw.x, y, b2.y + hw.y), Vector3(b2.x - hw.x, y, b2.y - hw.y), col, -1.0)

## Essences : 0 feuillu rond, 1 conifère, 2 feuillu élancé, 3 pin parasol, 4 palmier, 5 peuplier, 6 platane.
func _pick_tree(rng: RandomNumberGenerator) -> int:
	var mix: Array = style.get("trees", [0, 2, 1])
	return int(mix[rng.randi() % mix.size()])

## Recherche d'un monument nommé (étiquette BD TOPO) : position dans le repère de la ligne, ou Vector3.INF.
func find_label(substr: String) -> Vector3:
	if not v2: return Vector3.INF
	for k in table:
		var o: int = table[k].x
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
	var o: int = table[k].x
	var end: int = table[k].x + table[k].y
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
	var k := Vector2i(floori(c.x / tile_m), floori(c.z / tile_m))
	return buf.decode_u16(table[k].x) if table.has(k) else 0

## Zones interdites au décor (repère ville) : plateformes de tram (axe ± TRACK_KEEP) et quais.
## Arbres, lampadaires, éléments ponctuels et bâtiments n'y sont pas posés.
const TRACK_KEEP := 4.2
var _keepout: TrackView.KeepOut = null
var _tile_origin := Vector2.ZERO
## Rayon de houppier des modèles d'arbres (échelle 1), par essence.
const CROWN_R := [2.6, 2.3, 1.9, 3.4, 3.0, 1.1, 3.6]

func set_tracks(polylines: Array) -> void:
	if _keepout == null: _keepout = TrackView.KeepOut.new()
	var off := Vector2(position.x, position.z)
	for poly in polylines:
		var pl := PackedVector2Array()
		for q in poly: pl.append(q - off)
		_keepout.add_polyline(pl, TRACK_KEEP)

## Segment interdit supplémentaire (repère de la ligne), ex. quai de station.
func add_keepout(a_net: Vector2, b_net: Vector2, clearance: float) -> void:
	if _keepout == null: _keepout = TrackView.KeepOut.new()
	var off := Vector2(position.x, position.z)
	_keepout.add_segment(a_net - off, b_net - off, clearance)

## Vrai si le point (repère ville) est sur une plateforme ou un quai (marge `extra`).
func blocked(p_city: Vector2, extra: float = 0.0) -> bool:
	return _keepout != null and _keepout.blocked(p_city, extra)

func _add_tree(kind: int, pos: Vector3, rng: RandomNumberGenerator, scale: float = 1.0, exact: bool = false) -> void:
	var w := _tile_origin + Vector2(pos.x, pos.z)
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
	_trees_cur[kind].append(Transform3D(b, pos))
	if debug_props: placed_trees.append(w)

static func _tree_mesh(v: int) -> Mesh:
	if _trees.size() == TREE_KINDS:
		return _trees[v]
	_trees.clear()
	for k in TREE_KINDS:
		var A := _Arrays.new()
		var trunk := Color("#6b4f3a", 0.9)
		match k:
			0:  # feuillu rond (tilleul, chêne)
				A.box(Vector3(0, 1.3, 0), Vector3(0.35, 2.6, 0.35), trunk)
				A.cone(Vector3(0, 4.0, 0), 2.6, 1.8, 7, Color("#5d9a42", 0.9)); A.cone(Vector3(0, 4.0, 0), 2.6, -1.8, 7, Color("#4c8538", 0.9))
			1:  # conifère
				A.box(Vector3(0, 1.0, 0), Vector3(0.35, 2.0, 0.35), trunk)
				A.cone(Vector3(0, 1.6, 0), 2.3, 3.6, 6, Color("#2f6e46", 0.9)); A.cone(Vector3(0, 3.8, 0), 1.6, 3.2, 6, Color("#38804f", 0.9))
			2:  # feuillu élancé
				A.box(Vector3(0, 1.6, 0), Vector3(0.3, 3.2, 0.3), trunk)
				A.cone(Vector3(0, 4.4, 0), 1.9, 2.0, 7, Color("#6ea845", 0.9)); A.cone(Vector3(0, 4.4, 0), 1.9, -1.4, 7, Color("#5a9238", 0.9))
				A.cone(Vector3(0, 6.2, 0), 1.3, 1.6, 7, Color("#6ea845", 0.9))
			3:  # pin parasol : tronc haut, houppier plat
				A.box(Vector3(0, 2.6, 0), Vector3(0.4, 5.2, 0.4), Color("#7a5a44", 0.9))
				A.cone(Vector3(0, 5.6, 0), 3.4, 1.0, 8, Color("#3f7a3a", 0.9)); A.cone(Vector3(0, 5.6, 0), 3.4, -0.7, 8, Color("#356a33", 0.9))
			4:  # palmier
				A.cone(Vector3(0, 0, 0), 0.35, 7.5, 6, Color("#8b7355", 0.9))
				for i in 7:
					var ang := TAU * i / 7.0
					var d := Vector3(cos(ang), 0, sin(ang))
					A.tri(Vector3(0, 7.3, 0), Vector3(0, 7.3, 0) + d * 3.0 + Vector3(0, -1.2, 0) + d.cross(Vector3.UP) * 0.6,
						Vector3(0, 7.3, 0) + d * 3.0 + Vector3(0, -1.2, 0) - d.cross(Vector3.UP) * 0.6, Color("#4f8f3c", 0.9))
			5:  # peuplier : colonne
				A.box(Vector3(0, 0.8, 0), Vector3(0.3, 1.6, 0.3), trunk)
				A.cone(Vector3(0, 1.4, 0), 1.1, 9.0, 6, Color("#6c9e3c", 0.9))
			6:  # platane : grand houppier clair, tronc tacheté
				A.box(Vector3(0, 1.8, 0), Vector3(0.5, 3.6, 0.5), Color("#a39a7f", 0.9))
				A.cone(Vector3(0, 5.6, 0), 3.6, 2.4, 8, Color("#7fb04f", 0.9)); A.cone(Vector3(0, 5.6, 0), 3.6, -2.0, 8, Color("#6b9a41", 0.9))
		_trees.append(A.mesh())
	return _trees[v]

## Accumulateur de triangles (sommets, couleurs, UV). UV.y < 0 : pas de fenêtres.
class _Arrays:
	var v := PackedVector3Array()
	var c := PackedColorArray()
	var uv := PackedVector2Array()

	func count() -> int:
		return v.size()

	func tri(a: Vector3, b: Vector3, d: Vector3, col: Color, _u: float = -1.0) -> void:
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
			var shade := 0.88 + 0.12 * float(i % 2)
			tri(base + Vector3(cos(a0) * r, 0, sin(a0) * r), base + Vector3(cos(a1) * r, 0, sin(a1) * r), tip,
				Color(col.r * shade, col.g * shade, col.b * shade, col.a))

	func mesh() -> ArrayMesh:
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = v
		arr[Mesh.ARRAY_COLOR] = c
		arr[Mesh.ARRAY_TEX_UV] = uv
		var m := ArrayMesh.new()
		if v.size() > 0:
			m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		return m
