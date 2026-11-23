extends SceneTree
## Captures de contrôle des rames HD (hors jeu) :
## godot --path <projet vide> --rendering-driver opengl3 -s preview.gd -- <dir rame> <sortie> <préfixe> [vues] [lod]
## vues : ext34,side,rear34,int,cab,cabdesk,night (séparées par des virgules). Le glb est chargé à l'exécution
## (GLTFDocument) ; les matériaux sont complétés comme le fera StockHD (clearcoat, verre, émissifs).

var cam: Camera3D
var root3d: Node3D

func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var dir: String = a[0]; var out: String = a[1]; var pre: String = a[2]
	var views: PackedStringArray = (a[3] if a.size() > 3 else "ext34,side,int,cab").split(",")
	var lod: String = a[4] if a.size() > 4 else "lod0"
	DirAccess.make_dir_recursive_absolute(out)
	await process_frame
	root3d = Node3D.new(); get_root().add_child(root3d)
	var env := WorldEnvironment.new(); var e := Environment.new()
	var sky := Sky.new(); var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.36, 0.55, 0.82); sm.sky_horizon_color = Color(0.72, 0.8, 0.88)
	sm.ground_bottom_color = Color(0.3, 0.3, 0.28); sm.ground_horizon_color = Color(0.6, 0.62, 0.62)
	sky.sky_material = sm; e.sky = sky; e.background_mode = Environment.BG_SKY
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY; e.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC; e.tonemap_exposure = 1.0
	e.ssao_enabled = true
	env.environment = e; root3d.add_child(env)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-40, 145, 0); sun.light_energy = 1.25
	sun.shadow_enabled = true; sun.directional_shadow_max_distance = 80.0; root3d.add_child(sun)
	# sol + rails
	var g := MeshInstance3D.new(); var pm := PlaneMesh.new(); pm.size = Vector2(200, 200); g.mesh = pm
	var gm := StandardMaterial3D.new(); gm.albedo_color = Color(0.48, 0.47, 0.45); gm.roughness = 0.9; g.material_override = gm
	g.position.y = -0.005; root3d.add_child(g)
	for x in [-0.7175, 0.7175]:
		var r := MeshInstance3D.new(); var bm := BoxMesh.new(); bm.size = Vector3(0.07, 0.02, 200); r.mesh = bm
		var rm := StandardMaterial3D.new(); rm.albedo_color = Color(0.6, 0.6, 0.62); rm.metallic = 1.0; rm.roughness = 0.3
		r.material_override = rm; r.position = Vector3(x, -0.01, 0); root3d.add_child(r)
	# quai
	var q := MeshInstance3D.new(); var qb := BoxMesh.new(); qb.size = Vector3(3.0, 0.3, 60); q.mesh = qb
	var qm := StandardMaterial3D.new(); qm.albedo_color = Color(0.72, 0.71, 0.68); qm.roughness = 0.85; q.material_override = qm
	q.position = Vector3(-3.0, 0.15, 0); root3d.add_child(q)
	var train := _load(dir + "/" + lod + ".glb")
	root3d.add_child(train)
	var cabn: Node3D = null
	if FileAccess.file_exists(dir + "/cab.glb"):
		cabn = _load(dir + "/cab.glb")
	var probe := ReflectionProbe.new(); probe.size = Vector3(60, 20, 60); probe.position = Vector3(0, 3, 0)
	probe.update_mode = ReflectionProbe.UPDATE_ONCE; root3d.add_child(probe)
	cam = Camera3D.new(); cam.fov = 50; root3d.add_child(cam); cam.current = true
	var L := 0.0
	for c in train.get_children():
		if c.name.begins_with("module_"): L = maxf(L, absf(c.position.z) * 2.0)
	var m0 := train.get_node_or_null("module_00") as Node3D
	var front := -L * 0.5 - 4.0
	for v in views:
		if v == "cab" or v == "cabdesk" or v == "cabnight":
			if cabn == null: continue
			if cabn.get_parent() == null:
				m0.add_child(cabn)
				var px := train.find_child("cab_proxy_A", true, false)
				if px: px.visible = false
			if cabn.get_node_or_null("cab_light") == null:
				var ol := OmniLight3D.new(); ol.name = "cab_light"; ol.light_energy = 0.6; ol.omni_range = 3.0
				ol.position = Vector3(0, 2.2, -2.0); cabn.add_child(ol)
				var cl := cabn.find_child("em_interior_cab", true, false) as Node3D
				if cl: ol.global_position = cl.global_position + Vector3(0, -0.2, 0)
			var cd := cabn.find_child("cam_driver", true, false) as Node3D
			cam.global_transform = cd.global_transform; cam.fov = 62
			if v == "cabdesk":
				cam.rotate_object_local(Vector3.RIGHT, deg_to_rad(-24)); cam.fov = 60
		else:
			cam.fov = 50
			if cabn and cabn.get_parent(): cabn.get_parent().remove_child(cabn)
			var px2 := train.find_child("cab_proxy_A", true, false)
			if px2: px2.visible = true
		match v:
			"ext34": _look(Vector3(5.5, 2.3, front - 4.5), Vector3(0, 1.6, front + 9))
			"front": _look(Vector3(0.8, 1.7, front - 6.0), Vector3(0, 1.6, front + 4))
			"rear34": _look(Vector3(-6.0, 2.6, L * 0.5 + 8), Vector3(0, 1.4, L * 0.5 - 8))
			"side": cam.fov = 28; _look(Vector3(L * 0.95 + 8, 2.2, 0), Vector3(0, 1.6, 0))
			"roof": _look(Vector3(5, 6.5, 0), Vector3(0, 3.3, 0))
			"bogie": _look(Vector3(2.6, 0.5, front + 6), Vector3(0, 0.35, front + 9))
			"int":
				var m1 := train.get_node("module_01") as Node3D
				_look(m1.global_position + Vector3(0.3, 1.65, 2.2), m1.global_position + Vector3(-0.2, 1.3, -6))
				cam.fov = 70
		await process_frame; await process_frame
		for i in 6: await process_frame
		var img := get_root().get_texture().get_image()
		img.save_png(out + "/" + pre + "_" + v + ".png")
		print("saved ", out + "/" + pre + "_" + v + ".png")
	quit()

func _look(p: Vector3, t: Vector3) -> void:
	cam.global_position = p; cam.look_at(t, Vector3.UP)

func _load(path: String) -> Node3D:
	var doc := GLTFDocument.new(); var st := GLTFState.new()
	var err := doc.append_from_file(path, st)
	if err != OK:
		push_error("glb " + path + " : " + str(err)); return Node3D.new()
	var n := doc.generate_scene(st) as Node3D
	_fix(n)
	return n

func _fix(n: Node) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		for i in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(i) as StandardMaterial3D
			if m == null: continue
			var nm := m.resource_name
			for slot in [BaseMaterial3D.TEXTURE_ALBEDO, BaseMaterial3D.TEXTURE_NORMAL, BaseMaterial3D.TEXTURE_ORM, BaseMaterial3D.TEXTURE_EMISSION]:
				var tx := m.get_texture(slot)
				if tx and not tx.has_meta("mip"):
					var im := tx.get_image()
					if im and not im.has_mipmaps():
						if im.is_compressed(): im.decompress()
						im.generate_mipmaps()
						var it := ImageTexture.create_from_image(im); it.set_meta("mip", true)
						m.set_texture(slot, it)
			m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
			if nm.begins_with("livery") or nm.begins_with("paint_"):
				m.clearcoat_enabled = true; m.clearcoat = 1.0; m.clearcoat_roughness = 0.08
			if nm.begins_with("glass"):
				m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA; m.cull_mode = BaseMaterial3D.CULL_DISABLED
				m.metallic_specular = 0.9
	for c in n.get_children(): _fix(c)
