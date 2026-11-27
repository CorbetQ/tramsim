class_name CityPacks
extends RefCounted
## Données téléchargeables (docs/SERVEUR_DONNEES.md). Les exports (APK, EXE/MSI) ne contiennent que le moteur, l'UI et
## le catalogue ; chaque ville (scène, terrain, décor, monuments, lightmaps, rames HD et livrées propres) est un pack
## tramsim-city-<ville>-<plateforme>.pck qui dépend des packs communs (commun-rames, commun-decor). Les packs sont
## décrits par un manifeste (taille, sha256, URL, dépendances) servi par le serveur de données (server/, URL de base
## embarquée au build depuis DATA_DOMAIN, modifiable dans les Réglages) ou, en repli, par la release GitHub du build.
## Le téléchargement (reprise, sha256, annulation) est fait par PackDownloader ; ici : état local, montage, cache.
## En développement (arborescence source, data/packs/plan.json présent) toutes les données sont là : rien n'est monté.
const DATA_FORMAT := 1                               # format des packs compris par cette version de l'appli
const MANIFEST := "res://data/packs/%s.json"         # manifeste interne écrit dans chaque pack
const SOURCE_TREE := "res://data/packs/plan.json"    # présent seulement dans l'arborescence source (exclu des exports)
const COMMONS := ["commun-rames", "commun-decor"]
const USER_DIR := "user://packs"
const INSTALLED := "user://packs/installed.json"
const CACHED_MANIFEST := "user://packs/manifest.json"
const CONFIG := "user://packs/settings.cfg"
## URL de base du serveur de données, écrite par release.yml depuis la variable de dépôt DATA_DOMAIN ("" : aucun).
const SERVER_SETTING := "tramsim/data/base_url"
## Tag et dépôt de la release GitHub de ce build (repli) : écrits par release.yml dans project.godot.
const RELEASE_TAG_SETTING := "tramsim/release/tag"
const RELEASE_REPO_SETTING := "tramsim/release/repo"
const DEFAULT_REPO := "CorbetQ/tramsim"
const RELEASE_URL := "https://github.com/%s/releases/download/%s"
const RELEASE_BASE_SETTING := "tramsim/release/base_url"   # remplace l'URL de release (miroir, tests)
static var mounted: Dictionary = {}
static var _installed: Variant = null
static var _manifest: Variant = null
static var _override: Variant = null
## Tests : identifiants traités comme non téléchargés malgré l'arborescence source (écran de téléchargement).
static var simulated_absent: Dictionary = {}

static func game_version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", ""))

## Plateforme des packs : textures mobiles (etc2/astc, LOD Mobile) ou PC (s3tc/bptc, LOD0, 4k).
static func platform() -> String:
	var env := OS.get_environment("TRAMSIM_PACK_PLATFORM")
	if env in ["mobile", "pc"]: return env
	return "mobile" if OS.has_feature("mobile") else "pc"

static func engine_key() -> String:
	var v := Engine.get_version_info()
	return "%d.%d" % [v.major, v.minor]

static func is_common(id: String) -> bool:
	return id.begins_with("commun-")

static func pack_file(id: String, plat: String = "") -> String:
	if plat == "": plat = platform()
	return ("tramsim-%s-%s.pck" if is_common(id) else "tramsim-city-%s-%s.pck") % [id, plat]

static func file_name(city: String) -> String:
	return pack_file(city)

## Clé de pack d'une entrée du catalogue (préfixe de l'identifiant du réseau : lyon_t1 -> lyon).
static func key_of(entry: Dictionary) -> String:
	return str(entry.get("id", str(entry.get("path", "")).get_file().get_basename())).get_slice("_", 0)

static func keys_of_city(city: String) -> Array:
	var out: Array = []
	for e in NetworkRegistry.entries():
		if e.city == city and not CityPacks.key_of(e) in out: out.append(CityPacks.key_of(e))
	return out

## Vrai si les données sont lisibles sans pack (arborescence source) ou par un pack déjà monté.
static func present(id: String) -> bool:
	if simulated_absent.has(id): return false
	if FileAccess.file_exists(MANIFEST % id): return true
	if is_common(id): return FileAccess.file_exists(SOURCE_TREE)
	return FileAccess.file_exists("res://data/scenes/%s.json" % id)

# ------------------------------------------------------------------------------------------ état local (user://)

static func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path): return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))

static func _write_json(path: String, data: Variant) -> void:
	DirAccess.make_dir_recursive_absolute(USER_DIR)
	var f := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if f == null: return
	f.store_string(JSON.stringify(data, " ")); f.close()
	DirAccess.rename_absolute(path + ".tmp", path)

## Packs téléchargés : {id: {file, sha256, size, data_version, format, platform}}.
static func installed() -> Dictionary:
	if _installed == null:
		var d = _read_json(INSTALLED)
		_installed = d if d is Dictionary else {}
	return _installed

static func installed_path(id: String) -> String:
	var r: Dictionary = installed().get(id, {})
	if r.is_empty() or int(r.get("format", 0)) != DATA_FORMAT or str(r.get("platform", "")) != platform(): return ""
	var p := USER_DIR.path_join(str(r.get("file", "")))
	return p if FileAccess.file_exists(p) else ""

static func record_install(id: String, file: String, sha256: String, size: int, data_version: String) -> void:
	var old: Dictionary = installed().get(id, {})
	installed()[id] = {"file": file, "sha256": sha256, "size": size, "data_version": data_version,
		"format": DATA_FORMAT, "platform": platform()}
	_write_json(INSTALLED, installed())
	if not old.is_empty() and str(old.get("file", "")) != file and not mounted.has(id):
		DirAccess.remove_absolute(USER_DIR.path_join(str(old.file)))

## Supprime un pack téléchargé. Retourne un message ("" : supprimé immédiatement).
static func remove(id: String) -> String:
	var r: Dictionary = installed().get(id, {})
	if r.is_empty(): return "Pack « %s » non installé." % id
	installed().erase(id); _write_json(INSTALLED, installed())
	if mounted.has(id): return "Pack « %s » supprimé : espace libéré au prochain démarrage." % id
	DirAccess.remove_absolute(USER_DIR.path_join(str(r.get("file", ""))))
	return ""

## Fichiers de user://packs qui ne sont plus référencés (anciennes versions, suppressions différées).
static func cleanup() -> int:
	if not DirAccess.dir_exists_absolute(USER_DIR): return 0
	var keep := {}
	for r in installed().values(): keep[str(r.get("file", ""))] = true
	var n := 0
	for f in DirAccess.get_files_at(USER_DIR):
		if f.ends_with(".pck") and not keep.has(f):
			DirAccess.remove_absolute(USER_DIR.path_join(f)); n += 1
	return n

static func usage_bytes() -> int:
	var n := 0
	for id in installed():
		if installed_path(id) != "": n += int(installed()[id].get("size", 0))
	return n

static func space_left() -> int:
	DirAccess.make_dir_recursive_absolute(USER_DIR)
	var d := DirAccess.open(USER_DIR)
	return int(d.get_space_left()) if d != null else -1

# ------------------------------------------------------------------------------------------ serveur et manifeste

static func _config() -> ConfigFile:
	var c := ConfigFile.new(); c.load(CONFIG)
	return c

## URL de base du serveur : réglage avancé (user://packs/settings.cfg) sinon valeur embarquée au build.
static func base_url() -> String:
	if _override == null: _override = str(_config().get_value("server", "base_url", ""))
	var u := str(_override) if str(_override) != "" else str(ProjectSettings.get_setting(SERVER_SETTING, ""))
	u = u.strip_edges().trim_suffix("/")
	if u != "" and not u.begins_with("http"): u = "https://" + u
	return u

static func embedded_base_url() -> String:
	return str(ProjectSettings.get_setting(SERVER_SETTING, ""))

static func set_base_url(url: String) -> void:
	var c := _config(); c.set_value("server", "base_url", url.strip_edges())
	DirAccess.make_dir_recursive_absolute(USER_DIR); c.save(CONFIG)
	_override = url.strip_edges()

static func release_tag() -> String:
	var t := str(ProjectSettings.get_setting(RELEASE_TAG_SETTING, ""))
	return t if t != "" else "v" + game_version()

static func release_base() -> String:
	var forced := str(ProjectSettings.get_setting(RELEASE_BASE_SETTING, ""))
	if forced != "": return forced.trim_suffix("/")
	var repo := str(ProjectSettings.get_setting(RELEASE_REPO_SETTING, ""))
	return RELEASE_URL % [repo if repo != "" else DEFAULT_REPO, release_tag()]

## Sources de données dans l'ordre : serveur (manifeste par format), puis release GitHub de ce build.
static func sources() -> Array:
	var out: Array = []
	var b := base_url()
	if b != "":
		out.append({"name": "serveur", "manifest": [b + "/api/v1/formats/%d/manifest.json" % DATA_FORMAT, b + "/api/v1/manifest"], "root": b, "relative": false})
	out.append({"name": "release", "manifest": [release_base() + "/manifest.json"], "root": release_base(), "relative": true})
	return out

## URL d'un pack pour une source : chemin du manifeste (serveur) ou nom de fichier à côté du manifeste (release).
static func pack_url(src: Dictionary, entry: Dictionary) -> String:
	var u := str(entry.get("url", ""))
	if u.begins_with("http"): return u
	if bool(src.get("relative", false)) or u == "": return str(src.root) + "/" + str(entry.get("file", ""))
	return str(src.root) + ("" if u.begins_with("/") else "/") + u

## "" si le manifeste est utilisable par cette appli, sinon la raison.
static func incompatibility(man: Variant) -> String:
	if not man is Dictionary or not man.has("platforms"): return "manifeste illisible"
	if int(man.get("format", 0)) != DATA_FORMAT: return "format de données %s (appli : %d) : mettez le jeu à jour" % [man.get("format", "?"), DATA_FORMAT]
	if str(man.get("engine", engine_key())) != engine_key(): return "données pour Godot %s (appli : %s)" % [man.get("engine"), engine_key()]
	if not (man.platforms as Dictionary).has(platform()): return "aucun pack pour la plateforme " + platform()
	return ""

static func manifest() -> Dictionary:
	if _manifest == null:
		var d = _read_json(CACHED_MANIFEST)
		_manifest = d if d is Dictionary and incompatibility(d) == "" else {}
	return _manifest

static func store_manifest(man: Dictionary) -> void:
	_manifest = man; _write_json(CACHED_MANIFEST, man)

static func entry(id: String) -> Dictionary:
	return manifest().get("platforms", {}).get(platform(), {}).get(id, {})

static func requires(id: String) -> Array:
	if is_common(id): return []
	var e := entry(id)
	return e.get("requires", COMMONS) if not e.is_empty() else COMMONS.duplicate()

# ------------------------------------------------------------------------------------------ état d'une ville

## Pack et ses dépendances (communs d'abord).
static func closure(ids: Array) -> Array:
	var out: Array = []
	for id in ids:
		for d in requires(str(id)):
			if not d in out: out.append(d)
	for id in ids:
		if not id in out: out.append(id)
	return out

## "bundled" (données dans l'appli), "installed", "update" (sha256 différent dans le manifeste), "missing".
static func status(id: String) -> String:
	if installed_path(id) == "":
		if mounted.has(id) or present(id): return "bundled"
		return "missing"
	var e := entry(id)
	if not e.is_empty() and str(e.get("sha256", "")) != str(installed()[id].get("sha256", "")): return "update"
	return "installed"

## Packs à télécharger pour ces clés de ville (dépendances comprises) : absents, ou à mettre à jour si with_updates.
static func needed(keys: Array, with_updates := false) -> Array:
	var out: Array = []
	for id in closure(keys):
		var s := status(id)
		if s == "missing" or (with_updates and s == "update"): out.append(id)
	return out

## Taille à télécharger (octets, d'après le manifeste ; -1 si inconnue).
static func download_bytes(ids: Array) -> int:
	var n := 0
	for id in ids:
		var e := entry(str(id))
		if e.is_empty(): return -1
		n += int(e.get("size", 0))
	return n

static func human_size(bytes: float) -> String:
	if bytes < 0: return "taille inconnue"
	if bytes >= 1073741824.0: return "%.2f Go" % (bytes / 1073741824.0)
	if bytes >= 1048576.0: return "%.1f Mo" % (bytes / 1048576.0)
	return "%d ko" % int(ceil(bytes / 1024.0))

static func label(id: String) -> String:
	var e := entry(id)
	if e.has("label"): return str(e.label)
	for x in NetworkRegistry.entries():
		if key_of(x) == id: return str(x.city)
	return id

# ------------------------------------------------------------------------------------------ montage

static func search_paths(id: String) -> Array:
	var out: Array = []
	var p := installed_path(id)
	if p != "": out.append(p)
	var exe := OS.get_executable_path().get_base_dir()
	if exe != "": out.append(exe.path_join("packs").path_join(pack_file(id)))
	return out

## Monte un pack (sans ses dépendances). Vrai si les données sont lisibles.
static func mount(id: String) -> bool:
	if mounted.has(id): return true
	for p in search_paths(id):
		if FileAccess.file_exists(p) and ProjectSettings.load_resource_pack(p, true):
			mounted[id] = p
			var man = _read_json(MANIFEST % id)
			if man is Dictionary and int(man.get("format", DATA_FORMAT)) != DATA_FORMAT:
				push_warning("Pack %s au format %s (appli %d)" % [id, man.get("format"), DATA_FORMAT])
			if is_common(id): StockHD.reset_cache()
			return true
	return present(id)

## Monte le pack d'une ville et ses dépendances. Retourne "" si la ville est jouable, sinon un message.
static func ensure(city: String) -> String:
	if city == "": return ""
	var missing: Array = []
	for id in closure([city]):
		if not mount(id): missing.append(id)
	if missing.is_empty(): return ""
	return "Données absentes : %s à télécharger (%s)." % [", ".join(missing.map(func(x): return label(x))), ", ".join(missing.map(func(x): return pack_file(x)))]

## Réinitialise les caches statiques (tests, changement de dossier).
static func reload_state() -> void:
	_installed = null; _manifest = null; _override = null
