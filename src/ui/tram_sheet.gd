class_name TramSheet
extends Control
## Family → type → original body/livery/front → personal paint.
signal back
signal drive(pick: Dictionary)
var family := ""
var group_id := ""
var city := ""
var variant_id := ""
var variants: Array = []
var all_variants: Array = []
var types: Array = []
var designs: Array = []
var destinations: Array = []
var type_opt: TouchChoice
var livery_opt: TouchChoice
var paint_opt: TouchChoice
var target_opt: TouchChoice
var preview: TramPreview
var text: RichTextLabel
var drive_btn: Button
var compatibility_note: Label
var audio_note: Label
var form: Control
var editor: LiveryEditor
var edit_button: Button
var delete_button: Button

func _init(fam: String = "citadis_302", start_city: String = "", pick_id: String = "") -> void:
 family = TramModel.family_id(fam); city = start_city; variant_id = pick_id; name = "TramSheet"
 group_id = fam if StockCatalog.GROUP_NAMES.has(fam) else StockCatalog.group_id({"family":family})
 if pick_id != "" and not StockCatalog.find(pick_id).is_empty(): group_id = StockCatalog.group_id(StockCatalog.find(pick_id))

func _choice(parent: Node, title: String) -> TouchChoice:
 parent.add_child(UiTheme.label_(title,18,UiTheme.TEXT,true))
 var choice := TouchChoice.new(); choice.choice_title = title; choice.custom_minimum_size.y = 52; parent.add_child(choice); return choice

func _ready() -> void:
 set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 var bg := ColorRect.new(); bg.color = UiTheme.BG; bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(bg)
 var scroll := TouchScroll.new(); form = scroll; scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; add_child(scroll)
 var margin := MarginContainer.new(); margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 for side in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_"+side,16)
 scroll.add_child(margin)
 var column := VBoxContainer.new(); column.add_theme_constant_override("separation",12); margin.add_child(column)
 var top := HBoxContainer.new(); column.add_child(top)
 var back_btn := Button.new(); back_btn.text="← Catalogue";back_btn.custom_minimum_size=Vector2(140,52);top.add_child(back_btn);back_btn.pressed.connect(func():back.emit())
 var title := UiTheme.label_(StockCatalog.group_name(group_id),22,UiTheme.TEXT,true);title.size_flags_horizontal=Control.SIZE_EXPAND_FILL;title.clip_text=true;top.add_child(title)
 preview=TramPreview.new();preview.custom_minimum_size=Vector2(0,220 if UiLayout.compact(self) else 380);column.add_child(preview)
 var views:=HBoxContainer.new();column.add_child(views)
 for mode in [["threequarter","Vue 3/4"],["front","Face avant"],["side","Profil"]]:
  var button:=Button.new();button.text=mode[1];button.custom_minimum_size=Vector2(0,48);button.size_flags_horizontal=Control.SIZE_EXPAND_FILL;views.add_child(button)
  button.pressed.connect(func():preview.set_view(mode[0]))
 type_opt=_choice(column,"Type de rame")
 livery_opt=_choice(column,"Livrée et face avant d’origine")
 paint_opt=_choice(column,"Peinture")
 var tools:=HFlowContainer.new();column.add_child(tools)
 edit_button=Button.new();edit_button.text="Créer une livrée";edit_button.custom_minimum_size.y=52;tools.add_child(edit_button);edit_button.pressed.connect(open_editor)
 delete_button=Button.new();delete_button.text="Supprimer cette livrée";delete_button.custom_minimum_size.y=52;tools.add_child(delete_button);delete_button.pressed.connect(_delete_design)
 target_opt=_choice(column,"Réseau de conduite · mode libre")
 compatibility_note=UiTheme.label_("",15,UiTheme.MUTED);compatibility_note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;column.add_child(compatibility_note)
 drive_btn=Button.new();drive_btn.text="Conduire en mode libre";drive_btn.custom_minimum_size.y=64;column.add_child(drive_btn)
 text=RichTextLabel.new();text.bbcode_enabled=true;text.fit_content=true;text.scroll_active=false;text.custom_minimum_size.y=200;column.add_child(text)
 text.meta_clicked.connect(func(url):OS.shell_open(str(url)))
 audio_note=UiTheme.label_("",15,UiTheme.MUTED);audio_note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;column.add_child(audio_note)
 all_variants=StockCatalog.group_variants(group_id)
 var desired:Dictionary={}
 for entry in all_variants:
  var type_:String=StockCatalog.type_name(entry)
  if not type_ in types:types.append(type_)
  if desired.is_empty():desired=entry
  if str(entry.city)==city and str(entry.family)==family and not entry.fictional:desired=entry
  elif str(entry.city)==city and str(desired.city)!=city and not entry.fictional:desired=entry
 if variant_id!="":
  for entry in all_variants:
   if str(entry.id)==variant_id:desired=entry
 types.sort_custom(func(a,b):return str(a).naturalnocasecmp_to(str(b))<0)
 for type_ in types:type_opt.add_item(str(type_))
 type_opt.item_selected.connect(_type_selected);livery_opt.item_selected.connect(_select);target_opt.item_selected.connect(_target_changed)
 paint_opt.item_selected.connect(func(_i):_refresh_preview();_paint_buttons())
 drive_btn.pressed.connect(func():
  if variants.is_empty() or destinations.is_empty():return
  var entry:Dictionary=variants[maxi(livery_opt.selected,0)];var target:Dictionary=destinations[maxi(target_opt.selected,0)]
  drive.emit({"family":family,"variant_id":entry.id,"custom_livery":current_design(),"path":target.path,"city":target.city,"source":target.source_id,"line":"Réseau","free":true}))
 if desired.is_empty():drive_btn.disabled=true;return
 variant_id=str(desired.id)
 var selected:int=types.find(StockCatalog.type_name(desired));type_opt.select(selected);_type_selected(selected)

func _type_selected(index:int)->void:
 if index<0 or index>=types.size():return
 variants=all_variants.filter(func(entry):return StockCatalog.type_name(entry)==types[index])
 livery_opt.clear()
 var selected:=0
 for i in variants.size():
  var entry:Dictionary=variants[i]
  livery_opt.add_item(str(entry.city)+" · "+str(entry.name).replace("Alstom Citadis ","")+(" · FICTIF" if entry.fictional else ""))
  if str(entry.id)==variant_id:selected=i
 livery_opt.select(selected);_select(selected)

func current_meta()->Dictionary:
 return StockCatalog.origin_meta(variants[maxi(livery_opt.selected,0)]) if not variants.is_empty() else {}

func current_design()->Dictionary:
 return designs[paint_opt.selected-1].duplicate(true) if paint_opt.selected>0 and paint_opt.selected<=designs.size() else {}

func _refresh_paints(selected_id:String="")->void:
 designs=LiveryLibrary.designs(str(variants[livery_opt.selected].id));paint_opt.clear();paint_opt.add_item("Livrée d’origine")
 var selected:=0
 for i in designs.size():
  paint_opt.add_item(str(designs[i].name)+" · Personnalisée")
  if str(designs[i].id)==selected_id:selected=i+1
 paint_opt.select(selected);_paint_buttons()

func _paint_buttons()->void:
 edit_button.text="Modifier la livrée" if paint_opt.selected>0 else "Créer une livrée"
 delete_button.visible=paint_opt.selected>0;delete_button.text="Supprimer cette livrée"

func _refresh_preview()->void:
 if variants.is_empty():return
 var entry:Dictionary=variants[livery_opt.selected];var meta:=StockCatalog.origin_meta(entry)
 var vehicle:=VehicleLibrary.for_fleet(entry,meta);vehicle.custom_livery=current_design()
 preview.show_tram(meta,vehicle)
 text.text=sheet_text(family,vehicle,meta,entry.get("lines",[]))
 audio_note.text=TramAudio.profile_label(family,str(entry.id))

func _select(index:int)->void:
 if variants.is_empty():drive_btn.disabled=true;return
 livery_opt.select(index)
 var entry:Dictionary=variants[index];family=str(entry.family);variant_id=str(entry.id)
 _refresh_paints();_refresh_preview()
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
 var explanation:="%d réseaux compatibles · caractéristiques de la variante conservées."%destinations.size()
 if int(entry.gauge_mm)!=int(target.gauge_mm):explanation+=" Écartement adapté en mode libre."
 if entry.fictional:explanation="CONCEPT FICTIF · "+explanation
 compatibility_note.text=explanation

func open_editor()->void:
 if editor or variants.is_empty():return
 form.hide()
 editor=LiveryEditor.new(variants[livery_opt.selected],current_design());add_child(editor)
 editor.cancelled.connect(func():editor.queue_free();editor=null;form.show())
 editor.saved.connect(func(design):
  editor.queue_free();editor=null;form.show();_refresh_paints(str(design.id));_refresh_preview())

func _delete_design()->void:
 var design:=current_design()
 if design.is_empty():return
 if delete_button.text!="Confirmer la suppression":delete_button.text="Confirmer la suppression";return
 if LiveryLibrary.remove(str(design.id)):_refresh_paints();_refresh_preview()
 else:compatibility_note.text=LiveryLibrary.last_error

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
