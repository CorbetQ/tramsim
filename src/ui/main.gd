extends Control
## Menu : mode -> matériel -> départ ; HUD tactile, carte, tutoriel, sauvegarde.


var save: Dictionary
var session: MissionSession
var free: FreeSession
var view: LineView
var net: NetworkLoader
var net_path := ""
var vehicle: VehicleProfile
var notch := 0.0
var external_cam := true
var paused := false
var free_mode := false
var hud: Label
var log_label: Label
var map: MapView
var tuto: Label
var tuto_step := 0
var _result_saved := false
var mission: Dictionary = {}
var hour0 := 12.0
var _drag := false

const TUTO := [
	"1/4  Curseur gauche : haut = traction, bas = freinage.",
	"2/4  « Portes » à l'arrêt en station ; départ portes fermées, à l'heure (0 s d'avance, 60 s de retard max).",
	"3/4  Signal rouge ou fin de voie dépassés = échec. URGENCE = freinage maximal.",
	"4/4  « Caméra » bascule cabine / extérieur ; « Carte » affiche le réseau. Touchez ce message pour fermer."]

func _ready() -> void:
	save = SaveGame.load_data()
	_build_menu()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		paused = true
		_persist()

func _persist() -> void:
	if free != null:
		SaveGame.store_free(save, free, net_path, vehicle.id)
	SaveGame.save_data(save)

func _clear() -> void:
	for c in get_children(): c.queue_free()
	view = null; session = null; free = null; map = null; tuto = null

func _build_menu() -> void:
	_clear()
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var row := HBoxContainer.new(); row.add_theme_constant_override("separation", 24)
	center.add_child(row)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(600, 0)
	row.add_child(box)
	var preview := TramPreview.new()
	row.add_child(preview)
	var title := Label.new(); title.text = "Tram Sim France"; box.add_child(title)
	var all_nets: Array = NetworkRegistry.entries()
	var city_opt := OptionButton.new()
	var cities := NetworkRegistry.cities()
	for c in cities: city_opt.add_item(c)
	box.add_child(city_opt)
	var net_opt := OptionButton.new()
	box.add_child(net_opt)
	var city_nets: Array = []
	var fill_lines := func():
		city_nets.clear()
		city_nets.append_array(all_nets.filter(func(e): return e.city == cities[city_opt.selected]))
		net_opt.clear()
		for e in city_nets:
			net_opt.add_item("Ligne %s — %s%s" % [e.line, e.long_name, "  (tram-train)" if e.kind == "tram-train" else ""])
	fill_lines.call()
	var veh_opt := OptionButton.new()
	var vehicles := VehicleLibrary.all()
	for v in vehicles: veh_opt.add_item(v.family)
	box.add_child(veh_opt)
	var sheet := Label.new(); sheet.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; sheet.custom_minimum_size = Vector2(600, 0); box.add_child(sheet)
	var mode_opt := OptionButton.new(); mode_opt.add_item("Mission horaire"); mode_opt.add_item("Mode libre"); box.add_child(mode_opt)
	var mis_opt := OptionButton.new(); box.add_child(mis_opt)
	var mis_list: Array = []
	var time_opt := OptionButton.new()
	for t in ["Heure réelle du service", "Jour (12 h)", "Coucher de soleil (20 h)", "Nuit (23 h)", "Cycle accéléré (1 h = 1 min)"]: time_opt.add_item(t)
	time_opt.selected = int(save.settings.get("time_mode", 0))
	box.add_child(time_opt)
	var traffic_cb := CheckBox.new(); traffic_cb.text = "Trafic automobile"
	traffic_cb.button_pressed = save.settings.traffic; box.add_child(traffic_cb)
	var go := Button.new(); go.custom_minimum_size = Vector2(0, 90); box.add_child(go)
	var refresh := func(_i = 0):
		var v: VehicleProfile = vehicles[veh_opt.selected]
		var path: String = city_nets[net_opt.selected].path
		var n := NetworkLoader.new(); n.load_file(path)
		var supply: Array = n.supplies; var guid := str(n.meta.get("guidance", "steel"))
		var ok := Compatibility.mission_allowed(v, supply, guid)
		preview.show_tram(n.meta, v)
		mis_list.clear()
		mis_list.append_array(n.missions())
		mis_opt.clear()
		for m in mis_list:
			mis_opt.add_item("%s — départ %s → %s" % [m.id, m.start_time, m.headsign])
		if mis_list.is_empty(): mis_opt.add_item("Service de démonstration")
		sheet.text = "%s — %.0f m, %.0f t, %.0f kW, %d places, alim. %s\nValeurs estimées : %s" % [v.family, v.length_m, v.empty_mass_kg / 1000.0, v.power_kw, v.capacity, v.supply, ", ".join(v.estimated)]
		var libre: bool = mode_opt.selected == 1
		go.disabled = not ok and not libre
		go.text = "Démarrer" if (ok or libre) else "Matériel incompatible avec ce réseau (essayez le mode libre)"
		if libre and not ok: go.text = "Démarrer — " + Compatibility.adaptation_notice(v, supply, guid)
	var preselect := func(_i = 0):
		var n2 := NetworkLoader.new(); n2.load_file(city_nets[net_opt.selected].path)
		var dv := VehicleLibrary.default_for(n2.meta)
		for k in vehicles.size():
			if vehicles[k].id == dv.id: veh_opt.select(k)
	city_opt.item_selected.connect(func(_i): fill_lines.call(); preselect.call(); refresh.call())
	net_opt.item_selected.connect(func(_i): preselect.call(); refresh.call())
	for o in [veh_opt, mode_opt]: o.item_selected.connect(refresh)
	preselect.call()
	refresh.call()
	go.pressed.connect(func():
		save.settings.traffic = traffic_cb.button_pressed
		save.settings.time_mode = time_opt.selected
		net_path = city_nets[net_opt.selected].path
		vehicle = vehicles[veh_opt.selected]
		free_mode = mode_opt.selected == 1
		mission = mis_list[mis_opt.selected] if mis_opt.selected >= 0 and mis_opt.selected < mis_list.size() else {}
		_start())

func _start() -> void:
	_clear()
	_result_saved = false
	net = NetworkLoader.new()
	var errs := net.load_file(net_path)
	if not errs.is_empty():
		push_error(str(errs)); _build_menu(); return
	var first: String = net.meta.edges[0].id
	if not mission.is_empty():
		first = mission.start_edge
	if free_mode:
		var e := first
		var o := float(mission.get("start_offset", minf(100.0, net.graph.edges[first].length - 5.0)))
		if save.free.get("network", "") == net_path:
			e = save.free.edge; o = float(save.free.offset)
		free = FreeSession.new(net, vehicle, e, o, save.settings.traffic)
		session = free
	else:
		var sched: Array[float] = []
		var start_off := 100.0
		if not mission.is_empty():
			for t in mission.departures: sched.append(float(t))
			start_off = float(mission.start_offset)
		else:
			for i in net.stations.size(): sched.append(120.0 + 140.0 * i)
		session = MissionSession.new(net, vehicle, first, start_off, sched, 40)
		if not mission.is_empty():
			session.set_mission_stops(mission.stops)
		session.traffic.set_enabled(save.settings.traffic)
	session.event.connect(func(_k, text): log_label.text = text)
	var vp := SubViewportContainer.new(); vp.stretch = true
	vp.set_anchors_preset(Control.PRESET_FULL_RECT)
	var sv := SubViewport.new(); vp.add_child(sv); add_child(vp)
	view = LineView.new(); view.view_distance = float(save.settings.view_distance)
	sv.add_child(view); view.build(net, first, vehicle)
	hour0 = _start_hour()
	view.set_hour(hour0)
	# réglages mobiles : pas d'ombres, décor chargé moins loin (cible 4 Go / 30 i/s)
	if OS.has_feature("mobile"):
		view.day_night.sun.shadow_enabled = false
		if view.city: view.city.radius = 450.0
	view.update_from(session, true)
	if view.city: view.city.warm(view.cam.global_position)
	view.cam.current = true
	view.view_distance = float(save.settings.view_distance)
	hud = Label.new(); hud.position = Vector2(20, 10); add_child(hud)
	log_label = Label.new(); log_label.position = Vector2(20, 90); add_child(log_label)
	if free and free.adaptation_notice != "": log_label.text = free.adaptation_notice
	map = MapView.new(); map.size = Vector2(380, 420); map.position = Vector2(880, 100); map.visible = false
	map.setup(session, view); add_child(map)
	_build_controls()
	if not save.settings.tutorial_done:
		tuto = Label.new(); tuto.position = Vector2(200, 300); tuto.text = TUTO[0]
		tuto.mouse_filter = Control.MOUSE_FILTER_STOP
		tuto.gui_input.connect(_tuto_input); add_child(tuto)

func _tuto_input(ev: InputEvent) -> void:
	if (ev is InputEventMouseButton and ev.pressed) or (ev is InputEventScreenTouch and ev.pressed):
		tuto_step += 1
		if tuto_step >= TUTO.size():
			tuto.queue_free(); tuto = null
			save.settings.tutorial_done = true; SaveGame.save_data(save)
		else:
			tuto.text = TUTO[tuto_step]

func _btn(txt: String, pos: Vector2, sz: Vector2, cb: Callable) -> Button:
	var b := Button.new(); b.text = txt; b.position = pos; b.size = sz
	b.pressed.connect(cb); add_child(b); return b

func _build_controls() -> void:
	var sl := VSlider.new(); sl.min_value = -1; sl.max_value = 1; sl.step = 0.05
	sl.position = Vector2(30, 160); sl.size = Vector2(80, 380)
	sl.value_changed.connect(func(v): notch = v)
	add_child(sl)
	var x := 160.0
	_btn("Portes", Vector2(x, 560), Vector2(150, 90), func(): session.set_doors(not session.doors_open))
	_btn("Klaxon", Vector2(x + 160, 560), Vector2(140, 90), func(): log_label.text = "Dring !")
	_btn("Caméra", Vector2(x + 310, 560), Vector2(140, 90), func(): external_cam = not external_cam)
	_btn("Carte", Vector2(x + 460, 560), Vector2(120, 90), func(): map.visible = not map.visible)
	_btn("Pantogr.", Vector2(x + 590, 640), Vector2(130, 60), func(): session.toggle_pantograph(); log_label.text = "Pantographe " + ("levé" if session.pantograph_up else "baissé"))
	var eb := _btn("URGENCE", Vector2(1080, 540), Vector2(180, 130), func(): notch = -1.0; sl.value = -1.0; session.phys.step(0.0, -1.0, 0.0, true))
	eb.modulate = Color(1, 0.3, 0.3)
	_btn("Pause", Vector2(1100, 10), Vector2(150, 70), func(): paused = not paused; _persist())
	_btn("Menu", Vector2(940, 10), Vector2(150, 70), func(): _persist(); _build_menu())
	if free_mode:
		_btn("Aiguillage", Vector2(x + 590, 560), Vector2(150, 90), _toggle_switch)
		_btn("Remise sur voie", Vector2(x + 750, 560), Vector2(170, 90), func(): free.rerail(); log_label.text = "Remise sur voie")
		_btn("Trafic ±", Vector2(x + 930, 560), Vector2(100, 90), func(): free.set_traffic(not free.traffic.enabled); save.settings.traffic = free.traffic.enabled)

func _toggle_switch() -> void:
	var e: TrackGraph.Edge = net.graph.edges[free.edge_id]
	var outs: Array = net.graph.out_edges.get(e.to_node, [])
	if outs.size() < 2:
		log_label.text = "Pas d'aiguillage devant"; return
	var nb: int = (int(net.graph.switch_state.get(e.to_node, 0)) + 1) % outs.size()
	log_label.text = ("Aiguillage → " + str(outs[nb])) if free.select_branch(e.to_node, nb) else "Aiguillage occupé : manœuvre refusée"

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

func _unhandled_input(ev: InputEvent) -> void:
	# glisser horizontalement : tourner la caméra extérieure autour de la rame
	if view == null: return
	if ev is InputEventScreenDrag:
		view.orbit -= ev.relative.x * 0.006
	elif ev is InputEventMouseMotion and (ev.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		view.orbit -= ev.relative.x * 0.006

func _process(dt: float) -> void:
	if session == null: return
	if not paused and not session.finished:
		session.tick(minf(dt, 0.1), notch, false)
	view.set_hour(current_hour())
	view.update_from(session, external_cam)
	if map.visible: map.queue_redraw()
	var st: Dictionary = {}
	if not session.stops.is_empty():
		st = session.stops[mini(session.next_station, session.stops.size() - 1)]
	hud.text = view.day_night.clock_text() + "  |  " + "%d km/h (limite %d)  |  %s  |  voyageurs %d  |  portes %s%s%s" % [
		roundi(session.phys.speed * 3.6), roundi(session.speed_limit() * 3.6),
		("prochain : " + str(st.get("name", "")) if not free_mode else "mode libre"), session.phys.passengers,
		"ouvertes" if session.doors_open else "fermées", ("  | COUPURE ALIM." if not session.power_ok else "") + ("  | SURVITESSE" if session.overspeed else ""),
		("  | INCIDENT : " + free.incident) if free and free.incident != "" else ""]
	if session.finished and not _result_saved:
		_result_saved = true
		var d := session.debrief()
		SaveGame.add_result(save, net_path, vehicle.id, d)
		SaveGame.save_data(save)
		log_label.text = "%s — %s  (menu pour recommencer)" % ["MISSION RÉUSSIE" if d.success else "ÉCHEC", d.reason]
