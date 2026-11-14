class_name SignalPanel
extends PanelContainer
## Répétiteur de signalisation du HUD de conduite : prochain signal (aspect dessiné comme
## en voie : barre verticale, horizontale, oblique, point), sa nature et sa distance ;
## prochaine aiguille (direction, verrouillage) ; prochaine limitation de vitesse.
## Toucher / cliquer : affichage détaillé ou compact (cible ≥ 44 px).

const LAMP := Color(1.0, 0.95, 0.78)
const HEAD := Color("#121518")

var compact := false
var expanded := true
var session: MissionSession
var glyph: _Glyph
var sw_glyph: _Switch
var sign_: _Limit
var kind_l: Label
var aspect_l: Label
var dist_l: Label
var sw_l: Label
var lim_l: Label
var _rows: Array[Control] = []
var data: Dictionary = {}       # dernier état calculé (tests, captures)

func setup(s: MissionSession, compact_: bool) -> void:
	session = s; compact = compact_; expanded = not compact_
	name = "signal_panel"
	add_theme_stylebox_override("panel", UiTheme.box(Color(UiTheme.SURFACE, 0.84), 16, 12, UiTheme.BORDER, 1))
	mouse_filter = Control.MOUSE_FILTER_STOP
	tooltip_text = "Répétiteur de signalisation : toucher pour détailler / réduire"
	custom_minimum_size = Vector2(0, 64)
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 8); v.mouse_filter = Control.MOUSE_FILTER_IGNORE; add_child(v)
	var top := HBoxContainer.new(); top.add_theme_constant_override("separation", 12); top.mouse_filter = Control.MOUSE_FILTER_IGNORE; v.add_child(top)
	glyph = _Glyph.new(); glyph.custom_minimum_size = Vector2(38, 58) if compact else Vector2(50, 78); top.add_child(glyph)
	var tv := VBoxContainer.new(); tv.add_theme_constant_override("separation", -2); tv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL; tv.alignment = BoxContainer.ALIGNMENT_CENTER; top.add_child(tv)
	kind_l = UiTheme.label_("SIGNAL", UiTheme.SIZE_CAPTION, UiTheme.MUTED, true); tv.add_child(kind_l)
	aspect_l = UiTheme.label_("—", UiTheme.SIZE_BODY if compact else UiTheme.SIZE_H2, UiTheme.TEXT, true); tv.add_child(aspect_l)
	dist_l = UiTheme.label_("", UiTheme.SIZE_SMALL if compact else UiTheme.SIZE_BODY, UiTheme.TEXT); tv.add_child(dist_l)
	for l in [kind_l, aspect_l, dist_l]:
		l.clip_text = true; l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		l.custom_minimum_size = Vector2(120 if compact else 210, 0); l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if compact:   # rangée unique : signal, aiguille et limite côte à côte
		sw_glyph = _Switch.new(); sw_glyph.custom_minimum_size = Vector2(44, 44); sw_glyph.size_flags_vertical = Control.SIZE_SHRINK_CENTER; top.add_child(sw_glyph)
		sign_ = _Limit.new(); sign_.custom_minimum_size = Vector2(46, 46); sign_.size_flags_vertical = Control.SIZE_SHRINK_CENTER; top.add_child(sign_)
	var r2 := HBoxContainer.new(); r2.add_theme_constant_override("separation", 12); r2.mouse_filter = Control.MOUSE_FILTER_IGNORE; v.add_child(r2)
	if not compact:
		sw_glyph = _Switch.new(); sw_glyph.custom_minimum_size = Vector2(50, 46); r2.add_child(sw_glyph)
	sw_l = UiTheme.label_("", UiTheme.SIZE_SMALL, UiTheme.TEXT); sw_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sw_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER; sw_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; sw_l.custom_minimum_size = Vector2(190 if compact else 250, 0); r2.add_child(sw_l)
	var r3 := HBoxContainer.new(); r3.add_theme_constant_override("separation", 12); r3.mouse_filter = Control.MOUSE_FILTER_IGNORE; v.add_child(r3)
	if not compact:
		sign_ = _Limit.new(); sign_.custom_minimum_size = Vector2(50, 50); r3.add_child(sign_)
	lim_l = UiTheme.label_("", UiTheme.SIZE_SMALL, UiTheme.TEXT); lim_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lim_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER; lim_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; lim_l.custom_minimum_size = Vector2(190 if compact else 250, 0); r3.add_child(lim_l)
	_rows = [r2, r3]
	_apply_expanded()
	gui_input.connect(_on_input)

func _on_input(ev: InputEvent) -> void:
	if (ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT) or (ev is InputEventScreenTouch and ev.pressed):
		expanded = not expanded; _apply_expanded(); accept_event()

func _apply_expanded() -> void:
	for r in _rows: r.visible = expanded
	if compact:
		for l in [kind_l]: l.visible = expanded
	reset_size()

static func fmt_m(d: float) -> String:
	if d >= 1000.0: return "%.1f km" % (d / 1000.0)
	return "%d m" % roundi(maxf(d, 0.0))

## Calcule l'état du répétiteur pour une session (aussi utilisé par les tests).
static func compute(s: MissionSession, horizon: float = 1200.0) -> Dictionary:
	var sm := SignalModel.of(s.net)
	var g := s.net.graph
	var out := {"signal": {}, "switch": {}, "limit": {}, "current_limit": s.speed_limit()}
	var items := sm.ahead(s, horizon)
	for it in items:
		var sg: Dictionary = sm.list[int(it.i)]
		if out.signal.is_empty():
			out.signal = {"kind": str(sg.kind), "aspect": sm.aspect(int(it.i)), "distance": float(it.dist), "station": str(sg.get("station", ""))}
		if out.switch.is_empty() and sg.has("node"):
			var key := TrackGraph.skey(str(sg.node), int(sg.side))
			var owner := str(g.locks.get(key, ""))
			out.switch = {"distance": float(it.dist) + SignalModel.SETBACK_M, "direction": sm.branch_aspect(int(it.i)),
				"locked": owner != "", "mine": owner == s.train_id, "occupied": g.switch_occupied(str(sg.node)),
				"branches": g.choices(str(sg.node), int(sg.side)).size(), "labels": sg.get("labels", [])}
		if not out.signal.is_empty() and not out.switch.is_empty(): break
	# Fin d'autorisation du poste (point d'arrêt de fin d'itinéraire hors signal).
	if s.interlocking != null and not s.interlocking.authority.is_empty():
		var au: Dictionary = s.interlocking.authority
		var da := s.dist_to_point(str(au.edge), float(au.offset), horizon)
		if da != INF and da >= -0.5 and (out.signal.is_empty() or da < float(out.signal.distance) - 1.0):
			out.signal = {"kind": "authority", "aspect": "stop", "distance": da, "final": bool(au.get("final", false))}
	var r := s.next_restriction(800.0)
	if not r.is_empty(): out.limit = {"distance": float(r.distance), "limit": float(r.limit)}
	return out

func refresh() -> void:
	if session == null: return
	data = compute(session)
	var sig: Dictionary = data.signal
	if sig.is_empty():
		glyph.set_state("none", "")
		kind_l.text = "SIGNALISATION"; aspect_l.text = "Aucun signal"; dist_l.text = "dans les 1,2 km"
		aspect_l.add_theme_color_override("font_color", UiTheme.MUTED)
	else:
		var kind := str(sig.kind); var asp := str(sig.aspect)
		glyph.set_state(asp, kind)
		kind_l.text = SignalModel.kind_label(kind).to_upper() if kind != "authority" else ("POINT D'ARRÊT" if bool(sig.get("final", false)) else "FIN D'AUTORISATION")
		aspect_l.text = SignalModel.aspect_label(asp, kind)
		aspect_l.add_theme_color_override("font_color", UiTheme.DANGER if asp == "stop" else (UiTheme.WARNING if asp == "caution" else UiTheme.SUCCESS))
		dist_l.text = "à " + fmt_m(float(sig.distance))
	var sw: Dictionary = data.switch
	if sw.is_empty():
		sw_glyph.set_state("", [], false)
		sw_l.text = "Aucune aiguille devant"
		sw_l.add_theme_color_override("font_color", UiTheme.MUTED)
	else:
		var dir_txt: String = {"left": "à gauche", "right": "à droite", "go": "tout droit"}.get(str(sw.direction), str(sw.direction))
		var lock_txt := "verrouillée (poste)" if bool(sw.mine) else ("verrouillée (autre rame)" if bool(sw.locked) else ("occupée" if bool(sw.occupied) else "libre"))
		sw_glyph.set_state(str(sw.direction), sw.labels, bool(sw.locked))
		sw_l.text = ("Aiguille à %s · %s · %s" % [fmt_m(float(sw.distance)), dir_txt, lock_txt]) if not compact else ("Aiguille %s · %s" % [fmt_m(float(sw.distance)), dir_txt])
		sw_l.add_theme_color_override("font_color", UiTheme.TEXT)
	var cur := roundi(float(data.current_limit) * 3.6)
	if data.limit.is_empty():
		sign_.set_value(cur, false)
		lim_l.text = "Limite %d km/h" % cur
	else:
		sign_.set_value(roundi(float(data.limit.limit) * 3.6), true)
		lim_l.text = "%d km/h dans %s (actuelle %d)" % [roundi(float(data.limit.limit) * 3.6), fmt_m(float(data.limit.distance)), cur]

## Tête de signal dessinée : barre lunaire (verticale / horizontale / oblique), point.
class _Glyph extends Control:
	var aspect := "none"
	var kind := ""
	func _init() -> void: mouse_filter = Control.MOUSE_FILTER_IGNORE
	func set_state(a: String, k: String) -> void:
		if a == aspect and k == kind: return
		aspect = a; kind = k; queue_redraw()
	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size).grow(-2.0)
		if kind == "terminus": draw_rect(r, Color("#f2f2ee")); r = r.grow(-4.0)
		var sb := StyleBoxFlat.new(); sb.bg_color = SignalPanel.HEAD; sb.set_corner_radius_all(8)
		sb.border_color = Color(1, 1, 1, 0.25); sb.set_border_width_all(1)
		draw_style_box(sb, r)
		var c := r.get_center()
		var L := r.size.y * 0.58
		var w := maxf(r.size.x * 0.16, 4.0)
		if kind == "buffer" or aspect == "none":
			if kind == "buffer":
				for k in 4: draw_rect(Rect2(r.position + Vector2(4, r.size.y * 0.4), Vector2(r.size.x - 8, r.size.y * 0.2)).grow(0), Color("#c8202a") if k % 2 == 0 else Color.WHITE, false, 3.0)
			return
		if aspect == "caution":
			draw_circle(c + Vector2(0, r.size.y * 0.2), w * 0.9, SignalPanel.LAMP)
			draw_circle(c + Vector2(0, r.size.y * 0.2), w * 1.6, Color(SignalPanel.LAMP, 0.18))
			return
		var ang: float = {"go": 0.0, "stop": PI * 0.5, "left": -PI * 0.25, "right": PI * 0.25}.get(aspect, PI * 0.5)
		var d := Vector2(sin(ang), -cos(ang)) * L * 0.5
		var cc := c + Vector2(0, -r.size.y * 0.06)
		draw_line(cc - d, cc + d, Color(SignalPanel.LAMP, 0.2), w * 2.4, true)
		draw_line(cc - d, cc + d, SignalPanel.LAMP, w, true)

## Aiguille schématique : tronc et branches, branche active en surbrillance.
class _Switch extends Control:
	var dir := ""
	var labels: Array = []
	var locked := false
	func _init() -> void: mouse_filter = Control.MOUSE_FILTER_IGNORE
	func set_state(d: String, l: Array, lk: bool) -> void:
		if d == dir and l == labels and lk == locked: return
		dir = d; labels = l.duplicate(); locked = lk; queue_redraw()
	func _draw() -> void:
		var s := size
		var base := Vector2(s.x * 0.5, s.y - 4.0)
		var fork := Vector2(s.x * 0.5, s.y * 0.55)
		var dim := Color(1, 1, 1, 0.28)
		var on := UiTheme.HIGHLIGHT
		if labels.is_empty():
			draw_line(base, Vector2(s.x * 0.5, 4.0), dim, 4.0, true); return
		draw_line(base, fork, on, 5.0, true)
		var ends := {"left": Vector2(5.0, 5.0), "go": Vector2(s.x * 0.5, 3.0), "right": Vector2(s.x - 5.0, 5.0)}
		for k in labels:
			if str(k) != dir and ends.has(str(k)): draw_line(fork, ends[str(k)], dim, 4.0, true)
		if ends.has(dir): draw_line(fork, ends[dir], on, 5.0, true)
		if locked: draw_circle(Vector2(s.x - 7.0, s.y - 8.0), 6.0, UiTheme.SUCCESS)

## Panneau de limitation de vitesse (cercle rouge, valeur en km/h).
class _Limit extends Control:
	var value := 0
	var upcoming := false
	func _init() -> void: mouse_filter = Control.MOUSE_FILTER_IGNORE
	func set_value(v: int, up: bool) -> void:
		if v == value and up == upcoming: return
		value = v; upcoming = up; queue_redraw()
	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5 - 1.0
		draw_circle(c, r, Color("#d61f26"))
		draw_circle(c, r * 0.76, Color.WHITE)
		var f := UiTheme.font(true)
		var fs := int(r * (0.95 if value < 100 else 0.75))
		var t := str(value)
		var w := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(f, Vector2(c.x - w * 0.5, c.y + fs * 0.36), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("#111111"))
		if not upcoming: draw_arc(c, r + 0.5, 0, TAU, 32, Color(1, 1, 1, 0.0), 1.0)
