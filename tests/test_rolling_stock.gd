extends SceneTree
## Matériel roulant : chaque plan se construit (modules, longueur, budget de triangles), les animations
## (portes, pantographe) atteignent leurs états, la flotte des réseaux est résolue depuis data/rolling_stock.
var fails := 0
const BUDGET := 12000

func check(c: bool, m: String) -> void:
	if not c: fails += 1; printerr("ECHEC: ", m)
	else: print("ok: ", m)

func _init() -> void:
	var ids := TramModel.plan_ids()
	check(ids.size() >= 20, "%d plans trouvés" % ids.size())
	var meta := {"source_id": "test", "id": "test_1", "color": "#c8102e"}
	for id in ids:
		var p := TramModel.plan(id)
		var liv := TramModel.livery_for(meta, {"family": id})
		check(liv.family == id, "%s : livrée de la bonne famille" % id)
		var rig := TramModel.build_rig(liv, float(p.length_m))
		var n: int = (p.modules as Array).size()
		check(rig.modules.size() == n, "%s : %d modules (plan %d)" % [id, rig.modules.size(), n])
		var sum := 0.0
		for l in rig.module_lengths: sum += l
		check(absf(sum - float(p.length_m)) < 0.05, "%s : longueur %.2f m (plan %.2f)" % [id, sum, float(p.length_m)])
		check(rig.triangles > 1500 and rig.triangles <= BUDGET, "%s : %d triangles (budget %d)" % [id, rig.triangles, BUDGET])
		check(not rig.leaves.is_empty() and not rig.panto.is_empty(), "%s : %d vantaux, pantographe" % [id, rig.leaves.size()])
		# portes : fermées -> ouvertes en open_s, puis refermées
		var leaf: MeshInstance3D = rig.leaves[0].node
		var closed := leaf.position
		rig.set_doors(true)
		var t := 0.0
		while not rig.doors_open() and t < 20.0:
			rig.update(0.1); t += 0.1
		var travel := leaf.position.distance_to(closed)
		check(rig.doors_open() and absf(t - rig.door_time()) < 0.25 and travel > 0.4, "%s : portes ouvertes en %.1f s (déplacement %.2f m)" % [id, t, travel])
		rig.set_doors(false)
		for k in 200: rig.update(0.05)
		check(rig.doors_closed() and leaf.position.distance_to(closed) < 0.001, "%s : portes refermées" % id)
		# portes côté quai : seules celles du côté demandé bougent (droite = +x, sens de marche -z)
		for sd in ["right", "left", "both"]:
			var rest: Array = []
			for lf in rig.leaves: rest.append((lf.node as Node3D).transform)
			rig.set_doors(true, sd)
			for k in 200: rig.update(0.05)
			var ok := rig.doors_open()
			for li in rig.leaves.size():
				var lf: Dictionary = rig.leaves[li]
				var want: bool = sd == "both" or (sd == "right") == (float(lf.side) > 0.0)
				var moved := not (lf.node as Node3D).transform.is_equal_approx(rest[li])
				if moved != want: ok = false
			check(ok, "%s : portes côté %s seules ouvertes" % [id, sd])
			rig.set_doors(false)
			for k in 200: rig.update(0.05)
		check(rig.doors_closed(), "%s : portes refermées des deux côtés" % id)
		# pantographe : levé -> baissé -> levé
		var up_h := rig.pantograph_height()
		var head: Node3D = rig.panto.head
		var y_up := head.position.y
		rig.set_pantograph(false)
		for k in int(rig.panto_time() / 0.1) + 3: rig.update(0.1)
		var y_down := head.position.y
		check(rig.pantograph_down() and y_up - y_down > 1.2, "%s : pantographe abaissé (%.2f -> %.2f m)" % [id, y_up, y_down])
		rig.set_pantograph(true)
		for k in int(rig.panto_time() / 0.1) + 3: rig.update(0.1)
		check(rig.pantograph_up() and absf(rig.pantograph_height() - up_h) < 0.01, "%s : pantographe relevé" % id)
		for m in rig.modules: m.free()
	# variantes de longueur : modules ajoutés / retirés
	var nantes := TramModel.livery_for({"source_id": "nantes", "id": "nantes_1"}, {"family": "citadis_x05", "length": 48.0})
	var r48 := TramModel.build_rig(nantes, 48.0)
	check(r48.modules.size() >= 7 and absf(r48.length - 48.0) < 0.01, "Citadis X05 48 m : %d modules" % r48.modules.size())
	for m in r48.modules: m.free()
	# flottes et livrées des réseaux
	var angers := TramModel.fleet_for({"source_id": "angers", "id": "angers_a"})
	check(angers.size() == 2 and angers[0].family == "citadis_302", "flotte d'Angers : %s" % str(angers.map(func(e): return e.family)))
	var t4 := TramModel.fleet_for({"source_id": "idf", "id": "idf_t4"})
	check(t4[0].family == "avanto", "T4 : Avanto")
	var mtp := TramModel.livery_for({"source_id": "montpellier", "id": "montpellier_1"})
	check(mtp.family == "citadis_x01" and absf(float(mtp.length)-40.9)<.01, "Montpellier L1 : Citadis 401 et livrée hirondelles")
	# motifs procéduraux de livrée (shader des rames)
	for pair in [["montpellier_1", "swallows"], ["montpellier_2", "flowers"], ["montpellier_3", "waves"], ["montpellier_4", "gilding"], ["tours_a", "mirror_bands"]]:
		var lv := TramModel.livery_for({"source_id": str(pair[0]).split("_")[0], "id": pair[0]})
		var pt: Dictionary = lv.get("pattern", {})
		var rg := TramModel.build_rig(lv)
		var mat := rg.modules[0].material_override as ShaderMaterial
		check(str(pt.get("type", "")) == pair[1] and int(mat.get_shader_parameter("tram_pattern")) == Materials.PATTERN_IDS[pair[1]],
			"%s : motif %s" % pair)
		for m in rg.modules: m.free()
	var reims := TramModel.livery_for({"source_id": "reims", "id": "reims_tram"})
	var v0 := TramModel._variant(reims.merged({"variant": 0})); var v1 := TramModel._variant(reims.merged({"variant": 1}))
	check(not (v0.front as Color).is_equal_approx(v1.front), "Reims : couleur de face par rame")
	var v := VehicleLibrary.for_fleet(angers[0], {"source_id": "angers"})
	check(absf(v.length_m - 32.4) < 0.01 and v.model_family == "citadis_302", "VehicleLibrary.for_fleet : longueur du plan (%.1f m)" % v.length_m)
	var bx := VehicleLibrary.default_for({"source_id": "bordeaux", "id": "bordeaux_a"})
	check(absf(bx.length_m - 43.989) < 0.01, "Bordeaux : 44 m (dims de livrée)")
	# Nantes : Citadis X05 nantais (plan dédié, 45,6 m, 8 portes doubles par côté), Urbos 3 sur la ligne 1
	var n1: Array = TramModel.fleet_for({"source_id": "nantes", "id": "nantes_1"}).map(func(e): return e.family)
	var n2: Array = TramModel.fleet_for({"source_id": "nantes", "id": "nantes_2"}).map(func(e): return e.family)
	check("citadis_x05_nantes" in n1 and "urbos" in n1 and "citadis_x05_nantes" in n2 and not "urbos" in n2, "flotte de Nantes : L1 %s, L2 %s" % [n1, n2])
	var xn := TramModel.livery_for({"source_id": "nantes", "id": "nantes_1"}, {"family": "citadis_x05_nantes"})
	var rx := TramModel.build_rig(xn)
	var right := rx.leaves.filter(func(lf): return float(lf.side) > 0.0).size()
	check(absf(rx.length - 45.6) < 0.01 and right == 16, "Citadis X05 Nantes : %.1f m, %d vantaux côté droit (8 portes doubles)" % [rx.length, right])
	for m in rx.modules: m.free()
	var un := VehicleLibrary.for_fleet(TramModel.fleet_for({"source_id": "nantes", "id": "nantes_1"}).filter(func(e): return e.family == "urbos")[0], {"source_id": "nantes"})
	check(absf(un.length_m - 37.966) < 0.01, "Urbos 3 nantais : %.2f m" % un.length_m)
	check(TramModel.research("citadis_x05_nantes").get("sources", []).size() >= 2, "Citadis X05 Nantes : fiche sourcée")
	# catalogue : vignettes, familles par ville, fiche technique
	for id in ids:
		var tex := Catalogue.thumb(id)
		check(tex != null and tex.get_width() == 512 and tex.get_height() == 288, "%s : vignette 512×288" % id)
	var fams := Catalogue.families()
	check(fams.size() == ids.size(), "catalogue : %d familles" % fams.size())
	var in_nantes: Array = fams.filter(func(f): return "Nantes" in f.cities).map(func(f): return f.id)
	check("citadis_dualis" in in_nantes and "citadis_x05_nantes" in in_nantes and "incentro" in in_nantes, "catalogue filtré Nantes : %s" % str(in_nantes))
	var lx := Catalogue.lines_for("citadis_x05_nantes")
	check(not lx.is_empty() and lx[0].city == "Nantes", "catalogue : lignes du X05 nantais (%d)" % lx.size())
	var txt := TramSheet.sheet_text("citadis_x05_nantes", VehicleLibrary.for_fleet(lx[0].entry, lx[0].meta), lx[0].meta)
	check(txt.contains("45.60 m") and txt.contains("estimé") and txt.contains("metropole.nantes.fr"), "fiche : longueur, valeurs estimées, sources")
	quit(1 if fails > 0 else 0)
