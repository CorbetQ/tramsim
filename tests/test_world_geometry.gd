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
 # sol continu (voirie drapée) : bords de tuile communs, voirie au niveau du maillage, bordures de trottoir
 var tv:=TerrainView.new()
 check(tv.open("angers"),"sol continu d’Angers (TGR1)")
 var seam:=0.0;var tested:=0;var curbs:=0;var paved:=0
 for k in tv.keys:
  if not tv.has_tile(k+Vector2i(1,0)):continue
  var a:=tv.tile(k);var b:=tv.tile(k+Vector2i(1,0))
  for i in 40:
   var z:=i*10.0+3.3
   var ha:=tv.tile_height(a,tv.tile_m-0.001,z);var hb:=tv.tile_height(b,0.001,z)
   if not is_nan(ha) and not is_nan(hb):seam=maxf(seam,absf(ha-hb));tested+=1
  for m in a.mat:
   if m&31 in [RoadView.ASPHALT,RoadView.ASPHALT_MAJOR,RoadView.SIDEWALK]:paved+=1
   if m>>5:curbs+=1
  if tested>2000:break
 check(tested>500 and seam<0.05,"raccord de tuiles sans déchirure (%d points, écart max %.3f m)"%[tested,seam])
 check(paved>1000 and curbs>100,"chaussées et trottoirs dans le maillage (%d triangles, %d bordures)"%[paved,curbs])
 var mesh:=RoadView.build(tv,tv.tile(tv.keys[tv.keys.size()/2]),tv.keys[tv.keys.size()/2],{},null)
 check(mesh.get_surface_count()==1 and mesh.surface_get_format(0)&Mesh.ARRAY_FORMAT_TEX_UV2,"maillage de voirie : identifiant de matériau en UV2")
 tv.free()
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
 # décor élargi (tools/import/periphery.py) : monuments emblématiques couverts, occupation du sol réelle
 var landmarks:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/landmarks.json"))
 check(landmarks.cities.size()==styles.cities.size(),"monuments emblématiques listés pour toutes les villes")
 var ang:=CityScene.new();ang.open("angers",[47.443902,-0.554032])
 var covered:=0
 for lm in landmarks.cities.angers:
  var lat0:=deg_to_rad(47.443902)
  var x:=deg_to_rad(float(lm.lon)+0.554032)*6371008.8*cos(lat0);var z:=-deg_to_rad(float(lm.lat)-47.443902)*6371008.8
  if ang.table.has(Vector2i(floori(x/ang.tile_m),floori(z/ang.tile_m))):covered+=1
 check(covered==landmarks.cities.angers.size(),"Angers : château, cathédrale, gare… dans le décor détaillé (%d/%d)"%[covered,landmarks.cities.angers.size()])
 check(ang.terrain!=null and ang.terrain.land_ok and ang.terrain.land_colors.size()>=8,"Angers : occupation du sol (classes de l’orthophoto)")
 var img:=ang.terrain.land_image(ang.terrain.keys[0],Color.GRAY) if ang.terrain!=null else null
 check(img!=null and img.get_width()==18,"teinte d’occupation du sol par tuile (18 x 18)")
 ang.free()
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
