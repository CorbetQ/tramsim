class_name StationIdentityView
extends Node3D
## Authored station scenes: each site has surveyed footprints, architecture and references.
## The platform/track graph is preserved. Model details are culled independently on mobile.
var view: LineView
var data: Dictionary = {}
var by_name: Dictionary = {}
var by_way: Dictionary = {}
var owners: Dictionary = {}
var stats := {"stations": 0, "platforms": 0, "canopies": 0, "context_items": 0, "landmarks": 0}
var _profiles: Array = []
var _platforms: Dictionary = {}
var _glass: StandardMaterial3D
var _paving: ShaderMaterial
var _metal: Material
var _depot_built := false
var _depot_tracks: Dictionary = {}
var _depot_boundary := PackedVector2Array()

static func key(s: String) -> String:
	var k := StationLayout.norm(s)
	if k.begins_with("st "): k = "saint " + k.substr(3)
	return k.replace(" st ", " saint ")

func setup(v: LineView, source: String) -> void:
	view = v; name = "authored_station_scenes"
	var path := "res://data/station_models/%s.json" % source
	if not FileAccess.file_exists(path): return
	var raw: Variant = CityDataStore.document(path)
	if not raw is Dictionary: return
	data = raw
	_metal = Materials.building()
	_paving = ShaderMaterial.new(); _paving.shader = load("res://src/rendering/shaders/station_paving.gdshader")
	_glass = StandardMaterial3D.new(); _glass.albedo_color = Color(0.57, 0.74, 0.78, 0.30)
	_glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
	_glass.cull_mode = BaseMaterial3D.CULL_DISABLED; _glass.roughness = 0.14
	_glass.metallic = 0.12; _glass.clearcoat_enabled = true; _glass.clearcoat = 0.8
	for depot in view.net.meta.get("depots", []):
		for id in depot.tracks: _depot_tracks[id] = true
	for ll in data.get("depot", {}).get("fence", []): _depot_boundary.append(_point(ll))
	var served := {}
	for station in view.net.stations: served[key(station.name)] = true
	for profile in data.get("stations", []):
		if not served.has(key(profile.name)): continue
		_profiles.append(profile); by_name[key(profile.name)] = profile
		for way in profile.platform_ways: by_way[int(way)] = profile
	for platform in view.net.meta.get("platforms", []):
		if by_way.has(int(platform.osm_way)):
			var profile: Dictionary = by_way[int(platform.osm_way)]
			if not _platforms.has(profile.id): _platforms[profile.id] = []
			_platforms[profile.id].append(platform)

func depot_track_at(id: String, p: Vector3) -> bool:
	return _depot_tracks.has(id) and _depot_boundary.size() > 2 and Geometry2D.is_point_in_polygon(Vector2(p.x, p.z), _depot_boundary)

func _point(ll: Array) -> Vector2:
	var origin: Array = view.net.meta.origin
	return Vector2(deg_to_rad(float(ll[1]) - float(origin[1])) * CityScene.R * cos(deg_to_rad(float(origin[0]))), -deg_to_rad(float(ll[0]) - float(origin[0])) * CityScene.R)

func _owner(profile: Dictionary) -> Node3D:
	if owners.has(profile.id): return owners[profile.id]
	var owner := Node3D.new(); owner.name = str(profile.id)
	owner.set_meta("station_name", profile.name); owner.set_meta("survey", profile.get("observations", []))
	add_child(owner); owners[profile.id] = owner
	return owner

func _mesh(parent: Node3D, g: LineView._Geo, material: Material, distance_ := 240.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = g.mesh(Callable(view, "ground_at") if view.city else Callable())
	mi.material_override = material; mi.visibility_range_end = distance_; mi.visibility_range_end_margin = 20.0
	parent.add_child(mi)
	return mi

func _floor(p: Vector2, profile: Dictionary) -> float:
	var best := INF; var height_ := 0.0
	for pf in _platforms.get(profile.id, []):
		for i in pf.pts.size():
			var j: int = (i + 1) % pf.pts.size()
			var a := Vector2(pf.pts[i][0], pf.pts[i][1]); var b := Vector2(pf.pts[j][0], pf.pts[j][1])
			var q := Geometry2D.get_closest_point_to_segment(p, a, b)
			var dist := p.distance_squared_to(q)
			if dist < best:
				best = dist
				var t := clampf((q - a).dot(b - a) / maxf((b - a).length_squared(), .0001), 0.0, 1.0)
				height_ = lerpf(float(pf.y[i]), float(pf.y[j]), t) + float(pf.get("height_m", .3))
	return height_ if best < INF else view.ground_at(Vector3(p.x, 0, p.y))

func _frame(poly: PackedVector2Array) -> Dictionary:
	var c := Vector2.ZERO
	for p in poly: c += p
	c /= maxf(1.0, poly.size())
	var xx := 0.0; var zz := 0.0; var xz := 0.0
	for p in poly:
		var d := p - c; xx += d.x * d.x; zz += d.y * d.y; xz += d.x * d.y
	var angle := .5 * atan2(2.0 * xz, xx - zz)
	var tangent := Vector2(cos(angle), sin(angle))
	if tangent.y > 0.0: tangent = -tangent
	var normal := Vector2(-tangent.y, tangent.x)
	var low := Vector2(INF, INF); var high := Vector2(-INF, -INF)
	for p in poly:
		var q := Vector2((p - c).dot(tangent), (p - c).dot(normal)); low = low.min(q); high = high.max(q)
	return {"c": c, "t": tangent, "n": normal, "length": high.x - low.x, "width": high.y - low.y, "lo": low, "hi": high}

func _v(p: Vector2, y: float) -> Vector3:
	return Vector3(p.x, y, p.y)

func build_platform(pf: Dictionary) -> bool:
	if not by_way.has(int(pf.osm_way)): return false
	var profile: Dictionary = by_way[int(pf.osm_way)]
	var owner := _owner(profile)
	if LandmarkModels.replaces_platform(view, int(pf.osm_way)):   # quai modélisé (assets/models) : keepout et voyageurs seuls
		for i in pf.pts.size():
			var j: int = (i + 1) % pf.pts.size()
			if view.city: view.city.add_keepout(Vector2(pf.pts[i][0], pf.pts[i][1]), Vector2(pf.pts[j][0], pf.pts[j][1]), .6)
		view._platform_people(pf, owner, false)
		stats.platforms += 1
		return true
	var poly := PackedVector2Array(); var top := PackedVector3Array()
	var h := float(pf.get("height_m", .3))
	for i in pf.pts.size():
		poly.append(Vector2(pf.pts[i][0], pf.pts[i][1])); top.append(Vector3(pf.pts[i][0], float(pf.y[i]) + h, pf.pts[i][1]))
	var tris := Geometry2D.triangulate_polygon(poly)
	var g := LineView._Geo.new(); var details := LineView._Geo.new()
	for i in range(0, tris.size(), 3): g.tri(top[tris[i]], top[tris[i + 1]], top[tris[i + 2]], Color("#b7b5ab"))
	var c: Vector2 = _frame(poly).c
	var edge_points: PackedVector2Array = view.net.edge_info.get(str(pf.edge), {}).get("pts", PackedVector2Array())
	for i in poly.size():
		var j := (i + 1) % poly.size()
		var a := top[i]; var b := top[j]; var mid := (a + b) * .5
		details.quad(a - Vector3(0, h, 0), b - Vector3(0, h, 0), b, a, Color("#b1b0a7"))
		var inset := (c - poly[i]).normalized() * .12; var inset_b := (c - poly[j]).normalized() * .12
		details.quad(a + Vector3(0, .007, 0), b + Vector3(0, .007, 0), b + _v(inset_b, .007), a + _v(inset, .007), Color("#dbd9cb"))
		var closest := INF
		for k in range(1, edge_points.size()):
			closest = minf(closest, Vector2(mid.x, mid.z).distance_to(Geometry2D.get_closest_point_to_segment(Vector2(mid.x, mid.z), edge_points[k - 1], edge_points[k])))
		# Tactile warning belongs on the rail side, not all around the platform.
		if closest < 4.2 and a.distance_to(b) > 1.4:
			var ia := (c - poly[i]).normalized(); var ib := (c - poly[j]).normalized()
			var pa := a + _v(ia * .45, .012); var pb := b + _v(ib * .45, .012)
			details.quad(pa, pb, pb + _v(ib * .36, 0), pa + _v(ia * .36, 0), Color("#555b59"))
			var count_ := mini(70, ceili(a.distance_to(b) / .35))
			for n in count_:
				var q := pa.lerp(pb, (float(n) + .5) / count_) + _v(ia * .18, .008)
				details.box(q, Vector3(.035, .015, .16), Color("#b7b7ad"))
		elif a.distance_to(b) > 9.0 and closest > 5.0:
			# Back guardrails are interrupted at access paths / platform ends.
			_fence(details, a + Vector3(0, .02, 0), b + Vector3(0, .02, 0), Color("#535d5b"))
		if view.city: view.city.add_keepout(poly[i], poly[j], .6)
	_mesh(owner, g, _paving, 340.0); _mesh(owner, details, _metal)
	view._platform_people(pf, owner, false)
	stats.platforms += 1
	return true

func build_sites() -> void:
	for profile in _profiles:
		if LandmarkModels.replaces_station(view, str(profile.name)): stats.stations += 1; continue   # modèle dédié
		var owner := _owner(profile)
		for canopy in profile.canopies: _canopy(owner, profile, canopy)
		for surface in profile.get("surfaces", []): _surface(owner, surface)
		for item in profile.get("furniture", []): _item(owner, item)
		for landmark in profile.get("landmarks", []): _landmark(owner, landmark)
		stats.stations += 1
	if not data.is_empty() and not view.net.meta.get("depots", []).is_empty(): _depot_context()

func _pole(g: LineView._Geo, at: Vector3, h: float, radius: float, color_: Color) -> void:
	for j in 10:
		var a := TAU * j / 10.0; var b := TAU * (j + 1) / 10.0
		var p := at + Vector3(cos(a) * radius, 0, sin(a) * radius)
		var q := at + Vector3(cos(b) * radius, 0, sin(b) * radius)
		g.quad(p, q, q + Vector3.UP * h, p + Vector3.UP * h, color_)

func _beam(g: LineView._Geo, a: Vector3, b: Vector3, width: float, height_: float, color_: Color) -> void:
	if a.distance_to(b) < .01: return
	var direction := (b - a).normalized()
	var basis := Basis.looking_at(direction, Vector3.FORWARD if absf(direction.dot(Vector3.UP)) > .98 else Vector3.UP)
	g.box_basis((a + b) * .5, Vector3(width, height_, a.distance_to(b)), basis, color_)

func _canopy(owner: Node3D, profile: Dictionary, model: Dictionary) -> void:
	var poly := PackedVector2Array()
	for p in model.footprint: poly.append(_point(p))
	if poly.size() < 3: return
	var f := _frame(poly); var c: Vector2 = f.c; var t: Vector2 = f.t; var n: Vector2 = f.n
	var L: float = f.length; var W: float = f.width
	var glass_roof: bool = profile.roof_family == "glass"
	var y := _floor(c, profile); var roof_h := 3.15 if glass_roof else 2.54
	var dark := Color("#343e40"); var steel := Color("#c2c7c5") if glass_roof else dark
	var g := LineView._Geo.new(); var glass := LineView._Geo.new()
	var tris := Geometry2D.triangulate_polygon(poly)
	for i in range(0, tris.size(), 3):
		var a := poly[tris[i]]; var b := poly[tris[i + 1]]; var q := poly[tris[i + 2]]
		var v0 := _v(a, _floor(a, profile) + roof_h); var v1 := _v(b, _floor(b, profile) + roof_h); var v2 := _v(q, _floor(q, profile) + roof_h)
		if glass_roof: glass.tri(v0, v1, v2, Color.WHITE)
		else: g.tri(v0, v1, v2, dark)
	for i in poly.size():
		var a := poly[i]; var b := poly[(i + 1) % poly.size()]
		_beam(g, _v(a, _floor(a, profile) + roof_h), _v(b, _floor(b, profile) + roof_h), .10, .14, steel)
	# Slender real-world support sizes, roof ribs and glazing mullions.
	var bays := maxi(2, ceili(L / (3.8 if glass_roof else 2.8)))
	for i in bays + 1:
		var along := lerpf(float(f.lo.x) + .18, float(f.hi.x) - .18, float(i) / bays)
		var a := c + t * along + n * (float(f.lo.y) + .12)
		var b := c + t * along + n * (float(f.hi.y) - .12)
		# Clip roof ribs to non-rectangular glass-canopy footprints.
		var samples := 16; var run_a := Vector2.ZERO; var in_run := false
		for j in samples + 1:
			var q := a.lerp(b, float(j) / samples)
			var inside := Geometry2D.is_point_in_polygon(q, poly)
			if inside and not in_run: run_a = q; in_run = true
			if in_run and (not inside or j == samples):
				_beam(g, _v(run_a, _floor(run_a, profile) + roof_h - .08), _v(q, _floor(q, profile) + roof_h - .08), .075, .13, steel); in_run = false
		if glass_roof:
			for side in [-.32, .32]:
				var q: Vector2 = c + t * along + n * W * side
				if Geometry2D.is_point_in_polygon(q, poly): _pole(g, _v(q, _floor(q, profile)), roof_h, .084, steel)
		elif i % 2 == 0 or i == bays:
			var q := c + t * along + n * (W * .38)
			_pole(g, _v(q, _floor(q, profile)), roof_h - .07, .065, dark)
	if not glass_roof:
		# Rear glazing, central service cabinet, cantilever brackets and wood seat.
		var back := c + n * W * .36
		var a := back - t * L * .46; var b := back + t * L * .46
		glass.quad(_v(a, y + .28), _v(b, y + .28), _v(b, y + roof_h - .25), _v(a, y + roof_h - .25), Color.WHITE)
		var basis := Basis(Vector3(n.x, 0, n.y), Vector3.UP, Vector3(t.x, 0, t.y))
		g.box_basis(_v(back + t * L * .06, y + 1.1), Vector3(.17, 2.15, 1.7), basis, dark.lightened(.13))
		for i in 4:
			g.box_basis(_v(c - n * .04 + t * L * -.21, y + .47) + Vector3(n.x, 0, n.y) * (i * .09), Vector3(.075, .065, 2.0), basis, Color("#90755b"))
		for side in [-.95, .95]: g.box_basis(_v(c + t * (L * -.21 + side), y + .25), Vector3(.30, .48, .06), basis, dark)
		_sign(owner, str(profile.name), _v(c - n * W * .47, y + 2.25), t, .38, minf(L - .4, 5.8))
		g.box_basis(_v(c, y + roof_h - .19), Vector3(.055, .035, L * .72), basis, Color(.90, .83, .67, .1))
		# Irigo's six coloured strokes at the canopy fascia.
		for j in 6:
			var palette := ["#c83b57", "#db7736", "#dfc63f", "#79a34c", "#35a19e", "#6463a3"]
			g.box_basis(_v(c + t * (L * .36 - j * .10) - n * (W * .48), y + 2.28), Vector3(.035, .16, .055), basis, Color(palette[j]))
		_info(owner, profile, c + t * (L * .5 + 2.0), t, y)
	else:
		# Laminated glass panels are visible as a fine structural grid, not an opaque slab.
		for i in range(1, maxi(2, ceili(W / 1.7))):
			var across := lerpf(float(f.lo.y), float(f.hi.y), float(i) / maxi(2, ceili(W / 1.7)))
			var a := c + t * (float(f.lo.x) + .2) + n * across; var b := c + t * (float(f.hi.x) - .2) + n * across
			_beam(g, _v(a, y + roof_h), _v(b, y + roof_h), .035, .045, steel)
		_sign(owner, str(profile.name), _v(c, y + 2.65), t, .45, minf(L * .6, 7.0))
		_info(owner, profile, c - t * (L * .35), t, y)
	_mesh(owner, g, _metal, 320.0)
	if glass.v.size() > 0: _mesh(owner, glass, _glass, 280.0)
	if str(profile.name) == "St-Gilles": _copper_pavilion(owner, profile, c)
	stats.canopies += 1

func _sign(owner: Node3D, text_: String, at: Vector3, tangent: Vector2, h: float, w: float) -> void:
	var g := LineView._Geo.new()
	var basis := Basis(Vector3(tangent.x, 0, tangent.y), Vector3.UP, Vector3(-tangent.y, 0, tangent.x))
	g.box_basis(at, Vector3(w, h, .06), basis, Color("#374341")); _mesh(owner, g, _metal, 180.0)
	for sign_side in [-1.0, 1.0]:
		var label := Label3D.new(); label.text = text_; label.font = UiTheme.font(true)
		label.font_size = 56; label.pixel_size = minf(.006, w / maxf(56.0 * text_.length() * .62, 1.0))
		label.modulate = Color("#f2f1e8"); label.outline_size = 0; label.no_depth_test = false
		label.position = at + basis.z * sign_side * .037
		label.basis = basis if sign_side > 0 else basis.rotated(Vector3.UP, PI)
		label.visibility_range_end = 150.0; owner.add_child(label)

func _info(owner: Node3D, profile: Dictionary, p: Vector2, tangent: Vector2, y: float) -> void:
	var g := LineView._Geo.new(); var n := Vector2(-tangent.y, tangent.x)
	var basis := Basis(Vector3(n.x, 0, n.y), Vector3.UP, Vector3(tangent.x, 0, tangent.y))
	g.box_basis(_v(p, y + 1.1), Vector3(.35, 2.2, .72), basis, Color("#485553"))
	g.box_basis(_v(p + n * .19, y + 1.5), Vector3(.018, .33, .43), basis, Color("#bdd0c5"))
	g.box_basis(_v(p + n * .19, y + .95), Vector3(.018, .20, .30), basis, Color("#202a2b"))
	var led := p + tangent * 2.4
	_pole(g, _v(led, y), 3.1, .06, Color("#45504e"))
	g.box_basis(_v(led, y + 2.85), Vector3(.24, .52, 1.0), basis, Color("#293331"))
	for i in 2: g.box_basis(_v(led + n * .13, y + 2.94 - i * .17), Vector3(.018, .035, .65), basis, Color(.80, .54, .25, .1))
	_mesh(owner, g, _metal, 180.0)

func _surface(owner: Node3D, model: Dictionary) -> void:
	var g := LineView._Geo.new()
	for tri in model.get("triangles", []):
		_drape(g, _point(tri[0]), _point(tri[1]), _point(tri[2]), Color("#b7b6ab"))
	if g.v.size() > 0: _mesh(owner, g, _paving, 320.0)

func _drape(g: LineView._Geo, a: Vector2, b: Vector2, c: Vector2, color_: Color) -> void:
	var longest := maxf(a.distance_squared_to(b), maxf(b.distance_squared_to(c), c.distance_squared_to(a)))
	if longest > 36.0:
		if longest == a.distance_squared_to(b):
			var q := (a + b) * .5; _drape(g, a, q, c, color_); _drape(g, q, b, c, color_)
		elif longest == b.distance_squared_to(c):
			var q := (b + c) * .5; _drape(g, a, b, q, color_); _drape(g, a, q, c, color_)
		else:
			var q := (c + a) * .5; _drape(g, a, b, q, color_); _drape(g, q, b, c, color_)
		return
	# GEOS constrained triangles are clockwise; Godot ground faces need the opposite winding.
	if (b - a).cross(c - a) < 0.0:
		var swap := b; b = c; c = swap
	g.tri(_v(a, view.ground_at(_v(a, 0)) + .12), _v(b, view.ground_at(_v(b, 0)) + .12), _v(c, view.ground_at(_v(c, 0)) + .12), color_)

func _fence(g: LineView._Geo, a: Vector3, b: Vector3, color_: Color) -> void:
	var n := maxi(1, ceili(a.distance_to(b) / 2.0))
	for i in n + 1: _pole(g, a.lerp(b, float(i) / n), 1.0, .028, color_)
	for h in [.44, .96]: _beam(g, a + Vector3.UP * h, b + Vector3.UP * h, .035, .045, color_)

func _item(owner: Node3D, item: Dictionary) -> void:
	var p := _point(item.position); var at := _v(p, view.ground_at(_v(p, 0)) + .035)
	var basis := Basis(Vector3.UP, deg_to_rad(float(item.heading_deg)))
	var w := float(item.width_m); var L := float(item.length_m); var g := LineView._Geo.new()
	match str(item.type):
		"rail_fence": _fence(g, at - basis.z * L * .5, at + basis.z * L * .5, Color("#505d59"))
		"bench":
			for i in 4: g.box_basis(at + Vector3.UP * .46 + basis.x * (i - 1.5) * .11, Vector3(.095, .065, L), basis, Color("#927c5e"))
			for z in [-.38, .38]: g.box_basis(at + basis.z * L * z + Vector3.UP * .23, Vector3(w * .8, .46, .08), basis, Color("#414c48"))
		"planter":
			g.box_basis(at + Vector3.UP * .22, Vector3(w, .44, L), basis, Color("#989f92"))
			g.box_basis(at + Vector3.UP * .45, Vector3(w - .15, .03, L - .15), basis, Color("#4c4939"))
			for i in maxi(2, int(L / 1.1)):
				var q := at + basis.z * (float(i) - L * .45) + Vector3.UP * .7
				g.box_basis(q, Vector3(w * .72, .44, .72), basis, Color("#65774b"))
		"cycle_stands":
			for i in maxi(2, int(L / .85)):
				var q := at + basis.z * ((i - L * .45) * .85)
				_beam(g, q + basis.x * .36 + Vector3.UP * .8, q - basis.x * .36 + Vector3.UP * .8, .035, .04, Color("#68736b"))
				for side in [-1.0, 1.0]: _pole(g, q + basis.x * side * .36, .8, .021, Color("#68736b"))
		"parkride":
			_pole(g, at, 4.2, .07, Color("#515e5c")); g.box_basis(at + Vector3.UP * 3.8, Vector3(1.35, 1.1, .08), basis, Color("#38687a"))
			_sign(owner, "P + TRAM", at + Vector3.UP * 3.8, Vector2(basis.x.x, basis.x.z), .65, 1.5)
		"tree_pit", "history_ring":
			for i in 40:
				var a := TAU * i / 40; var b := TAU * (i + 1) / 40
				var v0 := at + Vector3(cos(a), 0, sin(a)) * w * .5; var v1 := at + Vector3(cos(b), 0, sin(b)) * w * .5
				var v2 := at + Vector3(cos(b), 0, sin(b)) * (w * .5 - .16); var v3 := at + Vector3(cos(a), 0, sin(a)) * (w * .5 - .16)
				g.quad(v0, v1, v2, v3, Color("#616b63"))
		"cafe":
			for i in maxi(2, int(L / 4.0)):
				var q := at + basis.z * (i * 4 - L * .35)
				_pole(g, q, 2.5, .025, Color("#64605a"))
				g.box_basis(q + Vector3.UP * 2.55, Vector3(w * .86, .10, 3.5), basis, Color("#a75041"))
				g.box_basis(q + Vector3.UP * .72, Vector3(.65, .07, .65), basis, Color("#91897a"))
		_:
			return
	_mesh(owner, g, _metal, 300.0); stats.context_items += 1

func _solid(_parent: Node3D, poly: PackedVector2Array, base: float, height_: float, wall: Color, roof: Color, _distance_ := 480.0) -> LineView._Geo:
	var g := LineView._Geo.new(); var tris := Geometry2D.triangulate_polygon(poly)
	for i in range(0, tris.size(), 3): g.tri(_v(poly[tris[i]], base + height_), _v(poly[tris[i + 1]], base + height_), _v(poly[tris[i + 2]], base + height_), roof)
	for i in poly.size():
		var a := poly[i]; var b := poly[(i + 1) % poly.size()]
		g.quad(_v(a, base), _v(b, base), _v(b, base + height_), _v(a, base + height_), wall)
	return g

func _landmark(owner: Node3D, model: Dictionary) -> void:
	var poly := PackedVector2Array()
	for ll in model.footprint: poly.append(_point(ll))
	if poly.size() < 3: return
	if view.city: view.city.replace_hangar(poly, str(model.kind) == "church")
	var f := _frame(poly); var c: Vector2 = f.c
	var base := view.ground_at(_v(c, 0)); var h := float(model.height_m)
	var roof_rise := float({"church": 10.5, "townhouse": 2.6, "theatre": 3.2, "iceparc": 2.4, "congress": 2.4}.get(str(model.kind), .4))
	if view.city: view.city.add_building_obstacle(poly, base, h + roof_rise)
	var kind := str(model.kind); var wall := Color(model.wall); var roof := Color(model.roof)
	var g := _solid(owner, poly, base, h, wall, roof)
	var detail := LineView._Geo.new(); var glass_color := Color("#344b52")
	var light := Color("#d9d7c9"); var slate := Color("#525c65")
	var floors := maxi(1, int(h / 3.4)); var is_big_hall := kind in ["iceparc", "gym", "congress", "church", "parking", "theatre"]
	for i in poly.size():
		var a := poly[i]; var b := poly[(i + 1) % poly.size()]; var length_ := a.distance_to(b)
		if length_ < 1.3: continue
		var t := (b - a).normalized(); var n := Vector2(-t.y, t.x)
		if (a.lerp(b, .5) + n).distance_squared_to(c) < (a.lerp(b, .5) - n).distance_squared_to(c): n = -n
		var basis := Basis(_v(t, 0), Vector3.UP, _v(n, 0))
		if kind == "church": continue
		if kind == "parking":
			for level in 4:
				var y := base + 1.8 + level * 2.5
				detail.box_basis(_v(a.lerp(b, .5) + n * .04, y), Vector3(length_, 1.15, .08), basis, Color("#4c5653"))
				_beam(detail, _v(a + n * .12, y + .62), _v(b + n * .12, y + .62), .18, .28, light)
			for j in maxi(1, int(length_ / 5.0)):
				var q := a.lerp(b, (j + .5) / maxf(1, int(length_ / 5.0)))
				detail.box_basis(_v(q + n * .13, base + h * .5), Vector3(.40, h, .30), basis, light)
			continue
		if kind in ["timber", "gym", "civic", "iceparc", "congress", "commercial", "vilar", "hospital"]:
			var step := .42 if kind == "timber" else (3.2 if kind == "gym" else 2.5)
			var count_ := maxi(1, int(length_ / step))
			for j in count_:
				var q := a.lerp(b, (j + .5) / count_) + n * .05
				if kind == "timber": detail.box_basis(_v(q, base + h * .5), Vector3(.09, h - .45, .16), basis, Color("#67533e"))
				else:
					var color_ := glass_color
					if kind == "gym": color_ = [Color("#8e9a74"), Color("#a6966c"), Color("#9da3a6"), Color("#797b8f")][j % 4]
					if kind == "civic" and j % 4 == 0: color_ = Color("#a1b870")
					detail.box_basis(_v(q, base + h * .38), Vector3(step * .88, h * .64, .075), basis, color_)
					if kind == "gym": detail.box_basis(_v(q + n * .09, base + h * .48), Vector3(.18, h * .90, .20), basis, Color("#a6483c"))
			if kind == "congress":
				for row in maxi(1, int(h / 2.5)):
					for col in maxi(1, int(length_ / 1.6)):
						var q := a.lerp(b, (col + .5) / maxi(1, int(length_ / 1.6))) + n * (.19 if (row + col) % 3 == 0 else .12)
						var silver: Color = [Color("#b8c0bd"), Color("#d6d9ce"), Color("#8b999a"), Color("#ccd1c6")][(row * 3 + col) % 4]
						detail.box_basis(_v(q, base + 1.5 + row * 2.5), Vector3(1.43, 2.25, .08), basis, silver)
			if kind == "vilar": _beam(detail, _v(a + n * .15, base + h - .8), _v(b + n * .15, base + h - .8), .22, .58, Color("#a3493c"))
			if kind == "timber":
				for j in maxi(1, int(length_ / 3.6)):
					var q := a.lerp(b, (j + .5) / maxi(1, int(length_ / 3.6))) + n * .15
					detail.box_basis(_v(q, base + h * .48), Vector3(1.65, 2.4, .10), basis, glass_color)
			continue
		var bays := maxi(1, int(length_ / (3.0 if kind == "maison_bleue" else 3.7)))
		for level in floors:
			var y := base + 1.8 + level * (h - 1.0) / floors
			for j in bays:
				var q := a.lerp(b, (j + .5) / bays) + n * .045
				var width_ := minf(length_ / bays * .52, 1.6)
				detail.box_basis(_v(q, y), Vector3(width_ + .22, 2.1, .08), basis, light)
				detail.box_basis(_v(q + n * .05, y), Vector3(width_, 1.84, .06), basis, glass_color)
				detail.box_basis(_v(q + n * .09, y), Vector3(.045, 1.9, .04), basis, light)
				if kind in ["maison_bleue", "housing"] and level > 0:
					# Odorico colour progression, projecting balconies and narrow golden bands.
					var blue := Color("#c7d3c4").lerp(Color("#477b92"), float(level) / floors) if kind == "maison_bleue" else wall.lightened(.07)
					detail.box_basis(_v(q + n * .39, y - .92), Vector3(width_ + .65, .15, .92), basis, light)
					detail.box_basis(_v(q + n * .80, y - .48), Vector3(width_ + .6, .68, .10), basis, blue)
					detail.box_basis(_v(q + n * .86, y - .13), Vector3(width_ + .7, .055, .06), basis, Color("#b6a16b"))
			if kind == "maison_bleue":
				var blue := Color("#c4d1c4").lerp(Color("#507e92"), float(level) / floors)
				_beam(detail, _v(a + n * .04, y - 1.10), _v(b + n * .04, y - 1.10), .09, .34, blue)
		# Cornice follows the actual polygon, not a bounding-box facade.
		_beam(detail, _v(a + n * .10, base + h - .16), _v(b + n * .10, base + h - .16), .32, .30, light)
	var facade_count := detail.v.size()
	if kind == "townhouse":
		# Low slate hip roof and pale stone cornice, tied to this building's footprint.
		for i in poly.size():
			var a := poly[i]; var b := poly[(i + 1) % poly.size()]
			detail.tri(_v(a, base + h + .03), _v(b, base + h + .03), _v(c, base + h + 2.6), slate.lightened((i % 3) * .035))
	if kind == "church":
		# The Avrillé church has an octagonal slate pyramid, not a flat slab.
		for i in poly.size(): g.tri(_v(poly[i], base + h), _v(poly[(i + 1) % poly.size()], base + h), _v(c, base + h + 10.5), slate.lightened((i % 3) * .035))
	elif kind == "congress":
		# Two faceted auditoria read distinctly in an aerial view.
		for specs in [[Vector2(-15, -10), 22.0, 2.4], [Vector2(13, 13), 12.5, 1.7]]:
			var ctr: Vector2 = c + specs[0]
			for j in 10:
				var a := ctr + Vector2(cos(TAU * j / 10), sin(TAU * j / 10)) * float(specs[1])
				var b := ctr + Vector2(cos(TAU * (j + 1) / 10), sin(TAU * (j + 1) / 10)) * float(specs[1])
				if Geometry2D.is_point_in_polygon(a, poly) and Geometry2D.is_point_in_polygon(b, poly): detail.tri(_v(a, base + h + .1), _v(b, base + h + .1), _v(ctr, base + h + float(specs[2])), Color("#a7adae").darkened((j % 3) * .04))
	elif kind == "iceparc":
		var t: Vector2 = f.t; var n: Vector2 = f.n; var basis := Basis(_v(n, 0), Vector3.UP, _v(t, 0))
		# Membrane roof, raised longitudinal crown and photovoltaic bands seen on IGN.
		var roof_len: float = f.length * .50; var roof_w: float = f.width * .67
		var crown := c + t * float(f.length) * .20
		for j in 14:
			var u0 := -roof_w * .5 + roof_w * j / 14; var u1 := -roof_w * .5 + roof_w * (j + 1) / 14
			var a := crown + n * u0; var b := crown + n * u1
			var y0 := base + h + .25 + 2.1 * sqrt(maxf(0, 1 - pow(u0 / (roof_w * .5), 2)))
			var y1 := base + h + .25 + 2.1 * sqrt(maxf(0, 1 - pow(u1 / (roof_w * .5), 2)))
			detail.quad(_v(a - t * roof_len * .5, y0), _v(b - t * roof_len * .5, y1), _v(b + t * roof_len * .5, y1), _v(a + t * roof_len * .5, y0), Color("#b8c2c1"))
		for rib in 22:
			var u := roof_w * (float(rib) / 21.0 - .5)
			var q := crown + n * u
			var y := base + h + .30 + 2.1 * sqrt(maxf(0.0, 1.0 - pow(u / (roof_w * .5), 2)))
			_beam(detail, _v(q - t * roof_len * .5, y), _v(q + t * roof_len * .5, y), .11, .07, Color("#d5dad3"))
		for j in 5:
			var q := c + t * (float(f.lo.x) * .76 + j * 1.9)
			for k in 10:
				var p := q + n * ((k - 4.5) * 3.0)
				if Geometry2D.is_point_in_polygon(p, poly): detail.box_basis(_v(p, base + h + .25), Vector3(2.85, .12, 1.65), basis, Color("#3a4d59"))
		# The two white external stair flights are a signature of the IceParc frontage.
		var station := _point([47.479394, -.549381]); var front_a := poly[0]; var front_b := poly[1]; var best := INF
		for i in poly.size():
			var a := poly[i]; var b := poly[(i + 1) % poly.size()]
			if a.distance_to(b) > 24.0 and a.lerp(b, .5).distance_to(station) < best:
				best = a.lerp(b, .5).distance_to(station); front_a = a; front_b = b
		var tangent: Vector2 = (front_b - front_a).normalized(); var normal := (station - front_a.lerp(front_b, .5)).normalized()
		var frame_ := Basis(_v(tangent, 0), Vector3.UP, _v(normal, 0))
		for side in [.26, .74]:
			var mid: Vector2 = front_a.lerp(front_b, side) + normal * 3.0
			for step in 25:
				var q: Vector2 = mid + tangent * (step - 12) * .48
				detail.box_basis(_v(q, base + .15 + step * .19), Vector3(.52, .19, 2.8), frame_, Color("#d9dbce"))
			for rail_side in [-1.0, 1.0]:
				_beam(detail, _v(mid - tangent * 6 + normal * 1.32 * rail_side, base + 1.0), _v(mid + tangent * 6 + normal * 1.32 * rail_side, base + 5.6), .045, .055, light)

	elif kind == "theatre":
		# Select the long street-facing edge toward the square for the portico.
		var target := _point([47.471182, -.551639]); var best := INF; var front_a := poly[0]; var front_b := poly[1]
		for i in poly.size():
			var a := poly[i]; var b := poly[(i + 1) % poly.size()]
			var score := a.lerp(b, .5).distance_to(target)
			if a.distance_to(b) > 12.0 and score < best: best = score; front_a = a; front_b = b
		var t: Vector2 = (front_b - front_a).normalized(); var n: Vector2 = (target - front_a.lerp(front_b, .5)).normalized(); var mid: Vector2 = front_a.lerp(front_b, .5)
		for j in 6:
			var q: Vector2 = mid + t * (j - 2.5) * 2.9 + n * .6
			_pole(detail, _v(q, base + 4.6), 7.4, .29, light)
			_beam(detail, _v(q - t * .45, base + 12), _v(q + t * .45, base + 12), .6, .24, light)
		detail.tri(_v(mid - t * 11 + n * .7, base + 13.1), _v(mid + t * 11 + n * .7, base + 13.1), _v(mid + n * .7, base + 17.4), Color("#d8ccb4"))
		var rear := c - n * 8.0
		for j in 24:
			var a: Vector2 = rear + Vector2(cos(TAU * j / 24), sin(TAU * j / 24)) * 9.5
			var b: Vector2 = rear + Vector2(cos(TAU * (j + 1) / 24), sin(TAU * (j + 1) / 24)) * 9.5
			detail.tri(_v(a, base + h + .1), _v(b, base + h + .1), _v(rear, base + h + 3.2), slate)
	elif kind == "parking":
		var t: Vector2 = f.t; var n: Vector2 = f.n; var basis := Basis(_v(n, 0), Vector3.UP, _v(t, 0))
		for side in [-1.0, 1.0]:
			for j in maxi(1, int(float(f.length) / 2.6)):
				var q: Vector2 = c + t * (j * 2.6 - float(f.length) * .44) + n * float(f.width) * side * .23
				detail.box_basis(_v(q, base + h + .02), Vector3(4.8, .025, .07), basis, Color("#d1d1bc"))
	var architecture := LineView._Geo.new()
	architecture.v = detail.v.slice(facade_count); architecture.c = detail.c.slice(facade_count); architecture.uv = detail.uv.slice(facade_count)
	detail.v.resize(facade_count); detail.c.resize(facade_count); detail.uv.resize(facade_count)
	_mesh(owner, g, _metal, 520.0)
	if detail.v.size() > 0: _mesh(owner, detail, _metal, 190.0)
	if architecture.v.size() > 0: _mesh(owner, architecture, _metal, 480.0)
	stats.landmarks += 1

func build_depot_building(_parent: Node3D, _depot: Dictionary, building: Dictionary) -> bool:
	if data.is_empty() or not str(building.source_id).begins_with("batiment.443016"): return false
	var token := "depot_" + str(building.source_id)
	if owners.has(token): return true
	var owner := Node3D.new(); owner.name = token; add_child(owner); owners[token] = owner
	var poly := PackedVector2Array()
	for p in building.pts: poly.append(Vector2(p[0], p[1]))
	if view.city: view.city.replace_hangar(poly)
	var base := float(building.base_y); var h := float(building.height_m)
	var main_hall := str(building.source_id) == "batiment.44301671"
	var g := LineView._Geo.new(); var detail := LineView._Geo.new()
	var f := _frame(poly); var c: Vector2 = f.c
	var white := Color("#d4d7cc"); var glass_ := Color("#465d55"); var red := Color("#b94c39")
	if main_hall:
		for tri in data.depot.workshop_roof_triangles:
			g.tri(_v(_point(tri[0]), base + h), _v(_point(tri[1]), base + h), _v(_point(tri[2]), base + h), white)
		var void_ := PackedVector2Array()
		for p in data.depot.workshop_void: void_.append(_point(p))
		for i in void_.size():
			var a := void_[i]; var b := void_[(i + 1) % void_.size()]
			g.quad(_v(a, base + 6.1), _v(b, base + 6.1), _v(b, base + h), _v(a, base + h), red)
			_beam(detail, _v(a, base + 6.15), _v(b, base + 6.15), .15, .3, white)
		var frame_ := _frame(void_); var ct: Vector2 = frame_.c
		var tris := Geometry2D.triangulate_polygon(void_)
		for i in range(0, tris.size(), 3): g.tri(_v(void_[tris[i]], base + 5.8), _v(void_[tris[i + 1]], base + 5.8), _v(void_[tris[i + 2]], base + 5.8), glass_)
		for k in 15:
			var t: Vector2 = frame_.t; var n: Vector2 = frame_.n
			var q := ct + t * (k - 7) * 3.3
			var a := q - n * 26; var b := q + n * 26
			# Only build roof trusses within the measured inner opening.
			for j in 30:
				var pa := a.lerp(b, float(j) / 30); var pb := a.lerp(b, float(j + 1) / 30)
				if Geometry2D.is_point_in_polygon(pa, void_) and Geometry2D.is_point_in_polygon(pb, void_):
					_beam(detail, _v(pa, base + 6.8), _v(pb, base + 6.8), .10, .15, Color("#a5b4ac"))
		var oval := PackedVector2Array(); var oval_center := Vector2.ZERO
		for ll in data.depot.get("oval_skylight", []):
			var q := _point(ll); oval.append(q); oval_center += q
		if oval.size() > 2:
			oval_center /= oval.size()
			for i in oval.size():
				var a := oval[i]; var b := oval[(i + 1) % oval.size()]
				g.tri(_v(a, base + 7.1), _v(b, base + 7.1), _v(oval_center, base + 8.0), Color("#6b7a7c"))
				_beam(detail, _v(a, base + 7.15), _v(b, base + 7.15), .18, .16, white)

	else:
		var tris := Geometry2D.triangulate_polygon(poly)
		for i in range(0, tris.size(), 3): g.tri(_v(poly[tris[i]], base + h), _v(poly[tris[i + 1]], base + h), _v(poly[tris[i + 2]], base + h), white)
	# Actual portal track envelopes leave driveable holes in the facades.
	var portals := TrackView.KeepOut.new()
	for id in building.portal_tracks:
		if view.net.edge_info.has(id): portals.add_polyline(view.net.edge_info[id].pts, 1.9)
	for i in poly.size():
		var a := poly[i]; var b := poly[(i + 1) % poly.size()]; var count_ := maxi(1, ceili(a.distance_to(b) / 1.5))
		for j in count_:
			var p := a.lerp(b, float(j) / count_); var q := a.lerp(b, float(j + 1) / count_)
			var bottom := base + 4.7 if portals.blocked(p.lerp(q, .5)) else base + .6
			g.quad(_v(p, bottom), _v(q, bottom), _v(q, base + h - .4), _v(p, base + h - .4), glass_)
			if j % 2 == 0: _beam(detail, _v(p, bottom), _v(p, base + h - .4), .15, .15, white)
			if bottom < base + 1.0: _beam(detail, _v(p, base + .3), _v(q, base + .3), .24, .60, Color("#9eaa9b"))
		_beam(detail, _v(a, base + h), _v(b, base + h), .55, .40, white)
	if not main_hall:
		var t: Vector2 = f.t; var n: Vector2 = f.n; var basis := Basis(_v(n, 0), Vector3.UP, _v(t, 0))
		for j in 18:
			var q := c + t * (j - 8.5) * 2.0
			if Geometry2D.is_point_in_polygon(q, poly): detail.box_basis(_v(q, base + h + .18), Vector3(float(f.width) * .65, .10, 1.8), basis, Color("#3d535c"))
	_mesh(owner, g, _metal, 700.0); _mesh(owner, detail, _metal, 550.0)
	return true

func _depot_context() -> void:
	if _depot_built: return
	_depot_built = true
	var owner := Node3D.new(); owner.name = "Raymond_Perron_yard"; add_child(owner)
	var g := LineView._Geo.new()
	# Long oval shelter and diagonal supports near the administration, measured on IGN.
	var poly := PackedVector2Array()
	for ll in data.depot.get("oval_shelter", []): poly.append(_point(ll))
	if poly.size() > 2:
		var f := _frame(poly); var c: Vector2 = f.c; var y := view.ground_at(_v(c, 0))
		var tris := Geometry2D.triangulate_polygon(poly)
		for i in range(0, tris.size(), 3): g.tri(_v(poly[tris[i]], y + 4.4), _v(poly[tris[i + 1]], y + 4.4), _v(poly[tris[i + 2]], y + 4.4), Color("#dedfd6"))
		for t_ in [-.3, .3]:
			var q: Vector2 = c + Vector2(f.t) * float(f.length) * t_
			_beam(g, _v(q - Vector2(f.n) * 1.5, y), _v(q, y + 4.4), .22, .22, Color("#a8b3a8"))
	# Fence / gate line and coach parking are surveyed separately from driveable tram geometry.
	for i in range(1, _depot_boundary.size()):
		var a := _depot_boundary[i - 1]; var b := _depot_boundary[i]
		var count_ := maxi(1, ceili(a.distance_to(b) / 2.5))
		for j in count_ + 1:
			var q := a.lerp(b, float(j) / count_)
			_pole(g, _v(q, view.ground_at(_v(q, 0))), 2.0, .025, Color("#667264"))
		for ht in [.8, 1.9]: _beam(g, _v(a, view.ground_at(_v(a, 0)) + ht), _v(b, view.ground_at(_v(b, 0)) + ht), .025, .035, Color("#657262"))
	for mark in data.depot.get("bus_parking", []):
		var a := _point(mark.start); var b := _point(mark.end)
		_beam(g, _v(a, view.ground_at(_v(a, 0)) + .14), _v(b, view.ground_at(_v(b, 0)) + .14), .12, .015, Color("#c8c9b7"))
	# Mark workshop service tracks at their true end positions; do not invent switches or blocking trains.
	for depot in view.net.meta.get("depots", []):
		for id in depot.tracks:
			if not view.net.edge_info.has(id): continue
			var e: Dictionary = view.net.edge_info[id]
			if not bool(e.get("buffer_stop", false)): continue
			var p: Vector3 = view.pos3(id, view.net.graph.edges[id].length)
			g.box(p + Vector3.UP * .65, Vector3(2.0, .18, .16), Color("#a94c3c"))
	_mesh(owner, g, _metal, 600.0)

func _copper_pavilion(owner: Node3D, profile: Dictionary, _center: Vector2) -> void:
	# Specific Saint-Gilles shelter wraps an existing copper-clad bell pavilion.
	var p := _point([47.5065413, -.5896151]); var y := _floor(p, profile)
	var g := LineView._Geo.new(); var cream := Color("#d2c8a9"); var copper := Color("#7c9c88")
	g.box(_v(p, y + 1.52), Vector3(2.35, 3.04, 2.35), cream)
	for level in 9:
		var h := 3.05 + level * .40; var w := 3.0 - level * .17
		g.box(_v(p, y + h + .20), Vector3(w, .40, w), copper.darkened(.05 * (level % 2)))
		g.box(_v(p, y + h), Vector3(w + .035, .035, w + .035), copper.darkened(.21))
	var top := _v(p, y + 8.1)
	for i in 4:
		var a := p + Vector2(cos(PI * .25 + i * PI * .5), sin(PI * .25 + i * PI * .5)) * 1.03
		var b := p + Vector2(cos(PI * .25 + (i + 1) * PI * .5), sin(PI * .25 + (i + 1) * PI * .5)) * 1.03
		g.tri(_v(a, y + 6.65), _v(b, y + 6.65), top, copper.darkened(i * .025))
	_mesh(owner, g, _metal, 320.0)
