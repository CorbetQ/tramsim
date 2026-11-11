extends SceneTree
## Vitrine des rames : une rame par famille (livrée d'un réseau qui l'exploite) et quelques livrées marquantes,
## vue de 3/4 avant (rame_<nom>.png), plus une vue de profil portes ouvertes / pantographe baissé (anim_*.png).
## Args : dossier de sortie.
const PICKS := [
	["avanto", "idf_t4", "avanto"], ["breda_vlc", "lille_tram", "breda_vlc"], ["citadis_302", "lyon_t1", "citadis_302"],
	["citadis_402", "bordeaux_a", "citadis_402"], ["citadis_403_strasbourg", "strasbourg_a", "citadis_403_strasbourg"],
	["citadis_compact", "avignon_t1", "citadis_compact"], ["citadis_dualis", "idf_t11", "citadis_dualis"],
	["citadis_reims", "reims_tram", "citadis_reims"], ["citadis_tours", "tours_a", "citadis_tours"],
	["citadis_x01", "montpellier_1", "citadis_x01"], ["citadis_x05", "caen_t1", "citadis_x05"], ["eurotram", "strasbourg_a", "eurotram"],
	["flexity_marseille", "marseille_t1", "flexity_marseille"], ["incentro", "nantes_1", "incentro"],
	["tango_rhonexpress", "lyon_rhonexpress", "tango_rhonexpress"], ["tfs", "grenoble_a", "tfs"], ["translohr", "clermont_a", "translohr"],
	["urbos", "besancon_t1", "urbos"], ["vevey_saint_etienne", "saintetienne_t1", "vevey_saint_etienne"],
	["liv_angers", "angers_a", "citadis_302"], ["liv_montpellier_1", "montpellier_1", "citadis_402"], ["liv_montpellier_2", "montpellier_2", "citadis_302"],
	["liv_idf_t3a", "idf_t3a", "citadis_402"], ["liv_mulhouse_tt", "mulhouse_tt", "avanto"]]

func _meta(id: String) -> Dictionary:
	var net := NetworkLoader.new()
	if net.load_file("res://data/networks/%s.json" % id).is_empty(): return net.meta
	var src := id.split("_")[0]
	return {"source_id": src, "id": id, "color": "#c8102e"}

func _init() -> void:
	var out: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "user://"
	var only := OS.get_cmdline_user_args()[1] if OS.get_cmdline_user_args().size() > 1 else ""
	var face := OS.get_cmdline_user_args().size() > 2 and OS.get_cmdline_user_args()[2] == "face"
	var world := Node3D.new(); root.add_child(world)
	var dn := DayNight.new(); world.add_child(dn); dn.setup(world); dn.set_hour(14.0)
	dn.env.fog_enabled = false
	var ground := MeshInstance3D.new(); var pm := PlaneMesh.new(); pm.size = Vector2(2400, 400); ground.mesh = pm
	var gm := StandardMaterial3D.new(); gm.albedo_color = Color("#6f716c"); pm.material = gm
	ground.position = Vector3(500, 0, 0)
	world.add_child(ground)
	var cam := Camera3D.new(); world.add_child(cam); cam.current = true; cam.fov = 38
	var rigs: Array = []
	var i := 0
	for p in PICKS:
		if only != "" and not str(p[0]).contains(only): continue
		var meta := _meta(p[1])
		var entry := {}
		for e in TramModel.fleet_for(meta):
			if e.family == p[2]: entry = e
		if entry.is_empty(): entry = {"family": p[2]}
		var liv := TramModel.livery_for(meta, entry)
		var rig := TramModel.build_rig(liv)
		var holder := Node3D.new(); world.add_child(holder)
		holder.position = Vector3(i * 40.0, 0, 0)
		rig.layout_straight()
		for m in rig.modules: holder.add_child(m)
		rigs.append([p[0], rig, holder, liv.name])
		print("%s : %s, %.1f m, %d modules, %d triangles" % [p[0], liv.name, rig.length, rig.modules.size(), rig.triangles])
		i += 1
	for f in 20: await process_frame
	for r in rigs:
		var rig: TramModel.Rig = r[1]; var x: float = (r[2] as Node3D).position.x
		var zf := -rig.length * 0.5
		cam.fov = 38
		cam.position = Vector3(x - 6.5, 2.3, zf - 8.0); cam.look_at(Vector3(x - 0.2, 1.6, zf + 4.5))
		if face:
			cam.position = Vector3(x - 3.2, 1.9, zf - 6.0); cam.look_at(Vector3(x, 1.6, zf + 1.0))
		for f in 3: await process_frame
		root.get_viewport().get_texture().get_image().save_png("%s/rame_%s.png" % [out, r[0]])
	# animations : profil, portes ouvertes et pantographe baissé sur la première rame, levé sur la seconde
	if rigs.size() >= 1:
		var rig: TramModel.Rig = rigs[0][1]; var x: float = (rigs[0][2] as Node3D).position.x
		rig.set_doors(true); rig.set_pantograph(true)
		for k in 40: rig.update(0.1)
		cam.fov = 45
		cam.position = Vector3(x + 22.0, 5.0, -rig.length * 0.25); cam.look_at(Vector3(x, 2.0, -rig.length * 0.25))
		for f in 3: await process_frame
		root.get_viewport().get_texture().get_image().save_png("%s/anim_%s_ouvert.png" % [out, rigs[0][0]])
		rig.set_doors(false); rig.set_pantograph(false)
		for k in 80: rig.update(0.1)
		for f in 3: await process_frame
		root.get_viewport().get_texture().get_image().save_png("%s/anim_%s_ferme.png" % [out, rigs[0][0]])
	quit()
