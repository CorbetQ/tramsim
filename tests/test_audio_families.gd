extends SceneTree
var failures := 0
func check(ok: bool, message: String) -> void:
	if ok: print("ok: ",message)
	else: failures += 1; printerr("ECHEC: ",message)
func _init() -> void:
	_run.call_deferred()
func state(v: float, extras: Dictionary = {}) -> Dictionary:
	var result := {"speed":v,"notch":1.0,"power_ok":true,"pantograph_up":true,"external":true}
	result.merge(extras,true); return result
func _run() -> void:
	var counts := {"exact_family":0,"related_family":0,"synthetic":0,"modeled":0}
	for family in TramModel.plan_ids():
		var p := TramAudio.profile_for(family)
		check(not p.is_empty() and counts.has(p.get("quality","")),family+" : couverture déclarée")
		counts[p.quality] += 1
		var ta := TramAudio.new(null,null,family); root.add_child(ta)
		check(ta.players.size()==TramAudio.LOOPS.size()+TramAudio.SHOTS.size(),family+" : tous les flux chargés")
		if p.quality in ["exact_family","related_family"]:
			var bank:Dictionary=p.bank_data
			check((bank.recorded_family==family)==(p.quality=="exact_family"),family+" : apparentement honnête")
			check(ta.streams.motor.resource_path.ends_with(bank.streams.motor),family+" : captation effectivement sélectionnée")
			for i in 40:ta.update_state(state(2.0),0.1)
			check(ta.gain.motor>0.9 and ta.gain.motor_hum<0.01,family+" : régime bas")
			for i in 40:ta.update_state(state(15.0),0.1)
			check(ta.gain.motor<0.01 and ta.gain.motor_hum>0.9,family+" : fondu régime haut")
			check(ta._active("motor").pitch_scale<=1.16,family+" : hauteur bornée, sans accélérer excessivement les captations")
			for i in 40:ta.update_state(state(0.0),0.1)
			check(ta.gain.motor<0.01 and ta.gain.motor_hum<0.01,family+" : silence de traction à l’arrêt")
		if family=="translohr":
			check(ta.players.real_rail.db<=-90.0 and ta.players.joint.db<=-90.0,"Translohr : pas de texture métallique ferroviaire")
			ta.squeal_chance=1.0
			for i in 40:ta.update_state(state(6.0,{"curvature":9.0}),0.1)
			check(ta.gain.squeal==0.0 and ta.streams.rolling.resource_path.contains("tyre_rolling"),"Translohr : roulement de pneus, pas de crissement")
		for i in 40:ta.update_state(state(6.0,{"underground":true}),0.1)
		check(ta.players.motor.p3.bus==TramAudio.TUNNEL_BUS,family+" : réverbération en tunnel")
		ta.update_state(state(6.0,{"bridge":true}),0.1)
		check(ta.players.motor.p3.bus==TramAudio.BRIDGE_BUS,family+" : résonance de pont")
		ta.queue_free(); await process_frame
	check(counts.exact_family==6 and counts.related_family==4 and counts.synthetic==8 and counts.modeled==2,"20 familles : 6 captées, 4 apparentées, 8 synthétiques, 2 modélisées")
	print("TOTAL_ECHECS|",failures); quit(1 if failures else 0)
