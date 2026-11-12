extends SceneTree
var fails:=0
func check(ok:bool,msg:String)->void:
 if ok:print("ok: ",msg)
 else:fails+=1;printerr("ECHEC: ",msg)
class WireView extends Node3D:
 var net:NetworkLoader
 var sectors:Dictionary={}
 var wire_vertices:=PackedVector3Array()
 func pos3(id:String,at:float)->Vector3:
  var p:Dictionary=net.point_on(id,at);return Vector3(p.p.x,p.y,p.p.y)
 func _frame(id:String,at:float)->Transform3D:
  var p:Dictionary=net.point_on(id,at)
  return Transform3D(Basis.looking_at(Vector3(p.dir.x,0,p.dir.y),Vector3.UP),pos3(id,at))
 func _add_geo(_parent:Node3D,g,material:Material)->void:
  if material is StandardMaterial3D:wire_vertices.append_array(g.v)

func _init()->void:
 var city:=CityScene.new();var geo:=CityScene._Arrays.new()
 city._ribbon(geo,PackedVector2Array([Vector2(0,0),Vector2(10,0),Vector2(10,10)]),4,0,Color.WHITE)
 var bound:=AABB(geo.v[0],Vector3.ZERO)
 for v in geo.v:bound=bound.expand(v)
 check(bound.position.x==0 and bound.end.z==10,"ruban routier : aucun dépassement longitudinal aux extrémités")
 check(geo.v[2]==geo.v[7] or geo.v[2]==geo.v[6],"raccord routier : sommets du joint partagés")
 city._decks=[[0,8.0,PackedVector3Array([Vector3(30,8,0),Vector3(60,8,0)]),Vector2i.ZERO]]
 for x in range(0,4):city._deck_cells[Vector2i(x,0)]=[[0,0]]
 check(city._deck_for_line(PackedVector2Array([Vector2(0,0),Vector2(200,0)]),false)==0,"pont court au début d’une longue route : tablier détecté")
 check(city._deck_for_line(PackedVector2Array([Vector2(45,-20),Vector2(45,20)]),false)==-1,"la route sous un pont transversal ne monte pas dessus")
 check(city._deck_for_line(PackedVector2Array([Vector2(0,0),Vector2(200,0)]),true)==-1,"pont routier distinct d’une voie ferrée")
 for x in range(0,7):city._road_level_cells[Vector2i(x,0)]=[[Vector2(0,0),Vector2(200,0),0]]
 check(city._known_road_level(Vector2(45,0),Vector2.RIGHT)==0,"niveau IGN au sol reconnu sous l’ouvrage")
 check(city._deck_for_line(PackedVector2Array([Vector2(0,0),Vector2(200,0)]),false)==-1,"une voie IGN au niveau zéro n’est pas projetée sur un pont parallèle")
 city._road_level_cells.clear()
 var approach:=city._bridge_approach(20,0,0,0)
 check(approach>0 and approach<8,"rampe d’approche continue à l’extérieur du tablier")
 check(city._bridge_approach(20,20,0,0)==0,"la rampe ne soulève pas la voirie voisine")
 for i in CityScene.TREE_KINDS:check(CityScene._tree_mesh(i).get_surface_count()>0,"végétation %d : maillage valide"%i)
 var identities:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/city_identity.json"))
 var styles:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/city_styles.json"))
 check(identities.size()==styles.cities.size(),"toutes les villes ont un profil de matériaux")
 check(identities.toulouse.masonry!=identities.angers.masonry,"brique toulousaine et pierre angevine distinctes")
 var n:=NetworkLoader.new();n.load_file("res://tests/fixtures/schema_test.json")
 for id in ["e0","e1","dep"]:
  n.graph.edges[id].length=10.0;n.edge_info[id].supply="overhead"
  n.edge_info[id].arc=PackedFloat64Array([0.0,10.0])
 n.edge_info.e0.pts=PackedVector2Array([Vector2(0,0),Vector2(10,0)])
 n.edge_info.e1.pts=PackedVector2Array([Vector2(10,0),Vector2(20,0)])
 n.edge_info.dep.pts=PackedVector2Array([Vector2(10,0),Vector2(10,10)])
 n.edge_info.e0.ys=PackedFloat32Array([0,0]);n.edge_info.e1.ys=PackedFloat32Array([0,0]);n.edge_info.dep.ys=PackedFloat32Array([6,6])
 var view:=WireView.new();view.net=n
 for id in n.edge_info:view.sectors[id]=view
 check(not ElectrificationView.support_clear(view,Vector3(5,0,1)),"poteau refusé dans le gabarit d’une voie")
 check(ElectrificationView.support_clear(view,Vector3(5,0,4)),"poteau possible à l’extérieur du gabarit")
 ElectrificationView.junctions(view)
 var correct:=not view.wire_vertices.is_empty()
 for v in view.wire_vertices:correct=correct and v.y<6.3
 check(correct,"intersection : aucun raccord LAC entre voies au sol et branche six mètres plus haut")
 view.free()
 city.free();print("TOTAL_ECHECS|",fails);quit(1 if fails else 0)
