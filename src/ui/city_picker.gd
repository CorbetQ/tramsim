class_name CityPicker
extends HBoxContainer
## Choix de la ville : liste filtrable (recherche) et carte de France cliquable (points des réseaux).
## Entrée dans la recherche : première ville trouvée. Cibles tactiles de 48 px.

signal chosen(city: String)

const FRANCE := [[51.09, 2.54], [50.95, 1.85], [50.1, 1.45], [49.75, 0.25], [49.45, 0.15], [49.3, -0.4], [49.65, -1.3], [49.7, -1.95],
	[49.2, -1.6], [48.65, -1.5], [48.85, -3.0], [48.6, -4.1], [48.4, -4.8], [48.0, -4.6], [47.8, -4.2], [47.5, -2.9], [47.2, -2.2],
	[46.8, -2.1], [46.2, -1.2], [45.6, -1.2], [44.6, -1.25], [43.55, -1.5], [43.35, -1.75], [43.0, -0.7], [42.8, 0.7], [42.6, 1.7],
	[42.45, 3.15], [43.0, 3.05], [43.4, 3.6], [43.55, 4.3], [43.35, 5.0], [43.1, 5.9], [43.4, 6.8], [43.7, 7.3], [43.8, 7.5], [44.15, 7.6],
	[44.4, 6.9], [45.1, 6.7], [45.5, 7.0], [45.9, 6.8], [46.4, 6.2], [46.5, 6.1], [47.0, 6.8], [47.5, 7.0], [47.6, 7.55], [48.1, 7.6],
	[48.95, 8.2], [49.15, 6.75], [49.55, 5.8], [49.8, 4.85], [50.15, 4.2], [50.35, 3.7], [50.75, 3.1]]

static var _origins: Dictionary = {}   # ville -> Vector2(lat, lon)

var cities: PackedStringArray
var selected := ""
var search: LineEdit
var map: Control
var _rows: VBoxContainer
var _buttons: Dictionary = {}
var _hover := ""

func _init(list: PackedStringArray, current: String, with_map := true) -> void:
	cities = list; selected = current
	add_theme_constant_override("separation", 12)
	var left := VBoxContainer.new(); left.size_flags_horizontal = Control.SIZE_EXPAND_FILL; left.add_theme_constant_override("separation", 8)
	add_child(left)
	search = LineEdit.new(); search.placeholder_text = "Rechercher une ville  ( / )"; search.custom_minimum_size = Vector2(0, 48)
	search.clear_button_enabled = true; search.name = "city_search"
	left.add_child(search)
	search.text_changed.connect(_filter)
	search.text_submitted.connect(func(_t):
		for c in cities:
			if _buttons[c].visible: pick(c); break)
	var sc := TouchScroll.new(); sc.custom_minimum_size = Vector2(0, 196); sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL; left.add_child(sc)
	_rows = VBoxContainer.new(); _rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL; _rows.add_theme_constant_override("separation", 4)
	sc.add_child(_rows)
	for c in cities:
		var n := NetworkRegistry.entries().filter(func(e): return e.city == c).map(func(e): return str(e.line))
		var uniq: Array = []
		for x in n:
			if not x in uniq: uniq.append(x)
		var b := UiTheme.button("%s   ·  %d ligne%s" % [c, uniq.size(), "s" if uniq.size() > 1 else ""], "", "ghost", Vector2(0, 48))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT; b.toggle_mode = true; b.name = "city_" + c.validate_node_name()
		b.set_meta("label", c); b.focus_mode = Control.FOCUS_ALL
		b.pressed.connect(pick.bind(c)); _rows.add_child(b); _buttons[c] = b
	if with_map:
		map = Control.new(); map.custom_minimum_size = Vector2(230, 230); map.name = "france_map"
		map.tooltip_text = "Carte des réseaux : cliquer une ville"
		map.draw.connect(_draw_map); map.gui_input.connect(_map_input); map.mouse_exited.connect(func(): _hover = ""; map.queue_redraw())
		add_child(map)
	_mark()

func pick(c: String) -> void:
	if not c in cities: return
	selected = c; _mark()
	chosen.emit(c)

## Ville suivante / précédente dans la liste filtrée (PgPréc / PgSuiv).
func step(delta: int) -> void:
	var vis: Array = Array(cities).filter(func(c): return _buttons[c].visible)
	if vis.is_empty(): return
	var i := vis.find(selected)
	pick(vis[posmod(i + delta, vis.size())] if i >= 0 else vis[0])

func _mark() -> void:
	for c in _buttons:
		_buttons[c].set_pressed_no_signal(c == selected)
	if map: map.queue_redraw()
	if _buttons.has(selected) and is_inside_tree():
		var b: Button = _buttons[selected]
		(func(): if is_instance_valid(b) and b.is_inside_tree(): (_rows.get_parent() as ScrollContainer).ensure_control_visible(b)).call_deferred()

func _ready() -> void:
	_mark()

func _filter(t: String) -> void:
	var q := _fold(t)
	for c in cities: _buttons[c].visible = q == "" or _fold(c).contains(q)
	if map: map.queue_redraw()

static func _fold(s: String) -> String:
	s = s.to_lower()
	for p in [["é", "e"], ["è", "e"], ["ê", "e"], ["ë", "e"], ["î", "i"], ["ï", "i"], ["ô", "o"], ["à", "a"], ["â", "a"], ["ç", "c"], ["-", " "], ["’", "'"]]:
		s = s.replace(p[0], p[1])
	return s

static func origin_of(c: String) -> Vector2:
	if not _origins.has(c):
		var o := Vector2(46.6, 2.4)
		for e in NetworkRegistry.entries():
			if e.city == c:   # « origin » figure en tête des fichiers réseau : lecture des premiers kilo-octets
				var f := FileAccess.open(e.path, FileAccess.READ)
				if f == null: break
				var re := RegEx.create_from_string("\"origin\"\\s*:\\s*\\[\\s*([-0-9.]+)\\s*,\\s*([-0-9.]+)")
				var m := re.search(f.get_buffer(4096).get_string_from_utf8())
				if m: o = Vector2(float(m.get_string(1)), float(m.get_string(2)))
				break
		_origins[c] = o
	return _origins[c]

func _proj(lat: float, lon: float) -> Vector2:
	# équirectangulaire corrigée (cos 46,5°), cadrée sur la métropole
	var x := (lon + 5.2) * 0.688; var y := (51.3 - lat)
	var k := minf(map.size.x / (13.6 * 0.688), map.size.y / 9.1)
	var off := (map.size - Vector2(13.6 * 0.688, 9.1) * k) * 0.5
	return off + Vector2(x, y) * k

func _city_at(p: Vector2) -> String:
	var best := ""; var bd := 26.0
	for c in cities:
		if not _buttons[c].visible: continue
		var o := origin_of(c)
		var d := _proj(o.x, o.y).distance_to(p)
		if d < bd: bd = d; best = c
	return best

func _map_input(ev: InputEvent) -> void:
	if ev is InputEventMouseMotion:
		var h := _city_at(ev.position)
		if h != _hover: _hover = h; map.tooltip_text = h if h != "" else "Carte des réseaux : cliquer une ville"; map.queue_redraw()
	elif (ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT) or (ev is InputEventScreenTouch and ev.pressed):
		var c := _city_at(ev.position)
		if c != "": pick(c); map.accept_event()

func _draw_map() -> void:
	var pts := PackedVector2Array()
	for p in FRANCE: pts.append(_proj(p[0], p[1]))
	map.draw_colored_polygon(pts, Color(1, 1, 1, 0.07))
	pts.append(pts[0]); map.draw_polyline(pts, Color(1, 1, 1, 0.28), 1.5, true)
	var font := UiTheme.font(true)
	for c in cities:
		var o := origin_of(c); var p := _proj(o.x, o.y)
		var on: bool = _buttons[c].visible
		var sel := c == selected
		map.draw_circle(p, 7.0 if sel else 4.5, UiTheme.HIGHLIGHT if sel else (UiTheme.ACCENT if on else Color(1, 1, 1, 0.25)))
		if sel or c == _hover:
			var fs := UiTheme.SIZE_CAPTION
			var w := font.get_string_size(c, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var at := Vector2(clampf(p.x - w * 0.5, 2.0, map.size.x - w - 2.0), p.y - 11.0)
			map.draw_string_outline(font, at, c, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0, 0, 0, 0.8))
			map.draw_string(font, at, c, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiTheme.TEXT)
