class_name StockGeometry
extends RefCounted
## Surcharges ciblées des plans historiques : conserve leur coque, UV, rig et livrées.
## Les relevés de silhouette sont des estimations depuis les photographies du registre.
static func apply(base:Dictionary,entry:Dictionary)->Dictionary:
 if str(entry.get("cab_profile",""))=="marseille_caf":base=TramModel.plan("flexity_marseille")
 if str(entry.get("cab_profile",""))=="naolib":base=TramModel.plan("citadis_x05_nantes")
 var p:Dictionary=base.duplicate(true)
 p.id=entry.get("family",base.id)
 if entry.is_empty():return p
 var cab:=str(entry.get("cab_profile",""));var src:=str(entry.get("network",""))
 var front:Dictionary=p.front
 # Les familles dédiées (Tours, Reims, Eurotram, Flexity…) conservent leurs profils d'origine.
 if cab in ["irigo302","irigo305"]:
  front.plan=[[0,1],[.35,.99],[.7,.94],[1,.76]]
  front.section=[[.25,.92],[.6,1],[1.2,1],[2.4,.99],[2.9,.90],[3.3,.66]]
  front.windshield={"bottom_m":1.03,"top_m":2.9,"wrap":.36,"lower_curve_m":.28}
  front.headlights={"shape":"round","x_m":.86,"y_m":.84,"w_m":.16,"h_m":.16}
  front.extra_lights=[{"x_m":.65,"y_m":.82,"r_m":.065,"color":"#55616b"},{"x_m":.47,"y_m":.84,"r_m":.06,"color":"#92242c"}]
  front.destination={"y_m":2.76,"w_m":1.25,"h_m":.20}
 elif cab=="lyon_egg":
  front.plan=[[0,1],[.35,.97],[.65,.9],[1,.68]]
  front.section=[[.2,.77],[.6,.97],[1.2,1],[2,.91],[2.65,.69],[3.3,.35]]
  front.windshield={"bottom_m":1.15,"top_m":2.75,"wrap":.32}
  front.headlights={"shape":"round","x_m":.68,"y_m":.73,"w_m":.14,"h_m":.14}
 elif cab in ["bordeaux","toulouse","grenoble","rouen"]:
  front.plan=[[0,1],[.35,.99],[.70,.94],[1,.72]]
  front.windshield={"bottom_m":.95 if cab=="bordeaux" else 1.12,"top_m":2.9,"wrap":.42}
  front.headlights={"shape":"round","x_m":.78,"y_m":.72,"w_m":.16,"h_m":.16}
 elif cab in ["dijon","brest","orleans302","lehavre","lemans","tam302","paris_t2","paris_t3","paris_t7","valenciennes"]:
  front.plan=[[0,1],[.35,.99],[.7,.95],[1,.75]]
  front.headlights={"shape":"round","x_m":.85,"y_m":.8,"w_m":.16,"h_m":.16}
  front.extra_lights=[{"x_m":.65,"y_m":.79,"r_m":.06,"color":"#65727c"}]
 elif cab=="cts403ng":
  front.plan=[[0,1],[.5,1],[.85,.94],[1,.80]];front.length_m=1.8;front.bulge=.12
  front.side=[[.2,.12],[.6,0],[1.1,.02],[1.5,.15],[2.4,.52],[3.1,.83],[3.3,1]]
  front.windshield={"bottom_m":1.12,"top_m":2.95,"wrap":.32};front.headlights={"shape":"strip","x_m":.87,"y_m":1.0,"w_m":.30,"h_m":.09}
 elif cab=="cts3":
  front.plan=[[0,1],[.4,.99],[.8,.92],[1,.76]];front.length_m=1.9
  front.windshield={"bottom_m":1.02,"top_m":2.95,"wrap":.42};front.headlights={"shape":"round","x_m":.87,"y_m":.85,"w_m":.13,"h_m":.13}
 elif cab=="marseille_caf":
  front.plan=[[0,1],[.4,.98],[.8,.92],[1,.78]];front.length_m=1.75
  front.windshield={"bottom_m":1.15,"top_m":2.9,"wrap":.35}
  front.headlights={"shape":"round","x_m":.80,"y_m":.95,"w_m":.17,"h_m":.17}
  front.extra_lights=[{"x_m":1.0,"y_m":.95,"r_m":.06,"color":"#8b2329"}]
 elif cab=="tpg_cityrunner":
  front.plan=[[0,1],[.4,.98],[.8,.95],[1,.8]];front.length_m=1.3
  front.windshield={"bottom_m":1.23,"top_m":2.84,"wrap":.23}
  front.headlights={"shape":"round","x_m":.77,"y_m":.9,"w_m":.17,"h_m":.17}
 elif cab in ["tango_tpg","tango_blt","flexity_basel","saarbahn"]:
  front.plan=[[0,1],[.5,.99],[.85,.94],[1,.82]];front.length_m=1.2
  front.windshield={"bottom_m":1.25,"top_m":2.9,"wrap":.20}
  front.headlights={"shape":"round","x_m":.86,"y_m":.9,"w_m":.16,"h_m":.16}
 if str(entry.get("id","")) in ["toulouse__citadis_305","besancon__citadis_x05"]:
  front.headlights={"shape":"round","x_m":.88,"y_m":1.07,"w_m":.14,"h_m":.14}
  front.extra_lights=[{"x_m":.9,"y_m":1.29,"r_m":.06,"color":"#c6cfd2"},{"x_m":.83,"y_m":.88,"r_m":.055,"color":"#8a2830"}]
 p.front=front
 var desired:=int(entry.get("module_count",(p.modules as Array).size()))
 var mods:Array=p.modules
 if desired!=mods.size():
  var lead:Dictionary=mods[0].duplicate(true);var tail:Dictionary=mods[-1].duplicate(true)
  var inside:Array=mods.slice(1,mods.size()-1);var replacement:Array=[lead]
  for i in range(1,desired-1):
   var template:Dictionary=inside[(i-1)%inside.size()].duplicate(true)
   if str(entry.family)=="urbos" and i%2==0:
    template={"kind":"middle","length_m":6.4,"bogie":true,"windows":[{"z0_m":.2,"z1_m":6.2}],"doors":[],"roof":[]}
   replacement.append(template)
  if desired>1:replacement.append(tail)
  p.modules=replacement
 var sizes:Array=entry.get("geometry",{}).get("module_lengths",[])
 if sizes.size()==(p.modules as Array).size():
  for i in sizes.size():
   var module:Dictionary=p.modules[i];var target:=float(sizes[i]);var ratio:=target/float(module.length_m)
   for door in module.get("doors",[]):door.z_m=float(door.z_m)*ratio
   for window in module.get("windows",[]):window.z0_m=float(window.z0_m)*ratio;window.z1_m=float(window.z1_m)*ratio
   for roof in module.get("roof",[]):roof.z_m=float(roof.z_m)*ratio
   if module.has("bogie_z_m"):module.bogie_z_m=float(module.bogie_z_m)*ratio
   module.length_m=target
 var pantograph_seen:=false
 for module in p.modules:
  for roof in module.get("roof",[]):
   if str(roof.get("type",""))=="pantograph":
    if pantograph_seen:roof.type="box"
    pantograph_seen=true
 # Normalise les positions des portes selon la longueur locale conservée du plan de base.
 if cab=="lille305":
  (p.modules[0] as Dictionary).doors=(p.modules[0].doors as Array).slice(-1)
  (p.modules[-1] as Dictionary).doors=(p.modules[-1].doors as Array).slice(0,1)
 if cab=="irigo305":
  for module in p.modules:
   for door in module.get("doors",[]):door.width_m=1.30;door.leaves=2
 if src=="saintetienne":p.unidirectional=true
 return p
