extends SceneTree
var fails := 0
func check(ok: bool, message: String) -> void:
	if not ok:fails+=1;printerr("FAIL: ",message)
	else:print("ok: ",message)
func _initialize() -> void:run.call_deferred()
func run() -> void:
	check(not CitadisMeshy.preview_exteriors,"unapproved exterior is opt-in")
	for id in CitadisMeshy.VARIANTS:
		var entry := StockCatalog.find(id)
		var liv := TramModel.livery_for({"source_id":entry.network,"id":entry.network+"_1"},entry)
		var key := CitadisMeshy.key_for(id)
		var profile := VehicleProfile.new();profile.variant_id=id;profile.width_m=entry.width;profile.fleet=entry
		var old := TramModel.build_rig(liv,-1,true)
		check(not old.modules[0].has_meta("meshy_experimental"),id+" retains accepted exterior by default")
		CitadisMeshy.preview_exteriors=true
		var rig := TramModel.build_rig(liv,-1,true)
		var stretched := TramModel.build_rig(liv,rig.length+2.0,true)
		check(not stretched.modules[0].has_meta("meshy_experimental"),id+" custom length safely uses procedural rig")
		for module in stretched.modules:module.free()
		check(rig.modules[0].has_meta("meshy_experimental"),id+" loads actual generated GLB")
		check(rig.modules.size()==old.modules.size() and rig.leaves.size()==old.leaves.size(),id+" preserves module and leaf topology")
		check(rig.triangles<55000 and rig.triangles>10000,id+" exterior triangle budget "+str(rig.triangles))
		for i in rig.modules.size():
			check(absf(rig.module_lengths[i]-old.module_lengths[i])<.001,id+" module anchor "+str(i))
			var aabb := rig.modules[i].mesh.get_aabb()
			check(aabb.size.z<=rig.module_lengths[i]+.01,id+" no triangle bridges module "+str(i))
			check(rig.modules[i].has_node("MechanicalScaffold"),id+" roof and bogie mechanics retained")
			root.add_child(rig.modules[i])
		rig.layout_straight()
		for side in ["left","right","both"]:
			var rest: Array=[]
			for leaf in rig.leaves:rest.append(leaf.node.transform)
			rig.set_doors(true,side)
			for frame in 150:rig.update(.05)
			var correct := rig.doors_open()
			for i in rig.leaves.size():
				var leaf: Dictionary=rig.leaves[i]
				var expected: bool=side=="both" or (side=="right")== (float(leaf.side)>0)
				correct=correct and ((not leaf.node.transform.is_equal_approx(rest[i]))==expected)
			check(correct,id+" animated door selection "+side)
			rig.set_doors(false)
			for frame in 150:rig.update(.05)
			check(rig.doors_closed(),id+" doors close without residual movement")
		var up: float=rig.panto.head.position.y
		rig.set_pantograph(false)
		for frame in 150:rig.update(.05)
		check(rig.pantograph_down() and up-rig.panto.head.position.y>1.2,id+" pantograph lowers")
		rig.set_pantograph(true)
		for frame in 150:rig.update(.05)
		check(rig.pantograph_up() and absf(rig.panto.head.position.y-up)<.001,id+" pantograph returns")
		TramInterior.attach(rig,profile);TramInterior.attach(rig,profile)
		var total_seats := 0
		for i in rig.modules.size():
			var interior := rig.modules[i].get_node("PassengerInterior")
			check(str(interior.get_meta("reference_profile"))==key,id+" exact interior profile")
			var seats: Array=interior.get_meta("seats")
			total_seats+=seats.size()
			for seat in seats:
				check(not CitadisInterior.in_door(seat.z,interior.get_meta("door_zones"),.84),id+" seat outside door vestibule")
			var before: Transform3D=interior.global_transform
			rig.modules[i].rotation.y=.2
			check(not before.is_equal_approx(interior.global_transform),id+" interior follows articulation")
			check(interior.get_meta("batched_draw_groups")<interior.get_meta("unbatched_meshes"),id+" draw calls batched")
		check(total_seats>=12,id+" usable modeled seats "+str(total_seats))
		TramInterior.show(rig,true)
		check(rig.modules[0].layers==TramInterior.EXTERIOR_LAYER,id+" passenger view hides opaque exterior")
		TramInterior.show(rig,false)
		check(not rig.modules[0].get_node("PassengerInterior").visible,id+" interior visibility reversible")
		for module in rig.modules:module.free()
		for module in old.modules:module.free()
		CitadisMeshy.preview_exteriors=false
	check(CitadisMeshy.key_for("angers__concept_citadis_405")=="","fictional variant unaffected")
	check(CitadisMeshy.parts("missing_test_profile","seat").is_empty(),"missing asset falls back without loading error")
	print("TOTAL_FAILURES|",fails);quit(1 if fails else 0)
