extends SceneTree
## Retournement en mode libre : heurtoir après le quai (plus de boucle artificielle), communication de voies
## avant le quai, changement de cabine à l'arrêt puis passage de la communication vers la voie opposée.
var fails := 0
func check(c: bool, m: String) -> void:
	if not c: fails += 1; printerr("ECHEC: ", m)
	else: print("ok: ", m)

func _init() -> void:
	var net := NetworkLoader.new(); net.load_file("res://data/free/angers.json")
	check(net.meta.get("turnback_stations", []).size() > 0, "arrêts de retournement présents")
	var xs: Array = net.meta.get("crossovers", [])
	check(xs.size() > 0, "communications de voies présentes")
	var loops := 0
	for e in net.meta.edges:
		if str(e.id).ends_with("_appr") and not str(e.from).ends_with("_pre"): loops += 1
	check(loops == 0, "plus de boucle artificielle aux terminus")
	var sw := {}
	for x in net.graph.switches(): sw[x[0]] = true
	var all_sw := true
	for c in xs:
		for n in c.nodes: all_sw = all_sw and sw.has(n)
	check(all_sw, "chaque nœud de communication est un aiguillage")
	# terminus : quai en impasse, communication avant le quai
	var c0: Dictionary = {}
	for c in xs:
		if c.station == "Roseraie": c0 = c
	var term: Dictionary = {}
	for s in net.stations:
		if s.name == "Roseraie" and net.graph.next_step(s.edge, 1).is_empty(): term = s
	check(not term.is_empty() and not c0.is_empty(), "terminus Roseraie en impasse (heurtoir après le quai)")
	var g := FreeSession.new(net, VehicleLibrary.citadis_302(), term.edge, float(term.offset), false)
	g.phys.speed = 3.0
	check(g.reverse() != "", "changement de cabine refusé en marche")
	g.phys.speed = 0.0
	var d0: Vector2 = net.point_on(g.edge_id, g.offset).dir * g.direction
	var err := g.reverse()
	check(err == "" and g.direction == -1, "changement de cabine au terminus " + err)
	var d1: Vector2 = net.point_on(g.edge_id, g.offset).dir * g.direction
	check(d0.dot(d1) < -0.5, "la rame repart dans l'autre sens")
	# itinéraire : communication vers la voie opposée (aiguillage pris en pointe en marche arrière)
	var x2: String = c0.nodes[1]
	var k := -1
	var ch: Array = net.graph.choices(x2, -1)
	for j in ch.size():
		if ch[j][0] == c0.edges[1]: k = j
	check(k >= 0 and g.select_branch(x2, k, -1), "aiguillage de communication manœuvré")
	var on_diag := false
	for i in 900:
		g.tick(0.1, 0.6 if g.phys.speed < 6.0 else 0.0)
		on_diag = on_diag or g.edge_id == c0.edges[1]
		if g.edge_id.begins_with("angers_a:av0_0_1|") and g.direction == 1 and g.offset > 60.0: break
	check(on_diag and g.incident == "", "communication franchie sans incident")
	check(g.edge_id.begins_with("angers_a:av0_0_1|") and g.direction == 1, "rame sur la voie opposée, sens normal")
	check(g.phys.speed > 1.0, "circulation après retournement")
	quit(1 if fails > 0 else 0)
