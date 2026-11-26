extends SceneTree
## Packs de ville (P4) : écrit build/packs/tramsim-city-<ville>.pck pour chaque ville hors du paquet de base
## (data/packs/base.json) avec PCKPacker : données brutes (data/scenes/<ville>*, data/free/<ville>*), modèles importés
## (assets/models/<ville>/*.import et leurs fichiers .godot/imported) et le manifeste res://data/packs/<ville>.json
## (version du jeu, fichiers, taille). Lancer après un import (godot --headless --import), comme l'export.
## Usage : godot --headless --path . -s tools/packs/build_packs.gd -- [dossier de sortie] [ville ...]
## Les mêmes motifs servent au filtre d'exclusion du preset Android (tools/packs/packs.py filters).
const DATA_DIRS := ["res://data/scenes", "res://data/free"]

static func base_cities() -> Array:
	var d = JSON.parse_string(FileAccess.get_file_as_string(CityPacks.BASE))
	return d.get("cities", []) if d is Dictionary else []

static func all_cities() -> Array:
	var out: Array = []
	for f in DirAccess.get_files_at("res://data/scenes"):
		if f.ends_with(".json") and not "_" in f: out.append(f.get_basename())
	out.sort()
	return out

## Fichiers d'une ville : [chemin res://, chemin disque].
static func city_files(city: String) -> Array:
	var out: Array = []
	for dir in DATA_DIRS:
		for f in DirAccess.get_files_at(dir):
			if f.ends_with(".import"): continue
			if f.get_basename() == city or f.begins_with(city + "_"):
				out.append([dir.path_join(f), ProjectSettings.globalize_path(dir.path_join(f))])
	var md := "res://assets/models/" + city
	if DirAccess.dir_exists_absolute(md):
		for f in DirAccess.get_files_at(md):
			if not f.ends_with(".import"): continue
			var imp := md.path_join(f)
			out.append([imp, ProjectSettings.globalize_path(imp)])
			var cfg := ConfigFile.new()
			if cfg.load(imp) != OK: continue
			for key in cfg.get_section_keys("remap"):
				if key == "path" or key.begins_with("path."):
					var p := str(cfg.get_value("remap", key))
					if FileAccess.file_exists(p): out.append([p, ProjectSettings.globalize_path(p)])
	return out

func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var outdir := a[0] if a.size() > 0 else "res://build/packs"
	outdir = ProjectSettings.globalize_path(outdir)
	DirAccess.make_dir_recursive_absolute(outdir)
	var cities: Array = a.slice(1) if a.size() > 1 else all_cities()
	var base := base_cities()
	var total := 0
	for city in cities:
		if city in base: continue
		var files := city_files(city)
		var size := 0
		var names: Array = []
		for f in files:
			size += FileAccess.get_file_as_bytes(f[1]).size() if f[1].ends_with(".json") else int(FileAccess.open(f[1], FileAccess.READ).get_length())
			names.append(f[0])
		var man := {"city": city, "version": CityPacks.game_version(), "files": names, "bytes": size}
		var tmp := OS.get_cache_dir().path_join("tramsim_pack_%s.json" % city)
		var fw := FileAccess.open(tmp, FileAccess.WRITE); fw.store_string(JSON.stringify(man)); fw.close()
		var pk := PCKPacker.new()
		var path := outdir.path_join(CityPacks.file_name(city))
		if pk.pck_start(path) != OK: printerr("ECHEC pck_start ", path); quit(1); return
		for f in files: pk.add_file(f[0], f[1])
		pk.add_file(CityPacks.MANIFEST % city, tmp)
		pk.flush()
		DirAccess.remove_absolute(tmp)
		var sz := FileAccess.open(path, FileAccess.READ).get_length()
		total += sz
		print("PACK|%s|fichiers=%d|%.1f Mo" % [city, files.size() + 1, sz / 1048576.0])
	print("PACKS|total=%.1f Mo" % (total / 1048576.0))
	quit()
