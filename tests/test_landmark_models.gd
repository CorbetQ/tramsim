extends SceneTree
## Modèles dédiés P1 (assets/models/landmark_models.json, src/rendering/landmark_models.gd) : manifeste, fichiers
## LOD0-2, budgets de triangles (station + abords ≤ 250 k LOD0 et ≤ 80 k Mobile ; cathédrale ≤ 150 k LOD0), triangles
## décroissants par LOD, matériaux tous issus de la bibliothèque PBR, et GABARIT : aucun sommet LOD0 à moins de
## 1,5 m de l'axe d'une voie entre rail + 0,35 m et rail + 4,2 m (quais et sol plus bas admis).
var fails := 0

class FakeView:
	var net: NetworkLoader

func check(c: bool, m: String) -> void:
	if c: print("ok: ", m)
	else: fails += 1; printerr("ECHEC: ", m)

## Réseau de tram de la ville dont une station est la plus proche de l'ancre WGS84 du modèle.
func _nearest_net(city: String, m: Dictionary) -> NetworkLoader:
	var best: NetworkLoader = null; var bd := INF
	for e in NetworkRegistry.entries():
		if CityPacks.key_of(e) != city or str(e.get("kind", "tram")) != "tram" or not str(e.path).begins_with("res://data/networks/"): continue
		var n := NetworkLoader.new(); n.load_file(str(e.path))
		var v := FakeView.new(); v.net = n
		var a := LandmarkModels.anchor(v, m)
		for id in n.edge_info:
			for p in n.edge_info[id].pts:
				var d := Vector2(a.x, a.z).distance_to(p)
				if d < bd: bd = d; best = n
	return best

func _init() -> void:
	var doc := LandmarkModels.manifest()
	check(doc.get("models", []).size() >= 3, "manifeste : %d modèles" % doc.get("models", []).size())
	var nets := {"angers_ralliement": "angers_c", "angers_cathedrale_saint_maurice": "angers_c", "nantes_tremie_l3": "nantes_3"}
	for m in doc.models:
		var t: Array = m.triangles
		# P4 : modèles simples (ouvrages singuliers) : LOD non croissants, LOD2 strictement plus léger que LOD0
		var p4 := str(m.get("lot", "")) == "P4"
		check(t.size() == 3 and (int(t[0]) > int(t[1]) and int(t[1]) > int(t[2]) if not p4 else int(t[0]) >= int(t[1]) and int(t[1]) >= int(t[2]) and (int(t[0]) > int(t[2]) or int(t[0]) < 2000)), "%s : LOD décroissants %s" % [m.id, t])
		check(int(t[0]) <= int(m.budget_lod0) and int(t[1]) <= int(m.budget_mobile), "%s : budget LOD0 %d ≤ %d, Mobile (LOD1) %d ≤ %d" % [m.id, t[0], m.budget_lod0, t[1], m.budget_mobile])
		var v := FakeView.new(); v.net = NetworkLoader.new(); v.net.load_file("res://data/networks/%s.json" % nets.get(m.id, "angers_c" if str(m.city) == "angers" else "nantes_1"))   # P3 : monuments près des lignes du centre
		if p4:   # P4 : ligne de tram de la ville la plus proche du monument
			v.net = _nearest_net(str(m.city), m)
		var a := LandmarkModels.anchor(v, m)
		var unknown := {}
		var verts := PackedVector3Array()
		for lod in 3:
			var ps := load(str(m.lods[lod])) as PackedScene
			check(ps != null, "%s : LOD%d chargé" % [m.id, lod])
			if ps == null: continue
			var inst := ps.instantiate()
			for mi in inst.find_children("*", "MeshInstance3D", true, false):
				var mesh: Mesh = (mi as MeshInstance3D).mesh
				for s in mesh.get_surface_count():
					var id := mesh.surface_get_material(s).resource_name if mesh.surface_get_material(s) else ""
					if LandmarkModels.material(id) == null: unknown[id] = true
					if lod == 0:
						for p in mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]: verts.append(p + a)
			inst.free()
		check(unknown.is_empty(), "%s : matériaux de la bibliothèque (inconnus : %s)" % [m.id, unknown.keys()])
		# gabarit : points d'axe de chaque sens tous les 0,5 m, indexés par cellule de 4 m
		var cells := {}
		for id in v.net.edge_info:
			var info: Dictionary = v.net.edge_info[id]
			var L: float = v.net.graph.edges[id].length
			var near := false
			for p in info.pts:
				if Vector2(a.x, a.z).distance_to(p) < 250.0: near = true; break
			if not near: continue
			var offs: Array = [0.0] if info.raw or info.get("physical", false) else [-LineView.TRACK_OFFSET, LineView.TRACK_OFFSET]
			for i in int(L / 0.5) + 1:
				var q := v.net.point_on(id, minf(L, i * 0.5))
				for o in offs:
					var c := Vector3(q.p.x - q.dir.y * o, q.y, q.p.y + q.dir.x * o)
					var k := Vector2i(floori(c.x / 4.0), floori(c.z / 4.0))
					if not cells.has(k): cells[k] = []
					cells[k].append(c)
		var bad := 0; var worst := ""
		for p in verts:
			var k := Vector2i(floori(p.x / 4.0), floori(p.z / 4.0))
			for dx in [-1, 0, 1]:
				for dz in [-1, 0, 1]:
					for c in cells.get(k + Vector2i(dx, dz), []):
						var cc: Vector3 = c
						if Vector2(p.x, p.z).distance_to(Vector2(cc.x, cc.z)) < 1.5 and p.y > cc.y + 0.35 and p.y < cc.y + CityScene.GAUGE_H:
							bad += 1
							if worst == "": worst = "%s rail %.2f dist %.2f" % [p - a, cc.y - a.y, Vector2(p.x, p.z).distance_to(Vector2(cc.x, cc.z))]
		check(bad == 0, "%s : gabarit libre (%d sommets LOD0 contrôlés, %d dans le gabarit %s)" % [m.id, verts.size(), bad, worst])
	print("TOTAL_ECHECS|%d" % fails)
	quit(1 if fails > 0 else 0)
