class_name Interlocking
extends RefCounted
## Poste d'aiguillage automatique du mode mission. Calcule l'itinéraire de la mission sur le
## réseau complet (sans rebroussement hors des points prévus), puis, au fil de la marche :
## réserve les sections devant la rame, positionne et verrouille les aiguillages, tient des
## signaux cohérents (voie libre sur l'itinéraire tracé, arrêt à la fin d'autorisation) et
## libère sections et aiguillages après le passage de la queue. Chaque rame possède son poste
## (propriétaire = identifiant de rame) : plusieurs rames peuvent partager le même graphe.

const RESERVE_M := 700.0        # itinéraire tracé devant le nez
const SIGNAL_SETBACK_M := 12.0  # signal placé avant le nœud protégé
const OVERLAP_M := 12.0         # dépassement admis au-delà du point d'arrêt final d'une étape
const WRONG_WAY_FACTOR := 40.0  # contre-sens sur voie banalisée de fait : très pénalisé
const SERVICE_FACTOR := 6.0     # voies de service (dépôt, garage) hors missions de dépôt
const REVERSE_WINDOW := Vector2(-12.0, 6.0) # position du nez autour du point de retournement

var net: NetworkLoader
var owner := "T1"
var closed: Dictionary = {}     # arêtes fermées (travaux, inondation)
var strict := false             # contre-sens interdit (déviation)
var allow_service := false
var waypoints: Array = []       # [{edge, offset, dir, reverse}]
var next_wp := 0
var path: Array = []            # étape courante : [[arête, sens]...]
var leg_end: Dictionary = {}
var pos := 0                    # indice du nez dans path
var reserved_to := -1
var released_to := 0
var locked: Dictionary = {}     # indice de transition -> [nœud, côté]
var authority: Dictionary = {}  # {edge, offset, final} : fin d'autorisation de mouvement
var error := ""
var legs_done := 0

func _init(network: NetworkLoader, owner_id: String = "T1") -> void:
	net = network
	owner = owner_id

# --- Calcul d'itinéraire -------------------------------------------------------------------

static func _key(e: String, d: int) -> String:
	return e + ("|+" if d > 0 else "|-")

static func edge_cost(network: NetworkLoader, e: String, d: int, closed_: Dictionary, service_ok: bool, strict_: bool) -> float:
	if closed_.has(e): return INF
	var info: Dictionary = network.edge_info[e]
	var c := float(network.graph.edges[e].length)
	var pref := int(info.get("preferred_direction", 0))
	if pref != 0 and pref != d:
		if strict_: return INF
		c *= WRONG_WAY_FACTOR
	if str(info.get("service", "")) != "" and not service_ok: c *= SERVICE_FACTOR
	return maxf(c, 0.1)

## Plus court itinéraire sans rebroussement d'un point de voie (nez, sens) à un autre.
## to_dir = 0 : sens indifférent. Retourne {path, cost, length} ou {}.
static func find_path(network: NetworkLoader, from_edge: String, from_offset: float, from_dir: int, to_edge: String, to_offset: float, to_dir: int,
		closed_: Dictionary = {}, service_ok: bool = false, strict_: bool = false, max_length: float = 30000.0) -> Dictionary:
	var g := network.graph
	if from_edge == to_edge and (to_dir == 0 or to_dir == from_dir) and (to_offset - from_offset) * from_dir >= -0.5:
		var dd := absf(to_offset - from_offset)
		return {"path": [[from_edge, from_dir]], "cost": dd, "length": dd}
	var L0: float = g.edges[from_edge].length
	var first := L0 - from_offset if from_dir > 0 else from_offset
	var heap := _Heap.new()
	var best := {}      # clé -> coût d'entrée
	var prev := {}      # clé -> clé parente
	var real := {}      # clé -> longueur réelle à l'entrée
	var start := "@S"
	_expand(network, from_edge, from_dir, first, first, start, heap, best, prev, real, closed_, service_ok, strict_)
	while not heap.empty():
		var it: Array = heap.pop()
		var c: float = it[0]; var k: String = it[1]
		if k.begins_with("@T"):
			var parent := k.substr(2)
			var out: Array = []
			var cur := parent
			while cur != start:
				var parts := cur.split("|")
				out.push_front([parts[0], 1 if parts[1] == "+" else -1])
				cur = prev[cur]
			out.push_front([from_edge, from_dir])
			return {"path": out, "cost": c, "length": float(it[2])}
		if c > best.get(k, INF) + 0.001: continue
		var e := str(it[2]); var d := int(it[3])
		var r: float = real[k]
		if r > max_length: continue
		if e == to_edge and (to_dir == 0 or to_dir == d):
			var part: float = to_offset if d > 0 else g.edges[e].length - to_offset
			var factor: float = edge_cost(network, e, d, closed_, service_ok, strict_) / maxf(g.edges[e].length, 0.1)
			heap.push([c + part * factor, "@T" + k, r + part])
		var step := edge_cost(network, e, d, closed_, service_ok, strict_)
		if step == INF: continue
		_expand(network, e, d, c + step, r + g.edges[e].length, k, heap, best, prev, real, closed_, service_ok, strict_)
	return {}

static func _expand(network: NetworkLoader, e: String, d: int, c: float, r: float, parent: String, heap: _Heap, best: Dictionary, prev: Dictionary, real: Dictionary,
		closed_: Dictionary, service_ok: bool, strict_: bool) -> void:
	var x := network.graph.exit_of(e, d)
	for ch in network.graph.choices(x[0], x[1]):
		var e2 := str(ch[0]); var d2 := int(ch[1])
		if edge_cost(network, e2, d2, closed_, service_ok, strict_) == INF: continue
		var k2 := _key(e2, d2)
		if c < best.get(k2, INF):
			best[k2] = c; prev[k2] = parent; real[k2] = r
			heap.push([c, k2, e2, d2])

## Itinéraire passant successivement par les points donnés : {path, length} ou {}.
static func plan_route(network: NetworkLoader, start: Dictionary, points: Array, closed_: Dictionary = {}, service_ok: bool = false, strict_: bool = false) -> Dictionary:
	var acc: Array = [[str(start.edge), int(start.dir)]]
	var e := str(start.edge); var o := float(start.offset); var d := int(start.dir)
	var total := 0.0
	for p in points:
		var r := find_path(network, e, o, d, str(p.edge), float(p.offset), int(p.get("dir", 0)), closed_, service_ok, strict_)
		if r.is_empty(): return {}
		for i in range(1, r.path.size()): acc.append(r.path[i])
		total += float(r.length)
		e = str(p.edge); o = float(p.offset); d = int(acc[-1][1])
	return {"path": acc, "length": total}

## Recherche d'un point de retournement (rame entière dégagée au-delà d'un nœud) depuis
## `from`, permettant de rejoindre `target` après changement de cabine.
## Retourne {point: {edge, offset, dir, reverse}, length} ou {}.
static func find_reversal(network: NetworkLoader, from: Dictionary, target: Dictionary, train_len: float, closed_: Dictionary = {}, max_back: float = 2500.0, service_ok: bool = false) -> Dictionary:
	var g := network.graph
	var best: Dictionary = {}
	var best_cost := INF
	var first_remaining: float = (g.edges[from.edge].length - float(from.offset)) if int(from.dir) > 0 else float(from.offset)
	var seen := {}
	var queue: Array = []
	var x := g.exit_of(str(from.edge), int(from.dir))
	for ch in g.choices(x[0], x[1]): queue.append([str(ch[0]), int(ch[1]), first_remaining])
	var n := 0
	while not queue.is_empty() and n < 40:
		var it: Array = queue.pop_front()
		var e: String = it[0]; var d: int = it[1]; var dist: float = it[2]
		if seen.has(_key(e, d)) or dist > 1500.0 or closed_.has(e): continue
		seen[_key(e, d)] = true; n += 1
		var L: float = g.edges[e].length
		if L >= train_len + 30.0:
			var entry := 0.0 if d > 0 else L
			var nose := entry + (train_len + 16.0) * d
			var tail := entry + 16.0 * d
			var back := find_path(network, e, tail, -d, str(target.edge), float(target.offset), int(target.get("dir", 0)), closed_, service_ok, false, max_back)
			if not back.is_empty() and float(back.length) <= max_back:
				var cost := dist + train_len + 16.0 + float(back.cost)
				if cost < best_cost:
					best_cost = cost
					best = {"point": {"edge": e, "offset": nose, "dir": d, "reverse": true}, "length": dist + train_len + 16.0 + float(back.length)}
		var y := g.exit_of(e, d)
		for ch in g.choices(y[0], y[1]): queue.append([str(ch[0]), int(ch[1]), dist + L])
	return best

# --- Exploitation ----------------------------------------------------------------------------

## Configure les points de passage et trace la première étape.
func setup(s: MissionSession, points: Array) -> bool:
	waypoints = points
	next_wp = 0
	return plan_leg(s)

## Étape suivante : jusqu'au prochain point de retournement (inclus) ou jusqu'à la fin.
func plan_leg(s: MissionSession) -> bool:
	release_all()
	var leg: Array = []
	while next_wp < waypoints.size():
		leg.append(waypoints[next_wp]); next_wp += 1
		if bool(leg[-1].get("reverse", false)): break
	if leg.is_empty():
		path = [[s.edge_id, s.direction]]; leg_end = {}
	else:
		var r := plan_route(net, {"edge": s.edge_id, "offset": s.offset, "dir": s.direction}, leg, closed, allow_service, strict)
		if r.is_empty():
			error = "Aucun itinéraire disponible"
			path = [[s.edge_id, s.direction]]; leg_end = {}
			return false
		path = r.path; leg_end = leg[-1]
	pos = 0; reserved_to = -1; released_to = 0; locked.clear(); error = ""
	update(s)
	return true

func awaiting_reverse() -> bool:
	return bool(leg_end.get("reverse", false))

## Vrai quand la rame est immobilisée au point de retournement, queue dégagée de l'aiguillage.
func can_reverse(s: MissionSession) -> bool:
	if not awaiting_reverse() or s.phys.speed > 0.1: return false
	var d := s.dist_to_point(str(leg_end.edge), float(leg_end.offset), 200.0)
	return d >= REVERSE_WINDOW.x and d <= REVERSE_WINDOW.y

## Appelé après un changement de cabine autorisé : trace l'étape suivante.
func after_reverse(s: MissionSession) -> bool:
	legs_done += 1
	return plan_leg(s)

func remaining_waypoints() -> int:
	return waypoints.size() - next_wp

## Mise à jour à chaque pas : suivi du nez, tracé devant, libération derrière.
func update(s: MissionSession) -> void:
	if path.is_empty(): return
	var found := -1
	for j in range(maxi(pos - 2, 0), mini(pos + 12, path.size())):
		if str(path[j][0]) == s.edge_id and int(path[j][1]) == s.direction:
			found = j
			if j >= pos: break
	if found < 0:
		error = "Sortie d'itinéraire"
		return
	pos = found
	_reserve(s)
	_release_behind(s)

func _reserve(s: MissionSession) -> void:
	var g := net.graph
	var ahead := s._ahead_on_edge()
	var i := pos
	authority = {}
	while true:
		var e := str(path[i][0]); var d := int(path[i][1])
		if not g.reserve(e, owner):
			_set_authority_end(i - 1, false); i -= 1; break
		if i == path.size() - 1:
			if leg_end.is_empty():
				authority = {}
			else:
				var L: float = g.edges[e].length
				authority = {"edge": e, "offset": clampf(float(leg_end.offset) + OVERLAP_M * d, 0.0, L), "final": true, "dir": d}
			break
		if ahead > RESERVE_M:
			_set_authority_end(i, false); break
		var x := g.exit_of(e, d)
		var branches := g.choices(x[0], x[1])
		var b := -1
		for k in branches.size():
			if str(branches[k][0]) == str(path[i + 1][0]) and int(branches[k][1]) == int(path[i + 1][1]): b = k
		if b < 0 or not g.lock_switch(str(x[0]), int(x[1]), b, owner):
			_set_authority_end(i, false); break
		# Aiguillage pris en talon : positionné et verrouillé lui aussi, côté d'arrivée.
		var back := g.choices(x[0], -int(x[1]))
		var tb := -1
		for k in back.size():
			if str(back[k][0]) == e and int(back[k][1]) == -d: tb = k
		if tb >= 0 and not g.lock_switch(str(x[0]), -int(x[1]), tb, owner):
			g.unlock_switch(str(x[0]), int(x[1]), owner)
			_set_authority_end(i, false); break
		locked[i] = [str(x[0]), int(x[1])]
		i += 1
		ahead += g.edges[str(path[i][0])].length
	reserved_to = maxi(reserved_to, i)

func _set_authority_end(i: int, final_: bool) -> void:
	if i < 0: i = 0
	var e := str(path[i][0]); var d := int(path[i][1])
	var L: float = net.graph.edges[e].length
	authority = {"edge": e, "offset": clampf((L - SIGNAL_SETBACK_M) if d > 0 else SIGNAL_SETBACK_M, 0.0, L), "final": final_, "dir": d}

func _release_behind(s: MissionSession) -> void:
	var tail_edge := str(s.route[0]) if not s.route.is_empty() else s.edge_id
	var t := pos
	while t > 0 and str(path[t][0]) != tail_edge: t -= 1
	var keep := {}
	for k in range(t, mini(reserved_to + 1, path.size())): keep[str(path[k][0])] = true
	for k in range(released_to, t):
		if not keep.has(str(path[k][0])): net.graph.unreserve(str(path[k][0]), owner)
		if locked.has(k):
			_unlock(k)
			locked.erase(k)
	released_to = maxi(released_to, t)

func _unlock(k: int) -> void:
	net.graph.unlock_switch(str(locked[k][0]), int(locked[k][1]), owner)
	net.graph.unlock_switch(str(locked[k][0]), -int(locked[k][1]), owner)

## Aiguillages actuellement verrouillés par ce poste : [[nœud, côté]...].
func locked_switch_list() -> Array:
	var out: Array = []
	for key in net.graph.locks:
		if str(net.graph.locks[key]) == owner: out.append(key)
	return out

func release_all() -> void:
	for k in locked: _unlock(k)
	locked.clear()
	for e in net.graph.reserved.keys():
		net.graph.unreserve(str(e), owner)

## Vrai si le nez a franchi la fin d'autorisation (signal fermé).
func authority_passed(s: MissionSession) -> bool:
	if authority.is_empty(): return false
	var d := s.dist_to_point(str(authority.edge), float(authority.offset), 200.0)
	return d < -0.05 and d > -60.0

## Signaux de l'itinéraire devant la rame : [{distance, state, edge, offset, node}].
func signals_ahead(s: MissionSession, horizon: float = 1500.0) -> Array:
	var out: Array = []
	for i in locked:
		if i < pos: continue
		var e := str(path[i][0]); var d := int(path[i][1])
		var node := str(locked[i][0])
		if net.graph.choices(node, int(locked[i][1])).size() < 2: continue
		var L: float = net.graph.edges[e].length
		var at := clampf((L - SIGNAL_SETBACK_M) if d > 0 else SIGNAL_SETBACK_M, 0.0, L)
		var dist := s.dist_to_point(e, at, horizon)
		if dist >= 0.0 and dist <= horizon: out.append({"distance": dist, "state": "clear", "edge": e, "offset": at, "node": node})
	if not authority.is_empty():
		var da := s.dist_to_point(str(authority.edge), float(authority.offset), horizon)
		if da >= -0.05 and da <= horizon:
			out.append({"distance": da, "state": "stop", "edge": str(authority.edge), "offset": float(authority.offset), "final": bool(authority.get("final", false))})
	out.sort_custom(func(a, b): return float(a.distance) < float(b.distance))
	return out

## Longueur restante de l'étape (m), du nez au point final.
func remaining_length(s: MissionSession) -> float:
	if leg_end.is_empty(): return 0.0
	return maxf(s.dist_to_point(str(leg_end.edge), float(leg_end.offset), 30000.0), 0.0)

## Tas binaire minimal (coût en tête de chaque élément).
class _Heap:
	var a: Array = []
	func empty() -> bool: return a.is_empty()
	func push(it: Array) -> void:
		a.append(it)
		var i := a.size() - 1
		while i > 0:
			var p := (i - 1) >> 1
			if float(a[p][0]) <= float(it[0]): break
			a[i] = a[p]; i = p
		a[i] = it
	func pop() -> Array:
		var top: Array = a[0]
		var last: Array = a.pop_back()
		if a.is_empty(): return top
		var i := 0; var n := a.size()
		while true:
			var l := 2 * i + 1
			if l >= n: break
			var r := l + 1
			var c := r if r < n and float(a[r][0]) < float(a[l][0]) else l
			if float(a[c][0]) >= float(last[0]): break
			a[i] = a[c]; i = c
		a[i] = last
		return top
