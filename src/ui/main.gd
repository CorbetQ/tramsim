extends Control
## Menu (mission / mode libre) et interface de conduite.
## Interface ancrée et mise à l'échelle (stretch canvas_items) : lisible du téléphone au grand écran de PC.
## Commandes : écran tactile/souris et clavier (voir KEYS_HELP).

const KEYS_HELP := "Clavier : Z/↑ traction · S/↓ freinage · X neutre · Espace urgence · O portes · K cloche · C caméra · M carte · P pantographe · A aiguillages · V changer de sens · R remise sur voie · Échap pause · F11 plein écran · molette : zoom"

const TUTO := [
	"Manipulateur à gauche (ou Z/S) : vers le haut = traction, vers le bas = freinage.",
	"À quai : « Portes » (O). Départ portes fermées, à l'heure : aucune avance, 60 s de retard au maximum.",
	"Signal rouge ou fin de voie dépassés = échec. URGENCE (Espace) = freinage maximal.",
	"« Caméra » (C) : cabine / extérieur ; glisser pour tourner autour de la rame, molette pour zoomer. Touchez pour fermer."]

var save: Dictionary
var session: MissionSession
var free: FreeSession
var view: LineView
var net: NetworkLoader
var net_path := ""
var vehicle: VehicleProfile
var notch := 0.0
var emergency := false
var external_cam := true
var paused := false
var free_mode := false
var mission: Dictionary = {}
var start_station: Dictionary = {}
var hour0 := 12.0
var _result_saved := false

# interface de conduite
var hud_speed: Label
var hud_info: Label
var hud_alert: Label
var log_label: Label
var notch_label: Label
var slider: VSlider
var map: MapView
var switch_panel: SwitchPanel
var pause_layer: Control
var debrief_layer: Control
var tuto: Label
var tuto_step := 0
var bell: AudioStreamPlayer
var _log_time := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = _make_theme()
	save = SaveGame.load_data()
	bell = AudioStreamPlayer.new(); bell.stream = _bell_sound(); add_child(bell)
	_build_menu()

func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 22
	var flat := StyleBoxFlat.new(); flat.bg_color = Color(0.13, 0.15, 0.18, 0.88)
	flat.set_corner_radius_all(10); flat.content_margin_left = 14; flat.content_margin_right = 14
	flat.content_margin_top = 8; flat.content_margin_bottom = 8
	var hov := flat.duplicate(); hov.bg_color = Color(0.2, 0.24, 0.29, 0.95)
	var prs := flat.duplicate(); prs.bg_color = Color(0.85, 0.55, 0.12, 0.95)
	for k in ["Button", "OptionButton"]:
		t.set_stylebox("normal", k, flat); t.set_stylebox("hover", k, hov); t.set_stylebox("pressed", k, prs)
		t.set_stylebox("focus", k, StyleBoxEmpty.new())
	var panel := StyleBoxFlat.new(); panel.bg_color = Color(0.07, 0.09, 0.12, 0.78); panel.set_corner_radius_all(12)
	panel.content_margin_left = 16; panel.content_margin_right = 16; panel.content_margin_top = 10; panel.content_margin_bottom = 10
	t.set_stylebox("panel", "PanelContainer", panel)
	return t

## Cloche de tram : deux coups (« ding-ding ») générés en PCM 16 bits.
func _bell_sound() -> AudioStreamWAV:
	var rate := 22050
	var data := PackedByteArray()
	var n := int(rate * 1.1)
	data.resize(n * 2)
	for i in n:
		var t := float(i) / rate
		var v := 0.0
		for hit in [0.0, 0.42]:
			if t >= hit:
				var u: float = t - hit
				v += (sin(TAU * 1180.0 * u) * 0.6 + sin(TAU * 2950.0 * u) * 0.25 + sin(TAU * 4410.0 * u) * 0.1) * exp(-u * 6.0)
		data.encode_s16(i * 2, int(clampf(v * 0.6, -1.0, 1.0) * 32000))
	var w := AudioStreamWAV.new(); w.format = AudioStreamWAV.FORMAT_16_BITS; w.mix_rate = rate; w.data = data
	return w

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		if session != null and not paused:
			_set_paused(true)
		_persist()

func _persist() -> void:
	if free != null and vehicle != null:
		SaveGame.store_free(save, free, net_path, vehicle.id)
	SaveGame.save_data(save)

func _clear() -> void:
	for c in get_children():
		if c != bell: c.queue_free()
	view = null; session = null; free = null; map = null; tuto = null; switch_panel = null; pause_layer = null; debrief_layer = null

# ----------------------------------------------------------------------------------------------- menu

func _build_menu() -> void:
	_clear()
	paused = false
	var bg := ColorRect.new(); bg.color = Color(0.1, 0.12, 0.15); bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(bg)
	var center := CenterContainer.new(); center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(center)
	var row := HBoxContainer.new(); row.add_theme_constant_override("separation", 28); center.add_child(row)
	var box := VBoxContainer.new(); box.custom_minimum_size = Vector2(560, 0); box.add_theme_constant_override("separation", 8)
	row.add_child(box)
	var right := VBoxContainer.new(); row.add_child(right)
	var preview := TramPreview.new(); right.add_child(preview)
	var sheet := Label.new(); sheet.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; sheet.custom_minimum_size = Vector2(520, 0)
	sheet.add_theme_font_size_override("font_size", 17); right.add_child(sheet)
	var title := Label.new(); title.text = "Tram Sim France"; title.add_theme_font_size_override("font_size", 40); box.add_child(title)
	# mode
	var modes := HBoxContainer.new(); box.add_child(modes)
	var grp := ButtonGroup.new()
	var b_mis := Button.new(); b_mis.text = "Mission horaire"; b_mis.toggle_mode = true; b_mis.button_group = grp
	var b_free := Button.new(); b_free.text = "Mode libre"; b_free.toggle_mode = true; b_free.button_group = grp
	for b in [b_mis, b_free]:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL; b.custom_minimum_size = Vector2(0, 56); modes.add_child(b)
	b_free.button_pressed = free_mode; b_mis.button_pressed = not free_mode
	var all_nets: Array = NetworkRegistry.entries()
	var cities := NetworkRegistry.cities()
	var city_opt := _opt(box, "Ville")
	for c in cities: city_opt.add_item(c)
	var line_row := _row(box, "Ligne"); var line_opt: OptionButton = line_row.get_child(1)
	var mis_row := _row(box, "Service"); var mis_opt: OptionButton = mis_row.get_child(1)
	var st_row := _row(box, "Départ"); var st_opt: OptionButton = st_row.get_child(1)
	var veh_opt := _opt(box, "Matériel")
	var cat_btn := Button.new(); cat_btn.text = "Catalogue…"; cat_btn.custom_minimum_size = Vector2(150, 48)
	cat_btn.tooltip_text = "Catalogue des rames : fiches techniques, livrées, choix du matériel"; veh_opt.get_parent().add_child(cat_btn)
	cat_btn.pressed.connect(func(): _open_catalogue(cities[city_opt.selected]))
	var time_opt := _opt(box, "Heure")
	for t in ["Heure réelle du service", "Jour (12 h)", "Coucher de soleil (20 h)", "Nuit (23 h)", "Cycle accéléré (1 h = 1 min)"]: time_opt.add_item(t)
	time_opt.selected = int(save.settings.get("time_mode", 0))
	var traffic_cb := CheckBox.new(); traffic_cb.text = "Trafic automobile"; traffic_cb.button_pressed = save.settings.traffic; box.add_child(traffic_cb)
	var go := Button.new(); go.custom_minimum_size = Vector2(0, 76); go.add_theme_font_size_override("font_size", 28); box.add_child(go)
	var keys := Label.new(); keys.text = KEYS_HELP; keys.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	keys.add_theme_font_size_override("font_size", 15); keys.modulate = Color(1, 1, 1, 0.7); box.add_child(keys)
	# état du menu (tableaux partagés : modifiés en place depuis les lambdas)
	var city_nets: Array = []
	var mis_list: Array = []
	var st_list: Array = []
	var vehicles: Array = []
	var cur_meta: Dictionary = {}
	var free_path := func() -> String: return "res://data/free/%s.json" % _source_of(city_nets)
	var fill := func():
		var is_free := b_free.button_pressed
		line_row.visible = not is_free; mis_row.visible = not is_free; st_row.visible = is_free
		city_nets.clear()
		city_nets.append_array(all_nets.filter(func(e): return e.city == cities[city_opt.selected]))
		if line_opt.item_count == 0 or line_opt.get_meta("city", "") != cities[city_opt.selected]:
			line_opt.clear()
			for e in city_nets: line_opt.add_item("%s — %s%s" % [e.line, e.long_name, "  (tram-train)" if e.kind == "tram-train" else ""])
			line_opt.set_meta("city", cities[city_opt.selected])
		var n := NetworkLoader.new()
		if is_free and FileAccess.file_exists(free_path.call()):
			n.load_file(free_path.call())
		else:
			n.load_file(city_nets[maxi(line_opt.selected, 0)].path)
		cur_meta.clear(); cur_meta.merge(n.meta)
		mis_list.clear(); mis_list.append_array(n.missions())
		mis_opt.clear()
		for m in mis_list: mis_opt.add_item("%s → %s" % [str(m.start_time).substr(0, 5), m.headsign])
		if mis_list.is_empty(): mis_opt.add_item("Service de démonstration")
		st_list.clear(); st_opt.clear()
		var seen := {}
		for s in n.stations:
			var key := "%s|%s" % [s.name, "/".join(s.get("lines", []))]
			var k := 1
			while seen.has(key + str(k)): k += 1
			seen[key + str(k)] = true
			st_list.append(s)
			st_opt.add_item("%s%s — quai %d" % [s.name, ("  (ligne " + "/".join(s.get("lines", [])) + ")") if s.has("lines") else "", k])
		# matériels : flotte du réseau, puis autres (mode d'adaptation si incompatibles)
		vehicles.clear(); veh_opt.clear()
		for f in TramModel.fleet_for(n.meta):
			vehicles.append(VehicleLibrary.for_fleet(f, n.meta)); veh_opt.add_item(f.name)
		for v in VehicleLibrary.all():
			vehicles.append(v); veh_opt.add_item("Autre : " + v.family)
	var refresh := func(_i = 0):
		var is_free := b_free.button_pressed
		var v: VehicleProfile = vehicles[maxi(veh_opt.selected, 0)]
		var supply := [str(cur_meta.get("supply", "overhead"))]
		var guid := str(cur_meta.get("guidance", "steel"))
		var ok := Compatibility.mission_allowed(v, supply, guid)
		preview.show_tram(cur_meta, v)
		sheet.text = "%s\n%.1f m · %.0f t · %.0f kW · %d places · %d km/h · alimentation %s%s\nValeurs estimées : %s" % [
			v.family, v.length_m, v.empty_mass_kg / 1000.0, v.power_kw, v.capacity, roundi(v.max_speed_ms * 3.6), v.supply,
			" · guidage pneus" if v.guidance == "rubber_guided" else "", ", ".join(v.estimated)]
		go.disabled = not ok and not is_free
		go.text = "Démarrer" if (ok or is_free) else "Matériel incompatible (essayez le mode libre)"
		if is_free and not ok: go.text = "Démarrer (mode d'adaptation)"
	var full := func(_i = 0):
		fill.call(); veh_opt.select(0); refresh.call()
	city_opt.item_selected.connect(full)
	line_opt.item_selected.connect(full)
	b_mis.toggled.connect(func(on): if on: full.call())
	b_free.toggled.connect(func(on): if on: full.call())
	veh_opt.item_selected.connect(refresh)
	full.call()
	# choix venu du catalogue (« Conduire cette rame ») : ville, ligne et matériel, puis départ
	var pick: Dictionary = get_meta("catalogue_pick", {})
	if not pick.is_empty():
		remove_meta("catalogue_pick")
		var ci := cities.find(str(pick.city))
		if ci >= 0:
			city_opt.select(ci); fill.call()
			for i in city_nets.size():
				if city_nets[i].path == pick.path: line_opt.select(i)
			fill.call()
			for i in vehicles.size():
				if (vehicles[i] as VehicleProfile).model_family == pick.family: veh_opt.select(i); break
			refresh.call()
	go.pressed.connect(func():
		save.settings.traffic = traffic_cb.button_pressed
		save.settings.time_mode = time_opt.selected
		free_mode = b_free.button_pressed
		vehicle = vehicles[maxi(veh_opt.selected, 0)]
		if free_mode:
			net_path = free_path.call()
			if not FileAccess.file_exists(net_path): net_path = city_nets[0].path
			start_station = st_list[maxi(st_opt.selected, 0)] if not st_list.is_empty() else {}
			mission = {}
		else:
			net_path = city_nets[maxi(line_opt.selected, 0)].path
			mission = mis_list[mis_opt.selected] if mis_opt.selected >= 0 and mis_opt.selected < mis_list.size() else {}
		_start())
	if pick.get("start", false) and not go.disabled: go.pressed.emit()

## Catalogue des rames par-dessus le menu (masqué) ; « Conduire cette rame » reconstruit le menu avec ce choix.
func _open_catalogue(city: String) -> Catalogue:
	var hidden: Array = []
	for c in get_children():
		if c is CanvasItem and c.visible: c.visible = false; hidden.append(c)
	var cat := Catalogue.new(city); add_child(cat)
	cat.closed.connect(func():
		for c in hidden:
			if is_instance_valid(c): c.visible = true)
	cat.drive.connect(func(p: Dictionary):
		p.start = true; set_meta("catalogue_pick", p); _build_menu())
	return cat

func _source_of(city_nets: Array) -> String:
	if city_nets.is_empty(): return ""
	var n := NetworkLoader.new(); n.load_file(city_nets[0].path)
	return str(n.meta.get("source_id", ""))

func _opt(parent: Control, label: String) -> OptionButton:
	return _row(parent, label).get_child(1)

func _row(parent: Control, label: String) -> HBoxContainer:
	var r := HBoxContainer.new(); parent.add_child(r)
	var l := Label.new(); l.text = label; l.custom_minimum_size = Vector2(120, 0); r.add_child(l)
	var o := OptionButton.new(); o.size_flags_horizontal = Control.SIZE_EXPAND_FILL; o.custom_minimum_size = Vector2(0, 48)
	o.fit_to_longest_item = false; o.clip_text = true
	r.add_child(o)
	return r

# ----------------------------------------------------------------------------------------------- partie

func _start() -> void:
	_clear()
	_result_saved = false
	paused = false
	emergency = false
	notch = 0.0
	net = NetworkLoader.new()
	var errs := net.load_file(net_path)
	if not errs.is_empty():
		push_error(str(errs)); _build_menu(); return
	var first: String = net.meta.edges[0].id
	if free_mode:
		var e := first
		var o := minf(30.0, net.graph.edges[first].length - 5.0)
		if not start_station.is_empty():
			e = start_station.edge; o = float(start_station.offset)
		free = FreeSession.new(net, vehicle, e, o, save.settings.traffic)
		session = free
		first = e
	else:
		if not mission.is_empty(): first = mission.start_edge
		var sched: Array[float] = []
		var start_off := 100.0
		if not mission.is_empty():
			for t in mission.departures: sched.append(float(t))
			start_off = float(mission.start_offset)
		else:
			for i in net.stations.size(): sched.append(120.0 + 140.0 * i)
		session = MissionSession.new(net, vehicle, first, start_off, sched, 40)
		if not mission.is_empty(): session.set_mission_stops(mission.stops)
		session.traffic.set_enabled(save.settings.traffic)
	session.event.connect(func(_k, text): _log(text))
	# 3D directement dans la fenêtre principale : pleine résolution sur grand écran
	view = LineView.new(); view.view_distance = float(save.settings.view_distance)
	add_child(view); view.build(net, first, vehicle)
	hour0 = _start_hour()
	view.set_hour(hour0)
	if OS.has_feature("mobile"):
		view.day_night.sun.shadow_enabled = false
		if view.city: view.city.radius = 450.0
	view.update_from(session, true)
	if view.city: view.city.warm(view.cam.global_position)
	view.cam.current = true
	add_child(TramAudio.new(view, bell))   # moteur sonore de la rame
	_build_hud()
	if free and free.adaptation_notice != "": _log(free.adaptation_notice)
	if not save.settings.tutorial_done: _show_tuto()

func _build_hud() -> void:
	# bandeau supérieur
	var top := PanelContainer.new(); top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 12; top.offset_right = -12; top.offset_top = 10
	add_child(top)
	var tr := HBoxContainer.new(); tr.add_theme_constant_override("separation", 22); top.add_child(tr)
	hud_speed = Label.new(); hud_speed.add_theme_font_size_override("font_size", 40); hud_speed.custom_minimum_size = Vector2(170, 0); tr.add_child(hud_speed)
	hud_info = Label.new(); hud_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL; hud_info.clip_text = true; hud_info.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS; tr.add_child(hud_info)
	for spec in [["Pause", func(): _set_paused(not paused)], ["Menu", func(): _persist(); _build_menu()]]:
		var b := Button.new(); b.text = spec[0]; b.custom_minimum_size = Vector2(120, 56); b.pressed.connect(spec[1]); tr.add_child(b)
	# alertes et messages
	var msg := VBoxContainer.new(); msg.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP); msg.offset_top = 110
	msg.grow_horizontal = Control.GROW_DIRECTION_BOTH; msg.mouse_filter = Control.MOUSE_FILTER_IGNORE; add_child(msg)
	hud_alert = Label.new(); hud_alert.add_theme_font_size_override("font_size", 30); hud_alert.add_theme_color_override("font_color", Color(1, 0.35, 0.3))
	hud_alert.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; msg.add_child(hud_alert)
	log_label = Label.new(); log_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	log_label.add_theme_color_override("font_outline_color", Color.BLACK); log_label.add_theme_constant_override("outline_size", 6); msg.add_child(log_label)
	# manipulateur (gauche)
	var lp := PanelContainer.new(); lp.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT); lp.offset_left = 12; lp.offset_top = 30; lp.offset_bottom = 30
	lp.grow_vertical = Control.GROW_DIRECTION_BOTH; add_child(lp)
	var lv := VBoxContainer.new(); lv.alignment = BoxContainer.ALIGNMENT_CENTER; lp.add_child(lv)
	var plus := Button.new(); plus.text = "▲ Traction"; plus.custom_minimum_size = Vector2(150, 56); lv.add_child(plus)
	slider = VSlider.new(); slider.min_value = -1; slider.max_value = 1; slider.step = 0.05; slider.value = 0
	slider.custom_minimum_size = Vector2(150, 240); slider.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	slider.add_theme_constant_override("grabber_offset", 0)
	slider.value_changed.connect(func(v): notch = v; if v > -0.99: emergency = false)
	lv.add_child(slider)
	var minus := Button.new(); minus.text = "▼ Freinage"; minus.custom_minimum_size = Vector2(150, 56); lv.add_child(minus)
	var zero := Button.new(); zero.text = "Neutre"; zero.custom_minimum_size = Vector2(150, 48); lv.add_child(zero)
	notch_label = Label.new(); notch_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; lv.add_child(notch_label)
	plus.pressed.connect(func(): _set_notch(notch + 0.25))
	minus.pressed.connect(func(): _set_notch(notch - 0.25))
	zero.pressed.connect(func(): _set_notch(0.0))
	# commandes (bas)
	var bottom := PanelContainer.new(); bottom.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM); bottom.offset_bottom = -10
	bottom.grow_horizontal = Control.GROW_DIRECTION_BOTH; bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN; add_child(bottom)
	var bh := HBoxContainer.new(); bh.add_theme_constant_override("separation", 10); bottom.add_child(bh)
	var specs := [["Portes\nO", _doors], ["Cloche\nK", _horn], ["Caméra\nC", _camera], ["Carte\nM", _toggle_map], ["Pantographe\nP", _panto]]
	if free_mode:
		specs += [["Aiguillages\nA", _toggle_switches], ["Changer de sens\nV", _reverse], ["Remise sur voie\nR", _rerail], ["Trafic\nT", _traffic]]
	for spec in specs:
		var b := Button.new(); b.text = spec[0]; b.custom_minimum_size = Vector2(108, 74); b.pressed.connect(spec[1])
		b.add_theme_font_size_override("font_size", 19); bh.add_child(b)
	# urgence (droite)
	var eb := Button.new(); eb.text = "URGENCE\n(Espace)"; eb.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	eb.offset_left = -200; eb.offset_top = -170; eb.offset_right = -14; eb.offset_bottom = -100
	eb.custom_minimum_size = Vector2(186, 70)
	var red := StyleBoxFlat.new(); red.bg_color = Color(0.75, 0.08, 0.08, 0.92); red.set_corner_radius_all(12)
	eb.add_theme_stylebox_override("normal", red); eb.add_theme_stylebox_override("hover", red)
	eb.pressed.connect(_emergency); add_child(eb)
	# carte
	map = MapView.new(); map.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	map.offset_left = -420; map.offset_right = -14; map.offset_top = 100; map.offset_bottom = -190
	map.visible = false; map.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map.setup(session, view); add_child(map)

func _set_notch(v: float) -> void:
	notch = clampf(v, -1.0, 1.0)
	if notch > -0.99: emergency = false
	if slider: slider.set_value_no_signal(notch)

func _doors() -> void:
	var was := session.doors_open
	session.set_doors(not session.doors_open)
	if session.doors_open == was and not was:
		_log("Ouverture refusée : rame en mouvement")

func _horn() -> void:
	bell.play(); _log("Ding ding !")

func _camera() -> void:
	external_cam = not external_cam

func _toggle_map() -> void:
	map.visible = not map.visible

func _panto() -> void:
	session.toggle_pantograph(); _log("Pantographe " + ("levé" if session.pantograph_up else "baissé"))

func _emergency() -> void:
	emergency = true; _set_notch(-1.0); _log("Freinage d'urgence")

func _reverse() -> void:  # changement de cabine : même voie, sens de marche inversé
	if free:
		var err := free.reverse()
		_log(err if err != "" else ("Changement de cabine : " + ("sens de la voie" if free.direction > 0 else "marche à contre-sens")))
		if switch_panel: switch_panel.refresh()

func _rerail() -> void:
	if free: free.rerail(); _log("Remise sur voie")

func _traffic() -> void:
	if free:
		free.set_traffic(not free.traffic.enabled); save.settings.traffic = free.traffic.enabled
		_log("Trafic " + ("activé" if free.traffic.enabled else "désactivé"))

func _toggle_switches() -> void:
	if not free_mode: return
	if switch_panel:
		switch_panel.queue_free(); switch_panel = null; return
	switch_panel = SwitchPanel.new(); add_child(switch_panel)
	switch_panel.setup(free, view)
	switch_panel.closed.connect(_toggle_switches)
	switch_panel.message.connect(_log)

func _log(t: String) -> void:
	if log_label: log_label.text = t
	_log_time = 6.0

func _set_paused(on: bool) -> void:
	paused = on
	if pause_layer: pause_layer.queue_free(); pause_layer = null
	if on:
		pause_layer = _overlay("Pause", [["Reprendre (Échap)", func(): _set_paused(false)], ["Menu principal", func(): _persist(); _build_menu()]])

func _overlay(title: String, buttons: Array, body: String = "") -> Control:
	var layer := ColorRect.new(); layer.color = Color(0, 0, 0, 0.55); layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(layer)
	var c := CenterContainer.new(); c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); layer.add_child(c)
	var p := PanelContainer.new(); c.add_child(p)
	var v := VBoxContainer.new(); v.custom_minimum_size = Vector2(460, 0); v.add_theme_constant_override("separation", 12); p.add_child(v)
	var t := Label.new(); t.text = title; t.add_theme_font_size_override("font_size", 38); t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; v.add_child(t)
	if body != "":
		var l := Label.new(); l.text = body; l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; v.add_child(l)
	for spec in buttons:
		var b := Button.new(); b.text = spec[0]; b.custom_minimum_size = Vector2(0, 64); b.pressed.connect(spec[1]); v.add_child(b)
	return layer

func _show_tuto() -> void:
	tuto = Label.new(); tuto.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	tuto.grow_horizontal = Control.GROW_DIRECTION_BOTH; tuto.grow_vertical = Control.GROW_DIRECTION_BOTH
	tuto.text = "1/%d  %s" % [TUTO.size(), TUTO[0]]
	tuto.add_theme_font_size_override("font_size", 26)
	tuto.add_theme_color_override("font_outline_color", Color.BLACK); tuto.add_theme_constant_override("outline_size", 10)
	tuto.mouse_filter = Control.MOUSE_FILTER_STOP
	tuto.gui_input.connect(_tuto_input); add_child(tuto)

func _tuto_input(ev: InputEvent) -> void:
	if (ev is InputEventMouseButton and ev.pressed) or (ev is InputEventScreenTouch and ev.pressed):
		tuto_step += 1
		if tuto_step >= TUTO.size():
			tuto.queue_free(); tuto = null
			save.settings.tutorial_done = true; SaveGame.save_data(save)
		else:
			tuto.text = "%d/%d  %s" % [tuto_step + 1, TUTO.size(), TUTO[tuto_step]]

## Heure de départ : horaire GTFS du service (mission), sinon selon le réglage.
func _start_hour() -> float:
	match int(save.settings.get("time_mode", 0)):
		1: return 12.0
		2: return 20.0
		3: return 23.0
	if not mission.is_empty():
		var p := str(mission.start_time).split(":")
		return fposmod(float(p[0]) + float(p[1]) / 60.0 + float(p[2]) / 3600.0, 24.0)
	return 9.0

func current_hour() -> float:
	var speed := 60.0 if int(save.settings.get("time_mode", 0)) == 4 else 1.0
	return hour0 + session.time_s * speed / 3600.0

# ----------------------------------------------------------------------------------------------- entrées

func _unhandled_input(ev: InputEvent) -> void:
	if view == null: return
	if ev is InputEventScreenDrag:
		view.orbit -= ev.relative.x * 0.006
	elif ev is InputEventMouseMotion and (ev.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		view.orbit -= ev.relative.x * 0.006
	elif ev is InputEventMouseButton and ev.pressed:
		if ev.button_index == MOUSE_BUTTON_WHEEL_UP: view.cam_dist = maxf(14.0, view.cam_dist * 0.9)
		elif ev.button_index == MOUSE_BUTTON_WHEEL_DOWN: view.cam_dist = minf(160.0, view.cam_dist * 1.1)
	elif ev is InputEventMagnifyGesture:
		view.cam_dist = clampf(view.cam_dist / ev.factor, 14.0, 160.0)

func _input(ev: InputEvent) -> void:
	if not (ev is InputEventKey) or not ev.pressed or ev.echo:
		return
	var k: int = ev.physical_keycode if ev.physical_keycode != 0 else ev.keycode
	if k == KEY_F11:
		var w := get_window()
		w.mode = Window.MODE_WINDOWED if w.mode == Window.MODE_FULLSCREEN else Window.MODE_FULLSCREEN
		return
	if session == null: return
	match k:
		KEY_ESCAPE:
			if switch_panel: _toggle_switches()
			else: _set_paused(not paused)
		KEY_SPACE: _emergency()
		KEY_X: _set_notch(0.0)
		KEY_O: _doors()
		KEY_K: _horn()
		KEY_C: _camera()
		KEY_M: _toggle_map()
		KEY_P: _panto()
		KEY_A: _toggle_switches()
		KEY_R: _rerail()
		KEY_V: _reverse()
		KEY_T: _traffic()
		KEY_W, KEY_Z, KEY_UP: _set_notch(notch + 0.25)
		KEY_S, KEY_DOWN: _set_notch(notch - 0.25)
		_: return
	get_viewport().set_input_as_handled()

# ----------------------------------------------------------------------------------------------- boucle

func _process(dt: float) -> void:
	if session == null: return
	if not paused and not session.finished:
		session.tick(minf(dt, 0.1), notch, emergency)
		if emergency and session.phys.speed < 0.05: emergency = false
	view.set_hour(current_hour())
	view.update_from(session, external_cam)
	if has_node("TramAudio"): ($TramAudio as TramAudio).update(session, notch, emergency, external_cam, paused, dt)
	if map.visible: map.queue_redraw()
	if switch_panel and Engine.get_process_frames() % 15 == 0: switch_panel.canvas.queue_redraw()
	_log_time -= dt
	if _log_time < 0.0 and log_label: log_label.text = ""
	var st: Dictionary = session.next_station_ahead() if free_mode else (session.stops[mini(session.next_station, session.stops.size() - 1)] if not session.stops.is_empty() else {})
	hud_speed.text = "%d km/h" % roundi(session.phys.speed * 3.6)
	var dep := ""
	if not free_mode and not session.finished and session.next_station < session.schedule.size():
		var rest := session.schedule[session.next_station] - session.time_s
		dep = "  ·  départ %s" % (("dans %d s" % roundi(rest)) if rest > 0 else ("+%d s" % roundi(-rest)))
	hud_info.text = "%s  ·  limite %d km/h  ·  %s%s\nvoyageurs %d  ·  portes %s" % [
		view.day_night.clock_text(), roundi(session.speed_limit() * 3.6),
		("prochain arrêt : " + str(st.get("name", "—"))), dep, session.phys.passengers,
		"ouvertes" if session.doors_open else "fermées"]
	var alerts: Array = []
	if session.overspeed: alerts.append("SURVITESSE")
	if not session.power_ok: alerts.append("COUPURE D'ALIMENTATION")
	if emergency: alerts.append("FREINAGE D'URGENCE")
	if free and free.incident != "": alerts.append("INCIDENT : " + free.incident + " — remise sur voie (R)")
	hud_alert.text = "  ·  ".join(alerts)
	notch_label.text = ("Traction %d %%" % roundi(notch * 100)) if notch > 0.01 else (("Freinage %d %%" % roundi(-notch * 100)) if notch < -0.01 else "Neutre")
	if session.finished and not _result_saved:
		_result_saved = true
		var d := session.debrief()
		SaveGame.add_result(save, net_path, vehicle.id, d)
		SaveGame.save_data(save)
		var lines := PackedStringArray()
		var names := ["à l'heure", "départ anticipé", "retard > 60 s", "arrêt oublié"]
		for s in d.stops: lines.append("%s : %s" % [s.name, names[s.result]])
		debrief_layer = _overlay("MISSION RÉUSSIE" if d.success else "ÉCHEC — " + d.reason,
			[["Rejouer", func(): _start()], ["Menu principal", func(): _build_menu()]], "\n".join(lines.slice(maxi(0, lines.size() - 12))))
