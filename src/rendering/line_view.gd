class_name LineView
extends Node3D
## Rendu schématique : voie, quais, signaux, rame. Les arêtes sont dépliées le long de X
## (branches décalées en Z) ; la géométrie réelle viendra de l'import OSM.

var net: NetworkLoader
var edge_origin: Dictionary = {}   # id -> Vector3
var tram: Node3D
var cam: Camera3D
var signal_nodes: Array[MeshInstance3D] = []

func build(network: NetworkLoader, start_edge: String) -> void:
	net = network
	var placed := {}
	var q: Array[String] = [start_edge]
	edge_origin[start_edge] = Vector3.ZERO
	while not q.is_empty():
		var id: String = q.pop_front()
		if placed.has(id): continue
		placed[id] = true
		var e: TrackGraph.Edge = net.graph.edges[id]
		var o: Vector3 = edge_origin[id]
		var end := o + Vector3(e.length, 0, 0)
		var outs: Array = net.graph.out_edges.get(e.to_node, [])
		for k in outs.size():
			if not edge_origin.has(outs[k]):
				edge_origin[outs[k]] = end + Vector3(0, 0, 8.0 * k)
				q.append(outs[k])
	for id in edge_origin:
		_add_box(edge_origin[id] + Vector3(net.graph.edges[id].length * 0.5, -0.1, 0), Vector3(net.graph.edges[id].length, 0.1, 1.435), Color(0.35, 0.35, 0.38))
	for s in net.stations:
		var p: Vector3 = edge_origin[s.edge] + Vector3(float(s.offset), 0.0, 2.6)
		_add_box(p + Vector3(0, 0.4, 0), Vector3(40, 0.8, 2.5), Color(0.8, 0.75, 0.6))
	for s in net.signals:
		var p2: Vector3 = edge_origin[s.edge] + Vector3(float(s.offset), 2.0, -2.0)
		signal_nodes.append(_add_box(p2, Vector3(0.4, 1.0, 0.4), Color(0.1, 0.8, 0.2)))
	tram = Node3D.new()
	_add_box_to(tram, Vector3(0, 1.8, 0), Vector3(32, 3.6, 2.4), Color(0.85, 0.1, 0.15))
	add_child(tram)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 35, 0)
	add_child(sun)
	var ground := _add_box(Vector3(1500, -0.5, 0), Vector3(4000, 0.2, 400), Color(0.35, 0.5, 0.3))
	cam = Camera3D.new()
	cam.far = 800.0
	add_child(cam)

func _add_box(pos: Vector3, size: Vector3, col: Color) -> MeshInstance3D:
	var m := _add_box_to(self, pos, size, col)
	return m

func _add_box_to(parent: Node3D, pos: Vector3, size: Vector3, col: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new(); bm.size = size
	var mat := StandardMaterial3D.new(); mat.albedo_color = col
	bm.material = mat
	mi.mesh = bm; mi.position = pos
	parent.add_child(mi)
	return mi

func update_from(s: MissionSession, external: bool) -> void:
	var front: Vector3 = edge_origin[s.edge_id] + Vector3(s.offset, 0, 0)
	tram.position = front - Vector3(s.phys.profile.length_m * 0.5, 0, 0)
	if external:
		cam.position = tram.position + Vector3(-25, 12, 30)
		cam.look_at(tram.position + Vector3(10, 1, 0))
	else:  # vue cabine simplifiée
		cam.position = front + Vector3(-1.5, 3.0, 0)
		cam.look_at(front + Vector3(30, 2.5, 0))
	for i in signal_nodes.size():
		var c := Color(0.1, 0.8, 0.2) if s.signal_state[i] == "clear" else Color(0.9, 0.1, 0.1)
		(signal_nodes[i].mesh.material as StandardMaterial3D).albedo_color = c
