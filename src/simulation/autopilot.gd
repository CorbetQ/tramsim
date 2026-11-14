class_name Autopilot
extends RefCounted
## Conduite automatique d'une rame (pilote automatique du mode libre, conducteurs des rames IA).
## Courbes de freinage vers chaque contrainte devant la rame : limites de vitesse (zones,
## sections, raccords), arrêt en station (portes ouvertes puis fermées), signaux fermés
## (SignalModel), fin d'autorisation du poste (Interlocking) et heurtoirs. La rame suit les
## aiguillages tels qu'ils sont positionnés (mode libre : itinéraire choisi au hasard, aiguilles
## positionnées par le pilote). Conduite « humaine » : le manipulateur glisse d'un cran à la fois
## (temps de maintien par cran, passage par le neutre avant toute inversion traction / freinage),
## démarrage progressif, marche sur l'erre, freinage anticipé doux, arrêt précis.
## Bascule APS / LAC à quai selon la section suivante. Renvoie le cran (-1..1, pas de 0,25).

const MARGIN_MS := 0.8          # marge sous chaque limite (≈ 3 km/h)
const STOP_MARGIN_M := 3.0      # arrêt avant un signal fermé
const STATION_EXIT_M := 4.0     # nez arrêté à 4 m de la sortie de quai
const REPLAN_S := 0.15
const HORIZON_M := 520.0
const MIN_DWELL_S := 12.0
const DOOR_CLOSE_S := 2.0
const CRAN_HOLD_S := 0.4        # temps minimal entre deux crans
const REVERSE_HOLD_S := 1.0     # neutre maintenu avant inversion traction <-> freinage, retour de sens
const URGENT_HOLD_S := 0.15
const REACTION_S := 2.0         # anticipation : distance parcourue pendant l'application du frein

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
var random_routes := false      # mode libre : direction tirée au hasard à chaque aiguillage
var rng := RandomNumberGenerator.new()
var cran := -3                  # position du manipulateur : -4 (freinage maximal) .. 4 (T4)
var _since := 0.0               # temps depuis le dernier changement de cran
var _last_step := 0             # sens du dernier déplacement (+1 / -1)
var _decided: Dictionary = {}   # aiguillages déjà choisis devant la rame
var power_switches: Array = []  # [{mode, speed, in_station}] : commutations faites (tests)
var _targets: Array = []        # [distance au plan, vitesse visée, marge, raison]
var _cap := 0.0
var _moved := 0.0
var _last_pos := 0.0
var _t := 0.0

func reset() -> void:
	state = "drive"; served = ""; _t = 0.0; _targets.clear(); holding = ""; station = {}; _decided.clear()

static func station_key(st: Dictionary) -> String:
	return str(st.get("name", "")) + "@" + str(st.get("edge", ""))

func _decel(s: MissionSession) -> float:
	var p := s.phys
	var a := minf(p.profile.service_brake_ms2, p.effective_adhesion() * TrainPhysics.G * 0.85) * 0.55
	# En descente, la pente réduit la décélération disponible.
	var slope := s.net.grade_at(s.edge_id, s.offset) * s.direction
	return maxf(a + TrainPhysics.G * minf(slope, 0.0), 0.2)

## Cran de manipulateur pour ce pas ; gère aussi l'ouverture et la fermeture des portes.
func control(s: MissionSession, dt: float) -> float:
	if s.blocked or s.finished: return -1.0
	_check_power(s)
	_since += dt; _pending_t += dt
	if state == "dwell":
		dwell_left -= dt
		holding = "station"
		status = "Arrêt : " + str(station.get("name", ""))
		_platform_power(s)
		if dwell_left <= 0.0 and s.doors_open and s.power_transition_left <= 0.0: s.set_doors(false)
		if dwell_left <= -DOOR_CLOSE_S and not s.doors_open:
			state = "drive"; _t = 0.0
		return _move_lever(-3, true)
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
	var a_need := 0.0             # décélération nécessaire vers la contrainte la plus contraignante
	var lag := s.phys.speed * REACTION_S * clampf((s.phys.speed - 2.0) / 4.0, 0.0, 1.0)   # pas d'anticipation en approche lente
	for t in _targets:
		var d: float = float(t[0]) - _moved - float(t[2])
		var vat: float = float(t[1])
		var allowed := 0.0 if (vat <= 0.01 and d <= 0.3) else sqrt(vat * vat + 2.0 * a * maxf(d - lag, 0.0))
		if vat <= 0.01: stop_d = minf(stop_d, d)
		if s.phys.speed > vat: a_need = maxf(a_need, (s.phys.speed * s.phys.speed - vat * vat) / (2.0 * maxf(d - lag * 0.5, 0.5)))
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
			return _move_lever(-3, true)
	if holding == "buffer" and auto_reverse and s is FreeSession and s.phys.speed < 0.05:
		if (s as FreeSession).reverse() == "":
			reset(); return _move_lever(-3, true)
	status = ("Arrêt devant signal" if reason == "signal" else ("Fin d'autorisation" if reason == "authority" else ("Arrêt : " + str(station.get("name", "")) if reason == "station" else "%d km/h" % roundi(vt * 3.6))))
	return _move_lever(_want(s, v, vt, curve, a_need), false, a_need)

## Cran voulu (avant glissement du manipulateur), avec hystérésis.
func _want(s: MissionSession, v: float, vt: float, curve: bool, a_need: float) -> int:
	var B := maxf(s.phys.profile.service_brake_ms2, 0.1)
	var err := vt - v
	if vt < 0.05 and v < 0.3: return -3                      # arrêt précis, maintien
	if vt < 0.05: return -4                                   # point d'arrêt atteint : freinage maximal
	if not s.power_ok and err > 0.0: return 0
	var braking := cran < 0
	# Freinage : niveau selon la décélération nécessaire, tenu tant que la courbe l'exige.
	if err < (-0.1 if braking else -0.35) or (curve and a_need > (0.12 if braking else 0.22) * B and v > 0.5):
		var r := a_need / B * 3.0 + maxf(-err - 0.2, 0.0) * 0.6
		var lvl := clampi(ceili(r - (0.25 if braking else 0.0)), 1, 3)
		if r > 3.2 and cran <= -3: lvl = 4                    # freinage maximal de service (pente, retard)
		if braking and absi(lvl + cran) == 1 and absf(r - float(-cran)) < 0.6: lvl = -cran   # hystérésis de niveau
		return -lvl
	# Traction : démarrage progressif, niveau selon l'écart, réduit avant la vitesse visée.
	var traction := cran > 0
	if err > (0.35 if v < 1.0 else (0.25 if traction else 1.0)):
		var w := clampi(ceili((err - 0.3) / 1.6), 1, 4)
		if traction and absi(w - cran) == 1 and err > 0.6: w = cran                       # hystérésis
		if s.phys.wheel_slip: w = mini(w, 1)
		return w
	return 0                                                  # marche sur l'erre

## Glissement du manipulateur vers `want` : un cran à la fois (CRAN_HOLD_S), consigne stable
## DEBOUNCE_S avant d'être suivie, jamais d'aller-retour rapide (REVERSE_HOLD_S), neutre tenu
## REVERSE_HOLD_S avant d'inverser traction / freinage. Serrage rapide côté freinage seulement
## quand on freine déjà (urgence, maintien à l'arrêt).
const DEBOUNCE_S := 0.6
var _last_sign := 0
var _pending := -99
var _pending_t := 0.0
func _move_lever(want: int, force: bool, a_need: float = 0.0) -> float:
	var urgent := force or a_need > 0.55 or want <= -4
	if want != _pending:
		_pending = want; _pending_t = 0.0
	if want != cran and not urgent and _pending_t < DEBOUNCE_S and not (want < cran and cran > 0 and want <= 0):
		return cran * 0.25
	if want != cran:
		var step := signi(want - cran)
		var nxt := cran + step
		var hold := CRAN_HOLD_S
		if _last_step != 0 and step != _last_step: hold = REVERSE_HOLD_S
		if cran == 0 and _last_sign != 0 and signi(nxt) != _last_sign: hold = maxf(hold, REVERSE_HOLD_S)
		elif urgent and step < 0 and cran < 0: hold = URGENT_HOLD_S
		elif urgent and step < 0 and cran > 0: hold = CRAN_HOLD_S * 0.5
		if _since >= hold:
			cran = nxt; _since = 0.0; _last_step = step
			if cran != 0: _last_sign = signi(cran)
	return cran * 0.25

## À quai : bascule vers l'alimentation de la section suivante (APS / LAC) si la station la permet.
func _platform_power(s: MissionSession) -> void:
	if s.phys.speed > 0.1 or s.power_transition_left > 0.0: return
	var need := supply_ahead(s, 60.0)
	if need == "" or need == s.power_mode or not need in s.available_power_modes(): return
	var here := s.net.supplies_at(s.edge_id, s.offset)
	if not need in here: return
	if s.set_power_mode(need) == "":
		power_switches.append({"mode": need, "speed": s.phys.speed, "in_station": s.net.station_contains(station, s.edge_id, s.offset) if not station.is_empty() else false})
		dwell_left = maxf(dwell_left, MissionSession.POWER_SWITCH_SECONDS + 0.5)

## Mode d'alimentation de la voie `dist` mètres devant le nez (aiguilles telles que positionnées).
static func supply_ahead(s: MissionSession, dist: float) -> String:
	var e := s.edge_id; var r := s.direction; var off := s.offset
	var left := dist
	for _k in 20:
		var L: float = s.net.graph.edges[e].length
		var room: float = (L - off) if r > 0 else off
		if room >= left: return s.net.supply_at(e, off + left * r)
		left -= room
		var nx := s.net.graph.next_step(e, r)
		if nx.is_empty(): return s.net.supply_at(e, L if r > 0 else 0.0)
		e = str(nx[0]); r = int(nx[1]); off = 0.0 if r > 0 else float(s.net.graph.edges[e].length)
	return ""

## Mode libre : direction tirée au hasard à l'approche de chaque aiguillage (aiguille positionnée
## par le pilote) ; contre-sens et voies de service peu probables, impasse possible (retournement).
func _choose_routes(s: MissionSession) -> void:
	if not random_routes or not (s is FreeSession): return
	var sm := SignalModel.of(s.net)
	var g := s.net.graph
	var reach := maxf(160.0, s.phys.speed * s.phys.speed / (2.0 * _decel(s)) + 80.0)
	var seen := {}
	for it in sm.ahead(s, reach):
		var sg: Dictionary = sm.list[int(it.i)]
		if not sg.has("node"): continue
		var key := TrackGraph.skey(str(sg.node), int(sg.side))
		seen[key] = true
		if _decided.has(key) or float(it.dist) < 2.0: continue
		var branches := g.choices(str(sg.node), int(sg.side))
		var weights: Array = []; var total := 0.0
		for br in branches:
			var info: Dictionary = s.net.edge_info[str(br[0])]
			var pref := int(info.get("preferred_direction", 0))
			var w := 1.0
			if pref != 0 and pref != int(br[1]): w *= 0.12
			if str(info.get("service", "")) != "": w *= 0.3
			var sup := str(info.get("supply", ""))
			if sup == "none" or (sup != "" and not sup in s.available_power_modes() and not "battery" in s.available_power_modes()): w *= 0.001
			weights.append(w); total += w
		var pick := rng.randf() * total
		var b := 0
		for k in weights.size():
			pick -= float(weights[k])
			if pick <= 0.0: b = k; break
		(s as FreeSession).select_branch(str(sg.node), b, int(sg.side))
		_decided[key] = true
	for k in _decided.keys():
		if not seen.has(k): _decided.erase(k)

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
	_choose_routes(s)
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
