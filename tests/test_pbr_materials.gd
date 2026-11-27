extends SceneTree
## Refonte P0 (docs/CDC_REFONTE_VISUELLE.md §7.2) : plus aucun cel shading, contour encré ni post-traitement d'arêtes ;
## matériaux PBR complets ou en repli documenté (PbrMaterials) ; chaîne de couleur unique.
## Sans rendu (--headless).
const SCAN_DIRS := ["res://src", "res://tests/audit", "res://tools/qa"]
## Mots interdits dans le code de rendu (shaders, scripts, scènes) : vestiges du style cel / toon / outline.
const FORBIDDEN := ["toon.gdshader", "toon_building", "cel.gdshaderinc", "cel_light", "cel_steps", "cel_layer_clip",
	"outline.gdshader", "edges.gdshader", "Materials.toon(", "day_night.edges", "day.edges"]
## Shaders autorisés en `unshaded` (ni décor ni objet éclairé) : ciel de transition, halo de lampadaire, effet de vitesse.
const UNSHADED_OK := ["halo.gdshader", "speed.gdshader", "transition_clouds.gdshader", "windscreen_rain.gdshader"]   # gouttes : réfraction de l'image (P4)

var fails := 0

func check(c: bool, m: String) -> void:
	if c: print("ok: ", m)
	else: fails += 1; printerr("ECHEC: ", m)

func _files(dir: String, out: Array) -> void:
	var d := DirAccess.open(dir)
	if d == null: return
	for f in d.get_files():
		if f.get_extension() in ["gd", "gdshader", "gdshaderinc", "tscn", "tres"]: out.append(dir.path_join(f))
	for sub in d.get_directories():
		if not sub.begins_with("."): _files(dir.path_join(sub), out)

func _init() -> void:
	var files: Array = []
	for d in SCAN_DIRS: _files(d, files)
	var hits: Array = []
	var lights: Array = []
	var unshaded: Array = []
	for f in files:
		if f.ends_with("test_pbr_materials.gd"): continue
		var s := FileAccess.get_file_as_string(f)
		for w in FORBIDDEN:
			if s.contains(w): hits.append("%s : %s" % [f, w])
		if f.get_extension() in ["gdshader", "gdshaderinc"]:
			if s.contains("void light()"): lights.append(f)
			if s.contains("unshaded") and s.contains("shader_type spatial") and not f.get_file() in UNSHADED_OK: unshaded.append(f)
	check(files.size() > 50, "%d fichiers de rendu analysés" % files.size())
	check(hits.is_empty(), "aucun vestige toon/cel/outline/edges : %s" % [hits])
	check(lights.is_empty(), "aucun light() personnalisé (éclairage PBR du moteur) : %s" % [lights])
	check(unshaded.is_empty(), "aucun shader spatial non éclairé hors liste blanche : %s" % [unshaded])
	for old in ["toon.gdshader", "toon_building.gdshader", "cel.gdshaderinc", "outline.gdshader", "edges.gdshader"]:
		check(not FileAccess.file_exists("res://src/rendering/shaders/" + old), "shader retiré : " + old)

	# Bibliothèque de matériaux
	var lib := PbrMaterials.library()
	check(lib.size() >= 12, "bibliothèque PBR : %d fiches dans data/materials" % lib.size())
	var errs: Array = []
	var fallback: Array = []
	for id in lib:
		errs.append_array(PbrMaterials.validate(lib[id]))
		var c := PbrMaterials.completeness(id)
		if c.fallback:
			fallback.append(id)
			# repli documenté : la fiche dit pourquoi elle n'a pas (encore) de textures
			if str(lib[id].get("source", "")).find("repli") < 0: errs.append("%s : repli non documenté" % id)
		var m := PbrMaterials.standard(id)
		if not is_equal_approx(m.roughness, float(lib[id].roughness)) or not is_equal_approx(m.metallic, float(lib[id].metallic)): errs.append("%s : scalaires PBR non appliqués" % id)
		if c.fallback and m.albedo_texture == null and m.albedo_color != PbrMaterials.color(id): errs.append("%s : couleur de repli absente" % id)
		if not c.fallback:
			var sm := PbrMaterials.surface(id)
			if int(sm.get_shader_parameter("layer")) != PbrMaterials.layer_of(id) or sm.get_shader_parameter("pbr_albedo_tex") == null or int(sm.get_shader_parameter("pbr_tex_quality")) <= 0: errs.append("%s : textures non branchées" % id)
			if not c.mobile: errs.append("%s : jeu mobile 1024² absent" % id)
			if str(lib[id].get("source", "")).find("CC0") < 0: errs.append("%s : licence non tracée" % id)
			if lib[id].has("texture_from") and lib[id].has("layer"): errs.append("%s : couche propre et empruntée" % id)
	check(errs.is_empty(), "fiches valides, complètes ou en repli documenté : %s" % [errs])
	print("PBR|textures complètes=%d|repli couleur unie=%d (%s)" % [lib.size() - fallback.size(), fallback.size(), ",".join(fallback)])
	var wa := PbrMaterials.world_arrays()
	var covered := {}
	for e in lib.values():
		if e.has("world_id"): covered[int(e.world_id)] = true
	check(covered.size() >= 15, "identifiants de matériau du décor 1 à 15 couverts : %s" % [covered.keys()])
	# P1 : textures réelles (tableaux 16 couches, 2048² PC / 1024² Mobile), licences tracées
	var textured := lib.size() - fallback.size()
	check(textured >= 14, "bibliothèque P1 : %d matériaux texturés (béton, dalle, enrobé, pavés, gazon, ballast, rail, façades, granit…)" % textured)
	var a2: TextureLayered = load("res://assets/textures/pbr/albedo_2k.jpg")
	var a1: TextureLayered = load("res://assets/textures/pbr/albedo_1k.jpg")
	check(a2 != null and a2.get_layers() >= 18 and a2.get_width() == 2048, "tableau PC : %d couches 2048²" % a2.get_layers())
	check(a1 != null and a1.get_layers() == a2.get_layers() and a1.get_width() == 1024, "tableau Mobile : mêmes couches en 1024²")
	check(a2 != null and a2.has_mipmaps(), "mipmaps des tableaux")
	var credits := FileAccess.get_file_as_string("res://CREDITS.md") + FileAccess.get_file_as_string("res://docs/refonte-visuelle/sources.json")
	var miss: Array = []
	for e in lib.values():
		var src := str(e.get("source", ""))
		var k := src.find("polyhaven.com/a/")
		if k >= 0:
			var asset := src.substr(k + 16).split(" ")[0]
			if credits.count(asset) < 2: miss.append(asset)
	check(miss.is_empty(), "textures créditées dans CREDITS.md et sources.json : %s" % [miss])
	var wl = Materials.building().get_shader_parameter("mat_layer")
	check(wl is PackedInt32Array and wl.size() == 16 and wl[2] == int(PbrMaterials.entry("enrobe").layer), "décor : couche de texture par identifiant de matériau")
	PbrMaterials.set_profile("mobile")
	var ql := int(Materials.building().get_shader_parameter("pbr_tex_quality"))
	var tl: TextureLayered = Materials.building().get_shader_parameter("pbr_albedo_tex")
	check(ql == 1 and tl != null and tl.get_width() == 1024, "profil Mobile : 1024², un échantillon")
	PbrMaterials.set_profile("ultra")
	check(int(Materials.building().get_shader_parameter("pbr_tex_quality")) == 2 and (Materials.building().get_shader_parameter("pbr_albedo_tex") as TextureLayered).get_width() == 2048, "profil Ultra : 2048², anti-répétition")
	check(is_equal_approx(wa.mat_metallic[9], float(PbrMaterials.entry("acier_rail").metallic)) and wa.mat_metallic[9] > 0.5, "rails métalliques (M_METAL = 9)")
	check(CityScene._Arrays.mat_id(TrackView.A_METAL) == 9.0 and is_equal_approx(TrackView.RAIL_TOP.a, TrackView.A_METAL) and CityScene._Arrays.mat_id(TrackView.RAIL_TOP.a) == 9.0, "acier des rails encodé M_METAL")

	# Matériaux partagés
	var b := Materials.building()
	check(b.shader.resource_path.ends_with("pbr_world.gdshader"), "décor : pbr_world.gdshader")
	var rough = b.get_shader_parameter("mat_roughness")
	check(rough is PackedFloat32Array and rough.size() == 16 and rough[2] > 0.5, "décor : rugosités par matériau posées")
	var o := Materials.object()
	check(o.shader.resource_path.ends_with("pbr_object.gdshader"), "objets : pbr_object.gdshader")
	var f := Materials.foliage()
	check(f.shader.resource_path.ends_with("pbr_object.gdshader") and float(f.get_shader_parameter("translucency")) > 0.0, "végétation PBR translucide")
	var t := Materials.tram(3.3)
	check(t.next_pass == null, "rame : aucune passe de contour")
	check(float(t.get_shader_parameter("surface_roughness")) < 0.5 and float(t.get_shader_parameter("surface_clearcoat")) > 0.0, "rame : peinture vernie (rugosité %.2f)" % float(t.get_shader_parameter("surface_roughness")))
	check(Materials.water().shader.resource_path.ends_with("water.gdshader"), "eau PBR")
	for sh in ["pbr_object", "pbr_world", "water", "station_paving"]:
		var code := FileAccess.get_file_as_string("res://src/rendering/shaders/%s.gdshader" % sh)
		check(code.contains("pbr_common.gdshaderinc") and code.contains("pbr_albedo(ALBEDO, OUTPUT_IS_SRGB)"), "%s : chaîne de couleur unique (pbr_albedo)" % sh)
	print("TOTAL_ECHECS|%d" % fails)
	quit(1 if fails > 0 else 0)
