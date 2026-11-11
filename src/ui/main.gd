extends Control
## Menu : mode -> matériel -> départ ; HUD tactile, carte, tutoriel, sauvegarde.

const NETS := {"Angers — ligne A (données provisoires)": "res://data/networks/angers_a.json"}

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
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.custom_minimum_size = Vector2(520, 0)
	add_child(box)
	var title := Label.new(); title.text = "Tram Sim France"; box.add_child(title)
	var net_opt := OptionButton.new()
	for k in NETS: net_opt.add_item(k)
	box.add_child(net_opt)
	var veh_opt := OptionButton.new()
	var vehicles := VehicleLibrary.all()
	for v in vehicles: veh_opt.add_item(v.family)
	box.add_child(veh_opt)
	var sheet := Label.new(); box.add_child(sheet)
	var mode_opt := OptionButton.new(); mode_opt.add_item("Mission horaire"); mode_opt.add_item("Mode libre"); box.add_child(mode_opt)
	var traffic_cb := CheckBox.new(); traffic_cb.text = "Trafic automobile"
	traffic_cb.button_pressed = save.settings.traffic; box.add_child(traffic_cb)
	var go := Button.new(); go.custom_minimum_size = Vector2(0, 90); box.add_child(go)
	var refresh := func(_i = 0):
		var v: VehicleProfile = vehicles[veh_opt.selected]
		var path: String = NETS.values()[net_opt.selected]
		var n := NetworkLoader.new(); n.load_file(path)
		var supply: Array = n.supplies; var guid := str(n.meta.get("guidance", "steel"))
		var ok := Compatibility.mission_allowed(v, supply, guid)
		sheet.text = "%s — %.0f m, %.0f t, %.0f kW, %d places, alim. %s\nValeurs estimées : %s" % [v.family, v.length_m, v.empty_mass_kg / 1000.0, v.power_kw, v.capacity, v.supply, ", ".join(v.estimated)]
		var libre: bool = mode_opt.selected == 1
		go.disabled = not ok and not libre
		go.text = "Démarrer" if (ok or libre) else "Matériel incompatible avec ce réseau (essayez le mode libre)"
		if libre and not ok: go.text = "Démarrer — " + Compatibility.adaptation_notice(v, supply, guid)
	for o in [net_opt, veh_opt, mode_opt]: o.item_selected.connect(refresh)
	refresh.call()
	go.pressed.connect(func():
		save.settings.traffic = traffic_cb.button_pressed
		net_path = NETS.values()[net_opt.selected]
		vehicle = vehicles[veh_opt.selected]
		free_mode = mode_opt.selected == 1
		_start())

func _start() -> void:
	_clear()
	_result_saved = false
	net = NetworkLoader.new()
	var errs := net.load_file(net_path)
	if not errs.is_empty():
		push_error(str(errs)); _build_menu(); return
	var first: String = net.meta.edges[0].id
	if free_mode:
		var e := first; var o := 100.0
		if save.free.get("network", "") == net_path:
			e = save.free.edge; o = float(save.free.offset)
		free = FreeSession.new(net, vehicle, e, o, save.settings.traffic)
		session = free
	else:
		var sched: Array[float] = [120.0, 260.0, 470.0, 610.0]
		session = MissionSession.new(net, vehicle, first, 100.0, sched, 40)
		session.traffic.set_enabled(save.settings.traffic)
	session.event.connect(func(_k, text): log_label.text = text)
	var vp := SubViewportContainer.new(); vp.stretch = true
	vp.set_anchors_preset(Control.PRESET_FULL_RECT)
	var sv := SubViewport.new(); vp.add_child(sv); add_child(vp)
	view = LineView.new(); sv.add_child(view); view.build(net, first)
	view.cam.current = true
	view.cam.far = float(save.settings.view_distance) * 2.0
	hud = Label.new(); hud.position = Vector2(20, 10); add_child(hud)
	log_label = Label.new(); log_label.position = Vector2(20, 90); add_child(log_label)
	if free and free.adaptation_notice != "": log_label.text = free.adaptation_notice
	map = MapView.new(); map.size = Vector2(700, 160); map.position = Vector2(290, 100); map.visible = false
	map.setup(session, view.edge_origin); add_child(map)
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

func _process(dt: float) -> void:
	if session == null: return
	if not paused and not session.finished:
		session.tick(minf(dt, 0.1), notch, false)
	view.update_from(session, external_cam)
	if map.visible: map.queue_redraw()
	var st: Dictionary = {}
	if not session.net.stations.is_empty():
		st = session.net.stations[mini(session.next_station, session.net.stations.size() - 1)]
	hud.text = "%d km/h (limite %d)  |  %s  |  voyageurs %d  |  portes %s%s%s" % [
		session.phys.speed * 3.6, session.speed_limit() * 3.6,
		("prochain : " + str(st.get("name", "")) if not free_mode else "mode libre"), session.phys.passengers,
		"ouvertes" if session.doors_open else "fermées", ("  | COUPURE ALIM." if not session.power_ok else "") + ("  | SURVITESSE" if session.overspeed else ""),
		("  | INCIDENT : " + free.incident) if free and free.incident != "" else ""]
	if session.finished and not _result_saved:
		_result_saved = true
		var d := session.debrief()
		SaveGame.add_result(save, net_path, vehicle.id, d)
		SaveGame.save_data(save)
		log_label.text = "%s — %s  (menu pour recommencer)" % ["MISSION RÉUSSIE" if d.success else "ÉCHEC", d.reason]
