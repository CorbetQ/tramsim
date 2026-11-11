class_name SaveGame
extends RefCounted
## Sauvegarde locale JSON : réglages, résultats de missions, dernière partie libre.

const DEFAULT_PATH := "user://save.json"
const VERSION := 1

static func default_data() -> Dictionary:
	return {"version": VERSION, "settings": {"view_distance": 400.0, "traffic": true, "tutorial_done": false},
		"results": [], "free": {}}

static func load_data(path: String = DEFAULT_PATH) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return default_data()
	var d = JSON.parse_string(f.get_as_text())
	if typeof(d) != TYPE_DICTIONARY or int(d.get("version", 0)) != VERSION:
		return default_data()   # fichier corrompu/ancien : repart propre
	var base := default_data()
	base.merge(d, true)
	return base

static func save_data(d: Dictionary, path: String = DEFAULT_PATH) -> bool:
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(d))
	f.close()
	return DirAccess.rename_absolute(tmp, path) == OK   # écriture atomique

static func add_result(d: Dictionary, network: String, vehicle: String, debrief: Dictionary) -> void:
	var stops: Array = []
	for s in debrief.stops:
		stops.append({"name": s.name, "result": int(s.result)})
	d.results.append({"network": network, "vehicle": vehicle, "success": debrief.success,
		"reason": debrief.reason, "time_s": debrief.time_s, "stops": stops})

static func store_free(d: Dictionary, s: FreeSession, network: String, vehicle: String) -> void:
	d.free = {"network": network, "vehicle": vehicle, "edge": s.checkpoint_edge,
		"offset": s.checkpoint_offset, "traffic": s.traffic.enabled}
