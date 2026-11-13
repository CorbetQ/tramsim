extends SceneTree
var fails := 0
func check(ok: bool, label: String) -> void:
 if ok: print("ok: ", label)
 else: fails += 1; printerr("ECHEC: ", label)
func _init() -> void: run.call_deferred()
func area(mesh: ArrayMesh) -> float:
 var v: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
 var result := 0.0
 for i in range(0, v.size(), 3): result += absf((v[i+2]-v[i]).cross(v[i+1]-v[i]).y) * 0.5
 return result
func run() -> void:
 var load_control := HomeBackground.LoadControl.new(); load_control.cancel()
 var unopened := CityScene.new()
 check(not unopened.warm(Vector3.ZERO, load_control) and unopened.built.is_empty(), "une vue d'accueil annulée ne continue pas à charger la ville")
 unopened.free()
 var terrain := TerrainView.new(); root.add_child(terrain)
 var tile := TerrainView.Tile.new()
 tile.pos = PackedVector3Array([Vector3(0,10,0),Vector3(400,10,0),Vector3(400,10,400),Vector3(0,10,400)])
 tile.tri = PackedInt32Array([0,1,2,0,2,3]); tile.mat = PackedByteArray([0,0])
 terrain._cache[Vector2i.ZERO] = tile; terrain.table[Vector2i.ZERO] = [0,0,0]
 terrain._far_nx=2; terrain._far_nz=2; terrain._far_x0=-10000; terrain._far_z0=-10000; terrain._far_step=20000
 terrain._far_h=PackedFloat32Array([0,0,0,0])
 terrain.update_far(Vector3(0,1000,0),{})
 var all_count: int = terrain._far_mesh.mesh.surface_get_array_len(0)
 var expected := 6 * int(pow(TerrainView.FAR_RADIUS*2/TerrainView.FAR_STEP,2))
 check(all_count==expected,"terrain lointain continu tant que la tuile détaillée n'est pas affichée")
 terrain.update_far(Vector3(0,1000,0),{Vector2i.ZERO:true})
 var count: int = terrain._far_mesh.mesh.surface_get_array_len(0)
 check(all_count-count==24,"seules les quatre cellules entièrement couvertes par la tuile affichée sont retirées")
 terrain.update_far(Vector3(0,1000,0),{})
 check(terrain._far_mesh.mesh.surface_get_array_len(0)==all_count,"déchargement d'une tuile : la couverture lointaine est rétablie sans déplacement caméra")
 var cut := TrackView.KeepOut.new(); cut.add_segment(Vector2(240,120),Vector2(290,150),3.0)
 var mesh := RoadView.build(terrain,tile,Vector2i.ZERO,{},cut)
 var remaining := area(mesh)
 check(remaining>159000 and remaining<159900,"ouverture de tunnel précise sans supprimer un demi-quartier : %.1f m² conservés" % remaining)
 var arrays := mesh.surface_get_arrays(0);var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
 var center := Vector2(265,135);var contains:=false;var height_ok:=true;var winding_ok:=true
 for i in range(0,vertices.size(),3):
  var a:=vertices[i];var b:=vertices[i+1];var c:=vertices[i+2]
  if Geometry2D.point_is_inside_triangle(center,Vector2(a.x,a.z),Vector2(b.x,b.z),Vector2(c.x,c.z)):contains=true
  height_ok=height_ok and absf(a.y-10)<0.001 and absf(b.y-10)<0.001 and absf(c.y-10)<0.001
  winding_ok=winding_ok and (c-a).cross(b-a).y>0
 check(not contains,"l'intérieur de la trémie reste réellement ouvert")
 check(height_ok,"les altitudes du relief sont conservées par la découpe")
 check(winding_ok,"toutes les faces du sol sont orientées vers le haut")
 terrain.queue_free();await process_frame
 var mountains:=TerrainView.new();root.add_child(mountains)
 check(mountains.open("grenoble"),"lecture native du terrain TGR2 de Grenoble")
 var altitude:=mountains.height(-200,-9800)
 check(altitude>400 and altitude<460,"relief de Grenoble cohérent avec le MNT IGN, sans saut de 655 m : %.2f" % altitude)
 mountains.queue_free();await process_frame
 print("TOTAL_ECHECS|",fails);quit(1 if fails else 0)
