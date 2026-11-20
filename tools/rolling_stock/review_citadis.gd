extends SceneTree
## Actual Godot renders; no image generation or compositing. DISPLAY needed.
## godot --path . --script tools/rolling_stock/review_citadis.gd
var world: Node3D
var camera: Camera3D
var label: Label
var directory := "res://docs/rolling-stock-meshy/captures/"

func _initialize() -> void:run.call_deferred()

func capture(name_: String) -> void:
	for i in 5:await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory+name_+".png")

func run() -> void:
	if DisplayServer.get_name()=="headless":printerr("A rendering display is required");quit(2);return
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
		var entry := StockCatalog.find(variant)
		var key := CitadisMeshy.key_for(variant)
		var profile := VehicleProfile.new();profile.variant_id=variant;profile.width_m=float(entry.width)
		profile.fleet=entry;profile.origin_city=str(entry.network)
		var livery := TramModel.livery_for({"source_id":str(entry.network),"id":str(entry.network)+"_1"},entry)
		for after in [false,true]:
			CitadisMeshy.preview_exteriors=after;CitadisMeshy.reference_interiors_enabled=after
			var rig := TramModel.build_rig(livery,-1,true)
			rig.layout_straight()
			for module in rig.modules:world.add_child(module)
			var state := "meshy-experimental" if after else "before"
			label.text=entry.name+" · "+state+" · exterior / closed doors"
			camera.position=Vector3(10,5,-rig.length*.5-9)
			camera.look_at(Vector3(0,1.4,-rig.length*.5+5))
			await capture(key+"-"+state+"-front")
			camera.position=Vector3(28,9,2);camera.look_at(Vector3(0,1.6,0))
			label.text=entry.name+" · "+state+" · full articulated train"
			await capture(key+"-"+state+"-side")
			var closed: Vector3=rig.leaves[0].node.position
			rig.set_doors(true,"both");rig.set_pantograph(false)
			for i in 100:rig.update(.1)
			label.text=entry.name+" · "+state+" · doors open / pantograph down"
			await capture(key+"-"+state+"-open")
			assert(rig.leaves[0].node.position.distance_to(closed)>.3)
			TramInterior.attach(rig,profile);TramInterior.show(rig,true)
			camera.cull_mask=1|2
			camera.position=Vector3(0,1.98,-rig.length*.5+3.4)
			camera.look_at(camera.position+Vector3(0,0,8))
			label.text=entry.name+" · "+state+" · passenger interior (estimated layout)"
			await capture(key+"-"+state+"-interior")
			for module in rig.modules:module.queue_free()
			await process_frame
		CitadisMeshy.preview_exteriors=false;CitadisMeshy.reference_interiors_enabled=true
	quit()
