extends SceneTree
var failures:=0
func check(ok:bool,message:String)->void:
	if ok:print("ok: ",message)
	else:failures+=1;printerr("ECHEC: ",message)
func _initialize()->void:run.call_deferred()
func run()->void:
	var variants: Array=load("res://tests/audit/family_front_shots.gd").CITADIS
	for mobile in [false,true]:
		DayNight.low_quality=mobile;StockHD.reset_cache()
		for id in variants:
			var e:=StockCatalog.find(id);var liv:=TramModel.livery_for(StockCatalog.origin_meta(e),e)
			var rig:=TramModel.build_rig(liv);var prefix:="%s / %s" % [id,"mobile" if mobile else "PC"]
			check(rig.hd!=null,prefix+" : habillage HD complet")
			check(rig.modules.size()==int(e.module_count) and absf(rig.length-float(e.length))<.01,prefix+" : longueur et caisses du type choisi")
			if rig.hd!=null:
				check(StockHD.check(str(id),rig).is_empty(),prefix+" : LOD, cabine, budget et pivots valides")
				check(str(rig.hd.entry.front_profile)==("x05_nantes" if e.cab_profile=="naolib" else "x05"),prefix+" : vrai profil de face du réseau")
				var door:Dictionary=rig.hd.doors[0];var closed:Transform3D=door.node.transform
				rig.set_doors(true,"both");rig.set_pantograph(false)
				for step in 90:rig.update(.05)
				check(not closed.is_equal_approx(door.node.transform) and rig.panto_t<.01,prefix+" : animations préservées")
			for module in rig.modules:module.free()
	DayNight.low_quality=false
	var one:=StockGeometry.apply(TramModel.plan("tfs"),StockCatalog.find("nantes__tfs"))
	var two:=StockGeometry.apply(TramModel.plan("tfs"),StockCatalog.find("idf__tfs__t1"))
	check(one.front!=two.front and one.front.windshield!=two.front.windshield,"TFS 1 et TFS 2 : silhouettes et vitrages distincts")
	check(not one.front.has("upper_light") and two.front.has("upper_light"),"troisième optique haute propre au TFS 2")
	for id in load("res://tests/audit/family_front_shots.gd").TFS:
		var e:=StockCatalog.find(id);var rig:=TramModel.build_rig(TramModel.livery_for(StockCatalog.origin_meta(e),e))
		check(StockCatalog.type_name(e)==("TFS 1" if e.cab_profile=="tfs_nantes" else "TFS 2"),str(id)+" : génération correcte")
		check(rig.triangles>1000 and rig.modules.size()==3,str(id)+" : rame complète rendue")
		for module in rig.modules:module.free()
	for id in ["angers__concept_citadis_205","angers__concept_citadis_405","nantes__concept_citadis_205","nantes__concept_citadis_305","idf__concept_tfs_1","nantes__concept_tfs_2"]:
		check(StockCatalog.find(id).fictional,str(id)+" : création fictive signalée")
	StockHD.reset_cache();print("TOTAL_ECHECS|",failures);quit(1 if failures else 0)
