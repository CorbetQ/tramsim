class_name VehicleProfile
extends Resource
## Fiche matériel. `estimated` liste les champs non issus du constructeur.

@export var id: String = ""
@export var family: String = ""
@export var model_family: String = ""   # plan 3D : data/rolling_stock/plans/<id>.json
@export var variant_id: String = ""
@export var fictional := false
@export var gauge_mm := 1435
@export var origin_city := ""
var fleet: Dictionary = {}                # entrée de flotte (livrée) si matériel du réseau
@export var length_m: float = 30.0
@export var width_m: float = 2.4
@export var empty_mass_kg: float = 40000.0
@export var power_kw: float = 500.0
@export var max_tractive_effort_n: float = 100000.0
@export var max_speed_ms: float = 19.4          # 70 km/h
@export var service_brake_ms2: float = 1.2
@export var emergency_brake_ms2: float = 2.8
@export var capacity: int = 200
@export_enum("overhead", "aps", "third_rail", "hybrid", "battery") var supply: String = "overhead"
@export_enum("steel", "rubber_guided") var guidance: String = "steel"
@export var electric_modes := PackedStringArray()
@export var estimated: PackedStringArray = []

func loaded_mass(passengers: int, kg_per_pax: float = 70.0) -> float:
	return empty_mass_kg + passengers * kg_per_pax

func power_modes() -> PackedStringArray:
	if not electric_modes.is_empty(): return electric_modes.duplicate()
	if supply == "hybrid": return PackedStringArray(["overhead", "aps"])
	return PackedStringArray([supply])
