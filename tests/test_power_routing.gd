extends SceneTree
var failures := 0
func check(ok: bool, text_: String) -> void:
	if ok: print("ok: ",text_)
	else: failures += 1; printerr("ECHEC: ",text_)
func _init() -> void:
	var n := NetworkLoader.new(); n.load_file("res://tests/fixtures/schema_test.json")
	var s := MissionSession.new(n, VehicleLibrary.citadis_302_hybride(), "e0", 30.0, [] as Array[float])
	s.traffic.enabled = false
	s.phys.speed = 2.0
	check(s.set_power_mode("aps") != "" and s.power_mode == "overhead" and s.pantograph_up, "refus en marche sans mutation du collecteur ni du mode")
	s.phys.speed = 0.0
	check(s.set_power_mode("aps") == "" and not s.pantograph_up and not s.phys.power_available, "sélection APS à l’arrêt et collecteur abaissé automatiquement")
	check(s.power_transition_left == MissionSession.POWER_SWITCH_SECONDS, "commutation mesurée par la simulation")
	s.tick(0.3,1.0); check(s.phys.speed == 0.0 and not s.power_ok, "traction interdite pendant commutation")
	s.tick(0.4,1.0); check(not s.power_ok and s.phys.speed == 0.0, "mode APS ne fournit pas de courant sur une section LAC")
	n.edge_info.e0.supply = "aps"; s.tick(0.1,1.0)
	check(s.power_ok and s.phys.speed > 0.0, "traction rétablie uniquement avec infrastructure compatible")
	s.phys.speed = 0.0; s.pantograph_up = false; s.power_mode = "overhead"; s.tick(0.1,1.0)
	check(not s.power_ok, "pantographe abaissé seul n’active jamais l’APS")
	check(s.set_power_mode("battery") != "", "mode non supporté refusé")
	var overhead := MissionSession.new(n,VehicleLibrary.citadis_302(),"e0",30.0,[] as Array[float])
	check(overhead.set_power_mode("aps") != "", "matériel LAC seul : APS refusé")
	var angers := NetworkLoader.new(); angers.load_file("res://data/free/angers.json")
	NormalRouting.initialize(angers)
	var corrected := 0
	for sw in angers.graph.switches():
		var options := angers.graph.choices(sw[0],sw[1])
		var first: Array = options[0]
		if angers.edge_info[first[0]].source.get("oneway","") != "yes" or int(first[1]) >= 0: continue
		var correct_exists := false
		for option in options:
			if angers.edge_info[option[0]].source.get("oneway","") == "yes" and int(option[1]) > 0: correct_exists = true
		if not correct_exists: continue
		var chosen: Array = options[angers.graph.active_branch(sw[0],sw[1])]
		check(int(angers.edge_info[chosen[0]].preferred_direction) == int(chosen[1]), "Angers %s : branche normale au lieu de la première branche" % sw[0])
		corrected += 1
	check(corrected == 6, "les six croisements signalés sont couverts")
	var key := "osm:11891531598"; angers.graph.switch_state[TrackGraph.skey(key,1)] = 0
	NormalRouting.initialize(angers)
	check(angers.graph.active_branch(key,1) == 0, "un choix manuel n’est pas réécrit par la politique de défaut")
	check(TrackView.APS_TOP_M > TrackView.BED_TOP_M and TrackView.APS_TOP_M < TrackView.RAIL_TOP_M, "contact APS au-dessus du lit de voie, sous le rail de roulement")
	var profile := VehicleLibrary.default_for({"source_id":"nice","city":"Nice","kind":"tram"})
	check("battery" in profile.power_modes() and not "aps" in profile.power_modes(), "autonomie de Nice distincte de l’APS")
	print("TOTAL_ECHECS|",failures); quit(1 if failures else 0)
