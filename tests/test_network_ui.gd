extends SceneTree
var failures := 0
func check(ok: bool, message: String) -> void:
	if ok: print("ok: ",message)
	else: failures += 1; printerr("ECHEC: ",message)
func _init() -> void:
	root.disable_3d = true; _run.call_deferred()
func _run() -> void:
	root.size=Vector2i(800,450)
	var main=load("res://src/ui/main.tscn").instantiate();root.add_child(main);await process_frame
	main.save.settings.tutorial_done=true;main.net_path="res://tests/fixtures/schema_test.json";main.vehicle=VehicleLibrary.citadis_302_hybride();main.start_station={};main.free_mode=true;main._start();main.paused=true
	for i in 5:await process_frame
	var labels: Array=[]
	for button in main.find_children("*","Button",true,false):
		if button.has_meta("label"):labels.append(button.get_meta("label"))
	check(labels.count("Plan")==1 and not "Carte" in labels and not "Aiguillages" in labels,"un seul bouton de plan dans le dock")
	main._power_picker();for i in 4:await process_frame
	var modals=get_nodes_in_group("touch_choice_modal")
	check(modals.size()==1 and modals[0].is_visible_in_tree(),"sélecteur alimentation visible, sans bouton temporaire à l’écran")
	if not modals.is_empty():
		var popup:Control=modals[0]
		var aps:Button
		for b in popup.find_children("*","Button",true,false):
			if b.text=="APS":aps=b
		check(aps!=null,"choix APS présent pour une rame hybride")
		if aps:aps.pressed.emit()
	await process_frame
	check(main.session.power_mode=="aps" and not main.session.pantograph_up,"le sélecteur commande réellement la simulation")
	main.session.phys.speed=2.0;main._power_picker();await process_frame
	check(get_nodes_in_group("touch_choice_modal").is_empty(),"sélecteur refusé en marche")
	main._toggle_plan();await process_frame;check(main.plan_panel!=null,"plan accessible en mode libre")
	main._toggle_plan();await process_frame
	main.free_mode=false;main.mission={};main._start();main.paused=true
	for i in 5:await process_frame
	main._toggle_plan();for i in 3:await process_frame
	check(main.plan_panel!=null and not main.plan_panel.session is FreeSession,"même plan accessible en mission")
	var before:Dictionary=main.net.graph.switch_state.duplicate()
	main.plan_panel._throw("N1",1,1)
	check(main.net.graph.switch_state==before,"aucune manœuvre possible en mission")
	main.queue_free();await process_frame;await process_frame
	print("TOTAL_ECHECS|",failures);quit(1 if failures else 0)
