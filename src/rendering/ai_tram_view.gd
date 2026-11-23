class_name AiTramView
extends RefCounted
## Rames IA en 3D : modèle TramModel animé (portes, pantographe) à la livrée de leur ligne,
## posées le long de la voie comme la rame du joueur ; masquées au-delà de la distance de vue.

var rigs: Dictionary = {}       # id -> TramModel.Rig
var roots: Dictionary = {}      # id -> Node3D
var _liveries: Dictionary = {}  # ligne -> livrée
var proxies: Dictionary = {}
var forced_detail := "" # boarded train keeps its articulated rig
const DETAIL_ENTER_M := 170.0
const DETAIL_EXIT_M := 205.0
var detailed: Dictionary = {}
var passenger_rigs: Dictionary = {}

func ensure_passenger_rig(view: LineView, train: AiTram) -> TramModel.Rig:
	var id := train.train_id
	if passenger_rigs.has(id):return rigs[id]
	var old: TramModel.Rig=rigs[id]
	var replacement := TramModel.build_rig(_livery(view,train.line),train.phys.profile.length_m,true)
	for i in replacement.modules.size():
		replacement.modules[i].transform=old.modules[i].transform
		roots[id].add_child(replacement.modules[i]);old.modules[i].queue_free()
	replacement.door_right=old.door_right;replacement.door_left=old.door_left;replacement.snap()
	rigs[id]=replacement;passenger_rigs[id]=true
	return replacement

static func potentially_visible(camera: Camera3D, point: Vector3, radius: float) -> bool:
	if point.distance_to(camera.global_position)<=radius:return true
	for plane in camera.get_frustum():
		if plane.distance_to(point)>radius:return false
	return true

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

## LOD HD des rames IA : un cran plus bas en Mobile, et au plus StockHD.MOBILE_MAX_LOD0 rames en LOD0
## (rame du joueur comprise). Retourne le LOD retenu.
var hd_lods: Dictionary = {}
func _hd_lod(view: LineView, id: String, rig: TramModel.Rig, lod0_used: Array, dt: float) -> int:
	if rig.hd == null: return -1
	var centre: Vector3 = rig.modules[rig.modules.size() / 2].global_position
	var l := StockHD.lod_for(view.cam.global_position.distance_to(centre), int(hd_lods.get(id, -1)), true)
	if l == 0 and StockHD.mobile() and lod0_used[0] >= StockHD.MOBILE_MAX_LOD0: l = 1
	if l == 0: lod0_used[0] += 1
	hd_lods[id] = l
	rig.hd.set_lod(l)
	rig.hd.update({"headlights": 1.0 if view.day_night.night > 0.35 else 0.45, "interior": view.day_night.night > 0.3,
		"wiper": view.rain > 0.15, "destination": str(rig.hd.livery.get("destination", ""))}, 0.0 if l > 1 else dt)
	return l

func sync(view: LineView, ai: AiTrams, center: Vector3, dt: float) -> void:
	var alive := {}
	var lod0_used := [1 if view.hd_lod == 0 or (view.hd_lod == -1 and view.rig != null and view.rig.hd != null) else 0]
	for t in ai.trams:
		alive[t.train_id] = true
		var p := view.pos3(t.edge_id, t.offset)
		var distance := p.distance_to(center)
		var show := distance < view.view_distance + 120.0 and potentially_visible(view.cam,p,t.phys.profile.length_m+4)
		if t.train_id==forced_detail:show=true
		var detail := distance < (DETAIL_EXIT_M if detailed.get(t.train_id,false) else DETAIL_ENTER_M) or t.train_id==forced_detail
		detailed[t.train_id]=detail
		if show and not detail:
			if not proxies.has(t.train_id):
				var proxy := MeshInstance3D.new();var mesh := BoxMesh.new();mesh.size=Vector3(t.phys.profile.width_m,2.8,t.phys.profile.length_m)
				proxy.mesh=mesh;proxy.material_override=TramInterior.material("distant_tram",Color("#c4d1d8"));proxy.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				view.add_child(proxy);proxies[t.train_id]=proxy
			var behind := view.body_point(t,t.phys.profile.length_m)
			var direction := (p-behind).normalized()
			if direction.length_squared()<.1:direction=Vector3.FORWARD
			proxies[t.train_id].transform=Transform3D(Basis.looking_at(direction,Vector3.UP),(p+behind)*.5+Vector3(0,1.6,0))
			proxies[t.train_id].visible=true
			if roots.has(t.train_id):roots[t.train_id].visible=false
			continue
		if proxies.has(t.train_id):proxies[t.train_id].visible=false
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
		_hd_lod(view, t.train_id, rig, lod0_used, dt)
	for id in roots.keys():
		if not alive.has(id):
			(roots[id] as Node3D).queue_free(); roots.erase(id); rigs.erase(id)
	for id in proxies.keys():
		if not alive.has(id):proxies[id].queue_free();proxies.erase(id)
	for id in detailed.keys():
		if not alive.has(id):detailed.erase(id)
	for id in passenger_rigs.keys():
		if not alive.has(id):passenger_rigs.erase(id)
