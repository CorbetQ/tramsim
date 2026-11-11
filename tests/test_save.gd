extends SceneTree
var fails := 0
func check(c: bool, m: String) -> void:
	if not c: fails += 1; printerr("ECHEC: ", m)
	else: print("ok: ", m)
func _init() -> void:
	var p := "user://test_save.json"
	var d := SaveGame.default_data()
	d.settings.traffic = false
	var deb := {"success": true, "reason": "", "time_s": 600.0, "stops": [{"name": "A", "result": 0}]}
	SaveGame.add_result(d, "angers_a", "citadis_302", deb)
	check(SaveGame.save_data(d, p), "écriture")
	var r := SaveGame.load_data(p)
	check(r.settings.traffic == false and r.results.size() == 1, "relecture identique")
	var f := FileAccess.open(p, FileAccess.WRITE); f.store_string("{pas du json"); f.close()
	check(SaveGame.load_data(p).results.is_empty(), "fichier corrompu => valeurs par défaut")
	check(SaveGame.load_data("user://absent.json").settings.has("view_distance"), "fichier absent => défauts")
	DirAccess.remove_absolute(p)
	quit(1 if fails > 0 else 0)
