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
	# P4 : rames HD des villes en packs hors APK (data/packs/stock.json), rames d'Angers et Nantes dans l'APK
	var excl: Array = []
	for x in android.get_slice('exclude_filter="', 1).get_slice('"', 0).split(","): excl.append(x.strip_edges())
	var st: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Builder.STOCK))
	var stock_cities: Dictionary = st.get("cities", {})
	check(stock_cities.get("lyon", []).size() > 0 and stock_cities.get("strasbourg", []).size() > 0, "rames HD de Lyon et Strasbourg dans leurs packs")
	check(not stock_cities.has("angers") and not stock_cities.has("nantes"), "aucune rame d'Angers ou Nantes en pack")
	var in_excl := func(p: String) -> bool:
		for x in excl:
			if x != "" and p.matchn(x): return true
		return false
	var miss := 0
	for p in stock_cities.get("lyon", []):
		if not in_excl.call(str(p).trim_prefix("res://")): miss += 1
	check(miss == 0, "preset Android : fichiers de rames de Lyon exclus (%d non exclus)" % miss)
	var pm: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/rolling_stock/parts_manifest.json"))
	var kept := 0; var lost: Array = []
	for vid in pm.variants:
		if not (str(vid).begins_with("angers__") or str(vid).begins_with("nantes__")): continue
		var kit_path := str(pm.kits.get(str(pm.variants[vid].kit), ""))
		var doc = JSON.parse_string(FileAccess.get_file_as_string(kit_path))
		for part in doc.get("parts", {}).values():
			for k in ["lod1", "lod1_m", "lod2", "lod3"]:
				var f := str(part.get("models", {}).get(k, ""))
				if f == "": continue
				if in_excl.call(f.trim_prefix("res://")): lost.append(f)
				else: kept += 1
	check(kept > 0 and lost.is_empty(), "rames d'Angers et Nantes (LOD Mobile) dans l'APK : %d fichiers, exclus à tort %s" % [kept, lost.slice(0, 3)])
	var lyon_files: Array = Builder.city_files("lyon")
	var has_stock := false
	for f in lyon_files: has_stock = has_stock or str(f[0]).begins_with("res://tram_parts/") or str(f[0]).begins_with("res://tram_livery/")
	check(has_stock, "pack lyon : rames HD incluses (%d fichiers)" % lyon_files.size())
	check(in_excl.call("assets/textures/pbr/albedo_2k.jpg") and not in_excl.call("assets/textures/pbr/albedo_1k.jpg"), "preset Android : PBR 2048² exclu, 1024² conservé")
	DirAccess.remove_absolute(path); DirAccess.remove_absolute(tmp)
	print("TOTAL_ECHECS|%d" % fails)
	quit(1 if fails > 0 else 0)
