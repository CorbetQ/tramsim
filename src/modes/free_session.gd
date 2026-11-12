class_name FreeSession
extends MissionSession
## Mode libre : pas de score ; un incident immobilise la rame jusqu'à la remise sur voie.

var incident := ""
var checkpoint_edge: String
var checkpoint_offset: float
var checkpoint_dir: int = 1
var adaptation_notice := ""

func _init(network: NetworkLoader, profile: VehicleProfile, start_edge: String, start_offset: float, traffic_on: bool = true) -> void:
	super._init(network, profile, start_edge, start_offset, [] as Array[float], 20)
	checkpoint_edge = start_edge
	checkpoint_offset = start_offset
	var normal := int(net.edge_info[start_edge].get("preferred_direction", 0))
	if normal != 0: direction = normal; route_dir = [normal]; checkpoint_dir = normal
	adaptation_notice = Compatibility.adaptation_notice(profile, network.supplies, str(network.meta.get("guidance", "steel")))
	initialize_power()
	NormalRouting.initialize(network)
	traffic.set_enabled(traffic_on)
	update_spans()

func _fail(reason: String) -> void:
	incident = reason
	blocked = true
	phys.speed = 0.0
	event.emit("incident", reason)

func _check_station_passed() -> void:
	pass

func _station_here() -> Dictionary:
	var station := next_station_ahead()
	return station if not station.is_empty() and net.station_contains(station, edge_id, offset) else {}

func tick(dt: float, notch: float, emergency: bool = false) -> void:
	super.tick(dt, notch, emergency)
	update_spans()

## Déclare au graphe la partie de chaque arête réellement sous la rame : un aiguillage n'est verrouillé
## que si la rame est sur sa zone (en mission, toute arête occupée verrouille ses aiguillages).
func update_spans() -> void:
	_sync_dirs()
	var rem := phys.profile.length_m
	var seen := {}
	for i in range(route.size() - 1, -1, -1):
		var id: String = route[i]
		var L: float = net.graph.edges[id].length
		var r: int = route_dir[i]
		var exit_x: float = offset if i == route.size() - 1 else (L if r > 0 else 0.0)
		var amount := minf(rem, exit_x if r > 0 else L - exit_x)
		var a := exit_x - amount * r
		var sp := Vector2(minf(a, exit_x), maxf(a, exit_x))
		if seen.has(id): sp = Vector2(minf(sp.x, seen[id].x), maxf(sp.y, seen[id].y))
		seen[id] = sp
		net.graph.set_span(id, sp.x, sp.y)
		rem -= amount
		if rem <= 0.0: break

func _update_dwell(dt: float) -> void:
	if doors_open:
		super._update_dwell(dt)

## Choisit la branche d'un aiguillage (nœud, côté de départ) ; refusé si occupé.
func select_branch(node: String, branch: int, side: int = 1) -> bool:
	return net.graph.throw_switch(node, branch, side)

## Remise sur voie : retour au dernier point sûr, avec libération des sections.
func rerail() -> void:
	for id in route:
		net.graph.release(id, train_id)
	route = [checkpoint_edge]
	route_dir = [checkpoint_dir]
	edge_id = checkpoint_edge
	offset = checkpoint_offset
	direction = checkpoint_dir
	net.graph.occupy(edge_id, train_id)
	update_spans()
	phys.speed = 0.0
	incident = ""
	blocked = false
	traffic.cars.clear()

func set_checkpoint() -> void:
	if phys.speed < 0.1:
		checkpoint_edge = edge_id
		checkpoint_offset = offset
		checkpoint_dir = direction

func set_traffic(on: bool) -> void:
	traffic.set_enabled(on)

## Changement de cabine : à l'arrêt, le conducteur passe à l'autre extrémité ; la queue devient la tête
## et la rame repart en sens inverse sur la même voie (aucun déplacement). Pour changer de voie, on
## emprunte ensuite une communication (aiguillages manœuvrables depuis le plan).
func reverse() -> String:
	if phys.speed > 0.1:
		return "Arrêtez la rame avant de changer de cabine"
	var tail: Array = locate_behind(phys.profile.length_m)
	var i: int = tail[3]
	var nr: Array[String] = []
	var nd: Array[int] = []
	for k in range(route.size() - 1, i - 1, -1):
		nr.append(route[k]); nd.append(-route_dir[k])
	# nouvelle route : de la nouvelle queue (ancien nez) au nouveau nez (ancienne queue)
	route = nr
	route_dir = nd
	edge_id = tail[0]
	offset = tail[1]
	direction = -int(tail[2])
	for id in route:
		net.graph.occupy(id, train_id)
	update_spans()
	doors_open = false
	checkpoint_edge = edge_id
	checkpoint_offset = offset
	checkpoint_dir = direction
	event.emit("reverse", "Changement de cabine : marche " + ("dans le sens de la voie" if direction > 0 else "à contre-sens de la voie"))
	return ""

## Adaptation libre d'un matériel étranger : conserve les interverrouillages
## du collecteur, même lorsque les caractéristiques de la rame sont adaptées.
func available_power_modes() -> PackedStringArray:
	if adaptation_notice == "": return super.available_power_modes()
	var modes := PackedStringArray()
	for mode in net.supplies:
		if mode != "none": modes.append(str(mode))
	return modes if not modes.is_empty() else super.available_power_modes()
