extends SceneTree
## Refonte P1 : préparation des scènes de cuisson LightmapGI des modèles dédiés (LandmarkModels, manifeste
## assets/models/landmark_models.json, champ "lightmap": true ou "station").
## Pour chaque modèle : LOD0 instancié, maillages dépliés en UV2 (ArrayMesh.lightmap_unwrap, xatlas, binaire éditeur),
## gi_mode STATIQUE, nœud LightmapGI réglé (qualité, rebonds, texel), soleil de midi en cuisson « dynamique » (seule la
## lumière indirecte est cuite : le soleil temps réel reste piloté par DayNight), ciel en couleur personnalisée.
## Sortie : assets/lightmaps/<id>/<id>_bake.tscn (+ maillages .res). La cuisson elle-même exige le RenderingDevice
## (éditeur, Vulkan) : voir tools/lightmaps/README (section « État P1 » du CDC) et bake_lightmaps.gd.
## Usage : godot --headless --path . -s tools/lightmaps/prepare_lightmaps.gd [-- id…]
const MANIFEST := "res://assets/models/landmark_models.json"
const OUT := "res://assets/lightmaps"

func _init() -> void:
	var only := OS.get_cmdline_user_args()
	var doc = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	var n := 0
	for m in doc.get("models", []):
		if not (bool(m.get("lightmap", false)) or m.has("station")): continue
		if not only.is_empty() and not str(m.id) in only: continue
		if prepare(m): n += 1
	print("LIGHTMAP|scenes preparees=%d" % n)
	quit(0 if n > 0 else 1)

static func prepare(m: Dictionary) -> bool:
	var src := str(m.lods[0])
	if not ResourceLoader.exists(src): printerr("absent : ", src); return false
	var dir := "%s/%s" % [OUT, m.id]
	DirAccess.make_dir_recursive_absolute(dir)
	var root := Node3D.new(); root.name = str(m.id)
	var model := (load(src) as PackedScene).instantiate() as Node3D
	model.name = "model"
	root.add_child(model)
	var k := 0
	var tris := 0
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var mesh := mi.mesh as ArrayMesh
		if mesh == null: continue
		var am := mesh.duplicate(true) as ArrayMesh
		var err := am.lightmap_unwrap(mi.global_transform if mi.is_inside_tree() else Transform3D.IDENTITY, 0.08)
		if err != OK: printerr("depliage UV2 impossible : ", mi.name); continue
		var path := "%s/mesh_%03d.res" % [dir, k]; k += 1
		ResourceSaver.save(am, path, ResourceSaver.FLAG_COMPRESS)
		mi.mesh = load(path)
		mi.gi_mode = GeometryInstance3D.GI_MODE_STATIC
		for s in am.get_surface_count():
			var ni := am.surface_get_array_index_len(s)
			tris += (ni if ni > 0 else am.surface_get_array_len(s)) / 3
	var lm := LightmapGI.new(); lm.name = "LightmapGI"
	lm.quality = LightmapGI.BAKE_QUALITY_MEDIUM
	lm.bounces = 3
	lm.directional = false            # Mobile : lightmap simple (pas de SH)
	lm.texel_scale = 1.0
	lm.max_texture_size = 2048
	lm.use_denoiser = true
	lm.interior = bool(m.get("lightmap", false))
	lm.environment_mode = LightmapGI.ENVIRONMENT_MODE_CUSTOM_COLOR
	lm.environment_custom_color = Color(0.62, 0.72, 0.86); lm.environment_custom_energy = 0.8
	root.add_child(lm)
	# données de cuisson pré-attribuées (fichier .lmbake) : l'éditeur cuit sans boîte de dialogue d'enregistrement
	var data := LightmapGIData.new()
	var data_path := "%s/%s.lmbake" % [dir, m.id]
	ResourceSaver.save(data, data_path)
	lm.light_data = load(data_path)
	var sun := DirectionalLight3D.new(); sun.name = "sun_bake"
	sun.light_bake_mode = Light3D.BAKE_DYNAMIC   # indirect seul ; direct temps réel (DayNight)
	sun.rotation_degrees = Vector3(-55, 30, 0)
	root.add_child(sun)
	for n in root.find_children("*", "", true, false): n.owner = root
	model.owner = root; lm.owner = root; sun.owner = root
	var ps := PackedScene.new(); ps.pack(root)
	var out := "%s/%s_bake.tscn" % [dir, m.id]
	var e := ResourceSaver.save(ps, out)
	print("LIGHTMAP|%s|maillages=%d|triangles=%d|scene=%s|err=%d" % [m.id, k, tris, out, e])
	root.free()
	return e == OK
