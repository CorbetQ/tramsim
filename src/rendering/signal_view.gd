class_name SignalView
extends RefCounted
## Signaux tramway en 3D au bord de la voie (SignalModel), lot P4 « ambiance » : feux **R17** à trois modules
## superposés sur mât tubulaire (embase, panneau de contraste noir à liseré, visières, lentilles éteintes en verre
## fumé, plaque d'identification) — module haut : barre verticale « voie libre » (oblique pour une direction), module
## central : point « arrêt sauf impossibilité », module bas : barre horizontale « arrêt ». Le symbole allumé est blanc
## lunaire émissif (bloom de nuit), les autres restent éteints : l'aspect affiché suit toujours `SignalModel.aspect`.
## Carré de terminus : tête sur panneau blanc ; signal de canton : plaque blanche ; heurtoir : butoir à bandes rouges et
## blanches et feu rouge. Placés à droite de la voie dans le sens de circulation, rattachés aux secteurs de voie (masqués
## avec eux) ; aspects mis à jour près de la caméra seulement. Corps d'un signal = un seul maillage partagé par type.
## Feux routiers de carrefour (R11v tricolores à visières, `road_light`) pilotés par la circulation (LineView).

const UPDATE_R := 420.0
const UPDATE_S := 0.2
const SIDE_M := 2.15
const MOD := 0.34            # pas vertical des modules R17
const LUNAR := Color(1.0, 0.96, 0.82)

var model: SignalModel
var heads: Array = []   # [indice, nœud, barre haute, point, barre basse, position, aspect affiché]
var _t := 0.0
static var _mats: Dictionary = {}
static var _meshes: Dictionary = {}

static func _lit(name: String, col: Color, energy: float = 2.6) -> Material:
	if _mats.has(name): return _mats[name]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color.BLACK; m.roughness = 0.3
	m.emission_enabled = true; m.emission = col; m.emission_energy_multiplier = energy
	_mats[name] = m
	return m

static func _shape(key: String, build: Callable) -> Mesh:
	if not _meshes.has(key): _meshes[key] = build.call()
	return _meshes[key]

static func _symbol(parent: Node3D, mesh: Mesh, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh; mi.material_override = mat; mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visible = false
	parent.add_child(mi)
	return mi

## Disque (lentille, point) dans le plan XY, face vers -Z.
static func _disk(g, ctr: Vector3, r: float, col: Color, sides := 14) -> void:
	for j in sides:
		var a := TAU * j / sides; var b := TAU * (j + 1) / sides
		g.tri(ctr, ctr + Vector3(cos(b) * r, sin(b) * r, 0), ctr + Vector3(cos(a) * r, sin(a) * r, 0), col)

## Visière (demi-tube ouvert vers le bas) autour d'une lentille, face vers -Z.
static func _visor(g, ctr: Vector3, r: float, depth: float, col: Color) -> void:
	for j in 7:
		var a := PI * j / 7.0; var b := PI * (j + 1) / 7.0
		var p := ctr + Vector3(cos(a) * r, sin(a) * r, 0); var q := ctr + Vector3(cos(b) * r, sin(b) * r, 0)
		g.quad(p, q, q + Vector3(0, 0, -depth), p + Vector3(0, 0, -depth), col)

## Mât tubulaire à 8 pans.
static func _mast(g, h: float, r: float, col: Color) -> void:
	for j in 8:
		var a := TAU * j / 8.0; var b := TAU * (j + 1) / 8.0
		var p := Vector3(cos(a) * r, 0, sin(a) * r); var q := Vector3(cos(b) * r, 0, sin(b) * r)
		g.quad(p, q, q + Vector3(0, h, 0), p + Vector3(0, h, 0), col)
	g.box(Vector3(0, 0.03, 0), Vector3(0.34, 0.06, 0.34), col.darkened(0.2))   # embase
	g.box(Vector3(0, 0.2, 0.0), Vector3(r * 2.6, 0.12, r * 2.6), col.darkened(0.1))

## Corps d'un feu R17 (mât, panneau, trois modules, visières, lentilles éteintes, plaque) : y = centre du module central.
static func r17_body(kind: String) -> Mesh:
	return _shape("r17_" + kind, func():
		var g := LineView._Geo.new()
		var metal := Color("#5d646b"); var black := Color(0.08, 0.09, 0.1, 0.41); var lens := Color(0.06, 0.07, 0.075, 0.5)
		var h := 2.75 if kind != "crossing" else 2.45
		var y := h + 0.5
		_mast(g, h + 0.2, 0.055, metal)
		if kind == "terminus": g.box(Vector3(0, y, 0.09), Vector3(0.82, 1.32, 0.04), Color("#f2f2ee"))
		if kind == "block": g.box(Vector3(0, y - 0.78, -0.02), Vector3(0.5, 0.18, 0.04), Color("#f2f2ee"))
		# panneau de contraste noir à liseré blanc
		g.box(Vector3(0, y, 0.06), Vector3(0.62, 1.2, 0.03), Color("#f2f2ee"))
		g.box(Vector3(0, y, 0.045), Vector3(0.56, 1.14, 0.03), black)
		for k in 3:
			var my := y + (1 - k) * MOD
			g.box(Vector3(0, my, -0.02), Vector3(0.3, 0.3, 0.16), black)            # module
			_disk(g, Vector3(0, my, -0.101), 0.12, lens)                           # lentille éteinte
			_visor(g, Vector3(0, my, -0.1), 0.135, 0.16, black)                    # visière
		g.box(Vector3(0, y - 0.88, -0.05), Vector3(0.22, 0.12, 0.02), Color("#f2f2ee"))   # plaque d'identification
		g.box(Vector3(0, y - 0.88, -0.061), Vector3(0.16, 0.035, 0.002), Color("#1b1d1f"))
		g.box(Vector3(0, y + 0.62, 0.0), Vector3(0.36, 0.05, 0.22), black)         # chapeau
		return g.mesh())

static func buffer_body() -> Mesh:
	return _shape("buffer", func():
		var g := LineView._Geo.new()
		var metal := Color("#4b5156")
		for s in [-0.55, 0.55]:
			g.box(Vector3(s, 0.5, 0.0), Vector3(0.14, 1.0, 0.14), metal)
			g.box(Vector3(s, 0.45, 0.45), Vector3(0.12, 0.12, 0.95), metal)   # jambe de force
		for k in 6:
			g.box(Vector3(-0.75 + 0.25 * k + 0.125, 1.0, -0.08), Vector3(0.25, 0.36, 0.05), Color("#c8202a") if k % 2 == 0 else Color("#f2f2ee"))
		g.box(Vector3(0, 0.62, -0.12), Vector3(1.4, 0.22, 0.12), Color("#2a2d30"))   # tampon
		g.box(Vector3(0, 1.4, 0.0), Vector3(0.05, 0.6, 0.05), metal)
		g.box(Vector3(0, 1.72, -0.02), Vector3(0.2, 0.2, 0.12), Color(0.08, 0.09, 0.1, 0.41))
		return g.mesh())

func build(view: LineView, m: SignalModel) -> void:
	model = m
	var lunar := _lit("lunar", LUNAR, 2.8)
	var red := _lit("buffer_red", Color(1.0, 0.12, 0.08), 2.2)
	var bar := _shape("bar", func(): var b := BoxMesh.new(); b.size = Vector3(0.05, 0.2, 0.012); return b)
	var dot := _shape("dot", func(): var c := CylinderMesh.new(); c.top_radius = 0.055; c.bottom_radius = 0.055; c.height = 0.012; c.radial_segments = 12; c.rings = 1; return c)
	var world := Materials.building()
	for i in m.list.size():
		var s: Dictionary = m.list[i]
		if not view.sectors.has(s.edge): continue
		var t := view._frame(str(s.edge), float(s.offset))
		var fwd := -t.basis.z * float(s.dir)
		fwd.y = 0.0
		if fwd.length() < 0.01: continue
		fwd = fwd.normalized()
		var right := fwd.cross(Vector3.UP).normalized()
		var root := Node3D.new()
		root.name = "signal_%d" % i
		root.transform = Transform3D(Basis.looking_at(-fwd, Vector3.UP), t.origin + right * SIDE_M)
		view.sectors[s.edge].add_child(root)
		var kind := str(s.kind)
		var body := MeshInstance3D.new(); body.name = "body"
		body.mesh = buffer_body() if kind == "buffer" else r17_body(kind)
		body.material_override = world
		body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(body)
		if kind == "buffer":
			var lamp := _symbol(root, dot, Vector3(0, 1.72, -0.085), red)
			lamp.rotation = Vector3(PI * 0.5, 0, 0); lamp.visible = true
			continue
		var y := (2.75 if kind != "crossing" else 2.45) + 0.5
		var top := _symbol(root, bar, Vector3(0, y + MOD, -0.104), lunar)
		var mid := _symbol(root, dot, Vector3(0, y, -0.104), lunar); mid.rotation = Vector3(PI * 0.5, 0, 0)
		var low := _symbol(root, bar, Vector3(0, y - MOD, -0.104), lunar); low.rotation = Vector3(0, 0, PI * 0.5)
		heads.append([i, root, top, mid, low, t.origin, ""])
	update(Vector3.ZERO, true)

## Symboles allumés pour un aspect : [barre haute visible, rotation de la barre haute, point, barre basse].
static func symbols(a: String) -> Array:
	match a:
		"go": return [true, 0.0, false, false]
		"left": return [true, -PI * 0.25, false, false]
		"right": return [true, PI * 0.25, false, false]
		"caution": return [false, 0.0, true, false]
	return [false, 0.0, false, true]

## Aspects des signaux proches de `center` (appel par image ; mise à jour toutes les UPDATE_S).
func update(center: Vector3, force: bool = false, dt: float = 0.0) -> void:
	_t -= dt
	if _t > 0.0 and not force: return
	_t = UPDATE_S
	for h in heads:
		if not force and ((h[5] as Vector3).distance_to(center) > UPDATE_R or not (h[1] as Node3D).is_visible_in_tree()): continue
		var a := model.aspect(int(h[0]))
		if a == str(h[6]): continue
		h[6] = a
		var sy := symbols(a)
		var top: MeshInstance3D = h[2]
		# Repère local : +X à gauche du conducteur ; rotation positive = sommet vers sa droite.
		top.visible = sy[0]; top.rotation = Vector3(0.0, 0.0, float(sy[1]))
		(h[3] as MeshInstance3D).visible = sy[2]
		(h[4] as MeshInstance3D).visible = sy[3]

# ------------------------------------------------------------------------------------------- feux routiers

static func r11_body() -> Mesh:
	return _shape("r11", func():
		var g := LineView._Geo.new()
		var metal := Color("#5d646b"); var black := Color(0.08, 0.09, 0.1, 0.41); var lens := Color(0.06, 0.07, 0.075, 0.5)
		_mast(g, 3.2, 0.06, metal)
		g.box(Vector3(0, 2.75, 0.03), Vector3(0.5, 1.1, 0.03), Color("#f2f2ee"))   # panneau de contraste à liseré
		g.box(Vector3(0, 2.75, 0.015), Vector3(0.44, 1.04, 0.03), black)
		g.box(Vector3(0, 2.75, -0.08), Vector3(0.3, 0.98, 0.2), black)
		for k in 3:
			var my := 2.75 + (1 - k) * 0.3
			_disk(g, Vector3(0, my, -0.181), 0.105, lens)
			_visor(g, Vector3(0, my, -0.18), 0.12, 0.18, black)
		g.box(Vector3(0, 1.1, -0.06), Vector3(0.14, 0.2, 0.08), Color("#d8d24a"))   # boîtier d'appel piéton
		return g.mesh())

## Feu tricolore de carrefour à la transformation `xf` (face vers -Z local) : {root, red, amber, green}.
static func road_light(parent: Node3D, xf: Transform3D) -> Dictionary:
	var root := Node3D.new(); root.name = "road_light"; root.transform = xf
	parent.add_child(root)
	var body := MeshInstance3D.new(); body.mesh = r11_body(); body.material_override = Materials.building()
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; root.add_child(body)
	var lens := _shape("road_lens", func(): var c := CylinderMesh.new(); c.top_radius = 0.1; c.bottom_radius = 0.1; c.height = 0.01; c.radial_segments = 14; c.rings = 1; return c)
	var out := {"root": root}
	var cols := {"red": Color(1.0, 0.1, 0.06), "amber": Color(1.0, 0.55, 0.05), "green": Color(0.1, 1.0, 0.45)}
	var k := 0
	for n in ["red", "amber", "green"]:
		var mi := _symbol(root, lens, Vector3(0, 2.75 + (1 - k) * 0.3, -0.184), _lit("road_" + n, cols[n], 2.4))
		mi.rotation = Vector3(PI * 0.5, 0, 0)
		out[n] = mi; k += 1
	set_road_light(out, false)
	return out

## État du feu : rouge, sinon vert (orange 3 s après un passage au rouge demandé : `amber`).
static func set_road_light(l: Dictionary, red: bool, amber := false) -> void:
	(l.red as MeshInstance3D).visible = red and not amber
	(l.amber as MeshInstance3D).visible = amber
	(l.green as MeshInstance3D).visible = not red and not amber
