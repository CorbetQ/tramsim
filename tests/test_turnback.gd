extends SceneTree
## Retournement en mode libre : refusé en pleine voie, possible aux arrêts de retournement.
var fails := 0
func check(c: bool, m: String) -> void:
	if not c: fails += 1; printerr("ECHEC: ", m)
	else: print("ok: ", m)

func _init() -> void:
	var net := NetworkLoader.new(); net.load_file("res://data/free/angers.json")
	check(net.meta.get("turnback_stations", []).size() > 0, "arrêts de retournement présents")
	# en pleine voie (station non terminus)
	var mid: Dictionary = {}
	for s in net.stations:
		if not s.get("turnback", false) and net.graph.edges[s.edge].length > 300.0: mid = s; break
	var f := FreeSession.new(net, VehicleLibrary.citadis_302(), mid.edge, float(mid.offset), false)
	check(f.reverse() != "", "retournement refusé loin d'un terminus")
	# à un terminus
	var term: Dictionary = {}
	for s in net.stations:
		if s.get("turnback", false) and float(s.offset) > 100.0: term = s; break
	var net2 := NetworkLoader.new(); net2.load_file("res://data/free/angers.json")
	var g := FreeSession.new(net2, VehicleLibrary.citadis_302(), term.edge, float(term.offset), false)
	var d0: Vector2 = net2.point_on(g.edge_id, g.offset).dir
	var err := g.reverse()
	check(err == "", "retournement au terminus " + str(term.name) + " " + err)
	var d1: Vector2 = net2.point_on(g.edge_id, g.offset).dir
	check(d0.dot(d1) < -0.5, "la rame repart dans l'autre sens")
	for i in 80: g.tick(0.1, 1.0)
	check(g.phys.speed > 1.0 and g.incident == "", "circulation après retournement")
	quit(1 if fails > 0 else 0)
