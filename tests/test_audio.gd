extends SceneTree
## Moteur sonore : flux chargés (OGG, boucles), création de TramAudio, mises à jour avec différents états
## (arrêt, traction, freinage électrique puis mécanique, courbe, portes, urgence, pause, cabine/extérieur),
## pilotage depuis une vraie MissionSession, budget data/audio <= 8 Mo.
var fails := 0
func check(c: bool, m: String) -> void:
	if not c: fails += 1; printerr("ECHEC: ", m)
	else: print("ok: ", m)

func _initialize() -> void:
	_run.call_deferred()

func _st(v: float, notch: float, extra: Dictionary = {}) -> Dictionary:
	var s := {"speed": v, "max_speed": 19.4, "notch": notch, "doors_open": false, "emergency": false, "pantograph_up": true,
		"power_ok": true, "speed_limit": 19.4, "paused": false, "external": true, "curvature": 0.0}
	s.merge(extra, true)
	return s

func _run() -> void:
	# flux
	var total := 0
	for n in TramAudio.LOOPS.keys() + TramAudio.SHOTS.keys() + ["gong"]:
		var s := TramAudio.load_stream(n, n in TramAudio.LOOPS)
		check(s is AudioStreamOggVorbis and s.get_length() > 0.1, "flux %s chargé (%.2f s)" % [n, s.get_length() if s else 0.0])
		if s is AudioStreamOggVorbis: check((s as AudioStreamOggVorbis).loop == (n in TramAudio.LOOPS), "%s : bouclage correct" % n)
	for f in DirAccess.get_files_at("res://data/audio"):
		if f.ends_with(".ogg"): total += FileAccess.get_file_as_bytes("res://data/audio/" + f).size()
	check(total > 0 and total <= 8 * 1024 * 1024, "data/audio : %.0f Ko (≤ 8 Mo)" % (total / 1024.0))
	check(FileAccess.file_exists("res://data/audio/sources.json"), "provenance des sons documentée")
	# moteur sonore sans vue (2D seulement pour l'ambiance, 3D sur l'ancre)
	var bell := AudioStreamPlayer.new(); root.add_child(bell)
	var ta := TramAudio.new(null, bell)
	root.add_child(ta)
	check(ta.players.size() == TramAudio.LOOPS.size() + TramAudio.SHOTS.size(), "%d lecteurs créés" % ta.players.size())
	check(bell.stream is AudioStreamOggVorbis, "gong attribué à la cloche")
	# hauteur de l'onduleur : monte avec la vitesse, paliers de mode (redescente) présents
	check(TramAudio.motor_hz(1.0) < TramAudio.motor_hz(5.0), "onduleur : la hauteur monte au démarrage")
	check(TramAudio.motor_hz(20.5 / 3.6) < TramAudio.motor_hz(19.5 / 3.6), "onduleur : palier de changement de mode")
	# séquence de conduite
	var dt := 1.0 / 30.0
	for i in 30: ta.update_state(_st(0.0, 0.0), dt)
	check(ta.gain.hvac > 0.5 and ta.gain.rolling < 0.01 and ta.gain.motor < 0.05, "à l'arrêt : climatisation, pas de roulement ni d'onduleur")
	check((ta.players.ambience.p2 as AudioStreamPlayer).playing, "ambiance urbaine jouée")
	var v := 0.0
	for i in 150:
		v = minf(v + 0.08, 12.0); ta.update_state(_st(v, 1.0), dt)
	check(ta.gain.motor > 0.8 and ta.gain.rolling > 0.4, "traction : onduleur %.2f, roulement %.2f" % [ta.gain.motor, ta.gain.rolling])
	var p3: AudioStreamPlayer3D = ta.players.motor.p3
	check(p3.playing and absf(p3.pitch_scale - TramAudio.motor_hz(v) / TramAudio.MOTOR_REF_HZ) < 0.001, "vue extérieure : onduleur spatialisé, hauteur %.2f" % p3.pitch_scale)
	check(ta.gain.carrier < 0.05, "porteuse asynchrone éteinte à vitesse établie")
	# courbe serrée
	for i in 30: ta.update_state(_st(6.0, 0.0, {"curvature": 9.0}), dt)
	check(ta.gain.squeal > 0.5, "crissement en courbe (%.2f)" % ta.gain.squeal)
	for i in 30: ta.update_state(_st(6.0, 0.0), dt)
	check(ta.gain.squeal < 0.1, "pas de crissement en alignement")
	# vue cabine : bascule 2D en conservant la lecture
	ta.update_state(_st(6.0, 0.5, {"external": false}), dt)
	check(not ta.players.motor.p3.playing and (ta.players.motor.p2 as AudioStreamPlayer).playing, "cabine : lecteurs 2D")
	# freinage électrique puis mécanique jusqu'à l'arrêt
	var ebrake := 0.0
	v = 6.0
	while v > 0.0:
		v = maxf(v - 0.05, 0.0); ta.update_state(_st(v, -0.7, {"external": false}), dt)
		if v > 3.0: ebrake = maxf(ebrake, ta.gain.motor)
	check(ebrake > 0.4, "freinage électrique audible (%.2f)" % ebrake)
	check(ta.shots.get("brake_mech", 0) == 1, "freinage mécanique final déclenché une fois")
	# portes
	ta.update_state(_st(0.0, 0.0, {"doors_open": true}), dt)
	check(ta.shots.get("door_open", 0) == 1, "ouverture des portes")
	ta.update_state(_st(0.0, 0.0), dt)
	check(ta.shots.get("door_chime", 0) == 1, "signal de fermeture des portes")
	for i in 20: ta.update_state(_st(0.0, 0.0), dt)
	check(ta.shots.get("door_close", 0) == 1, "fermeture des vantaux")
	# urgence
	ta.update_state(_st(10.0, -1.0, {"emergency": true}), dt)
	check(ta.shots.get("emergency", 0) == 1, "freinage d'urgence")
	# pantographe baissé : plus de traction
	for i in 30: ta.update_state(_st(5.0, 1.0, {"pantograph_up": false}), dt)
	check(ta.gain.motor < 0.2, "pantographe baissé : onduleur muet")
	# pause
	ta.update_state(_st(5.0, 1.0, {"paused": true}), dt)
	check(ta.is_paused, "pause : boucles suspendues")
	ta.update_state(_st(5.0, 1.0), dt)
	check(not ta.is_paused, "reprise après pause")
	ta.gong()
	check(bell.stream != null, "gong")
	# depuis une vraie session de conduite
	var net := NetworkLoader.new(); net.load_file("res://data/networks/angers_a.json")
	var veh := VehicleLibrary.default_for(net.meta)
	var sched: Array[float] = []
	for i in net.stations.size(): sched.append(120.0 + 140.0 * i)
	var s := MissionSession.new(net, veh, net.meta.edges[0].id, 100.0, sched, 40)
	for i in 120:
		s.tick(dt, 1.0)
		ta.update(s, 1.0, false, true, false, dt)
	check(s.phys.speed > 1.0 and ta.state.speed == s.phys.speed, "MissionSession : état transmis (%.1f m/s)" % s.phys.speed)
	ta.queue_free()
	await process_frame
	quit(1 if fails > 0 else 0)
