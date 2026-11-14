extends SceneTree
## Parcours reproductible de toutes les variantes ; les gains sont de l'instrumentation,
## et ne prouvent pas à eux seuls que le mixage réel est audible (voir captures Master).
class AudioView:
	extends Node3D
	var family := ""
	var livery: Dictionary = {}
	var modules: Array = []
var failures := 0
var rows: Array = []
func _initialize() -> void: _run.call_deferred()
func check(ok: bool, message: String) -> void:
	if not ok: failures += 1; printerr("ECHEC: ",message)
func state(kmh: float, notch: float, extra: Dictionary = {}) -> Dictionary:
	var s := {"speed":kmh/3.6,"max_speed":70/3.6,"notch":notch,"doors_open":false,"power_ok":true,"pantograph_up":true,"external":false,"paused":false}
	s.merge(extra,true); return s
func settle(ta: TramAudio, s: Dictionary, frames: int = 90) -> void:
	for i in frames: ta.update_state(s,1.0/60)
func _run() -> void:
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/rolling_stock/variants/index.json"))
	check(catalog.entries.size() == 76,"76 variantes attendues")
	var net := NetworkLoader.new(); net.load_file("res://data/networks/angers_a.json")
	var sched: Array[float] = []
	for i in net.stations.size(): sched.append(120.0+140*i)
	for entry in catalog.entries:
		var before := failures
		var view := AudioView.new(); view.family = entry.family; view.livery = {"variant_id":entry.id}; root.add_child(view)
		var bell := AudioStreamPlayer.new(); root.add_child(bell)
		var ta := TramAudio.new(view,bell,entry.family); root.add_child(ta)
		check(ta.players.size()==TramAudio.LOOPS.size()+TramAudio.SHOTS.size(),entry.id+" : tous lecteurs chargés")
		settle(ta,state(0,0))
		var idle := ta.gain.duplicate()
		check(ta.gain.rolling < 0.01,entry.id+" : arrêt sans roulement")
		settle(ta,state(0,1,{"doors_open":true}))
		check(ta.gain.motor < 0.01 and ta.gain.motor_hum < 0.01,entry.id+" : portes ouvertes sans traction")
		check(ta.shots.get("door_open",0)==1,entry.id+" : événement ouverture")
		settle(ta,state(0,0))
		check(ta.shots.get("door_chime",0)==1 and ta.shots.get("door_close",0)==1,entry.id+" : fermeture différée")
		ta.gong(); check(bell.playing,entry.id+" : gong actif")
		for k in 501: ta.update_state(state(k/10.0,minf(1,k/100.0)),1.0/60)
		var traction := ta.gain.duplicate()
		check(ta.gain.rolling > 0.5,entry.id+" : roulement à 50km/h")
		check(float(ta.gain.motor)+float(ta.gain.motor_hum) > 0.5,entry.id+" : traction audible selon gains")
		settle(ta,state(50,0))
		var coast := ta.gain.duplicate()
		check(float(ta.gain.motor)+float(ta.gain.motor_hum)<float(traction.motor)+float(traction.motor_hum),entry.id+" : roue libre distincte")
		settle(ta,state(30,0.5,{"external":true,"underground":true}))
		check(ta.players.motor.p3.bus==TramAudio.TUNNEL_BUS,entry.id+" : tunnel extérieur")
		settle(ta,state(30,0.5,{"bridge":true}))
		check(AudioServer.get_bus_send(AudioServer.get_bus_index(TramAudio.CAB_BUS))==TramAudio.BRIDGE_BUS,entry.id+" : pont cabine")
		settle(ta,state(30,0.5,{"paused":true}))
		check(ta.is_paused and ta._active("rolling").stream_paused,entry.id+" : pause effective boucle")
		settle(ta,state(30,0.5))
		check(not ta.is_paused and not ta._active("rolling").stream_paused,entry.id+" : reprise")
		for k in range(500,-1,-1): ta.update_state(state(k/10.0,-lerpf(0.25,0.85,1-k/500.0)),1.0/60)
		check(ta.shots.get("brake_mech",0)==1,entry.id+" : freinage final unique")
		settle(ta,state(0,1,{"power_ok":false}),240)
		check(ta.gain.motor < 0.01 and ta.gain.motor_hum < 0.01,entry.id+" : alimentation indisponible sans traction")
		settle(ta,state(0,1,{"pantograph_up":false}),240)
		check(ta.gain.motor < 0.01 and ta.gain.motor_hum < 0.01,entry.id+" : pantographe baissé sans traction")
		# Urgence avec manipulateur resté en traction : coupe la consigne immédiatement.
		ta.update_state(state(30,1,{"emergency":true}),1.0/60)
		check(ta.state.traction_load == 0.0 and ta.state.regen_load == 0.0,entry.id+" : urgence prioritaire sur cran positif")
		check(ta.shots.get("emergency",0)==1,entry.id+" : événement urgence unique")
		ta.update_state(state(30,1,{"emergency":true}),1.0/60)
		check(ta.shots.get("emergency",0)==1,entry.id+" : urgence maintenue sans redéclenchement")
		var profile := VehicleLibrary.for_fleet(entry)
		var session := MissionSession.new(net,profile,net.meta.edges[0].id,100,sched,40)
		for i in 60:
			session.tick(1.0/30,1.0); ta.update(session,1,false,false,false,1.0/30)
		check(session.phys.speed>0 and ta.state.speed==session.phys.speed,entry.id+" : MissionSession transmet vitesse")
		rows.append({"variant":entry.id,"family":entry.family,"quality":ta.sound_profile.get("quality","synthetic"),"idle":idle,"traction_50kmh":traction,"coasting_50kmh":coast,"shots":ta.shots.duplicate(),"failures":failures-before})
		print("VARIANT|",entry.id,"|",failures-before)
		ta.queue_free(); view.queue_free(); bell.queue_free(); await process_frame
	var report := {"variants":rows.size(),"failures":failures,"scope":"instrumentation and real MissionSession; no audible output claims in Dummy mode","rows":rows}
	var f := FileAccess.open("res://samples/tests/audio_variants.json",FileAccess.WRITE); f.store_string(JSON.stringify(report,"\t")); f.close()
	print("TOTAL_ECHECS|",failures); quit(1 if failures else 0)
