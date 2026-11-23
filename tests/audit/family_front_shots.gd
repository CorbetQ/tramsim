extends SceneTree
## Real Godot contact sheets, not AI illustrations. Optional output directory argument.
const CITADIS := ["angers__concept_citadis_205","angers__citadis_x05","angers__concept_citadis_405","nantes__concept_citadis_205","nantes__concept_citadis_305","nantes__citadis_x05_nantes"]
const TFS := ["nantes__tfs","nantes__concept_tfs_2","idf__concept_tfs_1","idf__tfs__t1"]
var out := "res://.cache/family-fronts"
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var args:=OS.get_cmdline_user_args()
	if args.size()>0:out=args[0]
	DirAccess.make_dir_recursive_absolute(out)
	if args.size()>1 and args[1]=="review":
		root.size=Vector2i(1920,1200);root.content_scale_size=root.size
		await capture([CITADIS[0],CITADIS[3],CITADIS[1],CITADIS[4],CITADIS[2],CITADIS[5]],2,"threequarter","citadis-x05-review")
		root.size=Vector2i(1440,1000);root.content_scale_size=root.size
		await capture(CITADIS,3,"front","citadis-x05-faces")
		StockHD.reset_cache();quit();return
	root.size=Vector2i(1440,1000);root.content_scale_size=Vector2i(1440,1000)
	await capture(CITADIS,3,"front","citadis-x05-faces")
	await capture(CITADIS,3,"threequarter","citadis-x05-types")
	await capture(TFS,2,"front","tfs-faces")
	await capture(TFS,2,"threequarter","tfs-types")
	StockHD.reset_cache();quit()
func capture(ids: Array, columns: int, view: String, filename: String) -> void:
	var bg:=ColorRect.new();bg.color=Color("#0c1118");bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);root.add_child(bg)
	var grid:=GridContainer.new();grid.columns=columns;grid.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);grid.add_theme_constant_override("h_separation",8);grid.add_theme_constant_override("v_separation",8);root.add_child(grid)
	for id in ids:
		var entry:=StockCatalog.find(id)
		var box:=VBoxContainer.new();box.size_flags_horizontal=Control.SIZE_EXPAND_FILL;box.size_flags_vertical=Control.SIZE_EXPAND_FILL;grid.add_child(box)
		var title:=Label.new();title.text=str(entry.name);title.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;title.add_theme_font_size_override("font_size",20);title.clip_text=true;box.add_child(title)
		var note:=Label.new();note.text=("FICTIF · " if entry.fictional else "MODÈLE RÉEL · ")+"%s · %.1f m · %d caisses" % [StockCatalog.type_name(entry),entry.length,entry.module_count];note.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;note.add_theme_color_override("font_color",Color("#f4bf60") if entry.fictional else Color("#87dac1"));box.add_child(note)
		var preview:=TramPreview.new();preview.custom_minimum_size=Vector2(0,0);preview.size_flags_horizontal=Control.SIZE_EXPAND_FILL;preview.size_flags_vertical=Control.SIZE_EXPAND_FILL;box.add_child(preview)
		preview.show_tram(StockCatalog.origin_meta(entry),VehicleLibrary.for_fleet(entry));preview.set_view(view)
		if view=="front":
			preview.cam.position=Vector3(0,1.8,-float(entry.length)*.5-7.8);preview.cam.fov=29
			preview.cam.look_at(Vector3(0,1.70,-float(entry.length)*.5+.2))
		preview.set_process(false);preview.rig.set_doors(false);preview.rig.update(0)
	for i in 8:await process_frame
	# Container resizes refit preview cameras. Apply inspection poses afterwards.
	if view.begins_with("roof_"):
		for box in grid.get_children():
			var preview:=box.get_child(box.get_child_count()-1) as TramPreview
			var direction:=-1.0 if view=="roof_front" else 1.0
			preview.cam.position=Vector3(4.5,4.9,direction*(preview.rig.length*.5+6.0));preview.cam.fov=32
			preview.cam.look_at(Vector3(0,2.85,direction*(preview.rig.length*.5-.8)))
		await process_frame
	await RenderingServer.frame_post_draw
	var path:=out+"/"+filename+".png"
	var error:=root.get_texture().get_image().save_png(path)
	print("CAPTURE|",path,"|",error)
	grid.queue_free();bg.queue_free();await process_frame;await process_frame
