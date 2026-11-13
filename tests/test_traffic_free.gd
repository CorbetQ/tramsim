extends SceneTree
## godot --headless --path . -s tests/test_traffic_free.gd
var fails := 0
func check(c: bool, m: String) -> void:
	if not c: fails += 1; printerr("ECHEC: ", m)
	else: print("ok: ", m)

func _net() -> NetworkLoader:
	var n := NetworkLoader.new(); n.load_file("res://tests/fixtures/schema_test.json"); return n

func _init() -> void:
	# feux : les voitures s'arrêtent quand la rame approche, et repartent après
	var s := MissionSession.new(_net(), VehicleLibrary.citadis_302_hybride(), "e1", 0.0, [] as Array[float], 10)
	for i in 400: s.traffic.step(0.1, "e0", 0.0, 0.0, func(_a, _b, _c, _d): return INF)
	check(s.traffic.cars.size() >= 1, "des voitures circulent")
	var red := func(_a, _b, _c, _d): return 50.0
	for i in 300: s.traffic.step(0.1, "e0", 0.0, 32.0, red)
	var maxpos := 0.0
	for c in s.traffic.cars: maxpos = maxf(maxpos, c.pos)
	check(s.traffic.light_red[0] and maxpos <= 95.5, "voitures arrêtées avant le croisement (feu rouge)")
	var gaps_ok := true
	var sorted := s.traffic.cars.duplicate(); sorted.sort_custom(func(a, b): return a.pos > b.pos)
	for i in range(1, sorted.size()):
		if sorted[i-1].pos - sorted[i].pos < RoadTraffic.CAR_LEN: gaps_ok = false
	check(gaps_ok, "distances de sécurité entre voitures")
	check(not s.traffic.car_in_crossing(0), "croisement dégagé sous feu rouge")
	# rame qui traverse avec trafic : pas de collision (priorité tram)
	var m := MissionSession.new(_net(), VehicleLibrary.citadis_302_hybride(), "e1", 0.0, [] as Array[float], 10)
	m.pantograph_up = false  # initialisation automatique sur la section APS
	while not m.finished and m.time_s < 120 and m.edge_id == "e1" and m.offset < 600:
		m.tick(0.1, 0.6 if m.phys.speed < 12.0 else 0.0)
	check(m.scorer.fail_reason == "" and m.offset >= 600.0, "traversée du croisement sans collision")
	# collision forcée : voiture dans le croisement, feu ignoré (trafic désynchronisé)
	var m2 := MissionSession.new(_net(), VehicleLibrary.citadis_302_hybride(), "e1", 280.0, [] as Array[float], 10)
	var car := RoadTraffic.Car.new(); car.pos = 101.0; m2.traffic.cars.append(car); m2.traffic.lanes[0]["spawn_every_s"] = 1e9
	m2.traffic.light_red[0] = false
	m2.phys.speed = 10.0
	m2.traffic.enabled = true
	# neutralise le pas de trafic pour garder la voiture en place
	m2.traffic.lanes[0]["light_range_m"] = -1.0
	for i in 30: m2.tick(0.1, 0.0); m2.traffic.cars[0].pos = 101.0 if m2.traffic.cars.size() > 0 else 0.0
	check(m2.scorer.fail_reason == "Collision avec un véhicule", "collision rame/voiture détectée")
	# trafic désactivable
	var f := FreeSession.new(_net(), VehicleLibrary.citadis_302_hybride(), "e0", 100.0, true)
	for i in 200: f.tick(0.1, 0.0)
	f.set_traffic(false)
	check(f.traffic.cars.is_empty(), "trafic désactivé : plus de voiture")
	# mode libre : incident puis remise sur voie
	var f2 := FreeSession.new(_net(), VehicleLibrary.citadis_302_hybride(), "e0", 100.0, false)
	f2.net.graph.occupy("e1", "AUTRE")
	var t := 0.0
	while f2.incident == "" and t < 300.0: f2.tick(0.1, 1.0); t += 0.1
	check(f2.incident == "Collision" and f2.blocked, "incident en mode libre (rame immobilisée)")
	var before := f2.offset
	f2.tick(0.1, 1.0)
	check(f2.offset == before, "rame bloquée tant que non remise sur voie")
	f2.net.graph.release("e1", "AUTRE")
	f2.rerail()
	check(not f2.blocked and f2.edge_id == "e0" and absf(f2.offset - 100.0) < 0.01, "remise sur voie")
	for i in 50: f2.tick(0.1, 1.0)
	check(f2.phys.speed > 0.0, "circulation reprend")
	# choix de branche en mode libre (aiguillage libre)
	var f3 := FreeSession.new(_net(), VehicleLibrary.citadis_302_hybride(), "e3", 100.0, false)
	check(f3.select_branch("N1", 1), "branche sélectionnée sur aiguillage libre")
	var f4 := FreeSession.new(_net(), VehicleLibrary.citadis_302_hybride(), "e0", 890.0, false)
	check(not f4.select_branch("N1", 1), "aiguillage occupé refusé en libre (rame sur la zone d'aiguillage)")
	var f4b := FreeSession.new(_net(), VehicleLibrary.citadis_302_hybride(), "e0", 100.0, false)
	check(f4b.select_branch("N1", 1), "aiguillage libre : rame loin de la zone d'aiguillage")
	# compatibilité
	var cit := VehicleLibrary.citadis_302(); var aps := VehicleLibrary.citadis_402_aps(); var tl := VehicleLibrary.translohr()
	check(Compatibility.mission_allowed(cit, ["overhead"], "steel"), "Citadis 302 compatible Angers")
	check(not Compatibility.mission_allowed(aps, ["overhead"], "steel"), "APS incompatible avec caténaire en mission")
	check(not Compatibility.mission_allowed(tl, ["overhead"], "steel"), "pneus incompatible avec voie ferrée")
	var f5 := FreeSession.new(_net(), tl, "e0", 100.0, false)
	check(f5.adaptation_notice.begins_with("Matériel incompatible") and f5.blocked, "matériel incompatible bloqué en libre")
	var f6 := FreeSession.new(_net(), VehicleLibrary.citadis_302_hybride(), "e0", 100.0, false)
	check(f6.adaptation_notice == "", "pas d'annonce si compatible")
	# cantonnement : section protégée occupée => signal à l'arrêt, franchissement = échec
	var b := MissionSession.new(_net(), VehicleLibrary.citadis_302_hybride(), "e0", 100.0, [] as Array[float], 10)
	b.traffic.set_enabled(false)
	b.tick(0.1, 0.0)
	check(b.signal_state[0] == "clear", "signal au vert, section libre")
	b.net.graph.occupy("e2", "AUTRE"); b.tick(0.1, 0.0)
	check(b.signal_state[0] == "stop", "signal à l'arrêt, section protégée occupée")
	b.net.graph.release("e2", "AUTRE"); b.tick(0.1, 0.0)
	check(b.signal_state[0] == "clear", "signal repasse au vert")
	var b2 := MissionSession.new(_net(), VehicleLibrary.citadis_302_hybride(), "e1", 1000.0, [] as Array[float], 10)
	b2.traffic.set_enabled(false); b2.pantograph_up = false; b2.phys.speed = 8.0
	b2.net.graph.occupy("e2", "AUTRE")
	for i in 100: b2.tick(0.1, 0.3)
	check(b2.scorer.fail_reason == "Signal d'arrêt franchi", "signal automatique franchi => échec")
	# registre + secteurs
	var reg := NetworkRegistry.scan()
	check(reg.size() >= 1, "registre : réseau(x) découvert(s)")
	var vw := LineView.new(); root.add_child(vw)
	var nn := _net(); vw.build(nn, "e0"); vw.view_distance = 300.0
	var near := vw.update_sectors(Vector3(100, 0, 0))
	var all := vw.update_sectors(Vector3(100, 0, 0)) 
	vw.view_distance = 100000.0
	check(near < vw.update_sectors(Vector3(100, 0, 0)), "seuls les secteurs proches sont affichés")
	quit(1 if fails > 0 else 0)
