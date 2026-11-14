class_name AiTramView
extends RefCounted
## Rames IA en 3D : modèle TramModel animé (portes, pantographe) à la livrée de leur ligne,
## posées le long de la voie comme la rame du joueur ; masquées au-delà de la distance de vue.

var rigs: Dictionary = {}       # id -> TramModel.Rig
var roots: Dictionary = {}      # id -> Node3D
var _liveries: Dictionary = {}  # ligne -> livrée

func _livery(view: LineView, line: String) -> Dictionary:
	if _liveries.has(line): return _liveries[line]
	var meta: Dictionary = view.net.meta.duplicate()
	var src := str(meta.get("source_id", meta.get("id", "")))
	meta["id"] = src + "_" + line.to_lower()
	meta["line"] = line
	meta["destination"] = line
	var liv := TramModel.livery_for(meta, LineView.tram_entry(null))
	_liveries[line] = liv
	return liv

func sync(view: LineView, ai: AiTrams, center: Vector3, dt: float) -> void:
	var alive := {}
	for t in ai.trams:
		alive[t.train_id] = true
		var p := view.pos3(t.edge_id, t.offset)
		var show := p.distance_to(center) < view.view_distance + 120.0
		if not roots.has(t.train_id):
			if not show: continue
			var root := Node3D.new(); root.name = "ai_" + t.train_id
			view.add_child(root)
			var rig := TramModel.build_rig(_livery(view, t.line), t.phys.profile.length_m)
			for m in rig.modules: root.add_child(m)
			roots[t.train_id] = root; rigs[t.train_id] = rig
			rig.set_pantograph(true); rig.snap()
		var root: Node3D = roots[t.train_id]
		root.visible = show
		if not show: continue
		var rig: TramModel.Rig = rigs[t.train_id]
		for i in rig.modules.size():
			var pf := view.body_point(t, rig.module_starts[i]); var pb := view.body_point(t, rig.module_starts[i] + rig.module_lengths[i])
			var dir := pf - pb
			if dir.length() < 0.01: dir = Vector3(1, 0, 0)
			rig.modules[i].transform = Transform3D(Basis.looking_at(dir.normalized(), Vector3.UP), (pf + pb) * 0.5)
		var side := view.layout.doors_at(view.net.stations, t.edge_id, t.offset) if view.layout != null else "right"
		if t.direction < 0 and side != "both": side = "left" if side == "right" else "right"
		rig.set_doors(t.doors_open, side)
		rig.update(dt)
	for id in roots.keys():
		if not alive.has(id):
			(roots[id] as Node3D).queue_free(); roots.erase(id); rigs.erase(id)
