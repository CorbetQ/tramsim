extends SceneTree
## Packs de données téléchargeables (docs/SERVEUR_DONNEES.md) : écrit <sortie>/tramsim-city-<ville>-<plateforme>.pck
## pour les 28 villes et tramsim-commun-<nom>-<plateforme>.pck pour les packs communs (data/packs/plan.json), avec
## PCKPacker : sources non importées telles quelles, ressources importées avec leur .import et leurs fichiers
## .godot/imported de la plateforme (mobile : etc2/astc, sans LOD0/4k/PBR 2048² ; pc : s3tc/bptc, tout), et le
## manifeste interne res://data/packs/<id>.json (format, version de données, fichiers). Lancer après un import.
## Usage : godot --headless --path . -s tools/packs/build_packs.gd -- <sortie> [--platform mobile|pc|all]
##         [--data-version V] [pack ...]   (pack : ville « lyon » ou commun « commun-rames »)
## Puis : python3 tools/packs/packs.py manifest <sortie> --data-version V (taille, sha256, URL, dépendances).
const PLAN := "res://data/packs/plan.json"
const STOCK := "res://data/packs/stock.json"
const SCAN_ROOTS := ["res://data/scenes", "res://data/free", "res://assets/models", "res://assets/textures", "res://assets/lightmaps", "res://tram_parts", "res://tram_livery"]

static func plan() -> Dictionary:
	var d = JSON.parse_string(FileAccess.get_file_as_string(PLAN))
	return d if d is Dictionary else {}

static func all_cities() -> Array:
	var out: Array = []
	for f in DirAccess.get_files_at("res://data/scenes"):
		if f.ends_with(".json") and not "_" in f: out.append(f.get_basename())
	out.sort()
	return out

static func common_ids() -> Array:
	return plan().get("commons", {}).keys()

static func _walk(dir: String, out: Array) -> void:
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".import") or f.ends_with(".uid") or f.ends_with(".md"): continue
		out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir): _walk(dir.path_join(d), out)

## Sources exclues des exports (res://…) réparties par pack : {id: [chemins]} ; « » : fichiers sans pack (erreur).
static func assignment() -> Dictionary:
	var p := plan()
	var cities := all_cities()
	var out := {"": []}
	for c in cities: out[c] = []
	for k in p.get("commons", {}): out[k] = []
	var st = JSON.parse_string(FileAccess.get_file_as_string(STOCK)) if FileAccess.file_exists(STOCK) else {}
	var owner := {}
	for c in (st.get("cities", {}) as Dictionary):
		for f in st.cities[c]: owner[str(f)] = str(c)
	var files: Array = []
	for r in SCAN_ROOTS:
		if DirAccess.dir_exists_absolute(r): _walk(r, files)
	for f in files:
		var rel := str(f).trim_prefix("res://")
		var id := ""
		if owner.has(f) and out.has(owner[f]): id = owner[f]
		if id == "" and not rel.begins_with("tram_parts/") and not rel.begins_with("tram_livery/"):
			for c in cities:
				for pat in p.get("city_patterns", []):
					if rel.match(str(pat).replace("{c}", c)): id = c; break
				if id != "": break
		if id == "":
			for k in p.get("commons", {}):
				for pat in p.commons[k].get("patterns", []):
					if rel.match(str(pat)): id = k; break
				if id != "": break
		out[id].append(f)
	return out

static func _mobile_skip(rel: String) -> bool:
	for pat in plan().get("mobile_exclude", []):
		if rel.match(str(pat)): return true
	return false

## Fichiers d'un pack pour une plateforme : [chemin res://, chemin disque].
static func pack_files(sources: Array, platform: String) -> Array:
	var out: Array = []
	var mobile := platform == "mobile"
	for p in sources:
		var src := str(p)
		if mobile and _mobile_skip(src.trim_prefix("res://")): continue
		var imp := src + ".import"
		if not FileAccess.file_exists(imp):
			out.append([src, ProjectSettings.globalize_path(src)])
			continue
		var cfg := ConfigFile.new()
		if cfg.load(imp) != OK or not cfg.has_section("remap"): continue
		var any := false
		for key in cfg.get_section_keys("remap"):
			if not (key == "path" or key.begins_with("path.")): continue
			if key != "path":
				var ok := (key.contains("etc2") or key.contains("astc")) if mobile else (key.contains("s3tc") or key.contains("bptc"))
				if not ok: continue
			var q := str(cfg.get_value("remap", key))
			if FileAccess.file_exists(q): out.append([q, ProjectSettings.globalize_path(q)]); any = true
		if any: out.append([imp, ProjectSettings.globalize_path(imp)])
	return out

## Fichiers du pack d'une ville (compatibilité des tests) : plateforme mobile.
static func city_files(city: String, platform: String = "mobile") -> Array:
	return pack_files(assignment().get(city, []), platform)

static func file_name(id: String, platform: String) -> String:
	return CityPacks.pack_file(id, platform)

## Écrit un pack ; retourne sa taille (octets) ou -1.
static func write_pack(id: String, files: Array, platform: String, _data_version: String, outdir: String) -> int:
	var size := 0
	var names: Array = []
	for f in files:
		var fa := FileAccess.open(f[1], FileAccess.READ)
		if fa != null: size += int(fa.get_length())
		names.append(f[0])
	# pas de version de données ici : un pack au contenu inchangé garde son sha256 (pas de nouveau téléchargement)
	var man := {"id": id, "format": CityPacks.DATA_FORMAT, "platform": platform,
		"files": names, "bytes": size}
	var tmp := OS.get_cache_dir().path_join("tramsim_pack_%s_%s.json" % [id, platform])
	var fw := FileAccess.open(tmp, FileAccess.WRITE); fw.store_string(JSON.stringify(man)); fw.close()
	var path := outdir.path_join(file_name(id, platform))
	var pk := PCKPacker.new()
	if pk.pck_start(path) != OK: printerr("ECHEC pck_start ", path); return -1
	for f in files: pk.add_file(f[0], f[1])
	pk.add_file(CityPacks.MANIFEST % id, tmp)
	pk.flush()
	DirAccess.remove_absolute(tmp)
	return int(FileAccess.open(path, FileAccess.READ).get_length())

func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var outdir := "res://build/packs"
	var platforms := ["mobile", "pc"]
	var data_version := ""
	var wanted: Array = []
	var i := 0
	while i < a.size():
		if a[i] == "--platform": platforms = ["mobile", "pc"] if a[i + 1] == "all" else [a[i + 1]]; i += 2; continue
		if a[i] == "--data-version": data_version = a[i + 1]; i += 2; continue
		if i == 0: outdir = a[i]
		else: wanted.append(a[i])
		i += 1
	outdir = ProjectSettings.globalize_path(outdir)
	DirAccess.make_dir_recursive_absolute(outdir)
	var asg := assignment()
	if not asg[""].is_empty():
		printerr("ECHEC fichiers sans pack : %d (%s)" % [asg[""].size(), asg[""].slice(0, 5)]); quit(1); return
	for platform in platforms:
		var total := 0
		for id in asg:
			if id == "" or (not wanted.is_empty() and not id in wanted): continue
			var files := pack_files(asg[id], platform)
			var sz := write_pack(id, files, platform, data_version, outdir)
			if sz < 0: quit(1); return
			total += sz
			print("PACK|%s|%s|fichiers=%d|%.1f Mo" % [platform, id, files.size() + 1, sz / 1048576.0])
		print("PACKS|%s|total=%.1f Mo" % [platform, total / 1048576.0])
	quit()
