class_name TrackGraph
extends RefCounted
## Graphe de voies : arêtes orientées, parcourables dans les deux sens (dir = +1 dans le sens de l'arête,
## -1 à rebours), aiguillages par nœud et par côté, occupation par section.
## Chaque extrémité d'arête est rangée d'un côté du nœud (+1 : côté aval, où partent par défaut les arêtes
## sortantes ; -1 : côté amont). Une rame qui arrive par un côté repart par l'autre : pas de demi-tour
## géométrique. Les communications de voies ("raw") portent leurs côtés explicitement.

class Edge:
	var id: String
	var from_node: String
	var to_node: String
	var length: float
	var occupied_by: String = ""
	var from_side: int = 1     # côté du nœud de départ où se raccorde l'arête
	var to_side: int = -1      # côté du nœud d'arrivée

var edges: Dictionary = {}              # id -> Edge
var out_edges: Dictionary = {}          # node -> Array[String]
var sides: Dictionary = {}              # node -> {1: [[edge, dir]...], -1: [...]} : départs possibles par côté
var incident: Dictionary = {}           # node -> Array[String] (toutes les arêtes raccordées)
var switch_state: Dictionary = {}       # clé (nœud, côté) -> index de branche active ; côté +1 : clé = nœud
var spans: Dictionary = {}              # arête -> Vector2(a, b) : partie réellement couverte par l'occupant
										# (absente : toute l'arête est considérée occupée)
const FOUL_M := 20.0                    # zone d'aiguillage : rame à moins de FOUL_M du nœud => verrouillé

func add_edge(id: String, from_node: String, to_node: String, length: float, from_side: int = 1, to_side: int = -1) -> void:
	var e := Edge.new()
	e.id = id; e.from_node = from_node; e.to_node = to_node; e.length = length
	e.from_side = 1 if from_side >= 0 else -1
	e.to_side = 1 if to_side >= 0 else -1
	edges[id] = e
	if not out_edges.has(from_node):
		out_edges[from_node] = []
	out_edges[from_node].append(id)
	_attach(from_node, e.from_side, id, 1)
	_attach(to_node, e.to_side, id, -1)

func _attach(node: String, side: int, id: String, dir: int) -> void:
	if not sides.has(node):
		sides[node] = {1: [], -1: []}
		incident[node] = []
	sides[node][side].append([id, dir])
	if not id in incident[node]:
		incident[node].append(id)

static func skey(node: String, side: int) -> String:
	return node if side > 0 else node + "#-1"

## Départs possibles d'un nœud par un côté : [[arête, sens]...].
func choices(node: String, side: int) -> Array:
	return sides.get(node, {}).get(side, [])

## Nœud atteint en parcourant l'arête dans le sens dir, et côté par lequel on en repart.
func exit_of(edge_id: String, dir: int) -> Array:
	var e: Edge = edges[edge_id]
	return [e.to_node, -e.to_side] if dir > 0 else [e.from_node, -e.from_side]

## Arête suivante dans le sens de marche : [arête, sens] ou [] en fin de voie.
func next_step(edge_id: String, dir: int = 1) -> Array:
	var x := exit_of(edge_id, dir)
	var lst := choices(x[0], x[1])
	if lst.is_empty():
		return []
	return lst[int(switch_state.get(skey(x[0], x[1]), 0)) % lst.size()]

func next_edge(edge_id: String) -> String:
	var st := next_step(edge_id, 1)
	return "" if st.is_empty() else st[0]  # "" : fin de voie

func active_branch(node: String, side: int = 1) -> int:
	var n := choices(node, side).size()
	return 0 if n == 0 else int(switch_state.get(skey(node, side), 0)) % n

## Aiguillages manœuvrables : [[nœud, côté]...] (au moins deux branches d'un même côté).
func switches() -> Array:
	var out: Array = []
	for node in sides:
		for side in [1, -1]:
			if sides[node][side].size() > 1:
				out.append([node, side])
	return out

func switch_occupied(node: String) -> bool:
	for id in incident.get(node, []):
		var e: Edge = edges[id]
		if e.occupied_by == "":
			continue
		if not spans.has(id):
			return true
		var sp: Vector2 = spans[id]
		if e.from_node == node and sp.x < FOUL_M:
			return true
		if e.to_node == node and sp.y > e.length - FOUL_M:
			return true
	return false

## Partie d'arête couverte par son occupant (affine le verrouillage des aiguillages).
func set_span(edge_id: String, a: float, b: float) -> void:
	spans[edge_id] = Vector2(minf(a, b), maxf(a, b))

## Refuse la manœuvre si une section raccordée au nœud est occupée.
func throw_switch(node: String, branch: int, side: int = 1) -> bool:
	var lst := choices(node, side)
	if branch < 0 or branch >= lst.size():
		return false
	if switch_occupied(node):
		return false
	switch_state[skey(node, side)] = branch
	return true

func occupy(edge_id: String, train_id: String) -> bool:
	var e: Edge = edges[edge_id]
	if e.occupied_by != "" and e.occupied_by != train_id:
		return false
	e.occupied_by = train_id
	return true

func release(edge_id: String, train_id: String) -> void:
	if edges[edge_id].occupied_by == train_id:
		edges[edge_id].occupied_by = ""
		spans.erase(edge_id)

## Contrôle d'import : arêtes dont les nœuds sont isolés ou longueurs invalides.
func validate() -> PackedStringArray:
	var errs := PackedStringArray()
	for e in edges.values():
		if e.length <= 0.0:
			errs.append("longueur invalide: " + e.id)
	return errs
