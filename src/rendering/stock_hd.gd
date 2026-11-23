class_name StockHD
extends RefCounted
## Rames HD (P2) : modèles par variante décrits par assets/models/rolling_stock/manifest.json
## (schéma : docs/refonte-visuelle/stock_manifest.md). Remplace l'habillage du rig TramModel quand la
## variante est complète ; sinon le rig garde son modèle actuel (procédural / CitadisMeshy).
## Le rig reste l'autorité (longueurs, états de portes et de pantographe) ; StockHD n'est qu'une vue.

const MANIFEST := "res://assets/models/rolling_stock/manifest.json"
const LOD_NAMES := ["LOD0", "LOD1", "LOD2", "LOD3"]
## Distances de bascule (budgets.json → rolling_stock_lod) et hystérésis.
const LOD_DIST := [25.0, 80.0, 250.0]
const HYSTERESIS := 0.1
const MOBILE_MAX_LOD0 := 3
const PAINT_ZONES := ["base", "front", "door", "roof", "skirt", "window"]

static var enabled := true
static var manifest_path := ""
static var _manifest: Dictionary = {}
static var _loaded_path := "-"
static var _scenes: Dictionary = {}
static var _mats: Dictionary = {}
static var _tris: Dictionary = {}

static func path() -> String:
	if manifest_path != "": return manifest_path
	var env := OS.get_environment("TRAMSIM_STOCK_MANIFEST")
	return env if env != "" else MANIFEST

static func reset_cache() -> void:
	# Templates are Nodes outside the tree: clearing a Dictionary does not free them.
	# Instantiated trains keep their own references to shared meshes/materials.
	for template in _scenes.values():
		if is_instance_valid(template): template.free()
	_manifest = {}; _loaded_path = "-"; _scenes.clear(); _mats.clear(); _tris.clear()

static func manifest() -> Dictionary:
	var p := path()
	if _loaded_path == p: return _manifest
	_loaded_path = p; _manifest = {}
	if FileAccess.file_exists(p):
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(p))
		if d is Dictionary: _manifest = d
	return _manifest

static func base_dir(entry: Dictionary) -> String:
	return path().get_base_dir().path_join(str(entry.get("dir", "")))

static func entry(variant_id: String) -> Dictionary:
	if not enabled or OS.get_environment("TRAMSIM_STOCK_HD") == "0": return {}
	return manifest().get("variants", {}).get(variant_id, {})

static func mobile() -> bool:
	# A GLES fallback on Android still needs the mobile geometry budget. low_quality
	# also drives the existing desktop mobile-content audit.
	return OS.has_feature("mobile") or DayNight.low_quality or PbrMaterials.profile == "mobile"

## Fichier d'un LOD ("LOD0".."LOD3" ou "cab") pour le profil courant (`mobile_file` si fourni).
static func file_for(e: Dictionary, lod: String, for_mobile: bool = mobile()) -> String:
	var spec: Dictionary = e.get("cab", {}) if lod == "cab" else e.get("lods", {}).get(lod, {})
	var f := str(spec.get("mobile_file", "")) if for_mobile else ""
	if f == "": f = str(spec.get("file", ""))
	return "" if f == "" else base_dir(e).path_join(f)

## Modèle (gabarit hors arbre, partagé). res:// importé, sinon glb lu à l'exécution (tests, user://).
static func scene(p: String) -> Node3D:
	if p == "": return null
	if _scenes.has(p): return _scenes[p]
	var root: Node3D = null
	if p.begins_with("res://") and ResourceLoader.exists(p):
		var ps := load(p) as PackedScene
		if ps != null: root = ps.instantiate() as Node3D
	elif FileAccess.file_exists(p):
		var doc := GLTFDocument.new(); var st := GLTFState.new()
		if doc.append_from_file(p, st) == OK: root = doc.generate_scene(st) as Node3D
	_scenes[p] = root
	return root

static func triangles(n: Node) -> int:
	if n == null: return 0
	var t := 0
	for mi in n.find_children("*", "MeshInstance3D", true, false) + ([n] if n is MeshInstance3D else []):
		var m: Mesh = (mi as MeshInstance3D).mesh
		if m == null: continue
		var k := m.get_instance_id()
		if not _tris.has(k): _tris[k] = m.get_faces().size() / 3
		t += int(_tris[k])
	return t

static func find(root: Node, name_: String) -> Node:
	if root == null: return null
	if str(root.name) == name_: return root
	return root.find_child(name_, true, false)

## Nœuds `module_XX` d'un modèle, dans l'ordre.
static func modules_of(root: Node) -> Array:
	var r: Array = []
	if root == null: return r
	var i := 0
	while true:
		var m := find(root, "module_%02d" % i)
		if m == null: break
		r.append(m); i += 1
	return r

## Portes d'un modèle : "n|S" -> [nœuds]. Accepte door_<n>_<L|R>[_a|_b].
static func doors_of(root: Node) -> Dictionary:
	var r := {}
	if root == null: return r
	for n in root.find_children("door_*", "", true, false):
		var parts := str(n.name).split("_")
		if parts.size() < 3 or not parts[1].is_valid_int() or not parts[2] in ["L", "R"]: continue
		var key := parts[1] + "|" + parts[2]
		if not r.has(key): r[key] = []
		r[key].append(n)
	return r

## Vérifie une variante (fichiers, nœuds requis, budgets) ; [] si valide. `rig` optionnel : longueurs.
static func check(variant_id: String, rig = null, active_profile_only := false) -> PackedStringArray:
	var err := PackedStringArray()
	var e := entry(variant_id)
	if e.is_empty(): err.append("variante absente du manifeste"); return err
	var mods: Array = e.get("modules", [])
	if mods.is_empty(): err.append("modules absents")
	var total := 0.0
	for length in mods:
		if not is_finite(float(length)) or float(length) <= 0.0: err.append("longueur de caisse invalide")
		total += float(length)
	if not is_finite(total) or absf(total - float(e.get("length_m", total))) > 0.02: err.append("somme des caisses différente de length_m")
	if rig != null:
		if rig.modules.size() != mods.size(): err.append("nombre de caisses %d ≠ rig %d" % [mods.size(), rig.modules.size()])
		else:
			for i in mods.size():
				if absf(float(mods[i]) - float(rig.module_lengths[i])) > 0.02: err.append("caisse %d : %.3f m ≠ rig %.3f m" % [i, float(mods[i]), rig.module_lengths[i]])
	var budget := _budgets()
	var profiles: Array = [mobile()] if active_profile_only else [false, true]
	for lod_i in 4:
		var ln: String = LOD_NAMES[lod_i]
		for mob in profiles:
			var f := file_for(e, ln, mob)
			var dedicated_mobile: bool = mob and f != file_for(e, ln, false)
			if mob and not dedicated_mobile and not active_profile_only: continue
			var root := scene(f)
			if root == null: err.append("%s : fichier illisible %s" % [ln, f]); continue
			if modules_of(root).size() != mods.size(): err.append("%s : %d module_XX ≠ %d" % [ln, modules_of(root).size(), mods.size()])
			# Shared over-budget LODs are skipped by HD.set_lod. LOD3 cannot fall
			# back any further, so its mobile limit always applies.
			var mobile_cap: bool = mob and (dedicated_mobile or lod_i == 3)
			var cap := int(budget.get(ln, {}).get("mobile_tris" if mobile_cap else "pc_tris", 1 << 30))
			var tris := triangles(root)
			if tris > cap: err.append("%s%s : %d triangles > %d" % [ln, " mobile" if mob else "", tris, cap])
			if lod_i == 0:
				var d := doors_of(root)
				var per_side := int(e.get("doors", 0))
				for s in ["L", "R"]:
					var c := 0
					for k in d: if str(k).ends_with("|" + s): c += 1
					if per_side > 0 and c != per_side: err.append("%s : %d portes côté %s ≠ %d" % [ln, c, s, per_side])
				# Count alone accepts door_99 in place of a missing door_0.
				for door_i in per_side:
					for s in ["L", "R"]:
						if not d.has("%d|%s" % [door_i, s]): err.append("%s : porte %d côté %s absente" % [ln, door_i, s])
				var lower := find(root, "panto_lower")
				var upper := find(root, "panto_upper")
				var head := find(root, "panto_head")
				if find(root, "panto_base") == null or lower == null or upper == null or head == null:
					err.append("%s : pantographe incomplet" % ln)
				elif not lower.is_ancestor_of(upper) or not upper.is_ancestor_of(head):
					err.append("%s : hiérarchie du pantographe invalide" % ln)
	for mob in profiles:
		if mob and file_for(e, "cab", true) == file_for(e, "cab", false) and not mobile(): continue
		var cab := scene(file_for(e, "cab", mob))
		var label := "cabine mobile" if mob else "cabine"
		if cab == null: err.append(label + " illisible"); continue
		if find(cab, "cam_driver") == null: err.append("cabine : cam_driver absent")
		var aliases: Dictionary = e.get("control_aliases", {})
		var present := {}
		for n in cab.find_children("ctl_*", "", true, false): present[CabActions.action_for_node(str(n.name), aliases)] = true
		for a in CabActions.actions():
			if not present.has(a): err.append("cabine : %s absent" % CabActions.node_for(a))
		var cab_cap := int(budget.get("LOD0", {}).get("mobile_cab_tris" if mob else "pc_cab_tris", 40000 if mob else 80000))
		if triangles(cab) > cab_cap: err.append("%s : %d triangles > %d" % [label, triangles(cab), cab_cap])
	return err

static var _budget_cache: Dictionary = {}
static func _budgets() -> Dictionary:
	if not _budget_cache.is_empty(): return _budget_cache
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://docs/refonte-visuelle/budgets.json"))
	var r: Dictionary = (d as Dictionary).get("rolling_stock_lod", {}) if d is Dictionary else {}
	if r.has("LOD3_impostor"): r["LOD3"] = r.LOD3_impostor
	_budget_cache = r
	return r

## LOD selon la distance (m) avec hystérésis ; `ai` : un cran plus bas en Mobile.
static func lod_for(distance: float, previous: int = -1, ai: bool = false, for_mobile: bool = mobile()) -> int:
	var l := 3
	for i in 3:
		var d: float = LOD_DIST[i]
		if previous >= 0 and previous <= i: d *= 1.0 + HYSTERESIS   # on reste plus longtemps au LOD fin
		if distance < d: l = i; break
	if ai and for_mobile: l = mini(l + 1, 3)
	return l

## Habille `rig` en HD si sa variante est complète. Retourne l'instance (aussi dans rig.hd) ou null.
static func apply(rig, livery: Dictionary) -> HD:
	var vid := str(livery.get("variant_id", ""))
	var e := entry(vid)
	if e.is_empty(): return null
	# Production validates/loads only the active platform; full multi-profile
	# validation belongs to check() in tests/CI, avoiding hidden PC textures on Android.
	if not check(vid, rig, true).is_empty(): return null
	var hd := HD.new()
	hd.build(rig, e, livery)
	rig.hd = hd
	return hd

static func material_for(src: Material, livery: Dictionary, glass_alpha := -1.0) -> Material:
	if not src is BaseMaterial3D: return src
	var n := str(src.resource_name)
	var key := "%d|%s|%s" % [src.get_instance_id(), str(livery.get("variant_id", "")) + str(livery.get("base", "")), glass_alpha]
	if _mats.has(key): return _mats[key]
	var m := (src as BaseMaterial3D).duplicate() as BaseMaterial3D
	# LOD atlases also contain constant-UV colour swatches. Anisotropic sampling
	# of their zero derivatives produces black speckles on GLES/llvmpipe.
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS if n.begins_with("livery") else BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	if n.begins_with("paint_") or n.begins_with("livery"):
		var zone := n.trim_prefix("paint_")
		if n.begins_with("paint_") and zone in PAINT_ZONES and livery.has(zone):
			m.albedo_color = Color(livery[zone]) if livery[zone] is String else livery[zone]
		m.clearcoat_enabled = true; m.clearcoat = 0.7; m.clearcoat_roughness = 0.12
		m.roughness = minf(m.roughness, 0.4)
	elif n.begins_with("glass"):
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		var a := glass_alpha if glass_alpha >= 0.0 else (0.22 if n.contains("windshield") else 0.45)
		m.albedo_color = Color(0.10, 0.14, 0.17, a)
		m.metallic = 0.85; m.roughness = 0.04; m.metallic_specular = 1.0
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mats[key] = m
	return m

## Applique les matériaux HD (livrée, clearcoat, vitrages) à toute une hiérarchie.
static func dress(root: Node, livery: Dictionary, glass_alpha := -1.0) -> void:
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var g := mi as MeshInstance3D
		if g.mesh == null: continue
		for s in g.mesh.get_surface_count():
			var src := g.mesh.surface_get_material(s)
			var m := material_for(src, livery, glass_alpha)
			if m != src: g.set_surface_override_material(s, m)

static func emissive(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color.darkened(0.6); m.emission_enabled = true; m.emission = color; m.emission_energy_multiplier = 0.0
	return m


## Instance HD d'une rame : LOD par caisse, animations et émissifs pilotés par l'état.
class HD:
	extends RefCounted
	var entry: Dictionary = {}
	var livery: Dictionary = {}
	var lods: Array = []           # [lod] -> Array[Node3D] (une racine par caisse)
	var lod := -2
	var heavy: Array = []          # [lod] -> trop lourd pour Mobile (pas de mobile_file) : on monte d'un LOD
	var doors: Array = []          # {node, rest, side, dir, single}
	var pantos: Array = []         # {lower, upper, head, rl, ru, rh}
	var wipers: Array = []         # {node, rest, end}
	var mirrors: Array = []        # {node, rest, sign}
	var em: Dictionary = {}        # catégorie -> Array[StandardMaterial3D]
	var signs: Array = []          # Label3D
	var cab: CabView = null
	var cab_end := "A"
	var wiper_phase := 0.0
	var mirror_t := 0.0
	var state: Dictionary = {}
	var _rig_ref: WeakRef
	var _dest := ""

	func build(rig, e: Dictionary, liv: Dictionary) -> void:
		entry = e; livery = liv; _rig_ref = weakref(rig)
		for i in rig.modules.size():
			var mod: MeshInstance3D = rig.modules[i]
			mod.set_meta("procedural_mesh", mod.mesh)
			mod.mesh = null
			for c in mod.get_children():
				if c is Node3D: (c as Node3D).visible = false
		var tris0 := 0
		for li in 4:
			var tpl := StockHD.scene(StockHD.file_for(e, StockHD.LOD_NAMES[li]))
			var inst := tpl.duplicate() as Node3D
			StockHD.dress(inst, liv)
			var roots: Array = StockHD.modules_of(inst)
			var per: Array = []
			for i in roots.size():
				var r: Node3D = roots[i]
				var holder := Node3D.new(); holder.name = "HD_LOD%d" % li
				for o in [r] + r.find_children("*", "", true, false): o.owner = null
				r.get_parent().remove_child(r)
				r.transform = Transform3D.IDENTITY
				holder.add_child(r)
				rig.modules[i].add_child(holder)
				per.append(holder)
				if li > 0:
					for g in r.find_children("*", "GeometryInstance3D", true, false):
						(g as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if li >= 2 else (g as GeometryInstance3D).cast_shadow
			inst.free()
			lods.append(per)
			var t := 0
			for h in per: t += StockHD.triangles(h)
			if li == 0: tris0 = t
			heavy.append(StockHD.mobile() and t > int(StockHD._budgets().get(StockHD.LOD_NAMES[li], {}).get("mobile_tris", 1 << 30)))
			if li <= 1: _collect_anim(per, rig)
			_collect_em(per)
		rig.triangles = tris0
		set_lod(0)
		animate(rig)

	func _collect_anim(per: Array, rig) -> void:
		var cfg: Dictionary = rig.door_cfg
		for h in per:
			for key in (StockHD.doors_of(h) as Dictionary):
				for n in StockHD.doors_of(h)[key]:
					var nm := str(n.name)
					var dir := -1.0 if nm.ends_with("_a") else 1.0
					doors.append({"node": n, "rest": (n as Node3D).transform, "side": 1.0 if str(key).ends_with("R") else -1.0,
						"dir": dir, "single": not (nm.ends_with("_a") or nm.ends_with("_b")),
						"travel": float(cfg.get("travel_m", 0.65)), "single_travel": float(cfg.get("single_leaf_travel_m", cfg.get("travel_m", 0.8)))})
			var lo := StockHD.find(h, "panto_lower") as Node3D
			if lo != null:
				var up := StockHD.find(h, "panto_upper") as Node3D
				var hd_ := StockHD.find(h, "panto_head") as Node3D
				pantos.append({"lower": lo, "upper": up, "head": hd_, "rl": lo.transform, "ru": up.transform if up else Transform3D(), "rh": hd_.transform if hd_ else Transform3D()})
			for w in h.find_children("wiper_*", "Node3D", true, false):
				wipers.append({"node": w, "rest": (w as Node3D).transform, "end": str(w.name).substr(6, 1)})
			for m in h.find_children("mirror_*", "Node3D", true, false):
				mirrors.append({"node": m, "rest": (m as Node3D).transform, "sign": 1.0 if str(m.name).ends_with("L") else -1.0})

	func _collect_em(per: Array) -> void:
		for h in per:
			for mi in h.find_children("em_*", "MeshInstance3D", true, false):
				var nm := str(mi.name)
				var cat := "interior" if nm.begins_with("em_interior") else nm.trim_prefix("em_")
				if cat.substr(0, 5) in ["head_", "tail_", "dest_"]: cat = cat.substr(0, 6)   # em_head_A, em_head_A_1… → head_A
				var col := Color(1, 0.96, 0.85)
				if cat.begins_with("tail"): col = Color(1, 0.08, 0.05)
				elif cat.begins_with("dest"): col = Color(0.08, 0.06, 0.04)
				elif cat == "interior": col = Color(1, 0.95, 0.86)
				elif cat.begins_with("drl"):
					# Keep the modeller's signature colour (Naolib's green crown).
					var source := (mi as MeshInstance3D).mesh.surface_get_material(0) as BaseMaterial3D
					if source != null: col = source.emission
				var m := StockHD.emissive(col)
				(mi as MeshInstance3D).material_override = m
				if not em.has(cat): em[cat] = []
				em[cat].append(m)
			for a in h.find_children("sign_dest_*", "Node3D", true, false):
				var l := Label3D.new(); l.name = "Destination"
				l.font_size = 64; l.outline_size = 0; l.shaded = false; l.double_sided = false
				l.modulate = Color(1, 0.67, 0.22); l.rotation.y = PI
				l.position = Vector3(0, 0, -0.005)
				l.set_meta("width", float(entry.get("sign", {}).get("width_m", 1.2)))
				a.add_child(l); signs.append(l)

	## LOD affiché (0..3) ; -1 : extérieur masqué (vue cabine).
	func set_lod(l: int) -> void:
		while l >= 0 and l < 3 and l < heavy.size() and heavy[l]: l += 1
		if l == lod: return
		lod = l
		for li in lods.size():
			for h in lods[li]: (h as Node3D).visible = li == l

	## Portes et pantographe depuis l'état du rig (appelé par Rig._apply).
	func animate(rig) -> void:
		var out_m := float(rig.door_cfg.get("out_m", 0.06))
		var plug := str(rig.door_cfg.get("type", "plug")) == "plug"
		for d in doors:
			var t: float = rig.door_side_t(float(d.side))
			var u1 := smoothstep(0.0, 1.0, clampf(t / 0.3, 0.0, 1.0)) if plug else 0.0
			var u2 := smoothstep(0.0, 1.0, clampf((t - 0.3) / 0.7, 0.0, 1.0)) if plug else smoothstep(0.0, 1.0, t)
			var travel: float = d.single_travel if d.single else d.travel
			var rest: Transform3D = d.rest
			(d.node as Node3D).transform = Transform3D(rest.basis, rest.origin + Vector3(float(d.side) * out_m * u1, 0, float(d.dir) * travel * u2))
		var pt := smoothstep(0.0, 1.0, rig.panto_t)
		var pc: Dictionary = entry.get("panto", {})
		var a1 := deg_to_rad(float(pc.get("lower_deg", -50.0))) * pt
		var a2 := deg_to_rad(float(pc.get("upper_deg", 100.0))) * pt
		for p in pantos:
			(p.lower as Node3D).transform = (p.rl as Transform3D) * Transform3D(Basis(Vector3.RIGHT, a1))
			if p.upper: (p.upper as Node3D).transform = (p.ru as Transform3D) * Transform3D(Basis(Vector3.RIGHT, a2))
			if p.head: (p.head as Node3D).transform = (p.rh as Transform3D) * Transform3D(Basis(Vector3.RIGHT, -(a1 + a2)))

	## Émissifs, essuie-glaces, rétroviseurs, girouette. `st` : {headlights (0..1), interior (bool), wiper (bool),
	## mirrors_folded (bool), destination (String), night (0..1)} ; cabine active = A (le rig place toujours la caisse 0 en tête).
	func update(st: Dictionary, dt: float) -> void:
		state = st
		var head := float(st.get("headlights", 0.6))
		_energy("head_A", 3.0 * head); _energy("head_B", 0.0)
		_energy("drl_A", 2.0 * head); _energy("drl_B", 0.0)
		_energy("tail_A", 0.0); _energy("tail_B", 2.0)
		_energy("interior", 1.6 if bool(st.get("interior", false)) else 0.0)
		_energy("dest_A", 1.0); _energy("dest_B", 1.0)
		var dest := str(st.get("destination", livery.get("destination", "")))
		if dest != _dest:
			_dest = dest
			for l in signs:
				var lb := l as Label3D
				lb.text = dest.to_upper().substr(0, 24)
				lb.pixel_size = minf(0.004, float(lb.get_meta("width")) / maxf(lb.text.length() * 36.0, 1.0))
		# essuie-glace : balayage sinusoïdal, retour en butée à l'arrêt
		var on := bool(st.get("wiper", false))
		var period := float(entry.get("wiper", {}).get("period_s", 1.6))
		# Finish the current sweep when switched off; do not teleport from mid-glass
		# to the park stop after a fixed fade duration.
		if on: wiper_phase = fposmod(wiper_phase + dt / period, 1.0)
		elif wiper_phase > 0.0:
			wiper_phase += dt / period
			if wiper_phase >= 1.0: wiper_phase = 0.0
		var sweep := deg_to_rad(float(entry.get("wiper", {}).get("sweep_deg", 90.0)))
		var axis := _axis(str(entry.get("wiper", {}).get("axis", "z")))
		var a := sweep * (0.5 - 0.5 * cos(TAU * wiper_phase))
		for w in wipers: (w.node as Node3D).transform = (w.rest as Transform3D) * Transform3D(Basis(axis, a))
		mirror_t = move_toward(mirror_t, 1.0 if bool(st.get("mirrors_folded", false)) else 0.0, dt * 2.0)
		var fold := deg_to_rad(float(entry.get("mirror", {}).get("fold_deg", 80.0))) * smoothstep(0.0, 1.0, mirror_t)
		for m in mirrors: (m.node as Node3D).transform = (m.rest as Transform3D) * Transform3D(Basis(Vector3.UP, float(m.sign) * fold))

	func wiper_angle() -> float:
		var sweep := deg_to_rad(float(entry.get("wiper", {}).get("sweep_deg", 90.0)))
		return sweep * (0.5 - 0.5 * cos(TAU * wiper_phase))

	func energy(cat: String) -> float:
		var l: Array = em.get(cat, [])
		return (l[0] as StandardMaterial3D).emission_energy_multiplier if not l.is_empty() else -1.0

	func _energy(cat: String, e: float) -> void:
		for m in em.get(cat, []): (m as StandardMaterial3D).emission_energy_multiplier = e

	static func _axis(s: String) -> Vector3:
		return Vector3.UP if s == "y" else (Vector3.BACK if s == "z" else Vector3.RIGHT)

	## Cabine de conduite (rame du joueur) : instanciée à la demande dans la caisse de tête.
	func ensure_cab(rig) -> CabView:
		if cab != null: return cab
		var tpl := StockHD.scene(StockHD.file_for(entry, "cab"))
		if tpl == null: return null
		cab = CabView.new()
		cab.setup(tpl.duplicate() as Node3D, entry, livery)
		rig.modules[0].add_child(cab)
		cab.visible = false
		return cab

	func set_cab_visible(on: bool) -> void:
		if cab != null: cab.visible = on
		for li in lods.size():
			for h in lods[li]:
				for p in (h as Node).find_children("cab_proxy_A", "", true, false): (p as Node3D).visible = not on
