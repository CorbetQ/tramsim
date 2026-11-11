extends SceneTree
## Joue une mission réelle (service du milieu de la liste) sur CHAQUE réseau livré, au pilote automatique.
## Sortie : une ligne "RESULT|id|arrêts|ok|avance|retard|oublié|durée|durée_gtfs|faute" par réseau.
func _init() -> void:
	var ap = preload("res://tests/autopilot.gd").new()
	var dir := "res://data/networks"
	var only: Array = OS.get_cmdline_user_args()
	var bad := 0
	var files := DirAccess.get_files_at(dir)
	for f in files:
		if not f.ends_with(".json"): continue
		if only.size() > 0 and not f.get_basename() in only: continue
		var net := NetworkLoader.new()
		var errs := net.load_file(dir + "/" + f)
		if not errs.is_empty():
			print("RESULT|%s|chargement|%s" % [f, errs]); bad += 1; continue
		var ms: Array = net.missions()
		if ms.is_empty():
			print("RESULT|%s|sans mission" % f); bad += 1; continue
		var mi: Dictionary = ms[ms.size() / 2]
		var v := VehicleLibrary.default_for(net.meta)
		var sched: Array[float] = []
		for t in mi.departures: sched.append(float(t))
		var m := MissionSession.new(net, v, mi.start_edge, float(mi.start_offset), sched, 60)
		m.set_mission_stops(mi.stops)
		m.traffic.set_enabled(false)
		ap._dt_state = 0.0
		ap._drive(m, 0.0, -1, float(mi.departures[-1]) + 1800.0)
		var d := m.debrief()
		var c := [0, 0, 0, 0]
		for s in d.stops: c[s.result] += 1
		var ok: bool = m.finished and d.reason == "" and c[1] == 0 and c[3] == 0 and d.stops.size() == mi.stops.size()
		if not ok: bad += 1
		print("RESULT|%s|%d|%d|%d|%d|%d|%d|%d|%s" % [f.get_basename(), mi.stops.size(), c[0], c[1], c[2], c[3], int(d.time_s), int(mi.departures[-1]), d.reason])
	print("TOTAL_ECHECS|%d" % bad)
	quit(0)
