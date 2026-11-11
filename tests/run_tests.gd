extends SceneTree
## godot --headless --path . -s tests/run_tests.gd

var fails := 0

func check(cond: bool, msg: String) -> void:
	if not cond:
		fails += 1
		printerr("ECHEC: ", msg)
	else:
		print("ok: ", msg)

func _init() -> void:
	var p := VehicleProfile.new()
	p.power_kw = 600.0; p.empty_mass_kg = 45000.0; p.max_speed_ms = 19.4
	# accélération
	var t := TrainPhysics.new(p)
	for i in 300: t.step(0.1, 1.0, 0.0)
	check(t.speed > 10.0 and t.speed <= p.max_speed_ms, "accélération plausible (%.1f m/s)" % t.speed)
	# charge ralentit l'accélération
	var a := TrainPhysics.new(p); var b := TrainPhysics.new(p); b.passengers = 250
	for i in 100: a.step(0.1, 1.0, 0.0); b.step(0.1, 1.0, 0.0)
	check(b.speed < a.speed, "la charge réduit l'accélération")
	# pente
	var c := TrainPhysics.new(p); var d := TrainPhysics.new(p)
	for i in 100: c.step(0.1, 1.0, 0.0); d.step(0.1, 1.0, 0.06)
	check(d.speed < c.speed, "la montée ralentit")
	# freinage
	var v0 := t.speed; var x0 := t.position
	while t.speed > 0.0: t.step(0.05, -1.0, 0.0)
	var dist := t.position - x0
	check(absf(dist - TrainPhysics.new(p).braking_distance(v0)) < 0.2 * dist, "distance de freinage cohérente")
	# coupure d'alimentation
	var e := TrainPhysics.new(p); e.power_available = false
	for i in 50: e.step(0.1, 1.0, 0.0)
	check(e.speed == 0.0, "pas de traction sans alimentation")
	# courbe
	check(TrainPhysics.curve_speed_limit(25.0) < TrainPhysics.curve_speed_limit(100.0), "limite en courbe")
	# graphe / aiguillage
	var g := TrackGraph.new()
	g.add_edge("a", "N0", "N1", 100.0); g.add_edge("b", "N1", "N2", 80.0); g.add_edge("c", "N1", "N3", 60.0)
	check(g.next_edge("a") == "b", "branche par défaut")
	check(g.throw_switch("N1", 1) and g.next_edge("a") == "c", "aiguillage manœuvré")
	g.occupy("a", "T1")
	check(not g.throw_switch("N1", 0), "aiguillage occupé refusé")
	check(g.next_edge("c") == "", "fin de voie détectée")
	check(g.validate().is_empty(), "graphe valide")
	# missions
	var m := MissionScorer.new()
	m.evaluate_departure("A", 100, 100); check(m.success(), "mission à l'heure")
	var m2 := MissionScorer.new(); m2.evaluate_departure("A", 100, 99)
	check(not m2.success(), "départ anticipé")
	var m3 := MissionScorer.new(); m3.evaluate_departure("A", 100, 161)
	check(not m3.success(), "retard > 60 s")
	var m4 := MissionScorer.new(); m4.evaluate_departure("A", 100, 160); check(m4.success(), "retard = 60 s toléré")
	var m5 := MissionScorer.new(); m5.evaluate_departure("A", 100, 100, false)
	check(not m5.success(), "arrêt oublié")
	var m6 := MissionScorer.new(); m6.safety_fault("signal"); check(not m6.success(), "faute de sécurité")
	quit(1 if fails > 0 else 0)
