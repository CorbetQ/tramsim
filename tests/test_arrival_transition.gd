extends SceneTree
var failures := 0
var shots := OS.get_environment("ARRIVAL_SHOTS")
func check(ok: bool, text: String) -> void:
	if ok: print("ok: ", text)
	else: failures += 1; printerr("ECHEC: ", text)
func _initialize() -> void: _run.call_deferred()
func shot(name_: String) -> void:
	if shots == "": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(shots.path_join(name_ + ".png"))
func _run() -> void:
	var main = load("res://src/ui/main.tscn").instantiate()
	main.menu_city = "Angers"; main.menu_page = "setup"; main.free_mode = true
	root.add_child(main)
	main.save.settings.home_bg = true; main.save.settings.intro = true; main.save.settings.tutorial_done = true
	main.save.settings.traffic = false; main._build_menu()
	check(main._city_loading_layer.visible and main._menu.go.disabled, "écran de chargement obligatoire et départ grisé")
	main._menu.go.pressed.emit()
	check(main.session == null and not main._launching, "aucun départ prématuré")
	await shot("01_loading")
	var deadline := Time.get_ticks_msec() + 180000
	while (not main._ready_for_launch("Angers") or main._menu.go.disabled or main._city_loading_layer.visible) and Time.get_ticks_msec() < deadline:
		await process_frame
	check(main._ready_for_launch("Angers") and not main._menu.go.disabled and not main._city_loading_layer.visible, "données et vue aérienne prêtes avant lancement")
	if main._menu.go.disabled: main.queue_free(); await process_frame; quit(1); return
	await shot("02_ready")
	var render_scale0 := root.scaling_3d_scale
	var msaa0 := root.msaa_3d
	var source_pose: Transform3D = main.home_bg._layers[-1].cam.global_transform
	var reads := CityDataStore.disk_reads
	main._menu.go.pressed.emit()
	check(main._launching and main.session == null, "le menu sort avant la création de la partie")
	await create_timer(0.20).timeout
	check(main.session == null, "fondu et zoom du menu visibles avant le départ")
	await shot("03_menu_fade")
	deadline = Time.get_ticks_msec() + 180000
	while main.intro == null and Time.get_ticks_msec() < deadline: await process_frame
	check(main.intro != null and main.session != null, "intro démarrée après la sortie du menu")
	if main.intro == null: quit(1); return
	var intro: IntroCamera = main.intro; intro.set_process(false)
	check(CityDataStore.disk_reads == reads, "aucune relecture des données après Lancer")
	check(main.notch == -0.75, "frein F3 conservé pendant l'arrivée")
	check(intro._pan_duration > 1.0 and is_instance_valid(intro._aerial), "LOD aérien réutilisé pour le glissement")
	var start := intro.pose_at(0.0)
	check(start.origin.distance_to(source_pose.origin) < 2.0, "continuité de position depuis l'accueil")
	var pan := intro.pose_at(IntroCamera.HOLD + intro._pan_duration * 0.5)
	check(pan.basis.z.dot(Vector3.UP) > .9999, "glissement vertical orienté au nord")
	check(absf(start.origin.y - pan.origin.y) < .1, "altitude constante pendant le glissement")
	for pair in [["04_pan", IntroCamera.HOLD + intro._pan_duration * .5], ["05_city_zoom", IntroCamera.HOLD + intro._pan_duration + .6], ["06_station_zoom", intro.duration - 1.1]]:
		intro._apply(pair[1])
		if is_instance_valid(intro._aerial) and intro._aerial.visible: intro._aerial.warm(intro.cam.global_position)
		elif main.view.city: main.view.city.warm(main.view.cam.global_position)
		await process_frame; await shot(pair[0])
	intro._apply(intro.duration)
	var final: Transform3D = main.view.cam.global_transform
	check(intro.cam.global_transform.is_equal_approx(final), "arrivée exactement sur la caméra de conduite")
	intro.skip(); await process_frame
	var skip_deadline := Time.get_ticks_msec() + 60000   # le passage attend la fin des tuiles LOD en cours
	while main.intro != null and Time.get_ticks_msec() < skip_deadline: await process_frame
	check(main.intro == null and main.view.cam.current and main.view.city.visible, "passage et restitution de la caméra/HUD")
	check(is_equal_approx(root.scaling_3d_scale, render_scale0) and root.msaa_3d == msaa0, "qualité de rendu restaurée après passage")
	await shot("07_driving")
	main.queue_free(); await CityScene.drain_background_jobs(self)
	print("TOTAL_ECHECS|", failures); quit(1 if failures else 0)
