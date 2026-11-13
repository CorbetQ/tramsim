class_name NetworkRegistry
extends RefCounted
## Catalogue des réseaux livrés. Lit res://data/index.json (généré par tools/import/build_index.py),
## sinon parcourt res://data/networks.

const INDEX := "res://data/index.json"

## Retourne [{city, line, long_name, path, kind, guidance, ...}] trié par ville.
static func entries() -> Array:
	var f := FileAccess.open(INDEX, FileAccess.READ)
	if f != null:
		var d = JSON.parse_string(f.get_as_text())
		if typeof(d) == TYPE_DICTIONARY and d.has("networks"):
			var result: Array = d.networks.duplicate()
			var extra := "res://data/catalogue/free_lines.json"
			if FileAccess.file_exists(extra):
				var free_lines: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(extra))
				result.append_array(free_lines.get("networks", []))
			return result
	var out: Array = []
	for name in DirAccess.get_files_at("res://data/networks"):
		if not name.ends_with(".json"): continue
		var n := NetworkLoader.new()
		if n.load_file("res://data/networks/" + name).is_empty():
			out.append({"city": n.meta.get("city", "?"), "line": n.meta.get("line", "?"), "long_name": n.meta.get("long_name", ""),
				"path": "res://data/networks/" + name, "kind": n.meta.get("kind", "tram"), "guidance": n.meta.get("guidance", "steel")})
	return out

static func cities() -> PackedStringArray:
	var c := PackedStringArray()
	for e in entries():
		if not e.city in c: c.append(e.city)
	c.sort()
	return c

## Compatibilité : libellé -> chemin (ancienne API).
static func scan(_dir: String = "") -> Dictionary:
	var out := {}
	for e in entries():
		out["%s — ligne %s" % [e.city, e.line]] = e.path
	return out
