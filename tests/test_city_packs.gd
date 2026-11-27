extends SceneTree
## Données téléchargeables (src/catalogue/city_packs.gd, tools/packs/build_packs.gd, data/packs/plan.json) :
## répartition de tous les fichiers lourds entre 28 packs de ville et les packs communs (aucun fichier orphelin),
## exports sans données de ville (Android, Windows, Windows ARM64), packs mobile/pc (textures et LOD par plateforme),
## construction et montage d'un pack réel (Aubagne) depuis user://packs, dépendances communes, URL serveur/release,
## compatibilité du manifeste (format, moteur, plateforme), repli sans pack (message, pas de plantage).
var fails := 0

func check(c: bool, m: String) -> void:
	if c: print("ok: ", m)
	else: fails += 1; printerr("ECHEC: ", m)

func _init() -> void:
	var Builder = load("res://tools/packs/build_packs.gd")
	var cities: Array = Builder.all_cities()
	check(cities.size() == 28 and "angers" in cities and "nantes" in cities, "28 villes en packs, Angers et Nantes comprises (%d)" % cities.size())
	check(Builder.common_ids() == CityPacks.COMMONS or Builder.common_ids().size() == CityPacks.COMMONS.size(), "packs communs : %s" % [Builder.common_ids()])
	var asg: Dictionary = Builder.assignment()
	check(asg[""].is_empty(), "aucun fichier lourd sans pack (%s)" % [asg[""].slice(0, 3)])
	for c in cities:
		check(("res://data/scenes/%s.bin" % c) in asg[c] or ("res://data/scenes/%s.json" % c) in asg[c], "pack %s : scène (%d fichiers)" % [c, asg[c].size()])
	var lyon_stock: Array = asg.lyon.filter(func(p): return str(p).begins_with("res://tram_parts/") or str(p).begins_with("res://tram_livery/"))
	check(not lyon_stock.is_empty(), "pack lyon : rames HD propres (%d fichiers)" % lyon_stock.size())
	var ang_stock: Array = asg.angers.filter(func(p): return str(p).begins_with("res://tram_parts/") or str(p).begins_with("res://tram_livery/"))
	check(not ang_stock.is_empty(), "pack angers : rames HD propres (%d fichiers)" % ang_stock.size())
	check(asg["commun-rames"].size() > 0 and asg["commun-decor"].size() > 0, "packs communs non vides (rames %d, décor %d)" % [asg["commun-rames"].size(), asg["commun-decor"].size()])
	check(asg["commun-decor"].any(func(p): return str(p).begins_with("res://assets/textures/pbr/")), "textures PBR dans commun-decor")
	# plateformes : mobile sans LOD0/4k/PBR 2048², pc avec ; textures importées propres à la plateforme
	var mob: Array = Builder.pack_files(asg["commun-decor"], "mobile")
	var pc: Array = Builder.pack_files(asg["commun-decor"], "pc")
	var has := func(files: Array, needle: String) -> bool:
		for f in files:
			if str(f[0]).contains(needle): return true
		return false
	check(not has.call(mob, "_2k.jpg") and has.call(pc, "_2k.jpg"), "PBR 2048² : pc seulement")
	check(has.call(mob, ".etc2.ctex") or has.call(mob, ".astc.ctex"), "textures mobile (etc2/astc)")
	check(not has.call(mob, ".s3tc.ctex") and (has.call(pc, ".s3tc.ctex") or has.call(pc, ".bptc.ctex")), "textures pc (s3tc/bptc) hors pack mobile")
	# exports : aucune donnée de ville ni rame HD dans les trois presets
	var cfg := FileAccess.get_file_as_string("res://export_presets.cfg")
	var presets := cfg.split("[preset.")
	var n := 0
	for blk in presets:
		if not blk.contains("exclude_filter=\""): continue
		n += 1
		var excl: Array = []
		for x in blk.get_slice('exclude_filter="', 1).get_slice('"', 0).split(","): excl.append(x.strip_edges())
		for pat in Builder.plan().export_exclude:
			check(pat in excl, "preset %s : %s exclu" % [blk.get_slice('name="', 1).get_slice('"', 0), pat])
	check(n == 3, "3 presets d'export contrôlés")
	# pack réel : Aubagne (mobile) dans user://packs, enregistré puis monté avec ses dépendances (présentes en dev)
	var files: Array = Builder.pack_files(asg.aubagne, CityPacks.platform())
	DirAccess.make_dir_recursive_absolute(CityPacks.USER_DIR)
	var dir := ProjectSettings.globalize_path(CityPacks.USER_DIR)
	var size: int = Builder.write_pack("aubagne", files, CityPacks.platform(), "test", dir)
	var fname := CityPacks.pack_file("aubagne")
	check(size > 100000 and fname == "tramsim-city-aubagne-%s.pck" % CityPacks.platform(), "pack construit : %s (%.1f Mo)" % [fname, size / 1048576.0])
	check(not FileAccess.file_exists(CityPacks.MANIFEST % "aubagne"), "manifeste interne absent avant montage")
	var backup = CityPacks.installed().duplicate(true)
	CityPacks.record_install("aubagne", fname, "x", size, "test")
	CityPacks.mounted.erase("aubagne")
	check(CityPacks.ensure("aubagne") == "" and CityPacks.mounted.has("aubagne"), "pack monté depuis user://packs")
	var man = JSON.parse_string(FileAccess.get_file_as_string(CityPacks.MANIFEST % "aubagne"))
	check(man is Dictionary and int(man.format) == CityPacks.DATA_FORMAT and man.files.size() == files.size(), "manifeste interne lu depuis le pack")
	check(CityPacks.closure(["aubagne"]) == CityPacks.COMMONS + ["aubagne"], "dépendances communes avant la ville")
	var err := CityPacks.ensure("villefantome")
	check(err.contains("absentes") and err.contains("tramsim-city-villefantome-"), "repli sans pack : « %s »" % err)
	check(CityPacks.status("villefantome") == "missing" and CityPacks.status("lyon") == "bundled", "états : absent / livré (arborescence source)")
	# URL : serveur (chemin du manifeste) et release (fichier à côté du manifeste)
	var e := {"file": "tramsim-city-lyon-pc.pck", "url": "/packs/20261127.1/tramsim-city-lyon-pc.pck"}
	check(CityPacks.pack_url({"root": "https://data.example", "relative": false}, e) == "https://data.example/packs/20261127.1/tramsim-city-lyon-pc.pck", "URL serveur")
	check(CityPacks.pack_url({"root": CityPacks.release_base(), "relative": true}, e).begins_with("https://github.com/") and CityPacks.release_base().ends_with(CityPacks.release_tag()), "URL de release : %s" % CityPacks.release_base())
	check(CityPacks.key_of({"id": "lyon_t1", "path": "res://data/networks/lyon_t1.json"}) == "lyon", "clé de pack d'une ligne")
	var ok_man := {"format": CityPacks.DATA_FORMAT, "engine": CityPacks.engine_key(), "platforms": {CityPacks.platform(): {}}}
	check(CityPacks.incompatibility(ok_man) == "", "manifeste compatible")
	var f2 := ok_man.duplicate(true); f2.format = CityPacks.DATA_FORMAT + 1
	check(CityPacks.incompatibility(f2).contains("format"), "format de données plus récent refusé")
	var e2 := ok_man.duplicate(true); e2.engine = "3.5"
	check(CityPacks.incompatibility(e2) != "", "moteur différent refusé")
	var srcs := CityPacks.sources()
	check(srcs[-1].name == "release" and (CityPacks.base_url() == "" or srcs[0].manifest[0].ends_with("/api/v1/formats/%d/manifest.json" % CityPacks.DATA_FORMAT)), "sources : serveur puis repli release")
	CityPacks.installed().clear(); CityPacks.installed().merge(backup)
	CityPacks._write_json(CityPacks.INSTALLED, CityPacks.installed())
	DirAccess.remove_absolute(CityPacks.USER_DIR.path_join(fname))
	print("TOTAL_ECHECS|%d" % fails)
	quit(1 if fails > 0 else 0)
