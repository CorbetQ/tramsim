extends SceneTree
var failures:=0
func check(ok:bool,message:String)->void:
	if not ok:failures+=1;printerr("ECHEC: ",message)
	else:print("ok: ",message)
func _initialize()->void:run.call_deferred()
func run()->void:
	var total:=0
	for entry in StockCatalog.entries():
		var cfg:=TramParts.configuration(entry)
		check(not cfg.is_empty() and cfg.rows.size()==int(entry.module_count),str(entry.id)+" : composition par paramètres du kit")
		if cfg.is_empty():continue
		for row in cfg.rows:
			var part:Dictionary=cfg.definition.parts[row.part]
			var models:Dictionary=part.models
			check(models.values().all(func(file):return TramParts.allowed(file) and FileAccess.file_exists(file)),str(entry.id)+" : prototype de caisse partagé")
			total+=1
	for network in ["angers","nantes"]:
		var ids:Array=["angers__concept_citadis_205","angers__citadis_x05","angers__concept_citadis_405"] if network=="angers" else ["nantes__concept_citadis_205","nantes__concept_citadis_305","nantes__citadis_x05_nantes"]
		var files:Array=[]
		for id in ids:
			var cfg:=TramParts.configuration(StockCatalog.find(id))
			files.append(cfg.definition.parts.end_a.models.lod0)
			check(cfg.rows.size()==int(StockCatalog.find(id).module_count),id+" : nombre de caisses paramétré")
		check(files[0]==files[1] and files[1]==files[2],network+" : même ressource d'extrémité pour 205, 305 et 405")
	for id in ["angers__citadis_x05","angers__citadis_302","nantes__citadis_x05_nantes"]:
		var entry:=StockCatalog.find(id);var cfg:=TramParts.configuration(entry)
		var counts:Array=[]
		for row in cfg.rows:
			var part:Dictionary=cfg.definition.parts[row.part];counts.append(int(part.door_count))
			if str(entry.network)=="angers":
				check(int(part.door_count)==(1 if row.role.begins_with("end_") else (0 if row.role=="powered" else 2)),id+" : portes selon le rôle de caisse")
				if row.role.begins_with("end_"):
					var door:Dictionary=part.plan.doors[0]
					check(float(door.z_m)<float(part.length_m)*.5 if row.role=="end_a" else float(door.z_m)>float(part.length_m)*.5,id+" : porte d'extrémité vers la cabine")
		check(counts==([2,0,2,0,2,0,2] if entry.network=="nantes" else [1,2,0,2,1]),id+" : distribution complète des portes")
	check(not TramParts.allowed("res://tram_parts/../../secret"),"chemin sortant des pièces rejeté")
	# Test real resource use, not just filenames, including independent native bodies.
	for id in ["nantes__tfs","idf__tfs__t1","nantes__incentro","clermont__translohr","angers__citadis_x05","nantes__citadis_x05_nantes"]:
		var entry:=StockCatalog.find(id);var liv:=TramModel.livery_for(StockCatalog.origin_meta(entry),entry);var rig:=TramModel.build_rig(liv)
		var used:=true
		if rig.hd!=null:
			for holder in rig.hd.lods[0]:
				var module:Node3D=holder.get_child(0);used=used and module.has_meta("tram_part_file")
		else:
			for module in rig.modules:
				used=used and module.has_meta("tram_part_file") and module.mesh==null and rig.parts_view!=null
		check(used,id+" : ressources indépendantes effectivement utilisées par le rendu")
		var animated:Node3D=rig.parts_view.bindings[0].visual if rig.parts_view!=null else rig.leaves[0].node
		var closed:Transform3D=animated.transform
		rig.set_doors(true,"both");rig.set_pantograph(false)
		for step in 90:rig.update(.05)
		check(not closed.is_equal_approx(animated.transform) and rig.panto_t<.01,id+" : liaisons des animations conservées")
		for module in rig.modules:module.free()
	var source:=StockCatalog.find("angers__citadis_x05")
	var design:=LiveryLibrary.create(source);design.colors.base="#b52a80"
	design.parts.end_a={"colors":design.colors.duplicate(true),"bands":design.bands.duplicate(true)};design.parts.end_a.colors.front="#0089ce"
	var scope_ok:=true;var ends_ok:=true
	for id in ["angers__concept_citadis_205","angers__concept_citadis_405","nantes__citadis_x05_nantes"]:
		var entry:=StockCatalog.find(id);var liv:=TramModel.livery_for(StockCatalog.origin_meta(entry),entry)
		liv=LiveryLibrary.apply(liv,design)
		scope_ok=scope_ok and liv.has("custom_livery") and liv.variant_id==id
		ends_ok=ends_ok and LiveryLibrary.for_part(design,entry,0).colors.front=="#0089ce" and LiveryLibrary.for_part(design,entry,int(entry.module_count)-1).colors.front!= "#0089ce"
		var rig:=TramModel.build_rig(liv);var actual:Dictionary={}
		if rig.hd!=null:
			for end in [0,rig.modules.size()-1]:
				for node in rig.hd.lods[0][end].find_children("*","MeshInstance3D",true,false):
					for s in node.mesh.get_surface_count():
						var material:=node.get_surface_override_material(s) as BaseMaterial3D
						if material!=null and material.resource_name.begins_with("livery"):
							var image:=material.albedo_texture.get_image()
							actual[end]=image.get_pixel(roundi(image.get_width()*.1725),roundi(image.get_height()*(.625+.375*(3.4-.45)/3.4)))
		print("PAINT_PIXELS|",id,"|",actual)
		check(actual.has(0) and actual.has(rig.modules.size()-1) and absf(actual[0].r-actual[rig.modules.size()-1].r)>.1,id+" : deux atlas d'extrémité réellement différents")
		for module in rig.modules:module.free()
	check(scope_ok,"même livrée appliquée à plusieurs tailles sans remplacer leur design d'extrémité")
	check(ends_ok,"réglage d'extrémité A conservé en 3, 5 et 7 caisses ; B indépendant")
	check(not LiveryLibrary.compatible(design,"nantes__tfs"),"pas de transfert implicite entre architectures différentes")
	var tfs:=StockCatalog.find("nantes__tfs");var native_design:=LiveryLibrary.create(tfs)
	var tfs_cfg:=TramParts.configuration(tfs)
	var hd_tfs:bool=str(tfs_cfg.definition.renderer)=="hd"
	var factory_path:String=TramParts.manifest().liveries[tfs_cfg.livery].parts.end_a.get("4k" if hd_tfs else "native","")
	var factory:=Image.load_from_file(factory_path) if not hd_tfs else (load(factory_path) as Texture2D).get_image();var green:=0
	if factory.is_compressed():factory.decompress()
	for y in range(roundi(factory.get_height()*.625),factory.get_height()):
		var color:=factory.get_pixel(roundi(factory.get_width()*.09375),y)
		if color.g>color.r+.15 and color.g>color.b+.08:green+=1
	check(green>=5,"bande verte TAN présente dans la face de l'atlas, avec les normales Godot")
	native_design.colors.window="#154694";native_design.colors.door="#f18023"
	var native_liv:=LiveryLibrary.apply(TramModel.livery_for(StockCatalog.origin_meta(tfs),tfs),native_design)
	var native_rig:=TramModel.build_rig(native_liv)
	# P4 : le TFS est passé en kit HD ; la peinture personnalisée passe alors par StockHD (même kit partagé).
	check(native_rig.parts_view!=null or (hd_tfs and native_rig.hd!=null),"peinture native conserve les prototypes partagés")
	if native_rig.parts_view!=null:
		var material:ShaderMaterial=native_rig.parts_view.bindings[0].visual.material_override
		check(material.get_shader_parameter("part_custom_enabled")==true,"atlas personnalisé natif effectivement relié")
		var window:Vector3=material.get_shader_parameter("part_window_color")
		check(window.distance_to(Vector3(21.0/255,70.0/255,148.0/255))<.01,"couleur des vitrages natifs indépendante de la palette d'origine")
	for module in native_rig.modules:module.free()
	StockHD.reset_cache();print("BODY_COUNT|",total);print("TOTAL_ECHECS|",failures);quit(1 if failures else 0)
