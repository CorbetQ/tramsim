extends SceneTree
var fails:=0
func check(ok:bool,label:String)->void:
 if ok:print("ok: ",label)
 else:fails+=1;printerr("ECHEC: ",label)
func _init()->void:run.call_deferred()
func run()->void:
 var entries:=NetworkRegistry.entries()
 var net:=NetworkLoader.new();check(net.load_file("res://data/free/nantes.json").is_empty(),"réseau physique de Nantes chargé")
 var choices:=FreeStartCatalog.lines(entries.filter(func(e):return e.city=="Nantes"),net)
 check(choices.size()==6,"trois lignes urbaines, deux tram-trains et Dépôts")
 for ref in ["TER T1","TER T2"]:
  var c:Dictionary=choices.filter(func(e):return e.line==ref)[0]
  var stops:=FreeStartCatalog.stops(net,c)
  check(stops.size()==(11 if ref=="TER T1" else 8),ref+" : tous les arrêts OSM présents")
  check(stops.all(func(s):return net.edge_info.has(s.edge) and s.snap_m<15 and s.source_relation>0),ref+" : arrêts sur des voies réelles avec provenance")
  check(stops[0].name=="Nantes",ref+" : départ gare de Nantes")
 var depot:Dictionary=choices.filter(func(e):return e.depot)[0]
 check(FreeStartCatalog.stops(net,depot).size()==4,"les quatre dépôts nantais sont proposés dans Dépôts")
 var missing:=[]
 for city in NetworkRegistry.cities():
  var city_entries:=entries.filter(func(e):return e.city==city)
  var first:=NetworkLoader.new();first.load_file(city_entries[0].path)
  var path:="res://data/free/"+str(first.meta.get("source_id",""))+".json"
  if not FileAccess.file_exists(path):continue
  var n:=NetworkLoader.new();n.load_file(path)
  for choice in FreeStartCatalog.lines(city_entries,n):
   if FreeStartCatalog.stops(n,choice).is_empty():missing.append(city+":"+str(choice.line))
 check(missing.is_empty(),"chaque ligne proposée possède des départs : "+str(missing))
 var main=load("res://src/ui/main.tscn").instantiate();root.add_child(main)
 main.save.settings.home_bg=false;main.menu_city="Nantes";main.menu_page="setup";main.free_mode=true;main._build_menu()
 for i in 8:await process_frame
 var t0:=Time.get_ticks_msec()   # préchargement de la ville (données LiDAR plus riches) : attendre qu'il soit prêt
 while not main.city_preload.is_ready("Nantes") and Time.get_ticks_msec()-t0<120000:await process_frame
 for i in 4:await process_frame
 var line:TouchChoice=main.find_child("line_choice",true,false);var stop:TouchChoice=main.find_child("stop_choice",true,false)
 check(line!=null and line.is_visible_in_tree() and line.item_count==6,"configuration libre : ligne visible avant le départ")
 var tt_index:=-1;var depot_index:=-1
 for i in line.item_count:
  if line.get_item_text(i).begins_with("TER T2"):tt_index=i
  if line.get_item_text(i)=="Dépôts":depot_index=i
 line.select(tt_index);line.item_selected.emit(tt_index)
 for i in 3:await process_frame
 check(stop.item_count==8 and stop.get_item_text(7)=="Clisson","choisir TER T2 affiche les huit gares jusqu'à Clisson")
 line.select(depot_index);line.item_selected.emit(depot_index)
 for i in 3:await process_frame
 check(stop.item_count==4 and not main._menu.go.disabled,"choisir Dépôts donne quatre emplacements de départ valides")
 main._menu.b_mis.button_pressed=true
 for i in 3:await process_frame
 check(line.item_count==7,"missions nantaises : services urbains existants sans faux horaires tram-train")
 main.free();await process_frame
 print("TOTAL_ECHECS|",fails);quit(1 if fails else 0)
