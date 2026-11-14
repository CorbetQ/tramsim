class_name ExploreMode
extends Control
## Mode « Explorer » : visite libre de la ville sélectionnée en caméra de survol (FreeCamera).
## Décor chargé par streaming autour de la caméra (CityScene, secteurs de voie), réglage de
## l'heure (DayNight), sauts vers les stations et monuments, vue du dessus, rames en
## circulation (AiTrams) sur le réseau complet. PC : ZQSD/WASD, clic droit + souris pour
## regarder, molette = altitude, Maj = accélérer, Espace / C = monter / descendre ; manette ;
## mobile : joystick virtuel, glisser pour regarder, pincer pour l'altitude. Échap : accueil.

signal exited

const AI_CAP_PC := 10
const AI_CAP_MOBILE := 5

var view: LineView
var net: NetworkLoader
var fly: FreeCamera
var ai: AiTrams
var city := ""
var hour := 12.0
var places: Array = []          # [{name, kind, pos}]
var gestures := MapGestures.new()
var _look_drag := false
var _list_layer: Control
var _hour_label: Label
var _hour_slider: HSlider
var _alt_label: Label
var joystick: _Joystick
var _dummy: MissionSession
var _ai_t := 0.0
var compact := false

func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	name = "explore"

## Construit la vue de la ville (réseau complet `path`) et l'interface.
func start(city_name: String, path: String, hour_: float, view_distance: float = 400.0, with_trams: bool = true) -> bool:
	city = city_name; hour = hour_
	net = NetworkLoader.new()
	if not net.load_file(path).is_empty() and net.graph.edges.is_empty(): return false
	NormalRouting.initialize(net)
	var first: String = net.meta.edges[0].id if net.meta.has("edges") else str(net.graph.edges.keys()[0])
	var vehicle := VehicleLibrary.default_for(net.meta)
	view = LineView.new(); view.view_distance = view_distance
	add_child(view); view.build(net, first, vehicle)
	view.tram.visible = false
	if view.headlight: view.headlight.visible = false
	view.set_hour(hour)
	if OS.has_feature("mobile") and view.city: view.city.radius = 450.0
	view.cam.current = true
	fly = FreeCamera.new(view.cam)
	fly.ground = func(p: Vector3) -> float: return view.ground_at(p)
	_collect_places()
	var start_at: Vector3 = places[0].pos if not places.is_empty() else view.pos3(first, 0.0)
	fly.yaw = 0.6
	fly.jump_to(start_at, 180.0, 110.0)
	if view.city: view.city.warm(fly.pos)
	if with_trams: _start_trams(vehicle)
	compact = UiLayout.compact(self)
	_build_ui()
	return true

func _start_trams(vehicle: VehicleProfile) -> void:
	var src := str(net.meta.get("source_id", net.meta.get("id", "")))
	if MissionCatalog.for_city(src).is_empty(): return
	# Rame fictive (non affichée, hors occupation) servant de référence au gestionnaire.
	var e := str(net.graph.edges.keys()[0])
	_dummy = MissionSession.new(net, vehicle, e, 0.0, [] as Array[float], 0)
	net.graph.release(e, _dummy.train_id)
	_dummy.train_id = "EXPLORER"
	ai = AiTrams.create(_dummy, src, hour, AI_CAP_MOBILE if OS.has_feature("mobile") else AI_CAP_PC, 0.0)
	SignalModel.of(net).interlocked = true
	_dummy.ai = ai

## Stations (noms uniques) et monuments (étiquettes du décor) pour les sauts rapides.
func _collect_places() -> void:
	var seen := {}
	for st in net.stations:
		var nm := str(st.name)
		if seen.has(nm) or not net.graph.edges.has(str(st.edge)): continue
		seen[nm] = true
		places.append({"name": nm, "kind": "station", "pos": view.pos3(str(st.edge), float(st.offset))})
	for lb in landmarks(view.city):
		if seen.has(str(lb[0])): continue
		seen[str(lb[0])] = true
		places.append({"name": str(lb[0]), "kind": "monument", "pos": lb[1]})

## Monuments du décor : [[nom, Vector3]] via CityScene.landmarks() (API demandée à l'agent
## MONDE) ; aucune lecture directe du format binaire des tuiles ici.
static func landmarks(c: CityScene) -> Array:
	if c == null or not c.has_method("landmarks"): return []
	return c.call("landmarks")

# --- Interface ----------------------------------------------------------------------------------

func _btn(text: String, icon_name: String, cb: Callable, kind: String = "normal") -> Button:
	var b := UiTheme.button(text, icon_name, kind, Vector2(0, 52))
	b.focus_mode = Control.FOCUS_NONE; b.pressed.connect(cb)
	b.add_theme_stylebox_override("normal", UiTheme.box(Color(UiTheme.SURFACE, 0.84), 14, 12, UiTheme.BORDER, 1))
	return b

func _build_ui() -> void:
	var safe := UiLayout.safe_insets(self)
	var top := _panel(); top.name = "explore_bar"
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	top.position = Vector2(14 + safe.x, 14 + safe.y); add_child(top)
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 8); top.add_child(v)
	var h := HBoxContainer.new(); h.add_theme_constant_override("separation", 10); v.add_child(h)
	h.add_child(UiTheme.icon_rect("camera", 28, UiTheme.ACCENT))
	var tv := VBoxContainer.new(); tv.add_theme_constant_override("separation", -3); h.add_child(tv)
	tv.add_child(UiTheme.label_("EXPLORER", UiTheme.SIZE_CAPTION, UiTheme.MUTED, true))
	tv.add_child(UiTheme.label_(city, UiTheme.SIZE_BODY if compact else UiTheme.SIZE_H2, UiTheme.TEXT, true))
	_alt_label = UiTheme.label_("", UiTheme.SIZE_SMALL, UiTheme.MUTED); v.add_child(_alt_label)
	var row := HBoxContainer.new(); row.add_theme_constant_override("separation", 8); v.add_child(row)
	var bt := _btn("" if compact else "Vue du dessus", "map", top_view); bt.name = "top_view"; bt.tooltip_text = "Vue du dessus (T)"; row.add_child(bt)
	var bl := _btn("" if compact else "Aller à…", "search", toggle_list); bl.name = "places"; bl.tooltip_text = "Stations et monuments (L)"; row.add_child(bl)
	var bh := _btn("" if compact else "Accueil", "home", leave); bh.name = "leave"; bh.tooltip_text = "Retour à l'accueil (Échap)"; row.add_child(bh)
	for b in [bt, bl, bh]: b.custom_minimum_size = Vector2(52 if compact else 0, 52)
	# heure (jour / nuit)
	var hp := _panel(); hp.name = "hour_panel"
	hp.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	hp.grow_horizontal = Control.GROW_DIRECTION_BEGIN; hp.offset_right = -14 - safe.z; hp.offset_left = -14 - safe.z; hp.offset_top = 14 + safe.y
	add_child(hp)
	var hv := VBoxContainer.new(); hv.add_theme_constant_override("separation", 4); hp.add_child(hv)
	var hh := HBoxContainer.new(); hh.add_theme_constant_override("separation", 8); hv.add_child(hh)
	hh.add_child(UiTheme.icon_rect("clock", 22, UiTheme.MUTED))
	_hour_label = UiTheme.label_("", UiTheme.SIZE_BODY, UiTheme.TEXT, true); hh.add_child(_hour_label)
	_hour_slider = HSlider.new(); _hour_slider.min_value = 0.0; _hour_slider.max_value = 24.0; _hour_slider.step = 0.25
	_hour_slider.value = hour; _hour_slider.custom_minimum_size = Vector2(200 if compact else 280, 44); _hour_slider.name = "hour"
	_hour_slider.focus_mode = Control.FOCUS_NONE
	_hour_slider.value_changed.connect(set_hour); hv.add_child(_hour_slider)
	set_hour(hour)
	# aide clavier (PC) ou joystick virtuel (tactile)
	var touch := DisplayServer.is_touchscreen_available() or compact
	joystick = _Joystick.new(); joystick.name = "joystick"
	joystick.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	joystick.custom_minimum_size = Vector2(170, 170)
	joystick.offset_top = -194 - safe.w; joystick.offset_bottom = -24 - safe.w
	joystick.offset_left = 24 + safe.x; joystick.offset_right = 194 + safe.x
	joystick.visible = touch; add_child(joystick)
	var updown := VBoxContainer.new(); updown.name = "updown"; updown.add_theme_constant_override("separation", 10)
	updown.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT); updown.grow_horizontal = Control.GROW_DIRECTION_BEGIN; updown.grow_vertical = Control.GROW_DIRECTION_BEGIN
	updown.offset_right = -24 - safe.z; updown.offset_bottom = -24 - safe.w; updown.offset_left = -24 - safe.z; updown.offset_top = -24 - safe.w
	updown.visible = touch; add_child(updown)
	for spec in [["plus", 1.0, "Monter"], ["minus", -1.0, "Descendre"]]:
		var b := UiTheme.button("", spec[0], "normal", Vector2(64, 64)); b.tooltip_text = spec[2]; b.focus_mode = Control.FOCUS_NONE
		b.add_theme_stylebox_override("normal", UiTheme.box(Color(UiTheme.SURFACE, 0.82), 18, 10, UiTheme.BORDER, 1))
		var amount: float = spec[1]
		b.button_down.connect(func(): fly.climb = amount); b.button_up.connect(func(): fly.climb = 0.0)
		updown.add_child(b)
	if not touch:
		var help := _panel(); help.name = "explore_help"
		help.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT); help.grow_vertical = Control.GROW_DIRECTION_BEGIN
		help.offset_left = 14 + safe.x; help.offset_bottom = -14 - safe.w; help.offset_top = -14 - safe.w
		add_child(help)
		var flow := HFlowContainer.new(); flow.add_theme_constant_override("h_separation", 8); flow.add_theme_constant_override("v_separation", 6)
		flow.custom_minimum_size = Vector2(760, 0); help.add_child(flow)
		for k in [["Z Q S D", "se déplacer"], ["Clic droit", "regarder"], ["Molette", "altitude"], ["Maj", "accélérer"], ["Espace / C", "monter / descendre"], ["T", "vue du dessus"], ["L", "aller à"], ["Échap", "accueil"]]:
			flow.add_child(UiTheme.keycap(k[0])); flow.add_child(UiTheme.label_(k[1], UiTheme.SIZE_SMALL, UiTheme.MUTED))
	for c in get_children():
		if c is Control: UiTheme.fade_in(c, 0.3)

func _panel() -> PanelContainer:
	return UiTheme.panel(Color(UiTheme.SURFACE, 0.82), 16, 12)

func set_hour(h: float) -> void:
	hour = fposmod(h, 24.0)
	if view: view.set_hour(hour)
	if _hour_label:
		var m := roundi(hour * 60.0)
		_hour_label.text = "%02d:%02d · %s" % [(m / 60) % 24, m % 60, "nuit" if hour < 6.5 or hour >= 21.0 else ("soirée" if hour >= 18.5 else "jour")]
	if _hour_slider and not is_equal_approx(_hour_slider.value, hour): _hour_slider.set_value_no_signal(hour)

func top_view() -> void:
	fly.top_view()

func leave() -> void:
	if ai != null:
		for t in ai.trams.duplicate(): t.remove()
	exited.emit()

## Liste des stations et monuments (recherche, cibles ≥ 48 px).
func toggle_list() -> void:
	if is_instance_valid(_list_layer):
		_list_layer.queue_free(); _list_layer = null; return
	var safe := UiLayout.safe_insets(self)
	var p := _panel(); p.name = "places_list"
	p.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	p.offset_left = 14 + safe.x; p.offset_right = (14 + safe.x) + (330 if compact else 420)
	p.offset_top = (150 if compact else 190) + safe.y; p.offset_bottom = -14 - safe.w
	add_child(p); _list_layer = p
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 8); p.add_child(v)
	var search := LineEdit.new(); search.placeholder_text = "Rechercher une station, un monument…"; search.custom_minimum_size = Vector2(0, 48)
	search.name = "search"; v.add_child(search)
	var sc := TouchScroll.new(); sc.size_flags_vertical = Control.SIZE_EXPAND_FILL; sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; v.add_child(sc)
	var lst := VBoxContainer.new(); lst.size_flags_horizontal = Control.SIZE_EXPAND_FILL; lst.add_theme_constant_override("separation", 4); sc.add_child(lst)
	var fill := func(q: String):
		for c in lst.get_children(): c.queue_free()
		for pl in places:
			if q != "" and not str(pl.name).to_lower().contains(q.to_lower()): continue
			var b := UiTheme.button(str(pl.name), "tram" if pl.kind == "station" else "flag", "ghost", Vector2(0, 48))
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT; b.clip_text = true; b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			b.focus_mode = Control.FOCUS_NONE
			var target: Vector3 = pl.pos
			b.set_meta("place", str(pl.name))
			b.pressed.connect(func(): go_to(target); toggle_list())
			lst.add_child(b)
	fill.call("")
	search.text_changed.connect(func(t): fill.call(t))

func go_to(target: Vector3) -> void:
	fly.jump_to(target, 110.0, 55.0)
	if view.city: view.city.warm(fly.pos)

# --- Boucle et entrées ---------------------------------------------------------------------------

func _process(dt: float) -> void:
	if view == null: return
	dt = minf(dt, 0.1)
	fly.move = joystick.value if is_instance_valid(joystick) and joystick.visible else Vector2.ZERO
	fly.step(dt)
	var p := fly.pos
	view.update_sectors(p)
	view.day_night.set_ground(view.ground_at(p))
	if view.city: view.city.update(p, 1)
	if ai != null:
		ai.focus = Vector2(p.x, p.z)
		ai.step(dt, _dummy)
		view.ai_view.sync(view, ai, p, dt)
	if view.signal_view: view.signal_view.update(p, false, dt)
	if _alt_label: _alt_label.text = "Altitude %d m%s%s" % [roundi(fly.agl()), " · accéléré" if fly.boost else "", (" · %d rames en ligne" % ai.trams.size()) if ai != null else ""]

func _unhandled_input(ev: InputEvent) -> void:
	if view == null: return
	if ev is InputEventKey and ev.pressed and not ev.echo:
		var k: int = ev.physical_keycode if ev.physical_keycode != 0 else ev.keycode
		var focus := get_viewport().gui_get_focus_owner()
		if focus is LineEdit and k != KEY_ESCAPE: return
		match k:
			KEY_ESCAPE, KEY_BACKSPACE:
				if is_instance_valid(_list_layer): toggle_list()
				else: leave()
			KEY_T: top_view()
			KEY_L: toggle_list()
			KEY_N: _hour_slider.value = fposmod(hour + 1.0, 24.0)
			_: return
		get_viewport().set_input_as_handled(); return
	if ev is InputEventScreenTouch or ev is InputEventScreenDrag:
		var action := gestures.feed(ev)
		if action.has("zoom"): fly.climb_by(-(float(action.zoom) - 1.0) * 6.0)
		elif action.has("pan"): fly.look(-(action.pan as Vector2))
		return
	if ev is InputEventMouseButton:
		if ev.device == -1 and DisplayServer.is_touchscreen_available(): return
		if ev.button_index == MOUSE_BUTTON_RIGHT: _look_drag = ev.pressed
		elif ev.pressed and ev.button_index == MOUSE_BUTTON_WHEEL_UP: fly.climb_by(-1.0)
		elif ev.pressed and ev.button_index == MOUSE_BUTTON_WHEEL_DOWN: fly.climb_by(1.0)
	elif ev is InputEventMouseMotion and ev.device != -1:
		if _look_drag or (ev.button_mask & MOUSE_BUTTON_MASK_RIGHT) != 0 or (ev.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
			fly.look(ev.relative)
	elif ev is InputEventMagnifyGesture:
		fly.climb_by(-(ev.factor - 1.0) * 6.0)

## Joystick virtuel (tactile et souris) : valeur dans le disque unité (x droite, y avant).
class _Joystick extends Control:
	var value := Vector2.ZERO
	var _active := -2
	func _init() -> void: mouse_filter = Control.MOUSE_FILTER_STOP
	func _gui_input(ev: InputEvent) -> void:
		var r := minf(size.x, size.y) * 0.5
		if ev is InputEventScreenTouch:
			if ev.pressed and _active == -2: _active = ev.index; _put(ev.position, r)
			elif not ev.pressed and ev.index == _active: _active = -2; value = Vector2.ZERO; queue_redraw()
			accept_event()
		elif ev is InputEventScreenDrag and ev.index == _active:
			_put(ev.position, r); accept_event()
		elif ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and ev.device != -1:
			if ev.pressed: _active = -1; _put(ev.position, r)
			else: _active = -2; value = Vector2.ZERO; queue_redraw()
			accept_event()
		elif ev is InputEventMouseMotion and _active == -1 and ev.device != -1:
			_put(ev.position, r); accept_event()
	func _put(p: Vector2, r: float) -> void:
		var d := (p - size * 0.5) / maxf(r * 0.8, 1.0)
		if d.length() > 1.0: d = d.normalized()
		value = Vector2(d.x, -d.y)
		queue_redraw()
	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5
		draw_circle(c, r, Color(UiTheme.SURFACE, 0.7))
		draw_arc(c, r - 1.0, 0.0, TAU, 48, Color(1, 1, 1, 0.25), 2.0, true)
		draw_circle(c + Vector2(value.x, -value.y) * r * 0.8, r * 0.36, Color(UiTheme.ACCENT, 0.85))
