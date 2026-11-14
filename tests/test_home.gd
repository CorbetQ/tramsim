extends SceneTree
## Accueil : ville en fond (chargement, changement avec fondu), parcours, lancement avec intro (fin et passage).
## xvfb-run -a -s "-screen 0 1600x900x24" godot --path . --rendering-driver opengl3 --resolution 1600x900 -s tests/test_home.gd
## HOME_SHOTS=<dossier> : captures de l'accueil (2 villes) et de 3 instants du zoom.
var fails := 0
var shots := OS.get_environment("HOME_SHOTS")
func check(c: bool, m: String) -> void:
	if c: print("ok: ", m)
	else: fails += 1; printerr("ECHEC: ", m)

func _key(k: Key) -> void:
	var e := InputEventKey.new(); e.keycode = k; e.physical_keycode = k; e.pressed = true
	Input.parse_input_event(e); await process_frame
	var u := e.duplicate(); u.pressed = false; Input.parse_input_event(u); await process_frame

func _shot(name: String) -> void:
	if shots == "": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(shots.path_join(name + ".png"))

func _wait_city(main: Node, city: String, limit := 420.0) -> bool:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < limit * 1000.0:
		await process_frame
		if main.home_bg != null and main.home_bg.shown == city and not main.home_bg.is_loading(): return true
	return false

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.save.settings.tutorial_done = true
	main.save.settings.erase("last_run")
	main.save.settings.home_bg = true; main.save.settings.time_mode = 1; main.save.settings.intro = true
	main.menu_city = "Bordeaux"; main.menu_page = "home"; main._build_menu()
	for i in 3: await process_frame
	check(main.find_child("card_mission", true, false) != null and main.find_child("card_free", true, false) != null, "accueil : cartes de mode")
	check(main.find_child("settings", true, false) != null, "accueil : réglages accessibles")
	check(main.home_bg is HomeBackground or main._city_loading_layer.visible, "accueil : fond 3D différé pendant le chargement obligatoire")
	var t0 := Time.get_ticks_msec()
	check(await _wait_city(main, "Bordeaux"), "accueil : Bordeaux vue du ciel chargée")
	print("chargement fond Bordeaux : %d ms" % (Time.get_ticks_msec() - t0))
	var frames := Engine.get_frames_drawn()
	await create_timer(1.2).timeout
	check(main.home_bg.layer_count() == 1, "un seul calque après le fondu")
	var bg_cam: Camera3D = main.home_bg._layers[-1].cam
	check(bg_cam.projection == Camera3D.PROJECTION_ORTHOGONAL and bg_cam.global_basis.z.dot(Vector3.UP) > 0.9999, "accueil : vue verticale orthographique orientée au nord")
	check(Engine.get_frames_drawn() - frames > 3, "l'accueil reste fluide pendant le survol")
	var lines: Node = main.home_bg.find_child("tram_lines", true, false)
	check(lines != null and lines.get_child_count() == 2, "lignes de tram en surbrillance")
	await _shot("home_bordeaux")
	# cibles tactiles >= 44 px
	var small := 0
	for b in main.find_children("*", "Button", true, false):
		if b.is_visible_in_tree() and b.size.y < 44.0: small += 1
	check(small == 0, "accueil : cibles tactiles >= 44 px (%d trop petites)" % small)
	# parcours : 1 -> configuration mission, changement de ville, Échap -> accueil
	await _key(KEY_1)
	for i in 3: await process_frame
	check(main.menu_page == "setup" and not main.free_mode, "touche 1 : configuration d'une mission")
	var picker: CityPicker = main._menu.picker
	check(picker != null and picker.selected == "Bordeaux", "ville courante présélectionnée")
	picker.search.text = "ange"; picker.search.text_changed.emit("ange"); picker.search.text_submitted.emit("ange")
	for i in 3: await process_frame
	check(picker.selected == "Angers" and main.menu_city == "Angers", "recherche + Entrée : Angers choisie")
	check(main.home_bg.city == "Angers", "changement de ville demandé au fond")
	check(await _wait_city(main, "Angers"), "fond : Angers chargée")
	check(main.home_bg.layer_count() == 2, "fondu enchaîné entre les deux villes")
	await create_timer(1.2).timeout
	check(main.home_bg.layer_count() == 1, "ancienne ville libérée après le fondu")
	var summary: Node = main.find_child("summary", true, false)
	check(summary != null and summary.is_visible_in_tree(), "résumé de la sélection visible")
	small = 0
	for b in main.find_children("*", "Button", true, false):
		if b.is_visible_in_tree() and b.size.y < 44.0: small += 1; print("  petite cible : ", b.name, " ", b.size)
	check(small == 0, "configuration : cibles tactiles >= 44 px")
	await _shot("home_angers")
	await _key(KEY_ESCAPE)
	for i in 3: await process_frame
	check(main.menu_page == "home", "Échap : retour à l'accueil")
	await _key(KEY_1)
	for i in 3: await process_frame
	# lancement (Entrée) : intro puis caméra de jeu
	await _key(KEY_ENTER)
	var launch_deadline := Time.get_ticks_msec() + 120000
	while main.intro == null and Time.get_ticks_msec() < launch_deadline: await process_frame
	check(main.session != null and main.intro != null, "Entrée : sortie du menu puis partie lancée avec l'intro")
	check(main.home_bg == null, "fond d'accueil libéré au lancement")
	if main.intro == null: _end(main); return
	var intro: IntroCamera = main.intro
	check(main.city_preload.ready_city == "" and CityDataStore.document("res://data/scenes/angers.json") is Dictionary, "données réutilisées ; LOD préparé pendant l’intro")
	check(intro.duration >= 4.0 and intro.duration <= 6.0, "durée de l'intro %.1f s" % intro.duration)
	check(intro.cam.current and not main.view.cam.current, "caméra d'intro active")
	var hud: Node = main.find_child("trip", true, false)
	check(hud != null and not hud.visible, "HUD masqué pendant l'intro")
	var final: Transform3D = main.view.cam.global_transform
	var heights: Array = []
	var start_ms := Time.get_ticks_msec()
	var marks := [0.9, 2.6, 4.0]
	var time0: float = main.session.time_s
	var intro_end := [0.0]
	intro.finished.connect(func(): intro_end[0] = intro.t)
	while main.intro != null and Time.get_ticks_msec() - start_ms < 90000:
		await process_frame
		if main.intro == null: break
		heights.append(intro.cam.global_position.y - final.origin.y)
		if not marks.is_empty() and intro.t >= marks[0]:
			marks.pop_front(); await _shot("intro_%d" % (3 - marks.size()))
	var took := (Time.get_ticks_msec() - start_ms) / 1000.0
	check(main.intro == null and intro_end[0] >= 4.0, "intro terminée seule (%.1f s réelles)" % took)
	check(heights.size() > 20 and heights[0] > 600.0 and heights[-1] < 80.0, "zoom du ciel (%.0f m) vers la rame" % (heights[0] if heights else 0.0))
	var mono := true
	for i in range(1, heights.size()): mono = mono and heights[i] <= heights[i - 1] + 0.5
	check(mono, "descente continue, sans à-coup")
	check(is_equal_approx(main.session.time_s, time0), "session figée pendant l'intro")
	await process_frame
	check(main.view.cam.current and main.view.cam.global_transform.origin.distance_to(final.origin) < 1.0, "passage fluide à la caméra de jeu")
	await create_timer(0.5).timeout
	check(hud.modulate.a > 0.9, "HUD affiché après l'intro")
	# relance : touche pour passer
	main._persist(); main.menu_page = "home"; main._build_menu()
	for i in 3: await process_frame
	check(main.find_child("resume", true, false) != null, "accueil : « Reprendre la dernière partie »")
	var resume_ready := Time.get_ticks_msec() + 120000
	while (not main._ready_for_launch(main.menu_city) or main._city_loading_layer.visible) and Time.get_ticks_msec() < resume_ready: await process_frame
	await _key(KEY_R)
	var resume_deadline := Time.get_ticks_msec() + 120000
	while main.intro == null and Time.get_ticks_msec() < resume_deadline: await process_frame
	check(main.intro != null, "R : reprise avec intro")
	await create_timer(0.6).timeout
	await _key(KEY_SPACE)
	var skip_deadline := Time.get_ticks_msec() + 60000
	while main.intro != null and Time.get_ticks_msec() < skip_deadline: await process_frame
	check(main.intro == null and main.view.cam.current, "touche : intro passée")
	check(not main.emergency, "la touche de passage n'actionne pas la rame")
	_end(main)

func _end(main: Node) -> void:
	main.queue_free(); await process_frame
	print("TOTAL_ECHECS|", fails); quit(1 if fails else 0)
