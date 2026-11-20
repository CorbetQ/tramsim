extends Node
## Fixed-step opt-in harness; production simulation rules are reused, not replaced.
const STEP := 1.0/60.0
var probe: PerfTelemetry
var main: Node
var phases: Array = []
var phase_index := -1
var steps := 0
var accumulator := 0.0
var last_us := 0
var active := false
var skipped := false
var camera: FreeCamera
var camera_base := Vector3.ZERO

func _ready() -> void:
	set_process(false);process_priority=-10;probe.completed.connect(_stop);_boot.call_deferred()

func _boot() -> void:
	await get_tree().process_frame
	main=get_tree().current_scene
	if main==null or not main.has_method("_start"):probe.finish("unsupported_scene");return
	main.benchmark_simulation=true
	var doc: Dictionary = CityDataStore.document(str(probe.config.network))
	main.menu_city=str(doc.city);main.free_mode=true;main.net_path=str(probe.config.network)
	main.vehicle=VehicleLibrary.default_for(doc)
	main.save.settings.tutorial_done=true;main.save.settings.intro=false;main.save.settings.home_bg=false
	main.save.settings.view_distance=float(probe.config.get("view_distance",400))
	main._show_bg(main.menu_city)
	var start := Time.get_ticks_msec()
	while not main.city_preload.is_ready(main.menu_city):
		await get_tree().process_frame
		if main.city_preload.error!="" or Time.get_ticks_msec()-start>180000:
			probe.mark_phase("loading","failed",str(main.city_preload.error));probe.finish("load_failed");return
	var edge: Dictionary = doc.edges[0]
	main.start_station={"edge":edge.id,"offset":minf(30,float(edge.length)*.5),"name":"benchmark"}
	await main._start(false)
	if main.session==null:probe.finish("load_failed");return
	probe.context={"network":main.net.meta.id,"selection":"first graph edge; density is not certified"}
	probe.mark_phase("loading","completed")
	main._set_autopilot(true);main.autopilot.serve_stations=false;main.autopilot.rng.seed=int(probe.config.get("seed",7))
	phases=probe.config.get("phases",PerfTelemetry.PHASES).duplicate()
	last_us=Time.get_ticks_usec();active=true;_advance();set_process(active)

func _advance() -> void:
	if is_instance_valid(main) and is_instance_valid(main.view):main.view.remove_meta("intro_camera")
	camera=null;phase_index+=1;steps=0;accumulator=0
	if phase_index>=phases.size():probe.finish("completed_with_skips" if skipped else "completed");return
	var name_ := str(phases[phase_index])
	if name_=="rain":
		probe.mark_phase(name_,"skipped","WeatherState absent on this revision; rain data not fabricated")
		skipped=true;_advance();return
	if name_=="terminus":
		var found := false
		var free_session := main.get("free") as FreeSession
		for id in main.net.graph.edges:
			var e: TrackGraph.Edge = main.net.graph.edges[id]
			if main.net.graph.choices(e.to_node,-e.to_side).is_empty():
				free_session.checkpoint_edge=id;free_session.checkpoint_offset=maxf(0,e.length-5);free_session.checkpoint_dir=1
				free_session.rerail();free_session.initialize_power();found=true;break
		if not found:
			probe.mark_phase(name_,"skipped","No terminal endpoint selected");skipped=true;_advance();return
		main.autopilot.enabled=false;main.notch=-.75
	if name_=="free_camera":
		main.external_cam=true;main.view.set_meta("intro_camera",true)
		camera=FreeCamera.new(main.view.cam);camera.ground=main.view.ground_at;camera_base=main.view.cam.position
	main.hour0=22.0 if name_=="night" else 12.0
	probe.mark_phase(name_)

func _process(_dt: float) -> void:
	if not active or not probe.enabled:return
	var now := Time.get_ticks_usec();accumulator+=(now-last_us)/1000000.0;last_us=now
	var count := 0
	while accumulator>=STEP and count<240:
		if main.autopilot.enabled:main.notch=main.autopilot.control(main.session,STEP)
		main.session.tick(STEP,main.notch,false)
		steps+=1;count+=1;accumulator-=STEP
		if camera!=null:
			var t := steps*STEP
			camera.pos=camera_base+Vector3(40*sin(t*.25),10*sin(t*.15),40*(1-cos(t*.25)))
			camera.pos.y=maxf(camera.pos.y,camera.ground_at(camera.pos)+FreeCamera.MIN_AGL)
			camera.yaw=.2*sin(t*.5);camera.pitch=-.45;camera.apply()
		if steps>=ceili(float(probe.config.get("phase_seconds",8))/STEP):
			probe.mark_phase(str(phases[phase_index]),"completed");_advance();break
	if accumulator>STEP*240:probe.context.fixed_step_backlog_s=accumulator
	if active:
		probe.context.edge=main.session.edge_id;probe.context.offset_m=main.session.offset
		probe.context.simulation_s=main.session.time_s;probe.context.speed_ms=main.session.phys.speed

func _stop(_state: String) -> void:
	active=false;set_process(false)
	if is_instance_valid(main) and main.has_method("_quit_safely"):main._quit_safely.call_deferred()
	else:get_tree().quit()
