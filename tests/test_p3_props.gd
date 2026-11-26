extends SceneTree
## Refonte P3 : végétation réaliste (Vegetation), mobilier détaillé (StreetProps), caténaire HD (ElectrificationView),
## decals de voirie (RoadDecals). Sans affichage.
var fails := 0

func check(c: bool, m: String) -> void:
	print(("ok " if c else "ECHEC: ") + m)
	if not c: fails += 1

func _init() -> void:
	# --- végétation
	var sp := Vegetation.species()
	check(sp.size() == 11, "11 essences (10 types + marronnier) : %d" % sp.size())
	var names := []
	for s in sp: names.append(s.name)
	for n in ["tilleul", "platane", "marronnier", "erable", "pin_parasol", "palmier"]:
		check(n in names, "essence urbaine française : " + n)
	for k in sp.size():
		var m := Vegetation.mesh(k)
		var tris := m.get_faces().size() / 3
		check(m.get_surface_count() == 1 and tris > 0, "%s : maillage valide (%d triangles)" % [sp[k].name, tris])
		check(tris < 1200, "%s : ≤ 1 200 triangles (LOD0)" % sp[k].name)
		if k < 7 or k == Vegetation.MARRONNIER:
			# houppier : rayon horizontal ≈ CityScene.CROWN_R (étirement LiDAR cohérent)
			var a := m.get_aabb()
			var r := maxf(a.size.x, a.size.z) * 0.5
			if k < 7: check(r < CityScene.CROWN_R[k] * 1.6 and r > CityScene.CROWN_R[k] * 0.6, "%s : houppier %.1f m ≈ %.1f m" % [sp[k].name, r, CityScene.CROWN_R[k]])
			check(Vegetation.has_impostor(k) and Vegetation.impostor_mesh(k).get_faces().size() == 6, "%s : imposteur 2 triangles" % sp[k].name)
		var c := m.surface_get_arrays(0)[Mesh.ARRAY_COLOR] as PackedColorArray
		var has_leaf := false; var has_bark := false
		for col in c:
			if col.a > 0.5: has_leaf = true
			else: has_bark = true
		check(has_leaf, "%s : cartes de feuillage" % sp[k].name)
		if k < 7 and k != 1 or k == Vegetation.MARRONNIER: check(has_bark, "%s : tronc/branches modélisés" % sp[k].name)
	var vm := Vegetation.material(); var im := Vegetation.impostor_material()
	check(vm.shader.resource_path.ends_with("vegetation.gdshader") and im.shader == vm.shader, "matériau végétation dédié")
	check(float(vm.get_shader_parameter("translucency")) > 0.0, "feuillage translucide (fiche vegetation_cartes)")
	check(vm.get_shader_parameter("foliage_tex") is Texture2D and (vm.get_shader_parameter("foliage_tex") as Texture2D).get_width() == 2048, "atlas de rameaux 2048 (PC)")
	Vegetation.set_mobile(true)
	check((vm.get_shader_parameter("foliage_tex") as Texture2D).get_width() == 1024 and (im.get_shader_parameter("foliage_tex") as Texture2D).get_width() == 512, "Mobile : atlas 1024, imposteurs 512")
	Vegetation.set_mobile(false)
	var code := FileAccess.get_file_as_string("res://src/rendering/shaders/vegetation.gdshader")
	check(code.contains("MAIN_CAM_INV_VIEW_MATRIX") and code.contains("ALPHA_SCISSOR_THRESHOLD") and code.contains("pbr_albedo(") and code.contains("BACKLIGHT"), "shader : LOD par instance (caméra principale), découpe alpha, chaîne de couleur, translucidité")
	var r := CityScene.tree_ranges()
	check(r.lod + CityScene.TREE_VEG_CELL * 0.71 <= r.near + 0.01, "bascule maillage/imposteur couverte par la portée des cellules")
	# --- mobilier
	for k in StreetProps.KINDS:
		var d := StreetProps.detail_mesh(k)
		check(d != null and d.get_surface_count() > 0, "mobilier %d : modèle détaillé" % k)
		if StreetProps.has_detail(k) and k != StreetProps.MUPI and k != StreetProps.BARRIER:
			check(d.get_faces().size() > StreetProps.mesh(k).get_faces().size(), "mobilier %d : plus détaillé que le LOD lointain" % k)
	var xf := [Transform3D.IDENTITY, Transform3D(Basis(), Vector3(3, 0, 0))]
	var lod := StreetProps.instances_lod(StreetProps.BENCH, xf)
	check(lod.size() == 2 and is_equal_approx(lod[0].visibility_range_end, lod[1].visibility_range_begin), "mobilier : LOD détaillé/simple complémentaires")
	for n in lod: n.free()
	# --- caténaire
	check(ElectrificationView.line_material().shader.resource_path.ends_with("wire.gdshader"), "fils : lignes à largeur d'écran minimale")
	check(is_equal_approx(ElectrificationView._messenger_h(0.0), 6.05) and ElectrificationView._messenger_h(0.5) < 5.85, "porteur en chaînette (flèche à mi-portée)")
	var w := ElectrificationView.Wires.new(); w.line(Vector3.ZERO, Vector3(10, 0, 0), 0.006, Color.GRAY)
	var wi := w.instance()
	check(wi.mesh.get_faces().size() == 6 and wi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "fil : un ruban par segment")
	wi.free()
	# --- decals
	check(not RoadDecals.enabled(), "decals : aucun en Compatibility / sans affichage")
	var dc := RoadDecals.make(RoadDecals.MANHOLE, Vector3.ZERO, 0.0, Vector2.ONE)
	check(dc.texture_albedo != null and dc.texture_normal != null and dc.distance_fade_enabled, "decal plaque d'égout : albédo + normale, fondu en distance")
	dc.free()
	print("TOTAL_ECHECS|%d" % fails)
	quit(1 if fails > 0 else 0)
