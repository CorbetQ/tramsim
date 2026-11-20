class_name CitadisMeshy
extends RefCounted
## Locally reconstructed shells from reference study/Meshy contours; Meshy seats.
## No generation or download during play, and no retained legacy visible geometry.
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
static var exteriors_enabled := true
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
	material.set_shader_parameter("use_texture",source.albedo_texture!=null)
	material.set_shader_parameter("base_color",source.albedo_color)
	material.set_shader_parameter("vertex_palette",source.resource_name.begins_with("CitadisPalette"))
	material.set_shader_parameter("surface_roughness",source.roughness)
	material.set_shader_parameter("surface_metallic",source.metallic)
	if source.emission_enabled:material.set_shader_parameter("emission_color",source.emission*source.emission_energy_multiplier)
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
	# One coherent reconstructed mesh set. Animation transforms remain authoritative.
	if not exteriors_enabled or OS.get_environment("TRAMSIM_CITADIS_LEGACY")=="1":return false
	var key := key_for(str(livery.get("variant_id","")))
	if key=="":return false
	if absf(rig.length-float(LENGTHS[key]))>.02 or absf(float(livery.get("width",2.4))-2.4)>.01:return false
	var imported := parts(key,"body")
	# Validate the complete set before touching the rig. Never mix generations.
	var required: Array[String]=[]
	for i in rig.modules.size():required.append("Module%02d"%i)
	for i in rig.leaves.size():required.append("Door%03d"%i)
	for name_ in ["PantoLower","PantoUpper","PantoHead"]:required.append(name_)
	if imported.size()!=required.size():return false
	for name_ in required:
		if not imported.has(name_):return false
	for i in rig.modules.size():
		var module: MeshInstance3D=rig.modules[i]
		replace_mesh(rig,module,imported["Module%02d"%i])
		module.set_meta("meshy_experimental",key)
		if module.has_node("Girouette"):
			var label: Label3D=module.get_node("Girouette")
			var direction := -1.0 if i==0 else 1.0
			var inset := .615 if key=="angers302" else (.50 if key=="angers305" else .284)
			label.position=Vector3(0,2.62,direction*(float(rig.module_lengths[i])*.5-inset+.09))
			label.pixel_size=minf(.004,1.25/maxf(label.text.length()*36.0,1.0))
			label.visible=true
			if key=="nantes405":
				label.modulate=Color("#dcebd8")
				for side in [-1,1]:
					var brand := Label3D.new();brand.name="NaolibLeft" if side<0 else "NaolibRight"
					brand.text="naolib";brand.font_size=64;brand.pixel_size=.0025
					brand.outline_size=0;brand.modulate=Color("#173a38");brand.shaded=false;brand.double_sided=false
					brand.rotation.y=side*PI*.5
					brand.position=Vector3(side*1.215,.77,direction*(float(rig.module_lengths[i])*.5-.93))
					module.add_child(brand)
			else:
				var brand := Label3D.new();brand.name="Brand";brand.text="ALSTOM"
				brand.font_size=64;brand.pixel_size=.0011
				brand.outline_size=0;brand.modulate=Color("#dde7e4");brand.shaded=false;brand.double_sided=false
				brand.rotation.y=label.rotation.y
				brand.position=Vector3(0,1.065,direction*(float(rig.module_lengths[i])*.5-.015))
				module.add_child(brand)

	for i in rig.leaves.size():replace_mesh(rig,rig.leaves[i].node,imported["Door%03d"%i])
	for pair in [["lower","PantoLower"],["upper","PantoUpper"],["head","PantoHead"]]:
		replace_mesh(rig,rig.panto[pair[0]],imported[pair[1]])
	return true

static func replace_mesh(rig, node: MeshInstance3D, mesh: Mesh) -> void:
	rig.triangles-=node.mesh.get_faces().size()/3
	node.mesh=styled_mesh(mesh)
	rig.triangles+=node.mesh.get_faces().size()/3
	node.material_override=null
	if str(node.name).begins_with("Module"):
		if not _materials.has("body_outline"):
			var outline := ShaderMaterial.new();outline.shader=load("res://src/rendering/shaders/outline.gdshader")
			outline.set_shader_parameter("width",.018);outline.set_shader_parameter("axis_center",Vector3(0,1.55,0))
			_materials["body_outline"]=outline
		node.material_overlay=_materials["body_outline"]
	node.set_meta("citadis_asset_revision",2)
