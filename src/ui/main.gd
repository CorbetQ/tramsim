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
	["V", "Changer de sens (mode libre)"], ["R", "Remise sur voie (mode libre)"], ["T", "Trafic automobile (mode libre)"],
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
var tram_audio: TramAudio
var bell: AudioStreamPlayer
var _alert_box: PanelContainer
var _hud_t := 0.0
var _compact := false
var _resize_pending := false
var camera_gestures := MapGestures.new()

func _ready() -> void:
	UiLayout.configure(get_window())
	_compact = UiLayout.compact(self)
	get_window().size_changed.connect(func(): UiLayout.configure(get_window()))
	resized.connect(_layout_changed)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = UiTheme.build()
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR   # icônes SVG nettes à toutes les échelles
	save = SaveGame.load_data()
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
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		if session != null and not paused:
			_set_paused(true)
		_persist()

func _persist() -> void:
	if free != null and vehicle != null:
		SaveGame.store_free(save, free, net_path, vehicle.id)
	SaveGame.save_data(save)

func _clear() -> void:
	camera_gestures.reset()
	for c in get_children():
		if c != bell: c.queue_free()
	view = null; tram_audio = null; session = null; free = null; tuto = null; plan_panel = null; pause_layer = null; debrief_layer = null
	help_layer = null; toasts = null; hud_switch = null; lamps.clear()

# ----------------------------------------------------------------------------------------------- menu

func _backdrop() -> void:
	var bg := TextureRect.new(); bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var gt := GradientTexture2D.new(); gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.8, 0.15); gt.fill_to = Vector2(0.0, 1.1); gt.width = 256; gt.height = 256
	var gr := Gradient.new(); gr.set_color(0, Color("#13312f")); gr.set_color(1, UiTheme.BG)
	gt.gradient = gr; bg.texture = gt; bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

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
		lamps.clear(); _build_hud(); _hud_t = 0.0

func _build_menu() -> void:
	_clear()
	paused = false
	_backdrop()
	if has_meta("catalogue_pick"): menu_page = "setup"
	if menu_page == "setup": _build_setup()
	else: _build_home()

func _build_home() -> void:
	var page := _page()
	var row := HBoxContainer.new(); row.add_theme_constant_override("separation", 40); page.add_child(row)
	var left := VBoxContainer.new(); left.size_flags_horizontal = Control.SIZE_EXPAND_FILL; left.size_flags_stretch_ratio = 1.0
	left.alignment = BoxContainer.ALIGNMENT_CENTER; left.add_theme_constant_override("separation", 14); row.add_child(left)
	var brand := HBoxContainer.new(); brand.add_theme_constant_override("separation", 16); left.add_child(brand)
	var logo := PanelContainer.new(); logo.add_theme_stylebox_override("panel", UiTheme.box(UiTheme.ACCENT, 16, 10)); brand.add_child(logo)
	var li := UiTheme.icon_rect("tram", 44, Color("#04201c")); logo.add_child(li)
	var tv := VBoxContainer.new(); tv.add_theme_constant_override("separation", -4); brand.add_child(tv)
	tv.add_child(UiTheme.label_("Tram Sim France", UiTheme.SIZE_DISPLAY, UiTheme.TEXT, true))
	tv.add_child(UiTheme.label_("Conduisez les tramways de %d villes françaises" % NetworkRegistry.cities().size(), UiTheme.SIZE_BODY, UiTheme.MUTED))
	left.add_child(_spacer(10))
	var cards := [
		["mission", "Mission horaire", "Un service réel (horaires GTFS) : desserte, ponctualité, signalisation.", func(): free_mode = false; menu_page = "setup"; _build_menu()],
		["free", "Mode libre", "Le réseau complet de la ville : aiguillages, changements de sens, trafic.", func(): free_mode = true; menu_page = "setup"; _build_menu()],
		["catalogue", "Catalogue des rames", "Fiches techniques, livrées et lignes de chaque matériel.", func(): _open_catalogue("")]]
	for c in cards:
		var b := _card_button(c[0], c[1], c[2]); b.pressed.connect(c[3]); left.add_child(b)
	left.add_child(_spacer(6))
	var hint := HBoxContainer.new(); hint.add_theme_constant_override("separation", 8); left.add_child(hint)
	hint.add_child(UiTheme.keycap("F1")); hint.add_child(UiTheme.label_("aide clavier", UiTheme.SIZE_SMALL, UiTheme.MUTED))
	hint.add_child(UiTheme.keycap("F11")); hint.add_child(UiTheme.label_("plein écran", UiTheme.SIZE_SMALL, UiTheme.MUTED))
	# vitrine : aperçu 3D d'une rame
	var right := VBoxContainer.new(); right.size_flags_horizontal = Control.SIZE_EXPAND_FILL; right.size_flags_stretch_ratio = 1.05
	right.alignment = BoxContainer.ALIGNMENT_CENTER; row.add_child(right); right.visible = not UiLayout.compact(self)
	var pc := UiTheme.panel(Color(0, 0, 0, 0.25), 22, 6); right.add_child(pc)
	var preview := TramPreview.new(); pc.add_child(preview); preview.custom_minimum_size = Vector2(480, 400)
	var entries := NetworkRegistry.entries()
	if not entries.is_empty():
		var e: Dictionary = entries[0]
		for x in entries:
			if str(x.city) == "Bordeaux": e = x; break
		var meta := Catalogue.meta_of(str(e.path))
		preview.show_tram(meta, VehicleLibrary.default_for(meta))
		var cap := UiTheme.label_("%s — ligne %s" % [e.city, e.line], UiTheme.SIZE_SMALL, UiTheme.MUTED)
		cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; right.add_child(cap)
	UiTheme.fade_in(page, 0.3)

func _spacer(h: float) -> Control:
	var s := Control.new(); s.custom_minimum_size = Vector2(0, h); s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return s

## Carte cliquable : icône, titre, description.
func _card_button(icon_name: String, title: String, desc: String) -> Button:
	var b := Button.new(); b.custom_minimum_size = Vector2(0, 92); b.name = "card_" + icon_name
	b.tooltip_text = desc; b.set_meta("title", title)
	b.add_theme_stylebox_override("normal", UiTheme.box(UiTheme.SURFACE, 18, 18, UiTheme.BORDER, 1))
	b.add_theme_stylebox_override("hover", UiTheme.box(UiTheme.SURFACE_3, 18, 18, Color(UiTheme.ACCENT, 0.7), 2))
	b.add_theme_stylebox_override("pressed", UiTheme.box(Color(UiTheme.ACCENT, 0.3), 18, 18, UiTheme.ACCENT, 2))
	var h := HBoxContainer.new(); h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 18; h.offset_right = -18; h.add_theme_constant_override("separation", 18); h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(h)
	var ib := PanelContainer.new(); ib.add_theme_stylebox_override("panel", UiTheme.box(Color(UiTheme.ACCENT, 0.16), 14, 10))
	ib.size_flags_vertical = Control.SIZE_SHRINK_CENTER; ib.mouse_filter = Control.MOUSE_FILTER_IGNORE; h.add_child(ib)
	ib.add_child(UiTheme.icon_rect(icon_name, 34, UiTheme.ACCENT))
	var v := VBoxContainer.new(); v.alignment = BoxContainer.ALIGNMENT_CENTER; v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE; h.add_child(v)
	v.add_child(UiTheme.label_(title, UiTheme.SIZE_H2, UiTheme.TEXT, true))
	var d := UiTheme.label_(desc, UiTheme.SIZE_SMALL, UiTheme.MUTED); d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; v.add_child(d)
	h.add_child(UiTheme.icon_rect("chevron", 22, UiTheme.MUTED))
	UiTheme.hover_fx(b)
	return b

## Carte d'étape numérotée de la configuration.
func _step(parent: Control, n: int, title: String) -> VBoxContainer:
	var p := UiTheme.panel(UiTheme.SURFACE, 16, 16); parent.add_child(p)
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 10); p.add_child(v)
	var h := HBoxContainer.new(); h.add_theme_constant_override("separation", 10); v.add_child(h)
	var num := UiTheme.label_(str(n), UiTheme.SIZE_SMALL, Color("#04201c"), true); num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	num.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	num.add_theme_stylebox_override("normal", UiTheme.box(UiTheme.ACCENT, 13, 6)); num.custom_minimum_size = Vector2(28, 28)
	h.add_child(num)
	h.add_child(UiTheme.label_(title, UiTheme.SIZE_BODY, UiTheme.TEXT, true))
	return v

func _build_setup() -> void:
	var page := _page()
	var col := VBoxContainer.new(); col.add_theme_constant_override("separation", 14); page.add_child(col)
	# barre supérieure : retour, mode (segmenté), catalogue
	var top := HBoxContainer.new(); top.add_theme_constant_override("separation", 12); col.add_child(top)
	var back := UiTheme.button("Accueil", "back", "ghost", Vector2(0, 52)); top.add_child(back)
	back.pressed.connect(func(): menu_page = "home"; _build_menu())
	var title := UiTheme.label_("Préparer le service", UiTheme.SIZE_H1, UiTheme.TEXT, true)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL; top.add_child(title); title.visible = not UiLayout.compact(self)
	var seg := PanelContainer.new(); seg.add_theme_stylebox_override("panel", UiTheme.box(Color(0, 0, 0, 0.3), 14, 4)); top.add_child(seg)
	var modes := HBoxContainer.new(); modes.add_theme_constant_override("separation", 4); seg.add_child(modes)
	var grp := ButtonGroup.new()
	var b_mis := UiTheme.button("Mission" if UiLayout.compact(self) else "Mission horaire", "mission", "chip", Vector2(0, 48)); b_mis.toggle_mode = true; b_mis.button_group = grp
	var b_free := UiTheme.button("Libre" if UiLayout.compact(self) else "Mode libre", "free", "chip", Vector2(0, 48)); b_free.toggle_mode = true; b_free.button_group = grp
	modes.add_child(b_mis); modes.add_child(b_free)
	b_free.button_pressed = free_mode; b_mis.button_pressed = not free_mode
	var cities := NetworkRegistry.cities()
	var city_ref := [""]
	var cat_btn := UiTheme.button("Catalogue", "catalogue", "normal", Vector2(0, 52)); top.add_child(cat_btn)
	cat_btn.tooltip_text = "Catalogue des rames : fiches techniques, livrées, choix du matériel"
	cat_btn.pressed.connect(func(): _open_catalogue(city_ref[0]))
	# corps : étapes à gauche, aperçu et départ à droite
	var body := HBoxContainer.new(); body.add_theme_constant_override("separation", 22); body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(body)
	var sc := TouchScroll.new(); sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL; sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(sc)
	var box := VBoxContainer.new(); box.size_flags_horizontal = Control.SIZE_EXPAND_FILL; box.add_theme_constant_override("separation", 12)
	sc.add_child(box)
	var s1 := _step(box, 1, "Ville et ligne")
	var city_opt := _opt(s1, "Ville")
	for c in cities: city_opt.add_item(c)
	var line_row := _row(s1, "Ligne"); var line_opt: TouchChoice = line_row.get_child(1)
	var s2 := _step(box, 2, "Service")
	var mis_row := _row(s2, "Service"); var mis_opt: TouchChoice = mis_row.get_child(1)
	var st_row := _row(s2, "Départ"); var st_opt: TouchChoice = st_row.get_child(1)
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
	# colonne droite
	var right := VBoxContainer.new(); right.add_theme_constant_override("separation", 12); right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_stretch_ratio = 0.9; body.add_child(right)
	var pc := UiTheme.panel(Color(0, 0, 0, 0.28), 20, 6); pc.size_flags_vertical = Control.SIZE_EXPAND_FILL; right.add_child(pc)
	var preview := TramPreview.new(); pc.add_child(preview); preview.custom_minimum_size = Vector2(240, 140) if UiLayout.compact(self) else Vector2(420, 240)
	var sum := HBoxContainer.new(); sum.add_theme_constant_override("separation", 10); right.add_child(sum)
	var badge := UiTheme.line_badge("", UiTheme.INFO, UiTheme.SIZE_H2); badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER; sum.add_child(badge)
	var sheet := UiTheme.label_("", UiTheme.SIZE_SMALL, UiTheme.TEXT); sheet.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sheet.size_flags_horizontal = Control.SIZE_EXPAND_FILL; sheet.max_lines_visible = 2; sheet.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	sum.add_child(sheet)
	var go := UiTheme.button("Démarrer", "play", "primary", Vector2(0, 72)); go.add_theme_font_size_override("font_size", 28)
	go.name = "start"; right.add_child(go)
	# état du menu (tableaux partagés : modifiés en place depuis les lambdas)
	var all_nets: Array = NetworkRegistry.entries()
	var city_nets: Array = []
	var mis_list: Array = []
	var st_list: Array = []
	var vehicles: Array = []
	var cur_meta: Dictionary = {}
	var free_path := func() -> String: return "res://data/free/%s.json" % _source_of(city_nets)
	var fill := func():
		var is_free := b_free.button_pressed
		line_row.visible = not is_free; mis_row.visible = not is_free; st_row.visible = is_free
		city_ref[0] = cities[city_opt.selected]
		city_nets.clear()
		city_nets.append_array(all_nets.filter(func(e): return e.city == cities[city_opt.selected]))
		if line_opt.item_count == 0 or line_opt.get_meta("city", "") != cities[city_opt.selected]:
			line_opt.clear()
			for e in city_nets:
				line_opt.add_icon_item(_swatch(_line_color(str(e.path))), "%s — %s%s" % [e.line, e.long_name, "  (tram-train)" if e.kind == "tram-train" else ""])
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
		if is_free:
			for depot in n.meta.get("depots", []):
				st_list.append(depot); st_opt.add_item("Remisage — " + str(depot.name))
		vehicles.clear(); veh_opt.clear()
		if is_free:
			for entry in StockCatalog.for_network(n.meta,n.supplies):
				vehicles.append(VehicleLibrary.for_fleet(entry,n.meta))
				veh_opt.add_item(str(entry.name)+" · "+str(entry.city)+(" · FICTIF" if entry.fictional else ""))
		else:
			for f in TramModel.fleet_for(n.meta):
				vehicles.append(VehicleLibrary.for_fleet(f,n.meta));veh_opt.add_item(f.name)
		cur_meta["required_supplies"]=n.supplies.duplicate()
	var refresh := func(_i = 0):
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
		sheet.text = "%s · %s\n%s" % [cities[city_opt.selected], v.family,
			(mis_opt.get_item_text(mis_opt.selected) if mis_opt.selected >= 0 else "") if not is_free else (st_opt.get_item_text(st_opt.selected) if st_opt.selected >= 0 else "")]
		go.disabled = not ok
		go.text = "Démarrer" if ok else "Matériel incompatible"

	var full := func(_i = 0):
		fill.call(); veh_opt.select(0); refresh.call()
	city_opt.item_selected.connect(full)
	line_opt.item_selected.connect(full)
	b_mis.toggled.connect(func(on): if on: free_mode = false; full.call())
	b_free.toggled.connect(func(on): if on: free_mode = true; full.call())
	veh_opt.item_selected.connect(refresh)
	mis_opt.item_selected.connect(refresh)
	st_opt.item_selected.connect(refresh)
	var last := cities.find(str(save.settings.get("last_city", "")))
	if last >= 0: city_opt.select(last)
	full.call()
	# choix venu du catalogue (« Conduire cette rame ») : ville, ligne et matériel, puis départ
	var pick: Dictionary = get_meta("catalogue_pick", {})
	if not pick.is_empty():
		remove_meta("catalogue_pick")
		if pick.get("free",false):b_free.button_pressed=true;b_mis.button_pressed=false;free_mode=true
		var ci := cities.find(str(pick.city))
		if ci >= 0:
			city_opt.select(ci); fill.call()
			for i in city_nets.size():
				if city_nets[i].path == pick.path: line_opt.select(i)
			fill.call()
			for i in vehicles.size():
				if (str(pick.get("variant_id",""))!="" and (vehicles[i] as VehicleProfile).variant_id==str(pick.variant_id)) or (str(pick.get("variant_id",""))=="" and (vehicles[i] as VehicleProfile).model_family==pick.family): veh_opt.select(i);break
			refresh.call()
	go.pressed.connect(func():
		save.settings.traffic = traffic_cb.button_pressed
		save.settings.time_mode = time_opt.selected
		save.settings.last_city = cities[city_opt.selected]
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
	UiTheme.fade_in(page, 0.25)
	if pick.get("start", false) and not go.disabled: go.pressed.emit()

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

func _source_of(city_nets: Array) -> String:
	if city_nets.is_empty(): return ""
	var n := NetworkLoader.new(); n.load_file(city_nets[0].path)
	return str(n.meta.get("source_id", ""))

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

func _start() -> void:
	_clear()
	_result_saved = false
	_speed_advice = {}
	paused = false
	emergency = false
	notch = -0.75 # F3 : immobilisation dès l’apparition, y compris en rampe.
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
		var normal := int(net.edge_info[e].get("preferred_direction", 0))
		free.direction = normal if normal != 0 else int(start_station.get("direction", 1))
		free.route_dir = [free.direction]; free.checkpoint_dir = free.direction; free.update_spans()
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
	# DayNight applique déjà le budget d’ombres mobile.
	if OS.has_feature("mobile") and view.city: view.city.radius = 450.0
	view.update_from(session, true)
	if view.city: view.city.warm(view.cam.global_position)
	view.cam.current = true
	tram_audio = TramAudio.new(view, bell); add_child(tram_audio)   # moteur sonore de la rame
	_build_hud()
	_set_notch(notch)
	if free and free.adaptation_notice != "": _log(free.adaptation_notice)
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
	var badge := UiTheme.line_badge(str(net.meta.get("line", "")) if not free_mode else str(net.meta.get("city", "")).substr(0, 3), lc, UiTheme.SIZE_H2)
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
	lever.changed.connect(func(v): notch = v; if v > -0.99: emergency = false)
	lv.add_child(lever)
	var minus := UiTheme.button("", "minus", "normal", Vector2(130, 50)); minus.tooltip_text = "Freinage (S)"; minus.name = "brake"
	minus.focus_mode = Control.FOCUS_NONE; lv.add_child(minus); minus.visible = not compact
	notch_label = UiTheme.label_("N", UiTheme.SIZE_SMALL, UiTheme.TEXT, true); notch_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	notch_label.custom_minimum_size = Vector2(0, 48 if compact else 34); notch_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	notch_label.mouse_filter = Control.MOUSE_FILTER_STOP; notch_label.tooltip_text = "Toucher : neutre (X)"
	notch_label.gui_input.connect(func(ev): if (ev is InputEventMouseButton or ev is InputEventScreenTouch) and ev.pressed: _set_notch(0.0))
	lv.add_child(notch_label)
	plus.pressed.connect(func(): _set_notch(notch + 0.25))
	minus.pressed.connect(func(): _set_notch(notch - 0.25))
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
		specs += [["Changer de sens", "reverse", "V", _reverse], ["Remise sur voie", "rerail", "R", _rerail], ["Trafic", "traffic", "T", _traffic]]
	for spec in specs:
		var b := UiTheme.tool_button(spec[0], spec[1], "" if compact else spec[2], 72.0 if compact else 88.0); b.pressed.connect(spec[3])
		b.add_theme_stylebox_override("normal", UiTheme.box(Color(UiTheme.SURFACE, 0.82), 14, 8, UiTheme.BORDER, 1))
		tools.add_child(b)
		if spec[1] == "power": power_button = b
	for c in [trip, tr, lp, rp, dock]: UiTheme.fade_in(c, 0.35)
	for c in get_children():
		if not c in before: c.add_to_group("driving_hud")

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

func _doors() -> void:
	var was := session.doors_open
	session.set_doors(not session.doors_open)
	if session.doors_open == was and not was:
		_log("Ouverture refusée : rame en mouvement", "warn")

func _horn() -> void:
	bell.play(); _log("Ding ding !", "info", "bell")

func _camera() -> void:
	external_cam = not external_cam
	_log("Caméra " + ("extérieure" if external_cam else "cabine"), "info", "camera")

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
	if view == null or paused or plan_panel != null or help_layer != null: return
	if (ev is InputEventMouseButton or ev is InputEventMouseMotion) and ev.device == -1: return
	if ev is InputEventScreenTouch or ev is InputEventScreenDrag:
		var action := camera_gestures.feed(ev)
		if action.has("zoom"): view.cam_dist = clampf(view.cam_dist / float(action.zoom), 14.0, 160.0)
		elif action.has("pan"): view.orbit -= action.pan.x * 0.006
	elif ev is InputEventMouseMotion and (ev.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		view.orbit -= ev.relative.x * 0.006
	elif ev is InputEventMouseButton and ev.pressed:
		if ev.button_index == MOUSE_BUTTON_WHEEL_UP: view.cam_dist = maxf(14.0, view.cam_dist * 0.9)
		elif ev.button_index == MOUSE_BUTTON_WHEEL_DOWN: view.cam_dist = minf(160.0, view.cam_dist * 1.1)
	elif ev is InputEventMagnifyGesture:
		view.cam_dist = clampf(view.cam_dist / ev.factor, 14.0, 160.0)

func _input(ev: InputEvent) -> void:
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
	if session == null: return
	match k:
		KEY_ESCAPE:
			if plan_panel: _toggle_plan()
			else: _set_paused(not paused)
		KEY_SPACE: _emergency()
		KEY_X: _set_notch(0.0)
		KEY_O: _doors()
		KEY_K: _horn()
		KEY_C: _camera()
		KEY_M: _toggle_plan()
		KEY_P: _power_picker()
		KEY_A: _toggle_plan()
		KEY_R: _rerail()
		KEY_V: _reverse()
		KEY_T: _traffic()
		KEY_W, KEY_Z, KEY_UP: _set_notch(notch + 0.25)
		KEY_S, KEY_DOWN: _set_notch(notch - 0.25)
		_: return
	get_viewport().set_input_as_handled()

# ----------------------------------------------------------------------------------------------- boucle

func _fmt_clock(h: float) -> String:
	h = fposmod(h, 24.0)
	var s := int(round(h * 3600.0))
	return "%02d:%02d:%02d" % [s / 3600 % 24, s / 60 % 60, s % 60]

func _process(dt: float) -> void:
	if session == null: return
	if not paused and not session.finished:
		session.tick(minf(dt, 0.1), notch, emergency)
		if emergency and session.phys.speed < 0.05: emergency = false
	view.set_hour(current_hour())
	view.update_from(session, external_cam)
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
	notch_label.text = ("Traction %d %%" % roundi(notch * 100)) if notch > 0.01 else (("URGENCE" if notch <= -0.99 else "Freinage %d %%" % roundi(-notch * 100)) if notch < -0.01 else "Neutre")
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
