class_name TrainPhysics
extends RefCounted
## Dynamique longitudinale 1D : traction limitée par effort et puissance,
## résistance de Davis, pente, freinage, limite de vitesse en courbe.

const G := 9.80665

var profile: VehicleProfile
var passengers: int = 0
var speed: float = 0.0      # m/s
var position: float = 0.0   # abscisse curviligne (m)
var power_available: bool = true

func _init(p: VehicleProfile) -> void:
	profile = p

func mass() -> float:
	return profile.loaded_mass(passengers)

## Résistance au roulement + aérodynamique (N).
func resistance(v: float) -> float:
	var m := mass()
	return 0.0015 * m * G + 0.05 * m * 0.01 * v + 6.0 * v * v

## notch : -1 (freinage max) .. +1 (traction max) ; grade : pente (+ = montée).
func step(dt: float, notch: float, grade: float, emergency: bool = false) -> void:
	var m := mass()
	var force := 0.0
	if emergency:
		force = -profile.emergency_brake_ms2 * m
	elif notch >= 0.0 and power_available:
		var fmax := minf(profile.max_tractive_effort_n, profile.power_kw * 1000.0 / maxf(speed, 1.0))
		force = notch * fmax
	elif notch < 0.0:
		force = notch * profile.service_brake_ms2 * m
	var drag := resistance(speed) + m * G * grade
	var net := force - drag if speed > 0.0 or force > drag else 0.0
	if force < 0.0:
		net = force - drag  # freinage + résistances
	speed = clampf(speed + net / m * dt, 0.0, profile.max_speed_ms)
	position += speed * dt

func braking_distance(v: float, emergency: bool = false) -> float:
	var a := profile.emergency_brake_ms2 if emergency else profile.service_brake_ms2
	return v * v / (2.0 * a)

## Vitesse max en courbe (m/s) pour un rayon donné et une accélération latérale tolérée.
static func curve_speed_limit(radius_m: float, lateral_ms2: float = 0.9) -> float:
	return sqrt(lateral_ms2 * radius_m)
