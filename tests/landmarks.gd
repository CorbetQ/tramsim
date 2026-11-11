extends SceneTree
## Captures de monuments (xvfb). Args : dossier, puis paires réseau:nom (ex. angers_b:Château d'Angers).
func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0]
	for pair in args.slice(1):
		var sp: PackedStringArray = pair.split(":")
		var net := NetworkLoader.new(); net.load_file("res://data/networks/%s.json" % sp[0])
		var view := LineView.new(); root.add_child(view)
		view.build(net, net.missions()[0].start_edge, VehicleLibrary.default_for(net.meta))
		view.set_hour(float(sp[2]) if sp.size() > 2 else 15.0)
		var p := view.city.find_label(sp[1]) if view.city else Vector3.INF
		if p == Vector3.INF:
			print("introuvable : ", pair); view.queue_free(); continue
		view.cam.current = true
		view.cam.position = p + Vector3(-95, 55, 95); view.cam.look_at(p + Vector3(0, 12, 0))
		view.city.warm(p)
		for f in 30: await process_frame
		root.get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, sp[1].to_lower().replace(" ", "_").replace("'", "")])
		print("ok : ", pair)
		view.queue_free()
		await process_frame
	quit()
