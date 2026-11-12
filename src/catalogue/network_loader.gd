class_name NetworkLoader
extends RefCounted
## Charge un réseau JSON versionné en TrackGraph + métadonnées de voie.

const SCHEMA := 1

var graph := TrackGraph.new()
var meta: Dictionary = {}
var edge_info: Dictionary = {}   # id -> {limit_ms, grade, curve_radius}
var stations: Array[Dictionary] = []
var signals: Array[Dictionary] = []
var supplies: Array = []

## Retourne la liste des erreurs (vide = OK).
func load_file(path: String) -> PackedStringArray:
	graph = TrackGraph.new()
	meta = {}; edge_info.clear(); stations.clear(); signals.clear(); supplies.clear()
	var errs := PackedStringArray()
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return PackedStringArray(["fichier introuvable: " + path])
	var data = JSON.parse_string(f.get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		return PackedStringArray(["JSON invalide: " + path])
	if int(data.get("schema", 0)) != SCHEMA:
		errs.append("schéma non supporté")
	meta = data
	var nodes: Array = data.get("nodes", [])
	for e in data.get("edges", []):
		if not (e.from in nodes and e.to in nodes):
			errs.append("nœud inconnu sur l'arête " + e.id)
		graph.add_edge(e.id, e.from, e.to, float(e.length), int(e.get("from_side", 1)), int(e.get("to_side", -1)))
		var lim := float(e.get("limit_kmh", 50)) / 3.6
		if e.has("curve_radius"):
			lim = minf(lim, TrainPhysics.curve_speed_limit(float(e.curve_radius)))
		var sup := str(e.get("supply", data.get("supply", "overhead")))
		if not sup in supplies:
			supplies.append(sup)
		var zones: Array = []
		for z in e.get("limits", []):
			zones.append([float(z[0]), float(z[1]), float(z[2]) / 3.6])
		var pts: PackedVector2Array = []
		for q in e.get("pts", []):
			pts.append(Vector2(float(q[0]), float(q[1])))
		var arc := PackedFloat64Array([0.0])
		for i in range(1, pts.size()): arc.append(arc[-1] + pts[i - 1].distance_to(pts[i]))
		var ys := PackedFloat32Array()
		for v in e.get("y", []): ys.append(float(v))
		if ys.size() != pts.size(): ys = PackedFloat32Array()
		edge_info[e.id] = {"limit_ms": lim, "zones": zones, "grade": float(e.get("grade", 0.0)), "supply": sup, "pts": pts, "raw": bool(e.get("raw", false)),
			"physical": bool(e.get("physical", false)), "structure_left": bool(e.get("structure_left", true)), "structure_right": bool(e.get("structure_right", true)),
			"gauge_mm": int(e.get("gauge_mm", 1435)), "service": str(e.get("service", "")), "name": str(e.get("name", "")), "source": e.get("source", {}),
			"arc": arc, "ys": ys, "bridge": e.get("bridge", []), "tunnel": e.get("tunnel", []), "trench": e.get("trench", [])}
	for s in data.get("stations", []):
		if not graph.edges.has(s.edge):
			errs.append("station sur arête inconnue: " + s.name)
		elif float(s.offset) > graph.edges[s.edge].length:
			errs.append("station hors arête: " + s.name)
		stations.append(s)
	for s in data.get("signals", []):
		if not graph.edges.has(s.edge):
			errs.append("signal sur arête inconnue")
		signals.append(s.duplicate())
	errs.append_array(graph.validate())
	return errs

## Limite (m/s) en un point : limite de l'arête, réduite par les zones de courbe.
func limit_at(edge_id: String, offset: float) -> float:
	var info: Dictionary = edge_info[edge_id]
	var v: float = info.limit_ms
	for z in info.zones:
		if offset >= z[0] and offset <= z[1]:
			v = minf(v, z[2])
	return v

## Missions horaires décrites dans le fichier réseau (issues du GTFS).
func missions() -> Array:
	return meta.get("missions", [])

func has_geometry() -> bool:
	for id in edge_info:
		if edge_info[id].pts.size() >= 2:
			return true
	return false

## Position (x, z en mètres) et cap le long de la polyligne de l'arête.
func point_on(edge_id: String, offset: float) -> Dictionary:
	var pts: PackedVector2Array = edge_info[edge_id].pts
	var L: float = graph.edges[edge_id].length
	if pts.size() < 2:
		return {"p": pts[0] if pts.size() > 0 else Vector2.ZERO, "dir": Vector2.RIGHT, "y": 0.0, "grade": 0.0}
	var arc: PackedFloat64Array = edge_info[edge_id].arc
	var total: float = arc[-1]
	var s := clampf(offset, 0.0, L) * (total / L if L > 0.0 else 1.0)
	var i := clampi(arc.bsearch(s) - 1, 0, pts.size() - 2)
	var seg: float = arc[i + 1] - arc[i]
	var u := 0.0 if seg < 0.00001 else clampf((s - arc[i]) / seg, 0.0, 1.0)
	var dir := (pts[i + 1] - pts[i]).normalized()
	var ys: PackedFloat32Array = edge_info[edge_id].get("ys", PackedFloat32Array())
	var y := 0.0; var g := 0.0
	if ys.size() == pts.size():
		y = lerpf(ys[i], ys[i + 1], u)
		g = (ys[i + 1] - ys[i]) / seg if seg > 0.01 else 0.0
	return {"p": pts[i].lerp(pts[i + 1], u), "dir": dir, "y": y, "grade": g}

## Pente locale (+ = montée dans le sens de l'arête), moyennée sur ~20 m ; pente moyenne de l'arête sans profil.
func grade_at(edge_id: String, offset: float) -> float:
	var info: Dictionary = edge_info[edge_id]
	if (info.get("ys", PackedFloat32Array()) as PackedFloat32Array).size() < 2: return float(info.get("grade", 0.0))
	var L: float = graph.edges[edge_id].length
	var a := clampf(offset - 10.0, 0.0, L); var b := clampf(offset + 10.0, 0.0, L)
	if b - a < 1.0: return float(point_on(edge_id, offset).grade)
	return (float(point_on(edge_id, b).y) - float(point_on(edge_id, a).y)) / (b - a)

## Altitude de l'axe de la voie (m, relative à "alt0" du réseau).
func height_at(edge_id: String, offset: float) -> float:
	return float(point_on(edge_id, offset).y)

## Vrai si l'abscisse est dans un des intervalles [s0, s1, ...] de la liste.
static func in_spans(spans: Array, offset: float) -> bool:
	for sp in spans:
		if offset >= float(sp[0]) and offset <= float(sp[1]): return true
	return false
