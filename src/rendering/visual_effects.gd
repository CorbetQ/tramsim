class_name VisualEffects
extends Node3D
## Optional bounded effects. Compatibility keeps its existing renderer; SSR is Forward+ only.
const PROFILES := {"economy":{"reflection":false,"glow":0.0,"blur":0.0},"balanced":{"reflection":true,"glow":0.18,"blur":0.0},"cinematic":{"reflection":true,"glow":0.26,"blur":0.22}}
var profile := "balanced"
var view: LineView
var probe: ReflectionProbe
var _anchor := Vector3.INF
var _cooldown := 0.0
var _last_basis := Basis.IDENTITY
var _has_camera := false

func setup(line: LineView, name_: String) -> void:
	view=line;profile=name_ if PROFILES.has(name_) else "balanced"
	var params: Dictionary=PROFILES[profile]
	view.speed_material.set_shader_parameter("bloom_amount",params.glow if RenderingServer.get_current_rendering_method()=="gl_compatibility" else 0.0)
	view.speed_material.set_shader_parameter("motion_amount",params.blur)
	if params.reflection:
		probe=ReflectionProbe.new();probe.size=Vector3(42,16,42);probe.max_distance=55
		probe.update_mode=ReflectionProbe.UPDATE_ONCE;probe.box_projection=true
		add_child(probe)
	if RenderingServer.get_current_rendering_method()=="gl_compatibility":view.day_night.env.ssr_enabled=false
	elif RenderingServer.get_current_rendering_method()=="forward_plus":view.day_night.env.ssr_enabled=profile=="cinematic"
	view.headlight.distance_fade_enabled=true;view.headlight.distance_fade_begin=65;view.headlight.distance_fade_length=20

func _process(dt: float) -> void:
	if view==null or view.cam==null:return
	_cooldown=maxf(0,_cooldown-dt)
	var p := view.cam.global_position
	# One local cubemap, recaptured on substantial movement, never six scene passes every frame.
	if probe!=null and _cooldown<=0 and (not _anchor.is_finite() or p.distance_to(_anchor)>60):
		probe.position=p;_anchor=p;_cooldown=12
		probe.update_mode=ReflectionProbe.UPDATE_ONCE
	var basis := view.cam.global_basis
	var motion := Vector2.ZERO
	if _has_camera:
		motion=Vector2((_last_basis.z-basis.z).dot(basis.x),(_last_basis.z-basis.z).dot(basis.y))
		if motion.length()>.12:motion=Vector2.ZERO # teleport/cut: no smear
	view.speed_material.set_shader_parameter("camera_motion",motion.limit_length(.025))
	_last_basis=basis;_has_camera=true
