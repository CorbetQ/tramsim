extends RefCounted
## Pilote automatique de test : respecte limites, arrêts, portes, horaires et pantographe.

## Pilote automatique : s'arrête à chaque station, ouvre/ferme les portes.
func _drive(m: MissionSession, hold_s: float = 0.0, skip_stop: int = -1, max_t: float = 1500.0) -> void:
	_dt_state = 0.0
	while not m.finished and m.time_s < max_t:
		_auto_pantograph(m)
		_drive_step(m, hold_s, skip_stop)

## Pilote : pantographe levé sur caténaire, baissé sur APS (changement dès l'entrée en section).
func _auto_pantograph(m: MissionSession) -> void:
	var want_up: bool = m.net.supply_at(m.edge_id, m.offset) == "overhead"
	if want_up != m.pantograph_up:
		m.toggle_pantograph()

var _dt_state := 0.0
func _drive_step(m: MissionSession, hold_s: float = 0.0, skip_stop: int = -1) -> void:
	var dt := 0.1
	var door_timer := _dt_state
	if true:
		var i := m.next_station
		var notch := 0.0
		var st: Dictionary = m.stops[i] if i < m.stops.size() else {}
		if not st.is_empty():
			var dist := _dist_to(m, st)
			var v := m.phys.speed
			# courbe de freinage à 0,6 m/s², réduite en descente (pente de la voie sous la rame)
			var dec := clampf(0.6 + 9.81 * minf(m.net.grade_at(m.edge_id, m.offset) * m.direction, 0.0), 0.2, 0.6)
			var vmax := minf(m.speed_limit() - 1.0, sqrt(maxf(0.0, 2.0 * dec * (dist - 1.0))))
			if i == skip_stop: vmax = m.speed_limit() - 1.0
			notch = 1.0 if v < vmax - 0.3 else (-1.0 if v > vmax + 0.3 else 0.0)
			if dist < 2.5 and dist > -4.0 and i != skip_stop: notch = -1.0
			if v < 0.05 and absf(dist) < 4.0 and i != skip_stop:
				if not m.doors_open and not m.served:
					m.set_doors(true); door_timer = 0.0
				elif m.doors_open:
					door_timer += dt
					if door_timer > maxf(m.dwell_left, 0.0) and m.time_s >= m.schedule[i] + 3.0 + hold_s and door_timer > 5.0:
						m.set_doors(false)
				elif m.served:
					notch = 1.0
			if m.served and not m.doors_open: notch = 1.0
		m.tick(dt, notch)
		_dt_state = door_timer

func _dist_to(m: MissionSession, st: Dictionary) -> float:
	var d := 0.0
	var e := m.edge_id
	if e == st.edge: return float(st.offset) - m.offset
	d = m.net.graph.edges[e].length - m.offset
	while true:
		e = m.net.graph.next_edge(e)
		if e == "": return 1e9
		if e == st.edge: return d + float(st.offset)
		d += m.net.graph.edges[e].length
	return 1e9

