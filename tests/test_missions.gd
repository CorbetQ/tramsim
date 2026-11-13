extends SceneTree
## Missions sur réseau complet : catalogue par ville, poste d'aiguillage (itinéraire réservé,
## aiguillages verrouillés, signaux, libération), refus de manœuvre manuelle, événements,
## réussite et échec de chaque type de mission sur au moins deux villes.

var failures := 0
func check(ok: bool, message: String) -> void:
	if ok: print("ok: ", message)
	else: failures += 1; printerr("ECHEC: ", message)

const CITIES := ["angers", "marseille", "caen", "saintetienne"]

## Conducteur automatique : courbe de freinage vers le prochain point d'arrêt (quai, cible,
## point de retournement, fin d'autorisation, obstacle), portes, pantographe, sablage.
func drive(s: MissionSession, opts: Dictionary = {}) -> void:
	var dt := 0.1
	var door_t := 0.0
	var max_t := float(opts.get("max_t", 4000.0))
	var powered_once := false
	while not s.finished and s.time_s < max_t:
		var v := s.phys.speed
		var goal := INF
		var stop_dist := INF
		var st: Dictionary = s.stops[s.next_station] if s.next_station < s.stops.size() else {}
		if not st.is_empty() and not s.served:
			stop_dist = s.dist_to_point(str(st.edge), float(st.offset), 3000.0)
			if stop_dist != INF and stop_dist > -4.0: goal = stop_dist
		elif s.served and s.next_station + 1 < s.stops.size():
			var nx: Dictionary = s.stops[s.next_station + 1]
			var dn := s.dist_to_point(str(nx.edge), float(nx.offset), 3000.0)
			if dn != INF and dn > 5.0: goal = dn
		elif st.is_empty() and not s.target.is_empty():
			var dtg := s.dist_to_point(str(s.target.edge), float(s.target.offset), 3000.0)
			if dtg != INF: goal = dtg
		var il := s.interlocking
		if il.awaiting_reverse() and (st.is_empty() or s.served or stop_dist == INF):
			var dr := s.dist_to_point(str(il.leg_end.edge), float(il.leg_end.offset), 3000.0)
			if dr != INF: goal = minf(goal, dr)
		if not il.authority.is_empty():
			var da := s.dist_to_point(str(il.authority.edge), float(il.authority.offset), 3000.0)
			if da != INF: goal = minf(goal, da - 3.0)
		if not bool(opts.get("ignore_obstacle", false)):
			for ob in s.events.of_kind("obstacle"):
				if str(ob.state) != "cleared":
					var d := s.dist_to_point(str(ob.edge), float(ob.offset), 600.0)
					if d != INF and d > 0.0: goal = minf(goal, d - 40.0)
		var dec := 0.35 if not s.events.of_kind("leaves").is_empty() else 0.6
		dec = clampf(dec + 9.81 * minf(s.net.grade_at(s.edge_id, s.offset) * s.direction, 0.0), 0.15, dec)
		var lim := s.speed_limit()
		if not bool(opts.get("flood_fast", false)):
			for rest in [s.next_restriction(400.0), s.events.next_restriction(s, 400.0)]:
				if not rest.is_empty(): lim = minf(lim, sqrt(pow(float(rest.limit), 2) + 2.0 * dec * maxf(float(rest.distance) - 5.0, 0.0)))
		else: lim = maxf(lim, 8.0) if s.speed_limit() < 3.0 else lim
		var vmax := minf(lim - 0.6, sqrt(maxf(0.0, 2.0 * dec * (goal - 1.0)))) if goal != INF else lim - 0.6
		var notch := 1.0 if v < vmax - 0.3 else (-1.0 if v > vmax + 0.3 else 0.0)
		if goal != INF and goal < 2.0: notch = -1.0
		# Mise sous tension / réarmement du pantographe.
		if not s.pantograph_up and v < 0.1 and s.power_mode == "overhead" and s.power_transition_left <= 0.0:
			var fault := false
			for f in s.events.of_kind("pantograph_fault"): fault = fault or str(f.state) == "fault"
			if not fault: s.set_power_mode("overhead")
		if not s.power_ok and v < 0.1 and s.power_transition_left <= 0.0 and s.pantograph_up == (s.power_mode == "overhead"):
			var here := s.events.filter_supplies(s, s.net.supplies_at(s.edge_id, s.offset))
			for mode in s.available_power_modes():
				if mode in here and mode != s.power_mode: s.set_power_mode(mode); break
		s.set_sanding(s.phys.adhesion < 0.1 and (notch < 0.0 or s.phys.wheel_slip))
		# Retournement.
		if il.awaiting_reverse() and il.can_reverse(s): s.reverse()
		# Desserte.
		if not st.is_empty():
			var at_platform := not s._station_here().is_empty()
			if v < 0.05 and at_platform and (stop_dist == INF or absf(stop_dist) < 6.0 or s.served):
				if not s.doors_open and not s.served:
					s.set_doors(true); door_t = 0.0
				elif s.doors_open:
					door_t += dt
					var free_time := bool(st.get("free_time", false))
					var ready: bool = door_t > maxf(s.dwell_left, 5.0) and (free_time or s.time_s >= s.schedule[s.next_station] + 2.0)
					if bool(st.get("alight_all", false)) and s.phys.passengers > 0 and not bool(opts.get("leave_with_pax", false)): ready = false
					if bool(opts.get("leave_with_pax", false)) and bool(st.get("alight_all", false)) and door_t > 1.0: ready = true
					if ready: s.set_doors(false)
			if s.served and not s.doors_open: notch = 1.0 if v < vmax else notch
			elif s.doors_open: notch = -0.75
		if OS.get_environment("MISSION_TRACE") != "" and roundi(s.time_s / dt) % 200 == 0:
			print("  t=%d %s@%.1f d%d v=%.1f lim=%.1f goal=%.1f next=%s served=%s doors=%s pow=%s pax=%d il=%d/%d auth=%s err=%s" % [s.time_s, s.edge_id, s.offset, s.direction, v, s.speed_limit(), goal, str(st.get("name", "-")), s.served, s.doors_open, s.power_ok, s.phys.passengers, il.pos, il.path.size(), str(il.authority), il.error])
		s.tick(dt, notch)
		if opts.has("stats"): opts.stats["min_adhesion"] = minf(float(opts.stats.get("min_adhesion", 1.0)), s.phys.adhesion)

func pick(list: Array, kind: String) -> Dictionary:
	for m in list: if str(m.type) == kind: return m
	return {}

func _init() -> void:
	var vehicle := VehicleLibrary.citadis_302_hybride()
	# --- Contrat d'API du catalogue
	var per_city := {}
	for c in CITIES:
		var list := MissionCatalog.for_city(c)
		if not list.is_empty(): per_city[c] = list
	check(per_city.size() >= 2, "catalogue de missions pour plusieurs villes (%d)" % per_city.size())
	var ok_contract := true
	for c in per_city:
		for m in per_city[c]:
			for k in ["id", "type", "title", "description", "line", "difficulty", "duration_min", "start_station", "conditions"]:
				ok_contract = ok_contract and m.has(k)
			ok_contract = ok_contract and int(m.difficulty) >= 1 and int(m.difficulty) <= 3 and typeof(m.conditions) == TYPE_ARRAY and str(m.type) in MissionCatalog.TYPES
	check(ok_contract, "missions : clés du contrat, difficulté 1-3, conditions en liste, types connus")
	check(MissionCatalog.for_city("ville_inexistante").is_empty(), "ville sans catalogue : aucune mission inventée")
	# Dépôts : uniquement ceux identifiés dans les données de la ville.
	var depot_ok := true
	for c in per_city:
		var raw = JSON.parse_string(FileAccess.get_file_as_string("res://data/free/%s.json" % c))
		var names: Array = raw.get("depots", []).map(func(d): return str(d.name))
		for m in per_city[c]:
			if str(m.type) in ["depot_exit", "depot_return"]: depot_ok = depot_ok and str(m.get("depot", "")) in names
	check(depot_ok, "missions de dépôt : dépôts identifiés à l'import uniquement")
	# --- Chaque type sur au moins deux villes
	var tested := {}
	var only := OS.get_environment("MISSION_ONLY")
	if only != "":
		for c in per_city:
			for m in per_city[c]:
				if str(m.id) == only: _run_type(m, vehicle, c)
		print("TOTAL_ECHECS|", failures); quit(); return
	for kind in MissionCatalog.TYPES:
		var cities_done := 0
		for c in per_city:
			if cities_done >= 2: break
			var m := pick(per_city[c], kind)
			if m.is_empty(): continue
			cities_done += 1
			_run_type(m, vehicle, c)
		tested[kind] = cities_done
		check(cities_done >= 2, "type %s : testé sur %d villes" % [kind, cities_done])
	# --- Échecs ciblés
	_failures(per_city, vehicle)
	print("TOTAL_ECHECS|", failures)
	quit(1 if failures else 0)

func _run_type(m: Dictionary, vehicle: VehicleProfile, city: String) -> void:
	var tag := "%s/%s" % [city, str(m.id)]
	var s := MissionCatalog.create_session(m, vehicle)
	check(s != null and s.net.graph.edges.size() > 50, tag + " : session créée sur le réseau complet")
	if s == null: return
	check(s.locked_switches() and not s is FreeSession, tag + " : aiguillages verrouillés en mission")
	check(s.interlocking.error == "" and s.interlocking.path.size() >= 1, tag + " : itinéraire tracé par le poste")
	var locked := s.interlocking.locked_switch_list()
	if not locked.is_empty():
		var key: String = locked[0]
		var node := key.trim_suffix("#-1"); var side := -1 if key.ends_with("#-1") else 1
		var before := s.net.graph.active_branch(node, side)
		var n := s.net.graph.choices(node, side).size()
		check(not s.select_branch(node, (before + 1) % n, side) and not s.net.graph.throw_switch(node, (before + 1) % n, side) and s.net.graph.active_branch(node, side) == before,
			tag + " : manœuvre manuelle refusée, aiguillage maintenu")
	var brief := s.mission_brief()
	check(not brief.objectives.is_empty() and brief.status == "en cours" and brief.locked_switches, tag + " : fiche de mission avec objectifs")
	var t0 := Time.get_ticks_msec()
	var stats := {}
	drive(s, {"stats": stats})
	var res := s.debrief()
	print("   ", tag, " ", Time.get_ticks_msec() - t0, " ms, t=", roundi(s.time_s), " s")
	check(res.success and int(res.stars) >= 1, tag + " : mission réussie (score %s, %s)%s" % [str(res.get("score")), str(res.reason), "" if res.success else " " + str(res.objectives.filter(func(o): return not o.done or o.failed).map(func(o): return o.id)) + " t=%d %s" % [roundi(s.time_s), str(res.stops.map(func(x): return x.result))]])
	check(s.net.graph.locks.size() <= 4, tag + " : aiguillages libérés derrière la rame (%d restants)" % s.net.graph.locks.size())
	match str(m.type):
		"depot_exit": check(s.achieved.has("powered"), tag + " : mise sous tension réalisée")
		"depot_return": check(s.achieved.has("alighted") and s.achieved.has("target"), tag + " : voyageurs débarqués et rame remisée")
		"turnback": check(s.interlocking.legs_done >= 1, tag + " : changement de cabine au point de retournement")
		"flood": if not s.events.of_kind("flood").is_empty(): check(s.events.flags.has("flood_crossed"), tag + " : zone inondée franchie à vue")
		"leaves": check(float(stats.get("min_adhesion", 1.0)) <= 0.08, tag + " : adhérence réduite (feuilles) appliquée sous la rame")
		"pantograph_fault": check(s.events.flags.has("fault_cleared"), tag + " : défaut pantographe traité")
		"power_cut": check(s.events.flags.has("power_restored") or s.events.of_kind("power_cut")[0].state == "pending", tag + " : coupure traitée")
		"obstacle": check(s.events.flags.has("obstacle_cleared"), tag + " : arrêt avant le véhicule puis dégagement")
		"deviation": check(not s.events.skipped_stops().is_empty() and not s.interlocking.closed.is_empty(), tag + " : section fermée et arrêts non desservis")

func _failures(per_city: Dictionary, vehicle: VehicleProfile) -> void:
	var done := {}
	for c in per_city:
		# Signal fermé : une autre rame occupe l'itinéraire, le poste arrête le tracé avant elle.
		var m := pick(per_city[c], "service")
		if not m.is_empty() and not done.has("signal"):
			var s := MissionCatalog.create_session(m, vehicle)
			var il := s.interlocking
			var far := -1
			var acc := 0.0
			for i in range(1, il.path.size()):
				acc += s.net.graph.edges[str(il.path[i][0])].length
				if acc > 900.0 and s.net.graph.edges[str(il.path[i][0])].occupied_by == "": far = i; break
			if far > 0:
				s.net.graph.occupy(str(il.path[far][0]), "T2")
				for k in 600: s.tick(0.1, 1.0)
				var stopped_before := s.finished and s.scorer.fail_reason.contains("Signal")
				check(stopped_before and s.edge_id != str(il.path[far][0]), c + " : autre rame sur l'itinéraire → signal fermé, franchissement = échec (" + s.scorer.fail_reason + ")")
				done["signal"] = true
		# Inondation traversée trop vite.
		m = pick(per_city[c], "flood")
		if not m.is_empty() and m.get("closed", []).is_empty() and not done.has("flood"):
			var s := MissionCatalog.create_session(m, vehicle)
			drive(s, {"flood_fast": true, "max_t": 1500.0})
			check(not s.debrief().success, c + " : inondation franchie au-delà de la marche à vue → échec (" + s.scorer.fail_reason + ")")
			done["flood"] = true
		# Véhicule sur la voie ignoré : collision.
		m = pick(per_city[c], "obstacle")
		if not m.is_empty() and not done.has("obstacle"):
			var s := MissionCatalog.create_session(m, vehicle)
			drive(s, {"ignore_obstacle": true, "max_t": 1500.0})
			check(not s.debrief().success and s.scorer.fail_reason.contains("véhicule"), c + " : obstacle ignoré → collision, échec")
			done["obstacle"] = true
		# Rentrée au dépôt avec voyageurs à bord.
		m = pick(per_city[c], "depot_return")
		if not m.is_empty() and not done.has("pax"):
			var s := MissionCatalog.create_session(m, vehicle)
			drive(s, {"leave_with_pax": true, "max_t": 600.0})
			check(not s.debrief().success and s.scorer.fail_reason.contains("voyageurs"), c + " : départ du terminus avec voyageurs → échec")
			done["pax"] = true
		# Changement de cabine hors du point de retournement : refusé.
		m = pick(per_city[c], "turnback")
		if not m.is_empty() and not done.has("reverse"):
			var s := MissionCatalog.create_session(m, vehicle)
			check(s.reverse() != "" and s.interlocking.legs_done == 0, c + " : changement de cabine refusé hors du point de retournement")
			done["reverse"] = true
		# Feuilles mortes : enrayage et distance de freinage allongée.
		m = pick(per_city[c], "leaves")
		if not m.is_empty() and not done.has("leaves"):
			var s := MissionCatalog.create_session(m, vehicle)
			var dry := TrainPhysics.new(vehicle); dry.velocity = 12.0
			var wet := TrainPhysics.new(vehicle); wet.velocity = 12.0; wet.adhesion = 0.07
			var sand := TrainPhysics.new(vehicle); sand.velocity = 12.0; sand.adhesion = 0.07; sand.sanding = true
			var slid := false
			for k in 400:
				dry.step(0.05, -1.0, 0.0); wet.step(0.05, -1.0, 0.0); sand.step(0.05, -1.0, 0.0); slid = slid or wet.wheel_slide
			check(slid and wet.position > dry.position * 1.4 and sand.position < wet.position, c + " : rail gras → enrayage, freinage allongé ; sablage efficace")
			check(s.sand_left_s > 0.0 and s.set_sanding(true), c + " : sablage disponible en mission feuilles mortes")
			done["leaves"] = true
		# Délai dépassé (sortie de dépôt sans conduire).
		m = pick(per_city[c], "depot_exit")
		if not m.is_empty() and not done.has("time"):
			var s := MissionCatalog.create_session(m, vehicle)
			check(not s.pantograph_up and not s.power_ok, c + " : sortie de dépôt pantographe abaissé, rame hors tension")
			while not s.finished and s.time_s < float(m.time_limit_s) + 5.0: s.tick(0.5, -1.0)
			check(s.finished and not s.debrief().success and s.mission_brief().status == "échouée", c + " : délai dépassé → échec")
			done["time"] = true
	for k in ["signal", "flood", "obstacle", "pax", "reverse", "leaves", "time"]:
		check(done.has(k), "scénario d'échec couvert : " + k)
