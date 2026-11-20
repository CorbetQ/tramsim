extends SceneTree
var fails := 0
const PREFIX := "user://p0-save-test"
func check(ok: bool, text: String) -> void:
	if not ok: fails += 1; printerr("ECHEC: ", text)
	else: print("ok: ", text)
func write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE); f.store_string(text); f.close()
func clean(path: String) -> void:
	for suffix in ["", ".tmp", ".bak", ".copying", ".bak.copying"]: DirAccess.remove_absolute(path + suffix)
func network(reverse: bool = false, parallel: bool = false) -> NetworkLoader:
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/schema_test.json"))
	d.id = "fixture"; d.origin = [47.0, -0.5]; d.nodes = ["a", "b"]
	d.stations = []; d.signals = []; d.roads = []
	d.edges = [{"id":"new", "from":"a", "to":"b", "length":100.0, "pts":[[100,0],[0,0]] if reverse else [[0,0],[100,0]], "y":[0,0], "source":{"way":123}}]
	if parallel: d.edges.append({"id":"parallel", "from":"a", "to":"b", "length":100.0, "pts":[[0,0.4],[100,0.4]], "y":[0,0], "source":{"way":123}})
	var net := NetworkLoader.new(); check(net.load_data(d).is_empty(), "réseau synthétique valide")
	return net
func _init() -> void:
	var p := PREFIX + ".json"; clean(p)
	var old := FileAccess.get_file_as_string("res://tests/fixtures/saves/v1.json")
	write(p, old)
	var first := SaveGame.load_checked(p)
	check(first.ok and first.status == "migrated" and first.data.version == 2, "migration réelle v1 -> v2")
	check(FileAccess.get_file_as_string(p + ".bak") == old, "backup v1 exact avant migration")
	check(first.data.results.size() == 1 and first.data.plugin_extension.preserved, "progression/extensions conservées")
	check(first.data.settings.view_distance == 400 and first.data.settings.custom_theme == "old", "défauts fusionnés sans perdre options inconnues")
	var hash := FileAccess.get_sha256(p)
	var again := SaveGame.load_checked(p)
	check(again.status == "loaded" and FileAccess.get_sha256(p) == hash and again.data.migration_log.size() == 1, "migration idempotente, pas de réécriture")
	var future := FileAccess.get_file_as_string("res://tests/fixtures/saves/future.json")
	write(p, future)
	check(SaveGame.load_checked(p).status == "future_version", "version future détectée même si schéma différent")
	check(not SaveGame.save_data(SaveGame.default_data(), p) and FileAccess.get_file_as_string(p) == future, "version future non écrasée par autosave")
	clean(p); write(p, "{broken")
	check(not SaveGame.load_checked(p).ok and not SaveGame.save_data(SaveGame.default_data(), p), "corruption sans copie : lecture/écriture protégées")
	var valid := JSON.stringify(SaveGame.default_data())
	write(p + ".bak", valid)
	var quarantine := p + ".corrupt-" + FileAccess.get_sha256(p).substr(0,12)
	var restored := SaveGame.load_checked(p)
	check(restored.ok and restored.status == "recovered" and FileAccess.file_exists(quarantine), "copie restaurée, corruption mise en quarantaine")
	DirAccess.remove_absolute(quarantine)
	clean(p); write(p + ".tmp", old)
	restored = SaveGame.load_checked(p)
	check(restored.ok and restored.data.results.size() == 1 and restored.data.version == 2, "reprise d'un temporaire complet après interruption")
	write(p + ".tmp", "broken")
	check(SaveGame.load_checked(p).ok and FileAccess.get_file_as_string(p) != "broken", "primaire valide prioritaire sur temporaire incomplet")
	clean(p); write(p + ".tmp", future); write(p + ".bak", valid)
	check(not SaveGame.load_checked(p).ok and not SaveGame.save_data(SaveGame.default_data(),p), "temporaire futur interdit la rétrogradation")
	clean(p); write(p,valid); write(p + ".tmp",future)
	check(not SaveGame.load_checked(p).ok and not SaveGame.save_data(SaveGame.default_data(),p) and FileAccess.get_file_as_string(p + ".tmp") == future, "primaire ancien ne détruit pas un checkpoint futur")
	clean(p)
	check(SaveResume.network_path({"net_path":"old"}, {"old":"res://data/networks/angers_a.json"}) == "res://data/networks/angers_a.json", "alias explicite d’un chemin réseau ancien")
	var invalid := SaveGame.default_data(); invalid.settings.traffic = "no"
	check(not SaveGame.validate_data(invalid).is_empty() and not SaveGame.save_data(invalid,p), "types de schéma contrôlés")
	var net := network()
	var saved := {"network":"old-path", "network_id":"fixture", "edge":"old", "offset":20, "direction":-1}
	net.meta.save_aliases = {"edges":{"old":{"edge":"new","shift_m":10}}}
	var mapped := SaveResume.resolve(saved,net,"new-path")
	check(mapped.ok and mapped.station.offset == 30 and mapped.station.direction == -1, "alias explicite du réseau/arête et sens préservés")
	net.meta.erase("save_aliases")
	saved.anchor = {"lat":47.0,"lon":-0.5 + rad_to_deg(20.0 / (SaveResume.EARTH_M * cos(deg_to_rad(47.0))))}
	saved.heading = [1,0]; saved.source = {"way":123}
	mapped = SaveResume.resolve(saved,network(true),"new-path")
	check(mapped.ok and absf(mapped.station.offset - 80) < .01 and mapped.station.direction == -1, "reprojection géographique après inversion de l'arête")
	check(SaveResume.resolve(saved,network(false,true),"new-path").status == "ambiguous", "voies proches ambiguës refusées")
	saved.anchor.lat = 46.0
	check(not SaveResume.resolve(saved,net,"new-path").ok, "aucune téléportation vers une voie éloignée")
	check(not SaveResume.resolve({"network":"other","edge":"old","offset":2}, net,"new-path").ok, "pas de confusion entre réseaux sans identifiant")
	var real := FreeSession.new(net, VehicleLibrary.citadis_302(), "new", 20.0, false)
	real.checkpoint_dir = -1
	var snapshot := SaveGame.default_data(); SaveGame.store_free(snapshot, real, "new-path", "citadis_302")
	check(snapshot.free.has("anchor") and snapshot.free.direction == -1, "checkpoint réel enrichi sans perdre l’API")
	check(SaveGame.save_data(snapshot,p) and SaveGame.load_data(p).free.edge == "new", "checkpoint réel relu sur disque")
	var before := FileAccess.get_sha256(p)
	DirAccess.remove_absolute(p + ".bak"); DirAccess.make_dir_absolute(p + ".bak")
	check(not SaveGame.save_data(snapshot,p) and FileAccess.get_sha256(p) == before, "échec de backup : aucun remplacement de l'original")
	DirAccess.remove_absolute(p + ".bak"); clean(p)
	check(SaveGame.default_data().version == SaveGame.VERSION, "API par défaut conservée")
	print("TOTAL_ECHECS|",fails); quit(1 if fails else 0)
