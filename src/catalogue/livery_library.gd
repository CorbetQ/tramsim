class_name LiveryLibrary
extends RefCounted
## Named user paint schemes. The base variant remains the authority for geometry,
## guidance, power and acoustics. SaveGame supplies atomic writes and recovery.
static var path := "user://liveries.json"
static var last_error := ""
static var _loaded := false
static var _data: Dictionary = {}
static var _writable := true
const ZONES := ["base", "front", "door", "roof", "skirt", "window"]

static func reset_cache() -> void:
	_loaded = false; _data = {}; last_error = ""

static func _load() -> void:
	if _loaded: return
	_loaded = true
	var report := SaveGame.load_checked(path)
	_data = report.data; _writable = report.get("writable", false)
	if not _writable: last_error = str(report.get("message", "Bibliothèque non modifiable"))
	if not _data.get("liveries", []) is Array:
		_writable = false
		last_error = "Bibliothèque invalide : fichier conservé."

static func clean(raw: Variant) -> Dictionary:
	if not raw is Dictionary or raw.is_empty(): return {}
	var version:Variant=raw.get("version",1)
	if not SaveGame._number(version) or float(version)!=floorf(float(version)) or not int(version) in [1,2]:return {}
	var base := str(raw.get("base_variant", ""))
	if StockCatalog.find(base).is_empty(): return {}
	var colors: Variant = raw.get("colors", {})
	if not colors is Dictionary: return {}
	var result := {"version":2, "id":str(raw.get("id", "")).substr(0,80), "base_variant":base,
		"name":str(raw.get("name", "Ma livrée")).strip_edges().substr(0,48), "label":str(raw.get("label", "")).substr(0,24), "colors":{}, "bands":[],"parts":{}}
	for zone in ZONES:
		var color := str(colors.get(zone, ""))
		if color.length() != 7 or not color.begins_with("#") or not Color.html_is_valid(color): return {}
		result.colors[zone] = Color(color).to_html(false).insert(0,"#")
	var bands: Variant = raw.get("bands", [])
	if not bands is Array or bands.size() > 2: return {}
	for band in bands:
		if not band is Dictionary: return {}
		var y: Variant = band.get("y", 0.7); var width: Variant = band.get("width", 0.15)
		if not SaveGame._number(y) or not SaveGame._number(width): return {}
		var color := str(band.get("color", ""))
		if color.length() != 7 or not Color.html_is_valid(color): return {}
		result.bands.append({"enabled":bool(band.get("enabled", true)), "y":clampf(float(y),0.15,3.0), "width":clampf(float(width),0.03,0.6), "color":color})
	if result.name == "": result.name = "Ma livrée"
	var parts:Variant=raw.get("parts",{})
	if not parts is Dictionary or parts.size()>32:return {}
	for key in parts:
		if not str(key) in ["end_a","end_b","powered","suspended"] and not (str(key).begins_with("caisse_") and str(key).trim_prefix("caisse_").is_valid_int()):return {}
		if not parts[key] is Dictionary:return {}
		var nested:=clean({"base_variant":base,"colors":parts[key].get("colors",result.colors),"bands":parts[key].get("bands",result.bands)})
		if nested.is_empty():return {}
		result.parts[key]={"colors":nested.colors,"bands":nested.bands}
	return result

static func compatible(design: Dictionary, variant: String) -> bool:
	var source:=StockCatalog.find(str(design.get("base_variant","")));var target:=StockCatalog.find(variant)
	return not source.is_empty() and not target.is_empty() and StockCatalog.group_id(source)==StockCatalog.group_id(target)

static func for_part(design: Dictionary, entry: Dictionary, index: int) -> Dictionary:
	if design.is_empty() or index<0:return design
	var result:=design.duplicate(true)
	var parts:Dictionary=design.get("parts",{})
	var role:=TramParts.role(entry,index)
	var patch:Dictionary=parts.get("caisse_%d"%index,parts.get(role,{}))
	if not patch.is_empty():result.colors=patch.colors.duplicate(true);result.bands=patch.bands.duplicate(true)
	result["_scheme_key"]=JSON.stringify(design).sha256_text()
	return result

static func create(entry: Dictionary) -> Dictionary:
	var liv := TramModel.livery_for(StockCatalog.origin_meta(entry), entry)
	var colors := {}
	for zone in ZONES: colors[zone] = "#" + (liv[zone] as Color).to_html(false)
	return {"version":2, "id":"", "base_variant":entry.id, "name":"Ma livrée", "label":"", "colors":colors,"parts":{},
		"bands":[{"enabled":true,"y":0.65,"width":0.18,"color":"#18baa6"},{"enabled":false,"y":2.6,"width":0.12,"color":"#f0b34e"}]}

static func designs(base_variant: String) -> Array:
	_load()
	var result: Array = []
	if not _data.get("liveries", []) is Array: return result
	for raw in _data.get("liveries", []):
		var design := clean(raw)
		if not design.is_empty() and compatible(design,base_variant): result.append(design)
	return result

static func save_design(raw: Dictionary, as_copy := false) -> Dictionary:
	_load(); last_error = ""
	if not _writable: last_error = "Bibliothèque protégée : fichier conservé."; return {}
	var design := clean(raw)
	if design.is_empty(): last_error = "Livrée invalide."; return {}
	if design.id == "" or as_copy: design.id = "paint_%d_%x" % [Time.get_unix_time_from_system(), randi()]
	var rows: Array = _data.get("liveries", []).duplicate(true)
	rows = rows.filter(func(row): return not row is Dictionary or str(row.get("id", "")) != design.id)
	if rows.size() >= 100: last_error = "Limite de 100 livrées atteinte."; return {}
	rows.append(design)
	var candidate := _data.duplicate(true); candidate.liveries = rows
	if not SaveGame.save_data(candidate, path): last_error = SaveGame.last_write_error; return {}
	_data = candidate
	return design.duplicate(true)

static func remove(id: String) -> bool:
	_load()
	if not _writable: last_error = "Bibliothèque protégée : fichier conservé."; return false
	var candidate := _data.duplicate(true)
	candidate.liveries = (_data.get("liveries", []) as Array).filter(func(row): return not row is Dictionary or str(row.get("id", "")) != id)
	if not SaveGame.save_data(candidate, path): last_error = SaveGame.last_write_error; return false
	_data = candidate
	return true

static func apply(livery: Dictionary, raw: Dictionary) -> Dictionary:
	var design := clean(raw)
	if design.is_empty() or not compatible(design,str(livery.get("variant_id", ""))): return livery
	var result := livery.duplicate(true)
	result.custom_livery = design
	for zone in ZONES: result[zone] = Color(design.colors[zone])
	result.elements = []
	result.erase("pattern")
	for band in design.bands:
		if band.enabled: result.elements.append({"type":"band","zone":"sides+front","y":[band.y,band.y+band.width],"colors":[Color(band.color)]})
	return result
