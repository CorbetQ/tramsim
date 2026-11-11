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

static func citadis_302_hybride() -> VehicleProfile:
	var p := citadis_302()
	p.id = "citadis_302_hybride"; p.family = "Alstom Citadis 302 (caténaire + APS)"
	p.supply = "hybrid"
	return p

static func citadis_402_aps() -> VehicleProfile:
	var p := citadis_302()
	p.id = "citadis_402_aps"; p.family = "Alstom Citadis 402 (APS)"
	p.length_m = 43.9; p.empty_mass_kg = 56000.0; p.power_kw = 840.0
	p.capacity = 300; p.supply = "aps"
	return p

static func translohr() -> VehicleProfile:
	var p := citadis_302()
	p.id = "translohr"; p.family = "Translohr (pneus, guidage central)"
	p.length_m = 46.0; p.empty_mass_kg = 52000.0; p.guidance = "rubber_guided"
	p.estimated.append_array(PackedStringArray(["length_m", "capacity"]))
	return p

static func all() -> Array[VehicleProfile]:
	return [citadis_302(), citadis_302_hybride(), citadis_402_aps(), translohr()]
