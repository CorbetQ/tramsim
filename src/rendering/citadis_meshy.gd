class_name CitadisMeshy
extends RefCounted
## Meshy geometry is adapted offline, never generated/downloaded during play.
## Exact variants only: a fictitious 405 Irigo must not inherit a 305 shell.
const ROOT := "res://data/rolling_stock/meshy_citadis/"
const VARIANTS := {
	"angers__citadis_302":"angers302",
	"angers__citadis_x05":"angers305",
	"nantes__citadis_x05_nantes":"nantes405",
}
const LENGTHS := {"angers302":32.4,"angers305":33.0,"nantes405":45.6}
static var _parts := {}
static var _materials := {}
static var preview_exteriors := false
static var reference_interiors_enabled := true

static func key_for(variant: String) -> String:
	return str(VARIANTS.get(variant,""))

static func parts(key: String, component: String) -> Dictionary:
	var cache_key := key+"_"+component
	if _parts.has(cache_key):return _parts[cache_key]
	var path := ROOT+cache_key+".glb"
	if not ResourceLoader.exists(path):return {}
	var packed := load(path) as PackedScene
	if packed==null:return {}
	var root := packed.instantiate()
	var result := {}
	for node in root.find_children("*","MeshInstance3D",true,false):
		# The offline adapter applies all transforms before exporting.
		result[str(node.name)] = node.mesh
	root.free()
	_parts[cache_key]=result
	return result

static func textured_material(source: Material, palette: int=0) -> Material:
	if not source is BaseMaterial3D:return source
	var id := str(source.get_instance_id())+"/"+str(palette)
	if _materials.has(id):return _materials[id]
	var material := ShaderMaterial.new()
	material.shader=load("res://src/rendering/shaders/meshy_citadis.gdshader")
	material.set_shader_parameter("base_texture",source.albedo_texture)
	material.set_shader_parameter("base_color",source.albedo_color)
	material.set_shader_parameter("seat_palette",palette if source.albedo_texture!=null else 0)
	_materials[id]=material
	return material

static func styled_mesh(mesh: Mesh, palette: int=0) -> Mesh:
	var key := str(mesh.get_instance_id())+"/"+str(palette)
	if _parts.has(key):return _parts[key]
	var copy := mesh.duplicate() as Mesh
	for surface in copy.get_surface_count():
		copy.surface_set_material(surface,textured_material(mesh.surface_get_material(surface),palette))
	_parts[key]=copy
	return copy

static func seat(key: String) -> Mesh:
	var result := parts(key,"seat")
	if result.is_empty():return null
	return styled_mesh(result.values()[0],2 if key=="nantes405" else 1)

static func apply_exterior(rig, livery: Dictionary) -> bool:
	# Whole-train reconstruction currently has visual defects. It is available
	# in the animation review tool, not silently shipped as an approved replacement.
	if not preview_exteriors and OS.get_environment("TRAMSIM_MESHY_PREVIEW")!="1":return false
	var key := key_for(str(livery.get("variant_id","")))
	if key=="":return false
	if absf(rig.length-float(LENGTHS[key]))>.02 or absf(float(livery.get("width",2.4))-2.4)>.01:return false
	var imported := parts(key,"body")
	if imported.size()!=rig.modules.size():return false
	for i in rig.modules.size():
		if not imported.has("Module%02d"%i):return false
	for i in rig.modules.size():
		var module: MeshInstance3D=rig.modules[i]
		var scaffold := mechanical_scaffold(module.mesh,float(rig.module_lengths[i]))
		if scaffold!=null:
			var fittings := MeshInstance3D.new();fittings.name="MechanicalScaffold"
			fittings.mesh=scaffold;fittings.material_override=module.material_override;module.add_child(fittings)
		rig.triangles-=module.mesh.get_faces().size()/3
		module.mesh=styled_mesh(imported["Module%02d"%i])
		rig.triangles+=module.mesh.get_faces().size()/3
		if scaffold!=null:rig.triangles+=scaffold.get_faces().size()/3
		module.material_override=null
		module.set_meta("meshy_experimental",key)
		if module.has_node("Girouette"):module.get_node("Girouette").visible=false
	return true

static func mechanical_scaffold(mesh: Mesh, length: float) -> ArrayMesh:
	# Reuse only the verified roof equipment, underframe and gangway mechanics.
	# In particular the pantograph base cannot float above an inferred AI roof.
	var tool := SurfaceTool.new();tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var count := 0
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX]!=null else PackedInt32Array()
		if indices.is_empty():
			for i in vertices.size():indices.append(i)
		for i in range(0,indices.size(),3):
			var keep_roof := true;var keep_bottom := true;var keep_end := true
			for j in 3:
				var v := vertices[indices[i+j]]
				keep_roof=keep_roof and v.y>=2.75
				keep_bottom=keep_bottom and v.y<=.7 and absf(v.x)<=1.0
				keep_end=keep_end and absf(v.z)>=length*.5-.20 and absf(v.x)<=1.1
			if not keep_roof and not keep_bottom and not keep_end:continue
			for j in 3:
				var idx := indices[i+j]
				if arrays[Mesh.ARRAY_NORMAL]!=null:tool.set_normal(arrays[Mesh.ARRAY_NORMAL][idx])
				if arrays[Mesh.ARRAY_COLOR]!=null:tool.set_color(arrays[Mesh.ARRAY_COLOR][idx])
				if arrays[Mesh.ARRAY_TEX_UV]!=null:tool.set_uv(arrays[Mesh.ARRAY_TEX_UV][idx])
				if arrays[Mesh.ARRAY_TEX_UV2]!=null:tool.set_uv2(arrays[Mesh.ARRAY_TEX_UV2][idx])
				tool.add_vertex(vertices[idx]);count+=1
	return tool.commit() if count>0 else null
