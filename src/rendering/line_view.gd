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
var signal_view: SignalView          # signalisation tramway (SignalModel) au bord de la voie
var ai_view := AiTramView.new()      # rames IA du mode mission
var _cab_fwd := Vector3.ZERO         # cap lissé de la caméra cabine
var sectors: Dictionary = {}       # edge id -> Node3D (affiché/masqué selon la distance)
var sector_bounds: Dictionary = {} # emprise complète, y compris les arêtes courbes
var tunnel_lights: Array[OmniLight3D] = []
var sector_center: Dictionary = {} # edge id -> Vector3
var view_distance := 400.0
var car_nodes: Array[MeshInstance3D] = []
var light_nodes: Array[MeshInstance3D] = []
var authored_stations := true
var station_identity: StationIdentityView
var city: CityScene
var day_night: DayNight
var headlight: SpotLight3D
var livery: Dictionary = {}
var family := ""
var speed_material: ShaderMaterial
var orbit := 0.0                   # rotation de la caméra extérieure (glisser au doigt)
var cam_dist := 40.0               # distance de la caméra extérieure (molette / pincement)
var top_view := false              # caméra vue du dessus (suit la rame, nez vers le haut de l'écran)
var top_height := 140.0            # hauteur de la vue du dessus (molette / pincement / boutons ±)
const TOP_MIN := 35.0
const TOP_MAX := 900.0
var _top_fwd := Vector3.ZERO
var _tram_len := 0.0
var _rig_fresh := false
# --- rames HD / cabine (P2) : état piloté par main.gd
var cab_data: Dictionary = {}       # écrans et voyants de la cabine (vitesse, cran, prochain arrêt, signal…)
var rain := 0.0                     # pluie (WeatherState) : essuie-glace automatique
var wiper_forced := false
var headlights_full := false
var mirrors_folded := false
var hd_lod := -1                    # LOD HD de la rame du joueur (-1 : vue cabine / pas de HD)
var external_view := true            # dernière vue demandée (WeatherView : pare-brise en cabine)
var speed_mps := 0.0
var night_lights: NightLights        # éclairage urbain dynamique de nuit (lot P4)

func build(network: NetworkLoader, start_edge: String, vehicle: VehicleProfile = null, prepared_city: CityScene = null) -> void:
	net = network
	StationShelters.reset()
	var fx_layer := CanvasLayer.new(); fx_layer.layer = -1; add_child(fx_layer)
	var fx := ColorRect.new(); fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fx.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); fx_layer.add_child(fx)
	speed_material = ShaderMaterial.new(); speed_material.shader = load("res://src/rendering/shaders/speed.gdshader"); fx.material = speed_material
	geometric = net.has_geometry()
	livery = TramModel.livery_for(net.meta, tram_entry(vehicle))
	family = livery.family
	if not geometric:
		_unfold(start_edge)
	day_night = DayNight.new(); add_child(day_night); day_night.setup(self)
	var src := str(net.meta.get("source_id", ""))
	if prepared_city != null and (not geometric or prepared_city.city != src):
		prepared_city.free(); prepared_city = null
	if geometric and net.meta.has("origin") and CityScene.available(src):
		city = prepared_city if prepared_city != null else CityScene.new()
		if prepared_city != null or city.open(src, net.meta.origin):
			city.radius = maxf(view_distance + 200.0, 500.0)
			add_child(city)
			city.bind_network(net)
		else:
			city.free(); city = null
	if geometric and authored_stations:
		station_identity = StationIdentityView.new(); add_child(station_identity); station_identity.setup(self, src)
	if geometric:   # types de stations, entraxe élargi au droit des quais centraux, quais
		layout = StationLayout.new(self)
		layout.load_city(src, net.meta.get("origin", [0, 0]))
		layout.build(net.stations, vehicle.length_m if vehicle != null else 32.0)
	var lo := Vector3(INF, 0, INF); var hi := Vector3(-INF, 0, -INF)
	for id in net.graph.edges:
		var sec := Node3D.new(); add_child(sec); sectors[id] = sec
		var a := pos3(id, 0.0); var b := pos3(id, net.graph.edges[id].length)
		sector_center[id] = (a + b) * 0.5
		var bounds := AABB(a, Vector3.ZERO).expand(b)
		if geometric:
			var info: Dictionary = net.edge_info[id]
			for i in info.pts.size():
				bounds = bounds.expand(Vector3(info.pts[i].x, info.ys[i] if i < info.ys.size() else 0.0, info.pts[i].y))
		sector_bounds[id] = bounds.grow(12.0)
		lo = Vector3(minf(lo.x, minf(a.x, b.x)), 0, minf(lo.z, minf(a.z, b.z)))
		hi = Vector3(maxf(hi.x, maxf(a.x, b.x)), 0, maxf(hi.z, maxf(a.z, b.z)))
		_track(sec, id)
		if geometric: ElectrificationView.build(self, id)
		if geometric and city == null: _generic_buildings(sec, id)
	if layout != null:
		for pf in layout.platforms: _platform(sectors[net.stations[pf.station].edge], pf)
	else:
		for s in net.stations: _station(sectors[s.edge], s)
	if geometric: ElectrificationView.junctions(self)
	_depot_buildings()
	_real_platforms()
	if station_identity: station_identity.build_sites()
	if geometric: LandmarkModels.attach(self)   # modèles dédiés (P1) : Ralliement, cathédrale, trémie
	_crossovers()
	for s in net.signals:
		var t2 := _frame(s.edge, float(s.offset))
		_post(sectors[s.edge], t2.origin - t2.basis.x * 2.2, 3.2)
		signal_nodes.append(_lamp(sectors[s.edge], t2.origin - t2.basis.x * 2.2 + Vector3(0, 3.0, 0), Color(0.1, 0.9, 0.3)))
	signal_view = SignalView.new(); signal_view.build(self, SignalModel.of(net))
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
	var gy := (city.min_height - 2.0) if city != null and city.has_terrain else -0.3
	ground.box(Vector3(0, gy, 0), Vector3(ext.x, 0.2, ext.z), Color("#97b46f"))
	_add_geo(self, ground, Materials.building(), Transform3D(Basis.IDENTITY, c))
	# near 0,2 m (et non 0,05) : précision de profondeur ×4 sur les couches de sol lointaines
	cam = Camera3D.new(); cam.far = 1600.0; cam.near = 0.2; cam.fov = 62.0; add_child(cam)
	headlight = SpotLight3D.new()
	headlight.spot_range = 70.0; headlight.spot_angle = 28.0; headlight.light_energy = 6.0
	headlight.light_color = Color(1.0, 0.95, 0.85)
	add_child(headlight)
	# Quatre lampes proches de la rame, sans ombres : éclairage lisible à coût borné.
	for i in 4:
		var light := OmniLight3D.new(); light.omni_range = 22.0; light.light_energy = 2.2
		light.light_color = Color("#ffe7c3"); light.shadow_enabled = false; light.visible = false
		add_child(light); tunnel_lights.append(light)
	night_lights = NightLights.new(); add_child(night_lights); night_lights.setup(self)

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
const WIDEN_RAMP := 35.0     # m : transition d'entraxe de part et d'autre d'un quai central
var widen: Dictionary = {}   # edge id -> [[o_bas, o_haut, élargissement, distance en o_haut, rampe, longueur pleine]]
var layout: StationLayout

func pos3(edge_id: String, offset: float) -> Vector3:
	if geometric:
		var q: Dictionary = net.point_on(edge_id, offset)
		var p: Vector2 = q.p
		var d: Vector2 = q.dir
		var y: float = q.y
		if net.edge_info[edge_id].raw or net.edge_info[edge_id].get("physical", false):  # géométrie déjà sur l'axe de la voie (communications de voies)
			return Vector3(p.x, y, p.y)
		var o := lateral(edge_id, offset)
		return Vector3(p.x - d.y * o, y, p.y + d.x * o)
	return edge_origin[edge_id] + Vector3(offset, 0, 0)

## Décalage de la voie à droite de l'axe commun : demi-entraxe, élargi progressivement au droit des quais centraux.
func lateral(edge_id: String, offset: float) -> float:
	if net.edge_info[edge_id].get("physical", false): return 0.0
	var o := TRACK_OFFSET
	for w in widen.get(edge_id, []):
		if offset < float(w[0]) - 0.01 or offset > float(w[1]) + 0.01: continue
		var d: float = float(w[3]) + float(w[1]) - offset
		var r: float = w[4]
		var t := clampf(minf(d, r * 2.0 + float(w[5]) - d) / r, 0.0, 1.0)
		if t > 0.0: o = maxf(o, TRACK_OFFSET + float(w[2]) * smoothstep(0.0, 1.0, t))
	return o

## Altitude du sol sous un point (relief IGN si disponible).
func ground_at(p: Vector3) -> float:
	return city.height_at(p) if city != null and city.has_terrain else 0.0

## Repère local : origine sur la voie, -Z = sens de marche, X = droite.
func _frame(edge_id: String, offset: float) -> Transform3D:
	var o := pos3(edge_id, offset)
	var d := Vector3(1, 0, 0)
	if geometric:
		var v: Vector2 = net.point_on(edge_id, offset).dir
		d = Vector3(v.x, 0, v.y)
	return Transform3D(Basis.looking_at(d.normalized(), Vector3.UP), o)

## Plateforme (nature réelle par tronçon si la scène IGN la fournit), longrines ou rails noyés ; rubans en onglet.
func _track(parent: Node3D, id: String) -> void:
	var pts: Array = []
	var info: Dictionary = net.edge_info[id] if geometric else {}
	var o := TRACK_OFFSET if geometric and not info.raw and not info.get("physical", false) else 0.0
	if geometric and widen.has(id):   # entraxe variable : voie échantillonnée déjà décalée
		var L: float = net.graph.edges[id].length
		var n := maxi(2, ceili(L / 4.0) + 1)
		for i in n: pts.append(pos3(id, L * i / (n - 1)))
		o = 0.0
	elif geometric:
		var ys: PackedFloat32Array = info.get("ys", PackedFloat32Array())
		var pl: PackedVector2Array = info.pts
		for i in pl.size(): pts.append(Vector3(pl[i].x, ys[i] if ys.size() == pl.size() else 0.0, pl[i].y))
	else:
		pts = [pos3(id, 0.0), pos3(id, net.graph.edges[id].length)]
	if pts.size() < 2: return
	var g := _Geo.new()
	var fallback := _bed_color(id)
	var paved := Color("#a49a8c") if city != null and city.style.get("trees", [0])[0] == 6 else Color("#9a958d")
	var nature := func(p: Vector3) -> int:
		if station_identity and station_identity.depot_track_at(id, p): return TrackView.BED_PAVED
		return city.track_nature_at(p) if city != null else TrackView.BED_UNKNOWN
	if geometric and not info.get("tunnel", []).is_empty():
		# L'orthophoto montre la surface au-dessus du tunnel : elle ne décrit pas son radier.
		for span_ in info.tunnel:
			if float(span_[0]) < 0.5 and float(span_[1]) > net.graph.edges[id].length - 0.5:
				nature = func(_p): return TrackView.BED_PAVED
				fallback = Color("#686c73"); paved = fallback; break
	# pas de talus de plateforme sur les ponts et en tunnel : points de ces ouvrages tous les 2 m
	var works := PackedVector3Array()
	if geometric:
		var Lw: float = net.graph.edges[id].length
		for sp in info.get("bridge", []) + info.get("tunnel", []):
			var s0 := maxf(0.0, float(sp[0])); var s1 := minf(Lw, float(sp[1]))
			var nn := maxi(1, ceili((s1 - s0) / 2.0))
			for k in nn + 1: works.append(pos3(id, s0 + (s1 - s0) * k / nn))
	var no_skirt := func(p: Vector3) -> bool:
		for w in works:
			if absf(w.x - p.x) < 1.5 and absf(w.z - p.z) < 1.5 and absf(w.y - p.y) < 3.0: return true
		return false
	var near := TrackView.NearSink.new(func(): var ng := _Geo.new(); ng.all_faces = true; return ng)
	TrackView.build(g, pts, o, nature, fallback, paved, float(info.get("gauge_mm", 1435)) / 1000.0, no_skirt if not works.is_empty() else Callable(), ground_at if city != null and city.has_terrain else Callable(), near)
	if geometric: _structures(g, id)
	_add_geo(parent, g, Materials.building())
	for ng in near.cells.values():   # profil Ri60 (LOD proche, refonte P1)
		var mn := _add_geo(parent, ng, Materials.building())
		mn.name = "rail_ri60"; mn.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mn.visibility_range_end = TrackView.detail_range(); mn.visibility_range_end_margin = 10.0

## Ouvrages d'une voie (intervalles calculés par tools/import/terrain.py) : pont (dalle, garde-corps, piles),
## tunnel (tube, portails), trémie (murs de soutènement).
func _structures(g: _Geo, id: String) -> void:
	var info: Dictionary = net.edge_info[id]
	if info.raw: return
	var L: float = net.graph.edges[id].length
	var concrete := Color("#b9b3a7")
	var inner := -2.6 if info.get("physical", false) else -lateral(id, 0.0) - 0.05   # axe commun (moitié de l'ouvrage côté voie opposée)
	for sp in info.get("bridge", []):
		var a := clampf(float(sp[0]), 0.0, L); var b := clampf(float(sp[1]), 0.0, L)
		var n := maxi(1, ceili((b - a) / 5.0))
		for i in n:
			var f0 := _frame(id, a + (b - a) * i / n); var f1 := _frame(id, a + (b - a) * (i + 1) / n)
			# voie portée par le tablier unique de l'ouvrage (CityScene) : pas de dalle ni de garde-corps propres
			if city != null and city.deck_carries(f0.interpolate_with(f1, 0.5).origin, net.point_on(id, a + (b - a) * (i + 0.5) / n).dir): continue
			var p := func(f: Transform3D, x: float, y: float) -> Vector3: return f.origin + f.basis.x * x + Vector3(0, y, 0)
			g.quad(p.call(f0, 2.9, 0.05), p.call(f1, 2.9, 0.05), p.call(f1, 2.9, -1.1), p.call(f0, 2.9, -1.1), concrete)
			g.quad(p.call(f0, inner, -1.1), p.call(f0, 2.9, -1.1), p.call(f1, 2.9, -1.1), p.call(f1, inner, -1.1), concrete.darkened(0.25))
			g.quad(p.call(f0, 1.75, 0.04), p.call(f1, 1.75, 0.04), p.call(f1, 2.9, 0.04), p.call(f0, 2.9, 0.04), Color("#8b8d90"))
			# corniche en saillie, bordure basse et garde-corps métallique (lisses et montants)
			var sides_: Array = []
			if info.get("structure_right", true): sides_.append([2.8, 1.0])
			if info.get("physical", false) and info.get("structure_left", true): sides_.append([inner, -1.0])
			for sd in sides_:
				var x: float = sd[0]; var o_: float = sd[1]
				g.quad(p.call(f0, x + o_ * 0.22, -0.45), p.call(f1, x + o_ * 0.22, -0.45), p.call(f1, x + o_ * 0.22, 0.32), p.call(f0, x + o_ * 0.22, 0.32), Color("#d9d3c6"))
				g.quad(p.call(f0, x - o_ * 0.1, 0.32), p.call(f1, x - o_ * 0.1, 0.32), p.call(f1, x + o_ * 0.22, 0.32), p.call(f0, x + o_ * 0.22, 0.32), Color("#e2ddd2"))
				g.quad(p.call(f0, x + o_ * 0.22, -0.45), p.call(f1, x + o_ * 0.22, -0.45), p.call(f1, x - o_ * 0.05, -0.62), p.call(f0, x - o_ * 0.05, -0.62), Color("#a9a396"))
				g.quad(p.call(f0, x - o_ * 0.1, 0.05), p.call(f1, x - o_ * 0.1, 0.05), p.call(f1, x - o_ * 0.1, 0.32), p.call(f0, x - o_ * 0.1, 0.32), Color("#d6d1c6"))
				for yy in [0.62, 1.08]:
					g.quad(p.call(f0, x, yy), p.call(f1, x, yy), p.call(f1, x, yy + 0.06), p.call(f0, x, yy + 0.06), Color("#4f5a61"))
				for u in [0.0, 0.5]:
					var fm := f0.interpolate_with(f1, u)
					g.box_basis(p.call(fm, x, 0.72), Vector3(0.05, 0.8, 0.05), fm.basis, Color("#4f5a61"))
		var s := a + 14.0
		while s < b - 6.0:
			var f := _frame(id, s)
			var top := f.origin + f.basis.x * 1.0
			var gh := ground_at(top)
			if top.y - gh > 2.5 and not (city != null and city.deck_carries(f.origin, net.point_on(id, s).dir)):
				# pile-voile sous l'axe de l'ouvrage et chevêtre sur toute la largeur
				var mid_x := (inner + 2.9) * 0.5
				var span_x := 2.9 - inner
				var c3 := f.origin + f.basis.x * mid_x
				var hgt := top.y - 1.1 - gh + 1.5 - 0.7
				g.box_basis(Vector3(c3.x, gh - 1.5 + hgt * 0.5, c3.z), Vector3(maxf(1.4, span_x * 0.55), hgt, 1.1), f.basis, concrete.darkened(0.1))
				g.box_basis(Vector3(c3.x, top.y - 1.1 - 0.35, c3.z), Vector3(span_x - 0.2, 0.7, 1.5), f.basis, concrete.darkened(0.04))
			s += 30.0
	for sp in info.get("tunnel", []):
		if LandmarkModels.covers_tunnel(self, id, sp): continue   # trémie modélisée (assets/models)
		var a := clampf(float(sp[0]), 0.0, L); var b := clampf(float(sp[1]), 0.0, L)
		var n := maxi(1, ceili((b - a) / 6.0))
		var wall := Color("#5d5a55")
		for i in n:
			var f0 := _frame(id, a + (b - a) * i / n); var f1 := _frame(id, a + (b - a) * (i + 1) / n)
			var p := func(f: Transform3D, x: float, y: float) -> Vector3: return f.origin + f.basis.x * x + Vector3(0, y, 0)
			if info.get("structure_right", true):
				g.quad(p.call(f0, 2.6, -0.1), p.call(f1, 2.6, -0.1), p.call(f1, 2.6, 4.8), p.call(f0, 2.6, 4.8), wall)
			if info.get("physical", false) and info.get("structure_left", true):
				g.quad(p.call(f0, inner, -0.1), p.call(f0, inner, 4.8), p.call(f1, inner, 4.8), p.call(f1, inner, -0.1), wall)
			g.quad(p.call(f0, inner, 4.8), p.call(f0, 2.6, 4.8), p.call(f1, 2.6, 4.8), p.call(f1, inner, 4.8), wall.darkened(0.3))
			if i % 3 == 0:   # éclairage de tunnel
				g.box_basis(p.call(f0, 2.45, 4.0), Vector3(0.12, 0.12, 1.2), f0.basis, Color(1.0, 0.9, 0.7, 0.1))
		for s in [a, b]:   # portails (si le tunnel débouche sur cette arête)
			if (s == a and a <= 0.5) or (s == b and b >= L - 0.5): continue
			var f := _frame(id, s)
			var top := ground_at(f.origin) - f.origin.y + 0.6
			if top < 5.6: continue
			var p := func(x: float, y: float) -> Vector3: return f.origin + f.basis.x * x + Vector3(0, y, 0)
			g.quad(p.call(inner, 4.8), p.call(3.6, 4.8), p.call(3.6, top), p.call(inner, top), concrete)
			g.quad(p.call(2.6, -0.1), p.call(3.6, -0.1), p.call(3.6, 4.8), p.call(2.6, 4.8), concrete)
			# cadre du portail (linteau et piédroit en saillie) et couronnement
			var fz := f.basis.z * (0.12 if s == a else -0.12)
			g.quad(p.call(inner, 4.75) + fz, p.call(2.75, 4.75) + fz, p.call(2.75, 5.5) + fz, p.call(inner, 5.5) + fz, concrete.lightened(0.12))
			g.quad(p.call(2.6, -0.1) + fz, p.call(2.95, -0.1) + fz, p.call(2.95, 5.5) + fz, p.call(2.6, 5.5) + fz, concrete.lightened(0.12))
			g.quad(p.call(inner, top) + fz, p.call(3.6, top) + fz, p.call(3.6, top + 0.25) + fz, p.call(inner, top + 0.25) + fz, concrete.lightened(0.2))
	for sp in info.get("trench", []):
		var a := clampf(float(sp[0]), 0.0, L); var b := clampf(float(sp[1]), 0.0, L)
		var n := maxi(1, ceili((b - a) / 6.0))
		for i in n:
			var u0 := float(i) / n; var u1 := float(i + 1) / n
			var f0 := _frame(id, lerpf(a, b, u0)); var f1 := _frame(id, lerpf(a, b, u1))
			var h0 := lerpf(float(sp[2]), float(sp[3]), u0) + 0.4; var h1 := lerpf(float(sp[2]), float(sp[3]), u1) + 0.4
			var p := func(f: Transform3D, x: float, y: float) -> Vector3: return f.origin + f.basis.x * x + Vector3(0, y, 0)
			g.quad(p.call(f0, 2.6, -0.1), p.call(f1, 2.6, -0.1), p.call(f1, 2.6, h1), p.call(f0, 2.6, h0), concrete)
			g.quad(p.call(f0, 2.6, h0), p.call(f1, 2.6, h1), p.call(f1, 2.9, h1), p.call(f0, 2.9, h0), concrete.lightened(0.15))
			if h0 > 1.2 and h1 > 1.2:   # couronnement débordant et garde-corps en tête de mur
				g.quad(p.call(f0, 2.5, h0 - 0.18), p.call(f1, 2.5, h1 - 0.18), p.call(f1, 2.5, h1 + 0.05), p.call(f0, 2.5, h0 + 0.05), concrete.lightened(0.1))
				g.quad(p.call(f0, 2.5, h0 + 0.05), p.call(f1, 2.5, h1 + 0.05), p.call(f1, 3.0, h1 + 0.05), p.call(f0, 3.0, h0 + 0.05), concrete.lightened(0.2))
				g.quad(p.call(f0, 2.8, h0 + 1.0), p.call(f1, 2.8, h1 + 1.0), p.call(f1, 2.8, h1 + 1.06), p.call(f0, 2.8, h0 + 1.06), Color("#4f5a61"))
				g.box_basis(p.call(f0, 2.8, h0 + 0.55), Vector3(0.05, 1.0, 0.05), f0.basis, Color("#4f5a61"))

## Bâtiments de remisage IGN : les passages suivent les voies réellement cartographiées.
func _depot_buildings() -> void:
	var seen := {}
	for depot in net.meta.get("depots", []):
		if not sectors.has(depot.edge): continue
		for building in depot.get("buildings", []):
			if station_identity and station_identity.build_depot_building(sectors[depot.edge], depot, building): continue
			if seen.has(building.source_id): continue
			seen[building.source_id] = true
			var polygon := PackedVector2Array()
			for p in building.pts: polygon.append(Vector2(float(p[0]), float(p[1])))
			if city: city.replace_hangar(polygon)
			var base := float(building.base_y); var height_ := float(building.height_m)
			var g := _Geo.new(); var roof := Color("#687b89"); var wall := Color("#b7bdba")
			var indices := Geometry2D.triangulate_polygon(polygon)
			for i in range(0, indices.size(), 3):
				var a: Vector2 = polygon[indices[i]]; var b: Vector2 = polygon[indices[i + 1]]; var c: Vector2 = polygon[indices[i + 2]]
				g.tri(Vector3(a.x, base + height_, a.y), Vector3(b.x, base + height_, b.y), Vector3(c.x, base + height_, c.y), roof)
			var portals := TrackView.KeepOut.new()
			for id in building.portal_tracks:
				if net.edge_info.has(id): portals.add_polyline(net.edge_info[id].pts, 1.9)
			for i in polygon.size():
				var a := polygon[i]; var b := polygon[(i + 1) % polygon.size()]
				var count_ := maxi(1, ceili(a.distance_to(b)))
				for j in count_:
					var p := a.lerp(b, float(j) / count_); var q := a.lerp(b, float(j + 1) / count_)
					var bottom := base + minf(4.5, height_ - 0.2) if portals.blocked((p + q) * 0.5) else base
					g.quad(Vector3(p.x, bottom, p.y), Vector3(q.x, bottom, q.y), Vector3(q.x, base + height_, q.y), Vector3(p.x, base + height_, p.y), wall)
			_add_geo(sectors[depot.edge], g, Materials.building())

## Quais cartographiés OSM : l'emprise réelle remplace l'implantation estimée GTFS.
func _real_platforms() -> void:
	for platform in net.meta.get("platforms", []):
		if station_identity and station_identity.build_platform(platform): continue
		if not sectors.has(platform.edge): continue
		var poly := PackedVector2Array(); var top: Array[Vector3] = []
		var h := float(platform.get("height_m", 0.3))
		for i in platform.pts.size():
			var p: Array = platform.pts[i]; poly.append(Vector2(float(p[0]), float(p[1])))
			top.append(Vector3(float(p[0]), float(platform.y[i]) + h, float(p[1])))
		var triangles := Geometry2D.triangulate_polygon(poly)
		var g := _Geo.new(); var color_ := Color("#c9c4b6")
		for i in range(0, triangles.size(), 3): g.tri(top[triangles[i]], top[triangles[i + 1]], top[triangles[i + 2]], color_)
		for i in top.size():
			var j := (i + 1) % top.size()
			g.quad(top[i] - Vector3(0, h, 0), top[j] - Vector3(0, h, 0), top[j], top[i], color_.darkened(0.18))
			if city: city.add_keepout(poly[i], poly[j], 0.5)
		# Le plus long bord fournit l'orientation du mobilier, pas l'axe GTFS.
		var longest := 0.0; var tangent := Vector3.FORWARD; var center := Vector3.ZERO
		for i in top.size():
			center += top[i]
			var delta := top[(i + 1) % top.size()] - top[i]
			if delta.length() > longest: longest = delta.length(); tangent = delta.normalized()
		center /= maxf(1.0, top.size())
		if not Geometry2D.is_point_in_polygon(Vector2(center.x, center.z), poly): center = top[triangles[0]].lerp(top[triangles[1]], 0.5).lerp(top[triangles[2]], 0.33) if triangles.size() >= 3 else top[0]
		var basis := Basis.looking_at(tangent, Vector3.UP)
		# Liseré tactile sur le bord le plus proche du rail.
		for i in top.size():
			var j := (i + 1) % top.size()
			var mid := top[i].lerp(top[j], 0.5)
			var inset := (center - mid).normalized() * 0.15
			var edge_: Array[Vector3] = [top[i] + inset, top[j] + inset]
			g.ribbon(edge_, 0.10, 0.012, Color("#eee6c9"))
		if platform.get("shelter", false) and longest > 8.0:
			# abri du réseau (P4) centré sur le quai OSM, ouvert côté voie (bord le plus proche du rail)
			var st := shelter_style()
			var across := basis.x
			var ep: PackedVector2Array = net.edge_info.get(str(platform.edge), {}).get("pts", PackedVector2Array())
			if ep.size() >= 2:
				var q := Vector2.ZERO
				var best := INF
				for k in range(1, ep.size()):
					var c2 := Geometry2D.get_closest_point_to_segment(Vector2(center.x, center.z), ep[k - 1], ep[k])
					if c2.distance_to(Vector2(center.x, center.z)) < best: best = c2.distance_to(Vector2(center.x, center.z)); q = c2
				var away := Vector3(center.x - q.x, 0, center.z - q.y)
				if away.dot(across) < 0.0: across = -across
			StationShelters.build(sectors[platform.edge], g, center - across * float(st.depth) * 0.5, across, basis.z, st, str(platform.get("name", "")), str(net.meta.get("line", "")), shelter_termini(), float(st.depth))
		_add_geo(sectors[platform.edge], g, Materials.building())
		_platform_people(platform, sectors[platform.edge])

## Style d'abri du réseau (StationShelters, par source_id) et terminus affichés par les PID.
var _shelter_style: Dictionary = {}
func shelter_style() -> Dictionary:
	if _shelter_style.is_empty(): _shelter_style = StationShelters.style(str(net.meta.get("source_id", "")))
	return _shelter_style

func shelter_termini() -> Array:
	if net.stations.is_empty(): return []
	return [str(net.stations[net.stations.size() - 1].name), str(net.stations[0].name)]

func _platform_people(platform: Dictionary, parent: Node3D, include_info := true) -> void:
	var poly := PackedVector2Array(); var top: Array[Vector3] = []; var center := Vector3.ZERO
	var tangent := Vector3.FORWARD; var longest := 0.0
	for i in platform.pts.size():
		var q := Vector3(platform.pts[i][0], float(platform.y[i]) + float(platform.get("height_m", .3)), platform.pts[i][1])
		poly.append(Vector2(q.x, q.z)); top.append(q); center += q
	center /= maxf(1.0, top.size())
	var triangles := Geometry2D.triangulate_polygon(poly)
	for i in top.size():
		var d := top[(i + 1) % top.size()] - top[i]
		if d.length() > longest: longest = d.length(); tangent = d.normalized()
	var basis := Basis.looking_at(tangent, Vector3.UP)
	# voyageurs en attente (instances) et poteau d'information, hors abri
	var rng := RandomNumberGenerator.new(); rng.seed = hash(str(platform.get("id", center)))
	var peds: Array = []; var pcols: Array = []
	var want := rng.randi_range(1, 3) if DayNight.low_quality else rng.randi_range(2, 7)
	for k in want * 3:
		if peds.size() >= want or triangles.size() < 3: break
		var t0 := rng.randi_range(0, triangles.size() / 3 - 1) * 3
		var r1 := sqrt(rng.randf()); var r2 := rng.randf()
		var q: Vector3 = top[triangles[t0]] * (1.0 - r1) + top[triangles[t0 + 1]] * (r1 * (1.0 - r2)) + top[triangles[t0 + 2]] * (r1 * r2)
		if Vector2(q.x - center.x, q.z - center.z).length() < 3.5: continue
		if absf((q - center).dot(tangent)) > longest * 0.5 - 7.0: continue   # extrémités (vue cabine) dégagées
		var edge_d := INF
		for i in poly.size():
			edge_d = minf(edge_d, Vector2(q.x, q.z).distance_to(Geometry2D.get_closest_point_to_segment(Vector2(q.x, q.z), poly[i], poly[(i + 1) % poly.size()])))
		if edge_d < 0.9: continue
		var b3 := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.92, 1.06))
		peds.append(Transform3D(b3, q)); pcols.append(StreetProps.clothes_color(rng))
	if not peds.is_empty(): parent.add_child(StreetProps.instances(StreetProps.PED if rng.randf() < 0.5 else StreetProps.PED_B, peds, pcols))
	if include_info and longest > 10.0:
		var ip := center + tangent * minf(5.0, longest * 0.3)
		if Geometry2D.is_point_in_polygon(Vector2(ip.x, ip.z), poly):
			parent.add_child(StreetProps.instances(StreetProps.INFO, [Transform3D(basis, ip)]))

## Plateforme par défaut (sans analyse d'orthophoto) : engazonnée en périphérie, pavée ou en enrobé
## dans les quartiers denses (densité de bâti IGN).
func _bed_color(id: String) -> Color:
	if city == null: return TrackView.GRASS
	var mid := pos3(id, net.graph.edges[id].length * 0.5)
	var dens := city.density_at(mid)
	if dens > 170: return Color("#a49a8c") if city.style.get("trees", [0])[0] == 6 else Color("#8f8a84")
	if dens > 110: return TrackView.ASPHALT
	return TrackView.GRASS

## Communications de voies (croisement en ciseaux) avant le quai des arrêts de retournement.
func _crossovers() -> void:
	if net.meta.get("geometry_kind", "") == "physical": return
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
	if city != null:  # quai, abri et totem : interdits aux arbres et lampadaires du décor
		var qa := t * Vector3(3.2, 0, zc - L * 0.5); var qb := t * Vector3(3.2, 0, zc + L * 0.5)
		city.add_keepout(Vector2(qa.x, qa.z), Vector2(qb.x, qb.z), 2.4)
	var lbl := Label3D.new()
	lbl.text = str(s.name)
	lbl.font_size = 64; lbl.pixel_size = 0.006
	lbl.outline_size = 12
	lbl.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	lbl.position = t * Vector3(3.5, 3.15, zc + 6.5)
	parent.add_child(lbl)

## Quai (StationLayout) : prisme suivant la voie, bordure blanche, rampe d'accès, abri, banc, totem et mobilier.
func _platform(parent: Node3D, pf: Dictionary) -> void:
	var inn: PackedVector3Array = pf.inner; var out: PackedVector3Array = pf.outer
	var n := inn.size()
	var g := _Geo.new()
	var top := Vector3(0, StationLayout.HEIGHT, 0); var bot := Vector3(0, -0.15, 0)
	var slab := Color("#d9d4c8"); var edge := Color("#f2f2ee")
	var lft: bool = pf.side == "left"
	for i in n - 1:
		var a := inn[i]; var b := inn[i + 1]; var c := out[i + 1]; var d := out[i]
		g.quad(a + top, b + top, c + top, d + top, slab)
		g.quad(a + bot, b + bot, b + top, a + top, slab.darkened(0.12))
		g.quad(d + top, c + top, c + bot, d + bot, slab.darkened(0.12))
		var ea := a.lerp(d, 0.25 / maxf(a.distance_to(d), 0.3)); var eb := b.lerp(c, 0.25 / maxf(b.distance_to(c), 0.3))
		g.quad(a + top + Vector3(0, 0.01, 0), b + top + Vector3(0, 0.01, 0), eb + top + Vector3(0, 0.01, 0), ea + top + Vector3(0, 0.01, 0), edge)
	g.quad(inn[0] + bot, out[0] + bot, out[0] + top, inn[0] + top, slab.darkened(0.12))
	# rampe d'accès à l'arrière du quai (pente 1/12)
	var tail := (inn[n - 1] - inn[n - 2]).normalized()
	var ra := inn[n - 1].lerp(out[n - 1], 0.15); var rb := inn[n - 1].lerp(out[n - 1], 0.85)
	g.quad(ra + top, rb + top, rb + tail * 3.6 + Vector3(0, -0.05, 0), ra + tail * 3.6 + Vector3(0, -0.05, 0), slab.darkened(0.05))
	# mobilier au milieu du quai
	var m := n / 2
	var t := (inn[mini(m + 1, n - 1)] - inn[maxi(m - 1, 0)]); t.y = 0.0; t = t.normalized()
	var o := out[m] - inn[m]; var w := Vector2(o.x, o.z).length(); o.y = 0.0; o = o.normalized()
	var basis := Basis(o, Vector3.UP, t)
	var y := inn[m].y + StationLayout.HEIGHT
	var at := func(x: float, h: float, z: float) -> Vector3: return Vector3(inn[m].x, y + h, inn[m].z) + o * x + t * z
	var sx := w - 0.75 if not lft else w * 0.62
	# abri du réseau (P4 : StationShelters, data/station_shelters.json) : toiture, vitrages, banc, PID, distributeur, totem
	var shelter := shelter_style()
	var sd := minf(float(shelter.depth), maxf(w - 0.9, 1.1))
	var front := maxf(0.8, w - sd - 0.12) if not lft else maxf(0.6, (w - sd) * 0.5)
	StationShelters.build(parent, g, at.call(front, 0.0, 0.0), o, t, shelter, str(net.stations[pf.station].name), str(net.meta.get("line", "")), shelter_termini(), sd)
	var tz := 6.0 if n * StationLayout.STEP > 16.0 else 0.0
	g.box_basis(at.call(sx + 0.2, 0.45, -tz + 3.6), Vector3(0.4, 0.9, 0.4), basis, Color("#56606a")) # corbeille
	for k in [-1.0, 1.0]:  # candélabres
		g.box_basis(at.call(sx + 0.3, 2.1, k * (n * StationLayout.STEP * 0.32)), Vector3(0.12, 4.2, 0.12), basis, Color("#4a4f55"))
		g.box_basis(at.call(sx + 0.15, 4.2, k * (n * StationLayout.STEP * 0.32)), Vector3(0.4, 0.12, 0.25), basis, Color(1.0, 0.92, 0.7, 0.1))
	# bande d'éveil de vigilance (podotactile) en retrait du nez de quai ; garde-corps à l'arrière d'un quai latéral
	for i in n - 1:
		var a := inn[i]; var b := inn[i + 1]; var ow := (out[i] - inn[i]); var ow1 := (out[i + 1] - inn[i + 1])
		var k0 := 0.5 / maxf(ow.length(), 0.6); var k1 := 0.9 / maxf(ow.length(), 0.6)
		var up := top + Vector3(0, 0.012, 0)
		g.quad(a + ow * k0 + up, b + ow1 * k0 + up, b + ow1 * k1 + up, a + ow * k1 + up, Color("#dcd5bd"))
		if not lft and absi(i - m) > 2:
			var pa := out[i] - ow.normalized() * 0.08 + top; var pb := out[i + 1] - ow1.normalized() * 0.08 + top
			g.quad(pa + Vector3(0, 0.95, 0), pb + Vector3(0, 0.95, 0), pb + Vector3(0, 1.02, 0), pa + Vector3(0, 1.02, 0), Color("#5b636a"))
			g.quad(pa + Vector3(0, 0.45, 0), pb + Vector3(0, 0.45, 0), pb + Vector3(0, 0.49, 0), pa + Vector3(0, 0.49, 0), Color("#5b636a"))
			if i % 2 == 0: g.box(pa + Vector3(0, 0.5, 0), Vector3(0.06, 1.0, 0.06), Color("#4a5056"))
	_add_geo(parent, g, Materials.building())
	# voyageurs en attente (silhouettes en instances) et poteau d'information
	var rng := RandomNumberGenerator.new(); rng.seed = int(pf.station) * 7 + (1 if lft else 0)
	var peds: Array = []; var pcols: Array = []; var peds_b: Array = []; var pcols_b: Array = []
	var count := rng.randi_range(1, 3) if DayNight.low_quality else rng.randi_range(2, 7)
	for k in count:
		var i := rng.randi_range(3, maxi(3, n - 4))
		if absi(i - m) <= 2 or i >= n - 1: continue
		var q := inn[i].lerp(out[i], rng.randf_range(0.42, 0.85)) + top
		var face := (inn[i] - out[i]); face.y = 0.0
		var b3 := Basis(Vector3.UP, rng.randf_range(-1.2, 1.2)) * Basis.looking_at(-face.normalized(), Vector3.UP)
		b3 = b3.scaled(Vector3.ONE * rng.randf_range(0.92, 1.06))
		if rng.randf() < 0.6: peds.append(Transform3D(b3, q)); pcols.append(StreetProps.clothes_color(rng))
		else: peds_b.append(Transform3D(b3, q)); pcols_b.append(StreetProps.clothes_color(rng))
	if not peds.is_empty(): parent.add_child(StreetProps.instances(StreetProps.PED, peds, pcols))
	if not peds_b.is_empty(): parent.add_child(StreetProps.instances(StreetProps.PED_B, peds_b, pcols_b))
	parent.add_child(StreetProps.instances(StreetProps.INFO, [Transform3D(basis, at.call(sx, 0.0, tz + 3.0))]))
	if city != null:  # quai et mobilier : interdits aux arbres et lampadaires du décor
		for i in range(0, n - 1, 2):
			var q := inn[i].lerp(out[i], 0.5); var r := inn[mini(i + 2, n - 1)].lerp(out[mini(i + 2, n - 1)], 0.5)
			city.add_keepout(Vector2(q.x, q.z), Vector2(r.x, r.z), w * 0.5 + 0.8)
	var lbl := Label3D.new()
	lbl.text = str(net.stations[pf.station].name)
	lbl.font_size = 64; lbl.pixel_size = 0.006
	lbl.outline_size = 12
	lbl.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	lbl.position = at.call(sx, 3.05, tz)
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
			if TrackView.keepout_for(net).blocked(Vector2(p.x, p.z), maxf(dpt, w) * 0.6):
				continue  # n'empiète pas sur une autre voie (croisements, troncs communs)
			var col := Color(0.85, 0.82, 0.76).darkened(rng.randf() * 0.15)
			col.a = 0.5 + rng.randf() * 0.49
			g.box_basis(p + Vector3(0, h * 0.5, 0), Vector3(dpt, h, w), t.basis, col)
		s += rng.randf_range(16.0, 24.0)
	_add_geo(parent, g, Materials.building())

func _add_geo(parent: Node3D, g: _Geo, mat: Material, xf: Transform3D = Transform3D.IDENTITY) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = g.mesh(Callable(self, "ground_at") if city != null and city.has_terrain else Callable(), xf)
	mi.material_override = mat; mi.transform = xf
	parent.add_child(mi)
	return mi

## Entrée de flotte d'un matériel : la sienne, sinon sa famille 3D (livrée du réseau appliquée).
static func tram_entry(vehicle: VehicleProfile) -> Dictionary:
	if vehicle == null: return {}
	if not vehicle.fleet.is_empty():
		var entry := vehicle.fleet.duplicate(true)
		if not vehicle.custom_livery.is_empty(): entry.custom_livery = vehicle.custom_livery.duplicate(true)
		return entry
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
		var bounds: AABB = sector_bounds[id]
		var closest := Vector3(clampf(center.x, bounds.position.x, bounds.end.x), clampf(center.y, bounds.position.y, bounds.end.y), clampf(center.z, bounds.position.z, bounds.end.z))
		var vis: bool = closest.distance_to(center) <= view_distance
		sectors[id].visible = vis
		if vis: shown += 1
	return shown

func update_from(s: MissionSession, external: bool) -> void:
	external_view = external; speed_mps = s.phys.speed
	_ensure_modules(s.phys.profile.length_m)
	EventView.sync(self, s)
	speed_material.set_shader_parameter("speed", s.phys.speed)
	cam.fov = lerpf(cam.fov, 62.0 + smoothstep(4.0, 22.0, s.phys.speed) * 7.0, 1.0 - exp(-get_process_delta_time() * 2.0))
	var n := modules.size()
	for i in n:
		var pf := body_point(s, rig.module_starts[i]); var pb := body_point(s, rig.module_starts[i] + rig.module_lengths[i])
		var dir := pf - pb
		if dir.length() < 0.01: dir = Vector3(1, 0, 0)
		modules[i].transform = Transform3D(Basis.looking_at(dir.normalized(), Vector3.UP), (pf + pb) * 0.5)
	# côté du quai réel (StationLayout : latéral à droite, central à gauche, multi-quais des deux côtés), selon le sens de marche
	var side := layout.doors_at(net.stations, s.edge_id, s.offset) if layout != null else "right"
	if s.direction < 0 and side != "both": side = "left" if side == "right" else "right"
	rig.set_doors(s.doors_open, side)
	rig.panto_transition_s = MissionSession.POWER_SWITCH_SECONDS
	rig.set_pantograph(s.pantograph_up)
	if _rig_fresh: rig.snap()
	else: rig.update(get_process_delta_time())
	_rig_fresh = false
	var front := _frame(s.edge_id, s.offset)
	var fwd := -front.basis.z * float(s.direction)   # sens de marche (cabine active)
	headlight.global_transform = Transform3D(Basis.looking_at((fwd + Vector3(0, -0.12, 0)).normalized(), Vector3.UP), front.origin + fwd * 0.5 + Vector3(0, 1.0, 0))
	var underground := NetworkLoader.in_spans(net.edge_info[s.edge_id].tunnel, s.offset)
	for i in tunnel_lights.size():
		tunnel_lights[i].visible = underground
		if underground:
			var offset_ := clampf(s.offset + float(s.direction) * (i - 1) * 18.0, 0.0, net.graph.edges[s.edge_id].length)
			tunnel_lights[i].position = pos3(s.edge_id, offset_) + Vector3(0, 4.3, 0)
	headlight.visible = underground or day_night.night > 0.35 or headlights_full
	if underground:
		day_night.env.ambient_light_energy = 0.32
		day_night.env.fog_density = 0.003
	var hd_cab := _update_hd(s, external, underground)
	tram.visible = external or hd_cab
	if has_meta("intro_camera"): pass   # IntroCamera active : la caméra de jeu reste sur sa pose d'arrivée
	elif external and top_view:   # vue du dessus : cap lissé, nez de la rame vers le haut de l'écran
		var dtt := get_process_delta_time()
		var flat := Vector3(fwd.x, 0.0, fwd.z).normalized()
		if flat == Vector3.ZERO: flat = Vector3.FORWARD
		if _top_fwd == Vector3.ZERO or _top_fwd.dot(flat) < 0.0 or dtt <= 0.0: _top_fwd = flat
		else: _top_fwd = _top_fwd.slerp(flat, 1.0 - exp(-dtt * 3.0)).normalized()
		var centre := front.origin - fwd * (_tram_len * 0.5)
		cam.transform = Transform3D(Basis.looking_at(Vector3.DOWN, _top_fwd), centre + Vector3(0, top_height, 0))
	elif external:
		var back := fwd.rotated(Vector3.UP, orbit)
		var k := cam_dist / 40.0
		cam.position = front.origin - back * cam_dist + Vector3(0, 9.5 * k, 0) + back.cross(Vector3.UP) * (-11.0 * k)
		var target := front.origin - fwd * 14.0 + Vector3(0, 2.0, 0)
		if underground:
			cam.position = front.origin - fwd * 10.0 + Vector3(0, 4.45, 0)
			target = front.origin + fwd * 8.0 + Vector3(0, 2.0, 0)
		elif city: cam.position = city.avoid_camera(target, cam.position)
		if not underground: cam.position = _clear_of_tram(cam.position)
		cam.look_at(target)
	elif hd_cab:  # cabine HD : point d'attache conducteur du modèle (pare-brise et pupitre visibles)
		cam.global_transform = rig.hd.cab.camera_transform()
	else:  # vue cabine : cap lissé (filtre exponentiel ~0,1 s), recalé sur un saut de cap > 60°
		var dtc := get_process_delta_time()
		if _cab_fwd == Vector3.ZERO or _cab_fwd.dot(fwd) < 0.5 or dtc <= 0.0: _cab_fwd = fwd.normalized()
		else: _cab_fwd = _cab_fwd.slerp(fwd.normalized(), 1.0 - exp(-dtc * 10.0)).normalized()
		cam.position = front.origin - _cab_fwd * 1.0 + Vector3(0, 2.6, 0)
		cam.look_at(cam.position + _cab_fwd * 30.0 + Vector3(0, -0.8, 0))
	update_sectors(front.origin)
	day_night.set_ground(ground_at(cam.global_position) if not underground else front.origin.y)
	if city: city.update(cam.global_position, 1)
	_update_cars(s)
	signal_view.update(front.origin, false, get_process_delta_time())
	if s.ai != null: ai_view.sync(self, s.ai, front.origin, get_process_delta_time())
	for i in signal_nodes.size():
		_set_lamp(signal_nodes[i], Color(0.1, 0.9, 0.3) if s.signal_state[i] == "clear" else Color(0.95, 0.1, 0.1))

## Rame HD du joueur : LOD (distance caméra, LOD0 en vue cabine), cabine, émissifs, essuie-glace, girouette.
## Retourne vrai quand la cabine HD fournit la vue conducteur.
func _update_hd(s: MissionSession, external: bool, underground: bool) -> bool:
	if rig == null or rig.hd == null: hd_lod = -1; return false
	var hd = rig.hd
	var cab_on := not external and hd.ensure_cab(rig) != null
	var dt := get_process_delta_time()
	if cab_on: hd_lod = -1
	else:
		var centre: Vector3 = modules[modules.size() / 2].global_position if not modules.is_empty() else Vector3.ZERO
		hd_lod = StockHD.lod_for(cam.global_position.distance_to(centre), hd_lod)
	hd.set_lod(hd_lod)
	hd.set_cab_visible(cab_on)
	var night: float = day_night.night
	var dest := str(livery.get("destination", ""))
	if not s.stops.is_empty(): dest = str(s.stops[s.stops.size() - 1].get("name", dest))
	hd.update({"headlights": 1.0 if (headlights_full or underground or night > 0.35) else 0.45, "interior": underground or night > 0.3,
		"wiper": wiper_forced or rain > 0.15, "mirrors_folded": mirrors_folded, "destination": dest}, dt)
	if hd.cab != null and cab_on:
		var d := cab_data.duplicate()
		d["toggles"] = {"pantograph": s.pantograph_up, "headlights": headlights_full, "wiper": wiper_forced or rain > 0.15,
			"mirrors": mirrors_folded, "reverser": s.direction < 0}
		hd.cab.update(d, dt)
	return cab_on

## Commande de cabine HD sous un point d'écran ({} : aucune).
func cab_pick(screen_pos: Vector2) -> Dictionary:
	if rig == null or rig.hd == null or rig.hd.cab == null: return {}
	return rig.hd.cab.pick(cam, screen_pos)

## Retour visuel d'une action sur la commande correspondante de la cabine HD.
func cab_pulse(action: String) -> void:
	if rig != null and rig.hd != null and rig.hd.cab != null: rig.hd.cab.pulse(action)

func has_hd_cab() -> bool:
	return rig != null and rig.hd != null and rig.hd.cab != null and rig.hd.cab.visible

## La caméra extérieure ne pénètre jamais la rame (caisses = boîtes orientées, marge 0,8 m) : elle passe au-dessus.
func _clear_of_tram(p: Vector3) -> Vector3:
	for i in modules.size():
		var local := modules[i].global_transform.affine_inverse() * p
		var half := float(rig.module_lengths[i]) * 0.5 + 0.8
		if absf(local.x) < 2.1 and absf(local.z) < half and local.y < 4.6 and local.y > -1.0:
			p.y = modules[i].global_transform.origin.y + 4.6
	return p

func _update_cars(s: MissionSession) -> void:
	var cars := s.traffic.cars
	while car_nodes.size() < cars.size():
		var g := _Geo.new()
		var body := Color.from_hsv(randf(), 0.55, 0.75)
		g.box(Vector3(0, 0.55, 0), Vector3(1.8, 0.7, 4.3), body)
		g.box(Vector3(0, 1.15, 0.2), Vector3(1.6, 0.55, 2.3), Color(0.25, 0.32, 0.38, 0.5))
		var mi := _add_geo(self, g, Materials.object())
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
	var all_faces := false   # décalage de couche aussi sur les faces verticales (profil de rail : flancs de gorge)
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

	## `ground` (Vector3 -> float, repère de la ligne) : UV2 = (matériau, hauteur au-dessus du terrain) pour le
	## décalage de profondeur des couches de sol (faces horizontales seulement ; 0 = sans décalage).
	func mesh(ground: Callable = Callable(), xf: Transform3D = Transform3D.IDENTITY) -> ArrayMesh:
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = v; arr[Mesh.ARRAY_COLOR] = c; arr[Mesh.ARRAY_TEX_UV] = uv
		var uv2 := PackedVector2Array(); uv2.resize(v.size())
		for i in range(0, v.size() - 2, 3):
			var id := CityScene._Arrays.mat_id(c[i].a)
			var h := 0.0
			var fn := (v[i + 2] - v[i]).cross(v[i + 1] - v[i])
			if all_faces or absf(fn.y) > 0.9 * fn.length():
				var ctr := xf * ((v[i] + v[i + 1] + v[i + 2]) / 3.0)
				h = ctr.y - (float(ground.call(ctr)) if ground.is_valid() else 0.0)
				if h < 0.0 or h > 2.5: h = 0.0
			for j in 3: uv2[i + j] = Vector2(id, h)
		arr[Mesh.ARRAY_TEX_UV2] = uv2
		var normals := PackedVector3Array(); normals.resize(v.size())
		for i in range(0, v.size() - 2, 3):
			var normal := (v[i + 2] - v[i]).cross(v[i + 1] - v[i]).normalized()
			if normal.y < -0.01: normal = -normal
			for j in 3: normals[i + j] = normal
		arr[Mesh.ARRAY_NORMAL] = normals
		var m := ArrayMesh.new()
		if v.size() > 0: m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		return m

## Au chargement, aucun historique n'existe encore derrière la rame. Prolonger
## la tangente d'entrée pour le modèle évite d'empiler les caisses au point 0.
## Ce prolongement visuel ne modifie ni la voie ni la position de simulation.
func body_point(s: MissionSession, behind: float) -> Vector3:
	var location := s.locate_behind(behind)
	var point := pos3(str(location[0]), float(location[1]))
	if int(location[3]) != 0: return point
	var available: float = s.offset if s.direction > 0 else net.graph.edges[s.edge_id].length - s.offset
	for i in range(s.route.size() - 1): available += net.graph.edges[s.route[i]].length
	if behind <= available: return point
	var id := str(location[0]); var off := float(location[1]); var r := int(location[2])
	var frame := _frame(id, off)
	var tangent := -frame.basis.z * float(r)
	return point - tangent * (behind - available)
