extends SceneTree
var failures := 0
func check(ok: bool, message: String) -> void:
	if not ok: failures += 1; printerr("ECHEC: ",message)
	else: print("ok: ",message)
func _initialize() -> void: run.call_deferred()

func run() -> void:
	LiveryLibrary.path = "user://test_liveries_%d.json" % Time.get_ticks_usec()
	LiveryLibrary.reset_cache()
	var groups := StockCatalog.grouped()
	var ids := {}; var count := 0; var x05 := {}
	for group in groups:
		check(not ids.has(group.id),"famille unique : "+str(group.id)); ids[group.id]=true
		count += group.variants.size()
		if group.id=="citadis_x05":x05=group
	check(count==StockCatalog.entries().size(),"toutes les variantes regroupées exactement une fois")
	for type_ in ["205","305","405"]:check(type_ in x05.types,"Citadis X05 : type "+type_)
	for id in ["angers__citadis_x05","nantes__citadis_x05_nantes","brest__citadis_305"]:
		check(x05.variants.any(func(e):return str(e.id)==id),"variante / face conservée : "+id)
	check(StockCatalog.group_id(StockCatalog.find("sarreguemines__flexity_link"))!="avanto","matériels réels séparés malgré un ancien plan de repli partagé")
	check(StockCatalog.group_id(StockCatalog.find("strasbourg__citadis_x05"))=="citadis_x03","403 NG classé selon son type plutôt que son ancien plan de rendu")
	var original := StockCatalog.find("angers__citadis_302").duplicate(true)
	var design := LiveryLibrary.create(original)
	design.name="Océane";design.colors.base="#b52a80";design.colors.front="#eef4f6";design.label="OCÉANE"
	var stored := LiveryLibrary.save_design(design)
	check(not stored.is_empty() and stored.id!="","création nommée et persistante")
	stored.name="Océane 2"
	stored=LiveryLibrary.save_design(stored)
	check(LiveryLibrary.designs(str(original.id)).size()==1,"modifier garde le même identifiant")
	var copy := LiveryLibrary.save_design(stored,true)
	check(copy.id!=stored.id and LiveryLibrary.designs(str(original.id)).size()==2,"copie indépendante")
	LiveryLibrary.reset_cache()
	check(LiveryLibrary.designs(str(original.id))[0].name=="Océane 2","relecture effective depuis le fichier")
	check(LiveryLibrary.remove(str(copy.id)) and LiveryLibrary.designs(str(original.id)).size()==1,"suppression d'une création sans toucher l'autre")
	check(StockCatalog.find(str(original.id))==original,"flotte officielle jamais modifiée")
	var invalid := stored.duplicate(true);invalid.colors.base="javascript:bad"
	check(LiveryLibrary.clean(invalid).is_empty(),"couleur invalide refusée")
	invalid=stored.duplicate(true);invalid.bands[0].width=NAN
	check(LiveryLibrary.clean(invalid).is_empty(),"dimensions non finies refusées")
	var meta := StockCatalog.origin_meta(original)
	var factory := TramModel.livery_for(meta,original)
	var painted_entry := original.duplicate(true);painted_entry.custom_livery=stored
	var painted := TramModel.livery_for(meta,painted_entry)
	check(painted.base==Color("#b52a80") and factory.base!=painted.base,"couleur appliquée au rendu sans recolorer l'origine")
	check(painted.variant_id==factory.variant_id and painted.geometry==factory.geometry,"face avant et géométrie inchangées")
	var wrong := TramModel.livery_for(StockCatalog.origin_meta(StockCatalog.find("nantes__citadis_x05_nantes")),StockCatalog.find("nantes__citadis_x05_nantes"))
	check(not LiveryLibrary.apply(wrong,stored).has("custom_livery"),"pas de livrée injectée sur un autre modèle")
	var profile := VehicleLibrary.for_fleet(original,meta);profile.custom_livery=stored
	var plain := VehicleLibrary.for_fleet(original,meta)
	check(profile.power_modes()==plain.power_modes() and profile.power_kw==plain.power_kw and profile.loaded_mass(20)==plain.loaded_mass(20),"peinture indépendante de la physique et de l'APS")
	check(LineView.tram_entry(profile).custom_livery==stored,"personnalisation transmise au modèle de conduite")
	for vid in ["angers__citadis_302","angers__citadis_x05","nantes__citadis_x05_nantes"]:
		var entry := StockCatalog.find(vid).duplicate(true)
		var paint := LiveryLibrary.create(entry);paint.colors.base="#b52a80";paint.label="ESSAI";paint.name="Essai"
		entry.custom_livery=paint
		var liv := TramModel.livery_for(StockCatalog.origin_meta(entry),entry)
		var rig := TramModel.build_rig(liv)
		check(rig.hd!=null,vid+" : modèle HD conservé")
		if rig.hd!=null:
			var door:Dictionary=rig.hd.doors[0]
			var closed:Transform3D=door.node.transform
			rig.set_doors(true,"both");rig.set_pantograph(false)
			for step in 120:rig.update(1.0/30.0)
			check(not door.node.transform.is_equal_approx(closed) and rig.panto_t<0.01,vid+" : portes et pantographe restent animés")
			rig.hd.set_lod(2)
			check(rig.hd.lods[2][0].visible and not rig.hd.lods[0][0].visible,vid+" : LOD repeints commutables")
			var found := false
			for mi in rig.hd.lods[0][0].find_children("*","MeshInstance3D",true,false):
				for s in mi.mesh.get_surface_count():
					var material:=mi.get_surface_override_material(s) as BaseMaterial3D
					if material!=null and material.resource_name.begins_with("livery"):
						var image:=material.albedo_texture.get_image()
						var color:=image.get_pixel(2,roundi(image.get_height()*0.625*(3.4-0.95)/3.4))
						found=found or (color.r>0.6 and color.b>0.3 and color.g<0.3)
			check(found,vid+" : atlas réellement repeint")
			check(not rig.hd.lods[0][rig.modules.size()/2].find_children("CustomLiveryLabel*","Label3D",true,false).is_empty(),vid+" : inscription 3D")
		for module in rig.modules:module.free()
	# Game resume resolves foreign rolling stock by its actual ID.
	Engine.set_meta("tramsim_benchmark",true)
	var main = load("res://src/ui/main.gd").new()
	main.save=SaveGame.default_data();main.vehicle=profile;main.net_path="res://data/free/angers.json";main.free_mode=true
	main._remember_run("Angers")
	check(main.save.settings.last_run.custom_livery==stored,"livrée incluse dans la reprise de partie")
	check(main._vehicle_by_id("angers__citadis_302",{"source_id":"nantes","id":"nantes_1"}).variant_id=="angers__citadis_302","reprise d'une rame étrangère sans substitution")
	main.set_meta("selected_livery",stored)
	check(main._selected_paint(plain).custom_livery==stored,"sélection conservée dans la préparation de conduite")
	var other:=VehicleLibrary.for_fleet(StockCatalog.find("nantes__citadis_x05_nantes"),{"source_id":"nantes"})
	check(main._selected_paint(other).custom_livery.is_empty(),"une autre rame ne reçoit pas la peinture par erreur")
	main.free();Engine.remove_meta("tramsim_benchmark")
	var malformed_path:=LiveryLibrary.path+"_malformed"
	var malformed:=SaveGame.default_data();malformed.liveries={"unexpected":true};SaveGame.save_data(malformed,malformed_path)
	LiveryLibrary.path=malformed_path;LiveryLibrary.reset_cache()
	var before:=FileAccess.get_sha256(malformed_path)
	check(LiveryLibrary.designs(str(original.id)).is_empty() and LiveryLibrary.save_design(stored).is_empty() and FileAccess.get_sha256(malformed_path)==before,"bibliothèque malformée préservée sans crash")
	var future_path:=LiveryLibrary.path+"_future"
	var file:=FileAccess.open(future_path,FileAccess.WRITE);file.store_string('{"version":999}');file.close()
	LiveryLibrary.path=future_path;LiveryLibrary.reset_cache()
	check(LiveryLibrary.save_design(stored).is_empty() and FileAccess.get_file_as_string(future_path)=='{"version":999}',"bibliothèque future conservée sans écrasement")
	StockHD.reset_cache()
	print("TOTAL_ECHECS|",failures);quit(1 if failures else 0)
