extends SceneTree
## Refonte P1 (docs/CDC_REFONTE_VISUELLE.md §7.2) : cadrages fixes C1–C3 reproduisant les références sur des sites
## réels, avec les modèles dédiés (LandmarkModels) et la bibliothèque de matériaux texturée.
## - C1 : cabine en station couverte (station enterrée de la trémie de la ligne 3, Nantes, modèle dédié) ;
## - C2 : rame à l'arrêt à Ralliement (Angers, ligne C), extérieur, cathédrale Saint-Maurice en fond ;
## - C3 : cabine en approche du portail de la trémie (Nantes, ligne 3) ;
## - C0 : cabine en approche de Ralliement (contrôle de la voie et de la voirie texturées).
## Usage : godot --path . [--rendering-method …] -s tests/audit/p1_shots.gd -- <dossier> [suffixe] [mobile]
## Écrit <dossier>/C<n><suffixe>.png et une ligne SHOT|… (draw calls, triangles, histogramme) par cadrage.
var out := "."
var suffix := ""
var mobile := false

func _init() -> void:
	_run.call_deferred()

func _start(net_id: String):
	var main = load("res://src/ui/main.tscn").instantiate(); root.add_child(main)
	await process_frame
	main.save.settings.tutorial_done = true; main.save.settings.traffic = false
	main.net_path = "res://data/networks/%s.json" % net_id; main.free_mode = false
	var net := NetworkLoader.new(); net.load_file(main.net_path)
	main.vehicle = VehicleLibrary.default_for(net.meta); main.mission = net.missions()[0]
	main._start(); main.paused = true
	for c in main.get_children():
		if c is Control or c is CanvasLayer: c.visible = false
	if mobile:
		VisualEffects.apply_profile("mobile", main.view.day_night.env, main.view.day_night.sun, root, "mobile")
		PbrMaterials.set_profile("mobile")
	return main

func _place(main, edge: String, offset: float, hour: float) -> void:
	var L: float = main.net.graph.edges[edge].length
	main.session.edge_id = edge; main.session.route.assign([edge])
	main.session.offset = clampf(offset, 1.0, maxf(1.0, L - 1.0)); main.view._rig_fresh = true
	main.hour0 = hour - main.session.time_s / 3600.0; main.view.set_hour(hour)
	await process_frame
	if main.view.city: main.view.city.warm(main.view.pos3(edge, main.session.offset))

func _shot(name: String) -> void:
	for i in 12: await process_frame
	await RenderingServer.frame_post_draw
	var draws := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var tris := int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	var img := root.get_texture().get_image()
	img.save_png("%s/%s%s.png" % [out, name, suffix])
	var h: Dictionary = load("res://tests/test_render_budgets.gd").histogram(img)
	print("SHOT|%s%s|renderer=%s|draws=%d|tris=%d|noir=%.2f%%|luma=%.2f" % [name, suffix, VisualEffects.renderer(), draws, tris, h.black * 100.0, h.luma])

func _station(main, name_: String) -> Dictionary:
	for s in main.net.stations:
		if str(s.name) == name_: return s
	return {}

func _run() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() > 0: out = a[0]
	if a.size() > 1: suffix = a[1]
	mobile = a.size() > 2 and a[2] == "mobile"
	if mobile: DayNight.low_quality = true
	DirAccess.make_dir_recursive_absolute(out)
	root.size = Vector2i(1280, 720)
	# C1, C2 : Ralliement (Angers C)
	var main = await _start("angers_c")
	var st := _station(main, "Ralliement")
	if not st.is_empty():
		await _place(main, st.edge, float(st.offset) - 28.0, 11.0)
		main.external_cam = false
		await _shot("C0")
		await _place(main, st.edge, float(st.offset), 15.5)
		main.external_cam = true
		var tram: Vector3 = main.view.pos3(st.edge, float(st.offset))
		var cath := tram
		for m in LandmarkModels.for_view(main.view):
			if str(m.id).contains("cathedrale"): cath = LandmarkModels.anchor(main.view, m)
		var d := Vector3(cath.x - tram.x, 0, cath.z - tram.z).normalized()
		if d == Vector3.ZERO: d = Vector3.FORWARD
		# axe de la voie orienté vers la cathédrale ; caméra sur le quai, en arrière de la rame
		var t: Vector3 = main.view.pos3(st.edge, float(st.offset) + 5.0) - main.view.pos3(st.edge, float(st.offset) - 5.0)
		t.y = 0.0; t = t.normalized()
		if t.dot(d) < 0.0: t = -t
		var side := t.cross(Vector3.UP)
		if side.dot(d) < 0.0: side = -side
		var cam := Camera3D.new(); cam.fov = 62.0; cam.far = 4000.0
		main.add_child(cam)
		# rame au premier plan, cathédrale (≈ 290 m, en haut de la rue) dans l'axe, focale serrée
		cam.fov = 46.0
		# les immeubles de la place masquent la nef à hauteur d'homme : point de vue surélevé (≈ 1er étage)
		cam.global_position = tram - d * 24.0 + side * 5.0 + Vector3(0, 7.0, 0)
		cam.look_at(tram.lerp(cath, 0.4) + Vector3(0, 9.0, 0), Vector3.UP)
		cam.make_current()
		await _shot("C2")
		cam.queue_free()
	else:
		printerr("ECHEC: station Ralliement introuvable")
	main.queue_free()
	for i in 3: await process_frame
	# C3 : trémie de la ligne 3 (Nantes) : tronçon en tunnel le plus proche du modèle dédié
	main = await _start("nantes_3")
	var anchor := Vector3.INF
	for m in LandmarkModels.for_view(main.view):
		if str(m.id).contains("tremie"): anchor = LandmarkModels.anchor(main.view, m)
	var best := ""; var best_s := 0.0; var bd := INF
	for id in main.net.edge_info:
		for sp in main.net.edge_info[id].get("tunnel", []):
			var s := float(sp[0]) + 12.0
			var p: Vector3 = main.view.pos3(id, s)
			var dd := p.distance_to(anchor) if anchor.is_finite() else float(bd) - 1.0
			if dd < bd: bd = dd; best = id; best_s = s
	if best != "":
		await _place(main, best, best_s, 11.0)
		main.external_cam = false
		await _shot("C1")
		await _place(main, best, best_s - 40.0, 11.0)
		await _shot("C3")
	else:
		printerr("ECHEC: aucune trémie sur nantes_3")
	main.queue_free()
	for i in 3: await process_frame
	quit()
