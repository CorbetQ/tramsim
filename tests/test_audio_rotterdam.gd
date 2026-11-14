extends SceneTree
## Approved source must reach every302 variant, with no captured acceleration falsely used as braking.
var failures := 0
func check(ok:bool,message:String)->void:
	if not ok:failures+=1;printerr("ECHEC: ",message)
func _initialize()->void:_run.call_deferred()
func settle(ta:TramAudio,s:Dictionary)->void:
	for i in 120:ta.update_state(s,1.0/30.0)
func st(speed:float,notch:float,extra:Dictionary={})->Dictionary:
	var result:Dictionary={"speed":speed,"notch":notch,"external":false,"power_ok":true,"pantograph_up":true}
	result.merge(extra,true);return result
func _run()->void:
	var catalog:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/rolling_stock/variants/index.json"))
	var count:=0
	for entry in catalog.entries:
		if entry.family!="citadis_302":continue
		count+=1
		var p:Dictionary=TramAudio.profile_for(entry.family,entry.id)
		check(p.bank=="rotterdam_citadis_traction",entry.id+" : banque approuvée sélectionnée")
		check(p.quality=="related_family",entry.id+" : source apparentée déclarée")
		check(p.bank_data.get("traction_only",false),entry.id+" : départ enregistré réservé à la traction")
	check(count==15,"15 variantes302 couvertes")
	var ta:=TramAudio.new(null,null,"citadis_302");root.add_child(ta)
	check(ta.streams.motor.resource_path.contains("rotterdam"),"flux de la captation chargé")
	settle(ta,st(5,0.2));var light:float=ta.gain.motor+ta.gain.motor_hum
	settle(ta,st(5,1));var full:float=ta.gain.motor+ta.gain.motor_hum
	check(full>light*1.2,"effort progressif perceptible dans les commandes de gain")
	settle(ta,st(5,0));check(ta.gain.motor+ta.gain.motor_hum<full*.2,"roue libre : retrait de traction")
	settle(ta,st(5,-1));check(ta.gain.motor+ta.gain.motor_hum<full*.2,"freinage : pas de départ enregistré présenté comme régénération")
	check(ta.gain.regen>.8,"frein électrique distinct maintenu")
	settle(ta,st(5,1,{"doors_open":true}));check(ta.state.traction_load==0,"portes ouvertes : traction interdite")
	settle(ta,st(5,1,{"emergency":true}));check(ta.state.traction_load==0,"urgence prioritaire")
	settle(ta,st(0,1));check(ta.gain.motor+ta.gain.motor_hum<.01,"arrêt : aucune boucle de départ permanente")
	print("ROTTERDAM_VARIANTS|",count,"|TOTAL_ECHECS|",failures);quit(1 if failures else 0)
