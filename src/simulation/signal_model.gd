class_name SignalModel
extends RefCounted
## Signalisation lumineuse tramway déduite du graphe de voies (un modèle par réseau chargé) :
## - « switch » : signal de direction d'itinéraire avant chaque aiguillage pris en pointe
##   (barre oblique gauche/droite, barre verticale tout droit, barre horizontale arrêt) ;
## - « terminus » : carré d'entrée de terminus (aiguillage menant à une voie en impasse) ;
## - « block » : signal d'espacement (cantonnement) sur les longues sections sans aiguillage ;
## - « crossing » : feu R17 de carrefour en sortie de station (priorité tramway sur demande) ;
## - « buffer » : heurtoir (arrêt absolu) en fin de voie.
## Les signaux d'aiguillage et d'espacement sont placés exactement aux points où le poste
## (Interlocking) peut arrêter une autorisation de mouvement : leur aspect découle des
## réservations du graphe (itinéraire tracé = voie libre, sinon arrêt).
## Aspects : "go", "left", "right", "stop", "caution" (point : arrêt sauf impossibilité).

const SETBACK_M := 12.0          # identique à Interlocking.SIGNAL_SETBACK_M
const BLOCK_M := 380.0           # longueur maximale d'un canton sans signal
const TERMINUS_REACH_M := 450.0  # impasse atteinte depuis l'aiguillage : carré de terminus
const CROSS_REQUEST_M := 200.0   # demande de priorité au carrefour (détection du nez)
const CROSS_AFTER_M := 4.0       # feu placé juste après la sortie de quai
const CAUTION_S := 3.0

var _net: WeakRef
var net: NetworkLoader:
	get: return _net.get_ref()
var list: Array[Dictionary] = []   # {kind, edge, offset, dir, node, side, labels, station}
var by_edge: Dictionary = {}       # arête -> [indices]
var at_end: Dictionary = {}        # "arête|±" -> indice : points d'arrêt possibles du poste
var cross: Dictionary = {}         # indice -> {aspect, t, need, n}
var interlocked := false           # réseau géré par postes (mode mission) : fermé par défaut

static func of(n: NetworkLoader) -> SignalModel:
	if n.has_meta("signal_model"):
		var m = n.get_meta("signal_model")
		if m != null and m.net == n: return m
	var model := SignalModel.new(n)
	n.set_meta("signal_model", model)   # pas de cycle : le modèle ne garde qu'une référence faible
	return model

static func key(e: String, d: int) -> String:
	return e + ("|+" if d > 0 else "|-")

func _init(n: NetworkLoader) -> void:
	_net = weakref(n)
	_build()

func _add(s: Dictionary) -> int:
	var i := list.size()
	list.append(s)
	if not by_edge.has(s.edge): by_edge[s.edge] = []
	by_edge[s.edge].append(i)
	if bool(s.get("at_end", false)): at_end[key(s.edge, int(s.dir))] = i
	return i

func _end_offset(e: String, d: int) -> float:
	var L: float = net.graph.edges[e].length
	return clampf((L - SETBACK_M) if d > 0 else SETBACK_M, 0.0, L)

func _build() -> void:
	var g := net.graph
	# 1. Signaux de direction d'itinéraire (et carrés de terminus) avant les aiguillages en pointe.
	for sw in g.switches():
		var node := str(sw[0]); var side := int(sw[1])
		var labels := _branch_labels(node, side)
		var kind := "terminus" if _dead_end_near(node, side) else "switch"
		for br in g.choices(node, -side):
			var e := str(br[0]); var d := -int(br[1])
			if at_end.has(key(e, d)): continue
			_add({"kind": kind, "edge": e, "offset": _end_offset(e, d), "dir": d, "node": node, "side": side, "labels": labels, "at_end": true})
	# 2. Heurtoirs.
	for e in g.edges:
		for d in [1, -1]:
			var x := g.exit_of(e, d)
			if g.choices(x[0], x[1]).is_empty() and float(g.edges[e].length) > 8.0:
				var L: float = g.edges[e].length
				_add({"kind": "buffer", "edge": e, "offset": clampf(L - 2.0 if d > 0 else 2.0, 0.0, L), "dir": d})
	# 3. Espacement : chaînes de sections sans aiguillage, un signal tous les BLOCK_M au plus.
	var seen := {}
	for e in g.edges:
		for d in [1, -1]:
			if _chain_start(e, d): _walk_chain(e, d, seen)
	# 4. Feux de carrefour R17 en sortie de station (priorité tramway).
	for st in net.stations: _crossing_for(st)
	for c in net.meta.get("crossings", []):   # carrefours réels exportés par l'import (optionnel)
		var e := str(c.get("edge", ""))
		if not g.edges.has(e): continue
		for d in ([int(c.dir)] if c.has("dir") else _dirs_of(e)):
			_add_crossing(e, float(c.offset) - CROSS_AFTER_M * d, d, "")

## Directions de circulation admises sur une arête (sens normal connu, sinon les deux).
func _dirs_of(e: String) -> Array:
	var pref := int(net.edge_info[e].get("preferred_direction", 0))
	return [pref] if pref != 0 else [1, -1]

func _chain_start(e: String, d: int) -> bool:
	var g := net.graph
	var x := g.exit_of(e, -d)   # nœud d'entrée, côté par lequel on en repartirait à rebours
	var s := -int(x[1])
	if g.choices(x[0], s).size() != 1: return true
	return g.choices(x[0], x[1]).size() != 1

func _walk_chain(e: String, d: int, seen: Dictionary) -> void:
	var g := net.graph
	var acc := 0.0
	for _i in 200:
		if seen.has(key(e, d)): return
		seen[key(e, d)] = true
		acc += float(g.edges[e].length)
		var x := g.exit_of(e, d)
		var nexts := g.choices(x[0], x[1])
		if nexts.size() != 1: return
		var e2 := str(nexts[0][0]); var d2 := int(nexts[0][1])
		if _chain_start(e2, d2): return
		if acc >= BLOCK_M and not at_end.has(key(e, d)) and float(g.edges[e].length) >= SETBACK_M + 2.0:
			_add({"kind": "block", "edge": e, "offset": _end_offset(e, d), "dir": d, "at_end": true})
			acc = 0.0
		e = e2; d = d2

func _dead_end_near(node: String, side: int) -> bool:
	var g := net.graph
	for br in g.choices(node, side):
		var e := str(br[0]); var d := int(br[1]); var dist := 0.0
		for _i in 12:
			dist += float(g.edges[e].length)
			if dist > TERMINUS_REACH_M: break
			var x := g.exit_of(e, d)
			var ch := g.choices(x[0], x[1])
			if ch.is_empty(): return true
			if ch.size() > 1: break
			e = str(ch[0][0]); d = int(ch[0][1])
	return false

## Sens de chaque branche d'un aiguillage vu du conducteur : "left", "right" ou "go" (tout droit).
func _branch_labels(node: String, side: int) -> Array:
	var g := net.graph
	var heading := Vector2.ZERO
	for br in g.choices(node, -side):
		var id := str(br[0]); var dir := -int(br[1])
		var at: float = g.edges[id].length if dir > 0 else 0.0
		heading += net.point_on(id, at).get("dir", Vector2.ZERO) * dir
	var angles: Array = []
	for br in g.choices(node, side):
		var id := str(br[0]); var dir := int(br[1])
		var L: float = g.edges[id].length
		var at: float = minf(8.0, L) if dir > 0 else maxf(L - 8.0, 0.0)
		var p0: Vector2 = net.point_on(id, 0.0 if dir > 0 else L).get("p", Vector2.ZERO)
		var p1: Vector2 = net.point_on(id, at).get("p", Vector2.ZERO)
		var h: Vector2 = (p1 - p0) if (p1 - p0).length() > 0.5 else net.point_on(id, 0.0 if dir > 0 else L).get("dir", Vector2.ZERO) * dir
		angles.append(heading.angle_to(h) if heading.length() > 0.01 and h.length() > 0.01 else 0.0)
	# Classement par angle : la plus à gauche « left », la plus à droite « right » ; une branche
	# quasi rectiligne (< 6°) ou la médiane d'un triple aiguillage : « go ».
	var order: Array = range(angles.size())
	order.sort_custom(func(x, y): return float(angles[x]) < float(angles[y]))
	var out: Array = []
	out.resize(angles.size())
	var straight := -1
	for k in angles.size():
		if absf(float(angles[k])) < deg_to_rad(6.0) and (straight < 0 or absf(float(angles[k])) < absf(float(angles[straight]))): straight = k
	if straight < 0 and angles.size() >= 3: straight = int(order[1])
	for rank in order.size():
		var k := int(order[rank])
		if k == straight: out[k] = "go"
		elif straight >= 0: out[k] = "right" if float(angles[k]) > float(angles[straight]) else "left"
		else: out[k] = "left" if rank == 0 else "right"
	if angles.size() == 1: out[0] = "go"
	return out

func _crossing_for(st: Dictionary) -> void:
	var g := net.graph
	var segs: Array = st.get("stop_area", {}).get("segments", [])
	var e0 := str(st.edge)
	if not g.edges.has(e0): return
	for d in _dirs_of(e0):
		var e := e0; var r := int(d); var exit_off := float(st.offset)
		if not segs.is_empty():
			for _i in 6:
				var found := false
				for s in segs:
					if str(s[0]) == e:
						exit_off = maxf(float(s[1]), float(s[2])) if r > 0 else minf(float(s[1]), float(s[2]))
						found = true
				if not found: break
				var nx := g.next_step(e, r)
				if nx.is_empty(): break
				var inside := false
				for s in segs: inside = inside or str(s[0]) == str(nx[0])
				if not inside: break
				e = str(nx[0]); r = int(nx[1])
		_add_crossing(e, exit_off + CROSS_AFTER_M * r, r, str(st.get("name", "")))

func _add_crossing(e: String, off: float, d: int, station: String) -> void:
	var L: float = net.graph.edges[e].length
	off = clampf(off, 0.5, maxf(L - 0.5, 0.5))
	# Pas de doublon avec un signal d'aiguillage, d'espacement ou un autre feu tout proche.
	for i in by_edge.get(e, []):
		var s: Dictionary = list[i]
		if int(s.dir) == d and (float(s.offset) - off) * d > -6.0 and (float(s.offset) - off) * d < 30.0: return
	var i := _add({"kind": "crossing", "edge": e, "offset": off, "dir": d, "station": station})
	cross[i] = {"aspect": "stop", "t": 0.0, "need": 1.5 + float(posmod(hash(e) + i * 7, 45)) * 0.1, "n": 0}

# --- Aspects -----------------------------------------------------------------------------------

## Aspect courant d'un signal (vu par la rame qui s'en approche).
func aspect(i: int) -> String:
	var s: Dictionary = list[i]
	match str(s.kind):
		"buffer": return "stop"
		"crossing": return str(cross[i].aspect)
	var g := net.graph
	var e := str(s.edge)
	var nx := g.next_step(e, int(s.dir))
	if nx.is_empty(): return "stop"
	var e2 := str(nx[0])
	var occ: String = g.edges[e].occupied_by
	if interlocked:
		var owner := str(g.reserved.get(e, ""))
		if owner == "": return "stop"
		if str(g.reserved.get(e2, "")) != owner: return "stop"
		if s.has("node") and str(g.locks.get(TrackGraph.skey(str(s.node), int(s.side)), "")) != owner: return "stop"
	else:
		var occ2: String = g.edges[e2].occupied_by
		if occ2 != "" and occ2 != occ: return "stop"
	return branch_aspect(i)

## Direction indiquée par un signal d'aiguillage selon la position de l'aiguille.
func branch_aspect(i: int) -> String:
	var s: Dictionary = list[i]
	if not s.has("labels"): return "go"
	var labels: Array = s.labels
	if labels.is_empty(): return "go"
	return str(labels[net.graph.active_branch(str(s.node), int(s.side)) % labels.size()])

static func is_stop(a: String) -> bool:
	return a == "stop"

## Signaux devant une rame (dans son sens de marche, en suivant les aiguilles telles qu'elles
## sont positionnées) : [{i, dist}] triés par distance.
func ahead(s: MissionSession, horizon: float = 600.0) -> Array:
	var out: Array = []
	var g := net.graph
	var e := s.edge_id; var r := s.direction
	var base := -(s.offset if r > 0 else float(g.edges[e].length) - s.offset)   # distance du début d'arête au nez
	for _k in 40:
		var L: float = g.edges[e].length
		var here: Array = []
		for i in by_edge.get(e, []):
			var sg: Dictionary = list[i]
			if int(sg.dir) != r: continue
			var d := base + (float(sg.offset) if r > 0 else L - float(sg.offset))
			if d >= -0.5 and d <= horizon: here.append({"i": i, "dist": d})
		here.sort_custom(func(a, b): return float(a.dist) < float(b.dist))
		out.append_array(here)
		base += L
		if base > horizon: break
		var nx := g.next_step(e, r)
		if nx.is_empty(): break
		e = str(nx[0]); r = int(nx[1])
	return out

# --- Carrefours : priorité tramway -------------------------------------------------------------

## Met à jour les feux de carrefour à partir des rames présentes (demande de priorité à
## CROSS_REQUEST_M) et mémorise sur chaque rame la liste des signaux devant elle (sig_ahead).
func update(dt: float, trains: Array) -> void:
	var req := {}
	for t in trains:
		if t == null: continue
		var a := ahead(t, CROSS_REQUEST_M + 60.0)
		t.sig_ahead = a
		for it in a:
			if cross.has(int(it.i)) and float(it.dist) <= CROSS_REQUEST_M: req[int(it.i)] = true
	for i in cross:
		var c: Dictionary = cross[i]
		if req.has(i):
			if c.aspect == "caution": c.aspect = "go"; c.t = 0.0
			elif c.aspect == "stop":
				c.t += dt
				if c.t >= float(c.need): c.aspect = "go"; c.t = 0.0
		else:
			match str(c.aspect):
				"go": c.aspect = "caution"; c.t = 0.0
				"caution":
					c.t += dt
					if c.t >= CAUTION_S:
						c.aspect = "stop"; c.t = 0.0; c.n += 1
						c.need = 1.5 + float(posmod(int(c.n) * 13 + i * 7, 45)) * 0.1
				_: c.t = 0.0

# --- Textes pour l'interface ------------------------------------------------------------------

static func kind_label(kind: String) -> String:
	return {"switch": "Signal d'aiguillage", "terminus": "Carré · entrée terminus", "block": "Signal d'espacement",
		"crossing": "Feu de carrefour R17", "buffer": "Heurtoir", "authority": "Fin d'autorisation"}.get(kind, kind)

static func aspect_label(a: String, kind: String = "") -> String:
	if kind == "buffer": return "Arrêt absolu"
	match a:
		"go": return "Voie libre" if kind != "switch" and kind != "terminus" else "Tout droit"
		"left": return "Direction à gauche"
		"right": return "Direction à droite"
		"caution": return "Arrêt sauf impossibilité"
	return "Arrêt"
