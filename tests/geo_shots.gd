extends SceneTree
## Vues dédiées (xvfb-run) : args = dossier, puis des specs "nom;réseau;cible;distance;orbite;hauteur(h)".
## réseau : chemin res:// ou id de data/networks ; cible : nom de station (sous-chaîne) ou "edge=<id>@<offset>" ;
## distance de caméra extérieure (0 = vue cabine), orbite en degrés.
func _shot(path: String) -> void:
	for i in 8: await process_frame
	root.get_viewport().get_texture().get_image().save_png(path)

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0]
	var main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.save.settings.tutorial_done = true
	for spec in args.slice(1):
		var f: PackedStringArray = spec.split(";")
		var path: String = f[1] if f[1].begins_with("res://") else "res://data/networks/%s.json" % f[1]
		var net := NetworkLoader.new(); net.load_file(path)
		main.net_path = path
		main.vehicle = VehicleLibrary.default_for(net.meta)
		main.free_mode = net.meta.get("kind", "") == "free"
		var edge := ""; var off := 0.0
		if f[2].begins_with("edge="):
			var t := f[2].substr(5).split("@")
			edge = t[0]; off = float(t[1])
		else:
			for s in net.stations:
				if f[2] in str(s.name): edge = s.edge; off = float(s.offset); break
		if edge == "": print("ECHEC cible introuvable ", spec); continue
		if main.free_mode:
			main.start_station = {"edge": edge, "offset": off, "name": "vue"}
		else:
			main.mission = net.missions()[0]
		main._start()
		main.session.edge_id = edge; main.session.route.assign([edge]); main.session.offset = off
		main.paused = true
		var dist := float(f[3]) if f.size() > 3 else 40.0
		main.external_cam = dist > 0.0
		if dist > 0.0: main.view.cam_dist = dist
		if f.size() > 4: main.view.orbit = deg_to_rad(float(f[4]))
		main.hour0 = 13.5 - main.session.time_s / 3600.0
		await process_frame
		var own: Camera3D = null
		if f.size() > 5:   # caméra libre : élévation (degrés) au-dessus de la cible
			var fr: Transform3D = main.view._frame(edge, off)
			var tgt := fr.origin + Vector3(0, 1.5, 0)
			var el := deg_to_rad(float(f[5])); var az := deg_to_rad(float(f[4]))
			var dir := (fr.basis.x.rotated(Vector3.UP, az) * cos(el) + Vector3.UP * sin(el)).normalized()
			own = Camera3D.new(); own.fov = 55.0; own.far = 2000.0
			main.add_child(own)
			own.global_position = tgt + dir * dist
			own.look_at(tgt)
			own.make_current()
		if main.view.city: main.view.city.warm(main.view.cam.global_position if own == null else own.global_position)
		await _shot("%s/%s.png" % [out, f[0]])
		if own: own.queue_free()
		print("vue ", f[0], " ", edge, " ", off)
	quit()
