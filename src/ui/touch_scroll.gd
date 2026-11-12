class_name TouchScroll
extends ScrollContainer
## Défilement natif Godot : inertie, capture du doigt et annulation des boutons
## dès le début d'un glissement. Ne pas ajouter un second défilement par souris émulée.
func _init() -> void:
	scroll_deadzone = 12
	follow_focus = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true

func _ready() -> void:
	_watch(self)

func _watch(node: Node) -> void:
	# STOP empêche le ScrollContainer de recevoir le début du geste lorsqu'il
	# commence sur un bouton. PASS garde le clic et permet SCROLL_BEGIN de
	# l'annuler dès que le doigt glisse (sans clic involontaire au relâchement).
	if (node is BaseButton or (node is Container and not node is ScrollContainer)) and node.mouse_filter == Control.MOUSE_FILTER_STOP:
		node.mouse_filter = Control.MOUSE_FILTER_PASS
	if node is OptionButton: node.action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE
	if not node.child_entered_tree.is_connected(_watch): node.child_entered_tree.connect(_watch)
	for child in node.get_children(): _watch(child)

# Le geste appartient au conteneur où il a commencé, même quand le doigt
# traverse un bouton, quitte son rectangle ou passe sur un autre panneau.
var _finger := -1
var _origin := Vector2.ZERO
var _last := Vector2.ZERO
var _scroll_origin := Vector2.ZERO
var _dragging := false
var _velocity := Vector2.ZERO
var _last_ms := 0

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and _finger == -1 and is_visible_in_tree() and get_global_rect().has_point(event.position):
			# Le scroller imbriqué le plus profond reçoit le geste.
			for child in find_children("*", "ScrollContainer", true, false):
				if child.is_visible_in_tree() and child.get_global_rect().has_point(event.position): return
			_finger = event.index; _origin = event.position; _last = _origin
			_scroll_origin = Vector2(scroll_horizontal, scroll_vertical)
			_velocity = Vector2.ZERO; _dragging = false; _last_ms = Time.get_ticks_msec()
		elif event.index == _finger and not event.pressed:
			_finger = -1
			if _dragging:
				propagate_notification(NOTIFICATION_SCROLL_END)
				get_viewport().set_input_as_handled()
			_dragging = false
	elif event is InputEventScreenDrag and event.index == _finger:
		var delta: Vector2 = event.position - _origin
		var horizontal := horizontal_scroll_mode != SCROLL_MODE_DISABLED and get_h_scroll_bar().max_value > size.x + 1.0
		var vertical := vertical_scroll_mode != SCROLL_MODE_DISABLED and get_v_scroll_bar().max_value > size.y + 1.0
		var along_axis := (horizontal and absf(delta.x) >= scroll_deadzone and absf(delta.x) >= absf(delta.y) * 0.7) or (vertical and absf(delta.y) >= scroll_deadzone and absf(delta.y) >= absf(delta.x) * 0.7)
		if not _dragging and along_axis:
			_dragging = true; follow_focus = false
			propagate_notification(NOTIFICATION_SCROLL_BEGIN)
		if _dragging:
			var now := Time.get_ticks_msec()
			var seconds := maxf(float(now - _last_ms) * 0.001, 0.008)
			_velocity = _velocity.lerp((_last - event.position) / seconds, 0.55)
			_apply_scroll(_scroll_origin - delta)
			_last = event.position; _last_ms = now
			get_viewport().set_input_as_handled()
	elif _dragging and event is InputEventMouseMotion and event.device == -1:
		# Android émet aussi une souris : une seule intégration du déplacement.
		get_viewport().set_input_as_handled()

func _apply_scroll(value: Vector2) -> void:
	if horizontal_scroll_mode != SCROLL_MODE_DISABLED: scroll_horizontal = roundi(value.x)
	if vertical_scroll_mode != SCROLL_MODE_DISABLED: scroll_vertical = roundi(value.y)

func _process(dt: float) -> void:
	if _finger >= 0 or _velocity.length() < 3.0: return
	_apply_scroll(Vector2(scroll_horizontal, scroll_vertical) + _velocity * minf(dt, 0.05))
	_velocity *= exp(-8.0 * dt)
