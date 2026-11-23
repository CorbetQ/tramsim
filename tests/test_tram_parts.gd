extends SceneTree
var failures:=0
func check(ok:bool,message:String)->void:
	if not ok:failures+=1;printerr("ECHEC: ",message)
	else:print("ok: ",message)
func _initialize()->void:run.call_deferred()
func run()->void:
	var index:=TramParts.manifest();var total:=0
	for entry in StockCatalog.entries():
		var rows:Array=index.variants.get(entry.id,{}).get("modules",index.native.get(entry.id,[]))
		check(rows.size()==int(entry.module_count),str(entry.id)+" : chaque caisse dispose d'un modèle et d'une texture")
		for row in rows:
			check(TramParts.allowed(str(row.file)) and FileAccess.file_exists(str(row.file)) and str(row.texture).begins_with("res://tram_livery/") and FileAccess.file_exists(str(row.texture)),str(entry.id)+" : caisse %d indépendante"%int(row.index))
			total+=1
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
				used=used and module.has_meta("tram_part_file") and module.material_override is ShaderMaterial and bool(module.material_override.get_shader_parameter("part_livery_enabled"))
		check(used,id+" : ressources indépendantes effectivement utilisées par le rendu")
		var closed:Transform3D=rig.leaves[0].node.transform
		rig.set_doors(true,"both");rig.set_pantograph(false)
		for step in 90:rig.update(.05)
		check(not closed.is_equal_approx(rig.leaves[0].node.transform) and rig.panto_t<.01,id+" : liaisons des animations conservées")
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
	check(scope_ok,"même livrée appliquée à plusieurs tailles sans remplacer leur design d'extrémité")
	check(ends_ok,"réglage d'extrémité A conservé en 3, 5 et 7 caisses ; B indépendant")
	check(not LiveryLibrary.compatible(design,"nantes__tfs"),"pas de transfert implicite entre architectures différentes")
	StockHD.reset_cache();print("BODY_COUNT|",total);print("TOTAL_ECHECS|",failures);quit(1 if failures else 0)
