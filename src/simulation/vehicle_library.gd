class_name VehicleLibrary
extends RefCounted
## Matériels fournis. Les valeurs listées dans `estimated` ne sont PAS constructeur.

static func citadis_302() -> VehicleProfile:
	var p := VehicleProfile.new()
	p.id = "citadis_302"; p.family = "Alstom Citadis 302"
	p.length_m = 32.0; p.width_m = 2.4; p.empty_mass_kg = 41000.0
	p.power_kw = 720.0; p.max_tractive_effort_n = 110000.0
	p.max_speed_ms = 70.0 / 3.6; p.capacity = 200; p.supply = "overhead"
	p.estimated = PackedStringArray(["empty_mass_kg", "power_kw", "max_tractive_effort_n", "service_brake_ms2", "emergency_brake_ms2"])
	return p
