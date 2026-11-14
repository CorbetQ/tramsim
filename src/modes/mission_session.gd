class_name MissionSession
extends RefCounted
## Session de conduite sur un réseau : position sur le graphe, arrêts, portes,
## signaux, occupation, ponctualité. Indépendante du rendu (testable sans écran).

signal event(kind: String, text: String)

const STOP_TOLERANCE_M := 5.0
const BOARD_RATE_PER_S := 4.0

var net: NetworkLoader
var phys: TrainPhysics
var scorer := MissionScorer.new()
var train_id := "T1"
var route: Array[String] = []        # arêtes parcourues (queue incluse)
var route_dir: Array[int] = []       # sens de parcours de chaque arête de route (+1 / -1)
var edge_id: String
var offset: float = 0.0              # abscisse du nez (tête dans le sens de marche) sur edge_id, depuis from_node
var direction: int = 1               # sens de marche sur edge_id : +1 dans le sens de l'arête, -1 à rebours
var time_s: float = 0.0
var doors_open := false
var finished := false
var overspeed := false
var stops: Array = []               # arrêts desservis par la mission (défaut : toutes les stations)
var schedule: Array[float] = []      # heure de départ prévue par station
var next_station := 0
var dwell_left := 0.0
var served := false                  # arrêt courant desservi
var door_cycle_done := false
var _departure_time := -1.0
var pantograph_up := true
var power_ok := true
var power_mode := "overhead"
var power_transition_left := 0.0
const POWER_SWITCH_SECONDS := 0.6
var traffic: RoadTraffic
var blocked := false
var visited: Dictionary = {}
var _board_acc := 0.0
var _alight_acc := 0.0
var signal_state: Dictionary = {}    # idx -> "clear"/"stop"
# Mode mission sur réseau complet (MissionCatalog) : poste d'aiguillage, événements, objectifs.
var interlocking: Interlocking = null
var events: MissionEvents = null
var mission: Dictionary = {}
var target: Dictionary = {}          # {edge, offset, tolerance} : immobilisation finale (dépôt)
var achieved: Dictionary = {}        # objectifs atteints (mise sous tension, débarquement, cible…)
var overspeed_s := 0.0
var sand_left_s := 0.0
const SAND_RESERVE_S := 90.0
const ALIGHT_RATE_PER_S := 6.0
# Signalisation lumineuse (SignalModel) : signaux devant la rame, rames IA du réseau.
var sig_ahead: Array = []            # [{i, dist}] mis à jour à chaque pas par SignalModel.update
var ai: AiTrams = null               # rames en circulation gérées par le jeu (mode mission)
var crossing_strict := true          # feu de carrefour franchi à l'arrêt = échec (mission)

func _init(network: NetworkLoader, profile: VehicleProfile, start_edge: String, start_offset: float, sched: Array[float], pax: int = 40) -> void:
	net = network
	stops = network.stations
	phys = TrainPhysics.new(profile)
	phys.passengers = pax
	edge_id = start_edge
	offset = start_offset
	schedule = sched
	route = [start_edge]
	route_dir = [1]
	visited[start_edge] = true
	net.graph.occupy(start_edge, train_id)
	for i in net.signals.size():
		signal_state[i] = net.signals[i].get("default", "clear")
	initialize_power()
	traffic = RoadTraffic.new(net.meta.get("roads", []))

## Remplace la liste d'arrêts (mission issue du GTFS) : indices dans net.stations.
func set_mission_stops(indices: Array) -> void:
	stops = []
	for i in indices:
		stops.append(net.stations[int(i)])

## Limite la plus restrictive sous la rame (du nez à la queue sur l'arête courante, et devant 0 m).
func speed_limit() -> float:
	var v := net.limit_at(edge_id, offset)
	var tail := offset - phys.profile.length_m * direction
	var lo := maxf(0.0, minf(tail, offset)); var hi := maxf(tail, offset)
	for z in net.edge_info[edge_id].zones:
		if z[1] >= lo and z[0] <= hi:
			v = minf(v, z[2])
	# Restrictions sous la queue sur les arêtes précédentes, sans lever trop tôt
	# la consigne lorsque le nez sort d'une courbe.
	var back := locate_behind(phys.profile.length_m)
	for index in range(int(back[3]), route.size() - 1):
		var previous := route[index]
		var length_: float = net.graph.edges[previous].length
		var from_: float = float(back[1]) if index == int(back[3]) else (0.0 if route_dir[index] > 0 else length_)
		var end_: float = length_ if route_dir[index] > 0 else 0.0
		v = minf(v, net.edge_info[previous].limit_ms)
		for zone in net.edge_info[previous].zones:
			if float(zone[1]) >= minf(from_, end_) and float(zone[0]) <= maxf(from_, end_): v = minf(v, zone[2])
	if events != null: v = minf(v, events.speed_cap(self))
	var remaining: float = net.graph.edges[edge_id].length - offset if direction > 0 else offset
	if remaining < 10.0: v = minf(v, net.junction_limit(edge_id, direction))
	# La queue conserve la restriction du raccord jusqu'à sa sortie complète.
	if (offset if direction > 0 else net.graph.edges[edge_id].length - offset) < phys.profile.length_m and route.size() >= 2:
		v = minf(v, net.junction_limit(route[-2], route_dir[-2]))
	return v

func set_doors(open: bool) -> void:
	if open and phys.speed > 0.1:
		return  # interdit en marche
	if open and not doors_open:
		_departure_time = -1.0
		var st := _station_here()
		if not st.is_empty():
			served = true
			dwell_left = float(st.dwell_s)
	if not open and doors_open:
		door_cycle_done = true
	doors_open = open

func _station_here() -> Dictionary:
	if next_station >= stops.size():
		return {}
	var s: Dictionary = stops[next_station]
	if net.station_contains(s, edge_id, offset) or (not s.has("stop_area") and absf(dist_to_point(str(s.edge), float(s.offset), 50.0)) <= STOP_TOLERANCE_M):
		return s
	return {}

func _fail(reason: String) -> void:
	scorer.safety_fault(reason)
	finished = true
	event.emit("fail", reason)

## Remise à zéro après échec (recommencer la mission) : recharge via nouvelle session.

## Distance (m) du nez de la rame à un point de voie : >0 devant, <0 derrière, INF si hors de portée.
func dist_to_point(to_edge: String, to_offset: float, horizon: float = 1500.0) -> float:
	if to_edge == edge_id:
		return (to_offset - offset) * direction
	_sync_dirs()
	var d: float = _ahead_on_edge()
	var e: String = edge_id
	var r: int = direction
	while d < horizon:
		var st := net.graph.next_step(e, r)
		if st.is_empty():
			break
		e = st[0]; r = st[1]
		var L: float = net.graph.edges[e].length
		if e == to_edge:
			return d + (to_offset if r > 0 else L - to_offset)
		d += L
	# croisement derrière sur une arête déjà parcourue et encore sous la rame
	var back := _behind_on_edge()
	for i in range(route.size() - 2, -1, -1):
		var L: float = net.graph.edges[route[i]].length
		if route[i] == to_edge:
			return -(back + (L - to_offset if route_dir[i] > 0 else to_offset))
		back += L
	return INF

## Distance du nez à la fin de l'arête courante (dans le sens de marche) et à son début (derrière).
func _ahead_on_edge() -> float:
	return net.graph.edges[edge_id].length - offset if direction > 0 else offset

func _behind_on_edge() -> float:
	return offset if direction > 0 else net.graph.edges[edge_id].length - offset

## route_dir suit route (route peut être réassignée de l'extérieur, ex. tests) : sens +1 par défaut.
func _sync_dirs() -> void:
	if route_dir.size() != route.size():
		route_dir.clear()
		for i in route.size():
			route_dir.append(direction if i == route.size() - 1 else 1)
	if not route.is_empty():
		route_dir[route.size() - 1] = direction

## Point de voie situé `d` mètres derrière le nez : [arête, abscisse, sens, indice dans route].
func locate_behind(d: float) -> Array:
	_sync_dirs()
	var i := route.size() - 1
	var rem := d
	var avail := _behind_on_edge()
	while rem > avail and i > 0:
		rem -= avail
		i -= 1
		avail = net.graph.edges[route[i]].length
	var L: float = net.graph.edges[route[i]].length
	var r: int = route_dir[i]
	var exit_x: float = offset if i == route.size() - 1 else (L if r > 0 else 0.0)
	return [route[i], clampf(exit_x - rem * r, 0.0, L), r, i]

var _st_index: Dictionary = {}

## Prochaine station devant la rame (toutes stations du réseau, utile en mode libre).
func next_station_ahead(max_edges: int = 10) -> Dictionary:
	if _st_index.is_empty():
		for st in net.stations:
			if not _st_index.has(st.edge): _st_index[st.edge] = []
			_st_index[st.edge].append(st)
			for segment in st.get("stop_area", {}).get("segments", []):
				var id := str(segment[0])
				if id == str(st.edge): continue
				if not _st_index.has(id): _st_index[id] = []
				if not st in _st_index[id]: _st_index[id].append(st)
	var e := edge_id
	var r := direction
	var off := offset
	for i in max_edges:
		var best: Dictionary = {}
		var best_distance := INF
		for st in _st_index.get(e, []):
			var start := float(st.offset); var end := start
			var segments: Array = st.get("stop_area", {}).get("segments", [])
			if not segments.is_empty():
				start = INF; end = -INF
				for segment in segments:
					if str(segment[0]) == e:
						start = minf(start, float(segment[1])); end = maxf(end, float(segment[2]))
			if start == INF: continue
			var ahead := (start - off) if r > 0 else (off - end)
			var exit_distance := (end - off) if r > 0 else (off - start)
			if exit_distance >= (-3.0 if segments.is_empty() else 0.0) and maxf(ahead, 0.0) < best_distance:
				best = st; best_distance = maxf(ahead, 0.0)
		if not best.is_empty(): return best
		var nx := net.graph.next_step(e, r)
		if nx.is_empty(): break
		e = nx[0]; r = nx[1]
		off = -1.0 if r > 0 else net.graph.edges[e].length + 1.0
	return {}

## Distance à l'entrée de la zone ; zéro pendant toute la présence à quai.
func station_distance(station: Dictionary, horizon: float = 3000.0) -> float:
	if net.station_contains(station, edge_id, offset): return 0.0
	var segments: Array = station.get("stop_area", {}).get("segments", [])
	if segments.is_empty(): return dist_to_point(str(station.edge), float(station.offset), horizon)
	var nearest := INF
	for segment in segments:
		for at in [segment[1], segment[2]]:
			var d := dist_to_point(str(segment[0]), float(at), horizon)
			if d >= 0.0: nearest = minf(nearest, d)
	return nearest

func _dist_cb(_e: String, _o: float, to_edge: String, to_offset: float) -> float:
	return dist_to_point(to_edge, to_offset)

func tick(dt: float, notch: float, emergency: bool = false) -> void:
	if finished or blocked:
		return
	time_s += dt
	if traffic.enabled and traffic.lanes.size() > 0:
		traffic.step(dt, edge_id, offset, phys.profile.length_m, _dist_cb)
		for li in traffic.lanes.size():
			var lane: Dictionary = traffic.lanes[li]
			var d := dist_to_point(lane.edge, float(lane.edge_offset))
			if d != INF and d <= 0.0 and d > -phys.profile.length_m and traffic.car_in_crossing(li):
				_fail("Collision avec un véhicule")
				return
	var info: Dictionary = net.edge_info[edge_id]
	var n := notch
	if doors_open:
		n = minf(n, -0.75)  # interverrouillage de portes : traction coupée et frein de maintien
	_update_signals()
	var sm := SignalModel.of(net)
	sm.interlocked = interlocking != null
	if ai != null: ai.step(dt, self)
	else: sm.update(dt, [self])
	if events != null:
		phys.adhesion = events.adhesion_at(self)
		if phys.sanding:
			sand_left_s = maxf(0.0, sand_left_s - dt)
			if sand_left_s <= 0.0: phys.sanding = false; event.emit("sand", "Réserve de sable épuisée")
	power_transition_left = maxf(0.0, power_transition_left - dt)
	_update_power(net.supply_at(edge_id, offset))
	if not power_ok: n = minf(n, -0.75) # frein de sécurité, maintien même en descente
	var before := phys.position
	phys.step(dt, n, net.grade_at(edge_id, offset) * direction, emergency or doors_open and phys.speed > 0.1)
	var d := phys.position - before
	overspeed = phys.speed > speed_limit() + 0.5
	if overspeed: overspeed_s += dt
	_advance(d)
	if finished:
		return
	if d > 0.0 and _crossing_passed(sm, d): return
	if power_ok and pantograph_up: achieved["powered"] = true
	if interlocking != null:
		interlocking.update(self)
		if interlocking.error == "Sortie d'itinéraire": _fail("Sortie de l'itinéraire tracé"); return
		if interlocking.authority_passed(self):
			_fail("Point d'arrêt de fin d'itinéraire dépassé" if bool(interlocking.authority.get("final", false)) else "Signal d'arrêt franchi (itinéraire non tracé)")
			return
	if events != null:
		var reason := events.tick(self, dt)
		if reason != "": _fail(reason); return
	if mission.has("time_limit_s") and time_s > float(mission.time_limit_s) and not finished:
		_fail("Délai dépassé"); return
	_update_dwell(dt)
	_check_station_passed()
	_check_target()

## Feu de carrefour franchi à l'arrêt pendant ce pas : échec en mission, avertissement sinon.
func _crossing_passed(sm: SignalModel, moved: float) -> bool:
	for it in sig_ahead:
		var i := int(it.i)
		if float(it.dist) > moved: break
		if float(it.dist) < 0.0 or not sm.cross.has(i) or sm.aspect(i) != "stop": continue
		if crossing_strict:
			_fail("Feu de carrefour franchi (barre horizontale)")
			return true
		event.emit("signal", "Feu de carrefour franchi à l'arrêt")
	return false

## Cantonnement automatique : un signal portant `protects` passe à l'arrêt si la section
## protégée est occupée par un autre mobile ; sans `protects`, l'état est celui fixé à la main.
func _update_signals() -> void:
	for i in net.signals.size():
		var sg: Dictionary = net.signals[i]
		if sg.has("protects"):
			var occ: String = net.graph.edges[sg.protects].occupied_by
			signal_state[i] = "stop" if (occ != "" and occ != train_id) else "clear"

## Alimentation selon le mode de la section et l'état du pantographe.
func available_power_modes() -> PackedStringArray:
	return phys.profile.power_modes()

func initialize_power() -> void:
	var modes := available_power_modes()
	var section := net.supply_at(edge_id, offset)
	power_mode = section if section in modes else str(modes[0])
	pantograph_up = power_mode == "overhead"
	power_transition_left = 0.0
	_update_power(section)

static func power_label(mode: String) -> String:
	return {"overhead":"LAC", "aps":"APS", "battery":"Autonomie", "third_rail":"Troisième rail", "none":"Non alimentée"}.get(mode, mode)

func set_power_mode(mode: String) -> String:
	if phys.speed >= 0.1: return "Arrêtez la rame avant de changer d’alimentation"
	if not mode in available_power_modes(): return "Alimentation incompatible avec ce matériel"
	if power_transition_left > 0.0: return "Commutation en cours"
	if power_mode == mode and pantograph_up == (mode == "overhead"): return ""
	power_mode = mode; pantograph_up = mode == "overhead"
	power_transition_left = POWER_SWITCH_SECONDS
	power_ok = false; phys.power_available = false
	event.emit("power", "Commutation vers " + power_label(mode))
	return ""

func _update_power(_edge_supply: String) -> void:
	var contact := pantograph_up if power_mode == "overhead" else not pantograph_up
	var here := net.supplies_at(edge_id, offset)
	if events != null: here = events.filter_supplies(self, here)
	var ok := power_transition_left <= 0.0 and power_mode in here and contact and power_mode in available_power_modes()
	if ok != power_ok:
		event.emit("power", "Alimentation rétablie" if ok else "Coupure d’alimentation — vérifier le mode")
	power_ok = ok; phys.power_available = ok

## Compatibilité des commandes internes anciennes : bascule via le même
## interverrouillage, jamais par déduction implicite du seul pantographe.
func toggle_pantograph() -> void:
	var modes := available_power_modes()
	if modes.size() < 2: return
	set_power_mode(str(modes[(modes.find(power_mode) + 1) % modes.size()]))

func _advance(d: float) -> void:
	if d < 0.0:
		_retreat(-d); return
	_sync_dirs()
	offset += d * direction
	while true:
		var e: TrackGraph.Edge = net.graph.edges[edge_id]
		# signal d'arrêt franchi (signaux orientés dans le sens de l'arête)
		if direction > 0:
			for i in net.signals.size():
				var s: Dictionary = net.signals[i]
				if s.edge == edge_id and signal_state[i] == "stop" and offset - d < float(s.offset) and offset >= float(s.offset):
					_fail("Signal d'arrêt franchi")
					return
		var over: float = offset - e.length if direction > 0 else -offset
		if over < 0.0:
			break
		var end_x: float = e.length if direction > 0 else 0.0
		var nxt := net.graph.next_step(edge_id, direction)
		if nxt.is_empty():
			offset = end_x
			phys.speed = 0.0
			_fail("Fin de voie dépassée")
			return
		if not net.graph.occupy(nxt[0], train_id):
			offset = end_x
			phys.speed = 0.0
			_fail("Collision")
			return
		edge_id = nxt[0]
		direction = nxt[1]
		offset = over if direction > 0 else net.graph.edges[edge_id].length - over
		route.append(edge_id)
		route_dir.append(direction)
		visited[edge_id] = true
	_release_tail()

## Recul réel, sans changer de cabine : retraverser les nœuds derrière le nez.
func _retreat(distance_: float) -> void:
	_sync_dirs()
	offset -= distance_*direction
	while offset < 0.0 or offset > net.graph.edges[edge_id].length:
		var extra: float = -offset if direction>0 else offset-net.graph.edges[edge_id].length
		var old := edge_id
		var history := route.size()>1
		var target:String
		var target_direction:int
		if history:
			target=route[-2];target_direction=route_dir[-2]
		else:
			var step := net.graph.next_step(edge_id,-direction)
			if step.is_empty():
				offset=clampf(offset,0.0,net.graph.edges[old].length); phys.speed=0.0
				_fail("Recul au-delà de la fin de voie"); return
			target=step[0];target_direction=-int(step[1])
		if not net.graph.occupy(target,train_id):
			offset=clampf(offset,0.0,net.graph.edges[old].length)
			phys.speed=0.0; _fail("Collision en recul"); return
		if history:route.pop_back();route_dir.pop_back()
		else:route=[target];route_dir=[target_direction]
		edge_id=target;direction=target_direction
		net.graph.release(old,train_id); visited[edge_id]=true
		offset=net.graph.edges[edge_id].length-extra if direction>0 else extra
	_release_tail()

## Libère les arêtes derrière la queue de la rame (longueur dans l'occupation).
func _release_tail() -> void:
	_sync_dirs()
	var covered := _behind_on_edge()
	var keep := route.size() - 1
	while covered < phys.profile.length_m and keep > 0:
		keep -= 1
		covered += net.graph.edges[route[keep]].length
	var kept := route.slice(keep)
	for i in keep:
		if not route[i] in kept:
			net.graph.release(route[i], train_id)
	route = kept
	route_dir = route_dir.slice(keep)

func _update_dwell(dt: float) -> void:
	var here: Dictionary = stops[next_station] if next_station < stops.size() else {}
	if doors_open and served:
		var board_rate := BOARD_RATE_PER_S
		var alight_rate := BOARD_RATE_PER_S * 0.8
		if bool(here.get("alight_all", false)):
			board_rate = 0.0; alight_rate = ALIGHT_RATE_PER_S
		elif events != null:
			var crowd := events.crowd_at(str(here.get("name", "")))
			if not crowd.is_empty():
				board_rate *= float(crowd.get("factor", 3.0))
				if not crowd.has("announced"): crowd["announced"] = true; event.emit("crowd", "Affluence à " + str(here.name) + " : embarquement prolongé")
		_board_acc += board_rate * dt
		_alight_acc += alight_rate * dt
		var on := int(_board_acc)
		var off := int(_alight_acc)
		_board_acc -= on
		_alight_acc -= off
		phys.passengers = clampi(phys.passengers + on - off, 0, phys.profile.capacity)
		if bool(here.get("alight_all", false)) and phys.passengers == 0 and not achieved.has("alighted"):
			achieved["alighted"] = true; event.emit("alight", "Tous les voyageurs sont descendus")
		dwell_left = maxf(0.0, dwell_left - dt)
	var last := next_station == stops.size() - 1
	# départ : portes fermées, cycle fait, rame qui repart (terminus : fermeture suffit)
	if served and door_cycle_done and not doors_open and (phys.speed > 0.5 or last):
		var st: Dictionary = stops[next_station]
		if _departure_time < 0.0: _departure_time = time_s - dt
		if not last and st.has("stop_area") and net.station_contains(st, edge_id, offset): return
		if bool(st.get("alight_all", false)) and phys.passengers > 0:
			_fail("Départ avec des voyageurs à bord (terminus : tout le monde descend)"); return
		var planned: float = _departure_time if bool(st.get("free_time", false)) else schedule[next_station]
		var r := scorer.evaluate_departure(st.name, planned, _departure_time, true)
		event.emit("departure", "%s : %s" % [st.name, ["OK", "départ anticipé", "retard > 60 s", "arrêt oublié"][r]])
		next_station += 1
		served = false
		door_cycle_done = false
		_departure_time = -1.0
		if next_station >= stops.size():
			finished = target.is_empty()

func _check_station_passed() -> void:
	if next_station >= stops.size() or served:
		return
	var s: Dictionary = stops[next_station]
	if net.station_contains(s, edge_id, offset): return
	var segments: Array = s.get("stop_area", {}).get("segments", [])
	if not segments.is_empty():
		var was_visited := false
		for segment in segments:
			was_visited = was_visited or visited.has(str(segment[0]))
		if not was_visited: return
		var last_distance := -INF
		for segment in segments:
			for at in [segment[1], segment[2]]:
				var d := dist_to_point(str(segment[0]), float(at), 500.0)
				if d != INF: last_distance = maxf(last_distance, d)
		if last_distance >= 0.0 or (last_distance == -INF and not was_visited): return
		# Les bornes ont toutes été dépassées, pas seulement le repère d'arrêt OSM.
		scorer.evaluate_departure(s.name, schedule[next_station], time_s, false)
		event.emit("missed", "Arrêt oublié : " + s.name)
		next_station += 1
		return
	var passed: bool = (s.edge == edge_id and (offset - float(s.offset)) * direction > STOP_TOLERANCE_M) or (s.edge in visited and s.edge != edge_id)
	if passed:
		scorer.evaluate_departure(s.name, schedule[next_station], time_s, false)
		event.emit("missed", "Arrêt oublié : " + s.name)
		next_station += 1

func debrief() -> Dictionary:
	var out := {"success": scorer.success(), "reason": scorer.fail_reason, "stops": scorer.stops, "time_s": time_s}
	if mission.is_empty(): return out
	var objectives := _objectives()
	var ok: bool = out.success and finished
	for o in objectives: ok = ok and bool(o.done) and not bool(o.failed)
	var score := 100.0
	for st in scorer.stops:
		score -= {MissionScorer.Result.OK: 0.0, MissionScorer.Result.EARLY: 10.0, MissionScorer.Result.LATE: 8.0, MissionScorer.Result.MISSED_STOP: 25.0}[int(st.result)]
	score -= minf(overspeed_s * 1.5, 30.0)
	if events != null: score -= minf(events.flood_overspeed_s * 3.0 + events.slide_s * 0.5, 30.0)
	score = clampf(score, 0.0, 100.0) if ok else 0.0
	out.success = ok
	out["score"] = roundi(score)
	out["stars"] = 0 if not ok else (3 if score >= 85.0 else (2 if score >= 65.0 else 1))
	out["objectives"] = objectives
	return out

## Immobilisation finale sur la cible (voie de remisage) une fois les arrêts desservis.
func _check_target() -> void:
	if target.is_empty() or finished or next_station < stops.size(): return
	var d := dist_to_point(str(target.edge), float(target.offset), 300.0)
	if d != INF and absf(d) <= float(target.get("tolerance", 20.0)) and phys.speed < 0.1 and not doors_open:
		achieved["target"] = true
		finished = true
		event.emit("target", "Rame immobilisée : " + str(target.get("name", "fin de mission")))

## Aiguillages verrouillés et gérés par le poste : jamais manœuvrables en mission.
func locked_switches() -> bool:
	return true

## Manœuvre manuelle refusée en mission (le panneau des aiguillages est en lecture seule).
func select_branch(_node: String, _branch: int, _side: int = 1) -> bool:
	event.emit("switch", "Aiguillages verrouillés : itinéraire tracé par le poste")
	return false

## Sablage (missions à adhérence réduite) : réserve limitée.
func set_sanding(on: bool) -> bool:
	if on and sand_left_s <= 0.0: return false
	phys.sanding = on
	return true

## Changement de cabine : en mission, seulement au point de retournement tracé par le poste.
func reverse() -> String:
	if phys.speed > 0.1: return "Arrêtez la rame avant de changer de cabine"
	if interlocking == null: return "Changement de cabine non prévu par la mission"
	if not interlocking.can_reverse(self): return "Changement de cabine refusé : rejoignez le point de retournement"
	_swap_cab()
	if not interlocking.after_reverse(self): _fail("Aucun itinéraire de retour disponible")
	return ""

## Bascule de cabine : la queue devient la tête, la rame repart en sens inverse sur la même voie.
func _swap_cab() -> void:
	var tail: Array = locate_behind(phys.profile.length_m)
	var i: int = tail[3]
	var nr: Array[String] = []
	var nd: Array[int] = []
	for k in range(route.size() - 1, i - 1, -1):
		nr.append(route[k]); nd.append(-route_dir[k])
	route = nr
	route_dir = nd
	edge_id = tail[0]
	offset = tail[1]
	direction = -int(tail[2])
	phys.velocity = -phys.velocity
	for id in route:
		net.graph.occupy(id, train_id)
	doors_open = false
	event.emit("reverse", "Changement de cabine : marche " + ("dans le sens de la voie" if direction > 0 else "à contre-sens de la voie"))

## Objectifs en cours de la mission (catalogue) : [{id, text, done, failed}].
func _objectives() -> Array:
	var out: Array = []
	var kind := str(mission.get("type", ""))
	var bad := false
	for st in scorer.stops: bad = bad or int(st.result) != MissionScorer.Result.OK
	if kind == "depot_exit":
		out.append({"id": "power", "text": "Mettre sous tension : lever le pantographe", "done": achieved.has("powered"), "failed": false})
	if kind in ["depot_return", "turnback"]:
		var terminus := ""
		for st in stops: if bool(st.get("alight_all", false)): terminus = str(st.name)
		out.append({"id": "alight", "text": "Faire descendre tous les voyageurs à " + terminus, "done": achieved.has("alighted"), "failed": false})
	if kind == "turnback":
		out.append({"id": "reverse", "text": "Changer de cabine au point de retournement", "done": interlocking != null and interlocking.legs_done > 0, "failed": false})
	if not stops.is_empty():
		out.append({"id": "stops", "text": "Desservir les arrêts à l’heure (%d/%d)" % [mini(next_station, stops.size()), stops.size()], "done": next_station >= stops.size(), "failed": bad})
	if kind == "depot_return":
		out.append({"id": "depot", "text": "Rentrer au dépôt et s’immobiliser : " + str(target.get("name", "")), "done": achieved.has("target"), "failed": false})
	if events != null:
		var skipped := events.skipped_stops()
		if not skipped.is_empty():
			out.append({"id": "detour", "text": "Suivre la déviation (non desservis : %s)" % ", ".join(PackedStringArray(skipped)), "done": finished and next_station >= stops.size(), "failed": false})
		if not events.of_kind("flood").is_empty():
			out.append({"id": "flood", "text": "Traverser la zone inondée à 10 km/h au plus", "done": events.flags.has("flood_crossed"), "failed": events.flood_overspeed_s > 3.0})
		if not events.of_kind("leaves").is_empty():
			out.append({"id": "adhesion", "text": "Maîtriser patinage et enrayage (sablage : %d s)" % roundi(sand_left_s), "done": finished, "failed": false})
		if not events.of_kind("pantograph_fault").is_empty():
			out.append({"id": "fault", "text": "Défaut pantographe : s’arrêter, réarmer, relever", "done": events.flags.has("fault_cleared"), "failed": false})
		if not events.of_kind("power_cut").is_empty():
			out.append({"id": "power_cut", "text": "Coupure d’alimentation : attendre le rétablissement ou basculer sur batterie", "done": events.flags.has("power_restored") or finished, "failed": false})
		if not events.of_kind("obstacle").is_empty():
			out.append({"id": "obstacle", "text": "Véhicule sur la voie : s’arrêter avant et attendre le dégagement", "done": events.flags.has("obstacle_cleared"), "failed": false})
		for c in events.of_kind("crowd"):
			out.append({"id": "crowd", "text": "Affluence à %s : tolérance de retard %d s" % [str(c.station), roundi(scorer.max_late_s)], "done": next_station >= stops.size(), "failed": bad})
	if mission.has("time_limit_s"):
		out.append({"id": "time", "text": "Terminer avant %d min" % ceili(float(mission.time_limit_s) / 60.0), "done": finished and time_s <= float(mission.time_limit_s), "failed": time_s > float(mission.time_limit_s)})
	return out

## Fiche de mission pour l'interface : titre, objectifs en cours, contraintes, état.
func mission_brief() -> Dictionary:
	var status := "en cours"
	if finished: status = "réussie" if debrief().success else "échouée"
	var next_text := ""
	if next_station < stops.size(): next_text = "Prochain arrêt : " + str(stops[next_station].name)
	elif not target.is_empty(): next_text = "Destination : " + str(target.get("name", ""))
	if interlocking != null and interlocking.awaiting_reverse() and interlocking.remaining_length(self) < 300.0 and (next_station >= stops.size() or not stops[next_station].get("alight_all", false) or achieved.has("alighted")):
		next_text = "Rejoindre le point de retournement puis changer de cabine"
	var signal_text := ""
	if interlocking != null:
		var sig := interlocking.signals_ahead(self, 800.0)
		if not sig.is_empty(): signal_text = "%s à %d m" % ["Voie libre" if sig[0].state == "clear" else "Arrêt", roundi(float(sig[0].distance))]
	return {"id": str(mission.get("id", "")), "title": str(mission.get("title", "")), "type": str(mission.get("type", "")),
		"line": str(mission.get("line", "")), "objectives": _objectives(), "conditions": mission.get("conditions", []),
		"constraints": mission.get("constraints", []), "next": next_text, "signal": signal_text, "status": status,
		"time_s": time_s, "reason": scorer.fail_reason, "locked_switches": locked_switches()}

## Première restriction devant la rame, sur l'itinéraire réellement sélectionné.
func next_restriction(horizon: float = 220.0) -> Dictionary:
	var current := speed_limit()
	var e := edge_id; var r := direction; var off := offset; var travelled := 0.0
	var best: Dictionary = {}; var nearest := horizon
	for iteration in 32:
		var length_: float = net.graph.edges[e].length
		var info: Dictionary = net.edge_info[e]
		if iteration > 0 and float(info.limit_ms) < current - 0.5 and travelled < nearest:
			nearest = travelled; best = {"distance":nearest, "limit":float(info.limit_ms)}
		for zone in info.zones:
			var start: float = float(zone[0]) if r > 0 else float(zone[1])
			var d := travelled + (start - off) * r
			if d > 1.0 and d < nearest and float(zone[2]) < current - 0.5:
				nearest = d; best = {"distance":d, "limit":float(zone[2])}
		var remaining: float = length_ - off if r > 0 else off
		var junction := net.junction_limit(e, r)
		if junction < current - 0.5 and travelled + remaining < nearest:
			nearest = travelled + remaining; best = {"distance":nearest, "limit":junction}
		travelled += remaining
		if travelled >= horizon: break
		var next := net.graph.next_step(e, r)
		if next.is_empty(): break
		e = str(next[0]); r = int(next[1]); off = 0.0 if r > 0 else net.graph.edges[e].length
	if events != null:
		var ev := events.next_restriction(self, horizon)
		if not ev.is_empty() and float(ev.distance) < nearest and float(ev.limit) < current - 0.5: best = ev
	return best
