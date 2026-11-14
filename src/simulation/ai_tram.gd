class_name AiTram
extends MissionSession
## Rame en circulation gérée par le jeu (mode mission) : conduite par Autopilot, itinéraire
## tracé par son propre poste (Interlocking, propriétaire = identifiant de rame), arrêts aux
## stations de sa ligne, retournement aux terminus, puis service dans l'autre sens.

const TURNBACK_MAX_M := 1500.0

var line := ""
var driver := Autopilot.new()
var legs: Array = []          # [points de passage aller, retour]
var leg := 0
var wait_s := 0.0             # immobilisation hors station (signal, autorisation)
var stuck := false
var fail_reason := ""
var turnbacks := 0

func _init(network: NetworkLoader, profile: VehicleProfile, id: String, line_: String, nose_edge: String, nose_offset: float, edges: Array, dirs: Array) -> void:
	train_id = id
	super._init(network, profile, nose_edge, nose_offset, [] as Array[float], 60)
	line = line_
	driver.enabled = true
	driver.line = line_
	driver.auto_reverse = false
	route.clear(); route_dir.clear()
	for k in edges.size():
		route.append(str(edges[k])); route_dir.append(int(dirs[k]))
		net.graph.occupy(str(edges[k]), train_id)
	edge_id = nose_edge
	direction = int(dirs[-1])
	pantograph_up = true
	power_ok = true; phys.power_available = true
	interlocking = Interlocking.new(net, train_id)
	interlocking.reserve_m = 420.0

func _fail(reason: String) -> void:
	stuck = true
	fail_reason = reason
	phys.velocity = 0.0

## Pas de simulation simplifié (pas d'alimentation, de trafic routier ni d'événements).
func ai_tick(dt: float) -> void:
	if stuck: return
	time_s += dt
	interlocking.update(self)
	if interlocking.error != "":
		_fail(interlocking.error); return
	var n := driver.control(self, dt)
	if driver.state != "dwell" and phys.speed < 0.05:
		if interlocking.awaiting_reverse() and interlocking.can_reverse(self):
			_swap_cab(); turnbacks += 1
			if not interlocking.after_reverse(self): _fail("Aucun itinéraire après retournement"); return
			driver.reset(); n = -0.75
		elif not interlocking.awaiting_reverse() and interlocking.remaining_waypoints() == 0 and interlocking.remaining_length(self) < 30.0:
			if not next_leg(): return
			n = -0.75
	phys.power_available = true
	var before := phys.position
	phys.step(dt, n, net.grade_at(edge_id, offset) * direction, false)
	var d := phys.position - before
	if absf(d) > 0.0: _advance(d)
	if phys.speed < 0.05 and driver.state != "dwell": wait_s += dt
	else: wait_s = 0.0

## Service suivant (autre sens) : itinéraire direct, ou changement de cabine sur place, ou
## recherche d'un point de retournement. Faux si aucun itinéraire n'existe (rame bloquée).
func next_leg() -> bool:
	leg = (leg + 1) % legs.size()
	var wps: Array = legs[leg]
	var first: Dictionary = wps[0]
	var direct := Interlocking.find_path(net, edge_id, offset, direction, str(first.edge), float(first.offset), int(first.get("dir", 0)), {}, false, false, TURNBACK_MAX_M)
	if direct.is_empty():
		_swap_cab(); turnbacks += 1
		var back := Interlocking.find_path(net, edge_id, offset, direction, str(first.edge), float(first.offset), int(first.get("dir", 0)), {}, false, false, TURNBACK_MAX_M)
		if back.is_empty():
			_swap_cab()   # cabine d'origine : avancer pour se retourner (impasse de terminus)
			var rv := _reversal_on_edge(first)
			if rv.is_empty():
				rv = Interlocking.find_reversal(net, {"edge": edge_id, "offset": offset, "dir": direction}, first, phys.profile.length_m)
			if rv.is_empty():
				_swap_cab()
				rv = _reversal_on_edge(first)
			if rv.is_empty():
				rv = Interlocking.find_reversal(net, {"edge": edge_id, "offset": offset, "dir": direction}, first, phys.profile.length_m)
			if rv.is_empty():
				_fail("Retournement impossible (%s@%.0f d%d vers %s)" % [edge_id, offset, direction, str(first.edge)]); return false
			wps = [rv.point] + wps
	driver.reset()
	if not interlocking.setup(self, wps):
		_fail("Itinéraire de retour impossible"); return false
	return true

## Retournement sur l'arête courante (voie en impasse au-delà du quai) : avancer, changer de
## cabine, revenir au point de départ du service suivant. {point} ou {}.
func _reversal_on_edge(first: Dictionary) -> Dictionary:
	var L: float = net.graph.edges[edge_id].length
	var room := (L - offset) if direction > 0 else offset
	var len_ := phys.profile.length_m
	if room < 12.0: return {}
	var nose := offset + (room - 8.0) * direction
	var tail := nose - (len_ + 1.0) * direction
	if (tail - offset) * direction < -len_: return {}
	var back := Interlocking.find_path(net, edge_id, clampf(tail, 0.0, L), -direction, str(first.edge), float(first.offset), int(first.get("dir", 0)), {}, false, false, TURNBACK_MAX_M)
	if back.is_empty(): return {}
	return {"point": {"edge": edge_id, "offset": nose, "dir": direction, "reverse": true}}

## Libère toutes les sections et réservations (retrait du service).
func remove() -> void:
	interlocking.release_all()
	for e in route: net.graph.release(e, train_id)
	stuck = true
