class_name LineView
extends Node3D
## Rendu : voie (ruban par arête), quais, signaux, carrefours, rame articulée.
## Géométrie réelle si le réseau fournit `pts` (import GTFS/OSM), sinon arêtes dépliées le long de X.

const MODULE_LEN := 7.0

var net: NetworkLoader
var geometric := false
var edge_origin: Dictionary = {}   # mode schématique : id -> Vector3
var tram: Node3D
var modules: Array[MeshInstance3D] = []
var cam: Camera3D
var signal_nodes: Array[MeshInstance3D] = []
var sectors: Dictionary = {}       # edge id -> Node3D (affiché/masqué selon la distance)
var sector_center: Dictionary = {} # edge id -> Vector3
var view_distance := 400.0
var car_nodes: Array[MeshInstance3D] = []
var light_nodes: Array[MeshInstance3D] = []
var livery := Color(0.85, 0.1, 0.15)

func build(network: NetworkLoader, start_edge: String) -> void:
	net = network
	geometric = net.has_geometry()
	if net.meta.has("color"):
		livery = Color.from_string(str(net.meta.color), livery)
	if not geometric:
		_unfold(start_edge)
	var lo := Vector3(INF, 0, INF); var hi := Vector3(-INF, 0, -INF)
	for id in net.graph.edges:
		var sec := Node3D.new(); add_child(sec); sectors[id] = sec
		var a := pos3(id, 0.0); var b := pos3(id, net.graph.edges[id].length)
		sector_center[id] = (a + b) * 0.5
		lo = Vector3(minf(lo.x, minf(a.x, b.x)), 0, minf(lo.z, minf(a.z, b.z)))
		hi = Vector3(maxf(hi.x, maxf(a.x, b.x)), 0, maxf(hi.z, maxf(a.z, b.z)))
		_track_ribbon(sec, id)
		if geometric: _buildings(sec, id)
	for s in net.stations:
		var t := _frame(s.edge, float(s.offset))
		_box(sectors[s.edge], t.origin + t.basis.x * 2.9 + Vector3(0, 0.4, 0) - t.basis.z * 0.0, Vector3(2.2, 0.8, 40.0), Color(0.8, 0.75, 0.6), t.basis)
	for s in net.signals:
		var t2 := _frame(s.edge, float(s.offset))
		signal_nodes.append(_box(sectors[s.edge], t2.origin - t2.basis.x * 2.0 + Vector3(0, 2.0, 0), Vector3(0.4, 1.0, 0.4), Color(0.1, 0.8, 0.2), t2.basis))
	for lane in net.meta.get("roads", []):
		var t3 := _frame(lane.edge, float(lane.edge_offset))
		_box(self, t3.origin + Vector3(0, -0.12, 0), Vector3(float(lane.length), 0.05, 7.0), Color(0.15, 0.15, 0.17), t3.basis)
		light_nodes.append(_box(self, t3.origin + t3.basis.x * 4.0 + Vector3(0, 2.0, 0) + t3.basis.z * 5.0, Vector3(0.4, 1.0, 0.4), Color(0.1, 0.8, 0.2), t3.basis))
	tram = Node3D.new(); add_child(tram)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-55, 35, 0); add_child(sun)
	var env := WorldEnvironment.new(); env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.62, 0.78, 0.92)
	env.environment.ambient_light_color = Color(0.6, 0.6, 0.65); env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	add_child(env)
	var c := (lo + hi) * 0.5; var ext := (hi - lo) + Vector3(600, 0, 600)
	_box(self, c + Vector3(0, -0.3, 0), Vector3(ext.x, 0.2, ext.z), Color(0.36, 0.48, 0.3))
	cam = Camera3D.new(); cam.far = 800.0; add_child(cam)

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
func pos3(edge_id: String, offset: float) -> Vector3:
	if geometric:
		var p: Vector2 = net.point_on(edge_id, offset).p
		return Vector3(p.x, 0.0, p.y)
	return edge_origin[edge_id] + Vector3(offset, 0, 0)

## Repère local : origine sur la voie, -Z = sens de marche.
func _frame(edge_id: String, offset: float) -> Transform3D:
	var o := pos3(edge_id, offset)
	var d := Vector3(1, 0, 0)
	if geometric:
		var v: Vector2 = net.point_on(edge_id, offset).dir
		d = Vector3(v.x, 0, v.y)
	var b := Basis.looking_at(d.normalized(), Vector3.UP)
	return Transform3D(b, o)

func _track_ribbon(parent: Node3D, id: String) -> void:
	var pts: Array[Vector3] = []
	if geometric:
		for q in net.edge_info[id].pts: pts.append(Vector3(q.x, 0.0, q.y))
	else:
		pts = [pos3(id, 0.0), pos3(id, net.graph.edges[id].length)]
	if pts.size() < 2: return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var w := 1.4
	for i in range(pts.size() - 1):
		var d := (pts[i + 1] - pts[i]).normalized()
		var n := Vector3(-d.z, 0, d.x) * w
		var a := pts[i] - n; var b := pts[i] + n; var c := pts[i + 1] + n; var e := pts[i + 1] - n
		for v in [a, b, c, a, c, e]:
			st.set_normal(Vector3.UP); st.add_vertex(v + Vector3(0, 0.02, 0))
	var mi := MeshInstance3D.new(); mi.mesh = st.commit()
	var mat := StandardMaterial3D.new(); mat.albedo_color = Color(0.33, 0.33, 0.36)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = mat
	parent.add_child(mi)
	_rails(parent, pts)

## Deux rails (écartement 1,435 m) en ruban fin, plus clairs que la plateforme.
func _rails(parent: Node3D, pts: Array[Vector3]) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for side in [-0.7175, 0.7175]:
		for i in range(pts.size() - 1):
			var d := (pts[i + 1] - pts[i]).normalized()
			var n := Vector3(-d.z, 0, d.x)
			var c0: Vector3 = pts[i] + n * side; var c1: Vector3 = pts[i + 1] + n * side
			var w := n * 0.04
			for v in [c0 - w, c0 + w, c1 + w, c0 - w, c1 + w, c1 - w]:
				st.set_normal(Vector3.UP); st.add_vertex(v + Vector3(0, 0.06, 0))
	var mi := MeshInstance3D.new(); mi.mesh = st.commit()
	var mat := StandardMaterial3D.new(); mat.albedo_color = Color(0.75, 0.75, 0.78); mat.metallic = 0.6
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = mat
	parent.add_child(mi)

## Bâtiments génériques de part et d'autre de la voie (MultiMesh par secteur, pseudo-aléatoire stable).
func _buildings(parent: Node3D, id: String) -> void:
	var L: float = net.graph.edges[id].length
	var rng := RandomNumberGenerator.new(); rng.seed = hash(id)
	var xf: Array[Transform3D] = []
	var cols: Array[Color] = []
	var s := 10.0
	while s < L - 5.0:
		var t := _frame(id, s)
		for side in [-1.0, 1.0]:
			if rng.randf() < 0.25: continue
			var h := rng.randf_range(6.0, 22.0)
			var w := rng.randf_range(10.0, 18.0)
			var dpt := rng.randf_range(10.0, 16.0)
			var off := rng.randf_range(14.0, 22.0) + dpt * 0.5
			var p: Vector3 = t.origin + t.basis.x * side * off + Vector3(0, h * 0.5, 0)
			xf.append(Transform3D(t.basis * Basis.from_scale(Vector3(dpt, h, w)), p))
			var g := rng.randf_range(0.72, 0.92)
			cols.append(Color(g, g * rng.randf_range(0.92, 1.0), g * rng.randf_range(0.82, 0.95)))
		s += rng.randf_range(16.0, 24.0)
	if xf.is_empty(): return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = BoxMesh.new()
	mm.instance_count = xf.size()
	for i in xf.size():
		mm.set_instance_transform(i, xf[i]); mm.set_instance_color(i, cols[i])
	var mmi := MultiMeshInstance3D.new(); mmi.multimesh = mm
	var mat := StandardMaterial3D.new(); mat.vertex_color_use_as_albedo = true
	mmi.material_override = mat
	parent.add_child(mmi)

func _box(parent: Node3D, pos: Vector3, size: Vector3, col: Color, basis: Basis = Basis.IDENTITY) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new(); bm.size = size
	var mat := StandardMaterial3D.new(); mat.albedo_color = col
	bm.material = mat
	mi.mesh = bm
	mi.transform = Transform3D(basis, pos)
	parent.add_child(mi)
	return mi

## Une caisse par module : chaque caisse est posée sur la voie (articulations).
func _ensure_modules(n: int) -> void:
	while modules.size() < n:
		var m := _box(tram, Vector3.ZERO, Vector3(2.4, 3.2, MODULE_LEN - 0.4), livery)
		_box(m, Vector3(0, 0.45, 0), Vector3(2.44, 1.1, MODULE_LEN - 1.2), Color(0.12, 0.16, 0.2))
		_box(m, Vector3(0, 1.75, 0), Vector3(2.0, 0.3, MODULE_LEN - 1.6), Color(0.85, 0.85, 0.85))
		modules.append(m)

func update_sectors(center: Vector3) -> int:
	var shown := 0
	for id in sectors:
		var len: float = net.graph.edges[id].length
		var vis: bool = (sector_center[id] as Vector3).distance_to(center) <= view_distance + len * 0.5
		sectors[id].visible = vis
		if vis: shown += 1
	return shown

func update_from(s: MissionSession, external: bool) -> void:
	var n := maxi(1, int(round(s.phys.profile.length_m / MODULE_LEN)))
	_ensure_modules(n)
	var seg := s.phys.profile.length_m / n
	for i in n:
		var f: Array = s.locate_behind(i * seg)
		var b: Array = s.locate_behind((i + 1) * seg)
		var pf := pos3(f[0], f[1]); var pb := pos3(b[0], b[1])
		var mid := (pf + pb) * 0.5 + Vector3(0, 1.9, 0)
		var dir := pf - pb
		if dir.length() < 0.01: dir = Vector3(1, 0, 0)
		modules[i].transform = Transform3D(Basis.looking_at(dir.normalized(), Vector3.UP), mid)
	var front := _frame(s.edge_id, s.offset)
	tram.visible = external
	var fwd := -front.basis.z
	if external:
		cam.position = front.origin - fwd * 35.0 + Vector3(0, 14, 0) + front.basis.x * 18.0
		cam.look_at(front.origin + fwd * 5.0 + Vector3(0, 1, 0))
	else:  # vue cabine
		cam.position = front.origin - fwd * 1.2 + Vector3(0, 3.0, 0)
		cam.look_at(cam.position + fwd * 30.0 + Vector3(0, -0.6, 0))
	update_sectors(front.origin)
	_update_cars(s)
	for i in signal_nodes.size():
		var c := Color(0.1, 0.8, 0.2) if s.signal_state[i] == "clear" else Color(0.9, 0.1, 0.1)
		(signal_nodes[i].mesh.material as StandardMaterial3D).albedo_color = c

func _update_cars(s: MissionSession) -> void:
	var cars := s.traffic.cars
	while car_nodes.size() < cars.size():
		car_nodes.append(_box(self, Vector3.ZERO, Vector3(1.9, 1.5, RoadTraffic.CAR_LEN), Color(0.2, 0.3, 0.9)))
	for i in car_nodes.size():
		var node := car_nodes[i]
		node.visible = i < cars.size()
		if node.visible:
			var lane: Dictionary = s.traffic.lanes[cars[i].lane]
			var t := _frame(lane.edge, float(lane.edge_offset))
			# la route croise la voie à angle droit (axe x local)
			var p := t.origin + t.basis.x * (float(cars[i].pos) - float(lane.cross_at)) + t.basis.z * 1.5 + Vector3(0, 0.8, 0)
			node.transform = Transform3D(Basis.looking_at(t.basis.x, Vector3.UP), p)
	for i in light_nodes.size():
		(light_nodes[i].mesh.material as StandardMaterial3D).albedo_color = Color(0.9, 0.1, 0.1) if s.traffic.light_red[i] else Color(0.1, 0.8, 0.2)
