class_name TouchChoice
extends Button
## Sélecteur dans le même viewport : le menu natif OptionButton/PopupMenu
## ouvre une fenêtre séparée et perd la capture tactile du formulaire.
signal item_selected(index: int)
var items: Array[Dictionary] = []
var selected := -1:
	set(value):
		selected = clampi(value, -1, items.size() - 1)
		_refresh_text()
var item_count: int:
	get: return items.size()
var fit_to_longest_item := false
var choice_title := "Choisir"
var popup: Control
var list: TouchScroll
var _layer: CanvasLayer
var _rows: VBoxContainer
static var _back_saved := true
static var _back_armed := false
var _search: LineEdit

func _init() -> void:
	action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE
	clip_text = true
	alignment = HORIZONTAL_ALIGNMENT_LEFT
	pressed.connect(open_picker)

func add_item(label: String, id: int = -1) -> void:
	items.append({"text":label, "id":id if id >= 0 else items.size(), "icon":null})
	if selected < 0: select(0)

func add_icon_item(texture: Texture2D, label: String, id: int = -1) -> void:
	add_item(label, id); items[-1].icon = texture
	_refresh_text()

func clear() -> void:
	close_picker(); items.clear(); selected = -1

func select(index: int) -> void:
	selected = index # comme OptionButton.select : pas de signal de changement.

func get_item_text(index: int) -> String:
	return str(items[index].text) if index >= 0 and index < items.size() else ""

func _refresh_text() -> void:
	text = get_item_text(selected) + "  ▾" if selected >= 0 else "—  ▾"
	icon = items[selected].icon if selected >= 0 else null

func open_picker() -> void:
	if disabled or items.is_empty() or is_instance_valid(popup): return
	if not _back_armed:
		_back_saved = get_tree().quit_on_go_back; _back_armed = true
	get_tree().quit_on_go_back = false
	_layer = CanvasLayer.new(); _layer.layer = 100; add_child(_layer)
	popup = Control.new(); popup.name = "choice_popup"
	popup.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	popup.add_to_group("touch_choice_modal"); _layer.add_child(popup)
	var shade := ColorRect.new(); shade.color = Color(0.01,0.02,0.03,0.7)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); popup.add_child(shade)
	shade.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT: close_picker())
	var panel := UiTheme.panel(UiTheme.SURFACE, 16, 12); panel.name = "choice_panel"
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var viewport_size := get_viewport_rect().size
	var width := minf(620.0, viewport_size.x - 24.0)
	panel.offset_left = (viewport_size.x - width) * 0.5
	panel.offset_right = -panel.offset_left
	panel.offset_top = 12.0; panel.offset_bottom = -12.0
	popup.add_child(panel)
	var column := VBoxContainer.new(); column.add_theme_constant_override("separation",8); panel.add_child(column)
	var header := HBoxContainer.new(); column.add_child(header)
	var heading := UiTheme.label_(choice_title, UiTheme.SIZE_H2, UiTheme.TEXT, true)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL; heading.clip_text = true; header.add_child(heading)
	var close := Button.new(); close.text = "Fermer"; close.custom_minimum_size = Vector2(90,48)
	close.pressed.connect(close_picker); header.add_child(close)
	_search = LineEdit.new(); _search.placeholder_text = "Rechercher…"; _search.custom_minimum_size.y = 46
	_search.clear_button_enabled = true; _search.virtual_keyboard_enabled = true; column.add_child(_search)
	_search.text_changed.connect(_filter_rows)
	_search.text_submitted.connect(func(_text): _search.release_focus(); DisplayServer.virtual_keyboard_hide())
	list = TouchScroll.new(); list.name = "choice_list"
	list.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL; column.add_child(list)
	_rows = VBoxContainer.new(); _rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation",4); list.add_child(_rows)
	for i in items.size():
		var button := Button.new(); button.text = str(items[i].text); button.icon = items[i].icon
		button.name = "choice_%d" % i; button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.clip_text = true; button.custom_minimum_size.y = 54
		button.action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE
		button.toggle_mode = true; button.button_pressed = i == selected
		button.pressed.connect(_choose.bind(i)); _rows.add_child(button)
	# Ne pas donner le focus au champ de recherche (pas de clavier forcé).
	_scroll_to_selection.call_deferred()

func _scroll_to_selection() -> void:
	if is_instance_valid(list) and selected >= 0:
		list.scroll_vertical = maxi(0, selected * 58 - roundi(list.size.y * 0.35))
		_rows.get_child(selected).grab_focus()

func _filter_rows(query: String) -> void:
	for i in _rows.get_child_count():
		_rows.get_child(i).visible = str(items[i].text).to_lower().contains(query.to_lower())
	list.scroll_vertical = 0

func _choose(index: int) -> void:
	var changed := selected != index
	select(index); close_picker()
	if changed: item_selected.emit(index)

func close_picker() -> void:
	if not is_instance_valid(popup): return
	if is_instance_valid(popup): popup.remove_from_group("touch_choice_modal"); popup.hide()
	if is_instance_valid(_layer): _layer.queue_free()
	TouchChoice._restore_back.call_deferred(get_tree())
	popup = null; list = null; _layer = null
	if is_inside_tree(): grab_focus()

func _input(event: InputEvent) -> void:
	if not is_instance_valid(popup): return
	if (event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE) or event.is_action_pressed("ui_cancel"):
		close_picker(); get_viewport().set_input_as_handled()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and is_instance_valid(popup): close_picker()

func _exit_tree() -> void:
	if is_instance_valid(popup): TouchChoice._restore_back.call_deferred(get_tree())

static func _restore_back(tree: SceneTree) -> void:
	# Une fermeture puis réouverture dans la même image ne doit pas réactiver
	# la sortie Android alors qu'un nouveau sélecteur est déjà ouvert.
	if tree.get_nodes_in_group("touch_choice_modal").is_empty() and _back_armed:
		tree.quit_on_go_back = _back_saved; _back_armed = false
