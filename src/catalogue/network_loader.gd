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
		graph.add_edge(e.id, e.from, e.to, float(e.length))
		var lim := float(e.get("limit_kmh", 50)) / 3.6
		if e.has("curve_radius"):
			lim = minf(lim, TrainPhysics.curve_speed_limit(float(e.curve_radius)))
		var sup := str(e.get("supply", data.get("supply", "overhead")))
		if not sup in supplies:
			supplies.append(sup)
		edge_info[e.id] = {"limit_ms": lim, "grade": float(e.get("grade", 0.0)), "supply": sup}
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
