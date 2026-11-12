extends SceneTree
## Capture reproductible sous un vrai renderer OpenGL ; -- ville largeur hauteur heure.
func _init() -> void:
	_run.call_deferred()
func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var city: String = args[0] if args.size() > 0 else "angers"
	root.size = Vector2i(int(args[1]), int(args[2])) if args.size() > 2 else Vector2i(1280, 720)
	var main = load("res://src/ui/main.tscn").instantiate(); root.add_child(main)
	await process_frame
	main.save.settings.tutorial_done = true
	main.net_path = "res://data/free/%s.json" % city; main.free_mode = true
	var net := NetworkLoader.new(); net.load_file(main.net_path)
	main.vehicle = VehicleLibrary.default_for(net.meta)
	main.start_station = net.stations[net.stations.size() / 3]
	for s in net.stations:
		if s.name == "Molière": main.start_station = s; break
	if args.size() > 4:
		var kind: String = args[4]
		var best := 0.0
		if kind == "depot" and not net.meta.get("depots", []).is_empty(): main.start_station = net.meta.depots[0]
		else:
			for e in net.meta.edges:
				for interval in e.get(kind, []):
					if float(interval[1]) - float(interval[0]) > best:
						best = float(interval[1]) - float(interval[0]); main.start_station = {"edge":e.id,"offset":(float(interval[0])+float(interval[1]))*0.5}
	main._start(); main.paused = false
	if OS.get_environment("TRAMSIM_REVIEW_FAST") == "1": main.view.day_night.sun.shadow_enabled = false
	if args.size() > 5 and args[5] == "cabine": main.external_cam = false
	main.hour0 = float(args[3]) if args.size() > 3 else 17.0
	main.view.set_hour(float(args[3]) if args.size() > 3 else 17.0)
	main.view.orbit = 0.6; main.view.cam_dist = 32.0
	for i in 18: await process_frame
	print("WORLD|camera=", main.view.cam.global_position," current=",root.get_camera_3d()," train=",main.view.pos3(main.session.edge_id,main.session.offset)," terrain=",main.view.city.height_at(main.view.cam.global_position)," tiles=",main.view.city.built.size()," min=",main.view.city.min_height)
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://build/review")
	var path := "res://build/review/%s-%dx%d-%s.png" % [city,root.size.x,root.size.y,args[4] if args.size() > 4 else "street"]
	root.get_texture().get_image().save_png(path)
	for name in ["trip", "lever", "dock", "emergency"]:
		var c := main.find_child(name,true,false) as Control
		print("LAYOUT|",name,"|",c.get_global_rect() if c else Rect2())
	print("CAPTURE|",ProjectSettings.globalize_path(path))
	main.queue_free(); await process_frame; await process_frame
	quit()
