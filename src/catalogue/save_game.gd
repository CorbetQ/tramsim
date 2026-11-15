class_name SaveGame
extends RefCounted
## API historique conservée ; aucune version future ou donnée corrompue n'est écrasée.
const DEFAULT_PATH := "user://save.json"
const VERSION := 2
static var last_load_report: Dictionary = {}
static var last_write_error := ""

static func default_data() -> Dictionary:
	return {"version": VERSION, "settings": {"view_distance": 400.0, "traffic": true, "tutorial_done": false},
		"results": [], "free": {}, "migration_log": []}

static func _number(v: Variant) -> bool:
	return (v is int or v is float) and is_finite(float(v))

## Champs connus validés sans supprimer les extensions inconnues.
static func validate_data(d: Variant) -> PackedStringArray:
	var errors := PackedStringArray()
	if not d is Dictionary: return PackedStringArray(["racine non objet"])
	if not _number(d.get("version")) or float(d.version) != floorf(float(d.version)) or int(d.version) < 1:
		return PackedStringArray(["version invalide"])
	for pair in [["settings", TYPE_DICTIONARY], ["results", TYPE_ARRAY], ["free", TYPE_DICTIONARY], ["migration_log", TYPE_ARRAY]]:
		if d.has(pair[0]) and typeof(d[pair[0]]) != pair[1]: errors.append(str(pair[0]) + " : type invalide")
	if not errors.is_empty(): return errors
	var settings: Dictionary = d.get("settings", {})
	for key in ["traffic", "tutorial_done", "ui_sounds"]:
		if settings.has(key) and not settings[key] is bool: errors.append("settings." + key + " : booléen attendu")
	if settings.has("view_distance") and (not _number(settings.view_distance) or float(settings.view_distance) <= 0): errors.append("distance invalide")
	for result in d.get("results", []):
		if not result is Dictionary:
			errors.append("résultat non objet"); continue
		if result.has("success") and not result.success is bool: errors.append("succès invalide")
		if result.has("time_s") and (not _number(result.time_s) or float(result.time_s) < 0): errors.append("durée invalide")
		if result.has("stops") and not result.stops is Array: errors.append("arrêts invalides")
	var free: Dictionary = d.get("free", {})
	for key in ["network", "vehicle", "edge"]:
		if free.has(key) and not free[key] is String: errors.append("free." + key + " : texte attendu")
	if free.has("offset") and (not _number(free.offset) or float(free.offset) < 0): errors.append("abscisse invalide")
	if free.has("direction") and (not _number(free.direction) or float(free.direction) not in [-1.0, 1.0]): errors.append("sens invalide")
	return errors

static func migrate(d: Dictionary) -> Dictionary:
	if _number(d.get("version")) and float(d.version) == floorf(float(d.version)) and int(d.version) > VERSION: return {"ok": false, "future": true, "message": "Sauvegarde créée par une version plus récente ; fichier conservé."}
	var errors := validate_data(d)
	if not errors.is_empty(): return {"ok": false, "message": "; ".join(errors)}
	var out := d.duplicate(true)
	var steps: Array = []
	while int(out.version) < VERSION:
		match int(out.version):
			1:
				if not out.has("migration_log"): out.migration_log = []
				var step := {"id": "save-v1-to-v2", "from": 1, "to": 2}
				out.migration_log.append(step); steps.append(step)
				out.version = 2
			_: return {"ok": false, "message": "Migration absente ; sauvegarde conservée."}
	var base := default_data()
	base.merge(out, true)
	var settings: Dictionary = default_data().settings
	settings.merge(base.settings, true); base.settings = settings
	return {"ok": true, "data": base, "steps": steps}

static func _inspect(path: String) -> Dictionary:
	if not FileAccess.file_exists(path): return {"exists": false, "ok": false}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null: return {"exists": true, "ok": false, "message": "Lecture impossible"}
	var parser := JSON.new()
	var err := parser.parse(f.get_as_text())
	f.close()
	if err != OK: return {"exists": true, "ok": false, "message": "JSON corrompu"}
	if not parser.data is Dictionary: return {"exists": true, "ok": false, "message": "Racine invalide"}
	var result := migrate(parser.data)
	result.exists = true
	return result

static func _copy_atomic(source: String, target: String) -> bool:
	var tmp := target + ".copying"
	if DirAccess.copy_absolute(source, tmp) != OK: return false
	return DirAccess.rename_absolute(tmp, target) == OK

static func _error_report(message: String, status: String) -> Dictionary:
	return {"ok": false, "writable": false, "status": status, "message": message, "data": default_data()}

static func load_checked(path: String = DEFAULT_PATH) -> Dictionary:
	var primary := _inspect(path)
	if primary.get("future", false): return _error_report(primary.message, "future_version")
	for suffix in [".tmp", ".bak"]:
		if _inspect(path + suffix).get("future", false): return _error_report("Copie plus récente ; tous les fichiers sont conservés.", "future_version")
	if primary.ok:
		if not primary.steps.is_empty():
			if not save_data(primary.data, path): return {"ok": false, "writable": false, "status": "migration_write_failed", "message": last_write_error, "data": primary.data}
		return {"ok": true, "writable": true, "status": "migrated" if not primary.steps.is_empty() else "loaded", "steps": primary.steps, "data": primary.data}
	# Une version future dans un checkpoint interrompu ne doit pas être rétrogradée.
	var pending := _inspect(path + ".tmp")
	if pending.get("future", false): return _error_report("Checkpoint plus récent ; fichiers conservés.", "future_version")
	var backup := _inspect(path + ".bak")
	if backup.get("future", false): return _error_report("Copie de sauvegarde plus récente ; fichiers conservés.", "future_version")
	for candidate in [[path + ".tmp", pending], [path + ".bak", backup]]:
		var info: Dictionary = candidate[1]
		if not info.ok: continue
		if primary.exists:
			var quarantine := path + ".corrupt-" + FileAccess.get_sha256(path).substr(0, 12)
			if not FileAccess.file_exists(quarantine) and not _copy_atomic(path, quarantine): return _error_report("Impossible de conserver le fichier corrompu.", "recovery_failed")
		# Copier d'abord les octets sources. Une migration ultérieure crée sa propre .bak.
		if not _copy_atomic(str(candidate[0]), path): return _error_report("Restauration impossible ; fichiers conservés.", "recovery_failed")
		var recovered := load_checked(path)
		recovered.recovered_from = candidate[0]
		if recovered.ok: recovered.status = "recovered"
		return recovered
	if primary.exists or pending.exists or backup.exists: return _error_report("Sauvegarde illisible. Fichiers conservés ; progression de cette session non enregistrée.", "corrupt")
	return {"ok": true, "writable": true, "status": "new", "data": default_data()}

static func load_data(path: String = DEFAULT_PATH) -> Dictionary:
	last_load_report = load_checked(path)
	return last_load_report.data

static func save_data(d: Dictionary, path: String = DEFAULT_PATH) -> bool:
	last_write_error = ""
	if not validate_data(d).is_empty() or int(d.get("version", 0)) != VERSION:
		last_write_error = "Schéma à enregistrer invalide ou non pris en charge."; return false
	for suffix in [".tmp", ".bak"]:
		if _inspect(path + suffix).get("future", false):
			last_write_error = "Écriture refusée : copie issue d’une version future."; return false
	var existing := _inspect(path)
	if existing.exists and not existing.ok:
		last_write_error = "Écriture refusée : fichier existant protégé (corrompu ou version future)."; return false
	if not existing.exists:
		for suffix in [".tmp", ".bak"]:
			var recovery := _inspect(path + suffix)
			if recovery.exists:
				last_write_error = "Une récupération est nécessaire avant l'écriture."; return false
	if existing.exists and not _copy_atomic(path, path + ".bak"):
		last_write_error = "Création de la copie .bak impossible ; original conservé."; return false
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		last_write_error = "Écriture du temporaire impossible."; return false
	f.store_string(JSON.stringify(d)); f.flush(); f.close()
	if not _inspect(tmp).ok:
		last_write_error = "Validation du temporaire impossible ; original conservé."; return false
	if DirAccess.rename_absolute(tmp, path) != OK:
		last_write_error = "Remplacement atomique impossible ; original et temporaire conservés."; return false
	return true

static func add_result(d: Dictionary, network: String, vehicle: String, debrief: Dictionary) -> void:
	var stops: Array = []
	for s in debrief.stops: stops.append({"name": s.name, "result": int(s.result)})
	d.results.append({"network": network, "vehicle": vehicle, "success": debrief.success,
		"reason": debrief.reason, "time_s": debrief.time_s, "stops": stops})

static func store_free(d: Dictionary, s: FreeSession, network: String, vehicle: String) -> void:
	d.free = SaveResume.checkpoint(s, network, vehicle)
