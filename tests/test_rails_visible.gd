extends SceneTree
## Rails visibles sur tout le réseau : le sol (tuiles détaillées, et relief lointain remaillé en corridors, affiché
## tant que les tuiles détaillées ne sont pas chargées) reste sous le champignon du rail moins 2 cm, tous les 4 m,
## hors ponts, tunnels et découpes de portail. Réseau physique (data/free, tram-trains compris) s'il existe, sinon
## chaque ligne de data/index.json.
## Fentes : au pied du talus de plateforme (TrackView._skirt), le sol n'est pas plus de 5 cm sous le talus (pas de
## vide visible entre plateforme et terrain) ; au-delà de SKIRT_DEPTH, mur de soutènement jusqu'au sol.
## Args optionnels : -- <villes séparées par des virgules>
## Tolérance : au plus TOL_SHARE des points de sol détaillé entre 2 cm et TOL_M m au-dessus (arrondis de l'import,
## triangles étirés résiduels) ; aucun sur le relief lointain ; aucun à plus de TOL_M.
const STEP := 4.0
const TOL_M := 0.35
const TOL_SHARE := 0.002
const GAP_SHARE := 0.002    # fentes plateforme / terrain (remblai de plus de SKIRT_DEPTH m hors ouvrage)
const FAR_EPS := 0.03       # interpolation des triangles de corridor aux raccords de cellules

var fails := 0

func _init() -> void:
	var only := PackedStringArray()
	if OS.get_cmdline_user_args().size() > 0: only = OS.get_cmdline_user_args()[0].split(",")
	var idx: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/index.json"))
	var by_city := {}
	for n in idx.networks:
		var c := str(n.id).split("_")[0]
		if not only.is_empty() and not c in only: continue
		if not by_city.has(c): by_city[c] = []
		by_city[c].append(str(n.path))
	for c in by_city:
		var paths: Array = by_city[c]
		var first := NetworkLoader.new(); first.load_file(paths[0])
		var src := str(first.meta.get("source_id", ""))
		var free := "res://data/free/%s.json" % src
		if FileAccess.file_exists(free): paths = [free]
		var stats := [0, 0, 0, 0.0, 0]   # contrôles, sol détaillé limite, relief lointain, pire écart, fentes
		for p in paths:
			var net := NetworkLoader.new(); net.load_file(p)
			if not net.has_geometry() or not net.meta.has("origin") or not CityScene.available(src): continue
			_check(net, src, p, stats)
		if stats[0] == 0: continue
		var ok: bool = stats[2] == 0 and stats[3] <= TOL_M and stats[1] <= stats[0] * TOL_SHARE and stats[4] <= stats[0] * GAP_SHARE
		if not ok: fails += 1
		print("%s %s : %d points, sol détaillé > rail-2 cm : %d, relief lointain : %d, pire %.2f m, fentes plateforme/sol : %d" % ["ok" if ok else "ECHEC", c, stats[0], stats[1], stats[2], stats[3], stats[4]])
	print("TOTAL_ECHECS|%d" % fails)
	quit(1 if fails > 0 else 0)

func _check(net: NetworkLoader, src: String, path: String, stats: Array) -> void:
	var city := CityScene.new()
	if not city.open(src, net.meta.origin): city.free(); return
	city.bind_network(net)
	var tv: TerrainView = city.terrain
	var shown := 0
	for id in net.edge_info:
		var info: Dictionary = net.edge_info[id]
		var L: float = net.graph.edges[id].length
		var offs: Array = [0.0] if info.raw or info.get("physical", false) else [-LineView.TRACK_OFFSET, LineView.TRACK_OFFSET]
		var n := maxi(1, ceili(L / STEP))
		for i in n + 1:
			var s := L * i / n
			var sp: Array = info.get("tunnel", []) + info.get("bridge", [])
			if NetworkLoader.in_spans(sp, s) or NetworkLoader.in_spans(sp, s - 1.0) or NetworkLoader.in_spans(sp, s + 1.0): continue   # culées, portails
			var q := net.point_on(id, s)
			for o in offs:
				var c := Vector2((q.p.x - q.dir.y * o - city.position.x) / city._x_scale, q.p.y + q.dir.x * o - city.position.z)
				if city._portal_cut.blocked(c): continue
				stats[0] += 1
				var top: float = q.y + TrackView.EMBED_TOP_M - 0.02
				var h := NAN
				if tv != null: h = tv.height(c.x, c.y)
				if not is_nan(h) and h > top:
					stats[1] += 1; stats[3] = maxf(stats[3], h - top)
					if shown < 4: shown += 1; print("  sol %s %s @%.0f : +%.2f m" % [path.get_file(), id, s, h - top])
				# fente plateforme / terrain : le talus (TrackView._skirt, même règle) atteint le sol à son pied ; un mur
				# vertical au-delà de SKIRT_DEPTH ferme toujours la fente
				for sd in ([-1.0, 1.0] if o == 0.0 else [signf(o)]):
					var bed: float = q.y + TrackView.BED_TOP_M
					var at := func(lat: float) -> float:
						var e2 := Vector2((q.p.x - q.dir.y * lat - city.position.x) / city._x_scale, q.p.y + q.dir.x * lat - city.position.z)
						return city.height_city(e2.x, e2.y)
					var dd := TrackView.skirt_drop(bed, at.call(o + sd * (1.75 + 0.6)))
					if dd > TrackView.SKIRT_DEPTH: continue
					var hf: float = at.call(o + sd * (1.75 + dd * 1.5))
					if hf < bed - dd - 0.05:
						stats[4] += 1
						if shown < 10: shown += 1; print("  fente %s %s @%.0f : sol %.2f m sous le pied du talus" % [path.get_file(), id, s, bed - dd - hf])
				var f := tv.far_tri(c.x, c.y) if tv != null else city.height_city(c.x, c.y)
				if f > top + FAR_EPS:
					stats[2] += 1; stats[3] = maxf(stats[3], f - top)
					if shown < 8: shown += 1; print("  lointain %s %s @%.0f : +%.2f m" % [path.get_file(), id, s, f - top])
	city.free()
