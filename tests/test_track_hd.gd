extends SceneTree
## Refonte P1 : voie à gorge HD (TrackView) — profil Ri60 en LOD proche par cellules, LOD de base confondu, matériaux
## texturés de la plateforme (dalle béton, pavés granit, bordures granit, béton banché). Sans rendu (--headless).
var fails := 0

func check(c: bool, m: String) -> void:
	if c: print("ok: ", m)
	else: fails += 1; printerr("ECHEC: ", m)

class G:
	var quads: Array = []
	func quad(a, b, c, d, col) -> void: quads.append([a, b, c, d, col])

func _init() -> void:
	var axis: Array = []
	for i in 21: axis.append(Vector3(i * 10.0, 0, 0))   # 200 m de voie droite
	for nature in [TrackView.BED_GRASS, TrackView.BED_ROAD, TrackView.BED_PAVED]:
		var g := G.new()
		var near := TrackView.NearSink.new(func(): return G.new())
		TrackView.build(g, axis, 0.0, func(_p): return nature, TrackView.GRASS, Color("#a49a8c"), 1.435, Callable(), Callable(), near)
		var nq := 0
		for c in near.cells.values(): nq += c.quads.size()
		check(near.cells.size() >= 3, "nature %d : LOD proche découpé en %d cellules de %d m" % [nature, near.cells.size(), TrackView.DETAIL_CELL])
		var per_seg := 6 + (1 if nature == TrackView.BED_GRASS else 0)
		check(nq >= 2 * 25 * per_seg, "nature %d : profil Ri60 (%d faces proches)" % [nature, nq])
		var ids := {}
		for q in g.quads: ids[CityScene._Arrays.mat_id((q[4] as Color).a)] = true
		if nature == TrackView.BED_PAVED: check(ids.has(12.0), "pavés granit (M_SETTS) : %s" % [ids.keys()])
		if nature == TrackView.BED_GRASS: check(ids.has(13.0) and ids.has(4.0), "gazon + bordures granit : %s" % [ids.keys()])
		# fond de gorge du profil confondu avec celui du LOD de base (aucun écart de hauteur)
		var yb_base := INF; var yb_near := INF
		for q in g.quads:
			if q[4] == TrackView.GROOVE: yb_base = minf(yb_base, q[0].y)
		for c in near.cells.values():
			for q in c.quads:
				if q[4] == TrackView.GROOVE: yb_near = minf(yb_near, q[0].y)
		check(is_equal_approx(yb_base, yb_near), "nature %d : fond de gorge commun aux deux LOD (%.3f / %.3f)" % [nature, yb_base, yb_near])
	# béton désactivé (pavés gris) : dalle M_CONCRETE + joints
	var g2 := G.new()
	TrackView.build(g2, axis, 0.0, func(_p): return TrackView.BED_PAVED, TrackView.GRASS, Color("#9a958d"))
	var has_c := false
	for q in g2.quads: if CityScene._Arrays.mat_id((q[4] as Color).a) == 10.0: has_c = true
	check(has_c, "dalle béton de plateforme (M_CONCRETE)")
	check(TrackView.detail_range() > 0.0, "portée du LOD proche %.0f m" % TrackView.detail_range())
	print("TOTAL_ECHECS|%d" % fails)
	quit(1 if fails > 0 else 0)
