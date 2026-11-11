class_name FreeSession
extends MissionSession
## Mode libre : pas de score ; un incident immobilise la rame jusqu'à la remise sur voie.

var incident := ""
var checkpoint_edge: String
var checkpoint_offset: float
var adaptation_notice := ""

func _init(network: NetworkLoader, profile: VehicleProfile, start_edge: String, start_offset: float, traffic_on: bool = true) -> void:
	super._init(network, profile, start_edge, start_offset, [] as Array[float], 20)
	checkpoint_edge = start_edge
	checkpoint_offset = start_offset
	adaptation_notice = Compatibility.adaptation_notice(profile, network.supplies, str(network.meta.get("guidance", "steel")))
	traffic.set_enabled(traffic_on)

func _fail(reason: String) -> void:
	incident = reason
	blocked = true
	phys.speed = 0.0
	event.emit("incident", reason)

func _check_station_passed() -> void:
	pass

func _update_dwell(dt: float) -> void:
	if doors_open:
		super._update_dwell(dt)

## Choisit la branche à un aiguillage ; refusé si occupé.
func select_branch(node: String, branch: int) -> bool:
	return net.graph.throw_switch(node, branch)

## Remise sur voie : retour au dernier point sûr, avec libération des sections.
func rerail() -> void:
	for id in route:
		net.graph.release(id, train_id)
	route = [checkpoint_edge]
	edge_id = checkpoint_edge
	offset = checkpoint_offset
	net.graph.occupy(edge_id, train_id)
	phys.speed = 0.0
	incident = ""
	blocked = false
	traffic.cars.clear()

func set_checkpoint() -> void:
	if phys.speed < 0.1:
		checkpoint_edge = edge_id
		checkpoint_offset = offset

func set_traffic(on: bool) -> void:
	traffic.set_enabled(on)

## Changement de sens (retournement) : possible à l'arrêt, près d'un arrêt de retournement
## (terminus ou terminus partiel, où existe une communication de voies). La rame repart sur la voie
## opposée, l'ancienne queue devenant la tête.
func reverse() -> String:
	if phys.speed > 0.1:
		return "Arrêtez la rame avant de changer de sens"
	var tail: Array = locate_behind(phys.profile.length_m)
	var q: Dictionary = net.point_on(tail[0], tail[1])
	var p: Vector2 = q.p
	var d: Vector2 = q.dir
	var near_tb := false
	for st in net.stations:
		if st.get("turnback", false):
			var sp: Dictionary = net.point_on(st.edge, float(st.offset))
			if (sp.p as Vector2).distance_to(p) < 160.0:
				near_tb = true; break
	if not near_tb and net.meta.has("turnback_stations"):
		return "Pas de communication de retournement ici (terminus ou terminus partiel uniquement)"
	var best := ""; var best_off := 0.0; var best_d := 8.0
	for id in net.edge_info:
		var pts: PackedVector2Array = net.edge_info[id].pts
		if pts.size() < 2 or id == edge_id: continue
		var acc := 0.0
		var total := 0.0
		for i in range(pts.size() - 1): total += pts[i].distance_to(pts[i + 1])
		for i in range(pts.size() - 1):
			var a := pts[i]; var b := pts[i + 1]
			var seg := a.distance_to(b)
			if seg > 0.0:
				var u := clampf((p - a).dot(b - a) / (seg * seg), 0.0, 1.0)
				var dist := p.distance_to(a.lerp(b, u))
				if dist < best_d and ((b - a) / seg).dot(d) < -0.7:
					best_d = dist; best = id
					var L: float = net.graph.edges[id].length
					best_off = (acc + seg * u) * (L / total if total > 0.0 else 1.0)
			acc += seg
	if best == "":
		return "Voie opposée introuvable ici"
	for id in route:
		net.graph.release(id, train_id)
	edge_id = best
	offset = clampf(best_off, 0.0, net.graph.edges[best].length)
	route = [best]
	visited[best] = true
	net.graph.occupy(best, train_id)
	doors_open = false
	checkpoint_edge = edge_id
	checkpoint_offset = offset
	event.emit("reverse", "Changement de sens effectué")
	return ""
