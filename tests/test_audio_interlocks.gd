extends SceneTree
## Vérifie la consigne instantanée de traction en mouvement ; les queues de gain
## lissées restent autorisées et ne sont pas une nouvelle commande de traction.
class AudioView:
	extends Node3D
	var family := ""
	var livery: Dictionary = {}
	var modules: Array = []
var failures := 0
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/rolling_stock/variants/index.json"))
	for entry in catalog.entries:
		var view := AudioView.new(); view.family = entry.family; view.livery = {"variant_id":entry.id}; root.add_child(view)
		var ta := TramAudio.new(view,null,entry.family); root.add_child(ta)
		var state := {"speed":8.0,"notch":1.0,"external":false,"power_ok":true,"pantograph_up":true,"doors_open":false}
		ta.update_state(state,1.0/60)
		if ta.state.traction_load != 1.0: failures += 1; printerr("ECHEC traction disponible : ",entry.id)
		state.doors_open = true; ta.update_state(state,1.0/60)
		if ta.state.traction_load != 0.0: failures += 1; printerr("ECHEC portes ouvertes : ",entry.id)
		state.doors_open = false; state.power_ok = false; ta.update_state(state,1.0/60)
		if ta.state.traction_load != 0.0: failures += 1; printerr("ECHEC alimentation : ",entry.id)
		state.power_ok = true; state.pantograph_up = false; ta.update_state(state,1.0/60)
		if ta.state.traction_load != 0.0: failures += 1; printerr("ECHEC pantographe : ",entry.id)
		state.supply = "aps"; ta.update_state(state,1.0/60)
		if ta.state.traction_load != 1.0: failures += 1; printerr("ECHEC APS : ",entry.id)
		state.emergency = true; ta.update_state(state,1.0/60)
		if ta.state.traction_load != 0.0 or ta.state.regen_load != 0.0: failures += 1; printerr("ECHEC urgence prioritaire sur cran positif : ",entry.id)
		if ta.shots.get("emergency",0) != 1: failures += 1; printerr("ECHEC événement urgence : ",entry.id)
		ta.queue_free(); view.queue_free(); await process_frame
	await create_timer(0.1).timeout
	print("VARIANTES|",catalog.entries.size(),"|TOTAL_ECHECS|",failures)
	quit(1 if failures else 0)
