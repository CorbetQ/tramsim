class_name RoadTraffic
extends RefCounted
## Voitures sur voies routières définies, croisant la plateforme tram à un passage.
## Feu routier relié à la voie : rouge quand une rame approche ou occupe le croisement.

const CAR_LEN := 4.5
const GAP := 2.0
const ACCEL := 2.0
const DECEL := 4.0
const V_ROAD := 13.9  # 50 km/h

class Car:
	var pos := 0.0
	var speed := 0.0
	var lane := 0

var lanes: Array[Dictionary] = []
var cars: Array[Car] = []
var enabled := true
var light_red: Array[bool] = []
var _since_spawn: Array[float] = []

func _init(road_defs: Array) -> void:
	for r in road_defs:
		lanes.append(r)
		light_red.append(false)
		_since_spawn.append(1e9)

func set_enabled(on: bool) -> void:
	enabled = on
	if not on:
		cars.clear()

## tram : {edge, offset, length_m, edge_len(Callable id->float), prev_edge(Callable)}
func light_for(lane: Dictionary, tram_edge: String, tram_offset: float, tram_len: float, dist_before: Callable) -> bool:
	# rouge si le nez de la rame est à moins de light_range avant le croisement, ou si elle le recouvre
	var d: float = dist_before.call(tram_edge, tram_offset, lane.edge, float(lane.edge_offset))
	if d == INF:
		return false
	return d < float(lane.get("light_range_m", 150.0)) and d > -(tram_len + 5.0)

func step(dt: float, tram_edge: String, tram_offset: float, tram_len: float, dist_before: Callable) -> void:
	if not enabled:
		return
	for li in lanes.size():
		var lane: Dictionary = lanes[li]
		light_red[li] = light_for(lane, tram_edge, tram_offset, tram_len, dist_before)
		_since_spawn[li] += dt
		if _since_spawn[li] >= float(lane.get("spawn_every_s", 10.0)):
			var last := _last_in_lane(li)
			if last == null or last.pos > CAR_LEN + GAP + 1.0:
				var c := Car.new(); c.lane = li; c.speed = V_ROAD * 0.6
				cars.append(c); _since_spawn[li] = 0.0
	# ordre de tête en premier
	cars.sort_custom(func(a: Car, b: Car) -> bool: return a.pos > b.pos)
	var leader: Array = []
	leader.resize(lanes.size())
	for c in cars:
		var lane: Dictionary = lanes[c.lane]
		var target := V_ROAD
		var stop_line: float = float(lane.cross_at) - 5.0
		var must_stop: bool = light_red[c.lane] and c.pos < stop_line + 1.5
		var limit_pos := INF
		if must_stop:
			limit_pos = stop_line
		var ld: Car = leader[c.lane]
		if ld != null:
			limit_pos = minf(limit_pos, ld.pos - CAR_LEN - GAP)
		if limit_pos < INF:
			var room := limit_pos - c.pos
			var v_safe := sqrt(maxf(0.0, 2.0 * DECEL * 0.7 * room)) if room > 0.0 else 0.0
			target = minf(target, v_safe)
		if c.speed < target:
			c.speed = minf(target, c.speed + ACCEL * dt)
		else:
			c.speed = maxf(target, c.speed - DECEL * dt)
		c.pos += c.speed * dt
		if limit_pos < INF and c.pos > limit_pos:
			c.pos = limit_pos
			c.speed = 0.0
		leader[c.lane] = c
	cars = cars.filter(func(c: Car) -> bool: return c.pos < float(lanes[c.lane].length))

## Vrai si une voiture se trouve sur l'emprise du croisement tram (±2,5 m).
func car_in_crossing(lane_idx: int) -> bool:
	var at: float = float(lanes[lane_idx].cross_at)
	for c in cars:
		if c.lane == lane_idx and c.pos > at - 2.5 and c.pos - CAR_LEN < at + 2.5:
			return true
	return false

func _last_in_lane(li: int) -> Car:
	var best: Car = null
	for c in cars:
		if c.lane == li and (best == null or c.pos < best.pos):
			best = c
	return best
