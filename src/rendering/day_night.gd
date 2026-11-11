class_name DayNight
extends Node
## Cycle jour/nuit : soleil (course est -> ouest), lune bleutée la nuit, ciel procédural, brouillard,
## lumière ambiante, et paramètre global `night` (fenêtres, phares, lampadaires).

var hour := 12.0
var sun: DirectionalLight3D
var env: Environment
var sky_mat: ProceduralSkyMaterial
var night := 0.0

func setup(parent: Node3D) -> void:
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 140.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	parent.add_child(sun)
	sky_mat = ProceduralSkyMaterial.new()
	var sky := Sky.new(); sky.sky_material = sky_mat
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.fog_enabled = true
	env.fog_density = 0.0016
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 1.6
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
	var day_col := _k([[0.0, Color("#3b4a7a")], [5.5, Color("#3b4a7a")], [7.0, Color("#ffb37a")], [9.0, Color("#fff1dc")],
		[17.0, Color("#fff1dc")], [19.8, Color("#ff9d5c")], [21.5, Color("#3b4a7a")], [24.0, Color("#3b4a7a")]], hour)
	if elev > -4.0:
		sun.rotation_degrees = Vector3(-maxf(elev, 3.0), azim, 0)
		sun.light_color = day_col
		sun.light_energy = lerpf(0.12, 0.95, clampf(elev / 25.0, 0.0, 1.0))
	else:  # clair de lune
		sun.rotation_degrees = Vector3(-35.0, 140.0, 0)
		sun.light_color = Color("#9fb4ff")
		sun.light_energy = 0.12
	sky_mat.sky_top_color = _k([[0.0, Color("#0b1026")], [5.5, Color("#0f1733")], [7.5, Color("#5d8fd8")], [12.0, Color("#3f7fd6")],
		[18.5, Color("#4f86d1")], [20.5, Color("#2a3a78")], [22.0, Color("#0b1026")], [24.0, Color("#0b1026")]], hour)
	sky_mat.sky_horizon_color = _k([[0.0, Color("#1a2140")], [5.5, Color("#2a2f55")], [7.0, Color("#ffb08a")], [9.0, Color("#bcd7f2")],
		[17.5, Color("#c4dbf2")], [20.0, Color("#ff9e6e")], [21.5, Color("#2a2f55")], [24.0, Color("#1a2140")]], hour)
	sky_mat.ground_horizon_color = sky_mat.sky_horizon_color
	sky_mat.ground_bottom_color = sky_mat.sky_top_color.darkened(0.4)
	env.ambient_light_color = _k([[0.0, Color("#2c3560")], [6.0, Color("#3a4170")], [8.0, Color("#b9c6d6")], [17.0, Color("#c4cfdc")],
		[20.5, Color("#6a5a7a")], [22.0, Color("#2c3560")], [24.0, Color("#2c3560")]], hour)
	env.ambient_light_energy = lerpf(0.42, 0.3, night)
	env.fog_light_color = sky_mat.sky_horizon_color
	env.fog_density = lerpf(0.0014, 0.0022, night)

func clock_text() -> String:
	return "%02d:%02d" % [int(hour), int(fmod(hour, 1.0) * 60.0)]
