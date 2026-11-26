class_name DayNight
extends Node
## Cycle jour/nuit : soleil (course est -> ouest), lune bleutée la nuit, ciel physique simplifié (sky.gdshader),
## brouillard exponentiel + brouillard de hauteur relatif au sol, lumière ambiante issue du ciel, tonemapper AgX et
## exposition, et paramètre global `night` (fenêtres, phares, lampadaires). Les effets dépendant du renderer et du
## profil de qualité (GI, SSAO, SSR, brouillard volumétrique, AA, ombres) sont appliqués par VisualEffects.

var hour := 12.0
var sun: DirectionalLight3D
var env: Environment
var sky_mat: ShaderMaterial
var night := 0.0
## Exposition de base (AgX) : multipliée par le profil de qualité ; la nuit est légèrement remontée (adaptation).
const EXPOSURE_DAY := 1.0
const EXPOSURE_NIGHT := 1.35
var exposure_scale := 1.0
## Qualité : mobile = ombres allégées, glow léger.
static var low_quality := OS.has_feature("mobile")

func setup(parent: Node3D) -> void:
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	# décor : normales de facette (CityScene) pour le biais normal ; rubans des voies sans normales : biais de profondeur
	sun.shadow_bias = 0.12
	sun.shadow_normal_bias = 1.6
	sun.shadow_blur = 0.25
	# diamètre apparent du soleil (0,53°) : pénombre physique (PCSS) en Forward+ si le profil l'active
	sun.light_angular_distance = 0.0
	sun.shadow_opacity = 0.9
	sun.directional_shadow_max_distance = 110.0 if low_quality else 170.0
	# P5 : deux cascades seulement (2 passes d'ombre au lieu de 4) : la première, nette, couvre les 60 premiers mètres
	# (40 m sur mobile), la seconde le reste jusqu'à la distance maximale.
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_split_1 = (40.0 if low_quality else 60.0) / sun.directional_shadow_max_distance
	sun.directional_shadow_blend_splits = not low_quality
	sun.directional_shadow_fade_start = 0.85
	parent.add_child(sun)
	sky_mat = ShaderMaterial.new()
	sky_mat.shader = load("res://src/rendering/shaders/sky.gdshader")
	var sky := Sky.new(); sky.sky_material = sky_mat
	sky.process_mode = Sky.PROCESS_MODE_REALTIME if not low_quality else Sky.PROCESS_MODE_AUTOMATIC
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	# ambiance PBR : radiance du ciel (teinte cohérente avec l'heure et la météo) + appoint de couleur
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 0.65
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_density = 0.0016
	env.fog_sky_affect = 0.0
	# brouillard de hauteur relatif au sol (set_ground) : seulement les fonds de vallée, jamais un voile uniforme
	env.fog_height = -10.0
	env.fog_height_density = 0.003
	# chaîne de couleur : AgX (filmique, sans dérive de teinte des hautes lumières), exposition par heure et profil
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = EXPOSURE_DAY
	env.tonemap_white = 16.0
	# bloom léger : seules les sources émissives (fenêtres, lampadaires, phares, soleil) débordent
	env.glow_enabled = true
	env.glow_normalized = false
	env.glow_intensity = 0.55 if low_quality else 0.8
	env.glow_strength = 1.0
	env.glow_bloom = 0.0
	# seuil au-dessus du blanc : ciel (disque solaire) et sources émissives seulement, jamais les façades claires
	env.glow_hdr_threshold = 1.1
	env.glow_hdr_scale = 2.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	for i in 7: env.set_glow_level(i, 0.0)
	env.set_glow_level(1, 0.5); env.set_glow_level(2, 0.8)
	if not low_quality: env.set_glow_level(3, 0.4)
	# aucune retouche globale : contraste et saturation neutres (palettes calibrées sur orthophoto et photos)
	env.adjustment_enabled = false
	env.adjustment_contrast = 1.0
	env.adjustment_saturation = 1.0
	var we := WorldEnvironment.new(); we.environment = env
	parent.add_child(we)
	set_hour(hour)

static func _k(keys: Array, h: float) -> Color:
	# interpolation entre couleurs clés [heure, couleur]
	for i in range(keys.size() - 1):
		var a: Array = keys[i]; var b: Array = keys[i + 1]
		if h >= a[0] and h <= b[0]:
			return (a[1] as Color).lerp(b[1], (h - a[0]) / maxf(b[0] - a[0], 0.001))
	return keys[-1][1]

func set_hour(h: float) -> void:
	hour = fposmod(h, 24.0)
	# hauteur du soleil : lever ~6h30, zénith 13h30 (heure légale), coucher ~20h30
	var t := (hour - 6.5) / 14.0
	var elev := sin(t * PI) * 58.0
	var azim := lerpf(-100.0, 100.0, clampf(t, 0.0, 1.0))
	night = clampf(1.0 - (elev + 6.0) / 14.0, 0.0, 1.0)
	RenderingServer.global_shader_parameter_set("night", night)
	# lumière dorée basse au lever / coucher, blanc chaud en journée
	var day_col := _k([[0.0, Color("#3b4a7a")], [5.5, Color("#3b4a7a")], [6.8, Color("#ffa86a")], [8.3, Color("#ffd29a")], [10.0, Color("#fff3e0")],
		[17.0, Color("#fff3e0")], [19.0, Color("#ffd08e")], [20.2, Color("#ffa264")], [21.5, Color("#3b4a7a")], [24.0, Color("#3b4a7a")]], hour)
	if elev > -4.0:
		sun.rotation_degrees = Vector3(-maxf(elev, 3.0), azim, 0)
		sun.light_color = day_col
		sun.light_energy = lerpf(0.25, 1.22, clampf(elev / 22.0, 0.0, 1.0))
	else:  # clair de lune
		sun.rotation_degrees = Vector3(-35.0, 140.0, 0)
		sun.light_color = Color("#a9bcff")
		sun.light_energy = 0.28   # lune (PBR : plus de plancher de paliers, la face à l'ombre ne reçoit que l'ambiance)
	var top := _k([[0.0, Color("#070b1e")], [5.5, Color("#101736")], [7.0, Color("#4f78c4")], [9.0, Color("#3f7fd6")], [12.0, Color("#3a7ad4")],
		[18.5, Color("#4a80cf")], [20.3, Color("#33407e")], [21.8, Color("#0a1028")], [24.0, Color("#070b1e")]], hour)
	var horizon := _k([[0.0, Color("#18203f")], [5.5, Color("#2c2f58")], [6.9, Color("#ffa77a")], [8.5, Color("#cde0f2")],
		[17.5, Color("#cfe1f2")], [19.3, Color("#f6cfa6")], [20.3, Color("#f0a07a")], [21.5, Color("#2c2f58")], [24.0, Color("#18203f")]], hour)
	sky_mat.set_shader_parameter("top_color", top)
	sky_mat.set_shader_parameter("horizon_color", horizon)
	sky_mat.set_shader_parameter("ground_color", top.lerp(horizon, 0.5).darkened(0.35))
	sky_mat.set_shader_parameter("sun_glow", day_col.lerp(Color("#ffd9a0"), 0.3))
	sky_mat.set_shader_parameter("cloud_light", horizon.lerp(Color.WHITE, 0.55).lerp(day_col, 0.25))
	sky_mat.set_shader_parameter("cloud_shade", horizon.lerp(top, 0.25).lerp(Color.WHITE, 0.2))
	sky_mat.set_shader_parameter("night", night)
	sky_mat.set_shader_parameter("energy", lerpf(1.0, 0.9, night))
	# ambiance : bleutée (ombres froides) le jour, violacée au crépuscule, bleu nuit
	env.ambient_light_color = _k([[0.0, Color("#2a3466")], [6.0, Color("#3e4478")], [8.0, Color("#b3bccb")], [17.0, Color("#bcc4d0")],
		[20.3, Color("#8a8ab0")], [22.0, Color("#2a3466")], [24.0, Color("#2a3466")]], hour)
	# nuit : le ciel noir n'éclaire plus ; ambiance urbaine (lune + halo de la ville) en couleur, sans noir bouché
	env.ambient_light_sky_contribution = lerpf(0.65, 0.25, night)
	env.ambient_light_energy = lerpf(0.55, 1.3, night)
	env.tonemap_exposure = lerpf(EXPOSURE_DAY, EXPOSURE_NIGHT, night) * exposure_scale
	env.fog_light_color = horizon.lerp(top, 0.35)   # perspective aérienne bleutée plutôt que voile blanc
	env.fog_light_energy = lerpf(0.9, 0.5, night)
	env.fog_density = lerpf(0.0003, 0.0017, night)   # jour : ~14 % à 500 m (vues obliques/aériennes lisibles)
	env.fog_aerial_perspective = 0.6
	env.glow_intensity = lerpf(0.35, 0.55 if low_quality else 0.9, night)

## Altitude du sol sous la caméra (repère de la ligne) : cale le brouillard de hauteur sur le terrain
## (et non sur l'altitude 0 : Angers est à −17 m, Saint-Étienne à +100 m par rapport à `alt0`).
var ground_y := 0.0
func set_ground(y: float) -> void:
	if is_nan(y): return
	ground_y = lerpf(ground_y, y, 0.1) if absf(ground_y - y) < 30.0 else y
	if env: env.fog_height = ground_y - 10.0

func clock_text() -> String:
	return "%02d:%02d" % [int(hour), int(fmod(hour, 1.0) * 60.0)]
