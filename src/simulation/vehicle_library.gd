class_name VehicleLibrary
extends RefCounted
## Matériels fournis. Les valeurs listées dans `estimated` ne sont PAS constructeur.

static func citadis_302() -> VehicleProfile:
	var p := VehicleProfile.new()
	p.id = "citadis_302"; p.family = "Alstom Citadis 302"; p.model_family = "citadis_302"
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
	p.id = "citadis_402_aps"; p.family = "Alstom Citadis 402 (APS)"; p.model_family = "citadis_402"
	p.length_m = 43.9; p.empty_mass_kg = 56000.0; p.power_kw = 840.0
	p.capacity = 300; p.supply = "aps"
	return p

static func translohr() -> VehicleProfile:
	var p := citadis_302()
	p.id = "translohr"; p.family = "Translohr (pneus, guidage central)"; p.model_family = "translohr"
	p.length_m = 46.0; p.empty_mass_kg = 52000.0; p.guidance = "rubber_guided"
	p.estimated.append_array(PackedStringArray(["length_m", "capacity"]))
	return p

static func dualis() -> VehicleProfile:
	var p := citadis_302()
	p.id = "citadis_dualis"; p.family = "Alstom Citadis Dualis (tram-train)"; p.model_family = "citadis_dualis"
	p.length_m = 42.0; p.empty_mass_kg = 60000.0; p.power_kw = 1000.0; p.max_tractive_effort_n = 120000.0
	p.max_speed_ms = 100.0 / 3.6; p.capacity = 250
	p.estimated.append_array(PackedStringArray(["length_m", "capacity", "max_speed_ms"]))
	return p

static func tango_express() -> VehicleProfile:
	var p := citadis_302()
	p.id = "tango_express"; p.family = "Stadler Tango (tram express)"; p.model_family = "tango_rhonexpress"
	p.length_m = 32.0; p.empty_mass_kg = 42000.0; p.power_kw = 800.0
	p.max_speed_ms = 100.0 / 3.6; p.capacity = 150
	p.estimated.append_array(PackedStringArray(["length_m", "capacity", "max_speed_ms"]))
	return p

## Matériel jouable à partir d'une entrée de flotte (TramModel.fleet_for, data/rolling_stock) : famille, longueur,
## nom et caractéristiques de research.json ; la livrée suit l'entrée.
static func for_fleet(entry: Dictionary, meta: Dictionary = {}) -> VehicleProfile:
	var fam := TramModel.family_id(str(entry.get("family", "citadis_302")))
	var r := TramModel.research(fam)
	var p: VehicleProfile
	match fam:
		"translohr": p = translohr()
		"citadis_dualis", "avanto": p = dualis()
		"tango_rhonexpress": p = tango_express()
		_: p = citadis_302()
	var est := PackedStringArray(p.estimated)
	var ref_len := float(r.get("length_m", p.length_m))
	if r.has("mass_t"): p.empty_mass_kg = float(r.mass_t) * 1000.0
	if r.has("power_kw"): p.power_kw = float(r.power_kw)
	if r.has("capacity"): p.capacity = int(r.capacity)
	if r.has("max_speed_kmh"): p.max_speed_ms = float(r.max_speed_kmh) / 3.6
	if r.has("width_m"): p.width_m = float(r.width_m)
	p.max_tractive_effort_n = maxf(p.max_tractive_effort_n, p.empty_mass_kg * 2.6)
	for k in r.get("estimated", []):
		var map := {"mass_t": "empty_mass_kg", "power_kw": "power_kw", "capacity": "capacity", "max_speed_kmh": "max_speed_ms", "width_m": "width_m"}
		if map.has(str(k)) and not map[str(k)] in est: est.append(map[str(k)])
	var L := float(entry.get("length", ref_len))
	if ref_len > 0.0 and not is_equal_approx(L, ref_len):
		p.empty_mass_kg *= L / ref_len
		p.capacity = int(p.capacity * L / ref_len)
	p.length_m = L
	p.width_m = float(entry.get("width", p.width_m))
	if str(meta.get("kind", "")) == "tram-train" and fam != "citadis_dualis" and fam != "avanto":
		p.max_speed_ms = maxf(p.max_speed_ms, 80.0 / 3.6)
	if fam == "translohr": p.guidance = "rubber_guided"
	p.id = "%s_%s" % [fam, str(entry.get("name", "")).md5_text().substr(0, 6)]
	p.family = str(entry.get("name", TramModel.plan(fam).get("name", fam)))
	if str(meta.get("source_id", "")) in ["angers", "bordeaux", "orleans", "reims", "tours", "nice"] and fam.begins_with("citadis"):
		p.supply = "hybrid"
	p.model_family = fam
	p.fleet = entry
	p.estimated = est
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
