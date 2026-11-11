class_name MapView
extends Control
## Carte du réseau : tracés, stations, position et sens de marche de la rame.

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
	var tp := _to_screen(Vector2(t.x, t.z))
	# sens de marche : flèche partant du nez de la rame
	var ah: Array = session.locate_behind(-40.0)
	var a3 := view.pos3(ah[0], ah[1])
	var dv := _to_screen(Vector2(a3.x, a3.z)) - tp
	if dv.length() > 0.2:
		dv = dv.normalized()
		draw_colored_polygon(PackedVector2Array([tp + dv * 16.0, tp + dv * 5.0 + dv.orthogonal() * 6.0, tp + dv * 5.0 - dv.orthogonal() * 6.0]), Color(1.0, 0.45, 0.3))
	draw_circle(tp, 7.0, Color.RED)
	if session.direction < 0 and not session.net.edge_info[session.edge_id].raw:
		draw_string(ThemeDB.fallback_font, tp + Vector2(10, -8), "contre-sens", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1.0, 0.6, 0.4))
