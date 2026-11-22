extends SceneTree
## Reproducible real-engine aerial views, identical poses for before/after comparisons.
var output := OS.get_environment("STATION_SHOTS")
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	if output == "": output = "res://docs/angers-stations/after"
	DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(1280, 960); root.msaa_3d = Viewport.MSAA_2X
	var net := NetworkLoader.new()
	var errors := net.load_file("res://data/free/angers.json")
	if not errors.is_empty(): printerr(errors); quit(1); return
	var view := LineView.new(); view.authored_stations = OS.get_environment("STATION_MODELS") != "0"; view.view_distance = 300.0; root.add_child(view)
	view.build(net, net.stations[0].edge, VehicleLibrary.citadis_302_hybride())
	view.set_hour(13.5); view.day_night.sun.shadow_enabled = true
	view.day_night.env.fog_enabled = false
	view.day_night.sun.directional_shadow_max_distance = 650.0
	var cam := view.cam; cam.current = true; cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.near = 0.5; cam.far = 1800.0
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/stations/angers.json"))
	var places: Array = data.stations.duplicate(true)
	var survey: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/station_models/angers.json"))
	for place in places:
		for profile in survey.stations:
			if StationIdentityView.key(place.name) == StationIdentityView.key(profile.name): place.span = profile.capture_span_m
	for depot in net.meta.depots:
		places.append({"name": "Dépôt Raymond-Perron", "net_position": depot.position, "span": 460.0})
	var canvas := CanvasLayer.new(); root.add_child(canvas)
	var label := Label.new(); label.position = Vector2(20, 18); label.add_theme_font_size_override("font_size", 24)
	label.add_theme_color_override("font_shadow_color", Color.BLACK); label.add_theme_constant_override("shadow_outline_size", 5); canvas.add_child(label)
	var manifest := []
	for i in places.size():
		var s: Dictionary = places[i]
		var filter_ := OS.get_environment("STATION_FILTER")
		if filter_ != "" and not str(i + 1) in filter_.split(","): continue
		var point := Vector3.ZERO
		if s.has("net_position"): point = Vector3(s.net_position[0], 0, s.net_position[1])
		else:
			point.x = deg_to_rad(float(s.lon) - float(net.meta.origin[1])) * CityScene.R * cos(deg_to_rad(float(net.meta.origin[0])))
			point.z = -deg_to_rad(float(s.lat) - float(net.meta.origin[0])) * CityScene.R
		point.y = view.ground_at(point)
		cam.size = float(s.get("span", 145.0))
		cam.position = point + (Vector3(65.0, 95.0, 65.0) * maxf(1.0, cam.size / 220.0) if OS.get_environment("STATION_OBLIQUE") == "1" else Vector3(0, 250.0, 0))
		cam.look_at(point, Vector3.UP if OS.get_environment("STATION_OBLIQUE") == "1" else Vector3.FORWARD)
		view.view_distance = 550.0 if s.has("net_position") else 260.0
		view.update_sectors(point)
		view.city.radius = maxf(380.0, cam.size * 1.1) if OS.get_environment("STATION_OBLIQUE") == "1" else (320.0 if s.has("net_position") else maxf(160.0, cam.size * .95))
		view.city.warm(point)
		label.text = str(s.name) + "  •  Angers / Irigo"
		for j in 3: await process_frame
		await RenderingServer.frame_post_draw
		var filename := "%02d-%s.png" % [i + 1, StationLayout.norm(s.name).replace(" ", "-")]
		root.get_texture().get_image().save_png(output.path_join(filename))
		manifest.append({"name": s.name, "file": filename, "center": [point.x, point.y, point.z], "camera_size": cam.size})
		print("CAPTURE|%d/%d|%s" % [i + 1, places.size(), filename])
	var f := FileAccess.open(output.path_join("manifest.json"), FileAccess.WRITE); f.store_string(JSON.stringify(manifest, "\t")); f.close()
	view.queue_free(); canvas.queue_free(); await CityScene.drain_background_jobs(self)
	print("CAPTURES_DONE|", manifest.size()); quit()
