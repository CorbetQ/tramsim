extends SceneTree
## Exporte les tabliers/piles du rendu réel ; aucun changement de géographie.
func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2: printerr("Usage: -- network.json report.json"); quit(2); return
	var net := NetworkLoader.new()
	if not net.load_file(args[0]).is_empty(): quit(2); return
	var city := CityScene.new()
	if not city.open(str(net.meta.get("source_id", "")), net.meta.get("origin", [])):
		city.free(); printerr("Décor absent : export non effectué"); quit(2); return
	city.bind_network(net)
	var obstacles: Array = []
	for index in city._decks.size():
		var deck: Array = city._decks[index]
		var line: PackedVector3Array = deck[2]
		for i in range(line.size() - 1):
			var a := Vector2(line[i].x, line[i].z); var b := Vector2(line[i + 1].x, line[i + 1].z)
			if a.distance_to(b) < 0.01: continue
			var normal := Vector2(-(b-a).y, (b-a).x).normalized() * float(deck[1]) * 0.5
			var polygon: Array = []
			for p in [a-normal,b-normal,b+normal,a+normal]: polygon.append([p.x * city._x_scale + city.position.x, p.y + city.position.z])
			obstacles.append({"id":"deck:%d:%d"%[index,i],"kind":"bridge_deck","polygon":polygon,
				"bottom_m":minf(line[i].y,line[i+1].y)-1.1,"top_m":maxf(line[i].y,line[i+1].y),
				"provenance":"CityScene._decks après bind_network ; géométrie BD TOPO et ajustements de rendu ; épaisseur 1.1 m du contrôle existant",
				"estimated":true,"uncertainty_m":null})
		var number := 0
		for pile in city.deck_piles(deck):
			var center: Vector3 = pile[0]
			var polygon: Array = []
			for delta in [Vector2(-.65,-.65),Vector2(.65,-.65),Vector2(.65,.65),Vector2(-.65,.65)]:
				polygon.append([(center.x+delta.x)*city._x_scale+city.position.x,center.z+delta.y+city.position.z])
			obstacles.append({"id":"pier:%d:%d"%[index,number],"kind":"pier","polygon":polygon,
				"bottom_m":float(pile[1]),"top_m":center.y-1.1,"estimated":true,"uncertainty_m":null,
				"provenance":"CityScene.deck_piles ; placement procédural d'après ouvrages/terrain, pas de pile relevée"})
			number += 1
	var report := {"schema_version":1,"network_id":net.meta.id,"network_sha256":FileAccess.get_sha256(args[0]),"frame":"network local x,z, relative rail y (metres)",
		"coverage":{"included":["bridge_deck","pier"],"not_included":["catenary_poles","wires","tunnel_mesh","platforms","water_mesh","terrain_mesh"]},"obstacles":obstacles}
	var output := FileAccess.open(args[1],FileAccess.WRITE)
	if output == null: city.free(); quit(2); return
	output.store_string(JSON.stringify(report,"\t"));output.close();city.free()
	print("OBSTACLES|",obstacles.size());quit()
