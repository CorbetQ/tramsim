extends SceneTree
## Circulation bidirectionnelle : marche arrière sur une voie, communication de voies (ciseaux),
## verrouillage des aiguillages occupés, changement de cabine sans changement de voie.
## godot --headless --path . -s tests/test_bidir.gd
var fails := 0
func check(c: bool, m: String) -> void:
	if not c: fails += 1; printerr("ECHEC: ", m)
	else: print("ok: ", m)

## Deux voies de sens opposés (A : NA0 -> NA3, B : NB0 -> NB3) et un croisement en ciseaux au milieu :
## d1 NA1 -> NB1 et d2 NB2 -> NA2 (NA1 face à NB2, NA2 face à NB1).
func _net() -> NetworkLoader:
	var n := NetworkLoader.new()
	n.supplies = ["overhead"]
	var spec := [["a0", "NA0", "NA1", 300.0, 1, -1], ["a1", "NA1", "NA2", 30.0, 1, -1], ["a2", "NA2", "NA3", 300.0, 1, -1],
		["b0", "NB0", "NB1", 300.0, 1, -1], ["b1", "NB1", "NB2", 30.0, 1, -1], ["b2", "NB2", "NB3", 300.0, 1, -1],
		["d1", "NA1", "NB1", 30.2, 1, 1], ["d2", "NB2", "NA2", 30.2, -1, -1]]
	for e in spec:
		n.graph.add_edge(e[0], e[1], e[2], e[3], e[4], e[5])
		n.edge_info[e[0]] = {"limit_ms": 15.0, "zones": [], "grade": 0.0, "supply": "overhead", "pts": PackedVector2Array(), "raw": e[0].begins_with("d")}
	return n

func _run(f: FreeSession, until: Callable, max_s: float = 200.0) -> void:
	var t := 0.0
	while t < max_s and f.incident == "" and not until.call():
		f.tick(0.1, 0.5 if f.phys.speed < 5.0 else 0.0); t += 0.1

func _init() -> void:
	var cit := VehicleLibrary.citadis_302()
	# graphe : côtés et choix d'itinéraire
	var g := _net().graph
	check(g.next_edge("a0") == "a1" and g.next_step("a2", -1) == ["a1", -1], "suite par défaut dans les deux sens")
	check(g.choices("NA1", 1).size() == 2 and g.choices("NA2", -1).size() == 2, "aiguillages de communication par côté d'approche")
	check(g.next_step("d1", 1) == ["b0", -1] and g.next_step("d2", -1) == ["b2", 1], "sortie de communication sans demi-tour")
	check(g.next_step("a2", 1).is_empty(), "fin de voie détectée")
	check(g.switches().size() == 4, "4 aiguillages dans le croisement en ciseaux")

	# 1. marche arrière sur une voie (après changement de cabine)
	var f := FreeSession.new(_net(), cit, "a2", 200.0, false)
	var L := cit.length_m
	check(f.reverse() == "" and f.direction == -1 and f.edge_id == "a2" and absf(f.offset - (200.0 - L)) < 0.01, "changement de cabine : la queue devient la tête")
	check(absf(f.dist_to_point("a0", 100.0) - (200.0 - L + 30.0 + 200.0)) < 0.5, "distance devant en marche arrière")
	var tail: Array = f.locate_behind(L)
	check(tail[0] == "a2" and absf(float(tail[1]) - 200.0) < 0.01, "queue derrière le nez dans le sens de marche")
	_run(f, func(): return f.edge_id == "a0" and f.offset < 150.0)
	check(f.incident == "" and f.edge_id == "a0" and f.direction == -1, "marche arrière sur la même voie jusqu'à a0")
	check(f.net.graph.edges["a2"].occupied_by == "", "sections libérées derrière la rame en marche arrière")
	check(f.next_station_ahead().is_empty(), "pas de station fantôme")

	# 2. changement de voie par la communication (aiguillage pris en pointe en marche arrière)
	var k := -1
	var ch := _net().graph.choices("NA2", -1)
	for j in ch.size():
		if ch[j][0] == "d2": k = j
	var h2 := FreeSession.new(_net(), cit, "a2", 120.0, false)
	check(h2.select_branch("NA2", k, -1), "aiguillage libre : rame hors de sa zone")
	h2.reverse()
	var seen_d2 := [false]
	_run(h2, func(): seen_d2[0] = seen_d2[0] or h2.edge_id == "d2"; return h2.edge_id == "b2" and h2.offset > 80.0)
	check(seen_d2[0] and h2.incident == "", "communication d2 franchie")
	check(h2.edge_id == "b2" and h2.direction == 1, "rame sur la voie B, sens normal")
	# 3. refus d'aiguillage occupé : rame engagée sur la communication
	var h4 := FreeSession.new(_net(), cit, "a2", 40.0, false)
	h4.reverse()
	check(not h4.select_branch("NA2", k, -1), "aiguillage refusé : rame arrêtée sur sa zone")
	var h5 := FreeSession.new(_net(), cit, "a2", 250.0, false)
	h5.reverse()
	check(h5.select_branch("NA2", k, -1), "aiguillage manœuvrable avant l'approche")
	_run(h5, func(): return h5.edge_id == "d2" and h5.offset < 15.0)
	check(h5.edge_id == "d2", "rame engagée sur la communication")
	check(not h5.select_branch("NA2", 0, -1) and not h5.select_branch("NB2", 1, 1), "aiguillages de la communication occupés : refus")
	check(h5.net.graph.active_branch("NA2", -1) == k, "état d'aiguillage inchangé après refus")
	# communication prise en pointe en marche avant : voie A -> voie B à contre-sens
	var fw := FreeSession.new(_net(), cit, "a0", 100.0, false)
	check(fw.select_branch("NA1", 1, 1), "aiguillage NA1 vers la communication")
	_run(fw, func(): return fw.edge_id == "b0" and fw.offset < 200.0)
	check(fw.incident == "" and fw.edge_id == "b0" and fw.direction == -1, "voie B parcourue à contre-sens après d1")

	# 4. changement de cabine sans changement de voie
	var c := FreeSession.new(_net(), cit, "a1", 20.0, false)
	_run(c, func(): return c.edge_id == "a2" and c.offset > 60.0)
	c.phys.speed = 0.0
	var e0 := c.edge_id; var o0 := c.offset; var r0: Array = c.route.duplicate()
	c.phys.speed = 2.0
	check(c.reverse() != "", "changement de cabine refusé en marche")
	c.phys.speed = 0.0
	check(c.reverse() == "", "changement de cabine à l'arrêt")
	var r1: Array = c.route.duplicate(); r1.reverse()
	check(r1 == r0 and c.direction == -1, "mêmes sections occupées, sens inversé")
	var all_occ := true
	for id in r0: all_occ = all_occ and c.net.graph.edges[id].occupied_by == c.train_id
	check(all_occ, "occupation conservée")
	c.reverse()
	check(c.edge_id == e0 and absf(c.offset - o0) < 0.01 and c.direction == 1, "double changement de cabine : retour à l'état initial")
	quit(1 if fails > 0 else 0)
