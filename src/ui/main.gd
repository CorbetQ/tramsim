extends Control
## Accueil, configuration de la partie (mission / mode libre) et interface de conduite.
## Thème : UiTheme (police Atkinson Hyperlegible, panneaux translucides, icônes SVG).
## Interface ancrée et mise à l'échelle (stretch canvas_items, expand) : téléphone, tablette, PC 16:9 à 21:9.
## Commandes : écran tactile/souris et clavier (aide : F1, voir KEYS).

const KEYS := [
	["Z / W / ↑", "Traction (cran suivant)"], ["S / ↓", "Freinage (cran suivant)"], ["X", "Neutre"],
	["Espace", "Freinage d'urgence"], ["O", "Ouvrir / fermer les portes"], ["K", "Cloche"],
	["P", "Alimentation LAC / APS (à l’arrêt)"], ["C", "Caméra cabine / extérieure"], ["M", "Plan du réseau"],
	["A", "Plan du réseau"], ["Tab", "Aiguillage suivant (panneau ouvert)"], ["1 – 3", "Choisir la branche"],
	["V", "Changer de sens (mode libre)"], ["L", "Pilote automatique (mode libre)"], ["R", "Remise sur voie (mode libre)"], ["T", "Trafic automobile (mode libre)"],
	["Échap", "Pause / fermer"], ["F1", "Cette aide"], ["F11", "Plein écran"], ["Molette / pincer", "Zoom caméra"],
	["Glisser", "Tourner autour de la rame"]]
const KEYS_HELP := "F1 : aide clavier · Z/S traction-freinage · Espace urgence · O portes · A aiguillages · Échap pause"

const TUTO := [
	["Manipulateur", "À gauche (ou Z / S) : vers le haut = traction, vers le bas = freinage. X = neutre."],
	["Portes et horaire", "À quai : « Portes » (O). Départ portes fermées, à l'heure : aucune avance, 60 s de retard au maximum."],
	["Sécurité", "Signal rouge ou fin de voie dépassés = échec. URGENCE (Espace) = freinage maximal."],
	["Caméra", "« Caméra » (C) : cabine / extérieur ; glisser pour tourner autour de la rame, molette pour zoomer."]]

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
var menu_page := "home"         # "home" | "setup"
var menu_city := ""             # ville sélectionnée (accueil, configuration, fond)
var scenario: Dictionary = {}   # mission scénarisée (MissionCatalog), sinon {}
var home_bg: HomeBackground     # ville vue du ciel derrière les menus
var intro: IntroCamera          # zoom de lancement en cours
var settings_layer: Control
var _menu: Dictionary = {}      # références de la page de menu courante (raccourcis)
var _intro_radius := 0.0
var city_preload: CityPreload
var _city_loading_layer: CanvasLayer
var _city_loading_title: Label
var _city_loading_detail: Label
var _city_retry: Button
var _launching := false
var _departure_context: Dictionary = {}

# interface de conduite
var hud_speed: Speedometer
var hud_info: Label             # prochain arrêt
var _speed_advice: Dictionary = {}
var hud_grade: Label
var hud_sub: Label              # distance / départ
var hud_sched: Label            # écart à l'horaire
var hud_clock: Label
var hud_alert: Label
var hud_switch: Button          # prochain aiguillage (mode libre)
var signal_panel: SignalPanel   # répétiteur de signalisation (signal, aiguille, limite à venir)
var autopilot := Autopilot.new()  # pilote automatique (mode libre)
var autopilot_button: Button
var cam_hud: HBoxContainer       # commandes caméra (zoom vue du dessus) et sortie du mode auto
var ai_trams: AiTrams           # rames en circulation (mode mission)
var explore: ExploreMode        # mode Explorer (caméra libre dans la ville)
var weather := WeatherState.new()
var weather_view: WeatherView
var notch_label: Label
var lever: NotchLever
var power_button: Button
var plan_panel: NetworkPlan
var pause_layer: Control
var debrief_layer: Control
var help_layer: Control
var toasts: VBoxContainer
var lamps: Dictionary = {}      # nom -> [PanelContainer, TextureRect, Label]
var tuto: Control
var tuto_step := 0
var _closing := false
var ui_audio: UiAudio
var tram_audio: TramAudio
var bell: AudioStreamPlayer
var _alert_box: PanelContainer
var _hud_t := 0.0
var _compact := false
var _resize_pending := false
var camera_gestures := MapGestures.new()

func _ready() -> void:
	get_tree().auto_accept_quit = false
	UiLayout.configure(get_window())
	_compact = UiLayout.compact(self)
	get_window().size_changed.connect(func(): UiLayout.configure(get_window()))
	resized.connect(_layout_changed)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = UiTheme.build()
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR   # icônes SVG nettes à toutes les échelles
	save = SaveGame.load_data()
	ui_audio = UiAudio.new(); ui_audio.enabled = bool(save.settings.get("ui_sounds", true)); add_child(ui_audio)
	bell = AudioStreamPlayer.new(); bell.stream = _bell_sound(); add_child(bell)
	_build_menu()

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
	if what == NOTIFICATION_WM_CLOSE_REQUEST and is_node_ready():
		_quit_safely(); return
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and session == null and not is_instance_valid(explore) and menu_page == "home" and settings_layer == null and is_node_ready() and get_tree().get_nodes_in_group("touch_choice_modal").is_empty():
		_quit_safely(); return
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and is_instance_valid(explore):
		explore.leave(); return
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and session == null and is_node_ready():
		var esc := InputEventKey.new(); esc.keycode = KEY_ESCAPE
		_menu_key(KEY_ESCAPE, esc)
		get_tree().quit_on_go_back = false
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		if session != null and not paused:
			_set_paused(true)
		_persist()

## Never quit with a renderer worker waiting on the scene-tree lock.
func _quit_safely() -> void:
	if _closing: return
	_closing = true
	set_process(false)
	_persist()
	if is_instance_valid(city_preload):
		city_preload.set_process(false)
		while city_preload._task >= 0 and not WorkerThreadPool.is_task_completed(city_preload._task):
			await get_tree().process_frame
	_clear()
	if is_instance_valid(home_bg): home_bg.queue_free(); home_bg = null
	if is_instance_valid(city_preload): city_preload.queue_free(); city_preload = null
	await CityScene.drain_background_jobs(get_tree())
	get_tree().quit()

func _persist() -> void:
	if free != null and vehicle != null:
		SaveGame.store_free(save, free, net_path, vehicle.id)
		save.free["weather"]=weather.snapshot()
	SaveGame.save_data(save)

func _clear() -> void:
	camera_gestures.reset()
	for c in get_children():
		if c != bell and c != ui_audio and c != home_bg and c != city_preload and c != _city_loading_layer: c.queue_free()
	if is_instance_valid(intro): intro.queue_free()
	intro = null; settings_layer = null
	view = null; tram_audio = null; session = null; free = null; tuto = null; plan_panel = null; pause_layer = null; debrief_layer = null
	help_layer = null; toasts = null; hud_switch = null; lamps.clear()
	signal_panel = null; autopilot_button = null; cam_hud = null; ai_trams = null; autopilot = Autopilot.new(); explore = null

# ----------------------------------------------------------------------------------------------- menu

func _backdrop() -> void:
	var bg := TextureRect.new(); bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var gt := GradientTexture2D.new(); gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.8, 0.15); gt.fill_to = Vector2(0.0, 1.1); gt.width = 256; gt.height = 256
	var gr := Gradient.new(); gr.set_color(0, Color("#13312f")); gr.set_color(1, UiTheme.BG)
	gt.gradient = gr; bg.texture = gt; bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg); move_child(bg, 0)

## Fond 3D de l'accueil (ville vue du ciel) : conservé d'une page de menu à l'autre, libéré au lancement.
func _bg_allowed() -> bool:
	return DisplayServer.get_name() != "headless" and not get_viewport().disable_3d and bool(save.settings.get("home_bg", true))

func _aerial_needed() -> bool:
	return DisplayServer.get_name() != "headless" and not get_viewport().disable_3d and (bool(save.settings.get("home_bg", true)) or bool(save.settings.get("intro", true)))

func _ensure_city_preload() -> void:
	if is_instance_valid(city_preload): return
	city_preload = CityPreload.new(); city_preload.name = "city_preload"; add_child(city_preload)
	city_preload.completed.connect(_city_data_completed)
	_city_loading_layer = CanvasLayer.new(); _city_loading_layer.layer = 90; _city_loading_layer.name = "city_loading"; add_child(_city_loading_layer)
	var shade := ColorRect.new(); shade.color = Color(0.025, 0.04, 0.06, 0.95)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); shade.mouse_filter = Control.MOUSE_FILTER_STOP
	_city_loading_layer.add_child(shade)
	var center := CenterContainer.new(); center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); shade.add_child(center)
	var box := VBoxContainer.new(); box.custom_minimum_size.x = 280; box.add_theme_constant_override("separation", 18); center.add_child(box)
	_city_loading_title = UiTheme.label_("", 24, UiTheme.TEXT, true); _city_loading_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; box.add_child(_city_loading_title)
	var bar := ProgressBar.new(); bar.indeterminate = true; bar.show_percentage = false; bar.custom_minimum_size.y = 8; box.add_child(bar)
	_city_loading_detail = UiTheme.label_("Préparation de la ville…", 16, UiTheme.MUTED); _city_loading_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; box.add_child(_city_loading_detail)
	_city_retry = UiTheme.button("Réessayer", "play", "primary", Vector2(0, 52)); box.add_child(_city_retry)
	_city_retry.pressed.connect(func(): city_preload.invalidate(); _show_bg(menu_city))
	_city_loading_layer.hide()

func _show_bg(city: String) -> void:
	_ensure_city_preload()
	city_preload.request(city)
	if not city_preload.is_ready(city):
		_city_loading_title.text = "Chargement de " + city
		_city_loading_detail.text = "Préparation de la ville…"
		_city_retry.hide(); _city_loading_layer.show()
		var go: Button = _menu.get("go")
		if is_instance_valid(go): go.disabled = true; go.text = "Chargement…"
		return
	_install_home_bg(city)
	_city_loading_layer.visible = not _ready_for_launch(city)
	_city_loading_title.text = "Chargement de " + city
	_city_loading_detail.text = "Préparation de la vue aérienne…"
	_city_retry.hide()

func _install_home_bg(city: String) -> void:
	if not _aerial_needed():
		if is_instance_valid(home_bg): home_bg.queue_free()
		home_bg = null; return
	if not is_instance_valid(home_bg):
		home_bg = HomeBackground.new(); add_child(home_bg)
		home_bg.city_ready.connect(_home_city_ready)
	move_child(home_bg, 1)
	home_bg.visible = _bg_allowed()
	home_bg.show_city(city)

func _city_data_completed(city: String, error: String) -> void:
	if city != menu_city or session != null or is_instance_valid(explore): return
	if error != "":
		_city_loading_detail.text = error; _city_retry.show(); _city_loading_layer.show()
		return
	if has_meta("deferred_catalogue_pick"):
		set_meta("catalogue_pick", get_meta("deferred_catalogue_pick")); remove_meta("deferred_catalogue_pick")
		_build_menu(); return
	_install_home_bg(city)
	_city_loading_layer.visible = not _ready_for_launch(city)
	_city_loading_detail.text = "Préparation de la vue aérienne…"
	var reload: Callable = _menu.get("reload_city", Callable())
	if reload.is_valid(): reload.call()

func _ready_for_launch(city: String) -> bool:
	if not is_instance_valid(city_preload) or not city_preload.is_ready(city): return false
	return not _aerial_needed() or (is_instance_valid(home_bg) and home_bg.shown == city and not home_bg.is_loading() and home_bg.layer_count() > 0)

func _home_city_ready(city: String) -> void:
	if city != menu_city or session != null or is_instance_valid(explore): return
	_city_loading_layer.hide()
	var refresh: Callable = _menu.get("refresh", Callable())
	if refresh.is_valid(): refresh.call()
	var go: Button = _menu.get("go")
	if _menu.get("auto_start", false) and is_instance_valid(go) and not go.disabled:
		_menu["auto_start"] = false; go.pressed.emit()

## Classe MissionCatalog (autre module) si présente : aucune dépendance à la compilation.
static func _catalog() -> Script:
	for c in ProjectSettings.get_global_class_list():
		if str(c["class"]) == "MissionCatalog" and ResourceLoader.exists(str(c.path)):
			var s = load(str(c.path))
			if s is Script: return s
	return null

static func _has_static(s: Script, m: String) -> bool:
	for d in s.get_script_method_list():
		if str(d.name) == m: return true
	return false

func _scenarios(city: String, source: String) -> Array:
	var cat := _catalog()
	if cat == null or not _has_static(cat, "for_city"): return []
	var out = cat.call("for_city", source)
	if (not out is Array or out.is_empty()) and city != source: out = cat.call("for_city", city)
	return out if out is Array else []

## Marges horizontales adaptées (contenu centré, largeur max) : 16:9 à 21:9, téléphone à PC.
func _page() -> MarginContainer:
	var scroll := TouchScroll.new(); scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; add_child(scroll)
	var m := MarginContainer.new(); m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(m)
	var fit := func():
		var safe := UiLayout.safe_insets(self)
		var side := maxf(12.0 if UiLayout.compact(self) else 28.0, (scroll.size.x - 1640.0) * 0.5)
		m.add_theme_constant_override("margin_left", int(side + safe.x)); m.add_theme_constant_override("margin_right", int(side + safe.z))
		m.add_theme_constant_override("margin_top", int(safe.y) + (12 if UiLayout.compact(self) else 24))
		m.add_theme_constant_override("margin_bottom", int(safe.w) + (12 if UiLayout.compact(self) else 22))
		m.custom_minimum_size.y = scroll.size.y
	scroll.resized.connect(fit); fit.call()
	return m

func _layout_changed() -> void:
	if not is_node_ready() or _resize_pending: return
	if UiLayout.compact(self) == _compact: return
	_resize_pending = true
	_reflow.call_deferred()

func _reflow() -> void:
	_resize_pending = false; _compact = UiLayout.compact(self)
	if session == null:
		_build_menu()
	else:
		for c in get_children():
			if c.is_in_group("driving_hud"):
				remove_child(c); c.queue_free()
		if is_instance_valid(cam_hud): remove_child(cam_hud); cam_hud.queue_free()
		lamps.clear(); _build_hud(); _hud_t = 0.0

func _build_menu() -> void:
	_clear()
	paused = false
	_menu.clear()
	_backdrop()
	if has_meta("catalogue_pick"): menu_page = "setup"
	var cities := NetworkRegistry.cities()
	if not menu_city in cities: menu_city = str(save.settings.get("last_city", ""))
	if not menu_city in cities: menu_city = "Bordeaux" if "Bordeaux" in cities else (cities[0] if not cities.is_empty() else "")
	_show_bg(menu_city)
	get_tree().quit_on_go_back = false
	if menu_page == "setup": _build_setup()
	else: _build_home()

## Dernière partie lancée (réglage last_run), si son réseau existe encore.
func _resume_info() -> Dictionary:
	var r = save.settings.get("last_run", {})
	if not r is Dictionary or not r.has("net_path") or not FileAccess.file_exists(str(r.net_path)): return {}
	return r

func _build_home() -> void:
	var page := _page()
	var row := HBoxContainer.new(); row.add_theme_constant_override("separation", 40); page.add_child(row)
	var lp := UiTheme.panel(Color(UiTheme.SURFACE, 0.74), 24, 22); lp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lp.size_flags_vertical = Control.SIZE_SHRINK_CENTER; lp.size_flags_stretch_ratio = 1.0; row.add_child(lp)
	var left := VBoxContainer.new(); left.add_theme_constant_override("separation", 12); lp.add_child(left)
	var brand := HBoxContainer.new(); brand.add_theme_constant_override("separation", 16); left.add_child(brand)
	var logo := PanelContainer.new(); logo.add_theme_stylebox_override("panel", UiTheme.box(UiTheme.ACCENT, 16, 10)); brand.add_child(logo)
	logo.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	logo.add_child(UiTheme.icon_rect("tram", 40, Color("#04201c")))
	var tv := VBoxContainer.new(); tv.add_theme_constant_override("separation", -4); brand.add_child(tv)
	tv.add_child(UiTheme.label_("Tram Sim France", UiTheme.SIZE_H1 if UiLayout.compact(self) else UiTheme.SIZE_DISPLAY, UiTheme.TEXT, true))
	var sub := UiTheme.label_("Conduisez les tramways de %d villes françaises" % NetworkRegistry.cities().size(), UiTheme.SIZE_SMALL, UiTheme.MUTED)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; tv.add_child(sub)
	var r := _resume_info()
	if not r.is_empty():
		var rb := _card_button("play", "Reprendre la dernière partie", str(r.get("label", "")) + "   ·   R")
		rb.name = "resume"; rb.add_theme_stylebox_override("normal", UiTheme.box(Color(UiTheme.ACCENT, 0.22), 18, 18, Color(UiTheme.ACCENT, 0.6), 1))
		rb.pressed.connect(_resume); left.add_child(rb)
	var cards := [
		["mission", "Mission", "Service horaire réel ou mission scénarisée (aléas).   ·   1", func(): _open_setup(false)],
		["free", "Mode libre", "Le réseau complet : aiguillages, changements de sens, trafic.   ·   2", func(): _open_setup(true)],
		["camera", "Explorer la ville", "Caméra libre au-dessus de %s : stations, monuments, jour et nuit.   ·   3" % menu_city, func(): _start_explore()],
		["tram", "Mode passager", "À pied, montez dans une rame à l’arrêt et voyagez à bord. Intérieurs estimés.", func(): _start_explore(true)],
		["catalogue", "Catalogue des rames", "Fiches techniques, livrées et lignes de chaque matériel.   ·   C", func(): _open_catalogue("")]]
	for c in cards:
		var b := _card_button(c[0], c[1], c[2]); b.pressed.connect(c[3]); left.add_child(b)
		if UiLayout.compact(self): b.custom_minimum_size.y = 72
	var tools := HBoxContainer.new(); tools.add_theme_constant_override("separation", 10); left.add_child(tools)
	var bs := UiTheme.button("Réglages", "switch", "normal", Vector2(0, 48)); bs.name = "settings"; bs.tooltip_text = "Réglages (G)"
	bs.pressed.connect(_open_settings); tools.add_child(bs)
	var bh := UiTheme.button("Aide", "help", "ghost", Vector2(0, 48)); bh.tooltip_text = "Aide clavier (F1)"; bh.pressed.connect(_toggle_help); tools.add_child(bh)
	var hint := HFlowContainer.new(); hint.add_theme_constant_override("h_separation", 8); hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tools.add_child(hint); hint.visible = not UiLayout.compact(self)
	for k in [["Entrée", "continuer"], ["Échap", "retour"]]:
		hint.add_child(UiTheme.keycap(k[0])); hint.add_child(UiTheme.label_(k[1], UiTheme.SIZE_SMALL, UiTheme.MUTED))
	# droite : la ville en fond, légende (ville, lignes aux couleurs GTFS)
	var right := VBoxContainer.new(); right.size_flags_horizontal = Control.SIZE_EXPAND_FILL; right.size_flags_stretch_ratio = 1.1
	right.alignment = BoxContainer.ALIGNMENT_END; row.add_child(right); right.visible = not UiLayout.compact(self)
	right.add_child(_city_caption(menu_city))
	UiTheme.fade_in(page, 0.3)

## Légende du fond : nom de la ville et pastilles des lignes.
func _city_caption(city: String) -> Control:
	var p := UiTheme.panel(Color(UiTheme.SURFACE, 0.6), 16, 12); p.size_flags_horizontal = Control.SIZE_SHRINK_END; p.name = "city_caption"
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 6); p.add_child(v)
	var t := UiTheme.label_(city, UiTheme.SIZE_H2, UiTheme.TEXT, true); t.name = "caption_city"; v.add_child(t)
	var h := HFlowContainer.new(); h.add_theme_constant_override("h_separation", 6); h.add_theme_constant_override("v_separation", 6); v.add_child(h)
	var seen := {}
	for e in NetworkRegistry.entries():
		if e.city != city or seen.has(str(e.line)): continue
		seen[str(e.line)] = true
		h.add_child(UiTheme.line_badge(str(e.line), _line_color(str(e.path)), UiTheme.SIZE_SMALL))
	v.add_child(UiTheme.label_("Vue du ciel · réseau de tramway", UiTheme.SIZE_CAPTION, UiTheme.MUTED))
	return p

## Mode Explorer : visite libre de la ville sélectionnée (réseau complet, décor en streaming).
func _start_explore(passenger: bool = false) -> void:
	var path := ""
	var first := ""
	for e in NetworkRegistry.entries():
		if str(e.city) != menu_city: continue
		if first == "": first = str(e.path)
		var src := str(Catalogue.meta_of(str(e.path)).get("source_id", ""))
		if src != "" and FileAccess.file_exists("res://data/free/%s.json" % src): path = "res://data/free/%s.json" % src; break
	if path == "": path = first
	if path == "": return
	if is_instance_valid(home_bg): home_bg.queue_free()
	home_bg = null
	get_tree().quit_on_go_back = false
	_clear()
	explore = PassengerMode.new() if passenger else ExploreMode.new(); add_child(explore)
	explore.exited.connect(func(): explore = null; _build_menu())
	if not explore.start(menu_city, path, _start_hour() if int(save.settings.get("time_mode", 0)) != 0 else 15.0, float(save.settings.view_distance), bool(save.settings.get("ai_trams", true))):
		explore.queue_free(); explore = null; _build_menu()
	else:explore.weather.configure(str(save.settings.get("weather","clear")))
	var effects := VisualEffects.new()
	if is_instance_valid(explore):explore.view.add_child(effects);effects.setup(explore.view,str(save.settings.get("visual_profile","economy" if OS.has_feature("mobile") else "balanced")))
	else:effects.free()

func _open_setup(free_: bool) -> void:
	free_mode = free_; menu_page = "setup"; _build_menu()

func _spacer(h: float) -> Control:
	var s := Control.new(); s.custom_minimum_size = Vector2(0, h); s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return s

## Carte cliquable : icône, titre, description.
func _card_button(icon_name: String, title: String, desc: String) -> Button:
	var b := Button.new(); b.custom_minimum_size = Vector2(0, 84); b.name = "card_" + icon_name
	b.tooltip_text = desc; b.set_meta("title", title)
	b.add_theme_stylebox_override("normal", UiTheme.box(Color(UiTheme.SURFACE_2, 0.8), 18, 16, UiTheme.BORDER, 1))
	b.add_theme_stylebox_override("hover", UiTheme.box(UiTheme.SURFACE_3, 18, 16, Color(UiTheme.ACCENT, 0.7), 2))
	b.add_theme_stylebox_override("pressed", UiTheme.box(Color(UiTheme.ACCENT, 0.3), 18, 16, UiTheme.ACCENT, 2))
	b.add_theme_stylebox_override("focus", UiTheme.box(Color.TRANSPARENT, 18, 16, UiTheme.HIGHLIGHT, 2))
	var h := HBoxContainer.new(); h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 16; h.offset_right = -16; h.add_theme_constant_override("separation", 16); h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(h)
	var ib := PanelContainer.new(); ib.add_theme_stylebox_override("panel", UiTheme.box(Color(UiTheme.ACCENT, 0.16), 14, 10))
	ib.size_flags_vertical = Control.SIZE_SHRINK_CENTER; ib.mouse_filter = Control.MOUSE_FILTER_IGNORE; h.add_child(ib)
	ib.add_child(UiTheme.icon_rect(icon_name, 30, UiTheme.ACCENT))
	var v := VBoxContainer.new(); v.alignment = BoxContainer.ALIGNMENT_CENTER; v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE; h.add_child(v)
	v.add_child(UiTheme.label_(title, UiTheme.SIZE_H2, UiTheme.TEXT, true))
	var d := UiTheme.label_(desc, UiTheme.SIZE_SMALL, UiTheme.MUTED); d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; v.add_child(d)
	d.max_lines_visible = 2; d.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	h.add_child(UiTheme.icon_rect("chevron", 22, UiTheme.MUTED))
	UiTheme.hover_fx(b)
	return b

## Carte d'étape numérotée de la configuration.
func _step(parent: Control, n: int, title: String) -> VBoxContainer:
	var p := UiTheme.panel(Color(UiTheme.SURFACE, 0.8), 16, 14); parent.add_child(p)
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 10); p.add_child(v)
	var h := HBoxContainer.new(); h.add_theme_constant_override("separation", 10); v.add_child(h)
	var num := UiTheme.label_(str(n), UiTheme.SIZE_SMALL, Color("#04201c"), true); num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	num.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	num.add_theme_stylebox_override("normal", UiTheme.box(UiTheme.ACCENT, 13, 6)); num.custom_minimum_size = Vector2(28, 28)
	h.add_child(num)
	h.add_child(UiTheme.label_(title, UiTheme.SIZE_BODY, UiTheme.TEXT, true))
	return v

const MISSION_TYPES := {"service": ["Service", "clock"], "detour": ["Déviation", "route"], "depot": ["Dépôt", "home"],
	"incident": ["Incident", "flag"], "night": ["Nuit", "clock"], "rush": ["Pointe", "clock"], "training": ["Formation", "help"]}
const CONDITIONS := {"detour": "Déviation", "flood": "Inondation", "leaves": "Feuilles mortes", "depot": "Dépôt", "rain": "Pluie",
	"snow": "Neige", "night": "Nuit", "fog": "Brouillard", "works": "Travaux", "traffic": "Trafic dense", "crowd": "Affluence",
	"power_cut": "Coupure d'alimentation", "signal_fault": "Panne de signal"}

static func _cond_label(c) -> String:
	var k := str(c.get("type", c.get("id", ""))) if c is Dictionary else str(c)
	return CONDITIONS.get(k, k.capitalize())

## Carte de mission scénarisée : type, difficulté, durée, conditions.
func _mission_card(m: Dictionary) -> Button:
	var b := Button.new(); b.toggle_mode = true; b.name = "mission_" + str(m.get("id", "x")).validate_node_name()
	b.set_meta("label", str(m.get("title", ""))); b.custom_minimum_size = Vector2(0, 76)
	b.add_theme_stylebox_override("normal", UiTheme.box(Color(1, 1, 1, 0.05), 14, 12, UiTheme.BORDER, 1))
	b.add_theme_stylebox_override("hover", UiTheme.box(Color(1, 1, 1, 0.1), 14, 12, Color(UiTheme.ACCENT, 0.5), 1))
	b.add_theme_stylebox_override("pressed", UiTheme.box(Color(UiTheme.ACCENT, 0.22), 14, 12, UiTheme.ACCENT, 2))
	var v := VBoxContainer.new(); v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.offset_left = 12; v.offset_right = -12; v.offset_top = 8; v.offset_bottom = -8; v.add_theme_constant_override("separation", 4); b.add_child(v)
	var h := HBoxContainer.new(); h.add_theme_constant_override("separation", 8); h.mouse_filter = Control.MOUSE_FILTER_IGNORE; v.add_child(h)
	var ty: Array = MISSION_TYPES.get(str(m.get("type", "service")), [str(m.get("type", "Mission")).capitalize(), "mission"])
	h.add_child(UiTheme.icon_rect(ty[1], 20, UiTheme.ACCENT))
	var t := UiTheme.label_(str(m.get("title", "Mission")), UiTheme.SIZE_SMALL, UiTheme.TEXT, true); t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.clip_text = true; t.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS; h.add_child(t)
	if str(m.get("line", "")) != "": h.add_child(UiTheme.line_badge(str(m.line), UiTheme.INFO, UiTheme.SIZE_CAPTION))
	var diff := clampi(int(m.get("difficulty", 1)), 1, 3)
	var info := "%s · %s · ≈ %d min" % [ty[0], "●".repeat(diff) + "○".repeat(3 - diff), int(m.get("duration_min", 0))]
	var conds: Array = m.get("conditions", []) if m.get("conditions", []) is Array else []
	if not conds.is_empty(): info += " · " + ", ".join(conds.map(_cond_label))
	var l := UiTheme.label_(info, UiTheme.SIZE_CAPTION, UiTheme.MUTED); l.clip_text = true; l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	v.add_child(l)
	b.tooltip_text = str(m.get("description", ""))
	return b

func _build_setup() -> void:
	var compact := UiLayout.compact(self)
	var page := _page()
	var col := VBoxContainer.new(); col.add_theme_constant_override("separation", 12); page.add_child(col)
	# barre supérieure : retour, mode (segmenté), catalogue, réglages
	var top := HBoxContainer.new(); top.add_theme_constant_override("separation", 10); col.add_child(top)
	var back := UiTheme.button("Accueil", "back", "ghost", Vector2(0, 52)); back.name = "back"; top.add_child(back)
	back.tooltip_text = "Retour à l'accueil (Échap)"
	back.pressed.connect(func(): menu_page = "home"; _build_menu())
	var title := UiTheme.label_("Préparer le service", UiTheme.SIZE_H1, UiTheme.TEXT, true)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL; top.add_child(title); title.visible = not compact
	if compact:
		var fill_ := Control.new(); fill_.size_flags_horizontal = Control.SIZE_EXPAND_FILL; top.add_child(fill_)
	var seg := PanelContainer.new(); seg.add_theme_stylebox_override("panel", UiTheme.box(Color(0, 0, 0, 0.4), 14, 4)); top.add_child(seg)
	var modes := HBoxContainer.new(); modes.add_theme_constant_override("separation", 4); seg.add_child(modes)
	var grp := ButtonGroup.new()
	var b_mis := UiTheme.button("Mission" if compact else "Mission  (1)", "mission", "chip", Vector2(0, 48)); b_mis.toggle_mode = true; b_mis.button_group = grp
	var b_free := UiTheme.button("Libre" if compact else "Mode libre  (2)", "free", "chip", Vector2(0, 48)); b_free.toggle_mode = true; b_free.button_group = grp
	modes.add_child(b_mis); modes.add_child(b_free)
	b_free.button_pressed = free_mode; b_mis.button_pressed = not free_mode
	var cities := NetworkRegistry.cities()
	var city_ref := [menu_city]
	var cat_btn := UiTheme.button("" if compact else "Catalogue", "catalogue", "normal", Vector2(52, 52)); top.add_child(cat_btn)
	cat_btn.tooltip_text = "Catalogue des rames (C) : fiches techniques, livrées, choix du matériel"
	cat_btn.pressed.connect(func(): _open_catalogue(city_ref[0]))
	var set_btn := UiTheme.button("", "switch", "normal", Vector2(52, 52)); set_btn.tooltip_text = "Réglages (G)"; set_btn.name = "settings"
	set_btn.pressed.connect(_open_settings); top.add_child(set_btn)
	# corps : étapes à gauche, la ville au centre (fond), résumé et lancement à droite
	var body := HBoxContainer.new(); body.add_theme_constant_override("separation", 18); body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(body)
	var sc := TouchScroll.new(); sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL; sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.size_flags_stretch_ratio = 1.0; body.add_child(sc)
	var box := VBoxContainer.new(); box.size_flags_horizontal = Control.SIZE_EXPAND_FILL; box.add_theme_constant_override("separation", 10)
	sc.add_child(box)
	var s1 := _step(box, 1, "Ville")
	# grand écran : liste filtrable + carte de France ; compact : sélecteur plein écran avec recherche
	var picker: Control
	if compact:
		var co := _opt(s1, "Ville"); co.choice_title = "Ville"
		for c in cities: co.add_item(c)
		co.selected = maxi(0, cities.find(city_ref[0])); picker = co
	else:
		picker = CityPicker.new(cities, city_ref[0], true); s1.add_child(picker)
	var s2 := _step(box, 2, "Ligne et départ")
	var line_row := _row(s2, "Ligne"); var line_opt: TouchChoice = line_row.get_child(1); line_opt.name = "line_choice"
	var scen_box := VBoxContainer.new(); scen_box.add_theme_constant_override("separation", 6); scen_box.name = "missions"; s2.add_child(scen_box)
	var mis_row := _row(s2, "Service"); var mis_opt: TouchChoice = mis_row.get_child(1)
	var st_row := _row(s2, "Départ"); var st_opt: TouchChoice = st_row.get_child(1); st_opt.name = "stop_choice"
	var s3 := _step(box, 3, "Rame")
	var veh_opt := _opt(s3, "Matériel")
	var specs := HFlowContainer.new(); specs.add_theme_constant_override("h_separation", 8); specs.add_theme_constant_override("v_separation", 8)
	s3.add_child(specs)
	var est := UiTheme.label_("", UiTheme.SIZE_CAPTION, UiTheme.MUTED); est.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; s3.add_child(est)
	var s4 := _step(box, 4, "Ambiance")
	var time_opt := _opt(s4, "Heure")
	for t in ["Heure réelle du service", "Jour (12 h)", "Coucher de soleil (20 h)", "Nuit (23 h)", "Cycle accéléré (1 h = 1 min)"]: time_opt.add_item(t)
	time_opt.selected = int(save.settings.get("time_mode", 0))
	var traffic_cb := CheckButton.new(); traffic_cb.text = "Trafic automobile"; traffic_cb.button_pressed = save.settings.traffic
	traffic_cb.custom_minimum_size = Vector2(0, 48); s4.add_child(traffic_cb)
	if not compact:   # fenêtre sur la ville (fond 3D)
		var gap := Control.new(); gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL; gap.size_flags_stretch_ratio = 0.45
		gap.mouse_filter = Control.MOUSE_FILTER_IGNORE; body.add_child(gap)
	# colonne droite : aperçu, résumé de la sélection, lancement (toujours visibles)
	var right := VBoxContainer.new(); right.add_theme_constant_override("separation", 10); right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_stretch_ratio = 0.62 if not compact else 0.8; body.add_child(right)
	var pc := UiTheme.panel(Color(0, 0, 0, 0.35), 20, 6); right.add_child(pc); pc.visible = not compact
	var preview := TramPreview.new(); pc.add_child(preview); preview.custom_minimum_size = Vector2(300, 190)
	var sp := UiTheme.panel(Color(UiTheme.SURFACE, 0.86), 18, 14); sp.size_flags_vertical = Control.SIZE_EXPAND_FILL; sp.name = "summary"; right.add_child(sp)
	var sv := VBoxContainer.new(); sv.add_theme_constant_override("separation", 6); sp.add_child(sv)
	var sh := HBoxContainer.new(); sh.add_theme_constant_override("separation", 10); sv.add_child(sh)
	var badge := UiTheme.line_badge("", UiTheme.INFO, UiTheme.SIZE_H2); badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER; sh.add_child(badge)
	sh.add_child(UiTheme.label_("Votre sélection", UiTheme.SIZE_BODY, UiTheme.TEXT, true))
	var grid := GridContainer.new(); grid.columns = 2; grid.add_theme_constant_override("h_separation", 10); sv.add_child(grid)
	var sum_vals := {}
	for k in ["Mode", "Ville", "Ligne", "Mission", "Rame"]:
		grid.add_child(UiTheme.label_(k.to_upper(), UiTheme.SIZE_CAPTION, UiTheme.MUTED, true))
		var val := UiTheme.label_("", UiTheme.SIZE_SMALL, UiTheme.TEXT); val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		val.clip_text = true; val.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS; grid.add_child(val); sum_vals[k] = val
	var sheet := sum_vals["Mission"] as Label
	var spacer_ := Control.new(); spacer_.size_flags_vertical = Control.SIZE_EXPAND_FILL; sv.add_child(spacer_)
	var go := UiTheme.button("Lancer", "play", "primary", Vector2(0, 64 if compact else 72)); go.add_theme_font_size_override("font_size", 22 if compact else 28)
	go.name = "start"; go.tooltip_text = "Lancer (Entrée)"; sv.add_child(go)
	_menu = {"go": go, "picker": picker, "b_mis": b_mis, "b_free": b_free, "back": back}
	# état du menu (tableaux partagés : modifiés en place depuis les lambdas)
	var all_nets: Array = NetworkRegistry.entries()
	var city_nets: Array = []
	var mis_list: Array = []
	var st_list: Array = []
	var vehicles: Array = []
	var free_lines: Array = []
	var scen_list: Array = []
	var scen_ref := [{}]
	var cur_meta: Dictionary = {}
	var free_path := func() -> String: return "res://data/free/%s.json" % _source_of(city_nets)
	var refresh_ref := [Callable()]
	var build_scen := func():
		for c in scen_box.get_children(): c.queue_free()
		scen_ref[0] = {}
		if scen_list.is_empty() or b_free.button_pressed:
			scen_box.visible = false; return
		scen_box.visible = true
		var sg := ButtonGroup.new()
		var gtfs := _mission_card({"id": "gtfs", "type": "service", "title": "Service horaire réel (GTFS)", "difficulty": 1,
			"duration_min": 0, "description": "Desserte d'un service réel : choisir l'horaire ci-dessous."})
		gtfs.button_group = sg; gtfs.button_pressed = true; scen_box.add_child(gtfs)
		gtfs.pressed.connect(func(): scen_ref[0] = {}; mis_row.visible = true; refresh_ref[0].call())
		for m in scen_list:
			var card := _mission_card(m); card.button_group = sg; scen_box.add_child(card)
			card.pressed.connect(func(): scen_ref[0] = m; mis_row.visible = false; refresh_ref[0].call())
	var fill := func():
		var is_free := b_free.button_pressed
		line_row.visible = true; mis_row.visible = not is_free and scen_ref[0].is_empty(); st_row.visible = is_free
		city_nets.clear()
		city_nets.append_array(all_nets.filter(func(e): return e.city == city_ref[0] and (is_free or not e.get("free_only", false))))
		if city_nets.is_empty():
			vehicles.clear(); st_list.clear(); line_opt.clear(); mis_opt.clear(); st_opt.clear()
			go.disabled = true; go.text = "Aucun service disponible"; return
		var reset: bool = line_opt.item_count == 0 or line_opt.get_meta("city", "") != city_ref[0] or line_opt.get_meta("free_mode", not is_free) != is_free
		if reset and not is_free:
			line_opt.clear()
			for e in city_nets:
				line_opt.add_icon_item(_swatch(_line_color(str(e.path))), "%s — %s%s" % [e.line, e.long_name, "  (tram-train)" if e.kind == "tram-train" else ""])
		var selected_path: String = free_path.call() if is_free and FileAccess.file_exists(free_path.call()) else str(city_nets[clampi(line_opt.selected, 0, city_nets.size() - 1)].path)
		var n: NetworkLoader = city_preload.network(selected_path) if city_preload.is_ready(city_ref[0]) else null
		if n == null:
			vehicles.clear(); st_list.clear(); go.disabled = true; go.text = "Chargement…"; return
		cur_meta.clear(); cur_meta.merge(n.meta)
		free_lines.clear()
		if is_free:
			free_lines.append_array(FreeStartCatalog.lines(city_nets, n))
			if reset:
				line_opt.clear()
				for choice in free_lines: line_opt.add_item(choice.label)
			if not free_lines.is_empty():
				var selected: Dictionary = free_lines[clampi(line_opt.selected, 0, free_lines.size() - 1)]
				cur_meta["line"] = selected.line; cur_meta["kind"] = selected.kind
		line_opt.set_meta("city", city_ref[0]); line_opt.set_meta("free_mode", is_free)
		mis_list.clear(); mis_list.append_array(n.missions())
		mis_opt.clear()
		for m in mis_list: mis_opt.add_item("%s → %s" % [str(m.start_time).substr(0, 5), m.headsign])
		if mis_list.is_empty(): mis_opt.add_item("Service de démonstration")
		st_list.clear(); st_opt.clear()
		var available: Array = FreeStartCatalog.stops(n, free_lines[clampi(line_opt.selected, 0, free_lines.size() - 1)]) if is_free and not free_lines.is_empty() else n.stations
		var counts := {}; var seen := {}
		for station in available: counts[station.name] = int(counts.get(station.name, 0)) + 1
		for station in available:
			var name_: String = station.name
			seen[name_] = int(seen.get(name_, 0)) + 1
			st_list.append(station)
			st_opt.add_item(name_ + (" — quai %d" % seen[name_] if counts[name_] > 1 else ""))
		vehicles.clear(); veh_opt.clear()
		if is_free:
			var fleet := StockCatalog.for_network(cur_meta, n.supplies)
			if cur_meta.get("kind") == "tram-train": fleet.sort_custom(func(a, b): return a.family == "citadis_dualis" and b.family != "citadis_dualis")
			for entry in fleet:
				vehicles.append(VehicleLibrary.for_fleet(entry,cur_meta))
				veh_opt.add_item(str(entry.name)+" · "+str(entry.city)+(" · FICTIF" if entry.fictional else ""))
		else:
			for f in TramModel.fleet_for(n.meta):
				vehicles.append(VehicleLibrary.for_fleet(f,n.meta));veh_opt.add_item(f.name)
		cur_meta["required_supplies"] = n.supplies.duplicate()
	var refresh := func(_i = 0):
		if vehicles.is_empty(): go.disabled = true; return
		var is_free := b_free.button_pressed
		var v: VehicleProfile = vehicles[maxi(veh_opt.selected, 0)]
		var supply:Array=cur_meta.get("required_supplies",[str(cur_meta.get("supply","overhead"))])
		var guid := str(cur_meta.get("guidance", "steel"))
		var ok := Compatibility.mission_allowed(v, supply, guid)
		preview.show_tram(cur_meta, v)
		for c in specs.get_children(): c.queue_free()
		for s in ["%.1f m" % v.length_m, "%.0f t" % (v.empty_mass_kg / 1000.0), "%.0f kW" % v.power_kw, "%d places" % v.capacity,
				"%d km/h" % roundi(v.max_speed_ms * 3.6), "alim. " + str(v.supply)] + (["guidage pneus"] if v.guidance == "rubber_guided" else []):
			var chip := UiTheme.label_(s, UiTheme.SIZE_SMALL, UiTheme.TEXT)
			chip.add_theme_stylebox_override("normal", UiTheme.box(Color(1, 1, 1, 0.07), 10, 10)); specs.add_child(chip)
		est.text = ("CONCEPT FICTIF · " if v.fictional else "") + ("Certaines caractéristiques sont estimées — voir la fiche." if not v.estimated.is_empty() else "")
		var lc := UiTheme.color_of(cur_meta.get("color", ""), UiTheme.INFO)
		badge.text = str(cur_meta.get("line", "")) if not is_free else "Réseau"
		badge.add_theme_stylebox_override("normal", UiTheme.box(lc, 8, 8))
		badge.add_theme_color_override("font_color", Color.WHITE if lc.get_luminance() < 0.6 else Color.BLACK)
		sum_vals["Mode"].text = "Mode libre" if is_free else ("Mission scénarisée" if not scen_ref[0].is_empty() else "Service horaire")
		sum_vals["Ville"].text = city_ref[0]
		sum_vals["Ligne"].text = line_opt.get_item_text(line_opt.selected) if is_free else "%s — %s" % [cur_meta.get("line", ""), cur_meta.get("long_name", "")]
		sum_vals["Rame"].text = v.family
		if is_free: sheet.text = st_opt.get_item_text(st_opt.selected) if st_opt.selected >= 0 else ""
		elif not scen_ref[0].is_empty(): sheet.text = str(scen_ref[0].get("title", ""))
		else: sheet.text = mis_opt.get_item_text(mis_opt.selected) if mis_opt.selected >= 0 else ""
		go.disabled = not ok or (is_free and st_list.is_empty()) or not _ready_for_launch(city_ref[0])
		go.text = "Départ indisponible" if is_free and st_list.is_empty() else ("Lancer" if ok else "Matériel incompatible")
	refresh_ref[0] = refresh
	_menu["refresh"] = refresh
	var full := func(_i = 0):
		fill.call()
		if veh_opt.item_count > 0: veh_opt.select(0)
		refresh.call()
	var reload_city := func():
		if not city_preload.is_ready(city_ref[0]): return
		var src := _source_of(all_nets.filter(func(e): return e.city == city_ref[0]))
		scen_list.clear(); scen_list.append_array(_scenarios(city_ref[0], src))
		build_scen.call(); full.call()
	_menu["reload_city"] = reload_city
	var city_changed := func(c: String):
		city_ref[0] = c; menu_city = c
		go.disabled = true; go.text = "Chargement…"
		_show_bg(c)
		if city_preload.is_ready(c): reload_city.call()
	if picker is CityPicker: picker.chosen.connect(city_changed)
	else: (picker as TouchChoice).item_selected.connect(func(i): city_changed.call(cities[i]))
	line_opt.item_selected.connect(full)
	b_mis.toggled.connect(func(on): if on: free_mode = false; build_scen.call(); full.call())
	b_free.toggled.connect(func(on): if on: free_mode = true; build_scen.call(); full.call())
	veh_opt.item_selected.connect(refresh)
	mis_opt.item_selected.connect(refresh)
	st_opt.item_selected.connect(refresh)
	if city_preload.is_ready(city_ref[0]): reload_city.call()
	else: go.disabled = true; go.text = "Chargement…"
	# choix venu du catalogue (« Conduire cette rame ») : ville, ligne et matériel, puis départ
	var pick: Dictionary = get_meta("catalogue_pick", {})
	if not pick.is_empty() and not city_preload.is_ready(str(pick.city)):
		remove_meta("catalogue_pick"); set_meta("deferred_catalogue_pick", pick)
		menu_city = str(pick.city); city_changed.call(menu_city); pick = {}
	if not pick.is_empty():
		remove_meta("catalogue_pick")
		if pick.get("free",false):b_free.button_pressed=true;b_mis.button_pressed=false;free_mode=true
		if str(pick.city) in cities:
			if picker is CityPicker: picker.pick(str(pick.city))
			else: picker.select(cities.find(str(pick.city))); city_changed.call(str(pick.city))
			for i in city_nets.size():
				if city_nets[i].path != pick.path or city_nets[i].get("free_only", false): continue
				if b_free.button_pressed:
					for j in free_lines.size():
						if free_lines[j].line == str(city_nets[i].line): line_opt.select(j)
				else: line_opt.select(i)
			fill.call()
			for i in vehicles.size():
				if (str(pick.get("variant_id",""))!="" and (vehicles[i] as VehicleProfile).variant_id==str(pick.variant_id)) or (str(pick.get("variant_id",""))=="" and (vehicles[i] as VehicleProfile).model_family==pick.family): veh_opt.select(i);break
			refresh.call()
	go.pressed.connect(func():
		if city_nets.is_empty() or vehicles.is_empty() or go.disabled: return
		save.settings.traffic = traffic_cb.button_pressed
		save.settings.time_mode = time_opt.selected
		save.settings.last_city = city_ref[0]
		free_mode = b_free.button_pressed
		vehicle = vehicles[maxi(veh_opt.selected, 0)]
		scenario = {}
		if free_mode:
			net_path = free_path.call()
			if not FileAccess.file_exists(net_path): net_path = city_nets[0].path
			start_station = st_list[maxi(st_opt.selected, 0)] if not st_list.is_empty() else {}
			mission = {}
		elif not scen_ref[0].is_empty():
			scenario = scen_ref[0]; mission = {}
			net_path = str(scenario.get("network", free_path.call()))
			if not FileAccess.file_exists(net_path):
				net_path = city_nets[maxi(line_opt.selected, 0)].path
				for e in city_nets:
					if str(e.line) == str(scenario.get("line", "")): net_path = e.path; break
		else:
			net_path = city_nets[maxi(line_opt.selected, 0)].path
			mission = mis_list[mis_opt.selected] if mis_opt.selected >= 0 and mis_opt.selected < mis_list.size() else {}
		_remember_run(city_ref[0])
		_start(true))
	UiTheme.fade_in(page, 0.25)
	_menu["auto_start"] = bool(pick.get("start", false))
	if _menu.auto_start and not go.disabled: _menu.auto_start = false; go.pressed.emit()

## Mémorise la partie lancée (bouton « Reprendre la dernière partie »).
func _remember_run(city: String) -> void:
	var label := "%s · %s · %s" % [city, "mode libre" if free_mode else ("mission « %s »" % scenario.get("title", "") if not scenario.is_empty()
		else "ligne %s %s" % [CityDataStore.document(net_path).get("line", ""), str(mission.get("start_time", "")).substr(0, 5)]), vehicle.family]
	save.settings.last_run = {"label": label, "city": city, "free": free_mode, "net_path": net_path, "vehicle": vehicle.id,
		"mission_key": "%s|%s" % [mission.get("start_time", ""), mission.get("headsign", "")] if not mission.is_empty() else "",
		"scenario": str(scenario.get("id", "")), "station": start_station.duplicate() if free_mode else {}}
	SaveGame.save_data(save)

func _vehicle_by_id(id: String, meta: Dictionary) -> VehicleProfile:
	for f in TramModel.fleet_for(meta):
		var v := VehicleLibrary.for_fleet(f, meta)
		if v.id == id: return v
	for v in VehicleLibrary.all():
		if v.id == id: return v
	return VehicleLibrary.default_for(meta)

func _resume() -> void:
	var r := _resume_info()
	if r.is_empty(): return
	if _launching: return
	_launching = true
	menu_city = str(r.get("city", menu_city)); _show_bg(menu_city)
	while not city_preload.is_ready(menu_city):
		await get_tree().process_frame
		if city_preload.error != "": _launching = false; return
	_launching = false
	var n: NetworkLoader = city_preload.network(str(r.net_path))
	if n == null: return
	net_path = str(r.net_path); free_mode = bool(r.free); mission = {}; scenario = {}; start_station = {}
	vehicle = _vehicle_by_id(str(r.vehicle), n.meta)
	menu_city = str(r.get("city", menu_city))
	if free_mode:
		var f: Dictionary = save.get("free", {})
		if str(f.get("network", "")) == net_path and n.edge_info.has(str(f.get("edge", ""))):
			start_station = {"edge": str(f.edge), "offset": float(f.offset), "name": "reprise"}
		elif r.get("station", {}) is Dictionary and not r.station.is_empty(): start_station = r.station
	elif str(r.get("scenario", "")) != "":
		for m in _scenarios(menu_city, str(n.meta.get("source_id", ""))):
			if str(m.get("id", "")) == str(r.scenario): scenario = m
	if not free_mode and scenario.is_empty():
		for m in n.missions():
			if "%s|%s" % [m.get("start_time", ""), m.get("headsign", "")] == str(r.get("mission_key", "")): mission = m
	if free_mode and save.get("free",{}).has("weather"):set_meta("resume_weather",save.free.weather)
	_start(true)

## Réglages (accueil) : distance de vue, trafic, ambiance, fond animé, astuces.
func _open_settings() -> void:
	if settings_layer: return
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 10)
	var weather_choice := _opt(v,"Météo")
	var weather_ids := ["clear","rain","fog","storm","dynamic"]
	for label in ["Temps sec","Pluie","Brouillard","Forte pluie","Dynamique (simulée)"]:weather_choice.add_item(label)
	weather_choice.select(maxi(0,weather_ids.find(str(save.settings.get("weather","clear")))))
	weather_choice.item_selected.connect(func(i):save.settings.weather=weather_ids[i])
	var effects_choice := _opt(v,"Effets")
	var effect_ids := ["economy","balanced","cinematic"]
	for label in ["Économie","Équilibré","Cinématique · flou caméra"]:effects_choice.add_item(label)
	effects_choice.select(maxi(0,effect_ids.find(str(save.settings.get("visual_profile","economy" if OS.has_feature("mobile") else "balanced")))))
	effects_choice.item_selected.connect(func(i):save.settings.visual_profile=effect_ids[i])
	var dists := [300.0, 400.0, 600.0, 900.0]
	var dist := _opt(v, "Vue"); for d in dists: dist.add_item("Distance de vue : %d m" % int(d))
	dist.selected = maxi(0, dists.find(float(save.settings.get("view_distance", 400.0))))
	dist.item_selected.connect(func(i): save.settings.view_distance = dists[i])
	var hour := _opt(v, "Heure")
	for t in ["Heure réelle du service", "Jour (12 h)", "Coucher de soleil (20 h)", "Nuit (23 h)", "Cycle accéléré (1 h = 1 min)"]: hour.add_item(t)
	hour.selected = int(save.settings.get("time_mode", 0)); hour.item_selected.connect(func(i): save.settings.time_mode = i)
	var checks := [["Sons d’interface", "ui_sounds", true], ["Trafic automobile", "traffic", true], ["Vue aérienne en fond d'accueil", "home_bg", true], ["Intro de lancement (zoom)", "intro", true]]
	for c in checks:
		var cb := CheckButton.new(); cb.text = c[0]; cb.custom_minimum_size = Vector2(0, 48)
		cb.button_pressed = bool(save.settings.get(c[1], c[2])); v.add_child(cb)
		cb.toggled.connect(func(on):
			save.settings[c[1]] = on
			if c[1] == "ui_sounds": ui_audio.enabled = on)
	var tut := CheckButton.new(); tut.text = "Revoir les astuces de conduite"; tut.custom_minimum_size = Vector2(0, 48)
	tut.button_pressed = not save.settings.tutorial_done; v.add_child(tut)
	tut.toggled.connect(func(on): save.settings.tutorial_done = not on)
	settings_layer = _overlay("Réglages", "switch", UiTheme.ACCENT, [["Fermer  (Échap)", "close", "primary", _close_settings]], "", [], v, 600.0)
	settings_layer.name = "settings_layer"

func _close_settings() -> void:
	if settings_layer == null: return
	settings_layer.queue_free(); settings_layer = null
	SaveGame.save_data(save)
	_show_bg(menu_city)

## Raccourcis des menus (accueil, configuration). Renvoie vrai si la touche est consommée.
func _menu_key(k: int, ev: InputEventKey) -> bool:
	if _launching or (is_instance_valid(_city_loading_layer) and _city_loading_layer.visible): return true
	if not get_tree().get_nodes_in_group("touch_choice_modal").is_empty(): return false
	for c in get_children():
		if c is Catalogue: return false
	if settings_layer:
		if k == KEY_ESCAPE or k == KEY_BACKSPACE: _close_settings(); return true
		return false
	var focus := get_viewport().gui_get_focus_owner()
	if focus is LineEdit:
		if k == KEY_ESCAPE: focus.release_focus(); return true
		return false
	var setup := menu_page == "setup"
	match k:
		KEY_ESCAPE, KEY_BACKSPACE:
			if setup: menu_page = "home"; _build_menu(); return true
		KEY_ENTER, KEY_KP_ENTER:
			if setup:
				var go: Button = _menu.get("go")
				if go and not go.disabled: go.pressed.emit()
			else: _open_setup(free_mode)
			return true
		KEY_1, KEY_KP_1:
			if setup: _menu.b_mis.button_pressed = true
			else: _open_setup(false)
			return true
		KEY_2, KEY_KP_2:
			if setup: _menu.b_free.button_pressed = true
			else: _open_setup(true)
			return true
		KEY_3, KEY_KP_3:
			if not setup: _start_explore(); return true
		KEY_R:
			if not setup and not _resume_info().is_empty(): _resume(); return true
		KEY_C: _open_catalogue(menu_city); return true
		KEY_G: _open_settings(); return true
		KEY_SLASH, KEY_KP_DIVIDE, KEY_F:
			if setup and (k != KEY_F or ev.ctrl_pressed):
				if _menu.picker is CityPicker: _menu.picker.search.grab_focus()
				else: _menu.picker.open_picker()
				return true
		KEY_PAGEUP, KEY_PAGEDOWN:
			if setup and _menu.picker is CityPicker: _menu.picker.step(-1 if k == KEY_PAGEUP else 1); return true
	return false

static var _line_colors: Dictionary = {}
func _line_color(path: String) -> Color:
	if not _line_colors.has(path):
		_line_colors[path] = UiTheme.color_of(Catalogue.meta_of(path).get("color", ""), UiTheme.INFO)
	return _line_colors[path]

func _swatch(c: Color) -> Texture2D:
	var img := Image.create(18, 18, false, Image.FORMAT_RGBA8); img.fill(c)
	return ImageTexture.create_from_image(img)

## Catalogue des rames par-dessus le menu (masqué) ; « Conduire cette rame » reconstruit le menu avec ce choix.
func _open_catalogue(city: String) -> Catalogue:
	var hidden: Array = []
	for c in get_children():
		if c is CanvasItem and c.visible: c.visible = false; hidden.append(c)
	var cat := Catalogue.new(city); add_child(cat)
	UiTheme.fade_in(cat, 0.2)
	cat.closed.connect(func():
		for c in hidden:
			if is_instance_valid(c): c.visible = true)
	cat.drive.connect(func(p: Dictionary):
		p.start = true; set_meta("catalogue_pick", p); _build_menu())
	return cat

static var _sources: Dictionary = {}
func _source_of(city_nets: Array) -> String:
	if city_nets.is_empty(): return ""
	var path := str(city_nets[0].path)
	if not _sources.has(path): _sources[path] = str(CityDataStore.document(path).get("source_id", ""))
	return _sources[path]

func _opt(parent: Control, label: String) -> TouchChoice:
	return _row(parent, label).get_child(1)

func _row(parent: Control, label: String) -> HBoxContainer:
	var r := HBoxContainer.new(); r.add_theme_constant_override("separation", 12); parent.add_child(r)
	var l := UiTheme.label_(label, UiTheme.SIZE_SMALL, UiTheme.MUTED); l.custom_minimum_size = Vector2(100, 0); r.add_child(l)
	var o := TouchChoice.new(); o.choice_title = label; o.size_flags_horizontal = Control.SIZE_EXPAND_FILL; o.custom_minimum_size = Vector2(0, 50)
	o.fit_to_longest_item = false; o.clip_text = true
	r.add_child(o)
	return r

# ----------------------------------------------------------------------------------------------- partie

## Lance la partie choisie. `with_intro` : zoom ville -> quartier -> station (lancement depuis le menu).
func _start(with_intro: bool = false) -> void:
	if _launching: return
	_launching = true
	if with_intro:
		_show_bg(menu_city)
		while not _ready_for_launch(menu_city):
			await get_tree().process_frame
			if city_preload.error != "": _launching = false; return
		var input_layer := CanvasLayer.new(); input_layer.layer = 100; input_layer.name = "departure_input"
		add_child(input_layer)
		var blocker := Control.new(); blocker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		blocker.mouse_filter = Control.MOUSE_FILTER_STOP; blocker.focus_mode = Control.FOCUS_ALL
		input_layer.add_child(blocker); blocker.grab_focus()
		if bool(save.settings.get("intro", true)):
			var tw := create_tween().set_parallel(true)
			for child in get_children():
				if child is Control and child != home_bg and not child.is_queued_for_deletion():
					child.pivot_offset = child.size * 0.5
					tw.tween_property(child, "modulate:a", 0.0, 0.42)
					tw.tween_property(child, "scale", Vector2(1.07, 1.07), 0.42).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
			if is_instance_valid(home_bg): home_bg.departure_zoom(0.42)
			await tw.finished
	_start_prepared(with_intro)
	_launching = false

func _start_prepared(with_intro: bool = false) -> void:
	if is_instance_valid(_city_loading_layer): _city_loading_layer.hide()
	var prepared_network: NetworkLoader = city_preload.network(net_path) if is_instance_valid(city_preload) else null
	_departure_context = home_bg.departure_context(prepared_network.meta.get("origin", [])) if is_instance_valid(home_bg) and prepared_network != null else {}
	if is_instance_valid(home_bg): home_bg.queue_free()
	home_bg = null
	with_intro = with_intro and bool(save.settings.get("intro", true))
	get_tree().quit_on_go_back = false
	_clear()
	_result_saved = false
	_speed_advice = {}
	paused = false
	emergency = false
	notch = -0.75 # F3 : immobilisation dès l’apparition, y compris en rampe.
	net = prepared_network if prepared_network != null else NetworkLoader.new()
	var errs := PackedStringArray() if prepared_network != null else net.load_file(net_path)
	if not errs.is_empty():
		push_error(str(errs)); _build_menu(); return
	var first: String = net.meta.edges[0].id
	if free_mode:
		var e := first
		var o := minf(30.0, net.graph.edges[first].length - 5.0)
		if not start_station.is_empty():
			e = start_station.edge; o = float(start_station.offset)
		free = FreeSession.new(net, vehicle, e, o, save.settings.traffic)
		var normal := int(net.edge_info[e].get("preferred_direction", 0))
		free.direction = normal if normal != 0 else int(start_station.get("direction", 1))
		free.route_dir = [free.direction]; free.checkpoint_dir = free.direction; free.update_spans()
		session = free
		first = e
	elif not scenario.is_empty() and _scenario_session():
		first = session.edge_id
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
	add_child(view)
	var prepared_scene: CityScene = city_preload.take_scene(net.meta.get("origin", [])) if is_instance_valid(city_preload) else null
	view.build(net, first, vehicle, prepared_scene)
	weather=WeatherState.new();weather.configure(str(save.settings.get("weather","clear")))
	if has_meta("resume_weather"):
		weather.restore(get_meta("resume_weather"));remove_meta("resume_weather")
	weather_view=WeatherView.new();view.add_child(weather_view)
	var effects := VisualEffects.new();view.add_child(effects);effects.setup(view,str(save.settings.get("visual_profile","economy" if OS.has_feature("mobile") else "balanced")))
	hour0 = _start_hour()
	view.set_hour(hour0)
	# Rames en circulation (missions sur réseau complet, poste d'aiguillage) : fréquences approchées.
	if session.interlocking != null and bool(save.settings.get("ai_trams", true)):
		ai_trams = AiTrams.create(session, str(scenario.get("city", menu_city)), hour0)
		ai_trams.message.connect(func(t): _log(t, "info", "tram"))
	# DayNight applique déjà le budget d’ombres mobile.
	if OS.has_feature("mobile") and view.city: view.city.radius = 450.0
	_intro_radius = view.city.radius if view.city else 0.0
	if with_intro and view.city:
		view.city.radius = minf(_intro_radius, 450.0)
		view.city.enable_async_lod()
	view.update_from(session, true)
	# Near detail streams during the aerial move; large-area geography is already resident.
	if view.city:
		if with_intro: view.city.update(view.cam.global_position, 0)
		else: view.city.warm(view.cam.global_position)
	view.cam.current = true
	tram_audio = TramAudio.new(view, bell); add_child(tram_audio)   # moteur sonore de la rame
	_build_hud()
	_set_notch(notch)
	if free and free.adaptation_notice != "": _log(free.adaptation_notice)
	if with_intro: _begin_intro()
	elif not save.settings.tutorial_done: _show_tuto()
	if is_instance_valid(city_preload): city_preload.invalidate()

## Session d'une mission scénarisée (MissionCatalog.create_session), sinon faux (repli GTFS).
func _scenario_session() -> bool:
	var cat := _catalog()
	if cat == null or not _has_static(cat, "create_session"): return false
	var s = cat.call("create_session", scenario, vehicle, net)
	if not s is MissionSession: return false
	session = s
	if s.net != null: net = s.net
	if session.get("traffic") != null: session.traffic.set_enabled(save.settings.traffic)
	return true

func _begin_intro() -> void:
	for c in get_children():
		if c.is_in_group("driving_hud"): (c as CanvasItem).visible = false
	var st := _next_stop()
	var city := str(net.meta.get("city", menu_city))
	var caps := PackedStringArray([city, ("Réseau de tramway" if free_mode else "Ligne %s — %s" % [net.meta.get("line", ""), net.meta.get("long_name", "")]),
		str(start_station.get("name", "")) if free_mode and not start_station.is_empty() else str(st.get("name", ""))])
	intro = IntroCamera.new(); view.add_child(intro)
	intro.finished.connect(_end_intro)
	intro.start(view, view.pos3(session.edge_id, session.offset), caps, _departure_context)

func _end_intro() -> void:
	intro = null
	if view == null: return
	if view.city and _intro_radius > 0.0: view.city.radius = _intro_radius
	for c in get_children():
		if c.is_in_group("driving_hud"):
			var ci := c as CanvasItem; ci.visible = true; ci.modulate.a = 0.0
			var tw := ci.create_tween(); tw.tween_property(ci, "modulate:a", 1.0, 0.35)
	if not save.settings.tutorial_done: _show_tuto()

func _hud_panel(alpha: float = 0.8) -> PanelContainer:
	var p := UiTheme.panel(Color(UiTheme.SURFACE, alpha), 16, 14)
	return p

func _icon_btn(icon_name: String, tip: String, cb: Callable, kind: String = "normal") -> Button:
	var b := UiTheme.button("", icon_name, kind, Vector2(52, 52)); b.tooltip_text = tip; b.name = "btn_" + icon_name
	b.focus_mode = Control.FOCUS_NONE; b.expand_icon = false
	b.add_theme_stylebox_override("normal", UiTheme.box(Color(UiTheme.SURFACE, 0.82), 14, 12, UiTheme.BORDER, 1))
	b.pressed.connect(cb)
	return b

func _line_meta_color() -> Color:
	return UiTheme.color_of(net.meta.get("color", ""), UiTheme.INFO)

func _build_hud() -> void:
	var before := get_children()
	var compact := UiLayout.compact(self)
	var safe := UiLayout.safe_insets(self)
	var lc := _line_meta_color()
	# --- carte de trajet (haut gauche) : ligne, prochain arrêt, horaire, voyants
	var trip := _hud_panel(); trip.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	trip.position = Vector2(14 + safe.x, 14 + safe.y); trip.custom_minimum_size = Vector2(300 if compact else 430, 0); trip.name = "trip"
	add_child(trip)
	var tv := VBoxContainer.new(); tv.add_theme_constant_override("separation", 6); trip.add_child(tv)
	var r1 := HBoxContainer.new(); r1.add_theme_constant_override("separation", 12); tv.add_child(r1)
	var badge := UiTheme.line_badge(str(scenario.get("line", net.meta.get("line", ""))) if not free_mode else str(net.meta.get("city", "")).substr(0, 3), lc, UiTheme.SIZE_H2)
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER; r1.add_child(badge)
	var sv := VBoxContainer.new(); sv.add_theme_constant_override("separation", -2); sv.size_flags_horizontal = Control.SIZE_EXPAND_FILL; r1.add_child(sv)
	sv.add_child(UiTheme.label_("PROCHAIN ARRÊT", UiTheme.SIZE_CAPTION, UiTheme.MUTED, true))
	hud_info = UiTheme.label_("—", UiTheme.SIZE_BODY if compact else UiTheme.SIZE_H2, UiTheme.TEXT, true)
	hud_info.clip_text = true; hud_info.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS; hud_info.custom_minimum_size = Vector2(170 if compact else 300, 0)
	sv.add_child(hud_info)
	hud_sub = UiTheme.label_("", UiTheme.SIZE_SMALL, UiTheme.MUTED); hud_sub.clip_text = true; sv.add_child(hud_sub)
	var lr := HBoxContainer.new(); lr.add_theme_constant_override("separation", 6); tv.add_child(lr); lr.visible = not compact
	for spec in [["doors", "doors", "Portes"], ["panto", "pantograph", "Panto"], ["power", "power", "Alim."], ["emerg", "emergency", "Urgence"]]:
		lr.add_child(_lamp(spec[0], spec[1], spec[2]))
	if free_mode:
		hud_switch = Button.new(); hud_switch.icon = UiTheme.icon("switch"); hud_switch.alignment = HORIZONTAL_ALIGNMENT_LEFT
		hud_switch.custom_minimum_size = Vector2(0, 48); hud_switch.clip_text = true; hud_switch.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		hud_switch.add_theme_font_size_override("font_size", UiTheme.SIZE_SMALL); hud_switch.focus_mode = Control.FOCUS_NONE
		hud_switch.tooltip_text = "Prochain aiguillage sur l'itinéraire : ouvrir le panneau (A)"
		hud_switch.visible = not compact
		hud_switch.name = "next_switch"; hud_switch.pressed.connect(_toggle_plan); tv.add_child(hud_switch)
	# --- horloge, écart, boutons (haut droite)
	var tr := HBoxContainer.new(); tr.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	tr.grow_horizontal = Control.GROW_DIRECTION_BEGIN; tr.offset_right = -14 - safe.z; tr.offset_top = 14 + safe.y; tr.offset_left = -14 - safe.z
	tr.add_theme_constant_override("separation", 8); add_child(tr)
	var cp := _hud_panel(); tr.add_child(cp)
	var ch := HBoxContainer.new(); ch.add_theme_constant_override("separation", 10); cp.add_child(ch)
	var clock_icon := UiTheme.icon_rect("clock", 24, UiTheme.MUTED); clock_icon.visible = not compact; ch.add_child(clock_icon)
	var cv := VBoxContainer.new(); cv.add_theme_constant_override("separation", -4); ch.add_child(cv)
	hud_clock = UiTheme.label_("--:--", UiTheme.SIZE_H2, UiTheme.TEXT, true); cv.add_child(hud_clock)
	hud_sched = UiTheme.label_("", UiTheme.SIZE_CAPTION, UiTheme.MUTED, true); cv.add_child(hud_sched); hud_sched.visible = not compact
	tr.add_child(_icon_btn("help", "Aide clavier (F1)", _toggle_help))
	tr.add_child(_icon_btn("pause", "Pause (Échap)", func(): _set_paused(not paused)))
	tr.add_child(_icon_btn("home", "Menu principal", func(): _persist(); _build_menu()))
	# --- répétiteur de signalisation (haut droite, sous l'horloge)
	# Écran bas (téléphone en paysage) : répétiteur réduit dans la colonne du tachymètre.
	var short := compact and get_viewport_rect().size.y < 420.0
	signal_panel = SignalPanel.new(); signal_panel.setup(session, compact, short)
	if not short:
		signal_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		signal_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		signal_panel.offset_right = -14 - safe.z; signal_panel.offset_left = -14 - safe.z
		signal_panel.offset_top = 14 + safe.y + (64 if compact else 74)
		add_child(signal_panel)
	# --- alertes (bandeau central) et notifications
	var mid := VBoxContainer.new(); mid.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP); mid.offset_top = 92
	mid.grow_horizontal = Control.GROW_DIRECTION_BOTH; mid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mid.add_theme_constant_override("separation", 8); add_child(mid)
	_alert_box = PanelContainer.new(); _alert_box.add_theme_stylebox_override("panel", UiTheme.box(Color(UiTheme.DANGER, 0.9), 22, 18))
	_alert_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER; _alert_box.visible = false; _alert_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mid.add_child(_alert_box)
	var ah := HBoxContainer.new(); ah.add_theme_constant_override("separation", 10); _alert_box.add_child(ah)
	ah.add_child(UiTheme.icon_rect("emergency", 26))
	hud_alert = UiTheme.label_("", UiTheme.SIZE_BODY, Color.WHITE, true); ah.add_child(hud_alert)
	toasts = VBoxContainer.new(); toasts.add_theme_constant_override("separation", 6); toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toasts.size_flags_horizontal = Control.SIZE_SHRINK_CENTER; mid.add_child(toasts)
	# --- manipulateur (gauche)
	var lp := _hud_panel(); lp.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT); lp.name = "lever"
	lp.grow_vertical = Control.GROW_DIRECTION_BEGIN; lp.offset_left = 14 + safe.x; lp.offset_bottom = -14 - safe.w
	add_child(lp)
	var lv := VBoxContainer.new(); lv.add_theme_constant_override("separation", 6); lp.add_child(lv)
	var plus := UiTheme.button("", "plus", "normal", Vector2(130, 50)); plus.tooltip_text = "Traction (Z)"; plus.name = "traction"
	plus.focus_mode = Control.FOCUS_NONE; lv.add_child(plus); plus.visible = not compact
	lever = NotchLever.new(); lever.size_flags_horizontal = Control.SIZE_EXPAND_FILL; lever.custom_minimum_size = Vector2(80, 140) if compact else Vector2(130, 250)
	lever.changed.connect(func(v): _manual(); notch = v; if v > -0.99: emergency = false)
	lv.add_child(lever)
	var minus := UiTheme.button("", "minus", "normal", Vector2(130, 50)); minus.tooltip_text = "Freinage (S)"; minus.name = "brake"
	minus.focus_mode = Control.FOCUS_NONE; lv.add_child(minus); minus.visible = not compact
	notch_label = UiTheme.label_("N", UiTheme.SIZE_SMALL, UiTheme.TEXT, true); notch_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	notch_label.custom_minimum_size = Vector2(0, 48 if compact else 34); notch_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	notch_label.mouse_filter = Control.MOUSE_FILTER_STOP; notch_label.tooltip_text = "Toucher : neutre (X)"
	notch_label.gui_input.connect(func(ev): if (ev is InputEventMouseButton or ev is InputEventScreenTouch) and ev.pressed: _set_notch(0.0))
	lv.add_child(notch_label)
	plus.pressed.connect(func(): _manual(); _set_notch(notch + 0.25))
	minus.pressed.connect(func(): _manual(); _set_notch(notch - 0.25))
	# --- tachymètre et urgence (droite)
	var rp := VBoxContainer.new(); rp.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	rp.grow_horizontal = Control.GROW_DIRECTION_BEGIN; rp.grow_vertical = Control.GROW_DIRECTION_BEGIN
	rp.offset_right = -14 - safe.z; rp.offset_bottom = -14 - safe.w; rp.offset_left = -14 - safe.z; rp.offset_top = -14 - safe.w
	rp.add_theme_constant_override("separation", 10); rp.alignment = BoxContainer.ALIGNMENT_END; add_child(rp)
	var eb := UiTheme.button("URGENCE", "emergency", "danger", Vector2(144, 52) if compact else Vector2(212, 64)); eb.name = "emergency"
	eb.add_theme_font_size_override("font_size", 18 if compact else UiTheme.SIZE_H2); eb.tooltip_text = "Freinage d'urgence (Espace)"; eb.focus_mode = Control.FOCUS_NONE
	eb.pressed.connect(_emergency); rp.add_child(eb)
	hud_grade = UiTheme.label_("Pente 0 ‰", 15, UiTheme.TEXT, true); hud_grade.name = "slope"
	hud_grade.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; rp.add_child(hud_grade)
	hud_speed = Speedometer.new(); rp.add_child(hud_speed)
	if short:
		signal_panel.size_flags_horizontal = Control.SIZE_SHRINK_END
		rp.add_child(signal_panel); rp.move_child(signal_panel, 0); hud_grade.visible = false
	if compact: hud_speed.custom_minimum_size = Vector2(144, 144)
	# --- barre d'outils (bas, centrée ; passe sur deux rangées si l'écran est étroit)
	var dock := TouchScroll.new(); dock.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	dock.offset_left = (134 if compact else 180) + safe.x; dock.offset_right = (-172 if compact else -244) - safe.z
	dock.offset_top = -90 - safe.w; dock.offset_bottom = -8 - safe.w
	dock.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; dock.name = "dock"; add_child(dock)
	var tools := HBoxContainer.new(); tools.add_theme_constant_override("separation", 8)
	tools.size_flags_horizontal = Control.SIZE_EXPAND_FILL; tools.alignment = BoxContainer.ALIGNMENT_CENTER; dock.add_child(tools)
	var specs := [["Portes", "doors", "O", _doors], ["Cloche", "bell", "K", _horn], ["Caméra", "camera", "C", _camera], ["Plan", "map", "M", _toggle_plan], ["Alimentation", "power", "P", _power_picker]]
	if free_mode:
		specs += [["Pilote auto", "autopilot", "L", _toggle_autopilot], ["Changer de sens", "reverse", "V", _reverse], ["Remise sur voie", "rerail", "R", _rerail], ["Trafic", "traffic", "T", _traffic]]
	for spec in specs:
		var b := UiTheme.tool_button(spec[0], spec[1], "" if compact else spec[2], 72.0 if compact else 88.0); b.pressed.connect(spec[3])
		b.add_theme_stylebox_override("normal", UiTheme.box(Color(UiTheme.SURFACE, 0.82), 14, 8, UiTheme.BORDER, 1))
		tools.add_child(b)
		if spec[1] == "power": power_button = b
		if spec[1] == "autopilot": autopilot_button = b; b.name = "tool_autopilot"
	for c in [trip, tr, lp, rp, dock, signal_panel]: UiTheme.fade_in(c, 0.35)
	for c in get_children():
		if not c in before: c.add_to_group("driving_hud")
	_build_cam_hud(safe)

## Barre caméra : en conduite automatique, seuls « Quitter le mode auto » et « Caméra » restent ;
## en vue du dessus, boutons de zoom − / +.
func _build_cam_hud(safe: Vector4) -> void:
	if is_instance_valid(cam_hud): cam_hud.queue_free()
	cam_hud = HBoxContainer.new(); cam_hud.name = "cam_hud"
	cam_hud.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	cam_hud.grow_horizontal = Control.GROW_DIRECTION_BOTH; cam_hud.grow_vertical = Control.GROW_DIRECTION_BEGIN
	cam_hud.offset_bottom = -104 - safe.w; cam_hud.offset_top = -104 - safe.w
	cam_hud.alignment = BoxContainer.ALIGNMENT_CENTER; cam_hud.add_theme_constant_override("separation", 10)
	cam_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(cam_hud)
	var quit_auto := UiTheme.button("Quitter le mode auto", "autopilot", "primary", Vector2(0, 56)); quit_auto.name = "quit_auto"
	quit_auto.focus_mode = Control.FOCUS_NONE; quit_auto.tooltip_text = "Reprendre la conduite (L)"
	quit_auto.pressed.connect(func(): _set_autopilot(false, "Conduite manuelle : pilote automatique coupé")); cam_hud.add_child(quit_auto)
	var cb := _icon_btn("camera", "Caméra : extérieure / cabine / dessus (C)", _camera); cb.name = "auto_camera"; cb.custom_minimum_size = Vector2(56, 56); cam_hud.add_child(cb)
	for spec in [["minus", "Zoom arrière (vue du dessus)", 1.0 / 1.25, "zoom_out"], ["plus", "Zoom avant (vue du dessus)", 1.25, "zoom_in"]]:
		var f: float = spec[2]
		var zb := _icon_btn(spec[0], spec[1], func(): _zoom(f)); zb.name = spec[3]; zb.custom_minimum_size = Vector2(56, 56); cam_hud.add_child(zb)
	_apply_auto_ui()

## Interface masquée en conduite automatique (PC et mobile).
func _apply_auto_ui() -> void:
	var auto := autopilot.enabled
	for c in get_children():
		if c.is_in_group("driving_hud"): (c as CanvasItem).visible = not auto
	if not is_instance_valid(cam_hud): return
	var top: bool = view != null and view.top_view and external_cam
	for n in ["quit_auto", "auto_camera"]: (cam_hud.get_node(n) as Control).visible = auto
	for n in ["zoom_out", "zoom_in"]: (cam_hud.get_node(n) as Control).visible = top
	cam_hud.visible = auto or top
	# Mode auto : barre en bas de l'écran (dock masqué) ; sinon au-dessus du dock.
	var safe := UiLayout.safe_insets(self)
	cam_hud.offset_bottom = (-16.0 if auto else -104.0) - safe.w; cam_hud.offset_top = cam_hud.offset_bottom

## Zoom : distance de la caméra extérieure ou hauteur de la vue du dessus (f > 1 : rapproche).
func _zoom(f: float) -> void:
	if view == null: return
	if view.top_view and external_cam: view.top_height = clampf(view.top_height / f, LineView.TOP_MIN, LineView.TOP_MAX)
	else: view.cam_dist = clampf(view.cam_dist / f, 14.0, 160.0)

func _lamp(id: String, icon_name: String, text: String) -> PanelContainer:
	var p := PanelContainer.new(); p.name = "lamp_" + id; p.tooltip_text = text
	var h := HBoxContainer.new(); h.add_theme_constant_override("separation", 5); p.add_child(h)
	var ic := UiTheme.icon_rect(icon_name, 18); h.add_child(ic)
	var l := UiTheme.label_(text, UiTheme.SIZE_CAPTION, UiTheme.TEXT, true); h.add_child(l)
	lamps[id] = [p, ic, l, -1]
	_set_lamp(id, 0)
	return p

## État d'un voyant : 0 éteint, 1 normal (vert), 2 attention (ambre), 3 alarme (rouge).
func _set_lamp(id: String, state: int, text: String = "") -> void:
	if not lamps.has(id): return
	var L: Array = lamps[id]
	if text != "": (L[2] as Label).text = text
	if L[3] == state: return
	L[3] = state
	var col: Color = [Color(1, 1, 1, 0.06), Color(UiTheme.SUCCESS, 0.22), Color(UiTheme.WARNING, 0.3), Color(UiTheme.DANGER, 0.85)][state]
	var fg: Color = [UiTheme.MUTED, UiTheme.SUCCESS, UiTheme.WARNING, Color.WHITE][state]
	(L[0] as PanelContainer).add_theme_stylebox_override("panel", UiTheme.box(col, 10, 8))
	(L[1] as TextureRect).modulate = fg
	(L[2] as Label).add_theme_color_override("font_color", fg)

func _set_notch(v: float) -> void:
	notch = clampf(v, -1.0, 1.0)
	if notch > -0.99: emergency = false
	if lever: lever.set_value(notch)

## Reprise en main : toute commande manuelle de traction / freinage coupe le pilote automatique.
func _manual() -> void:
	if autopilot.enabled: _set_autopilot(false, "Conduite manuelle : pilote automatique coupé")

func _toggle_autopilot() -> void:
	_set_autopilot(not autopilot.enabled)

func _set_autopilot(on: bool, why: String = "") -> void:
	if on and (free == null or free.incident != ""):
		_log("Pilote automatique : mode libre, rame sur voie", "warn", "autopilot"); return
	autopilot.enabled = on
	if on:
		autopilot.reset(); autopilot.random_routes = true; autopilot.rng.randomize()
		autopilot.cran = clampi(roundi(notch * 4.0), -3, 4)
	_log(why if why != "" else ("Pilote automatique activé : limites, stations, signaux" if on else "Pilote automatique désactivé"), "info", "autopilot")
	_apply_auto_ui()
	if is_instance_valid(autopilot_button):
		autopilot_button.add_theme_stylebox_override("normal", UiTheme.box(Color(UiTheme.ACCENT_DARK, 0.92) if on else Color(UiTheme.SURFACE, 0.82), 14, 8, UiTheme.ACCENT if on else UiTheme.BORDER, 2 if on else 1))

func _doors() -> void:
	if autopilot.enabled and autopilot.state != "dwell": _manual()
	var was := session.doors_open
	session.set_doors(not session.doors_open)
	if session.doors_open == was and not was:
		_log("Ouverture refusée : rame en mouvement", "warn")

func _horn() -> void:
	bell.play(); _log("Ding ding !", "info", "bell")

## Cycle caméra : extérieure -> cabine -> vue du dessus -> extérieure.
func _camera() -> void:
	if external_cam and not view.top_view: external_cam = false
	elif not external_cam: external_cam = true; view.top_view = true
	else: view.top_view = false
	_apply_auto_ui()
	_log("Caméra " + ("cabine" if not external_cam else ("vue du dessus (molette / pincer / ± pour zoomer)" if view.top_view else "extérieure")), "info", "camera")

func _power_picker() -> void:
	if session.phys.speed >= 0.1:
		_log("Arrêtez la rame avant de changer d’alimentation", "warn"); return
	var choice := TouchChoice.new(); choice.choice_title = "Alimentation"
	var modes := session.available_power_modes()
	for mode in modes: choice.add_item(MissionSession.power_label(mode))
	choice.select(modes.find(session.power_mode)); add_child(choice)
	choice.position = Vector2(-4096, -4096)
	choice.item_selected.connect(func(index):
		var error := session.set_power_mode(str(modes[index]))
		_log(error if error != "" else "Alimentation : " + MissionSession.power_label(session.power_mode), "warn" if error != "" else "info", "power"))
	choice.open_picker()
	if is_instance_valid(choice.popup): choice.popup.tree_exited.connect(func(): choice.queue_free())

func _emergency() -> void:
	emergency = true; _set_notch(-1.0); _log("Freinage d'urgence", "danger", "emergency")

func _reverse() -> void:  # changement de cabine : même voie, sens de marche inversé
	if free:
		var err := free.reverse()
		_log(err if err != "" else ("Changement de cabine : " + ("cabine avant" if free.direction > 0 else "cabine arrière")), "warn" if err != "" else "info", "reverse")
		if plan_panel: plan_panel.refresh()

func _rerail() -> void:
	if free: free.rerail(); _log("Remise sur voie", "info", "rerail")

func _traffic() -> void:
	if free:
		free.set_traffic(not free.traffic.enabled); save.settings.traffic = free.traffic.enabled
		_log("Trafic " + ("activé" if free.traffic.enabled else "désactivé"), "info", "traffic")

func _toggle_plan() -> void:
	if plan_panel:
		var sp := plan_panel; plan_panel = null
		UiTheme.fade_out_free(sp, 0.12); return
	plan_panel = NetworkPlan.new(); add_child(plan_panel)
	plan_panel.setup(session, view)
	plan_panel.closed.connect(_toggle_plan)
	plan_panel.message.connect(func(t): _log(t, "info", "switch"))
	UiTheme.fade_in(plan_panel, 0.15)

## Notification (toast) : apparaît en fondu, disparaît après quelques secondes ; doublons regroupés.
func _log(t: String, kind: String = "info", icon_name: String = "") -> void:
	if toasts == null or t == "": return
	for c in toasts.get_children():
		if c.get_meta("text", "") == t and not c.is_queued_for_deletion():
			c.set_meta("ttl", 4.5); return
	var col: Color = {"info": UiTheme.INFO, "warn": UiTheme.WARNING, "danger": UiTheme.DANGER, "ok": UiTheme.SUCCESS}.get(kind, UiTheme.INFO)
	var lt := t.to_lower()
	if kind == "info" and ("refus" in lt or "échec" in lt or "occupé" in lt or "retard" in lt): col = UiTheme.WARNING
	var p := PanelContainer.new(); p.set_meta("text", t); p.set_meta("ttl", 4.5); p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := UiTheme.box(Color(0.07, 0.085, 0.11, 0.92), 14, 14); sb.border_width_left = 4; sb.border_color = col
	p.add_theme_stylebox_override("panel", sb)
	p.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var h := HBoxContainer.new(); h.add_theme_constant_override("separation", 10); p.add_child(h)
	h.add_child(UiTheme.icon_rect(icon_name if icon_name != "" else "tram", 20, col))
	var l := UiTheme.label_(t, UiTheme.SIZE_SMALL, UiTheme.TEXT); l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(minf(560.0, 18.0 + t.length() * 9.0), 0); h.add_child(l)
	toasts.add_child(p); toasts.move_child(p, 0)
	while toasts.get_child_count() > 3:
		var old := toasts.get_child(toasts.get_child_count() - 1); toasts.remove_child(old); old.queue_free()
	UiTheme.fade_in(p, 0.2)

func _tick_toasts(dt: float) -> void:
	if toasts == null: return
	for c in toasts.get_children():
		if c.is_queued_for_deletion(): continue
		var ttl: float = c.get_meta("ttl", 0.0) - dt
		c.set_meta("ttl", ttl)
		if ttl < 0.0 and ttl + dt >= 0.0: UiTheme.fade_out_free(c, 0.35)

func _set_paused(on: bool) -> void:
	camera_gestures.reset()
	paused = on
	if pause_layer: pause_layer.queue_free(); pause_layer = null
	if on:
		var st: Dictionary = _next_stop()
		var stats := [["Heure", view.day_night.clock_text() if view else "--"], ["Vitesse", "%d km/h" % roundi(session.phys.speed * 3.6)],
			["Prochain arrêt", str(st.get("name", "—"))], ["Voyageurs", str(session.phys.passengers)]]
		pause_layer = _overlay("Pause", "pause", UiTheme.ACCENT, [["Reprendre  (Échap)", "play", "primary", func(): _set_paused(false)],
			["Aide clavier  (F1)", "keyboard", "normal", _toggle_help], ["Menu principal", "home", "normal", func(): _persist(); _build_menu()]], "", stats)

## Calque modal : fond assombri + carte centrée (titre, statistiques, texte, boutons).
func _overlay(title: String, icon_name: String, col: Color, buttons: Array, body: String = "", stats: Array = [], extra: Control = null, panel_width: float = 520.0) -> Control:
	var layer := ColorRect.new(); layer.color = Color(0.02, 0.03, 0.05, 0.62); layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(layer)
	var c := CenterContainer.new(); c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); layer.add_child(c)
	var p := UiTheme.panel(Color(0.08, 0.1, 0.13, 0.96), 22, 26); c.add_child(p)
	var scroll := TouchScroll.new(); scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO; p.add_child(scroll)
	var v := VBoxContainer.new(); v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 14); scroll.add_child(v)
	var fit := func():
		var safe := UiLayout.safe_insets(self)
		var width_ := maxf(240.0, minf(panel_width, size.x - safe.x - safe.z - 84.0))
		v.custom_minimum_size.x = width_ - 20.0
		scroll.custom_minimum_size = Vector2(width_, maxf(100.0, minf(v.get_combined_minimum_size().y, size.y - safe.y - safe.w - 84.0)))
	v.minimum_size_changed.connect(fit); layer.resized.connect(fit); fit.call_deferred()
	var h := HBoxContainer.new(); h.add_theme_constant_override("separation", 14); v.add_child(h)
	var ib := PanelContainer.new(); ib.add_theme_stylebox_override("panel", UiTheme.box(Color(col, 0.2), 14, 10)); h.add_child(ib)
	ib.add_child(UiTheme.icon_rect(icon_name, 32, col))
	var t := UiTheme.label_(title, UiTheme.SIZE_H1, UiTheme.TEXT, true); t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; t.custom_minimum_size = Vector2(0, 0); h.add_child(t)
	if not stats.is_empty():
		var g := GridContainer.new(); g.columns = mini(stats.size(), 4); g.add_theme_constant_override("h_separation", 22); v.add_child(g)
		for s in stats:
			var sv := VBoxContainer.new(); sv.add_theme_constant_override("separation", -2); g.add_child(sv)
			sv.add_child(UiTheme.label_(str(s[0]).to_upper(), UiTheme.SIZE_CAPTION, UiTheme.MUTED, true))
			var val := UiTheme.label_(str(s[1]), UiTheme.SIZE_BODY, s[2] if s.size() > 2 else UiTheme.TEXT, true)
			val.clip_text = true; val.custom_minimum_size = Vector2(100, 0); sv.add_child(val)
	if body != "":
		var l := UiTheme.label_(body, UiTheme.SIZE_SMALL, UiTheme.MUTED); l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; v.add_child(l)
	if extra: v.add_child(extra)
	for spec in buttons:
		var b := UiTheme.button(spec[0], spec[1], spec[2], Vector2(0, 60)); b.pressed.connect(spec[3]); v.add_child(b)
	UiTheme.fade_in(layer, 0.18)
	return layer

func _toggle_help() -> void:
	if help_layer:
		help_layer.queue_free(); help_layer = null
		paused = bool(get_meta("help_previous_paused", false)); return
	set_meta("help_previous_paused", paused); paused = session != null
	var g := GridContainer.new(); g.columns = 2 if UiLayout.compact(self) else 4; g.add_theme_constant_override("h_separation", 14); g.add_theme_constant_override("v_separation", 8)
	for k in KEYS:
		var kc := UiTheme.keycap(k[0]); kc.size_flags_horizontal = Control.SIZE_SHRINK_END; g.add_child(kc)
		var l := UiTheme.label_(k[1], UiTheme.SIZE_SMALL, UiTheme.TEXT); l.custom_minimum_size = Vector2(0 if UiLayout.compact(self) else 250, 0)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; l.size_flags_horizontal = Control.SIZE_EXPAND_FILL; g.add_child(l)
	help_layer = _overlay("Commandes", "keyboard", UiTheme.INFO, [["Fermer  (F1)", "close", "normal", _toggle_help]], "© OpenStreetMap : ODbL 1.0 · IGN BD TOPO/RGE ALTI : Licence Ouverte 2.0 · Godot : MIT. Crédits complets : CREDITS.md.", [], g, 960.0)
	help_layer.name = "help"

func _show_tuto() -> void:
	tuto = Control.new(); tuto.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); tuto.mouse_filter = Control.MOUSE_FILTER_STOP
	tuto.gui_input.connect(_tuto_input); add_child(tuto)
	var c := CenterContainer.new(); c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); c.mouse_filter = Control.MOUSE_FILTER_IGNORE; tuto.add_child(c)
	var p := UiTheme.panel(Color(0.07, 0.09, 0.12, 0.94), 20, 22); p.mouse_filter = Control.MOUSE_FILTER_IGNORE; c.add_child(p)
	var v := VBoxContainer.new(); v.custom_minimum_size = Vector2(520, 0); v.add_theme_constant_override("separation", 8); v.mouse_filter = Control.MOUSE_FILTER_IGNORE; p.add_child(v)
	v.add_child(UiTheme.label_("", UiTheme.SIZE_CAPTION, UiTheme.ACCENT, true))
	v.add_child(UiTheme.label_("", UiTheme.SIZE_H2, UiTheme.TEXT, true))
	var b := UiTheme.label_("", UiTheme.SIZE_BODY, UiTheme.TEXT); b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; v.add_child(b)
	v.add_child(UiTheme.label_("Touchez pour continuer", UiTheme.SIZE_CAPTION, UiTheme.MUTED))
	_tuto_text()
	UiTheme.fade_in(tuto, 0.25)

func _tuto_text() -> void:
	var v := tuto.get_child(0).get_child(0).get_child(0)
	(v.get_child(0) as Label).text = "ASTUCE %d / %d" % [tuto_step + 1, TUTO.size()]
	(v.get_child(1) as Label).text = TUTO[tuto_step][0]
	(v.get_child(2) as Label).text = TUTO[tuto_step][1]

func _tuto_input(ev: InputEvent) -> void:
	if (ev is InputEventMouseButton and ev.pressed) or (ev is InputEventScreenTouch and ev.pressed):
		tuto_step += 1
		if tuto_step >= TUTO.size():
			tuto.queue_free(); tuto = null
			save.settings.tutorial_done = true; SaveGame.save_data(save)
		else:
			_tuto_text()

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

func _time_speed() -> float:
	return 60.0 if int(save.settings.get("time_mode", 0)) == 4 else 1.0

func current_hour() -> float:
	return hour0 + session.time_s * _time_speed() / 3600.0

func _next_stop() -> Dictionary:
	if session == null: return {}
	if free_mode: return session.next_station_ahead()
	return session.stops[mini(session.next_station, session.stops.size() - 1)] if not session.stops.is_empty() else {}

# ----------------------------------------------------------------------------------------------- entrées

func _unhandled_input(ev: InputEvent) -> void:
	if intro != null: return
	if view == null or paused or plan_panel != null or help_layer != null: return
	if (ev is InputEventMouseButton or ev is InputEventMouseMotion) and ev.device == -1: return
	if ev is InputEventScreenTouch or ev is InputEventScreenDrag:
		var action := camera_gestures.feed(ev)
		if action.has("zoom"): _zoom(float(action.zoom))
		elif action.has("pan"): view.orbit -= action.pan.x * 0.006
	elif ev is InputEventMouseMotion and (ev.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		view.orbit -= ev.relative.x * 0.006
	elif ev is InputEventMouseButton and ev.pressed:
		if ev.button_index == MOUSE_BUTTON_WHEEL_UP: _zoom(1.0 / 0.9)
		elif ev.button_index == MOUSE_BUTTON_WHEEL_DOWN: _zoom(1.0 / 1.1)
	elif ev is InputEventMagnifyGesture:
		_zoom(ev.factor)

func _input(ev: InputEvent) -> void:
	if intro != null:   # intro de lancement : touche, clic ou toucher pour passer
		if (ev is InputEventKey and ev.pressed and not ev.echo) or (ev is InputEventMouseButton and ev.pressed) or (ev is InputEventScreenTouch and ev.pressed):
			intro.skip(); get_viewport().set_input_as_handled()
		return
	if is_instance_valid(explore): return   # le mode Explorer gère ses propres entrées
	if ev is InputEventScreenTouch and not ev.pressed: camera_gestures.feed(ev)
	if not (ev is InputEventKey) or not ev.pressed or ev.echo:
		return
	var k: int = ev.physical_keycode if ev.physical_keycode != 0 else ev.keycode
	if k == KEY_F11:
		var w := get_window()
		w.mode = Window.MODE_WINDOWED if w.mode == Window.MODE_FULLSCREEN else Window.MODE_FULLSCREEN
		return
	if k == KEY_F1:
		_toggle_help(); get_viewport().set_input_as_handled(); return
	if help_layer and k == KEY_ESCAPE:
		_toggle_help(); get_viewport().set_input_as_handled(); return
	# saisie en cours (recherche d'arrêt) : les lettres vont au champ texte
	if get_viewport().gui_get_focus_owner() is LineEdit and k != KEY_ESCAPE: return
	if session == null:
		if _menu_key(k, ev): get_viewport().set_input_as_handled()
		return
	match k:
		KEY_ESCAPE:
			if plan_panel: _toggle_plan()
			else: _set_paused(not paused)
		KEY_SPACE: _manual(); _emergency()
		KEY_X: _manual(); _set_notch(0.0)
		KEY_L: _toggle_autopilot()
		KEY_O: _doors()
		KEY_K: _horn()
		KEY_C: _camera()
		KEY_M: _toggle_plan()
		KEY_P: _power_picker()
		KEY_A: _toggle_plan()
		KEY_R: _rerail()
		KEY_V: _reverse()
		KEY_T: _traffic()
		KEY_W, KEY_Z, KEY_UP: _manual(); _set_notch(notch + 0.25)
		KEY_S, KEY_DOWN: _manual(); _set_notch(notch - 0.25)
		_: return
	get_viewport().set_input_as_handled()

# ----------------------------------------------------------------------------------------------- boucle

func _fmt_clock(h: float) -> String:
	h = fposmod(h, 24.0)
	var s := int(round(h * 3600.0))
	return "%02d:%02d:%02d" % [s / 3600 % 24, s / 60 % 60, s % 60]

func _process(dt: float) -> void:
	if session == null: return
	if intro != null:   # Camera owns the frozen world; no duplicate detailed tile builds.
		return
	if not paused and not session.finished:
		weather.step(minf(dt,.1));weather.apply_to(session)
		if session.ai!=null:
			for train in session.ai.trams:weather.apply_to(train)
		if autopilot.enabled:
			if free == null or free.incident != "": _set_autopilot(false, "Pilote automatique coupé : incident")
			else: notch = autopilot.control(session, minf(dt, 0.1))
		session.tick(minf(dt, 0.1), notch, emergency)
		if emergency and session.phys.speed < 0.05: emergency = false
	view.set_hour(current_hour())
	view.update_from(session, external_cam)
	if is_instance_valid(weather_view):weather_view.apply(weather,view,NetworkLoader.in_spans(net.edge_info[session.edge_id].tunnel,session.offset))
	if is_instance_valid(tram_audio): tram_audio.update(session, notch, emergency, external_cam, paused, dt)
	if plan_panel and Engine.get_process_frames() % 15 == 0: plan_panel.canvas.queue_redraw()
	_tick_toasts(dt)
	if is_instance_valid(power_button):
		var caption := power_button.get_child(0).get_child(1) as Label
		caption.text = MissionSession.power_label(session.power_mode) + ("…" if session.power_transition_left > 0.0 else "")
		power_button.tooltip_text = "Alimentation : " + caption.text + " (à l’arrêt)"
	var lim := session.speed_limit() * 3.6
	hud_speed.set_values(session.phys.speed * 3.6, lim, session.phys.profile.max_speed_ms * 3.6, session.overspeed)
	if lever and lever.value != notch: lever.set_value(notch)
	notch_label.text = ("Auto · " + autopilot.status) if autopilot.enabled else ("Traction %d %%" % roundi(notch * 100)) if notch > 0.01 else (("URGENCE" if notch <= -0.99 else "Freinage %d %%" % roundi(-notch * 100)) if notch < -0.01 else "Neutre")
	notch_label.add_theme_color_override("font_color", UiTheme.TRACTION if notch > 0.01 else (UiTheme.BRAKE if notch < -0.01 else UiTheme.TEXT))
	var alerts: Array = []
	if session.phys.wheel_slip: alerts.append("PATINAGE — RÉDUIRE LA TRACTION")
	if session.phys.rollback: alerts.append("RECUL — APPLIQUER LE FREIN")
	if not _speed_advice.is_empty() and session.phys.speed > float(_speed_advice.limit) + 0.5:
		alerts.append("RALENTIR : %d km/h dans %d m" % [roundi(float(_speed_advice.limit) * 3.6), roundi(_speed_advice.distance)])
	if session.overspeed: alerts.append("SURVITESSE")
	if not session.power_ok: alerts.append("COMMUTATION EN COURS" if session.power_transition_left > 0.0 else "COUPURE — MODE " + MissionSession.power_label(session.power_mode))
	if emergency: alerts.append("FREINAGE D'URGENCE")
	if free and free.incident != "": alerts.append("INCIDENT : " + free.incident + " — remise sur voie (R)")
	hud_alert.text = "  ·  ".join(alerts)
	_alert_box.visible = not alerts.is_empty()
	if _alert_box.visible: _alert_box.modulate.a = 0.75 + 0.25 * sin(Time.get_ticks_msec() * 0.008)
	# voyants
	_set_lamp("doors", 2 if session.doors_open else 1, "Portes ouvertes" if session.doors_open else "Portes")
	_set_lamp("panto", 1 if session.pantograph_up else 0, "Panto")
	_set_lamp("power", 1 if session.power_ok else 3, MissionSession.power_label(session.power_mode) if session.power_ok else ("Commutation" if session.power_transition_left > 0.0 else "Coupure"))
	_set_lamp("emerg", 3 if emergency else 0, "Urgence")
	_hud_t -= dt
	if _hud_t > 0.0 and not session.finished: return
	_hud_t = 0.2
	_speed_advice = session.next_restriction()
	if is_instance_valid(signal_panel): signal_panel.refresh()
	hud_clock.text = view.day_night.clock_text()
	var st := _next_stop()
	hud_info.text = str(st.get("name", "—"))
	var sub := PackedStringArray()
	if not st.is_empty():
		var d := session.station_distance(st)
		if d >= 0.0 and d < 2999.0: sub.append("dans %d m" % roundi(d) if d >= 15.0 else "à quai")
	var gradient := net.grade_at(session.edge_id, session.offset) * session.direction * 1000.0
	hud_grade.text = "%s %+.1f ‰" % ["Montée" if gradient > 0.5 else ("Descente" if gradient < -0.5 else "Palier"), gradient]
	var modes := PackedStringArray()
	for mode in net.supplies_at(session.edge_id, session.offset): modes.append(MissionSession.power_label(mode))
	sub.append(" + ".join(modes))
	sub.append("%d voyageurs" % session.phys.passengers)
	hud_sub.text = "  ·  ".join(sub)
	hud_sched.text = ""
	if not free_mode and not session.finished and session.next_station < session.schedule.size():
		var due: float = session.schedule[session.next_station]
		var rest := due - session.time_s
		var at := _fmt_clock(hour0 + due * _time_speed() / 3600.0).substr(0, 5)
		if rest >= 0.0:
			hud_sched.text = "départ %s · dans %d s" % [at, roundi(rest)]
			hud_sched.add_theme_color_override("font_color", UiTheme.SUCCESS)
		else:
			hud_sched.text = "départ %s · retard +%d s" % [at, roundi(-rest)]
			hud_sched.add_theme_color_override("font_color", UiTheme.WARNING if rest > -60.0 else UiTheme.DANGER)
	elif free_mode:
		hud_sched.text = "mode libre" + ("" if session.direction > 0 or net.meta.get("geometry_kind", "") == "physical" else " · contre-sens")
		hud_sched.add_theme_color_override("font_color", UiTheme.MUTED)
	if hud_switch:
		var up := NetworkPlan.upcoming(free, 2500.0)
		if up.is_empty():
			hud_switch.text = "Aucun aiguillage devant"; hud_switch.modulate = Color(1, 1, 1, 0.7)
		else:
			var u: Array = up[0]
			hud_switch.text = "Aiguillage à %d m  →  %s" % [roundi(u[2]), NetworkPlan.branch_text(free, u[0], u[1])]
			hud_switch.modulate = Color.WHITE
	if session.finished and not _result_saved:
		_result_saved = true
		var d := session.debrief()
		SaveGame.add_result(save, net_path, vehicle.id, d)
		SaveGame.save_data(save)
		_show_debrief(d)

func _show_debrief(d: Dictionary) -> void:
	var names := ["à l'heure", "départ anticipé", "retard > 60 s", "arrêt oublié"]
	var cols := [UiTheme.SUCCESS, UiTheme.WARNING, UiTheme.BRAKE, UiTheme.DANGER]
	var counts := [0, 0, 0, 0]
	for s in d.stops: counts[clampi(int(s.result), 0, 3)] += 1
	var stats := [["Durée", "%d min %02d s" % [int(d.time_s) / 60, int(d.time_s) % 60]]]
	for i in 4: stats.append([names[i], str(counts[i]), cols[i] if counts[i] > 0 else UiTheme.TEXT])
	var sc := TouchScroll.new(); sc.custom_minimum_size = Vector2(0, 220); sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var lst := VBoxContainer.new(); lst.size_flags_horizontal = Control.SIZE_EXPAND_FILL; sc.add_child(lst)
	for s in d.stops:
		var h := HBoxContainer.new(); h.add_theme_constant_override("separation", 10); lst.add_child(h)
		var dot := ColorRect.new(); dot.color = cols[clampi(int(s.result), 0, 3)]; dot.custom_minimum_size = Vector2(10, 10)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER; h.add_child(dot)
		var n := UiTheme.label_(str(s.name), UiTheme.SIZE_SMALL); n.size_flags_horizontal = Control.SIZE_EXPAND_FILL; h.add_child(n)
		h.add_child(UiTheme.label_(names[clampi(int(s.result), 0, 3)], UiTheme.SIZE_SMALL, UiTheme.MUTED))
	debrief_layer = _overlay("Mission réussie" if d.success else "Échec — " + str(d.reason), "check" if d.success else "flag",
		UiTheme.SUCCESS if d.success else UiTheme.DANGER,
		[["Rejouer", "play", "primary", func(): _start()], ["Menu principal", "home", "normal", func(): _build_menu()]], "", stats, sc)
	debrief_layer.name = "debrief"
