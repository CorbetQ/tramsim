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
