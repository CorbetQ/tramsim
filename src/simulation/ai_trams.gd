class_name AiTrams
extends RefCounted
## Rames en circulation sur le réseau du mode mission, gérées par le jeu.
## Fréquences approchées des lignes (intervalle GTFS typique selon l'heure), nombre plafonné
## (PC / mobile), simulation simplifiée hors de vue (pas plus grossier). Chaque rame trace son
## itinéraire avec son propre poste : cantonnement et aiguillages partagés avec le joueur.
## Une rame immobilisée trop longtemps (interblocage) ou qui retient le joueur au signal
## est retirée du service (régulation), puis réinjectée plus tard ailleurs sur sa ligne.

signal message(text: String)

const MAX_PC := 10
const MAX_MOBILE := 5
const NEAR_M := 1200.0        # au-delà : pas de simulation grossier
const COARSE_DT := 0.25
const STUCK_S := 360.0        # interblocage entre rames IA (sections longues comprises) : retrait
const YIELD_S := 60.0         # joueur retenu au signal par une rame IA : régulation
const RESPAWN_S := 90.0
const SPAWN_CLEAR_M := 450.0  # distance minimale au joueur pour une mise en service
const TURNBACK_S := 150.0

var net: NetworkLoader
var vehicle: VehicleProfile
var player: MissionSession
var trams: Array[AiTram] = []
var lines: Dictionary = {}    # ligne -> {legs: [{waypoints, path, stops: [[station, t]], duration}], headway, cycle}
var cap := MAX_PC
var hour := 12.0
var removed := 0
var collisions := 0
var _acc: Dictionary = {}
var _pending: Array = []      # [ligne, délai]
var _player_wait := 0.0
var _next := 1
var _rng := RandomNumberGenerator.new()

## Intervalle approché entre deux passages (s) selon l'heure et le type de ligne.
static func headway_s(hour_: float, kind: String = "tram") -> float:
	if kind == "tram-train": return 1800.0
	var h := fposmod(hour_, 24.0)
	if h < 5.5 or h >= 23.0: return 1200.0
	if h >= 21.0 or h < 6.5: return 900.0
	if (h >= 7.0 and h < 9.5) or (h >= 16.5 and h < 19.0): return 300.0
	return 420.0

## Ligne d'une mission : missions de service du catalogue de la ville, dans les deux sens.
static func create(p: MissionSession, city: String, hour_: float, max_trams: int = -1) -> AiTrams:
	var a := AiTrams.new()
	a.net = p.net; a.vehicle = p.phys.profile; a.player = p; a.hour = hour_
	a.cap = max_trams if max_trams >= 0 else (MAX_MOBILE if OS.has_feature("mobile") else MAX_PC)
	a._rng.seed = hash(city) + int(hour_ * 60.0)
	a._load_lines(city)
	a._spawn_initial()
	p.ai = a
	return a

func _load_lines(city: String) -> void:
	var by_line := {}
	for m in MissionCatalog.for_city(city):
		if str(m.get("type", "")) != "service" or m.get("waypoints", []).is_empty(): continue
		var l := str(m.line)
		if not by_line.has(l): by_line[l] = []
		by_line[l].append(m)
	for l in by_line:
		var leg0 := _mission_leg(by_line[l][0])
		if leg0.is_empty(): continue
		var leg1: Dictionary = {}
		var last_name := str(net.stations[int(leg0.stops[-1][0])].name)
		for m in by_line[l].slice(1):
			if str(net.stations[int(m.stops[0].station)].name) == last_name: leg1 = _mission_leg(m)
			if not leg1.is_empty(): break
		if leg1.is_empty(): leg1 = _reverse_leg(leg0)
		var legs: Array = [leg0] if leg1.is_empty() else [leg0, leg1]
		var cycle := 0.0
		for lg in legs: cycle += float(lg.duration) + TURNBACK_S
		if legs.size() == 1: cycle += float(leg0.duration)
		lines[l] = {"legs": legs, "headway": headway_s(hour), "cycle": cycle}

func _mission_leg(m: Dictionary) -> Dictionary:
	var st: Dictionary = m.start
	var plan := Interlocking.plan_route(net, {"edge": str(st.edge), "offset": float(st.offset), "dir": int(st.dir)}, m.waypoints)
	if plan.is_empty(): return {}
	var stops: Array = []
	var deps: Array = m.get("departures", [])
	var t0 := float(deps[0]) if not deps.is_empty() else 0.0
	for k in (m.stops as Array).size():
		stops.append([int(m.stops[k].station), (float(deps[k]) - t0) if k < deps.size() else 90.0 * k])
	var wps: Array = []
	for w in m.waypoints: wps.append((w as Dictionary).duplicate())
	wps[0]["dir"] = int(st.dir)   # départ du terminus dans le sens de service
	return {"waypoints": wps, "path": plan.path, "stops": stops, "duration": (stops[-1][1] if not stops.is_empty() else 600.0) + 60.0}

## Service retour construit à partir de l'aller (stations en ordre inverse, quai de l'autre
## sens choisi par le plus court itinéraire sans rebroussement) quand le catalogue n'a pas de
## mission dans l'autre sens.
func _reverse_leg(leg0: Dictionary) -> Dictionary:
	var path0: Array = leg0.path
	var last: Array = path0[-1]
	var stops0: Array = leg0.stops
	var t_end := float(stops0[-1][1])
	var e := str(last[0]); var d := -int(last[1])
	var term: Dictionary = net.stations[int(stops0[-1][0])]
	var o := float(term.offset) if str(term.edge) == e else (0.0 if d < 0 else float(net.graph.edges[e].length))
	var path: Array = [[e, d]]
	var wps: Array = []; var stops: Array = []
	var first := true
	for k in range(stops0.size() - 1, -1, -1):
		var name := str(net.stations[int(stops0[k][0])].name)
		var best: Dictionary = {}; var best_cost := INF; var best_i := -1
		for i in net.stations.size():
			var cand: Dictionary = net.stations[i]
			if str(cand.name) != name: continue
			var r := Interlocking.find_path(net, e, o, d, str(cand.edge), float(cand.offset), 0, {}, false, false, 6000.0)
			if not r.is_empty() and float(r.cost) < best_cost: best = r; best_cost = float(r.cost); best_i = i
		if best.is_empty(): continue
		var cand: Dictionary = net.stations[best_i]
		for j in range(1, (best.path as Array).size()): path.append(best.path[j])
		e = str(cand.edge); o = float(cand.offset); d = int(path[-1][1])
		var w := {"edge": e, "offset": o, "dir": d if first else 0}
		first = false
		wps.append(w)
		stops.append([best_i, t_end - float(stops0[k][1])])
	if wps.size() < 2: return {}
	# L'itinéraire de référence part du quai de départ (premier point).
	var i0 := 0
	for j in path.size():
		if str(path[j][0]) == str(wps[0].edge): i0 = j; break
	return {"waypoints": wps, "path": path.slice(i0), "stops": stops, "duration": float(stops[-1][1]) + 60.0}

func _spawn_initial() -> void:
	var want := {}
	var total := 0
	for l in lines:
		var n := clampi(roundi(float(lines[l].cycle) / float(lines[l].headway)), 1, 40)
		want[l] = n; total += n
	if total > cap and total > 0:
		var scale := float(cap) / float(total)
		for l in want: want[l] = maxi(1 if cap >= lines.size() else 0, floori(int(want[l]) * scale))
	for l in want:
		var n := int(want[l])
		var offset := _rng.randf()
		for k in n:
			if trams.size() >= cap: return
			_spawn(l, fposmod(offset + float(k) / float(n), 1.0) * float(lines[l].cycle))

## Mise en service d'une rame de la ligne `l` à la phase `phase` (s) de son cycle.
func _spawn(l: String, phase: float) -> bool:
	var info: Dictionary = lines[l]
	var legs: Array = info.legs
	# Candidats : stations du cycle à partir de la phase demandée.
	var cands: Array = []
	var t := 0.0
	for li in legs.size():
		for sp in legs[li].stops: cands.append([li, int(sp[0]), t + float(sp[1])])
		t += float(legs[li].duration) + TURNBACK_S
	cands.sort_custom(func(a, b): return fposmod(float(a[2]) - phase, t) < fposmod(float(b[2]) - phase, t))
	for c in cands:
		if _try_spawn(l, int(c[0]), int(c[1])): return true
	return false

func _try_spawn(l: String, li: int, station_index: int) -> bool:
	var lg: Dictionary = lines[l].legs[li]
	var path: Array = lg.path
	var st: Dictionary = net.stations[station_index]
	var j := -1
	for k in path.size():
		if str(path[k][0]) == str(st.edge): j = k; break
	if j < 0: return false
	var g := net.graph
	var e := str(st.edge); var d := int(path[j][1])
	var L: float = g.edges[e].length
	var off := float(st.offset)
	var p: Dictionary = net.point_on(e, off)
	var pp: Dictionary = net.point_on(player.edge_id, player.offset)
	if (p.p as Vector2).distance_to(pp.p) < SPAWN_CLEAR_M: return false
	# Sections sous la rame (vers l'arrière le long de l'itinéraire de la ligne).
	var length := vehicle.length_m + 2.0
	var edges: Array = [e]; var dirs: Array = [d]
	var covered := off if d > 0 else L - off
	var k := j - 1
	while covered < length:
		if k < 0: return false
		edges.push_front(str(path[k][0])); dirs.push_front(int(path[k][1]))
		covered += float(g.edges[str(path[k][0])].length)
		k -= 1
	for id in edges:
		if g.edges[id].occupied_by != "" or g.reserved.has(id): return false
	# Points de passage restants de l'étape (repérés dans l'ordre le long de l'itinéraire).
	var wps: Array = []
	var cursor := 0
	for w in lg.waypoints:
		var found := -1
		for q in range(cursor, path.size()):
			if str(path[q][0]) == str(w.edge): found = q; break
		if found < 0: continue
		cursor = found
		if found > j or (found == j and (float(w.offset) - off) * d > 5.0): wps.append(w)
	if wps.is_empty(): return false
	var id := "IA%d" % _next
	_next += 1
	var tram := AiTram.new(net, vehicle, id, l, e, off, edges, dirs)
	var legs_wps: Array = []
	for x in lines[l].legs: legs_wps.append(x.waypoints)
	tram.legs = legs_wps; tram.leg = li
	tram.driver.served = Autopilot.station_key(st)   # mise en service au départ de la station
	if not tram.interlocking.setup(tram, wps):
		tram.remove(); return false
	trams.append(tram)
	_acc[id] = 0.0
	return true

func _retire(t: AiTram, why: String) -> void:
	t.remove()
	trams.erase(t)
	_acc.erase(t.train_id)
	removed += 1
	_pending.append([t.line, RESPAWN_S])
	if why != "": message.emit(why)

## Pas de simulation de toutes les rames IA (appelé par la session du joueur avant son pas).
func step(dt: float, p: MissionSession = null) -> void:
	if p != null: player = p
	var sm := SignalModel.of(net)
	var all: Array = [player]
	all.append_array(trams)
	sm.update(dt, all)
	var pp: Vector2 = net.point_on(player.edge_id, player.offset).p
	for t in trams.duplicate():
		if t.stuck:
			if t.fail_reason.contains("Collision"): collisions += 1
			_retire(t, "Rame %s retirée : %s" % [t.train_id, t.fail_reason] if OS.is_debug_build() and OS.get_environment("AI_TRACE") != "" else ""); continue
		var near := (net.point_on(t.edge_id, t.offset).p as Vector2).distance_to(pp) < NEAR_M
		if near:
			t.ai_tick(dt + float(_acc[t.train_id])); _acc[t.train_id] = 0.0
		else:
			_acc[t.train_id] = float(_acc[t.train_id]) + dt
			if float(_acc[t.train_id]) >= COARSE_DT:
				t.ai_tick(float(_acc[t.train_id])); _acc[t.train_id] = 0.0
		if t.wait_s > STUCK_S: _retire(t, "Régulation : rame %s retirée du service%s" % [t.train_id, (" (%s@%.0f %s %s)" % [t.edge_id, t.offset, t.driver.status, _why(t) + " | " + _holder(t)]) if OS.get_environment("AI_TRACE") != "" else ""])
	_yield_to_player(dt)
	for q in _pending.duplicate():
		q[1] = float(q[1]) - dt
		if float(q[1]) <= 0.0:
			_pending.erase(q)
			if trams.size() < cap and lines.has(str(q[0])):
				if not _spawn(str(q[0]), _rng.randf() * float(lines[str(q[0])].cycle)): _pending.append([q[0], RESPAWN_S])

## Le joueur, arrêté devant une fin d'autorisation tenue par une rame IA, n'attend jamais
## indéfiniment : passé YIELD_S, la rame qui le bloque est retirée du service.
func _yield_to_player(dt: float) -> void:
	var il := player.interlocking
	if il == null or il.authority.is_empty() or bool(il.authority.get("final", false)) or player.phys.speed > 0.1:
		_player_wait = 0.0; return
	var da := player.dist_to_point(str(il.authority.edge), float(il.authority.offset), 300.0)
	if da == INF or da > 120.0:
		_player_wait = 0.0; return
	_player_wait += dt
	if _player_wait < YIELD_S: return
	var blocker := blocking_tram()
	if blocker != null:
		_retire(blocker, "Régulation : rame %s (ligne %s) retirée pour libérer votre itinéraire" % [blocker.train_id, blocker.line])
	_player_wait = 0.0

## Rame IA qui tient la section au-delà de la fin d'autorisation du joueur (ou null).
func blocking_tram() -> AiTram:
	var il := player.interlocking
	if il == null or il.authority.is_empty(): return null
	var g := net.graph
	var owners := {}
	for k in range(il.pos, mini(il.path.size(), il.pos + 40)):
		var e := str(il.path[k][0])
		var o := str(g.reserved.get(e, g.edges[e].occupied_by))
		if o != "" and o != player.train_id: owners[o] = true
		var x := g.exit_of(e, int(il.path[k][1]))
		var lock := str(g.locks.get(TrackGraph.skey(str(x[0]), int(x[1])), ""))
		if lock != "" and lock != player.train_id: owners[lock] = true
		if not owners.is_empty(): break
	for t in trams:
		if owners.has(t.train_id): return t
	return null

func _why(t: AiTram) -> String:
	var sm := SignalModel.of(net)
	var g := net.graph
	for it in sm.ahead(t, 300.0):
		var sg: Dictionary = sm.list[int(it.i)]
		if sm.aspect(int(it.i)) == "stop":
			var nx := g.next_step(str(sg.edge), int(sg.dir))
			var e2 := str(nx[0]) if not nx.is_empty() else ""
			return "%s à %d m, suite %s rés=%s occ=%s lock=%s" % [sg.kind, roundi(it.dist), e2, g.reserved.get(e2, ""), g.edges[e2].occupied_by if e2 != "" else "", g.locks.get(TrackGraph.skey(str(sg.get("node", "")), int(sg.get("side", 1))), "")]
	return "auth " + str(t.interlocking.authority)

func _holder(t: AiTram) -> String:
	var il := t.interlocking; var g := net.graph
	for k in range(il.pos, il.path.size()):
		var e := str(il.path[k][0])
		var r := str(g.reserved.get(e, "")); var o: String = g.edges[e].occupied_by
		if (r != "" and r != t.train_id) or (o != "" and o != t.train_id):
			return "bloqué en %d/%d : %s rés=%s occ=%s" % [k, il.path.size(), e, r, o]
		if k + 1 < il.path.size():
			var x := g.exit_of(e, int(il.path[k][1]))
			for sd in [int(x[1]), -int(x[1])]:
				var lk := str(g.locks.get(TrackGraph.skey(str(x[0]), sd), ""))
				if lk != "" and lk != t.train_id: return "aiguille %s verrouillée par %s (%d/%d)" % [x[0], lk, k, il.path.size()]
	return "fin d'itinéraire"

## Rames en service à proximité (pour l'affichage).
func near(center: Vector2, radius: float) -> Array:
	var out: Array = []
	for t in trams:
		if (net.point_on(t.edge_id, t.offset).p as Vector2).distance_to(center) <= radius: out.append(t)
	return out
