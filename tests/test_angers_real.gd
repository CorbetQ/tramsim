extends SceneTree
## Lignes réelles (GTFS Irigo) : chargement, géométrie, faisabilité d'une mission horaire au pilote automatique.
var fails := 0
func check(c: bool, m: String) -> void:
	if not c: fails += 1; printerr("ECHEC: ", m)
	else: print("ok: ", m)

func _init() -> void:
	var helper = preload("res://tests/autopilot.gd").new()
	for line in ["a", "b", "c"]:
		var net := NetworkLoader.new()
		var errs := net.load_file("res://data/networks/angers_%s.json" % line)
		check(errs.is_empty(), "ligne %s chargée %s" % [line.to_upper(), errs])
		check(net.has_geometry() and net.missions().size() > 0, "ligne %s : géométrie + missions" % line.to_upper())
		# continuité : on peut faire le tour complet (aller, rebroussement, retour)
		var e: String = net.missions()[0].start_edge
		var seen := {}
		while e != "" and not seen.has(e):
			seen[e] = true
			e = net.graph.next_edge(e)
		check(seen.size() == net.graph.edges.size(), "ligne %s : boucle aller/retour continue (%d/%d arêtes)" % [line.to_upper(), seen.size(), net.graph.edges.size()])
	# mission réelle ligne A (service de milieu de journée)
	var net := NetworkLoader.new(); net.load_file("res://data/networks/angers_a.json")
	var ms: Array = net.missions()
	var mi: Dictionary = ms[ms.size() / 2]
	var sched: Array[float] = []
	for t in mi.departures: sched.append(float(t))
	var m := MissionSession.new(net, VehicleLibrary.citadis_302_hybride(), mi.start_edge, float(mi.start_offset), sched, 60)
	m.set_mission_stops(mi.stops)
	m.traffic.set_enabled(false)
	helper._drive(m, 0.0, -1, 4000.0)
	var d := m.debrief()
	var counts := [0, 0, 0, 0]
	for s in d.stops: counts[s.result] += 1
	print("mission %s %s : %d arrêts, OK=%d avance=%d retard=%d oublié=%d, durée %.0f s (GTFS %d s) %s" % [mi.id, mi.start_time, d.stops.size(), counts[0], counts[1], counts[2], counts[3], d.time_s, mi.departures[-1], d.reason])
	check(m.finished and d.reason == "", "mission réelle ligne A menée au terminus sans faute de sécurité")
	check(counts[3] == 0 and counts[1] == 0, "aucun arrêt oublié ni départ anticipé")
	quit(1 if fails > 0 else 0)
