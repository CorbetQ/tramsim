extends SceneTree
var failures := 0
func check(ok: bool, message: String) -> void:
	if ok: print("ok: ",message)
	else: failures += 1; printerr("ECHEC: ",message)
func network() -> NetworkLoader:
	var n := NetworkLoader.new(); n.load_file("res://tests/fixtures/schema_test.json")
	n.stations[0].offset=895.0
	n.stations[0].stop_area={"segments":[["e0",880.0,900.0],["e1",0.0,25.0]]}
	n.edge_info.e0.power_overlaps=[[880.0,900.0]]
	n.edge_info.e1.power_overlaps=[[0.0,25.0]]
	return n
func mission(n: NetworkLoader, edge: String, at: float, dir: int = 1) -> MissionSession:
	var s := MissionSession.new(n,VehicleLibrary.citadis_302_hybride(),edge,at,[0.0,1000.0,2000.0,3000.0] as Array[float])
	s.traffic.enabled=false;s.direction=dir;s.route_dir=[dir]
	if edge=="e1":s.route=["e0","e1"];s.route_dir=[1,dir];s.visited.e0=true
	return s
func _init() -> void:
	var n:=network();var s:=mission(n,"e1",20.0)
	s.tick(0.01,-0.75)
	check(s.next_station==0,"repère dépassé de 25 m et changement d’arête : arrêt toujours actif au quai")
	s.set_doors(true)
	check(s.served,"desserte possible jusqu’au bout du quai, au-delà de l’ancien rayon de 5 m")
	s.set_doors(false);s.phys.speed=1.0;s.tick(0.01,-0.75)
	check(s.next_station==0,"repositionnement après fermeture des portes : station conservée dans la zone")
	var departure_time:=s._departure_time
	s.offset=26.0;s.time_s=200.0;s.tick(0.01,-0.75)
	check(s.next_station==1 and s.scorer.stops.size()==1,"station suivante uniquement après sortie de la zone")
	check(departure_time<1.0 and s.scorer.stops[0].result==MissionScorer.Result.OK,"score basé sur le début du départ, sans décaler l’horaire GTFS")
	s=mission(network(),"e1",20.0);s.tick(0.01,-0.75)
	check(s.next_station==0,"arrêt non desservi encore possible dans la zone")
	s.offset=26.0;s.tick(0.01,-0.75)
	check(s.next_station==1,"arrêt oublié seulement après la fin du quai")
	s=mission(network(),"e0",882.0,-1);s.tick(0.01,-0.75)
	check(s.next_station==0,"même zone dans le sens inverse")
	s.offset=879.0;s.tick(0.01,-0.75)
	check(s.next_station==1,"sens inverse : oubli après la borne basse")
	s=mission(network(),"e0",890.0)
	check(s.power_ok,"LAC disponible à l’entrée du quai de transition")
	check(s.set_power_mode("aps")=="","APS sélectionnable à l’arrêt sur le quai LAC/APS")
	s.tick(0.3,-0.75);check(not s.power_ok,"la double alimentation ne court-circuite pas le délai de commutation")
	s.tick(0.4,-0.75);check(s.power_ok and not s.pantograph_up,"APS alimente la rame sur le même quai")
	s.offset=879.0;s.tick(0.01,-0.75);check(not s.power_ok,"en dehors du recouvrement LAC : APS coupée")
	s=mission(network(),"e1",20.0)
	s.set_power_mode("overhead");s.tick(0.7,-0.75)
	check(s.power_ok and s.pantograph_up,"transition inverse : LAC disponible sur le quai de base APS")
	s.offset=26.0;s.tick(0.01,-0.75);check(not s.power_ok,"en dehors du recouvrement APS : LAC coupée")
	var free:=FreeSession.new(network(),VehicleLibrary.citadis_302_hybride(),"e1",20.0,false)
	check(free.next_station_ahead().name=="Terminus Sud" and free.station_distance(free.next_station_ahead())==0.0,"libre : nom et à-quai conservés après le point et le nœud")
	free.offset=26.0
	check(free.next_station_ahead().name=="Centre","libre : prochaine station après sortie du quai")
	var angers:=NetworkLoader.new();angers.load_file("res://data/free/angers.json")
	var count:=0
	for st in angers.stations:
		if st.name!="Foch-Maison Bleue":continue
		count+=1
		for segment in st.stop_area.segments:
			for at in [float(segment[1])+0.1,float(segment[2])-0.1]:
				check(angers.supplies_at(str(segment[0]),at)==PackedStringArray(["overhead","aps"]),"Foch %s : deux alimentations jusqu’au bout du quai %s"%[st.stop_id,segment[0]])
				var f:=FreeSession.new(angers,VehicleLibrary.citadis_302_hybride(),str(segment[0]),at,false)
				check(f.next_station_ahead().get("stop_id","")==st.stop_id,"Foch %s : arrêt retenu aux deux extrémités"%st.stop_id)
	check(count==2,"les deux directions de Foch–Maison Bleue sont couvertes")
	print("TOTAL_ECHECS|",failures);quit(1 if failures else 0)
