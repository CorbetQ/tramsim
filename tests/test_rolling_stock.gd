extends SceneTree
## Matériel roulant : chaque plan se construit (modules, longueur, budget de triangles), les animations
## (portes, pantographe) atteignent leurs états, la flotte des réseaux est résolue depuis data/rolling_stock.
var fails := 0
const BUDGET := 6500

func check(c: bool, m: String) -> void:
	if not c: fails += 1; printerr("ECHEC: ", m)
	else: print("ok: ", m)

func _init() -> void:
	var ids := TramModel.plan_ids()
	check(ids.size() >= 19, "%d plans trouvés" % ids.size())
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
	check(mtp.family == "citadis_402" and (mtp.base as Color).is_equal_approx(Color("#377ae6")), "Montpellier L1 : livrée hirondelles")
	var v := VehicleLibrary.for_fleet(angers[0], {"source_id": "angers"})
	check(absf(v.length_m - 32.4) < 0.01 and v.model_family == "citadis_302", "VehicleLibrary.for_fleet : longueur du plan (%.1f m)" % v.length_m)
	var bx := VehicleLibrary.default_for({"source_id": "bordeaux", "id": "bordeaux_a"})
	check(absf(bx.length_m - 44.0) < 0.01, "Bordeaux : 44 m (dims de livrée)")
	quit(1 if fails > 0 else 0)
