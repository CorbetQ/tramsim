class_name TramParts
extends RefCounted
## Compositions reference independent, animated bodies. Never combine two visible shells.
const INDEX := "res://data/rolling_stock/parts_manifest.json"
static var enabled := true
static var _data: Dictionary = {}
static var _blank: ImageTexture
static var _kits: Dictionary = {}
static var _fitted_meshes: Dictionary = {}

static func kit(id: String) -> Dictionary:
	if _kits.has(id):return _kits[id]
	var path:String=manifest().get("kits",{}).get(id,"")
	if not allowed(path) or not FileAccess.file_exists(path):return {}
	var value=JSON.parse_string(FileAccess.get_file_as_string(path))
	if not value is Dictionary:return {}
	_kits[id]=value;return value

static func configuration(entry: Dictionary) -> Dictionary:
	if not enabled or manifest().get("schema",0)!=2 or entry.is_empty():return {}
	var ref:Dictionary=manifest().get("variants",{}).get(str(entry.get("id","")),{})
	var base:=kit(str(ref.get("kit","")))
	if base.get("parts",{}).is_empty():return {}
	var count:=int(entry.get("module_count",ref.get("count",0)))
	if count<2:return {}
	var layout:Array=(base.layout as Array).duplicate()
	if layout.size()!=count:
		var pool:Array=[]
		var start_role:String=base.parts[base.layout[1]].role if base.layout.size()>2 else "suspended"
		for role_ in [start_role,"powered" if start_role=="suspended" else "suspended"]:
			for key in base.parts:
				if base.parts[key].role==role_:pool.append(key);break
		if count>2 and pool.is_empty():return {}
		layout=["end_a"]
		for i in count-2:layout.append(pool[i%pool.size()])
		layout.append("end_b")
	var panto_slots:Array=[]
	for i in layout.size():
		if bool(base.parts[layout[i]].get("pantograph",false)):panto_slots.append(i)
	if panto_slots.is_empty():
		for key in base.parts:
			if base.parts[key].get("pantograph",false) and count>2:
				var slot:=clampi(count/2,1,count-2);layout[slot]=key;panto_slots.append(slot);break
	var active_panto:=int(panto_slots[0]) if not panto_slots.is_empty() else -1
	var equipment:Dictionary=base.get("equipment",{}).get("pantograph",{})
	var mount:Dictionary={}
	if not equipment.is_empty():
		active_panto=-1
		for i in range(1,count-1):
			if str(base.parts[layout[i]].role)==str(equipment.role):active_panto=i;break
		var fallback:=active_panto<0
		if fallback:active_panto=0
		mount={"slot":active_panto,"z_ratio":.70 if fallback else float(equipment.z_ratio),"y":float(equipment.mount_y)+(.32 if fallback else 0.0)}
	var lengths:Array=[]
	for key in layout:lengths.append(float(base.parts[key].length_m))
	var desired:=float(entry.get("length",ref.length_m))
	var explicit:Array=entry.get("geometry",{}).get("module_lengths",[])
	if explicit.size()==count:lengths=explicit.duplicate()
	elif count==int(base.master_count) and absf(desired-float(base.master_length))<.02:
		lengths=base.get("master_lengths",lengths).duplicate()
	else:
		var middle:=0.0
		for i in range(1,count-1):middle+=float(lengths[i])
		var available:=desired-float(lengths[0])-float(lengths[-1])
		if count>2 and available>0:
			for i in range(1,count-1):lengths[i]=float(lengths[i])*available/middle
		else:
			var total:=0.0
			for length in lengths:total+=float(length)
			for i in lengths.size():lengths[i]=float(lengths[i])*desired/total
	var rows:Array=[];var offset:=-desired*.5;var doors:=0
	for i in count:
		var part:Dictionary=base.parts[layout[i]]
		rows.append({"part":layout[i],"index":i,"role":part.role,"length_m":float(lengths[i]),"center_z":offset+float(lengths[i])*.5,"pantograph":i==active_panto})
		offset+=float(lengths[i]);doors+=int(part.get("door_count",0))
	return {"kit":base.id,"definition":base,"rows":rows,"length_m":desired,"doors":doors,"livery":ref.get("livery",base.id),"equipment_mount":mount}

static func configure_plan(original: Dictionary, entry: Dictionary) -> Dictionary:
	var cfg:=configuration(entry)
	if cfg.is_empty():return original
	var p:Dictionary=cfg.definition.frame.duplicate(true);p.id=entry.family;p.modules=[]
	for row in cfg.rows:
		var module:Dictionary=cfg.definition.parts[row.part].plan.duplicate(true)
		var ratio:=float(row.length_m)/float(module.length_m)
		for door in module.get("doors",[]):door.z_m=float(door.z_m)*ratio
		for window in module.get("windows",[]):window.z0_m=float(window.z0_m)*ratio;window.z1_m=float(window.z1_m)*ratio
		for roof in module.get("roof",[]):
			roof.z_m=float(roof.z_m)*ratio
			if str(roof.type)=="pantograph" and not row.pantograph:roof.type="box"
		if module.has("bogie_z_m"):module.bogie_z_m=float(module.bogie_z_m)*ratio
		if row.pantograph and not cfg.equipment_mount.is_empty():
			var roof:Dictionary=cfg.definition.equipment.pantograph.roof.duplicate(true)
			roof.z_m=float(cfg.equipment_mount.z_ratio)*float(row.length_m);module.roof.append(roof)
		module.length_m=float(row.length_m);p.modules.append(module)
	return p

static func hd_entry(variant: String) -> Dictionary:
	var entry:=StockCatalog.find(variant);var cfg:=configuration(entry)
	if cfg.is_empty() or str(cfg.definition.renderer)!="hd":return {}
	var result:Dictionary=StockHD.manifest().get("variants",{}).get(str(cfg.definition.master),{}).duplicate(true)
	if result.is_empty():return {}
	result["_kit"]=cfg.kit;result["_variant"]=variant;result.family=entry.family;result.name=entry.name
	result.length_m=cfg.length_m;result.modules=[];result.doors=cfg.doors
	for row in cfg.rows:result.modules.append(row.length_m)
	# Derived composition budgets come from the actual shared prototypes.
	for lod in StockHD.LOD_NAMES:
		for mobile in [false,true]:
			var key:=_lod_key(lod,mobile);var count:=0
			for row in cfg.rows:count+=int(cfg.definition.parts[row.part].get("triangles",{}).get(key,0))
			if not cfg.equipment_mount.is_empty():count+=int(cfg.definition.equipment.pantograph.get("triangles",{}).get(key,0))
			result.lods[lod]["mobile_tris" if mobile else "tris"]=count
	if not cfg.equipment_mount.is_empty():
		result.panto.module=int(cfg.equipment_mount.slot)
		var offset:=float(cfg.equipment_mount.y)-float(cfg.definition.equipment.pantograph.mount_y)
		result.panto.head_down_y=float(result.panto.head_down_y)+offset;result.panto.head_up_y=float(result.panto.head_up_y)+offset
	return result
static func manifest() -> Dictionary:
	if _data.is_empty() and FileAccess.file_exists(INDEX):
		var value=JSON.parse_string(FileAccess.get_file_as_string(INDEX))
		if value is Dictionary:_data=value
	return _data
static func lod_file(variant: String, lod: String, mobile: bool) -> String:
	if not enabled:return ""
	if manifest().get("schema",0)==2:
		var ref:Dictionary=manifest().get("variants",{}).get(variant,{})
		var base:=kit(str(ref.get("kit","")))
		if base.is_empty() or base.get("renderer")!="hd":return ""
		if lod=="cab":return str(base.cab.get("cab_m" if mobile else "cab",""))
		return str(manifest().kits[base.id])+"::"+variant+"::"+lod+"::"+str(int(mobile))
	var entry:Dictionary=manifest().get("variants",{}).get(variant,{})
	if lod=="cab":return str(entry.get("cab",{}).get("cab_m" if mobile else "cab",""))
	var key:String={"LOD0":"lod1" if mobile else "lod0","LOD1":"lod1_m" if mobile else "lod1","LOD2":"lod2","LOD3":"lod3"}.get(lod,"")
	return str(entry.get("lods",{}).get(key,""))
static func allowed(path: String) -> bool:
	return path.begins_with("res://tram_parts/") and not ".." in path.get_slice("::",0).split("/") and not "\\" in path
static func assemble(path: String) -> Node3D:
	if "::" in path:return assemble_kit(path)
	if not allowed(path) or not FileAccess.file_exists(path):return null
	var value=JSON.parse_string(FileAccess.get_file_as_string(path))
	if not value is Dictionary or value.get("schema")!=1 or not value.get("parts") is Array:return null
	var holder:=Node3D.new();holder.name="ComposedTram"
	var rows:Array=value.parts
	for i in rows.size():
		var row:Dictionary=rows[i]
		if not allowed(str(row.get("file",""))) or int(row.get("index",-1))!=i:
			holder.free();return null
		var source:=StockHD.scene(str(row.file))
		if source==null:holder.free();return null
		var instance:=source.duplicate() as Node3D
		var body:=StockHD.find(instance,"module_%02d" % i) as Node3D
		if body==null:instance.free();holder.free();return null
		for node in [body]+body.find_children("*","",true,false):node.owner=null
		body.get_parent().remove_child(body);holder.add_child(body)
		body.transform=Transform3D.IDENTITY;body.position.z=float(row.center_z)
		body.set_meta("tram_part_file",row.file);body.set_meta("tram_part_role",row.role)
		instance.free()
	return holder
static func role(entry: Dictionary, index: int) -> String:
	var cfg:=configuration(entry)
	if not cfg.is_empty() and index>=0 and index<cfg.rows.size():return str(cfg.rows[index].role)
	var count:=int(entry.get("module_count",1))
	if index==0:return "end_a"
	if index==count-1:return "end_b"
	var plan:=StockGeometry.apply(TramModel.plan(str(entry.family)),entry)
	return "powered" if bool(plan.modules[index].get("bogie",false)) else "suspended"

static func apply_native(rig, livery: Dictionary) -> bool:
	if not enabled:return false
	if manifest().get("schema",0)==2:return apply_native_kit(rig,livery)
	var rows:Array=manifest().get("native",{}).get(str(livery.variant_id),[])
	if rows.size()!=rig.modules.size():return false
	var sources:Array=[]
	for row in rows:
		if not allowed(str(row.get("file",""))):return false
		var source:=StockHD.scene(str(row.file))
		if source==null:return false
		sources.append(source)
	for i in rows.size():
		var target:MeshInstance3D=rig.modules[i];var source:Node3D=sources[i]
		for node in [source]+source.find_children("*","MeshInstance3D",true,false):
			if not node is MeshInstance3D or (node as MeshInstance3D).mesh==null:continue
			var destination:=target.get_node_or_null(source.get_path_to(node)) as MeshInstance3D
			if destination==null:continue
			destination.mesh=(node as MeshInstance3D).mesh
			var original:=destination.material_override as ShaderMaterial
			var baked:=(node as MeshInstance3D).material_override as ShaderMaterial
			if original==null or baked==null:continue
			var material:=original.duplicate() as ShaderMaterial
			material.set_shader_parameter("part_livery_enabled",true)
			material.set_shader_parameter("part_livery",baked.get_shader_parameter("part_livery"))
			var design:=LiveryLibrary.for_part(livery.get("custom_livery",{}),livery.stock_entry,i)
			if not design.is_empty():
				if _blank==null:
					var image:=Image.create(1024,512,false,Image.FORMAT_RGBA8);image.fill(Color.WHITE);_blank=ImageTexture.create_from_image(image)
				material.set_shader_parameter("part_custom_enabled",true)
				material.set_shader_parameter("part_custom",LiveryPainter.texture(_blank,design,livery.stock_entry,i))
				var window:=Color(str(design.colors.window))
				material.set_shader_parameter("part_window_color",Vector3(window.r,window.g,window.b))
				material.set_shader_parameter("part_size",Vector3(float(livery.width),3.4,rig.module_lengths[i]))
				material.set_shader_parameter("part_end",-1 if i==0 else (1 if i==rows.size()-1 else 0))
			destination.material_override=material
		target.set_meta("tram_part_file",rows[i].file);target.set_meta("tram_part_role",rows[i].role)
	return true

static func _lod_key(lod: String, mobile: bool) -> String:
	return str({"LOD0":"lod1" if mobile else "lod0","LOD1":"lod1_m" if mobile else "lod1","LOD2":"lod2","LOD3":"lod3"}.get(lod,"lod0"))

static func _knots(part: Dictionary, target: float, front_length: float) -> Array:
	var length:=float(part.length_m);var ratio:=target/length
	var ranges:Array=[]
	var lo:=-length*.5;var hi:=length*.5
	if str(part.role)=="end_a":ranges.append([lo,lo+front_length+.25,-target*.5,-target*.5+front_length+.25])
	if str(part.role)=="end_b":ranges.append([hi-front_length-.25,hi,target*.5-front_length-.25,target*.5])
	for door in part.plan.get("doors",[]):
		var center:=float(door.z_m)-length*.5;var half:=float(door.width_m)*.5+.035
		var intersects:=false
		for existing in ranges:
			if center+half>float(existing[0]) and center-half<float(existing[1]):intersects=true
		if not intersects:ranges.append([center-half,center+half,center*ratio-half,center*ratio+half])
	if part.plan.get("bogie",false):
		var center:=float(part.plan.get("bogie_z_m",length*.5))-length*.5;var intersects:=false
		for existing in ranges:
			if center+.85>float(existing[0]) and center-.85<float(existing[1]):intersects=true
		if not intersects:ranges.append([center-.85,center+.85,center*ratio-.85,center*ratio+.85])
	var knots:Array=[Vector2(lo,-target*.5),Vector2(hi,target*.5)]
	for region in ranges:
		knots.append(Vector2(region[0],region[2]));knots.append(Vector2(region[1],region[3]))
	knots.sort_custom(func(a,b):return a.x<b.x)
	var clean:Array=[]
	for point in knots:
		if clean.is_empty() or absf(point.x-clean[-1].x)>.0001:clean.append(point)
	for i in range(1,clean.size()):
		if clean[i].y<=clean[i-1].y:
			# Unusually short bodies keep a rigid nose and resize the rear body.
			if str(part.role)=="end_a":return [Vector2(lo,-target*.5),Vector2(lo+front_length+.25,-target*.5+front_length+.25),Vector2(hi,target*.5)]
			if str(part.role)=="end_b":return [Vector2(lo,-target*.5),Vector2(hi-front_length-.25,target*.5-front_length-.25),Vector2(hi,target*.5)]
			return [Vector2(lo,-target*.5),Vector2(hi,target*.5)]
	return clean

static func _map_z(z: float, knots: Array) -> float:
	for i in range(1,knots.size()):
		if z<=knots[i].x:
			var a:Vector2=knots[i-1];var b:Vector2=knots[i]
			return lerpf(a.y,b.y,(z-a.x)/maxf(b.x-a.x,.00001))
	var last:Vector2=knots[-1];return last.y+(z-last.x)

static func _fit_node(node: Node3D, old_parent: Transform3D, new_parent: Transform3D, knots: Array, rigid_parent := false) -> void:
	var old:=old_parent*node.transform
	var new_transform:=old
	var rigid:=rigid_parent or str(node.name).to_lower().begins_with("panto")
	if rigid_parent:new_transform=new_parent*node.transform
	else:new_transform.origin.z=_map_z(old.origin.z,knots)
	node.transform=new_parent.affine_inverse()*new_transform
	if node is MeshInstance3D and (node as MeshInstance3D).mesh!=null and not rigid:
		var source:Mesh=(node as MeshInstance3D).mesh
		var key:=str(source.get_instance_id())+str(knots)+str(old)+str(new_transform)
		if not _fitted_meshes.has(key):
			var mesh:=ArrayMesh.new()
			var inverse:=new_transform.affine_inverse()
			var normal_basis:=old.basis.inverse().transposed()
			for surface in source.get_surface_count():
				var arrays:Array=source.surface_get_arrays(surface)
				var positions:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
				var normals:PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
				for i in positions.size():
					var p:=old*positions[i];var initial:=p.z;p.z=_map_z(initial,knots)
					positions[i]=inverse*p
					if not normals.is_empty():
						var n:=normal_basis*normals[i]
						var derivative:=(_map_z(initial+.001,knots)-_map_z(initial-.001,knots))/.002
						n.z/=maxf(derivative,.01);normals[i]=(new_transform.basis.transposed()*n).normalized()
				arrays[Mesh.ARRAY_VERTEX]=positions;arrays[Mesh.ARRAY_NORMAL]=normals
				mesh.add_surface_from_arrays(source.surface_get_primitive_type(surface),arrays)
				mesh.surface_set_material(surface,source.surface_get_material(surface))
			if _fitted_meshes.size()>=128:_fitted_meshes.erase(_fitted_meshes.keys()[0])
			_fitted_meshes[key]=mesh
		(node as MeshInstance3D).mesh=_fitted_meshes[key]
	for child in node.get_children():
		if child is Node3D:_fit_node(child,old,new_transform,knots,rigid)

static func _strip_panto(root: Node3D, part: Dictionary) -> void:
	for node in root.find_children("panto_*","",true,false):
		if is_instance_valid(node):node.get_parent().remove_child(node);node.free()
	for path in part.get("bindings",{}).get("panto",{}).values():
		var node:=root.get_node_or_null(str(path))
		if node!=null:node.get_parent().remove_child(node);node.free()

## P4 : un kit HD partagé par plusieurs réseaux garde ses caisses ; seul l'atlas `livery*` change (surcharge de surface,
## reprise par StockHD.dress). Matériaux mis en cache par atlas : aucune copie de maillage.
static var _repainted: Dictionary = {}
static func _repaint(body: Node3D, livery_id: String, part: String, lod_key: String) -> void:
	var tag:String={"lod0":"4k","lod1":"2k","lod1_m":"2k","lod2":"512","lod3":"256"}.get(lod_key,"2k")
	var atlas:String=manifest().get("liveries",{}).get(livery_id,{}).get("parts",{}).get(part,{}).get(tag,"")
	if tag=="4k" and not ResourceLoader.exists(atlas):atlas=manifest().get("liveries",{}).get(livery_id,{}).get("parts",{}).get(part,{}).get("2k","")   # P4 : 4k hors APK Android
	if not atlas.begins_with("res://tram_livery/livery/") or not ResourceLoader.exists(atlas):return
	for mi in body.find_children("*","MeshInstance3D",true,false)+([body] if body is MeshInstance3D else []):
		var g:=mi as MeshInstance3D
		if g.mesh==null:continue
		for s in g.mesh.get_surface_count():
			var src:=g.mesh.surface_get_material(s)
			if not src is BaseMaterial3D or not str(src.resource_name).begins_with("livery"):continue
			var k:="%d|%s"%[src.get_instance_id(),atlas]
			if not _repainted.has(k):
				var m:=(src as BaseMaterial3D).duplicate() as BaseMaterial3D
				m.albedo_texture=load(atlas);_repainted[k]=m
			g.set_surface_override_material(s,_repainted[k])

static func assemble_kit(path: String) -> Node3D:
	var fields:=path.split("::")
	if fields.size()!=4:return null
	var entry:=StockCatalog.find(fields[1]);var cfg:=configuration(entry)
	if cfg.is_empty() or str(manifest().kits[cfg.kit])!=fields[0]:return null
	var key:=_lod_key(fields[2],fields[3]=="1")
	var holder:=Node3D.new();holder.name="ComposedTram";var door_offset:=0
	for row in cfg.rows:
		var part:Dictionary=cfg.definition.parts[row.part]
		var file:String=part.models.get(key,"")
		if not allowed(file):holder.free();return null
		var source:=StockHD.scene(file)
		if source==null:holder.free();return null
		var instance:=source.duplicate() as Node3D
		var body:=StockHD.find(instance,str(part.root)) as Node3D
		if body==null:instance.free();holder.free();return null
		for node in [body]+body.find_children("*","",true,false):node.owner=null
		if body!=instance:body.get_parent().remove_child(body)
		holder.add_child(body)
		if body!=instance:instance.free()
		body.transform=Transform3D.IDENTITY
		if str(cfg.livery)!=str(cfg.kit):_repaint(body,str(cfg.livery),str(row.part),key)
		if not row.pantograph:_strip_panto(body,part)
		if absf(float(row.length_m)-float(part.length_m))>.0001:
			_fit_node(body,Transform3D.IDENTITY,Transform3D.IDENTITY,_knots(part,float(row.length_m),float(cfg.definition.frame.front.get("length_m",1.2))))
		var body_offset:=body.position
		body.set_meta("tram_part_local_offset",body_offset)
		if row.pantograph and not cfg.equipment_mount.is_empty():
			var equipment:Dictionary=cfg.definition.equipment.pantograph
			var gear_file:String=equipment.models.get(key,"")
			if gear_file!="":
				var gear_source:=StockHD.scene(gear_file)
				if gear_source==null:holder.free();return null
				var gear_instance:=gear_source.duplicate() as Node3D
				var gear:=StockHD.find(gear_instance,"panto_base") as Node3D
				if gear==null:gear_instance.free();holder.free();return null
				for node in [gear]+gear.find_children("*","",true,false):node.owner=null
				if gear!=gear_instance:gear.get_parent().remove_child(gear)
				body.add_child(gear)
				if gear!=gear_instance:gear_instance.free()
				gear.position=Vector3(0,float(cfg.equipment_mount.y),(float(cfg.equipment_mount.z_ratio)-.5)*float(row.length_m))-body_offset
		var old_ids:Array=[]
		for node in body.find_children("door_*","",true,false):
			var pieces:=str(node.name).split("_")
			if pieces.size()>2 and pieces[1].is_valid_int() and not int(pieces[1]) in old_ids:old_ids.append(int(pieces[1]))
		old_ids.sort()
		for node in body.find_children("door_*","",true,false):
			var pieces:=str(node.name).split("_")
			if pieces.size()>2 and pieces[1].is_valid_int():
				pieces[1]=str(door_offset+old_ids.find(int(pieces[1])));node.name="_".join(pieces)
		if row.role=="end_b":
			# End B is one canonical rear model, independent of train length.
			pass
		body.name="module_%02d"%int(row.index);body.position.z=float(row.center_z)+body_offset.z
		body.set_meta("tram_part_file",file);body.set_meta("tram_part_role",row.role);body.set_meta("tram_part_index",row.index)
		door_offset+=int(part.get("door_count",0))
	return holder

class NativeView:
	extends RefCounted
	var bindings:Array=[]
	func bind(visual:Node3D,control:Node3D)->void:
		bindings.append({"visual":visual,"control":control,"offset":visual.transform*control.transform.affine_inverse()})
	func sync()->void:
		for binding in bindings:binding.visual.transform=binding.offset*binding.control.transform

static func apply_native_kit(rig, livery: Dictionary) -> bool:
	var cfg:=configuration(livery.get("stock_entry",{}))
	if cfg.is_empty() or cfg.definition.renderer!="native" or cfg.rows.size()!=rig.modules.size():return false
	var templates:Array=[];var factories:Array=[]
	for row in cfg.rows:
		var part:Dictionary=cfg.definition.parts[row.part]
		var file:String=part.models.get("native","")
		var atlas:String=manifest().liveries.get(cfg.livery,{}).get("parts",{}).get(row.part,{}).get("native","")
		if not allowed(file) or not atlas.begins_with("res://tram_livery/livery/") or not ResourceLoader.exists(atlas):return false
		var source:=StockHD.scene(file)
		if source==null:return false
		templates.append(source);factories.append(load(atlas))
	# Validate all resources before hiding the complete procedural fallback.
	var view:=NativeView.new()
	for i in cfg.rows.size():
		var row:Dictionary=cfg.rows[i];var part:Dictionary=cfg.definition.parts[row.part]
		var target:MeshInstance3D=rig.modules[i]
		var body:=templates[i].duplicate() as Node3D;body.transform=Transform3D.IDENTITY
		if not row.pantograph:_strip_panto(body,part)
		if absf(float(row.length_m)-float(part.length_m))>.0001:
			_fit_node(body,Transform3D.IDENTITY,Transform3D.IDENTITY,_knots(part,float(row.length_m),float(cfg.definition.frame.front.get("length_m",1.2))))
		var controls:Array=[]
		for leaf in rig.leaves:
			if target.is_ancestor_of(leaf.node):controls.append(leaf.node)
		var leaves:Array=part.bindings.get("leaves",[])
		for j in mini(controls.size(),leaves.size()):
			var visual:=body.get_node_or_null(str(leaves[j])) as Node3D
			if visual!=null:view.bind(visual,controls[j])
		if row.pantograph:
			for name_ in part.bindings.get("panto",{}):
				var visual:=body.get_node_or_null(str(part.bindings.panto[name_])) as Node3D
				if visual!=null and rig.panto.has(name_):view.bind(visual,rig.panto[name_])
		var original:=target.material_override as ShaderMaterial
		for node in [body]+body.find_children("*","MeshInstance3D",true,false):
			if not node is MeshInstance3D or not node.material_override is ShaderMaterial or original==null:continue
			var baked:=node.material_override as ShaderMaterial
			var material:=original.duplicate() as ShaderMaterial
			material.set_shader_parameter("part_livery_enabled",true)
			material.set_shader_parameter("part_livery",baked.get_shader_parameter("part_livery"))
			material.set_shader_parameter("part_factory_enabled",true)
			material.set_shader_parameter("part_factory",factories[i])
			material.set_shader_parameter("part_size",Vector3(float(livery.width),3.4,float(row.length_m)))
			material.set_shader_parameter("part_end",-1 if i==0 else (1 if i==cfg.rows.size()-1 else 0))
			var design:=LiveryLibrary.for_part(livery.get("custom_livery",{}),livery.stock_entry,i)
			if not design.is_empty():
				if _blank==null:
					var image:=Image.create(1024,512,false,Image.FORMAT_RGBA8);image.fill(Color.WHITE);_blank=ImageTexture.create_from_image(image)
				design=design.duplicate(true);design["_paint_only"]=true
				material.set_shader_parameter("part_custom_enabled",true)
				material.set_shader_parameter("part_custom",LiveryPainter.texture(_blank,design,livery.stock_entry,i))
				var window:=Color(str(design.colors.window))
				material.set_shader_parameter("part_window_color",Vector3(window.r,window.g,window.b))
			node.material_override=material
		for child in target.get_children():
			if child is Node3D:child.hide()
		target.mesh=null;target.add_child(body)
		target.set_meta("tram_part_file",part.models.native);target.set_meta("tram_part_role",row.role)
		body.set_meta("tram_part_index",i)
	rig.parts_view=view;view.sync();return true
