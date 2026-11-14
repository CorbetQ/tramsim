extends SceneTree
## Audit du fond d'accueil (vue aérienne orthographique de HomeBackground) : une image par ville.
## Args : -- <dossier> [ville...]  (noms de NetworkRegistry.cities(), ex. Angers ; défaut : toutes)
## Sortie : <dossier>/home_<ville>.png et lignes "HOME|ville|ms|part de la couleur dominante".

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "res://.cache/home-shots"
	DirAccess.make_dir_recursive_absolute(out)
	var wanted := args.slice(1)
	var cities := NetworkRegistry.cities()
	for c in cities:
		if not wanted.is_empty() and not (c in wanted or c.to_lower() in wanted): continue
		var bg := HomeBackground.new()
		root.add_child(bg)
		bg.size = Vector2(1600, 900)
		var t0 := Time.get_ticks_msec()
		bg.show_city(c)
		var ok := false
		for i in 3000:
			await process_frame
			if bg.shown == c and bg.layer_count() > 0 and not bg.is_loading():
				ok = true; break
		for L in bg._layers:
			if L.vp != null: L.vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		for i in 40: await process_frame          # fondu enchaîné
		await RenderingServer.frame_post_draw
		var img: Image = null
		for L in bg._layers:
			if L.vp != null: img = L.vp.get_texture().get_image()
			elif L.rect.texture != null: img = L.rect.texture.get_image()
		var dom := 0.0
		if img != null:
			img.save_png(out.path_join("home_%s.png" % c.validate_filename().to_lower()))
			dom = _dominant(img)
		print("HOME|%s|%d|%.2f|%s" % [c, Time.get_ticks_msec() - t0, dom, "ok" if ok else "TIMEOUT"])
		bg.queue_free()
		for i in 5: await process_frame
	quit()

## Part de pixels du « vide » (sol uni) : histogramme grossier, couleur la plus fréquente.
func _dominant(img: Image) -> float:
	var h := {}
	var n := 0
	for y in range(0, img.get_height(), 6):
		for x in range(0, img.get_width(), 6):
			var c := img.get_pixel(x, y)
			var k := Vector3i(int(c.r * 16), int(c.g * 16), int(c.b * 16))
			h[k] = h.get(k, 0) + 1; n += 1
	var best := 0
	for k in h: best = maxi(best, h[k])
	return float(best) / maxf(1.0, float(n))
