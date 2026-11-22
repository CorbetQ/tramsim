extends SceneTree
## Integration checks: real platforms, bridge heights, independent city origin, model culling and preload reuse.
var failures := 0
func check(ok: bool, label_: String) -> void:
	if ok: print("ok: ", label_)
	else: failures += 1; printerr("ECHEC: ", label_)
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	var net := NetworkLoader.new()
	check(net.load_file("res://data/free/angers.json").is_empty(), "réseau Angers chargé")
	var view := LineView.new(); root.add_child(view)
	view.build(net, net.stations[0].edge, VehicleLibrary.citadis_302_hybride())
	var identity := view.station_identity
	check(identity != null, "modèles documentés intégrés à LineView")
	check(identity.stats.stations == 42 and identity.stats.platforms == 79, "42 arrêts et 79 emprises réelles")
	# Ralliement (2 auvents, Grand Théâtre) : modèle dédié assets/models (LandmarkModels), plus construit ici
	var dedicated := LandmarkModels.replaces_station(view, "Ralliement")
	check(identity.stats.canopies == (76 if dedicated else 78) and identity.stats.landmarks == (43 if dedicated else 44), "abris et voisinages individuels construits (%d, %d)" % [identity.stats.canopies, identity.stats.landmarks])
	check(not dedicated or view.get_node_or_null("landmark_models/angers_ralliement") != null, "Ralliement : modèle dédié instancié")
	var finite := true; var culled := true; var vertices := 0; var ground_faces_up := true
	for node in identity.find_children("*", "MeshInstance3D", true, false):
		culled = culled and node.visibility_range_end > 0
		var aabb: AABB = node.mesh.get_aabb()
		finite = finite and aabb.position.is_finite() and aabb.size.is_finite()
		for surface in node.mesh.get_surface_count():
			vertices += node.mesh.surface_get_array_len(surface)
			if node.material_override == identity._paving:
				var points: PackedVector3Array = node.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
				for j in range(0, points.size(), 3): ground_faces_up = ground_faces_up and (points[j + 2] - points[j]).cross(points[j + 1] - points[j]).y >= -.0001
	check(finite and vertices > 10000, "géométrie finie, non vide (%d sommets)" % vertices)
	check(ground_faces_up, "triangulation des sols orientée vers le ciel, sans dallage noir")
	check(culled, "tous les détails ont une distance de visibilité")
	check(not identity.find_children("*", "MultiMeshInstance3D", true, false).is_empty(), "voyageurs en attente conservés dans les quais personnalisés")
	var obstacle: Array = view.city._authored_camera_blocks[0]
	var middle := Vector2.ZERO
	for p in obstacle[0]: middle += p
	middle /= obstacle[0].size()
	var target := Vector3(middle.x, (float(obstacle[1]) + float(obstacle[2])) * .5, middle.y)
	check(view.city.camera_clear(target - Vector3(200, 0, 0), target) < 1.0, "les bâtiments personnalisés restent des obstacles pour la caméra")
	var profile: Dictionary = identity.by_name[StationIdentityView.key("Les Gares")]
	var max_error := 0.0
	for platform in identity._platforms[profile.id]:
		var p := Vector2(platform.pts[0][0], platform.pts[0][1])
		var expected := float(platform.y[0]) + float(platform.get("height_m", .3))
		max_error = maxf(max_error, absf(identity._floor(p, profile) - expected))
	check(max_error < .015, "mobilier des Gares à la cote des quais du pont, pas au sol inférieur")
	var paved := 0
	for depot in net.meta.depots:
		for id in depot.tracks:
			if identity.depot_track_at(id, view.pos3(id, net.graph.edges[id].length * .5)): paved += 1
	check(paved > 30, "sol minéral des voies de service du dépôt (%d tronçons)" % paved)
	# Regression: small LOD radii used for aerial previews must not drop the tile under the camera.
	var bascule: Dictionary = identity.by_name[StationIdentityView.key("Bascule")]
	var xy := identity._point([bascule.lat, bascule.lon]); var center := Vector3(xy.x, 0, xy.y)
	view.city.radius = 80.0; view.city.warm(center)
	var local_ := center - view.city.position; local_.x /= view.city._x_scale
	var key_ := Vector2i(floori(local_.x / view.city.tile_m), floori(local_.z / view.city.tile_m))
	check(view.city.built.has(key_), "la tuile sous Bascule reste chargée avec un LOD de 80 m")
	check(is_equal_approx(view.city._tile_distance(Vector2i(0, 0), Vector2(.01, .01)), 0.0), "distance LOD calculée depuis l’emprise de tuile")
	# A mission has a different origin. Geographic canopy points must still coincide with its platform positions.
	var mission := NetworkLoader.new(); mission.load_file("res://data/networks/angers_a.json")
	var mission_view := LineView.new(); mission_view.net = mission
	var mission_models := StationIdentityView.new(); mission_models.setup(mission_view, "angers")
	check(mission_models.by_name.has(StationIdentityView.key("Foch-Maison Bleue")), "modèles partagés avec les lignes de mission")
	CityDataStore.install({}, {"res://data/station_models/angers.json": identity.data})
	var reads := CityDataStore.disk_reads
	var again := StationIdentityView.new(); again.setup(mission_view, "angers")
	check(CityDataStore.disk_reads == reads, "document de modèles réutilisé depuis le cache")
	again.free(); mission_models.free(); mission_view.free()
	var other_view := LineView.new(); other_view.net = net
	var other := StationIdentityView.new(); other.setup(other_view, "nantes")
	check(other.data.is_empty() and other.by_way.is_empty(), "aucun modèle angevin injecté dans les autres villes")
	other.free(); other_view.free()
	view.queue_free(); await CityScene.drain_background_jobs(self)
	print("TOTAL_ECHECS|", failures); quit(1 if failures else 0)
