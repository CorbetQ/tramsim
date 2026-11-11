class_name Materials
extends RefCounted
## Matériaux partagés (un seul ShaderMaterial par usage : moins d'appels de rendu sur mobile).

static var _cache: Dictionary = {}

static func _shader(path: String) -> Shader:
	if not _cache.has(path):
		_cache[path] = load(path)
	return _cache[path]

static func toon() -> ShaderMaterial:
	if not _cache.has("toon"):
		var m := ShaderMaterial.new(); m.shader = _shader("res://src/rendering/shaders/toon.gdshader")
		_cache.toon = m
	return _cache.toon

static func building() -> ShaderMaterial:
	if not _cache.has("building"):
		var m := ShaderMaterial.new(); m.shader = _shader("res://src/rendering/shaders/toon_building.gdshader")
		_cache.building = m
	return _cache.building

static func water() -> ShaderMaterial:
	if not _cache.has("water"):
		var m := ShaderMaterial.new(); m.shader = _shader("res://src/rendering/shaders/water.gdshader")
		_cache.water = m
	return _cache.water

## Caisse de tram : cel shading + contour encré (passe supplémentaire).
static func tram(height: float) -> ShaderMaterial:
	var key := "tram_%.2f" % height
	if not _cache.has(key):
		var m := ShaderMaterial.new(); m.shader = _shader("res://src/rendering/shaders/toon.gdshader")
		var o := ShaderMaterial.new(); o.shader = _shader("res://src/rendering/shaders/outline.gdshader")
		o.set_shader_parameter("axis_center", Vector3(0, height * 0.5, 0))
		m.next_pass = o
		_cache[key] = m
	return _cache[key]
