extends SceneTree
## Refonte P0 (docs/CDC_REFONTE_VISUELLE.md §7.2) : budgets de rendu et histogramme des captures sur des points
## d'audit fixes (Angers, station la plus dense de la ligne principale) : 3e personne, cabine, verticale, nuit.
## - draw calls et triangles par image (Performance.get_monitor) ≤ budgets.json du profil actif. Le profil « repli »
##   (Compatibility) tourne sur PC : il est jugé sur le budget « high ».
## - P1 : seconde passe au contenu Mobile (DayNight.low_quality, LOD/HLOD Mobile de la végétation, du mobilier et des
##   détails, textures 1024², réglages du profil Mobile) jugée BLOQUANTE sur le budget « mobile » (≤ 600 draw calls,
##   ≤ 800 k triangles, ombres comprises).
## - histogramme : noir pur (< 3/255) ≤ acceptance.pure_black_pct_max (2 %), sursaturation (un canal ≥ 254/255)
##   ≤ SATURATED_MAX, luminance moyenne dans [LUMA_MIN, LUMA_MAX] de jour (ni image bouchée ni délavée).
## Nécessite un affichage : xvfb-run … --rendering-driver opengl3 --rendering-method gl_compatibility (run_all.sh).
## Args optionnels : -- <dossier de sortie des captures>
const SATURATED_MAX := 0.03
const LUMA_MIN := 0.22
const LUMA_MAX := 0.75
const BUDGET_OF := {"ultra": "ultra_pc", "high": "high", "mobile": "mobile", "fallback": "high"}

var fails := 0
var main
var budgets: Dictionary
var budget: Dictionary
var out := ""
var pass_name := ""

func check(c: bool, m: String) -> void:
	if c: print("ok: ", m)
	else: fails += 1; printerr("ECHEC: ", m)

func _init() -> void:
	_run.call_deferred()

## Part de noir pur, de pixels saturés et luminance moyenne (réduction 320×180).
static func histogram(img: Image) -> Dictionary:
	img = img.duplicate(); img.convert(Image.FORMAT_RGB8); img.resize(320, 180, Image.INTERPOLATE_NEAREST)
	var black := 0; var sat := 0; var luma := 0.0
	var n := 320 * 180
	for y in 180:
		for x in 320:
			var c := img.get_pixel(x, y)
			if maxf(c.r, maxf(c.g, c.b)) < 3.0 / 255.0: black += 1
			if maxf(c.r, maxf(c.g, c.b)) >= 254.0 / 255.0: sat += 1
			luma += 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
	return {"black": float(black) / n, "saturated": float(sat) / n, "luma": luma / n}

func _shot(name: String, day: bool) -> void:
	for i in 8: await process_frame
	await RenderingServer.frame_post_draw
	var draws := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var tris := int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	var img := root.get_texture().get_image()
	name = pass_name + name
	if out != "": img.save_png("%s/%s.png" % [out, name])
	var h := histogram(img)
	var ai_n := 0; var hd_n := 0
	if main.view.ai_view != null:
		for id in main.view.ai_view.roots:
			if (main.view.ai_view.roots[id] as Node3D).visible: ai_n += 1
		for id in main.view.ai_view.rigs:
			if main.view.ai_view.rigs[id].hd != null: hd_n += 1
	print("BUDGET|%s|draws=%d|tris=%d|noir=%.2f%%|sature=%.2f%%|luma=%.2f|ia_visibles=%d|ia_hd=%d|hd_lod=%d" % [name, draws, tris, h.black * 100.0, h.saturated * 100.0, h.luma, ai_n, hd_n, main.view.hd_lod])
	check(draws > 0 and draws <= int(budget.draw_calls_max), "%s : %d draw calls ≤ %d" % [name, draws, int(budget.draw_calls_max)])
	check(tris > 0 and tris <= int(budget.visible_tris_max), "%s : %d triangles ≤ %d" % [name, tris, int(budget.visible_tris_max)])
	var mob: Dictionary = budgets.profiles.mobile
	if pass_name == "" and (draws > int(mob.draw_calls_max) or tris > int(mob.visible_tris_max)):
		print("INFO|%s : au-delà du budget Mobile (%d draws, %d triangles) au contenu PC (jugé par la passe mobile_)" % [name, int(mob.draw_calls_max), int(mob.visible_tris_max)])
	check(h.black * 100.0 <= float(budgets.acceptance.pure_black_pct_max), "%s : noir pur %.2f %% ≤ %s %%" % [name, h.black * 100.0, budgets.acceptance.pure_black_pct_max])
	check(h.saturated <= SATURATED_MAX, "%s : pixels saturés %.2f %% ≤ %.0f %%" % [name, h.saturated * 100.0, SATURATED_MAX * 100.0])
	if day: check(h.luma >= LUMA_MIN and h.luma <= LUMA_MAX, "%s : luminance moyenne %.2f dans [%.2f, %.2f]" % [name, h.luma, LUMA_MIN, LUMA_MAX])

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	out = args[0] if args.size() > 0 else ""
	if out != "": DirAccess.make_dir_recursive_absolute(out)
	budgets = JSON.parse_string(FileAccess.get_file_as_string("res://docs/refonte-visuelle/budgets.json"))
	if DisplayServer.get_name() == "headless":
		print("SKIP test_render_budgets : affichage requis"); print("TOTAL_ECHECS|0"); quit(0); return
	await _pass(false)
	await _pass(true)
	print("TOTAL_ECHECS|%d" % fails)
	quit(1 if fails > 0 else 0)

func _pass(mobile: bool) -> void:
	pass_name = "mobile_" if mobile else ""
	DayNight.low_quality = mobile or OS.has_feature("mobile")
	root.size = Vector2i(1280, 720)
	main = load("res://src/ui/main.tscn").instantiate(); root.add_child(main)
	await process_frame
	main.save.settings.tutorial_done = true
	main.save.settings.traffic = true
	main.save.settings.visual_profile = "auto"
	var idx: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/index.json"))
	var line := {}
	for n in idx.networks:
		if str(n.id).begins_with("angers") and n.kind == "tram" and (line.is_empty() or float(n.length_km) > float(line.length_km)): line = n
	main.net_path = str(line.path); main.free_mode = false
	var net := NetworkLoader.new(); net.load_file(main.net_path)
	main.vehicle = VehicleLibrary.default_for(net.meta)
	main.mission = net.missions()[0]
	main._start(); main.paused = true
	for c in main.get_children():
		if c is Control or c is CanvasLayer: c.visible = false
	var profile := VisualEffects.effective_profile("auto")
	if mobile:
		profile = "mobile"
		VisualEffects.apply_profile("mobile", main.view.day_night.env, main.view.day_night.sun, root, "mobile")
		PbrMaterials.set_profile("mobile")
	budget = budgets.profiles[BUDGET_OF[profile]]
	print("BUDGET|profil=%s|renderer=%s|budget=%s" % [profile, VisualEffects.renderer(), BUDGET_OF[profile]])
	# point d'audit : station sur la tuile de décor la plus chargée (comme tests/audit/audit_shots.gd « dense »)
	var cs = main.view.city
	var best := {}; var bb := -1
	for s in net.stations:
		var p: Vector3 = main.view.pos3(s.edge, float(s.offset))
		var b := 0
		if cs != null:
			var c: Vector3 = p - cs.position; c.x /= cs._x_scale
			b = int(cs.table.get(Vector2i(floori(c.x / cs.tile_m), floori(c.z / cs.tile_m)), Vector2i.ZERO).y)
		if b > bb: bb = b; best = s
	var L: float = main.net.graph.edges[best.edge].length
	main.session.edge_id = best.edge; main.session.route.assign([best.edge])
	main.session.offset = clampf(float(best.offset), 1.0, maxf(1.0, L - 1.0)); main.view._rig_fresh = true
	print("BUDGET|point|%s" % best.name)
	main.hour0 = 13.5 - main.session.time_s / 3600.0; main.view.set_hour(13.5)
	main.external_cam = true; main.view.orbit = 0.6; main.view.cam_dist = 32.0
	await process_frame
	if cs: cs.warm(main.view.cam.global_position)
	await _shot("dense_ext", true)
	# rames IA visibles (P2) : 4 rames garées devant la rame du joueur, LOD HD des rames IA (Mobile : un cran
	# plus bas, au plus 3 rames en LOD0) ; même contenu, budget inchangé.
	var extra: Array = []
	var lod0 := [1 if main.view.hd_lod == 0 else 0]
	var ia_liv: Dictionary = main.view.livery
	if not StockHD.entry("angers__citadis_x05").is_empty():   # rames HD livrées : rames IA en X05 HD
		ia_liv = TramModel.livery_for(main.net.meta, StockCatalog.find("angers__citadis_x05"))
	for k in 4:
		var rig := TramModel.build_rig(ia_liv)
		var holder := Node3D.new(); main.view.add_child(holder); extra.append(holder)
		for m in rig.modules: holder.add_child(m)
		rig.layout_straight()
		var f0: Transform3D = main.view._frame(main.session.edge_id, main.session.offset)
		var fwd := -f0.basis.z * float(main.session.direction)
		var f := Transform3D(f0.basis, f0.origin + fwd * (22.0 + 40.0 * k) + f0.basis.x * (3.3 if k % 2 == 0 else -3.3))
		holder.global_transform = f
		if rig.hd != null:
			var l := StockHD.lod_for(main.view.cam.global_position.distance_to(f.origin), -1, true)
			if l == 0 and StockHD.mobile() and lod0[0] >= StockHD.MOBILE_MAX_LOD0: l = 1
			if l == 0: lod0[0] += 1
			rig.hd.set_lod(l); rig.hd.update({"headlights": 0.45}, 0.0)
	await _shot("dense_ia", true)
	print("BUDGET|dense_ia|lod0=%d" % lod0[0])
	for h in extra: h.queue_free()
	main.external_cam = false
	await _shot("dense_cab", true)
	main.external_cam = true
	var pos: Vector3 = main.view.pos3(main.session.edge_id, main.session.offset)
	var aer := Camera3D.new(); aer.far = 3000.0; aer.near = 5.0; aer.fov = rad_to_deg(2.0 * atan(125.0 / 600.0))
	main.add_child(aer); aer.global_position = pos + Vector3(0, 600, 0); aer.look_at(pos, Vector3(0, 0, -1)); aer.make_current()
	if cs: cs.warm(pos)
	await _shot("dense_aer", true)
	main.view.cam.make_current()
	main.hour0 = 22.5 - main.session.time_s / 3600.0; main.view.set_hour(22.5)
	await _shot("dense_nuit", false)
	main.queue_free(); await process_frame; await process_frame
