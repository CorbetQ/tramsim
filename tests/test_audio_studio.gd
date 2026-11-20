extends SceneTree
## Runtime lifecycle, crossfade, missing assets, voice budget and genuine state transitions.
var fails := 0
func check(ok: bool, message: String) -> void:
	if not ok: fails += 1; printerr("FAIL|", message)
	else: print("PASS|", message)
func _initialize() -> void:
	_run.call_deferred()
func drive(extra: Dictionary = {}) -> Dictionary:
	var st := {"speed": 7.0, "notch": 0.6, "external": true, "power_ok": true, "pantograph_up": true}
	st.merge(extra, true)
	return st
func _run() -> void:
	var view := Node3D.new(); root.add_child(view)
	var bell := AudioStreamPlayer.new(); root.add_child(bell)
	var ta := TramAudio.new(view, bell, "citadis_302"); root.add_child(ta)
	for i in 120: ta.update_state(drive(), 1.0 / 60.0)
	check(ta.players.motor.p3.playing, "traction external starts")
	var count := ta.players.size()
	ta.set_external(false); ta.set_external(true); ta.update_state(drive(), .016)
	check(not ta.players.motor.p2.playing, "same-frame view reversal leaves no inactive voice")
	ta.update_state(drive({"external": false}), 1.0 / 60.0)
	check(ta.players.motor.p2.playing and ta.players.motor.p3.playing, "view crossfade overlaps readers")
	for i in 15: ta.update_state(drive({"external": false}), 1.0 / 60.0)
	check(ta.players.motor.p2.playing and not ta.players.motor.p3.playing, "old view reader stops after 150ms")
	check(ta.players.size() == count, "crossfade allocates no extra players")
	for i in 10:
		ta.update_state(drive({"external": true}), .01)
		ta.update_state(drive({"external": false}), .01)
	check(ta.active_voice_count() <= TramAudio.LOOPS.size() * 2 - TramAudio.TWO_D_ONLY.size() + TramAudio.MAX_SHOT_VOICES * 2 + 1, "rapid reversals respect fixed loop/shot voice envelope")
	await process_frame
	ta.gong(); ta.update_state(drive({"paused": true}), .016)
	check(bell.stream_paused, "gong pauses")
	check((not ta.players.motor.p2.playing or ta.players.motor.p2.stream_paused) and (not ta.players.motor.p3.playing or ta.players.motor.p3.stream_paused), "both crossfade sides pause")
	var gongs: int = int(ta.shots.get("gong", 0)); ta.gong()
	check(int(ta.shots.get("gong", 0)) == gongs, "paused gong not retriggered")
	ta.update_state(drive({"paused": false, "underground": true}), .016)
	check(ta.players.motor.p3.bus == TramAudio.TUNNEL_BUS, "tunnel routing preserved")
	ta.update_state(drive({"bridge": true}), .016)
	check(ta.players.motor.p3.bus == TramAudio.BRIDGE_BUS, "bridge routing preserved")
	# Independent, bounded transient allocation: emergency preempts a low-priority joint.
	for key in ["joint", "brake_release", "brake_mech", "door_open", "door_chime", "emergency"]:
		ta._shot(key)
	var voices := 0
	for key in ta.players:
		if not ta.players[key].loop and ta._active(key).playing: voices += 1
	check(voices <= TramAudio.MAX_SHOT_VOICES and ta._active("emergency").playing, "transient priority budget")
	# Inject only into test instance. Production routing and files remain untouched.
	ta.sound_profile.streams = {"motor": "studio/missing.ogg"}
	ta.players.motor.p2.free(); ta.players.motor.p3.free(); ta.players.erase("motor")
	ta._make("motor", true, -25.0)
	check("motor" in ta.fallback_layers and ta.streams.motor != null, "missing bank layer falls back")
	ta.update_state(drive({"finished": true}), .016)
	check(ta.active_voice_count() == 0 and not bell.playing, "finished session stops every voice")
	var finished_gongs: int = int(ta.shots.get("gong", 0)); ta.gong()
	check(int(ta.shots.get("gong", 0)) == finished_gongs, "finished session rejects new gong")
	var anchor := ta.anchor
	ta.queue_free(); await process_frame; await process_frame
	check(not is_instance_valid(anchor), "view-owned 3D anchor freed with audio")
	check(view.get_child_count() == 0, "no orphan spatial readers")
	var profile := TramAudio.profile_for("citadis_302", "angers__citadis_302", "nonexistent")
	check(profile.bank == "rotterdam_citadis_traction", "invalid audition bank preserves approved fallback")
	view.queue_free(); bell.queue_free(); await process_frame
	await create_timer(0.1).timeout
	print("TOTAL_ECHECS|", fails)
	quit(1 if fails else 0)
