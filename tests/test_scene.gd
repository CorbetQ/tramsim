extends SceneTree
func _init() -> void:
	var main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main._start_mission()
	for i in 20: await process_frame
	var ok: bool = main.session != null and main.view != null and main.view.tram != null
	print("scène instanciée: ", ok, " | ", main.hud.text)
	quit(0 if ok else 1)
