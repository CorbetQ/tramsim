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

func tick(dt: float, notch: float, emergency: bool = false) -> void:
	if finished:
		return
	time_s += dt
	var info: Dictionary = net.edge_info[edge_id]
	var n := notch
	if doors_open:
		n = minf(n, 0.0)  # traction coupée portes ouvertes
	var before := phys.position
	phys.step(dt, n, info.grade, emergency or doors_open and phys.speed > 0.1)
	var d := phys.position - before
	overspeed = phys.speed > info.limit_ms + 0.5
	_advance(d)
	if finished:
		return
	_update_dwell(dt)
	_check_station_passed()

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
