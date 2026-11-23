extends SceneTree
## Export every non-HD body independently, preserving the existing authored mesh
## and animated children. A lossless body palette replaces only RGB storage.
var failures:=0
func _initialize()->void:run.call_deferred()
func run()->void:
	TramParts.enabled=false
	var manifest:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(TramParts.INDEX))
	manifest.native={}
	for entry in StockCatalog.entries():
		if manifest.variants.has(str(entry.id)):continue
		var livery:=TramModel.livery_for(StockCatalog.origin_meta(entry),entry)
		var rig:=TramModel.build_rig(livery);var rows:Array=[]
		for i in rig.modules.size():
			var body:MeshInstance3D=rig.modules[i];var role:=TramParts.role(entry,i)
			var category:="extremites" if role.begins_with("end_") else ("motrices" if role=="powered" else "suspendues")
			var directory:="res://tram_parts/%s/%s" % [category,entry.id]
			var textures:="res://tram_livery/livery/%s/%s" % [entry.network,entry.id]
			DirAccess.make_dir_recursive_absolute(directory);DirAccess.make_dir_recursive_absolute(textures)
			var texture_path:=textures+"/caisse_%02d_palette.png"%i
			bake(body,texture_path)
			for child in body.find_children("*","",true,false):child.owner=body
			var packed:=PackedScene.new();var error:=packed.pack(body)
			var path:=directory+"/caisse_%02d.scn"%i
			if error==OK:error=ResourceSaver.save(packed,path,ResourceSaver.FLAG_COMPRESS)
			if error!=OK:failures+=1;printerr("ECHEC: export ",path," ",error)
			rows.append({"file":path,"texture":texture_path,"role":role,"index":i,"length_m":rig.module_lengths[i],"front_design":entry.cab_profile if role.begins_with("end_") else ""})
		manifest.native[str(entry.id)]=rows
		for body in rig.modules:body.free()
		print("PARTS|",entry.id,"|",rows.size())
	var file:=FileAccess.open(TramParts.INDEX,FileAccess.WRITE);file.store_string(JSON.stringify(manifest,"  ")+"\n");file.close()
	StockHD.reset_cache();print("TOTAL_ECHECS|",failures);quit(1 if failures else 0)

func bake(body:Node3D,path:String)->void:
	var meshes:Array=[];var colors:Dictionary={}
	for node in [body]+body.find_children("*","MeshInstance3D",true,false):
		if not node is MeshInstance3D or (node as MeshInstance3D).mesh==null or not (node as MeshInstance3D).material_override is ShaderMaterial:continue
		meshes.append(node)
		for surface in node.mesh.get_surface_count():
			var arrays:Array=node.mesh.surface_get_arrays(surface)
			for color in arrays[Mesh.ARRAY_COLOR]:
				var key:=(color as Color).to_html(false)
				if not colors.has(key):colors[key]=colors.size()
	if colors.is_empty():colors["ffffff"]=0
	var width:=1
	while width<colors.size():width*=2
	if width>4096:failures+=1;printerr("ECHEC: palette trop grande ",path);return
	var image:=Image.create(width,1,false,Image.FORMAT_RGBA8);image.fill(Color.WHITE)
	for key in colors:image.set_pixel(int(colors[key]),0,Color("#"+str(key)))
	image.save_png(path)
	# The texture is external in the saved scene. Editor import follows production.
	var texture:=ImageTexture.create_from_image(image);texture.take_over_path(path)
	for node in meshes:
		var mesh:=ArrayMesh.new()
		for surface in node.mesh.get_surface_count():
			var arrays:Array=node.mesh.surface_get_arrays(surface)
			var rgb:PackedColorArray=arrays[Mesh.ARRAY_COLOR]
			var uv:PackedVector2Array=arrays[Mesh.ARRAY_TEX_UV2] if arrays[Mesh.ARRAY_TEX_UV2]!=null else PackedVector2Array()
			if uv.is_empty():uv.resize((arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size())
			for j in rgb.size():uv[j].y=(float(colors[rgb[j].to_html(false)])+.5)/width
			arrays[Mesh.ARRAY_TEX_UV2]=uv
			mesh.add_surface_from_arrays(node.mesh.surface_get_primitive_type(surface),arrays)
		var material:=node.material_override.duplicate() as ShaderMaterial
		material.set_shader_parameter("part_livery_enabled",true);material.set_shader_parameter("part_livery",texture)
		node.mesh=mesh;node.material_override=material
