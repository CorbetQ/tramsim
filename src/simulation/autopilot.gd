class_name Autopilot
extends RefCounted
## Conduite automatique d'une rame (pilote automatique du mode libre, conducteurs des rames IA).
## Courbes de freinage vers chaque contrainte devant la rame : limites de vitesse (zones,
## sections, raccords), arrêt en station (portes ouvertes puis fermées), signaux fermés
## (SignalModel), fin d'autorisation du poste (Interlocking) et heurtoirs. La rame suit les
## aiguillages tels qu'ils sont positionnés. Renvoie un cran de manipulateur (-1..1).

const MARGIN_MS := 0.8          # marge sous chaque limite (≈ 3 km/h)
const STOP_MARGIN_M := 3.0      # arrêt avant un signal fermé
const STATION_EXIT_M := 4.0     # nez arrêté à 4 m de la sortie de quai
const REPLAN_S := 0.15
const HORIZON_M := 520.0
const MIN_DWELL_S := 12.0
const DOOR_CLOSE_S := 2.0

var enabled := false
var state := "drive"            # drive | dwell
var dwell_left := 0.0
var served := ""                # station desservie (clé) : ignorée jusqu'à sa sortie
var line := ""                  # rames IA : seulement les stations de cette ligne
var serve_stations := true
var auto_reverse := true        # mode libre : changement de cabine au heurtoir
var station: Dictionary = {}    # station visée
var status := ""                # explication courte (HUD)
var holding := ""               # raison de l'immobilisation : "", "station", "signal", "authority", "buffer"
var stations_served := 0
var _targets: Array = []        # [distance au plan, vitesse visée, marge, raison]
var _cap := 0.0
var _moved := 0.0
var _last_pos := 0.0
var _t := 0.0

func reset() -> void:
	state = "drive"; served = ""; _t = 0.0; _targets.clear(); holding = ""; station = {}

static func station_key(st: Dictionary) -> String:
	return str(st.get("name", "")) + "@" + str(st.get("edge", ""))

func _decel(s: MissionSession) -> float:
	var p := s.phys
	return minf(p.profile.service_brake_ms2, p.effective_adhesion() * TrainPhysics.G * 0.85) * 0.55

## Cran de manipulateur pour ce pas ; gère aussi l'ouverture et la fermeture des portes.
func control(s: MissionSession, dt: float) -> float:
	if s.blocked or s.finished: return -1.0
	_check_power(s)
	if state == "dwell":
		dwell_left -= dt
		holding = "station"
		status = "Arrêt : " + str(station.get("name", ""))
		if dwell_left <= 0.0 and s.doors_open: s.set_doors(false)
		if dwell_left <= -DOOR_CLOSE_S:
			state = "drive"; _t = 0.0
		return -0.75
	_moved += absf(s.phys.position - _last_pos)
	_last_pos = s.phys.position
	_t -= dt
	if _t <= 0.0:
		_plan(s); _t = REPLAN_S; _moved = 0.0
	var v := s.phys.speed
	var a := _decel(s)
	var vt := _cap
	var curve := false
	var reason := ""
	var stop_d := INF
	for t in _targets:
		var d: float = float(t[0]) - _moved - float(t[2])
		var vat: float = float(t[1])
		var allowed := 0.0 if (vat <= 0.01 and d <= 0.3) else sqrt(vat * vat + 2.0 * a * maxf(d, 0.0))
		if vat <= 0.01: stop_d = minf(stop_d, d)
		if allowed < vt:
			vt = allowed; curve = true; reason = str(t[3])
	holding = reason if vt < 0.05 and v < 0.1 else ""
	# Arrivée à quai : portes, temps d'arrêt.
	if v < 0.05 and serve_stations and not station.is_empty() and station_key(station) != served \
			and s.net.station_contains(station, s.edge_id, s.offset):
		s.set_doors(true)
		if s.doors_open:
			state = "dwell"; served = station_key(station); stations_served += 1
			dwell_left = maxf(float(station.get("dwell_s", 20.0)), MIN_DWELL_S)
			return -0.75
	if holding == "buffer" and auto_reverse and s is FreeSession and s.phys.speed < 0.05:
		if (s as FreeSession).reverse() == "":
			reset(); return -0.75
	status = ("Arrêt devant signal" if reason == "signal" else ("Fin d'autorisation" if reason == "authority" else ("Arrêt : " + str(station.get("name", "")) if reason == "station" else "%d km/h" % roundi(vt * 3.6))))
	var err := vt - v
	var n := 0.0
	if vt < 0.05 and v < 0.25: n = -0.75
	elif err > 0.25: n = clampf(0.25 + err * 0.4, 0.2, 1.0)
	elif err > -0.05: n = clampf(err * 0.6, 0.0, 0.3)
	else:
		var ff := -a / maxf(s.phys.profile.service_brake_ms2, 0.1) if curve else 0.0
		n = clampf(ff + err * 0.9, -1.0, -0.05)
	if s.phys.wheel_slip: n = minf(n, 0.35)
	if not s.power_ok and n > 0.0: n = 0.0
	return n

## Alimentation : à l'arrêt, bascule vers un mode disponible sur la section (LAC / APS / batterie).
func _check_power(s: MissionSession) -> void:
	if s.power_ok or s.phys.speed > 0.1 or s.power_transition_left > 0.0: return
	var here := s.net.supplies_at(s.edge_id, s.offset)
	if s.events != null: here = s.events.filter_supplies(s, here)
	for mode in s.available_power_modes():
		if mode in here:
			s.set_power_mode(mode); return
	if "battery" in s.available_power_modes(): s.set_power_mode("battery")

func _plan(s: MissionSession) -> void:
	_targets.clear()
	_cap = maxf(s.speed_limit() - MARGIN_MS, 1.0)
	for r in restrictions(s, HORIZON_M):
		_targets.append([float(r[0]), maxf(float(r[1]) - MARGIN_MS, 0.6), float(r[2]), "limit"])
	station = {}
	if serve_stations:
		var st := station_ahead(s)
		if not st.is_empty():
			var d := stop_distance(s, st)
			if d != INF:
				station = st
				_targets.append([d, 0.0, 0.0, "station"])
	var sm := SignalModel.of(s.net)
	var v := s.phys.speed
	for it in sm.ahead(s, HORIZON_M):
		var i := int(it.i)
		var asp := sm.aspect(i)
		var dist := float(it.dist)
		if asp == "caution" and v * v / (2.0 * _decel(s)) > dist - STOP_MARGIN_M: continue
		if asp == "stop" or asp == "caution":
			_targets.append([dist, 0.0, STOP_MARGIN_M, "buffer" if str(sm.list[i].kind) == "buffer" else "signal"])
			break
	if s.interlocking != null and not s.interlocking.authority.is_empty():
		var au: Dictionary = s.interlocking.authority
		var d := s.dist_to_point(str(au.edge), float(au.offset), HORIZON_M + 300.0)
		if d != INF and d > -1.0:
			_targets.append([d, 0.0, 10.0 if bool(au.get("final", false)) else 2.0, "authority"])

## Restrictions devant le nez : [[distance, limite (m/s), marge d'application]].
static func restrictions(s: MissionSession, horizon: float) -> Array:
	var out: Array = []
	var net := s.net
	var e := s.edge_id; var r := s.direction; var off := s.offset
	var travelled := 0.0
	for it in 40:
		var L: float = net.graph.edges[e].length
		var info: Dictionary = net.edge_info[e]
		if it > 0: out.append([travelled, float(info.limit_ms), 2.0])
		for z in info.zones:
			var zs: float = float(z[0]) if r > 0 else float(z[1])
			var ze: float = float(z[1]) if r > 0 else float(z[0])
			var dend := travelled + (ze - off) * r
			if dend > 0.0: out.append([maxf(travelled + (zs - off) * r, 0.0), float(z[2]), 2.0])
		var remaining: float = (L - off) if r > 0 else off
		var j := net.junction_limit(e, r)
		if j < INF: out.append([travelled + remaining, j, 12.0])
		travelled += remaining
		if travelled >= horizon: break
		var nx := net.graph.next_step(e, r)
		if nx.is_empty(): break
		e = str(nx[0]); r = int(nx[1])
		off = 0.0 if r > 0 else float(net.graph.edges[e].length)
	if s.events != null:
		var ev := s.events.next_restriction(s, horizon)
		if not ev.is_empty(): out.append([float(ev.distance), float(ev.limit), 2.0])
	return out

## Prochaine station à desservir devant la rame (filtrée par ligne, station desservie exclue).
func station_ahead(s: MissionSession) -> Dictionary:
	s.next_station_ahead(1)   # construit l'index des stations par arête
	var net := s.net
	var e := s.edge_id; var r := s.direction; var off := s.offset
	var travelled := 0.0
	for _k in 24:
		var best: Dictionary = {}; var best_d := INF
		for st in s._st_index.get(e, []):
			if served == station_key(st): continue
			if line != "" and not _serves(st, line): continue
			var lo := INF; var hi := -INF
			var segs: Array = st.get("stop_area", {}).get("segments", [])
			if segs.is_empty(): lo = float(st.offset) - 3.0; hi = float(st.offset) + 3.0
			for seg in segs:
				if str(seg[0]) == e: lo = minf(lo, float(seg[1])); hi = maxf(hi, float(seg[2]))
			if lo == INF: continue
			var exit_d := (hi - off) if r > 0 else (off - lo)
			var entry_d := (lo - off) if r > 0 else (off - hi)
			if exit_d >= 0.5 and entry_d < best_d: best = st; best_d = entry_d
		if not best.is_empty(): return best
		var L: float = net.graph.edges[e].length
		travelled += (L - off) if r > 0 else off
		if travelled > HORIZON_M * 3.0: break
		var nx := net.graph.next_step(e, r)
		if nx.is_empty(): break
		e = str(nx[0]); r = int(nx[1])
		off = -1.0 if r > 0 else float(net.graph.edges[e].length) + 1.0
	return {}

static func _serves(st: Dictionary, line_: String) -> bool:
	for l in st.get("lines", []):
		if str(l).to_lower() == line_.to_lower(): return true
	return false

## Distance du nez au point d'arrêt de la station (sortie de quai moins STATION_EXIT_M).
static func stop_distance(s: MissionSession, st: Dictionary) -> float:
	var segs: Array = st.get("stop_area", {}).get("segments", [])
	if segs.is_empty(): return s.dist_to_point(str(st.edge), float(st.offset), HORIZON_M * 3.0)
	var lo := INF; var hi := -INF
	for seg in segs:
		for at in [seg[1], seg[2]]:
			var d := s.dist_to_point(str(seg[0]), float(at), HORIZON_M * 3.0)
			if d == INF: continue
			lo = minf(lo, d); hi = maxf(hi, d)
	if hi == -INF or hi < 0.5: return INF
	var stop := hi - STATION_EXIT_M
	if stop < lo + 1.0: stop = (lo + hi) * 0.5
	return maxf(stop, 0.0)
