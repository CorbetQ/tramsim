extends SceneTree
var failures:=0
func check(ok:bool,label:String)->void:
 if ok:print("ok: ",label)
 else:failures+=1;printerr("ECHEC: ",label)
func _init()->void:run.call_deferred()
func run()->void:
 root.size=Vector2i(640,360);UiLayout.configure(root)
 var sheet:=TramSheet.new("citadis_302","Angers","angers__citadis_302");sheet.theme=UiTheme.build();root.add_child(sheet)
 for i in 8:await process_frame
 check(sheet.preview.size.x<=640,"aperçu contenu sur un téléphone de 640 × 360 px")
 check(sheet.drive_btn.size.x<=640,"bouton de conduite contenu sur petit écran")
 check(sheet.variants[sheet.livery_opt.selected].id=="angers__citadis_302","variante Irigo précise sélectionnée")
 var destination:=-1
 for i in sheet.destinations.size():
  if str(sheet.destinations[i].source_id)=="nantes":destination=i
 check(destination>=0,"réseau de Nantes disponible pour une rame Irigo")
 var picks:Array=[];sheet.drive.connect(func(pick):picks.append(pick))
 sheet.target_opt.select(destination);sheet.target_opt.item_selected.emit(destination);sheet.drive_btn.pressed.emit()
 check(picks.size()==1 and picks[0].variant_id=="angers__citadis_302" and picks[0].source=="nantes" and picks[0].free,"choix transmis sans repeindre ni remplacer la rame")
 check(sheet.destinations.all(func(target):return target.guidance=="steel"),"aucun réseau sur pneus proposé à l'Irigo")
 await RenderingServer.frame_post_draw
 DirAccess.make_dir_recursive_absolute("res://.cache")
 root.get_texture().get_image().save_png("res://.cache/stock-ui-phone.png")
 sheet.free();await process_frame
 var catalogue:=Catalogue.new("Nantes");catalogue.theme=UiTheme.build();root.add_child(catalogue)
 for i in 5:await process_frame
 check(catalogue.grid.get_child_count()==6,"six variantes et concept Naolib à Nantes, sans doublons de lignes")
 check(catalogue.grid.columns==1,"catalogue sur une colonne à 640 × 360 px")
 catalogue.free();await process_frame
 print("TOTAL_ECHECS|",failures);quit(1 if failures else 0)
