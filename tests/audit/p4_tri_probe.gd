extends SceneTree
## P4 (optimisation Mobile) : répartition approchée des triangles visibles par catégorie de nœud (maillages dans le
## tronc de vue et la portée de visibilité, multimaillages entiers) au cadrage oblique 150 m de Ralliement (p3f_shots).
## Usage : godot --path . -s tests/audit/p4_tri_probe.gd -- [mobile] [réseau] [station]
var mobile := false

func _init() -> void:
	_run.call_deferred()

func _tris(m: Mesh) -> int:
	var n := 0
	for s in m.get_surface_count():
		var a := m.surface_get_arrays(s)
		var idx = a[Mesh.ARRAY_INDEX]
		n += (idx.size() if idx != null and idx.size() > 0 else a[Mesh.ARRAY_VERTEX].size()) / 3
	return n

func _run() -> void:
	var a := OS.get_cmdline_user_args()
	mobile = "mobile" in a
	var net_id := "angers_c"; var stn := "Ralliement"
	if a.size() >= 3: net_id = a[1]; stn = a[2]
	if mobile: DayNight.low_quality = true
	root.size = Vector2i(1280, 720)
	var main = load("res://src/ui/main.tscn").instantiate(); root.add_child(main)
	await process_frame
	main.save.settings.tutorial_done = true; main.save.settings.traffic = false
	main.net_path = "res://data/networks/%s.json" % net_id; main.free_mode = false
	var net := NetworkLoader.new(); net.load_file(main.net_path)
	main.vehicle = VehicleLibrary.default_for(net.meta); main.mission = net.missions()[0]
	main._start(); main.paused = true
	for c in main.get_children():
		if c is Control or c is CanvasLayer: c.visible = false
	if mobile:
		VisualEffects.apply_profile("mobile", main.view.day_night.env, main.view.day_night.sun, root, "mobile")
		PbrMaterials.set_profile("mobile")
	var st: Dictionary = {}
	for s in main.net.stations:
		if str(s.name) == stn: st = s; break
	var L: float = main.net.graph.edges[st.edge].length
	main.session.edge_id = st.edge; main.session.route.assign([st.edge])
	main.session.offset = clampf(float(st.offset) - 70.0, 1.0, maxf(1.0, L - 1.0)); main.view._rig_fresh = true
	main.hour0 = 10.5 - main.session.time_s / 3600.0; main.view.set_hour(10.5)
	await process_frame
	var p: Vector3 = main.view.pos3(st.edge, main.session.offset)
	if main.view.city: main.view.city.warm(p)
	var t: Vector3 = main.view.pos3(st.edge, main.session.offset + 5.0) - main.view.pos3(st.edge, main.session.offset - 5.0)
	t.y = 0.0; t = t.normalized()
	var side := t.cross(Vector3.UP)
	var cam := Camera3D.new(); cam.fov = 60.0; cam.far = 6000.0
	main.add_child(cam)
	cam.global_position = p - t * 110.0 + side * 70.0 + Vector3(0, 75.0, 0)
	cam.look_at(p + t * 20.0, Vector3.UP); cam.make_current()
	main.external_cam = true
	for i in 16: await process_frame
	await RenderingServer.frame_post_draw
	print("PROBE|total|draws=%d|tris=%d" % [Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)])
	var planes := cam.get_frustum()
	var cat := {}
	for n in root.find_children("*", "GeometryInstance3D", true, false):
		var gi := n as GeometryInstance3D
		if not gi.is_visible_in_tree(): continue
		var aabb := gi.global_transform * gi.get_aabb()
		var inside := true
		for pl in planes:
			if not _aabb_front(aabb, pl): inside = false; break
		if not inside: continue
		var d := cam.global_position.distance_to(aabb.get_center())
		if gi.visibility_range_end > 0.0 and d > gi.visibility_range_end + gi.visibility_range_end_margin: continue
		if d < gi.visibility_range_begin: continue
		var k := ""; var tris := 0
		if gi is MeshInstance3D and (gi as MeshInstance3D).mesh != null:
			tris = _tris((gi as MeshInstance3D).mesh); k = "mesh:" + str(gi.name).rstrip("0123456789_").left(18) + "@" + str(gi.get_parent().name).left(12).rstrip("0123456789_-")
		elif gi is MultiMeshInstance3D and (gi as MultiMeshInstance3D).multimesh != null and (gi as MultiMeshInstance3D).multimesh.mesh != null:
			var mm := (gi as MultiMeshInstance3D).multimesh
			var cnt := mm.visible_instance_count if mm.visible_instance_count >= 0 else mm.instance_count
			tris = _tris(mm.mesh) * cnt; k = "multi:" + str(gi.name).rstrip("0123456789_").left(18)
		else: continue
		cat[k] = int(cat.get(k, 0)) + tris
	var keys := cat.keys(); keys.sort_custom(func(x, y): return cat[x] > cat[y])
	for kk in keys.slice(0, 25): print("PROBE|%s|%d" % [kk, cat[kk]])
	quit()

static func _aabb_front(b: AABB, pl: Plane) -> bool:
	var c := b.get_center(); var e := b.size * 0.5
	var r := absf(pl.normal.x) * e.x + absf(pl.normal.y) * e.y + absf(pl.normal.z) * e.z
	return pl.distance_to(c) <= r
