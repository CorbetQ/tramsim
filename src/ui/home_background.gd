class_name HomeBackground
extends Control
## Arrière-plan de l'accueil : la ville sélectionnée vue du ciel (décor CityScene réel, rayon réduit),
## vue verticale orthographique, nord en haut, lignes de tram aux couleurs GTFS, fin d'après-midi.
## Changement de ville : chargement en tâche de fond (WorkerThreadPool), puis fondu enchaîné.
## Mobile (`still_mode`) : rayon minimal, une seule image rendue puis 3D libérée (image fixe).

signal city_ready(city: String)

static var still_mode := OS.has_feature("mobile")
const HOUR := 17.3                      # lumière rasante, ciel encore clair
const FADE := 0.9
const R := 6371008.8

var city := ""                          # ville demandée (nom affiché)
var shown := ""                         # ville affichée
var render_scale := 0.6 if still_mode else 0.85
var _layers: Array[Dictionary] = []     # {vp, rect, cam, center, dist, city, still}
var _task := -1
var _job: Dictionary = {}               # résultat du thread en cours
var _shade: TextureRect
var _departing := false
var _control: LoadControl

class LoadControl:
	extends RefCounted
	var mutex := Mutex.new()
	var _cancelled := false
	func cancel() -> void:
		mutex.lock(); _cancelled = true; mutex.unlock()
	func cancelled() -> bool:
		mutex.lock(); var result := _cancelled; mutex.unlock()
		return result

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	name = "home_background"

func _ready() -> void:
	# voile de lisibilité : plus sombre à gauche (panneaux), léger à droite (la ville)
	_shade = TextureRect.new(); _shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var gt := GradientTexture2D.new(); gt.width = 256; gt.height = 8
	var gr := Gradient.new(); gr.set_color(0, Color(0.02, 0.03, 0.05, 0.72)); gr.set_color(1, Color(0.02, 0.03, 0.05, 0.12))
	gr.add_point(0.55, Color(0.02, 0.03, 0.05, 0.3)); gt.gradient = gr
	_shade.texture = gt; _shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; _shade.stretch_mode = TextureRect.STRETCH_SCALE
	add_child(_shade)
	resized.connect(_fit)

## Affiche une ville (nom de NetworkRegistry). Sans effet si elle est déjà affichée ou en cours de chargement.
func show_city(name_: String) -> void:
	if name_ == city: return
	city = name_
	if _task < 0: _launch()
	elif _control != null: _control.cancel()

func is_loading() -> bool:
	return _task >= 0

func layer_count() -> int:
	return _layers.size()

func _launch() -> void:
	var entries := NetworkRegistry.entries().filter(func(e): return e.city == city)
	if entries.is_empty(): return
	# rayon de décor : couvre le cadre (±1,47 d × ±0,83 d en 16:9 ; jusqu'au 21:9) ; tuiles allégées (CityScene.lite)
	var radius := 1.25 if still_mode else 1.6
	_control = LoadControl.new()
	_job = {"city": city, "entries": entries, "radius": radius, "control": _control}
	_task = WorkerThreadPool.add_task(_load.bind(_job), false, "home_background")

## Thread : réseau (tracés + couleurs), scène de la ville, tuiles autour du centre.
static func _load(job: Dictionary) -> void:
	var lines: Array = []
	var lo := Vector2(INF, INF); var hi := Vector2(-INF, -INF)
	var src := ""; var origin := []
	var seen := {}
	for e in job.entries:
		if job.control.cancelled(): return
		if seen.has(str(e.line)): continue   # variantes de service d'une même ligne : tracé déjà couvert
		seen[str(e.line)] = true
		var d = CityDataStore.document(e.path)
		if not d is Dictionary or not d.has("origin"): continue
		if src == "":
			src = str(d.get("source_id", "")); origin = d.origin
		var polys: Array = []
		for ed in d.get("edges", []):
			if e.get("free_only", false) and not str(e.line) in ed.get("lines", []): continue
			var pts: Array = ed.get("pts", [])
			if pts.size() < 2: continue
			var ys: Array = ed.get("y", [])
			var pl := PackedVector3Array()
			for i in pts.size():
				var p := _to_city(Vector2(float(pts[i][0]), float(pts[i][1])), d.origin, origin)
				pl.append(Vector3(p.x, float(ys[i]) if i < ys.size() else NAN, p.y))
				lo = lo.min(p); hi = hi.max(p)
			polys.append(pl)
		lines.append({"color": UiTheme.color_of(d.get("color", ""), UiTheme.INFO), "polys": polys, "urban": e.get("kind", "tram") != "tram-train"})
	job.lines = lines
	job.origin = origin.duplicate()
	if lines.is_empty() or not lo.is_finite(): return
	# centre = médiane des tracés (cœur du réseau, là où les lignes se croisent), pas le centre de l'emprise
	var xs: Array[float] = []; var zs: Array[float] = []
	var central: Array = lines.filter(func(ln): return ln.urban)
	if central.is_empty(): central = lines
	for ln in central:
		for pl: PackedVector3Array in ln.polys:
			for q in pl: xs.append(q.x); zs.append(q.z)
	xs.sort(); zs.sort()
	var center := Vector2(xs[xs.size() / 2], zs[zs.size() / 2])
	var extent := maxf(hi.x - lo.x, hi.y - lo.y)
	job.dist = clampf(extent * 0.12, 700.0, 1300.0)
	job.center = Vector3(center.x, 0.0, center.y)
	if CityScene.available(src):
		var meta = CityDataStore.document("res://data/scenes/%s.json" % src)
		var cs := CityScene.new()
		if meta is Dictionary and cs.open(src, origin):
			cs.radius = job.radius * job.dist
			cs.lite = true
			if not cs.warm(job.center, job.control):
				cs.free(); return
			if cs.has_terrain: job.center.y = cs.height_at(job.center)
			job.scene = cs
		else:
			cs.free()

## Repère d'une ligne (origine propre) -> repère commun de la ville (origine de la première ligne).
static func _to_city(p: Vector2, o_line: Array, o_city: Array) -> Vector2:
	if o_city.is_empty() or (float(o_line[0]) == float(o_city[0]) and float(o_line[1]) == float(o_city[1])): return p
	var lat_c := deg_to_rad(float(o_city[0]))
	var dx := deg_to_rad(float(o_line[1]) - float(o_city[1])) * R * cos(lat_c)
	var dz := -deg_to_rad(float(o_line[0]) - float(o_city[0])) * R
	return Vector2(dx + p.x * cos(deg_to_rad(float(o_line[0]))) / cos(lat_c), dz + p.y)

func _process(_dt: float) -> void:
	if _task >= 0 and WorkerThreadPool.is_task_completed(_task):
		WorkerThreadPool.wait_for_task_completion(_task); _task = -1
		var job := _job; _job = {}
		if job.city == city and job.has("dist") and not job.control.cancelled(): _install(job)
		elif job.has("scene"): (job.scene as Node).free()
		if city != shown and (city != job.city or job.control.cancelled()): _launch()
	var visible_ := is_visible_in_tree()
	for L in _layers:
		if L.vp == null: continue
		if bool(L.get("visible", false)) != visible_:
			L.vp.render_target_update_mode = SubViewport.UPDATE_ONCE if visible_ else SubViewport.UPDATE_DISABLED
			L["visible"] = visible_

func _place(L: Dictionary) -> void:
	var d: float = L.dist
	var look: Vector3 = L.center
	L.cam.position = look + Vector3.UP * d * 2.0
	L.cam.look_at(look, Vector3.FORWARD)

func _install(job: Dictionary) -> void:
	var vp := SubViewport.new(); vp.own_world_3d = true; vp.msaa_3d = Viewport.MSAA_2X if not still_mode else Viewport.MSAA_DISABLED
	# quelques images complètes (ciel, environnement, matériaux prêts) avant de figer : la toute première image
	# d'un SubViewport neuf sort délavée (plan blanc) sous Compatibility
	vp.size = _vp_size(); vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var world := Node3D.new(); vp.add_child(world)
	var day := DayNight.new(); world.add_child(day); day.setup(world); day.set_hour(HOUR)
	if day.edges: day.edges.visible = false             # contours encrés : prévus pour la vue rapprochée
	day.sun.shadow_enabled = false                         # vue lointaine : ombres inutiles
	# Vue cartographique orthographique : la distance verticale ne doit pas décolorer toute la ville.
	day.env.fog_enabled = false
	day.env.fog_height_density = 0.0
	if job.has("scene"): world.add_child(job.scene)
	world.add_child(_line_mesh(job.lines, job.dist))
	var cam := Camera3D.new(); cam.fov = 50.0; cam.near = 2.0; cam.far = job.dist * 5.0; world.add_child(cam); cam.current = true
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = job.dist * 1.65
	var rect := TextureRect.new(); rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE; rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED; rect.texture = vp.get_texture(); rect.modulate.a = 0.0
	add_child(rect); move_child(rect, _shade.get_index())
	var L := {"vp": vp, "rect": rect, "cam": cam, "center": job.center, "dist": job.dist,
		"city": job.city, "still": still_mode, "day": day, "visible": true, "origin": job.origin, "scene": job.get("scene")}
	_place(L)
	_layers.append(L)
	shown = job.city
	if OS.get_environment("HOME_BG_DEBUG") != "": print("fond %s : centre %s, distance %.0f, tuiles %d" % [job.city, job.center, job.dist, job.scene.built.size() if job.has("scene") else -1])
	if still_mode: _freeze.call_deferred(L)
	else: _settle.call_deferred(L)
	var tw := rect.create_tween(); tw.tween_property(rect, "modulate:a", 1.0, FADE)
	tw.tween_callback(func():
		for old in _layers.duplicate():
			if old != L: _drop(old)
		city_ready.emit(job.city))

## Bureau : rendu continu le temps de quelques images, puis une seule image par changement (UPDATE_ONCE).
func _settle(L: Dictionary) -> void:
	for i in 4: await RenderingServer.frame_post_draw
	if not _departing and L.vp != null and is_instance_valid(L.vp):
		L.vp.render_target_update_mode = SubViewport.UPDATE_ONCE if is_visible_in_tree() else SubViewport.UPDATE_DISABLED
		L["visible"] = is_visible_in_tree()

## Mobile : quelques images (ciel, éclairage) puis copie figée ; la 3D est libérée.
func _freeze(L: Dictionary) -> void:
	for i in 5: await RenderingServer.frame_post_draw
	if _departing or not is_instance_valid(L.vp): return
	var img: Image = L.vp.get_texture().get_image()
	if img != null and not img.is_empty(): L.rect.texture = ImageTexture.create_from_image(img)
	L.vp.render_target_update_mode = SubViewport.UPDATE_DISABLED

## Keep the already-built aerial LOD for the pan; no second city read on launch.
func departure_zoom(seconds: float) -> void:
	_departing = true
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_shade, "modulate:a", 0.0, seconds)
	if _layers.is_empty(): return
	var layer: Dictionary = _layers[-1]
	if is_instance_valid(layer.cam) and is_instance_valid(layer.vp):
		layer.rect.texture = layer.vp.get_texture()
		layer.vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		var routes: Node = layer.vp.find_child("tram_lines", true, false)
		if routes != null:
			for child in routes.get_children():
				if child is MeshInstance3D and child.material_override is BaseMaterial3D:
					tw.tween_property(child.material_override, "albedo_color:a", 0.0, seconds)
		tw.tween_property(layer.cam, "size", layer.cam.size * 0.94, seconds).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)

func departure_context(destination_origin: Array) -> Dictionary:
	if _layers.is_empty() or destination_origin.size() < 2: return {}
	var layer: Dictionary = _layers[-1]
	if not is_instance_valid(layer.cam): return {}
	var pose: Transform3D = layer.cam.global_transform
	var p := _to_city(Vector2(pose.origin.x, pose.origin.z), layer.origin, destination_origin)
	pose.origin.x = p.x; pose.origin.z = p.y
	var result := {"transform": pose, "size": layer.cam.size, "hour": HOUR}
	var aerial: CityScene = layer.get("scene")
	if is_instance_valid(aerial):
		aerial.get_parent().remove_child(aerial)
		aerial.align_to_origin(destination_origin)
		result["aerial"] = aerial
	return result

func _drop(L: Dictionary) -> void:
	_layers.erase(L)
	if L.vp != null and is_instance_valid(L.vp): L.vp.queue_free()
	if is_instance_valid(L.rect): L.rect.queue_free()

func _vp_size() -> Vector2i:
	var s := size if size.x > 8 else get_viewport_rect().size
	return Vector2i(maxi(64, int(s.x * render_scale)), maxi(64, int(s.y * render_scale)))

func _fit() -> void:
	for L in _layers:
		if L.vp != null:
			L.vp.size = _vp_size()
			L.vp.render_target_update_mode = SubViewport.UPDATE_ONCE

## Lignes de tram en surbrillance : ruban coloré + liseré sombre, toujours visibles (sans test de profondeur).
static func _line_mesh(lines: Array, dist: float) -> Node3D:
	var root := Node3D.new(); root.name = "tram_lines"
	var w := clampf(dist * 0.011, 7.0, 16.0)
	for pass_ in 2:
		var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for ln in lines:
			var col: Color = Color(0.02, 0.03, 0.05, 0.55) if pass_ == 0 else ln.color.lightened(0.08)
			var half := w * (0.95 if pass_ == 0 else 0.5)
			for pl: PackedVector3Array in ln.polys:
				for i in pl.size() - 1:
					var a := pl[i]; var b := pl[i + 1]
					a.y = (0.0 if is_nan(a.y) else a.y) + 6.0; b.y = (0.0 if is_nan(b.y) else b.y) + 6.0
					var t := Vector3(b.x - a.x, 0, b.z - a.z)
					if t.length() < 0.01: continue
					var n := Vector3(-t.z, 0, t.x).normalized() * half
					st.set_color(col)
					for v in [a - n, a + n, b + n, a - n, b + n, b - n]: st.add_vertex(v)
		var mi := MeshInstance3D.new(); mi.mesh = st.commit()
		var m := StandardMaterial3D.new(); m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.vertex_color_use_as_albedo = true; m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.no_depth_test = true; m.cull_mode = BaseMaterial3D.CULL_DISABLED; m.render_priority = pass_
		mi.material_override = m; mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
	return root

func _exit_tree() -> void:
	if _task >= 0:
		# arrêt non bloquant : la tâche voit l'annulation (entre deux tuiles), la fin est récupérée plus tard
		if _control != null: _control.cancel()
		_orphans.append([_task, _job])
		_task = -1; _job = {}
		var tree := Engine.get_main_loop() as SceneTree
		if tree != null and not tree.process_frame.is_connected(_reap):
			tree.process_frame.connect(_reap)

## Chargements abandonnés (fond quitté en cours de chargement) : [tâche, job], libérés une fois terminés.
static var _orphans: Array = []

static func _reap() -> void:
	for o in _orphans.duplicate():
		if WorkerThreadPool.is_task_completed(o[0]):
			WorkerThreadPool.wait_for_task_completion(o[0])
			if o[1].has("scene") and is_instance_valid(o[1].scene): (o[1].scene as Node).free()
			_orphans.erase(o)
	var tree := Engine.get_main_loop() as SceneTree
	if _orphans.is_empty() and tree != null and tree.process_frame.is_connected(_reap):
		tree.process_frame.disconnect(_reap)
