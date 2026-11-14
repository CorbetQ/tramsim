extends SceneTree
## Capture du véritable bus Master Godot, sans resynthèse externe.
## ALSA null: ALSA_CONFIG_PATH=/tmp/tramsim-asound.conf godot --display-driver headless --audio-driver ALSA --path . --script tools/audio/capture_driving_audio.gd -- citadis_302 angers__citadis_302
class AudioView:
	extends Node3D
	var family := "citadis_302"
	var livery: Dictionary = {}
	var modules: Array = []
var ta: TramAudio
var session: MissionSession
var recorder: AudioEffectRecord
var elapsed := 0.0
var family := "citadis_302"
var variant := "angers__citadis_302"
var did_gong := false
var log_rows: Array = []
var next_log := 0.0
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0: family = args[0]
	if args.size() > 1: variant = args[1]
	var view := AudioView.new(); view.family = family; view.livery = {"variant_id":variant}; root.add_child(view)
	var camera := Camera3D.new(); view.add_child(camera); camera.position = Vector3(3, 2, 7); camera.current = true
	var bell := AudioStreamPlayer.new(); root.add_child(bell)
	ta = TramAudio.new(view, bell, family); root.add_child(ta)
	var net := NetworkLoader.new(); net.load_file("res://data/networks/angers_a.json")
	var profile := VehicleLibrary.citadis_302(); profile.model_family = family; profile.variant_id = variant
	var schedule: Array[float] = []
	for i in net.stations.size(): schedule.append(120.0 + 140.0 * i)
	session = MissionSession.new(net, profile, net.meta.edges[0].id, 100.0, schedule, 40)
	recorder = AudioEffectRecord.new(); recorder.format = AudioStreamWAV.FORMAT_16_BITS
	AudioServer.add_bus_effect(0, recorder); recorder.set_recording_active(true)
	print("CAPTURE_BEGIN|", family, "|", variant, "|", AudioServer.get_mix_rate(), "|", AudioServer.get_driver_name())
	process_frame.connect(_frame)
func _frame() -> void:
	var dt := minf(root.get_process_delta_time(), 0.1)
	elapsed += dt
	var speed := 0.0
	var notch := 0.0
	var phase := "idle"
	if elapsed >= 2 and elapsed < 5: phase = "doors_open"; session.doors_open = true
	else: session.doors_open = false
	if elapsed >= 5 and not did_gong: ta.gong(); did_gong = true
	if elapsed >= 7 and elapsed < 23:
		phase = "traction"; speed = (elapsed - 7) / 16 * 50 / 3.6; notch = clampf((elapsed - 7) / 4, 0.15, 1.0)
	elif elapsed >= 23 and elapsed < 27:
		phase = "coasting"; speed = lerpf(50.0, 46.0, (elapsed - 23) / 4) / 3.6
	elif elapsed >= 27 and elapsed < 39:
		phase = "braking"; speed = maxf(0, 46 * (1 - (elapsed - 27) / 12)) / 3.6; notch = -lerpf(0.25, 0.85, (elapsed - 27) / 12)
	elif elapsed >= 39 and elapsed < 42: phase = "doors_open_final"; session.doors_open = true
	elif elapsed >= 44 and elapsed < 46: phase = "paused"
	# Session réelle ; vitesse imposée pour un scénario acoustique strictement comparable.
	session.phys.speed = speed
	session.net.edge_info[session.edge_id].tunnel = [[0.0, 100000.0]] if elapsed >= 27 and elapsed < 31 else []
	session.net.edge_info[session.edge_id].bridge = [[0.0, 100000.0]] if elapsed >= 31 and elapsed < 35 else []
	ta.update(session, notch, false, elapsed >= 23 and elapsed < 33, phase == "paused", dt)
	if elapsed >= next_log:
		log_rows.append({"seconds":snappedf(elapsed,0.01),"phase":phase,"kmh":speed*3.6,"notch":notch,"external":ta.external,"tunnel":ta.in_tunnel,"bridge":ta.on_bridge,"gains":ta.gain.duplicate(),"shots":ta.shots.duplicate(),"master_left_db":AudioServer.get_bus_peak_volume_left_db(0,0)})
		next_log += 0.5
	if elapsed >= 48:
		process_frame.disconnect(_frame)
		recorder.set_recording_active(false)
		var recording := recorder.get_recording()
		var out := "res://samples/demos/" + family + "_godot_mix.wav"
		var err := recording.save_to_wav(out)
		var report := {"family":family,"variant":variant,"driver":AudioServer.get_driver_name(),"mix_rate":AudioServer.get_mix_rate(),"recording_rate":recording.mix_rate,"duration":recording.get_length(),"method":"Godot AudioEffectRecord on Master; MissionSession with prescribed speed; controlled acoustic zones","timeline":log_rows}
		var f := FileAccess.open("res://samples/demos/" + family + "_godot_mix.json",FileAccess.WRITE); f.store_string(JSON.stringify(report,"\t")); f.close()
		print("CAPTURE_END|",out,"|",err,"|",recording.get_length(),"|",recording.data.size())
		quit(err)
