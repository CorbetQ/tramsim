extends SceneTree
## P3 façades (src/rendering/facades.gd) : grammaire par styles régionaux appliquée aux tuiles BD TOPO d'Angers et de
## Nantes. Vérifie : styles attendus par quartier (Anjou au centre d'Angers, XVIIIe à Feydeau, haussmannien au centre
## de Nantes, moderne, pavillonnaire, activités), relief en LOD proche par cellules (portée PC / Mobile, ombres
## coupées en Mobile), trame des baies identique au shader, budget de triangles du relief par tuile.
var fails := 0

func check(c: bool, m: String) -> void:
	if c: print("ok ", m)
	else: print("ECHEC ", m); fails += 1

func _init() -> void:
	_run.call_deferred()

func _tile_at(cs: CityScene, lat: float, lon: float) -> Vector2i:
	var meta: Dictionary = CityDataStore.document("res://data/scenes/%s.json" % cs.city)
	var x := deg_to_rad(lon - float(meta.origin[1])) * CityScene.R * cos(deg_to_rad(float(meta.origin[0])))
	var z := -deg_to_rad(lat - float(meta.origin[0])) * CityScene.R
	return Vector2i(floori(x / cs.tile_m), floori(z / cs.tile_m))

func _relief(node: Node) -> Array:
	var out: Array = []
	for c in node.get_children():
		if c.name.begins_with("facade_relief"): out.append(c)
	return out

func _run() -> void:
	# trame des baies : miroir exact du shader (pbr_world.gdshader, bloc M_FACADE)
	var g := Facades.bays(CityScene.F_TUFFEAU, 712.0)
	var variant := fposmod(712.0 * 0.6180339, 1.0)
	check(is_equal_approx(float(g.bay), lerpf(2.4, 4.0, variant)) and float(g.fh) == 3.3, "trame tuffeau : travée %.2f m, étage 3,3 m" % float(g.bay))
	check(is_equal_approx(float(g.hw), lerpf(0.17, 0.21, variant) * float(g.bay)), "demi-largeur des baies identique au shader")
	var shader := FileAccess.get_file_as_string("res://src/rendering/shaders/pbr_world.gdshader")
	check(shader.contains("float shop_w = mix(4.2, 6.5, fract(facade_seed * 0.371));") and Facades.SHOP_W == 4.2, "trame des vitrines (graine nulle) : 4,2 m")
	check(shader.contains("vec2 cell = vec2(UV.x / bay, (UV.y - 0.4) / fh);"), "origine des rangées de baies à 0,4 m")
	var expect := {"angers": [[47.4716, -0.5540, ["anjou"]]],
		"nantes": [[47.2122, -1.5545, ["nantes_xviii"]], [47.2150, -1.5590, ["haussmann", "nantes_xviii"]]],
		# P4 : styles régionaux des autres villes (quartiers de data/facade_styles.json, près des lignes de tram)
		"lyon": [[45.7600, 4.8345, ["haussmann"]]], "bordeaux": [[44.8410, -0.5730, ["bordelais"]]],
		"strasbourg": [[48.5810, 7.7430, ["colombage", "haussmann"]]], "lille": [[50.6370, 3.0645, ["flamand"]]],
		"toulouse": [[43.6030, 1.4430, ["toulousain"]]], "marseille": [[43.2965, 5.3760, ["mediterraneen"]]],
		"nice": [[43.6975, 7.2700, ["mediterraneen"]]], "lehavre": [[49.4935, 0.1100, ["reconstruction"]]],
		"rouen": [[49.4410, 1.0915, ["colombage"]]], "clermont": [[45.7780, 3.0850, ["faubourg"]]]}
	var origins := {}
	for city in expect:
		origins[city] = CityDataStore.document("res://data/scenes/%s.json" % city).origin
	for city in expect:
		var cs := CityScene.new()
		check(cs.open(city, origins[city]), "%s : scène ouverte" % city)
		check(not cs._fac_dist.is_empty(), "%s : quartiers de style chargés (%d)" % [city, cs._fac_dist.size()])
		root.add_child(cs)
		for site in expect[city]:
			var k := _tile_at(cs, site[0], site[1])
			cs.facade_stats = {}; cs.stats.erase("facade_tris")
			DayNight.low_quality = false
			var node := cs._build_tile(k)
			var styles := {}
			for s in cs.facade_stats: styles[Facades.NAMES[s]] = cs.facade_stats[s]
			print("INFO|%s %s|styles=%s|relief_tris=%d" % [city, k, styles, int(cs.stats.get("facade_tris", 0))])
			for st in site[2]: check(int(styles.get(st, 0)) > (20 if city in ["angers", "nantes"] else 12), "%s %s : style %s présent (%d bâtiments)" % [city, k, st, int(styles.get(st, 0))])
			var rel := _relief(node)
			check(rel.size() >= 4, "%s %s : relief en %d cellules de LOD proche" % [city, k, rel.size()])
			var ok_range := true; var tris := 0; var big := 0
			for r in rel:
				ok_range = ok_range and is_equal_approx((r as MeshInstance3D).visibility_range_end, Facades.NEAR_PC)
				var n: int = (r as MeshInstance3D).mesh.surface_get_array_len(0) / 3
				tris += n; big = maxi(big, n)
			check(ok_range, "%s %s : portée du relief %.0f m (PC)" % [city, k, Facades.NEAR_PC])
			check(tris > (20000 if city in ["angers", "nantes"] else 5000) and tris < 900000, "%s %s : relief %d triangles par tuile (borne 900 k)" % [city, k, tris])
			check(big < 250000, "%s %s : cellule la plus chargée %d triangles" % [city, k, big])
			node.free()
			DayNight.low_quality = true
			var mnode := cs._build_tile(k)
			var mrel := _relief(mnode)
			var mob_ok := not mrel.is_empty()
			for r in mrel:
				mob_ok = mob_ok and is_equal_approx((r as MeshInstance3D).visibility_range_end, Facades.NEAR_MOBILE) \
					and (r as MeshInstance3D).cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			check(mob_ok, "%s %s : Mobile : portée %.0f m, sans ombre" % [city, k, Facades.NEAR_MOBILE])
			mnode.free()
			DayNight.low_quality = false
		cs.queue_free()
	# styles hors quartiers : moderne, pavillonnaire, activités
	var far: Array = []
	for c in [[CityScene.F_BETON, 0, 18.0, 900.0], [CityScene.F_ENDUIT, 0, 7.0, 120.0], [CityScene.F_ENDUIT, 2, 9.0, 3000.0]]:
		far.append(Facades.NAMES[Facades.pick("angers", [], Vector2(1e5, 1e5), c[1], c[2], c[3], c[0], 7)])
	check(far == ["moderne", "pavillon", "activite"], "styles hors quartiers : %s" % [far])
	print("TOTAL_ECHECS|%d" % fails)
	quit(1 if fails > 0 else 0)
