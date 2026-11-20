extends SceneTree
var fails := 0
func _initialize() -> void:run.call_deferred()
func run() -> void:
	var total := 0;var groups := 0;var before := 0
	for id in TramModel.plan_ids():
		var plan := TramModel.plan(id)
		var liv := TramModel.livery_for({"source_id":"test","id":"test_1","color":"#c8102e"},{"family":id})
		var rig := TramModel.build_rig(liv,float(plan.length_m),true)
		var profile := VehicleProfile.new();profile.width_m=float(plan.width_m);profile.length_m=float(plan.length_m)
		var parent := Node3D.new();root.add_child(parent)
		for module in rig.modules:parent.add_child(module)
		TramInterior.attach(rig,profile)
		for i in rig.modules.size():
			var fitout := rig.modules[i].get_node_or_null("PassengerInterior")
			if fitout==null:fails+=1;printerr("ECHEC: missing fit-out ",id);continue
			groups+=int(fitout.get_meta("batched_draw_groups"));before+=int(fitout.get_meta("unbatched_meshes"))
			for seat in fitout.get_meta("seats",[]):
				if absf(seat.x)>profile.width_m*.5 or absf(seat.z)>rig.module_lengths[i]*.5:fails+=1;printerr("ECHEC: seat outside envelope ",id)
		parent.queue_free();await process_frame;total+=1
	print("FAMILIES|",total,"|INTERIOR_SOURCE_MESHES|",before,"|BATCH_GROUPS|",groups)
	print("TOTAL_ECHECS|",fails);quit(1 if fails else 0)
