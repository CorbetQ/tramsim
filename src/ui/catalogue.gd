class_name Catalogue
extends Control
## Catalogue des rames : grille de cartes (vignette pré-rendue, nom, réseaux), filtre par ville ; une carte ouvre la
## fiche de la rame (TramSheet : aperçu 3D, fiche technique, livrée par réseau, « Conduire cette rame »).
## Données : plans data/rolling_stock/plans, flottes data/rolling_stock/liveries.json, fiches research.json,
## vignettes data/rolling_stock/thumbs/<famille>.png (tools/render_thumbs.gd).

signal drive(pick: Dictionary)   # {family, path, city, line, source}
signal closed

const THUMBS := "res://data/rolling_stock/thumbs/"
const ALL := "Toutes les villes"

var city := ""                   # filtre initial (ville du menu) ; "" = toutes
var filter: TouchChoice
var grid: GridContainer
var list_box: Control
var sheet: TramSheet
var _cities: PackedStringArray = []

static var _net_cache: Array = []

func _init(start_city: String = "") -> void:
	city = start_city
	name = "Catalogue"

## Lignes jouables : [{id, city, line, path, source, meta}] (meta allégée lue dans le fichier réseau).
static func lines_index() -> Array:
	if not _net_cache.is_empty(): return _net_cache
	var keys: Array = TramModel._liveries().keys()
	keys.sort_custom(func(a, b): return str(a).length() > str(b).length())
	for e in NetworkRegistry.entries():
		var meta := meta_of(str(e.path))
		var src := str(meta.get("source_id", ""))
		if src == "":
			for k in keys:
				if str(e.get("id", "")).begins_with(str(k) + "_"): src = str(k); break
		meta.source_id = src
		_net_cache.append({"id": str(e.get("id", meta.get("id", ""))), "city": str(e.city), "line": str(e.line),
			"long_name": str(e.get("long_name", "")), "path": str(e.path), "source": src, "meta": meta})
	return _net_cache

## En-tête d'un fichier réseau (sans nœuds / arêtes) : id, couleur, source_id, kind, guidance, supply…
static func meta_of(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null: return {}
	var d = JSON.parse_string(f.get_as_text())
	var out := {}
	if d is Dictionary:
		for k in d:
			if not (d[k] is Array or d[k] is Dictionary): out[k] = d[k]
	return out

## Lignes où circule une famille : [{city, line, path, source, meta, entry}] (flotte TramModel.fleet_for).
static func lines_for(family: String) -> Array:
	var out: Array = []
	for l in lines_index():
		for e in TramModel.fleet_for(l.meta):
			if str(e.family) == family:
				var r: Dictionary = l.duplicate(); r.entry = e; out.append(r); break
	return out

## Familles du catalogue : [{id, name, manufacturer, cities, sources}] ; les familles sans ligne jouable restent
## listées (matériel « Autre »).
static func families() -> Array:
	var out: Array = []
	for id in TramModel.plan_ids():
		var p := TramModel.plan(id)
		var r := TramModel.research(id)
		var cities := PackedStringArray(); var srcs := PackedStringArray()
		for entry in StockCatalog.entries():
			if str(entry.family)!=id:continue
			if not str(entry.city) in cities:cities.append(str(entry.city))
			if not str(entry.network) in srcs:srcs.append(str(entry.network))
		out.append({"id": id, "name": str(p.get("name", r.get("name", id))).replace(" [AJOUT]", "").strip_edges(), "manufacturer": str(r.get("manufacturer", "")),
			"cities": cities, "sources": srcs})
	return out

static func thumb(id: String) -> Texture2D:
	var path := THUMBS + id + ".png"
	if ResourceLoader.exists(path):
		var t = load(path)
		if t is Texture2D: return t
	if FileAccess.file_exists(path):
		var img := Image.load_from_file(path)
		if img: return ImageTexture.create_from_image(img)
	return null

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new(); bg.color = Color(0.1, 0.12, 0.15); bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	list_box = MarginContainer.new(); list_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]: list_box.add_theme_constant_override("margin_" + side, 24)
	add_child(list_box)
	var col := VBoxContainer.new(); col.add_theme_constant_override("separation", 14); list_box.add_child(col)
	var top := HFlowContainer.new(); top.add_theme_constant_override("separation", 16); col.add_child(top)
	var back := Button.new(); back.text = "← Menu"; back.custom_minimum_size = Vector2(140, 52); top.add_child(back)
	back.pressed.connect(func(): closed.emit(); queue_free())
	var title := Label.new(); title.text = "Familles de tramways"; title.add_theme_font_size_override("font_size", 34)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL; title.visible = not UiLayout.compact(self); top.add_child(title)
	var fl := Label.new(); fl.text = "Livrée d’origine"; top.add_child(fl)
	filter = TouchChoice.new(); filter.choice_title = "Ville"; filter.custom_minimum_size = Vector2(220 if UiLayout.compact(self) else 300, 52); top.add_child(filter)
	filter.add_item(ALL)
	_cities = PackedStringArray()
	for entry in StockCatalog.entries():
		if not str(entry.city) in _cities:_cities.append(str(entry.city))
	_cities.sort()
	for c in _cities: filter.add_item(c)
	var idx := _cities.find(city)
	filter.select(idx + 1 if idx >= 0 else 0)
	filter.item_selected.connect(func(_i): _fill())
	var scroll := TouchScroll.new(); scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; col.add_child(scroll)
	grid = GridContainer.new(); grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 16); grid.add_theme_constant_override("v_separation", 16)
	scroll.add_child(grid)
	resized.connect(_columns)
	_columns()
	_fill()

func _columns() -> void:
	if grid: grid.columns = clampi(int((size.x - 64.0) / 360.0), 1, 6)

func selected_city() -> String:
	return "" if filter == null or filter.selected <= 0 else _cities[filter.selected - 1]

## Remplit la grille selon le filtre de ville.
func _fill() -> void:
	for c in grid.get_children(): c.queue_free()
	var cf := selected_city()
	for group in StockCatalog.grouped(cf):
		grid.add_child(_card(group,cf))

func card_count() -> int:
	var n := 0
	for c in grid.get_children():
		if not c.is_queued_for_deletion(): n += 1
	return n

func _card(f: Dictionary, cf: String) -> Control:
	var b := Button.new(); b.custom_minimum_size = Vector2(minf(344,maxf(240,size.x-64)),300); b.name = "card_" + str(f.id)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.tooltip_text = str(f.name)
	var v := VBoxContainer.new(); v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 8)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE; b.add_child(v)
	var tr := TextureRect.new(); tr.texture = thumb(str(f.get("preview_family", f.id))); tr.custom_minimum_size = Vector2(0, 184)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE; v.add_child(tr)
	var nl := Label.new(); nl.text = str(f.name); nl.add_theme_font_size_override("font_size", 18)
	nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; nl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(nl)
	var cl := Label.new(); cl.add_theme_font_size_override("font_size", 14); cl.modulate = Color(1, 1, 1, 0.72)
	cl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; cl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cl.max_lines_visible = 2; cl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	cl.text = "Types " + " · ".join(PackedStringArray(f.types)) + "\n%d livrées / faces · " % (f.variants as Array).size() + ", ".join(PackedStringArray(f.cities))
	v.add_child(cl)
	b.pressed.connect(func(): open_sheet(str(f.id), cf))
	return b

## Ouvre la fiche d'une rame (livrée du premier réseau de la ville filtrée).
func open_sheet(id: String, cf: String = "",variant_id:String="") -> TramSheet:
	if sheet: sheet.queue_free()
	sheet = TramSheet.new(id, cf,variant_id)
	add_child(sheet)
	list_box.visible = false
	sheet.back.connect(func(): list_box.visible = true; sheet.queue_free(); sheet = null)
	sheet.drive.connect(func(pick): drive.emit(pick))
	return sheet
