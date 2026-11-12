extends SceneTree
## Géographie et stations : profils en long (pentes plausibles, pente utilisée par la physique), relief et ponts,
## types de stations (Belle-Beille Campus, Haluchère), quais jamais sur une voie et qui suivent la courbure.
var fails := 0
func check(c: bool, m: String) -> void:
	if not c: fails += 1; printerr("ECHEC: ", m)
	else: print("ok: ", m)

func _init() -> void:
	_grades()
	_physics()
	_terrain()
	_stations()
	quit(1 if fails > 0 else 0)

## Pentes : profil présent partout, rampes <= 8 % (tolérance d'échantillonnage) sur 20 m glissants.
func _grades() -> void:
	var files: Array = []
	for d in ["res://data/networks/", "res://data/free/"]:
		for f in DirAccess.get_files_at(d):
			if f.ends_with(".json"): files.append(d + f)
	var worst := 0.0; var worst_raw := 0.0; var worst_at := ""; var missing := 0; var total := 0; var relief := 0.0
	for path in files:
		var net := NetworkLoader.new(); net.load_file(path)
		for id in net.edge_info:
			var info: Dictionary = net.edge_info[id]
			if info.pts.size() < 2: continue
			total += 1
			if (info.ys as PackedFloat32Array).size() != info.pts.size(): missing += 1; continue
			var L: float = net.graph.edges[id].length
			var s := 0.0
			while s + 20.0 <= L:
				var g := absf(net.height_at(id, s + 20.0) - net.height_at(id, s)) / 20.0
				if info.raw: worst_raw = maxf(worst_raw, g)
				elif g > worst: worst = g; worst_at = "%s %s @%d" % [path.get_file(), id, s]
				s += 10.0
			relief = maxf(relief, absf(float(info.ys[0]) - float(info.ys[-1])))
	check(total > 0 and missing == 0, "profil en long sur toutes les arêtes (%d arêtes, %d sans)" % [total, missing])
	check(worst <= 0.085, "rampes <= 8 %% sur 20 m (max %.1f %% : %s)" % [worst * 100.0, worst_at])
	check(worst_raw <= 0.12, "communications de voies : pente <= 12 %% (max %.1f %%)" % (worst_raw * 100.0))
	check(relief > 5.0, "relief réel présent (dénivelé max d'une arête %.1f m)" % relief)

## Physique : la pente de la voie sous la rame freine en montée, entraîne en descente, signe selon le sens de marche.
func _physics() -> void:
	var net := NetworkLoader.new(); net.load_file("res://data/networks/lyon_t1.json")
	var best := ""; var bg := 0.0
	for id in net.edge_info:
		var L: float = net.graph.edges[id].length
		for k in range(1, 10):
			var g := net.grade_at(id, L * k / 10.0)
			if absf(g) > absf(bg): bg = g; best = id
	check(absf(bg) > 0.01, "pente non nulle sur une ligne réelle (lyon_t1 : %.1f %%)" % (bg * 100.0))
	var up := TrainPhysics.new(VehicleLibrary.citadis_302()); var flat := TrainPhysics.new(VehicleLibrary.citadis_302())
	var down := TrainPhysics.new(VehicleLibrary.citadis_302())
	for i in 300:
		up.step(0.05, 1.0, 0.06); flat.step(0.05, 1.0, 0.0); down.step(0.05, 0.0, -0.06)
	check(up.speed < flat.speed, "montée de 6 %% : accélération réduite (%.1f < %.1f m/s)" % [up.speed, flat.speed])
	check(down.speed > 0.5, "descente de 6 %% sans traction : la rame prend de la vitesse (%.1f m/s)" % down.speed)
	var L: float = net.graph.edges[best].length
	var mid := L * 0.5
	var dy := net.height_at(best, mid + 10.0) - net.height_at(best, mid - 10.0)
	check(signf(net.grade_at(best, mid)) == signf(dy), "pente orientée selon l'arête (%.1f %%)" % (net.grade_at(best, mid) * 100.0))
	var sched: Array[float] = []
	var fwd := MissionSession.new(net, VehicleLibrary.citadis_302(), best, mid, sched)
	var bwd := MissionSession.new(net, VehicleLibrary.citadis_302(), best, mid, sched)
	bwd.direction = -1
	for m in [fwd, bwd]:
		m.phys.speed = 4.0
		for i in 40: m.tick(0.05, 0.0)
	var down_s: float = (bwd if dy > 0.0 else fwd).phys.speed; var up_s: float = (fwd if dy > 0.0 else bwd).phys.speed
	check(down_s > up_s + 0.05, "sur rame en marche sur l'erre : descente %.2f m/s > montée %.2f m/s (pente signée par le sens de marche)" % [down_s, up_s])

## Relief et ouvrages (Angers) : terrain, pont sur la Maine au-dessus de l'eau, voie posée sur le terrain ailleurs.
func _terrain() -> void:
	var net := NetworkLoader.new(); net.load_file("res://data/networks/angers_a.json")
	var city := CityScene.new()
	check(city.open("angers", net.meta.origin) and city.has_terrain, "scène d'Angers avec relief")
	var on_bridge := 0; var gap := 0.0; var flat_err := 0.0; var n := 0
	for id in net.edge_info:
		var info: Dictionary = net.edge_info[id]
		var L: float = net.graph.edges[id].length
		var s := 5.0
		while s < L:
			var q: Dictionary = net.point_on(id, s)
			var p := Vector3(q.p.x, 0, q.p.y)
			var h := city.height_at(p)
			if NetworkLoader.in_spans(info.bridge, s):
				on_bridge += 1; gap = maxf(gap, float(q.y) - h)
			elif not NetworkLoader.in_spans(info.tunnel, s):
				flat_err = maxf(flat_err, absf(float(q.y) - h)); n += 1
			s += 10.0
	check(on_bridge > 10 and gap > 4.0, "pont sur la Maine : voie au-dessus du terrain (%.1f m)" % gap)
	check(n > 100 and flat_err < 0.8, "voie au niveau du sol hors ouvrages (écart max %.2f m)" % flat_err)
	check(city._decks.size() > 5, "ponts routiers BD TOPO (%d tabliers)" % city._decks.size())
	var wl := 0
	for k in city._water_lv: wl += (city._water_lv[k] as Array).size()
	check(wl > 0, "niveaux d'eau BD TOPO")
	city.free()

## Stations : types attendus, côté des portes, quais hors voies et parallèles à la voie.
func _stations() -> void:
	var cases := {"res://data/free/angers.json": [["Belle-Beille Campus", "multi", "both"], ["Jean Vilar", "lateral", "right"]],
		"res://data/free/nantes.json": [["Haluchère - Batignolles", "multi", "both"], ["Bouffay", "lateral", "right"]],
		"res://data/networks/angers_b.json": [["Belle-Beille Campus", "multi", "both"]],
		"res://data/networks/lyon_t1.json": [], "res://data/networks/bordeaux_a.json": []}
	for path in cases:
		var net := NetworkLoader.new(); net.load_file(path)
		var view := LineView.new(); root.add_child(view)
		view.build(net, net.graph.edges.keys()[0], VehicleLibrary.default_for(net.meta))
		var lay: StationLayout = view.layout
		check(lay != null and not lay.groups.is_empty(), "%s : types de stations chargés" % path.get_file())
		for c in cases[path]:
			var found := false
			for i in net.stations.size():
				if net.stations[i].name == c[0]:
					found = true
					check(lay.infos[i].type == c[1] and lay.infos[i].doors == c[2], "%s : %s = %s (%s), portes %s" % [path.get_file(), c[0], c[1], lay.infos[i].type, lay.infos[i].doors])
					var pf := 0
					for p in lay.platforms: pf += int(p.station == i)
					check(pf >= 1, "%s : %s a %d quai(s)" % [path.get_file(), c[0], pf])
			check(found, "%s : station %s présente" % [path.get_file(), c[0]])
		# voies rendues (entraxe élargi compris, communications de voies comprises)
		var ko := TrackView.KeepOut.new()
		for id in net.graph.edges:
			var L: float = net.graph.edges[id].length
			var m := maxi(2, ceili(L / 2.0) + 1)
			var prev := view.pos3(id, 0.0)
			for k in range(1, m):
				var q := view.pos3(id, L * k / (m - 1))
				ko.add_segment(Vector2(prev.x, prev.z), Vector2(q.x, q.z), StationLayout.GAP - 0.2)
				prev = q
		var bad := 0; var pts := 0; var served := {}
		for p in lay.platforms:
			served[p.station] = true
			for k in (p.inner as PackedVector3Array).size():
				var a: Vector3 = p.inner[k]; var b: Vector3 = p.outer[k]
				for q in [a.lerp(b, 0.05), a.lerp(b, 0.5), b]:
					pts += 1
					if ko.blocked(Vector2(q.x, q.z)): bad += 1
		check(pts > 0 and bad == 0, "%s : aucun quai sur une voie (%d points, %d en défaut)" % [path.get_file(), pts, bad])
		check(served.size() >= net.stations.size() * 0.85, "%s : %d/%d arrêts avec quai" % [path.get_file(), served.size(), net.stations.size()])
		# courbure : bord de quai à distance constante du centre de la voie (polyligne décalée, pas une boîte droite)
		var on_track := TrackView.KeepOut.new()
		for id in net.graph.edges:
			var L: float = net.graph.edges[id].length
			var m := maxi(2, ceili(L / 2.0) + 1)
			var prev := view.pos3(id, 0.0)
			for k in range(1, m):
				var q := view.pos3(id, L * k / (m - 1))
				on_track.add_segment(Vector2(prev.x, prev.z), Vector2(q.x, q.z), 0.15)
				prev = q
		var dev := 0.0; var off_track := 0
		for p in lay.platforms:
			for k in (p.inner as PackedVector3Array).size():
				var c: Vector3 = p.center[k]
				dev = maxf(dev, absf(Vector2(p.inner[k].x - c.x, p.inner[k].z - c.z).length() - StationLayout.GAP))
				if not on_track.blocked(Vector2(c.x, c.z)): off_track += 1
		check(dev < 0.05 and off_track == 0, "%s : quais parallèles à la voie (bord à %.2f m, écart %.3f m, %d hors voie)" % [path.get_file(), StationLayout.GAP, dev, off_track])
		# stations multi-quais : au moins 3 quais au total
		for c in cases[path]:
			if c[1] != "multi": continue
			var tot := 0
			for p in lay.platforms: tot += int(net.stations[p.station].name == c[0])
			check(tot >= 3, "%s : %s compte %d quais" % [path.get_file(), c[0], tot])
		view.queue_free()
