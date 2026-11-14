class_name CityPreload
extends Node
## Disk reads, JSON parsing and graph preparation happen before the launch button is enabled.
signal completed(city: String, error: String)
var city := ""
var ready_city := ""
var error := ""
var _task := -1
var _job: Dictionary = {}
var _networks: Dictionary = {}
var _bundle_city := ""
var _bundle_files: Dictionary = {}
var _bundle_documents: Dictionary = {}
var _scene: CityScene
var _audio_assets: Array[Resource] = []

func request(selected: String) -> void:
	city = selected
	error = ""
	if ready_city == city: return
	if _task < 0: _launch()

func is_ready(selected: String) -> bool:
	return ready_city == selected and not _networks.is_empty()

func network(path: String) -> NetworkLoader:
	return _networks.get(path)

func take_scene(origin: Array) -> CityScene:
	var result := _scene
	_scene = null
	if result != null: result.align_to_origin(origin)
	return result

func _launch() -> void:
	_job = {"city": city, "entries": NetworkRegistry.entries().filter(func(e): return e.city == city), "cached_files": _bundle_files if _bundle_city == city else {}, "cached_documents": _bundle_documents if _bundle_city == city else {}}
	_task = WorkerThreadPool.add_task(_load.bind(_job), false, "city_data_preload")

static func _read(job: Dictionary, path: String) -> PackedByteArray:
	if job.cached_files.has(path): return job.cached_files[path]
	return FileAccess.get_file_as_bytes(path)

static func _parse(job: Dictionary, path: String, raw: PackedByteArray) -> Variant:
	if job.cached_documents.has(path): return job.cached_documents[path]
	return JSON.parse_string(raw.get_string_from_utf8())

static func _load(job: Dictionary) -> void:
	var files := {}; var documents := {}; var networks := {}; var sources := {}
	for entry in job.entries:
		var path := str(entry.path)
		if documents.has(path): continue
		var raw := _read(job, path)
		var data: Variant = _parse(job, path, raw)
		if not data is Dictionary: job.error = "Réseau illisible : " + path; return
		files[path] = raw; documents[path] = data
		sources[str(data.get("source_id", ""))] = true
	if files.is_empty(): job.error = "Aucune donnée disponible pour " + str(job.city); return
	var paths: Array[String] = []
	for source in sources:
		if source == "": continue
		for directory in ["scenes", "free", "stations", "station_models", "platforms", "depots", "missions", "operations"]:
			var folder: String = "res://data/" + str(directory)
			if not DirAccess.dir_exists_absolute(folder): continue
			for filename in DirAccess.get_files_at(folder):
				if filename == source + ".json" or filename == source + ".bin" or filename.begins_with(source + "_"):
					if not filename.ends_with(".import"): paths.append(folder + "/" + filename)
	for path in ["res://data/city_styles.json", "res://data/city_identity.json", "res://data/crossings.json", "res://data/landmarks.json", "res://data/audio/families.json"]:
		if FileAccess.file_exists(path): paths.append(path)
	for path in paths:
		if files.has(path): continue
		var raw := _read(job, path)
		files[path] = raw
		if path.ends_with(".json"):
			var data: Variant = _parse(job, path, raw)
			if data == null: job.error = "Données invalides : " + path; return
			documents[path] = data
	for path in documents:
		if not (path.begins_with("res://data/networks/") or path.begins_with("res://data/free/")): continue
		var n := NetworkLoader.new()
		var errors := n.load_data(documents[path].duplicate(true))
		if not errors.is_empty(): job.error = "Réseau invalide : " + path + " · " + str(errors); return
		networks[path] = n
	job.files = files; job.documents = documents; job.networks = networks

func _process(_dt: float) -> void:
	if _task < 0: return
	if not WorkerThreadPool.is_task_completed(_task): return
	WorkerThreadPool.wait_for_task_completion(_task); _task = -1
	var job := _job; _job = {}
	if job.city != city:
		if is_ready(city): completed.emit(city, "")
		else: _launch()
		return
	error = str(job.get("error", ""))
	if error == "":
		_bundle_city = city; _bundle_files = job.files; _bundle_documents = job.documents
		CityDataStore.install(job.files, job.documents)
		_networks = job.networks
		if _audio_assets.is_empty():
			_audio_assets.append(load("res://src/rendering/transition_noise.tres"))
			for key in TramAudio.LOOPS.keys() + TramAudio.SHOTS.keys() + ["gong"]:
				var stream := TramAudio.load_stream(key, key in TramAudio.LOOPS)
				if stream != null: _audio_assets.append(stream)
			var families: Dictionary = CityDataStore.document("res://data/audio/families.json")
			for bank in families.get("banks", {}).values():
				for resource_path in bank.get("streams", {}).values():
					var stream := TramAudio.stream_path("res://data/audio/" + str(resource_path), true)
					if stream != null: _audio_assets.append(stream)
			TramAudio.profile_for("citadis_302")
			for family in TramModel.plan_ids(): TramModel.plan(family)
			StockCatalog.entries()
		if is_instance_valid(_scene): _scene.free()
		_scene = null
		var n: NetworkLoader = _networks.values()[0]
		var source := str(n.meta.get("source_id", ""))
		if CityScene.available(source):
			_scene = CityScene.new()
			if not _scene.open(source, n.meta.origin):
				_scene.free(); _scene = null
		ready_city = city
	else:
		ready_city = ""; _networks.clear()
	completed.emit(city, error)

func invalidate() -> void:
	ready_city = ""; _networks.clear()

func _exit_tree() -> void:
	if _task >= 0: WorkerThreadPool.wait_for_task_completion(_task)
	if is_instance_valid(_scene): _scene.free()
