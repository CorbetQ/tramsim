extends SceneTree
## Captures des vrais rigs HD, matériaux et écrans pilotés par le runtime (aucun rendu IA).
## godot --path . --rendering-method gl_compatibility -s tests/audit/stock_hd_shots.gd -- build/stock-hd [mobile]
var out := "build/stock-hd"
var cam: Camera3D
var stage: Node3D

func _initialize() -> void: run.call_deferred()

func shot(label: String) -> bool:
	for i in 5: await process_frame
	await RenderingServer.frame_post_draw
	var path := out.path_join(label + ".png")
	var image := root.get_texture().get_image()
	if image.save_png(path) != OK:
		push_error("Capture impossible : " + path); return false
	print("SHOT|", path)
	if DayNight.low_quality and label == "nantes__citadis_x05_nantes-exterieur":
		# Fixed camera / flat cab partition behind the windshield. This patch
		# exposed anisotropic zero-UV atlas speckles (4.08% dark outliers).
		var values := PackedFloat32Array()
		for y in range(320, 360):
			for x in range(715, 775):
				var color := image.get_pixel(x, y)
				values.append(color.r * 0.2126 + color.g * 0.7152 + color.b * 0.0722)
		values.sort()
		var median := values[values.size() / 2]; var dark := 0
		for value in values: if value < median - 0.06: dark += 1
		var share := float(dark) / values.size()
		print("STIPPLE|nantes_mobile|dark_outliers=", share)
		if share > 0.02:
			push_error("Pointillés dans l'atlas mobile : " + str(share)); return false
	return true

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0: out = args[0]
	DayNight.low_quality = "mobile" in args
	PbrMaterials.set_profile("mobile" if DayNight.low_quality else "high")
	DirAccess.make_dir_recursive_absolute(out)
	root.size = Vector2i(1280, 720)
	stage = Node3D.new(); root.add_child(stage)
	var environment := WorldEnvironment.new(); var env := Environment.new()
	var sky := Sky.new(); sky.sky_material = ProceduralSkyMaterial.new()
	env.sky = sky; env.background_mode = Environment.BG_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	environment.environment = env; stage.add_child(environment)
	var sun := DirectionalLight3D.new(); stage.add_child(sun)
	sun.rotation_degrees = Vector3(-45, -35, 0); sun.light_energy = 1.0; sun.shadow_enabled = true
	var floor_ := MeshInstance3D.new(); var plane := PlaneMesh.new(); plane.size = Vector2(120, 120)
	floor_.mesh = plane; floor_.material_override = PbrMaterials.surface("beton_dalle", {})
	floor_.position.y = -0.01; stage.add_child(floor_)
	cam = Camera3D.new(); stage.add_child(cam); cam.current = true; cam.fov = 55
	for vid in StockHD.manifest().get("variants", {}):
		cam.fov = 55
		var fleet := StockCatalog.find(vid)
		var liv := TramModel.livery_for({"source_id": fleet.network, "destination": "Essai HD"}, fleet)
		var rig := TramModel.build_rig(liv)
		if rig.hd == null: push_error("Rame HD indisponible : " + vid); quit(1); return
		var holder := Node3D.new(); stage.add_child(holder)
		for module in rig.modules: holder.add_child(module)
		rig.layout_straight()
		var front: Vector3 = rig.modules[0].global_position - Vector3(0, 0, rig.module_lengths[0] * 0.5)
		rig.hd.update({"destination": "ESSAI HD", "headlights": 0.45}, 0.0)
		cam.position = front + Vector3(5, 2.4, -8)
		cam.look_at(front + Vector3(0, 1.6, 6))
		if not await shot(vid + "-exterieur"): quit(1); return
		rig.set_doors(true, "right"); rig.set_pantograph(false)
		for i in 40: rig.update(0.1)
		if not await shot(vid + "-portes-aps"): quit(1); return
		var cab: CabView = rig.hd.ensure_cab(rig)
		rig.hd.set_lod(-1); rig.hd.set_cab_visible(true)
		cam.global_transform = cab.camera_transform(); cam.fov = 62
		cab.update({"speed_kmh": 32, "limit_kmh": 50, "notch": 0.25,
			"next_stop": "Essai cabine HD", "distance_m": 230, "signal": "Voie libre",
			"lamps": {"power": true, "doors": true}}, 0.0)
		if not await shot(vid + "-cabine"): quit(1); return
		holder.queue_free(); await process_frame
	StockHD.reset_cache()
	quit(0)
