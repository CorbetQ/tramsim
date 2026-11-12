class_name TramSheet
extends Control
## Fiche d'une rame du catalogue : aperçu 3D tournant (livrée choisie), fiche technique sourcée (research.json :
## valeurs estimées signalées « ≈ »), sélecteur de livrée par réseau / ligne, bouton « Conduire cette rame ».

signal back
signal drive(pick: Dictionary)   # {family, path, city, line, source}

const SUPPLY := {"overhead": "ligne aérienne de contact 750 V CC", "aps": "APS (alimentation par le sol) + LAC 750 V",
	"third_rail": "troisième rail", "hybrid": "LAC + batteries / supercondensateurs", "battery": "batteries"}

var family := ""
var city := ""
var lines: Array = []            # Catalogue.lines_for(family), ville filtrée en tête
var livery_opt: OptionButton
var preview: TramPreview
var text: RichTextLabel
var drive_btn: Button

func _init(fam: String = "citadis_302", start_city: String = "") -> void:
	family = TramModel.family_id(fam)
	city = start_city
	name = "TramSheet"

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new(); bg.color = Color(0.1, 0.12, 0.15); bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var scroll := TouchScroll.new(); scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; add_child(scroll)
	var m := MarginContainer.new(); m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]: m.add_theme_constant_override("margin_" + side, 24)
	scroll.add_child(m)
	var col := VBoxContainer.new(); col.add_theme_constant_override("separation", 12); m.add_child(col)
	var top := HBoxContainer.new(); top.add_theme_constant_override("separation", 16); col.add_child(top)
	var bb := Button.new(); bb.text = "← Catalogue"; bb.custom_minimum_size = Vector2(170, 52); top.add_child(bb)
	bb.pressed.connect(func(): back.emit())
	var title := Label.new(); title.add_theme_font_size_override("font_size", 32); title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.text = str(TramModel.plan(family).get("name", family)).replace(" [AJOUT]", ""); title.clip_text = true; top.add_child(title)
	var row := BoxContainer.new(); row.vertical = UiLayout.compact(self); row.add_theme_constant_override("separation", 24); row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(row)
	var left := VBoxContainer.new(); left.add_theme_constant_override("separation", 10); row.add_child(left)
	preview = TramPreview.new(); left.add_child(preview)
	preview.custom_minimum_size = Vector2(0, 220) if UiLayout.compact(self) else Vector2(760, 470)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var lr := HBoxContainer.new(); left.add_child(lr)
	var ll := Label.new(); ll.text = "Livrée"; ll.custom_minimum_size = Vector2(90, 0); lr.add_child(ll)
	livery_opt = OptionButton.new(); livery_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	livery_opt.custom_minimum_size = Vector2(0, 52); livery_opt.clip_text = true; lr.add_child(livery_opt)
	drive_btn = Button.new(); drive_btn.text = "Conduire cette rame"; drive_btn.custom_minimum_size = Vector2(0, 72)
	drive_btn.add_theme_font_size_override("font_size", 26); left.add_child(drive_btn)
	text = RichTextLabel.new(); text.bbcode_enabled = true; text.fit_content = UiLayout.compact(self); text.scroll_active = not UiLayout.compact(self)
	text.custom_minimum_size = Vector2(0, 200)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL; text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text.add_theme_font_size_override("normal_font_size", 17); text.add_theme_font_size_override("bold_font_size", 17)
	text.add_theme_font_size_override("italics_font_size", 16)
	text.meta_clicked.connect(func(u): OS.shell_open(str(u)))
	row.add_child(text)
	# livrées : une entrée par (réseau, ligne) où la rame circule ; lignes de même réseau et même livrée regroupées
	var all := Catalogue.lines_for(family)
	var first: Array = all.filter(func(l): return city != "" and l.city == city)
	lines = first + all.filter(func(l): return not l in first)
	var seen := {}
	var shown: Array = []
	for l in lines:
		var liv := TramModel.livery_for(l.meta, l.entry)
		var key := "%s|%s|%s|%s" % [l.source, liv.base, liv.front, str(liv.get("pattern", {}).get("type", ""))]
		if seen.has(key):
			if not l.line in shown[seen[key]].lines: shown[seen[key]].lines.append(l.line)
			continue
		seen[key] = shown.size()
		shown.append({"l": l, "lines": [l.line]})
	lines = shown
	for s in shown:
		livery_opt.add_item("%s — ligne%s %s" % [s.l.city, "s" if s.lines.size() > 1 else "", ", ".join(s.lines)])
	if shown.is_empty():
		livery_opt.add_item("Livrée générique (hors flotte)"); drive_btn.disabled = true
	livery_opt.item_selected.connect(_select)
	drive_btn.pressed.connect(func():
		if lines.is_empty(): return
		var l: Dictionary = lines[maxi(livery_opt.selected, 0)].l
		drive.emit({"family": family, "path": l.path, "city": l.city, "line": l.line, "source": l.source}))
	_select(0)

func current_meta() -> Dictionary:
	if lines.is_empty(): return {"source_id": "", "id": "catalogue"}
	return lines[maxi(livery_opt.selected, 0)].l.meta

func _select(i: int) -> void:
	var meta := current_meta()
	var entry: Dictionary = lines[i].l.entry if not lines.is_empty() else {"family": family}
	var v := VehicleLibrary.for_fleet(entry, meta)
	preview.show_tram(meta, v)
	text.text = sheet_text(family, v, meta, lines[i].lines if not lines.is_empty() else [])

## Fiche technique (BBCode) : research.json, variante du réseau choisi, valeurs estimées signalées.
static func sheet_text(fam: String, v: VehicleProfile, meta: Dictionary, on_lines: Array = []) -> String:
	var r := TramModel.research(fam).duplicate(true)
	var p := TramModel.plan(fam)
	var est: Array = r.get("estimated", []).duplicate()
	# variante du réseau affiché (research.variants « <réseau>_… ») : valeurs sourcées propres au réseau
	var src := str(meta.get("source_id", ""))
	var vd: Dictionary = {}
	for k in r.get("variants", {}):
		if src != "" and (str(k) == src or str(k).begins_with(src + "_")) and r.variants[k] is Dictionary: vd = r.variants[k]
	for k in vd:
		r[k] = vd[k]; est.erase(k)
	var e := func(k: String, s: String) -> String: return ("≈ " + s + " [color=#e0b050](estimé)[/color]") if k in est else s
	var out := PackedStringArray()
	var row := func(label: String, val: String): out.append("[b]%s[/b] : %s" % [label, val])
	row.call("Constructeur", str(r.get("manufacturer", "—")) + ((" · " + str(r.generation)) if r.has("generation") else ""))
	var L := v.length_m if v else float(r.get("length_m", p.get("length_m", 0.0)))
	var Lref := float(r.get("length_m", L))
	row.call("Longueur", e.call("length_m", "%.2f m" % L) + ("" if is_equal_approx(L, Lref) else " (version du réseau ; type %.2f m)" % Lref))
	row.call("Largeur", e.call("width_m", "%.2f m" % (v.width_m if v else float(r.get("width_m", 2.4)))))
	row.call("Hauteur", e.call("height_m", "%.2f m" % float(r.get("height_m", p.get("height_m", 3.3)))))
	row.call("Plancher", e.call("floor_height_m", "%d mm au-dessus du rail (plancher bas intégral)" % roundi(float(r.get("floor_height_m", p.get("floor_m", 0.32))) * 1000.0)))
	row.call("Masse à vide", e.call("mass_t", "%.1f t" % (float(r.get("mass_t", 0.0)) if vd.has("mass_t") or not v else v.empty_mass_kg / 1000.0)))
	row.call("Puissance", e.call("power_kw", "%d kW" % roundi(float(r.get("power_kw", 0.0)) if vd.has("power_kw") or not v else v.power_kw)))
	row.call("Vitesse maximale", e.call("max_speed_kmh", "%d km/h" % roundi(v.max_speed_ms * 3.6 if v else float(r.get("max_speed_kmh", 70)))))
	row.call("Capacité", e.call("capacity", "%d voyageurs" % (int(r.get("capacity", 0)) if vd.has("capacity") or not v else v.capacity)))
	var doors := "%d par côté" % int(r.get("doors_per_side", 0))
	if r.has("door_type"): doors += " · " + str(r.door_type)
	if r.has("door_width_m"): doors += " · %.2f m" % float(r.door_width_m)
	if r.has("doors_detail"): doors += " (" + str(r.doors_detail) + ")"
	row.call("Portes", e.call("doors_per_side", doors))
	var mods: Array = p.get("modules", [])
	var kinds := {"cab": "cabine", "suspended": "suspendu", "middle": "intermédiaire"}
	var mk := PackedStringArray()
	for mo in mods: mk.append(str(kinds.get(str(mo.kind), str(mo.kind))))
	if r.get("modules") is int or r.get("modules") is float: row.call("Modules", e.call("modules", "%d caisses" % int(r.modules)))
	else: row.call("Modules", e.call("modules", "%d caisses (%s)" % [mods.size(), " · ".join(mk)]))
	var sup := str(r.get("supply", ""))
	if sup == "":
		sup = str(SUPPLY.get(str(meta.get("supply", v.supply if v else "overhead")), "ligne aérienne de contact 750 V CC"))
	if v and v.guidance == "rubber_guided": sup += " · guidage par rail central, roulement sur pneus"
	row.call("Alimentation", sup)
	var nets := PackedStringArray()
	for l in Catalogue.lines_for(fam):
		var s := "%s %s" % [l.city, l.line]
		if not s in nets: nets.append(s)
	row.call("Réseaux et lignes", ", ".join(nets) if not nets.is_empty() else "aucune ligne du jeu (matériel « Autre »)")
	if not on_lines.is_empty(): row.call("Livrée affichée", "%s — ligne(s) %s" % [str(meta.get("city", "")), ", ".join(on_lines)])
	if r.has("notes"): out.append("\n[i]%s[/i]" % str(r.notes))
	if r.has("front"): out.append("[i]Face avant : %s[/i]" % str(r.front))
	if not est.is_empty():
		out.append("\n[color=#e0b050]Valeurs estimées (≈) : %s[/color]" % ", ".join(est))
	var srcs: Array = r.get("sources", []) + p.get("sources", []).filter(func(s): return str(s).begins_with("http"))
	var uniq := PackedStringArray()
	for s in srcs:
		if not str(s) in uniq: uniq.append(str(s))
	out.append("\n[b]Sources[/b] :")
	for s in uniq: out.append("• [url=%s]%s[/url]" % [s, s.uri_decode().replace("https://", "")])
	return "\n".join(out)
