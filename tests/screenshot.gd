extends SceneTree
## Captures du rendu (xvfb-run). Args : dossier, réseau, [arête].
func _shot(path: String) -> void:
	for i in 6: await process_frame
	root.get_viewport().get_texture().get_image().save_png(path)

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "user://"
	var netf: String = args[1] if args.size() > 1 else "angers_a"
	var main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.save.settings.tutorial_done = true
	await _shot(out + "/" + netf + "_0_menu.png")
	var net := NetworkLoader.new(); net.load_file("res://data/networks/%s.json" % netf)
	main.net_path = "res://data/networks/%s.json" % netf
	main.vehicle = VehicleLibrary.default_for(net.meta)
	main.free_mode = false
	main.mission = net.missions()[0]
	main._start()
	var ids: Array = net.graph.edges.keys()
	var e9: String = args[2] if args.size() > 2 else ids[mini(10, ids.size() - 1)]
	main.session.edge_id = e9; main.session.route.assign([e9]); main.session.offset = minf(120.0, net.graph.edges[e9].length * 0.6)
	main.paused = true
	if main.view.city: main.view.city.warm(main.view.cam.global_position)
	for h in [[13.5, "jour"], [20.3, "soir"], [23.0, "nuit"]]:
		main.hour0 = h[0] - main.session.time_s / 3600.0
		main.external_cam = true
		await _shot("%s/%s_ext_%s.png" % [out, netf, h[1]])
	main.hour0 = 13.5 - main.session.time_s / 3600.0
	main.external_cam = false
	await _shot("%s/%s_cabine.png" % [out, netf])
	main.external_cam = true
	main.map.visible = true; main.map.queue_redraw()
	await _shot("%s/%s_carte.png" % [out, netf])
	if main.view.city: print("tuiles: ", main.view.city.stats)
	main.map.visible = false
	# mode libre + panneau des aiguillages
	var src := str(net.meta.get("source_id", ""))
	if FileAccess.file_exists("res://data/free/%s.json" % src):
		main.free_mode = true
		main.net_path = "res://data/free/%s.json" % src
		var fn := NetworkLoader.new(); fn.load_file(main.net_path)
		main.start_station = fn.stations[mini(5, fn.stations.size() - 1)]
		main._start()
		main.paused = true
		await _shot("%s/%s_libre.png" % [out, netf])
		main._toggle_switches()
		await _shot("%s/%s_aiguillages.png" % [out, netf])
	quit()
