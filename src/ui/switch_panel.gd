class_name SwitchPanel
extends Control
## Plan du réseau (mode libre) : tracés, stations, rame (avec son sens de marche), itinéraire prévu et
## tous les aiguillages du réseau, y compris ceux des communications de voies (un par nœud et par côté).
## Clic sur un aiguillage : le sélectionne ; ses branches s'affichent à droite et se choisissent
## explicitement (refus si la rame est sur la zone d'aiguillage). Clic droit : branche suivante.
## Liste à droite filtrable : aiguillages sur l'itinéraire, proches de la rame, ou tous.
## Molette : zoom ; glisser : déplacement.

signal closed
signal message(text: String)

var session: FreeSession
var view: LineView
var lines: Array = []          # [PackedVector2Array, Color]
var switch_pos: Dictionary = {} # clé (TrackGraph.skey) -> Vector2 (m)
var switch_of: Dictionary = {}  # clé -> [nœud, côté]
var switch_name: Dictionary = {} # clé -> libellé court
var selected := ""              # clé de l'aiguillage sélectionné
var filter := "route"           # "route" | "near" | "all"
var sel_box: VBoxContainer
var filter_btns: Dictionary = {}
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
	help.text = "Cliquez un aiguillage sur le plan pour le sélectionner puis choisissez sa branche (clic droit : branche suivante). Vert : branche active ; rouge : occupé. Molette : zoom, glisser : déplacer."
	help.add_theme_font_size_override("font_size", 16); side.add_child(help)
	sel_box = VBoxContainer.new(); side.add_child(sel_box)
	var frow := HBoxContainer.new(); side.add_child(frow)
	for f in [["route", "Itinéraire"], ["near", "Proches"], ["all", "Tous"]]:
		var fb := Button.new(); fb.text = f[1]; fb.toggle_mode = true; fb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		fb.custom_minimum_size = Vector2(0, 44)
		fb.pressed.connect(func(): filter = f[0]; refresh())
		frow.add_child(fb); filter_btns[f[0]] = fb
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
	var xnames := {}
	for c in s.net.meta.get("crossovers", []):
		for n in c.nodes: xnames[n] = "communication " + str(c.station)
	var idx := 0
	for sw in s.net.graph.switches():
		var key := TrackGraph.skey(sw[0], sw[1])
		var first: Array = s.net.graph.choices(sw[0], sw[1])[0]
		var p3 := v.pos3(first[0], 0.0 if first[1] > 0 else s.net.graph.edges[first[0]].length)
		switch_pos[key] = Vector2(p3.x, p3.z)
		switch_of[key] = sw
		idx += 1
		switch_name[key] = "Aiguillage %d%s" % [idx, (" (" + xnames[sw[0]] + ")") if xnames.has(sw[0]) else ""]
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

## Itinéraire prévu : [[arête, sens]...] depuis la rame, dans son sens de marche, selon les aiguillages.
func route_ahead(max_m: float = 6000.0) -> Array:
	var g := session.net.graph
	var out: Array = [[session.edge_id, session.direction]]
	var seen := {session.edge_id: true}
	var e: String = session.edge_id
	var r: int = session.direction
	var d: float = g.edges[e].length - session.offset if r > 0 else session.offset
	while d < max_m:
		var st := g.next_step(e, r)
		if st.is_empty() or seen.has(st[0]): break
		e = st[0]; r = st[1]; seen[e] = true
		out.append([e, r])
		d += g.edges[e].length
	return out

## Aiguillages pris en pointe sur l'itinéraire : [[clé, distance (m)]...].
func switches_on_route() -> Array:
	var g := session.net.graph
	var out: Array = []
	var d: float = 0.0
	var ra := route_ahead()
	for i in ra.size():
		var e: String = ra[i][0]; var r: int = ra[i][1]
		var L: float = g.edges[e].length
		d += (L - session.offset if r > 0 else session.offset) if i == 0 else L
		var x := g.exit_of(e, r)
		var key := TrackGraph.skey(x[0], x[1])
		if switch_of.has(key): out.append([key, d])
	return out

func _tram_pos() -> Vector2:
	var t3 := view.pos3(session.edge_id, session.offset)
	return Vector2(t3.x, t3.z)

## Première station rencontrée en partant d'une arête dans un sens (pour nommer une branche).
func branch_label(edge_id: String, dir: int = 1) -> String:
	var g := session.net.graph
	var e := edge_id
	var r := dir
	var seen := {}
	var via := ""
	for i in 12:
		if e == "" or seen.has(e): break
		seen[e] = true
		if session.net.edge_info[e].raw and via == "": via = "communication, "
		if _st_by_edge.has(e):
			var st: Dictionary = _st_by_edge[e][0]
			var ls := _lines_of(e)
			return "%svers %s%s%s" % [via, st.name, ("  (ligne " + "/".join(ls) + ")") if ls.size() > 0 else "", "" if r > 0 else " à contre-sens"]
		var x := g.exit_of(e, r)
		var ch := g.choices(x[0], x[1])
		if ch.is_empty(): return via + "heurtoir"
		if ch.size() != 1: break
		e = ch[0][0]; r = ch[0][1]
	return via + "vers " + edge_id
func _lines_of(e: String) -> Array:
	for raw in session.net.meta.edges:
		if raw.id == e: return raw.get("lines", [])
	return []

func refresh() -> void:
	for c in list_box.get_children(): c.queue_free()
	for c in sel_box.get_children(): c.queue_free()
	for f in filter_btns: filter_btns[f].button_pressed = f == filter
	var g := session.net.graph
	# aiguillage sélectionné : branches à choisir explicitement
	if selected != "" and switch_of.has(selected):
		var sw: Array = switch_of[selected]
		var lbl := Label.new(); lbl.add_theme_font_size_override("font_size", 20)
		lbl.text = switch_name[selected] + ("  — OCCUPÉ" if g.switch_occupied(sw[0]) else "")
		sel_box.add_child(lbl)
		var ch := g.choices(sw[0], sw[1])
		var cur := g.active_branch(sw[0], sw[1])
		for k in ch.size():
			var b := Button.new()
			b.text = ("● " if k == cur else "○ ") + branch_label(ch[k][0], ch[k][1])
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.custom_minimum_size = Vector2(0, 52)
			b.pressed.connect(func(): _throw(sw[0], k, sw[1]))
			sel_box.add_child(b)
	# liste filtrée
	var items: Array = []
	if filter == "route":
		items = switches_on_route()
	else:
		var tp := _tram_pos()
		for key in switch_pos:
			var dd: float = tp.distance_to(switch_pos[key])
			if filter == "all" or dd < 1500.0: items.append([key, dd])
		items.sort_custom(func(a, b): return a[1] < b[1])
	var shown := 0
	for it in items:
		var key: String = it[0]
		var sw: Array = switch_of[key]
		var ch := g.choices(sw[0], sw[1])
		var cur := g.active_branch(sw[0], sw[1])
		var b := Button.new()
		b.text = "%s%s — %d m\n   %s" % ["▶ " if key == selected else "", switch_name[key], int(it[1]), branch_label(ch[cur][0], ch[cur][1])]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(0, 56)
		if g.switch_occupied(sw[0]): b.modulate = Color(1.0, 0.6, 0.6)
		b.pressed.connect(func(): _select(key, true))
		list_box.add_child(b)
		shown += 1
		if shown >= 30: break
	if shown == 0:
		var l := Label.new(); l.text = "Aucun aiguillage sur l'itinéraire." if filter == "route" else "Aucun aiguillage proche."; list_box.add_child(l)
	canvas.queue_redraw()

func _select(key: String, center: bool = false) -> void:
	selected = key
	if center and switch_pos.has(key):
		var c := (lo + hi) * 0.5
		pan = -(switch_pos[key] - c) * _scale()
	refresh()

func _throw(node: String, branch: int, side: int = 1) -> void:
	if session.select_branch(node, branch, side):
		var ch: Array = session.net.graph.choices(node, side)[branch]
		message.emit("Aiguillage manœuvré : " + branch_label(ch[0], ch[1]))
	else:
		message.emit("Aiguillage occupé : manœuvre refusée")
	refresh()
func _draw_plan() -> void:
	var route := {}
	for e in route_ahead(): route[e[0]] = true
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
	var g := session.net.graph
	for key in switch_pos:
		var sw: Array = switch_of[key]
		var c := _to_screen(switch_pos[key]) + (Vector2(0, 0) if sw[1] > 0 else Vector2(5, 5))
		var ch := g.choices(sw[0], sw[1])
		var cur := g.active_branch(sw[0], sw[1])
		# branches : inactive en gris, active en vert le long des premiers mètres
		for k in ch.size():
			var e: String = ch[k][0]
			var L: float = g.edges[e].length
			var a := view.pos3(e, minf(30.0, L) if ch[k][1] > 0 else maxf(0.0, L - 30.0))
			canvas.draw_line(c, _to_screen(Vector2(a.x, a.z)), Color(0.2, 0.95, 0.4) if k == cur else Color(0.45, 0.45, 0.5), 5.0 if k == cur else 2.0)
		var occ := g.switch_occupied(sw[0])
		var r := 9.0 if key != selected else 12.0
		canvas.draw_circle(c, r, Color(0.9, 0.2, 0.2) if occ else Color(0.15, 0.6, 1.0))
		canvas.draw_arc(c, r + 2.0, 0, TAU, 20, Color(1.0, 0.85, 0.1) if key == selected else Color.WHITE, 3.0 if key == selected else 2.0)
		if key == selected:
			canvas.draw_string(font, c + Vector2(14, 18), switch_name[key], HORIZONTAL_ALIGNMENT_LEFT, -1, 16)
	# rame : position et flèche du sens de marche
	var t3 := view.pos3(session.edge_id, session.offset)
	var tp := _to_screen(Vector2(t3.x, t3.z))
	var ah: Array = session.locate_behind(-25.0)
	var a3 := view.pos3(ah[0], ah[1])
	var dv := _to_screen(Vector2(a3.x, a3.z)) - tp
	if dv.length() > 0.5:
		dv = dv.normalized()
		canvas.draw_colored_polygon(PackedVector2Array([tp + dv * 22.0, tp + dv * 8.0 + dv.orthogonal() * 8.0, tp + dv * 8.0 - dv.orthogonal() * 8.0]), Color(1.0, 0.3, 0.2))
	canvas.draw_circle(tp, 9.0, Color(0.95, 0.15, 0.15))
	canvas.draw_string(font, tp + Vector2(12, -10), "Tram" + ("" if session.direction > 0 else " (contre-sens)"), HORIZONTAL_ALIGNMENT_LEFT, -1, 18)

func _plan_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed:
		if ev.button_index == MOUSE_BUTTON_WHEEL_UP: zoom *= 1.15; canvas.queue_redraw(); return
		if ev.button_index == MOUSE_BUTTON_WHEEL_DOWN: zoom = maxf(0.5, zoom / 1.15); canvas.queue_redraw(); return
		if ev.button_index == MOUSE_BUTTON_LEFT:
			var best := _pick(ev.position)
			if best != "":
				_select(best)
			else:
				_dragging = true
		if ev.button_index == MOUSE_BUTTON_RIGHT:
			var best := _pick(ev.position)
			if best != "":
				selected = best
				var sw: Array = switch_of[best]
				var n := session.net.graph.choices(sw[0], sw[1]).size()
				_throw(sw[0], (session.net.graph.active_branch(sw[0], sw[1]) + 1) % n, sw[1])
	elif ev is InputEventMouseButton and not ev.pressed:
		_dragging = false
	elif ev is InputEventMouseMotion and _dragging:
		pan += ev.relative; canvas.queue_redraw()
	elif ev is InputEventScreenDrag:
		pan += ev.relative; canvas.queue_redraw()
	elif ev is InputEventMagnifyGesture:
		zoom = maxf(0.5, zoom * ev.factor); canvas.queue_redraw()

func _pick(pos: Vector2) -> String:
	var best := ""; var bd := 28.0
	for key in switch_pos:
		var d: float = _to_screen(switch_pos[key]).distance_to(pos)
		if d < bd: bd = d; best = key
	return best
