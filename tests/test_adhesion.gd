extends SceneTree
var fails:=0
func check(ok:bool,msg:String)->void:
 if ok:print("ok: ",msg)
 else:fails+=1;printerr("ECHEC: ",msg)
func _init()->void:
 var p:=VehicleLibrary.citadis_302()
 var gentle:=TrainPhysics.new(p);var hard:=TrainPhysics.new(p)
 for i in 10:gentle.step(.05,.25,0);hard.step(.05,1,0)
 check(not gentle.wheel_slip and hard.wheel_slip,"traction progressive adhérente ; pleine traction patine au démarrage")
 check(hard.slip_ratio>0 and hard.speed>gentle.speed,"patinage mesuré sans immobilisation artificielle")
 var wet:=TrainPhysics.new(p);wet.adhesion=.14
 var dry:=TrainPhysics.new(p)
 for i in 80:wet.step(.05,1,0);dry.step(.05,1,0)
 check(wet.position<dry.position,"rail humide : adhérence et accélération réduites")
 for i in 30:hard.step(.05,0,0)
 check(not hard.wheel_slip and hard.slip_ratio==0,"réduction de traction : fin du patinage")
 var rollback:=TrainPhysics.new(p)
 for i in 40:rollback.step(.05,0,.04)
 check(rollback.velocity<-.3 and rollback.position<0 and rollback.rollback,"frein relâché en montée : recul réel sous la gravité")
 check(rollback.speed==absf(rollback.velocity),"HUD et portes utilisent la norme de la vitesse")
 for i in 80:rollback.step(.05,-.75,.04)
 check(rollback.velocity==0,"F3 arrête puis maintient une rame qui reculait")
 for grade in [-.08,.08]:
  var hold:=TrainPhysics.new(p)
  for i in 80:hold.step(.05,-.75,grade)
  check(hold.speed==0,"F3 retient dès le spawn sur pente %s"%grade)
 var reverse:=TrainPhysics.new(p);reverse.velocity=-2
 for i in 80:reverse.step(.05,1,0)
 check(reverse.velocity>0,"traction rattrape le recul puis repart vers l’avant sans changer de cabine")
 var n:=NetworkLoader.new();n.load_file("res://tests/fixtures/schema_test.json")
 var session:=FreeSession.new(n,p,"e1",.02,false)
 session.route=["e0","e1"];session.route_dir=[1,1];session.phys.velocity=-1
 session._advance(-.2)
 check(session.edge_id=="e0" and absf(session.offset-899.82)<.001 and session.direction==1,"recul à travers un nœud : position et orientation de cabine correctes")
 session=FreeSession.new(n,p,"e1",.02,false);session.phys.velocity=-1;session._advance(-.2)
 check(session.edge_id=="e0" and session.direction==1,"recul avant le point de spawn : prédécesseur retrouvé dans le graphe")
 session=FreeSession.new(n,p,"e0",100.0,false);n.edge_info.e0.grade=.04
 session.set_doors(true)
 for i in 100:session.tick(.05,0.0)
 check(session.phys.speed==0 and session.offset==100.0,"portes ouvertes : frein de maintien automatique en rampe")
 var collision_net:=NetworkLoader.new();collision_net.load_file("res://tests/fixtures/schema_test.json")
 var collision:=FreeSession.new(collision_net,p,"e1",.02,false)
 collision_net.graph.occupy("e0","OTHER");collision.phys.velocity=-1;collision._advance(-.2)
 check(collision.blocked and collision.edge_id=="e1" and collision_net.graph.edges.e1.occupied_by=="T1","recul vers voie occupée : arrêt et occupation cohérents")
 var change:=FreeSession.new(n,p,"e0",100,false);change.phys.velocity=-.09
 change.reverse()
 check(change.phys.velocity>0,"changement de cabine : vitesse signée dans le nouveau repère")
 print("TOTAL_ECHECS|",fails);quit(1 if fails else 0)
