extends SceneTree
## P4 packs de ville (src/catalogue/city_packs.gd, tools/packs/build_packs.gd) : construction d'un pack (Aubagne)
## dans user://packs, montage par CityPacks.ensure (manifeste res://data/packs/aubagne.json lisible seulement depuis le
## pack), repli sans pack (ville inconnue : message, pas de plantage), URL de la release, filtre d'exclusion du preset
## Android cohérent avec les villes en packs (data/packs/base.json).
var fails := 0

func check(c: bool, m: String) -> void:
	if c: print("ok: ", m)
	else: fails += 1; printerr("ECHEC: ", m)

func _init() -> void:
	var Builder = load("res://tools/packs/build_packs.gd")
	var base: Array = Builder.base_cities()
	check("angers" in base and "nantes" in base, "paquet de base : %s" % [base])
	var files: Array = Builder.city_files("aubagne")
	var has_scene := false
	for f in files: has_scene = has_scene or f[0] == "res://data/scenes/aubagne.bin"
	check(has_scene and files.size() >= 5, "fichiers du pack aubagne : %d (scène incluse)" % files.size())
	DirAccess.make_dir_recursive_absolute(CityPacks.USER_DIR)
	var path := CityPacks.download_path("aubagne")
	var pk := PCKPacker.new()
	check(pk.pck_start(path) == OK, "pck_start %s" % path)
	for f in files: pk.add_file(f[0], f[1])
	var tmp := OS.get_cache_dir().path_join("tramsim_pack_test.json")
	var fw := FileAccess.open(tmp, FileAccess.WRITE); fw.store_string(JSON.stringify({"city": "aubagne", "version": CityPacks.game_version()})); fw.close()
	pk.add_file(CityPacks.MANIFEST % "aubagne", tmp); pk.flush()
	check(not FileAccess.file_exists(CityPacks.MANIFEST % "aubagne"), "manifeste absent avant montage")
	CityPacks.mounted.erase("aubagne")
	check(CityPacks.ensure("aubagne") == "" and CityPacks.mounted.has("aubagne"), "pack monté depuis user://packs")
	check(FileAccess.file_exists(CityPacks.MANIFEST % "aubagne"), "manifeste lu depuis le pack")
	var err := CityPacks.ensure("villefantome")
	check(err.contains("absentes") and err.contains("tramsim-city-villefantome.pck"), "repli sans pack : « %s »" % err)
	check(CityPacks.download_url("lyon").begins_with("https://github.com/") and CityPacks.download_url("lyon").ends_with("/tramsim-city-lyon.pck"), "URL de release : %s" % CityPacks.download_url("lyon"))
	check(CityPacks.key_of({"id": "lyon_t1", "path": "res://data/networks/lyon_t1.json"}) == "lyon", "clé de pack d'une ligne")
	var cfg := FileAccess.get_file_as_string("res://export_presets.cfg")
	var android := cfg.get_slice("[preset.1]", 0)
	for c in Builder.all_cities():
		var excluded := android.contains("data/scenes/%s.*" % c)
		check(excluded == not (c in base), "preset Android : %s %s" % [c, "en pack" if excluded else "dans l'APK"])
	DirAccess.remove_absolute(path); DirAccess.remove_absolute(tmp)
	print("TOTAL_ECHECS|%d" % fails)
	quit(1 if fails > 0 else 0)
