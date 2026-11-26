class_name StationShelters
extends RefCounted
## Abris de station par réseau (lot P4 « ambiance », docs/CDC_REFONTE_VISUELLE.md §6) : forme de toiture, porteurs,
## vitrages, banc, appui ischiatique, plan rétroéclairé, écran d'information (PID animé : prochains passages), distributeur,
## valideur, totem, bandeau LED, d'après data/station_shelters.json (silhouettes et teintes génériques, sans logo).
## La géométrie est ajoutée au `_Geo` du quai (mêmes maillage et matériau : aucun draw call de plus) ; seuls les textes
## (nom, PID) sont des Label3D bornés en distance. Repère local : x vers l'arrière du quai (0 = devant de l'abri), y haut,
## z le long de la voie.

const PATH := "res://data/station_shelters.json"
const GLASS := Color(0.62, 0.74, 0.80, 0.5)      # repli opaque (pbr_world : teinte unie) sans maillage de verre
const GLASS_T := Color(0.58, 0.70, 0.76, 0.26)   # verre feuilleté (maillage de verre transparent)
const LIT := 0.1                                   # alpha < 0,25 : lumineux (M_LIGHT)
const PID_RANGE := 45.0
const PID_RANGE_MOBILE := 22.0
const PID_PERIOD := 5.0

static var _doc: Dictionary = {}
## PID posés : {label (WeakRef), line, termini, seed} ; lampes des bandeaux LED (repère de la vue) pour NightLights.
static var boards: Array = []
static var lights := PackedVector3Array()
static var stats := {"shelters": 0, "pids": 0}
static var _t := 0.0

static func doc() -> Dictionary:
	if _doc.is_empty():
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH)) if FileAccess.file_exists(PATH) else null
		_doc = d if d is Dictionary else {"default": {}, "networks": {}}
	return _doc

## Style d'abri d'un réseau (source_id) : valeurs par défaut complétées par celles du réseau.
static func style(network: String) -> Dictionary:
	var d := doc()
	var st: Dictionary = (d.get("default", {}) as Dictionary).duplicate(true)
	st.merge(d.get("networks", {}).get(network, {}), true)
	st["network"] = network if d.get("networks", {}).has(network) else "default"
	return st

static func reset() -> void:
	boards.clear(); lights.clear(); stats = {"shelters": 0, "pids": 0}

static func _c(v: Variant, a := 1.0) -> Color:
	var c := Color(str(v)); c.a = a; return c

## Repère d'un texte (Label3D) lisible depuis `toward` (normale horizontale vers le lecteur), jamais en miroir.
static func facing(toward: Vector3) -> Basis:
	var zf := Vector3(toward.x, 0.0, toward.z).normalized()
	return Basis(Vector3.UP.cross(zf), Vector3.UP, zf)

# ------------------------------------------------------------------------------------------- géométrie

static var _glass_mat: StandardMaterial3D = null
## Verre des abris (un matériau transparent partagé : un draw call par quai).
static func glass_material() -> StandardMaterial3D:
	if _glass_mat == null:
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true; m.vertex_color_is_srgb = true
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA; m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.roughness = 0.06; m.metallic = 0.1; m.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
		_glass_mat = m
	return _glass_mat

class _F:
	var g
	var gg       # maillage de verre (null : repli opaque dans g)
	func glass(a: Vector3, bb: Vector3, c: Vector3, d: Vector3) -> void:
		if gg != null: gg.quad(p(a.x, a.y, a.z), p(bb.x, bb.y, bb.z), p(c.x, c.y, c.z), p(d.x, d.y, d.z), StationShelters.GLASS_T)
		else: quad(a, bb, c, d, StationShelters.GLASS)
	var o: Vector3
	var x: Vector3
	var z: Vector3
	var b: Basis
	func p(px: float, py: float, pz: float) -> Vector3: return o + x * px + Vector3.UP * py + z * pz
	func box(px: float, py: float, pz: float, s: Vector3, col: Color) -> void: g.box_basis(p(px, py, pz), s, b, col)
	func quad(a: Vector3, bb: Vector3, c: Vector3, d: Vector3, col: Color) -> void: g.quad(p(a.x, a.y, a.z), p(bb.x, bb.y, bb.z), p(c.x, c.y, c.z), p(d.x, d.y, d.z), col)
	## tube vertical à 8 pans (poteau)
	func post(px: float, pz: float, y0: float, y1: float, r: float, col: Color) -> void:
		for j in 8:
			var a := TAU * j / 8.0; var c := TAU * (j + 1) / 8.0
			var u := Vector3(px + cos(a) * r, y0, pz + sin(a) * r); var v := Vector3(px + cos(c) * r, y0, pz + sin(c) * r)
			quad(u, v, v + Vector3(0, y1 - y0, 0), u + Vector3(0, y1 - y0, 0), col)
	## poutre entre deux points locaux (section carrée)
	func beam(a: Vector3, c: Vector3, w: float, col: Color) -> void:
		var pa := p(a.x, a.y, a.z); var pc := p(c.x, c.y, c.z)
		if pa.distance_to(pc) < 0.01: return
		var dir := (pc - pa).normalized()
		var bb := Basis.looking_at(dir, Vector3.FORWARD if absf(dir.dot(Vector3.UP)) > 0.98 else Vector3.UP)
		g.box_basis((pa + pc) * 0.5, Vector3(w, w, pa.distance_to(pc)), bb, col)

## Abri complet. `origin` : devant de l'abri au niveau du quai (milieu en longueur) ; `back` : horizontale vers l'arrière
## du quai ; `along` : le long de la voie. Retourne le nombre d'éléments posés.
static func build(owner: Node3D, g, origin: Vector3, back: Vector3, along: Vector3, st: Dictionary, station_name: String,
		line_label: String = "", termini: Array = [], max_depth: float = 99.0, glass_geo = null) -> int:
	var f := _F.new(); f.g = g; f.gg = glass_geo; f.o = origin; f.x = back.normalized(); f.z = along.normalized()
	f.b = Basis(f.x, Vector3.UP, f.z)
	var L := float(st.get("length", 6.6)); var D := minf(float(st.get("depth", 1.6)), max_depth); var H := float(st.get("height", 2.55))
	var frame := _c(st.get("frame", "#4f575c")); var roofc := _c(st.get("roof_color", "#5d646b"))
	var accent := _c(st.get("accent", "#6c7a80"))
	var glass_roof := bool(st.get("glass_roof", false))
	var roof_col := roofc
	var hl := L * 0.5
	var n := 0
	# --- porteurs
	match str(st.get("supports", "rear")):
		"two_rows":
			for zz in [-hl + 0.35, hl - 0.35]:
				for xx in [0.18, D - 0.12]: f.post(xx, zz, 0.0, H, 0.05, frame)
				f.beam(Vector3(0.18, H - 0.06, zz), Vector3(D - 0.12, H - 0.06, zz), 0.08, frame)
		"mast":
			for zz in ([-L * 0.25, L * 0.25] if L > 6.0 else [0.0]):
				f.post(D * 0.5, zz, 0.0, H, 0.085, frame)
				f.box(D * 0.5, 0.04, zz, Vector3(0.36, 0.08, 0.36), frame)   # platine
				for s in [-1.0, 1.0]: f.beam(Vector3(D * 0.5, H - 0.55, zz), Vector3(D * 0.5 + s * D * 0.48, H - 0.02, zz), 0.06, frame)
		_:
			var zs := [-hl + 0.4, hl - 0.4]
			if L > 7.4: zs.append(0.0)
			for zz in zs:
				f.post(D - 0.1, zz, 0.0, H, 0.055, frame)
				f.box(D - 0.1, 0.03, zz, Vector3(0.22, 0.06, 0.22), frame)
				f.beam(Vector3(D - 0.1, H - 0.45, zz), Vector3(0.05, H - 0.05, zz), 0.06, frame)   # console
	# --- toiture
	var roof_kind := str(st.get("roof", "flat"))
	var top := H
	match roof_kind:
		"mono":
			var yf := H + 0.28; var yb := H - 0.05
			if glass_roof: f.glass(Vector3(-0.2, yf, -hl), Vector3(-0.2, yf, hl), Vector3(D + 0.1, yb, hl), Vector3(D + 0.1, yb, -hl))
			else: f.quad(Vector3(-0.2, yf, -hl), Vector3(-0.2, yf, hl), Vector3(D + 0.1, yb, hl), Vector3(D + 0.1, yb, -hl), roof_col)
			for zz in range(0, int(L / 1.2) + 1):
				var z := -hl + zz * L / maxf(1.0, floorf(L / 1.2))
				f.beam(Vector3(-0.2, yf - 0.03, z), Vector3(D + 0.1, yb - 0.03, z), 0.05, frame)
			f.beam(Vector3(-0.2, yf - 0.03, -hl), Vector3(-0.2, yf - 0.03, hl), 0.08, frame)
			f.beam(Vector3(D + 0.1, yb - 0.03, -hl), Vector3(D + 0.1, yb - 0.03, hl), 0.08, frame)
			top = yf
		"curved", "wing":
			var segs := 8
			var prev := Vector3.ZERO
			for i in segs + 1:
				var u := float(i) / segs
				var xx := lerpf(-0.18, D + 0.12, u)
				var yy := H + (0.32 * sin(PI * u) if roof_kind == "curved" else 0.42 * absf(u - 0.5) * 2.0)
				var cur := Vector3(xx, yy, 0)
				if i > 0:
					if glass_roof: f.glass(Vector3(prev.x, prev.y, -hl), Vector3(prev.x, prev.y, hl), Vector3(cur.x, cur.y, hl), Vector3(cur.x, cur.y, -hl))
					else: f.quad(Vector3(prev.x, prev.y, -hl), Vector3(prev.x, prev.y, hl), Vector3(cur.x, cur.y, hl), Vector3(cur.x, cur.y, -hl), roof_col)
					for zz in [-hl, -hl * 0.33, hl * 0.33, hl]:
						f.beam(Vector3(prev.x, prev.y - 0.03, zz), Vector3(cur.x, cur.y - 0.03, zz), 0.05, frame)
				prev = cur
			for xx in [-0.18, D + 0.12]:
				f.beam(Vector3(xx, H - 0.02 + (0.42 if roof_kind == "wing" else 0.0), -hl), Vector3(xx, H - 0.02 + (0.42 if roof_kind == "wing" else 0.0), hl), 0.07, frame)
			if roof_kind == "wing": f.beam(Vector3(D * 0.5, H - 0.04, -hl), Vector3(D * 0.5, H - 0.04, hl), 0.1, frame)
			top = H + 0.4
		"wave":
			var segs := maxi(8, int(L / 0.6))
			for i in segs:
				var z0 := -hl + L * i / segs; var z1 := -hl + L * (i + 1) / segs
				var y0 := H + 0.2 * sin(z0 / L * TAU * 1.5); var y1 := H + 0.2 * sin(z1 / L * TAU * 1.5)
				f.quad(Vector3(-0.25, y0 + 0.12, z0), Vector3(-0.25, y1 + 0.12, z1), Vector3(D + 0.15, y1, z1), Vector3(D + 0.15, y0, z0), roof_col)
				f.quad(Vector3(-0.25, y0 + 0.12, z0), Vector3(-0.25, y0 + 0.04, z0), Vector3(-0.25, y1 + 0.04, z1), Vector3(-0.25, y1 + 0.12, z1), frame)
			top = H + 0.35
		"disk":
			var r := D * 0.5 + 0.2; var cx := D * 0.5; var th := 0.12
			var ring: Array = []
			for side in [-1.0, 1.0]:
				for k in 9:
					var a := PI * k / 8.0
					ring.append(Vector3(cx + cos(a) * r * side, 0, side * (hl - r * 0.6) + sin(a) * r * side))
			for i in ring.size():
				var a: Vector3 = ring[i]; var c: Vector3 = ring[(i + 1) % ring.size()]
				f.quad(Vector3(cx, H + th, 0), Vector3(a.x, H + th, a.z), Vector3(c.x, H + th, c.z), Vector3(cx, H + th, 0), roofc)
				f.quad(Vector3(a.x, H, a.z), Vector3(c.x, H, c.z), Vector3(c.x, H + th, c.z), Vector3(a.x, H + th, a.z), roofc.darkened(0.1))
				f.quad(Vector3(cx, H, 0), Vector3(c.x, H, c.z), Vector3(a.x, H, a.z), Vector3(cx, H, 0), roofc.darkened(0.25))
			top = H + th
		_:   # flat : dalle mince et bandeau
			if glass_roof:
				f.glass(Vector3(-0.15, H + 0.08, -hl), Vector3(-0.15, H + 0.08, hl), Vector3(D + 0.15, H + 0.08, hl), Vector3(D + 0.15, H + 0.08, -hl))
				f.box(D * 0.5, H + 0.03, -hl, Vector3(D + 0.3, 0.1, 0.08), frame); f.box(D * 0.5, H + 0.03, hl, Vector3(D + 0.3, 0.1, 0.08), frame)
				f.box(D + 0.12, H + 0.03, 0.0, Vector3(0.08, 0.1, L), frame)
			else: f.box(D * 0.5, H + 0.05, 0.0, Vector3(D + 0.3, 0.1, L), roof_col)
			if glass_roof:
				for zz in range(0, int(L / 1.3) + 1):
					f.box(D * 0.5, H, -hl + zz * L / maxf(1.0, floorf(L / 1.3)), Vector3(D + 0.3, 0.07, 0.05), frame)
			f.box(-0.13, H + 0.02, 0.0, Vector3(0.05, 0.26, L), frame)
			top = H + 0.1
	# bandeau de couleur du réseau (ou traits colorés) sous la rive avant
	var strokes: Array = st.get("fascia_strokes", [])
	if strokes.is_empty(): f.box(-0.1, H - 0.12, 0.0, Vector3(0.03, 0.06, L * 0.9), accent)
	else:
		for j in strokes.size(): f.box(-0.1, H - 0.2, hl * 0.72 - j * 0.1, Vector3(0.035, 0.16, 0.055), _c(strokes[j]))
	# bandeau LED sous la toiture (lumineux la nuit) + source de lumière dynamique
	f.box(D * 0.45, H - 0.08, 0.0, Vector3(0.07, 0.025, L * 0.75), _c(st.get("led", "#ffe3b8"), LIT))
	lights.append(f.p(D * 0.45, H - 0.1, 0.0))
	n += 2
	# --- vitrages : fond et joues
	if bool(st.get("rear_glass", true)):
		var xb := D - 0.03
		f.glass(Vector3(xb, 0.18, -hl + 0.3), Vector3(xb, 0.18, hl - 0.3), Vector3(xb, H - 0.18, hl - 0.3), Vector3(xb, H - 0.18, -hl + 0.3))
		f.box(xb, 0.16, 0.0, Vector3(0.05, 0.05, L - 0.6), frame); f.box(xb, H - 0.16, 0.0, Vector3(0.05, 0.05, L - 0.6), frame)
		var bays := maxi(2, int(L / 1.45))
		for i in bays + 1: f.box(xb, H * 0.5, -hl + 0.3 + (L - 0.6) * i / bays, Vector3(0.05, H - 0.3, 0.04), frame)
		# plan du réseau rétroéclairé et affiche horaire dans le fond
		f.box(xb - 0.03, 1.35, -hl + 0.95, Vector3(0.04, 1.15, 0.85), _c("#e9ebe3", LIT))
		f.box(xb - 0.035, 1.35, -hl + 0.95, Vector3(0.035, 1.21, 0.91), frame)
		n += 2
	if bool(st.get("side_glass", true)):
		for zz in [-hl + 0.28, hl - 0.28]:
			f.glass(Vector3(D * 0.35, 0.18, zz), Vector3(D - 0.05, 0.18, zz), Vector3(D - 0.05, H - 0.18, zz), Vector3(D * 0.35, H - 0.18, zz))
			f.box(D * 0.35, H * 0.5, zz, Vector3(0.04, H - 0.3, 0.04), frame)
	# --- assise
	var bz := hl * 0.15
	if str(st.get("bench", "metal")) == "wood":
		for i in 4: f.box(D - 0.5 + i * 0.1, 0.46, bz, Vector3(0.075, 0.04, 2.2), _c("#9a7a58"))
		for i in 3: f.box(D - 0.12, 0.62 + i * 0.1, bz, Vector3(0.04, 0.075, 2.2), _c("#9a7a58"))
	else:
		f.box(D - 0.35, 0.46, bz, Vector3(0.42, 0.04, 2.2), _c("#7d868b"))
		f.box(D - 0.12, 0.72, bz, Vector3(0.03, 0.42, 2.2), _c("#7d868b"))
	for s in [-1.0, 1.0]: f.box(D - 0.33, 0.22, bz + s * 0.95, Vector3(0.36, 0.44, 0.05), frame)
	if bool(st.get("lean_bar", true)):
		f.beam(Vector3(D - 0.2, 0.76, -hl + 0.7), Vector3(D - 0.2, 0.76, -hl + 2.1), 0.06, frame)
		for zz in [-hl + 0.75, -hl + 2.05]: f.post(D - 0.2, zz, 0.0, 0.76, 0.025, frame)
	n += 2
	# --- mobilier de quai hors abri : distributeur, valideur, totem, mât lumineux
	if bool(st.get("tvm", true)):
		f.box(D - 0.45, 0.82, hl + 0.9, Vector3(0.5, 1.64, 0.6), _c("#3d4a57"))
		f.box(D - 0.71, 1.25, hl + 0.9, Vector3(0.02, 0.32, 0.4), _c("#9fc6d8", LIT))   # écran tactile
		f.box(D - 0.71, 1.62, hl + 0.9, Vector3(0.025, 0.06, 0.58), accent)
		n += 1
	if bool(st.get("validator", true)):
		f.post(D - 0.5, hl + 1.9, 0.0, 1.05, 0.05, frame)
		f.box(D - 0.5, 1.15, hl + 1.9, Vector3(0.16, 0.22, 0.14), _c("#2b3134"))
		f.box(D - 0.585, 1.17, hl + 1.9, Vector3(0.01, 0.08, 0.1), _c("#62d39a", LIT))
		n += 1
	f.box(D - 0.25, 1.35, -hl - 1.2, Vector3(0.3, 2.7, 0.5), accent)                  # totem
	f.box(D - 0.25, 2.55, -hl - 1.2, Vector3(0.32, 0.22, 0.52), _c("#f3f2ea", LIT))  # caisson lumineux
	if bool(st.get("light_mast", false)):
		f.post(D - 0.1, -hl - 2.6, 0.0, 6.5, 0.07, frame)
		f.box(D - 0.1, 6.3, -hl - 2.6, Vector3(0.18, 0.5, 0.18), _c("#fff1d6", LIT))
		lights.append(f.p(D - 0.1, 6.2, -hl - 2.6))
	n += 1
	# --- écran PID (prochains passages) suspendu sous la toiture, vu le long du quai
	if bool(st.get("pid", true)):
		var pz := hl * 0.55
		f.post(0.55, pz, H - 0.45, H, 0.015, frame)
		f.box(0.55, H - 0.62, pz, Vector3(0.95, 0.34, 0.08), _c("#1b1f22"))
		f.box(0.55, H - 0.62, pz - 0.042, Vector3(0.88, 0.27, 0.005), _c("#101418", LIT))
		_pid(owner, f.p(0.55, H - 0.62, pz - 0.05), facing(-f.z), line_label, termini, station_name)
		n += 1
	_sign(owner, station_name, f, H - 0.33 if roof_kind != "disk" else H - 0.12, minf(L * 0.55, 3.4))
	stats.shelters += 1
	return n

## Plaque du nom de la station sous la rive avant (face à la voie).
static func _sign(owner: Node3D, text_: String, f: _F, y: float, w: float) -> void:
	if text_ == "": return
	f.box(-0.19, y, 0.0, Vector3(0.03, 0.2, w), _c("#20272a"))
	var basis := facing(-f.x); var at := f.p(-0.212, y, 0.0)
	var lbl := Label3D.new(); lbl.text = text_
	lbl.font_size = 48; lbl.pixel_size = minf(0.0035, w / maxf(48.0 * text_.length() * 0.62, 1.0))
	lbl.modulate = Color("#f2f1e8"); lbl.outline_size = 0; lbl.no_depth_test = false; lbl.double_sided = false
	lbl.basis = basis; lbl.position = at
	lbl.visibility_range_end = 70.0 if not DayNight.low_quality else 35.0
	lbl.name = "shelter_sign"
	owner.add_child(lbl)

static func _pid(owner: Node3D, at: Vector3, basis: Basis, line_label: String, termini: Array, station_name: String) -> void:
	var lbl := Label3D.new()
	lbl.name = "pid"
	lbl.font_size = 40; lbl.pixel_size = 0.0019
	lbl.modulate = Color(1.0, 0.72, 0.25); lbl.outline_size = 0
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT; lbl.width = 440.0; lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
	lbl.basis = basis; lbl.position = at
	lbl.visibility_range_end = PID_RANGE_MOBILE if DayNight.low_quality else PID_RANGE
	lbl.shaded = false; lbl.double_sided = false
	owner.add_child(lbl)
	var seed := absi(hash(station_name)) % 600
	boards.append({"label": weakref(lbl), "line": line_label, "termini": termini, "seed": seed})
	lbl.text = pid_text(line_label, termini, 12.0, seed)
	stats.pids += 1

## Texte du PID : deux prochains passages par direction (intervalle selon l'heure, décalage stable par station).
static func pid_text(line_label: String, termini: Array, hour: float, seed: int) -> String:
	var headway := 5.0 if (hour >= 7.0 and hour < 9.5) or (hour >= 16.5 and hour < 19.5) else (8.0 if hour >= 6.0 and hour < 21.0 else 15.0)
	var minute := hour * 60.0 + seed * 0.37
	var rows: Array = []
	var dests: Array = termini if not termini.is_empty() else ["Terminus"]
	for i in mini(dests.size(), 2):
		var wait := headway - fposmod(minute + i * headway * 0.45, headway)
		var nxt := int(floor(wait))
		var first := "à quai" if nxt <= 0 else "%d min" % nxt
		var dest := str(dests[i])
		if dest.length() > 18: dest = dest.substr(0, 17) + "."
		rows.append("%s  %-18s %6s  %2d min" % [line_label if line_label != "" else "T", dest, first, nxt + int(headway)])
	return "\n".join(rows)

## Mise à jour des PID proches (appel par image, réel toutes les PID_PERIOD s) ; renvoie le nombre de PID rafraîchis.
static func update_boards(cam_pos: Vector3, hour: float, dt: float) -> int:
	_t -= dt
	if _t > 0.0: return 0
	_t = PID_PERIOD
	var keep: Array = []; var n := 0
	for b in boards:
		var l = (b.label as WeakRef).get_ref()
		if l == null: continue
		keep.append(b)
		var lbl := l as Label3D
		if not lbl.is_inside_tree() or lbl.global_position.distance_to(cam_pos) > PID_RANGE + 10.0: continue
		lbl.text = pid_text(str(b.line), b.termini, hour, int(b.seed))
		n += 1
	boards = keep
	return n
