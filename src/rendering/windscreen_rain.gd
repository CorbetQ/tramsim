class_name WindscreenRain
extends MeshInstance3D
## Gouttes sur le pare-brise en vue cabine (lot P4 « ambiance », shaders/windscreen_rain.gdshader) : quad accroché à la
## caméra, dessiné par-dessus la scène dans la seule partie haute de l'écran (pare-brise). Le balai est celui de la rame :
## angle des nœuds `wiper_*` de la rame HD (StockHD.wiper_angle, période et débattement du manifeste), sinon cycle
## simulé de 1,6 s quand l'essuie-glace est en marche (pluie > 0,15 ou touche E). Chaque secteur angulaire balayé note
## l'heure du passage : les gouttes nées avant disparaissent, les nouvelles se reforment selon l'intensité de la pluie.

const BINS := 16
var mat: ShaderMaterial
var clear_t := PackedFloat32Array()
var _phase := 0.0
var _prev_angle := 0.0
var strength := 0.0

func _init() -> void:
	name = "windscreen_rain"
	var q := QuadMesh.new(); q.size = Vector2(4.0, 3.0)
	mesh = q
	mat = ShaderMaterial.new(); mat.shader = load("res://src/rendering/shaders/windscreen_rain.gdshader")
	mat.render_priority = 100
	material_override = mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	extra_cull_margin = 16384.0
	position = Vector3(0, 0, -0.35)
	clear_t.resize(BINS); clear_t.fill(-1e6)
	visible = false

static func now() -> float:
	return Time.get_ticks_msec() / 1000.0

## rain : intensité (0..1, déjà nulle sous abri) ; wiper_on : essuie-glace en marche ; hd_angle : angle du balai HD
## (radians, < 0 : pas de rame HD) ; sweep : débattement HD ; speed : vitesse de la rame (m/s).
func update_wiper(dt: float, rain: float, wiper_on: bool, hd_angle: float, sweep: float, speed: float, night: float) -> void:
	strength = move_toward(strength, rain, dt * (0.08 if rain > strength else 0.03))
	visible = strength > 0.02
	var t := now()
	var a := 0.0
	if hd_angle >= 0.0 and sweep > 0.01:
		a = clampf(hd_angle / sweep, 0.0, 1.0)
	else:
		if wiper_on: _phase = fposmod(_phase + dt / 1.6, 1.0)
		elif _phase > 0.0:
			_phase += dt / 1.6
			if _phase >= 1.0: _phase = 0.0
		a = 0.5 - 0.5 * cos(TAU * _phase)
	# secteurs franchis depuis l'image précédente (aller et retour) : passage du balai noté
	var lo := minf(a, _prev_angle); var hi := maxf(a, _prev_angle)
	if hi - lo > 0.0005:
		for b in BINS:
			var c := (b + 0.5) / BINS
			if c >= lo - 0.5 / BINS and c <= hi + 0.5 / BINS: clear_t[b] = t
	_prev_angle = a
	if not visible: return
	mat.set_shader_parameter("rain", strength)
	mat.set_shader_parameter("now", t)
	mat.set_shader_parameter("clear_t", clear_t)
	mat.set_shader_parameter("speed", speed)
	mat.set_shader_parameter("night", night)

## Dernier passage du balai par secteur (tests).
func cleared_since(t: float) -> int:
	var n := 0
	for v in clear_t: if v >= t: n += 1
	return n
