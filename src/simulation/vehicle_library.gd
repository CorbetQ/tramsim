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

static func dualis() -> VehicleProfile:
	var p := citadis_302()
	p.id = "citadis_dualis"; p.family = "Alstom Citadis Dualis (tram-train)"
	p.length_m = 42.0; p.empty_mass_kg = 60000.0; p.power_kw = 1000.0; p.max_tractive_effort_n = 120000.0
	p.max_speed_ms = 100.0 / 3.6; p.capacity = 250
	p.estimated.append_array(PackedStringArray(["length_m", "capacity", "max_speed_ms"]))
	return p

static func tango_express() -> VehicleProfile:
	var p := citadis_302()
	p.id = "tango_express"; p.family = "Stadler Tango (tram express)"
	p.length_m = 32.0; p.empty_mass_kg = 42000.0; p.power_kw = 800.0
	p.max_speed_ms = 100.0 / 3.6; p.capacity = 150
	p.estimated.append_array(PackedStringArray(["length_m", "capacity", "max_speed_ms"]))
	return p

## Matériel jouable à partir d'une entrée de flotte (data/liveries.json) : famille, longueur, livrée.
static func for_fleet(entry: Dictionary, meta: Dictionary = {}) -> VehicleProfile:
	var fam := str(entry.get("family", "citadis"))
	var p: VehicleProfile
	match fam:
		"translohr": p = translohr()
		"dualis": p = dualis()
		"avanto":
			p = dualis(); p.id = "avanto"
		"tango": p = tango_express()
		_: p = citadis_302()
	if fam == "tfs":
		p.width_m = 2.3; p.power_kw = 550.0; p.max_tractive_effort_n = 90000.0; p.capacity = 170
	var L := float(entry.get("length", p.length_m))
	p.empty_mass_kg *= L / p.length_m
	p.capacity = int(p.capacity * L / p.length_m)
	p.length_m = L
	if str(meta.get("kind", "")) == "tram-train" and fam != "dualis" and fam != "avanto":
		p.max_speed_ms = maxf(p.max_speed_ms, 80.0 / 3.6)
	p.id = "%s_%s" % [fam, str(entry.get("name", "")).md5_text().substr(0, 6)]
	p.family = str(entry.get("name", fam))
	p.model_family = fam
	p.fleet = entry
	if not "length_m" in p.estimated: p.estimated.append("length_m")
	return p

## Matériel par défaut cohérent avec le réseau : premier matériel de sa flotte.
static func default_for(meta: Dictionary) -> VehicleProfile:
	if meta.has("source_id"):
		var fl: Array = TramModel.fleet_for(meta)
		if not fl.is_empty():
			var v := for_fleet(fl[0], meta)
			if meta.get("guidance", "steel") == "rubber_guided": v.guidance = "rubber_guided"
			return v
	return _default_generic(meta)

static func _default_generic(meta: Dictionary) -> VehicleProfile:
	if meta.get("guidance", "steel") == "rubber_guided":
		return translohr()
	match str(meta.get("kind", "")):
		"tram-train": return dualis()
		"express": return tango_express()
	return citadis_302()

static func all() -> Array[VehicleProfile]:
	return [citadis_302(), citadis_302_hybride(), citadis_402_aps(), translohr(), dualis(), tango_express()]
