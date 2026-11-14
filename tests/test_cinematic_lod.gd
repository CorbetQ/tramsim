extends SceneTree
## Natural playback benchmark: never freezes time, moves the camera manually or warms tiles.
var failures := 0
func check(ok: bool, message: String) -> void:
	if ok: print("ok: ", message)
	else: failures += 1; printerr("ECHEC: ", message)
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	var main = load("res://src/ui/main.tscn").instantiate()
	var city := OS.get_environment("LOD_CITY")
	if city == "": city = "Angers"
	main.menu_city = city; main.menu_page = "setup"; main.free_mode = true
	root.add_child(main)
	main.save.settings.home_bg = OS.get_environment("LOD_NO_BACKGROUND") != "1"; main.save.settings.intro = true; main.save.settings.tutorial_done = true
	main.save.settings.traffic = false; main._build_menu()
	var deadline := Time.get_ticks_msec() + 180000
	while (not main._ready_for_launch(city) or main._menu.go.disabled or main._city_loading_layer.visible) and Time.get_ticks_msec() < deadline: await process_frame
	check(main._ready_for_launch(city), "city ready before launch")
	if not main._ready_for_launch(city): quit(1); return
	var proxy: CityScene = main.home_bg._layers[-1].scene
	check(proxy is AerialCityLOD and proxy.prepared, "static geographic aerial LOD prepared before launch")
	print("LOD_PROXY|city=%s|triangles=%d|patches=%d" % [city, proxy.triangles, proxy.get_child_count()])
	var render_scale0 := root.scaling_3d_scale
	var msaa0 := root.msaa_3d
	main._menu.go.pressed.emit()
	deadline = Time.get_ticks_msec() + 60000
	while main.session == null and Time.get_ticks_msec() < deadline: await process_frame
	if main.session == null: check(false, "launch creates session"); main.queue_free(); await process_frame; quit(1); return
	var start := Time.get_ticks_usec(); var last := start
	var frames: Array[float] = []; var aerial_frames: Array[float] = []
	var saved_aerial := false
	var max_draws := 0; var max_primitives := 0
	while is_instance_valid(main.intro) and Time.get_ticks_usec() - start < 60000000:
		await process_frame
		var now := Time.get_ticks_usec(); var ms := (now - last) / 1000.0; last = now
		frames.append(ms)
		if is_instance_valid(main.intro) and is_instance_valid(main.intro._aerial) and main.intro._aerial.visible:
			aerial_frames.append(ms)
			if not saved_aerial and main.intro.t > 1.0 and OS.get_environment("LOD_SHOTS") != "":
				saved_aerial = true
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(OS.get_environment("LOD_SHOTS").path_join(city + "-aerial.png"))
			max_draws = maxi(max_draws, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
			max_primitives = maxi(max_primitives, int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)))
	var seconds := (Time.get_ticks_usec() - start) / 1000000.0
	frames.sort(); aerial_frames.sort()
	check(not is_instance_valid(main.intro), "natural cinematic completes within 60 s")
	check(is_equal_approx(root.scaling_3d_scale, render_scale0) and root.msaa_3d == msaa0, "render quality restored after cinematic")
	check(main.view.city.async_lod, "detailed street tiles stream off the main thread")
	check(not frames.is_empty() and not aerial_frames.is_empty(), "natural playback frames recorded")
	if not frames.is_empty() and not aerial_frames.is_empty():
		print("LOD_BENCH|city=%s|duration_s=%.2f|frames=%d|median_ms=%.2f|p95_ms=%.2f|aerial_median_ms=%.2f|aerial_p95_ms=%.2f|aerial_draws=%d|aerial_primitives=%d" % [city, seconds, frames.size(), frames[frames.size()/2], frames[int(frames.size()*.95)], aerial_frames[aerial_frames.size()/2], aerial_frames[int(aerial_frames.size()*.95)], max_draws, max_primitives])
	if OS.get_environment("LOD_SHOTS") != "":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OS.get_environment("LOD_SHOTS").path_join(city + "-arrival.png"))
	main.queue_free(); await process_frame
	var reap_deadline := Time.get_ticks_msec() + 30000
	while CityScene.retired_lod_jobs > 0 and Time.get_ticks_msec() < reap_deadline: await process_frame
	check(CityScene.retired_lod_jobs == 0, "in-flight worker reclaimed without blocking scene removal")
	print("TOTAL_ECHECS|", failures); quit(1 if failures else 0)
