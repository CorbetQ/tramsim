class_name FreeStartCatalog
extends RefCounted
## Le choix de ligne filtre le départ, le réseau physique complet reste accessible en conduite.
static func lines(entries: Array, net: NetworkLoader) -> Array:
	var result: Array = []; var seen := {}
	for entry in entries:
		var line := str(entry.line)
		if seen.has(line): continue
		seen[line] = true
		result.append({"line": line, "kind": str(entry.get("kind", "tram")), "label": line + (" · Tram-train — " + str(entry.get("long_name", "")) if entry.get("kind") == "tram-train" else ""), "depot": false})
	if not net.meta.get("depots", []).is_empty(): result.append({"line": "depots", "kind": "depot", "label": "Dépôts", "depot": true})
	return result

static func stops(net: NetworkLoader, line: Dictionary) -> Array:
	if line.get("depot", false): return net.meta.get("depots", []).duplicate()
	var result: Array = []
	for station in net.stations:
		for ref in station.get("lines", []):
			if str(ref).to_lower() == str(line.line).to_lower():
				result.append(station); break
	return result
