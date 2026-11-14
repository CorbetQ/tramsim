class_name UiAudio
extends Node
## Quiet CC0 clicks on confirmed actions only; no hover/drag/slider-motion sounds.
const DIR := "res://data/audio/free_sfx/"
var enabled := true
var played := 0
var _last_usec := -1000000
var _player: AudioStreamPlayer
var _streams := {}

func _ready() -> void:
	_player = AudioStreamPlayer.new(); _player.volume_db = -21.0; add_child(_player)
	for key in ["click", "back", "confirm"]:
		_streams[key] = TramAudio.stream_path(DIR + "ui_" + key + ".ogg", false)
	get_tree().node_added.connect(_watch, CONNECT_DEFERRED)
	_watch_tree(get_tree().root)

func _watch_tree(node: Node) -> void:
	_watch(node)
	for child in node.get_children(): _watch_tree(child)

func _watch(node: Node) -> void:
	if not is_instance_valid(node) or not node is BaseButton: return
	if node.has_meta("ui_sound_hook"): return
	node.set_meta("ui_sound_hook", true)
	node.pressed.connect(_pressed.bind(weakref(node)))

func _pressed(button_ref: WeakRef) -> void:
	var button: BaseButton = button_ref.get_ref()
	if button == null or button.disabled: return
	# TouchScroll cancels button presses when a gesture becomes a drag. Also reject
	# early press-mode buttons inside an active scroll gesture.
	var parent := button.get_parent()
	while parent != null:
		if parent is TouchScroll and parent._dragging: return
		parent = parent.get_parent()
	var label: String = str(button.name).to_lower() + " " + (button.text.to_lower() if button is Button else "")
	var key := "click"
	if "retour" in label or "fermer" in label or "back" in label: key = "back"
	elif "lancer" in label or "reprendre" in label or button.name == "go": key = "confirm"
	play(key)

func play(key := "click") -> void:
	var now := Time.get_ticks_usec()
	if not enabled or now - _last_usec < 80000 or not _streams.has(key): return
	_last_usec = now
	_player.stream = _streams[key]; _player.play(); played += 1
