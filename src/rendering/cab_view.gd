class_name CabView
extends Node3D
## Cabine de conduite HD (cab.glb, repère de la caisse de tête) : point de vue conducteur, commandes
## `ctl_*` animées et cliquables (CabActions), voyants `em_lamp_*`, écrans `screen_*` en SubViewport (CabScreens).

var entry: Dictionary = {}
var model: Node3D
var camera_node: Node3D
var controls: Array = []        # {action, node, rest, kind, cfg, aabb}
var lamps: Dictionary = {}      # voyant -> Array[StandardMaterial3D]
var screens: CabScreens
var toggles: Dictionary = {}    # action -> bool
var _press: Dictionary = {}     # action -> temps restant d'appui (s)
var notch := 0.0
var _notch_shown := 0.0
const PRESS_S := 0.25

func setup(m: Node3D, e: Dictionary, livery: Dictionary) -> void:
	name = "Cab"; entry = e; model = m
	add_child(model)
	StockHD.dress(model, livery, 0.12)
	camera_node = StockHD.find(model, "cam_driver") as Node3D
	var aliases: Dictionary = e.get("control_aliases", {})
	var cfgs: Dictionary = e.get("controls", {})
	for n in model.find_children("ctl_*", "Node3D", true, false):
		var action := CabActions.action_for_node(str(n.name), aliases)
		if action == "": continue
		var cfg: Dictionary = cfgs.get(str(n.name), {})
		var kind := str(cfg.get("kind", CabActions.ACTIONS.get(action, {}).get("kind", "button")))
		controls.append({"action": action, "node": n, "rest": (n as Node3D).transform, "kind": kind, "cfg": cfg, "aabb": _local_aabb(n)})
	for mi in model.find_children("em_lamp_*", "MeshInstance3D", true, false):
		var k := str(mi.name).trim_prefix("em_lamp_")
		var col := Color(1, 0.15, 0.1) if k == "emergency" else (Color(1, 0.7, 0.1) if k in ["doors", "sand"] else Color(0.2, 1, 0.35))
		var mat := StockHD.emissive(col)
		(mi as MeshInstance3D).material_override = mat
		if not lamps.has(k): lamps[k] = []
		lamps[k].append(mat)
	screens = CabScreens.new(); screens.name = "Screens"; add_child(screens)
	screens.setup(model, e.get("screens", {}))

## AABB (repère du nœud) des maillages de la commande, élargie à 3 cm minimum pour le toucher.
static func _local_aabb(n: Node3D) -> AABB:
	var box := AABB(); var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false) + ([n] if n is MeshInstance3D else []):
		var g := mi as MeshInstance3D
		if g.mesh == null: continue
		var xf := Transform3D.IDENTITY
		var c: Node = g
		while c != n and c != null:
			xf = (c as Node3D).transform * xf; c = c.get_parent()
		var b := xf * g.mesh.get_aabb()
		box = b if first else box.merge(b); first = false
	if first: box = AABB(Vector3(-0.02, -0.02, -0.02), Vector3(0.04, 0.04, 0.04))
	var grow := Vector3(maxf(0.0, 0.03 - box.size.x), maxf(0.0, 0.03 - box.size.y), maxf(0.0, 0.03 - box.size.z)) * 0.5
	return AABB(box.position - grow, box.size + grow * 2.0)

func control(action: String) -> Dictionary:
	for c in controls:
		if c.action == action: return c
	return {}

func camera_transform() -> Transform3D:
	return camera_node.global_transform if camera_node else global_transform

## Retour visuel d'une action (clavier, HUD ou clic) : appui des boutons, bascule des commutateurs.
func pulse(action: String, on: Variant = null) -> void:
	var c := control(action)
	if c.is_empty(): return
	if c.kind == "toggle": toggles[action] = (not bool(toggles.get(action, false))) if on == null else bool(on)
	else: _press[action] = PRESS_S

func set_toggle(action: String, on: bool) -> void:
	toggles[action] = on

func pressed(action: String) -> bool:
	return float(_press.get(action, 0.0)) > 0.0

## data : {notch, speed_kmh, limit_kmh, next_stop, distance_m, signal, signal_color, lamps:{…}, toggles:{…}}
func update(data: Dictionary, dt: float) -> void:
	notch = float(data.get("notch", notch))
	for k in data.get("toggles", {}): toggles[k] = bool(data.toggles[k])
	_notch_shown = move_toward(_notch_shown, notch, dt * 4.0) if dt > 0.0 else notch
	for c in controls:
		var cfg: Dictionary = c.cfg
		var axis := StockHD.HD._axis(str(cfg.get("axis", "x" if c.kind != "button" else "z")))
		var rest: Transform3D = c.rest
		match str(c.kind):
			"lever":
				var r: Array = cfg.get("range_deg", [-30.0, 30.0])
				var a := lerpf(float(r[0]), float(r[1]), (_notch_shown + 1.0) * 0.5)
				(c.node as Node3D).transform = rest * Transform3D(Basis(axis, deg_to_rad(a)))
			"toggle", "knob":
				var on := bool(toggles.get(c.action, false))
				var a := float(cfg.get("on_deg", 30.0)) if on else float(cfg.get("off_deg", 0.0))
				(c.node as Node3D).transform = rest * Transform3D(Basis(axis, deg_to_rad(a)))
			_:
				var t := float(_press.get(c.action, 0.0))
				var depth := absf(float(cfg.get("travel_m", 0.01))) * (1.0 if t > 0.0 else 0.0)   # enfoncement selon -axe local (signe ignoré)
				(c.node as Node3D).transform = rest * Transform3D(Basis(), -axis * depth)
	for k in _press.keys():
		_press[k] = float(_press[k]) - dt
		if float(_press[k]) <= -0.01: _press.erase(k)
	var lv: Dictionary = data.get("lamps", {})
	for k in lamps:
		for m in lamps[k]: (m as StandardMaterial3D).emission_energy_multiplier = 2.5 if bool(lv.get(k, false)) else 0.05
	if screens: screens.refresh(data, dt)

## Commande sous un point d'écran (souris / toucher) : {action, node, hit (repère du nœud), up (bool)} ou {}.
func pick(cam: Camera3D, screen_pos: Vector2) -> Dictionary:
	if not visible or cam == null: return {}
	var o := cam.project_ray_origin(screen_pos)
	var d := cam.project_ray_normal(screen_pos)
	var best := {}; var best_d := INF
	for c in controls:
		var n := c.node as Node3D
		if not n.is_visible_in_tree(): continue
		var inv := n.global_transform.affine_inverse()
		var lo := inv * o; var ld := inv.basis * d
		var hit: Variant = (c.aabb as AABB).intersects_ray(lo, ld)
		if hit == null: continue
		var gd := (n.global_transform * (hit as Vector3)).distance_to(o)
		if gd < best_d and gd < 3.0:
			best_d = gd
			# manipulateur : moitié haute de l'écran = traction, basse = freinage
			best = {"action": c.action, "node": n, "hit": hit, "up": screen_pos.y < cam.unproject_position(n.global_position).y}
	return best
