class_name NormalRouting
extends RefCounted
## Réglage initial seulement : préserver la branche normale, pas la branche
## géométriquement la plus à droite. Les manœuvres du joueur restent libres.
static func initialize(net: NetworkLoader) -> void:
	if net.meta.get("geometry_kind", "") != "physical": return
	for sw in net.graph.switches():
		var node := str(sw[0]); var side := int(sw[1])
		var key := TrackGraph.skey(node, side)
		if net.graph.switch_state.has(key): continue
		var branches := net.graph.choices(node, side)
		var incoming: Array[Vector2] = []
		for branch in net.graph.choices(node, -side):
			var id := str(branch[0]); var dir := -int(branch[1]); var info: Dictionary = net.edge_info[id]
			if info.service != "": continue
			var normal := int(info.get("preferred_direction", 0))
			if normal != 0 and normal != dir: continue
			var at: float = net.graph.edges[id].length if dir > 0 else 0.0
			incoming.append(net.point_on(id, at).dir * dir)
		var best := 0; var best_score := INF; var best_id := ""
		for i in branches.size():
			var id := str(branches[i][0]); var dir := int(branches[i][1]); var info: Dictionary = net.edge_info[id]
			var normal := int(info.get("preferred_direction", 0))
			var at: float = 0.0 if dir > 0 else net.graph.edges[id].length
			var heading: Vector2 = net.point_on(id, at).dir * dir
			var alignment := -1.0 if not incoming.is_empty() else 1.0
			for tangent in incoming: alignment = maxf(alignment, tangent.dot(heading))
			var score := (10000.0 if normal != 0 and normal != dir else 0.0) + (100.0 if info.service != "" else 0.0) + (10.0 if normal == 0 else 0.0) + acos(clampf(alignment,-1.0,1.0))
			if score < best_score or (is_equal_approx(score,best_score) and id < best_id):
				best = i; best_score = score; best_id = id
		net.graph.switch_state[key] = best
