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

static func path_for(c: String) -> String:
	return "res://data/scenes/%s.bin" % c

static func available(c: String) -> bool:
	return c != "" and FileAccess.file_exists(path_for(c))

## Ouvre la scène d'une ville et la cale sur le repère de la ligne (origine lat/lon de la ligne).
func open(c: String, net_origin: Array) -> bool:
	city = c
	buf = FileAccess.get_file_as_bytes(path_for(c))
	if buf.size() < 8 or buf.slice(0, 4).get_string_from_ascii() != "TSC1":
		return false
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
	return true

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
	var trees: Array = [[], [], []]
	var seed := hash(k)
	# sol urbain de la tuile
	S.quad(Vector3(0, 0, 0), Vector3(tile_m, 0, 0), Vector3(tile_m, 0, tile_m), Vector3(0, 0, tile_m), Color.from_string(str(style.get("ground", "#cfcac0")), Color.GRAY), -1.0)
	# --- bâtiments
	var nb := buf.decode_u16(o); o += 2
	for b in nb:
		var n := buf.decode_u8(o); var cls := buf.decode_u8(o + 1); var h := buf.decode_u16(o + 2) * 0.1; o += 4
		var ring := PackedVector2Array(); ring.resize(n)
		for i in n:
			ring[i] = Vector2(buf.decode_s16(o) * 0.1, buf.decode_s16(o + 2) * 0.1); o += 4
		var nt := buf.decode_u8(o); o += 1
		var idx := buf.slice(o, o + nt * 3); o += nt * 3
		_building(S, ring, idx, cls, h, seed + b)
	stats.buildings += nb
	# --- surfaces
	var np := buf.decode_u16(o); o += 2
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
				if cls == P_FOREST or cls == P_GRASS or cls == P_CEMETERY:
					var area := absf((b - a).cross(c - a)) * 0.5
					var dens := 110.0 if cls == P_FOREST else 700.0
					var count := mini(int(area / dens + rng.randf()), 40)
					for i in count:
						var r1 := sqrt(rng.randf()); var r2 := rng.randf()
						var q := a * (1.0 - r1) + b * (r1 * (1.0 - r2)) + c * (r1 * r2)
						trees[rng.randi() % 3].append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.8, 1.35)), Vector3(q.x, y, q.y)))
	# --- lignes (routes, voies ferrées)
	var nl := buf.decode_u16(o); o += 2
	for l in nl:
		var cls := buf.decode_u8(o); var w := buf.decode_u8(o + 1) / 5.0; var n := buf.decode_u16(o + 2); o += 4
		var pts := PackedVector2Array(); pts.resize(n)
		for i in n:
			pts[i] = Vector2(buf.decode_s16(o) * 0.1, buf.decode_s16(o + 2) * 0.1); o += 4
		_line(S, pts, cls, w, seed + l)
	# --- maillages
	var mi := MeshInstance3D.new(); mi.mesh = S.mesh(); mi.material_override = Materials.building()
	node.add_child(mi)
	if W.count() > 0:
		var wi := MeshInstance3D.new(); wi.mesh = W.mesh(); wi.material_override = Materials.water()
		node.add_child(wi)
	for v in 3:
		if trees[v].is_empty(): continue
		var mm := MultiMesh.new(); mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _tree_mesh(v); mm.instance_count = trees[v].size()
		for i in trees[v].size(): mm.set_instance_transform(i, trees[v][i])
		var mmi := MultiMeshInstance3D.new(); mmi.multimesh = mm; mmi.material_override = Materials.toon()
		node.add_child(mmi)
	stats.tiles += 1
	return node

func _building(S: _Arrays, ring: PackedVector2Array, idx: PackedByteArray, cls: int, h: float, seed: int) -> void:
	var n := ring.size()
	var wall: Color
	match cls:
		2: wall = Color("#c7c3ba").lerp(Color("#a9b0b5"), (seed % 7) / 7.0)
		3: wall = Color("#e9e3d3")
		4: wall = Color("#eee6d2")
		5: wall = Color("#b9b6ae")
		_: wall = _pal("walls", seed)
	var has_windows := cls == 0 or cls == 1 or cls == 4
	wall.a = (0.5 + 0.49 * float(absi(seed * 2654435761) % 1000) / 1000.0) if has_windows else 0.4
	var u := 0.0
	for i in n:
		var a := ring[i]; var b := ring[(i + 1) % n]
		var len := a.distance_to(b)
		S.wall(Vector3(a.x, 0, a.y), Vector3(b.x, 0, b.y), h, wall, u, u + len)
		u += len
	# toit : pyramide basse pour les petites maisons, sinon toit plat
	var area := 0.0
	var cen := Vector2.ZERO
	for i in n:
		area += ring[i].cross(ring[(i + 1) % n]) * 0.5
		cen += ring[i]
	cen /= n
	area = absf(area)
	if cls == 0 and h <= 11.0 and n <= 8 and area < 260.0:
		var roof := Color.from_string(str(style.get("pitched", "#a65e44")), Color.BROWN)
		var apex := Vector3(cen.x, h + clampf(sqrt(area) * 0.32, 1.2, 3.5), cen.y)
		for i in n:
			var a := ring[i]; var b := ring[(i + 1) % n]
			var shade := 0.92 + 0.08 * float(i % 2)
			S.tri(Vector3(a.x, h, a.y), Vector3(b.x, h, b.y), apex, Color(roof.r * shade, roof.g * shade, roof.b * shade, 0.4), -1.0)
	else:
		var roof := _pal("roofs", seed / 7)
		roof.a = 0.4
		for t in range(0, idx.size(), 3):
			var a := ring[idx[t]]; var b := ring[idx[t + 1]]; var c := ring[idx[t + 2]]
			S.tri(Vector3(a.x, h, a.y), Vector3(b.x, h, b.y), Vector3(c.x, h, c.y), roof, -1.0)
		# acrotère pour les toits plats élevés
		if h > 12.0 and n <= 12:
			for i in n:
				var a := ring[i]; var b := ring[(i + 1) % n]
				S.wall(Vector3(a.x, h, a.y), Vector3(b.x, h, b.y), 0.6, Color(roof.r * 1.1, roof.g * 1.1, roof.b * 1.1, 0.4), 0.0, 0.0)

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
				S.box(Vector3(p.x, 3.0, p.y), Vector3(0.18, 6.0, 0.18), Color("#4a4d52", 0.4))
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

## Arbres low poly : 3 variantes (feuillu rond, conifère, feuillu haut).
static func _tree_mesh(v: int) -> Mesh:
	if _trees.size() == 3:
		return _trees[v]
	_trees.clear()
	for k in 3:
		var A := _Arrays.new()
		var trunk := Color("#6b4f3a", 0.9)
		A.box(Vector3(0, 1.2, 0), Vector3(0.35, 2.4, 0.35), trunk)
		var greens := [Color("#4f8f3c", 0.9), Color("#2f6e46", 0.9), Color("#679f3f", 0.9)]
		var g: Color = greens[k]
		if k == 1:  # conifère : deux cônes à 6 pans
			A.cone(Vector3(0, 1.8, 0), 2.4, 3.6, 6, g)
			A.cone(Vector3(0, 4.0, 0), 1.7, 3.0, 6, g.lightened(0.08))
		else:  # feuillu : bipyramide facettée
			var r := 2.4 if k == 0 else 1.8
			var y0 := 2.2 if k == 0 else 2.6
			A.cone(Vector3(0, y0 + 1.6, 0), r, 1.6, 7, g.lightened(0.06))
			A.cone(Vector3(0, y0 + 1.6, 0), r, -1.6, 7, g.darkened(0.1))
			if k == 2:
				A.cone(Vector3(0, y0 + 3.6, 0), r * 0.75, 1.8, 7, g)
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
