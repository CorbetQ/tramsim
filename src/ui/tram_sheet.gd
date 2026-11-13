class_name TramSheet
extends Control
## Fiche d'une rame du catalogue : aperçu 3D tournant (livrée choisie), fiche technique sourcée (research.json :
## valeurs estimées signalées « ≈ »), sélecteur de livrée par réseau / ligne, bouton « Conduire cette rame ».

signal back
signal drive(pick: Dictionary)   # {family, path, city, line, source}

var family:=""
var city:=""
var variant_id:=""
var lines:Array=[]
var variants:Array=[]
var destinations:Array=[]
var livery_opt:TouchChoice
var target_opt:TouchChoice
var preview:TramPreview
var text:RichTextLabel
var drive_btn:Button
var compatibility_note:Label
var audio_note:Label

func _init(fam:String="citadis_302",start_city:String="",pick_id:String="")->void:
	family=TramModel.family_id(fam);city=start_city;variant_id=pick_id;name="TramSheet"
func _ready()->void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg:=ColorRect.new();bg.color=Color(.07,.09,.12);bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(bg)
	var scroll:=TouchScroll.new();scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;add_child(scroll)
	var margin:=MarginContainer.new();margin.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	for side in ["left","right","top","bottom"]:margin.add_theme_constant_override("margin_"+side,16)
	scroll.add_child(margin)
	var column:=VBoxContainer.new();column.add_theme_constant_override("separation",14);margin.add_child(column)
	var top:=HBoxContainer.new();column.add_child(top)
	var back_btn:=Button.new();back_btn.text="← Catalogue";back_btn.custom_minimum_size=Vector2(150,52);top.add_child(back_btn);back_btn.pressed.connect(func():back.emit())
	var title:=UiTheme.label_("Choisir une rame",24,UiTheme.TEXT,true);title.size_flags_horizontal=Control.SIZE_EXPAND_FILL;title.clip_text=true;top.add_child(title)
	preview=TramPreview.new();preview.custom_minimum_size=Vector2(0,230 if UiLayout.compact(self) else 410);column.add_child(preview)
	var views:=HBoxContainer.new();column.add_child(views)
	for mode in [["threequarter","Vue 3/4"],["front","Face avant"],["side","Profil"]]:
		var button:=Button.new();button.text=mode[1];button.custom_minimum_size=Vector2(0,48);button.size_flags_horizontal=Control.SIZE_EXPAND_FILL;views.add_child(button)
		button.pressed.connect(func():preview.set_view(mode[0]))
	column.add_child(UiTheme.label_("Rame et livrée d’origine",18,UiTheme.TEXT,true))
	livery_opt=TouchChoice.new();livery_opt.choice_title="Rame et livrée";livery_opt.custom_minimum_size.y=54;column.add_child(livery_opt)
	for entry in StockCatalog.entries():
		if str(entry.family)==family:variants.append(entry)
	var selected:=0
	for i in variants.size():
		var entry:Dictionary=variants[i];livery_opt.add_item(str(entry.name)+" · "+str(entry.city)+(" · FICTIF" if entry.fictional else ""))
		if str(entry.id)==variant_id or (variant_id=="" and str(entry.city)==city):selected=i
	livery_opt.select(selected)
	column.add_child(UiTheme.label_("Réseau de conduite · mode libre",18,UiTheme.TEXT,true))
	target_opt=TouchChoice.new();target_opt.choice_title="Réseau compatible";target_opt.custom_minimum_size.y=54;column.add_child(target_opt)
	compatibility_note=UiTheme.label_("",15,UiTheme.MUTED);compatibility_note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;column.add_child(compatibility_note)
	drive_btn=Button.new();drive_btn.text="Conduire en mode libre";drive_btn.custom_minimum_size.y=64;column.add_child(drive_btn)
	text=RichTextLabel.new();text.bbcode_enabled=true;text.fit_content=true;text.scroll_active=false;text.custom_minimum_size.y=200;column.add_child(text)
	text.meta_clicked.connect(func(url):OS.shell_open(str(url)))
	audio_note=UiTheme.label_("",15,UiTheme.MUTED);audio_note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;column.add_child(audio_note)
	livery_opt.item_selected.connect(_select);target_opt.item_selected.connect(_target_changed)
	drive_btn.pressed.connect(func():
		if variants.is_empty() or destinations.is_empty():return
		var entry:Dictionary=variants[maxi(livery_opt.selected,0)];var target:Dictionary=destinations[maxi(target_opt.selected,0)]
		drive.emit({"family":family,"variant_id":entry.id,"path":target.path,"city":target.city,"source":target.source_id,"line":"Réseau","free":true}))
	_select(selected)
func current_meta()->Dictionary:
	return StockCatalog.origin_meta(variants[maxi(livery_opt.selected,0)]) if not variants.is_empty() else {}
func _select(index:int)->void:
	if variants.is_empty():drive_btn.disabled=true;return
	var entry:Dictionary=variants[index];var meta:=StockCatalog.origin_meta(entry);var vehicle:=VehicleLibrary.for_fleet(entry,meta)
	preview.show_tram(meta,vehicle);text.text=sheet_text(family,vehicle,meta,entry.get("lines",[]));audio_note.text=TramAudio.profile_label(family,str(entry.id))
	var previous:=""
	if target_opt.selected>=0 and target_opt.selected<destinations.size():previous=str(destinations[target_opt.selected].city)
	destinations.clear();target_opt.clear()
	for target in StockCatalog.targets():
		if StockCatalog.issues(entry,target.supplies,str(target.guidance)).is_empty():destinations.append(target);target_opt.add_item(str(target.city))
	var chosen:=0
	for i in destinations.size():
		if str(destinations[i].city)==(previous if previous!="" else city):chosen=i
	target_opt.select(chosen);drive_btn.disabled=destinations.is_empty();_target_changed(chosen)
func _target_changed(index:int)->void:
	if destinations.is_empty():compatibility_note.text="Aucun réseau compatible : vérifier APS et guidage.";return
	var entry:Dictionary=variants[maxi(livery_opt.selected,0)];var target:Dictionary=destinations[index]
	var explanation:="Livrée d’origine conservée · %d réseaux compatibles."%destinations.size()
	if int(entry.gauge_mm)!=int(target.gauge_mm):explanation+=" Écartement adapté pour ce scénario libre."
	if entry.fictional:explanation="CONCEPT FICTIF · "+explanation
	compatibility_note.text=explanation

## Fiche technique (BBCode) : research.json, variante du réseau choisi, valeurs estimées signalées.
static func sheet_text(fam:String,v:VehicleProfile,meta:Dictionary,on_lines:Array=[])->String:
	var entry:Dictionary=v.fleet if v else StockCatalog.resolve({"family":fam},meta)
	var lines:=PackedStringArray()
	if entry.get("fictional",false):lines.append("[color=#f0b3ff][b]CONCEPT FICTIF — création du simulateur, aucune commande réelle.[/b][/color]")
	lines.append("[b]%s[/b] · %s"%[entry.get("name",fam),entry.get("city","")])
	lines.append("[b]Dimensions[/b] : %.2f m × %.2f m · %d caisses"%[v.length_m,v.width_m,int(entry.get("module_count",5))])
	lines.append("[b]Conduite[/b] : "+("unidirectionnelle · portes à droite" if bool(entry.get("geometry",{}).get("unidirectional",false)) else "bidirectionnelle"))
	lines.append("[b]Roulement[/b] : %s · écartement d’origine %d mm"%["pneus et guidage central" if v.guidance=="rubber_guided" else "rails",v.gauge_mm])
	var names:Dictionary={"overhead":"LAC","aps":"APS","battery":"autonomie embarquée / SRS"};var powers:=PackedStringArray()
	for mode in v.power_modes():powers.append(names.get(mode,mode))
	lines.append("[b]Alimentation à bord[/b] : "+" + ".join(powers))
	var estimated:Array=entry.get("estimated",[])
	for item in [["Masse à vide","mass_t","%.1f t"%(v.empty_mass_kg/1000)],["Puissance","power_kw","%d kW"%v.power_kw],["Capacité","capacity","%d voyageurs"%v.capacity]]:
		lines.append("[b]%s[/b] : %s%s"%[item[0],item[2]," [color=#e0b050](estimé pour la simulation)[/color]" if item[1] in estimated else ""])
	lines.append("[color=#e0b050]Formes fines, implantation des équipements, effort de traction et freinage : estimations de modélisation. Les photographies ne constituent pas des plans industriels.[/color]")
	lines.append("\n[b]Sources techniques et photographiques[/b]")
	for url in entry.get("sources",[]):lines.append("• [url=%s]%s[/url]"%[url,str(url).uri_decode()])
	for ref in entry.get("references",[]):
		lines.append("• [url=%s]%s[/url] — %s · %s"%[ref.get("url",""),ref.get("title","Photo"),ref.get("author",""),ref.get("license","")])
	return "\n".join(lines)
