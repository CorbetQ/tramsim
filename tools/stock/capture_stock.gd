extends SceneTree
## Banc de comparaison commun avant/après ; deux angles fixes, aucune retouche de capture.
func _init()->void:_run.call_deferred()
func _run()->void:
 var args:=OS.get_cmdline_user_args();var manifest:=args[0];var phase:=args[1];var output:=args[2]
 var data:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(manifest))
 root.size=Vector2i(1280,720);root.msaa_3d=Viewport.MSAA_2X
 var world:=Node3D.new();root.add_child(world)
 var environment:=Environment.new();environment.background_mode=Environment.BG_SKY
 var sky:=Sky.new();var sky_mat:=ProceduralSkyMaterial.new();sky_mat.sky_top_color=Color("#738faa");sky_mat.sky_horizon_color=Color("#ccd9df");sky_mat.ground_horizon_color=Color("#a1afb3");sky_mat.ground_bottom_color=Color("#657178");sky.sky_material=sky_mat;environment.sky=sky
 environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.ambient_light_color=Color("#c8d7e0");environment.ambient_light_energy=.4
 environment.reflected_light_source=Environment.REFLECTION_SOURCE_SKY
 var env:=WorldEnvironment.new();env.environment=environment;world.add_child(env)
 var sun:=DirectionalLight3D.new();sun.light_energy=.95;sun.rotation_degrees=Vector3(-48,-35,0);sun.shadow_enabled=true;sun.shadow_normal_bias=1.0;world.add_child(sun)
 var fill:=DirectionalLight3D.new();fill.light_energy=.16;fill.rotation_degrees=Vector3(-18,145,0);world.add_child(fill)
 var ground:=MeshInstance3D.new();var plane:=PlaneMesh.new();plane.size=Vector2(200,200);ground.mesh=plane
 var floor_mat:=StandardMaterial3D.new();floor_mat.albedo_color=Color("#879298");floor_mat.roughness=1;ground.material_override=floor_mat;world.add_child(ground)
 var holder:=Node3D.new();world.add_child(holder)
 var camera:=Camera3D.new();camera.near=.1;camera.far=220;camera.fov=34;world.add_child(camera);camera.current=true
 RenderingServer.global_shader_parameter_set("night",0.0)
 DirAccess.make_dir_recursive_absolute(output)
 var previous:Dictionary={}
 var previous_path:=output.get_base_dir()+"/before/captures.json"
 if phase=="after" and FileAccess.file_exists(previous_path):
  for shot in JSON.parse_string(FileAccess.get_file_as_string(previous_path)):previous[str(shot.id)+"-"+str(shot.angle)]=shot
 var results:Array=[]
 if args.size()>3 and FileAccess.file_exists(output+"/captures.json"):
  for old in JSON.parse_string(FileAccess.get_file_as_string(output+"/captures.json")):
   if not str(old.id) in args.slice(3):results.append(old)
 for row in data.entries:
  if bool(row.get("fictional",false)) and phase=="before":continue
  if args.size()>3 and not str(row.id) in args.slice(3):continue
  var meta:Dictionary=row.get("capture_meta",{"source_id":row.network,"id":str(row.network)+"_"+str(row.line),"city":row.city,"color":"#337d88","line":"ESSAIS"})
  var entry:Dictionary={"family":row.family} if phase=="before" else row
  var liv:=TramModel.livery_for(meta,entry);liv.variant=0
  var rig:=TramModel.build_rig(liv);rig.layout_straight();rig.set_pantograph(true);rig.snap()
  for module in rig.modules:holder.add_child(module)
  var reference_length:=maxf(float(row.length),rig.length)
  for angle in ["threequarter","front"]:
   var target:=Vector3(0,1.5,-reference_length*.04)
   if angle=="front":
    camera.position=Vector3(0,1.85,-reference_length*.5-8.0);target=Vector3(0,1.7,-reference_length*.5+.5);camera.fov=33
   else:camera.position=Vector3(reference_length*.75+3,reference_length*.20+3,-reference_length*.72-3);camera.fov=34
   var key:=str(row.id)+"-"+str(angle)
   if previous.has(key):
    var shot:Dictionary=previous[key];camera.position=Vector3(shot.camera[0],shot.camera[1],shot.camera[2]);target=Vector3(shot.target[0],shot.target[1],shot.target[2])
   camera.look_at(target)
   for i in 3:await process_frame
   await RenderingServer.frame_post_draw
   var filename:String=str(row.id)+"-"+angle+".png";root.get_texture().get_image().save_png(output+"/"+filename)
   results.append({"id":row.id,"angle":angle,"phase":phase,"image":phase+"/"+filename,"camera":[camera.position.x,camera.position.y,camera.position.z],"target":[target.x,target.y,target.z],"length":rig.length,"modules":rig.modules.size(),"triangles":rig.triangles})
  for module in rig.modules:module.free()
  print("CAPTURE|",phase,"|",row.id,"|",rig.triangles," triangles")
 var file:=FileAccess.open(output+"/captures.json",FileAccess.WRITE);file.store_string(JSON.stringify(results,"  "));file.close();quit()
