extends SceneTree
var failures := 0
func check(ok: bool, message: String) -> void:
	if ok: print("ok: ", message)
	else: failures += 1; printerr("ECHEC: ", message)
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	var ui := UiAudio.new(); root.add_child(ui)
	var button := Button.new(); root.add_child(button)
	await process_frame; await process_frame
	button.pressed.emit()
	check(ui.played == 1 and ui._player.stream != null, "confirmed action plays an imported CC0 click")
	button.pressed.emit()
	check(ui.played == 1, "rapid duplicate actions do not stack clicks")
	ui._last_usec = -1000000; button.disabled = true; button.pressed.emit()
	check(ui.played == 1, "disabled action is silent")
	button.disabled = false; ui.enabled = false; button.pressed.emit()
	check(ui.played == 1, "interface mute setting is respected")
	ui.enabled = true
	var scroll := TouchScroll.new(); root.add_child(scroll)
	button.reparent(scroll); scroll._dragging = true
	ui._last_usec = -1000000; button.pressed.emit()
	check(ui.played == 1, "drag inside a list makes no click sound")
	var ta := TramAudio.new(); root.add_child(ta)
	for n in ["birds", "air"]:
		check(ta.streams[n] is AudioStreamOggVorbis and ta.streams[n].loop and ta.players[n].p3 == null, n + ": environmental loop surrounds listener")
	var st := {"speed": 0.0, "hour": 12.0}
	for i in 80: ta.update_state(st, 0.1)
	check(ta.gain.birds > 0.9, "daytime birds at station")
	st.hour = 23.0
	for i in 80: ta.update_state(st, 0.1)
	check(ta.gain.birds < 0.001, "no daytime birds at night")
	st.hour = 12.0; st.underground = true
	for i in 80: ta.update_state(st, 0.1)
	check(ta.gain.birds < 0.001 and ta.gain.ambience < 0.001, "outdoor recordings fade out in a tunnel")
	st.underground = false; st.traffic_enabled = false
	for i in 80: ta.update_state(st, 0.1)
	check(ta.gain.ambience < 0.31 and ta.gain.birds > 0.9, "traffic toggle lowers urban layer while preserving nature")
	ta.queue_free(); scroll.queue_free(); ui.queue_free(); await process_frame
	print("TOTAL_ECHECS|", failures); quit(1 if failures else 0)
