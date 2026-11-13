extends SceneTree
## Audit visuel 0.11 : prises de vue automatiques d'une ville (ligne principale = plus longue ligne tram de data/index.json).
## Args : -- <dossier> <ville> [points]  (ville = préfixe d'identifiant : angers, idf, saintetienne…)
## 4 points choisis automatiquement : dense (station sur la tuile de décor la plus chargée), pont (plus long tablier),
## pente (plus longue trémie/tunnel, sinon plus forte déclivité), term (terminus le plus éloigné du centre).
## Vues : ext (3e personne, 13h30), cab (cabine), aer (verticale, focale longue, 250 m au sol, nord en haut), nuit (dense, 22h30).
## Sortie : <dossier>/<ville>_<point>_<vue>.png et lignes "AUDIT|..." (lat/lon du centre des vues aériennes, stats rendu,
## part de la couleur dominante : ECHEC au-delà de 45 % en vue 3e personne ou cabine).
const AERIAL_M := 250.0
const AERIAL_H := 600.0

var main
var out := ""
var city := ""

func _init() -> void:
	_run.call_deferred()

func _pick_line(c: String) -> Dictionary:
	var idx: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/index.json"))
	var best := {}
	for n in idx.networks:
		if str(n.id).split("_")[0] != c: continue
		var score := (1000.0 if n.kind == "tram" else 0.0) + float(n.length_km)
		if best.is_empty() or score > best.score: best = {"score": score, "n": n}
	return best.get("n", {})

func _tile_bytes(p: Vector3) -> int:
	var cs = main.view.city
	if cs == null: return 0
	var c: Vector3 = p - cs.position; c.x /= cs._x_scale
	var k := Vector2i(floori(c.x / cs.tile_m), floori(c.z / cs.tile_m))
	return int(cs.table.get(k, Vector2i.ZERO).y)

func _longest(edges: Array, key: String) -> Dictionary:
	var best := {}; var bl := 0.0
	for e in edges:
		for iv in e.get(key, []):
			var l := float(iv[1]) - float(iv[0])
			if l > bl: bl = l; best = {"edge": e.id, "a": float(iv[0]), "b": float(iv[1]), "len": l}
	return best

func _points(net: NetworkLoader) -> Array:
	var pts: Array = []
	var dense := {}; var db := -1
	for s in net.stations:
		var b := _tile_bytes(main.view.pos3(s.edge, float(s.offset)))
		if b > db: db = b; dense = s
	pts.append({"name": "dense", "edge": dense.edge, "offset": float(dense.offset), "info": "%s tuile=%d o" % [dense.name, db]})
	var br := _longest(net.meta.edges, "bridge")
	if not br.is_empty():
		pts.append({"name": "pont", "edge": br.edge, "offset": (br.a + br.b) * 0.5, "info": "tablier %.0f m" % br.len})
	else:
		var s2: Dictionary = net.stations[net.stations.size() / 2]
		pts.append({"name": "pont", "edge": s2.edge, "offset": float(s2.offset), "info": "AUCUN pont sur la ligne : station mediane %s" % s2.name})
	var tu := _longest(net.meta.edges, "tunnel")
	if not tu.is_empty():
		pts.append({"name": "pente", "edge": tu.edge, "offset": maxf(0.0, tu.a - 25.0), "info": "tremie avant tunnel %.0f m" % tu.len})
	else:
		var bg := 0.0; var be := {}
		for e in net.meta.edges:
			if float(e.length) > 40.0 and absf(float(e.get("grade", 0.0))) > bg: bg = absf(float(e.grade)); be = e
		pts.append({"name": "pente", "edge": be.id, "offset": float(be.length) * 0.5, "info": "declivite %.1f %%" % (bg * 100.0)})
	var p0: Vector3 = main.view.pos3(dense.edge, float(dense.offset))
	var t: Dictionary = net.stations[0]
	var tl: Dictionary = net.stations[net.stations.size() - 1]
	if main.view.pos3(tl.edge, float(tl.offset)).distance_to(p0) > main.view.pos3(t.edge, float(t.offset)).distance_to(p0): t = tl
	pts.append({"name": "term", "edge": t.edge, "offset": float(t.offset), "info": "terminus %s" % t.name})
	return pts

func _place(edge: String, off: float) -> void:
	var L: float = main.net.graph.edges[edge].length
	off = clampf(off, 1.0, maxf(1.0, L - 1.0))
	main.session.edge_id = edge; main.session.route.assign([edge]); main.session.offset = off
	main.view._rig_fresh = true

func _hour(h: float) -> void:
	main.hour0 = h - main.session.time_s / 3600.0
	main.view.set_hour(h)

func _shot(name: String) -> void:
	var t0 := Time.get_ticks_msec()
	for i in 10: await process_frame
	await RenderingServer.frame_post_draw
	var dt := (Time.get_ticks_msec() - t0) / 10.0
	root.get_texture().get_image().save_png("%s/%s_%s.png" % [out, city, name])
	var prim := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
	var draws := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	print("AUDIT|shot|%s|%s|ms=%.0f|prims=%d|draws=%d|tiles=%d" % [city, name, dt, prim, draws, main.view.city.built.size() if main.view.city else 0])
	_color_check(root.get_texture().get_image(), name)

## Contrôle « pas plus de 45 % d'une même couleur à l'écran » (caméra dans un mur, un houppier, la rame, sous le
## terrain, ou aplat) : histogramme sur 16 niveaux par canal d'une réduction 320×180 (plus proche voisin).
const COLOR_MAX := 0.45
var color_failures := 0
func _color_check(img: Image, name: String) -> void:
	img.resize(320, 180, Image.INTERPOLATE_NEAREST)
	var hist := {}
	for y in 180:
		for x in 320:
			var c := img.get_pixel(x, y)
			var key := (int(c.r * 15.99) << 8) | (int(c.g * 15.99) << 4) | int(c.b * 15.99)
			hist[key] = int(hist.get(key, 0)) + 1
	var top := 0; var top_key := 0
	for k in hist:
		if hist[k] > top: top = hist[k]; top_key = k
	var share := float(top) / (320.0 * 180.0)
	var ok := share <= COLOR_MAX or name.ends_with("_aer") or name.ends_with("_nuit")
	if not ok: color_failures += 1
	print("AUDIT|couleur|%s|%s|%.0f%%|#%x%x%x|%s" % [city, name, share * 100.0, top_key >> 8, (top_key >> 4) & 15, top_key & 15, "OK" if ok else "ECHEC"])

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	out = args[0]; city = args[1]
	var only: PackedStringArray = args[2].split(",") if args.size() > 2 else PackedStringArray()
	DirAccess.make_dir_recursive_absolute(out)
	var line := _pick_line(city)
	if line.is_empty(): print("AUDIT|ECHEC|ville inconnue ", city); quit(1); return
	root.size = Vector2i(1280, 720)
	main = load("res://src/ui/main.tscn").instantiate(); root.add_child(main)
	await process_frame
	main.save.settings.tutorial_done = true
	main.save.settings.traffic = true
	main.net_path = str(line.path); main.free_mode = false
	var net := NetworkLoader.new(); net.load_file(main.net_path)
	main.vehicle = VehicleLibrary.default_for(net.meta)
	main.mission = net.missions()[0]
	main._start(); main.paused = true
	for c in main.get_children():
		if c is Control or c is CanvasLayer: c.visible = false
	var lat0 := float(net.meta.origin[0]); var lon0 := float(net.meta.origin[1])
	print("AUDIT|line|%s|%s|%s|scene=%s" % [city, line.id, line.long_name, main.view.city != null])
	# Perspective à focale longue (et non orthographique) : mêmes chemins de shader qu'en jeu.
	var aer := Camera3D.new(); aer.keep_aspect = Camera3D.KEEP_HEIGHT; aer.far = 3000.0; aer.near = 5.0
	aer.fov = rad_to_deg(2.0 * atan(AERIAL_M * 0.5 / AERIAL_H))
	main.add_child(aer)
	for p in _points(net):
		if not only.is_empty() and not p.name in only: continue
		_place(p.edge, p.offset)
		var pos: Vector3 = main.view.pos3(main.session.edge_id, main.session.offset)
		var lat := lat0 - rad_to_deg(pos.z / CityScene.R)
		var lon := lon0 + rad_to_deg(pos.x / (CityScene.R * cos(deg_to_rad(lat0))))
		var grd: float = main.view.ground_at(pos)
		print("AUDIT|point|%s|%s|%s|%.2f|%.6f|%.6f|rail_y=%.2f|sol_y=%.2f|%s" % [city, p.name, p.edge, main.session.offset, lat, lon, pos.y, grd, p.info])
		_hour(13.5)
		if OS.get_environment("AUDIT_FOG") == "0": main.view.day_night.env.fog_enabled = false  # diagnostic
		main.external_cam = true; main.view.orbit = 0.6; main.view.cam_dist = 32.0
		await process_frame
		if main.view.city: main.view.city.warm(main.view.cam.global_position)
		await _shot(p.name + "_ext")
		main.external_cam = false
		await _shot(p.name + "_cab")
		main.external_cam = true
		aer.global_position = Vector3(pos.x, pos.y + AERIAL_H, pos.z)
		aer.look_at(pos, Vector3(0, 0, -1))
		aer.make_current()
		var fog: bool = main.view.day_night.env.fog_enabled
		main.view.day_night.env.fog_enabled = OS.get_environment("AUDIT_AER_FOG") == "1"
		if main.view.city: main.view.city.warm(pos)
		await _shot(p.name + "_aer")
		main.view.day_night.env.fog_enabled = fog
		main.view.cam.make_current()
		if p.name == "dense":
			_hour(22.5)
			await _shot(p.name + "_nuit")
	print("AUDIT|fin|%s|couleur_echecs=%d" % [city, color_failures])
	main.queue_free(); await process_frame
	quit()
