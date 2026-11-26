class_name LandmarkModels
extends Node3D
## Modèles dédiés détaillés (lot P1) : station Ralliement et abords, cathédrale Saint-Maurice (Angers), trémie de la
## ligne 3 (Nantes). glTF LOD0-2 générés par tools/models/build_all.py, décrits par assets/models/landmark_models.json
## (ancre WGS84 + altitude du jeu, portées de LOD, emprises du décor générique remplacé, obstacles caméra, keepouts).
## Branchement : `LandmarkModels.attach(view)` une fois la vue construite (après les quais et les sites de station).
## Requêtes statiques (avant l'instanciation, pendant la construction de la voie et des quais) :
## `replaces_platform(view, osm_way)`, `replaces_station(view, name)`, `covers_tunnel(view, edge_id, span)`.
## Matériaux : chaque primitive glTF porte l'identifiant d'une fiche data/materials (bibliothèque PbrMaterials) ;
## verres, émissifs et feuillage (cartes alpha) reçoivent un BaseMaterial3D dérivé de la fiche.
## Mobile : LOD0 jamais instancié (LOD1 dès 0 m) pour tenir le budget de triangles.

const MANIFEST := "res://assets/models/landmark_models.json"
const GLASS := {"vitrage": 0.32}
const CARDS := ["lm_feuillage"]

static var _doc: Dictionary = {}
static var _mats: Dictionary = {}

var models: Array = []          # [{id, node, triangles}]
var view: Node

static func manifest() -> Dictionary:
	if _doc.is_empty() and FileAccess.file_exists(MANIFEST):
		var d = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
		if d is Dictionary: _doc = d
	return _doc

## Modèles de la ville d'un réseau dont les fichiers existent.
static func for_view(v) -> Array:
	var out: Array = []
	if v == null or v.net == null or not v.net.meta.has("origin"): return out
	var src := str(v.net.meta.get("source_id", ""))
	for m in manifest().get("models", []):
		if m.get("lot", "") == "P3" and OS.get_environment("TRAMSIM_P3_MONUMENTS") == "0": continue   # planches avant/après
		if str(m.city) == src and ResourceLoader.exists(str(m.lods[1])): out.append(m)
	return out

## Ancre (repère du réseau) : même projection que CityScene / StationIdentityView.
static func anchor(v, m: Dictionary) -> Vector3:
	var origin: Array = v.net.meta.origin
	var ll: Array = m.anchor
	var x := deg_to_rad(float(ll[1]) - float(origin[1])) * CityScene.R * cos(deg_to_rad(float(origin[0])))
	var z := -deg_to_rad(float(ll[0]) - float(origin[0])) * CityScene.R
	return Vector3(x, float(m.anchor_y), z)

static func _ring(a: Vector3, pts: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts: out.append(Vector2(a.x + float(p[0]), a.z + float(p[1])))
	return out

static func replaces_platform(v, osm_way: int) -> bool:
	for m in for_view(v):
		if osm_way in m.get("platform_ways", []).map(func(w): return int(w)): return true
	return false

static func replaces_station(v, name_: String) -> bool:
	for m in for_view(v):
		if m.has("station") and StationIdentityView.key(str(m.station)) == StationIdentityView.key(name_): return true
	return false

## Vrai si l'intervalle de tunnel `span` de l'arête est couvert par une trémie modélisée (l'ouvrage générique est omis).
static func covers_tunnel(v, edge_id: String, span: Array) -> bool:
	for m in for_view(v):
		if not m.has("tunnel_footprint"): continue
		var poly := _ring(anchor(v, m), m.tunnel_footprint)
		var mid: Vector3 = v.pos3(edge_id, (float(span[0]) + float(span[1])) * 0.5)
		if Geometry2D.is_point_in_polygon(Vector2(mid.x, mid.z), poly): return true
	return false

## Instancie les modèles de la ville de la vue (enfant de la vue) ; renvoie le nœud (ou null si aucun modèle).
static func attach(v) -> LandmarkModels:
	var list := for_view(v)
	if list.is_empty(): return null
	var node := LandmarkModels.new(); node.name = "landmark_models"; node.view = v
	v.add_child(node)
	for m in list: node._add(m)
	return node

func _add(m: Dictionary) -> void:
	var a := anchor(view, m)
	var root := Node3D.new(); root.name = str(m.id); root.position = a
	add_child(root)
	var mobile := RenderingServer.get_current_rendering_method() == "mobile"
	var ranges: Array = m.ranges_m
	var tris := 0
	for lod in 3:
		if mobile and lod == 0: continue
		var path := str(m.lods[lod])
		if not ResourceLoader.exists(path): continue
		var scene := load(path) as PackedScene
		if scene == null: continue
		var inst := scene.instantiate() as Node3D
		inst.name = "lod%d" % lod
		root.add_child(inst)
		var begin := 0.0 if (lod == 0 or (mobile and lod == 1)) else float(ranges[lod])
		_setup(inst, begin, float(ranges[lod + 1]), lod == 0 or (mobile and lod == 1))
		if lod == (1 if mobile else 0): tris = int(m.triangles[lod])
	models.append({"id": m.id, "node": root, "triangles": tris})
	var city = view.city
	if city == null: return
	for ring in m.get("replace", []): city.replace_hangar(_ring(a, ring), true)
	for b in m.get("blocks", []):
		if (b[0] as Array).size() >= 3: city.add_building_obstacle(_ring(a, b[0]), a.y + float(b[1]), float(b[2]))
	for k in m.get("keepout", []):
		city.add_keepout(Vector2(a.x + float(k[0][0]), a.z + float(k[0][1])), Vector2(a.x + float(k[1][0]), a.z + float(k[1][1])), float(k[2]))
	if m.has("portal_cut"):
		var pc: Array = m.portal_cut
		city.add_portal_cut(Vector2(a.x + float(pc[0][0]), a.z + float(pc[0][1])), Vector2(a.x + float(pc[1][0]), a.z + float(pc[1][1])), float(pc[2]))

func _setup(n: Node, begin: float, end: float, keep_collision: bool) -> void:
	for c in n.get_children(): _setup(c, begin, end, keep_collision)
	if n is CollisionObject3D and not keep_collision:
		n.queue_free(); return
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		mi.visibility_range_begin = begin
		mi.visibility_range_begin_margin = 10.0 if begin > 0.0 else 0.0
		mi.visibility_range_end = end
		mi.visibility_range_end_margin = 10.0
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
		mi.gi_mode = GeometryInstance3D.GI_MODE_STATIC
		for i in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(i)
			var id := src.resource_name if src != null else ""
			var mat := material(id)
			if mat != null: mi.set_surface_override_material(i, mat)

## Matériau d'une fiche de la bibliothèque (partagé entre modèles).
static func material(id: String) -> Material:
	if _mats.has(id): return _mats[id]
	if id.contains("#"):   # variante teintée « fiche#rrggbb » (ex. pierre patinée des tours)
		var base := id.get_slice("#", 0); var tint := Color.from_string("#" + id.get_slice("#", 1), PbrMaterials.color(base))
		_mats[id] = PbrMaterials.surface(base, {"tint": tint}) if not PbrMaterials.completeness(base).fallback else material(base)
		return _mats[id]
	var e := PbrMaterials.entry(id)
	if e.is_empty(): return null
	var m: Material
	if GLASS.has(id):
		var g := (PbrMaterials.standard(id).duplicate() as StandardMaterial3D)
		g.albedo_color.a = GLASS[id]; g.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
		g.cull_mode = BaseMaterial3D.CULL_DISABLED
		m = g
	elif id in CARDS:
		var f := StandardMaterial3D.new()
		f.albedo_color = Color.WHITE
		var p := str(e.get("card_texture", ""))
		if p != "" and ResourceLoader.exists(p): f.albedo_texture = load(p)
		f.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR; f.alpha_scissor_threshold = 0.45
		f.cull_mode = BaseMaterial3D.CULL_DISABLED; f.roughness = float(e.roughness)
		f.backlight_enabled = true; f.backlight = Color(0.32, 0.4, 0.15)
		f.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		m = f
	elif bool(e.get("emission", false)):
		var s := (PbrMaterials.standard(id).duplicate() as StandardMaterial3D)
		s.emission_enabled = true; s.emission = PbrMaterials.color(id); s.emission_energy_multiplier = float(e.get("emission_energy", 1.0))
		m = s
	else:
		m = PbrMaterials.surface(id) if not PbrMaterials.completeness(id).fallback else PbrMaterials.standard(id)
	_mats[id] = m
	return m

## Triangles instanciés au LOD le plus fin (contrôle de budget).
func lod0_triangles() -> int:
	var t := 0
	for m in models: t += int(m.triangles)
	return t
