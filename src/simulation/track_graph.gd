class_name TrackGraph
extends RefCounted
## Graphe de voies : arêtes orientées, aiguillages, occupation par section.

class Edge:
	var id: String
	var from_node: String
	var to_node: String
	var length: float
	var occupied_by: String = ""

var edges: Dictionary = {}              # id -> Edge
var out_edges: Dictionary = {}          # node -> Array[String]
var switch_state: Dictionary = {}       # node -> index de branche active

func add_edge(id: String, from_node: String, to_node: String, length: float) -> void:
	var e := Edge.new()
	e.id = id; e.from_node = from_node; e.to_node = to_node; e.length = length
	edges[id] = e
	if not out_edges.has(from_node):
		out_edges[from_node] = []
	out_edges[from_node].append(id)

func next_edge(edge_id: String) -> String:
	var e: Edge = edges[edge_id]
	var outs: Array = out_edges.get(e.to_node, [])
	if outs.is_empty():
		return ""  # fin de voie
	return outs[switch_state.get(e.to_node, 0) % outs.size()]

## Refuse la manœuvre si une section sortante ou la section entrante est occupée.
func throw_switch(node: String, branch: int) -> bool:
	var outs: Array = out_edges.get(node, [])
	if branch < 0 or branch >= outs.size():
		return false
	for id in outs:
		if edges[id].occupied_by != "":
			return false
	for e in edges.values():
		if e.to_node == node and e.occupied_by != "":
			return false
	switch_state[node] = branch
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

## Contrôle d'import : arêtes dont les nœuds sont isolés ou longueurs invalides.
func validate() -> PackedStringArray:
	var errs := PackedStringArray()
	for e in edges.values():
		if e.length <= 0.0:
			errs.append("longueur invalide: " + e.id)
	return errs
