extends SceneTree
var failures:=0
func check(ok:bool,message:String)->void:
 if ok:print("ok: ",message)
 else:failures+=1;printerr("ECHEC: ",message)
func _init()->void:
 var entries:=StockCatalog.entries();var seen:Dictionary={};var concepts:=0;var maximum:=0
 for entry in entries:
  check(not seen.has(str(entry.id)),"identifiant unique : "+str(entry.id));seen[str(entry.id)]=true
  if entry.fictional:concepts+=1
  var origin:=StockCatalog.origin_meta(entry)
  var liv:=TramModel.livery_for(origin,entry);var rig:=TramModel.build_rig(liv)
  maximum=maxi(maximum,rig.triangles)
  var valid:=rig.modules.size()==int(entry.module_count) and absf(rig.length-float(entry.length))<.01 and not rig.panto.is_empty()
  for module in rig.modules:
   # HD rigs intentionally clear the procedural mesh; inspect their child
   # geometry instead of dereferencing a null legacy mesh.
   var box:=CabView._local_aabb(module) if rig.hd!=null or rig.parts_view!=null else module.mesh.get_aabb()
   valid=valid and box.size.is_finite() and box.size.x>1 and box.size.y>2 and box.size.z>1
  check(valid,"géométrie et articulations : "+str(entry.id))
  if TramParts.configuration(entry).get("definition",{}).get("renderer")=="native":
   check(rig.modules.all(func(module):return module.has_meta("tram_part_file")),"caisses chargées depuis tram_parts : "+str(entry.id))
   var panto_bindings:=0
   if rig.parts_view!=null:
    for binding in rig.parts_view.bindings:
     if binding.control in [rig.panto.get("lower"),rig.panto.get("upper"),rig.panto.get("head")]:panto_bindings+=1
   check(panto_bindings==3,"pantographe visible relié aux trois commandes : "+str(entry.id))
  var cap:=int(StockHD._budgets().LOD0.mobile_tris if StockHD.mobile() else StockHD._budgets().LOD0.pc_tris) if rig.hd!=null else 15999
  check(rig.triangles<=cap,"budget du modèle sélectionné : %s (%d ≤ %d)"%[entry.id,rig.triangles,cap])
  if str(entry.network)=="saintetienne":check(rig.leaves.all(func(leaf):return float(leaf.side)>0),"portes uniquement à droite : "+str(entry.id))
  for module in rig.modules:module.free()
 check(concepts==7,"sept concepts clairement identifiés, dont les quatre combinaisons de démonstration")
 var angers:Dictionary={"source_id":"angers","id":"angers_a","guidance":"steel"}
 var foreign:=StockCatalog.find("nantes__incentro")
 var profile:=VehicleLibrary.for_fleet(foreign,angers)
 check(not "aps" in profile.power_modes(),"choisir Angers ne confère pas l'APS à un Incentro")
 check(not Compatibility.mission_allowed(profile,["overhead","aps"],"steel"),"Incentro refusé sur réseau APS")
 for stock in StockCatalog.for_network(angers,["overhead","aps"]):
  check("aps" in stock.electric_modes and stock.guidance=="steel","filtre électrique et guidage : "+str(stock.id))
 var unchanged:=VehicleLibrary.default_for({"source_id":"angers","id":"angers_a","guidance":"rubber_guided"})
 check(unchanged.guidance=="steel","le choix d'un réseau ne transforme pas non plus le guidage de la rame")
 var irigo:=StockCatalog.find("angers__citadis_302")
 var native_paint:=TramModel.livery_for(angers,irigo)
 var foreign_paint:=TramModel.livery_for({"source_id":"nantes","id":"nantes_1","color":"#ff0000"},irigo)
 check(native_paint.base==foreign_paint.base and native_paint.elements==foreign_paint.elements,"livrée Irigo conservée à Nantes")
 check(StockCatalog.find("idf__citadis_302__t8").id=="idf__citadis_302__t7","T7 et T8 regroupés avec migration de l'ancien identifiant")
 check(StockCatalog.find("idf__citadis_dualis__t12").id=="idf__citadis_dualis__t11","Dualis IDFM regroupés")
 check(StockCatalog.native_for(angers).all(func(stock):return not stock.fictional),"concepts absents des flottes de mission")
 # Depuis 66cb61c (Codex), toutes les Citadis 302 utilisent la traction enregistrée approuvée (Rotterdam) ;
 # la captation du Mans reste sélectionnée pour la Citadis 402 du Mans.
 var lemans:=TramAudio.profile_for("citadis_302","lemans__citadis_402")
 check(str(lemans.bank_data.source.page).contains("458858"),"captation du Mans effectivement sélectionnée")
 check(TramAudio.profile_for("avanto","sarreguemines__flexity_link").quality=="synthetic","pas de fausse captation Avanto pour le Saarbahn")
 StockHD.reset_cache()
 print("MAX_TRIANGLES|",maximum);print("TOTAL_ECHECS|",failures);quit(1 if failures else 0)
