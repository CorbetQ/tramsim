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
var output_name := ""
var expected_bank := ""
# Diagnostic audition only. Recorded motor layers can still contain rolling/environment.
const TRACTION_LAYERS := ["motor", "motor_hum", "carrier", "regen"]
var capture_mode := "full_mix"
var filter_mode := "production_filters"
var muted_layers: Array = []
var production_reference_db: Dictionary = {}
var stream_paths: Dictionary = {}
var did_gong := false
var log_rows: Array = []
var next_log := 0.0
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0: family = args[0]
	if args.size() > 1: variant = args[1]
	if args.size() > 2: output_name = args[2]
	if args.size() > 3: expected_bank = args[3]
	if args.size() > 4: capture_mode = args[4]
	if args.size() > 5: filter_mode = args[5]
	if capture_mode not in ["full_mix", "traction_solo"]:
		printerr("CAPTURE_INVALID_MODE|",capture_mode); quit(2); return
	if filter_mode not in ["production_filters", "bypass_cabin"] or (filter_mode == "bypass_cabin" and capture_mode != "traction_solo"):
		printerr("CAPTURE_INVALID_FILTER_MODE|",filter_mode); quit(2); return
	if output_name.is_empty():
		output_name = family + "_godot_mix"
		if capture_mode == "traction_solo": output_name += "_traction_solo"
		if filter_mode == "bypass_cabin": output_name += "_bypass_cabin"
	# Refuse silencieux de familles inconnues et variantes incohérentes.
	if not family in TramModel.plan_ids():
		printerr("CAPTURE_INVALID_FAMILY|",family); quit(2); return
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/rolling_stock/variants/index.json"))
	var variant_ok := false
	for entry in catalog.entries:
		if entry.id == variant: variant_ok = entry.family == family
	if not variant_ok:
		printerr("CAPTURE_INVALID_VARIANT|",family,"|",variant); quit(2); return
	var view := AudioView.new(); view.family = family; view.livery = {"variant_id":variant}; root.add_child(view)
	var camera := Camera3D.new(); view.add_child(camera); camera.position = Vector3(3, 2, 7); camera.current = true
	var bell := AudioStreamPlayer.new(); root.add_child(bell)
	ta = TramAudio.new(view, bell, family); root.add_child(ta)
	if not expected_bank.is_empty() and str(ta.sound_profile.get("bank", "")) != expected_bank:
		printerr("CAPTURE_INVALID_BANK|",ta.sound_profile.get("bank"),"|expected|",expected_bank); quit(2); return
	for key in ta.streams: stream_paths[key] = ta.streams[key].resource_path
	print("CAPTURE_PROFILE|",TramModel.family_id(family),"|",ta.sound_profile.get("bank"),"|",JSON.stringify(stream_paths))
	for key in ta.players:
		production_reference_db[key] = ta.players[key].db
		if key not in TRACTION_LAYERS:
			muted_layers.append(key)
			# Prevent brief shot leakage between game and audio threads during update().
			if capture_mode == "traction_solo": ta.players[key].db = -80.0
	if capture_mode == "full_mix": muted_layers.clear()
	_apply_audition_mode()
	print("CAPTURE_AUDITION|",capture_mode,"|",filter_mode,"|muted|",JSON.stringify(muted_layers))
	var net := NetworkLoader.new(); net.load_file("res://data/networks/angers_a.json")
	var profile := VehicleLibrary.citadis_302(); profile.model_family = family; profile.variant_id = variant
	var schedule: Array[float] = []
	for i in net.stations.size(): schedule.append(120.0 + 140.0 * i)
	session = MissionSession.new(net, profile, net.meta.edges[0].id, 100.0, schedule, 40)
	recorder = AudioEffectRecord.new(); recorder.format = AudioStreamWAV.FORMAT_16_BITS
	AudioServer.add_bus_effect(0, recorder); recorder.set_recording_active(true)
	print("CAPTURE_BEGIN|", family, "|", variant, "|", AudioServer.get_mix_rate(), "|", AudioServer.get_driver_name())
	process_frame.connect(_frame)
func _apply_audition_mode() -> void:
	if capture_mode != "traction_solo": return
	# Apply after update: production mix/controller keeps running, then diagnostic masking is applied.
	for key in ta.players:
		var entry: Dictionary = ta.players[key]
		for player in [entry.p2, entry.p3]:
			if player == null: continue
			if key not in TRACTION_LAYERS: player.volume_db = -80.0
			elif filter_mode == "bypass_cabin": player.bus = TramAudio.BUS
	if ta.bell: ta.bell.volume_db = -80.0

func _routing_snapshot() -> Dictionary:
	var routing := {}
	for key in ta.players:
		var entry: Dictionary = ta.players[key]
		var active: Node = entry.p3 if ta.external and entry.p3 != null else entry.p2
		routing[key] = {"bus":active.bus,"volume_db":active.volume_db,"pitch_scale":active.pitch_scale,"playing":active.playing,"muted_for_audition":key in muted_layers}
	return routing

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
	_apply_audition_mode()
	if elapsed >= next_log:
		log_rows.append({"seconds":snappedf(elapsed,0.01),"phase":phase,"kmh":speed*3.6,"notch":notch,"external":ta.external,"tunnel":ta.in_tunnel,"bridge":ta.on_bridge,"gains":ta.gain.duplicate(),"shots":ta.shots.duplicate(),"actual_routing":_routing_snapshot(),"master_left_db":AudioServer.get_bus_peak_volume_left_db(0,0)})
		next_log += 0.5
	if elapsed >= 48:
		process_frame.disconnect(_frame)
		recorder.set_recording_active(false)
		var recording := recorder.get_recording()
		var out := "res://samples/demos/" + output_name + ".wav"
		var err := recording.save_to_wav(out)
		var report := {"family":family,"resolved_family":TramModel.family_id(family),"resolved_bank":ta.sound_profile.get("bank",""),"stream_paths":stream_paths,"variant":variant,"driver":AudioServer.get_driver_name(),"mix_rate":AudioServer.get_mix_rate(),"recording_rate":recording.mix_rate,"duration":recording.get_length(),"capture_mode":capture_mode,"filter_mode":filter_mode,"muted_layers":muted_layers,"production_reference_db":production_reference_db,"retained_layers":TRACTION_LAYERS if capture_mode == "traction_solo" else [],"audition_disclosure":"Layer solo, not source separation: recorded motor streams may contain rolling and environment. No loudness normalization. bypass_cabin routes retained layers directly to TramFX, bypassing cabin and environment buses." if capture_mode == "traction_solo" else "Production mix, no audition muting or filter bypass.","method":"Godot AudioEffectRecord on Master; MissionSession with prescribed speed; controlled acoustic zones","timeline":log_rows}
		var f := FileAccess.open("res://samples/demos/" + output_name + ".json",FileAccess.WRITE); f.store_string(JSON.stringify(report,"\t")); f.close()
		print("CAPTURE_END|",out,"|",err,"|",recording.get_length(),"|",recording.data.size())
		quit(err)
