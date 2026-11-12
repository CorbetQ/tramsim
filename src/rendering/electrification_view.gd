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
	var cuts: Array[float] = [0.0, length_]
	for i in range(1, count): cuts.append(length_ * i / count)
	for zone in net.edge_info[id].get("supply_zones", []) + net.edge_info[id].get("power_overlaps", []):
		for at in [float(zone[0]), float(zone[1])]:
			if at > 0.0 and at < length_ and not at in cuts: cuts.append(at)
	cuts.sort()
	var last_mode := ""
	var pole_distance := 36.0
	for i in cuts.size() - 1:
		var a := cuts[i]
		var b := cuts[i + 1]
		var mode := net.supply_at(id, (a + b) * 0.5)
		var modes := net.supplies_at(id, (a + b) * 0.5)
		var pa: Vector3 = view.pos3(id, a); var pb: Vector3 = view.pos3(id, b)
		var frame: Transform3D = view._frame(id, a)
		if "aps" in modes:
			# Segments de contact séparés par les joints isolants, au centre des rails.
			var delta := (pb - pa).normalized() * minf(0.08, pa.distance_to(pb) * 0.2)
			var rail: Array[Vector3] = [pa + delta, pb - delta]
			g.ribbon(rail, 0.30, TrackView.BED_TOP_M + 0.008, Color("#383d3f"))
			g.ribbon(rail, 0.12, TrackView.APS_TOP_M, Color("#b3b8b5"))
		if "overhead" in modes:
			var wire: Array[Vector3] = [pa, pb]
			wires.ribbon(wire, 0.035, 5.45, Color("#353a3d"))
			wires.ribbon(wire, 0.025, 6.05, Color("#535757"))
			wires.box(pa.lerp(pb, 0.5) + Vector3.UP * 5.75, Vector3(0.025, 0.60, 0.025), Color("#555b5a"))
			pole_distance += b - a
			if (pole_distance >= 30.0 or last_mode != mode) and not near_junction(net,id,a):
				pole_distance = 0.0
				var side:=1.0
				var support := pa + frame.basis.x * 3.25
				if not support_clear(view,support):
					side=-1.0; support=pa-frame.basis.x*3.25
				if not support_clear(view,support): continue
				# Pas de poteau dans un tunnel ; consoles fixées à la voûte.
				if not NetworkLoader.in_spans(net.edge_info[id].tunnel, a):
					g.box(support + Vector3.UP * 3.2, Vector3(0.13, 6.4, 0.13), Color("#555d60"))
					g.box(support + Vector3.UP * 0.14, Vector3(0.42, 0.28, 0.42), Color("#aaa79a"))
				g.box_basis(pa + frame.basis.x * (side*1.55) + Vector3.UP * 5.9, Vector3(3.5, 0.08, 0.08), frame.basis, Color("#626966"))
				g.box(pa + Vector3.UP * 5.68, Vector3(0.045, 0.46, 0.045), Color("#363c3b"))
				g.box(pa + frame.basis.x * (side*2.8) + Vector3.UP * 5.9, Vector3(0.25, 0.16, 0.16), Color("#beb7a4"))
		last_mode = mode
	if not g.v.is_empty(): view._add_geo(view.sectors[id], g, Materials.building())
	if not wires.v.is_empty(): view._add_geo(view.sectors[id], wires, wire_material())

static func near_junction(net: NetworkLoader,id: String,at: float) -> bool:
	var edge:TrackGraph.Edge=net.graph.edges[id]
	return (at<10.0 and net.graph.incident[edge.from_node].size()>2) or (edge.length-at<10.0 and net.graph.incident[edge.to_node].size()>2)

static var _pole_net := 0
static var _pole_cells: Dictionary = {}

static func support_clear(view,point: Vector3) -> bool:
	# Grille de recherche bornée ; une console ne peut se planter sur la voie voisine.
	var net:NetworkLoader=view.net
	if _pole_net!=net.get_instance_id():
		_pole_net=net.get_instance_id();_pole_cells.clear()
		for id in net.edge_info:
			var pts:PackedVector2Array=net.edge_info[id].pts
			for i in pts.size()-1:
				var lo:=Vector2(minf(pts[i].x,pts[i+1].x)-7.0,minf(pts[i].y,pts[i+1].y)-7.0)
				var hi:=Vector2(maxf(pts[i].x,pts[i+1].x)+7.0,maxf(pts[i].y,pts[i+1].y)+7.0)
				for x in range(floori(lo.x/16.0),floori(hi.x/16.0)+1):
					for y in range(floori(lo.y/16.0),floori(hi.y/16.0)+1):
						var key:=Vector2i(x,y)
						if not _pole_cells.has(key):_pole_cells[key]=[]
						_pole_cells[key].append([id,i])
	for item in _pole_cells.get(Vector2i(floori(point.x/16.0),floori(point.z/16.0)),[]):
		var id:String=item[0];var i:int=item[1];var info:Dictionary=net.edge_info[id];var pts:PackedVector2Array=info.pts
		var q:=Geometry2D.get_closest_point_to_segment(Vector2(point.x,point.z),pts[i],pts[i+1])
		if q.distance_to(Vector2(point.x,point.z))>7.0:continue
		var fraction:=pts[i].distance_to(q)/maxf(pts[i].distance_to(pts[i+1]),0.001)
		var at:float=lerpf(info.arc[i],info.arc[i+1],fraction)/maxf(float(info.arc[-1]),0.001)*net.graph.edges[id].length
		var rail:Vector3=view.pos3(id,at)
		if Vector2(rail.x-point.x,rail.z-point.z).length()<1.9 and absf(rail.y-point.y)<1.0:return false
	return true

static func junctions(view) -> void:
	var net: NetworkLoader = view.net
	for node in net.graph.incident:
		var connected:Array=net.graph.incident[node]
		if connected.size()<3:continue
		var endpoints:Array=[]
		for branch in connected:
			var edge:TrackGraph.Edge=net.graph.edges[branch]
			var at:=0.0 if edge.from_node==node else edge.length
			if "overhead" in net.supplies_at(branch,at):endpoints.append([branch,at,view.pos3(branch,at)])
		if endpoints.size()<2:continue
		# Grouper par niveau : aucun fil entre un pont et les voies passant dessous.
		while not endpoints.is_empty():
			var first:Array=endpoints.pop_back();var cluster:Array=[first]
			for i in range(endpoints.size()-1,-1,-1):
				if absf(endpoints[i][2].y-first[2].y)<0.75:cluster.append(endpoints.pop_at(i))
			if cluster.size()<2:continue
			var center:=Vector3.ZERO
			for item in cluster:center+=item[2]
			center/=cluster.size()
			var id:String=first[0];var frame:Transform3D=view._frame(id,first[1])
			var hardware:=LineView._Geo.new();var wires:=LineView._Geo.new()
			for item in cluster:
				if (item[2] as Vector3).distance_to(center)>0.03:
					var contact:Array[Vector3]=[item[2],center]
					wires.ribbon(contact,0.045,5.45,Color("#46494c"))
			# Suspension au-dessus des appareils de voie, poteaux en retrait.
			var span:Array[Vector3]=[center-frame.basis.x*7.0,center+frame.basis.x*7.0]
			wires.ribbon(span,0.035,6.1,Color("#555a5e"))
			for sign_ in [-1.0,1.0]:
				var foot:Vector3=center+frame.basis.x*(7.0*sign_)
				if support_clear(view,foot) and not NetworkLoader.in_spans(net.edge_info[id].tunnel,float(first[1])):
					hardware.box(foot+Vector3.UP*3.15,Vector3(0.16,6.3,0.16),Color("#566264"))
			if not hardware.v.is_empty():view._add_geo(view.sectors[id],hardware,Materials.building())
			if not wires.v.is_empty():view._add_geo(view.sectors[id],wires,wire_material())

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
