extends SceneTree
## Lot P4 « ambiance » : galeries hors réseau (abris de station par réseau, feux R17 / R11 et heurtoir), jour et nuit.
## Usage : xvfb-run … godot --path . --rendering-method gl_compatibility -s tests/audit/p4a_gallery.gd -- <dossier>
## [abris|feux] [nuit]

var out := "user://p4a"

func _init() -> void:
	_run.call_deferred()

func _shot(name: String) -> void:
	for i in 6: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [out, name])
	print("SHOT|%s|draws=%d|tris=%d" % [name, Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)])

func _ground(parent: Node3D, size: Vector2, col: Color, a := 0.31) -> void:
	var g := LineView._Geo.new()
	var c := Color(col.r, col.g, col.b, a)
	g.quad(Vector3(-size.x, 0, -size.y), Vector3(size.x, 0, -size.y), Vector3(size.x, 0, size.y), Vector3(-size.x, 0, size.y), c)
	var mi := MeshInstance3D.new(); mi.mesh = g.mesh(); mi.material_override = Materials.building(); parent.add_child(mi)

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0: out = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	var what := args[1] if args.size() > 1 else "abris"
	var nights := [false, true] if args.size() <= 2 else [args.has("nuit")]
	root.size = Vector2i(1600, 900)
	var world := Node3D.new(); root.add_child(world)
	var dn := DayNight.new(); world.add_child(dn); dn.setup(world)
	VisualEffects.apply_profile(VisualEffects.effective_profile("auto"), dn.env, dn.sun, root)
	PbrMaterials.set_profile(VisualEffects.effective_profile("auto"))
	var cam := Camera3D.new(); cam.fov = 50.0; cam.near = 0.1; cam.far = 600.0; world.add_child(cam); cam.make_current()
	if what == "abris":
		var nets := ["angers", "nantes", "lyon", "bordeaux", "strasbourg", "montpellier", "grenoble", "idf", "lille", "toulouse", "nice", "reims"]
		_ground(world, Vector2(140, 30), Color("#c9c4b6"))
		var g := LineView._Geo.new(); var gl := LineView._Geo.new()
		for i in nets.size():
			var st := StationShelters.style(nets[i])
			var ox := float(i) * 14.0
			# quai : dalle, bordure blanche, bande podotactile
			g.box(Vector3(ox, 0.15, 0.0), Vector3(12.5, 0.3, 4.0), Color("#d9d4c8", 0.31))
			g.box(Vector3(ox, 0.305, -1.85), Vector3(12.5, 0.012, 0.18), Color("#f2f2ee"))
			StationShelters.build(world, g, Vector3(ox, 0.3, -0.6), Vector3(0, 0, 1), Vector3(1, 0, 0), st, nets[i].capitalize(), "A", ["Terminus Nord", "Terminus Sud"], 2.6, gl)
			var lbl := Label3D.new(); lbl.text = nets[i]; lbl.font_size = 64; lbl.pixel_size = 0.006; lbl.position = Vector3(ox, 0.6, -2.6)
			lbl.rotation = Vector3(-PI * 0.5, 0, 0); lbl.modulate = Color.BLACK; world.add_child(lbl)
		var mi := MeshInstance3D.new(); mi.mesh = g.mesh(); mi.material_override = Materials.building(); world.add_child(mi)
		var mg := MeshInstance3D.new(); mg.mesh = gl.mesh(); mg.material_override = StationShelters.glass_material(); world.add_child(mg)
		for night in nights:
			dn.set_hour(22.5 if night else 15.0)
			StationShelters.update_boards(Vector3.ZERO, dn.hour, 10.0)
			var suffix := "_nuit" if night else ""
			for k in 4:
				var x0 := k * 3 * 14.0 + 14.0
				cam.global_position = Vector3(x0 - 3.0, 2.2, -11.5); cam.look_at(Vector3(x0, 1.5, 0.3))
				await _shot("abris_%d%s" % [k, suffix])
			for i in nets.size():
				var ox := float(i) * 14.0
				cam.global_position = Vector3(ox - 4.2, 1.75, -5.6); cam.look_at(Vector3(ox + 0.4, 1.6, 0.4))
				await _shot("abri_%s%s" % [nets[i], suffix])
	else:
		_ground(world, Vector2(40, 30), Color("#5f6268"), 0.28)
		var aspects := ["go", "left", "right", "caution", "stop"]
		for i in aspects.size():
			var root_ := Node3D.new(); root_.position = Vector3(i * 1.6 - 3.2, 0, 0); root_.rotation.y = PI; world.add_child(root_)
			var body := MeshInstance3D.new(); body.mesh = SignalView.r17_body("crossing" if i < 4 else "block"); body.material_override = Materials.building(); root_.add_child(body)
			var y := (2.45 if i < 4 else 2.75) + 0.5
			var bar := SignalView._shape("bar", func(): var b := BoxMesh.new(); b.size = Vector3(0.05, 0.2, 0.012); return b)
			var dot := SignalView._shape("dot", func(): var c := CylinderMesh.new(); c.top_radius = 0.055; c.bottom_radius = 0.055; c.height = 0.012; c.radial_segments = 12; c.rings = 1; return c)
			var sy := SignalView.symbols(aspects[i])
			var lunar := SignalView._lit("lunar", SignalView.LUNAR, 2.8)
			var top := SignalView._symbol(root_, bar, Vector3(0, y + SignalView.MOD, -0.113), lunar); top.visible = sy[0]; top.rotation.z = sy[1]
			var mid := SignalView._symbol(root_, dot, Vector3(0, y, -0.113), lunar); mid.rotation.x = PI * 0.5; mid.visible = sy[2]
			var low := SignalView._symbol(root_, bar, Vector3(0, y - SignalView.MOD, -0.113), lunar); low.rotation.z = PI * 0.5; low.visible = sy[3]
		var rl := SignalView.road_light(world, Transform3D(Basis(Vector3.UP, PI), Vector3(5.0, 0, 0)))
		SignalView.set_road_light(rl, true)
		var rl2 := SignalView.road_light(world, Transform3D(Basis(Vector3.UP, PI), Vector3(6.4, 0, 0)))
		SignalView.set_road_light(rl2, false)
		var rl3 := SignalView.road_light(world, Transform3D(Basis(Vector3.UP, PI), Vector3(7.8, 0, 0)))
		SignalView.set_road_light(rl3, true, true)
		var buf := MeshInstance3D.new(); buf.mesh = SignalView.buffer_body(); buf.material_override = Materials.building(); buf.position = Vector3(-6.5, 0, 0); buf.rotation.y = PI; world.add_child(buf)
		if args.has("pluie"):   # gouttes de pare-brise sur la caméra (balai simulé arrêté)
			var ws := WindscreenRain.new(); cam.add_child(ws); ws.strength = 0.9
			ws.update_wiper(0.016, 0.9, false, -1.0, 0.0, 0.0, 0.0)
		for night in nights:
			dn.set_hour(22.5 if night else 15.0)
			cam.global_position = Vector3(0.8, 2.6, 7.5); cam.look_at(Vector3(0.8, 2.3, 0))
			await _shot("feux%s" % ("_nuit" if night else ""))
			cam.global_position = Vector3(-1.6, 3.0, 2.6); cam.look_at(Vector3(-1.6, 2.95, 0))
			await _shot("feux_proche%s" % ("_nuit" if night else ""))
	quit(0)
