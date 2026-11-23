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
 if cab=="naolib":
  var source_modules:Array=p.modules.duplicate(true);p.modules=[]
  for source_index in [0,2,3,2,3,2,6]:p.modules.append(source_modules[source_index].duplicate(true))
 var front:Dictionary=p.front
 # Les familles dédiées (Tours, Reims, Eurotram, Flexity…) conservent leurs profils d'origine.
 if cab=="tfs_nantes":
  front.length_m=.65;front.bulge=.055
  front.plan=[[0,1],[.65,1],[.9,.98],[1,.91]]
  front.section=[[.25,.94],[.65,1],[2.8,1],[3.10,.97],[3.36,.90]]
  front.side=[[.25,.16],[.65,0],[1.2,.02],[2.7,.16],[3.08,.22],[3.36,1]]
  front.windshield={"bottom_m":1.30,"top_m":3.04,"wrap":.02,"lower_curve_m":.14,"half_width_m":.89}
  front.headlights={"shape":"round","x_m":.72,"y_m":1.12,"w_m":.16,"h_m":.16}
  front.extra_lights=[{"x_m":.72,"y_m":.91,"r_m":.04,"color":"#e66c43"},{"x_m":.58,"y_m":.91,"r_m":.035,"color":"#942e2e"}]
  front.destination={"y_m":2.87,"w_m":1.55,"h_m":.20}
  front.wiper_lines=[[[.68,1.32],[-.12,2.27]]]
 elif cab in ["tfs_paris","tfs_grenoble"]:
  front.length_m=.54;front.bulge=.095
  front.plan=[[0,1],[.65,.995],[.9,.97],[1,.89]]
  front.section=[[.25,.90],[.70,.97],[1.3,1],[2.8,.98],[3.15,.93],[3.36,.83]]
  front.side=[[.25,.23],[.65,0],[1.1,0],[2.7,.08],[3.10,.13],[3.36,1]]
  front.windshield={"bottom_m":1.15,"top_m":3.10,"wrap":.03,"lower_curve_m":.04,"half_width_m":.94}
  front.headlights={"shape":"round","x_m":.83,"y_m":.75,"w_m":.13,"h_m":.13}
  front.lamp_housings={"x_m":.76,"y_m":.75,"w_m":.30,"h_m":.18}
  front.upper_light={"y_m":3.23}
  front.destination={"y_m":2.92,"w_m":1.55,"h_m":.20}
  front.wiper_lines=[[[.68,1.17],[.10,2.08]],[[-.68,1.17],[-.10,2.08]]]
 elif cab in ["irigo302","irigo305"]:
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
 if not pantograph_seen:
  var first_module:Dictionary=p.modules[0]
  if not first_module.has("roof"):first_module.roof=[]
  first_module.roof.append({"type":"pantograph","z_m":float(first_module.length_m)*.65,"size":[1.2,.3,2.0]})
 if cab=="lille305":
  (p.modules[0] as Dictionary).doors=(p.modules[0].doors as Array).slice(-1)
  (p.modules[-1] as Dictionary).doors=(p.modules[-1].doors as Array).slice(0,1)
 if cab in ["irigo302","irigo305"]:
  var first_ratio:=float(p.modules[0].doors[0].z_m)/float(p.modules[0].length_m)
  for i in p.modules.size():
   var module:Dictionary=p.modules[i];var length:=float(module.length_m)
   if i==0 or i==p.modules.size()-1:
    var center:=length*first_ratio if i==0 else length*(1-first_ratio)
    var door_width:=.8 if cab=="irigo302" else 1.3
    module.doors=[{"z_m":center,"width_m":door_width,"leaves":1 if cab=="irigo302" else 2}]
    module.windows=[]
    for bounds in [[.18,center-door_width*.5-.12],[center+door_width*.5+.12,length-.18]]:
     if bounds[1]-bounds[0]>.15:module.windows.append({"z0_m":bounds[0],"z1_m":bounds[1]})
   elif module.get("bogie",false):module.doors=[]
   else:
    module.doors=[{"z_m":length*.25,"width_m":1.3,"leaves":2},{"z_m":length*.75,"width_m":1.3,"leaves":2}]
    module.windows=[{"z0_m":length*.25+.73,"z1_m":length*.75-.73}]
 if src=="saintetienne":p.unidirectional=true
 return TramParts.configure_plan(p,entry)
