extends SceneTree
func _init()->void:run.call_deferred()
func run()->void:
 var destination:=OS.get_environment("MAP_SHOTS")
 if destination=="":destination="res://.cache/map-shots"
 DirAccess.make_dir_recursive_absolute(destination)
 var net:=NetworkLoader.new();net.load_file("res://data/free/nantes.json")
 var world:=Node3D.new();root.add_child(world)
 var day:=DayNight.new();world.add_child(day);day.setup(world);day.set_hour(13)
 var city:=CityScene.new();city.radius=450;city.open("nantes",net.meta.origin);world.add_child(city);city.bind_network(net)
 var camera:=Camera3D.new();camera.fov=62;camera.far=3000;world.add_child(camera);camera.current=true
 for name_ in ["Commerce","Beaujoire","Haluchère - Batignolles"]:
  var found:Dictionary={}
  for s in net.stations:
   if str(s.name).to_lower().replace("-"," ").contains(name_.to_lower().replace("-"," ")):found=s;break
  if found.is_empty():continue
  var q:=net.point_on(found.edge,found.offset);var focus:=Vector3(q.p.x,q.y,q.p.y)
  city.warm(focus)
  camera.position=focus+Vector3(200,160,320);camera.look_at(focus+Vector3(0,10,0))
  for i in 5:await process_frame
  await RenderingServer.frame_post_draw
  root.get_texture().get_image().save_png(destination.path_join(name_.validate_filename()+".png"))
  print("CAPTURE|",name_,"|",focus)
 world.queue_free();await process_frame;quit()
