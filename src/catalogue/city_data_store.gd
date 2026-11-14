class_name CityDataStore
extends RefCounted
## Only the selected city's bundle is retained. Bytes are copy-on-write; callers must not mutate JSON.
static var _bytes: Dictionary = {}
static var _json: Dictionary = {}
static var _lock := Mutex.new()
static var disk_reads := 0

static func install(files: Dictionary, documents: Dictionary) -> void:
	_lock.lock()
	_bytes = files; _json = documents
	_lock.unlock()

static func bytes(path: String) -> PackedByteArray:
	_lock.lock()
	var hit: bool = _bytes.has(path)
	var value: PackedByteArray = _bytes.get(path, PackedByteArray())
	if not hit: disk_reads += 1
	_lock.unlock()
	return value if hit else FileAccess.get_file_as_bytes(path)

static func document(path: String) -> Variant:
	_lock.lock()
	var hit: bool = _json.has(path)
	var value: Variant = _json.get(path)
	_lock.unlock()
	return value if hit else JSON.parse_string(bytes(path).get_string_from_utf8())
