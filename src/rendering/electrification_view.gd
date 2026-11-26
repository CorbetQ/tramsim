class_name ElectrificationView
extends RefCounted
## Équipement visible à l'altitude des rails. Les fils de chaque branche se
## rejoignent au nœud topologique ; aucun raccord entre croisements dénivelés.
static func build(view, id: String) -> void:
	var net: NetworkLoader = view.net
	var length_: float = net.graph.edges[id].length
	var g := LineView._Geo.new()        # poteaux, consoles (toujours)
	var det := LineView._Geo.new()      # isolateurs, bras de rappel, semelles (LOD proche)
	var wires := Wires.new()            # fil de contact, porteur (toujours)
	var drop := Wires.new()             # pendules, haubans (LOD proche)
	var count := maxi(1, ceili(length_ / 5.0))
	var cuts: Array[float] = [0.0, length_]
	for i in range(1, count): cuts.append(length_ * i / count)
	for zone in net.edge_info[id].get("supply_zones", []) + net.edge_info[id].get("power_overlaps", []):
		for at in [float(zone[0]), float(zone[1])]:
			if at > 0.0 and at < length_ and not at in cuts: cuts.append(at)
	cuts.sort()
	var last_mode := ""
	var pole_distance := 36.0
	var span_i := 0
	var lattice := str(net.meta.get("source_id", net.meta.get("city", ""))).to_lower() in LATTICE_CITIES
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
			# Caténaire HD : fil de contact en zigzag (± 20 cm entre supports), porteur en chaînette (6,05 m aux
			# supports, flèche de 25 cm à mi-portée), pendules tous les 5 m ; lignes à largeur d'écran minimale.
			var pole_now := (pole_distance + (b - a) >= SPAN or last_mode != mode) and not near_junction(net, id, a)
			var u0 := clampf(pole_distance / SPAN, 0.0, 1.0)
			var u1 := 1.0 if pole_now else clampf((pole_distance + b - a) / SPAN, 0.0, 1.0)
			var z := 1.0 if span_i % 2 == 0 else -1.0
			var nb: Vector3 = view._frame(id, b).basis.x
			var ca := pa + frame.basis.x * (z * STAGGER * (1.0 - 2.0 * u0)) + Vector3.UP * CONTACT_H
			var cb := pb + nb * (z * STAGGER * (1.0 - 2.0 * u1)) + Vector3.UP * CONTACT_H
			var ma := pa + Vector3.UP * _messenger_h(u0); var mb := pb + Vector3.UP * _messenger_h(u1)
			wires.line(ca, cb, 0.006, Color("#4f463c"))
			wires.line(ma, mb, 0.0065, Color("#585c5c"))
			if u0 > 0.04 and u0 < 0.96: drop.line(ca, ma, 0.0025, Color("#5c605f"))
			pole_distance += b - a
			if pole_now:
				pole_distance = 0.0; span_i += 1
				var side := 1.0
				var support := pa + frame.basis.x * 3.25
				if not support_clear(view, support):
					side = -1.0; support = pa - frame.basis.x * 3.25
				if not support_clear(view, support): continue
				var x := frame.basis.x * side
				var in_tunnel := NetworkLoader.in_spans(net.edge_info[id].tunnel, a)
				var top := support + Vector3.UP * 6.9
				# Pas de poteau dans un tunnel ; consoles fixées à la voûte.
				if not in_tunnel:
					if lattice: _lattice_pole(g, support, 7.0, frame.basis, Color("#5c6466"))
					else:
						_tube(g, support, top, 0.13, 0.09, 10, Color("#59625f"))
						_tube(g, top, top + Vector3.UP * 0.06, 0.1, 0.0, 10, Color("#59625f"))
					det.box(support + Vector3.UP * 0.02, Vector3(0.5, 0.04, 0.5), Color("#4d5254"))   # platine
					det.box(support + Vector3.UP * 0.12, Vector3(0.34, 0.16, 0.34), Color("#9b9a90"))  # massif
					if last_mode != mode or i == cuts.size() - 2:   # fin de canton : hauban d'ancrage
						var foot := support + x * 3.0 - (pb - pa).normalized() * 2.0
						drop.line(top - Vector3.UP * 0.4, foot + Vector3.UP * 0.05, 0.008, Color("#6a6e6c"))
						det.box(foot + Vector3.UP * 0.05, Vector3(0.3, 0.1, 0.3), Color("#9b9a90"))
				# console : tube supérieur (porteur), tube inférieur incliné (contact), isolateurs côté poteau
				var root := support - x * 0.13
				var c_hi := root + Vector3.UP * 6.25; var c_lo := root + Vector3.UP * 5.55
				var over := pa + Vector3.UP * 6.1 + x * 0.1
				var reg := ca + x * 0.55 + Vector3.UP * 0.18
				_tube(g, c_hi, over, 0.035, 0.03, 6, Color("#7b8384"))
				_tube(g, c_lo, reg, 0.03, 0.028, 6, Color("#7b8384"))
				_tube(g, c_lo + (reg - c_lo) * 0.55, c_hi + (over - c_hi) * 0.55, 0.02, 0.02, 5, Color("#7b8384"))   # contrefiche
				_tube(det, reg, ca, 0.012, 0.012, 4, Color("#6f7677"))      # bras de rappel
				drop.line(over, ma, 0.004, Color("#5c605f"))                  # suspension du porteur
				for ins in [[c_hi, over], [c_lo, reg]]:
					var d0: Vector3 = ins[0]; var d1: Vector3 = ins[1]
					_insulator(det, d0 + (d1 - d0).normalized() * 0.18, (d1 - d0).normalized())
		last_mode = mode
	var sector: Node3D = view.sectors[id]
	if not g.v.is_empty(): view._add_geo(sector, g, Materials.building())
	if not det.v.is_empty():
		var mi: MeshInstance3D = view._add_geo(sector, det, Materials.building())
		mi.visibility_range_end = DETAIL_RANGE * (0.5 if DayNight.low_quality else 1.0)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if not wires.v.is_empty(): sector.add_child(wires.instance())
	if not drop.v.is_empty():
		var dm := drop.instance()
		dm.visibility_range_end = DETAIL_RANGE * (0.5 if DayNight.low_quality else 1.0)
		sector.add_child(dm)

const SPAN := 30.0
const STAGGER := 0.2
const CONTACT_H := 5.45
const DETAIL_RANGE := 140.0
## Réseaux à poteaux en treillis (anciennes lignes, dépôts) ; les autres : poteaux tubulaires coniques.
const LATTICE_CITIES := ["saintetienne", "lille", "marseille"]

static func _messenger_h(u: float) -> float:
	return 5.80 + 0.25 * pow(2.0 * u - 1.0, 2.0)

## Tube conique (facettes) de a vers b.
static func _tube(g: LineView._Geo, a: Vector3, b: Vector3, r0: float, r1: float, sides: int, col: Color) -> void:
	var d := (b - a).normalized()
	var x := d.cross(Vector3.FORWARD if absf(d.y) > 0.9 else Vector3.UP).normalized()
	var z := d.cross(x)
	for i in sides:
		var a0 := TAU * i / sides; var a1 := TAU * (i + 1) / sides
		var e0 := x * cos(a0) + z * sin(a0); var e1 := x * cos(a1) + z * sin(a1)
		g.quad(a + e0 * r0, b + e0 * r1, b + e1 * r1, a + e1 * r0, col)

## Isolateur composite : 4 ailettes le long de l'axe `d`.
static func _insulator(g: LineView._Geo, p: Vector3, d: Vector3) -> void:
	_tube(g, p, p + d * 0.32, 0.022, 0.022, 6, Color("#8a8f89"))
	for k in 4:
		var q := p + d * (0.05 + 0.075 * k)
		_tube(g, q, q + d * 0.02, 0.05, 0.05, 8, Color("#7d4f36"))

## Poteau en treillis : 4 cornières + croisillons (faces tournées vers la voie).
static func _lattice_pole(g: LineView._Geo, foot: Vector3, h: float, b: Basis, col: Color) -> void:
	var w := 0.16
	var corners := [b.x * w + b.z * w, b.x * w - b.z * w, -b.x * w - b.z * w, -b.x * w + b.z * w]
	for c in corners:
		g.box(foot + c + Vector3.UP * h * 0.5, Vector3(0.04, h, 0.04), col)
	var n := int(h / 0.5)
	for k in n:
		var y0 := 0.5 * k; var y1 := y0 + 0.5
		for f in 4:
			var c0: Vector3 = corners[f]; var c1: Vector3 = corners[(f + 1) % 4]
			_tube(g, foot + c0 + Vector3.UP * y0, foot + c1 + Vector3.UP * y1, 0.012, 0.012, 3, col)

## Fils : lignes tournées vers la caméra, largeur d'écran minimale (wire.gdshader) ; NORMAL = tangente,
## UV = (côté ±1, rayon en m).
class Wires:
	var v := PackedVector3Array()
	var t := PackedVector3Array()
	var c := PackedColorArray()
	var uv := PackedVector2Array()

	func line(a: Vector3, b: Vector3, r: float, col: Color) -> void:
		var d := (b - a).normalized()
		for q in [[a, -1.0], [b, -1.0], [b, 1.0], [a, -1.0], [b, 1.0], [a, 1.0]]:
			v.append(q[0]); t.append(d); c.append(col); uv.append(Vector2(q[1], r))

	func instance() -> MeshInstance3D:
		var arr := []; arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = v; arr[Mesh.ARRAY_NORMAL] = t; arr[Mesh.ARRAY_COLOR] = c; arr[Mesh.ARRAY_TEX_UV] = uv
		var m := ArrayMesh.new(); m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		var aabb := m.get_aabb(); m.custom_aabb = aabb.grow(0.5)
		var mi := MeshInstance3D.new(); mi.mesh = m; mi.material_override = ElectrificationView.line_material()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		return mi

static var _line_mat: ShaderMaterial = null
static func line_material() -> ShaderMaterial:
	if _line_mat == null:
		_line_mat = ShaderMaterial.new(); _line_mat.shader = load("res://src/rendering/shaders/wire.gdshader")
	return _line_mat

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
			var hardware:=LineView._Geo.new();var wires:=Wires.new()
			for item in cluster:
				if (item[2] as Vector3).distance_to(center)>0.03:
					wires.line(item[2]+Vector3.UP*CONTACT_H,center+Vector3.UP*CONTACT_H,0.006,Color("#4f463c"))
			# Suspension transversale au-dessus des appareils de voie (câble porteur + pendule), poteaux en retrait.
			var l:=center-frame.basis.x*7.0+Vector3.UP*6.25;var r:=center+frame.basis.x*7.0+Vector3.UP*6.25
			wires.line(l,center+Vector3.UP*6.05,0.007,Color("#585c5c"));wires.line(center+Vector3.UP*6.05,r,0.007,Color("#585c5c"))
			wires.line(center+Vector3.UP*6.05,center+Vector3.UP*CONTACT_H,0.004,Color("#5c605f"))
			for sign_ in [-1.0,1.0]:
				var foot:Vector3=center+frame.basis.x*(7.0*sign_)
				if support_clear(view,foot) and not NetworkLoader.in_spans(net.edge_info[id].tunnel,float(first[1])):
					_tube(hardware,foot,foot+Vector3.UP*6.9,0.14,0.1,10,Color("#566264"))
					hardware.box(foot+Vector3.UP*0.12,Vector3(0.36,0.16,0.36),Color("#9b9a90"))
					_insulator(hardware,foot+Vector3.UP*6.25-frame.basis.x*(0.4*sign_),-frame.basis.x*sign_)
			if not hardware.v.is_empty():view._add_geo(view.sectors[id],hardware,Materials.building())
			if not wires.v.is_empty():view.sectors[id].add_child(wires.instance())

## Fil fin : ne pas l'inscrire dans le tampon de profondeur utilisé par les
## contours. Sinon un fil de moins d'un pixel devient une ligne de points noirs.
static func wire_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true; material.vertex_color_is_srgb = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(1.0, 1.0, 1.0, 0.96)
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.roughness = 0.75
	return material
