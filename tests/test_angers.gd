extends SceneTree
## godot --headless --path . -s tests/test_angers.gd
var fails := 0
func check(c: bool, m: String) -> void:
	if not c: fails += 1; printerr("ECHEC: ", m)
	else: print("ok: ", m)

func _new(delay: float = 0.0, pax: int = 40) -> MissionSession:
	var net := NetworkLoader.new()
	var errs := net.load_file("res://data/networks/angers_a.json")
	assert(errs.is_empty(), str(errs))
	var sched: Array[float] = [120.0 + delay, 260.0, 470.0, 610.0]
	return MissionSession.new(net, VehicleLibrary.citadis_302(), "e0", 100.0, sched, pax)

## Pilote automatique : s'arrête à chaque station, ouvre/ferme les portes.
func _drive(m: MissionSession, hold_s: float = 0.0, skip_stop: int = -1, max_t: float = 1500.0) -> void:
	_dt_state = 0.0
	while not m.finished and m.time_s < max_t:
		_drive_step(m, hold_s, skip_stop)

var _dt_state := 0.0
func _drive_step(m: MissionSession, hold_s: float = 0.0, skip_stop: int = -1) -> void:
	var dt := 0.1
	var door_timer := _dt_state
	if true:
		var i := m.next_station
		var notch := 0.0
		var st: Dictionary = m.net.stations[i] if i < m.net.stations.size() else {}
		if not st.is_empty():
			var dist := _dist_to(m, st)
			var v := m.phys.speed
			var vmax := minf(m.speed_limit() - 1.0, sqrt(maxf(0.0, 2.0 * 0.6 * (dist - 1.0))))
			if i == skip_stop: vmax = m.speed_limit() - 1.0
			notch = 1.0 if v < vmax - 0.3 else (-1.0 if v > vmax + 0.3 else 0.0)
			if dist < 2.5 and dist > -4.0 and i != skip_stop: notch = -1.0
			if v < 0.05 and absf(dist) < 4.0 and i != skip_stop:
				if not m.doors_open and not m.served:
					m.set_doors(true); door_timer = 0.0
				elif m.doors_open:
					door_timer += dt
					if door_timer > maxf(m.dwell_left, 0.0) and m.time_s >= m.schedule[i] + 3.0 + hold_s and door_timer > 5.0:
						m.set_doors(false)
				elif m.served:
					notch = 1.0
			if m.served and not m.doors_open: notch = 1.0
		m.tick(dt, notch)
		_dt_state = door_timer

func _dist_to(m: MissionSession, st: Dictionary) -> float:
	var d := 0.0
	var e := m.edge_id
	if e == st.edge: return float(st.offset) - m.offset
	d = m.net.graph.edges[e].length - m.offset
	while true:
		e = m.net.graph.next_edge(e)
		if e == "": return 1e9
		if e == st.edge: return d + float(st.offset)
		d += m.net.graph.edges[e].length
	return 1e9

func _init() -> void:
	var net := NetworkLoader.new()
	check(net.load_file("res://data/networks/angers_a.json").is_empty(), "réseau valide")
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
	var e3 := 0
	while not m3.finished and m3.time_s < 900: m3.tick(0.1, 1.0)
	check(m3.scorer.fail_reason == "Fin de voie dépassée", "fin de voie dépassée => échec")
	# signal d'arrêt
	var m4 := _new()
	m4.signal_state[0] = "stop"
	while not m4.finished and m4.time_s < 900: m4.tick(0.1, 1.0)
	check(m4.scorer.fail_reason == "Signal d'arrêt franchi", "signal d'arrêt franchi => échec")
	# collision par occupation
	var m5 := _new()
	m5.net.graph.occupy("e1", "AUTRE")
	while not m5.finished and m5.time_s < 900: m5.tick(0.1, 1.0)
	check(m5.scorer.fail_reason == "Collision", "section occupée => collision")
	# aiguillage vers le dépôt (N1 : e1 ou dep)
	var m6 := _new()
	check(not m6.net.graph.throw_switch("N1", 1), "aiguillage refusé : rame sur la section d'approche")
	var net6 := NetworkLoader.new(); net6.load_file("res://data/networks/angers_a.json")
	check(net6.graph.throw_switch("N1", 1) and net6.graph.next_edge("e0") == "dep", "aiguillage libre vers dépôt")
	# portes interdites en marche
	var m8 := _new(); m8.phys.speed = 5.0; m8.set_doors(true)
	check(not m8.doors_open, "portes refusées en marche")
	# charge évolue à l'arrêt
	var m9 := _new(); m9.phys.speed = 0.0; m9.edge_id = "e0"; m9.offset = 850.0
	var p0 := m9.phys.passengers; m9.set_doors(true)
	for i in 100: m9.tick(0.1, 0.0)
	check(m9.phys.passengers != p0, "montée/descente modifie la charge")
	quit(1 if fails > 0 else 0)
