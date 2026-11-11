extends SceneTree
## Captures du rendu (nécessite un affichage, ex. xvfb-run). Arg : dossier de sortie.
func _init() -> void:
	var out: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "user://"
	var main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.save.settings.tutorial_done = true
	await process_frame
	root.get_viewport().get_texture().get_image().save_png(out + "/0_menu.png")
	var net := NetworkLoader.new(); net.load_file("res://data/networks/angers_a.json")
	main.net_path = "res://data/networks/angers_a.json"
	main.vehicle = VehicleLibrary.citadis_302()
	main.free_mode = false
	main.mission = net.missions()[0]
	main._start()
	# avance la rame au milieu d'une inter-station
	main.session.edge_id = "A0_9"; main.session.route.assign(["A0_8", "A0_9"]); main.session.offset = 150.0
	main.paused = true
	for i in 10: await process_frame
	root.get_viewport().get_texture().get_image().save_png(out + "/1_exterieur.png")
	main.external_cam = false
	for i in 5: await process_frame
	root.get_viewport().get_texture().get_image().save_png(out + "/2_cabine.png")
	main.map.visible = true; main.map.queue_redraw()
	for i in 5: await process_frame
	root.get_viewport().get_texture().get_image().save_png(out + "/3_carte.png")
	quit()
