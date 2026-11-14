class_name IntroCamera
extends Node3D
## Intro de lancement : zooms successifs ville -> quartier -> station, puis la caméra de jeu.
## Trois paliers (ralentissement à chacun, léger voile), interpolation logarithmique de la distance.
## La caméra de jeu (LineView.cam) reste figée sur sa pose d'arrivée pendant l'intro (garde dans
## LineView.update_from via la méta "intro_camera") ; le décor de la zone de départ est déjà
## construit (CityScene.warm) avant la première image. Touche, clic ou toucher : passer.

signal finished

## [distance à la cible (m), élévation (°), décalage d'azimut (rad), durée vers le palier suivant (s)]
const STAGES := [[2200.0, 90.0, 0.0, 1.3], [700.0, 90.0, 0.0, 1.0], [160.0, 82.0, 0.0, 1.6]]
const PAN := 1.3
const HOLD := 0.18          # immobile sur la vue de la ville (fondu d'entrée)
const VEIL := 0.22          # opacité maximale du voile entre paliers

var view: LineView
var cam: Camera3D
var t := 0.0
var duration := 0.0
var progress := 0.0
var _keys: Array = []       # [position, cible]
var _final: Transform3D
var _final_fov := 62.0
var _fog0 := -1.0
var _fog_enabled := true
var _fog_height := 0.0
var _shadow0 := false
var _edges0 := false
var _layer: CanvasLayer
var _veil: ColorRect
var _caption: Label
var _captions: PackedStringArray
var _done := false
var _skip_requested := false
var _clouds: ShaderMaterial
var _cloud_rect: ColorRect
var _render_scale0 := 1.0
var _msaa0 := Viewport.MSAA_DISABLED
var _render_restored := false
var _pan_duration := 0.0
var _start_pose: Transform3D
var _top_size := 1800.0
var _aerial: CityScene
var _arrival_hour := 12.0
var _departure_hour := 12.0
var _hidden_detail: Array[Node3D] = []
var _showing_aerial := false

## `focus` : point de départ de la rame (repère LineView) ; `captions` : un texte par palier.
func start(v: LineView, focus: Vector3, captions: PackedStringArray = PackedStringArray(), departure: Dictionary = {}) -> void:
	view = v; _captions = captions
	_render_scale0 = get_viewport().scaling_3d_scale
	_msaa0 = get_viewport().msaa_3d
	get_viewport().msaa_3d = Viewport.MSAA_DISABLED
	get_viewport().scaling_3d_scale = minf(_render_scale0, 0.65)
	if v.day_night and v.day_night.env:
		_fog0 = v.day_night.env.fog_density
		_fog_enabled = v.day_night.env.fog_enabled
		_fog_height = v.day_night.env.fog_height_density
	_shadow0 = v.day_night.sun.shadow_enabled if v.day_night else false
	_edges0 = v.day_night.edges.visible if v.day_night and v.day_night.edges else false
	_final = v.cam.global_transform; _final_fov = v.cam.fov
	var h := _final.origin - focus; h.y = 0.0
	h = h.normalized() if h.length() > 0.5 else Vector3(0, 0, 1)
	for s in STAGES:
		var dir := h.rotated(Vector3.UP, s[2])
		var e := deg_to_rad(s[1])
		_keys.append([focus + dir * s[0] * cos(e) + Vector3(0, s[0] * sin(e), 0), focus])
	_start_pose = departure.get("transform", _xf(_keys[0][0], _keys[0][1]))
	_pan_duration = PAN if departure.has("transform") else 0.0
	_top_size = float(departure.get("size", 1800.0))
	if _pan_duration > 0.0: _keys[0][0].y = _start_pose.origin.y
	_arrival_hour = v.day_night.hour if v.day_night else 12.0
	_departure_hour = float(departure.get("hour", _arrival_hour))
	_aerial = departure.get("aerial")
	if is_instance_valid(_aerial): add_child(_aerial)
	_keys.append([_final.origin, _final.origin - _final.basis.z * maxf(8.0, _final.origin.distance_to(focus))])
	duration = HOLD + _pan_duration
	for s in STAGES: duration += s[3]
	cam = Camera3D.new(); cam.near = 0.5; cam.fov = 55.0; add_child(cam)
	v.set_meta("intro_camera", cam)
	cam.current = true
	_layer = CanvasLayer.new(); _layer.layer = 50; add_child(_layer)
	_veil = ColorRect.new(); _veil.color = Color(0.02, 0.03, 0.05, 1.0); _veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); _layer.add_child(_veil)
	var clouds := ColorRect.new(); clouds.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clouds.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_clouds = ShaderMaterial.new(); _clouds.shader = load("res://src/rendering/shaders/transition_clouds.gdshader")
	_clouds.set_shader_parameter("cloud_noise", load("res://src/rendering/transition_noise.tres"))
	_cloud_rect = clouds
	clouds.material = _clouds; _layer.add_child(clouds)
	_caption = Label.new(); _caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_caption.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM); _caption.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_caption.offset_top = -120; _caption.offset_bottom = -64; _caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.add_theme_font_override("font", UiTheme.font(true)); _caption.add_theme_font_size_override("font_size", UiTheme.SIZE_H1)
	_caption.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8)); _caption.add_theme_constant_override("shadow_offset_y", 2)
	_layer.add_child(_caption)
	var hint := Label.new(); hint.text = "Toucher ou appuyer sur une touche pour passer"; hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT); hint.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	hint.grow_vertical = Control.GROW_DIRECTION_BEGIN; hint.offset_right = -22; hint.offset_bottom = -18
	hint.add_theme_font_size_override("font_size", UiTheme.SIZE_SMALL); hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.75))
	hint.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8)); hint.name = "skip_hint"
	_layer.add_child(hint)
	_apply(0.0)

## Pose de l'intro au temps `time` (s) : utilisé par le rendu et les tests.
func pose_at(time: float) -> Transform3D:
	if time <= HOLD: return _start_pose
	if _pan_duration > 0.0 and time < HOLD + _pan_duration:
		var u := smoothstep(0.0, 1.0, (time - HOLD) / _pan_duration)
		# Translation stays vertical/north-up until the station is centered.
		return Transform3D(_start_pose.basis, _start_pose.origin.lerp(_keys[0][0], u))
	var tt := time - HOLD - _pan_duration
	for i in STAGES.size():
		var d: float = STAGES[i][3]
		if tt <= d or i == STAGES.size() - 1:
			var u := clampf(tt / d, 0.0, 1.0)
			u = u * u * (3.0 - 2.0 * u)                    # ralentit à l'approche de chaque palier
			var a: Array = _keys[i]; var b: Array = _keys[i + 1]
			var look: Vector3 = a[1].lerp(b[1], u)
			var oa: Vector3 = a[0] - a[1]; var ob: Vector3 = b[0] - b[1]
			var length := exp(lerpf(log(maxf(oa.length(), 0.1)), log(maxf(ob.length(), 0.1)), u))
			var dir := oa.normalized().slerp(ob.normalized(), u)
			var xf := _xf(look + dir * length, look)
			if i < STAGES.size() - 1: xf.basis = Basis.looking_at((look - xf.origin).normalized(), Vector3.FORWARD)
			if i == STAGES.size() - 1:
				var initial: Vector3 = _keys[i][1] - _keys[i][0]
				xf.basis = Basis.looking_at(initial.normalized(), Vector3.FORWARD).slerp(_final.basis, u)
				if u >= 1.0: xf = _final
			return xf
		tt -= d
	return _final

func _xf(p: Vector3, look: Vector3) -> Transform3D:
	var direction := (look - p).normalized()
	return Transform3D(Basis.looking_at(direction, Vector3.FORWARD if absf(direction.dot(Vector3.UP)) > 0.999 else Vector3.UP), p)

func _process(dt: float) -> void:
	if _done: return
	if _skip_requested:
		if view.city and view.city.lod_pending():
			view.city.update(view.cam.global_position, 2); return
		finish(); return
	# Start detail streaming immediately while only the cheap aerial proxy is visible.
	if view.city: view.city.update(view.cam.global_position, 1)
	var next := t + minf(dt, 0.5)
	# Hold the aerial move while the next visible LOD tiles are prepared, never reveal empty squares.
	if is_instance_valid(_aerial) and next < HOLD + _pan_duration + STAGES[0][3]:
		_aerial.update(pose_at(next).origin, 0)
	var detail_switch := HOLD + _pan_duration + STAGES[0][3] + STAGES[1][3] + 0.18
	if next >= detail_switch and view.city and view.city.lod_pending():
		view.city.update(view.cam.global_position, 2)
		if view.city.lod_pending(): next = minf(next, detail_switch - 0.001)
	t = next
	_apply(t)
	if t >= duration: finish()

func _apply(time: float) -> void:
	progress = clampf(time / duration, 0.0, 1.0)
	cam.global_transform = pose_at(time)
	var height := cam.global_position.distance_to(_keys[-1][1])
	cam.far = maxf(1600.0, height * 4.0)
	# palier courant (légende) et voile : fondu d'entrée puis léger voile à chaque changement de palier
	var stage := 0; var edge := HOLD + _pan_duration
	var veil := (1.0 - smoothstep(0.0, HOLD, time)) if _pan_duration == 0.0 else 0.0
	for i in STAGES.size():
		var end_: float = edge + STAGES[i][3]
		if time > edge + STAGES[i][3] * 0.5: stage = i + 1
		if i < STAGES.size() - 1: veil = maxf(veil, VEIL * (1.0 - smoothstep(0.0, 0.3, absf(time - end_))))
		edge = end_
	_veil.color.a = veil
	var cloud_strength := 0.0
	var elapsed := HOLD + _pan_duration
	for i in 2:
		elapsed += STAGES[i][3]
		cloud_strength = maxf(cloud_strength, 0.9 * (1.0 - smoothstep(0.0, 0.45, absf(time - elapsed))))
	_cloud_rect.visible = cloud_strength > 0.005
	_clouds.set_shader_parameter("strength", cloud_strength)
	_clouds.set_shader_parameter("travel", time)
	stage = mini(stage, STAGES.size() - 1)
	_caption.text = _captions[stage] if stage < _captions.size() else ""
	_caption.modulate.a = 1.0 - smoothstep(duration - 0.6, duration - 0.1, time)
	var zoom_start := HOLD + _pan_duration
	var last_zoom := zoom_start + STAGES[0][3] + STAGES[1][3]
	var u := smoothstep(last_zoom, duration, time)
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL if time < last_zoom + 0.18 else Camera3D.PROJECTION_PERSPECTIVE
	var sizes := [_top_size, 580.0, 135.0, 42.0]
	var local := maxf(time - zoom_start, 0.0)
	cam.size = _top_size
	for i in STAGES.size():
		var d: float = STAGES[i][3]
		if local <= d or i == STAGES.size() - 1:
			var q := smoothstep(0.0, 1.0, clampf(local / d, 0.0, 1.0))
			cam.size = exp(lerpf(log(sizes[i]), log(sizes[i + 1]), q)); break
		local -= d
	if is_instance_valid(_aerial):
		_aerial.visible = time < last_zoom + 0.18
		if _aerial.visible != _showing_aerial:
			_showing_aerial = _aerial.visible
			if _showing_aerial:
				for child in view.get_children():
					if child is Node3D and child != self and child != view.cam and child != view.city and not child is Light3D and child.visible:
						_hidden_detail.append(child); child.visible = false
			else: _restore_detail()
		if view.city: view.city.visible = not _aerial.visible
		if view.day_night:
			view.day_night.sun.shadow_enabled = false
			if view.day_night.edges: view.day_night.edges.visible = false

	if view.day_night: view.day_night.set_hour(lerpf(_departure_hour, _arrival_hour, smoothstep(zoom_start, duration, time)))
	cam.fov = lerpf(55.0, _final_fov, u)
	# brume allégée en altitude (DayNight la recalcule à chaque image avant ce nœud)
	if view.day_night and view.day_night.env:
		var env := view.day_night.env
		var high := smoothstep(180.0, 400.0, height)
		env.fog_enabled = _fog_enabled and high < 0.999
		env.fog_height_density = _fog_height * (1.0 - high)
		env.fog_density *= 1.0 - high

func _restore_render_settings() -> void:
	if _render_restored: return
	_render_restored = true
	get_viewport().scaling_3d_scale = _render_scale0
	get_viewport().msaa_3d = _msaa0

func _exit_tree() -> void:
	_restore_render_settings()
	_restore_detail()

func _restore_detail() -> void:
	for node in _hidden_detail:
		if is_instance_valid(node): node.visible = true
	_hidden_detail.clear()

## Fin (ou passage) : la caméra de jeu reprend la main, à la même pose.
func finish() -> void:
	if _done: return
	_done = true
	_restore_render_settings()
	_restore_detail()
	if is_instance_valid(view):
		if view.city: view.city.visible = true
		if view.day_night:
			view.day_night.set_hour(_arrival_hour)
			view.day_night.env.fog_enabled = _fog_enabled
			view.day_night.env.fog_height_density = _fog_height
			view.day_night.sun.shadow_enabled = _shadow0
			if view.day_night.edges: view.day_night.edges.visible = _edges0
		view.remove_meta("intro_camera")
		view.cam.current = true
	cam.current = false
	finished.emit()
	queue_free()

func skip() -> void:
	if view.city and view.city.lod_pending():
		_skip_requested = true
		if _caption: _caption.text = "Arrivée en station…"
		return
	finish()
