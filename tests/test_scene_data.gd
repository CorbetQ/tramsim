extends SceneTree
## Données de décor (data/scenes) : lecture de toutes les tuiles de toutes les villes (TSC1 à TSC4),
## nature de plateforme, et aucun arbre ni lampadaire sur la plateforme d'une ligne test par ville.
## Usage : godot --headless --path . -s tests/test_scene_data.gd [-- ville...]
const MAX_TILES := 14        # tuiles construites par ville (le long de la ligne test)

func _seg_dist(p: Vector2, polys: Array) -> float:
	var best := INF
	for pl in polys:
		for i in range(pl.size() - 1):
			best = minf(best, p.distance_to(Geometry2D.get_closest_point_to_segment(p, pl[i], pl[i + 1])))
	return best

func _init() -> void:
	var only: Array = OS.get_cmdline_user_args()
	var nets := {}
	for f in DirAccess.get_files_at("res://data/networks"):
		if not f.ends_with(".json"): continue
		var d = JSON.parse_string(FileAccess.get_file_as_string("res://data/networks/" + f))
		var src := str(d.get("source_id", ""))
		if src != "" and not nets.has(src): nets[src] = f
	var fails := 0
	var cities := 0
	for f in DirAccess.get_files_at("res://data/scenes"):
		if not f.ends_with(".bin") or f.ends_with("_terrain.bin") or f.ends_with("_ground.bin") or f.ends_with("_land.bin"): continue
		var c := f.get_basename()
		if only.size() > 0 and not c in only: continue
		cities += 1
		if not nets.has(c):
			print("ECHEC %s : aucun réseau" % c); fails += 1; continue
		var net := NetworkLoader.new(); net.load_file("res://data/networks/" + str(nets[c]))
		var cs := CityScene.new()
		if not cs.open(c, net.meta.origin):
			print("ECHEC %s : lecture" % c); fails += 1; cs.free(); continue
		# occupation du sol (TLC1) : lisible, classes connues sur la plupart des tuiles de sol
		if FileAccess.file_exists("res://data/scenes/%s_land.bin" % c):
			if cs.terrain == null or not cs.terrain.land_ok:
				print("ECHEC %s : occupation du sol illisible" % c); fails += 1
			else:
				var known := 0; var total := 0
				for k in cs.terrain.keys:
					total += 1
					if cs.terrain.land_class((k.x + 0.5) * cs.tile_m, (k.y + 0.5) * cs.tile_m) >= 0: known += 1
				if known < total * 0.95:
					print("ECHEC %s : occupation du sol connue sur %d/%d tuiles" % [c, known, total]); fails += 1
		var bad := 0
		for k in cs.table:
			if not cs.tile_ok(k): bad += 1
		if bad > 0:
			print("ECHEC %s : %d tuiles mal formées" % [c, bad]); fails += 1
		var polys: Array = []
		var off := Vector2(cs.position.x, cs.position.z)
		var keys := {}
		for id in net.edge_info:
			var pl := PackedVector2Array()
			for q in net.edge_info[id].pts: pl.append(q)
			if pl.size() < 2: continue
			polys.append(pl)
			for q in pl:
				var k := Vector2i(floori((q.x - off.x) / cs.tile_m), floori((q.y - off.y) / cs.tile_m))
				if cs.table.has(k): keys[k] = true
		cs.set_tracks(polys)
		cs.debug_props = true
		var local: Array = []
		for pl in polys:
			var l2 := PackedVector2Array()
			for q in pl: l2.append(q - off)
			local.append(l2)
		var trees := 0
		var on_track := 0
		var built := 0
		for k in keys.keys().slice(0, MAX_TILES):
			var node := cs._build_tile(k)
			built += 1
			node.free()
		for p in cs.placed_trees:
			trees += 1
			if _seg_dist(p, local) < CityScene.TRACK_KEEP - 0.01: on_track += 1
		var lamps_on := 0
		for p in cs.placed_props:
			if _seg_dist(p, local) < CityScene.TRACK_KEEP - 0.01: lamps_on += 1
		var nat := 0
		for pl in polys:
			for q in pl:
				if cs.track_nature_at(Vector3(q.x, 0, q.y)) != 0: nat += 1
		var line := "%s : %d tuiles, %d construites, %d arbres, %d lampadaires, nature connue %d pts, sur voie : %d arbres %d lampadaires" % [
			c, cs.table.size(), built, trees, cs.placed_props.size(), nat, on_track, lamps_on]
		if on_track > 0 or lamps_on > 0:
			print("ECHEC " + line); fails += 1
		else:
			print("ok " + line)
		cs.free()
	print("TOTAL_ECHECS|%d|villes|%d" % [fails, cities])
	quit(1 if fails > 0 else 0)
