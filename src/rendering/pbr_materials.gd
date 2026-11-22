class_name PbrMaterials
extends RefCounted
## Bibliothèque de matériaux PBR : une fiche JSON par matériau dans `data/materials/`.
## Fiche : id, label, albedo_color (teinte sRGB d'affichage), roughness, metallic, specular, uv_scale_m (taille réelle
## du motif en mètres), normal_scale, world_id (identifiant M_* du shader de décor pbr_world.gdshader), options
## clearcoat, translucency, emission. Textures (P1) : `textures` {albedo, normal, orm} (2048², PC) et
## `textures_mobile` (1024²) désignent les TABLEAUX de textures partagés (assets/textures/pbr/*.jpg importés en
## TextureLayered VRAM compressée) et `layer` la couche du matériau ; `albedo_mean`, `roughness_mean`, `ao_mean`
## (moyennes de la couche, tools/materials/build_texture_arrays.py) servent à moduler la teinte calibrée sans la décaler.
## `texture_from` : emprunt de la couche d'une autre fiche (teinte propre), `texture_contrast` / `texture_saturation`
## (0..1) : amplitude et saturation du détail d'albédo emprunté.
## REPLI DOCUMENTÉ : sans tableau de textures ou sans couche, couleur unie `albedo_color` + normale plate + scalaires.
## `completeness()` dit, par matériau, ce qui est texturé et ce qui est en repli.
##
## API pour les scènes dédiées (stations, trémies, monuments) : `PbrMaterials.surface(id)` renvoie un ShaderMaterial
## (pbr_surface.gdshader) texturé, projection métrique en espace monde (aucune UV1 requise, UV2 libre pour LightmapGI),
## suivant le profil de qualité courant (`set_profile`, appelé par VisualEffects). `surface(id, {"tint": Color,
## "vertex_color": true, "scale": 1.5, "local": true})` pour une variante.
const DIR := "res://data/materials"
const REQUIRED := ["id", "albedo_color", "roughness", "metallic", "uv_scale_m"]

const TEX_PROFILES := {"ultra": {"res": "textures", "quality": 2}, "high": {"res": "textures", "quality": 2},
	"mobile": {"res": "textures_mobile", "quality": 1}, "fallback": {"res": "textures_mobile", "quality": 1}}
## Type d'appareil de façade (CityScene._wall_code, pbr_world) -> fiche : enduit, brique, pierre de taille, andésite,
## tuffeau, enduit du Sud, béton (Perret), grand ensemble, brique et pierre, mur-rideau (sans texture).
const FACADE_IDS := ["facade_enduit", "facade_brique", "pierre_taille", "pierre_taille", "facade_tuffeau", "facade_enduit",
	"beton_banche", "beton_banche", "facade_brique", ""]
const SURFACE_SHADER := "res://src/rendering/shaders/pbr_surface.gdshader"
const N_IDS := 16      # identifiants de matériau du décor (pbr_world)
const N_LAYERS := 24   # couches de texture possibles (pbr_textures.gdshaderinc)

static var _lib: Dictionary = {}
static var _std: Dictionary = {}
static var _surf: Dictionary = {}
static var _arrays: Dictionary = {}
static var profile := "high"

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

## Tableau de textures d'un emplacement (albedo, normal, orm) pour le jeu `res` (textures / textures_mobile).
static func _tex(e: Dictionary, slot: String, res := "textures") -> TextureLayered:
	var p := str(e.get(res, {}).get(slot, ""))
	if p == "" or not e.has("layer"): return null
	if not _arrays.has(p):
		_arrays[p] = load(p) as TextureLayered if ResourceLoader.exists(p) else null
	var t: TextureLayered = _arrays[p]
	if t == null or int(e.layer) < 0 or int(e.layer) >= t.get_layers(): return null
	return t

## Couche de texture du matériau (-1 : repli).
## `texture_from` : la fiche emprunte la couche d'une autre fiche (même famille, teinte propre) ; `texture_contrast`
## (0..1) atténue le détail d'albédo emprunté (inox, zinc, peintures claires).
static func layer_of(id: String) -> int:
	var e := entry(id)
	if e.has("texture_from"): return layer_of(str(e.texture_from))
	return int(e.layer) if completeness(id).fallback == false else -1

## Textures présentes / en repli : {albedo, normal, orm, mobile: bool, fallback: bool (au moins une en repli)}.
static func completeness(id: String) -> Dictionary:
	var e := entry(id)
	if e.has("texture_from") and entry(str(e.texture_from)).has("layer"): return completeness(str(e.texture_from))
	var r := {"albedo": _tex(e, "albedo") != null, "normal": _tex(e, "normal") != null, "orm": _tex(e, "orm") != null,
		"mobile": _tex(e, "albedo", "textures_mobile") != null and _tex(e, "normal", "textures_mobile") != null and _tex(e, "orm", "textures_mobile") != null}
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

## Matériau standard (couleur unie + scalaires de la fiche) : repli sans shader, pour les cas où un BaseMaterial3D est
## exigé. Les surfaces texturées passent par `surface(id)`.
static func standard(id: String) -> BaseMaterial3D:
	if _std.has(id): return _std[id]
	var e := entry(id)
	var m := StandardMaterial3D.new()
	m.albedo_color = color(id)
	m.roughness = float(e.get("roughness", 0.8))
	m.metallic = float(e.get("metallic", 0.0))
	m.metallic_specular = float(e.get("specular", 0.5))
	if float(e.get("clearcoat", 0.0)) > 0.0:
		m.clearcoat_enabled = true; m.clearcoat = float(e.clearcoat); m.clearcoat_roughness = 0.25
	if bool(e.get("emission", false)):
		m.emission_enabled = true; m.emission = m.albedo_color
	_std[id] = m
	return m

## Surface texturée (pbr_surface.gdshader) d'un matériau de la bibliothèque. `opts` : tint (Color, défaut
## albedo_color), vertex_color (bool : multiplie par la couleur de sommet), scale (agrandit le motif), local (bool :
## projection dans le repère de l'objet, pour les objets mobiles). Partagée par (id, opts) : peu d'appels de rendu.
static func surface(id: String, opts: Dictionary = {}) -> ShaderMaterial:
	var key := id + var_to_str(opts)
	if _surf.has(key): return _surf[key]
	var e := entry(id)
	var m := ShaderMaterial.new()
	m.shader = load(SURFACE_SHADER)
	var tint: Color = opts.get("tint", color(id))
	m.set_shader_parameter("albedo_tint", Vector3(tint.r, tint.g, tint.b))
	m.set_shader_parameter("use_vertex_color", bool(opts.get("vertex_color", false)))
	m.set_shader_parameter("surface_roughness", float(e.get("roughness", 0.8)))
	m.set_shader_parameter("surface_metallic", float(e.get("metallic", 0.0)))
	m.set_shader_parameter("surface_specular", float(e.get("specular", 0.5)))
	m.set_shader_parameter("uv_scale_mul", float(opts.get("scale", 1.0)))
	m.set_shader_parameter("local_space", bool(opts.get("local", false)))
	m.set_shader_parameter("layer", layer_of(id))
	m.set_shader_parameter("pbr_tex_contrast", float(e.get("texture_contrast", 1.0)))
	m.set_shader_parameter("pbr_tex_saturation", float(e.get("texture_saturation", 1.0)))
	_apply_textures(m)
	_surf[key] = m
	return m

## Profil de qualité (VisualEffects) : 2048² + anti-répétition (Ultra, Haut), 1024² un échantillon (Mobile, Repli).
## Réapplique aux matériaux partagés déjà créés.
static func set_profile(p: String) -> void:
	if not TEX_PROFILES.has(p): p = "fallback"
	profile = p
	if Materials._cache.has("building"): _apply_textures(Materials._cache.building)
	for m in _surf.values(): _apply_textures(m)

## Tableaux et paramètres de texture du profil courant (communs à pbr_world et pbr_surface).
static func _apply_textures(mat: ShaderMaterial) -> void:
	var tp: Dictionary = TEX_PROFILES[profile]
	var mean := PackedVector3Array(); mean.resize(N_LAYERS)
	var info := PackedVector4Array(); info.resize(N_LAYERS)
	var any := ""
	var sets := {}
	for e in library().values():
		if not e.has("layer"): continue
		var i := int(e.layer)
		if i < 0 or i >= N_LAYERS: continue
		var c := Color.from_string(str(e.get("albedo_mean", e.albedo_color)), Color(0.5, 0.5, 0.5))
		mean[i] = Vector3(c.r, c.g, c.b)
		info[i] = Vector4(float(e.uv_scale_m), float(e.get("roughness_mean", e.roughness)), float(e.get("ao_mean", 1.0)), float(e.get("normal_scale", 1.0)))
		if not completeness(str(e.id)).fallback: any = str(e.id)
	var q := 0
	if any != "":
		var e := entry(any)
		for slot in ["albedo", "normal", "orm"]:
			var t := _tex(e, slot, tp.res)
			if t == null: t = _tex(e, slot)
			sets[slot] = t
		q = int(tp.quality) if sets.albedo != null and sets.normal != null and sets.orm != null else 0
	if q > 0:
		mat.set_shader_parameter("pbr_albedo_tex", sets.albedo)
		mat.set_shader_parameter("pbr_normal_tex", sets.normal)
		mat.set_shader_parameter("pbr_orm_tex", sets.orm)
	mat.set_shader_parameter("pbr_tex_quality", q)
	mat.set_shader_parameter("pbr_layer_mean", mean)
	mat.set_shader_parameter("pbr_layer_info", info)

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
	var r := PackedFloat32Array(); r.resize(N_IDS); r.fill(0.9)
	var m := PackedFloat32Array(); m.resize(N_IDS); m.fill(0.0)
	var s := PackedFloat32Array(); s.resize(N_IDS); s.fill(0.5)
	var l := PackedInt32Array(); l.resize(N_IDS); l.fill(-1)
	for e in library().values():
		if not e.has("world_id"): continue
		var i := int(e.world_id)
		if i < 0 or i >= N_IDS: continue
		r[i] = float(e.roughness); m[i] = float(e.metallic); s[i] = float(e.get("specular", 0.5))
		if not (i == 7): l[i] = layer_of(str(e.id))   # façades : par type d'appareil (facade_layer)
	var f := PackedInt32Array(); f.resize(FACADE_IDS.size())
	for k in FACADE_IDS.size(): f[k] = layer_of(FACADE_IDS[k]) if FACADE_IDS[k] != "" else -1
	return {"mat_roughness": r, "mat_metallic": m, "mat_specular": s, "mat_layer": l, "facade_layer": f}

static func apply_world(mat: ShaderMaterial) -> void:
	var a := world_arrays()
	for k in a: mat.set_shader_parameter(k, a[k])
	_apply_textures(mat)
