extends SceneTree
## Vitrine des rames (familles et livrées). Args : dossier de sortie.
func _init() -> void:
	var out: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "user://"
	var world := Node3D.new(); root.add_child(world)
	var dn := DayNight.new(); world.add_child(dn); dn.setup(world); dn.set_hour(15.0)
	var ground := MeshInstance3D.new(); var pm := PlaneMesh.new(); pm.size = Vector2(400, 400); ground.mesh = pm
	var gm := StandardMaterial3D.new(); gm.albedo_color = Color("#8fae6a"); pm.material = gm
	world.add_child(ground)
	var picks := [["angers_a", "Angers A"], ["bordeaux_a", "Bordeaux A"], ["strasbourg_a", "Strasbourg A"], ["marseille_t1", "Marseille T1"],
		["montpellier_3", "Montpellier 3"], ["tours_a", "Tours A"], ["reims_tram", "Reims"], ["clermont_a", "Clermont A"],
		["idf_t4", "IDF T4"], ["besancon_t1", "Besançon T1"], ["lille_tram", "Lille"], ["dijon_t1", "Dijon T1"]]
	var i := 0
	for p in picks:
		var net := NetworkLoader.new()
		if not net.load_file("res://data/networks/%s.json" % p[0]).is_empty(): continue
		var liv := TramModel.livery_for(net.meta)
		var v := VehicleLibrary.default_for(net.meta)
		var mods := TramModel.build(32.0 if v.length_m < 40 else v.length_m * 0.8, liv)
		var holder := Node3D.new(); world.add_child(holder)
		holder.position = Vector3((i % 4) * 9.0 - 13.5, 0, (i / 4) * 45.0)
		var seg := 32.0 / mods.size()
		for k in mods.size():
			mods[k].position = Vector3(0, 0, -16.0 + seg * (k + 0.5))
			holder.add_child(mods[k])
		var lbl := Label3D.new(); lbl.text = "%s\n%s" % [p[1], liv.family]; lbl.font_size = 96; lbl.pixel_size = 0.01
		lbl.position = Vector3(0, 5.2, -14.0); lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED; lbl.outline_size = 16
		holder.add_child(lbl)
		i += 1
	var cam := Camera3D.new(); world.add_child(cam); cam.current = true; cam.fov = 50
	for f in 40: await process_frame
	var shots := [[Vector3(-4, 3.5, -34), Vector3(-4, 1.8, -16), "face_avant"], [Vector3(26, 5, -24), Vector3(0, 1.8, -10), "profil"], [Vector3(-6, 4, -30), Vector3(-9, 1.8, -14), "zoom"]]
	for s in shots:
		cam.position = s[0]; cam.look_at(s[1])
		for f in 6: await process_frame
		root.get_viewport().get_texture().get_image().save_png("%s/rames_%s.png" % [out, s[2]])
	quit()
