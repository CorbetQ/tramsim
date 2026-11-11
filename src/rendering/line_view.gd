class_name LineView
extends Node3D
## Rendu d'une ligne : décor réel (CityScene, BD TOPO IGN) ou décor générique, plateforme et rails,
## quais avec abris, signaux, carrefours, rame modélisée articulée (TramModel), cycle jour/nuit (DayNight).
## Géométrie réelle si le réseau fournit `pts` (import GTFS), sinon arêtes dépliées le long de X.

var net: NetworkLoader
var geometric := false
var edge_origin: Dictionary = {}   # mode schématique : id -> Vector3
var tram: Node3D
var modules: Array[MeshInstance3D] = []
var rig: TramModel.Rig                 # rame animée (portes, pantographe)
var cam: Camera3D
var signal_nodes: Array[MeshInstance3D] = []
var sectors: Dictionary = {}       # edge id -> Node3D (affiché/masqué selon la distance)
var sector_center: Dictionary = {} # edge id -> Vector3
var view_distance := 400.0
var car_nodes: Array[MeshInstance3D] = []
var light_nodes: Array[MeshInstance3D] = []
var city: CityScene
var day_night: DayNight
var headlight: SpotLight3D
var livery: Dictionary = {}
var family := ""
var orbit := 0.0                   # rotation de la caméra extérieure (glisser au doigt)
var cam_dist := 40.0               # distance de la caméra extérieure (molette / pincement)
var _tram_len := 0.0
var _rig_fresh := false

func build(network: NetworkLoader, start_edge: String, vehicle: VehicleProfile = null) -> void:
	net = network
	geometric = net.has_geometry()
	livery = TramModel.livery_for(net.meta, tram_entry(vehicle))
	family = livery.family
	if not geometric:
		_unfold(start_edge)
	day_night = DayNight.new(); add_child(day_night); day_night.setup(self)
	var src := str(net.meta.get("source_id", ""))
	if geometric and net.meta.has("origin") and CityScene.available(src):
		city = CityScene.new()
		if city.open(src, net.meta.origin):
			city.radius = maxf(view_distance + 200.0, 500.0)
			add_child(city)
			var polys: Array = []
			for id in net.edge_info:
				var pl := PackedVector2Array()
				for q in net.edge_info[id].pts: pl.append(q)
				if pl.size() >= 2: polys.append(pl)
			city.set_tracks(polys)
		else:
			city.free(); city = null
	var lo := Vector3(INF, 0, INF); var hi := Vector3(-INF, 0, -INF)
	for id in net.graph.edges:
		var sec := Node3D.new(); add_child(sec); sectors[id] = sec
		var a := pos3(id, 0.0); var b := pos3(id, net.graph.edges[id].length)
		sector_center[id] = (a + b) * 0.5
		lo = Vector3(minf(lo.x, minf(a.x, b.x)), 0, minf(lo.z, minf(a.z, b.z)))
		hi = Vector3(maxf(hi.x, maxf(a.x, b.x)), 0, maxf(hi.z, maxf(a.z, b.z)))
		_track(sec, id)
		if geometric and city == null: _generic_buildings(sec, id)
	for s in net.stations:
		_station(sectors[s.edge], s)
	_crossovers()
	for s in net.signals:
		var t2 := _frame(s.edge, float(s.offset))
		_post(sectors[s.edge], t2.origin - t2.basis.x * 2.2, 3.2)
		signal_nodes.append(_lamp(sectors[s.edge], t2.origin - t2.basis.x * 2.2 + Vector3(0, 3.0, 0), Color(0.1, 0.9, 0.3)))
	for lane in net.meta.get("roads", []):
		var t3 := _frame(lane.edge, float(lane.edge_offset))
		var road := _Geo.new()
		road.box(Vector3(0, -0.04, 0), Vector3(float(lane.length), 0.06, 7.0), Color("#5b5f66"))
		_add_geo(self, road, Materials.building(), t3)
		_post(self, t3.origin + t3.basis.x * 4.0 + t3.basis.z * 5.0, 3.0)
		light_nodes.append(_lamp(self, t3.origin + t3.basis.x * 4.0 + Vector3(0, 2.8, 0) + t3.basis.z * 5.0, Color(0.1, 0.9, 0.3)))
	tram = Node3D.new(); add_child(tram)
	# sol au-delà du corridor
	var c := (lo + hi) * 0.5; var ext := (hi - lo) + Vector3(3000, 0, 3000)
	var ground := _Geo.new()
	ground.box(Vector3(0, -0.3, 0), Vector3(ext.x, 0.2, ext.z), Color("#97b46f"))
	_add_geo(self, ground, Materials.building(), Transform3D(Basis.IDENTITY, c))
	cam = Camera3D.new(); cam.far = 1600.0; cam.fov = 62.0; add_child(cam)
	headlight = SpotLight3D.new()
	headlight.spot_range = 70.0; headlight.spot_angle = 28.0; headlight.light_energy = 6.0
	headlight.light_color = Color(1.0, 0.95, 0.85)
	add_child(headlight)

func set_hour(h: float) -> void:
	day_night.set_hour(h)
	headlight.visible = day_night.night > 0.35

func _unfold(start_edge: String) -> void:
	var placed := {}
	var q: Array[String] = [start_edge]
	edge_origin[start_edge] = Vector3.ZERO
	while not q.is_empty():
		var id: String = q.pop_front()
		if placed.has(id): continue
		placed[id] = true
		var e: TrackGraph.Edge = net.graph.edges[id]
		var end: Vector3 = edge_origin[id] + Vector3(e.length, 0, 0)
		var outs: Array = net.graph.out_edges.get(e.to_node, [])
		for k in outs.size():
			if not edge_origin.has(outs[k]):
				edge_origin[outs[k]] = end + Vector3(0, 0, 8.0 * k)
				q.append(outs[k])
	for id in net.graph.edges:
		if not edge_origin.has(id):
			edge_origin[id] = Vector3(0, 0, 30.0 + 8.0 * edge_origin.size())

## Position 3D d'un point de voie.
const TRACK_OFFSET := 1.75   # demi-entraxe : chaque sens roule à droite de l'axe commun

func pos3(edge_id: String, offset: float) -> Vector3:
	if geometric:
		var q: Dictionary = net.point_on(edge_id, offset)
		var p: Vector2 = q.p
		var d: Vector2 = q.dir
		if net.edge_info[edge_id].raw:  # géométrie déjà sur l'axe de la voie (communications de voies)
			return Vector3(p.x, 0.0, p.y)
		return Vector3(p.x - d.y * TRACK_OFFSET, 0.0, p.y + d.x * TRACK_OFFSET)
	return edge_origin[edge_id] + Vector3(offset, 0, 0)

## Repère local : origine sur la voie, -Z = sens de marche, X = droite.
func _frame(edge_id: String, offset: float) -> Transform3D:
	var o := pos3(edge_id, offset)
	var d := Vector3(1, 0, 0)
	if geometric:
		var v: Vector2 = net.point_on(edge_id, offset).dir
		d = Vector3(v.x, 0, v.y)
	return Transform3D(Basis.looking_at(d.normalized(), Vector3.UP), o)

## Plateforme engazonnée, longrines béton, rails.
func _track(parent: Node3D, id: String) -> void:
	var pts: Array[Vector3] = []
	if geometric:
		for q in net.edge_info[id].pts: pts.append(Vector3(q.x, 0.0, q.y))
	else:
		pts = [pos3(id, 0.0), pos3(id, net.graph.edges[id].length)]
	if pts.size() < 2: return
	var g := _Geo.new()
	var o := TRACK_OFFSET if geometric else 0.0
	g.ribbon(pts, 3.5, 0.09, _bed_color(id), o)
	for off in [-0.72, 0.72]:
		g.ribbon(pts, 0.42, 0.11, Color("#b3b1aa"), o + off)
		g.ribbon(pts, 0.08, 0.17, Color("#8f959c", 0.9), o + off)
	_add_geo(parent, g, Materials.building())

## Plateforme : engazonnée en périphérie, pavée ou en enrobé dans les quartiers denses (densité de bâti IGN).
func _bed_color(id: String) -> Color:
	if city == null: return Color("#6f9f50")
	var mid := pos3(id, net.graph.edges[id].length * 0.5)
	var dens := city.density_at(mid)
	if dens > 170: return Color("#a49a8c") if city.style.get("trees", [0])[0] == 6 else Color("#8f8a84")
	if dens > 110: return Color("#6b6e73")
	return Color("#6f9f50")

## Communications de voies (croisement en ciseaux) avant le quai des arrêts de retournement.
func _crossovers() -> void:
	var done: Array = []
	var cand: Array = []
	for s in net.stations:
		if s.get("turnback", false): cand.append(s)
	if cand.is_empty():  # réseau d'une ligne : terminus = arrêts des approches
		for s in net.stations:
			if str(s.edge).ends_with("_appr"): cand.append(s)
	for s in cand:
		var L: float = net.graph.edges[s.edge].length
		var so := float(s.offset)
		var a := so - 80.0; var b := so - 48.0
		if a < 0.0: continue
		var c := pos3(s.edge, so)
		var dup := false
		for p in done:
			if (p as Vector3).distance_to(c) < 70.0: dup = true; break
		if dup: continue
		done.append(c)
		var g := _Geo.new()
		var fa := _frame(s.edge, a); var fb := _frame(s.edge, b)
		var off := TRACK_OFFSET if geometric else 0.0
		# pos3 inclut déjà le décalage de la voie de droite : la voie opposée est à -2 x décalage
		for diag in [[0.0, -2.0 * off], [-2.0 * off, 0.0]]:
			var p0: Vector3 = fa.origin + fa.basis.x * diag[0]
			var p1: Vector3 = fb.origin + fb.basis.x * diag[1]
			var pts: Array[Vector3] = [p0, p1]
			g.ribbon(pts, 2.6, 0.095, Color("#7d7a73"))
			for r in [-0.72, 0.72]:
				g.ribbon(pts, 0.08, 0.17, Color("#8f959c", 0.9), r)
		# moteurs d'aiguille
		for k in [a, b]:
			var f := _frame(s.edge, k)
			g.box_basis(f.origin + f.basis.x * 1.4 + Vector3(0, 0.25, 0), Vector3(0.5, 0.4, 0.9), f.basis, Color("#d9b43a"))
		_add_geo(sectors[s.edge], g, Materials.building())

## Quai avec abri, banc et totem, à droite dans le sens de marche.
func _station(parent: Node3D, s: Dictionary) -> void:
	var t := _frame(s.edge, float(s.offset))
	var g := _Geo.new()
	var L := 42.0
	var zc := L * 0.5 - 2.0   # le quai s'étend vers l'arrière depuis le point d'arrêt du nez
	g.box(Vector3(2.85, 0.15, zc), Vector3(2.4, 0.3, L), Color("#d9d4c8"))
	g.box(Vector3(1.72, 0.31, zc), Vector3(0.18, 0.02, L), Color("#f2f2ee"))
	var acc: Color = livery.get("accent", Color("#c8102e"))
	for k in [-1.0, 1.0]:
		g.box(Vector3(3.6, 1.4, zc + k * 3.0), Vector3(0.1, 2.5, 0.1), Color("#4a4f55"))
	g.box(Vector3(3.3, 2.7, zc), Vector3(1.5, 0.08, 7.0), Color("#5d646b"))
	g.box(Vector3(3.95, 1.5, zc), Vector3(0.05, 2.0, 6.6), Color(0.6, 0.75, 0.82, 0.5))
	g.box(Vector3(3.55, 0.75, zc), Vector3(0.5, 0.1, 2.4), Color("#7a6a58"))
	g.box(Vector3(3.5, 1.4, zc + 6.5), Vector3(0.3, 2.8, 0.6), acc)
	_add_geo(parent, g, Materials.building(), t)
	var lbl := Label3D.new()
	lbl.text = str(s.name)
	lbl.font_size = 64; lbl.pixel_size = 0.006
	lbl.outline_size = 12
	lbl.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	lbl.position = t * Vector3(3.5, 3.15, zc + 6.5)
	parent.add_child(lbl)

func _post(parent: Node3D, p: Vector3, h: float) -> void:
	var g := _Geo.new()
	g.box(Vector3(0, h * 0.5, 0), Vector3(0.14, h, 0.14), Color("#3f4449"))
	_add_geo(parent, g, Materials.building(), Transform3D(Basis.IDENTITY, p))

func _lamp(parent: Node3D, p: Vector3, col: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new(); bm.size = Vector3(0.35, 0.55, 0.35)
	var mat := StandardMaterial3D.new(); mat.albedo_color = col
	mat.emission_enabled = true; mat.emission = col; mat.emission_energy_multiplier = 1.5
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.material = mat
	mi.mesh = bm; mi.position = p
	parent.add_child(mi)
	return mi

func _set_lamp(mi: MeshInstance3D, col: Color) -> void:
	var mat := (mi.mesh as BoxMesh).material as StandardMaterial3D
	mat.albedo_color = col; mat.emission = col

## Décor générique (réseaux sans scène IGN) : bâtiments pseudo-aléatoires stables.
func _generic_buildings(parent: Node3D, id: String) -> void:
	var L: float = net.graph.edges[id].length
	var rng := RandomNumberGenerator.new(); rng.seed = hash(id)
	var g := _Geo.new()
	var s := 10.0
	while s < L - 5.0:
		var t := _frame(id, s)
		for side in [-1.0, 1.0]:
			if rng.randf() < 0.25: continue
			var h := rng.randf_range(6.0, 22.0)
			var w := rng.randf_range(10.0, 18.0)
			var dpt := rng.randf_range(10.0, 16.0)
			var p: Vector3 = t.origin + t.basis.x * side * (rng.randf_range(14.0, 22.0) + dpt * 0.5)
			var col := Color(0.85, 0.82, 0.76).darkened(rng.randf() * 0.15)
			col.a = 0.5 + rng.randf() * 0.49
			g.box_basis(p + Vector3(0, h * 0.5, 0), Vector3(dpt, h, w), t.basis, col)
		s += rng.randf_range(16.0, 24.0)
	_add_geo(parent, g, Materials.building())

func _add_geo(parent: Node3D, g: _Geo, mat: Material, xf: Transform3D = Transform3D.IDENTITY) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = g.mesh(); mi.material_override = mat; mi.transform = xf
	parent.add_child(mi)
	return mi

## Entrée de flotte d'un matériel : la sienne, sinon sa famille 3D (livrée du réseau appliquée).
static func tram_entry(vehicle: VehicleProfile) -> Dictionary:
	if vehicle == null: return {}
	if not vehicle.fleet.is_empty(): return vehicle.fleet
	return {"family": vehicle.model_family if vehicle.model_family != "" else vehicle.id}

func _ensure_modules(length_m: float) -> void:
	if not modules.is_empty() and is_equal_approx(length_m, _tram_len): return
	for m in modules: m.queue_free()
	rig = TramModel.build_rig(livery, length_m)
	modules = rig.modules
	for m in modules: tram.add_child(m)
	_tram_len = length_m
	_rig_fresh = true

func update_sectors(center: Vector3) -> int:
	var shown := 0
	for id in sectors:
		var len: float = net.graph.edges[id].length
		var vis: bool = (sector_center[id] as Vector3).distance_to(center) <= view_distance + len * 0.5
		sectors[id].visible = vis
		if vis: shown += 1
	return shown

func update_from(s: MissionSession, external: bool) -> void:
	_ensure_modules(s.phys.profile.length_m)
	var n := modules.size()
	for i in n:
		var f: Array = s.locate_behind(rig.module_starts[i])
		var b: Array = s.locate_behind(rig.module_starts[i] + rig.module_lengths[i])
		var pf := pos3(f[0], f[1]); var pb := pos3(b[0], b[1])
		var dir := pf - pb
		if dir.length() < 0.01: dir = Vector3(1, 0, 0)
		modules[i].transform = Transform3D(Basis.looking_at(dir.normalized(), Vector3.UP), (pf + pb) * 0.5)
	rig.set_doors(s.doors_open, "right")   # quais à droite dans le sens de marche
	rig.set_pantograph(s.pantograph_up)
	if _rig_fresh: rig.snap()
	else: rig.update(get_process_delta_time())
	_rig_fresh = false
	var front := _frame(s.edge_id, s.offset)
	var fwd := -front.basis.z
	headlight.global_transform = Transform3D(Basis.looking_at((fwd + Vector3(0, -0.12, 0)).normalized(), Vector3.UP), front.origin + fwd * 0.5 + Vector3(0, 1.0, 0))
	tram.visible = external
	if external:
		var back := fwd.rotated(Vector3.UP, orbit)
		var k := cam_dist / 40.0
		cam.position = front.origin - back * cam_dist + Vector3(0, 9.5 * k, 0) + back.cross(Vector3.UP) * (-11.0 * k)
		cam.look_at(front.origin - fwd * 14.0 + Vector3(0, 2.0, 0))
	else:  # vue cabine
		cam.position = front.origin - fwd * 1.0 + Vector3(0, 2.6, 0)
		cam.look_at(cam.position + fwd * 30.0 + Vector3(0, -0.8, 0))
	update_sectors(front.origin)
	if city: city.update(cam.global_position, 1)
	_update_cars(s)
	for i in signal_nodes.size():
		_set_lamp(signal_nodes[i], Color(0.1, 0.9, 0.3) if s.signal_state[i] == "clear" else Color(0.95, 0.1, 0.1))

func _update_cars(s: MissionSession) -> void:
	var cars := s.traffic.cars
	while car_nodes.size() < cars.size():
		var g := _Geo.new()
		var body := Color.from_hsv(randf(), 0.55, 0.75)
		g.box(Vector3(0, 0.55, 0), Vector3(1.8, 0.7, 4.3), body)
		g.box(Vector3(0, 1.15, 0.2), Vector3(1.6, 0.55, 2.3), Color(0.25, 0.32, 0.38, 0.5))
		var mi := _add_geo(self, g, Materials.toon())
		car_nodes.append(mi)
	for i in car_nodes.size():
		var node := car_nodes[i]
		node.visible = i < cars.size()
		if node.visible:
			var lane: Dictionary = s.traffic.lanes[cars[i].lane]
			var t := _frame(lane.edge, float(lane.edge_offset))
			var p := t.origin + t.basis.x * (float(cars[i].pos) - float(lane.cross_at)) + t.basis.z * 1.5
			node.transform = Transform3D(Basis.looking_at(t.basis.x, Vector3.UP), p)
	for i in light_nodes.size():
		_set_lamp(light_nodes[i], Color(0.95, 0.1, 0.1) if s.traffic.light_red[i] else Color(0.1, 0.9, 0.3))

## Petit accumulateur géométrique (couleurs de sommets ; alpha < 0.75 = vitrage, < 0.25 = lumineux).
class _Geo:
	var v := PackedVector3Array()
	var c := PackedColorArray()
	var uv := PackedVector2Array()

	func tri(a: Vector3, b: Vector3, d: Vector3, col: Color) -> void:
		v.append_array([a, b, d]); c.append_array([col, col, col])
		uv.append_array([Vector2(-1, -1), Vector2(-1, -1), Vector2(-1, -1)])

	func quad(a: Vector3, b: Vector3, d: Vector3, e: Vector3, col: Color) -> void:
		tri(a, b, d, col); tri(a, d, e, col)

	func box(ctr: Vector3, s: Vector3, col: Color) -> void:
		box_basis(ctr, s, Basis.IDENTITY, col)

	func box_basis(ctr: Vector3, s: Vector3, b: Basis, col: Color) -> void:
		var h := s * 0.5
		var p := []
		for q in [Vector3(-h.x, -h.y, -h.z), Vector3(h.x, -h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(-h.x, h.y, -h.z),
			Vector3(-h.x, -h.y, h.z), Vector3(h.x, -h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z)]:
			p.append(ctr + b * q)
		for f in [[0, 1, 2, 3], [5, 4, 7, 6], [4, 0, 3, 7], [1, 5, 6, 2], [3, 2, 6, 7]]:
			quad(p[f[0]], p[f[1]], p[f[2]], p[f[3]], col)

	func ribbon(pts: Array[Vector3], w: float, y: float, col: Color, offset: float = 0.0) -> void:
		for i in range(pts.size() - 1):
			var d := (pts[i + 1] - pts[i]).normalized()
			var n := Vector3(-d.z, 0, d.x)
			var a := pts[i] + n * offset - d * 0.05; var b := pts[i + 1] + n * offset + d * 0.05
			var hw := n * (w * 0.5)
			quad(a - hw + Vector3(0, y, 0), a + hw + Vector3(0, y, 0), b + hw + Vector3(0, y, 0), b - hw + Vector3(0, y, 0), col)

	func mesh() -> ArrayMesh:
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = v; arr[Mesh.ARRAY_COLOR] = c; arr[Mesh.ARRAY_TEX_UV] = uv
		var m := ArrayMesh.new()
		if v.size() > 0: m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		return m
