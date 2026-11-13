class_name TrainPhysics
extends RefCounted
## Dynamique longitudinale 1D : traction limitée par effort et puissance,
## résistance de Davis, pente, freinage, limite de vitesse en courbe.

const G := 9.80665

var profile: VehicleProfile
var passengers: int = 0
## Vitesse signée dans le sens de la cabine. speed reste une norme pour le HUD,
## les portes et les sons ; position conserve le sens réel du déplacement.
var velocity := 0.0
var speed: float:
	get: return absf(velocity)
	set(value): velocity = maxf(value, 0.0)
var adhesion := 0.26 # rail sec, coefficient estimé ; 0,14 représente un rail humide
var driven_mass_fraction := 0.55
var slip_ratio := 0.0
var wheel_slip := false
var wheel_slide := false   # enrayage : freinage de service supérieur à l'adhérence disponible
var sanding := false       # sablage : améliore l'adhérence tant qu'il est actif
const SAND_GAIN := 0.08
var rollback: bool:
	get: return velocity < -0.05
var _slip_time := 0.0
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
	if dt <= 0.0: return
	var m := mass()
	var demand := 0.0
	if notch > 0.0 and power_available and not emergency:
		demand = clampf(notch,0.0,1.0) * minf(profile.max_tractive_effort_n,profile.power_kw*1000.0/maxf(speed,1.0))
	var mu := maxf(effective_adhesion(),0.02) if profile.guidance != "rubber_guided" else maxf(adhesion,0.55)
	var grip := mu * m * G * driven_mass_fraction
	wheel_slip = demand > grip * 1.02
	_slip_time += dt
	var target := clampf((demand-grip)/maxf(grip,1.0),0.0,1.0) if wheel_slip else 0.0
	slip_ratio = move_toward(slip_ratio,target,dt*3.0)
	var traction := minf(demand,grip*(0.90+0.04*sin(_slip_time*19.0))) if wheel_slip else demand
	var brake := (profile.emergency_brake_ms2 if emergency else maxf(-notch,0.0)*profile.service_brake_ms2)*m
	# Frein de service limité par l'adhérence (tous essieux freinés) ; le frein d'urgence
	# conserve les patins électromagnétiques, indépendants de l'adhérence roue-rail.
	var brake_grip := mu * m * G
	wheel_slide = not emergency and speed > 0.3 and brake > brake_grip * 1.02
	if wheel_slide: brake = brake_grip * 0.85
	var drive := traction-m*G*grade
	var drag := resistance(speed)
	var force := drive
	if speed < 0.015:
		if absf(drive) <= brake+drag:
			velocity=0.0; return
		force -= signf(drive)*(brake+drag)
	else:
		force -= signf(velocity)*(brake+drag)
	var next := velocity+force/m*dt
	# Le frein retient la rame à zéro sans la propulser dans l'autre sens.
	if next*velocity < 0.0 and absf(drive) <= brake+drag: next=0.0
	velocity=clampf(next,-profile.max_speed_ms,profile.max_speed_ms)
	position += velocity*dt

## Adhérence disponible, sablage compris.
func effective_adhesion() -> float:
	return minf(adhesion + (SAND_GAIN if sanding else 0.0), 0.30) if sanding else adhesion

func braking_distance(v: float, emergency: bool = false) -> float:
	var a := profile.emergency_brake_ms2 if emergency else minf(profile.service_brake_ms2, effective_adhesion() * G * 0.85)
	return v * v / (2.0 * a)

## Vitesse max en courbe (m/s) pour un rayon donné et une accélération latérale tolérée.
static func curve_speed_limit(radius_m: float, lateral_ms2: float = 0.9) -> float:
	return sqrt(lateral_ms2 * radius_m)
