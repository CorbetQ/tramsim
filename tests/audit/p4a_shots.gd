extends SceneTree
## Lot P4 « ambiance » : captures en jeu jour / pluie / brume matinale / nuit / nuit de pluie / neige, cabine sous la
## pluie (gouttes et balai), sur le point d'audit dense d'Angers (comme test_render_budgets) et une station de Nantes.
## Usage : xvfb-run … godot --path . --rendering-method gl_compatibility -s tests/audit/p4a_shots.gd -- <dossier> [mobile]
## [city=angers|nantes]

var main
var out := "user://p4a"
var mobile := false

func _init() -> void:
	_run.call_deferred()

func _shot(name: String) -> void:
	for i in 10: await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png("%s/%s%s.png" % [out, "mobile_" if mobile else "", name])
	var h: Dictionary = load("res://tests/test_render_budgets.gd").histogram(img)
	print("SHOT|%s|draws=%d|tris=%d|noir=%.2f%%|luma=%.2f|lumieres=%d" % [name, Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME), h.black * 100.0, h.luma, main.view.night_lights.active])

func _hour(h: float) -> void:
	main.hour0 = h - main.session.time_s / 3600.0; main.view.set_hour(h)

## Météo imposée sans transition (rain, fog, wetness) ; neige : preset « snow ».
func _weather(preset: String, rain: float, fog: float, wet: float) -> void:
	var w: WeatherState = main.weather
	w.set_preset(preset); w.rain = rain; w.fog = fog; w.wetness = wet
	var wv: WeatherView = main.weather_view
	wv.wet = wet * (0.55 if preset == "snow" else 1.0)
	wv.snow_cover = 0.75 if preset == "snow" else 0.0
	if wv.windscreen != null: wv.windscreen.strength = rain
	main.view.rain = rain

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0: out = args[0]
	mobile = args.has("mobile")
	var city := "angers"
	for a in args: if str(a).begins_with("city="): city = str(a).substr(5)
	DirAccess.make_dir_recursive_absolute(out)
	DayNight.low_quality = mobile
	root.size = Vector2i(1280, 720)
	main = load("res://src/ui/main.tscn").instantiate(); root.add_child(main)
	await process_frame
	main.save.settings.tutorial_done = true; main.save.settings.traffic = true; main.save.settings.visual_profile = "auto"
	var idx: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/index.json"))
	var line := {}
	for n in idx.networks:
		if str(n.id).begins_with(city) and n.kind == "tram" and (line.is_empty() or float(n.length_km) > float(line.length_km)): line = n
	main.net_path = str(line.path); main.free_mode = false
	var net := NetworkLoader.new(); net.load_file(main.net_path)
	main.vehicle = VehicleLibrary.default_for(net.meta)
	main.mission = net.missions()[0]
	main._start(); main.paused = true
	for c in main.get_children():
		if c is Control or c is CanvasLayer: c.visible = false
	if mobile:
		VisualEffects.apply_profile("mobile", main.view.day_night.env, main.view.day_night.sun, root, "mobile")
		PbrMaterials.set_profile("mobile")
	var cs = main.view.city
	var best := {}; var bb := -1
	for s in net.stations:
		var p: Vector3 = main.view.pos3(s.edge, float(s.offset))
		var b := 0
		if cs != null:
			var c: Vector3 = p - cs.position; c.x /= cs._x_scale
			b = int(cs.table.get(Vector2i(floori(c.x / cs.tile_m), floori(c.z / cs.tile_m)), Vector2i.ZERO).y)
		if b > bb: bb = b; best = s
	var L: float = main.net.graph.edges[best.edge].length
	main.session.edge_id = best.edge; main.session.route.assign([best.edge])
	main.session.offset = clampf(float(best.offset), 1.0, maxf(1.0, L - 1.0)); main.view._rig_fresh = true
	print("SHOT|point|%s|%s" % [city, best.name])
	main.external_cam = true; main.view.orbit = 0.6; main.view.cam_dist = 26.0
	await process_frame
	if cs: cs.warm(main.view.cam.global_position)
	_hour(14.0); _weather("clear", 0, 0, 0); await _shot("jour")
	_weather("rain", 0.85, 0.12, 1.0); await _shot("pluie")
	_hour(7.2); _weather("clear", 0.0, 0.15, 0.3); await _shot("brume_matin")
	_hour(20.6); _weather("clear", 0, 0, 0); await _shot("crepuscule")
	_hour(22.5); await _shot("nuit")
	_weather("rain", 0.85, 0.12, 1.0); await _shot("nuit_pluie")
	_hour(10.0); _weather("snow", 0.5, 0.25, 0.6); await _shot("neige")
	# cabine sous la pluie : gouttes, balai en marche
	_hour(14.0); _weather("rain", 0.9, 0.12, 1.0)
	main.view.wiper_forced = false
	main.external_cam = false
	await _shot("cabine_pluie")
	main.view.wiper_forced = true
	for i in 50: await process_frame
	await _shot("cabine_pluie_balai")
	_hour(22.5); await _shot("cabine_nuit_pluie")
	quit(0)
