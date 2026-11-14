extends SceneTree
## Mode Explorer (xvfb-run) : accueil -> caméra libre, déplacements clavier, vue du dessus,
## sauts vers les stations, heure, rames en circulation, joystick tactile, retour à l'accueil.
var fails := 0
func check(c: bool, m: String) -> void:
	if not c: fails += 1; printerr("ECHEC: ", m)
	else: print("ok: ", m)

func _key(k: Key, pressed: bool) -> void:
	var e := InputEventKey.new(); e.physical_keycode = k; e.keycode = k; e.pressed = pressed
	Input.parse_input_event(e)

func _init() -> void:
	root.disable_3d = true
	_run.call_deferred()

func _run() -> void:
	var main = load("res://src/ui/main.tscn").instantiate(); root.add_child(main)
	await process_frame
	main.save.settings.tutorial_done = true
	main.save.settings.home_bg = false
	for dims in [Vector2i(1600, 900), Vector2i(800, 400)]:
		root.size = dims
		main.menu_city = "Angers"; main.menu_page = "home"; main._build_menu()
		for i in 3: await process_frame
		var card: Button = null
		for b in main.find_children("*", "Button", true, false):
			if str(b.get_meta("title", "")).begins_with("Explorer") or (b as Button).text.begins_with("Explorer") or b.find_children("*", "Label", true, false).any(func(l): return (l as Label).text == "Explorer la ville"):
				card = b; break
		check(card != null, "%s : carte « Explorer la ville » à l'accueil" % dims)
		if card == null: continue
		card.pressed.emit()
		for i in 5: await process_frame
		var ex: ExploreMode = main.explore
		check(ex != null and ex.view != null and ex.view.cam.current, "%s : caméra libre active" % dims)
		if ex == null: continue
		var viewport := Rect2(Vector2.ZERO, Vector2(dims)).grow(1)
		for n in ["explore_bar", "hour_panel", "top_view", "places", "leave"]:
			var c := ex.find_child(n, true, false) as Control
			check(c != null and viewport.encloses(c.get_global_rect()) and c.size.y >= 44.0, "%s : %s accessible (≥ 44 px)" % [dims, n])
		var compact: bool = UiLayout.compact(ex)
		check(ex.joystick.visible == (compact or DisplayServer.is_touchscreen_available()), "%s : joystick virtuel %s" % [dims, "affiché" if ex.joystick.visible else "masqué (PC)"])
		# Clavier : avance (touche physique W = Z en AZERTY).
		var p0: Vector3 = ex.fly.pos
		_key(KEY_W, true)
		for i in 20: await process_frame
		_key(KEY_W, false)
		var moved: Vector3 = ex.fly.pos - p0
		check(moved.length() > 1.0 and moved.normalized().dot(ex.fly.forward()) > 0.7, "%s : Z/W avance dans le sens du regard (%.1f m)" % [dims, moved.length()])
		# Joystick virtuel : vers la droite.
		ex.joystick.value = Vector2(1, 0); ex.joystick.visible = true
		var p1: Vector3 = ex.fly.pos
		for i in 20: await process_frame
		ex.joystick.value = Vector2.ZERO; ex.joystick.visible = compact
		check((ex.fly.pos - p1).dot(ex.fly.right()) > 1.0, "%s : joystick latéral" % dims)
		# Molette / pincement : altitude.
		var h0: float = ex.fly.agl()
		ex.fly.climb_by(2.0)
		check(ex.fly.agl() > h0, "%s : montée (molette / pincement)" % dims)
		ex.top_view()
		check(ex.fly.pitch < -1.5 and ex.fly.agl() > 300.0, "%s : vue du dessus" % dims)
		# Sauts vers stations / monuments.
		check(ex.places.size() > 20, "%s : %d stations et monuments" % [dims, ex.places.size()])
		ex.toggle_list()
		for i in 2: await process_frame
		var lst := ex.find_child("places_list", true, false) as Control
		check(lst != null and viewport.encloses(lst.get_global_rect()), "%s : liste « Aller à » dans l'écran" % dims)
		var target: Vector3 = ex.places[3].pos
		ex.fly.top_view()
		var bt: Button = null
		for b in lst.find_children("*", "Button", true, false):
			if str(b.get_meta("place", "")) == str(ex.places[3].name): bt = b; break
		var found := bt != null
		if bt: bt.pressed.emit()
		for i in 2: await process_frame
		var kinds := {}
		for pl in ex.places: kinds[pl.kind] = int(kinds.get(pl.kind, 0)) + 1
		print("  lieux ", kinds, " boutons ", lst.find_children("*", "Button", true, false).size() if is_instance_valid(lst) else -1, " bouton ", found, " dist ", Vector2(ex.fly.pos.x - target.x, ex.fly.pos.z - target.z).length(), " liste ", is_instance_valid(lst))
		check(found and Vector2(ex.fly.pos.x - target.x, ex.fly.pos.z - target.z).length() < 200.0 and not is_instance_valid(lst), "%s : saut vers %s" % [dims, ex.places[3].name])
		# Heure : nuit.
		(ex.find_child("hour", true, false) as HSlider).value = 23.0
		await process_frame
		check(is_equal_approx(ex.hour, 23.0) and ex.view.day_night.night > 0.5, "%s : réglage de l'heure (nuit)" % dims)
		# Rames en circulation.
		for i in 30: await process_frame
		check(ex.ai != null and ex.ai.trams.size() > 0, "%s : rames en circulation (%d)" % [dims, ex.ai.trams.size() if ex.ai else 0])
		# Échap : retour à l'accueil.
		_key(KEY_ESCAPE, true); await process_frame; _key(KEY_ESCAPE, false)
		for i in 3: await process_frame
		check(main.explore == null and main.menu_page == "home" and main.find_child("explore", true, false) == null, "%s : Échap revient à l'accueil" % dims)
	print("TOTAL_ECHECS|%d" % fails)
	quit(1 if fails > 0 else 0)
