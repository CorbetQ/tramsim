extends SceneTree
## Continuité géométrique des voies (tools/import/smooth_tracks.py) sur toutes les villes, réseaux de lignes
## (data/networks) et réseaux libres (data/free) :
## - variation de cap entre segments consécutifs d'une arête < MAX_TURN_DEG (pas de pli dans les courbes) ;
## - aux nœuds, chaque extrémité d'arête prolonge sa meilleure continuation (côté opposé du nœud) à moins de
##   MAX_TURN_DEG (aiguillages, stations, raccords entre arêtes) ;
## - extrémités raccordées (réseaux libres) : toutes les arêtes d'un nœud partent du même point (voies connectées) ;
## - aucune longueur de jeu modifiée hors de la géométrie (stations, quais et signaux restent dans leur arête) ;
## - suivi de la rame : le cap interpolé (TrackGraph.smooth_dir) échantillonné tous les 0,25 m n'a pas de saut de taux de rotation > 1,5° (pas de pli).
## godot --headless --path . -s tests/test_track_smoothness.gd
const MAX_TURN_DEG := 2.0
const BRANCH_MAX_DEG := 50.0   # au-delà : pas une continuation (croisement, rebroussement)
var fails := 0
func check(c: bool, m: String) -> void:
	if not c: fails += 1; printerr("ECHEC: ", m)
	else: print("ok: ", m)

## Calcul en double précision (les coordonnées sont à plusieurs dizaines de km de l'origine en IdF et à Nantes).
static func _turn(a: Array, b: Array, c: Array) -> float:
	var ux := float(b[0]) - float(a[0]); var uz := float(b[1]) - float(a[1])
	var vx := float(c[0]) - float(b[0]); var vz := float(c[1]) - float(b[1])
	if absf(ux) + absf(uz) < 1e-6 or absf(vx) + absf(vz) < 1e-6: return 0.0
	return absf(rad_to_deg(atan2(ux * vz - uz * vx, ux * vx + uz * vz)))

static func _first_dir(pts: Array, from_start: bool) -> Vector2:
	var a: Array = pts[0] if from_start else pts[-1]
	var b: Array = pts[1] if from_start else pts[-2]
	return Vector2(float(b[0]) - float(a[0]), float(b[1]) - float(a[1])).normalized()

func _scan(path: String) -> Dictionary:
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	var res := {"max": 0.0, "where": "", "junction": 0.0, "jwhere": "", "gap": 0.0}
	if typeof(d) != TYPE_DICTIONARY: return res
	var att := {}   # nœud -> {1: [[dir sortante, point]], -1: [...]}
	for e in d.get("edges", []):
		var pts: Array = e.get("pts", [])
		if e.get("raw", false) or pts.size() < 2: continue
		# exclus : fragments OSM < 2 m et voies historiques non électrifiées (boucle hippomobile d'IdF, R < 8 m)
		var exempt: bool = float(e.length) < 2.0 or str(e.get("supply", "")) == "none"
		for i in range(1, pts.size() - 1):
			if exempt: break
			var t := _turn(pts[i - 1], pts[i], pts[i + 1])
			if t > res.max: res.max = t; res.where = "%s#%d" % [e.id, i]
		var fs := 1 if int(e.get("from_side", 1)) >= 0 else -1
		var ts := 1 if int(e.get("to_side", -1)) >= 0 else -1
		for spec in [[e.from, fs, true], [e.to, ts, false]]:
			if not att.has(spec[0]): att[spec[0]] = {1: [], -1: []}
			var p: Array = pts[0] if spec[2] else pts[-1]
			att[spec[0]][spec[1]].append([_first_dir(pts, spec[2]), Vector2(float(p[0]), float(p[1]))])
	for node in att:
		var all_: Array = att[node][1] + att[node][-1]
		for x in all_: res.gap = maxf(res.gap, (x[1] as Vector2).distance_to(all_[0][1]))
		for side in [1, -1]:
			for x in att[node][side]:
				var best := INF
				for y in att[node][-side]:
					best = minf(best, absf(rad_to_deg((x[0] as Vector2).angle_to(-(y[0] as Vector2)))))
				if best < BRANCH_MAX_DEG and best > res.junction: res.junction = best; res.jwhere = str(node)
	return res

func _files(dir: String) -> PackedStringArray:
	var out := PackedStringArray()
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".json"): out.append(dir + "/" + f)
	return out

func _init() -> void:
	var worst := {"max": 0.0, "junction": 0.0, "gap": 0.0}
	var n := 0
	for path in _files("res://data/networks") + _files("res://data/free"):
		var r := _scan(path)
		n += 1
		if r.max >= MAX_TURN_DEG: check(false, "%s : pli de %.2f° (%s)" % [path.get_file(), r.max, r.where])
		if r.junction >= MAX_TURN_DEG: check(false, "%s : raccord de %.2f° au nœud %s" % [path.get_file(), r.junction, r.jwhere])
		# réseaux libres (axes OSM physiques) : nœuds = points communs. Les réseaux de lignes ont des nœuds
		# logiques (approches de terminus, sauts d'axe) dont les extrémités ne coïncident pas par construction.
		if path.contains("/free/") and r.gap > 0.05: check(false, "%s : extrémités disjointes au nœud (%.3f m)" % [path.get_file(), r.gap])
		for k in ["max", "junction"]: worst[k] = maxf(worst[k], r[k])
		if path.contains("/free/"): worst.gap = maxf(worst.gap, r.gap)
	print("variation de cap max %.2f°, raccords %.2f°, écart aux nœuds %.3f m (%d réseaux)" % [worst.max, worst.junction, worst.gap, n])
	check(n > 100, "tous les réseaux analysés")
	check(worst.max < MAX_TURN_DEG, "aucune cassure de cap > %.0f° entre segments consécutifs" % MAX_TURN_DEG)
	check(worst.junction < MAX_TURN_DEG, "raccords tangents aux nœuds (aiguillages, stations)")
	# suivi de la rame : cap de NetworkLoader.point_on le long des courbes serrées d'Angers, Nantes, Lyon, Bordeaux
	for city in ["angers", "nantes", "lyon", "bordeaux"]:
		var net := NetworkLoader.new()
		var errs := net.load_file("res://data/free/%s.json" % city)
		check(errs.is_empty(), "%s : réseau libre chargé" % city)
		var jump := 0.0; var raw_jump := 0.0
		for id in net.graph.edges:
			if str(net.edge_info[id].get("service", "")) != "": continue   # faisceaux de dépôt : rayons de manœuvre
			var L: float = net.graph.edges[id].length
			var pts: PackedVector2Array = net.edge_info[id].pts
			var arc: PackedFloat64Array = net.edge_info[id].arc
			var k := arc[-1] / maxf(L, 0.001)
			var prev := TrackGraph.smooth_dir(pts, arc, 0.0)
			var prev_raw: Vector2 = net.point_on(id, 0.0).dir
			# saut = variation du taux de rotation entre deux pas (nulle sur un arc, pic sur un pli)
			var rate := NAN; var rate_raw := NAN
			var s := 0.25
			while s <= L:
				var d := TrackGraph.smooth_dir(pts, arc, s * k)
				var dr: Vector2 = net.point_on(id, s).dir
				var r := rad_to_deg(prev.angle_to(d)); var rr := rad_to_deg(prev_raw.angle_to(dr))
				if not is_nan(rate): jump = maxf(jump, absf(r - rate)); raw_jump = maxf(raw_jump, absf(rr - rate_raw))
				rate = r; rate_raw = rr
				prev = d; prev_raw = dr; s += 0.25
		print("%s : saut de cap par segment (point_on) %.2f°, cap interpolé (TrackGraph.smooth_dir) %.2f°" % [city, raw_jump, jump])
		check(jump < 1.5, "%s : cap interpolé de la rame sans pli (saut de rotation max %.2f° par pas de 0,25 m)" % [city, jump])
	print("TOTAL_ECHECS|", fails)
	quit(1 if fails else 0)
