extends SceneTree
## Refonte P4 (villes) : cadrages fixes avant/après par ville. Réseau par défaut (ligne de tram la plus longue de la
## ville, data/index.json), station sur la tuile de décor la plus chargée (comme test_render_budgets) : cabine et
## oblique (≈ 150 m). Option « mon » : monuments P4 de landmark_models.json (vue oblique automatique).
## Usage : godot --path . -s tests/audit/p4v_shots.gd -- <dossier> <suffixe> [mobile] [mon] ville1 ville2 ...
var out := "."
var suffix := ""
var mobile := false
## Station de centre-ville par ville (point WGS84 : la station la plus proche, toutes lignes de tram confondues).
const CENTERS := {"lyon": [45.7530, 4.8290], "bordeaux": [44.8414, -0.5700], "strasbourg": [48.5835, 7.7458],
	"lille": [50.6365, 3.0705], "toulouse": [43.5925, 1.4440], "marseille": [43.2985, 5.3780], "nice": [43.6975, 7.2700],
	"montpellier": [43.6085, 3.8800], "grenoble": [45.1890, 5.7250], "idf": [48.8190, 2.3600], "reims": [49.2570, 4.0270],
	"dijon": [47.3240, 5.0400], "rouen": [49.4270, 1.0880], "caen": [49.1830, -0.3620], "lehavre": [49.4945, 0.1070],
	"brest": [48.3920, -4.4860], "tours": [47.3900, 0.6890], "orleans": [47.9020, 1.9050], "lemans": [48.0060, 0.1970],
	"besancon": [47.2405, 6.0230], "mulhouse": [47.7470, 7.3380], "clermont": [45.7760, 3.0820], "saintetienne": [45.4395, 4.3860],
	"avignon": [43.9420, 4.8050], "aubagne": [43.2925, 5.5680], "valenciennes": [50.3580, 3.5230],
	"angers": [47.4705, -0.5510], "nantes": [47.2135, -1.5560]}

func _init() -> void:
	_run.call_deferred()

static func default_net(city: String) -> Dictionary:
	var idx: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/index.json"))
	var line := {}
	for n in idx.networks:
		if str(n.id).get_slice("_", 0) == city and n.kind == "tram" and (line.is_empty() or float(n.length_km) > float(line.length_km)): line = n
	return line

## Réseau de tram de la ville et station les plus proches du centre (CENTERS) : [chemin, nom de station].
static func center_net(city: String) -> Array:
	var idx: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/index.json"))
	var c: Array = CENTERS.get(city, [])
	var best := []; var bd := INF
	for n in idx.networks:
		if str(n.id).get_slice("_", 0) != city or n.kind != "tram" or c.is_empty(): continue
		var doc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(str(n.path)))
		var o: Array = doc.origin
		var x := deg_to_rad(float(c[1]) - float(o[1])) * CityScene.R * cos(deg_to_rad(float(o[0])))
		var z := -deg_to_rad(float(c[0]) - float(o[0])) * CityScene.R
		var ed := {}
		for e in doc.edges: ed[e.id] = e
		for s in doc.stations:
			var e = ed.get(s.edge)
			if e == null or e.pts.is_empty(): continue
			var k := clampi(int(float(s.offset) / maxf(float(e.length), 1.0) * (e.pts.size() - 1)), 0, e.pts.size() - 1)
			var d := Vector2(float(e.pts[k][0]), float(e.pts[k][1])).distance_to(Vector2(x, z))
			if d < bd: bd = d; best = [str(n.path), str(s.name)]
	return best

func _start(path: String):
	var main = load("res://src/ui/main.tscn").instantiate(); root.add_child(main)
	await process_frame
	main.save.settings.tutorial_done = true; main.save.settings.traffic = false
	main.net_path = path; main.free_mode = false
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

static func dense_station(main) -> Dictionary:
	var cs = main.view.city
	var best := {}; var bb := -1
	for s in main.net.stations:
		var p: Vector3 = main.view.pos3(s.edge, float(s.offset))
		var b := 0
		if cs != null:
			var c: Vector3 = p - cs.position; c.x /= cs._x_scale
			b = int(cs.table.get(Vector2i(floori(c.x / cs.tile_m), floori(c.z / cs.tile_m)), Vector2i.ZERO).y)
		if b > bb: bb = b; best = s
	return best

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
	out = a[0]; suffix = a[1]
	var cities: Array = []
	var mon := false
	for w in a.slice(2):
		if w == "mobile": mobile = true
		elif w == "mon": mon = true
		else: cities.append(w)
	if mobile: DayNight.low_quality = true
	DirAccess.make_dir_recursive_absolute(out)
	root.size = Vector2i(1280, 720)
	var lm: Array = []
	if mon:
		var d = JSON.parse_string(FileAccess.get_file_as_string("res://assets/models/landmark_models.json"))
		for m in d.models:
			if str(m.get("lot", "")) == "P4": lm.append(m)
	for city in cities:
		var line := default_net(city)
		if line.is_empty(): continue
		var cn := center_net(city) if not mon else []
		var main = await _start(str(line.path) if cn.is_empty() else str(cn[0]))
		main.hour0 = 10.5 - main.session.time_s / 3600.0; main.view.set_hour(10.5)
		if not mon:
			var st := dense_station(main)
			if not cn.is_empty():
				for s2 in main.net.stations:
					if str(s2.name) == str(cn[1]): st = s2; break
			var L: float = main.net.graph.edges[st.edge].length
			main.session.edge_id = st.edge; main.session.route.assign([st.edge])
			main.session.offset = clampf(float(st.offset) - 40.0, 1.0, maxf(1.0, L - 1.0)); main.view._rig_fresh = true
			await process_frame
			var p: Vector3 = main.view.pos3(st.edge, main.session.offset)
			if main.view.city: main.view.city.warm(p)
			print("SITE|%s|%s|%s" % [city, main.net_path, st.name])
			main.external_cam = false
			await _shot("%s_cabine" % city)
			var t: Vector3 = main.view.pos3(st.edge, minf(main.session.offset + 5.0, L)) - main.view.pos3(st.edge, maxf(main.session.offset - 5.0, 0.0))
			t.y = 0.0; t = t.normalized()
			var side := t.cross(Vector3.UP)
			var cam := Camera3D.new(); cam.fov = 60.0; cam.far = 6000.0
			main.add_child(cam)
			cam.global_position = p - t * 110.0 + side * 70.0 + Vector3(0, 75.0, 0)
			cam.look_at(p + t * 20.0, Vector3.UP); cam.make_current()
			await _shot("%s_oblique150" % city)
		else:
			for m in lm:
				if str(m.city) != city: continue
				var tgt := _net_point(main, float(m.anchor[0]), float(m.anchor[1]))
				var best: Dictionary = {}; var bd := INF
				for s in main.net.stations:
					var dd: float = main.view.pos3(s.edge, float(s.offset)).distance_to(tgt)
					if dd < bd: bd = dd; best = s
				main.session.edge_id = best.edge; main.session.route.assign([best.edge])
				main.session.offset = float(best.offset); main.view._rig_fresh = true
				await process_frame
				tgt = _net_point(main, float(m.anchor[0]), float(m.anchor[1]))
				var sh: Array = m.get("shot", [180.0, 70.0, 160.0, 15.0])
				var az := deg_to_rad(float(sh[2]))
				var eye := tgt + Vector3(sin(az), 0, cos(az)) * float(sh[0]) + Vector3(0, float(sh[1]), 0)
				if main.view.city: main.view.city.warm(tgt)
				var cam := Camera3D.new(); cam.fov = 55.0; cam.far = 8000.0
				main.add_child(cam); cam.global_position = eye
				cam.look_at(tgt + Vector3(0, float(sh[3]), 0), Vector3.UP); cam.make_current()
				main.external_cam = true
				await _shot("mon_%s" % m.id)
				cam.queue_free()
		main.queue_free()
		for i in 3: await process_frame
	quit()
