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
