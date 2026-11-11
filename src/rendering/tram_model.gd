class_name TramModel
extends RefCounted
## Rames low poly générées depuis les plans `data/rolling_stock/plans/<famille>.json` (voir docs/rolling_stock_schema.md) :
## modules aux longueurs réelles, caisse profilée (jupe, baies, bandeau, épaulement de toit), face avant lissée par anneaux
## (front.plan / front.side), pare-brise, feux, girouette, portes aux positions du plan (vantaux animés), soufflets,
## équipements de toiture, pantographe animé, bogies ; livrées de `data/rolling_stock/liveries.json` (réseau / famille / ligne).
## Repère d'un module : x latéral, y vertical (0 = rail), -z = sens de marche ; origine au centre du module.
## Alpha des couleurs de sommets : < 0.75 vitrage éclairé la nuit, < 0.25 feux émissifs.

const GLASS_A := 0.5     # baies latérales, vitrage de portes (éclairés la nuit)
const SHIELD_A := 0.8    # pare-brise : sombre, non éclairé
const LAMP_A := 0.1      # feux, girouette (émissifs)
const PLAN_DIR := "res://data/rolling_stock/plans/"
const LIVERIES := "res://data/rolling_stock/liveries.json"
const RESEARCH := "res://data/rolling_stock/research.json"
const GAP := 0.12        # demi-intervalle d'intercirculation entre deux caisses
## Anciennes familles (sauvegardes, profils génériques) -> plans.
const ALIASES := {"citadis": "citadis_302", "citadis_302_hybride": "citadis_302", "citadis_402_aps": "citadis_402",
	"dualis": "citadis_dualis", "tango": "tango_rhonexpress", "tango_express": "tango_rhonexpress", "breda": "breda_vlc",
	"urbos_short": "urbos", "reims": "citadis_reims", "tours": "citadis_tours"}
const DEFAULT_COLORS := {"base": "#f1f2f2", "window": "#1d2a33", "door": "#f1f2f2", "front": "#f1f2f2", "roof": "#c9cdd0", "skirt": "#3a3f44"}
const COLOR_KEYS := ["base", "window", "door", "front", "roof", "skirt"]

static var _plans: Dictionary = {}
static var _liv: Dictionary = {}
static var _research: Dictionary = {}
static var _plain_mat: Dictionary = {}

# ---------------------------------------------------------------- données

static func _json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null: return {}
	var d = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}

## Identifiant de plan valide pour une famille (alias des anciennes familles, repli Citadis 302).
static func family_id(f: String) -> String:
	f = str(ALIASES.get(f, f))
	if f != "" and (_plans.has(f) or FileAccess.file_exists(PLAN_DIR + f + ".json")): return f
	return "citadis_302"

static func plan(f: String) -> Dictionary:
	var id := family_id(f)
	if not _plans.has(id): _plans[id] = _json(PLAN_DIR + id + ".json")
	return _plans[id]

static func plan_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for f in DirAccess.get_files_at(PLAN_DIR):
		if f.ends_with(".json"): out.append(f.get_basename())
	out.sort()
	return out

## Fiche sourcée d'une famille (research.json).
static func research(f: String) -> Dictionary:
	if _research.is_empty(): _research = _json(RESEARCH)
	return _research.get("families", {}).get(family_id(f), {})

static func _liveries() -> Dictionary:
	if _liv.is_empty(): _liv = _json(LIVERIES)
	return _liv

## [source_id, livrée réseau, clé de ligne, surcharge de ligne]
static func _ctx(meta: Dictionary) -> Array:
	var src := str(meta.get("source_id", ""))
	var net: Dictionary = {} if src == "" or src.begins_with("_") else _liveries().get(src, {})
	var key := str(meta.get("id", "")).trim_prefix(src + "_").split("_")[0].to_lower()
	var line: Dictionary = net.get("lines", {}).get(key, {})
	return [src, net, key, line]

static func _generic_family(meta: Dictionary) -> String:
	if str(meta.get("guidance", "steel")) == "rubber_guided": return "translohr"
	match str(meta.get("kind", "")):
		"tram-train": return "citadis_dualis"
		"express": return "tango_rhonexpress"
	return "citadis_302"

## Couches de surcharge applicables à une famille, de la plus générale à la plus précise : réseau, famille, ligne.
static func _layers(net: Dictionary, line: Dictionary, fam: String) -> Array:
	var out: Array = []
	if net.is_empty(): return out
	var base: Dictionary = net.duplicate()
	if family_id(str(net.get("family", ""))) != fam:
		base.erase("name"); base.erase("dims")
	out.append(base)
	var fo: Dictionary = net.get("families", {}).get(fam, {})
	if not fo.is_empty(): out.append(fo)
	var lf := str(line.get("family", ""))
	if not line.is_empty() and (lf == "" or family_id(lf) == fam): out.append(line)
	return out

static func _entry(net: Dictionary, line: Dictionary, fam: String, src: String, key: String) -> Dictionary:
	var p := plan(fam)
	var e := {"family": fam, "name": str(p.get("name", fam)), "length": float(p.get("length_m", 32.0)),
		"width": float(p.get("width_m", 2.4)), "network": src, "line": key}
	for l in _layers(net, line, fam):
		if l.has("name"): e.name = str(l.name)
		var d: Dictionary = l.get("dims", {})
		if d.has("length_m"): e.length = float(d.length_m)
		if d.has("width_m"): e.width = float(d.width_m)
	e.name = str(e.name).replace(" [AJOUT]", "").strip_edges()
	return e

## Flotte jouable d'un réseau / d'une ligne : entrées {name, family, length, width, network, line}.
## Matériel propre à la ligne d'abord, puis la flotte du réseau (sauf familles réservées à d'autres lignes).
static func fleet_for(meta: Dictionary) -> Array:
	var c := _ctx(meta)
	var src: String = c[0]; var net: Dictionary = c[1]; var key: String = c[2]; var line: Dictionary = c[3]
	var fams: Array[String] = []
	if net.is_empty():
		fams.append(_generic_family(meta))
	else:
		if line.has("family"): fams.append(family_id(str(line.family)))
		for f in net.get("fleet", [net.get("family", "citadis_302")]):
			var id := family_id(str(f))
			if id in fams: continue
			var on_lines: Dictionary = research(id).get("lines", {})
			if on_lines.has(src):
				if not key in on_lines[src]: continue
			elif line.has("family"):
				continue
			fams.append(id)
		if fams.is_empty(): fams.append(family_id(str(net.get("family", ""))))
	var out: Array = []
	for f in fams: out.append(_entry(net, line, f, src, key))
	return out

static func _color(v: Variant, route: Color) -> Color:
	var s := str(v)
	if s == "route": return route
	return Color.from_string(s, Color.GRAY)

## Livrée résolue (couleurs, éléments, dimensions) pour un réseau / une ligne et une entrée de flotte.
static func livery_for(meta: Dictionary, entry: Dictionary = {}) -> Dictionary:
	var c := _ctx(meta)
	var net: Dictionary = c[1]; var line: Dictionary = c[3]
	var fam := str(entry.get("family", ""))
	fam = family_id(fam) if fam != "" else str(fleet_for(meta)[0].family)
	var e := _entry(net, line, fam, c[0], c[2])
	var raw: Dictionary = DEFAULT_COLORS.duplicate()
	raw.elements = [] if not net.is_empty() else [{"type": "band", "colors": ["route"], "y": [0.5, 0.85], "zone": "sides+front"}]
	for l in _layers(net, line, fam):
		for k in COLOR_KEYS + ["elements"]:
			if l.has(k): raw[k] = l[k]
	var route := Color.from_string(str(meta.get("color", "#c8102e")), Color(0.78, 0.06, 0.18))
	if route.get_luminance() > 0.92: route = Color(0.2, 0.3, 0.45)
	var res := {"family": fam, "name": str(entry.get("name", e.name)), "length": float(entry.get("length", e.length)),
		"width": float(entry.get("width", e.width)), "route": route}
	for k in COLOR_KEYS: res[k] = _color(raw[k], route)
	var els: Array = []
	for el in raw.elements:
		var r: Dictionary = (el as Dictionary).duplicate(true)
		var cols: Array = []
		for col in r.get("colors", []): cols.append(_color(col, route))
		if cols.is_empty(): cols.append(route)
		r.colors = cols
		els.append(r)
	res.elements = els
	return res

# ---------------------------------------------------------------- construction

## Construit une rame animable. `length_m` < 0 : longueur de la livrée (dims) ou du plan.
static func build_rig(livery: Dictionary, length_m: float = -1.0) -> Rig:
	var fam := family_id(str(livery.get("family", "citadis_302")))
	var p := plan(fam)
	var L := length_m if length_m > 0.0 else float(livery.get("length", p.get("length_m", 32.0)))
	var bld := _Body.new(p, livery, L)
	return bld.make_rig()

## Compatibilité : modules seuls (sans animation).
static func build(length_m: float, livery: Dictionary, family: String = "") -> Array[MeshInstance3D]:
	var liv := livery.duplicate()
	if family != "": liv.family = family
	return build_rig(liv, length_m).modules

static func _material_plain(h: float) -> ShaderMaterial:
	var key := "%.2f" % h
	if not _plain_mat.has(key):
		var m: ShaderMaterial = Materials.tram(h).duplicate()
		m.next_pass = null
		_plain_mat[key] = m
	return _plain_mat[key]

static func _ip(pts: Array, x: float) -> float:
	if pts.is_empty(): return 0.0
	if x <= float(pts[0][0]): return float(pts[0][1])
	for i in range(1, pts.size()):
		var a: Array = pts[i - 1]; var b: Array = pts[i]
		if x <= float(b[0]):
			var d := float(b[0]) - float(a[0])
			return float(b[1]) if d <= 1e-6 else lerpf(float(a[1]), float(b[1]), (x - float(a[0])) / d)
	return float(pts[-1][1])

## Rame construite : modules (MeshInstance3D, origine au centre), vantaux et pantographe animés.
class Rig:
	extends RefCounted
	var family := ""
	var name := ""
	var length := 0.0
	var modules: Array[MeshInstance3D] = []
	var module_lengths: PackedFloat32Array = PackedFloat32Array()
	var module_starts: PackedFloat32Array = PackedFloat32Array()   # distance du nez avant à l'avant de chaque module
	var triangles := 0
	var leaves: Array = []          # {node, side, dir, travel, hinge}
	var door_cfg: Dictionary = {}
	var panto: Dictionary = {}      # {lower, upper, head, hinge: Vector2(y,z), l1, l2, head_z, down, up, roof}
	var panto_cfg: Dictionary = {}
	var doors_target := false
	var panto_target := true
	var door_t := 0.0
	var panto_t := 1.0

	func set_doors(open: bool) -> void: doors_target = open
	func set_pantograph(up: bool) -> void: panto_target = up
	func door_time() -> float: return maxf(float(door_cfg.get("open_s", 2.5)), 0.05)
	func panto_time() -> float: return maxf(float(panto_cfg.get("raise_s", 4.0)), 0.05)
	func doors_open() -> bool: return door_t >= 1.0
	func doors_closed() -> bool: return door_t <= 0.0
	func pantograph_up() -> bool: return panto_t >= 1.0
	func pantograph_down() -> bool: return panto_t <= 0.0
	## Hauteur de l'archet au-dessus du toit (m).
	func pantograph_height() -> float:
		return lerpf(float(panto.get("down", 0.25)), float(panto.get("up", 2.0)), smoothstep(0.0, 1.0, panto_t))

	## Place les états sans transition.
	func snap() -> void:
		door_t = 1.0 if doors_target else 0.0
		panto_t = 1.0 if panto_target else 0.0
		_apply()

	func update(dt: float) -> void:
		var d0 := door_t; var p0 := panto_t
		door_t = move_toward(door_t, 1.0 if doors_target else 0.0, dt / door_time())
		panto_t = move_toward(panto_t, 1.0 if panto_target else 0.0, dt / panto_time())
		if d0 != door_t or p0 != panto_t: _apply()

	## Modules alignés en ligne droite autour de l'origine (aperçus).
	func layout_straight() -> void:
		for i in modules.size():
			modules[i].position = Vector3(0, 0, -length * 0.5 + module_starts[i] + module_lengths[i] * 0.5)

	func _apply() -> void:
		var typ := str(door_cfg.get("type", "plug"))
		var out_m := float(door_cfg.get("out_m", 0.06))
		for lf in leaves:
			var n: Node3D = lf.node
			if typ == "swing":
				var a: float = -float(lf.side) * float(lf.dir) * deg_to_rad(95.0) * smoothstep(0.0, 1.0, door_t)
				var hinge: Vector3 = lf.hinge
				var b := Basis(Vector3.UP, a)
				n.transform = Transform3D(b, hinge - b * hinge)
				continue
			var u1 := 1.0; var u2 := smoothstep(0.0, 1.0, door_t)
			if typ == "plug":
				u1 = smoothstep(0.0, 1.0, clampf(door_t / 0.3, 0.0, 1.0))
				u2 = smoothstep(0.0, 1.0, clampf((door_t - 0.3) / 0.7, 0.0, 1.0))
			else:
				u1 = 0.0
			n.position = Vector3(float(lf.side) * out_m * u1, 0.0, float(lf.dir) * float(lf.travel) * u2)
		if panto.is_empty(): return
		var hinge: Vector2 = panto.hinge   # (y, z)
		var head := Vector2(float(panto.roof) + pantograph_height(), float(panto.head_z))
		var l1: float = panto.l1; var l2: float = panto.l2
		var dv := head - hinge
		var d := clampf(dv.length(), absf(l1 - l2) + 0.01, l1 + l2 - 0.01)
		var u := dv.normalized()
		head = hinge + u * d
		var a := (l1 * l1 - l2 * l2 + d * d) / (2.0 * d)
		var hh := sqrt(maxf(l1 * l1 - a * a, 0.0))
		var mid := hinge + u * a
		var k1 := mid + Vector2(-u.y, u.x) * hh
		var k2 := mid - Vector2(-u.y, u.x) * hh
		var knee := k1 if k1.y < k2.y else k2       # genou vers l'avant (-z)
		(panto.lower as Node3D).transform = _beam(hinge, knee)
		(panto.upper as Node3D).transform = _beam(knee, head)
		(panto.head as Node3D).position = Vector3(0, head.x, head.y)

	static func _beam(a: Vector2, b: Vector2) -> Transform3D:
		var v := Vector3(0, b.x - a.x, b.y - a.y)
		var z := Vector3.RIGHT.cross(v).normalized()
		return Transform3D(Basis(Vector3.RIGHT, v, z), Vector3(0, a.x, a.y))


## Accumulateur de triangles (couleurs par sommet, faces orientées vers `out`).
class _Mesh:
	extends RefCounted
	var st := SurfaceTool.new()
	var tris := 0

	func _init() -> void:
		st.begin(Mesh.PRIMITIVE_TRIANGLES)

	func tri(a: Vector3, b: Vector3, c: Vector3, col: Color, out: Vector3) -> void:
		var n := (b - a).cross(c - a)
		if n.length_squared() < 1e-10: return
		if n.dot(out) > 0.0:  # Godot : faces avant dans le sens horaire
			var t := b; b = c; c = t
		st.set_color(col); st.add_vertex(a)
		st.set_color(col); st.add_vertex(b)
		st.set_color(col); st.add_vertex(c)
		tris += 1

	func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, out: Vector3) -> void:
		tri(a, b, c, col, out); tri(a, c, d, col, out)

	func box(c: Vector3, s: Vector3, col: Color, top: Color = Color(0, 0, 0, 0)) -> void:
		var h := s * 0.5
		var p := [c + Vector3(-h.x, -h.y, -h.z), c + Vector3(h.x, -h.y, -h.z), c + Vector3(h.x, h.y, -h.z), c + Vector3(-h.x, h.y, -h.z),
			c + Vector3(-h.x, -h.y, h.z), c + Vector3(h.x, -h.y, h.z), c + Vector3(h.x, h.y, h.z), c + Vector3(-h.x, h.y, h.z)]
		quad(p[0], p[1], p[2], p[3], col, Vector3(0, 0, -1)); quad(p[5], p[4], p[7], p[6], col, Vector3(0, 0, 1))
		quad(p[4], p[0], p[3], p[7], col, Vector3(-1, 0, 0)); quad(p[1], p[5], p[6], p[2], col, Vector3(1, 0, 0))
		quad(p[3], p[2], p[6], p[7], top if top.a > 0.0 else col, Vector3(0, 1, 0)); quad(p[4], p[5], p[1], p[0], col, Vector3(0, -1, 0))

	## Prisme trapézoïdal : base (w, l) en y0, sommet (wt, lt) en y1, décalage du sommet en z.
	func frustum(c: Vector3, w: float, l: float, wt: float, lt: float, hgt: float, col: Color, top: Color, dz: float = 0.0) -> void:
		var b := [c + Vector3(-w / 2, 0, -l / 2), c + Vector3(w / 2, 0, -l / 2), c + Vector3(w / 2, 0, l / 2), c + Vector3(-w / 2, 0, l / 2)]
		var t := [c + Vector3(-wt / 2, hgt, -lt / 2 + dz), c + Vector3(wt / 2, hgt, -lt / 2 + dz), c + Vector3(wt / 2, hgt, lt / 2 + dz), c + Vector3(-wt / 2, hgt, lt / 2 + dz)]
		var ctr := c + Vector3(0, hgt * 0.5, 0)
		for i in 4:
			var j := (i + 1) % 4
			quad(b[i], b[j], t[j], t[i], col, ((b[i] + b[j] + t[i] + t[j]) * 0.25 - ctr).normalized())
		quad(t[0], t[1], t[2], t[3], top, Vector3.UP)

	## Polygone convexe plan (éventail).
	func poly(pts: Array, col: Color, out: Vector3) -> void:
		for i in range(1, pts.size() - 1): tri(pts[0], pts[i], pts[i + 1], col, out)

	func commit() -> ArrayMesh:
		return st.commit()


## Géométrie d'une rame (plan + livrée + longueur).
class _Body:
	extends RefCounted
	var P: Dictionary
	var L: Dictionary
	var total := 32.0
	var hw := 1.2
	var h := 3.3
	var yb := 0.25          # bas de caisse (jupe)
	var floor_y := 0.35
	var skirt := 0.45
	var wb := 1.05
	var wt := 2.45
	var cant := 2.75
	var sh := 0.25
	var door_top := 2.45
	var dglass_lo := 0.9
	var dglass_hi := 2.3
	var Lf := 1.5
	var front: Dictionary
	var side_pts: Array = []
	var plan_pts: Array = []
	var sect_pts: Array = []
	var ws_lo := 1.1
	var ws_hi := 2.8
	var wrap := 0.3
	var bumper := 0.05
	var mods: Array = []       # modules du plan, mis à l'échelle
	var scale := 1.0
	var levels: Array = []     # niveaux de paroi (yb..cant)
	var profile: Array = []    # demi-profil droit (Vector2) bas -> centre du toit
	var full: Array = []       # profil complet droite -> gauche
	var decals: Array = []     # {pts: Array[Vector2(zg, y)], col, glass: bool}
	var rubber := false

	func _init(p: Dictionary, liv: Dictionary, length_m: float) -> void:
		P = p; L = liv; total = length_m
		var b: Dictionary = P.get("body", {})
		hw = float(liv.get("width", P.get("width_m", 2.4))) * 0.5
		h = float(P.get("height_m", 3.3))
		floor_y = float(P.get("floor_m", 0.35))
		skirt = float(b.get("skirt_top_m", 0.45)); wb = float(b.get("window_bottom_m", 1.05)); wt = float(b.get("window_top_m", 2.45))
		cant = float(b.get("cant_m", 2.75)); sh = float(b.get("roof_shoulder_m", 0.25))
		rubber = P.has("guidance")
		yb = 0.14 if rubber else 0.25
		door_top = minf(wt, cant - 0.12)
		dglass_lo = maxf(floor_y + 0.55, wb - 0.15); dglass_hi = door_top - 0.12
		front = P.get("front", {})
		Lf = float(front.get("length_m", 1.5))
		side_pts = (front.get("side", [[0.0, 0.0]]) as Array).duplicate(true)
		if float(side_pts[-1][0]) < h - 0.02: side_pts.append([h, 1.0])
		plan_pts = front.get("plan", [[0, 1], [1, 0.8]])
		sect_pts = front.get("section", [])
		var ws: Dictionary = front.get("windshield", {})
		ws_lo = float(ws.get("bottom_m", 1.1)); ws_hi = float(ws.get("top_m", 2.8)); wrap = float(ws.get("wrap", 0.3))
		bumper = float(front.get("bumper_m", 0.05))
		_prepare_modules()
		_prepare_levels()
		_prepare_decals()

	# ------------------------------------------------ modules (ajout / retrait de paires, mise à l'échelle)
	func _has_panto(m: Dictionary) -> bool:
		for r in m.get("roof", []):
			if str(r.get("type", "")) == "pantograph": return true
		return false

	func _prepare_modules() -> void:
		mods = (P.get("modules", []) as Array).duplicate(true)
		var cur := 0.0
		for m in mods: cur += float(m.length_m)
		var inner := mods.slice(1, mods.size() - 1)
		var unit: Array = inner.slice(0, 2) if inner.size() >= 2 else inner
		var ulen := 0.0
		for m in unit: ulen += float(m.length_m)
		var guard := 0
		while ulen > 0.0 and total - cur > 0.6 * ulen and guard < 4:
			var copies: Array = []
			for m in unit:
				var c: Dictionary = (m as Dictionary).duplicate(true)
				if unit.size() == 1: c.bogie = true
				for r in c.get("roof", []):
					if str(r.type) == "pantograph": r.type = "box"
				copies.append(c)
			for k in copies.size(): mods.insert(1 + k, copies[k])
			cur += ulen; guard += 1
		guard = 0
		while ulen > 0.0 and mods.size() > 3 and cur - total > 0.6 * ulen and guard < 4:
			var removed := false
			for i in range(1, mods.size() - unit.size()):
				var ok := true
				for k in unit.size():
					if _has_panto(mods[i + k]) or str(mods[i + k].kind) != str(unit[k].kind): ok = false
				if ok:
					for k in unit.size(): mods.remove_at(i)
					cur -= ulen; removed = true
					break
			if not removed: break
			guard += 1
		scale = total / maxf(cur, 1.0)
		var has_p := false
		for m in mods: has_p = has_p or _has_panto(m)
		if not has_p:  # pantographe par défaut sur le module central
			var mid: Dictionary = mods[mods.size() / 2]
			var roof: Array = mid.get("roof", [])
			roof.append({"type": "pantograph", "z_m": float(mid.length_m) * 0.5, "size": [1.5, 0.3, 2.0]})
			mid.roof = roof

	# ------------------------------------------------ niveaux et profil
	func _prepare_levels() -> void:
		var ys: Array = [yb, floor_y, skirt, wb, wt, cant, door_top, ws_lo, ws_hi]
		for el in L.get("elements", []):
			var yr: Array = el.get("y", [])
			if yr.size() < 2: continue
			var y0 := float(yr[0]); var y1 := float(yr[1])
			ys.append(y0); ys.append(y1)
			var n := 0
			match str(el.get("type", "")):
				"stripes": n = (el.colors as Array).size()
				"gradient": n = 4
			for k in range(1, n): ys.append(lerpf(y0, y1, float(k) / n))
		for sp in side_pts: ys.append(float(sp[0]))
		ys.sort()
		levels = []
		for y in ys:
			var yy := clampf(float(y), yb, cant)
			if levels.is_empty() or yy - float(levels[-1]) > 0.035: levels.append(yy)
			elif is_equal_approx(yy, cant): levels[-1] = cant
		if float(levels[-1]) < cant - 0.001: levels.append(cant)
		profile = []
		for y in levels: profile.append(Vector2(hw, float(y)))
		profile.append(Vector2(hw - sh * 0.35, cant + (h - cant) * 0.62))
		profile.append(Vector2(hw - sh, h))
		profile.append(Vector2(0.0, h))
		full = profile.duplicate()
		for k in range(profile.size() - 2, -1, -1): full.append(Vector2(-profile[k].x, profile[k].y))

	# ------------------------------------------------ couleurs
	func _zone_ok(el: Dictionary, zone: String) -> bool:
		var z := str(el.get("zone", "sides"))
		if str(el.get("type", "")) == "front_mask": return zone == "front"
		match zone:
			"side": return z.contains("sides")
			"front": return z.contains("front")
			"door": return z.contains("sides") or z.contains("doors")
		return false

	func _z_ok(el: Dictionary, zg: float) -> bool:
		if not el.has("z"): return true
		var zr: Array = el.z
		var f := zg / total
		if f >= float(zr[0]) and f <= float(zr[1]): return true
		return bool(el.get("symmetric", false)) and 1.0 - f >= float(zr[0]) and 1.0 - f <= float(zr[1])

	## Couleur de surface hors vitrage : base / face avant / porte / jupe puis éléments de livrée.
	func surf(y: float, zg: float, zone: String) -> Color:
		var c: Color = L.skirt if y < skirt else (L.front if zone == "front" else (L.door if zone == "door" else L.base))
		if zone == "door" and y < skirt: c = L.door
		for el in L.elements:
			var t := str(el.get("type", ""))
			if not t in ["band", "front_mask", "stripes", "gradient"]: continue
			if not _zone_ok(el, zone) or not _z_ok(el, zg): continue
			var yr: Array = el.get("y", [0, 0])
			var y0 := float(yr[0]); var y1 := float(yr[1])
			if y < y0 or y > y1: continue
			var cols: Array = el.colors
			var f := clampf((y - y0) / maxf(y1 - y0, 0.001), 0.0, 0.999)
			match t:
				"stripes": c = cols[int(f * cols.size())]
				"gradient": c = (cols[0] as Color).lerp(cols[-1], f)
				_: c = cols[0]
		return c

	func glass() -> Color:  # reflet léger du ciel pour la lisibilité
		var g: Color = (L.window as Color).lerp(Color(0.45, 0.55, 0.63), 0.18); g.a = GLASS_A; return g

	func shield() -> Color:
		var g: Color = (L.window as Color).lerp(Color(0.42, 0.52, 0.62), 0.25); g.a = SHIELD_A; return g

	# ------------------------------------------------ décors (diagonales, motifs)
	func _prepare_decals() -> void:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(str(L.get("name", "")) + str(L.get("family", "")))
		for el in L.elements:
			var t := str(el.get("type", ""))
			var yr: Array = el.get("y", [skirt, cant])
			var y0 := float(yr[0]); var y1 := minf(float(yr[1]), cant)
			var cols: Array = el.colors
			if t == "diagonal" and str(el.get("zone", "")).contains("sides"):
				var zr: Array = el.get("z", [0.0, 0.15])
				var za := float(zr[0]) * total; var zb := float(zr[1]) * total
				var w := (zb - za) / cols.size()
				var run := (y1 - y0) / tan(deg_to_rad(float(el.get("angle_deg", 60.0))))
				for k in cols.size():
					var z0 := za + w * k
					var pts := [Vector2(z0, y0), Vector2(z0 + w, y0), Vector2(z0 + w + run, y1), Vector2(z0 + run, y1)]
					decals.append({"pts": pts, "col": cols[k], "glass": false})
					if bool(el.get("symmetric", false)):
						var mp: Array = []
						for q in pts: mp.append(Vector2(total - q.x, q.y))
						decals.append({"pts": mp, "col": cols[k], "glass": false})
			elif t == "panel" and str(el.get("zone", "")).contains("sides"):
				_pattern(str(el.get("pattern", "")), cols, y0, y1, rng)

	func _shape(kind: String, c: Vector2, r: float, ang: float) -> Array:
		var pts: Array = []
		match kind:
			"hex":
				for i in 6: pts.append(c + Vector2(r, 0).rotated(ang + i * TAU / 6.0))
			"leaf":
				pts = [c + Vector2(-r * 1.6, 0).rotated(ang), c + Vector2(0, -r * 0.55).rotated(ang), c + Vector2(r * 1.6, 0).rotated(ang), c + Vector2(0, r * 0.55).rotated(ang)]
			"rect":
				pts = [c + Vector2(-r, -r * 0.35), c + Vector2(r, -r * 0.35), c + Vector2(r, r * 0.35), c + Vector2(-r, r * 0.35)]
			"wing":  # aile d'hirondelle
				pts = [c, c + Vector2(r * 1.5, r * 0.55).rotated(ang), c + Vector2(r * 1.7, r * 0.75).rotated(ang), c + Vector2(r * 0.1, r * 0.35).rotated(ang)]
		return pts

	func _pattern(pat: String, cols: Array, y0: float, y1: float, rng: RandomNumberGenerator) -> void:
		var bands: Array = []   # zones verticales sans vitrage
		if y0 < wb: bands.append([maxf(y0, skirt), minf(y1, wb)])
		if y1 > wt: bands.append([maxf(y0, wt), minf(y1, cant)])
		match pat:
			"door_berlingots", "led_bars", "ring", "visuals":
				return  # traités sur les portes / la face avant, ou non représentables
			"perret_claustra":
				for b in bands:
					if float(b[1]) - float(b[0]) < 0.2: continue
					var z := 0.6
					while z < total - 0.6:
						decals.append({"pts": _shape("rect", Vector2(z, (float(b[0]) + float(b[1])) * 0.5), 0.22, 0.0), "col": cols[0], "glass": true})
						z += 0.7
				return
		for b in bands:
			var ya := float(b[0]); var yz := float(b[1])
			if yz - ya < 0.15: continue
			var n := int(total * (yz - ya) * 1.1)
			for i in n:
				var c := Vector2(rng.randf_range(0.3, total - 0.3), rng.randf_range(ya + 0.06, yz - 0.06))
				var r := rng.randf_range(0.10, minf(0.28, (yz - ya) * 0.45))
				var col: Color = cols[rng.randi() % cols.size()]
				match pat:
					"swallows":
						var a := rng.randf_range(-0.5, 0.3)
						var wing := _shape("wing", c, r, a)
						var mirror: Array = []
						for q in wing: mirror.append(Vector2(2.0 * c.x - q.x, q.y))
						mirror.reverse()
						decals.append({"pts": wing, "col": col, "glass": true})
						decals.append({"pts": mirror, "col": col, "glass": true})
					"leaves":
						decals.append({"pts": _shape("leaf", c, r, rng.randf_range(-0.8, 0.8)), "col": col, "glass": true})
					"heritage":
						decals.append({"pts": _shape("rect", c, r, 0.0), "col": col, "glass": true})
					_:
						decals.append({"pts": _shape("hex", c, r, rng.randf() * PI), "col": col, "glass": true})

	## Découpe d'un polygone convexe par un rectangle (z0, z1, y0, y1) — Sutherland-Hodgman.
	static func clip(pts: Array, z0: float, z1: float, y0: float, y1: float) -> Array:
		var out := pts
		for e in 4:
			if out.is_empty(): return out
			var inp := out; out = []
			for i in inp.size():
				var a: Vector2 = inp[i]; var b: Vector2 = inp[(i + 1) % inp.size()]
				var da := _dist(a, e, z0, z1, y0, y1); var db := _dist(b, e, z0, z1, y0, y1)
				if da >= 0.0: out.append(a)
				if (da >= 0.0) != (db >= 0.0): out.append(a + (b - a) * (da / (da - db)))
		return out

	static func _dist(p: Vector2, e: int, z0: float, z1: float, y0: float, y1: float) -> float:
		match e:
			0: return p.x - z0
			1: return z1 - p.x
			2: return p.y - y0
		return y1 - p.y

	func _emit_decals(m: _Mesh, x: float, side: float, gz: float, z0: float, z1: float, y_ranges_plain: Array, y_ranges_glass: Array) -> void:
		# gz : z global du centre du module (z local = zg - gz)
		for d in decals:
			var yrs: Array = y_ranges_glass if bool(d.glass) else y_ranges_plain
			for yr in yrs:
				var c := clip(d.pts, z0 + gz, z1 + gz, float(yr[0]), float(yr[1]))
				if c.size() < 3: continue
				var p3: Array = []
				for q in c: p3.append(Vector3(x, q.y, q.x - gz))
				m.poly(p3, d.col, Vector3(side, 0, 0))

	# ------------------------------------------------ face avant
	func smax(y: float) -> float:
		return clampf(1.0 - TramModel._ip(side_pts, y), 0.0, 1.0)

	func plan_w(s: float) -> float:
		return TramModel._ip(plan_pts, s)

	func sect_w(y: float, s: float) -> float:
		if sect_pts.is_empty(): return 1.0
		return lerpf(1.0, TramModel._ip(sect_pts, y), s)

	func nose_pt(p: Vector2, s: float, zj: float, dir: float) -> Vector3:
		var bump := bumper * s if p.y <= skirt + 0.01 else 0.0
		return Vector3(p.x * plan_w(s) * sect_w(p.y, s), p.y, zj + dir * (s * Lf + bump))

	## z de la surface avant au point (|x|, y) (feux, girouette).
	func face_z(x: float, y: float, zj: float, dir: float) -> float:
		var sm := smax(y)
		var s := sm
		if hw * plan_w(sm) * sect_w(y, sm) < x:
			var lo := 0.0; var hi := sm
			for i in 12:
				var mid := (lo + hi) * 0.5
				if hw * plan_w(mid) * sect_w(y, mid) > x: lo = mid
				else: hi = mid
			s = lo
		return zj + dir * (s * Lf + (bumper * s if y <= skirt + 0.01 else 0.0))

	func nose(m: _Mesh, zj: float, dir: float, is_front: bool, gz: float) -> void:
		var S := [0.0, 0.22, 0.42, 0.6, 0.75, 0.88, 1.0]
		var rings: Array = []; var ses: Array = []
		for s in S:
			var ring: Array = []; var se: Array = []
			for p in full:
				var e := minf(float(s), smax(p.y))
				ring.append(nose_pt(p, e, zj, dir)); se.append(e)
			rings.append(ring); ses.append(se)
		var zg := gz + zj
		for k in range(1, rings.size()):
			var A: Array = rings[k - 1]; var B: Array = rings[k]
			for j in range(full.size() - 1):
				var a0: Vector3 = A[j]; var a1: Vector3 = A[j + 1]; var b0: Vector3 = B[j]; var b1: Vector3 = B[j + 1]
				if a0.is_equal_approx(b0) and a1.is_equal_approx(b1): continue
				var y := (a0.y + a1.y + b0.y + b1.y) * 0.25
				var s := (float(ses[k - 1][j]) + float(ses[k - 1][j + 1]) + float(ses[k][j]) + float(ses[k][j + 1])) * 0.25
				var col: Color
				if y > ws_lo and y < ws_hi and s >= smax(y) - wrap - 0.02 and s > 0.1:
					col = shield()
				elif y >= h - 0.02:
					col = L.roof
				else:
					col = surf(y, zg, "front" if s > 0.18 else "side")
				var xm := (a0.x + a1.x + b0.x + b1.x) * 0.25
				m.quad(a0, a1, b1, b0, col, Vector3(xm, y - h * 0.5, dir * 0.8))
		# calotte frontale : bandes horizontales entre les deux flancs, légèrement bombée au centre
		var tip: Array = rings[-1]
		var n := full.size()
		var c_idx := profile.size() - 1
		for j in range(c_idx):
			var r0: Vector3 = tip[j]; var r1: Vector3 = tip[j + 1]; var l0: Vector3 = tip[n - 1 - j]; var l1: Vector3 = tip[n - 2 - j]
			var y := (r0.y + r1.y) * 0.5
			var b0 := Vector3(0, 0, dir * (0.05 if r0.y < cant else 0.0)); var b1 := Vector3(0, 0, dir * (0.05 if r1.y < cant else 0.0))
			var m0 := (r0 + l0) * 0.5 + b0; var m1 := (r1 + l1) * 0.5 + b1
			var col: Color
			var frame := surf(y, zg, "front")
			if y > ws_lo and y < ws_hi: col = shield()
			elif y >= h - 0.02: col = L.roof
			else: col = frame
			if col == frame or y >= h - 0.02:
				m.quad(r0, r1, m1, m0, col, Vector3(0.2, 0, dir))
				m.quad(m0, m1, l1, l0, col, Vector3(-0.2, 0, dir))
			else:  # pare-brise encadré par des montants
				var k0 := 0.9 if wrap > 0.15 else 0.94
				var e0 := m0.lerp(r0, k0); var e1 := m1.lerp(r1, k0); var f0 := m0.lerp(l0, k0); var f1 := m1.lerp(l1, k0)
				m.quad(r0, r1, e1, e0, frame, Vector3(0.3, 0, dir))
				m.quad(e0, e1, m1, m0, col, Vector3(0.2, 0, dir))
				m.quad(m0, m1, f1, f0, col, Vector3(-0.2, 0, dir))
				m.quad(f0, f1, l1, l0, frame, Vector3(-0.3, 0, dir))
		# dessous du nez
		var jb: Vector3 = rings[0][0]; var tb: Vector3 = tip[0]
		m.quad(Vector3(jb.x, yb, jb.z), Vector3(-jb.x, yb, jb.z), Vector3(-tb.x, yb, tb.z), Vector3(tb.x, yb, tb.z), L.skirt.darkened(0.3), Vector3.DOWN)
		_lamps(m, zj, dir, is_front)

	func _lamps(m: _Mesh, zj: float, dir: float, is_front: bool) -> void:
		var hl: Dictionary = front.get("headlights", {})
		var y := float(hl.get("y_m", 0.85)); var x := float(hl.get("x_m", 0.8))
		var w := float(hl.get("w_m", 0.3)); var hh := float(hl.get("h_m", 0.12))
		var shape := str(hl.get("shape", "rect"))
		var white := Color(1.0, 0.97, 0.86, LAMP_A)
		var red := Color(0.95, 0.12, 0.08, LAMP_A)
		for side in [-1.0, 1.0]:
			var lx: float = side * x
			var z := face_z(absf(lx), y, zj, dir)
			if is_front:
				_lamp(m, shape, Vector3(lx, y, z), w, hh, white, dir)
			else:
				_lamp(m, shape, Vector3(lx, y, z), w * 0.7, hh, red, dir)
		var ul: Dictionary = front.get("upper_light", {})
		if not ul.is_empty():
			var uy := float(ul.get("y_m", h - 0.15))
			_lamp(m, "round", Vector3(0, uy, face_z(0.0, uy, zj, dir)), 0.14, 0.14, white if is_front else red, dir)
		var dest: Dictionary = front.get("destination", {})
		var dy := float(dest.get("y_m", h - 0.45)); var dw := float(dest.get("w_m", 1.4)); var dh := float(dest.get("h_m", 0.22))
		dy = minf(dy, h - dh * 0.5 - 0.03)
		var dz := face_z(dw * 0.5, dy, zj, dir)
		m.box(Vector3(0, dy, dz), Vector3(dw + 0.06, dh + 0.06, 0.04), Color(0.05, 0.05, 0.06))
		m.box(Vector3(-dw * 0.12, dy, dz + dir * 0.025), Vector3(dw * 0.62, dh * 0.5, 0.03), Color(1.0, 0.6, 0.1, LAMP_A))
		m.box(Vector3(dw * 0.36, dy, dz + dir * 0.025), Vector3(dw * 0.12, dh * 0.6, 0.03), Color(1.0, 0.6, 0.1, LAMP_A))
		var ring: Dictionary = front.get("ring", {})
		if not ring.is_empty():
			var ry := float(ring.get("y_m", 1.0)); var rr := float(ring.get("r_m", 0.35)); var rw := float(ring.get("width_m", 0.05))
			var rc: Color = L.route if str(ring.get("color", "route")) == "route" else Color.from_string(str(ring.color), Color.WHITE)
			var segs := 14
			for i in segs:
				var a0 := TAU * i / segs; var a1 := TAU * (i + 1) / segs
				var pts: Array = []
				for q in [[a0, rr + rw], [a1, rr + rw], [a1, rr - rw], [a0, rr - rw]]:
					var px := cos(float(q[0])) * float(q[1]); var py := ry + sin(float(q[0])) * float(q[1])
					pts.append(Vector3(px, py, face_z(absf(px), py, zj, dir) + dir * 0.012))
				m.poly(pts, rc, Vector3(0, 0, dir))
		for el in L.elements:  # barres lumineuses de face avant (Tours)
			if str(el.get("pattern", "")) == "led_bars" and is_front:
				var yr: Array = el.get("y", [0.6, 2.6])
				for side in [-1.0, 1.0]:
					var bx: float = side * (hw * plan_w(1.0) - 0.12)
					var by := (float(yr[0]) + float(yr[1])) * 0.5
					m.box(Vector3(bx, by, face_z(absf(bx), by, zj, dir) + dir * 0.01), Vector3(0.05, float(yr[1]) - float(yr[0]), 0.04), Color(0.92, 0.95, 1.0, LAMP_A))

	func _lamp(m: _Mesh, shape: String, c: Vector3, w: float, hh: float, col: Color, dir: float) -> void:
		var bez := Color(0.08, 0.08, 0.09)
		if shape == "round":
			var r := maxf(w, hh) * 0.5
			var pts: Array = []; var outer: Array = []
			for i in 8:
				var a := TAU * i / 8.0
				pts.append(c + Vector3(cos(a) * r, sin(a) * r, dir * 0.03))
				outer.append(c + Vector3(cos(a) * (r + 0.04), sin(a) * (r + 0.04), dir * 0.02))
			m.poly(outer, bez, Vector3(0, 0, dir))
			m.poly(pts, col, Vector3(0, 0, dir))
		else:
			m.box(c + Vector3(0, 0, dir * 0.01), Vector3(w + 0.06, hh + 0.06, 0.04), bez)
			m.box(c + Vector3(0, 0, dir * 0.03), Vector3(w, hh, 0.03), col)

	# ------------------------------------------------ caisse d'un module
	func make_rig() -> TramModel.Rig:
		var rig := TramModel.Rig.new()
		rig.family = str(P.get("id", "")); rig.name = str(L.get("name", P.get("name", "")))
		rig.length = total
		rig.door_cfg = P.get("door_anim", {})
		rig.panto_cfg = P.get("pantograph", {})
		var mat := Materials.tram(h)
		var plain := TramModel._material_plain(h)
		var g0 := 0.0
		var n := mods.size()
		for i in n:
			var md: Dictionary = mods[i]
			var Lm := float(md.length_m) * scale
			var m := _Mesh.new()
			var mi := MeshInstance3D.new()
			mi.name = "Module%d" % i
			var leaves := _module(m, md, i, n, Lm, g0 + Lm * 0.5, rig, mi, mat, plain)
			mi.mesh = m.commit()
			mi.material_override = mat
			rig.triangles += m.tris + leaves
			rig.modules.append(mi)
			rig.module_lengths.append(Lm)
			rig.module_starts.append(g0)
			g0 += Lm
		rig.snap()
		return rig

	func _module(m: _Mesh, md: Dictionary, i: int, n: int, Lm: float, gz: float, rig: TramModel.Rig, mi: MeshInstance3D, mat: Material, plain: Material) -> int:
		var front_cab := i == 0 and str(md.kind) == "cab"
		var rear_cab := i == n - 1 and str(md.kind) == "cab"
		var zA := -Lm * 0.5 + (Lf if front_cab else GAP)
		var zB := Lm * 0.5 - (Lf if rear_cab else GAP)
		var zo := -Lm * 0.5   # z local de l'avant du module
		# portes et baies (z local)
		var doors: Array = []
		for d in md.get("doors", []):
			var zc := zo + float(d.z_m) * scale
			var w := float(d.get("width_m", 1.3))
			doors.append({"z0": clampf(zc - w * 0.5, zA + 0.05, zB - 0.05), "z1": clampf(zc + w * 0.5, zA + 0.05, zB - 0.05), "leaves": int(d.get("leaves", 2)), "zc": zc})
		var wins: Array = []
		for wdw in md.get("windows", []):
			var a := clampf(zo + float(wdw.z0_m) * scale, zA, zB); var b := clampf(zo + float(wdw.z1_m) * scale, zA, zB)
			if b - a > 0.05: wins.append([a, b])
		var zs: Array = [zA, zB]
		for d in doors: zs.append(d.z0); zs.append(d.z1)
		for wdw in wins: zs.append(wdw[0]); zs.append(wdw[1])
		for el in L.elements:
			if el.has("z") and str(el.type) in ["band", "stripes", "gradient"]:
				for f in el.z:
					zs.append(float(f) * total - gz)
					if bool(el.get("symmetric", false)): zs.append((1.0 - float(f)) * total - gz)
		var zz: Array = []
		for z in zs:
			if float(z) >= zA - 1e-4 and float(z) <= zB + 1e-4: zz.append(float(z))
		zz.sort()
		var cuts: Array = []
		for z in zz:
			if cuts.is_empty() or float(z) - float(cuts[-1]) > 0.01: cuts.append(z)
		cuts[-1] = zB
		var interior := Color(0.16, 0.17, 0.19, GLASS_A)
		# parois latérales : rangées de niveaux, cellules fusionnées par couleur
		for side in [1.0, -1.0]:
			var x: float = side * hw
			for r in range(levels.size() - 1):
				var y0 := float(levels[r]); var y1 := float(levels[r + 1])
				var ym := (y0 + y1) * 0.5
				var run_z := float(cuts[0]); var run_c := Color(-1, 0, 0)
				for k in range(cuts.size() - 1):
					var za := float(cuts[k]); var zb := float(cuts[k + 1])
					var zm := (za + zb) * 0.5
					var col: Color
					var in_door := false
					for d in doors:
						if zm > float(d.z0) and zm < float(d.z1) and ym > floor_y and ym < door_top: in_door = true
					var in_win := false
					for wdw in wins:
						if zm > float(wdw[0]) and zm < float(wdw[1]) and ym > wb and ym < wt: in_win = true
					if in_door: col = interior
					elif in_win: col = glass()
					else: col = surf(ym, zm + gz, "side")
					if k > 0 and not col.is_equal_approx(run_c):
						m.quad(Vector3(x, y0, run_z), Vector3(x, y1, run_z), Vector3(x, y1, za), Vector3(x, y0, za), run_c, Vector3(side, 0, 0))
						run_z = za
					run_c = col
				m.quad(Vector3(x, y0, run_z), Vector3(x, y1, run_z), Vector3(x, y1, zB), Vector3(x, y0, zB), run_c, Vector3(side, 0, 0))
			# épaulement et toit
			for k in range(levels.size() - 1, profile.size() - 1):
				var a: Vector2 = profile[k]; var b: Vector2 = profile[k + 1]
				var col: Color = L.roof if k >= levels.size() else surf((a.y + b.y) * 0.5, gz, "side")
				m.quad(Vector3(side * a.x, a.y, zA), Vector3(side * b.x, b.y, zA), Vector3(side * b.x, b.y, zB), Vector3(side * a.x, a.y, zB), col,
					Vector3(side * (a.x + b.x), (a.y + b.y) - h, 0))
			# décors (hors portes ; les portes reçoivent leur part sur les vantaux)
			var zfree: Array = []
			var zcur := zA
			for d in doors:
				zfree.append([zcur, float(d.z0)]); zcur = float(d.z1)
			zfree.append([zcur, zB])
			for zr in zfree:
				if float(zr[1]) - float(zr[0]) > 0.02:
					_emit_decals(m, x + side * 0.008, side, gz, float(zr[0]), float(zr[1]), [[yb, cant]], [[yb, wb], [wt, cant]])
		# fond de caisse
		m.quad(Vector3(-hw, yb, zA), Vector3(hw, yb, zA), Vector3(hw, yb, zB), Vector3(-hw, yb, zB), L.skirt.darkened(0.3), Vector3.DOWN)
		# extrémités d'intercirculation, soufflet
		var dark := Color(0.13, 0.13, 0.14)
		for e in [[zA, -1.0, front_cab], [zB, 1.0, rear_cab]]:
			if bool(e[2]): continue
			var pts: Array = []
			for p in full: pts.append(Vector3(p.x, p.y, float(e[0])))
			m.poly(pts, dark, Vector3(0, 0, float(e[1])))
		if i < n - 1:
			var bl := Vector3(hw * 2.0 - 0.22, cant - yb + 0.05, GAP * 2.0 + 0.06)
			m.box(Vector3(0, yb + 0.05 + bl.y * 0.5, Lm * 0.5), bl, Color(0.17, 0.17, 0.18))
			for rz in [-0.06, 0.06]:
				m.box(Vector3(0, yb + 0.05 + bl.y * 0.5, Lm * 0.5 + float(rz)), Vector3(bl.x + 0.06, bl.y + 0.04, 0.035), Color(0.1, 0.1, 0.11))
		# face avant
		if front_cab: nose(m, zA, -1.0, true, gz)
		if rear_cab: nose(m, zB, 1.0, false, gz)
		# bogies / roues
		if bool(md.get("bogie", false)):
			var bz := zo + float(md.get("bogie_z_m", float(md.length_m) * 0.5)) * scale
			_bogie(m, bz)
		# toiture
		for r in md.get("roof", []):
			_roof_item(m, r, zo, zA, zB, front_cab, rear_cab, rig, mi, plain)
		# vantaux
		var tris := 0
		for d in doors:
			tris += _door(d, gz, rig, mi, mat)
		return tris

	func _bogie(m: _Mesh, bz: float) -> void:
		var steel := Color(0.16, 0.16, 0.17)
		var wheel := Color(0.28, 0.27, 0.26)
		if rubber:
			m.box(Vector3(0, 0.12, bz), Vector3(0.3, 0.16, 0.8), steel)   # galet de guidage central
			for side in [-1.0, 1.0]:
				_wheel(m, Vector3(side * (hw - 0.45), 0.42, bz), 0.42, 0.3, Color(0.08, 0.08, 0.08), side)
			return
		for side in [-1.0, 1.0]:
			m.box(Vector3(side * (hw - 0.42), 0.42, bz), Vector3(0.18, 0.3, 2.3), steel)
			for az in [-0.9, 0.9]:
				_wheel(m, Vector3(side * (hw - 0.52), 0.32, bz + float(az)), 0.32, 0.12, wheel, side)

	func _wheel(m: _Mesh, c: Vector3, r: float, w: float, col: Color, side: float) -> void:
		var pts: Array = []
		for i in 8:
			var a := TAU * i / 8.0
			pts.append(Vector2(cos(a) * r, sin(a) * r))
		var xo: float = c.x + side * w * 0.5
		var xi: float = c.x - side * w * 0.5
		var face: Array = []
		for p in pts: face.append(Vector3(xo, c.y + p.y, c.z + p.x))
		m.poly(face, col.darkened(0.2), Vector3(side, 0, 0))
		for i in 8:
			var a: Vector2 = pts[i]; var b: Vector2 = pts[(i + 1) % 8]
			m.quad(Vector3(xo, c.y + a.y, c.z + a.x), Vector3(xo, c.y + b.y, c.z + b.x), Vector3(xi, c.y + b.y, c.z + b.x), Vector3(xi, c.y + a.y, c.z + a.x), col,
				Vector3(0, (a.y + b.y), (a.x + b.x)))

	func _roof_item(m: _Mesh, r: Dictionary, zo: float, zA: float, zB: float, front_cab: bool, rear_cab: bool, rig: TramModel.Rig, mi: MeshInstance3D, plain: Material) -> void:
		var sz: Array = r.get("size", [1.4, 0.3, 2.0])
		var w := minf(float(sz[0]), hw * 2.0 - 0.1); var hh := float(sz[1]); var l := float(sz[2])
		var zc := zo + float(r.get("z_m", 0.0)) * scale
		var roof: Color = L.roof
		match str(r.get("type", "box")):
			"hvac":
				m.frustum(Vector3(0, h, zc), w, l, w - 0.22, l - 0.2, hh, roof.darkened(0.08), roof.darkened(0.25))
			"fairing":
				# carénage profilé posé sur la caisse, plongeant vers l'extrémité la plus proche
				var dz := -1.0 if zc < 0.0 else 1.0
				if front_cab: dz = -1.0
				elif rear_cab: dz = 1.0
				var za := maxf(zc - l * 0.5, zA); var zb := minf(zc + l * 0.5, zB)
				if zb - za < 0.6:
					if dz < 0.0: za = zA; zb = zA + l
					else: za = zB - l; zb = zB
				_wedge(m, za, zb, w, hh, dz, roof.lightened(0.04))
			"pantograph":
				_pantograph(m, zc, w, l, rig, mi, plain)
			_:
				m.box(Vector3(0, h + hh * 0.5, zc), Vector3(w, hh, l), roof.darkened(0.15), roof.darkened(0.3))

	## Carénage en coin : hauteur nulle côté `dz` (extrémité), `hh` à l'opposé.
	func _wedge(m: _Mesh, za: float, zb: float, w: float, hh: float, dz: float, col: Color) -> void:
		var lo := za if dz < 0.0 else zb
		var hi := zb if dz < 0.0 else za
		var w2 := w * 0.5; var wt := w2 - 0.12
		var b0 := Vector3(-w2, h, lo); var b1 := Vector3(w2, h, lo); var b2 := Vector3(w2, h, hi); var b3 := Vector3(-w2, h, hi)
		var t2 := Vector3(wt, h + hh, hi); var t3 := Vector3(-wt, h + hh, hi)
		var t1 := Vector3(wt, h + hh * 0.75, lerpf(hi, lo, 0.45)); var t0 := Vector3(-wt, h + hh * 0.75, lerpf(hi, lo, 0.45))
		m.quad(t0, t1, t2, t3, col, Vector3.UP)
		m.quad(b0, b1, t1, t0, col, Vector3(0, 1, dz))
		m.quad(b2, b3, t3, t2, col, Vector3(0, 0, -dz))
		for sx in [-1.0, 1.0]:
			var i0 := b1 if sx > 0 else b0; var i1 := t1 if sx > 0 else t0; var i2 := t2 if sx > 0 else t3; var i3 := b2 if sx > 0 else b3
			m.quad(i0, i1, i2, i3, col.darkened(0.06), Vector3(sx, 0, 0))

	func _pantograph(m: _Mesh, zc: float, w: float, l: float, rig: TramModel.Rig, mi: MeshInstance3D, plain: Material) -> void:
		var steel := Color(0.3, 0.31, 0.33)
		var ins := Color(0.55, 0.32, 0.2)
		for sx in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				m.box(Vector3(sx * w * 0.32, h + 0.08, zc + sz * l * 0.38), Vector3(0.1, 0.16, 0.1), ins)
			m.box(Vector3(sx * w * 0.32, h + 0.2, zc), Vector3(0.08, 0.08, l), steel)
		m.box(Vector3(0, h + 0.2, zc + l * 0.38), Vector3(w * 0.64, 0.08, 0.1), steel)
		var pc: Dictionary = P.get("pantograph", {})
		var cfg := {"down": float(pc.get("down_m", 0.25)), "up": float(pc.get("up_m", 2.0)), "roof": h,
			"hinge": Vector2(h + 0.26, zc + l * 0.38)}
		var old := str(pc.get("type", "")) == "single_arm_old"
		cfg.l1 = 1.75 if not old else 1.6
		cfg.l2 = 1.65 if not old else 1.5
		cfg.head_z = zc + l * 0.38 - (float(cfg.l1) - float(cfg.l2))   # archet à l'aplomb du point de repli
		var dark := Color(0.2, 0.21, 0.22)
		# bras inférieur (cadre), bras supérieur, archet : maillages séparés, longueur unitaire le long de +Y
		var lower := _Mesh.new()
		for sx in [-1.0, 1.0]:
			lower.box(Vector3(sx * 0.22, 0.5, 0), Vector3(0.07, 1.0, 0.07), dark)
		lower.box(Vector3(0, 0.96, 0), Vector3(0.5, 0.06, 0.06), dark)
		var upper := _Mesh.new()
		upper.box(Vector3(0, 0.5, 0), Vector3(0.05, 1.0, 0.05), dark)
		var head := _Mesh.new()
		head.box(Vector3(0, 0.03, 0), Vector3(1.3, 0.05, 0.12), Color(0.12, 0.12, 0.12))
		for sx in [-1.0, 1.0]:
			head.box(Vector3(sx * 0.75, -0.03, 0), Vector3(0.25, 0.04, 0.08), Color(0.12, 0.12, 0.12))
		head.box(Vector3(0, -0.08, 0), Vector3(0.6, 0.06, 0.06), dark)
		var names := ["PantoLower", "PantoUpper", "PantoHead"]
		var nodes: Array = []
		var k := 0
		for pm in [lower, upper, head]:
			var node := MeshInstance3D.new(); node.name = names[k]; k += 1
			node.mesh = (pm as _Mesh).commit(); node.material_override = plain
			mi.add_child(node); nodes.append(node)
			rig.triangles += (pm as _Mesh).tris
		cfg.lower = nodes[0]; cfg.upper = nodes[1]; cfg.head = nodes[2]
		rig.panto = cfg

	## Vantaux d'une porte : maillages séparés (coordonnées du module, déplacés par Rig._apply).
	func _door(d: Dictionary, gz: float, rig: TramModel.Rig, mi: MeshInstance3D, mat: Material) -> int:
		var z0 := float(d.z0); var z1 := float(d.z1)
		var nl := clampi(int(d.leaves), 1, 2)
		var da: Dictionary = P.get("door_anim", {})
		var tris := 0
		var parts: Array = []
		if nl == 2:
			var zm := (z0 + z1) * 0.5
			parts = [[z0, zm, -1.0, float(da.get("travel_m", (z1 - z0) * 0.5))], [zm, z1, 1.0, float(da.get("travel_m", (z1 - z0) * 0.5))]]
		else:
			var dir := 1.0 if (z0 + z1) * 0.5 < 0.0 else -1.0
			parts = [[z0, z1, dir, float(da.get("single_leaf_travel_m", z1 - z0))]]
		var rows: Array = [floor_y]
		for y in levels:
			if float(y) > floor_y + 0.03 and float(y) < door_top - 0.03: rows.append(float(y))
		for y in [dglass_lo, dglass_hi]:
			rows.append(y)
		rows.append(door_top)
		rows.sort()
		var ry: Array = []
		for y in rows:
			if ry.is_empty() or float(y) - float(ry[-1]) > 0.02: ry.append(y)
		for side in [1.0, -1.0]:
			var x: float = side * (hw + (0.03 if str(da.get("type", "plug")) != "sliding" else 0.06))
			for pt in parts:
				var a := float(pt[0]) + 0.01; var b := float(pt[1]) - 0.01
				var lm := _Mesh.new()
				var fr := 0.07
				for r in range(ry.size() - 1):
					var y0 := float(ry[r]); var y1 := float(ry[r + 1]); var ym := (y0 + y1) * 0.5
					var c := surf(ym, (a + b) * 0.5 + gz, "door")
					if ym > dglass_lo and ym < dglass_hi:
						lm.quad(Vector3(x, y0, a), Vector3(x, y1, a), Vector3(x, y1, a + fr), Vector3(x, y0, a + fr), c, Vector3(side, 0, 0))
						lm.quad(Vector3(x, y0, a + fr), Vector3(x, y1, a + fr), Vector3(x, y1, b - fr), Vector3(x, y0, b - fr), glass(), Vector3(side, 0, 0))
						lm.quad(Vector3(x, y0, b - fr), Vector3(x, y1, b - fr), Vector3(x, y1, b), Vector3(x, y0, b), c, Vector3(side, 0, 0))
					else:
						lm.quad(Vector3(x, y0, a), Vector3(x, y1, a), Vector3(x, y1, b), Vector3(x, y0, b), c, Vector3(side, 0, 0))
				# chants
				var xi: float = x - side * 0.04
				var ec: Color = (L.door as Color).darkened(0.35)
				lm.quad(Vector3(x, floor_y, a), Vector3(x, door_top, a), Vector3(xi, door_top, a), Vector3(xi, floor_y, a), ec, Vector3(0, 0, -1))
				lm.quad(Vector3(x, floor_y, b), Vector3(x, door_top, b), Vector3(xi, door_top, b), Vector3(xi, floor_y, b), ec, Vector3(0, 0, 1))
				lm.quad(Vector3(x, door_top, a), Vector3(x, door_top, b), Vector3(xi, door_top, b), Vector3(xi, door_top, a), ec, Vector3.UP)
				# portes « berlingots » (T4) et décors sur les vantaux
				for el in L.elements:
					if str(el.get("pattern", "")) == "door_berlingots":
						var cols: Array = el.colors
						var ci := int(absf(gz + a) * 1.7) % cols.size()
						var yc := (dglass_lo + dglass_hi) * 0.5
						var pts: Array = []
						for q in 6:
							var ang := TAU * q / 6.0
							pts.append(Vector3(x + side * 0.006, yc + sin(ang) * 0.75, (a + b) * 0.5 + cos(ang) * (b - a) * 0.32))
						lm.poly(pts, cols[ci], Vector3(side, 0, 0))
				_emit_decals(lm, x + side * 0.006, side, gz, a, b, [[floor_y, door_top]], [[floor_y, dglass_lo], [dglass_hi, door_top]])
				var node := MeshInstance3D.new()
				node.name = "Leaf"
				node.mesh = lm.commit(); node.material_override = mat
				mi.add_child(node)
				tris += lm.tris
				var hinge_z := a if float(pt[2]) < 0.0 else b   # battant : charnière côté ouverture
				rig.leaves.append({"node": node, "side": side, "dir": float(pt[2]), "travel": float(pt[3]), "hinge": Vector3(x, 0, hinge_z)})
		return tris
