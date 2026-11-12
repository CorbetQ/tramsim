extends SceneTree
## Charger tous les réseaux physiques et vérifier coordonnées, jonctions et services.
func _init() -> void:
	var fails := 0; var count := 0; var service := 0; var depots := 0
	for file in DirAccess.get_files_at("res://data/free"):
		if not file.ends_with(".json"): continue
		var net := NetworkLoader.new(); var errors := net.load_file("res://data/free/" + file)
		var bad := errors.size(); var ends := {}
		if net.meta.get("geometry_kind", "") != "physical": bad += 1
		var view := LineView.new(); view.net = net; view.geometric = true
		for raw in net.meta.edges:
			var id: String = raw.id; var L: float = raw.length
			if not id.begins_with("osm:") or not raw.get("physical", false): bad += 1
			if not str(raw.get("service", "")).is_empty(): service += 1
			for endpoint in [[raw.from, 0.0],[raw.to,L]]:
				var p := view.pos3(id,endpoint[1])
				if ends.has(endpoint[0]) and p.distance_to(ends[endpoint[0]]) > 0.015: bad += 1
				ends[endpoint[0]] = p
				var q := net.point_on(id,endpoint[1])
				if Vector2(p.x,p.z).distance_to(q.p) > 0.001: bad += 1
		for depot in net.meta.get("depots", []):
			depots += 1
			if not net.graph.edges.has(depot.edge): bad += 1
		if bad:
			printerr("ECHEC: ",file," : ",bad," erreurs ",errors); fails += 1
		else: print("ok: ",file," : jonctions cohérentes, axes physiques conservés")
		view.free(); count += 1
	if count != 28 or service < 1000 or depots < 20:
		printerr("ECHEC: couverture : ",count," réseaux, ",service," services, ",depots," remisages"); fails += 1
	else: print("ok: couverture ",count," réseaux, ",service," sections de service, ",depots," remisages")
	# Réutilisation d'un chargeur : ne doit pas accumuler les anciens nœuds / stations.
	var loader := NetworkLoader.new(); loader.load_file("res://data/free/angers.json")
	loader.load_file("res://tests/fixtures/schema_test.json")
	if loader.graph.edges.size() != loader.meta.edges.size(): printerr("ECHEC: ancien graphe conservé"); fails += 1
	else: print("ok: rechargement sans état résiduel")
	quit(1 if fails else 0)
