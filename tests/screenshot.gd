extends SceneTree
## Captures du rendu (nécessite un affichage, ex. xvfb-run). Arg : dossier de sortie.
func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "user://"
	var netf: String = args[1] if args.size() > 1 else "angers_a"
	var main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.save.settings.tutorial_done = true
	await process_frame
	root.get_viewport().get_texture().get_image().save_png(out + "/" + netf + "_0_menu.png")
	var net := NetworkLoader.new(); net.load_file("res://data/networks/%s.json" % netf)
	main.net_path = "res://data/networks/%s.json" % netf
	main.vehicle = VehicleLibrary.citadis_302()
	main.free_mode = false
	main.mission = net.missions()[0]
	main._start()
	# avance la rame au milieu d'une inter-station
	var ids: Array = net.graph.edges.keys()
	var e9: String = ids[mini(9, ids.size() - 1)]
	main.session.edge_id = e9; main.session.route.assign([e9]); main.session.offset = minf(150.0, net.graph.edges[e9].length * 0.6)
	main.paused = true
	for i in 10: await process_frame
	root.get_viewport().get_texture().get_image().save_png(out + "/" + netf + "_1_exterieur.png")
	main.external_cam = false
	for i in 5: await process_frame
	root.get_viewport().get_texture().get_image().save_png(out + "/" + netf + "_2_cabine.png")
	main.map.visible = true; main.map.queue_redraw()
	for i in 5: await process_frame
	root.get_viewport().get_texture().get_image().save_png(out + "/" + netf + "_3_carte.png")
	quit()
