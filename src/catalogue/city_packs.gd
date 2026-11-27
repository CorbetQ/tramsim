class_name CityPacks
extends RefCounted
## Packs de ville (refonte P4, docs/CDC_REFONTE_VISUELLE.md §7.1 « APK de base ≤ 150 Mo + packs de ville ≤ 400 Mo »).
## Les données propres à une ville (data/scenes/<ville>*, data/free/<ville>*, data/stations…, assets/models/<ville>/)
## sont livrées hors du paquet de base Android dans tramsim-city-<ville>.pck (tools/packs/build_packs.gd). Le paquet de
## base garde index.json, les réseaux (catalogue des lignes) et les villes de data/packs/base.json (Angers, Nantes).
## Au choix d'une ville absente : montage du pack s'il est déjà sur l'appareil (user://packs, dossier « packs » à côté
## de l'exécutable, OS.get_user_data_dir), sinon téléchargement depuis la release GitHub de la version du jeu
## (CityPreload) ; repli : message d'erreur et ville indisponible, le reste du jeu fonctionne.
## Sur PC (installateur complet) et en développement, toutes les données sont présentes : rien n'est monté.
const BASE := "res://data/packs/base.json"
const MANIFEST := "res://data/packs/%s.json"      # écrit dans chaque pack : version, fichiers
const FILE := "tramsim-city-%s.pck"
const RELEASE_URL := "https://github.com/CorbetQ/tramsim/releases/download/%s/%s"
## Tag de la release GitHub qui publie les packs de ce build : écrit par release.yml dans project.godot
## (tramsim/release/tag = v<APP_VERSION>-build.<run_number>) avant l'export ; à défaut (build local), v<version>.
const RELEASE_TAG_SETTING := "tramsim/release/tag"
const USER_DIR := "user://packs"
static var mounted: Dictionary = {}

## Version du jeu (les packs sont construits pour une version donnée : les données doivent correspondre).
static func game_version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", ""))

static func file_name(city: String) -> String:
	return FILE % city

## Clé de pack d'une entrée du catalogue (préfixe de l'identifiant du réseau : lyon_t1 -> lyon).
static func key_of(entry: Dictionary) -> String:
	return str(entry.get("id", str(entry.get("path", "")).get_file().get_basename())).get_slice("_", 0)

## Vrai si les données de la ville sont lisibles (paquet de base, installation complète ou pack monté).
static func present(city: String) -> bool:
	return FileAccess.file_exists("res://data/scenes/%s.json" % city) or FileAccess.file_exists(MANIFEST % city)

## Chemins où chercher un pack déjà téléchargé ou livré à côté du jeu.
static func search_paths(city: String) -> Array:
	var out := [USER_DIR.path_join(file_name(city))]
	var exe := OS.get_executable_path().get_base_dir()
	if exe != "": out.append(exe.path_join("packs").path_join(file_name(city)))
	out.append(OS.get_user_data_dir().path_join("packs").path_join(file_name(city)))
	return out

## Monte le pack de la ville s'il est trouvé. Retourne "" si la ville est disponible, sinon un message.
static func ensure(city: String) -> String:
	if city == "" or mounted.has(city): return ""
	for p in search_paths(city):
		if FileAccess.file_exists(p) and ProjectSettings.load_resource_pack(p, true):
			mounted[city] = p
			var man = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST % city)) if FileAccess.file_exists(MANIFEST % city) else null
			if man is Dictionary and str(man.get("version", "")) != game_version():
				push_warning("Pack %s construit pour la version %s (jeu %s)" % [city, man.get("version", "?"), game_version()])
			return ""
	if present(city): return ""
	return "Données de la ville « %s » absentes : pack %s à télécharger." % [city, file_name(city)]

## Tag de la release GitHub de ce build (celle qui publie ses packs).
static func release_tag() -> String:
	var t := str(ProjectSettings.get_setting(RELEASE_TAG_SETTING, ""))
	return t if t != "" else "v" + game_version()

## URL du pack sur la release GitHub de ce build.
static func download_url(city: String) -> String:
	return RELEASE_URL % [release_tag(), file_name(city)]

## Chemin de destination d'un téléchargement.
static func download_path(city: String) -> String:
	DirAccess.make_dir_recursive_absolute(USER_DIR)
	return USER_DIR.path_join(file_name(city))
