extends SceneTree
## Refonte P3 (façades, monuments) : cadrages fixes avant/après. Centres d'Angers (Ralliement, ligne C) et de Nantes
## (Commerce, ligne 1) : cabine, rue (piéton), oblique (≈ 150 m), aérienne (≈ 450 m) ; monuments (vue oblique
## depuis un point WGS84). « Avant » : TRAMSIM_FACADES=0 TRAMSIM_P3_MONUMENTS=0 (bâti générique d'avant P3).
## Usage : godot --path . -s tests/audit/p3f_shots.gd -- <dossier> [suffixe] [mobile] [sites|monuments]
var out := "."
var suffix := ""
var mobile := false
const SITES := [["angers_c", "Ralliement", 70.0], ["nantes_1", "Commerce", 60.0]]
## [réseau, nom, lat, lon, distance, hauteur, azimut (degrés, 0 = depuis le sud), visée au-dessus du sol]
const MONUMENTS := [
	["angers_c", "chateau_angers", 47.46995, -0.55985, 260.0, 120.0, 120.0, 10.0],
	["angers_c", "gare_saint_laud", 47.46455, -0.55655, 140.0, 55.0, 20.0, 8.0],
	["angers_c", "hotel_de_ville_angers", 47.47080, -0.54830, 120.0, 55.0, 140.0, 10.0],
	["nantes_1", "chateau_nantes", 47.21625, -1.54934, 210.0, 80.0, 215.0, 0.0],
	["nantes_1", "cathedrale_nantes", 47.21790, -1.55030, 230.0, 90.0, 160.0, 25.0],
	["nantes_1", "tour_bretagne", 47.21760, -1.55825, 330.0, 60.0, 150.0, 70.0],
	["nantes_1", "gare_nantes", 47.21750, -1.54200, 190.0, 70.0, 10.0, 8.0],
	["nantes_1", "lieu_unique", 47.21500, -1.54580, 140.0, 50.0, 330.0, 20.0],
	["nantes_1", "passage_pommeraye", 47.21288, -1.55961, 40.0, 8.0, 166.0, 9.0],
	["nantes_1", "elephant", 47.20675, -1.56425, 55.0, 14.0, 290.0, 6.0],
]

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
	for i in 16: await process_frame
	await RenderingServer.frame_post_draw
	var draws := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var tris := int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	var img := root.get_texture().get_image()
	img.save_png("%s/%s%s.png" % [out, name, suffix])
	print("SHOT|%s%s|draws=%d|tris=%d" % [name, suffix, draws, tris])

func _net_point(main, lat: float, lon: float) -> Vector3:
	var o: Array = main.net.meta.origin
	var x := deg_to_rad(lon - float(o[1])) * CityScene.R * cos(deg_to_rad(float(o[0])))
	var z := -deg_to_rad(lat - float(o[0])) * CityScene.R
	var y := 0.0
	var cs = main.view.city
	if cs != null and cs.has_terrain: y = cs.height_at(Vector3(x, 0, z))
	return Vector3(x, y, z)

func _run() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() > 0: out = a[0]
	if a.size() > 1: suffix = a[1]
	mobile = "mobile" in a.slice(2)
	var only := ""
	for w in a.slice(2):
		if w in ["sites", "monuments"]: only = w
	if mobile: DayNight.low_quality = true
	DirAccess.make_dir_recursive_absolute(out)
	root.size = Vector2i(1280, 720)
	for site in (SITES if only != "monuments" else []):
		var main = await _start(site[0])
		var st: Dictionary = {}
		for s in main.net.stations:
			if str(s.name) == site[1]: st = s; break
		var city: String = str(site[0]).get_slice("_", 0)
		var L: float = main.net.graph.edges[st.edge].length
		main.session.edge_id = st.edge; main.session.route.assign([st.edge])
		main.session.offset = clampf(float(st.offset) - float(site[2]), 1.0, maxf(1.0, L - 1.0)); main.view._rig_fresh = true
		main.hour0 = 10.5 - main.session.time_s / 3600.0; main.view.set_hour(10.5)
		await process_frame
		var p: Vector3 = main.view.pos3(st.edge, main.session.offset)
		if main.view.city: main.view.city.warm(p)
		main.external_cam = false
		await _shot("%s_cabine" % city)
		var t: Vector3 = main.view.pos3(st.edge, main.session.offset + 5.0) - main.view.pos3(st.edge, main.session.offset - 5.0)
		t.y = 0.0; t = t.normalized()
		var side := t.cross(Vector3.UP)
		var cam := Camera3D.new(); cam.fov = 60.0; cam.far = 6000.0
		main.add_child(cam)
		cam.global_position = p + side * 7.5 + Vector3(0, 1.65, 0) - t * 4.0
		cam.look_at(p + t * 35.0 - side * 4.0 + Vector3(0, 6.0, 0), Vector3.UP)
		cam.make_current()
		await _shot("%s_rue" % city)
		cam.global_position = p - t * 110.0 + side * 70.0 + Vector3(0, 75.0, 0)
		cam.look_at(p + t * 20.0, Vector3.UP)
		await _shot("%s_oblique150" % city)
		cam.global_position = p - t * 180.0 + side * 120.0 + Vector3(0, 420.0, 0)
		cam.look_at(p + t * 60.0, Vector3.UP)
		await _shot("%s_aerienne" % city)
		main.queue_free()
		for i in 3: await process_frame
	var cur := ""
	var main = null
	var pick: Array = []
	for w in a.slice(2):
		if str(w).begins_with("only="): pick = str(w).substr(5).split(",")
	for m in (MONUMENTS if only != "sites" else []):
		if not pick.is_empty() and not (m[1] in pick): continue
		if m[0] != cur:
			if main != null: main.queue_free(); for i in 3: await process_frame
			main = await _start(m[0]); cur = m[0]
			main.hour0 = 10.5 - main.session.time_s / 3600.0; main.view.set_hour(10.5)
		var tgt := _net_point(main, m[2], m[3])
		# rame posée à la station la plus proche : la ville se charge autour de la rame
		var best: Dictionary = {}; var bd := INF
		for s in main.net.stations:
			var d: float = main.view.pos3(s.edge, float(s.offset)).distance_to(tgt)
			if d < bd: bd = d; best = s
		main.session.edge_id = best.edge; main.session.route.assign([best.edge])
		main.session.offset = float(best.offset); main.view._rig_fresh = true
		await process_frame
		tgt = _net_point(main, m[2], m[3])
		var az := deg_to_rad(float(m[6]))
		var eye := tgt + Vector3(sin(az), 0, cos(az)) * float(m[4]) + Vector3(0, float(m[5]), 0)
		if main.view.city: main.view.city.warm(tgt)
		var cam := Camera3D.new(); cam.fov = 55.0; cam.far = 6000.0
		main.add_child(cam); cam.global_position = eye
		cam.look_at(tgt + Vector3(0, float(m[7]), 0), Vector3.UP); cam.make_current()
		main.external_cam = true
		await _shot("mon_%s" % m[1])
		cam.queue_free()
	quit()
