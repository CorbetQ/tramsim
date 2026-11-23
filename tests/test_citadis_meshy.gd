extends SceneTree
var fails := 0
func check(ok: bool, message: String) -> void:
	if not ok:fails+=1;printerr("FAIL: ",message)
	else:print("ok: ",message)
func _initialize() -> void:run.call_deferred()
func run() -> void:
	check(CitadisMeshy.exteriors_enabled,"coherent stylised set is enabled")
	for id in CitadisMeshy.VARIANTS:
		var entry := StockCatalog.find(id)
		var liv := TramModel.livery_for({"source_id":entry.network,"id":entry.network+"_1"},entry)
		var key := CitadisMeshy.key_for(id)
		var profile := VehicleProfile.new();profile.variant_id=id;profile.width_m=entry.width;profile.fleet=entry
		CitadisMeshy.exteriors_enabled=false
		var old := TramModel.build_rig(liv,-1,true)
		check(not old.modules[0].has_meta("meshy_experimental"),id+" explicit legacy comparison uses full old rig")
		CitadisMeshy.exteriors_enabled=true
		var rig := TramModel.build_rig(liv,-1,true)
		var stretched := TramModel.build_rig(liv,rig.length+2.0,true)
		check(not stretched.modules[0].has_meta("meshy_experimental"),id+" custom length safely uses procedural rig")
		for module in stretched.modules:module.free()
		var altered:=liv.duplicate(true)
		var changed:Array=[]
		for size_ in old.module_lengths:changed.append(float(size_))
		changed[0]+=.5;changed[1]-=.5
		altered.stock_entry.geometry={"module_lengths":changed}
		var incompatible:=TramModel.build_rig(altered,-1,true)
		check(not incompatible.modules[0].has_meta("meshy_experimental"),id+" rejects different body lengths despite matching total")
		for module in incompatible.modules:module.free()
		check(rig.modules[0].has_meta("meshy_experimental"),id+" loads complete reconstructed GLB")
		check(rig.modules.size()==old.modules.size() and rig.leaves.size()==old.leaves.size(),id+" preserves module and leaf topology")
		check(rig.triangles<25000 and rig.triangles>2500,id+" exterior triangle budget "+str(rig.triangles))
		if key=="nantes405":
			for end_index in [0,rig.modules.size()-1]:
				var module: MeshInstance3D=rig.modules[end_index]
				var arrays := module.mesh.surface_get_arrays(0)
				var positions: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
				var tags: PackedVector2Array=arrays[Mesh.ARRAY_TEX_UV]
				var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
				var cells := {};var rows := {};var luminous_triangles := 0
				var direction := -1.0 if end_index==0 else 1.0
				for triangle in range(0,indices.size(),3):
					var a := indices[triangle];var b := indices[triangle+1];var c := indices[triangle+2]
					var centre := (positions[a]+positions[b]+positions[c])/3.0
					if tags[a].x>.2 or centre.y<.64 or centre.y>1.20:continue
					if direction*centre.z<rig.module_lengths[end_index]*.5-.70:continue
					luminous_triangles+=1
					var row := floori((centre.y-.64)/.109)
					rows[row]=true;cells[Vector2i(floori((centre.x+1.04)/.14),row)]=true
				check(luminous_triangles>=240 and cells.size()>=45 and rows.size()>=5,"Naolib end %d: full-width five-row honeycomb optics (%d triangles / %d occupied cells)"%[end_index,luminous_triangles,cells.size()])
			check(not rig.modules[0].has_node("Brand") and rig.modules[0].has_node("NaolibLeft") and rig.modules[0].has_node("NaolibRight"),"Naolib logos are on the white side cheeks, not in place of the optics")
		for i in rig.modules.size():
			check(absf(rig.module_lengths[i]-old.module_lengths[i])<.001,id+" module anchor "+str(i))
			var aabb := rig.modules[i].mesh.get_aabb()
			check(aabb.size.z<=rig.module_lengths[i]+.01,id+" no triangle bridges module "+str(i))
			check(not rig.modules[i].has_node("MechanicalScaffold"),id+" no legacy casing overlay")
			var nodes: Array=[rig.modules[i]]
			nodes.append_array(rig.modules[i].find_children("*","MeshInstance3D",true,false))
			for node in nodes:
				check(int(node.get_meta("citadis_asset_revision",0))==2,id+" complete visible mesh replaced: "+str(node.name))
				var faces: PackedVector3Array=node.mesh.get_faces()
				var degenerate := 0
				for triangle in range(0,faces.size(),3):
					if (faces[triangle+1]-faces[triangle]).cross(faces[triangle+2]-faces[triangle]).length_squared()<1e-16:degenerate+=1
				check(degenerate==0,id+" no zero-area triangles: "+str(node.name))
				for surface in node.mesh.get_surface_count():
					var mat: ShaderMaterial=node.mesh.surface_get_material(surface)
					check(node.mesh.get_surface_count()==1 and mat.get_shader_parameter("vertex_palette")==true,id+" one palette surface per part")
					check(mat!=null and mat.get_shader_parameter("base_texture")==null,id+" no photographic projection: "+str(node.name))
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
		CitadisMeshy.exteriors_enabled=true
	check(CitadisMeshy.key_for("angers__concept_citadis_405")=="","fictional variant unaffected")
	check(CitadisMeshy.parts("missing_test_profile","seat").is_empty(),"missing asset falls back without loading error")
	print("TOTAL_FAILURES|",fails);quit(1 if fails else 0)
