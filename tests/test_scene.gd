extends SceneTree
func _run(main: Node, free: bool) -> bool:
	main.free_mode = free
	main.net_path = "res://tests/fixtures/schema_test.json"
	main.vehicle = VehicleLibrary.citadis_302_hybride()
	main._start()
	for i in 30: await process_frame
	var ok: bool = main.session != null and main.view != null and main.view.tram != null
	ok = ok and main.hud_speed is Speedometer and main.lever is NotchLever and main.lamps.size() == 4
	if free:
		main._toggle_plan()
		for i in 3: await process_frame
		ok = ok and main.plan_panel != null and main.plan_panel.switch_pos.size() > 0
		main._toggle_plan()
	print("scène (libre=%s): %s | %s" % [free, ok, main.hud_info.text])
	return ok
func _init() -> void:
	var main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var a = await _run(main, false)
	var b = await _run(main, true)
	main.menu_page = "home"; main._build_menu()
	await process_frame
	var c: bool = main.find_child("card_mission", true, false) != null and main.find_child("card_free", true, false) != null
	main.menu_page = "setup"; main._build_menu()
	for i in 3: await process_frame
	var go = main.find_child("start", true, false)
	var t0 := Time.get_ticks_msec()   # préchargement de la ville (lent sur la CI) : attendre l'activation du départ
	while go is Button and go.disabled and Time.get_ticks_msec() - t0 < 120000:
		await process_frame
		go = main.find_child("start", true, false)
	c = c and go is Button and not go.disabled
	print("menu : accueil + configuration ", c)
	quit(0 if a and b and c else 1)
