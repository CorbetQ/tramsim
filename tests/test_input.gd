extends SceneTree
## Test d'entrées réelles : clics/glissers souris sur l'interface en jeu (xvfb-run ou --headless).
var fails := 0
func check(c: bool, m: String) -> void:
	if not c: fails += 1; printerr("ECHEC: ", m)
	else: print("ok: ", m)

func _click(p: Vector2) -> void:
	var d := InputEventMouseButton.new(); d.button_index = MOUSE_BUTTON_LEFT; d.pressed = true; d.position = p; d.global_position = p
	Input.parse_input_event(d)
	await process_frame
	var u := InputEventMouseButton.new(); u.button_index = MOUSE_BUTTON_LEFT; u.pressed = false; u.position = p; u.global_position = p
	Input.parse_input_event(u)
	await process_frame

func _find(main: Node, text: String) -> Button:
	for n in main.find_children("*", "Button", true, false):
		if (n as Button).text.begins_with(text) or str(n.get_meta("label", "")).begins_with(text): return n
	return null

func _key(k: Key, shift := false) -> void:
	var e := InputEventKey.new(); e.keycode = k; e.physical_keycode = k; e.pressed = true; e.shift_pressed = shift
	Input.parse_input_event(e); await process_frame
	var u := e.duplicate(); u.pressed = false; Input.parse_input_event(u); await process_frame

func _press(b: Control) -> void:
	await _click(b.get_global_rect().get_center())
	for i in 3: await process_frame

func _init() -> void:
	# Les entrées et la physique sont testées ici ; le rendu 3D est vérifié par visual_review.gd.
	root.disable_3d = true
	var main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.save.settings.tutorial_done = true
	var net := NetworkLoader.new(); net.load_file("res://data/networks/angers_a.json")
	main.net_path = "res://data/networks/angers_a.json"
	main.vehicle = VehicleLibrary.default_for(net.meta)
	main.free_mode = false
	main.mission = net.missions()[2]
	main._start(); main.view.day_night.sun.shadow_enabled = false
	for i in 5: await process_frame
	# portes (on est à quai)
	var b := _find(main, "Portes")
	check(b != null, "bouton Portes présent")
	await _click(b.get_global_rect().get_center())
	for i in 3: await process_frame
	check(main.session.doors_open, "clic Portes : portes ouvertes")
	await _click(b.get_global_rect().get_center())
	for i in 3: await process_frame
	check(not main.session.doors_open, "clic Portes : portes fermées")
	# traction : clic en haut du manipulateur
	# voyants et outils du HUD
	var pb := _find(main, "Pantographe")
	check(pb != null, "bouton Pantographe présent")
	await _press(pb)
	check(not main.session.pantograph_up, "clic Pantographe : baissé")
	check(main.lamps["panto"][3] == 0, "voyant pantographe éteint")
	await _press(pb)
	check(main.session.pantograph_up, "clic Pantographe : levé")
	var hb: Button = main.find_child("btn_help", true, false)
	await _press(hb)
	check(main.help_layer != null, "bouton aide : aide affichée")
	await _key(KEY_F1)
	check(main.help_layer == null, "F1 : aide fermée")
	check(main.hud_speed is Speedometer and main.hud_info.text != "", "tachymètre et prochain arrêt")
	var sl: NotchLever = main.lever
	var r := sl.get_global_rect()
	await _click(Vector2(r.get_center().x, r.position.y + 6))
	for i in 60: await process_frame
	print("notch=", main.notch, " vitesse=", main.session.phys.speed, " paused=", main.paused)
	check(main.notch > 0.5, "manipulateur en traction")
	check(main.session.phys.speed > 0.5, "la rame accélère")
	# clavier : freinage
	for n in 6:
		var k := InputEventKey.new(); k.keycode = KEY_S; k.physical_keycode = KEY_S; k.pressed = true
		Input.parse_input_event(k); await process_frame
		var u := k.duplicate(); u.pressed = false; Input.parse_input_event(u); await process_frame
	check(main.notch < 0.0, "touche S (x6) : freinage")
	var sp := InputEventKey.new(); sp.keycode = KEY_SPACE; sp.physical_keycode = KEY_SPACE; sp.pressed = true
	Input.parse_input_event(sp); await process_frame
	check(main.emergency and main.notch <= -0.99, "Espace : freinage d'urgence")
	for i in 120: await process_frame
	check(main.session.phys.speed < 0.1, "la rame s'arrête")
	# pause visible et reprise
	main._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	check(main.paused and main.pause_layer != null, "perte de focus : pause affichée")
	for i in 3: await process_frame
	var rb := _find(main, "Reprendre")
	await _click(rb.get_global_rect().get_center())
	for i in 3: await process_frame
	check(not main.paused, "bouton Reprendre")
	# mode libre : panneau des aiguillages
	main.free_mode = true
	main.net_path = "res://data/free/angers.json"
	var fn := NetworkLoader.new(); fn.load_file(main.net_path)
	main.start_station = fn.stations[0]
	main._start(); main.view.day_night.sun.shadow_enabled = false
	for i in 5: await process_frame
	var ab := _find(main, "Aiguillages")
	check(ab != null, "mode libre : bouton Aiguillages")
	await _click(ab.get_global_rect().get_center())
	for i in 3: await process_frame
	check(main.plan_panel != null, "panneau des aiguillages ouvert")
	var spn: NetworkPlan = main.plan_panel
	var g: TrackGraph = main.free.net.graph
	await _press(spn.filter_btns["all"])
	check(spn.filter == "all" and spn.rows.size() > 0, "filtre Tous : %d aiguillages" % spn.rows.size())
	# un aiguillage libre de la liste : clic -> bulle -> clic sur une autre branche
	var key := ""
	for k in spn._row_keys.slice(0, 5):
		if not g.switch_occupied(spn.switch_of[k][0]): key = k; break
	check(key != "", "aiguillage libre visible dans la liste")
	await _press(spn.rows[key][0])
	check(spn.selected == key and spn.popover.visible, "clic liste : aiguillage sélectionné, bulle ouverte")
	var sw: Array = spn.switch_of[key]
	var before := g.active_branch(sw[0], sw[1])
	var target: Button = null
	for bb in spn.popover.find_children("branch_*", "Button", true, false):
		if int(bb.get_meta("branch")) != before and not bb.is_queued_for_deletion(): target = bb
	check(target != null, "bulle : bouton de branche")
	await _press(target)
	check(g.active_branch(sw[0], sw[1]) != before, "clic branche : aiguillage manœuvré")
	# clavier : 1 = première branche, Tab = aiguillage suivant
	await _key(KEY_1)
	check(g.active_branch(sw[0], sw[1]) == 0, "touche 1 : branche 1")
	await _key(KEY_TAB)
	check(spn.selected != key and spn.selected != "", "Tab : aiguillage suivant")
	# clic sur le plan : sélection d'un aiguillage par sa position
	spn.selected = ""; spn.refresh()
	for i in 3: await process_frame
	await _click(spn.screen_pos(key))
	for i in 3: await process_frame
	check(spn.selected == spn._pick(spn.canvas.get_global_transform().affine_inverse() * spn.screen_pos(key)) and spn.selected != "", "clic sur le plan : aiguillage sélectionné")
	await _key(KEY_A)
	for i in 3: await process_frame
	check(main.plan_panel == null, "A : panneau fermé")
	quit(1 if fails > 0 else 0)
