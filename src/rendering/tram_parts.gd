class_name TramParts
extends RefCounted
## Compositions reference independent, animated bodies. Never combine two visible shells.
const INDEX := "res://data/rolling_stock/parts_manifest.json"
static var enabled := true
static var _data: Dictionary = {}
static var _blank: ImageTexture
static func manifest() -> Dictionary:
	if _data.is_empty() and FileAccess.file_exists(INDEX):
		var value=JSON.parse_string(FileAccess.get_file_as_string(INDEX))
		if value is Dictionary:_data=value
	return _data
static func lod_file(variant: String, lod: String, mobile: bool) -> String:
	if not enabled:return ""
	var entry:Dictionary=manifest().get("variants",{}).get(variant,{})
	var key:String={"LOD0":"lod1" if mobile else "lod0","LOD1":"lod1_m" if mobile else "lod1","LOD2":"lod2","LOD3":"lod3"}.get(lod,"")
	return str(entry.get("lods",{}).get(key,""))
static func allowed(path: String) -> bool:
	return path.begins_with("res://tram_parts/") and not "/../" in path and not "\\" in path
static func assemble(path: String) -> Node3D:
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
	var count:=int(entry.get("module_count",1))
	if index==0:return "end_a"
	if index==count-1:return "end_b"
	var plan:=StockGeometry.apply(TramModel.plan(str(entry.family)),entry)
	return "powered" if bool(plan.modules[index].get("bogie",false)) else "suspended"

static func apply_native(rig, livery: Dictionary) -> bool:
	if not enabled:return false
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
				material.set_shader_parameter("part_size",Vector3(float(livery.width),3.4,rig.module_lengths[i]))
				material.set_shader_parameter("part_end",-1 if i==0 else (1 if i==rows.size()-1 else 0))
			destination.material_override=material
		target.set_meta("tram_part_file",rows[i].file);target.set_meta("tram_part_role",rows[i].role)
	return true
