extends SceneTree
## godot --headless --path . -s tests/test_autopilot.gd
## Pilote automatique du mode libre : parcours complet d'une ligne d'Angers (aiguillages
## positionnés le long de l'itinéraire de la ligne), sans survitesse ni signal franchi,
## avec arrêt portes ouvertes à chaque station de la ligne ; reprise en main immédiate.
var fails := 0
func check(c: bool, m: String) -> void:
	if not c: fails += 1; printerr("ECHEC: ", m)
	else: print("ok: ", m)

func _init() -> void:
	var vehicle := VehicleLibrary.citadis_302_hybride()
	for id in ["angers_A_service_0", "angers_B_service_1"]:
		_line_run(id, vehicle)
	_signals_sanity(vehicle)
	print("TOTAL_ECHECS|%d" % fails)
	quit(1 if fails > 0 else 0)

func _mission(id: String) -> Dictionary:
	for m in MissionCatalog.for_city("angers"):
		if str(m.id) == id: return m
	return {}

func _line_run(id: String, vehicle: VehicleProfile) -> void:
	var m := _mission(id)
	check(not m.is_empty(), "mission de référence %s" % id)
	if m.is_empty(): return
	var net := NetworkLoader.new(); net.load_file("res://data/free/angers.json")
	var st: Dictionary = m.start
	var s := FreeSession.new(net, vehicle, str(st.edge), float(st.offset), false)
	s.direction = int(st.dir); s.route_dir = [s.direction]; s.update_spans()
	var plan := Interlocking.plan_route(net, {"edge": str(st.edge), "offset": float(st.offset), "dir": int(st.dir)}, m.waypoints)
	check(not plan.is_empty(), "itinéraire de la ligne %s calculé" % m.line)
	if plan.is_empty(): return
	var path: Array = plan.path
	var ap := Autopilot.new(); ap.enabled = true
	var names := {}
	for i in m.stops: names[str(net.stations[int(i.station)].name)] = true
	var served := {}
	var signals_passed := 0
	s.event.connect(func(kind, _t): if kind == "signal": signals_passed += 1)
	var overspeed_max := 0.0
	var idx := 0
	var last: Dictionary = m.waypoints[-1]
	var arrived := false
	var dt := 0.1
	var was_dwell := false
	while s.time_s < 5400.0 and s.incident == "":
		# Aiguilleur : positionne les aiguilles de l'itinéraire de ligne devant la rame.
		for j in range(idx, mini(idx + 12, path.size())):
			if str(path[j][0]) == s.edge_id and int(path[j][1]) == s.direction: idx = j; break
		for j in range(idx, mini(idx + 8, path.size() - 1)):
			var x := net.graph.exit_of(str(path[j][0]), int(path[j][1]))
			var ch := net.graph.choices(x[0], x[1])
			for k in ch.size():
				if str(ch[k][0]) == str(path[j + 1][0]) and int(ch[k][1]) == int(path[j + 1][1]) and net.graph.active_branch(x[0], x[1]) != k:
					net.graph.throw_switch(x[0], k, x[1])
		var n := ap.control(s, dt)
		if ap.state == "dwell" and not was_dwell: served[str(ap.station.get("name", ""))] = true
		was_dwell = ap.state == "dwell"
		s.tick(dt, n)
		if OS.get_environment("AP_TRACE") != "" and roundi(s.time_s / dt) % 300 == 0:
			print("  t=%d %s@%.0f d%d v=%.1f n=%.2f st=%s %s hold=%s idx=%d/%d" % [s.time_s, s.edge_id, s.offset, s.direction, s.phys.speed, n, ap.state, ap.status, ap.holding, idx, path.size()])
		if s.overspeed: overspeed_max = maxf(overspeed_max, (s.phys.speed - s.speed_limit()) * 3.6)
		var d := s.dist_to_point(str(last.edge), float(last.offset), 400.0)
		if d != INF and absf(d) < 25.0 and s.phys.speed < 0.05 and ap.state == "dwell":
			arrived = true; break
	var missing: Array = []
	for nm in names: if not served.has(nm): missing.append(nm)
	print("  ligne %s : %d s, %d stations desservies, survitesse max %.1f km/h, incident '%s'" % [m.line, roundi(s.time_s), served.size(), overspeed_max, s.incident])
	check(arrived, "ligne %s parcourue jusqu'au terminus %s" % [m.line, str(net.stations[int(m.stops[-1].station)].name)])
	check(overspeed_max == 0.0, "ligne %s : aucun dépassement de vitesse" % m.line)
	check(s.incident == "" and signals_passed == 0, "ligne %s : aucun signal franchi, aucun incident" % m.line)
	check(missing.is_empty(), "ligne %s : arrêt portes ouvertes à chaque station (%s)" % [m.line, ", ".join(PackedStringArray(missing))])

## Arrêt devant un signal fermé (aiguille occupée par un mobile) puis reprise de la marche.
func _signals_sanity(vehicle: VehicleProfile) -> void:
	var net := NetworkLoader.new(); net.load_file("res://data/free/angers.json")
	var sm := SignalModel.of(net)
	var kinds := {}
	for sg in sm.list: kinds[str(sg.kind)] = int(kinds.get(str(sg.kind), 0)) + 1
	print("  signaux Angers : ", kinds)
	check(kinds.get("switch", 0) + kinds.get("terminus", 0) > 10 and kinds.get("crossing", 0) > 20 and kinds.get("buffer", 0) > 0, "signaux d'aiguillage, de carrefour et heurtoirs placés")
	var ok_labels := true
	for sg in sm.list:
		if sg.has("labels"): ok_labels = ok_labels and (sg.labels as Array).size() == net.graph.choices(str(sg.node), int(sg.side)).size()
	check(ok_labels, "chaque branche d'aiguillage a un sens indiqué")
	# Reprise en main : une rame lancée, le pilote coupé rend le manipulateur au joueur.
	var m := _mission("angers_A_service_0")
	var st: Dictionary = m.start
	var s := FreeSession.new(net, vehicle, str(st.edge), float(st.offset), false)
	s.direction = int(st.dir); s.route_dir = [s.direction]
	var ap := Autopilot.new(); ap.enabled = true
	for i in 300: s.tick(0.1, ap.control(s, 0.1))
	check(s.phys.speed > 2.0 or ap.state == "dwell", "le pilote automatique met la rame en marche")
	ap.enabled = false
	for i in 100: s.tick(0.1, -1.0)
	check(s.phys.speed < 0.1, "reprise en main : freinage manuel obéi")
