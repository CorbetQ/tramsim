extends SceneTree
## Client des données téléchargeables (src/catalogue/pack_downloader.gd, city_packs.gd) contre un serveur HTTP local
## (tests/fixtures/pack_server.py, Range) : manifeste par format, téléchargement avec coupure puis reprise (Range),
## sha256 faux -> rejet, annulation puis reprise, mise à jour (nouvelle empreinte), repli sur la release quand le
## serveur est injoignable, mode hors ligne (pack installé toujours monté), suppression.
var fails := 0
var srv_pid := -1
var port := 0
var srv_root := ""
var backup := {}
const KEEP := ["installed.json", "manifest.json", "settings.cfg"]

func check(c: bool, m: String) -> void:
	if c: print("ok: ", m)
	else: fails += 1; printerr("ECHEC: ", m)

func _initialize() -> void: _run.call_deferred()

func _sha(path: String) -> String:
	var ctx := HashingContext.new(); ctx.start(HashingContext.HASH_SHA256)
	var f := FileAccess.open(path, FileAccess.READ)
	while f.get_position() < f.get_length(): ctx.update(f.get_buffer(1 << 20))
	return ctx.finish().hex_encode()

## Pack factice : manifeste interne, marqueur et charge aléatoire (taille réglable).
func _make_pack(id: String, marker: String, filler: int, dir: String) -> String:
	var tmp := OS.get_cache_dir().path_join("tramsim_dl_%s" % id)
	DirAccess.make_dir_recursive_absolute(tmp)
	var m := FileAccess.open(tmp.path_join("m.json"), FileAccess.WRITE); m.store_string(JSON.stringify({"id": id, "format": CityPacks.DATA_FORMAT})); m.close()
	var k := FileAccess.open(tmp.path_join("k.txt"), FileAccess.WRITE); k.store_string(marker); k.close()
	var b := FileAccess.open(tmp.path_join("b.bin"), FileAccess.WRITE)
	var rng := RandomNumberGenerator.new(); rng.seed = hash(id + marker)
	var buf := PackedByteArray(); buf.resize(filler)
	for i in filler: buf[i] = rng.randi() & 255
	b.store_buffer(buf); b.close()
	var path := dir.path_join(CityPacks.pack_file(id))
	var pk := PCKPacker.new(); pk.pck_start(path)
	pk.add_file(CityPacks.MANIFEST % id, tmp.path_join("m.json"))
	pk.add_file("res://tests/fixtures/_dl_%s.txt" % id, tmp.path_join("k.txt"))
	pk.add_file("res://tests/fixtures/_dl_%s.bin" % id, tmp.path_join("b.bin"))
	pk.flush()
	return path

func _entry(id: String, path: String, prefix: String, ver: String, sha := "") -> Dictionary:
	return {"kind": "city", "label": "Ville " + id, "file": path.get_file(), "size": int(FileAccess.open(path, FileAccess.READ).get_length()),
		"sha256": sha if sha != "" else _sha(path), "url": "%s/packs/%s/%s" % [prefix, ver, path.get_file()], "requires": []}

func _write_manifest(path: String, ver: String, packs: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var man := {"schema": 1, "format": CityPacks.DATA_FORMAT, "engine": CityPacks.engine_key(), "data_version": ver,
		"platforms": {CityPacks.platform(): packs}}
	var f := FileAccess.open(path, FileAccess.WRITE); f.store_string(JSON.stringify(man)); f.close()

func _wait(sig: Signal, timeout := 30.0) -> Array:
	var box := [null]
	var cb := func(a = null, b = null): box[0] = [a, b]
	sig.connect(cb)
	var deadline := Time.get_ticks_msec() + int(timeout * 1000)
	while box[0] == null and Time.get_ticks_msec() < deadline: await process_frame
	sig.disconnect(cb)
	return box[0] if box[0] != null else [null, "délai dépassé"]

func _log() -> String:
	return FileAccess.get_file_as_string(srv_root.path_join("_log.txt")) if FileAccess.file_exists(srv_root.path_join("_log.txt")) else ""

func _run() -> void:
	# état utilisateur sauvegardé puis restauré
	DirAccess.make_dir_recursive_absolute(CityPacks.USER_DIR)
	for f in KEEP:
		var p := CityPacks.USER_DIR.path_join(f)
		if FileAccess.file_exists(p): backup[f] = FileAccess.get_file_as_bytes(p); DirAccess.remove_absolute(p)
	CityPacks.reload_state()
	srv_root = ProjectSettings.globalize_path("user://test_pack_server")
	_rmrf(srv_root)
	DirAccess.make_dir_recursive_absolute(srv_root.path_join("release"))
	var v1 := srv_root.path_join("packs/T1"); DirAccess.make_dir_recursive_absolute(v1)
	var a1 := _make_pack("villetest", "v1", 600000, v1)
	var bad := _make_pack("villefausse", "x", 50000, v1)
	var slow := _make_pack("villelente", "s", 2500000, v1)
	_write_manifest(srv_root.path_join("api/v1/formats/%d/manifest.json" % CityPacks.DATA_FORMAT), "T1", {
		"villetest": _entry("villetest", a1, "/cut", "T1"),
		"villefausse": _entry("villefausse", bad, "", "T1", "0".repeat(64)),
		"villelente": _entry("villelente", slow, "/slow", "T1")})
	# release (repli) : manifeste et fichiers à plat, URL relative au manifeste
	var r1 := _make_pack("villerepli", "r", 40000, srv_root.path_join("release"))
	_write_manifest(srv_root.path_join("release/manifest.json"), "R1", {"villerepli": _entry("villerepli", r1, "", "R1")})
	port = 18000 + randi() % 1500
	var py := OS.get_environment("PYTHON") if OS.get_environment("PYTHON") != "" else "python3"
	srv_pid = OS.create_process(py, [ProjectSettings.globalize_path("res://tests/fixtures/pack_server.py"), srv_root, str(port)])
	check(srv_pid > 0, "serveur local lancé (port %d)" % port)
	var base := "http://127.0.0.1:%d" % port
	CityPacks._override = base
	ProjectSettings.set_setting(CityPacks.RELEASE_BASE_SETTING, base + "/release")
	var dl := PackDownloader.new(); root_node().add_child(dl)
	var ok := false
	for i in 50:   # attente du serveur
		dl.fetch_manifest(); var r := await _wait(dl.manifest_done, 10.0)
		if r[0] == true: ok = true; break
		OS.delay_msec(100)
	check(ok and CityPacks.entry("villetest").get("size", 0) > 0, "manifeste du serveur (format %d)" % CityPacks.DATA_FORMAT)
	check(CityPacks.status("villetest") == "missing" and CityPacks.needed(["villetest"]) == ["villetest"], "ville absente avant téléchargement")
	# coupure à mi-fichier puis reprise automatique (Range)
	var seen := [0]
	dl.progress.connect(func(_id, done, total, _s): seen[0] = maxi(seen[0], done))
	dl.download(["villetest"]); var r := await _wait(dl.finished, 60.0)
	check(r[0] == true, "téléchargement après coupure : %s" % [r])
	check(_log().contains("/cut/packs/T1/%s bytes=" % CityPacks.pack_file("villetest")), "reprise par requête Range après la coupure")
	check(seen[0] > 0, "progression publiée (%d octets)" % seen[0])
	check(CityPacks.status("villetest") == "installed" and CityPacks.mounted.has("villetest"), "pack installé et monté")
	check(FileAccess.get_file_as_string("res://tests/fixtures/_dl_villetest.txt") == "v1", "données du pack lisibles")
	check(CityPacks.ensure("villetest") == "", "ville jouable")
	# sha256 faux : rejet, rien d'installé, .part supprimé
	dl.download(["villefausse"]); r = await _wait(dl.finished, 30.0)
	check(r[0] == false and str(r[1]).contains("sha256"), "sha256 faux rejeté : %s" % r[1])
	check(not CityPacks.installed().has("villefausse") and not FileAccess.file_exists(CityPacks.USER_DIR.path_join(CityPacks.pack_file("villefausse") + ".part")), "aucun fichier gardé après rejet")
	# annulation pendant un envoi lent, puis reprise depuis le .part
	dl.download(["villelente"])
	var deadline := Time.get_ticks_msec() + 20000
	seen[0] = 0
	while seen[0] < 200000 and Time.get_ticks_msec() < deadline: await process_frame
	dl.cancel(); r = await _wait(dl.finished, 20.0)
	var part := CityPacks.USER_DIR.path_join(CityPacks.pack_file("villelente") + ".part")
	var partial := int(FileAccess.open(part, FileAccess.READ).get_length()) if FileAccess.file_exists(part) else 0
	check(r[0] == false and str(r[1]).contains("annulé") and partial > 0, "annulation : %s (%d octets gardés)" % [r[1], partial])
	dl.download(["villelente"]); r = await _wait(dl.finished, 60.0)
	check(r[0] == true and _log().contains("/slow/packs/T1/%s bytes=%d-" % [CityPacks.pack_file("villelente"), partial]), "reprise après annulation depuis %d octets" % partial)
	# mise à jour : nouvelle empreinte dans le manifeste
	var v2 := srv_root.path_join("packs/T2"); DirAccess.make_dir_recursive_absolute(v2)
	var a2 := _make_pack("villetest", "v2", 30000, v2)
	_write_manifest(srv_root.path_join("api/v1/formats/%d/manifest.json" % CityPacks.DATA_FORMAT), "T2", {"villetest": _entry("villetest", a2, "", "T2")})
	dl.fetch_manifest(); r = await _wait(dl.manifest_done)
	check(r[0] == true and CityPacks.status("villetest") == "update" and CityPacks.needed(["villetest"], true) == ["villetest"], "mise à jour détectée (version T2)")
	var old_file := str(CityPacks.installed().villetest.file)
	dl.download(["villetest"]); r = await _wait(dl.finished)
	check(r[0] == true and CityPacks.status("villetest") == "installed" and str(CityPacks.installed().villetest.file) != old_file, "mise à jour installée sous un nouveau nom")
	check(FileAccess.get_file_as_string("res://tests/fixtures/_dl_villetest.txt") == "v2", "nouvelle version montée")
	# serveur injoignable : repli sur la release
	CityPacks._override = "http://127.0.0.1:%d" % (port + 1)
	dl.download(["villerepli"]); r = await _wait(dl.finished)
	check(r[0] == true and CityPacks.installed().has("villerepli") and _log().contains("/release/" + CityPacks.pack_file("villerepli")), "repli sur la release GitHub : %s" % [r])
	# hors ligne : plus aucun serveur
	OS.kill(srv_pid); srv_pid = -1; OS.delay_msec(200)
	dl.fetch_manifest(); r = await _wait(dl.manifest_done)
	check(r[0] == false, "hors ligne : manifeste indisponible (%s)" % r[1])
	dl.download(["villeinconnue"]); r = await _wait(dl.finished)
	check(r[0] == false and str(r[1]).contains("Hors ligne"), "hors ligne : téléchargement refusé avec message")
	CityPacks.mounted.erase("villetest")
	check(CityPacks.ensure("villetest") == "" and CityPacks.mounted.has("villetest"), "hors ligne : ville déjà téléchargée montée depuis user://packs")
	# suppression (gestion de l'espace)
	var used := CityPacks.usage_bytes()
	CityPacks.mounted.erase("villerepli")
	var repli_file := CityPacks.USER_DIR.path_join(str(CityPacks.installed().villerepli.file))
	check(CityPacks.remove("villerepli") == "" and CityPacks.usage_bytes() < used and not CityPacks.installed().has("villerepli") and not FileAccess.file_exists(repli_file), "suppression d'une ville téléchargée (fichier effacé)")
	var test_file := CityPacks.USER_DIR.path_join(str(CityPacks.installed().villetest.file))
	check(CityPacks.remove("villetest").contains("démarrage") and FileAccess.file_exists(test_file), "suppression d'un pack monté différée au démarrage")
	check(CityPacks.cleanup() >= 1 and not FileAccess.file_exists(test_file), "nettoyage des fichiers non référencés")
	dl.queue_free(); await process_frame
	_cleanup()
	print("TOTAL_ECHECS|%d" % fails)
	quit(1 if fails > 0 else 0)

func root_node() -> Window:
	return get_root()

func _rmrf(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir): return
	for f in DirAccess.get_files_at(dir): DirAccess.remove_absolute(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir): _rmrf(dir.path_join(d))
	DirAccess.remove_absolute(dir)

func _cleanup() -> void:
	if srv_pid > 0: OS.kill(srv_pid)
	for id in CityPacks.installed().keys(): CityPacks.remove(id)
	for f in DirAccess.get_files_at(CityPacks.USER_DIR):
		if f.contains("ville") : DirAccess.remove_absolute(CityPacks.USER_DIR.path_join(f))
	for f in KEEP:
		var p := CityPacks.USER_DIR.path_join(f)
		DirAccess.remove_absolute(p)
		if backup.has(f):
			var w := FileAccess.open(p, FileAccess.WRITE); w.store_buffer(backup[f]); w.close()
	CityPacks.reload_state()
	_rmrf(srv_root)
