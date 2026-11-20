extends SceneTree
func _initialize() -> void:
	if NativeSimulation.kernel()==null:printerr("ECHEC: native kernel required");quit(1);return
	var results := {}
	for backend in [false,true]:
		var timings: Array[float] = []
		NativeSimulation.enabled=backend
		for repetition in 3:
			var physics := TrainPhysics.new(VehicleLibrary.citadis_302())
			for i in 1000:physics.step(1.0/60,.5,0)
			var start := Time.get_ticks_usec()
			for i in 30000:physics.step(1.0/60,.5 if i%600<300 else -.5,.02)
			timings.append((Time.get_ticks_usec()-start)/1000.0)
		results["rust" if backend else "gdscript"]=timings
	results["scope"]="CPU physics microbenchmark only; not game FPS or Android"
	results["steps_per_run"]=30000;results["godot"]=Engine.get_version_info().string
	results["processor"]=OS.get_processor_name()
	var file := FileAccess.open("res://.cache/next/native-benchmark.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(results,"\t"));file.close()
	print(JSON.stringify(results));quit()
