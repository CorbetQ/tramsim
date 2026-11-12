extends SceneTree
## Régression des gestes natifs et du HUD dans de petites fenêtres réelles.
var fails := 0
func check(c: bool, m: String) -> void:
	if c: print("ok: ",m)
	else: fails += 1; printerr("ECHEC: ",m)
func touch(id: int, pos: Vector2, pressed: bool) -> InputEventScreenTouch:
	var e := InputEventScreenTouch.new(); e.index = id; e.position = pos; e.pressed = pressed; return e
func drag(id: int, pos: Vector2) -> InputEventScreenDrag:
	var e := InputEventScreenDrag.new(); e.index = id; e.position = pos; return e
func system_touch(event: InputEvent) -> void:
	# Sur Android le serveur d'affichage fournit également la souris tactile.
	# parse_input_event() sous X11 n'injecte pas cette seconde séquence système.
	Input.parse_input_event(event)
	if event is InputEventScreenTouch:
		var mouse := InputEventMouseButton.new(); mouse.device = -1; mouse.position = event.position; mouse.global_position = event.position
		mouse.button_index = MOUSE_BUTTON_LEFT; mouse.pressed = event.pressed; Input.parse_input_event(mouse)
	elif event is InputEventScreenDrag:
		var mouse := InputEventMouseMotion.new(); mouse.device = -1; mouse.position = event.position; mouse.global_position = event.position
		mouse.button_mask = MOUSE_BUTTON_MASK_LEFT; mouse.relative = event.relative; Input.parse_input_event(mouse)
func _init() -> void:
	# Les entrées et la physique sont testées ici ; le rendu 3D est vérifié par visual_review.gd.
	root.disable_3d = true
	_run.call_deferred()
func _run() -> void:
	# ScrollContainer utilise la souris émulée, et active son inertie uniquement en mode tactile.
	Input.emulate_touch_from_mouse = true
	Input.emulate_mouse_from_touch = true
	var gestures := MapGestures.new()
	gestures.feed(touch(0,Vector2(100,100),true))
	check(gestures.feed(touch(0,Vector2(102,100),false)).has("select"), "tap sélectionné au relâchement")
	gestures.feed(touch(0,Vector2(100,100),true))
	var pan := gestures.feed(drag(0,Vector2(130,100)))
	check(pan.get("pan",Vector2.ZERO) == Vector2(30,0), "un doigt déplace le plan une seule fois")
	check(not gestures.feed(touch(0,Vector2(130,100),false)).has("select"), "glissement sans sélection accidentelle")
	gestures.feed(touch(0,Vector2(100,100),true)); gestures.feed(touch(1,Vector2(200,100),true))
	var pinch := gestures.feed(drag(1,Vector2(250,100)))
	check(is_equal_approx(float(pinch.get("zoom",0)),1.5), "pincement à deux doigts avec facteur de zoom exact")
	gestures.feed(touch(1,Vector2(250,100),false))
	check(not gestures.feed(touch(0,Vector2(100,100),false)).has("select"), "aucun tap après un pincement")
	var main = load("res://src/ui/main.tscn").instantiate(); root.add_child(main)
	await process_frame
	main.save.settings.tutorial_done = true
	for dimensions in [Vector2i(640,360),Vector2i(800,450),Vector2i(1280,720)]:
		root.size = dimensions
		for i in 4: await process_frame
		main.net_path = "res://tests/fixtures/schema_test.json"; main.free_mode = true
		main.start_station = {}; main.vehicle = VehicleLibrary.citadis_302_hybride(); main._start(); main.view.day_night.sun.shadow_enabled = false
		for i in 6: await process_frame
		check(is_equal_approx(main.notch, -0.75), "départ au cran F3")
		var viewport := Rect2(Vector2.ZERO, Vector2(dimensions))
		var rects := {}
		for name in ["trip", "lever", "dock", "emergency", "btn_pause", "btn_home", "slope"]:
			var c := main.find_child(name,true,false) as Control
			check(c != null and viewport.grow(1).encloses(c.get_global_rect()), "%s : %s accessible" % [dimensions,name])
			if c: rects[name] = c.get_global_rect()
		check(not rects.trip.intersects(rects.lever), "%s : trajet et manipulateur séparés" % dimensions)
		check(not rects.trip.intersects(rects.btn_pause), "%s : pause indépendante du trajet" % dimensions)
		if dimensions.x == 640:
			var dock := main.find_child("dock",true,false) as ScrollContainer
			var position_ := dock.get_global_rect().position + Vector2(dock.size.x - 40, 35)
			system_touch(touch(0,position_,true)); await process_frame
			var previous := position_
			for j in 8:
				var current := position_ - Vector2((j + 1) * 24,0)
				var event := drag(0,current); event.relative = current - previous; previous = current
				system_touch(event); await process_frame
			system_touch(touch(0,previous,false)); await process_frame
			await create_timer(0.35).timeout
			check(dock.scroll_horizontal > 40, "défilement du dock par glissement tactile natif (%d px)" % dock.scroll_horizontal)
			check(main.plan_panel == null, "glisser le dock ne déclenche pas le bouton Carte")
		main._toggle_help()
		for i in 4: await process_frame
		var help_panel := main.help_layer.find_children("*", "PanelContainer",true,false)[0] as Control
		check(viewport.grow(1).encloses(help_panel.get_global_rect()), "%s : aide contenue dans l'écran" % dimensions)
		main._toggle_help()
		main._toggle_plan()
		for i in 4: await process_frame
		var sp: NetworkPlan = main.plan_panel
		check(sp.canvas.size.x >= dimensions.x * 0.5, "%s : plan d'aiguillages lisible" % dimensions)
		check(not sp.compact or not sp._side_panel.visible, "%s : liste repliée sur petit écran" % dimensions)
		sp._plan_input(touch(0,Vector2(100,100),true))
		var before := sp.pan
		sp._plan_input(drag(0,Vector2(140,100))); sp._plan_input(touch(0,Vector2(140,100),false))
		check(sp.pan - before == Vector2(40,0), "%s : glisser tactile réel du panneau" % dimensions)
		var emulated := InputEventMouseMotion.new(); emulated.device = -1; emulated.relative = Vector2(40,0)
		before = sp.pan; sp._dragging = true; sp._plan_input(emulated)
		check(sp.pan == before, "%s : souris tactile émulée ignorée" % dimensions)
		main._toggle_plan()
		main.menu_page = "setup"; main._build_menu()
		for i in 4: await process_frame
		var start := main.find_child("start",true,false) as Button
		check(start != null and start.size.x > 100, "%s : lancement disponible dans la configuration" % dimensions)
		if dimensions.x == 640:
			var option := main.find_children("*", "Button",true,false).filter(func(node): return node is TouchChoice)[0] as TouchChoice
			var container: Node = option.get_parent()
			while container != null and not (container is TouchScroll): container = container.get_parent()
			var form := container as TouchScroll
			var point := option.get_global_rect().get_center()
			system_touch(touch(0,point,true)); await process_frame
			for j in 5:
				var event := drag(0,point - Vector2(0,(j+1)*18)); event.relative = Vector2(0,-18)
				system_touch(event); await process_frame
			system_touch(touch(0,point - Vector2(0,90),false)); await create_timer(0.35).timeout
			check(form.scroll_vertical > 15, "formulaire : glisser depuis une liste déroule la page")
			check(not is_instance_valid(option.popup), "formulaire : glisser ne choisit pas une option")
			option.close_picker()

	main.queue_free(); await process_frame
	quit(1 if fails else 0)
