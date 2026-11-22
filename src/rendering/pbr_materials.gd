class_name PbrMaterials
extends RefCounted
## Bibliothèque de matériaux PBR (refonte P0) : une fiche JSON par matériau dans `data/materials/`.
## Fiche : id, label, albedo_color (teinte sRGB d'affichage), roughness, metallic, specular, textures {albedo, normal,
## orm} (chemins res://, vides tant que P1 n'a pas livré les textures), uv_scale_m (taille d'un motif en mètres),
## normal_scale, world_id (identifiant M_* du shader de décor pbr_world.gdshader), options clearcoat, translucency,
## emission.
## REPLI DOCUMENTÉ : une texture absente (chemin vide ou fichier manquant) est remplacée par la couleur unie
## `albedo_color` (albédo), une normale plate (normal map désactivée) et les scalaires roughness/metallic à la place
## de l'ORM. `completeness()` dit, par matériau, ce qui est texturé et ce qui est en repli.

const DIR := "res://data/materials"
const REQUIRED := ["id", "albedo_color", "roughness", "metallic", "uv_scale_m"]

static var _lib: Dictionary = {}
static var _std: Dictionary = {}

static func library() -> Dictionary:
	if not _lib.is_empty(): return _lib
	var d := DirAccess.open(DIR)
	if d == null: return _lib
	for f in d.get_files():
		var name := f.trim_suffix(".remap")
		if not name.ends_with(".json"): continue
		var data = JSON.parse_string(FileAccess.get_file_as_string(DIR + "/" + name))
		if data is Dictionary and data.has("id"): _lib[str(data.id)] = data
	return _lib

static func entry(id: String) -> Dictionary:
	return library().get(id, {})

static func color(id: String, fallback := Color(0.5, 0.5, 0.5)) -> Color:
	return Color.from_string(str(entry(id).get("albedo_color", "")), fallback)

static func _tex(e: Dictionary, slot: String) -> Texture2D:
	var p := str(e.get("textures", {}).get(slot, ""))
	if p == "" or not ResourceLoader.exists(p): return null
	return load(p) as Texture2D

## Textures présentes / en repli : {albedo, normal, orm: bool, fallback: bool (au moins une en repli)}.
static func completeness(id: String) -> Dictionary:
	var e := entry(id)
	var r := {"albedo": _tex(e, "albedo") != null, "normal": _tex(e, "normal") != null, "orm": _tex(e, "orm") != null}
	r.fallback = not (r.albedo and r.normal and r.orm)
	return r

## Fiche incomplète (champs obligatoires) : liste des erreurs (vide = valide).
static func validate(e: Dictionary) -> Array:
	var errs: Array = []
	for k in REQUIRED:
		if not e.has(k): errs.append("%s : champ %s absent" % [e.get("id", "?"), k])
	if e.has("roughness") and (float(e.roughness) < 0.0 or float(e.roughness) > 1.0): errs.append("%s : rugosité hors [0,1]" % e.id)
	if e.has("metallic") and (float(e.metallic) < 0.0 or float(e.metallic) > 1.0): errs.append("%s : métal hors [0,1]" % e.id)
	if e.has("albedo_color") and not Color.html_is_valid(str(e.albedo_color)): errs.append("%s : couleur invalide" % e.id)
	return errs

## Matériau standard (ORMMaterial3D si une texture ORM existe), triplanaire monde à l'échelle `uv_scale_m`.
static func standard(id: String) -> BaseMaterial3D:
	if _std.has(id): return _std[id]
	var e := entry(id)
	var orm := _tex(e, "orm")
	var m: BaseMaterial3D = ORMMaterial3D.new() if orm != null else StandardMaterial3D.new()
	m.albedo_color = color(id)
	m.roughness = float(e.get("roughness", 0.8))
	m.metallic = float(e.get("metallic", 0.0))
	m.metallic_specular = float(e.get("specular", 0.5))
	var alb := _tex(e, "albedo")
	if alb != null: m.albedo_texture = alb; m.albedo_color = Color.WHITE
	var nrm := _tex(e, "normal")
	if nrm != null:
		m.normal_enabled = true; m.normal_texture = nrm; m.normal_scale = float(e.get("normal_scale", 1.0))
	if orm != null: (m as ORMMaterial3D).orm_texture = orm
	if alb != null or nrm != null or orm != null:
		m.uv1_triplanar = true; m.uv1_world_triplanar = true
		m.uv1_scale = Vector3.ONE / maxf(float(e.get("uv_scale_m", 1.0)), 0.01)
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	if float(e.get("clearcoat", 0.0)) > 0.0:
		m.clearcoat_enabled = true; m.clearcoat = float(e.clearcoat); m.clearcoat_roughness = 0.25
	if bool(e.get("emission", false)):
		m.emission_enabled = true; m.emission = m.albedo_color
	_std[id] = m
	return m

## Scalaires PBR d'un matériau objet (pbr_object.gdshader).
static func apply_object(mat: ShaderMaterial, id: String) -> void:
	var e := entry(id)
	if e.is_empty(): return
	mat.set_shader_parameter("surface_roughness", float(e.roughness))
	mat.set_shader_parameter("surface_metallic", float(e.metallic))
	mat.set_shader_parameter("surface_specular", float(e.get("specular", 0.5)))
	mat.set_shader_parameter("surface_clearcoat", float(e.get("clearcoat", 0.0)))
	mat.set_shader_parameter("translucency", float(e.get("translucency", 0.0)))

## Tableaux PBR du shader de décor (index = identifiant M_* de pbr_world.gdshader).
static func world_arrays() -> Dictionary:
	var r := PackedFloat32Array(); r.resize(10); r.fill(0.9)
	var m := PackedFloat32Array(); m.resize(10); m.fill(0.0)
	var s := PackedFloat32Array(); s.resize(10); s.fill(0.5)
	for e in library().values():
		if not e.has("world_id"): continue
		var i := int(e.world_id)
		if i < 0 or i >= 10: continue
		r[i] = float(e.roughness); m[i] = float(e.metallic); s[i] = float(e.get("specular", 0.5))
	return {"mat_roughness": r, "mat_metallic": m, "mat_specular": s}

static func apply_world(mat: ShaderMaterial) -> void:
	var a := world_arrays()
	for k in a: mat.set_shader_parameter(k, a[k])
