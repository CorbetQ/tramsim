class_name SaveResume
extends RefCounted
## Adaptateur de checkpoint. Aucun graphe n'est corrigé ou réécrit.
const EARTH_M := 6371008.8
const MAX_REMAP_M := 12.0

static func checkpoint(s: FreeSession, network: String, vehicle: String) -> Dictionary:
	var edge: String = s.checkpoint_edge
	var q := s.net.point_on(edge, s.checkpoint_offset)
	var origin: Array = s.net.meta.get("origin", [])
	var out := {"network": network, "network_id": s.net.meta.get("id", ""), "vehicle": vehicle,
		"edge": edge, "offset": s.checkpoint_offset, "direction": s.checkpoint_dir, "traffic": s.traffic.enabled,
		"heading": [q.dir.x * s.checkpoint_dir, q.dir.y * s.checkpoint_dir], "edge_fingerprint": edge_fingerprint(s.net, edge), "source": s.net.edge_info[edge].get("source", {}).duplicate(true)}
	if origin.size() == 2:
		out.anchor = {"lat": float(origin[0]) - rad_to_deg(q.p.y / EARTH_M),
			"lon": float(origin[1]) + rad_to_deg(q.p.x / (EARTH_M * cos(deg_to_rad(float(origin[0])))))}
	return out

static func edge_fingerprint(net: NetworkLoader, edge: String) -> String:
	var info: Dictionary = net.edge_info[edge]
	return JSON.stringify({"pts": Array(info.pts), "source": info.get("source", {})}).sha256_text()

static func network_path(run: Dictionary, aliases: Dictionary = {}) -> String:
	var path := str(run.get("net_path", ""))
	if FileAccess.file_exists(path): return path
	if aliases.is_empty() and FileAccess.file_exists("res://data/save_aliases.json"):
		var config: Variant = CityDataStore.document("res://data/save_aliases.json")
		if config is Dictionary: aliases = config.get("networks", {})
	var declared := str(aliases.get(path, ""))
	if declared.begins_with("res://data/") and FileAccess.file_exists(declared): return declared
	var wanted := str(run.get("network_id", ""))
	if wanted.is_empty(): return ""
	for entry in NetworkRegistry.entries():
		if str(entry.get("id", "")) == wanted and FileAccess.file_exists(str(entry.path)): return str(entry.path)
	# Graphes libres hors de l'index commercial, ID stable conservé au checkpoint.
	for filename in DirAccess.get_files_at("res://data/free"):
		if not filename.ends_with(".json"): continue
		var candidate := "res://data/free/" + filename
		var doc: Variant = CityDataStore.document(candidate)
		if doc is Dictionary and str(doc.get("id", "")) == wanted: return candidate
	return ""

static func resolve(saved: Dictionary, net: NetworkLoader, path: String, max_distance: float = MAX_REMAP_M) -> Dictionary:
	if saved.is_empty(): return {"ok": false, "status": "empty"}
	var aliases: Dictionary = net.meta.get("save_aliases", {})
	var same_id := not str(saved.get("network_id", "")).is_empty() and str(saved.network_id) == str(net.meta.get("id", ""))
	if str(saved.get("network", "")) != path and not same_id and not str(saved.get("network", "")) in aliases.get("networks", []):
		return {"ok": false, "status": "different_network"}
	var edge := str(saved.get("edge", ""))
	var offset := float(saved.get("offset", -1))
	if not is_finite(offset) or offset < 0: return {"ok": false, "status": "invalid_offset"}
	var direction := int(saved.get("direction", 1))
	if direction not in [-1, 1]: return {"ok": false, "status": "invalid_direction"}
	if net.edge_info.has(edge) and offset <= float(net.graph.edges[edge].length):
		if not saved.has("edge_fingerprint") or str(saved.edge_fingerprint) == edge_fingerprint(net, edge):
			return _resolved(edge, offset, direction, "unchanged")
	var explicit: Variant = aliases.get("edges", {}).get(edge)
	if explicit is Dictionary:
		var target := str(explicit.get("edge", ""))
		var new_offset := offset * float(explicit.get("scale", 1)) + float(explicit.get("shift_m", 0))
		if int(explicit.get("direction", 1)) in [-1, 1] and net.graph.edges.has(target) and is_finite(new_offset) and new_offset >= 0 and new_offset <= float(net.graph.edges[target].length):
			return _resolved(target, new_offset, direction * int(explicit.get("direction", 1)), "explicit_alias")
	var anchor: Variant = saved.get("anchor")
	var origin: Array = net.meta.get("origin", [])
	if not anchor is Dictionary or not origin.size() == 2: return {"ok": false, "status": "unresolved", "message": "Checkpoint conservé : arête absente, sans ancre vérifiable."}
	if not _number(anchor.get("lat")) or not _number(anchor.get("lon")): return {"ok": false, "status": "invalid_anchor"}
	var point := Vector2(deg_to_rad(float(anchor.lon) - float(origin[1])) * EARTH_M * cos(deg_to_rad(float(origin[0]))), -deg_to_rad(float(anchor.lat) - float(origin[0])) * EARTH_M)
	var candidates: Array = []
	var source_way := str(saved.get("source", {}).get("way", ""))
	for id in net.edge_info:
		var info: Dictionary = net.edge_info[id]
		var pts: PackedVector2Array = info.pts
		for i in range(1, pts.size()):
			var delta := pts[i] - pts[i - 1]
			var t := clampf((point - pts[i - 1]).dot(delta) / maxf(delta.length_squared(), 0.000001), 0, 1)
			var distance := point.distance_to(pts[i - 1] + delta * t)
			if distance <= max_distance:
				var same_source := not source_way.is_empty() and str(info.get("source", {}).get("way", "")) == source_way
				candidates.append({"edge": str(id), "offset": float(info.arc[i - 1]) + delta.length() * t, "distance": distance, "same_source": same_source, "tangent": delta.normalized()})
	if candidates.is_empty(): return {"ok": false, "status": "too_far", "message": "Checkpoint conservé : voie trop éloignée de l'ancre."}
	candidates.sort_custom(func(a, b):
		if a.same_source != b.same_source: return a.same_source
		if not is_equal_approx(a.distance, b.distance): return a.distance < b.distance
		return str(a.edge) < str(b.edge))
	var best: Dictionary = candidates[0]
	for other in candidates.slice(1):
		if other.edge != best.edge and other.same_source == best.same_source and absf(float(other.distance) - float(best.distance)) < 1.0:
			return {"ok": false, "status": "ambiguous", "message": "Plusieurs voies possibles ; checkpoint conservé, choix de départ requis."}
	var heading: Variant = saved.get("heading", [])
	if heading is Array and heading.size() == 2 and _number(heading[0]) and _number(heading[1]):
		var forward := Vector2(float(heading[0]), float(heading[1]))
		if forward.length() > 0.1: direction = 1 if forward.dot(best.tangent) >= 0 else -1
	var resolved := _resolved(best.edge, best.offset, direction, "geographic_anchor")
	resolved.distance_m = best.distance
	return resolved

static func _resolved(edge: String, offset: float, direction: int, status: String) -> Dictionary:
	return {"ok": true, "status": status, "station": {"edge": edge, "offset": offset, "direction": direction, "name": "reprise", "restored": true}}

static func _number(v: Variant) -> bool:
	return (v is float or v is int) and is_finite(float(v))
