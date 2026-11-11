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
var edge_id: String
var offset: float = 0.0
var time_s: float = 0.0
var doors_open := false
var finished := false
var overspeed := false
var schedule: Array[float] = []      # heure de départ prévue par station
var next_station := 0
var dwell_left := 0.0
var served := false                  # arrêt courant desservi
var door_cycle_done := false
var pantograph_up := true
var power_ok := true
var traffic: RoadTraffic
var blocked := false
var visited: Dictionary = {}
var _board_acc := 0.0
var _alight_acc := 0.0
var signal_state: Dictionary = {}    # idx -> "clear"/"stop"

func _init(network: NetworkLoader, profile: VehicleProfile, start_edge: String, start_offset: float, sched: Array[float], pax: int = 40) -> void:
	net = network
	phys = TrainPhysics.new(profile)
	phys.passengers = pax
	edge_id = start_edge
	offset = start_offset
	schedule = sched
	route = [start_edge]
	visited[start_edge] = true
	net.graph.occupy(start_edge, train_id)
	for i in net.signals.size():
		signal_state[i] = net.signals[i].get("default", "clear")
	traffic = RoadTraffic.new(net.meta.get("roads", []))

func speed_limit() -> float:
	return net.edge_info[edge_id].limit_ms

func set_doors(open: bool) -> void:
	if open and phys.speed > 0.1:
		return  # interdit en marche
	if open and not doors_open:
		var st := _station_here()
		if not st.is_empty():
			served = true
			dwell_left = float(st.dwell_s)
	if not open and doors_open:
		door_cycle_done = true
	doors_open = open

func _station_here() -> Dictionary:
	if next_station >= net.stations.size():
		return {}
	var s: Dictionary = net.stations[next_station]
	if s.edge == edge_id and absf(float(s.offset) - offset) <= STOP_TOLERANCE_M:
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
		return to_offset - offset
	var d: float = net.graph.edges[edge_id].length - offset
	var e: String = edge_id
	while d < horizon:
		e = net.graph.next_edge(e)
		if e == "":
			break
		if e == to_edge:
			return d + to_offset
		d += net.graph.edges[e].length
	# croisement derrière sur une arête déjà parcourue et encore sous la rame
	var back := offset
	for i in range(route.size() - 2, -1, -1):
		if route[i] == to_edge:
			return -(back + net.graph.edges[to_edge].length - to_offset)
		back += net.graph.edges[route[i]].length
	return INF

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
		n = minf(n, 0.0)  # traction coupée portes ouvertes
	_update_signals()
	_update_power(info.supply)
	var before := phys.position
	phys.step(dt, n, info.grade, emergency or doors_open and phys.speed > 0.1)
	var d := phys.position - before
	overspeed = phys.speed > info.limit_ms + 0.5
	_advance(d)
	if finished:
		return
	_update_dwell(dt)
	_check_station_passed()

## Cantonnement automatique : un signal portant `protects` passe à l'arrêt si la section
## protégée est occupée par un autre mobile ; sans `protects`, l'état est celui fixé à la main.
func _update_signals() -> void:
	for i in net.signals.size():
		var sg: Dictionary = net.signals[i]
		if sg.has("protects"):
			var occ: String = net.graph.edges[sg.protects].occupied_by
			signal_state[i] = "stop" if (occ != "" and occ != train_id) else "clear"

## Alimentation selon le mode de la section et l'état du pantographe.
func _update_power(edge_supply: String) -> void:
	var sup := phys.profile.supply
	var ok := true
	if sup == "hybrid":
		ok = (edge_supply == "overhead" and pantograph_up) or (edge_supply == "aps" and not pantograph_up)
	elif sup == "overhead":
		ok = edge_supply == "overhead" and pantograph_up
	else:
		ok = sup == edge_supply
	if ok != power_ok:
		event.emit("power", "Alimentation rétablie" if ok else "Coupure d'alimentation")
	power_ok = ok
	phys.power_available = ok

func toggle_pantograph() -> void:
	pantograph_up = not pantograph_up

func _advance(d: float) -> void:
	offset += d
	while true:
		var e: TrackGraph.Edge = net.graph.edges[edge_id]
		# signal d'arrêt franchi
		for i in net.signals.size():
			var s: Dictionary = net.signals[i]
			if s.edge == edge_id and signal_state[i] == "stop" and offset - d < float(s.offset) and offset >= float(s.offset):
				_fail("Signal d'arrêt franchi")
				return
		if offset < e.length:
			break
		var nxt := net.graph.next_edge(edge_id)
		if nxt == "":
			offset = e.length
			phys.speed = 0.0
			_fail("Fin de voie dépassée")
			return
		if not net.graph.occupy(nxt, train_id):
			offset = e.length
			phys.speed = 0.0
			_fail("Collision")
			return
		offset -= e.length
		edge_id = nxt
		route.append(nxt)
		visited[nxt] = true
	_release_tail()

## Libère les arêtes derrière la queue de la rame (longueur dans l'occupation).
func _release_tail() -> void:
	var covered := offset
	var keep := route.size() - 1
	while covered < phys.profile.length_m and keep > 0:
		keep -= 1
		covered += net.graph.edges[route[keep]].length
	for i in keep:
		net.graph.release(route[i], train_id)
	route = route.slice(keep)

func _update_dwell(dt: float) -> void:
	if doors_open and served:
		_board_acc += BOARD_RATE_PER_S * dt
		_alight_acc += BOARD_RATE_PER_S * 0.8 * dt
		var on := int(_board_acc)
		var off := int(_alight_acc)
		_board_acc -= on
		_alight_acc -= off
		phys.passengers = clampi(phys.passengers + on - off, 0, phys.profile.capacity)
		dwell_left = maxf(0.0, dwell_left - dt)
	var last := next_station == net.stations.size() - 1
	# départ : portes fermées, cycle fait, rame qui repart (terminus : fermeture suffit)
	if served and door_cycle_done and not doors_open and (phys.speed > 0.5 or last):
		var st: Dictionary = net.stations[next_station]
		var r := scorer.evaluate_departure(st.name, schedule[next_station], time_s - dt, true)
		event.emit("departure", "%s : %s" % [st.name, ["OK", "départ anticipé", "retard > 60 s", "arrêt oublié"][r]])
		next_station += 1
		served = false
		door_cycle_done = false
		if next_station >= net.stations.size():
			finished = true

func _check_station_passed() -> void:
	if next_station >= net.stations.size() or served:
		return
	var s: Dictionary = net.stations[next_station]
	var passed: bool = (s.edge == edge_id and offset > float(s.offset) + STOP_TOLERANCE_M) or (s.edge in visited and s.edge != edge_id)
	if passed:
		scorer.evaluate_departure(s.name, schedule[next_station], time_s, false)
		event.emit("missed", "Arrêt oublié : " + s.name)
		next_station += 1

func debrief() -> Dictionary:
	return {"success": scorer.success(), "reason": scorer.fail_reason, "stops": scorer.stops, "time_s": time_s}
