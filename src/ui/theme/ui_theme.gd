class_name UiTheme
extends RefCounted
## Thème de l'interface : palette, police Atkinson Hyperlegible (OFL), panneaux translucides arrondis,
## icônes vectorielles (data/ui/icons/*.svg), hiérarchie typographique et petites animations.

const FONT_REG := "res://data/ui/fonts/AtkinsonHyperlegible-Regular.ttf"
const FONT_BOLD := "res://data/ui/fonts/AtkinsonHyperlegible-Bold.ttf"
const ICONS := "res://data/ui/icons/"

# palette (sombre, lisible en plein soleil comme de nuit)
const BG := Color("#0d1117")
const SURFACE := Color(0.086, 0.106, 0.133, 0.84)
const SURFACE_2 := Color(0.13, 0.16, 0.2, 0.92)
const SURFACE_3 := Color(0.19, 0.23, 0.28, 0.96)
const BORDER := Color(1, 1, 1, 0.09)
const TEXT := Color("#eef2f6")
const MUTED := Color("#9aa6b4")
const ACCENT := Color("#2dd4bf")      # actions principales, état actif
const ACCENT_DARK := Color("#0f766e")
const HIGHLIGHT := Color("#fbbf24")   # itinéraire, sélection
const INFO := Color("#60a5fa")
const SUCCESS := Color("#34d399")
const WARNING := Color("#f59e0b")
const DANGER := Color("#ef4444")
const TRACTION := Color("#34d399")
const BRAKE := Color("#fb923c")

# typographie
const SIZE_DISPLAY := 46
const SIZE_H1 := 32
const SIZE_H2 := 24
const SIZE_BODY := 20
const SIZE_SMALL := 16
const SIZE_CAPTION := 14

const TOUCH := 48.0   # cible tactile minimale (px de référence 1280×720)

static var _regular: Font
static var _bold: Font
static var _icons: Dictionary = {}

static func font(bold: bool = false) -> Font:
	if _regular == null:
		_regular = _load_font(FONT_REG)
		_bold = _load_font(FONT_BOLD)
	return _bold if bold else _regular

static func _load_font(path: String) -> Font:
	var f: FontFile = null
	if ResourceLoader.exists(path):
		f = load(path) as FontFile
	if f == null and FileAccess.file_exists(path):
		f = FontFile.new(); f.load_dynamic_font(path)
	if f == null: return ThemeDB.fallback_font
	f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	f.hinting = TextServer.HINTING_LIGHT
	f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_AUTO
	f.fallbacks = [ThemeDB.fallback_font]   # flèches, symboles absents de la police
	return f

static func icon(name: String) -> Texture2D:
	if _icons.has(name): return _icons[name]
	var t: Texture2D = null
	var p := ICONS + name + ".svg"
	if ResourceLoader.exists(p): t = load(p)
	_icons[name] = t
	return t

static func box(bg: Color, radius: int = 14, pad: float = 14.0, border: Color = Color.TRANSPARENT, bw: int = 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new(); s.bg_color = bg
	s.set_corner_radius_all(radius); s.corner_detail = 6; s.anti_aliasing = true
	s.content_margin_left = pad; s.content_margin_right = pad
	s.content_margin_top = pad * 0.6; s.content_margin_bottom = pad * 0.6
	if bw > 0: s.border_color = border; s.set_border_width_all(bw)
	return s

static func build() -> Theme:
	var t := Theme.new()
	t.default_font = font()
	t.default_font_size = SIZE_BODY
	for k in ["Label", "Button", "OptionButton", "CheckBox", "CheckButton", "LineEdit", "PopupMenu", "TooltipLabel", "RichTextLabel", "ItemList"]:
		t.set_color("font_color", k, TEXT)
	t.set_font("bold_font", "RichTextLabel", font(true))
	t.set_color("default_color", "RichTextLabel", TEXT)
	t.set_color("font_disabled_color", "Button", Color(MUTED, 0.6))
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", Color("#06231f"))
	t.set_color("font_hover_pressed_color", "Button", Color("#06231f"))
	t.set_color("font_focus_color", "Button", TEXT)
	t.set_color("icon_pressed_color", "Button", Color("#06231f"))
	t.set_color("icon_hover_pressed_color", "Button", Color("#06231f"))
	t.set_constant("h_separation", "Button", 10)
	t.set_constant("icon_max_width", "Button", 28)
	var n := box(SURFACE_2, 12, 16, BORDER, 1)
	var h := box(SURFACE_3, 12, 16, Color(ACCENT, 0.45), 1)
	var p := box(ACCENT, 12, 16)
	var d := box(Color(SURFACE_2, 0.5), 12, 16)
	var f := box(Color(0, 0, 0, 0), 12, 16, Color(ACCENT, 0.9), 2); f.draw_center = false
	for k in ["Button", "OptionButton", "CheckBox"]:
		t.set_stylebox("normal", k, n); t.set_stylebox("hover", k, h); t.set_stylebox("pressed", k, p)
		t.set_stylebox("hover_pressed", k, p); t.set_stylebox("disabled", k, d); t.set_stylebox("focus", k, f)
	# CheckBox : fond discret, la coche porte l'état
	var cb := box(Color(0, 0, 0, 0), 12, 10)
	for st in ["normal", "pressed", "hover_pressed"]: t.set_stylebox(st, "CheckBox", cb)
	t.set_stylebox("hover", "CheckBox", box(Color(1, 1, 1, 0.05), 12, 10))
	t.set_color("font_pressed_color", "CheckBox", TEXT); t.set_color("font_hover_pressed_color", "CheckBox", TEXT)
	t.set_color("font_pressed_color", "OptionButton", Color("#06231f"))
	t.set_stylebox("panel", "PanelContainer", box(SURFACE, 18, 18, BORDER, 1))
	t.set_stylebox("panel", "PopupMenu", box(Color(0.1, 0.12, 0.15, 0.98), 12, 10, BORDER, 1))
	t.set_stylebox("hover", "PopupMenu", box(Color(ACCENT, 0.25), 8, 8))
	t.set_constant("v_separation", "PopupMenu", 14)
	t.set_font_size("font_size", "PopupMenu", SIZE_BODY)
	t.set_stylebox("panel", "TooltipPanel", box(Color(0.06, 0.07, 0.09, 0.96), 8, 10, BORDER, 1))
	t.set_font_size("font_size", "TooltipLabel", SIZE_SMALL)
	t.set_stylebox("normal", "LineEdit", box(Color(0, 0, 0, 0.35), 12, 14, BORDER, 1))
	t.set_stylebox("focus", "LineEdit", box(Color(0, 0, 0, 0.0), 12, 14, Color(ACCENT, 0.9), 2))
	t.set_color("font_placeholder_color", "LineEdit", Color(MUTED, 0.8))
	t.set_color("caret_color", "LineEdit", ACCENT)
	# défilement fin et arrondi
	for k in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", k, box(Color(1, 1, 1, 0.04), 6, 3))
		t.set_stylebox("grabber", k, box(Color(1, 1, 1, 0.22), 6, 3))
		t.set_stylebox("grabber_highlight", k, box(Color(ACCENT, 0.6), 6, 3))
		t.set_stylebox("grabber_pressed", k, box(ACCENT, 6, 3))
	t.set_stylebox("panel", "ScrollContainer", StyleBoxEmpty.new())
	t.set_color("font_color", "Label", TEXT)
	return t

## Variantes de boutons (style local).
static func style_button(b: Button, kind: String = "normal") -> void:
	match kind:
		"primary":
			b.add_theme_stylebox_override("normal", box(ACCENT, 14, 18))
			b.add_theme_stylebox_override("hover", box(ACCENT.lightened(0.15), 14, 18))
			b.add_theme_stylebox_override("pressed", box(ACCENT_DARK, 14, 18))
			b.add_theme_stylebox_override("disabled", box(Color(SURFACE_3, 0.7), 14, 18))
			for c in ["font_color", "font_hover_color", "font_focus_color", "icon_normal_color", "icon_hover_color", "icon_focus_color"]:
				b.add_theme_color_override(c, Color("#04201c"))
			b.add_theme_color_override("font_pressed_color", Color.WHITE)
			b.add_theme_font_override("font", font(true))
		"danger":
			b.add_theme_stylebox_override("normal", box(Color(DANGER, 0.92), 16, 18, Color(1, 1, 1, 0.25), 2))
			b.add_theme_stylebox_override("hover", box(DANGER.lightened(0.12), 16, 18, Color(1, 1, 1, 0.5), 2))
			b.add_theme_stylebox_override("pressed", box(DANGER.darkened(0.3), 16, 18))
			for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
				b.add_theme_color_override(c, Color.WHITE)
			b.add_theme_font_override("font", font(true))
		"ghost":
			b.add_theme_stylebox_override("normal", box(Color(1, 1, 1, 0.0), 12, 12))
			b.add_theme_stylebox_override("hover", box(Color(1, 1, 1, 0.08), 12, 12))
			b.add_theme_stylebox_override("pressed", box(Color(ACCENT, 0.3), 12, 12))
			b.add_theme_color_override("font_pressed_color", TEXT)
		"chip":
			b.add_theme_stylebox_override("normal", box(Color(1, 1, 1, 0.06), 22, 14, BORDER, 1))
			b.add_theme_stylebox_override("hover", box(Color(1, 1, 1, 0.12), 22, 14, Color(ACCENT, 0.5), 1))
			b.add_theme_stylebox_override("pressed", box(ACCENT, 22, 14))
			b.add_theme_stylebox_override("hover_pressed", box(ACCENT.lightened(0.1), 22, 14))

static func button(text: String, icon_name: String = "", kind: String = "normal", min_size: Vector2 = Vector2(0, TOUCH)) -> Button:
	var b := Button.new(); b.text = text
	if icon_name != "": b.icon = icon(icon_name)
	b.custom_minimum_size = min_size
	b.focus_mode = Control.FOCUS_NONE if OS.has_feature("mobile") else Control.FOCUS_ALL
	if kind != "normal": style_button(b, kind)
	hover_fx(b)
	return b

## Bouton d'outil carré : icône au-dessus d'un libellé court et de sa touche.
static func tool_button(label: String, icon_name: String, key: String = "", w: float = 84.0) -> Button:
	var b := Button.new(); b.custom_minimum_size = Vector2(w, 76); b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = label + ((" (" + key + ")") if key != "" else "")
	b.text = ""; b.name = "tool_" + label
	b.set_meta("label", label)
	var v := VBoxContainer.new(); v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.alignment = BoxContainer.ALIGNMENT_CENTER; v.add_theme_constant_override("separation", 2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE; b.add_child(v)
	var ic := TextureRect.new(); ic.texture = icon(icon_name); ic.custom_minimum_size = Vector2(30, 30)
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE; ic.name = "icon"; v.add_child(ic)
	var l := label_(label, SIZE_CAPTION, TEXT); l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE; l.clip_text = true; l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS; v.add_child(l)
	if key != "":
		var kb := key_badge(key); kb.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT); kb.position = Vector2(w - 24, 4)
		kb.mouse_filter = Control.MOUSE_FILTER_IGNORE; b.add_child(kb)
	hover_fx(b)
	return b

static func key_badge(key: String) -> Label:
	var k := Label.new(); k.text = key
	k.add_theme_font_size_override("font_size", 11); k.add_theme_color_override("font_color", MUTED)
	k.add_theme_stylebox_override("normal", box(Color(1, 1, 1, 0.07), 4, 4))
	return k

## Touche de clavier dessinée (aide F1).
static func keycap(key: String) -> Label:
	var k := Label.new(); k.text = key; k.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	k.add_theme_font_override("font", font(true)); k.add_theme_font_size_override("font_size", SIZE_SMALL)
	var s := box(Color(1, 1, 1, 0.08), 6, 10, Color(1, 1, 1, 0.25), 1); s.border_width_bottom = 3
	k.add_theme_stylebox_override("normal", s); k.custom_minimum_size = Vector2(36, 0)
	return k

static func label_(text: String, size: int = SIZE_BODY, color: Color = TEXT, bold: bool = false) -> Label:
	var l := Label.new(); l.text = text
	l.add_theme_font_size_override("font_size", size); l.add_theme_color_override("font_color", color)
	if bold: l.add_theme_font_override("font", font(true))
	return l

static func panel(bg: Color = SURFACE, radius: int = 18, pad: float = 18.0) -> PanelContainer:
	var p := PanelContainer.new(); p.add_theme_stylebox_override("panel", box(bg, radius, pad, BORDER, 1))
	return p

## Pastille de ligne (« A », « T2 ») à la couleur GTFS.
static func line_badge(text: String, col: Color, size: int = SIZE_BODY) -> Label:
	var l := Label.new(); l.text = text; l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_override("font", font(true)); l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color.WHITE if col.get_luminance() < 0.6 else Color.BLACK)
	l.add_theme_stylebox_override("normal", box(col, 8, 8))
	l.custom_minimum_size = Vector2(size * 1.8, 0)
	return l

static func icon_rect(name: String, sz: float = 24.0, tint: Color = Color.WHITE) -> TextureRect:
	var ic := TextureRect.new(); ic.texture = icon(name); ic.custom_minimum_size = Vector2(sz, sz)
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ic.modulate = tint; ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return ic

static func color_of(s, fallback: Color = INFO) -> Color:
	var t := str(s).strip_edges()
	if t == "" or t == "<null>": return fallback
	if not t.begins_with("#"): t = "#" + t
	return Color.from_string(t, fallback)

# ---------------------------------------------------------------------------- animations légères

static func fade_in(c: CanvasItem, dur: float = 0.18, from_y: float = 0.0) -> void:
	if c == null or not c.is_inside_tree(): return
	c.modulate.a = 0.0
	var tw := c.create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(c, "modulate:a", 1.0, dur)
	if from_y != 0.0 and c is Control and not (c.get_parent() is Container):
		var y: float = c.position.y
		c.position.y = y + from_y
		tw.parallel().tween_property(c, "position:y", y, dur)

static func fade_out_free(c: CanvasItem, dur: float = 0.2) -> void:
	if c == null or not c.is_inside_tree(): return
	var tw := c.create_tween()
	tw.tween_property(c, "modulate:a", 0.0, dur)
	tw.tween_callback(c.queue_free)

## Survol : léger éclaircissement animé (complète le style « hover »).
static func hover_fx(c: Control) -> void:
	c.mouse_entered.connect(func():
		var tw := c.create_tween(); tw.tween_property(c, "self_modulate", Color(1.08, 1.08, 1.08), 0.12))
	c.mouse_exited.connect(func():
		var tw := c.create_tween(); tw.tween_property(c, "self_modulate", Color.WHITE, 0.15))
