class_name MissionCatalog
extends RefCounted
## Catalogue des missions par ville (res://data/missions/<ville>.json, généré par
## tools/build_missions.gd). Les missions se jouent sur le réseau complet de la ville
## (res://data/free/<ville>.json) ; l'itinéraire est tracé par le poste d'aiguillage.

const DIR := "res://data/missions/"
const TYPES := ["service", "night", "crowd", "depot_exit", "depot_return", "turnback", "deviation", "flood", "leaves", "pantograph_fault", "power_cut", "obstacle"]

static var _cache: Dictionary = {}

static func _load(city_id: String) -> Dictionary:
	if _cache.has(city_id): return _cache[city_id]
	var out := {}
	if FileAccess.file_exists(DIR + city_id + ".json"):
		var d: Variant = CityDataStore.document(DIR + city_id + ".json")
		if typeof(d) == TYPE_DICTIONARY: out = d
	_cache[city_id] = out
	return out

## Missions disponibles pour une ville : {id, type, title, description, line, difficulty (1-3),
## duration_min, start_station, conditions} (+ données internes utilisées par create_session).
static func for_city(city_id: String) -> Array:
	var out: Array = []
	for m in _load(city_id).get("missions", []):
		var it: Dictionary = m.duplicate(true)
		it["city"] = city_id
		out.append(it)
	return out

## Session prête : réseau complet chargé, itinéraire tracé, événements configurés.
static func create_session(mission: Dictionary, vehicle: VehicleProfile, prepared: NetworkLoader = null) -> MissionSession:
	var city := str(mission.get("city", ""))
	var path := str(mission.get("network", "res://data/free/%s.json" % city))
	var net := prepared if prepared != null else NetworkLoader.new()
	var errs := PackedStringArray() if prepared != null else net.load_file(path)
	if not errs.is_empty() and net.graph.edges.is_empty():
		push_error("MissionCatalog : réseau illisible " + path)
		return null
	NormalRouting.initialize(net)
	var st: Dictionary = mission.start
	var sched: Array[float] = []
	for t in mission.get("departures", []): sched.append(float(t))
	var s := MissionSession.new(net, vehicle, str(st.edge), float(st.offset), sched, int(mission.get("passengers", 40)))
	s.direction = int(st.dir)
	s.route_dir = [s.direction]
	s.traffic.set_enabled(false)
	s.mission = mission
	var stops: Array = []
	for item in mission.get("stops", []):
		var station: Dictionary = net.stations[int(item.station)].duplicate(true)
		for k in item:
			if k != "station": station[k] = item[k]
		stops.append(station)
	s.stops = stops
	if mission.has("target"): s.target = mission.target
	s.scorer.max_late_s = float(mission.get("late_tolerance_s", MissionScorer.MAX_LATE_S))
	s.events = MissionEvents.new(mission.get("events", []), float(mission.get("adhesion", MissionEvents.DRY_ADHESION)))
	if not s.events.of_kind("leaves").is_empty(): s.sand_left_s = MissionSession.SAND_RESERVE_S
	var il := Interlocking.new(net, s.train_id)
	for e in mission.get("closed", []): il.closed[str(e)] = true
	il.strict = bool(mission.get("strict", false))
	il.allow_service = bool(mission.get("service_tracks", false))
	s.interlocking = il
	if not il.setup(s, mission.get("waypoints", [])):
		push_error("MissionCatalog : itinéraire impossible pour " + str(mission.get("id", "")))
	if bool(mission.get("pantograph_down", false)):
		s.pantograph_up = false
		s.power_mode = "overhead"
		s._update_power("")
	s.events.announce(s)
	return s

## Points de voie de la mission (pour le rendu ou l'aperçu du plan).
static func stations_of(mission: Dictionary) -> Array:
	return mission.get("stops", []).map(func(it): return int(it.station))
