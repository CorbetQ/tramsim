class_name MissionEvents
extends RefCounted
## Événements d'exploitation d'une mission : zones (inondation, feuilles mortes, chantier,
## coupure d'alimentation), défauts ponctuels (pantographe, véhicule sur la voie) et
## affluence. Indépendant du rendu ; EventView en lit la liste pour l'affichage.

const DRY_ADHESION := 0.26
const FLOOD_LIMIT_MS := 10.0 / 3.6
const FLOOD_FAIL_MS := 15.0 / 3.6
const OBSTACLE_SIGHT_M := 180.0
const OBSTACLE_STOP_M := 80.0
const FAULT_REARM_S := 10.0

var items: Array = []           # copie des événements de la mission, enrichie de l'état
var base_adhesion := DRY_ADHESION
var flood_overspeed_s := 0.0
var slide_s := 0.0
var slip_s := 0.0
var flags: Dictionary = {}      # objectifs atteints : "fault_cleared", "obstacle_cleared", "power_restored"...

func _init(list: Array = [], adhesion: float = DRY_ADHESION) -> void:
	base_adhesion = adhesion
	for ev in list:
		var it: Dictionary = ev.duplicate(true)
		it["state"] = "pending"
		it["t"] = 0.0
		items.append(it)

func of_kind(kind: String) -> Array:
	return items.filter(func(it): return str(it.kind) == kind)

static func _in_segments(segments: Array, edge: String, offset: float) -> bool:
	for sg in segments:
		if str(sg[0]) == edge and offset >= minf(float(sg[1]), float(sg[2])) - 0.01 and offset <= maxf(float(sg[1]), float(sg[2])) + 0.01:
			return true
	return false

## Vrai si le nez ou la queue de la rame est dans la zone.
static func train_in(s: MissionSession, segments: Array) -> bool:
	if _in_segments(segments, s.edge_id, s.offset): return true
	var tail := s.locate_behind(s.phys.profile.length_m)
	return _in_segments(segments, str(tail[0]), float(tail[1]))

func zone_active(it: Dictionary) -> bool:
	match str(it.kind):
		"power_cut": return str(it.state) == "active"
		_: return true

## Limite imposée par les événements sous la rame (INF si aucune).
func speed_cap(s: MissionSession) -> float:
	var v := INF
	for it in items:
		if str(it.kind) == "flood" and train_in(s, it.get("segments", [])): v = minf(v, FLOOD_LIMIT_MS)
		elif str(it.kind) == "works_slow" and train_in(s, it.get("segments", [])): v = minf(v, float(it.get("limit_kmh", 20)) / 3.6)
	return v

## Prochaine zone limitée (inondation) devant la rame : {distance, limit} ou {}.
func next_restriction(s: MissionSession, horizon: float = 400.0) -> Dictionary:
	var best := {}
	for it in items:
		if str(it.kind) != "flood": continue
		if train_in(s, it.get("segments", [])): continue
		for sg in it.get("segments", []):
			for at in [float(sg[1]), float(sg[2])]:
				var d := s.dist_to_point(str(sg[0]), at, horizon)
				if d != INF and d > 0.0 and d < float(best.get("distance", horizon)):
					best = {"distance": d, "limit": FLOOD_LIMIT_MS}
	return best

## Adhérence au point du nez : feuilles mortes ou rail humide.
func adhesion_at(s: MissionSession) -> float:
	var mu := base_adhesion
	for it in items:
		if str(it.kind) == "leaves" and train_in(s, it.get("segments", [])): mu = minf(mu, float(it.get("adhesion", 0.07)))
		elif str(it.kind) == "flood" and train_in(s, it.get("segments", [])): mu = minf(mu, 0.12)
	return mu

## Alimentations réellement disponibles (coupure de sous-station).
func filter_supplies(s: MissionSession, supplies: PackedStringArray) -> PackedStringArray:
	for it in items:
		if str(it.kind) == "power_cut" and str(it.state) == "active" and train_in(s, it.get("segments", [])):
			var out := PackedStringArray()
			for m in supplies:
				if m != "overhead" and m != "aps": out.append(m)
			return out
	return supplies

## Affluence : facteur d'embarquement et durée minimale d'arrêt à une station.
func crowd_at(station_name: String) -> Dictionary:
	for it in items:
		if str(it.kind) == "crowd" and str(it.get("station", "")) == station_name: return it
	return {}

## Arrêts non desservis (déviation, fermeture) : noms.
func skipped_stops() -> Array:
	var out: Array = []
	for it in items:
		if str(it.kind) in ["works", "flood_closed"]:
			for n in it.get("skipped", []): if not n in out: out.append(n)
	return out

func announce(s: MissionSession) -> void:
	for it in items:
		match str(it.kind):
			"works":
				s.event.emit("works", "Travaux : section fermée, itinéraire de déviation tracé par le poste")
			"flood_closed":
				s.event.emit("flood", "Inondation : section fermée, itinéraire de détour tracé par le poste")
			"flood":
				s.event.emit("flood", "Voie submergée signalée : marche à vue à 10 km/h dans la zone")
			"leaves":
				pass
		if str(it.kind) in ["works", "flood_closed"]:
			for n in it.get("skipped", []): s.event.emit("skip", "Arrêt non desservi : " + str(n))
	if not of_kind("leaves").is_empty():
		s.event.emit("leaves", "Feuilles mortes : rail glissant, sablage disponible")

## Évolution des événements ; retourne un motif d'échec ou "".
func tick(s: MissionSession, dt: float) -> String:
	if s.phys.wheel_slide: slide_s += dt
	if s.phys.wheel_slip: slip_s += dt
	for it in items:
		var kind := str(it.kind)
		match kind:
			"flood":
				if train_in(s, it.get("segments", [])):
					if str(it.state) == "pending":
						it.state = "inside"; s.event.emit("flood", "Entrée en zone inondée : 10 km/h")
					if s.phys.speed > FLOOD_LIMIT_MS + 0.3: flood_overspeed_s += dt
					if s.phys.speed > FLOOD_FAIL_MS: return "Zone inondée traversée au-delà de la marche à vue"
				elif str(it.state) == "inside":
					it.state = "done"; flags["flood_crossed"] = true
					s.event.emit("flood", "Zone inondée franchie")
			"obstacle":
				if str(it.state) == "cleared": continue
				var d := s.dist_to_point(str(it.edge), float(it.offset), OBSTACLE_SIGHT_M + 50.0)
				if str(it.state) == "pending" and d != INF and d >= 0.0 and d <= OBSTACLE_SIGHT_M:
					it.state = "seen"; s.event.emit("obstacle", "Véhicule engageant la voie à %d m : marche à vue, arrêt" % roundi(d))
				if str(it.state) in ["pending", "seen"]:
					if d != INF and d <= 1.0 and d > -s.phys.profile.length_m:
						return "Collision avec un véhicule sur la voie"
					if str(it.state) == "seen" and s.phys.speed < 0.1 and d > 0.0 and d <= OBSTACLE_STOP_M:
						it.t = float(it.t) + dt
						if float(it.t) >= float(it.get("clear_after_s", 20.0)):
							it.state = "cleared"; flags["obstacle_cleared"] = true
							s.event.emit("obstacle", "Voie dégagée : reprise de la marche")
			"pantograph_fault":
				if str(it.state) == "pending":
					var d := s.dist_to_point(str(it.edge), float(it.offset), 400.0)
					if d != INF and d <= 0.0:
						it.state = "fault"; it.t = 0.0
						s.pantograph_up = false
						s.event.emit("pantograph", "Défaut pantographe : abaissement d'urgence — arrêtez la rame pour réarmer")
				elif str(it.state) == "fault":
					if s.power_mode == "overhead": s.pantograph_up = false
					if s.phys.speed < 0.1:
						it.t = float(it.t) + dt
						if float(it.t) >= FAULT_REARM_S:
							it.state = "rearmed"
							s.event.emit("pantograph", "Pantographe réarmé : relevez-le (alimentation LAC)")
					else: it.t = 0.0
				elif str(it.state) == "rearmed" and s.pantograph_up and s.power_ok:
					it.state = "done"; flags["fault_cleared"] = true
					s.event.emit("pantograph", "Pantographe relevé : tension rétablie")
			"power_cut":
				if str(it.state) == "pending" and train_in(s, it.get("segments", [])):
					it.state = "active"; it.t = 0.0
					s.event.emit("power", "Coupure de sous-station : ligne aérienne hors tension")
				elif str(it.state) == "active":
					it.t = float(it.t) + dt
					if float(it.t) >= float(it.get("duration_s", 75.0)):
						it.state = "done"; flags["power_restored"] = true
						s.event.emit("power", "Sous-station réalimentée : tension rétablie")
	return ""

## Données de rendu : [{kind, segments | edge+offset, state}].
func render_items() -> Array:
	var out: Array = []
	for it in items:
		if str(it.kind) == "obstacle" and str(it.state) == "cleared": continue
		out.append(it)
	return out
