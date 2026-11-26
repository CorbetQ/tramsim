extends SceneTree
## Refonte P3 (végétation, mobilier, caténaire) : cadrages fixes avant/après sur Angers (Foch-Maison Bleue,
## boulevard planté) et Nantes (Duchesse Anne - Château) : cabine, rue (piéton sur le trottoir), oblique (≈ 35 m).
## Usage : godot --path . [--rendering-method …] -s tests/audit/p3_shots.gd -- <dossier> [suffixe] [mobile]
## Écrit <dossier>/<ville>_<cadrage><suffixe>.png et une ligne SHOT|… (draw calls, triangles, histogramme).
var out := "."
var suffix := ""
var mobile := false
const SITES := [["angers_a", "Foch-Maison Bleue", 40.0], ["nantes_1", "Duchesse Anne - Château", 35.0]]

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

func _shot(name: String) -> void:
	for i in 14: await process_frame
	await RenderingServer.frame_post_draw
	var draws := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var tris := int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	var img := root.get_texture().get_image()
	img.save_png("%s/%s%s.png" % [out, name, suffix])
	var h: Dictionary = load("res://tests/test_render_budgets.gd").histogram(img)
	print("SHOT|%s%s|renderer=%s|draws=%d|tris=%d|noir=%.2f%%|luma=%.2f" % [name, suffix, VisualEffects.renderer(), draws, tris, h.black * 100.0, h.luma])

func _run() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() > 0: out = a[0]
	if a.size() > 1: suffix = a[1]
	mobile = "mobile" in a.slice(2)
	if mobile: DayNight.low_quality = true
	DirAccess.make_dir_recursive_absolute(out)
	root.size = Vector2i(1280, 720)
	for site in SITES:
		var main = await _start(site[0])
		var st: Dictionary = {}
		for s in main.net.stations:
			if str(s.name) == site[1]: st = s; break
		if st.is_empty():
			printerr("ECHEC: station %s introuvable" % site[1]); main.queue_free(); continue
		var city: String = str(site[0]).get_slice("_", 0)
		var off := float(st.offset) - float(site[2])
		var L: float = main.net.graph.edges[st.edge].length
		main.session.edge_id = st.edge; main.session.route.assign([st.edge])
		main.session.offset = clampf(off, 1.0, maxf(1.0, L - 1.0)); main.view._rig_fresh = true
		main.hour0 = 11.0 - main.session.time_s / 3600.0; main.view.set_hour(11.0)
		await process_frame
		var p: Vector3 = main.view.pos3(st.edge, main.session.offset)
		if main.view.city: main.view.city.warm(p)
		main.external_cam = false
		await _shot("%s_cabine" % city)
		var t: Vector3 = main.view.pos3(st.edge, main.session.offset + 5.0) - main.view.pos3(st.edge, main.session.offset - 5.0)
		t.y = 0.0; t = t.normalized()
		var side := t.cross(Vector3.UP)
		var cam := Camera3D.new(); cam.fov = 60.0; cam.far = 4000.0
		main.add_child(cam)
		# rue : piéton sur le trottoir, à 7 m de l'axe de la voie, regard le long de la voie
		cam.global_position = p + side * 7.0 + Vector3(0, 1.65, 0) - t * 6.0
		cam.look_at(p + t * 40.0 + side * 2.0 + Vector3(0, 3.0, 0), Vector3.UP)
		cam.make_current()
		await _shot("%s_rue" % city)
		# oblique : ≈ 35 m, 40° sous l'horizon
		cam.global_position = p - t * 30.0 + side * 22.0 + Vector3(0, 32.0, 0)
		cam.look_at(p + t * 15.0, Vector3.UP)
		await _shot("%s_oblique" % city)
		cam.queue_free()
		main.queue_free()
		for i in 3: await process_frame
	quit()
