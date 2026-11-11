extends SceneTree
## Vitrine des rames (familles et livrées). Args : dossier de sortie.
func _init() -> void:
	var out: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "user://"
	var world := Node3D.new(); root.add_child(world)
	var dn := DayNight.new(); world.add_child(dn); dn.setup(world); dn.set_hour(15.0)
	var ground := MeshInstance3D.new(); var pm := PlaneMesh.new(); pm.size = Vector2(400, 400); ground.mesh = pm
	var gm := StandardMaterial3D.new(); gm.albedo_color = Color("#8fae6a"); pm.material = gm
	world.add_child(ground)
	var picks := [["angers_a", 0], ["nantes_1", 0], ["nantes_1", 1], ["grenoble_a", 0], ["strasbourg_a", 0], ["marseille_t1", 0],
		["montpellier_1", 0], ["lille_tram", 0], ["bordeaux_a", 0], ["clermont_a", 0], ["idf_t4", 0], ["tours_a", 0]]
	var i := 0
	for p in picks:
		var net := NetworkLoader.new()
		if not net.load_file("res://data/networks/%s.json" % p[0]).is_empty(): continue
		var fleet: Array = TramModel.fleet_for(net.meta)
		var entry: Dictionary = fleet[mini(p[1], fleet.size() - 1)]
		var v := VehicleLibrary.for_fleet(entry, net.meta)
		var liv := TramModel.livery_for(net.meta, entry)
		var mods := TramModel.build(minf(v.length_m, 36.0), liv, v.model_family)
		var holder := Node3D.new(); world.add_child(holder)
		holder.position = Vector3((i % 4) * 9.0 - 13.5, 0, (i / 4) * 45.0)
		var seg := minf(v.length_m, 36.0) / mods.size()
		for k in mods.size():
			mods[k].position = Vector3(0, 0, -16.0 + seg * (k + 0.5))
			holder.add_child(mods[k])
		var lbl := Label3D.new(); lbl.text = "%s\n%s" % [net.meta.city, liv.name]; lbl.font_size = 80; lbl.pixel_size = 0.008
		lbl.position = Vector3(0, 5.0, -14.0); lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED; lbl.outline_size = 16
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
