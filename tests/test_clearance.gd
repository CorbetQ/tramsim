extends SceneTree
## Gabarit de la rame sur toutes les lignes à décor IGN : la voie est échantillonnée tous les 2 m (axe de chaque sens)
## et rien ne doit entrer dans le gabarit (CityScene.GAUGE_H au-dessus du rail, demi-largeur 1,5 m par sens) :
## tablier routier BD TOPO traversé, pile, terrain au-dessus du rail hors tunnel (voie enterrée sans tube),
## plan d'eau au-dessus du rail. Même état que le jeu : CityScene.bind_network.
## Args optionnels : -- <préfixes de villes>   (ex. rouen,lehavre)
const STEP := 2.0
const HALF := 1.5

var fails := 0
var checks := 0

func _init() -> void:
	var only := PackedStringArray()
	var args := OS.get_cmdline_user_args()
	if args.size() > 0: only = args[0].split(",")
	var idx: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/index.json"))
	var per_city := {}
	for n in idx.networks:
		var c := str(n.id).split("_")[0]
		if not only.is_empty() and not c in only: continue
		var net := NetworkLoader.new(); net.load_file(str(n.path))
		var src := str(net.meta.get("source_id", ""))
		if not net.has_geometry() or not net.meta.has("origin") or not CityScene.available(src): continue
		if Time.get_ticks_msec() > 900000:   # borne de durée (15 min)
			print("ECHEC durée dépassée avant %s" % n.id); fails += 1; break
		var bad := _line(net, src, str(n.id))
		per_city[c] = int(per_city.get(c, 0)) + bad
	for c in per_city: print("%s %s : %d point(s) hors gabarit" % ["ok" if per_city[c] == 0 else "ECHEC", c, per_city[c]])
	print("gabarit : %d contrôles, %d échecs" % [checks, fails])
	print("TOTAL_ECHECS|%d" % fails)
	quit(1 if fails > 0 else 0)

func _line(net: NetworkLoader, src: String, line_id: String) -> int:
	var city := CityScene.new()
	if not city.open(src, net.meta.origin): city.free(); return 0
	city.bind_network(net)
	# piles de tous les tabliers, indexées par cellule de 32 m
	var piles := {}
	for d in city._decks:
		for p in city.deck_piles(d):
			var k := Vector2i(floori(p[0].x / 32.0), floori(p[0].z / 32.0))
			if not piles.has(k): piles[k] = []
			piles[k].append(p)
	var bad := 0
	var reported := {}
	for id in net.edge_info:
		var info: Dictionary = net.edge_info[id]
		var L: float = net.graph.edges[id].length
		var offs: Array = [0.0] if info.raw or info.get("physical", false) else [-LineView.TRACK_OFFSET, LineView.TRACK_OFFSET]
		var n := maxi(1, ceili(L / STEP))
		for i in n + 1:
			var s := L * i / n
			if NetworkLoader.in_spans(info.get("tunnel", []), s): continue
			var q := net.point_on(id, s)
			for o in offs:
				var pn := Vector3(q.p.x - q.dir.y * o, q.y, q.p.y + q.dir.x * o)
				var c := Vector2((pn.x - city.position.x) / city._x_scale, pn.z - city.position.z)
				var why := _obstacle(city, piles, c, q.y, NetworkLoader.in_spans(info.get("bridge", []), s))
				checks += 1
				if why == "": continue
				bad += 1
				var key := "%s|%s|%d" % [id, why, int(s / 50.0)]
				if not reported.has(key) and reported.size() < 12:
					reported[key] = true
					print("ECHEC %s %s @%.0f m : %s (rail %.1f)" % [line_id, id, s, why, q.y])
	fails += bad
	city.free()
	return bad

func _obstacle(city: CityScene, piles: Dictionary, c: Vector2, rail: float, on_bridge: bool) -> String:
	var top := rail + CityScene.GAUGE_H
	# tabliers BD TOPO
	for it in city._deck_cells.get(Vector2i(floori(c.x / 32.0), floori(c.y / 32.0)), []):
		var d: Array = city._decks[it[0]]
		var pl: PackedVector3Array = d[2]
		var a := Vector2(pl[it[1]].x, pl[it[1]].z); var b := Vector2(pl[it[1] + 1].x, pl[it[1] + 1].z)
		var t := clampf((c - a).dot(b - a) / maxf((b - a).length_squared(), 1e-4), 0.0, 1.0)
		if (a + (b - a) * t).distance_to(c) > float(d[1]) * 0.5 + HALF: continue
		var y := lerpf(pl[it[1]].y, pl[it[1] + 1].y, t)
		if y > rail + 0.25 and y - 1.1 < top:
			return "tablier traversé (dessus %.1f)" % y
	for k in [Vector2i(floori(c.x / 32.0), floori(c.y / 32.0))]:
		for dx in [-1, 0, 1]:
			for dz in [-1, 0, 1]:
				for p in piles.get(k + Vector2i(dx, dz), []):
					var pc: Vector3 = p[0]
					if Vector2(pc.x, pc.z).distance_to(c) < 0.65 + HALF and float(p[1]) - 1.5 < top and pc.y - 1.1 > rail:
						return "pile"
	if not on_bridge and city.has_terrain:
		var h := city.height_city(c.x, c.y)
		if h > rail + 0.5 and not city._portal_cut.blocked(c):
			return "terrain au-dessus du rail (%.1f)" % h
	var w := city.water_at(c)
	if not is_nan(w) and w > rail - 0.3:
		return "eau au-dessus du rail (%.1f)" % w
	return ""
