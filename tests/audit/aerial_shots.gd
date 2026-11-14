extends SceneTree
## Vues aériennes verticales du décor (caméra orthographique, nord en haut, 13 h, sans brouillard) pour l'audit.
## Args : -- <views.json> [fichier...]  (views.json : tests/audit/aerial_views.py prepare ; fichiers : sous-ensemble)
## Chaque vue est rendue en mosaïque de cases de CHUNK m (tuiles de décor chargées autour de chaque case, puis libérées),
## assemblée en une image de `px` pixels de côté : <dossier de views.json>/raw_<fichier>.png.
## Lignes de tram en surimpression fine (couleurs GTFS). Sortie console : "AERIAL|fichier|cases|ms|tuiles".
const CHUNK := 2000.0

var vp: SubViewport
var cam: Camera3D
var cs: CityScene
var lines_node: Node3D

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var path := args[0]
	var only := args.slice(1)
	var js: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	var dir := path.get_base_dir()
	vp = SubViewport.new(); vp.own_world_3d = true; vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var world := Node3D.new(); vp.add_child(world)
	var day := DayNight.new(); world.add_child(day); day.setup(world); day.set_hour(13.0)
	if day.edges: day.edges.visible = false
	day.sun.shadow_enabled = false
	day.env.fog_enabled = false
	day.env.fog_height_density = 0.0
	cs = CityScene.new()
	if not cs.open(str(js.city), js.origin):
		push_error("scène absente : " + str(js.city)); quit(1); return
	cs.lite = true
	world.add_child(cs)
	cam = Camera3D.new(); cam.projection = Camera3D.PROJECTION_ORTHOGONAL; cam.near = 5.0; cam.far = 8000.0
	world.add_child(cam); cam.current = true
	for v: Dictionary in js.views:
		if not only.is_empty() and not str(v.file) in only: continue
		var t0 := Time.get_ticks_msec()
		var size := float(v.size)
		var n := maxi(1, ceili(size / CHUNK))
		var cpx := int(round(float(js.px) / n))
		var step := size / n
		vp.size = Vector2i(cpx, cpx)
		_set_lines(js.lines, size / (cpx * n))
		var img := Image.create(cpx * n, cpx * n, false, Image.FORMAT_RGB8)
		var built := 0
		for j in n:
			for ii in n:
				var i := ii if j % 2 == 0 else n - 1 - ii      # parcours en serpentin : tuiles réutilisées
				var c := Vector3(float(v.cx) - size * 0.5 + (i + 0.5) * step, 0.0, float(v.cz) - size * 0.5 + (j + 0.5) * step)
				cs.radius = step * 0.75 + 200.0
				cs.warm(c)
				built = maxi(built, cs.built.size())
				var y := cs.height_at(c) if cs.has_terrain else 0.0
				cam.size = step
				cam.position = Vector3(c.x, y + 3000.0, c.z)
				cam.look_at(Vector3(c.x, y, c.z), Vector3.FORWARD)
				for f in 3: await RenderingServer.frame_post_draw
				var part := vp.get_texture().get_image()
				part.convert(Image.FORMAT_RGB8)
				img.blit_rect(part, Rect2i(0, 0, cpx, cpx), Vector2i(i * cpx, j * cpx))
		img.save_png(dir.path_join("raw_%s.png" % v.file))
		print("AERIAL|%s|%d|%d|%d" % [v.file, n * n, Time.get_ticks_msec() - t0, built])
	quit()

## Tracés des lignes : ruban coloré à liseré sombre, toujours visible, ~3 px de large.
func _set_lines(lines: Array, mpp: float) -> void:
	if lines_node != null: lines_node.queue_free()
	lines_node = Node3D.new(); cs.get_parent().add_child(lines_node)
	var w := maxf(2.0, mpp * 3.0)
	for pass_ in 2:
		var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for ln in lines:
			var col: Color = Color(0.02, 0.03, 0.05, 0.6) if pass_ == 0 else Color.from_string(str(ln.color), Color.SKY_BLUE)
			var half := w * (0.9 if pass_ == 0 else 0.45)
			var pts: Array = ln.pts
			st.set_color(col)
			for i in pts.size() - 1:
				var a := Vector3(float(pts[i][0]), 400.0, float(pts[i][1])); var b := Vector3(float(pts[i + 1][0]), 400.0, float(pts[i + 1][1]))
				var t := b - a
				if t.length() < 0.01: continue
				var nrm := Vector3(-t.z, 0, t.x).normalized() * half
				for q in [a - nrm, a + nrm, b + nrm, a - nrm, b + nrm, b - nrm]: st.add_vertex(q)
		var mi := MeshInstance3D.new(); mi.mesh = st.commit()
		var m := StandardMaterial3D.new(); m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.vertex_color_use_as_albedo = true; m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.no_depth_test = true; m.cull_mode = BaseMaterial3D.CULL_DISABLED; m.render_priority = pass_
		mi.material_override = m; mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		lines_node.add_child(mi)
