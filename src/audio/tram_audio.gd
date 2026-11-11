class_name TramAudio
extends Node
## Moteur sonore de la rame : couches pilotées par l'état de MissionSession (vitesse, cran, portes, urgence,
## pantographe, courbes). Boucles : onduleur IGBT (sifflement dont la hauteur suit la vitesse, paliers de modulation
## façon Citadis), porteuse de découpage (basse vitesse), roulement, crissement en courbe, compresseur / climatisation,
## ambiance urbaine. Ponctuels : joints de rail, freinage mécanique final, desserrage, urgence, portes (ouverture,
## signal de fermeture, fermeture), gong. Sons synthétisés (data/audio/make_audio.py), provenance et références
## libres dans data/audio/sources.json et CREDITS.md. Vue extérieure : AudioStreamPlayer3D portés par la rame ; cabine : AudioStreamPlayer 2D.

const DIR := "res://data/audio/"
## Boucles : nom -> volume de référence (dB à gain 1).
const LOOPS := {"motor": -7.0, "carrier": -17.0, "rolling": -9.0, "squeal": -15.0, "hvac": -19.0, "ambience": -16.0}
## Ponctuels : nom -> volume de référence (dB).
const SHOTS := {"joint": -10.0, "brake_mech": -9.0, "brake_release": -15.0, "emergency": -5.0,
	"door_open": -9.0, "door_chime": -8.0, "door_close": -9.0}
const TWO_D_ONLY := ["ambience"]          # l'ambiance entoure l'auditeur, elle ne suit pas la rame
const CAB_DB := {"motor": -3.0, "rolling": -4.0, "squeal": -6.0, "ambience": -8.0, "hvac": 2.0, "carrier": -2.0}
const MOTOR_REF_HZ := 1000.0              # fondamentale de motor.ogg à pitch_scale 1 (voir data/audio/make_audio.py)

var view: Node                            # LineView (rame en vue extérieure), facultatif
var bell: AudioStreamPlayer               # cloche de main.gd : reçoit le gong
var anchor: Node3D
var external := true
var players: Dictionary = {}              # nom -> {p2, p3, loop, db}
var gain: Dictionary = {}                 # nom -> gain linéaire lissé
var streams: Dictionary = {}              # nom -> AudioStream chargé
var state: Dictionary = {}                # dernier état appliqué (tests / debug)
var shots: Dictionary = {}                # nom -> nombre de déclenchements (tests / debug)
var is_paused := false
var _prev: Dictionary = {}
var _joint_left := 12.0
var _close_delay := -1.0
var _rng := RandomNumberGenerator.new()

func _init(line_view: Node = null, bell_player: AudioStreamPlayer = null) -> void:
	name = "TramAudio"
	view = line_view
	bell = bell_player
	_rng.seed = 7

func _ready() -> void:
	anchor = Node3D.new(); anchor.name = "TramAudioAnchor"
	if view is Node3D: view.add_child(anchor)
	else: add_child(anchor)
	for n in LOOPS: _make(n, true, LOOPS[n])
	for n in SHOTS: _make(n, false, SHOTS[n])
	var g := load_stream("gong", false)
	if bell and g: bell.stream = g; bell.volume_db = -6.0

## Flux de data/audio/<nom>.ogg (importé, sinon lu directement).
static func load_stream(n: String, loop: bool) -> AudioStream:
	var path := DIR + n + ".ogg"
	var s: AudioStream = null
	if ResourceLoader.exists(path): s = load(path)
	elif FileAccess.file_exists(path): s = AudioStreamOggVorbis.load_from_file(path)
	if s is AudioStreamOggVorbis: (s as AudioStreamOggVorbis).loop = loop
	return s

func _make(n: String, loop: bool, db: float) -> void:
	var s := load_stream(n, loop)
	if s == null:
		push_warning("TramAudio : flux manquant " + n); return
	streams[n] = s
	var p2 := AudioStreamPlayer.new(); p2.stream = s; p2.name = n + "_2d"; add_child(p2)
	var p3: AudioStreamPlayer3D = null
	if not n in TWO_D_ONLY:
		p3 = AudioStreamPlayer3D.new(); p3.stream = s; p3.name = n + "_3d"
		p3.unit_size = 14.0; p3.max_distance = 260.0; p3.attenuation_filter_cutoff_hz = 9000.0
		p3.attenuation_filter_db = -12.0
		p3.position = _offset(n)
		anchor.add_child(p3)
	players[n] = {"p2": p2, "p3": p3, "loop": loop, "db": db}
	gain[n] = 0.0

## Position des sources sur la rame (repère du module central, avant vers -z).
func _offset(n: String) -> Vector3:
	match n:
		"motor", "carrier": return Vector3(0, 0.4, 0)
		"hvac": return Vector3(0, 3.4, 2.0)
		"door_open", "door_close", "door_chime": return Vector3(1.3, 1.6, 0)
		"squeal", "joint", "brake_mech": return Vector3(0, 0.2, -4.0)
	return Vector3(0, 0.8, 0)

func _active(n: String) -> Node:
	var e: Dictionary = players[n]
	return e.p3 if external and e.p3 != null else e.p2

func _inactive(n: String) -> Node:
	var e: Dictionary = players[n]
	if e.p3 == null: return null
	return e.p2 if external else e.p3

## Bascule cabine / extérieur : les boucles reprennent au même point sur l'autre lecteur.
func set_external(on: bool) -> void:
	if on == external: return
	external = on
	for n in players:
		var old: Node = _inactive(n)
		var cur: Node = _active(n)
		if old == null or old == cur: continue
		if old.playing:
			var pos: float = old.get_playback_position()
			old.stop()
			if players[n].loop: cur.play(pos)

func _shot(n: String, vol: float = 1.0, pitch: float = 1.0) -> void:
	if not players.has(n): return
	var p: Node = _active(n)
	p.volume_db = float(players[n].db) + linear_to_db(maxf(vol, 0.001)) + (float(CAB_DB.get(n, 0.0)) if not external else 0.0)
	p.pitch_scale = pitch
	p.play()
	shots[n] = int(shots.get(n, 0)) + 1

## Courbe de hauteur de l'onduleur (Hz) en fonction de la vitesse (m/s) : porteuse asynchrone puis modes
## synchrones ; la fréquence statorique monte avec la vitesse et redescend à chaque changement de mode
## (« escalier » caractéristique des Citadis à IGBT ; valeurs estimées, cf. data/audio/sources.json).
static func motor_hz(v: float) -> float:
	var kmh := v * 3.6
	if kmh < 6.0: return lerpf(380.0, 640.0, kmh / 6.0)
	if kmh < 20.0: return lerpf(640.0, 1150.0, (kmh - 6.0) / 14.0)
	if kmh < 34.0: return lerpf(820.0, 1300.0, (kmh - 20.0) / 14.0)
	return lerpf(980.0, 1500.0, clampf((kmh - 34.0) / 36.0, 0.0, 1.0))

## Mise à jour depuis la session de conduite (appelée chaque image par main.gd).
func update(s: Object, notch: float, emergency: bool, ext: bool, paused: bool, dt: float) -> void:
	if s == null: return
	var st := {"speed": float(s.phys.speed), "max_speed": float(s.phys.profile.max_speed_ms), "notch": notch,
		"doors_open": bool(s.doors_open), "emergency": emergency, "pantograph_up": bool(s.pantograph_up),
		"power_ok": bool(s.power_ok), "speed_limit": float(s.speed_limit()), "paused": paused or bool(s.finished),
		"external": ext, "curvature": _curvature()}
	update_state(st, dt)

## Courbure apparente (degrés entre caisses voisines) lue sur la rame affichée.
func _curvature() -> float:
	if view == null or not ("modules" in view): return 0.0
	var mods: Array = view.modules
	var worst := 0.0
	for i in range(1, mods.size()):
		var a: Vector3 = -(mods[i - 1] as Node3D).global_transform.basis.z
		var b: Vector3 = -(mods[i] as Node3D).global_transform.basis.z
		worst = maxf(worst, rad_to_deg(a.angle_to(b)))
	return worst

## Cœur du mixage : état {speed, max_speed, notch, doors_open, emergency, pantograph_up, power_ok, speed_limit,
## paused, external, curvature} -> gains et hauteurs des couches, déclenchement des ponctuels.
func update_state(st: Dictionary, dt: float) -> void:
	state = st
	set_external(bool(st.get("external", true)))
	if view is Node3D and "modules" in view and not (view.modules as Array).is_empty():
		var mods: Array = view.modules
		anchor.global_transform = (mods[mods.size() / 2] as Node3D).global_transform
	var paused := bool(st.get("paused", false))
	is_paused = paused
	for n in players:
		var p: Node = _active(n)
		p.stream_paused = paused and players[n].loop
	if paused: return
	var v := float(st.get("speed", 0.0))
	var vmax := maxf(float(st.get("max_speed", 19.4)), 1.0)
	var notch := float(st.get("notch", 0.0))
	var doors := bool(st.get("doors_open", false))
	var emerg := bool(st.get("emergency", false))
	var powered := bool(st.get("pantograph_up", true)) and bool(st.get("power_ok", true))
	var kmh := v * 3.6
	# traction / freinage électrique : effort de l'onduleur
	var trac := clampf(notch, 0.0, 1.0) if powered and not doors else 0.0
	var ebrake := clampf(-notch, 0.0, 1.0) * smoothstep(0.8, 2.5, v) if not emerg else 0.0
	var load := maxf(trac, ebrake)
	var t := {}
	t.motor = (0.3 + 0.7 * load) if load > 0.02 else 0.15 * smoothstep(1.0, 6.0, v)   # roue libre : léger résidu
	t.carrier = load * (1.0 - smoothstep(5.0, 9.0, v)) * (0.6 + 0.4 * trac)
	t.rolling = pow(clampf(v / 16.0, 0.0, 1.0), 0.8)
	var curv := float(st.get("curvature", 0.0))
	var lim_kmh := float(st.get("speed_limit", vmax)) * 3.6
	var tight := maxf(smoothstep(2.5, 7.0, curv), (1.0 - smoothstep(18.0, 30.0, lim_kmh)) * 0.6)
	t.squeal = tight * smoothstep(1.5, 4.0, v) * (1.0 - smoothstep(9.0, 14.0, v) * 0.5)
	t.hvac = (0.55 + 0.45 * (1.0 - smoothstep(0.5, 6.0, v))) * (1.0 if powered else 0.25)
	t.ambience = 1.0
	var k := clampf(dt * 6.0, 0.0, 1.0)
	for n in t:
		if not players.has(n): continue
		gain[n] = lerpf(float(gain[n]), float(t[n]), k)
		var p: Node = _active(n)
		var g := float(gain[n])
		var db := float(players[n].db) + linear_to_db(maxf(g, 0.0001)) + (float(CAB_DB.get(n, 0.0)) if not external else 0.0)
		p.volume_db = db
		if g > 0.002 and not p.playing: p.play(_rng.randf() * 0.5)
		elif g <= 0.002 and p.playing: p.stop()
	if players.has("motor"): _active("motor").pitch_scale = motor_hz(v) / MOTOR_REF_HZ
	if players.has("rolling"): _active("rolling").pitch_scale = 0.75 + 0.5 * clampf(v / vmax, 0.0, 1.0)
	if players.has("squeal"): _active("squeal").pitch_scale = 0.95 + 0.1 * sin(Time.get_ticks_msec() * 0.0013)
	# joints de rail : « ta-tac » des deux essieux d'un bogie, espacement irrégulier (soudures, aiguillages)
	_joint_left -= v * dt
	if _joint_left <= 0.0:
		_joint_left = _rng.randf_range(14.0, 36.0)
		if v > 1.5: _shot("joint", clampf(0.35 + kmh / 60.0, 0.0, 1.0), clampf(0.85 + v / vmax * 0.3, 0.8, 1.2))
	# freinage mécanique final (sous ~7 km/h en freinage) et desserrage au démarrage
	var pv := float(_prev.get("speed", v))
	var braking := notch < -0.05 or emerg
	if braking and pv >= 2.0 and v < 2.0 and v > 0.05: _shot("brake_mech", clampf(0.5 + absf(notch) * 0.5, 0.0, 1.0))
	if pv < 0.05 and v >= 0.05 and trac > 0.0: _shot("brake_release", 0.8)
	if emerg and not bool(_prev.get("emergency", false)) and v > 0.5: _shot("emergency")
	# portes : ouverture ; à la fermeture, signal sonore puis fermeture des vantaux
	var was_open := bool(_prev.get("doors_open", doors))
	if doors and not was_open: _shot("door_open"); _close_delay = -1.0
	if not doors and was_open: _shot("door_chime"); _close_delay = 0.45
	if _close_delay >= 0.0:
		_close_delay -= dt
		if _close_delay < 0.0: _shot("door_close")
	_prev = st.duplicate()

## Gong de tram (cloche de main.gd).
func gong() -> void:
	if bell: bell.play()
