extends SceneTree
## Actual Godot renders; no image generation or compositing. DISPLAY needed.
## godot --path . --script tools/rolling_stock/review_citadis.gd
var world: Node3D
var camera: Camera3D
var label: Label
var directory := "res://docs/rolling-stock-meshy/captures/"
var render_failures := 0

func _initialize() -> void:run.call_deferred()

func capture(name_: String) -> void:
	for i in 5:await process_frame
	await RenderingServer.frame_post_draw
	var frame := root.get_texture().get_image()
	frame.save_png(directory+name_+".png")
	# Existing PR image URLs must show the corrected model, not the rejected V1.
	if name_.contains("facade-v3"):
		frame.save_png(directory+name_.replace("facade-v3","meshy-experimental")+".png")
		frame.save_png(directory+name_.replace("facade-v3","stylised-v2")+".png")
	if name_.contains("facade-v3") and name_.ends_with("-face"):
		# Regression check for the black untextured-material bug; not a realism score.
		var luminance := 0.0
		var x0 := 804 if name_.begins_with("nantes405") else 620
		var y0 := 518 if name_.begins_with("nantes405") else 535
		var width_ := 16 if name_.begins_with("nantes405") else 40
		for x in range(x0,x0+width_,2):
			for y in range(y0,y0+10,2):luminance+=frame.get_pixel(x,y).get_luminance()/(width_*2.5)

		print("RENDER_BODY|",name_,"|",luminance)
		if luminance<.25:render_failures+=1;printerr("FAIL: body material rendered black: ",name_)

func run() -> void:
	if DisplayServer.get_name()=="headless":printerr("A rendering display is required");quit(2);return
	if OS.get_environment("TRAMSIM_REVIEW_CAPTURE_ROOT")!="":directory=OS.get_environment("TRAMSIM_REVIEW_CAPTURE_ROOT")
	DirAccess.make_dir_recursive_absolute(directory)
	root.size=Vector2i(1280,720)
	world=Node3D.new();root.add_child(world)
	var environment := WorldEnvironment.new();var env := Environment.new()
	env.background_mode=Environment.BG_COLOR;env.background_color=Color("#98afbf")
	env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.ambient_light_color=Color("#d6e5ed");env.ambient_light_energy=.55
	environment.environment=env;world.add_child(environment)
	var sun := DirectionalLight3D.new();sun.rotation_degrees=Vector3(-40,-35,0);sun.light_energy=.8
	sun.shadow_enabled=true;world.add_child(sun)
	var ground := MeshInstance3D.new();var mesh := BoxMesh.new();mesh.size=Vector3(100,.1,100)
	ground.mesh=mesh;ground.position.y=-.12
	ground.material_override=TramInterior.material("review_floor",Color("#616f70"));world.add_child(ground)
	camera=Camera3D.new();camera.fov=55;camera.far=160;world.add_child(camera);camera.current=true
	var overlay := CanvasLayer.new();root.add_child(overlay)
	label=Label.new();label.position=Vector2(24,20);label.add_theme_font_size_override("font_size",24)
	label.add_theme_color_override("font_shadow_color",Color.BLACK);label.add_theme_constant_override("shadow_offset_x",2)
	label.add_theme_constant_override("shadow_offset_y",2);overlay.add_child(label)
	for variant in CitadisMeshy.VARIANTS:
		if OS.get_environment("TRAMSIM_REVIEW_VARIANT")!="" and variant!=OS.get_environment("TRAMSIM_REVIEW_VARIANT"):continue
		var entry := StockCatalog.find(variant)
		var key := CitadisMeshy.key_for(variant)
		var profile := VehicleProfile.new();profile.variant_id=variant;profile.width_m=float(entry.width)
		profile.fleet=entry;profile.origin_city=str(entry.network)
		var livery := TramModel.livery_for({"source_id":str(entry.network),"id":str(entry.network)+"_1"},entry)
		for after in ([true] if OS.get_environment("TRAMSIM_REVIEW_ONLY_V2")=="1" else [false,true]):
			CitadisMeshy.exteriors_enabled=after;CitadisMeshy.reference_interiors_enabled=after
			var rig := TramModel.build_rig(livery,-1,true)
			rig.layout_straight()
			for module in rig.modules:world.add_child(module)
			var state := "facade-v3" if after else "before"
			label.text=entry.name+" · "+state+" · exterior / closed doors"
			camera.position=Vector3(6,3.6,-rig.length*.5-6)
			camera.look_at(Vector3(0,1.5,-rig.length*.5+2.3))
			await capture(key+"-"+state+"-front")
			camera.position=Vector3(0,1.65,-rig.length*.5-7)
			camera.fov=35;camera.look_at(Vector3(0,1.65,-rig.length*.5+1))
			label.text=entry.name+" · "+state+" · front detail"
			await capture(key+"-"+state+"-face")
			if after:
				root.size=Vector2i(720,900)
				label.text=entry.name+"\nFaçade · références photographiques"
				await capture(key+"-"+state+"-portrait")
				root.size=Vector2i(1280,720)
				if key=="nantes405":
					camera.position=Vector3(0,1.65,rig.length*.5+7)
					camera.look_at(Vector3(0,1.65,rig.length*.5-1))
					label.text=entry.name+" · façade arrière / optiques rouges"
					await capture(key+"-"+state+"-rear")
			camera.fov=55
			camera.position=Vector3(28,9,2);camera.look_at(Vector3(0,1.6,0))
			label.text=entry.name+" · "+state+" · full articulated train"
			await capture(key+"-"+state+"-side")
			var closed: Vector3=rig.leaves[0].node.position
			rig.set_doors(true,"both");rig.set_pantograph(false)
			for i in 100:rig.update(.1)
			label.text=entry.name+" · "+state+" · doors open / pantograph down"
			await capture(key+"-"+state+"-open")
			assert(rig.leaves[0].node.position.distance_to(closed)>.3)
			if after and OS.get_environment("TRAMSIM_REVIEW_ANIMATION")=="1":
				var animation_path := "res://.cache/citadis-v2/animation/"+key+"/"
				DirAccess.make_dir_recursive_absolute(animation_path)
				rig.set_doors(false);rig.set_pantograph(true);rig.snap()
				for frame_index in 64:
					if frame_index==0:rig.set_doors(true,"both");rig.set_pantograph(false)
					if frame_index==32:rig.set_doors(false);rig.set_pantograph(true)
					rig.update(.125)
					var curvature := sin(frame_index/63.0*PI)/90.0
					for i in rig.modules.size():
						var d: float=rig.module_starts[i]+rig.module_lengths[i]*.5-rig.length*.5
						var angle := d*curvature
						rig.modules[i].position=Vector3((1.0-cos(angle))/curvature if curvature>.00001 else 0.0,0,sin(angle)/curvature if curvature>.00001 else d)
						rig.modules[i].rotation.y=angle
					label.text=entry.name+" · portes / pantographe / articulation · "+("ouverture" if frame_index<32 else "fermeture")
					await process_frame;await RenderingServer.frame_post_draw
					root.get_texture().get_image().save_png(animation_path+"%03d.png"%frame_index)
				rig.layout_straight()
				for module in rig.modules:module.rotation=Vector3.ZERO
				rig.set_doors(true,"both");rig.set_pantograph(false);rig.snap()
			TramInterior.attach(rig,profile);TramInterior.show(rig,true)
			camera.cull_mask=1|2
			camera.position=Vector3(0,1.98,-rig.length*.5+3.4)
			camera.look_at(camera.position+Vector3(0,0,8))
			label.text=entry.name+" · "+state+" · passenger interior (estimated layout)"
			await capture(key+"-"+state+"-interior")
			for module in rig.modules:module.queue_free()
			await process_frame
		CitadisMeshy.exteriors_enabled=false;CitadisMeshy.reference_interiors_enabled=true
	quit(1 if render_failures else 0)
