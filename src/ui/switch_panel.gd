class_name SwitchPanel
extends Control
## Plan du réseau (mode libre) : tracés, stations, rame, itinéraire prévu et aiguillages cliquables.
## Clic sur un aiguillage : passe à la branche suivante (refusé si la zone est occupée).
## Liste à droite : prochains aiguillages sur l'itinéraire, avec un bouton par direction.
## Molette : zoom ; glisser : déplacement.

signal closed
signal message(text: String)

var session: FreeSession
var view: LineView
var lines: Array = []          # [PackedVector2Array, Color]
var switch_pos: Dictionary = {} # nœud -> Vector2 (m)
var lo := Vector2(INF, INF)
var hi := Vector2(-INF, -INF)
var zoom := 1.0
var pan := Vector2.ZERO
var list_box: VBoxContainer
var canvas: Control
var _dragging := false
var _st_by_edge: Dictionary = {}

func setup(s: FreeSession, v: LineView) -> void:
	session = s; view = v
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new(); bg.color = Color(0.06, 0.08, 0.11, 0.94); bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var row := HBoxContainer.new(); row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 16; row.offset_top = 16; row.offset_right = -16; row.offset_bottom = -16
	add_child(row)
	canvas = Control.new(); canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL; canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	canvas.clip_contents = true
	canvas.draw.connect(_draw_plan)
	canvas.gui_input.connect(_plan_input)
	row.add_child(canvas)
	var side := VBoxContainer.new(); side.custom_minimum_size = Vector2(360, 0)
	row.add_child(side)
	var t := Label.new(); t.text = "Aiguillages"; t.add_theme_font_size_override("font_size", 30); side.add_child(t)
	var help := Label.new(); help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.text = "Cliquez un aiguillage sur le plan pour changer de branche, ou choisissez la direction ci-dessous. Molette : zoom, glisser : déplacer."
	help.add_theme_font_size_override("font_size", 16); side.add_child(help)
	var sc := ScrollContainer.new(); sc.size_flags_vertical = Control.SIZE_EXPAND_FILL; side.add_child(sc)
	list_box = VBoxContainer.new(); list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL; sc.add_child(list_box)
	var close := Button.new(); close.text = "Fermer (A)"; close.custom_minimum_size = Vector2(0, 64)
	close.pressed.connect(func(): closed.emit()); side.add_child(close)
	# géométrie du plan
	for id in s.net.graph.edges:
		var poly := PackedVector2Array()
		var L: float = s.net.graph.edges[id].length
		var pts: PackedVector2Array = s.net.edge_info[id].pts
		var n := clampi(pts.size(), 2, 24)
		for k in n:
			var p := v.pos3(id, L * k / (n - 1))
			poly.append(Vector2(p.x, p.z))
			lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.z)); hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.z))
		lines.append([poly, id])
	for node in s.net.graph.out_edges:
		if s.net.graph.out_edges[node].size() > 1:
			var p3 := v.pos3(s.net.graph.out_edges[node][0], 0.0)
			switch_pos[node] = Vector2(p3.x, p3.z)
	for st in s.net.stations:
		if not _st_by_edge.has(st.edge): _st_by_edge[st.edge] = []
		_st_by_edge[st.edge].append(st)
	refresh()

func _scale() -> float:
	var span := (hi - lo); span = Vector2(maxf(span.x, 1.0), maxf(span.y, 1.0))
	return minf((canvas.size.x - 40.0) / span.x, (canvas.size.y - 40.0) / span.y) * zoom

func _to_screen(p: Vector2) -> Vector2:
	var c := (lo + hi) * 0.5
	return canvas.size * 0.5 + (p - c) * _scale() + pan

## Itinéraire prévu : arêtes suivies depuis la rame selon l'état actuel des aiguillages.
func route_ahead(max_m: float = 6000.0) -> Array:
	var out: Array = [session.edge_id]
	var e: String = session.edge_id
	var d: float = session.net.graph.edges[e].length - session.offset
	while d < max_m:
		e = session.net.graph.next_edge(e)
		if e == "" or e in out: break
		out.append(e)
		d += session.net.graph.edges[e].length
	return out

## Première station rencontrée en partant d'une arête (pour nommer une branche).
func branch_label(edge_id: String) -> String:
	var e := edge_id
	var seen := {}
	for i in 12:
		if e == "" or seen.has(e): break
		seen[e] = true
		if _st_by_edge.has(e):
			var st: Dictionary = _st_by_edge[e][0]
			return "vers %s%s" % [st.name, ("  (ligne " + "/".join(_lines_of(e)) + ")") if _lines_of(e).size() > 0 else ""]
		e = session.net.graph.next_edge(e) if session.net.graph.out_edges.get(session.net.graph.edges[e].to_node, []).size() == 1 else ""
	return "vers " + edge_id

func _lines_of(e: String) -> Array:
	for raw in session.net.meta.edges:
		if raw.id == e: return raw.get("lines", [])
	return []

func refresh() -> void:
	for c in list_box.get_children(): c.queue_free()
	var route := route_ahead()
	var count := 0
	for e in route:
		var node: String = session.net.graph.edges[e].to_node
		var outs: Array = session.net.graph.out_edges.get(node, [])
		if outs.size() < 2: continue
		count += 1
		var lbl := Label.new(); lbl.text = "Aiguillage %d" % count; lbl.add_theme_font_size_override("font_size", 20)
		list_box.add_child(lbl)
		var cur: int = int(session.net.graph.switch_state.get(node, 0)) % outs.size()
		for k in outs.size():
			var b := Button.new()
			b.text = ("● " if k == cur else "○ ") + branch_label(outs[k])
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.custom_minimum_size = Vector2(0, 52)
			b.pressed.connect(func(): _throw(node, k))
			list_box.add_child(b)
		if count >= 6: break
	if count == 0:
		var l := Label.new(); l.text = "Aucun aiguillage sur l'itinéraire."; list_box.add_child(l)
	canvas.queue_redraw()

func _throw(node: String, branch: int) -> void:
	if session.select_branch(node, branch):
		message.emit("Aiguillage manœuvré : " + branch_label(session.net.graph.out_edges[node][branch]))
	else:
		message.emit("Aiguillage occupé : manœuvre refusée")
	refresh()

func _draw_plan() -> void:
	var route := {}
	for e in route_ahead(): route[e] = true
	for item in lines:
		var poly: PackedVector2Array = item[0]
		var sp := PackedVector2Array()
		for p in poly: sp.append(_to_screen(p))
		var on: bool = route.has(item[1])
		canvas.draw_polyline(sp, Color(1.0, 0.8, 0.2) if on else Color(0.75, 0.78, 0.82), 4.0 if on else 2.0, true)
	for st in session.net.stations:
		var p3 := view.pos3(st.edge, float(st.offset))
		canvas.draw_circle(_to_screen(Vector2(p3.x, p3.z)), 3.0, Color(0.95, 0.95, 0.95))
	var font := ThemeDB.fallback_font
	for node in switch_pos:
		var c := _to_screen(switch_pos[node])
		var outs: Array = session.net.graph.out_edges[node]
		var cur: int = int(session.net.graph.switch_state.get(node, 0)) % outs.size()
		# branche active : trait vert le long des premiers mètres
		var e: String = outs[cur]
		var a := view.pos3(e, minf(40.0, session.net.graph.edges[e].length))
		canvas.draw_line(c, _to_screen(Vector2(a.x, a.z)), Color(0.2, 0.95, 0.4), 5.0)
		canvas.draw_circle(c, 9.0, Color(0.15, 0.6, 1.0))
		canvas.draw_arc(c, 11.0, 0, TAU, 20, Color.WHITE, 2.0)
	var t3 := view.pos3(session.edge_id, session.offset)
	canvas.draw_circle(_to_screen(Vector2(t3.x, t3.z)), 9.0, Color(0.95, 0.15, 0.15))
	canvas.draw_string(font, _to_screen(Vector2(t3.x, t3.z)) + Vector2(12, -10), "Tram", HORIZONTAL_ALIGNMENT_LEFT, -1, 18)

func _plan_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed:
		if ev.button_index == MOUSE_BUTTON_WHEEL_UP: zoom *= 1.15; canvas.queue_redraw(); return
		if ev.button_index == MOUSE_BUTTON_WHEEL_DOWN: zoom = maxf(0.5, zoom / 1.15); canvas.queue_redraw(); return
		if ev.button_index == MOUSE_BUTTON_LEFT:
			var best := ""; var bd := 28.0
			for node in switch_pos:
				var d: float = _to_screen(switch_pos[node]).distance_to(ev.position)
				if d < bd: bd = d; best = node
			if best != "":
				var outs: Array = session.net.graph.out_edges[best]
				_throw(best, (int(session.net.graph.switch_state.get(best, 0)) + 1) % outs.size())
			else:
				_dragging = true
	elif ev is InputEventMouseButton and not ev.pressed:
		_dragging = false
	elif ev is InputEventMouseMotion and _dragging:
		pan += ev.relative; canvas.queue_redraw()
	elif ev is InputEventScreenDrag:
		pan += ev.relative; canvas.queue_redraw()
	elif ev is InputEventMagnifyGesture:
		zoom = maxf(0.5, zoom * ev.factor); canvas.queue_redraw()
