class_name ElectrificationView
extends RefCounted
## Équipement visible à l'altitude des rails. Les fils de chaque branche se
## rejoignent au nœud topologique ; aucun raccord entre croisements dénivelés.
static func build(view, id: String) -> void:
	var net: NetworkLoader = view.net
	var length_: float = net.graph.edges[id].length
	var g := LineView._Geo.new()
	var wires := LineView._Geo.new()
	var count := maxi(1, ceili(length_ / 5.0))
	var last_mode := ""
	var pole_distance := 36.0
	for i in count:
		var a := length_ * i / count
		var b := length_ * (i + 1) / count
		var mode := net.supply_at(id, (a + b) * 0.5)
		var pa: Vector3 = view.pos3(id, a); var pb: Vector3 = view.pos3(id, b)
		var frame: Transform3D = view._frame(id, a)
		if mode == "aps":
			# Segments de contact séparés par les joints isolants, au centre des rails.
			var delta := (pb - pa).normalized() * 0.08
			var rail: Array[Vector3] = [pa + delta, pb - delta]
			g.ribbon(rail, 0.30, TrackView.BED_TOP_M + 0.008, Color("#383d3f"))
			g.ribbon(rail, 0.12, TrackView.APS_TOP_M, Color("#b3b8b5"))
		elif mode == "overhead":
			var wire: Array[Vector3] = [pa, pb]
			wires.ribbon(wire, 0.035, 5.45, Color("#353a3d"))
			wires.ribbon(wire, 0.025, 6.05, Color("#535757"))
			wires.box(pa.lerp(pb, 0.5) + Vector3.UP * 5.75, Vector3(0.025, 0.60, 0.025), Color("#555b5a"))
			pole_distance += b - a
			if pole_distance >= 30.0 or last_mode != mode:
				pole_distance = 0.0
				var support := pa + frame.basis.x * 3.25
				# Pas de poteau dans un tunnel ; consoles fixées à la voûte.
				if not NetworkLoader.in_spans(net.edge_info[id].tunnel, a):
					g.box(support + Vector3.UP * 3.2, Vector3(0.13, 6.4, 0.13), Color("#555d60"))
					g.box(support + Vector3.UP * 0.14, Vector3(0.42, 0.28, 0.42), Color("#aaa79a"))
				g.box_basis(pa + frame.basis.x * 1.55 + Vector3.UP * 5.9, Vector3(3.5, 0.08, 0.08), frame.basis, Color("#626966"))
				g.box(pa + Vector3.UP * 5.68, Vector3(0.045, 0.46, 0.045), Color("#363c3b"))
				g.box(pa + frame.basis.x * 2.8 + Vector3.UP * 5.9, Vector3(0.25, 0.16, 0.16), Color("#beb7a4"))
		last_mode = mode
	if not g.v.is_empty(): view._add_geo(view.sectors[id], g, Materials.building())
	if not wires.v.is_empty(): view._add_geo(view.sectors[id], wires, wire_material())

static func junctions(view) -> void:
	var net: NetworkLoader = view.net
	for node in net.graph.incident:
		var connected: Array = net.graph.incident[node]
		if connected.size() < 3: continue
		var id := str(connected[0]); var edge: TrackGraph.Edge = net.graph.edges[id]
		var offset := 0.0 if edge.from_node == node else edge.length
		if net.supply_at(id, offset) != "overhead": continue
		var frame: Transform3D = view._frame(id, offset)
		var p := frame.origin
		var g := LineView._Geo.new()
		# Portée transversale de suspension ; chaque branche garde son fil
		# de contact jusqu'au point commun (croisement / cœur d'aiguille aérien).
		var span: Array[Vector3] = [p - frame.basis.x * 4.0, p + frame.basis.x * 4.0]
		g.ribbon(span, 0.035, 6.1, Color("#40484b"))
		for side in [-1.0, 1.0]:
			if not NetworkLoader.in_spans(net.edge_info[id].tunnel, offset):
				g.box(p + frame.basis.x * side * 4.0 + Vector3.UP * 3.25, Vector3(0.14, 6.5, 0.14), Color("#515a5b"))
			g.box(p + frame.basis.x * side * 3.5 + Vector3.UP * 6.1, Vector3(0.22, 0.13, 0.13), Color("#c2bda9"))
		g.box(p + Vector3.UP * 5.8, Vector3(0.04, 0.65, 0.04), Color("#535957"))
		for branch in connected:
			var e: TrackGraph.Edge = net.graph.edges[branch]
			var at := 0.0 if e.from_node == node else e.length
			if net.supply_at(branch, at) != "overhead": continue
			var f: Transform3D = view._frame(branch, at)
			g.box_basis(p + Vector3.UP * 5.45, Vector3(0.13, 0.035, 0.65), f.basis, Color("#857b5e"))
		view._add_geo(view.sectors[id], g, Materials.building())

## Fil fin : ne pas l'inscrire dans le tampon de profondeur utilisé par les
## contours. Sinon un fil de moins d'un pixel devient une ligne de points noirs.
static func wire_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(1.0, 1.0, 1.0, 0.96)
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.roughness = 0.75
	return material
