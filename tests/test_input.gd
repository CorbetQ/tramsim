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
		if (n as Button).text.begins_with(text): return n
	return null

func _init() -> void:
	var main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.save.settings.tutorial_done = true
	var net := NetworkLoader.new(); net.load_file("res://data/networks/angers_a.json")
	main.net_path = "res://data/networks/angers_a.json"
	main.vehicle = VehicleLibrary.default_for(net.meta)
	main.free_mode = false
	main.mission = net.missions()[2]
	main._start()
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
	var sl: VSlider = main.find_children("*", "VSlider", true, false)[0]
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
	main._start()
	for i in 5: await process_frame
	var ab := _find(main, "Aiguillages")
	check(ab != null, "mode libre : bouton Aiguillages")
	await _click(ab.get_global_rect().get_center())
	for i in 3: await process_frame
	check(main.switch_panel != null, "panneau des aiguillages ouvert")
	var bl := 0
	for n in main.switch_panel.find_children("*", "Button", true, false):
		if (n as Button).text.begins_with("○") or (n as Button).text.begins_with("●"): bl += 1
	print("boutons de branches : ", bl)
	quit(1 if fails > 0 else 0)
