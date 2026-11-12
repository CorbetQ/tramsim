extends SceneTree
class PlatformView:
	extends RefCounted
	var net: NetworkLoader
	func _frame(_edge: String, _offset: float) -> Transform3D: return Transform3D.IDENTITY
var failures := 0
func check(ok: bool, message: String) -> void:
	if ok: print("ok: ", message)
	else: failures += 1; printerr("ECHEC: ", message)
func _init() -> void:
	var n := NetworkLoader.new(); n.load_file("res://tests/fixtures/schema_test.json")
	var id: String = n.meta.edges[0].id
	var m := MissionSession.new(n, VehicleLibrary.citadis_302_hybride(), id, 20.0, [] as Array[float])
	m.traffic.enabled = false
	n.edge_info[id].supply = "aps"; n.edge_info[id].grade = -0.08; n.edge_info[id].ys = PackedFloat32Array()
	var start := m.offset
	for i in 100: m.tick(0.02, 1.0)
	check(not m.power_ok and absf(m.offset - start) < 0.001, "APS avec pantographe levé : aucune dérive en descente malgré la traction")
	m.toggle_pantograph()
	for i in 80: m.tick(0.02, 1.0)
	check(m.power_ok and m.phys.speed > 0.1, "reprise de traction après sélection APS")
	m.phys.speed = 5.0; m.pantograph_up = true
	for i in 3000: m.tick(0.02, 1.0)
	check(m.phys.speed < 0.01, "coupure en mouvement : freinage progressif jusqu’à l’arrêt")
	var boundary := MissionSession.new(n, VehicleLibrary.citadis_302_hybride(), "e0", 898.0, [] as Array[float])
	boundary.stops = [{"name":"Limite", "edge":"e1", "offset":0.0, "dwell_s":20.0}]
	check(not boundary._station_here().is_empty(), "arrêt à un nœud : quai reconnu depuis le tronçon précédent")
	# Voie droite puis arc de cercle exact, indépendamment du rayon stocké.
	var data := {"schema":1,"nodes":["a","b"],"edges":[{"id":"curve","from":"a","to":"b","length":31.4,"limit_kmh":70,"pts":[]}],"stations":[]}
	for i in 21:
		var angle := PI * 0.5 * i / 20.0
		data.edges[0].pts.append([20.0 * sin(angle), 20.0 * (1.0 - cos(angle))])
	var file := FileAccess.open("user://curve-test.json", FileAccess.WRITE); file.store_string(JSON.stringify(data)); file.close()
	var curve := NetworkLoader.new(); curve.load_file("user://curve-test.json")
	check(curve.limit_at("curve", 15.0) * 3.6 <= 15.1, "rayon 20 m : limite locale arrondie à 15 km/h au maximum")
	data.edges[0].pts = [[0,0],[15,0],[31.4,0]]
	file = FileAccess.open("user://curve-test.json", FileAccess.WRITE); file.store_string(JSON.stringify(data)); file.close()
	curve.load_file("user://curve-test.json")
	check(is_equal_approx(curve.limit_at("curve", 15.0)*3.6,70.0), "voie droite : aucune réduction artificielle")
	DirAccess.remove_absolute("user://curve-test.json")
	var angers := NetworkLoader.new(); angers.load_file("res://data/free/angers.json")
	check(angers.meta.platforms.size() >= 75 and "aps" in angers.supplies, "Angers : quais OSM ouverts et sections APS importés")
	var anchored := 0
	for station in angers.stations:
		if station.has("source_osm_node"): anchored += 1
	check(anchored > 60, "Angers : arrêts ancrés aux nœuds OSM")
	var platform_view := PlatformView.new(); platform_view.net = n
	n.meta.platforms = [{"name":"Station", "pts":[[-4,-10],[-2,-10],[-2,10],[-4,10]]}]
	var layout := StationLayout.new(platform_view)
	var station := {"name":"Station", "edge":"e0", "offset":0.0}
	check(layout.info_for(station, Vector3.ZERO).doors == "left", "empreinte à gauche : portes à gauche indépendamment du type GTFS")
	n.meta.platforms[0].pts = [[2,-10],[4,-10],[4,10],[2,10]]
	check(layout.info_for(station, Vector3.ZERO).doors == "right", "empreinte à droite : portes à droite")
	var visual := LineView.new(); visual.net = n; visual.geometric = false
	visual.edge_origin["e0"] = Vector3.ZERO
	var start_session := MissionSession.new(n, VehicleLibrary.citadis_302_hybride(), "e0", 0.0, [] as Array[float])
	check(visual.body_point(start_session, 0.0).distance_to(visual.body_point(start_session, 30.0)) > 29.9, "départ au point zéro : les caisses gardent leur espacement")
	visual.free()
	print("TOTAL_ECHECS|",failures); quit(1 if failures else 0)
