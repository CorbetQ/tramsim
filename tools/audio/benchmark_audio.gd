extends SceneTree
## Controller benchmark only, not a claim about mixer CPU or physical-device latency.
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var script: Script = load(args[0]) if not args.is_empty() else load("res://src/audio/tram_audio.gd")
	var results: Array = []
	for family in ["citadis_302", "citadis_x05"]:
		var view := Node3D.new(); root.add_child(view)
		var bell := AudioStreamPlayer.new(); root.add_child(bell)
		var before := OS.get_static_memory_usage()
		var start := Time.get_ticks_usec()
		var ta: Node = script.new(view, bell, family); root.add_child(ta)
		var load_us := Time.get_ticks_usec() - start
		var samples: Array[int] = []
		var maximum := 0
		for i in 3600:
			var st := {"speed": 14.0 * sin(PI * float(i % 1200) / 1200.0), "notch": .7 if i % 1200 < 700 else -.5,
				"external": i % 600 < 300, "underground": i % 1000 < 200, "bridge": i % 1000 > 800,
				"power_ok": true, "pantograph_up": true, "doors_open": i % 1200 < 30}
			start = Time.get_ticks_usec(); ta.update_state(st, 1.0 / 60.0); samples.append(Time.get_ticks_usec() - start)
			var voices := 0
			for e in ta.players.values():
				for reader in [e.p2, e.p3]:
					if reader != null and reader.playing: voices += 1
			maximum = maxi(maximum, voices)
			if i % 60 == 0: await process_frame
		samples.sort()
		results.append({"family": family, "load_us": load_us, "update_p50_us": samples[1800], "update_p95_us": samples[3420],
			"update_max_us": samples[-1], "static_memory_delta_bytes": OS.get_static_memory_usage() - before,
			"max_active_reader_voices": maximum})
		var anchor: Node = ta.anchor
		ta.free()
		# Clean up baseline's known orphan, so it cannot bias the second family.
		if is_instance_valid(anchor): anchor.free()
		view.free(); bell.free()
	print("BENCHMARK|", JSON.stringify({"scope": "headless controller CPU; Dummy mixer; no physical-device audio latency measurement", "results": results}))
	await create_timer(0.1).timeout
	quit()
