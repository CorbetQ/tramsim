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
	_random_routes(vehicle)
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
	var last_n := -0.75; var last_sign := -1.0; var last_sign_t := 0.0
	var changes := 0; var inversions := 0
	var used := {}
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
		if not is_equal_approx(n, last_n):
			changes += 1
			if signf(n) != 0.0 and last_sign != 0.0 and signf(n) != last_sign and s.time_s - last_sign_t < 1.0: inversions += 1
			last_n = n
		if signf(n) != 0.0:
			if signf(n) != last_sign: last_sign = signf(n)
			last_sign_t = s.time_s
		used[roundi(n * 4.0)] = true
		if ap.state == "dwell" and not was_dwell: served[str(ap.station.get("name", ""))] = true
		if OS.get_environment("AP_TRACE") != "" and names.has(str(ap.station.get("name", ""))) and not served.has(str(ap.station.get("name", ""))) and str(ap.station.get("name", "")) == "Centre de Congrès" and Autopilot.stop_distance(s, ap.station) < 8.0: print("  quai ? %s v=%.1f n=%.2f d=%.1f %s@%.1f in=%s hold=%s g=%.3f slide=%s adh=%.2f st=%s" % [ap.station.name, s.phys.speed, n, Autopilot.stop_distance(s, ap.station), s.edge_id, s.offset, net.station_contains(ap.station, s.edge_id, s.offset), ap.holding, net.grade_at(s.edge_id, s.offset) * s.direction, s.phys.wheel_slide, s.phys.adhesion, ap.state])
		was_dwell = ap.state == "dwell"
		s.tick(dt, n)
		if OS.get_environment("AP_TRACE") != "" and roundi(s.time_s / dt) % 300 == 0:
			print("  t=%d %s@%.0f d%d v=%.1f n=%.2f st=%s %s hold=%s idx=%d/%d" % [s.time_s, s.edge_id, s.offset, s.direction, s.phys.speed, n, ap.state, ap.status, ap.holding, idx, path.size()])
		if s.overspeed:
			if OS.get_environment("AP_TRACE") != "" and (s.phys.speed - s.speed_limit()) * 3.6 > overspeed_max + 1.0: print("  survitesse t=%d %s@%.0f v=%.1f lim=%.1f n=%.2f %s" % [s.time_s, s.edge_id, s.offset, s.phys.speed * 3.6, s.speed_limit() * 3.6, n, ap.status])
			overspeed_max = maxf(overspeed_max, (s.phys.speed - s.speed_limit()) * 3.6)
		var d := s.dist_to_point(str(last.edge), float(last.offset), 400.0)
		if d != INF and absf(d) < 25.0 and s.phys.speed < 0.05 and ap.state == "dwell":
			arrived = true; break
	var missing: Array = []
	for nm in names: if not served.has(nm): missing.append(nm)
	print("  ligne %s : %d s, %d stations desservies, survitesse max %.1f km/h, incident '%s'" % [m.line, roundi(s.time_s), served.size(), overspeed_max, s.incident])
	check(arrived, "ligne %s parcourue jusqu'au terminus %s" % [m.line, str(net.stations[int(m.stops[-1].station)].name)])
	check(overspeed_max == 0.0, "ligne %s : aucun dépassement de vitesse" % m.line)
	check(s.incident == "" and signals_passed == 0, "ligne %s : aucun signal franchi, aucun incident" % m.line)
	var tr := 0; var br := 0
	for k in used:
		if int(k) > 0: tr += 1
		elif int(k) < 0: br += 1
	var per_min := changes / maxf(s.time_s / 60.0, 1.0)
	print("  ligne %s : %.1f changements de cran / min, %d inversions < 1 s, crans traction %d freinage %d, commutations %s" % [m.line, per_min, inversions, tr, br, str(ap.power_switches)])
	check(per_min < 22.0, "ligne %s : manipulateur calme (%.1f crans / min)" % [m.line, per_min])
	check(inversions == 0, "ligne %s : aucune inversion traction / freinage en moins de 1 s" % m.line)
	check(tr >= 3 and br >= 2, "ligne %s : paliers variés (%d traction, %d freinage)" % [m.line, tr, br])
	var aps_ok := true
	for sw in ap.power_switches: aps_ok = aps_ok and float(sw.speed) < 0.1 and bool(sw.in_station)
	if m.line == "A": check(not ap.power_switches.is_empty() and aps_ok, "ligne A : bascule APS / LAC faite à quai (%d)" % ap.power_switches.size())
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

## Itinéraires aléatoires (mode libre) : le pilote positionne les aiguilles au hasard, se retourne
## aux terminus et ne reste jamais bloqué.
func _random_routes(vehicle: VehicleProfile) -> void:
	var net := NetworkLoader.new(); net.load_file("res://data/free/angers.json")
	var m := _mission("angers_B_service_1")
	var st: Dictionary = m.start
	var s := FreeSession.new(net, vehicle, str(st.edge), float(st.offset), false)
	s.direction = int(st.dir); s.route_dir = [s.direction]; s.update_spans()
	var ap := Autopilot.new(); ap.enabled = true; ap.random_routes = true; ap.rng.seed = 7
	var edges := {}
	var still := 0.0; var still_max := 0.0
	var reversals := 0
	s.event.connect(func(kind, _t): if kind == "reverse": reversals += 1)
	while s.time_s < 2400.0 and s.incident == "":
		s.tick(0.1, ap.control(s, 0.1))
		edges[s.edge_id] = true
		still = still + 0.1 if s.phys.speed < 0.05 and ap.state != "dwell" else 0.0
		if still > 90.0 and still_max <= 90.0: print("  bloqué %s@%.0f d%d %s hold=%s power=%s %s %s" % [s.edge_id, s.offset, s.direction, ap.status, ap.holding, s.power_ok, s.power_mode, net.supplies_at(s.edge_id, s.offset)])
		still_max = maxf(still_max, still)
	print("  aléatoire : %d sections, %d retournements, immobilisation max %d s, incident '%s'" % [edges.size(), reversals, roundi(still_max), s.incident])
	check(s.incident == "" and edges.size() > 40 and still_max < 90.0, "itinéraires aléatoires : %d sections parcourues sans blocage" % edges.size())
