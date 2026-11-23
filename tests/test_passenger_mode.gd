extends SceneTree
var fails := 0
func check(ok: bool, message: String) -> void:
	if not ok:fails+=1;printerr("ECHEC: ",message)
	else:print("ok: ",message)
func _initialize() -> void:run.call_deferred()
func run() -> void:
	var mode := PassengerMode.new();root.add_child(mode);mode.set_process(false)
	check(mode.start("Angers","res://data/free/angers.json",12,200,true),"passenger starts on existing city network")
	mode.set_process(false)
	check(mode.ai!=null and not mode.ai.trams.is_empty(),"actual AI services available")
	mode.hour=23.99;mode.time_rate_hours_per_second=1;mode._process(.02)
	check(mode.hour<.02,"passenger day/night clock wraps midnight")
	mode.hour=12;mode.time_rate_hours_per_second=0
	if mode.ai==null or mode.ai.trams.is_empty():mode.queue_free();quit(1);return
	var t: AiTram=mode.ai.trams[0]
	mode.view.ai_view.forced_detail=t.train_id
	mode.view.ai_view.sync(mode.view,mode.ai,mode.view.pos3(t.edge_id,t.offset),.01)
	var rig: TramModel.Rig=mode.view.ai_view.rigs[t.train_id]
	var plan := TramModel.plan(rig.family)
	var module_index := -1;var door := {}
	for i in plan.modules.size():
		if not plan.modules[i].get("doors",[]).is_empty():module_index=i;door=plan.modules[i].doors[0];break
	check(module_index>=0,"boardable door found in actual family plan")
	var at := Vector3(t.phys.profile.width_m*.5,float(plan.get("floor_m",.32))+1.65,float(door.z_m)-rig.module_lengths[module_index]*.5)
	t.phys.velocity=0;t.doors_open=true;t.driver.state="dwell";t.driver.dwell_left=100
	rig.set_doors(true,"right");rig.snap()
	mode.walker.position=rig.modules[module_index].global_transform*(Vector3(-at.x,at.y,at.z)-Vector3(.5,0,0))
	mode.interact();check(mode.walker.train_id=="","closed opposite-side door cannot be used")
	mode.walker.position=rig.modules[module_index].global_transform*(at+Vector3(.5,0,0))
	mode.interact()
	rig=mode.view.ai_view.rigs[t.train_id]
	check(mode.walker.train_id==t.train_id,"boards actual stationary AI through open door")
	check(rig.modules[module_index].has_node("PassengerInterior"),"interior generated lazily on boarding")
	check(is_instance_valid(mode.onboard_audio),"boarded train uses existing family audio engine")
	var interior := rig.modules[module_index].get_node("PassengerInterior")
	if CitadisMeshy.key_for(t.phys.profile.variant_id)!="":
		check(str(interior.get_meta("reference_profile",""))==CitadisMeshy.key_for(t.phys.profile.variant_id),"actual boarded service uses exact Meshy interior profile")
	check(not interior.find_children("*","MultiMeshInstance3D",true,false).is_empty(),"interior objects batched instead of individual draw nodes")
	check(int(interior.get_meta("batched_draw_groups"))<int(interior.get_meta("unbatched_meshes")),"batching reduces interior draw groups")
	print("INTERIOR_BATCH|",interior.get_meta("unbatched_meshes"),"|",interior.get_meta("batched_draw_groups"))
	var seats: Array=interior.get_meta("seats",[])
	check(not seats.is_empty(),"usable passenger seats exist")
	if not seats.is_empty():
		mode.walker.position=rig.modules[module_index].global_transform*(seats[0]+Vector3(0,.5,0))
		mode.toggle_seat();check(mode.walker.seated,"passenger takes a nearby modeled seat")
		mode._process(.01);mode.toggle_seat();check(not mode.walker.seated,"passenger stands back into aisle")
	mode._process(.01)
	mode.walker.yaw=PI;mode.touch_move=Vector2.UP
	var distance_before := mode.walker.ride_distance
	mode._process(.1);mode.touch_move=Vector2.ZERO
	check(mode.walker.ride_distance>distance_before,"walking forward while looking rearwards moves toward rear")
	var ride_before := mode.walker.position
	t.doors_open=false;t.phys.velocity=3
	mode._process(.1)
	check(mode.walker.position.distance_to(ride_before)>.01,"passenger is carried by real moving articulated rig")
	mode.interact();check(mode.walker.train_id==t.train_id,"cannot alight from moving tram")
	t.phys.velocity=0;t.doors_open=true;t.driver.state="dwell";t.driver.dwell_left=100
	mode.walker.ride_distance=rig.module_starts[module_index]+float(door.z_m)
	mode.walker.lateral=0
	mode._process(.01);rig.set_doors(true,"both");rig.snap()
	mode.interact();check(mode.walker.train_id=="","can alight after actual session stops and doors open")
	check(mode.onboard_audio==null,"alighting releases onboard audio")
	var camera := mode.view.cam;camera.position=Vector3(0,2,0);camera.rotation=Vector3.ZERO
	check(AiTramView.potentially_visible(camera,Vector3(0,2,-20),2),"frustum keeps visible tram")
	check(not AiTramView.potentially_visible(camera,Vector3(0,2,20),2),"frustum rejects tram behind camera")
	check(AiTramView.potentially_visible(camera,Vector3(0,2,1),3),"frustum preserves train containing viewer")
	if DisplayServer.get_name()!="headless":
		# Capture actual occupied/foot states, rather than leaving the HUD stale after a camera pose.
		mode.interact();mode._process(.001)
		check(mode.walker.train_id==t.train_id,"rendered interior capture is actually aboard the service")
		var effects := VisualEffects.new();mode.view.add_child(effects);effects.setup(mode.view,"cinematic")
		mode.view.cam.position=rig.modules[module_index].global_transform*Vector3(0,float(plan.get("floor_m",.32))+1.65,0)
		mode.view.cam.global_basis=rig.modules[module_index].global_basis*Basis(Vector3.UP,PI)
		TramInterior.show(rig,true)
		for i in 8:await process_frame
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute("res://.cache/next")
		root.get_texture().get_image().save_png("res://.cache/next/passenger-interior.png")
		mode.walker.ride_distance=rig.module_starts[module_index]+float(door.z_m)
		mode._process(.001);rig.set_doors(true,"both");rig.snap();mode.interact();mode._process(.001)
		check(mode.walker.train_id=="","rendered exterior capture is actually on foot")
		var at_station := mode.view.pos3(t.edge_id,t.offset)
		mode.view.cam.position=at_station+Vector3(5,2.3,8)
		mode.view.cam.look_at(at_station+Vector3(0,1.2,-15))
		if mode.view.city:mode.view.city.radius=200;mode.view.city.warm(mode.view.cam.position)
		mode.weather.rain=.85;mode.weather.fog=.15;mode.weather.wetness=.7
		mode.view.day_night.set_hour(18.5);mode.weather_view.apply(mode.weather,mode.view)
		for i in 12:await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.cache/next/passenger-rain.png")
	for train in mode.ai.trams.duplicate():train.remove()
	mode.queue_free();await process_frame;await CityScene.drain_background_jobs(self)
	StockHD.reset_cache()
	print("TOTAL_ECHECS|",fails);quit(1 if fails else 0)
