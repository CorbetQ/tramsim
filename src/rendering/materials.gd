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

static func foliage() -> ShaderMaterial:
	if not _cache.has("foliage"):
		var m := ShaderMaterial.new(); m.shader = _shader("res://src/rendering/shaders/toon.gdshader")
		m.set_shader_parameter("wind_strength", 0.15)
		# palette des arbres prévue pour une double conversion gamma : houppiers ramenés aux verts sombres et
		# désaturés de l'orthophoto IGN (canopée ≈ #3d4a35 à #5a6a48 au soleil)
		m.set_shader_parameter("color_gamma", 1.5); m.set_shader_parameter("saturation", 0.75)
		m.set_shader_parameter("albedo_mul", Vector3(0.75, 0.72, 0.66)); _cache.foliage = m
	return _cache.foliage

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

## Réglage d'exposition des rames : les couleurs de livrée sont mesurées sur photos (teinte déjà éclairée) ;
## face au soleil, soleil + ambiance ≈ 1 restitue la teinte mesurée sans écrêtage, les ombres restent plus profondes et froides.
const TRAM_TONE := {"tram_albedo_day": 0.8, "tram_albedo_night": 0.95, "tram_sun": 0.88, "shade_floor": 0.18,
	"rim_strength": 0.08, "bands": 3.0, "color_gamma": 1.0, "saturation": 1.12}
const PATTERN_IDS := {"swallows": 1, "flowers": 2, "waves": 3, "gilding": 4, "mirror_bands": 5, "leaves": 6}

## Caisse de tram : cel shading + contour encré (passe supplémentaire).
## `pattern` : motif procédural de livrée résolu ({type, colors: Array[Color], y, scale, density, seed}).
static func tram(height: float, pattern: Dictionary = {}) -> ShaderMaterial:
	var pid: int = PATTERN_IDS.get(str(pattern.get("type", "")), 0)
	var key := "tram_%.2f" % height
	if pid > 0: key += "_" + str(hash(var_to_str(pattern)))
	if not _cache.has(key):
		var m := ShaderMaterial.new(); m.shader = _shader("res://src/rendering/shaders/toon.gdshader")
		for k in TRAM_TONE: m.set_shader_parameter(k, TRAM_TONE[k])
		if pid > 0:
			m.set_shader_parameter("tram_pattern", pid)
			var cols: Array = pattern.get("colors", [])
			for i in 4:
				var c: Color = cols[mini(i, cols.size() - 1)] if not cols.is_empty() else Color.WHITE
				m.set_shader_parameter("tram_pat_c%d" % i, c)
			var yr: Array = pattern.get("y", [0.45, 3.0])
			m.set_shader_parameter("tram_pat_box", Vector4(float(yr[0]), float(yr[1]),
				float(pattern.get("scale", 1.0)), float(pattern.get("density", 0.6))))
			m.set_shader_parameter("tram_pat_seed", float(pattern.get("seed", 0.0)))
			m.set_shader_parameter("tram_pat_glass", float(pattern.get("glass", 0.0)))
		var o := ShaderMaterial.new(); o.shader = _shader("res://src/rendering/shaders/outline.gdshader")
		o.set_shader_parameter("axis_center", Vector3(0, height * 0.5, 0))
		m.next_pass = o
		_cache[key] = m
	return _cache[key]
