class_name FreeCamera
extends RefCounted
## Caméra de survol libre (type drone) du mode Explorer : déplacement horizontal relatif au cap,
## montée / descente, vitesse proportionnelle à la hauteur au-dessus du sol, accélération (Maj),
## jamais sous le sol. Entrées : clavier (ZQSD / WASD par touches physiques, Espace / C),
## manette (sticks, gâchettes), joystick virtuel et gestes (via move / look / climb_by).

const MIN_AGL := 2.5
const MAX_ALT := 1800.0
const LOOK_RAD_PER_PX := 0.005
const PITCH_MIN := -1.56
const PITCH_MAX := 0.9

var cam: Camera3D
var pos := Vector3.ZERO
var yaw := 0.0
var pitch := -0.45
var base_speed := 14.0
var move := Vector2.ZERO        # entrée analogique externe : x latéral (droite +), y avant (+)
var climb := 0.0                # entrée analogique externe : montée (+) / descente (-)
var boost := false
var ground: Callable = Callable()   # Vector3 -> hauteur du sol (m)
var _glide := Vector3.ZERO      # inertie légère

func _init(camera: Camera3D) -> void:
	cam = camera

func ground_at(p: Vector3) -> float:
	return float(ground.call(p)) if ground.is_valid() else 0.0

func agl() -> float:
	return pos.y - ground_at(pos)

func forward() -> Vector3:
	return Vector3(-sin(yaw), 0.0, -cos(yaw))

func right() -> Vector3:
	return Vector3(cos(yaw), 0.0, -sin(yaw))

func look(delta_px: Vector2) -> void:
	yaw = wrapf(yaw - delta_px.x * LOOK_RAD_PER_PX, -PI, PI)
	pitch = clampf(pitch - delta_px.y * LOOK_RAD_PER_PX, PITCH_MIN, PITCH_MAX)

## Montée / descente immédiate (molette, pincement) proportionnelle à la hauteur.
func climb_by(amount: float) -> void:
	pos.y = clampf(pos.y + amount * maxf(agl(), 6.0) * 0.18, ground_at(pos) + MIN_AGL, MAX_ALT)

func speed() -> float:
	return base_speed * (1.0 + maxf(agl(), 0.0) / 35.0) * (3.0 if boost else 1.0)

func _keys() -> Vector3:
	var k := Vector3.ZERO
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP): k.z += 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN): k.z -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT): k.x += 1.0
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT): k.x -= 1.0
	if Input.is_physical_key_pressed(KEY_SPACE) or Input.is_physical_key_pressed(KEY_E) or Input.is_physical_key_pressed(KEY_PAGEUP): k.y += 1.0
	if Input.is_physical_key_pressed(KEY_C) or Input.is_physical_key_pressed(KEY_CTRL) or Input.is_physical_key_pressed(KEY_PAGEDOWN): k.y -= 1.0
	return k

func _pad(dt: float) -> Vector3:
	var p := Vector3.ZERO
	if Input.get_connected_joypads().is_empty(): return p
	var dz := func(v: float) -> float: return 0.0 if absf(v) < 0.18 else v
	p.x = dz.call(Input.get_joy_axis(0, JOY_AXIS_LEFT_X))
	p.z = -dz.call(Input.get_joy_axis(0, JOY_AXIS_LEFT_Y))
	p.y = Input.get_joy_axis(0, JOY_AXIS_TRIGGER_RIGHT) - Input.get_joy_axis(0, JOY_AXIS_TRIGGER_LEFT)
	var lx: float = dz.call(Input.get_joy_axis(0, JOY_AXIS_RIGHT_X)); var ly: float = dz.call(Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y))
	if lx != 0.0 or ly != 0.0: look(Vector2(lx, ly) * 520.0 * dt)
	if Input.is_joy_button_pressed(0, JOY_BUTTON_LEFT_SHOULDER): boost = true
	return p

func step(dt: float) -> void:
	var k := _keys() + _pad(dt)
	boost = Input.is_physical_key_pressed(KEY_SHIFT) or (not Input.get_connected_joypads().is_empty() and Input.is_joy_button_pressed(0, JOY_BUTTON_LEFT_SHOULDER))
	var m := Vector2(clampf(k.x + move.x, -1.0, 1.0), clampf(k.z + move.y, -1.0, 1.0))
	var up := clampf(k.y + climb, -1.0, 1.0)
	var v := speed()
	var want := (forward() * m.y + right() * m.x) * v + Vector3.UP * up * v * 0.6
	_glide = _glide.lerp(want, 1.0 - exp(-dt * 6.0))
	pos += _glide * dt
	pos.y = clampf(pos.y, ground_at(pos) + MIN_AGL, MAX_ALT)
	apply()

func apply() -> void:
	if cam == null: return
	cam.transform = Transform3D(Basis.from_euler(Vector3(pitch, yaw, 0.0)), pos)

## Vue zénithale au-dessus de la position courante (nord en haut).
func top_view(height: float = 380.0) -> void:
	yaw = 0.0; pitch = PITCH_MIN
	pos.y = ground_at(pos) + height
	_glide = Vector3.ZERO
	apply()

## Saut vers un point : vue oblique à distance, cap conservé, cible au centre.
func jump_to(target: Vector3, dist: float = 120.0, height: float = 60.0) -> void:
	var g := ground_at(target)
	var t := Vector3(target.x, maxf(target.y, g), target.z)
	pos = t - forward() * dist + Vector3.UP * height
	pos.y = maxf(pos.y, ground_at(pos) + MIN_AGL)
	var d := (t + Vector3.UP * 8.0) - pos
	pitch = clampf(atan2(d.y, Vector2(d.x, d.z).length()), PITCH_MIN, PITCH_MAX)
	_glide = Vector3.ZERO
	apply()
