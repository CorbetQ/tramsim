class_name StationLayout
extends RefCounted
## Implantation des stations (data/stations/<ville>.json, tools/import/stations.py) : type (quais latéraux face à face,
## quai central, quais décalés, station multi-quais), côté d'ouverture des portes, quais qui suivent la courbure de la
## voie (polyligne décalée), jamais sur une voie (distance minimale au rail), longueur adaptée à la rame la plus longue.

const GAP := 1.45          # m : axe de la voie -> bord du quai (rame de 2,40 à 2,65 m)
const LAT_W := 3.0         # largeur d'un quai latéral
const ISLAND_W := 3.8      # largeur d'un quai central (entraxe élargi en conséquence)
const STEP := 2.5          # m : pas d'échantillonnage le long de la voie
const HEIGHT := 0.30       # hauteur du quai au-dessus du rail
const DOOR_SIDES := {"lateral": "right", "offset": "right", "central": "left", "multi": "both"}

var view                   # LineView (pos3, lateral, net)
var groups: Array = []     # {key, type, doors, pos: Vector2 repère réseau}
var platform_m := 0.0
var infos: Array = []      # par station du réseau : {type, doors}
var platforms: Array = []  # {station, side ("right"/"left"), inner, outer, center (voie) : PackedVector3Array}
var _tracks: TrackView.KeepOut

static func norm(s: String) -> String:
	var t := s.to_lower()
	for p in [["é", "e"], ["è", "e"], ["ê", "e"], ["ë", "e"], ["à", "a"], ["â", "a"], ["î", "i"], ["ï", "i"], ["ô", "o"], ["ö", "o"],
			["ù", "u"], ["û", "u"], ["ü", "u"], ["ç", "c"], ["œ", "oe"], ["–", " "], ["-", " "], ["'", " "], ["’", " "], [",", " "], [".", " "]]:
		t = t.replace(p[0], p[1])
	while t.contains("  "): t = t.replace("  ", " ")
	return t.strip_edges()

func _init(v) -> void:
	view = v

## Types de stations de la ville (repère du réseau : origine net.meta.origin).
func load_city(city: String, origin: Array) -> void:
	var path := "res://data/stations/%s.json" % city
	if city == "" or not FileAccess.file_exists(path): return
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(d) != TYPE_DICTIONARY: return
	platform_m = float(d.get("platform_m", 0.0))
	var lat0 := float(origin[0]); var lon0 := float(origin[1])
	for s in d.get("stations", []):
		var p := Vector2(deg_to_rad(float(s.lon) - lon0) * CityScene.R * cos(deg_to_rad(lat0)), -deg_to_rad(float(s.lat) - lat0) * CityScene.R)
		groups.append({"key": norm(str(s.name)), "type": str(s.type), "doors": str(s.doors), "pos": p})

## Type et côté des portes (par rapport au sens de l'arête) d'une station du réseau.
func info_for(s: Dictionary, p: Vector3) -> Dictionary:
	var k := norm(str(s.name))
	var best: Dictionary = {}; var bd := 400.0
	for g in groups:
		if g.key == k:
			var d: float = (g.pos as Vector2).distance_to(Vector2(p.x, p.z))
			if d < bd: bd = d; best = g
	var result := {"type": "lateral", "doors": "right"} if best.is_empty() else {"type": best.type, "doors": best.doors}
	# Les empreintes OSM déterminent le côté réel, sans élargir ni déplacer les rails.
	var closest := 14.0; var right: Vector3 = view._frame(s.edge, float(s.offset)).basis.x
	for platform in view.net.meta.get("platforms", []):
		if str(platform.get("name", "")) != "" and norm(str(platform.name)) != k: continue
		var points: Array = platform.pts
		for i in points.size():
			var a := Vector2(points[i][0], points[i][1]); var b := Vector2(points[(i + 1) % points.size()][0], points[(i + 1) % points.size()][1])
			var q := Geometry2D.get_closest_point_to_segment(Vector2(p.x, p.z), a, b)
			var distance_ := q.distance_to(Vector2(p.x, p.z))
			if distance_ < closest:
				closest = distance_
				result.doors = "right" if Vector3(q.x - p.x, 0, q.y - p.z).dot(right) > 0.0 else "left"
	return result

# ------------------------------------------------------------------------------------------- parcours de voie

## Arête précédente (même voie) : prédécesseur non « raw » le mieux aligné.
func _pred(id: String) -> String:
	var net: NetworkLoader = view.net
	var e: TrackGraph.Edge = net.graph.edges[id]
	var d0: Vector2 = net.point_on(id, 0.0).dir
	var best := ""; var bc := -2.0
	for k in net.graph.edges:
		var f: TrackGraph.Edge = net.graph.edges[k]
		if f.to_node != e.from_node or net.edge_info[k].raw or k == id: continue
		var c: float = (net.point_on(k, f.length).dir as Vector2).dot(d0)
		if c > bc: bc = c; best = k
	return best if bc > 0.5 else ""

func _succ(id: String) -> String:
	var net: NetworkLoader = view.net
	var e: TrackGraph.Edge = net.graph.edges[id]
	var d1: Vector2 = net.point_on(id, e.length).dir
	var best := ""; var bc := -2.0
	for k in net.graph.out_edges.get(e.to_node, []):
		if net.edge_info[k].raw or k == id or str(k).ends_with("_appr"): continue
		var c: float = (net.point_on(k, 0.0).dir as Vector2).dot(d1)
		if c > bc: bc = c; best = k
	return best if bc > 0.5 else ""

## Intervalle [nez + avant, nez - arrière] le long de la voie (franchit les nœuds) : morceaux [arête, o_bas, o_haut, d_haut]
## avec d = distance depuis le début de l'intervalle (côté avant), croissante vers l'arrière.
func span(edge: String, nose: float, ahead: float, behind: float) -> Array:
	var net: NetworkLoader = view.net
	var e := edge; var start := nose + ahead
	while start > net.graph.edges[e].length + 0.01:
		var n := _succ(e)
		if n == "": start = net.graph.edges[e].length; break
		start -= net.graph.edges[e].length; e = n
	var out: Array = []
	var left := ahead + behind; var d := 0.0
	var hi := start
	while left > 0.01:
		var lo := maxf(0.0, hi - left)
		out.append([e, lo, hi, d])
		d += hi - lo; left -= hi - lo
		if left <= 0.01: break
		var p := _pred(e)
		if p == "": break
		e = p; hi = net.graph.edges[e].length
	return out

# ------------------------------------------------------------------------------------------- implantation

## Types, élargissements d'entraxe (quais centraux) puis géométrie des quais.
func build(stations: Array, vehicle_len: float) -> void:
	var L := maxf(platform_m, vehicle_len + 3.0)
	platform_m = L
	infos.clear()
	for s in stations:
		var p: Vector3 = view.pos3(s.edge, float(s.offset))
		infos.append(info_for(s, p))
	# quais centraux : voie déportée de (ISLAND_W / 2 + GAP) - demi-entraxe, transitions progressives
	var extra: float = ISLAND_W * 0.5 + GAP - LineView.TRACK_OFFSET
	for i in stations.size():
		var t: String = infos[i].type
		if view.net.meta.get("geometry_kind", "") == "physical": continue
		if t != "central" and t != "multi": continue
		var s: Dictionary = stations[i]
		var R: float = LineView.WIDEN_RAMP
		for piece in span(s.edge, float(s.offset), 1.5 + R, L - 1.5 + R):
			if not view.widen.has(piece[0]): view.widen[piece[0]] = []
			view.widen[piece[0]].append([piece[1], piece[2], extra, piece[3], R, L])
	# voies rendues (centre de chaque voie, entraxe élargi compris) : zone interdite aux quais
	_tracks = TrackView.KeepOut.new()
	var net: NetworkLoader = view.net
	for id in net.graph.edges:
		var Le: float = net.graph.edges[id].length
		var n := maxi(2, ceili(Le / 4.0) + 1)
		var prev: Vector3 = view.pos3(id, 0.0)
		for k in range(1, n):
			var q: Vector3 = view.pos3(id, Le * k / (n - 1))
			_tracks.add_segment(Vector2(prev.x, prev.z), Vector2(q.x, q.z), GAP - 0.08)
			prev = q
	platforms.clear()
	for i in stations.size():
		var t: String = infos[i].type
		var station_pos: Vector3 = view.pos3(stations[i].edge, float(stations[i].offset))
		var real_platform := false
		for platform in view.net.meta.get("platforms", []):
			for p in platform.pts:
				if Vector2(float(p[0]), float(p[1])).distance_to(Vector2(station_pos.x, station_pos.z)) < L:
					real_platform = true; break
			if real_platform: break
		if real_platform or view.net.meta.has("platform_source"): continue # pas de quai fictif hors empreinte OSM
		if t == "lateral" or t == "offset" or t == "multi": _platform(i, stations[i], "right", L)
		if t == "central" or t == "multi": _platform(i, stations[i], "left", L)

## Quai d'un côté de la voie : bord intérieur à GAP du centre de la voie, sections bloquées par une autre voie omises.
func _platform(i: int, s: Dictionary, side: String, L: float) -> void:
	var sg := 1.0 if side == "right" else -1.0
	if view.net.meta.get("geometry_kind", "") == "physical": sg *= float(s.get("direction", 1))
	var inner := PackedVector3Array(); var outer := PackedVector3Array(); var center := PackedVector3Array()
	var flush := func() -> void:
		if inner.size() >= 4:
			platforms.append({"station": i, "side": side, "inner": inner.duplicate(), "outer": outer.duplicate(), "center": center.duplicate()})
		inner.clear(); outer.clear(); center.clear()
	for piece in span(s.edge, float(s.offset), 1.5, L - 1.5):
		var a: float = piece[1]; var b: float = piece[2]
		var n := maxi(1, ceili((b - a) / STEP))
		for k in range(n + 1):
			if k == 0 and not inner.is_empty(): continue
			var off := b - (b - a) * k / n
			var f: Transform3D = view._frame(piece[0], off)
			var w: float = LAT_W if side == "right" else (ISLAND_W if view.net.meta.get("geometry_kind", "") == "physical" else view.lateral(piece[0], off) - GAP)
			var pi: Vector3 = f.origin + f.basis.x * (sg * GAP)
			var po: Vector3 = f.origin + f.basis.x * (sg * (GAP + w))
			var pm := (pi + po) * 0.5
			var ok := w > 0.6
			for q in [pi + f.basis.x * sg * 0.1, pm, po]:
				if ok and _tracks.blocked(Vector2(q.x, q.z)): ok = false
			if ok:
				inner.append(pi); outer.append(po); center.append(f.origin)
			else:
				flush.call()
	flush.call()

## Côté d'ouverture des portes à la station la plus proche du point d'arrêt (sens de l'arête), "right" par défaut.
func doors_at(stations: Array, edge: String, offset: float) -> String:
	for i in stations.size():
		var s: Dictionary = stations[i]
		if i < infos.size() and (view.net.station_contains(s, edge, offset) or (not s.has("stop_area") and s.edge == edge and absf(float(s.offset) - offset) < 25.0)):
			return infos[i].doors
	return "right"
