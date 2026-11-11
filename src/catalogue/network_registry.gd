class_name NetworkRegistry
extends RefCounted
## Découvre les réseaux livrés dans res://data/networks (un JSON par ligne/réseau).

static func scan(dir: String = "res://data/networks") -> Dictionary:
	var out := {}
	for f in DirAccess.get_files_at(dir):
		if not f.ends_with(".json"):
			continue
		var n := NetworkLoader.new()
		if not n.load_file(dir + "/" + f).is_empty():
			push_warning("réseau invalide ignoré: " + f)
			continue
		var label := "%s — ligne %s" % [n.meta.get("city", "?"), n.meta.get("line", "?")]
		if n.meta.get("provisional", false):
			label += " (données provisoires)"
		out[label] = dir + "/" + f
	return out
