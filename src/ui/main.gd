extends Control
## Menu minimal + HUD tactile. Plein écran paysage ; commandes grandes, pouce-friendly.

const NET_PATH := "res://data/networks/angers_a.json"

var session: MissionSession
var view: LineView
var net: NetworkLoader
var notch := 0.0
var external_cam := true
var paused := false
var hud: Label
var log_label: Label
var panel: Control

func _ready() -> void:
	_build_menu()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		paused = true

func _build_menu() -> void:
	_clear()
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	add_child(box); panel = box
	var t := Label.new(); t.text = "Tram Sim France — Angers, ligne A (données provisoires)"
	box.add_child(t)
	var b := Button.new(); b.text = "Mission : Citadis 302"; b.custom_minimum_size = Vector2(420, 90)
	b.pressed.connect(_start_mission); box.add_child(b)

func _clear() -> void:
	for c in get_children(): c.queue_free()
	if view: view.queue_free(); view = null

func _start_mission() -> void:
	_clear()
	net = NetworkLoader.new()
	var errs := net.load_file(NET_PATH)
	if not errs.is_empty():
		push_error(str(errs)); return
	var sched: Array[float] = [120.0, 260.0, 470.0, 610.0]
	session = MissionSession.new(net, VehicleLibrary.citadis_302(), "e0", 100.0, sched, 40)
	session.event.connect(func(_k, text): log_label.text = text)
	var vp := SubViewportContainer.new(); vp.stretch = true
	vp.set_anchors_preset(Control.PRESET_FULL_RECT)
	var sv := SubViewport.new(); vp.add_child(sv); add_child(vp)
	view = LineView.new(); sv.add_child(view); view.build(net, "e0")
	view.cam.current = true
	hud = Label.new(); hud.position = Vector2(20, 10); add_child(hud)
	log_label = Label.new(); log_label.position = Vector2(20, 90); add_child(log_label)
	_build_controls()

func _btn(txt: String, pos: Vector2, size: Vector2, cb: Callable) -> Button:
	var b := Button.new(); b.text = txt; b.position = pos; b.size = size
	b.pressed.connect(cb); add_child(b); return b

func _build_controls() -> void:
	var sl := VSlider.new(); sl.min_value = -1; sl.max_value = 1; sl.step = 0.05
	sl.position = Vector2(30, 160); sl.size = Vector2(80, 380)
	sl.value_changed.connect(func(v): notch = v)
	add_child(sl)
	var x := 160.0
	_btn("Portes", Vector2(x, 560), Vector2(160, 90), func(): session.set_doors(not session.doors_open))
	_btn("Avertisseur", Vector2(x + 180, 560), Vector2(180, 90), func(): log_label.text = "Dring !")
	_btn("Caméra", Vector2(x + 380, 560), Vector2(160, 90), func(): external_cam = not external_cam)
	var eb := _btn("URGENCE", Vector2(1080, 540), Vector2(180, 130), func(): session.tick(0.0, -1.0, true); notch = -1.0)
	eb.modulate = Color(1, 0.3, 0.3)
	_btn("Pause", Vector2(1100, 10), Vector2(150, 70), func(): paused = not paused)

func _process(dt: float) -> void:
	if session == null: return
	var emergency := false
	if not paused and not session.finished:
		session.tick(minf(dt, 0.1), notch, emergency)
	view.update_from(session, external_cam)
	var st := session.net.stations[mini(session.next_station, session.net.stations.size() - 1)]
	hud.text = "%d km/h (limite %d)  |  prochain : %s  |  voyageurs %d  |  portes %s%s" % [
		session.phys.speed * 3.6, session.speed_limit() * 3.6, st.name, session.phys.passengers,
		"ouvertes" if session.doors_open else "fermées", "  | SURVITESSE" if session.overspeed else ""]
	if session.finished:
		var d := session.debrief()
		log_label.text = "%s — %s" % ["MISSION RÉUSSIE" if d.success else "ÉCHEC", d.reason]
