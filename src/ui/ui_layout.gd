class_name UiLayout
extends RefCounted
## Les dimensions de l'interface sont exprimées en pixels logiques, proches des dp Android.
static func configure(window: Window) -> void:
	var density := maxf(1.0, DisplayServer.screen_get_dpi() / 160.0) if OS.has_feature("mobile") else 1.0
	var logical := Vector2(window.size) / density
	var factor := maxf(1.0, maxf(640.0 / maxf(logical.x, 1.0), 360.0 / maxf(logical.y, 1.0)))
	window.content_scale_size = Vector2i(logical * factor)

static func compact(control: Control) -> bool:
	var s := control.get_viewport_rect().size
	return s.x < 1100.0 or s.y < 620.0

static func safe_insets(control: Control) -> Vector4:
	if not OS.has_feature("mobile"): return Vector4.ZERO
	var window := control.get_window()
	var usable := DisplayServer.get_display_safe_area()
	if usable.size.x <= 0 or usable.size.y <= 0: return Vector4.ZERO
	var physical := Rect2i(DisplayServer.window_get_position(), window.size)
	var safe := physical.intersection(usable)
	if safe.size.x <= 0 or safe.size.y <= 0: return Vector4.ZERO
	var ratio := control.get_viewport_rect().size / Vector2(window.size)
	return Vector4((safe.position.x - physical.position.x) * ratio.x,
		(safe.position.y - physical.position.y) * ratio.y,
		(physical.end.x - safe.end.x) * ratio.x, (physical.end.y - safe.end.y) * ratio.y)
