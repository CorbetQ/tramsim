extends SceneTree
## Inspect the shipped meshes, not a flag: upper roofs need body underneath.
var failures:=0
func check(ok:bool,message:String)->void:
	if ok:print("ok: ",message)
	else:failures+=1;printerr("ECHEC: ",message)
func _initialize()->void:run.call_deferred()
func transform_to(body:Node3D,node:Node3D)->Transform3D:
	var transform:=Transform3D.IDENTITY;var current:=node
	while current!=body:
		transform=current.transform*transform;current=current.get_parent()
	return transform
func inside_nose(point:Vector3,boundary:float,direction:float,cfg:Dictionary,width:float)->bool:
	var advance:=direction*(point.z-boundary)
	if advance<=0:return true
	var profile:Dictionary=cfg.definition.nose_profile
	var depth:=float(cfg.definition.frame.front.length_m)*TramModel._sm(profile.D,point.y)
	if depth<=.001:return advance<.003
	var body:Dictionary=cfg.definition.frame.body
	var half:=width*.5-.018*pow(point.y-1.75,2)
	var cant:=float(body.cant_m);var height:=float(cfg.definition.frame.height_m)
	if point.y<.42:
		var t:=clampf((point.y-.25)/(.42-.25),0,1)
		half=(width*.5-.07)+(half-width*.5+.07)*(1-pow(1-t,2))
	elif point.y>cant:
		var shoulder:=float(body.roof_shoulder_m)
		var xc:=width*.5-.018*pow(cant-1.75,2)
		half=xc-shoulder+shoulder*sqrt(maxf(0,1-pow((point.y-cant)/(height-cant),2)))
	return pow(absf(point.x)/maxf(half,.01),float(profile.p))+pow(advance/depth,float(profile.p))<=1.025
func run()->void:
	var ids:Array=load("res://tests/audit/family_front_shots.gd").CITADIS.duplicate()
	ids.append("angers__citadis_302")
	for id in ids:
		var entry:=StockCatalog.find(id);var cfg:=TramParts.configuration(entry)
		var height:=float(cfg.definition.frame.height_m)
		var front:=float(cfg.definition.frame.front.length_m)
		for mobile in [false,true]:
			for lod in StockHD.LOD_NAMES:
				var root_:=StockHD.scene(TramParts.lod_file(id,lod,mobile))
				check(root_!=null,"%s %s %s : ressource lisible"%[id,lod,mobile])
				if root_==null:continue
				for index in [0,cfg.rows.size()-1]:
					var body:=StockHD.find(root_,"module_%02d"%index) as Node3D
					var boundary:=-float(cfg.rows[index].length_m)*.5+front if index==0 else float(cfg.rows[index].length_m)*.5-front
					var count:=0;var invalid:=0
					var cabin_vertices:=0;var cabin_invalid:=0
					for node in [body]+body.find_children("*","MeshInstance3D",true,false):
						if not node is MeshInstance3D or node.mesh==null:continue
						if "panto" in str(body.get_path_to(node)).to_lower():continue
						var transform:=transform_to(body,node)
						for surface in node.mesh.get_surface_count():
							var vertices:PackedVector3Array=node.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
							for point in vertices:
								var actual:Vector3=transform*point
								if "cab_proxy" in str(body.get_path_to(node)):
									cabin_vertices+=1
									if not inside_nose(actual,boundary,-1 if index==0 else 1,cfg,float(entry.width)):cabin_invalid+=1
								if actual.y<=height+.005:continue
								count+=1
								if actual.z<boundary-.002 if index==0 else actual.z>boundary+.002:invalid+=1
					check(count>0 and invalid==0,"%s %s %s extrémité %d : %d sommets au-dessus du toit, %d sans support"%[id,lod,mobile,index,count,invalid])
					if cabin_vertices>0:check(cabin_invalid==0,"%s %s %s extrémité %d : plafond/plancher de cabine contenus dans la coque (%d sommets hors coque)"%[id,lod,mobile,index,cabin_invalid])
	StockHD.reset_cache();print("TOTAL_ECHECS|",failures);quit(1 if failures else 0)
