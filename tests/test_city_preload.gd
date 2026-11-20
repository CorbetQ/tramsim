extends SceneTree
var failures := 0
func check(ok: bool, text: String) -> void:
	if ok: print("ok: ", text)
	else: failures += 1; printerr("ECHEC: ", text)
func _initialize() -> void: _run.call_deferred()
func wait_city(p: CityPreload, city: String) -> bool:
	var deadline := Time.get_ticks_msec() + 90000
	while Time.get_ticks_msec() < deadline:
		await process_frame
		if p.is_ready(city): return true
		if p.error != "": printerr(p.error); return false
	return false
func _run() -> void:
	var p := CityPreload.new(); root.add_child(p)
	p.request("Bordeaux"); p.request("Angers")
	check(await wait_city(p, "Angers"), "dernier choix chargé malgré une ville précédente en vol")
	check(not p.is_ready("Bordeaux"), "aucun état prêt périmé")
	if not p.is_ready("Angers"): quit(1); return
	var n: NetworkLoader = p.network("res://data/free/angers.json")
	check(n != null and not n.graph.edges.is_empty(), "réseau complet préconstruit avant lancement")
	var model_reads := CityDataStore.disk_reads
	var station_models: Dictionary = CityDataStore.document("res://data/station_models/angers.json")
	check(station_models.stations.size() == 42 and CityDataStore.disk_reads == model_reads, "modèles des stations préchargés dès le choix de la ville")
	var reads := CityDataStore.disk_reads
	var scene := p.take_scene(n.meta.origin)
	check(scene != null and scene.terrain != null, "décor et métadonnées de terrain prêts avant départ")
	var duplicate := NetworkLoader.new(); duplicate.load_file("res://data/free/angers.json")
	check(CityDataStore.disk_reads == reads, "réseau et décor réutilisés sans lecture de données")
	var name_: String = n.meta.stations[0].name
	duplicate.meta.stations[0].name = "modified"
	check(n.meta.stations[0].name == name_, "réseaux indépendants des documents du cache")
	if scene != null: scene.free()
	p.request("Ville inexistante")
	var deadline := Time.get_ticks_msec() + 30000
	while p.error == "" and Time.get_ticks_msec() < deadline: await process_frame
	check(p.error != "" and not p.is_ready("Ville inexistante"), "échec visible sans faux état prêt")
	p.request("Angers")
	check(await wait_city(p, "Angers"), "reprise après erreur")
	p.queue_free(); await process_frame
	print("TOTAL_ECHECS|", failures); quit(1 if failures else 0)
