class_name TramAudio
extends Node
## Moteur sonore de la rame : couches pilotées par l'état de MissionSession (vitesse, cran, portes, urgence,
## pantographe, courbes). Boucles : onduleur IGBT (raie chantée dont la hauteur suit la vitesse, paliers de modes
## synchrones façon Citadis), ronronnement des moteurs, porteuse de découpage (démarrage), roulement, crissement en
## courbe (rare), compresseur / climatisation, ambiance urbaine. Ponctuels : joints de rail, freinage mécanique final, desserrage, urgence, portes (ouverture,
## signal de fermeture, fermeture), gong. Banques traitées / modélisées (tools/audio/design_samples.py), synthèses événementielles (data/audio/make_audio.py), provenance et références
## libres dans data/audio/sources.json et CREDITS.md. Vue extérieure : AudioStreamPlayer3D portés par la rame ; cabine : AudioStreamPlayer 2D.
## Mixage : fichiers normalisés en sonie (-20 LUFS boucles, -18 LUFS ponctuels), niveaux relatifs ci-dessous, bus « TramFX »
## (égaliseur anti-stridence, compresseur, limiteur) et bus « TramCabin » (passe-bas : sources extérieures entendues
## depuis la cabine) créés à la volée.

const DIR := "res://data/audio/"
## Boucles : nom -> volume de référence (dB à gain 1).
const LOOPS := {"motor": -25.0, "motor_hum": -11.0, "carrier": -32.0, "rolling": -8.0, "squeal": -26.0, "hvac": -21.0,
	"ambience": -20.0, "real_rail": -21.0, "regen": -21.0}
## Ponctuels : nom -> volume de référence (dB).
const SHOTS := {"joint": -13.0, "brake_mech": -14.0, "brake_release": -20.0, "emergency": -9.0,
	"door_open": -15.0, "door_chime": -17.0, "door_close": -14.0}
const GONG_DB := -11.0
const TWO_D_ONLY := ["ambience"]          # l'ambiance entoure l'auditeur, elle ne suit pas la rame
## Cabine : correction de niveau (dB) et sources extérieures étouffées (bus TramCabin, passe-bas).
const CAB_DB := {"motor": -4.0, "motor_hum": 1.0, "rolling": -3.0, "squeal": -6.0, "ambience": -6.0, "hvac": 3.0,
	"real_rail": -4.0, "regen": -3.0, "carrier": -3.0, "joint": -2.0, "door_open": -3.0, "door_close": -3.0, "door_chime": 2.0}
const CAB_MUFFLED := ["rolling", "squeal", "ambience", "joint", "brake_mech", "emergency", "carrier", "motor", "real_rail", "regen"]
const BUS := "TramFX"
const CAB_BUS := "TramCabin"
const TUNNEL_BUS := "TramTunnel"
static var _family_manifest: Dictionary = {}
var audio_family := ""
var sound_profile: Dictionary = {}
var sound_bank: Dictionary = {}
var in_tunnel := false
var on_bridge := false
const BRIDGE_BUS := "TramBridge"
const MOTOR_REF_HZ := 300.0               # fondamentale de motor.ogg à pitch_scale 1 (voir data/audio/make_audio.py)
const HUM_REF_HZ := 120.0                 # raie 2f de motor_hum.ogg à pitch_scale 1
const MODE_KMH := [18.0, 38.0]            # changements de mode synchrone (redescente de la raie d'onduleur)

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
var squeal_chance := 0.35                 # probabilité qu'une courbe serrée crisse (le crissement reste rare)
var _squeal_on := false
var _in_curve := false

func _init(line_view: Node = null, bell_player: AudioStreamPlayer = null, family_hint: String = "") -> void:
	audio_family = family_hint
	name = "TramAudio"
	view = line_view
	bell = bell_player
	_rng.seed = 7

func _ready() -> void:
	anchor = Node3D.new(); anchor.name = "TramAudioAnchor"
	if view is Node3D: view.add_child(anchor)
	else: add_child(anchor)
	setup_buses()
	if audio_family == "" and view != null and "family" in view: audio_family = str(view.family)
	var variant_id:=""
	if view!=null and "livery" in view:variant_id=str(view.livery.get("variant_id",""))
	sound_profile = profile_for(audio_family,variant_id)
	sound_bank = sound_profile.get("bank_data", {})
	for n in LOOPS: _make(n, true, LOOPS[n])
	for n in SHOTS: _make(n, false, SHOTS[n])
	_route()
	var g := load_stream("gong", false)
	if bell and g: bell.stream = g; bell.volume_db = GONG_DB; bell.bus = BUS

## Bus TramFX (-> Master) : égaliseur (atténue 3-10 kHz, léger creux 250 Hz), compresseur doux, limiteur -1 dB.
## Bus TramCabin (-> TramFX) : passe-bas 1,6 kHz + étagement grave, pour l'extérieur entendu depuis la cabine.
static func setup_buses() -> void:
	if AudioServer.get_bus_index(BUS) == -1:
		AudioServer.add_bus(); var i := AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, BUS); AudioServer.set_bus_send(i, "Master")
		var eq := AudioEffectEQ6.new()
		for b in [[1, -1.0], [3, -2.0], [4, -4.0], [5, -6.0]]: eq.set_band_gain_db(b[0], b[1])
		AudioServer.add_bus_effect(i, eq)
		var c := AudioEffectCompressor.new(); c.threshold = -18.0; c.ratio = 3.0; c.attack_us = 8000.0
		c.release_ms = 250.0; c.gain = 0.0
		AudioServer.add_bus_effect(i, c)
		var l := AudioEffectHardLimiter.new(); l.ceiling_db = -1.0
		AudioServer.add_bus_effect(i, l)
	if AudioServer.get_bus_index(CAB_BUS) == -1:
		AudioServer.add_bus(); var j := AudioServer.bus_count - 1
		AudioServer.set_bus_name(j, CAB_BUS); AudioServer.set_bus_send(j, BUS)
		var lp := AudioEffectLowPassFilter.new(); lp.cutoff_hz = 1600.0; lp.resonance = 0.5
		AudioServer.add_bus_effect(j, lp)
		var sh := AudioEffectLowShelfFilter.new(); sh.cutoff_hz = 180.0; sh.gain = 1.4
		AudioServer.add_bus_effect(j, sh)

	if AudioServer.get_bus_index(TUNNEL_BUS) == -1:
		AudioServer.add_bus(); var j := AudioServer.bus_count - 1
		AudioServer.set_bus_name(j, TUNNEL_BUS); AudioServer.set_bus_send(j, BUS)
		var room := AudioEffectReverb.new(); room.room_size = 0.65; room.damping = 0.75
		room.wet = 0.18; room.dry = 0.9; AudioServer.add_bus_effect(j, room)

	if AudioServer.get_bus_index(BRIDGE_BUS) == -1:
		AudioServer.add_bus(); var j := AudioServer.bus_count - 1
		AudioServer.set_bus_name(j, BRIDGE_BUS); AudioServer.set_bus_send(j, BUS)
		var eq := AudioEffectEQ6.new(); eq.set_band_gain_db(0, 4.0); eq.set_band_gain_db(1, 2.0)
		AudioServer.add_bus_effect(j, eq)
		var room := AudioEffectReverb.new(); room.room_size = 0.35; room.wet = 0.06; room.dry = 1.0
		AudioServer.add_bus_effect(j, room)

## Bus de chaque lecteur selon la vue (3D et extérieur -> TramFX ; cabine : sources extérieures -> TramCabin).
func _route() -> void:
	var environment_bus := TUNNEL_BUS if in_tunnel else (BRIDGE_BUS if on_bridge else BUS)
	AudioServer.set_bus_send(AudioServer.get_bus_index(CAB_BUS), environment_bus)
	for n in players:
		var e: Dictionary = players[n]
		(e.p2 as AudioStreamPlayer).bus = CAB_BUS if (not external and n in CAB_MUFFLED) else environment_bus
		if e.p3 != null: (e.p3 as AudioStreamPlayer3D).bus = environment_bus

## Flux de data/audio/<nom>.ogg (importé, sinon lu directement).
static func load_stream(n: String, loop: bool) -> AudioStream:
	return stream_path(DIR + ("banks/real_rail_designed.ogg" if n == "real_rail" else n + ".ogg"), loop)

static func stream_path(path: String, loop: bool) -> AudioStream:
	var s: AudioStream = null
	if ResourceLoader.exists(path): s = load(path)
	elif FileAccess.file_exists(path): s = AudioStreamOggVorbis.load_from_file(path)
	if s is AudioStreamOggVorbis: (s as AudioStreamOggVorbis).loop = loop
	return s

func _make(n: String, loop: bool, db: float) -> void:
	var overrides: Dictionary = sound_bank.get("streams", {}).duplicate()
	overrides.merge(sound_profile.get("streams", {}), true)
	var s := stream_path(DIR + str(overrides[n]), loop) if overrides.has(n) else load_stream(n, loop)
	db = float(sound_bank.get("mix", {}).get(n, db))
	if bool(sound_profile.get("rubber", false)) and n in ["real_rail", "squeal", "joint"]: db = -90.0
	if s == null:
		push_warning("TramAudio : flux manquant " + n); return
	streams[n] = s
	var p2 := AudioStreamPlayer.new(); p2.stream = s; p2.name = n + "_2d"; add_child(p2)
	var p3: AudioStreamPlayer3D = null
	if not n in TWO_D_ONLY:
		p3 = AudioStreamPlayer3D.new(); p3.stream = s; p3.name = n + "_3d"
		# source étendue (rame de 30-45 m) : unité 10 m, absorption de l'air (passe-bas avec la distance)
		p3.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p3.unit_size = 10.0; p3.max_distance = 300.0; p3.max_db = 0.0; p3.panning_strength = 0.8
		p3.attenuation_filter_cutoff_hz = 6000.0; p3.attenuation_filter_db = -18.0
		p3.position = _offset(n)
		anchor.add_child(p3)
	players[n] = {"p2": p2, "p3": p3, "loop": loop, "db": db}
	gain[n] = 0.0

## Position des sources sur la rame (repère du module central, avant vers -z).
func _offset(n: String) -> Vector3:
	match n:
		"motor", "carrier", "motor_hum", "regen": return Vector3(0, 0.4, 0)
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
	_route()
	for n in players:
		var old: Node = _inactive(n)
		var cur: Node = _active(n)
		if old == null or old == cur: continue
		if old.playing:
			var pos: float = old.get_playback_position()
			old.stop()
			cur.volume_db = old.volume_db
			cur.pitch_scale = old.pitch_scale
			cur.stream_paused = old.stream_paused
			cur.play(pos)

func _shot(n: String, vol: float = 1.0, pitch: float = 1.0) -> void:
	if not players.has(n): return
	var p: Node = _active(n)
	p.volume_db = float(players[n].db) + linear_to_db(maxf(vol, 0.001)) + (float(CAB_DB.get(n, 0.0)) if not external else 0.0)
	p.pitch_scale = pitch
	p.play()
	shots[n] = int(shots.get(n, 0)) + 1

## Courbe de hauteur de la raie d'onduleur (Hz) en fonction de la vitesse (m/s) : MLI asynchrone au démarrage,
## puis modes synchrones dont la raie monte avec la fréquence statorique et redescend à chaque changement de mode
## (MODE_KMH ; « escalier » des tramways à IGBT, plage 140-620 Hz : chantant sans être strident).
static func motor_hz(v: float) -> float:
	var kmh := v * 3.6
	if kmh < 4.0: return lerpf(140.0, 230.0, kmh / 4.0)
	if kmh < MODE_KMH[0]: return lerpf(230.0, 440.0, (kmh - 4.0) / (MODE_KMH[0] - 4.0))
	if kmh < MODE_KMH[1]: return lerpf(280.0, 480.0, (kmh - MODE_KMH[0]) / (MODE_KMH[1] - MODE_KMH[0]))
	return lerpf(360.0, 620.0, clampf((kmh - MODE_KMH[1]) / 32.0, 0.0, 1.0))

## Raie magnétique 2f des moteurs (Hz) : f_stator ~ 1,6 Hz par km/h + glissement.
static func hum_hz(v: float) -> float:
	return 55.0 + 3.2 * v * 3.6

## Mise à jour depuis la session de conduite (appelée chaque image par main.gd).
func update(s: Object, notch: float, emergency: bool, ext: bool, paused: bool, dt: float) -> void:
	if s == null: return
	var st := {"speed": float(s.phys.speed), "max_speed": float(s.phys.profile.max_speed_ms), "notch": notch,
		"doors_open": bool(s.doors_open), "emergency": emergency, "pantograph_up": bool(s.pantograph_up),
		"wheel_slip":s.phys.slip_ratio, "power_ok": bool(s.power_ok), "supply": s.power_mode, "speed_limit": float(s.speed_limit()), "paused": paused or bool(s.finished),
		"external": ext, "bridge": NetworkLoader.in_spans(s.net.edge_info[s.edge_id].bridge, s.offset), "underground": NetworkLoader.in_spans(s.net.edge_info[s.edge_id].tunnel, s.offset), "curvature": _curvature()}
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
	state = st.duplicate()
	state.audio_family = audio_family
	state.audio_quality = sound_profile.get("quality", "synthetic")
	var tunnel := bool(st.get("underground", false))
	var bridge := bool(st.get("bridge", false))
	if tunnel != in_tunnel or bridge != on_bridge:
		in_tunnel = tunnel; on_bridge = bridge; _route()
	set_external(bool(st.get("external", true)))
	if view is Node3D and "modules" in view and not (view.modules as Array).is_empty():
		var mods: Array = view.modules
		anchor.global_transform = (mods[mods.size() / 2] as Node3D).global_transform
	var paused := bool(st.get("paused", false))
	is_paused = paused
	for n in players:
		var p: Node = _active(n)
		p.stream_paused = paused
	if paused: return
	var v := maxf(float(st.get("speed", 0.0)), 0.0)
	var vmax := maxf(float(st.get("max_speed", 19.4)), 1.0)
	var notch := float(st.get("notch", 0.0))
	var doors := bool(st.get("doors_open", false))
	var emerg := bool(st.get("emergency", false))
	var contact := bool(st.get("pantograph_up", true)) or str(st.get("supply", "overhead")) in ["aps", "battery", "third_rail"]
	var powered := contact and bool(st.get("power_ok", true))
	var kmh := v * 3.6
	# traction / freinage électrique : effort de l'onduleur
	var trac := clampf(notch, 0.0, 1.0) if powered and not doors and not emerg else 0.0
	var ebrake := clampf(-notch, 0.0, 1.0) * smoothstep(0.8, 2.5, v) if not emerg else 0.0
	var load := maxf(trac, 0.65 * ebrake)
	state.traction_load = trac
	state.regen_load = ebrake
	state.audio_mode = "traction" if trac > 0.02 else ("braking" if ebrake > 0.02 else "coasting")
	var t := {}
	t.motor = (0.22 + 0.78 * load) * smoothstep(0.0, 0.7, v) if load > 0.02 else 0.035 * smoothstep(1.0, 6.0, v)   # roue libre : léger résidu
	t.motor_hum = (0.4 + 0.6 * load) * clampf(v, 0.3, 1.0) if load > 0.02 else 0.07 * smoothstep(0.0, 6.0, v)
	t.regen = ebrake * smoothstep(0.4, 2.0, v)
	t.carrier = trac * (1.0 - smoothstep(1.5, 2.5, v)) * (0.6 + 0.4 * trac)
	t.carrier = maxf(float(t.carrier),float(st.get("wheel_slip",0.0))*0.35)
	t.rolling = pow(clampf(v / 16.0, 0.0, 1.0), 1.5)               # amplitude ~ v^1,5 : niveau ~ 30 log10(v)
	# crissement : courbe serrée (> ~5° entre caisses), 2-9 m/s, une courbe sur trois environ
	var curv := float(st.get("curvature", 0.0))
	var tight := smoothstep(4.0, 8.0, curv)
	if tight > 0.3 and not _in_curve: _in_curve = true; _squeal_on = _rng.randf() < squeal_chance
	elif tight < 0.1: _in_curve = false; _squeal_on = false
	t.squeal = tight * smoothstep(2.0, 4.0, v) * (1.0 - smoothstep(8.0, 12.0, v) * 0.6) if _squeal_on else 0.0
	if bool(sound_bank.get("recorded", false)):
		var high := smoothstep(4.0, 12.0, v)
		var drive := (0.35 + 0.65 * load) * smoothstep(0.1, 0.8, v) if load > 0.02 else 0.025 * smoothstep(1.0, 6.0, v)
		t.motor = drive * sqrt(1.0 - high)
		t.motor_hum = drive * sqrt(high)
	if bool(sound_profile.get("rubber", false)): t.squeal = 0.0
	t.hvac = (0.6 + 0.4 * (1.0 - smoothstep(0.5, 6.0, v))) * (1.0 if powered else 0.25)
	t.real_rail = (0.30 * load * smoothstep(0.3, 3.0, v) + 0.65 * t.rolling) * (1.25 if on_bridge else 1.0)
	t.rolling *= 1.25 if on_bridge else 1.0
	t.ambience = 0.12 if in_tunnel else 1.0
	# Different attack/release times avoid abrupt effort and coasting transitions.
	var elapsed := clampf(dt, 0.0, 0.25)
	for n in t:
		if not players.has(n): continue
		var tau := 0.28 if float(t[n]) > float(gain[n]) else 0.6
		var k := 1.0 - exp(-elapsed / tau)
		gain[n] = lerpf(float(gain[n]), float(t[n]), k)
		var p: Node = _active(n)
		var g := float(gain[n])
		var db := float(players[n].db) + linear_to_db(maxf(g, 0.0001)) + (float(CAB_DB.get(n, 0.0)) if not external else 0.0)
		p.volume_db = db
		if g > 0.002 and not p.playing: p.play()
		elif g <= 0.002 and p.playing: p.stop()
	# A single smoothed pitch controller prevents instant octave jumps, including hum and braking.
	var pitches := {"motor": clampf(motor_hz(v) / MOTOR_REF_HZ * float(sound_profile.get("motor_pitch_factor", 1.0)), 0.38, 2.0),
		"motor_hum": clampf(hum_hz(v) / HUM_REF_HZ * float(sound_profile.get("hum_pitch_factor", 1.0)), 0.4, 2.65),
		"regen": clampf(0.7 + v / 24.0, 0.7, 1.45),
		"real_rail": 0.85 + 0.25 * clampf(v / vmax, 0.0, 1.0),
		"rolling": 0.75 + 0.5 * clampf(v / vmax, 0.0, 1.0),
		"squeal": 0.97 + 0.05 * sin(Time.get_ticks_msec() * 0.0013)}
	if bool(sound_bank.get("recorded", false)):
		# A captured pass-by is a texture, not a speed-calibrated isolated motor.
		# Keep transposition within ~2 semitones, use effort and crossfade for dynamics.
		var recorded_pitch := clampf(0.94 + 0.12 * v / maxf(float(sound_bank.get("reference_speed_ms", 8.0)), 1.0), 0.94, 1.12)
		pitches.motor = recorded_pitch
		pitches.motor_hum = recorded_pitch
	for n in pitches:
		if players.has(n):
			var p: Node = _active(n)
			p.pitch_scale = lerpf(float(p.pitch_scale), float(pitches[n]), 1.0 - exp(-elapsed / 0.3))
	state.loop_gains = gain.duplicate()
	state.loop_pitches = pitches.duplicate()
	# joints de rail : « ta-tac » des deux essieux d'un bogie, espacement irrégulier (soudures, aiguillages)
	_joint_left -= v * dt
	if _joint_left <= 0.0:
		_joint_left = _rng.randf_range(80.0, 220.0)
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
	if bell:
		bell.play()
		shots["gong"] = int(shots.get("gong", 0)) + 1

static func profile_for(family_id: String,variant_id:String="") -> Dictionary:
	if family_id.is_empty(): return {}
	if _family_manifest.is_empty() and FileAccess.file_exists(DIR + "families.json"):
		var data = JSON.parse_string(FileAccess.get_file_as_string(DIR + "families.json"))
		if data is Dictionary: _family_manifest = data
	var key := TramModel.family_id(family_id)
	var profile: Dictionary = _family_manifest.get("profiles", {}).get(key, {}).duplicate(true)
	profile.merge(_family_manifest.get("variant_profiles",{}).get(variant_id,{}),true)
	profile.bank_data = _family_manifest.get("banks", {}).get(str(profile.get("bank", "")), {}).duplicate(true)
	return profile

static func profile_label(family_id: String,variant_id:String="") -> String:
	var profile := profile_for(family_id,variant_id)
	var bank: Dictionary = profile.get("bank_data", {})
	match str(profile.get("quality", "synthetic")):
		"exact_family": return "Captation : " + str(bank.get("label", ""))
		"related_family": return "Captation apparentée : " + str(bank.get("label", ""))
		"modeled": return "Restitution modélisée : " + str(bank.get("label", ""))
	return "Traction estimée (son de remplacement)"
