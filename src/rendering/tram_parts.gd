class_name TramParts
extends RefCounted
## Compositions reference independent, animated bodies. Never combine two visible shells.
const INDEX := "res://data/rolling_stock/parts_manifest.json"
static var enabled := true
static var _data: Dictionary = {}
static func manifest() -> Dictionary:
	if _data.is_empty() and FileAccess.file_exists(INDEX):
		var value=JSON.parse_string(FileAccess.get_file_as_string(INDEX))
		if value is Dictionary:_data=value
	return _data
static func lod_file(variant: String, lod: String, mobile: bool) -> String:
	if not enabled:return ""
	var entry:Dictionary=manifest().get("variants",{}).get(variant,{})
	var key:={"LOD0":"lod1" if mobile else "lod0","LOD1":"lod1_m" if mobile else "lod1","LOD2":"lod2","LOD3":"lod3"}.get(lod,"")
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
