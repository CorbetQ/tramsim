extends SceneTree
## Génère res://data/missions/<ville>.json : catalogue de missions jouées sur le réseau complet
## (data/free/<ville>.json). Horaires : GTFS des fichiers de ligne (data/networks) ; dépôts :
## ceux identifiés à l'import (tools/import/identify_depots.py). Aucun dépôt joignable → pas de
## mission de dépôt. Chaque itinéraire est validé par le planificateur du poste d'aiguillage.
## Usage : godot --headless --path . -s tools/build_missions.gd [-- ville ...]

const GEN_LEN := 50.0           # longueur maximale de rame admise aux points de retournement
const MAX_INCIDENT_LINES := 3
const WINDOW := 6

var net: NetworkLoader
var by_stop: Dictionary = {}
var by_name: Dictionary = {}
var city := ""

func _init() -> void:
	var only := OS.get_cmdline_user_args()
	var idx = JSON.parse_string(FileAccess.get_file_as_string("res://data/index.json"))
	var files_by_city := {}
	for entry in idx.networks:
		var meta = JSON.parse_string(FileAccess.get_file_as_string(entry.path))
		if typeof(meta) != TYPE_DICTIONARY: continue
		var src := str(meta.get("source_id", ""))
		if src == "" or meta.get("missions", []).is_empty(): continue
		if not files_by_city.has(src): files_by_city[src] = []
		files_by_city[src].append(meta)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://data/missions"))
	var total := 0
	for name in DirAccess.get_files_at("res://data/free"):
		if not name.ends_with(".json"): continue
		city = name.get_basename()
		if not only.is_empty() and not city in only: continue
		var t0 := Time.get_ticks_msec()
		var missions := build_city(files_by_city.get(city, []))
		var out := {"schema": 1, "city": city, "network": "res://data/free/%s.json" % city, "generator": "tools/build_missions.gd", "missions": missions}
		var f := FileAccess.open("res://data/missions/%s.json" % city, FileAccess.WRITE)
		f.store_string(JSON.stringify(out, "", false)); f.close()
		var kinds := {}
		for m in missions: kinds[m.type] = int(kinds.get(m.type, 0)) + 1
		print("%s : %d missions %s (%d ms)" % [city, missions.size(), str(kinds), Time.get_ticks_msec() - t0])
		total += missions.size()
	print("TOTAL|", total)
	quit()

# --- Outils --------------------------------------------------------------------------------

func wp(i: int) -> Dictionary:
	var st: Dictionary = net.stations[i]
	return {"edge": str(st.edge), "offset": float(st.offset), "dir": 0}

## Point de départ en gare : sens de marche menant au point suivant par le plus court itinéraire.
func start_at(i: int, next_point: Dictionary, closed := {}, strict := false, service := false) -> Dictionary:
	var st := wp(i)
	var best := INF
	st.dir = 1
	for d in [1, -1]:
		var r := Interlocking.find_path(net, st.edge, st.offset, d, str(next_point.edge), float(next_point.offset), int(next_point.get("dir", 0)), closed, service, strict)
		if not r.is_empty() and float(r.cost) < best: best = float(r.cost); st.dir = d
	return st

## Enchaîne les arrêts d'une course GTFS sur le réseau complet : pour chaque arrêt, quai
## (stop_id ou même nom) atteignable au moindre coût depuis le précédent, sans contre-sens
## prolongé. Les arrêts inaccessibles sont écartés. Retourne [[indice libre, départ]...].
func map_trip(line_meta: Dictionary, trip: Dictionary) -> Array:
	var seq: Array = []
	for k in trip.stops.size():
		var st: Dictionary = line_meta.stations[int(trip.stops[k])]
		var cands: Array = by_stop.get(str(st.get("stop_id", "")), []).duplicate()
		for c in by_name.get(str(st.name), []): if not c in cands: cands.append(c)
		if not cands.is_empty(): seq.append([cands, float(trip.departures[k])])
	if seq.size() < 2: return []
	var out: Array = []
	var cur := {}
	var i := 0
	# Départ : meilleure combinaison quai / sens vers l'arrêt suivant.
	while cur.is_empty() and i < seq.size() - 1:
		var best := INF
		for c0 in seq[i][0]:
			for d in [1, -1]:
				for c1 in seq[i + 1][0]:
					var r := Interlocking.find_path(net, str(net.stations[c0].edge), float(net.stations[c0].offset), d, str(net.stations[c1].edge), float(net.stations[c1].offset), 0)
					if r.is_empty() or float(r.cost) > 5.0 * float(r.length) + 2000.0: continue
					if float(r.cost) < best:
						best = float(r.cost)
						cur = {"edge": str(net.stations[c1].edge), "offset": float(net.stations[c1].offset), "dir": int(r.path[-1][1])}
						out = [[c0, seq[i][1], d], [c1, seq[i + 1][1]]]
		i += 1
	if cur.is_empty(): return []
	for j in range(i + 1, seq.size()):
		var best := INF; var pick := -1; var nd := 0
		for c in seq[j][0]:
			var r := Interlocking.find_path(net, str(cur.edge), float(cur.offset), int(cur.dir), str(net.stations[c].edge), float(net.stations[c].offset), 0)
			if r.is_empty() or float(r.cost) > 5.0 * float(r.length) + 2000.0: continue
			if float(r.cost) < best: best = float(r.cost); pick = c; nd = int(r.path[-1][1])
		if pick < 0: continue
		out.append([pick, seq[j][1]])
		cur = {"edge": str(net.stations[pick].edge), "offset": float(net.stations[pick].offset), "dir": nd}
	return out

static func hour_of(t: String) -> float:
	var p := t.split(":")
	return (float(p[0]) + float(p[1]) / 60.0) if p.size() >= 2 else 12.0

func route(start: Dictionary, points: Array, closed := {}, strict := false, service := false) -> Dictionary:
	return Interlocking.plan_route(net, start, points, closed, service, strict)

## Point situé à `d` m le long d'un itinéraire partant de (path[0], from_off).
func along(path: Array, from_off: float, d: float) -> Array:
	var rem := d
	for i in path.size():
		var e := str(path[i][0]); var r := int(path[i][1])
		var L: float = net.graph.edges[e].length
		var start := from_off if i == 0 else (0.0 if r > 0 else L)
		var avail := (L - start) if r > 0 else start
		if rem <= avail or i == path.size() - 1:
			return [e, clampf(start + minf(rem, avail) * r, 0.0, L)]
		rem -= avail
	return [str(path[-1][0]), 0.0]

## Segments [[arête, a, b]] couvrant [d0, d1] le long de l'itinéraire.
func segments(path: Array, from_off: float, d0: float, d1: float) -> Array:
	var out: Array = []
	var acc := 0.0
	for i in path.size():
		var e := str(path[i][0]); var r := int(path[i][1])
		var L: float = net.graph.edges[e].length
		var start := from_off if i == 0 else (0.0 if r > 0 else L)
		var avail := (L - start) if r > 0 else start
		var a := maxf(d0, acc); var b := minf(d1, acc + avail)
		if b > a:
			var x0 := start + (a - acc) * r; var x1 := start + (b - acc) * r
			out.append([e, snappedf(minf(x0, x1), 0.01), snappedf(maxf(x0, x1), 0.01)])
		acc += avail
		if acc >= d1: break
	return out

func leg(a: int, b: int, closed := {}, strict := false) -> Dictionary:
	var st := start_at(a, wp(b), closed, strict)
	return Interlocking.find_path(net, st.edge, st.offset, st.dir, str(net.stations[b].edge), float(net.stations[b].offset), 0, closed, false, strict)

func base(id: String, type: String, line: String, title: String, description: String, difficulty: int, first: String, conditions: Array) -> Dictionary:
	return {"id": "%s_%s" % [city, id], "type": type, "title": title, "description": description, "line": line, "difficulty": difficulty,
		"duration_min": 5, "start_station": first, "conditions": conditions, "network": "res://data/free/%s.json" % city}

func window_mission(m: Dictionary, stops: Array, start_hour: float) -> Dictionary:
	# stops : [[indice, départ GTFS]]
	var t0: float = stops[0][1]
	var deps: Array = []; var items: Array = []; var wps: Array = []
	for s in stops:
		deps.append(snappedf(float(s[1]) - t0 + 60.0, 1.0)); items.append({"station": int(s[0])}); wps.append(wp(int(s[0])))
	var st := start_at(int(stops[0][0]), wp(int(stops[1][0]))) if stops.size() > 1 else wp(int(stops[0][0]))
	if st.dir == 0: st.dir = 1
	m["start"] = st
	m["stops"] = items; m["departures"] = deps; m["waypoints"] = wps
	m["duration_min"] = maxi(3, ceili((float(deps[-1]) + 60.0) / 60.0))
	m["start_hour"] = snappedf(start_hour, 0.01)
	m["passengers"] = 40
	return m

# --- Construction ---------------------------------------------------------------------------

func build_city(line_files: Array) -> Array:
	net = NetworkLoader.new()
	net.load_file("res://data/free/%s.json" % city)
	by_stop.clear(); by_name.clear()
	for i in net.stations.size():
		var nm := str(net.stations[i].name)
		if not by_name.has(nm): by_name[nm] = []
		by_name[nm].append(i)
		var sid := str(net.stations[i].get("stop_id", ""))
		if sid == "": continue
		if not by_stop.has(sid): by_stop[sid] = []
		by_stop[sid].append(i)
	var missions: Array = []
	var lines_done := {}
	var incident_lines := 0
	var depot_lines := 0
	line_files.sort_custom(func(a, b): return str(a.id) < str(b.id))
	for lm in line_files:
		var line := str(lm.line)
		if lines_done.has(line): continue
		var day := {}; var night := {}
		for trip in lm.missions:
			var h := hour_of(str(trip.start_time))
			var dkey := str(trip.direction)
			if h >= 7.0 and h <= 19.0 and not day.has(dkey): day[dkey] = trip
			if (h >= 21.0 or h < 5.0) and night.is_empty(): night = trip
		var mapped := {}
		for dkey in day:
			var trip: Dictionary = day[dkey]
			var m := map_trip(lm, trip)
			if m.size() < maxi(4, int(trip.stops.size() * 0.8)): continue
			var pts: Array = []
			for s in m: pts.append(wp(int(s[0])))
			var st0 := start_at(int(m[0][0]), pts[1])
			if route(st0, pts.slice(1)).is_empty(): continue
			mapped[dkey] = [trip, m]
		if mapped.is_empty(): continue
		lines_done[line] = true
		var keys := mapped.keys(); keys.sort()
		var headsign := func(k): return str(mapped[k][0].headsign)
		# Service commercial (chaque sens)
		for k in keys:
			var trip: Dictionary = mapped[k][0]; var m: Array = mapped[k][1]
			var first := str(net.stations[int(m[0][0])].name)
			var x := base("%s_service_%s" % [line, k], "service", line, "Ligne %s — service vers %s" % [line, headsign.call(k)],
				"Service commercial complet selon l’horaire GTFS (%s), de %s à %s." % [str(trip.start_time), first, headsign.call(k)], 1, first, ["jour", "horaire GTFS"])
			window_mission(x, m, hour_of(str(trip.start_time)))
			x["constraints"] = ["Aucun départ anticipé", "Retard maximal 60 s", "Aiguillages gérés par le poste"]
			missions.append(x)
		# Service de nuit
		if not night.is_empty():
			var m := map_trip(lm, night)
			if m.size() >= 4:
				var pts: Array = []
				for s in m: pts.append(wp(int(s[0])))
				var st0 := start_at(int(m[0][0]), pts[1])
				if not route(st0, pts.slice(1)).is_empty():
					var first := str(net.stations[int(m[0][0])].name)
					var x := base("%s_night" % line, "night", line, "Ligne %s — dernier service de nuit" % line,
						"Course de nuit de %s (%s) vers %s : visibilité réduite, quais peu éclairés." % [first, str(night.start_time), str(night.headsign)], 1, first, ["nuit", "horaire GTFS"])
					window_mission(x, m, hour_of(str(night.start_time)))
					x["passengers"] = 8
					x["constraints"] = ["Aucun départ anticipé", "Retard maximal 60 s"]
					missions.append(x)
		var k0: String = keys[0]
		var trip0: Dictionary = mapped[k0][0]; var m0: Array = mapped[k0][1]
		var h0 := hour_of(str(trip0.start_time))
		if depot_lines < MAX_INCIDENT_LINES:
			if _depot_missions(missions, line, mapped, keys): depot_lines += 1
		if incident_lines >= MAX_INCIDENT_LINES or m0.size() < WINDOW + 2: continue
		incident_lines += 1
		var k := clampi(m0.size() / 4, 1, m0.size() - WINDOW - 1)
		var win: Array = m0.slice(k, k + WINDOW)
		var names := func(i): return str(net.stations[int(win[i][0])].name)
		# Affluence
		var x := base("%s_crowd" % line, "crowd", line, "Ligne %s — affluence d’événement" % line,
			"Sortie de manifestation à %s : embarquement massif, tolérance de retard élargie." % names.call(2), 2, names.call(0), ["événement", "affluence"])
		window_mission(x, win, 18.5)
		x["events"] = [{"kind": "crowd", "station": names.call(2), "factor": 3.5}]
		x["late_tolerance_s"] = 120.0; x["passengers"] = 90
		x["constraints"] = ["Retard maximal 120 s", "Capacité de la rame"]
		missions.append(x)
		# Incidents entre les arrêts 2 et 3 de la fenêtre
		var a: int = int(win[2][0]); var b: int = int(win[3][0])
		var lg := leg(a, b)
		if lg.is_empty(): continue
		var L: float = lg.length
		var from_off := float(net.stations[a].offset)
		# Inondation (marche à vue)
		x = base("%s_flood" % line, "flood", line, "Ligne %s — voie inondée" % line,
			"Orage : la voie est submergée entre %s et %s. Marche à vue à 10 km/h dans la zone." % [names.call(2), names.call(3)], 2, names.call(0), ["pluie", "inondation", "marche à vue"])
		window_mission(x, win, h0)
		x["events"] = [{"kind": "flood", "segments": segments(lg.path, from_off, L * 0.3, minf(L * 0.3 + 160.0, L - 40.0))}]
		x["adhesion"] = 0.14
		x["late_tolerance_s"] = 150.0
		x["constraints"] = ["10 km/h maximum dans la zone inondée", "Retard maximal 150 s"]
		missions.append(x)
		# Feuilles mortes : approches des arrêts 2, 3 et 4
		x = base("%s_leaves" % line, "leaves", line, "Ligne %s — feuilles mortes" % line,
			"Automne : rails glissants avant %s, %s et %s. Patinage, enrayage et freinage allongé ; sablage disponible." % [names.call(2), names.call(3), names.call(4)], 3, names.call(0), ["automne", "feuilles mortes", "sablage"])
		window_mission(x, win, h0)
		var zones: Array = []
		for j in [2, 3, 4]:
			var pl := leg(int(win[j - 1][0]), int(win[j][0]))
			if pl.is_empty(): continue
			zones.append({"kind": "leaves", "adhesion": 0.07, "segments": segments(pl.path, float(net.stations[int(win[j - 1][0])].offset), maxf(float(pl.length) - 260.0, 0.0), float(pl.length) + 3.0)})
		x["events"] = zones; x["adhesion"] = 0.20; x["late_tolerance_s"] = 90.0
		x["constraints"] = ["Adhérence réduite", "Retard maximal 90 s", "Réserve de sable : 90 s"]
		missions.append(x)
		# Panne de pantographe
		var p := along(lg.path, from_off, L * 0.4)
		x = base("%s_pantograph" % line, "pantograph_fault", line, "Ligne %s — défaut de pantographe" % line,
			"Le pantographe s’abaisse entre %s et %s : immobiliser la rame, réarmer, relever." % [names.call(2), names.call(3)], 2, names.call(0), ["incident technique"])
		window_mission(x, win, h0)
		x["events"] = [{"kind": "pantograph_fault", "edge": p[0], "offset": p[1]}]
		x["late_tolerance_s"] = 180.0
		x["constraints"] = ["Réarmement à l’arrêt (10 s)", "Retard maximal 180 s"]
		missions.append(x)
		# Coupure d'alimentation
		x = base("%s_power_cut" % line, "power_cut", line, "Ligne %s — coupure d’alimentation" % line,
			"Défaut de sous-station entre %s et %s : ligne aérienne hors tension pendant 75 s." % [names.call(2), names.call(3)], 2, names.call(0), ["incident d’alimentation"])
		window_mission(x, win, h0)
		x["events"] = [{"kind": "power_cut", "duration_s": 75.0, "segments": segments(lg.path, from_off, L * 0.25, minf(L * 0.25 + 400.0, L))}]
		x["late_tolerance_s"] = 180.0
		x["constraints"] = ["Pas de traction sans tension", "Retard maximal 180 s"]
		missions.append(x)
		# Véhicule sur la voie : interstation la plus longue de la fenêtre
		var best := -1; var best_l := 0.0; var best_leg := {}
		for j in range(1, WINDOW):
			var ll := leg(int(win[j - 1][0]), int(win[j][0]))
			if not ll.is_empty() and float(ll.length) > best_l: best = j; best_l = float(ll.length); best_leg = ll
		if best > 0 and best_l >= 300.0:
			var q := along(best_leg.path, float(net.stations[int(win[best - 1][0])].offset), best_l * 0.6)
			x = base("%s_obstacle" % line, "obstacle", line, "Ligne %s — véhicule sur la voie" % line,
				"Une voiture engage le gabarit entre %s et %s : marche à vue, arrêt avant l’obstacle." % [names.call(best - 1), names.call(best)], 2, names.call(0), ["circulation", "marche à vue"])
			window_mission(x, win, h0)
			x["events"] = [{"kind": "obstacle", "edge": q[0], "offset": q[1], "clear_after_s": 20.0}]
			x["late_tolerance_s"] = 150.0
			x["constraints"] = ["Arrêt avant l’obstacle", "Retard maximal 150 s"]
			missions.append(x)
		_deviation_missions(missions, line, m0, h0)
		_turnback_mission(missions, line, mapped, keys)
	return missions

func _deviation_missions(missions: Array, line: String, trip: Array, h0: float) -> void:
	for jj in range(2, trip.size() - 3):
		var win: Array = trip.slice(jj - 2, jj + 4)
		var j := 2
		var names := func(i): return str(net.stations[int(win[i][0])].name)
		var prev := int(win[j - 1][0]); var nxt := int(win[j + 1][0])
		var orig := leg(prev, nxt)
		if orig.is_empty(): continue
		var keep := {str(net.stations[prev].edge): true, str(net.stations[nxt].edge): true}
		for seg in net.stations[prev].get("stop_area", {}).get("segments", []): keep[str(seg[0])] = true
		for seg in net.stations[nxt].get("stop_area", {}).get("segments", []): keep[str(seg[0])] = true
		var to_j := leg(prev, int(win[j][0]))
		if to_j.is_empty(): continue
		var dj := float(to_j.length)
		var closed := {}
		var acc := 0.0
		for i in orig.path.size():
			var e := str(orig.path[i][0]); var r := int(orig.path[i][1])
			var Le: float = net.graph.edges[e].length
			var st_off := float(net.stations[prev].offset) if i == 0 else (0.0 if r > 0 else Le)
			var avail := (Le - st_off) if r > 0 else st_off
			if acc + avail >= dj - 150.0 and acc <= dj + 150.0 and not keep.has(e): closed[e] = true
			acc += avail
		if closed.is_empty(): continue
		var strict := true
		var det := leg(prev, nxt, closed, true)
		if det.is_empty():
			strict = false
			det = leg(prev, nxt, closed, false)
			if det.is_empty() or (float(det.cost) - float(det.length)) / (Interlocking.WRONG_WAY_FACTOR - 1.0) > 2500.0: continue
		var extra := float(det.length) - float(orig.length)
		if float(det.length) > maxf(6.0 * float(orig.length), float(orig.length) + 3000.0) or float(det.length) > 8000.0: continue
		var stops: Array = []
		var skipped: Array = []
		for i in win.size():
			var idx := int(win[i][0])
			if i == j or closed.has(str(net.stations[idx].edge)): skipped.append(str(net.stations[idx].name)); continue
			stops.append([idx, float(win[i][1]) + (extra / 7.0 + 30.0 if i > j else 0.0)])
		var pts: Array = []
		for s in stops.slice(1): pts.append(wp(int(s[0])))
		var st0 := start_at(int(stops[0][0]), pts[0], closed, strict)
		if route(st0, pts, closed, strict).is_empty(): continue
		var cl := closed.keys()
		var works := segments(orig.path, float(net.stations[prev].offset), 0.0, float(orig.length))
		var x := base("%s_deviation" % line, "deviation", line, "Ligne %s — déviation pour travaux" % line,
			"Section fermée autour de %s : détour de %d m tracé par le poste %s ; arrêt non desservi annoncé." % [names.call(j), roundi(float(det.length)), "par d’autres lignes" if strict else "en voie unique temporaire par les communications"], 2, names.call(0), ["travaux", "déviation"] + ([] if strict else ["contre-sens"]))
		window_mission(x, stops, h0)
		x["closed"] = cl; x["strict"] = strict
		x["events"] = [{"kind": "works", "skipped": skipped, "segments": works.filter(func(sg): return closed.has(str(sg[0])))}]
		x["constraints"] = ["Itinéraire de déviation imposé", "Arrêts non desservis : " + ", ".join(PackedStringArray(skipped)), "Retard maximal 60 s"]
		missions.append(x)
		var y := base("%s_flood_closed" % line, "flood", line, "Ligne %s — inondation, section fermée" % line,
			"Crue : la voie est impraticable autour de %s. Détour tracé par le poste ; arrêt non desservi." % names.call(j), 3, names.call(0), ["pluie", "inondation", "section fermée", "détour"])
		window_mission(y, stops, h0)
		y["closed"] = cl; y["strict"] = strict; y["adhesion"] = 0.14
		y["events"] = [{"kind": "flood_closed", "skipped": skipped, "segments": x.events[0].segments}]
		y["late_tolerance_s"] = 90.0
		y["constraints"] = ["Section submergée fermée", "Retard maximal 90 s"]
		missions.append(y)
		return

func _turnback_mission(missions: Array, line: String, mapped: Dictionary, keys: Array) -> void:
	if keys.size() < 2: return
	var m0: Array = mapped[keys[0]][1]; var m1: Array = mapped[keys[1]][1]
	var cands: Array = []
	for j in range(3, m0.size() - 2):
		if bool(net.stations[int(m0[j][0])].get("turnback", false)): cands.push_front(j)
		else: cands.append(j)
	var tries := 0
	for j in cands:
		tries += 1
		if tries > 14: break
		var s := int(m0[j][0])
		var name := str(net.stations[s].name)
		var q := -1
		for i in m1.size():
			if str(net.stations[int(m1[i][0])].name) == name and int(m1[i][0]) != s: q = i
		if q < 0 or q + 2 >= m1.size(): continue
		var o := int(m1[q][0])
		var arrive := Interlocking.plan_route(net, start_at(int(m0[j - 1][0]), wp(s)), [wp(s)])
		if arrive.is_empty(): continue
		var rev := Interlocking.find_reversal(net, {"edge": wp(s).edge, "offset": wp(s).offset, "dir": int(arrive.path[-1][1])}, wp(o), GEN_LEN, {}, 1500.0)
		if rev.is_empty(): continue
		var stops: Array = []
		var t_base: float = m0[j - 3][1]
		for i in range(j - 3, j + 1): stops.append([int(m0[i][0]), float(m0[i][1])])
		var x := base("%s_turnback" % line, "turnback", line, "Ligne %s — terminus partiel à %s" % [line, name],
			"Service limité à %s : faire descendre les voyageurs, retourner sur la communication puis reprendre le service en sens inverse." % name, 2, str(net.stations[int(stops[0][0])].name), ["terminus partiel", "changement de cabine"])
		window_mission(x, stops, hour_of(str(mapped[keys[0]][0].start_time)))
		x.stops[-1]["alight_all"] = true; x.stops[-1]["free_time"] = true
		x.waypoints.append(rev.point)
		var t := float(x.departures[-1]) + 60.0 + float(rev.length) / 4.0
		var dq: float = m1[q][1]
		for i in range(q, q + 3):
			x.stops.append({"station": int(m1[i][0]), "free_time": true})
			x.waypoints.append(wp(int(m1[i][0])))
			x.departures.append(snappedf(t + float(m1[i][1]) - dq, 1.0))
		x["time_limit_s"] = snappedf(float(x.departures[-1]) * 1.6 + 300.0, 1.0)
		x["duration_min"] = ceili(float(x.departures[-1]) / 60.0) + 2
		x["constraints"] = ["Changement de cabine au point de retournement uniquement", "Terminus : tout le monde descend", "Délai : %d min" % ceili(float(x.time_limit_s) / 60.0)]
		missions.append(x)
		return

func _depot_missions(missions: Array, line: String, mapped: Dictionary, keys: Array) -> bool:
	var depots: Array = net.meta.get("depots", [])
	if depots.is_empty(): return false
	var made := false
	# Sortie : du dépôt au premier arrêt (meilleure combinaison dépôt / sens)
	var best := {}; var best_l := INF
	for d in depots:
		if not net.graph.edges.has(str(d.get("edge", ""))): continue
		for k in keys:
			var first := int(mapped[k][1][0][0])
			for dir in [1, -1]:
				var r := Interlocking.find_path(net, str(d.edge), float(d.offset), dir, str(net.stations[first].edge), float(net.stations[first].offset), 0, {}, true, false, 8000.0)
				if not r.is_empty() and float(r.length) < best_l:
					best_l = float(r.length); best = {"depot": d, "dir": dir, "first": first, "k": k}
	if not best.is_empty():
		var d: Dictionary = best.depot
		var first: int = best.first
		var fname := str(net.stations[first].name)
		var x := base("%s_depot_exit" % line, "depot_exit", line, "Ligne %s — sortie de dépôt" % line,
			"Prise de service au %s : mise sous tension, lever le pantographe, sortie sur l’itinéraire tracé jusqu’à %s (%d m)." % [str(d.name), fname, roundi(best_l)], 1, str(d.name), ["dépôt", "mise sous tension"])
		x["start"] = {"edge": str(d.edge), "offset": float(d.offset), "dir": int(best.dir)}
		x["stops"] = [{"station": first, "free_time": true}]
		x["waypoints"] = [wp(first)]
		x["departures"] = [snappedf(best_l / 6.0 + 120.0, 1.0)]
		x["time_limit_s"] = snappedf(best_l / 3.0 + 400.0, 1.0)
		x["duration_min"] = ceili(float(x.time_limit_s) / 120.0) + 2
		x["passengers"] = 0; x["pantograph_down"] = true; x["service_tracks"] = true
		x["depot"] = str(d.name)
		x["start_hour"] = 5.25
		x["constraints"] = ["Pantographe abaissé au départ", "Itinéraire de sortie tracé par le poste", "Délai : %d min" % ceili(float(x.time_limit_s) / 60.0)]
		missions.append(x)
		made = true
	# Rentrée : du terminus au dépôt, voyageurs à débarquer
	best = {}; best_l = INF
	for d in depots:
		if not net.graph.edges.has(str(d.get("edge", ""))): continue
		for k in keys:
			var term := int(mapped[k][1][-1][0])
			var prev_stop := int(mapped[k][1][-2][0])
			var arrive := Interlocking.plan_route(net, start_at(prev_stop, wp(term)), [wp(term)])
			if arrive.is_empty(): continue
			var start := wp(term); start.dir = int(arrive.path[-1][1])
			var target := {"edge": str(d.edge), "offset": float(d.offset), "dir": 0}
			var r := Interlocking.find_path(net, start.edge, start.offset, start.dir, target.edge, target.offset, 0, {}, true, false, 8000.0)
			if not r.is_empty() and float(r.length) < best_l:
				best_l = float(r.length); best = {"depot": d, "term": term, "start": start, "rev": {}}
			if r.is_empty() or float(r.length) > 6000.0:
				var rev := Interlocking.find_reversal(net, start, target, GEN_LEN, {}, 8000.0, true)
				if not rev.is_empty() and float(rev.length) < best_l:
					best_l = float(rev.length); best = {"depot": d, "term": term, "start": start, "rev": rev.point}
	if not best.is_empty():
		var d: Dictionary = best.depot
		var tname := str(net.stations[int(best.term)].name)
		var x := base("%s_depot_return" % line, "depot_return", line, "Ligne %s — rentrée au dépôt" % line,
			"Fin de service à %s : tout le monde descend, puis rentrée au %s (%d m)%s." % [tname, str(d.name), roundi(best_l), " avec changement de cabine" if not best.rev.is_empty() else ""], 2, tname, ["fin de service", "dépôt"])
		x["start"] = best.start
		x["stops"] = [{"station": int(best.term), "alight_all": true, "free_time": true}]
		x["departures"] = [60.0]
		var target := {"edge": str(d.edge), "offset": float(d.offset), "dir": 0}
		x["waypoints"] = [wp(int(best.term))] + ([best.rev] if not best.rev.is_empty() else []) + [target]
		x["target"] = {"edge": str(d.edge), "offset": float(d.offset), "tolerance": 25.0, "name": str(d.name)}
		x["time_limit_s"] = snappedf(best_l / 3.0 + 500.0, 1.0)
		x["duration_min"] = ceili(float(x.time_limit_s) / 120.0) + 2
		x["passengers"] = 70; x["service_tracks"] = true
		x["depot"] = str(d.name)
		x["start_hour"] = 21.5
		x["constraints"] = ["Aucun voyageur à bord en quittant le terminus", "Immobilisation sur la voie de remisage", "Délai : %d min" % ceili(float(x.time_limit_s) / 60.0)]
		missions.append(x)
		made = true
	return made
