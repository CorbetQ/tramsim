extends SceneTree
## godot --headless --path . -s tests/test_angers.gd
var fails := 0
func check(c: bool, m: String) -> void:
	if not c: fails += 1; printerr("ECHEC: ", m)
	else: print("ok: ", m)

func _new(delay: float = 0.0, pax: int = 40) -> MissionSession:
	var net := NetworkLoader.new()
	var errs := net.load_file("res://tests/fixtures/schema_test.json")
	assert(errs.is_empty(), str(errs))
	var sched: Array[float] = [120.0 + delay, 260.0, 470.0, 610.0]
	return MissionSession.new(net, VehicleLibrary.citadis_302_hybride(), "e0", 100.0, sched, pax)

var ap = preload("res://tests/autopilot.gd").new()
func _drive(m: MissionSession, hold_s: float = 0.0, skip_stop: int = -1, max_t: float = 1500.0) -> void:
	ap._drive(m, hold_s, skip_stop, max_t)
func _auto_pantograph(m: MissionSession) -> void:
	ap._auto_pantograph(m)

func _init() -> void:
	var net := NetworkLoader.new()
	check(net.load_file("res://tests/fixtures/schema_test.json").is_empty(), "réseau valide")
	check(net.load_file("res://nope.json").size() == 1, "fichier manquant signalé")
	# mission nominale
	var m := _new()
	_drive(m)
	var r := m.debrief()
	print(r)
	print(m.edge_id, " ", m.offset, " ", m.phys.speed, " next=", m.next_station, " doors=", m.doors_open)
	check(m.finished and m.debrief().success, "mission nominale réussie (4 arrêts à l'heure)")
	# départ anticipé (le pilote part 30 s trop tôt) et retard > 60 s
	var me := _new(); _drive(me, -50.0)
	check(not me.debrief().success and me.scorer.stops[0].result == MissionScorer.Result.EARLY, "départ anticipé => échec")
	var ml := _new(); _drive(ml, 90.0)
	check(not ml.debrief().success, "retard > 60 s => échec")
	# arrêt oublié
	var m2 := _new()
	_drive(m2, 0.0, 1)
	check(not m2.debrief().success, "arrêt oublié => échec")
	# fin de voie
	var m3 := _new()
	while not m3.finished and m3.time_s < 900: _auto_pantograph(m3); m3.tick(0.1, 1.0)
	check(m3.scorer.fail_reason == "Fin de voie dépassée", "fin de voie dépassée => échec")
	# signal d'arrêt
	var m4 := _new()
	m4.net.graph.occupy("e2", "AUTRE")  # section protégée occupée => signal à l'arrêt
	while not m4.finished and m4.time_s < 900: _auto_pantograph(m4); m4.tick(0.1, 1.0)
	check(m4.scorer.fail_reason == "Signal d'arrêt franchi", "signal d'arrêt franchi => échec")
	# collision par occupation
	var m5 := _new()
	m5.net.graph.occupy("e1", "AUTRE")
	while not m5.finished and m5.time_s < 900: _auto_pantograph(m5); m5.tick(0.1, 1.0)
	check(m5.scorer.fail_reason == "Collision", "section occupée => collision")
	# aiguillage vers le dépôt (N1 : e1 ou dep)
	var m6 := _new()
	check(not m6.net.graph.throw_switch("N1", 1), "aiguillage refusé : rame sur la section d'approche")
	var net6 := NetworkLoader.new(); net6.load_file("res://tests/fixtures/schema_test.json")
	check(net6.graph.throw_switch("N1", 1) and net6.graph.next_edge("e0") == "dep", "aiguillage libre vers dépôt")
	# portes interdites en marche
	var m8 := _new(); m8.phys.speed = 5.0; m8.set_doors(true)
	check(not m8.doors_open, "portes refusées en marche")
	# charge évolue à l'arrêt
	var m9 := _new(); m9.phys.speed = 0.0; m9.edge_id = "e0"; m9.offset = 850.0
	var p0 := m9.phys.passengers; m9.set_doors(true)
	for i in 100: m9.tick(0.1, 0.0)
	check(m9.phys.passengers != p0, "montée/descente modifie la charge")
	# APS : transitions caténaire <-> sol
	var a := _new(); a.edge_id = "e1"; a.route = ["e1"]; a.offset = 10.0; a.phys.speed = 10.0
	a.tick(0.1, 1.0)
	check(not a.power_ok, "pantographe levé sur APS => coupure d'alimentation")
	var v0 := a.phys.speed
	for i in 50: a.tick(0.1, 0.5)
	check(a.phys.speed < v0, "la rame ralentit sans traction (coupure)")
	check(a.set_power_mode("aps") != "", "changement APS refusé en mouvement")
	while a.phys.speed > 0.01: a.tick(0.1, -1.0)
	a.set_power_mode("aps")
	for i in 8: a.tick(0.1, -0.75)
	check(a.power_ok, "pantographe baissé sur APS => alimentation rétablie")
	var o := _new(); o.toggle_pantograph(); o.tick(0.1, 1.0)
	check(not o.power_ok, "pantographe baissé sur caténaire => coupure")
	var n7 := NetworkLoader.new(); n7.load_file("res://tests/fixtures/schema_test.json")
	check(not Compatibility.mission_allowed(VehicleLibrary.citadis_302(), n7.supplies, "steel"), "caténaire seul incompatible avec réseau mixte")
	check(Compatibility.mission_allowed(VehicleLibrary.citadis_302_hybride(), n7.supplies, "steel"), "hybride compatible réseau mixte")
	quit(1 if fails > 0 else 0)
