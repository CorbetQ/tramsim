class_name LiveryEditor
extends Control
signal saved(design: Dictionary)
signal cancelled
var entry: Dictionary
var design: Dictionary
var preview: TramPreview
var name_input: LineEdit
var label_input: LineEdit
var zone_choice: TouchChoice
var hex_input: LineEdit
var status: Label
var timer: Timer
var duplicate_button: Button
const ZONE_LABELS := ["Caisse", "Face avant", "Portes", "Toiture", "Jupe", "Bandeau des vitrages"]

func _init(base: Dictionary = {}, current: Dictionary = {}) -> void:
	entry = base
	design = LiveryLibrary.create(base) if current.is_empty() else current.duplicate(true)
	name = "LiveryEditor"

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var background := ColorRect.new(); background.color = UiTheme.BG; background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(background)
	var scroll := TouchScroll.new(); scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; add_child(scroll)
	var margin := MarginContainer.new(); margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_"+side,16)
	scroll.add_child(margin)
	var col := VBoxContainer.new(); col.add_theme_constant_override("separation",12); margin.add_child(col)
	var top := HFlowContainer.new(); col.add_child(top)
	_button(top,"← Annuler",func():cancelled.emit())
	_button(top,"Enregistrer",func():save_current())
	duplicate_button = _button(top,"Enregistrer une copie",func():save_current(true))
	var title := UiTheme.label_("Éditeur de livrée · " + str(entry.name),20,UiTheme.TEXT,true); title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; col.add_child(title)
	preview = TramPreview.new(); preview.custom_minimum_size = Vector2(0,210 if UiLayout.compact(self) else 340); col.add_child(preview)
	var views := HBoxContainer.new(); col.add_child(views)
	for view in [["threequarter","Vue 3/4"],["front","Face avant"],["side","Profil"]]:
		_button(views,view[1],func():preview.set_view(view[0]))
	name_input = _line(col,"Nom de la livrée",48,str(design.name))
	label_input = _line(col,"Inscription sur les flancs",24,str(design.label))
	label_input.text_changed.connect(func(value):design.label=value;_schedule())
	col.add_child(UiTheme.label_("Zone à peindre",17,UiTheme.TEXT,true))
	zone_choice = TouchChoice.new(); zone_choice.choice_title = "Zone de couleur"; zone_choice.custom_minimum_size.y = 52; col.add_child(zone_choice)
	for label in ZONE_LABELS: zone_choice.add_item(label)
	zone_choice.item_selected.connect(func(_index):hex_input.text=design.colors[LiveryLibrary.ZONES[zone_choice.selected]])
	var palette := HFlowContainer.new(); palette.add_theme_constant_override("h_separation",8); palette.add_theme_constant_override("v_separation",8); col.add_child(palette)
	for color in ["#ffffff","#181d24","#c83232","#f19832","#ebd12f","#63b23e","#13ae91","#0089ce","#283a9e","#813da5","#de64a9","#bfc5cc"]:
		var swatch := _button(palette,"",func():set_color(LiveryLibrary.ZONES[zone_choice.selected],color))
		swatch.custom_minimum_size = Vector2(44,44)
		var chip := ColorRect.new(); chip.color = Color(color); chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT,Control.PRESET_MODE_MINSIZE,6); swatch.add_child(chip)
	hex_input = _line(col,"Couleur précise · #RRGGBB",7,str(design.colors.base))
	hex_input.text_submitted.connect(func(value):set_color(LiveryLibrary.ZONES[zone_choice.selected],value))
	_button(col,"Appliquer la couleur",func():set_color(LiveryLibrary.ZONES[zone_choice.selected],hex_input.text))
	for index in 2: _band_controls(col,index)
	var note := UiTheme.label_("La face, les équipements et les dimensions restent ceux de la variante choisie. Les vitrages et les masques de face sont préservés.",14,UiTheme.MUTED)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; col.add_child(note)
	status = UiTheme.label_("",15,UiTheme.ACCENT); status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; col.add_child(status)
	timer = Timer.new(); timer.one_shot = true; timer.wait_time = 0.2; add_child(timer); timer.timeout.connect(refresh_preview)
	refresh_preview()

func _button(parent: Node, text_: String, callback: Callable) -> Button:
	var button := Button.new(); button.text = text_; button.custom_minimum_size.y = 48; button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(button); button.pressed.connect(callback); return button

func _line(parent: Node, title: String, length: int, value: String) -> LineEdit:
	parent.add_child(UiTheme.label_(title,16,UiTheme.TEXT))
	var line := LineEdit.new(); line.text = value; line.max_length = length; line.custom_minimum_size.y = 48; parent.add_child(line); return line

func _band_controls(parent: Node, index: int) -> void:
	# Older schemes may have no stripes; editor always exposes two optional bands.
	while design.bands.size() < 2: design.bands.append({"enabled":false,"y":0.65,"width":0.18,"color":"#18baa6"})
	var enabled := CheckButton.new(); enabled.text = "Bande %d" % (index+1); enabled.custom_minimum_size.y = 48; enabled.button_pressed = design.bands[index].enabled; parent.add_child(enabled)
	enabled.toggled.connect(func(on):design.bands[index].enabled=on;_schedule())
	for property in [["y","Hauteur",0.15,3.0],["width","Épaisseur",0.03,0.6]]:
		var row := HBoxContainer.new(); parent.add_child(row)
		row.add_child(UiTheme.label_(property[1]+" (m)",15,UiTheme.MUTED))
		var number := SpinBox.new(); number.min_value=property[2];number.max_value=property[3];number.step=0.01;number.value=design.bands[index][property[0]];number.size_flags_horizontal=Control.SIZE_EXPAND_FILL;number.custom_minimum_size.y=48;row.add_child(number)
		number.value_changed.connect(func(value):design.bands[index][property[0]]=value;_schedule())
	var color := _line(parent,"Couleur de la bande %d" % (index+1),7,design.bands[index].color)
	_button(parent,"Appliquer la bande %d" % (index+1),func():
		if color.text.length()==7 and Color.html_is_valid(color.text):design.bands[index].color=color.text;_schedule()
		else:status.text="Utiliser une couleur #RRGGBB.")

func set_color(zone: String, value: String) -> void:
	if not zone in LiveryLibrary.ZONES or value.length()!=7 or not value.begins_with("#") or not Color.html_is_valid(value):
		status.text = "Utiliser une couleur #RRGGBB."; return
	design.colors[zone] = value
	if zone == LiveryLibrary.ZONES[zone_choice.selected]: hex_input.text = value
	status.text = ""; _schedule()

func _schedule() -> void:
	if timer: timer.start()

func refresh_preview() -> void:
	var vehicle := VehicleLibrary.for_fleet(entry,StockCatalog.origin_meta(entry))
	vehicle.custom_livery = LiveryLibrary.clean(design)
	preview.show_tram(StockCatalog.origin_meta(entry),vehicle)

func save_current(as_copy := false) -> void:
	design.name = name_input.text; design.label = label_input.text
	var result := LiveryLibrary.save_design(design,as_copy)
	if result.is_empty(): status.text = LiveryLibrary.last_error; return
	design = result
	saved.emit(result)
