class_name WeatherView
extends Node3D
## Météo visible, bornée autour de la caméra (lot P4 « ambiance ») ; la géographie n'est pas modifiée.
## - Pluie : gouttes (CPUParticles3D) ; neige légère (preset « snow ») : flocons lents.
## - Chaussée mouillée : paramètre global `wet` (WeatherState.wetness, lissé, réduit sous abri / en tunnel) lu par
##   pbr_world, pbr_surface et station_paving (assombrissement, rugosité basse : reflets du ciel, SSR en Ultra ;
##   flaques et ronds de pluie) ; `snow` : couverture neigeuse des faces horizontales, accumulée puis fondue lentement.
## - Pare-brise : gouttes et balai en vue cabine (WindscreenRain, lié aux nœuds wiper_* de la rame HD).
## - Brouillard : exponentiel + hauteur (tous profils), brume matinale (5 h – 9 h 30) plus dense au ras du sol ;
##   brouillard volumétrique en Ultra (Forward+) avec diffusion avant (rayons du soleil bas).
var drops: CPUParticles3D
var flakes: CPUParticles3D
var windscreen: WindscreenRain
var wet := 0.0
var snow_cover := 0.0
var morning := 0.0

static func _particles(amount: int, size: Vector2, color: Color) -> CPUParticles3D:
	var p := CPUParticles3D.new(); p.amount = amount
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	var mesh := QuadMesh.new(); mesh.size = size
	var mat := StandardMaterial3D.new(); mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA; mat.vertex_color_use_as_albedo = true; mat.vertex_color_is_srgb = true
	mat.albedo_color = Color.WHITE; mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED; mesh.material = mat; p.mesh = mesh
	p.color = color; p.local_coords = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; p.emitting = false
	return p

func _ready() -> void:
	var mobile := OS.has_feature("mobile") or DayNight.low_quality
	drops = _particles(160 if mobile else 320, Vector2(0.018, 0.45), Color(0.65, 0.8, 0.92, 0.3))
	drops.lifetime = 1.2; drops.emission_box_extents = Vector3(10, 0.2, 10); drops.direction = Vector3(-0.12, -1, 0)
	drops.spread = 4; drops.initial_velocity_min = 15; drops.initial_velocity_max = 22; drops.gravity = Vector3(0, -3, 0)
	add_child(drops)
	flakes = _particles(220 if mobile else 480, Vector2(0.05, 0.05), Color(0.95, 0.96, 1.0, 0.8))
	flakes.lifetime = 7.0; flakes.emission_box_extents = Vector3(16, 0.3, 16); flakes.direction = Vector3(0.2, -1, 0.1)
	flakes.spread = 25; flakes.initial_velocity_min = 0.6; flakes.initial_velocity_max = 1.4; flakes.gravity = Vector3(0, -0.35, 0)
	flakes.orbit_velocity_min = 0.0; flakes.angular_velocity_max = 40.0
	add_child(flakes)

## Brume matinale (0..1) : maximale vers 7 h 15, nulle avant 5 h et après 9 h 30.
static func morning_mist(hour: float) -> float:
	var m := clampf(1.0 - absf(hour - 7.25) / 2.25, 0.0, 1.0)
	return m * m * (3.0 - 2.0 * m)

func apply(state: WeatherState, view: LineView, sheltered: bool = false) -> void:
	if drops == null or view.cam == null: return
	var dt := get_process_delta_time()
	if dt <= 0.0: dt = 1.0 / 60.0
	global_position = view.cam.global_position + Vector3(0, 9, 0)
	var snowing := state.preset == "snow"
	drops.emitting = state.rain > 0.03 and not sheltered and not snowing
	drops.visible = not sheltered
	drops.color = Color(0.65, 0.8, 0.92, state.rain * .4)
	flakes.emitting = snowing and state.rain > 0.03 and not sheltered
	flakes.visible = snowing and not sheltered
	flakes.position = Vector3(0, -2, 0)
	# chaussée mouillée et neige (globaux des shaders PBR)
	var target_wet := clampf(state.wetness * 1.15, 0.0, 1.0) * (0.2 if sheltered else 1.0) * (0.55 if snowing else 1.0)
	wet = move_toward(wet, target_wet, dt * 0.25)
	var target_snow := clampf(state.rain * 1.6, 0.0, 0.85) if snowing else 0.0
	snow_cover = move_toward(snow_cover, target_snow, dt * (1.0 / 90.0 if target_snow > snow_cover else 1.0 / 240.0))
	RenderingServer.global_shader_parameter_set("wet", wet)
	RenderingServer.global_shader_parameter_set("snow", snow_cover)
	# brouillard : météo + brume matinale (DayNight.set_hour remet la densité exponentielle à chaque image)
	var dn := view.day_night
	var env := dn.env
	morning = morning_mist(dn.hour) * (1.0 - state.rain * 0.5)
	env.fog_density += state.fog * 0.012 + state.rain * 0.001 + morning * 0.0012 + (0.002 if snowing else 0.0) * state.rain
	env.fog_height_density = 0.003 + morning * 0.03 + state.fog * 0.02
	if env.volumetric_fog_enabled:
		env.volumetric_fog_density = 0.0025 + morning * 0.012 + state.fog * 0.025 + state.rain * 0.004
		env.volumetric_fog_anisotropy = 0.55 if morning > 0.05 else 0.2
		env.volumetric_fog_albedo = Color(1.0, 0.93, 0.85).lerp(Color(0.9, 0.92, 0.96), 1.0 - morning)
		env.volumetric_fog_length = 96.0 + morning * 64.0
	dn.sun.light_energy *= 1.0 - state.rain * 0.45
	var sky := dn.sky_mat
	for key in ["top_color", "horizon_color", "cloud_light", "cloud_shade"]:
		var original: Color = sky.get_shader_parameter(key)
		sky.set_shader_parameter(key, original.lerp(Color("#8999a5"), state.rain * .65))
	sky.set_shader_parameter("cloud_cover", clampf(0.45 + state.rain * 0.5 + state.fog * 0.3, 0.0, 0.98))
	_windscreen(state, view, sheltered or snowing, dt)

## Gouttes et balai du pare-brise, en vue cabine seulement.
func _windscreen(state: WeatherState, view: LineView, sheltered: bool, dt: float) -> void:
	var cab: bool = not view.external_view
	if windscreen == null:
		if not cab or state.rain < 0.03: return
		windscreen = WindscreenRain.new()
	if windscreen.get_parent() != view.cam:
		if windscreen.get_parent() != null: windscreen.get_parent().remove_child(windscreen)
		view.cam.add_child(windscreen)
	var wiper_on: bool = view.wiper_forced or state.rain > 0.15
	var angle := -1.0; var sweep := 0.0
	if view.rig != null and view.rig.hd != null and view.rig.hd.has_method("wiper_angle") and not view.rig.hd.wipers.is_empty():
		angle = view.rig.hd.wiper_angle()
		sweep = deg_to_rad(float(view.rig.hd.entry.get("wiper", {}).get("sweep_deg", 90.0)))
	windscreen.update_wiper(dt, state.rain if cab and not sheltered else 0.0, wiper_on, angle, sweep, view.speed_mps, view.day_night.night)
	if not cab: windscreen.visible = false
