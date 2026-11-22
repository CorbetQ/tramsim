extends SceneTree
## Captures de contrôle des modèles dédiés (P1) dans le jeu réel : cabine et vue extérieure en approche, puis vues
## obliques libres autour des ancres de assets/models/landmark_models.json.
## xvfb-run godot --path . [--rendering-driver opengl3|vulkan] -s tools/qa/capture_landmark_models.gd -- <dossier> <réseau> <arête> <offset> [tag]
func _shot(path: String, frames := 8) -> void:
	for i in frames: await process_frame
	root.get_viewport().get_texture().get_image().save_png(path)
	print("capture ", path)

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0]; var netf: String = args[1]; var edge: String = args[2]; var off := float(args[3])
	var tag: String = args[4] if args.size() > 4 else netf
	DirAccess.make_dir_recursive_absolute(out)
	var main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.save.settings.tutorial_done = true
	var net := NetworkLoader.new(); net.load_file("res://data/networks/%s.json" % netf)
	main.net_path = "res://data/networks/%s.json" % netf
	main.vehicle = VehicleLibrary.default_for(net.meta)
	main.free_mode = false
	main.mission = net.missions()[0]
	main._start()
	main.session.edge_id = edge; main.session.route.assign([edge]); main.session.offset = off
	main.paused = true
	main.hour0 = 14.0 - main.session.time_s / 3600.0
	if main.view.city: main.view.city.warm(main.view.cam.global_position)
	var lm: LandmarkModels = main.view.get_node_or_null("landmark_models")
	print("landmark_models: ", lm.models.map(func(m): return [m.id, m.triangles]) if lm else "absent")
	for c in main.find_children("*", "CanvasLayer", true, false): (c as CanvasLayer).visible = false
	main.external_cam = false
	await _shot("%s/%s_cabine.png" % [out, tag], 30)
	main.external_cam = true
	await _shot("%s/%s_ext.png" % [out, tag])
	print("draws ", RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME), " tris ", RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))
	if lm == null: quit(); return
	# vues obliques : caméra libre autour de chaque modèle
	var cam := Camera3D.new(); cam.fov = 60.0; cam.near = 0.2; cam.far = 3000.0
	main.view.add_child(cam)
	var poses: Array = []
	for i in range(5, args.size(), 1):
		poses.append(args[i])
	for p in poses:
		var f: PackedStringArray = str(p).split(",")   # id,dx,dy,dz,tx,ty,tz (relatifs à l'ancre),nom
		var node: Node3D = lm.get_node_or_null(f[0])
		if node == null: continue
		var a := node.global_position
		cam.global_position = a + Vector3(float(f[1]), float(f[2]), float(f[3]))
		cam.look_at(a + Vector3(float(f[4]), float(f[5]), float(f[6])), Vector3.UP)
		cam.current = true
		main.view.set_process(false)
		if main.view.city: main.view.city.warm(cam.global_position)
		await _shot("%s/%s_%s.png" % [out, tag, f[7]], 12)
	quit()
