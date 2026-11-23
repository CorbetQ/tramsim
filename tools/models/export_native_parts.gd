extends SceneTree
## Export one geometry prototype per design/role; type and length stay parameters.
var failures:=0
func _initialize()->void:run.call_deferred()
func save_json(path:String,value)->void:
 var indent:="" if path.begins_with("res://.cache/") else "  "
 var file:=FileAccess.open(path,FileAccess.WRITE);file.store_string(JSON.stringify(value,indent)+"\n");file.close()
func run()->void:
 TramParts.enabled=false;StockHD.enabled=false
 var manifest:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(TramParts.INDEX))
 DirAccess.make_dir_recursive_absolute("res://.cache/kit-factory")
 for kid in manifest.kits:
  var path:String=manifest.kits[kid]
  var kit:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(path))
  if kit.renderer!="native":continue
  var entry:=StockCatalog.find(kit.master)
  var livery:=TramModel.livery_for(StockCatalog.origin_meta(entry),entry)
  var rig:=TramModel.build_rig(livery)
  var plan:=StockGeometry.apply(TramModel.plan(str(entry.family)),entry)
  kit.frame=plan.duplicate(true);kit.frame.erase("modules")
  kit.master_lengths=[];kit.layout=[];kit.parts={}
  var prototypes:Dictionary={}
  for i in rig.modules.size():
   var role:="end_a" if i==0 else ("end_b" if i==rig.modules.size()-1 else ("powered" if plan.modules[i].get("bogie",false) else "suspended"))
   var key:=role
   if prototypes.has(key) and plan.modules[prototypes[key]].get("doors",[]).size()!=plan.modules[i].get("doors",[]).size():key+="_doors" if not plan.modules[i].get("doors",[]).is_empty() else "_nodoor"
   prototypes.get_or_add(key,i)
   # Prefer the equipped instance of a repeated role; the renderer removes its
   # moving equipment from the other occurrences instead of exporting a type copy.
   if rig.panto.has("lower") and rig.modules[i].is_ancestor_of(rig.panto.lower):prototypes[key]=i
   kit.layout.append(key);kit.master_lengths.append(rig.module_lengths[i])
  for key in prototypes:
   var i:int=prototypes[key];var body:MeshInstance3D=rig.modules[i]
   var role:String=key.get_slice("_doors",0).get_slice("_nodoor",0)
   var category:="extremites" if role.begins_with("end_") else ("motrices" if role=="powered" else "suspendues")
   var directory:="res://tram_parts/%s/%s"%[category,kid]
   var textures:="res://tram_livery/materials/%s"%kid
   DirAccess.make_dir_recursive_absolute(directory);DirAccess.make_dir_recursive_absolute(textures)
   var bindings:={"leaves":[],"panto":{}}
   for leaf in rig.leaves:
    if body.is_ancestor_of(leaf.node):bindings.leaves.append(str(body.get_path_to(leaf.node)))
   for part in ["lower","upper","head"]:
    if rig.panto.has(part) and body.is_ancestor_of(rig.panto[part]):bindings.panto[part]=str(body.get_path_to(rig.panto[part]))
   var module:Dictionary=plan.modules[i].duplicate(true)
   var ratio:=float(rig.module_lengths[i])/float(module.length_m)
   module.length_m=rig.module_lengths[i]
   for door in module.get("doors",[]):door.z_m=float(door.z_m)*ratio
   for window in module.get("windows",[]):window.z0_m=float(window.z0_m)*ratio;window.z1_m=float(window.z1_m)*ratio
   for roof in module.get("roof",[]):roof.z_m=float(roof.z_m)*ratio
   if module.has("bogie_z_m"):module.bogie_z_m=float(module.bogie_z_m)*ratio
   var texture_path:String=textures+"/"+str(key)+"_palette.png"
   bake(body,texture_path)
   for child in body.find_children("*","",true,false):child.owner=body
   var packed:=PackedScene.new();var error:=packed.pack(body)
   var model:String=directory+"/"+str(key)+".scn"
   if error==OK:error=ResourceSaver.save(packed,model,ResourceSaver.FLAG_COMPRESS)
   if error!=OK:failures+=1;printerr("ECHEC: export ",model)
   kit.parts[key]={"role":role,"root":str(body.name),"source_index":i,"plan":module,"length_m":rig.module_lengths[i],"door_count":module.get("doors",[]).size(),"models":{"native":model},"palette":texture_path,"bindings":bindings,"pantograph":not bindings.panto.is_empty()}
  for body in rig.modules:body.free()
  # Bake a normalized body paint atlas per original livery, never per train size.
  var styles:Dictionary={}
  for target in StockCatalog.entries():
   if manifest.variants[target.id].kit!=kid:continue
   var paint:=TramModel.livery_for(StockCatalog.origin_meta(target),target)
   var signature:Dictionary={}
   for field in TramModel.COLOR_KEYS+["elements","pattern"]:signature[field]=paint.get(field)
   var digest:=JSON.stringify(signature).sha256_text().substr(0,12)
   var style:=str(kid)+"_"+str(target.network)+"_"+digest
   manifest.variants[target.id].livery=style
   if styles.has(style):continue
   styles[style]=true
   paint.stock_entry=entry;paint.family=entry.family;paint.length=entry.length;paint.width=entry.width
   var painted:=TramModel.build_rig(paint)
   manifest.liveries[style]={"kit":kid,"parts":{}}
   for key in prototypes:
    var i:int=prototypes[key];var body:MeshInstance3D=painted.modules[i]
    var triangles:Array=[]
    for node in [body]+body.find_children("*","MeshInstance3D",true,false):
     if not node is MeshInstance3D or node.mesh==null or not node.material_override is ShaderMaterial:continue
     var transform:=Transform3D.IDENTITY if node==body else relative_to(body,node)
     for surface in node.mesh.get_surface_count():
      var arrays:Array=node.mesh.surface_get_arrays(surface)
      var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX];var colors:PackedColorArray=arrays[Mesh.ARRAY_COLOR];var uv:PackedVector2Array=arrays[Mesh.ARRAY_TEX_UV2]
      var normals:PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
      var indices:PackedInt32Array=arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX]!=null else PackedInt32Array()
      if indices.is_empty():
       for j in vertices.size():indices.append(j)
      for j in range(0,indices.size(),3):
       var at:=indices[j]
       if colors[at].a<.9 or uv[at].x<.25:continue
       var a:=transform*vertices[at];var b:=transform*vertices[indices[j+1]];var c:=transform*vertices[indices[j+2]]
       # Godot uses clockwise triangle winding. The authored normal, rather
       # than a counterclockwise cross product, identifies the painted face.
       var normal:=(transform.basis.inverse().transposed()*normals[at]).normalized()
       triangles.append([[a.x,a.y,a.z],[b.x,b.y,b.z],[c.x,c.y,c.z],colors[at].to_html(false),[normal.x,normal.y,normal.z]])
    var texture_path:="res://tram_livery/livery/%s/%s.png"%[style,key]
    manifest.liveries[style].parts[key]={"native":texture_path}
    save_json("res://.cache/kit-factory/%s__%s.json"%[style,key],{"length":painted.module_lengths[i],"width":paint.width,"role":kit.parts[key].role,"base":paint.base.to_html(false),"roof":paint.roof.to_html(false),"skirt":paint.skirt.to_html(false),"front":paint.front.to_html(false),"triangles":triangles,"output":texture_path})
   for body in painted.modules:body.free()
  save_json(path,kit)
  print("KIT|",kid,"|",kit.parts.size(),"|",styles.size())
 save_json(TramParts.INDEX,manifest)
 StockHD.reset_cache();print("TOTAL_ECHECS|",failures);quit(1 if failures else 0)
func relative_to(body:Node3D,node:Node3D)->Transform3D:
 var value:=node.transform;var parent:=node.get_parent()
 while parent!=body:value=(parent as Node3D).transform*value;parent=parent.get_parent()
 return value

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
