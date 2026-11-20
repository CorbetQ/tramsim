extends SceneTree
## Ouvrages d'art cohérents (tablier unique par pont, tools/import/bridges.py), même état que le jeu en mode libre
## (réseau physique, tram-trains compris ; CityScene.bind_network : tabliers calés sur les voies) :
## 1. voies portées : sur les tronçons de pont des voies, un tablier présent sous la voie est à moins de
##    DECK_TOL m du profil (rail - 0,1 m) ;
## 2. rampes continues : pas de marche (dénivelé entre sommets > rampe de 10 % + STEP_MAX m),
##    cassure d'axe <= ANGLE_MAX° par tranche de 5 m, extrémités raccordées au sol (au plus STEP_MAX m au-dessus du
##    sol affiché) sauf raccord à un autre tablier ou à une voie portée ;
## 3. voies d'un même ouvrage fusionnées : pas deux tabliers parallèles côte à côte (< 2,5 m d'écart latéral) à
##    moins de 2,5 m d'altitude l'un de l'autre.
## Chaque critère est compté ; la ville échoue si une part dépasse MAX_SHARE (tolérance pour les défauts des données
## sources, voir la sortie détaillée ; état avant tools/import/bridges.py à Nantes : 133 segments non fusionnés,
## 107 marches pour 80 tabliers).
## 4. aucun tablier à plus de HIGH_MAX m au-dessus du sol affiché (altitude aberrante).
## Args optionnels : -- <villes séparées par des virgules>
const DECK_TOL := 0.3
const STEP_MAX := 0.2
const ANGLE_MAX := 5.0
const MAX_SHARE := {"porte": 0.12, "marche": 0.02, "axe": 0.05, "extremite": 0.45, "fusion": 0.10, "haut": 0.0}
const HIGH_MAX := 30.0

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
		if not TerrainView.available(src): continue
		var free := "res://data/free/%s.json" % src
		var net := NetworkLoader.new(); net.load_file(free if FileAccess.file_exists(free) else paths[0])
		if not net.has_geometry() or not net.meta.has("origin"): continue
		_city(c, src, net)
	print("TOTAL_ECHECS|%d" % fails)
	quit(1 if fails > 0 else 0)

func _city(c: String, src: String, net: NetworkLoader) -> void:
	var city := CityScene.new()
	if not city.open(src, net.meta.origin): city.free(); return
	city.bind_network(net)
	var bad := {"porte": 0, "marche": 0, "axe": 0, "extremite": 0, "fusion": 0, "haut": 0}
	var shown := 0
	var carried := 0
	# 1. voies portées
	for id in net.edge_info:
		var info: Dictionary = net.edge_info[id]
		var L: float = net.graph.edges[id].length
		for sp in info.get("bridge", []):
			var s := float(sp[0]) + 1.0
			while s < float(sp[1]) - 1.0:
				var q := net.point_on(id, s)
				var cpt := Vector2((q.p.x - city.position.x) / city._x_scale, q.p.y - city.position.z)
				var dy := _carrying_deck(city, cpt, q.dir, q.y)
				if not is_nan(dy):
					carried += 1
					if absf(dy) > DECK_TOL:
						bad.porte += 1
						if shown < 6: shown += 1; print("  %s %s @%.0f : tablier à %+.2f m du rail-0,1" % [c, id, s, dy])
				s += 4.0
	# 2. continuité des tabliers et 3. fusion
	for di in city._decks.size():
		var d: Array = city._decks[di]
		var pl: PackedVector3Array = d[2]
		for i in range(pl.size() - 1):
			var a := pl[i]; var b := pl[i + 1]
			var h := Vector2(b.x - a.x, b.z - a.z).length()
			# marche : dénivelé entre deux sommets au-delà d'une rampe de 10 % de plus de STEP_MAX
			if absf(b.y - a.y) > h * 0.1 + STEP_MAX:
				bad.marche += 1
				if shown < 30: shown += 1; print("  %s tablier %d sommet %d : marche %.2f m sur %.1f m" % [c, di, i, b.y - a.y, h])
			if i > 0:
				var u := Vector2(a.x - pl[i - 1].x, a.z - pl[i - 1].z); var v := Vector2(b.x - a.x, b.z - a.z)
				var turn := rad_to_deg(absf(u.angle_to(v)))
				if turn > ANGLE_MAX * maxf(1.0, (u.length() + v.length()) * 0.5 / 5.0):
					bad.axe += 1
					if shown < 12: shown += 1; print("  %s tablier %d sommet %d : cassure d'axe %.1f°" % [c, di, i, turn])
		for p in pl:   # aucun tablier à plus de HIGH_MAX m au-dessus du sol (altitude aberrante)
			if p.y - city.height_city(p.x, p.z) > HIGH_MAX:
				bad.haut += 1
				if shown < 20: shown += 1; print("  %s tablier %d : %.0f m au-dessus du sol en (%.0f, %.0f)" % [c, di, p.y - city.height_city(p.x, p.z), p.x, p.z])
				break
		for e in [0, pl.size() - 1]:
			var p := pl[e]
			var g := city.height_city(p.x, p.z)
			if p.y - g <= STEP_MAX + 0.04: continue   # extrémité au sol ou entrant dans le talus
			if _joined(city, di, p) or not city._tracks_near(Vector2(p.x, p.z), float(d[1]) * 0.5 + 4.0).is_empty(): continue
			bad.extremite += 1
			if shown < 16: shown += 1; print("  %s tablier %d extrémité (%.0f, %.0f) : %.2f m au-dessus du sol" % [c, di, p.x, p.z, p.y - g])
		bad.fusion += _side_by_side(city, di)
	var segs := 0
	for d in city._decks: segs += (d[2] as PackedVector3Array).size() - 1
	# parts tolérées (données BD TOPO : bretelles en Y, ouvrages voisins distincts, culées sur talus non relevés) ;
	# une régression de l'import ou du calage les dépasse
	var share := {"porte": float(bad.porte) / maxf(carried, 1.0), "marche": float(bad.marche) / maxf(segs, 1.0),
		"axe": float(bad.axe) / maxf(segs, 1.0), "extremite": float(bad.extremite) / maxf(city._decks.size() * 2.0, 1.0),
		"fusion": float(bad.fusion) / maxf(segs, 1.0), "haut": float(bad.haut)}
	var ok := true
	for k in share:
		if share[k] > float(MAX_SHARE[k]): ok = false
	if not ok: fails += 1
	print("%s %s : %d tabliers (%d segments), %d points de voie portés ; écarts %s ; parts %s" % ["ok" if ok else "ECHEC", c, city._decks.size(), segs, carried, str(bad),
		", ".join(share.keys().map(func(k): return "%s %.1f %%" % [k, share[k] * 100.0]))])
	city.free()

## Écart (tablier - (rail - 0,1)) du tablier parallèle à la voie qui la porte (à moins de 2 m sous le rail), NAN sinon.
func _carrying_deck(city: CityScene, p: Vector2, dir: Vector2, rail: float) -> float:
	var best := NAN
	for it in city._deck_cells.get(Vector2i(floori(p.x / 32.0), floori(p.y / 32.0)), []):
		var d: Array = city._decks[it[0]]
		var pl: PackedVector3Array = d[2]
		var a := Vector2(pl[it[1]].x, pl[it[1]].z); var b := Vector2(pl[it[1] + 1].x, pl[it[1] + 1].z)
		if (b - a).length() < 0.01 or absf((b - a).normalized().dot(dir)) < 0.9: continue
		var t := (p - a).dot(b - a) / (b - a).length_squared()
		if t < -0.01 or t > 1.01 or (a + (b - a) * t).distance_to(p) > float(d[1]) * 0.5: continue
		t = clampf(t, 0.0, 1.0)
		var y := lerpf(pl[it[1]].y, pl[it[1] + 1].y, t)
		var dy := y - (rail - 0.1)
		if dy < -2.0 or dy > 2.0: continue
		if is_nan(best) or absf(dy) < absf(best): best = dy
	return best

## Extrémité posée sur un autre tablier (bretelle, ouvrage contigu) à moins de STEP_MAX m.
func _joined(city: CityScene, di: int, p: Vector3) -> bool:
	for it in city._deck_cells.get(Vector2i(floori(p.x / 32.0), floori(p.z / 32.0)), []):
		if int(it[0]) == di: continue
		var y := city.deck_city(p.x, p.z, int(it[0]))
		if not is_nan(y) and absf(y - p.y) <= STEP_MAX + 0.3: return true
	return false

## Tabliers parallèles côte à côte (même ouvrage non fusionné) : nombre de segments en cause pour le tablier di.
func _side_by_side(city: CityScene, di: int) -> int:
	var d: Array = city._decks[di]
	var pl: PackedVector3Array = d[2]
	var n := 0
	for i in range(pl.size() - 1):
		var m := (pl[i] + pl[i + 1]) * 0.5
		var u := Vector2(pl[i + 1].x - pl[i].x, pl[i + 1].z - pl[i].z)
		if u.length() < 0.5: continue
		u = u.normalized()
		for it in city._deck_cells.get(Vector2i(floori(m.x / 32.0), floori(m.z / 32.0)), []):
			if int(it[0]) <= di: continue
			var e: Array = city._decks[it[0]]
			var ql: PackedVector3Array = e[2]
			var a := ql[it[1]]; var b := ql[it[1] + 1]
			var v := Vector2(b.x - a.x, b.z - a.z)
			if v.length() < 0.5 or absf(v.normalized().dot(u)) < 0.9: continue
			var c := Geometry2D.get_closest_point_to_segment(Vector2(m.x, m.z), Vector2(a.x, a.z), Vector2(b.x, b.z))
			var gap := c.distance_to(Vector2(m.x, m.z)) - (float(d[1]) + float(e[1])) * 0.5
			var t := clampf((Vector2(m.x, m.z) - Vector2(a.x, a.z)).dot(v) / v.length_squared(), 0.0, 1.0)
			if gap < 2.5 and absf(lerpf(a.y, b.y, t) - m.y) < 2.5:
				n += 1
				break
	return n
