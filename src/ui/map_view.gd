class_name MapView
extends Control
## Carte du réseau : tracés, stations, position de la rame.

var session: MissionSession
var view: LineView
var lines: Array = []    # [PackedVector2Array] en mètres (x, z)
var lo := Vector2(INF, INF)
var hi := Vector2(-INF, -INF)

func setup(s: MissionSession, v: LineView) -> void:
	session = s; view = v
	for id in s.net.graph.edges:
		var poly := PackedVector2Array()
		var L: float = s.net.graph.edges[id].length
		var n := 8
		for k in n + 1:
			var p := v.pos3(id, L * k / n)
			poly.append(Vector2(p.x, p.z))
			lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.z)); hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.z))
		lines.append(poly)

func _to_screen(p: Vector2) -> Vector2:
	var span := (hi - lo); span = Vector2(maxf(span.x, 1.0), maxf(span.y, 1.0))
	var sc := minf((size.x - 30.0) / span.x, (size.y - 30.0) / span.y)
	return Vector2(15, 15) + (p - lo) * sc

func _draw() -> void:
	if session == null: return
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.65))
	for poly in lines:
		var sp := PackedVector2Array()
		for p in poly: sp.append(_to_screen(p))
		draw_polyline(sp, Color.WHITE, 2.0)
	for st in session.stops:
		var p3 := view.pos3(st.edge, float(st.offset))
		draw_circle(_to_screen(Vector2(p3.x, p3.z)), 4.0, Color.GOLD)
	var t := view.pos3(session.edge_id, session.offset)
	draw_circle(_to_screen(Vector2(t.x, t.z)), 7.0, Color.RED)
