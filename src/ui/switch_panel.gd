class_name NetworkPlan
extends Control
## Poste d'aiguillage (mode libre) : plan du réseau coloré par ligne GTFS, noms des arrêts au zoom, rame
## (flèche du sens de marche), itinéraire prévu et aiguillages à manœuvrer mis en évidence (numérotés).
## Sélection : clic / toucher sur un aiguillage du plan ou de la liste → bulle avec les branches illustrées
## (flèche + destination) ; état libre / sur l'itinéraire / occupé (verrouillé). Clic droit : branche suivante.
## Outils : suivre la rame, recentrer, zoom, recherche d'arrêt. Raccourcis : A ouvre/ferme (main.gd),
## Tab / Maj+Tab aiguillage suivant / précédent, 1–3 choix de branche, F suivre la rame, Échap fermer.
## Cibles tactiles ≥ 48 px ; molette / pincer : zoom ; glisser : déplacement.

signal closed
signal message(text: String)

var session: MissionSession
var view: LineView
var lines: Array = []            # [PackedVector2Array (m), arête, [couleurs]]
var switch_pos: Dictionary = {}  # clé (TrackGraph.skey) -> Vector2 (m)
var switch_of: Dictionary = {}   # clé -> [nœud, côté]
var switch_name: Dictionary = {} # clé -> libellé court
var switch_dirs: Dictionary = {} # clé -> [Vector2 direction de chaque branche (m)]
var selected := ""               # clé de l'aiguillage sélectionné
var filter := "route"            # "route" | "near" | "all"
var follow := true               # suivre la rame
var lo := Vector2(INF, INF)
var hi := Vector2(-INF, -INF)
var zoom := 1.0
var pan := Vector2.ZERO
var canvas: Control
var list_box: VBoxContainer
var popover: PanelContainer
var search: LineEdit
var results: VBoxContainer
var follow_btn: Button
var speed_lbl: Label
var filter_btns: Dictionary = {}
var rows: Dictionary = {}        # clé -> [Button, Label nom, Label détail, PanelContainer état, Label état]
var _row_keys: Array = []
var _st_names: Array = []        # [nom, Vector2 (m)] uniques
var _flash := Vector2.INF        # arrêt recherché (m)
var _flash_t := 0.0
var _dragging := false
var _drag_moved := 0.0
var _press_pos := Vector2.ZERO
var _t := 0.0
var gestures := MapGestures.new()
var compact := false
var _map_panel: Control
var _side_panel: Control

const LABEL_SCALE := 0.06        # px par mètre à partir duquel les noms d'arrêts s'affichent
const PICK_R := 30.0             # rayon de sélection (px) : cible tactile ~60 px

static var _st_cache: Dictionary = {}     # id réseau -> {arête: [stations]}
static var _color_cache: Dictionary = {}  # ville -> {ligne: Color}

# ----------------------------------------------------------------------------------------------- outils statiques

static func _stations_by_edge(s: MissionSession) -> Dictionary:
	var k := s.net.get_instance_id()
	if not _st_cache.has(k):
		var d := {}
		for st in s.net.stations:
			if not d.has(st.edge): d[st.edge] = []
			d[st.edge].append(st)
		_st_cache[k] = d
	return _st_cache[k]

## Itinéraire prévu depuis la rame : [[arête, sens]...], selon la position des aiguillages.
static func route_of(s: MissionSession, max_m: float = 6000.0) -> Array:
	var g := s.net.graph
	var out: Array = [[s.edge_id, s.direction]]
	var seen := {s.edge_id: true}
	var e: String = s.edge_id
	var r: int = s.direction
	var d: float = g.edges[e].length - s.offset if r > 0 else s.offset
	while d < max_m:
		var st := g.next_step(e, r)
		if st.is_empty() or seen.has(st[0]): break
		e = st[0]; r = st[1]; seen[e] = true
		out.append([e, r])
		d += g.edges[e].length
	return out

## Aiguillages pris en pointe devant la rame : [[nœud, côté, distance (m)]...].
static func upcoming(s: MissionSession, max_m: float = 6000.0) -> Array:
	if s == null: return []
	var g := s.net.graph
	var out: Array = []
	var d := 0.0
	var ra := route_of(s, max_m)
	for i in ra.size():
		var e: String = ra[i][0]; var r: int = ra[i][1]
		var L: float = g.edges[e].length
		d += (L - s.offset if r > 0 else s.offset) if i == 0 else L
		var x := g.exit_of(e, r)
		if g.choices(x[0], x[1]).size() > 1: out.append([x[0], x[1], d])
	return out

## Destination d'une branche : première station rencontrée (ligne, contre-sens, communication).
static func label_for(s: MissionSession, edge_id: String, dir: int = 1) -> String:
	var g := s.net.graph
	var sbe := _stations_by_edge(s)
	var e := edge_id
	var r := dir
	var seen := {}
	var via := ""
	for i in 12:
		if e == "" or seen.has(e): break
		seen[e] = true
		var info: Dictionary = s.net.edge_info[e]
		if str(info.get("service", "")) != "" and via == "": via = "voie de service, "
		elif info.raw and via == "": via = "communication, "
		for depot in s.net.meta.get("depots", []):
			if e in depot.get("tracks", []): return "vers " + str(depot.name)
		if sbe.has(e):
			var st: Dictionary = sbe[e][0]
			var ls: Array = st.get("lines", [])
			return "%svers %s%s%s" % [via, st.name, ("  (ligne " + "/".join(ls) + ")") if ls.size() > 0 else "", "" if r > 0 or s.net.meta.get("geometry_kind", "") == "physical" else " à contre-sens"]
		var x := g.exit_of(e, r)
		var ch := g.choices(x[0], x[1])
		if ch.is_empty(): return via + "heurtoir"
		if ch.size() != 1: break
		e = ch[0][0]; r = ch[0][1]
	return via + "fin de voie"

## Destination de la branche active d'un aiguillage.
static func branch_text(s: MissionSession, node: String, side: int) -> String:
	var ch := s.net.graph.choices(node, side)
	if ch.is_empty(): return ""
	var b: Array = ch[s.net.graph.active_branch(node, side)]
	return label_for(s, b[0], b[1])

static func line_colors(meta: Dictionary) -> Dictionary:
	var city := str(meta.get("city", ""))
	if not _color_cache.has(city):
		var d := {}
		for e in NetworkRegistry.entries():
			if str(e.city) == city:
				d[str(e.line)] = UiTheme.color_of(e.color if e.has("color") else Catalogue.meta_of(str(e.path)).get("color", ""), UiTheme.INFO)
		_color_cache[city] = d
	return _color_cache[city]

# ----------------------------------------------------------------------------------------------- construction

func setup(s: MissionSession, v: LineView) -> void:
	session = s; view = v
	compact = get_viewport_rect().size.x < 1100.0 or get_viewport_rect().size.y < 620.0
	name = "NetworkPlan"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new(); bg.color = Color(0.02, 0.03, 0.05, 0.6); bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE; add_child(bg)
	var row := HBoxContainer.new(); row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var safe := UiLayout.safe_insets(self)
	row.offset_left = 14 + safe.x; row.offset_top = 14 + safe.y; row.offset_right = -14 - safe.z; row.offset_bottom = -14 - safe.w
	row.add_theme_constant_override("separation", 12); add_child(row)
	# --- plan
	var mp := PanelContainer.new(); mp.add_theme_stylebox_override("panel", UiTheme.box(Color(0.05, 0.065, 0.085, 0.95), 18, 0, UiTheme.BORDER, 1))
	mp.size_flags_horizontal = Control.SIZE_EXPAND_FILL; row.add_child(mp); _map_panel = mp
	canvas = Control.new(); canvas.clip_contents = true; canvas.name = "plan"
	canvas.draw.connect(_draw_plan); canvas.gui_input.connect(_plan_input)
	mp.add_child(canvas)
	_build_toolbar()
	# --- colonne latérale
	var side := UiTheme.panel(Color(0.07, 0.085, 0.11, 0.96), 18, 16); side.custom_minimum_size = Vector2(300 if compact else 380, 0); row.add_child(side)
	_side_panel = side; side.visible = not compact
	if compact: side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sv := VBoxContainer.new(); sv.add_theme_constant_override("separation", 10); side.add_child(sv)
	var head := HBoxContainer.new(); head.add_theme_constant_override("separation", 10); sv.add_child(head)
	if compact:
		var back := UiTheme.button("Carte", "map", "normal", Vector2(0, 52))
		back.pressed.connect(func(): side.hide(); mp.show())
		head.add_child(back)
	head.add_child(UiTheme.icon_rect("switch", 28, UiTheme.ACCENT))
	var hv := VBoxContainer.new(); hv.add_theme_constant_override("separation", -4); hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL; head.add_child(hv)
	hv.add_child(UiTheme.label_("Plan du réseau", UiTheme.SIZE_H2, UiTheme.TEXT, true))
	speed_lbl = UiTheme.label_("", UiTheme.SIZE_CAPTION, UiTheme.MUTED); hv.add_child(speed_lbl)
	var close := UiTheme.button("", "close", "ghost", Vector2(52, 52)); close.tooltip_text = "Fermer (M / A / Échap)"; close.name = "close"
	close.pressed.connect(func(): closed.emit()); head.add_child(close)
	var seg := PanelContainer.new(); seg.add_theme_stylebox_override("panel", UiTheme.box(Color(0, 0, 0, 0.3), 14, 4)); sv.add_child(seg)
	var frow := HBoxContainer.new(); frow.add_theme_constant_override("separation", 4); seg.add_child(frow)
	var grp := ButtonGroup.new()
	for f in [["route", "Itinéraire"], ["near", "Proches"], ["all", "Tous"]]:
		var fb := UiTheme.button(f[1], "", "chip", Vector2(0, 46)); fb.toggle_mode = true; fb.button_group = grp
		fb.size_flags_horizontal = Control.SIZE_EXPAND_FILL; fb.name = "filter_" + f[0]
		fb.pressed.connect(func(): filter = f[0]; refresh())
		frow.add_child(fb); filter_btns[f[0]] = fb
	var sc := TouchScroll.new(); sc.size_flags_vertical = Control.SIZE_EXPAND_FILL; sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sv.add_child(sc)
	list_box = VBoxContainer.new(); list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL; list_box.add_theme_constant_override("separation", 6)
	sc.add_child(list_box)
	var keys := HFlowContainer.new(); keys.add_theme_constant_override("h_separation", 6); keys.add_theme_constant_override("v_separation", 4); sv.add_child(keys)
	for k in [["Tab", "suivant"], ["1–3", "branche"], ["F", "suivre"], ["A", "fermer"]]:
		keys.add_child(UiTheme.keycap(k[0])); keys.add_child(UiTheme.label_(k[1], UiTheme.SIZE_CAPTION, UiTheme.MUTED))
	_build_geometry()
	var up := upcoming(session)
	if not up.is_empty(): selected = TrackGraph.skey(up[0][0], up[0][1])
	set_follow(true)
	refresh()

func _tool(icon_name: String, tip: String, cb: Callable) -> Button:
	var b := UiTheme.button("", icon_name, "normal", Vector2(52, 52)); b.tooltip_text = tip; b.focus_mode = Control.FOCUS_NONE
	b.name = "tool_" + icon_name
	b.add_theme_stylebox_override("normal", UiTheme.box(Color(0.1, 0.12, 0.15, 0.92), 14, 12, UiTheme.BORDER, 1))
	b.pressed.connect(cb)
	return b

func _build_toolbar() -> void:
	# recherche d'arrêt (haut gauche)
	var sb := VBoxContainer.new(); sb.position = Vector2(14, 14); sb.add_theme_constant_override("separation", 4); canvas.add_child(sb)
	search = LineEdit.new(); search.placeholder_text = "Rechercher un arrêt…"; search.custom_minimum_size = Vector2(230 if compact else 330, 52)
	search.clear_button_enabled = true; search.name = "search"
	search.add_theme_stylebox_override("normal", UiTheme.box(Color(0.1, 0.12, 0.15, 0.94), 14, 14, UiTheme.BORDER, 1))
	search.text_changed.connect(_on_search)
	search.text_submitted.connect(func(_t):
		if results.get_child_count() > 0: (results.get_child(0) as Button).pressed.emit())
	sb.add_child(search)
	results = VBoxContainer.new(); results.add_theme_constant_override("separation", 2); sb.add_child(results)
	# outils (haut droite)
	var tb := BoxContainer.new(); tb.vertical = not compact
	tb.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT if compact else Control.PRESET_TOP_RIGHT); tb.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	tb.offset_right = -14; tb.offset_top = -66 if compact else 14; tb.offset_left = -66
	if compact: tb.offset_bottom = -14; tb.grow_vertical = Control.GROW_DIRECTION_BEGIN
	tb.add_theme_constant_override("separation", 8); canvas.add_child(tb)
	if compact:
		tb.add_child(_tool("switch", "Liste des aiguillages", func(): _side_panel.show(); _map_panel.hide()))
		var close_map := _tool("close", "Fermer", func(): closed.emit())
		close_map.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT); close_map.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		close_map.offset_left = -66; close_map.offset_right = -14; close_map.offset_top = 14; canvas.add_child(close_map)
	follow_btn = _tool("follow", "Suivre la rame (F)", func(): set_follow(not follow)); follow_btn.toggle_mode = true; tb.add_child(follow_btn)
	tb.add_child(_tool("recenter", "Vue d'ensemble", recenter))
	tb.add_child(_tool("plus", "Zoom avant", func(): _zoom_at(canvas.size * 0.5, 1.4)))
	tb.add_child(_tool("minus", "Zoom arrière", func(): _zoom_at(canvas.size * 0.5, 1.0 / 1.4)))
	# légende (bas gauche)
	var lg := HFlowContainer.new(); lg.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE); lg.grow_vertical = Control.GROW_DIRECTION_BEGIN
	lg.offset_left = 14; lg.offset_bottom = -12; lg.offset_right = -14; lg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lg.add_theme_constant_override("h_separation", 6); canvas.add_child(lg)
	lg.visible = not compact
	for it in [[Color.WHITE, "Libre"], [UiTheme.HIGHLIGHT, "À manœuvrer (itinéraire)"], [UiTheme.DANGER, "Occupé : verrouillé"], [UiTheme.ACCENT, "Branche active"]]:
		var p := PanelContainer.new(); p.add_theme_stylebox_override("panel", UiTheme.box(Color(0.08, 0.1, 0.13, 0.9), 12, 10)); p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var h := HBoxContainer.new(); h.add_theme_constant_override("separation", 6); p.add_child(h)
		var dot := Label.new(); dot.text = "●"; dot.add_theme_color_override("font_color", it[0]); dot.add_theme_font_size_override("font_size", 14); h.add_child(dot)
		h.add_child(UiTheme.label_(it[1], UiTheme.SIZE_CAPTION, UiTheme.TEXT))
		lg.add_child(p)
	# bulle de l'aiguillage sélectionné
	popover = PanelContainer.new(); popover.name = "popover"; popover.visible = false
	var ps := UiTheme.box(Color(0.09, 0.11, 0.14, 0.97), 16, 14, Color(UiTheme.ACCENT, 0.6), 2)
	ps.shadow_color = Color(0, 0, 0, 0.45); ps.shadow_size = 12
	popover.add_theme_stylebox_override("panel", ps)
	canvas.add_child(popover)

func _build_geometry() -> void:
	var s := session; var v := view
	var lc := line_colors(s.net.meta)
	var raw_lines := {}
	for raw in s.net.meta.edges: raw_lines[raw.id] = raw.get("lines", [])
	for id in s.net.graph.edges:
		var poly := PackedVector2Array()
		var L: float = s.net.graph.edges[id].length
		var pts: PackedVector2Array = s.net.edge_info[id].pts
		var n := clampi(pts.size(), 2, 24)
		for k in n:
			var p := v.pos3(id, L * k / (n - 1))
			poly.append(Vector2(p.x, p.z))
			lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.z)); hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.z))
		var cols: Array = []
		for l in raw_lines.get(id, []):
			if lc.has(str(l)): cols.append(lc[str(l)])
		if cols.is_empty() and not s.net.edge_info[id].raw:
			cols.append(UiTheme.color_of(s.net.meta.get("color", ""), Color(0.7, 0.74, 0.8)))
		lines.append([poly, id, cols])
	var xnames := {}
	for c in s.net.meta.get("crossovers", []):
		for n in c.nodes: xnames[n] = "communication " + str(c.station)
	var g := s.net.graph
	var idx := 0
	for sw in g.switches():
		var key := TrackGraph.skey(sw[0], sw[1])
		var ch: Array = g.choices(sw[0], sw[1])
		var first: Array = ch[0]
		var p3 := v.pos3(first[0], 0.0 if first[1] > 0 else g.edges[first[0]].length)
		var c := Vector2(p3.x, p3.z)
		switch_pos[key] = c
		switch_of[key] = sw
		var dirs: Array = []
		for b in ch:
			var L: float = g.edges[b[0]].length
			var a := v.pos3(b[0], minf(30.0, L) if b[1] > 0 else maxf(0.0, L - 30.0))
			dirs.append((Vector2(a.x, a.z) - c).normalized())
		switch_dirs[key] = dirs
		idx += 1
		switch_name[key] = "Aiguillage %d%s" % [idx, (" (" + xnames[sw[0]] + ")") if xnames.has(sw[0]) else ""]
	var seen := {}
	for st in s.net.stations:
		if seen.has(st.name): continue
		seen[st.name] = true
		var p3 := v.pos3(st.edge, float(st.offset))
		_st_names.append([str(st.name), Vector2(p3.x, p3.z)])

	for depot in session.net.meta.get("depots", []):
		var p: Array = depot.position
		_st_names.append([str(depot.name), Vector2(float(p[0]), float(p[1]))])

# ----------------------------------------------------------------------------------------------- géométrie écran

func _scale() -> float:
	var span := (hi - lo); span = Vector2(maxf(span.x, 1.0), maxf(span.y, 1.0))
	return minf((canvas.size.x - 80.0) / span.x, (canvas.size.y - 80.0) / span.y) * zoom

func _to_screen(p: Vector2) -> Vector2:
	var c := (lo + hi) * 0.5
	return canvas.size * 0.5 + (p - c) * _scale() + pan

func _center_on(p: Vector2) -> void:
	var c := (lo + hi) * 0.5
	pan = -(p - c) * _scale()

func _zoom_at(at: Vector2, f: float) -> void:
	var c := (lo + hi) * 0.5
	var world := (at - canvas.size * 0.5 - pan) / _scale() + c
	zoom = clampf(zoom * f, 0.5, 400.0)
	if follow: return canvas.queue_redraw()
	pan = at - canvas.size * 0.5 - (world - c) * _scale()
	canvas.queue_redraw()

func set_follow(on: bool) -> void:
	follow = on
	if follow_btn: follow_btn.set_pressed_no_signal(on)
	if on and zoom < 4.0: zoom = 4.0
	canvas.queue_redraw()

func recenter() -> void:
	set_follow(false); zoom = 1.0; pan = Vector2.ZERO; canvas.queue_redraw()

func _tram_pos() -> Vector2:
	var t3 := view.pos3(session.edge_id, session.offset)
	return Vector2(t3.x, t3.z)

# ----------------------------------------------------------------------------------------------- compatibilité

func route_ahead(max_m: float = 6000.0) -> Array:
	return route_of(session, max_m)

## Aiguillages pris en pointe sur l'itinéraire : [[clé, distance (m)]...].
func switches_on_route() -> Array:
	var out: Array = []
	for u in upcoming(session):
		var key := TrackGraph.skey(u[0], u[1])
		if switch_of.has(key): out.append([key, u[2]])
	return out

func branch_label(edge_id: String, dir: int = 1) -> String:
	return label_for(session, edge_id, dir)

# ----------------------------------------------------------------------------------------------- liste et bulle

func _items() -> Array:
	if filter == "route": return switches_on_route()
	var items: Array = []
	var tp := _tram_pos()
	for key in switch_pos:
		var dd: float = tp.distance_to(switch_pos[key])
		if filter == "all" or dd < 1500.0: items.append([key, dd])
	items.sort_custom(func(a, b): return a[1] < b[1])
	return items.slice(0, 40)

func _state(key: String) -> int:  # 0 libre, 1 sur l'itinéraire, 2 occupé (verrouillé)
	var sw: Array = switch_of[key]
	if session.net.graph.switch_occupied(sw[0]): return 2
	for it in switches_on_route():
		if it[0] == key: return 1
	return 0

func _state_style(st: int) -> Array:  # [couleur, libellé]
	return [[Color(1, 1, 1, 0.75), "Libre"], [UiTheme.HIGHLIGHT, "Itinéraire"], [UiTheme.DANGER, "Occupé"]][st]

func refresh() -> void:
	for f in filter_btns: filter_btns[f].set_pressed_no_signal(f == filter)
	for c in list_box.get_children(): c.queue_free()
	rows.clear(); _row_keys.clear()
	var items := _items()
	var route_keys := {}
	var ri := 0
	for it in switches_on_route():
		ri += 1; route_keys[it[0]] = ri
	for it in items:
		var key: String = it[0]
		var b := Button.new(); b.custom_minimum_size = Vector2(0, 66); b.focus_mode = Control.FOCUS_NONE
		b.set_meta("key", key); b.name = "row_" + str(_row_keys.size())
		var h := HBoxContainer.new(); h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); h.offset_left = 10; h.offset_right = -10
		h.add_theme_constant_override("separation", 10); h.mouse_filter = Control.MOUSE_FILTER_IGNORE; b.add_child(h)
		var num := UiTheme.label_(str(route_keys.get(key, "")) if route_keys.has(key) else "", UiTheme.SIZE_SMALL, Color.BLACK, true)
		num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; num.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		num.custom_minimum_size = Vector2(30, 30); num.size_flags_vertical = Control.SIZE_SHRINK_CENTER; h.add_child(num)
		var v := VBoxContainer.new(); v.size_flags_horizontal = Control.SIZE_EXPAND_FILL; v.alignment = BoxContainer.ALIGNMENT_CENTER
		v.add_theme_constant_override("separation", -2); v.mouse_filter = Control.MOUSE_FILTER_IGNORE; h.add_child(v)
		var nl := UiTheme.label_("", UiTheme.SIZE_SMALL, UiTheme.TEXT, true); nl.clip_text = true; v.add_child(nl)
		var dl := UiTheme.label_("", UiTheme.SIZE_CAPTION, UiTheme.MUTED); dl.clip_text = true; dl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		v.add_child(dl)
		var chip := PanelContainer.new(); chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER; chip.mouse_filter = Control.MOUSE_FILTER_IGNORE; h.add_child(chip)
		var cl := UiTheme.label_("", UiTheme.SIZE_CAPTION, Color.BLACK, true); chip.add_child(cl)
		b.pressed.connect(func(): _select(key, true))
		list_box.add_child(b)
		rows[key] = [b, nl, dl, chip, cl, num, it[1]]
		_row_keys.append(key)
	if items.is_empty():
		var l := UiTheme.label_("Aucun aiguillage sur l'itinéraire." if filter == "route" else "Aucun aiguillage proche.", UiTheme.SIZE_SMALL, UiTheme.MUTED)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; list_box.add_child(l)
	_update_rows(items)
	_build_popover()
	canvas.queue_redraw()

func _update_rows(items: Array) -> void:
	for it in items:
		var key: String = it[0]
		if not rows.has(key): continue
		var R: Array = rows[key]
		var st := _state(key)
		var ss := _state_style(st)
		(R[1] as Label).text = switch_name[key]
		(R[2] as Label).text = "%s · %s" % [("%d m" % int(it[1])) if it[1] < 10000 else "%.1f km" % (it[1] / 1000.0), branch_text(session, switch_of[key][0], switch_of[key][1])]
		(R[3] as PanelContainer).add_theme_stylebox_override("panel", UiTheme.box(ss[0], 10, 8))
		(R[4] as Label).text = ss[1]
		(R[5] as Label).add_theme_stylebox_override("normal", UiTheme.box(UiTheme.HIGHLIGHT if st == 1 else Color(1, 1, 1, 0.12), 15, 4) if (R[5] as Label).text != "" else StyleBoxEmpty.new())
		var b: Button = R[0]
		var sel: bool = key == selected
		b.add_theme_stylebox_override("normal", UiTheme.box(Color(UiTheme.ACCENT, 0.18) if sel else Color(1, 1, 1, 0.04), 12, 10,
			Color(UiTheme.ACCENT, 0.9) if sel else UiTheme.BORDER, 2 if sel else 1))
		b.add_theme_stylebox_override("hover", UiTheme.box(Color(1, 1, 1, 0.1), 12, 10, Color(UiTheme.ACCENT, 0.5), 1))
		b.add_theme_stylebox_override("pressed", UiTheme.box(Color(UiTheme.ACCENT, 0.3), 12, 10))

func _build_popover() -> void:
	for c in popover.get_children(): c.queue_free()
	popover.visible = selected != "" and switch_of.has(selected)
	if not popover.visible: return
	var g := session.net.graph
	var sw: Array = switch_of[selected]
	var st := _state(selected)
	var scroll := TouchScroll.new(); scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(300 if compact else 330, maxf(100.0, minf(360.0, canvas.size.y - 160.0)))
	popover.add_child(scroll)
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 8); v.custom_minimum_size = Vector2(280 if compact else 310, 0)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL; scroll.add_child(v)
	var h := HBoxContainer.new(); h.add_theme_constant_override("separation", 8); v.add_child(h)
	var tl := UiTheme.label_(switch_name[selected], UiTheme.SIZE_BODY, UiTheme.TEXT, true); tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tl.clip_text = true; tl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS; h.add_child(tl)
	var ss := _state_style(st)
	var chip := UiTheme.label_(("Occupé · verrouillé" if st == 2 else ss[1]), UiTheme.SIZE_CAPTION, Color.BLACK, true)
	chip.add_theme_stylebox_override("normal", UiTheme.box(ss[0], 10, 8)); chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER; h.add_child(chip)
	var x := UiTheme.button("", "close", "ghost", Vector2(48, 48)); x.tooltip_text = "Fermer la bulle"; x.focus_mode = Control.FOCUS_NONE
	x.pressed.connect(func(): selected = ""; refresh()); h.add_child(x)
	var ch := g.choices(sw[0], sw[1])
	var cur := g.active_branch(sw[0], sw[1])
	var dirs: Array = switch_dirs.get(selected, [])
	for k in ch.size():
		var b := Button.new(); b.custom_minimum_size = Vector2(0, 60); b.focus_mode = Control.FOCUS_NONE
		b.set_meta("branch", k); b.name = "branch_%d" % k; b.disabled = not session is FreeSession or (st == 2 and k != cur)
		b.tooltip_text = "Branche %d" % (k + 1)
		var active := k == cur
		b.add_theme_stylebox_override("normal", UiTheme.box(Color(UiTheme.ACCENT, 0.2) if active else Color(1, 1, 1, 0.05), 12, 10,
			UiTheme.ACCENT if active else UiTheme.BORDER, 2 if active else 1))
		b.add_theme_stylebox_override("hover", UiTheme.box(Color(1, 1, 1, 0.12), 12, 10, Color(UiTheme.ACCENT, 0.6), 1))
		var bh := HBoxContainer.new(); bh.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); bh.offset_left = 8; bh.offset_right = -10
		bh.add_theme_constant_override("separation", 10); bh.mouse_filter = Control.MOUSE_FILTER_IGNORE; b.add_child(bh)
		var kc := UiTheme.keycap(str(k + 1)); kc.size_flags_vertical = Control.SIZE_SHRINK_CENTER; bh.add_child(kc)
		var arrow := BranchArrow.new(); arrow.dirs = dirs; arrow.index = k; arrow.active = active; bh.add_child(arrow)
		var bl := UiTheme.label_(label_for(session, ch[k][0], ch[k][1]), UiTheme.SIZE_SMALL, UiTheme.TEXT, active)
		bl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; bl.size_flags_horizontal = Control.SIZE_EXPAND_FILL; bl.max_lines_visible = 2
		bl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER; bh.add_child(bl)
		if active: bh.add_child(UiTheme.icon_rect("check", 22, UiTheme.ACCENT))
		b.pressed.connect(func(): _throw(sw[0], k, sw[1]))
		v.add_child(b)
	if st == 2:
		var w := UiTheme.label_("Une rame occupe la zone d'aiguillage : manœuvre impossible.", UiTheme.SIZE_CAPTION, UiTheme.DANGER)
		w.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; v.add_child(w)
	popover.reset_size()
	_place_popover()
	UiTheme.fade_in(popover, 0.12)

func _place_popover() -> void:
	if not popover.visible or not switch_pos.has(selected): return
	var p := _to_screen(switch_pos[selected])
	var sz := popover.get_combined_minimum_size()
	var pos := p + Vector2(26, -sz.y * 0.5)
	if pos.x + sz.x > canvas.size.x - 76.0: pos.x = p.x - 26.0 - sz.x
	pos.x = clampf(pos.x, 8.0, maxf(8.0, canvas.size.x - sz.x - 76.0))
	pos.y = clampf(pos.y, 76.0, maxf(76.0, canvas.size.y - sz.y - 56.0))
	popover.position = pos

func _select(key: String, center: bool = false) -> void:
	selected = key
	if compact and _map_panel != null:
		_side_panel.hide(); _map_panel.show()
	if center and switch_pos.has(key):
		set_follow(false)
		if zoom < 3.0: zoom = 3.0
		_center_on(switch_pos[key])
	refresh()

## Aiguillage suivant / précédent de la liste affichée (Tab / Maj+Tab).
func select_next(step: int = 1) -> void:
	if _row_keys.is_empty(): return
	var i := _row_keys.find(selected)
	i = (i + step + _row_keys.size()) % _row_keys.size() if i >= 0 else 0
	_select(_row_keys[i], true)

## Choix de branche de l'aiguillage sélectionné (touches 1–3).
func choose(branch: int) -> void:
	if not switch_of.has(selected): return
	var sw: Array = switch_of[selected]
	if branch < session.net.graph.choices(sw[0], sw[1]).size(): _throw(sw[0], branch, sw[1])

func _throw(node: String, branch: int, side: int = 1) -> void:
	if not session is FreeSession:
		message.emit("Plan en lecture seule pendant une mission"); return
	if (session as FreeSession).select_branch(node, branch, side):
		var ch: Array = session.net.graph.choices(node, side)[branch]
		message.emit("Aiguillage manœuvré : " + label_for(session, ch[0], ch[1]))
	else:
		message.emit("Aiguillage occupé : manœuvre refusée")
	refresh()

# ----------------------------------------------------------------------------------------------- recherche

static func _fold(s: String) -> String:
	var t := s.to_lower()
	for p in [["é", "e"], ["è", "e"], ["ê", "e"], ["ë", "e"], ["à", "a"], ["â", "a"], ["î", "i"], ["ï", "i"], ["ô", "o"], ["ù", "u"], ["û", "u"], ["ü", "u"], ["ç", "c"], ["-", " "], ["'", " "]]:
		t = t.replace(p[0], p[1])
	return t

func _on_search(q: String) -> void:
	for c in results.get_children(): c.queue_free()
	var f := _fold(q.strip_edges())
	if f.length() < 2: return
	var n := 0
	for s in _st_names:
		if not f in _fold(s[0]): continue
		var b := UiTheme.button(s[0], "flag", "normal", Vector2(330, 48)); b.alignment = HORIZONTAL_ALIGNMENT_LEFT; b.focus_mode = Control.FOCUS_NONE
		b.add_theme_stylebox_override("normal", UiTheme.box(Color(0.1, 0.12, 0.15, 0.96), 12, 12, UiTheme.BORDER, 1))
		var p: Vector2 = s[1]
		b.pressed.connect(func(): goto_point(p); search.release_focus())
		results.add_child(b)
		n += 1
		if n >= 6: break

func goto_point(p: Vector2) -> void:
	set_follow(false)
	if _scale() < LABEL_SCALE * 1.5: zoom *= LABEL_SCALE * 1.5 / _scale()
	_center_on(p)
	_flash = p; _flash_t = 3.0
	for c in results.get_children(): c.queue_free()
	canvas.queue_redraw()

# ----------------------------------------------------------------------------------------------- boucle et entrées

func _process(dt: float) -> void:
	_t += dt
	_flash_t = maxf(0.0, _flash_t - dt)
	if speed_lbl: speed_lbl.text = ("Libre · " if session is FreeSession else "Mission · lecture seule · ") + "%d km/h · %s" % [roundi(session.phys.speed * 3.6), "prochain arrêt : " + str(session.next_station_ahead().get("name", "—"))]
	if Engine.get_process_frames() % 2 == 0: canvas.queue_redraw()
	if Engine.get_process_frames() % 30 == 0:
		var items := _items()
		var keys: Array = items.map(func(it): return it[0])
		if keys != _row_keys: refresh()
		else: _update_rows(items)

func _input(ev: InputEvent) -> void:
	if not is_visible_in_tree() or not (ev is InputEventKey) or not ev.pressed or ev.echo: return
	if get_viewport().gui_get_focus_owner() == search: return
	var k: int = ev.physical_keycode if ev.physical_keycode != 0 else ev.keycode
	match k:
		KEY_TAB: select_next(-1 if ev.shift_pressed else 1)
		KEY_1, KEY_KP_1: choose(0)
		KEY_2, KEY_KP_2: choose(1)
		KEY_3, KEY_KP_3: choose(2)
		KEY_F: set_follow(not follow)
		KEY_EQUAL, KEY_KP_ADD: _zoom_at(canvas.size * 0.5, 1.4)
		KEY_MINUS, KEY_KP_SUBTRACT: _zoom_at(canvas.size * 0.5, 1.0 / 1.4)
		_: return
	get_viewport().set_input_as_handled()

func _plan_input(ev: InputEvent) -> void:
	if ev is InputEventScreenTouch or ev is InputEventScreenDrag:
		var action := gestures.feed(ev)
		if action.has("zoom"):
			set_follow(false); _zoom_at(action.anchor, action.zoom)
		if action.has("pan"):
			set_follow(false); pan += action.pan; canvas.queue_redraw()
		if action.has("select"):
			var key := _pick(action.select)
			if key != "": _select(key)
			elif selected != "": selected = ""; refresh()
		canvas.accept_event()
		return
	# Godot synthétise également une souris depuis le doigt : ne pas l'appliquer deux fois.
	if (ev is InputEventMouseButton or ev is InputEventMouseMotion) and ev.device == -1: return
	if ev is InputEventMouseButton and ev.pressed:
		if ev.button_index == MOUSE_BUTTON_WHEEL_UP: _zoom_at(ev.position, 1.15); return
		if ev.button_index == MOUSE_BUTTON_WHEEL_DOWN: _zoom_at(ev.position, 1.0 / 1.15); return
		if ev.button_index == MOUSE_BUTTON_LEFT:
			if search.has_focus(): search.release_focus()
			_dragging = true; _drag_moved = 0.0; _press_pos = ev.position
		if ev.button_index == MOUSE_BUTTON_RIGHT:
			var best := _pick(ev.position)
			if best != "":
				selected = best
				var sw: Array = switch_of[best]
				var n := session.net.graph.choices(sw[0], sw[1]).size()
				_throw(sw[0], (session.net.graph.active_branch(sw[0], sw[1]) + 1) % n, sw[1])
	elif ev is InputEventMouseButton and not ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		_dragging = false
		if _drag_moved < 12.0:   # toucher / clic sans glisser : sélection
			var best := _pick(ev.position)
			if best != "": _select(best)
			elif selected != "": selected = ""; refresh()
	elif ev is InputEventMouseMotion and _dragging:
		_drag_moved += ev.relative.length()
		if _drag_moved >= 12.0:
			if follow: set_follow(false)
			pan += ev.relative; canvas.queue_redraw()
	elif ev is InputEventMagnifyGesture:
		_zoom_at(ev.position, ev.factor)
	elif ev is InputEventPanGesture:
		pan -= ev.delta * 8.0; canvas.queue_redraw()

func _pick(pos: Vector2) -> String:
	var best := ""; var bd := PICK_R
	for key in switch_pos:
		var d: float = _to_screen(switch_pos[key]).distance_to(pos)
		if d < bd: bd = d; best = key
	return best

## Position écran d'un aiguillage (tests, bulle).
func screen_pos(key: String) -> Vector2:
	return canvas.get_global_transform() * _to_screen(switch_pos[key])

# ----------------------------------------------------------------------------------------------- dessin

static func _offset_poly(sp: PackedVector2Array, d: float) -> PackedVector2Array:
	var out := PackedVector2Array(); out.resize(sp.size())
	for i in sp.size():
		var a := sp[maxi(i - 1, 0)]; var b := sp[mini(i + 1, sp.size() - 1)]
		var t := (b - a); var n := Vector2(-t.y, t.x).normalized() if t.length() > 0.001 else Vector2.ZERO
		out[i] = sp[i] + n * d
	return out

func _draw_plan() -> void:
	if follow: _center_on(_tram_pos())
	var font := UiTheme.font(); var bold := UiTheme.font(true)
	var sc := _scale()
	var g := session.net.graph
	# quadrillage discret (repère d'échelle)
	var step_m := 100.0
	while step_m * sc < 60.0: step_m *= 5.0 if str(step_m).begins_with("1") else 2.0
	var c0 := (lo + hi) * 0.5
	var origin := canvas.size * 0.5 + pan - c0 * sc
	var gx := fposmod(origin.x, step_m * sc); var gy := fposmod(origin.y, step_m * sc)
	var gc := Color(1, 1, 1, 0.035)
	var x := gx
	while x < canvas.size.x: canvas.draw_line(Vector2(x, 0), Vector2(x, canvas.size.y), gc, 1.0); x += step_m * sc
	var y := gy
	while y < canvas.size.y: canvas.draw_line(Vector2(0, y), Vector2(canvas.size.x, y), gc, 1.0); y += step_m * sc
	var rect := Rect2(Vector2(-60, -60), canvas.size + Vector2(120, 120))
	var route := {}
	for e in route_of(session): route[e[0]] = true
	var w := clampf(2.0 + sc * 8.0, 3.0, 9.0)
	var screens: Array = []
	for item in lines:
		var poly: PackedVector2Array = item[0]
		var sp := PackedVector2Array()
		var vis := false
		for p in poly:
			var q := _to_screen(p); sp.append(q)
			if not vis and rect.has_point(q): vis = true
		screens.append(sp if vis else PackedVector2Array())
		if vis and route.has(item[1]):
			canvas.draw_polyline(sp, Color(UiTheme.HIGHLIGHT, 0.35), w + 10.0, true)
	for i in lines.size():
		var sp: PackedVector2Array = screens[i]
		if sp.is_empty(): continue
		var cols: Array = lines[i][2]
		if cols.is_empty():
			canvas.draw_polyline(sp, Color(0.55, 0.6, 0.66), maxf(2.0, w * 0.45), true)
		elif cols.size() == 1:
			canvas.draw_polyline(sp, cols[0], w, true)
		else:   # tronc commun : un filet par ligne, côte à côte
			var ww := w / cols.size() + 0.6
			for k in cols.size():
				canvas.draw_polyline(_offset_poly(sp, (k - (cols.size() - 1) * 0.5) * ww), cols[k], ww, true)
		if route.has(lines[i][1]):
			canvas.draw_polyline(sp, Color(1, 1, 1, 0.75), 1.5, true)
	# arrêts et noms (au zoom)
	var names := sc >= LABEL_SCALE
	var taken: Array = []
	var dot_r := clampf(sc * 12.0, 2.5, 6.0)
	for st in _st_names:
		var q := _to_screen(st[1])
		if not rect.has_point(q): continue
		canvas.draw_circle(q, dot_r + 1.5, Color(0.05, 0.06, 0.08))
		canvas.draw_circle(q, dot_r, Color.WHITE)
		if names:
			var fs := UiTheme.SIZE_CAPTION
			var tsz := font.get_string_size(st[0], HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
			var r := Rect2(q + Vector2(dot_r + 5.0, -tsz.y * 0.5), tsz)
			var free_spot := true
			for t in taken:
				if (t as Rect2).intersects(r): free_spot = false; break
			if free_spot:
				taken.append(r)
				canvas.draw_string_outline(font, r.position + Vector2(0, tsz.y * 0.75), st[0], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 5, Color(0.04, 0.05, 0.07, 0.95))
				canvas.draw_string(font, r.position + Vector2(0, tsz.y * 0.75), st[0], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiTheme.TEXT)
	if _flash_t > 0.0 and _flash != Vector2.INF:
		var q := _to_screen(_flash)
		var a := fmod(_t * 1.5, 1.0)
		canvas.draw_arc(q, 10.0 + a * 30.0, 0, TAU, 32, Color(UiTheme.ACCENT, 1.0 - a), 3.0, true)
	# aiguillages
	var on_route := {}
	var n := 0
	for it in switches_on_route():
		n += 1; on_route[it[0]] = n
	var pulse := 0.5 + 0.5 * sin(_t * 5.0)
	for key in switch_pos:
		var c := _to_screen(switch_pos[key])
		if not rect.has_point(c): continue
		var sw: Array = switch_of[key]
		var cur := g.active_branch(sw[0], sw[1])
		var dirs: Array = switch_dirs[key]
		var occ := g.switch_occupied(sw[0])
		var sel: bool = key == selected
		var big: bool = sel or on_route.has(key)
		var bl := 22.0 if big else 14.0
		for k in dirs.size():
			var d: Vector2 = dirs[k]
			var col := UiTheme.ACCENT if k == cur else Color(0.5, 0.52, 0.58, 0.9)
			canvas.draw_line(c, c + d * bl * (1.3 if k == cur else 1.0), col, 5.0 if k == cur else 2.5, true)
		var r := 9.0 if big else 6.5
		var fill := UiTheme.DANGER if occ else (UiTheme.HIGHLIGHT if on_route.has(key) else Color.WHITE)
		if on_route.has(key) and not occ:
			canvas.draw_circle(c, r + 4.0 + pulse * 5.0, Color(UiTheme.HIGHLIGHT, 0.25 * (1.0 - pulse * 0.5)))
		if sel: canvas.draw_circle(c, r + 7.0, Color(UiTheme.ACCENT, 0.35))
		canvas.draw_circle(c, r + 2.0, Color(0.05, 0.06, 0.08))
		canvas.draw_circle(c, r, fill)
		if sel: canvas.draw_arc(c, r + 7.0, 0, TAU, 32, UiTheme.ACCENT, 2.5, true)
		if on_route.has(key):
			var s := str(on_route[key])
			var ts := bold.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 13)
			canvas.draw_string(bold, c + Vector2(-ts.x * 0.5, 4.5), s, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.BLACK)
		elif occ:
			canvas.draw_rect(Rect2(c + Vector2(-3, -1), Vector2(6, 5)), Color.WHITE)
			canvas.draw_arc(c + Vector2(0, -1), 2.5, PI, TAU, 8, Color.WHITE, 1.5)
	# rame : flèche orientée dans le sens de marche
	var tp := _to_screen(_tram_pos())
	var ah: Array = session.locate_behind(-25.0)
	var a3 := view.pos3(ah[0], ah[1])
	var dv := _to_screen(Vector2(a3.x, a3.z)) - tp
	dv = dv.normalized() if dv.length() > 0.5 else Vector2.UP
	var o := dv.orthogonal()
	var tri := PackedVector2Array([tp + dv * 20.0, tp - dv * 12.0 + o * 13.0, tp - dv * 5.0, tp - dv * 12.0 - o * 13.0])
	canvas.draw_circle(tp, 24.0, Color(UiTheme.DANGER, 0.18 + 0.1 * pulse))
	var outline := PackedVector2Array(tri); outline.append(tri[0])
	canvas.draw_colored_polygon(tri, UiTheme.DANGER)
	canvas.draw_polyline(outline, Color.WHITE, 2.5, true)
	var lab := "Rame" + ("" if session.direction > 0 or session.net.meta.get("geometry_kind", "") == "physical" else " · contre-sens")
	canvas.draw_string_outline(bold, tp + Vector2(22, -14), lab, HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.SIZE_SMALL, 5, Color(0.04, 0.05, 0.07))
	canvas.draw_string(bold, tp + Vector2(22, -14), lab, HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.SIZE_SMALL, Color.WHITE)
	# échelle
	var bar := step_m * sc
	var bp := Vector2(canvas.size.x - 80.0 - bar, canvas.size.y - 22.0)
	canvas.draw_line(bp, bp + Vector2(bar, 0), Color(1, 1, 1, 0.6), 2.0)
	canvas.draw_string(font, bp + Vector2(0, -6), ("%d m" % int(step_m)) if step_m < 1000.0 else ("%d km" % int(step_m / 1000.0)), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.6))
	_place_popover()


## Pictogramme d'une branche : tige d'approche puis départ vers la branche (angles accentués pour la lisibilité).
class BranchArrow extends Control:
	var dirs: Array = []
	var index := 0
	var active := false
	func _init() -> void:
		custom_minimum_size = Vector2(40, 44); mouse_filter = Control.MOUSE_FILTER_IGNORE
	## Angles répartis selon l'ordre gauche → droite des branches (les écarts réels sont trop faibles à l'échelle).
	func _ang(k: int, m: Vector2) -> float:
		if dirs.size() < 2: return 0.0
		var a := m.angle_to(dirs[k])
		var rank := 0
		for j in dirs.size():
			var b := m.angle_to(dirs[j])
			if b < a - 0.0001 or (absf(b - a) <= 0.0001 and j < k): rank += 1
		return lerpf(-0.75, 0.75, float(rank) / (dirs.size() - 1))
	func _draw() -> void:
		if dirs.is_empty(): return
		var m := Vector2.ZERO
		for d in dirs: m += d
		m = m.normalized() if m.length() > 0.01 else dirs[0]
		var base := Vector2(size.x * 0.5, size.y - 4.0)
		var mid := Vector2(size.x * 0.5, size.y * 0.55)
		for k in dirs.size():
			if k == index: continue
			var a := _ang(k, m)
			draw_line(mid, mid + Vector2(sin(a), -cos(a)) * 18.0, Color(1, 1, 1, 0.22), 3.0, true)
		var a := _ang(index, m)
		var col := UiTheme.ACCENT if active else Color.WHITE
		var tip := mid + Vector2(sin(a), -cos(a)) * 19.0
		draw_line(base, mid, col, 4.0, true)
		draw_line(mid, tip, col, 4.0, true)
		var dv := (tip - mid).normalized(); var o := dv.orthogonal()
		draw_colored_polygon(PackedVector2Array([tip + dv * 5.0, tip - dv * 4.0 + o * 6.0, tip - dv * 4.0 - o * 6.0]), col)
