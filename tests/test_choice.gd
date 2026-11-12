extends SceneTree
## Menus réellement ouverts, gestes injectés dans le viewport (pas appel direct
## au gestionnaire du scroller) : traversée de lignes, annulation et sélection.
var failures := 0
func check(ok: bool, message: String) -> void:
	if ok: print("ok: ",message)
	else: failures += 1; printerr("ECHEC: ",message)
func finger(position: Vector2, down: bool) -> void:
	var touch := InputEventScreenTouch.new(); touch.index = 0; touch.position = position; touch.pressed = down; Input.parse_input_event(touch)
	var mouse := InputEventMouseButton.new(); mouse.device = -1; mouse.position = position; mouse.global_position = position
	mouse.button_index = MOUSE_BUTTON_LEFT; mouse.pressed = down; Input.parse_input_event(mouse)
func motion(position: Vector2, delta: Vector2) -> void:
	var touch := InputEventScreenDrag.new(); touch.index = 0; touch.position = position; touch.relative = delta; Input.parse_input_event(touch)
	var mouse := InputEventMouseMotion.new(); mouse.device = -1; mouse.position = position; mouse.global_position = position
	mouse.button_mask = MOUSE_BUTTON_MASK_LEFT; mouse.relative = delta; Input.parse_input_event(mouse)
func tap(point: Vector2) -> void:
	finger(point,true); await process_frame; finger(point,false); await process_frame
func _init() -> void:
	root.disable_3d = true; _run.call_deferred()
func _run() -> void:
	Input.emulate_touch_from_mouse = true; Input.emulate_mouse_from_touch = true
	for dimensions in [Vector2i(640,360),Vector2i(800,450)]:
		root.size = dimensions; UiLayout.configure(root)
		await process_frame
		var screen := Control.new(); screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); screen.theme = UiTheme.build(); root.add_child(screen)
		var page := TouchScroll.new(); page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); page.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; screen.add_child(page)
		var column := VBoxContainer.new(); column.size_flags_horizontal = Control.SIZE_EXPAND_FILL; page.add_child(column)
		var space := Control.new(); space.custom_minimum_size.y = 80; column.add_child(space)
		var choice := TouchChoice.new(); choice.custom_minimum_size.y = 54; choice.choice_title = "Service"; column.add_child(choice)
		for i in 100: choice.add_item("Service %02d" % i)
		var filler := Control.new(); filler.custom_minimum_size.y = 1200; column.add_child(filler)
		var events := [0]; choice.item_selected.connect(func(_i): events[0] += 1)
		for i in 5: await process_frame
		await tap(choice.get_global_rect().get_center())
		for i in 4: await process_frame
		check(is_instance_valid(choice.popup), "%s : un tap ouvre le sélecteur" % dimensions)
		if not is_instance_valid(choice.popup): screen.free(); continue
		var scroll := choice.list
		var start := scroll.get_global_rect().position + Vector2(scroll.size.x * 0.5,scroll.size.y - 25)
		finger(start,true); await process_frame
		for i in 12:
			motion(start - Vector2(0,(i+1)*19),Vector2(0,-19)); await process_frame
		finger(start-Vector2(0,228),false); await process_frame
		check(scroll.scroll_vertical > 150, "%s : menu ouvert défile en traversant plusieurs lignes" % dimensions)
		check(choice.selected == 0 and events[0] == 0 and is_instance_valid(choice.popup), "glisser ne sélectionne ni ne ferme le menu")
		check(page.scroll_vertical == 0, "la page derrière le menu reste immobile")
		await create_timer(0.8).timeout
		var target: Button
		for button in choice._rows.get_children():
			if scroll.get_global_rect().grow(-15).has_point(button.get_global_rect().get_center()): target = button; break
		check(target != null, "une ligne est sélectionnable après le glissement")
		if target:
			var expected := int(target.name.trim_prefix("choice_"))
			await tap(target.get_global_rect().get_center())
			check(choice.selected == expected and events[0] == 1 and not is_instance_valid(choice.popup), "tap après défilement : une seule sélection et fermeture")
		await tap(choice.get_global_rect().get_center()); for i in 3: await process_frame
		if is_instance_valid(choice.popup):
			choice._search.text = "Service 97"; choice._search.text_changed.emit(choice._search.text)
			await process_frame
			var count := 0
			for button in choice._rows.get_children(): count += int(button.visible)
			check(count == 1, "recherche dans les services sans perdre les indices")
			await tap(choice._rows.get_child(97).get_global_rect().get_center())
			check(choice.selected == 97 and events[0] == 2, "résultat filtré : bon service sélectionné")
		choice.open_picker(); for i in 3: await process_frame
		var key := InputEventKey.new(); key.pressed = true; key.keycode = KEY_ESCAPE; Input.parse_input_event(key); await process_frame
		key.pressed = false; Input.parse_input_event(key)
		check(not is_instance_valid(choice.popup), "Échap ferme le menu")
		choice.open_picker(); for i in 3: await process_frame
		check(not quit_on_go_back, "Retour Android ne quitte pas le jeu pendant le choix")
		choice.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST); await process_frame; await process_frame
		check(not is_instance_valid(choice.popup) and quit_on_go_back, "Retour Android ferme seulement le choix et restaure son comportement")
		screen.free(); await process_frame
	print("TOTAL_ECHECS|",failures); quit(1 if failures else 0)
