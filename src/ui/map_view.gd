class_name MapView
extends Control
## Carte schématique du réseau : arêtes dépliées, stations, position de la rame.

var session: MissionSession
var origins: Dictionary = {}

func setup(s: MissionSession, edge_origin: Dictionary) -> void:
	session = s
	origins = edge_origin

func _draw() -> void:
	if session == null or origins.is_empty():
		return
	var maxx := 1.0
	for id in origins:
		maxx = maxf(maxx, origins[id].x + session.net.graph.edges[id].length)
	var sc := (size.x - 40.0) / maxx
	var to2 := func(v: Vector3) -> Vector2: return Vector2(20.0 + v.x * sc, size.y * 0.5 + v.z * 4.0)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.6))
	for id in origins:
		var a: Vector2 = to2.call(origins[id])
		var b: Vector2 = to2.call(origins[id] + Vector3(session.net.graph.edges[id].length, 0, 0))
		draw_line(a, b, Color.WHITE, 3.0)
	for st in session.net.stations:
		draw_circle(to2.call(origins[st.edge] + Vector3(float(st.offset), 0, 0)), 6.0, Color.GOLD)
	draw_circle(to2.call(origins[session.edge_id] + Vector3(session.offset, 0, 0)), 8.0, Color.RED)
