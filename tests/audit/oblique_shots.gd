extends SceneTree
## Vues en perspective des zones complexes : décor du jeu (CityScene complet, 13 h) et référence réelle (orthophoto IGN
## drapée sur le MNS LiDAR HD, préparée par tests/audit/oblique_views.py), même caméra.
## Args : -- <sites.json> [réseau]   Sortie : jeu_<site>_<vue>.png et ref_<site>_<vue>.png (1280 x 720) à côté de
## sites.json. [réseau] (res://data/free/<ville>.json ou une ligne) : voies, ouvrages et caténaire affichés (LineView,
## même état que le jeu : tabliers calés sur les voies, corridors du relief lointain).
const VIEWS := {"proche": [75.0, 30.0], "obl": [170.0, 38.0], "haut": [320.0, 60.0]}

var game_vp: SubViewport
var ref_vp: SubViewport
var game_cam: Camera3D
var ref_cam: Camera3D

func _init() -> void:
	_run.call_deferred()

func _vp() -> SubViewport:
	var vp := SubViewport.new(); vp.own_world_3d = true; vp.size = Vector2i(1280, 720); vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	return vp

func _run() -> void:
	var path := OS.get_cmdline_user_args()[0]
	var dir := path.get_base_dir()
	var js: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	game_vp = _vp(); ref_vp = _vp()
	var gw := Node3D.new(); game_vp.add_child(gw)
	var day := DayNight.new(); gw.add_child(day); day.setup(gw); day.set_hour(13.5)
	day.env.fog_enabled = false
	var cs := CityScene.new()
	if not cs.open(str(js.city), js.origin): quit(1); return
	cs.radius = 700.0
	var lv: LineView = null
	if OS.get_cmdline_user_args().size() > 1:
		var net := NetworkLoader.new(); net.load_file(OS.get_cmdline_user_args()[1])
		lv = LineView.new(); lv.view_distance = 900.0
		gw.add_child(lv)
		lv.build(net, str(net.meta.edges[0].id), null, cs)
		lv.day_night.queue_free(); lv.cam.current = false
		cs.radius = 700.0
	else:
		gw.add_child(cs)
	game_cam = Camera3D.new(); game_cam.fov = 55.0; game_cam.far = 4000.0; gw.add_child(game_cam); game_cam.current = true
	var rw := Node3D.new(); ref_vp.add_child(rw)
	var env := WorldEnvironment.new(); env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR; env.environment.background_color = Color(0.72, 0.8, 0.88)
	rw.add_child(env)
	ref_cam = Camera3D.new(); ref_cam.fov = 55.0; ref_cam.far = 4000.0; rw.add_child(ref_cam); ref_cam.current = true
	var ref_mesh := MeshInstance3D.new(); rw.add_child(ref_mesh)
	for s: Dictionary in js.sites:
		var c := Vector3(float(s.x), 0.0, float(s.z))
		cs.warm(c)
		c.y = cs.height_city(c.x, c.z)
		if lv != null: lv.update_sectors(c + cs.position)
		ref_mesh.mesh = _ref_mesh(dir.path_join("ref_%s" % s.name), c, float(s.half))
		var mat := StandardMaterial3D.new(); mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_texture = ImageTexture.create_from_image(Image.load_from_file(dir.path_join("ref_%s.png" % s.name)))
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		ref_mesh.material_override = mat
		var d := Vector3(cos(float(s.dir)), 0.0, sin(float(s.dir)))
		var p := Vector3(-d.z, 0.0, d.x)
		for v in VIEWS:
			var dist: float = VIEWS[v][0]; var pitch := deg_to_rad(float(VIEWS[v][1]))
			var pos := c + p * dist * cos(pitch) + Vector3.UP * dist * sin(pitch)
			await _shot(dir, s.name, v, pos, c)
		var q := c - d * 60.0
		if s.get("street") != null: q = Vector3(float(s.street[0]), 0.0, float(s.street[1]))
		var street := Vector3(q.x, cs.height_city(q.x, q.z) + 1.7, q.z)
		await _shot(dir, s.name, "rue", street, c + Vector3.UP * 4.0)
		print("OBLIQUE|%s|%s" % [s.name, s.ref])
	quit()

func _shot(dir: String, site: String, v: String, pos: Vector3, at: Vector3) -> void:
	for cam in [game_cam, ref_cam]:
		cam.position = pos
		cam.look_at(at, Vector3.UP)
	for i in 4: await RenderingServer.frame_post_draw
	game_vp.get_texture().get_image().save_png(dir.path_join("jeu_%s_%s.png" % [site, v]))
	ref_vp.get_texture().get_image().save_png(dir.path_join("ref_%s_%s.png" % [site, v]))

## Maillage de référence : grille de hauteurs (npy float32, pas 2 m, altitudes relatives à alt0), UV de l'orthophoto.
func _ref_mesh(base: String, c: Vector3, half: float) -> ArrayMesh:
	var b := FileAccess.get_file_as_bytes(base + ".npy")
	var hl := b.decode_u16(8)
	var header := b.slice(10, 10 + hl).get_string_from_ascii()
	var shp := header.split("(")[1].split(")")[0].split(",")
	var nz := int(shp[0]); var nx := int(shp[1])
	var o := 10 + hl
	var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var step := 2.0 * half / nx
	var k := 2      # une maille de 4 m (2 x 2 m) : relief et ouvrages lisibles, maillage léger
	var x0 := c.x - half; var z0 := c.z - half
	for iz in range(0, nz - k, k):
		for ix in range(0, nx - k, k):
			var q := []
			for dd in [Vector2i(0, 0), Vector2i(k, 0), Vector2i(k, k), Vector2i(0, k)]:
				var jx: int = ix + dd.x; var jz: int = iz + dd.y
				var h := b.decode_float(o + (jz * nx + jx) * 4)
				if is_nan(h): h = c.y
				q.append([Vector3(x0 + (jx + 0.5) * step, h, z0 + (jz + 0.5) * step), Vector2((jx + 0.5) / nx, (jz + 0.5) / nz)])
			for t in [[0, 1, 2], [0, 2, 3]]:
				for i in t:
					st.set_uv(q[i][1]); st.add_vertex(q[i][0])
	return st.commit()
