extends SceneTree
var failures := 0
func check(ok: bool, message: String) -> void:
	if not ok: failures += 1; printerr("ECHEC: ",message)
	else: print("ok: ",message)
func _initialize() -> void: run.call_deferred()
func settle() -> void:
	for i in 6: await process_frame
func shot(name_: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.cache/livery/"+name_+".png")
func fits(node: Control) -> bool:
	return node.get_global_rect().position.x >= -1 and node.get_global_rect().end.x <= root.get_visible_rect().size.x+1
func run() -> void:
	DirAccess.make_dir_recursive_absolute("res://.cache/livery")
	LiveryLibrary.path="user://test_livery_ui_%d.json" % Time.get_ticks_usec(); LiveryLibrary.reset_cache()
	root.size=Vector2i(1280,720);UiLayout.configure(root)
	var catalogue := Catalogue.new(); catalogue.theme=UiTheme.build();root.add_child(catalogue);await settle()
	check(catalogue.card_count()==StockCatalog.grouped().size(),"grille globale sans doublons de famille")
	await shot("catalogue-families")
	catalogue.free();await process_frame
	var sheet := TramSheet.new("citadis_x05","Nantes","nantes__citadis_x05_nantes");sheet.theme=UiTheme.build();root.add_child(sheet);await settle()
	check(sheet.type_opt.get_item_text(sheet.type_opt.selected)=="405","type 405 Naolib initialisé")
	check(sheet.family=="citadis_x05_nantes","géométrie physique Naolib conservée")
	check(sheet.types.has("205") and sheet.types.has("305"),"types 205 et 305 disponibles dans X05")
	await shot("catalogue-x05")
	var type305:int=sheet.types.find("305");sheet.type_opt.select(type305);sheet.type_opt.item_selected.emit(type305);await settle()
	var irigo:=-1
	for i in sheet.variants.size():
		if sheet.variants[i].id=="angers__citadis_x05":irigo=i
	check(irigo>=0,"face Irigo 305 disponible")
	sheet.livery_opt.select(irigo);sheet.livery_opt.item_selected.emit(irigo);await settle()
	check(sheet.family=="citadis_x05" and sheet.variant_id=="angers__citadis_x05","type et livrée changent ensemble sans modèle superposé")
	sheet.open_editor();await settle()
	check(sheet.editor!=null and not sheet.form.visible,"éditeur ouvert depuis la variante")
	sheet.editor.name_input.text="Océane";sheet.editor.label_input.text="OCÉANE"
	sheet.editor.set_color("base","#0089ce");sheet.editor.set_color("front","#ffffff")
	sheet.editor.design.bands[0].color="#ebd12f";sheet.editor.design.bands[0].width=0.24
	sheet.editor.design.label="OCÉANE";sheet.editor.refresh_preview();await settle()
	await shot("editor-custom")
	check(sheet.editor.preview.rig.hd!=null,"aperçu de peinture sur le vrai modèle HD")
	sheet.editor.save_current();await settle()
	check(sheet.editor==null and sheet.current_design().name=="Océane","enregistrement sélectionne la livrée créée")
	var saved_id:String=sheet.current_design().id
	var picks:Array=[];sheet.drive.connect(func(pick):picks.append(pick));sheet.drive_btn.pressed.emit()
	check(picks.size()==1 and picks[0].custom_livery.id==saved_id and picks[0].variant_id=="angers__citadis_x05","conduite reçoit la bonne face et une copie de la peinture")
	sheet.open_editor();await settle();sheet.editor.set_color("base","#de64a9");sheet.editor.cancelled.emit();await settle()
	check(sheet.current_design().colors.base=="#0089ce","annulation ne modifie pas la livrée sauvegardée")
	sheet.paint_opt.select(0);sheet.paint_opt.item_selected.emit(0);await settle()
	check(sheet.current_design().is_empty() and sheet.preview.rig.hd!=null,"retour au modèle HD avec la livrée d’origine")
	for dimensions in [Vector2i(640,360),Vector2i(360,640)]:
		root.size=dimensions;UiLayout.configure(root);await settle()
		check(fits(sheet.preview) and fits(sheet.type_opt) and fits(sheet.drive_btn),"fiche contenue : %s" % dimensions)
		sheet.open_editor();await settle()
		check(fits(sheet.editor.preview) and fits(sheet.editor.name_input),"éditeur contenu : %s" % dimensions)
		await shot("editor-%dx%d" % [dimensions.x,dimensions.y])
		sheet.editor.cancelled.emit();await settle()
	sheet.paint_opt.select(1);sheet.paint_opt.item_selected.emit(1)
	sheet._delete_design();check(not sheet.current_design().is_empty(),"suppression exige une confirmation")
	sheet._delete_design();check(sheet.current_design().is_empty() and LiveryLibrary.designs("angers__citadis_x05").is_empty(),"suppression confirmée restaure l’origine")
	sheet.free();await settle()
	# Real game path, using a small schematic fixture to keep CI independent of map streaming.
	root.size=Vector2i(1280,720);UiLayout.configure(root)
	Engine.set_meta("tramsim_benchmark",true)
	var main=load("res://src/ui/main.tscn").instantiate();root.add_child(main);await settle()
	main.save.settings.tutorial_done=true;main.save.settings.ai_trams=false;main.save.settings.traffic=false
	main.net_path="res://tests/fixtures/schema_test.json";main.free_mode=true
	main.set_meta("selected_livery",picks[0].custom_livery)
	main.vehicle=main._selected_paint(VehicleLibrary.for_fleet(StockCatalog.find(str(picks[0].variant_id)),{}))
	main._start();await settle()
	check(main.session!=null and main.view.rig.hd!=null and main.view.livery.custom_livery.id==saved_id,"livrée réellement chargée en conduite, même supprimée de la bibliothèque")
	check(main.view.livery.base==Color("#0089ce"),"couleur personnalisée conservée dans LineView")
	main._doors();await settle()
	check(main.session.doors_open,"commandes de conduite utilisables avec la livrée")
	main.external_cam=true;main._apply_auto_ui();await settle();await shot("driving-custom-fixture")
	main.queue_free();await settle();Engine.remove_meta("tramsim_benchmark");StockHD.reset_cache()
	print("TOTAL_ECHECS|",failures);quit(1 if failures else 0)
