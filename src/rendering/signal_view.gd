class_name SignalView
extends RefCounted
## Signaux tramway en 3D au bord de la voie (SignalModel) : mât, tête noire, feux lunaires
## en barre (verticale : voie libre, horizontale : arrêt, oblique : direction) et point
## (arrêt sauf impossibilité). Carré de terminus : tête sur panneau blanc ; heurtoir :
## panneau rouge et blanc. Placés à droite de la voie dans le sens de circulation, rattachés
## aux secteurs de voie (masqués avec eux) ; aspects mis à jour près de la caméra seulement.

const UPDATE_R := 420.0
const UPDATE_S := 0.2
const SIDE_M := 2.15

var model: SignalModel
var heads: Array = []   # [indice, nœud, barre, point, position, aspect affiché]
var _t := 0.0
static var _mats: Dictionary = {}
static var _meshes: Dictionary = {}

static func _mat(name: String, col: Color, lit: bool) -> Material:
	if _mats.has(name): return _mats[name]
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	if lit: m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	else: m.roughness = 0.8
	_mats[name] = m
	return m

static func _box(size: Vector3) -> BoxMesh:
	var k := str(size)
	if _meshes.has(k): return _meshes[k]
	var b := BoxMesh.new(); b.size = size
	_meshes[k] = b
	return b

static func _part(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _box(size); mi.material_override = mat; mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi

func build(view: LineView, m: SignalModel) -> void:
	model = m
	var dark := _mat("head", Color("#15181b"), false)
	var metal := _mat("post", Color("#5d646b"), false)
	var white := _mat("plate", Color("#f2f2ee"), false)
	var red := _mat("red", Color("#c8202a"), false)
	var lamp := _mat("lamp", Color(1.0, 0.96, 0.82), true)
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
		if kind == "buffer":
			_part(root, Vector3(0.1, 1.0, 0.1), Vector3(0.0, 0.5, 0.0), metal)
			for k in 4:
				_part(root, Vector3(0.3, 0.32, 0.04), Vector3(-0.45 + 0.3 * k, 1.05, -0.06), red if k % 2 == 0 else white)
			continue
		var h := 2.75 if kind != "crossing" else 2.45
		_part(root, Vector3(0.12, h, 0.12), Vector3(0.0, h * 0.5, 0.0), metal)
		var head_y := h + 0.5
		if kind == "terminus": _part(root, Vector3(0.78, 1.18, 0.05), Vector3(0.0, head_y, 0.08), white)
		if kind == "block": _part(root, Vector3(0.5, 0.18, 0.05), Vector3(0.0, head_y - 0.72, -0.02), white)
		_part(root, Vector3(0.52, 0.95, 0.22), Vector3(0.0, head_y, 0.0), dark)
		_part(root, Vector3(0.6, 0.06, 0.32), Vector3(0.0, head_y + 0.5, -0.04), dark)   # visière
		var bar := _part(root, Vector3(0.08, 0.52, 0.03), Vector3(0.0, head_y + 0.08, -0.12), lamp)
		var dot := _part(root, Vector3(0.15, 0.15, 0.03), Vector3(0.0, head_y - 0.32, -0.12), lamp)
		heads.append([i, root, bar, dot, t.origin, ""])
	update(Vector3.ZERO, true)

## Aspects des signaux proches de `center` (appel par image ; mise à jour toutes les UPDATE_S).
func update(center: Vector3, force: bool = false, dt: float = 0.0) -> void:
	_t -= dt
	if _t > 0.0 and not force: return
	_t = UPDATE_S
	for h in heads:
		if not force and ((h[4] as Vector3).distance_to(center) > UPDATE_R or not (h[1] as Node3D).is_visible_in_tree()): continue
		var a := model.aspect(int(h[0]))
		if a == str(h[5]): continue
		h[5] = a
		var bar: MeshInstance3D = h[2]; var dot: MeshInstance3D = h[3]
		bar.visible = a != "caution"
		dot.visible = a == "caution"
		# Repère local : +X à gauche du conducteur ; rotation positive = sommet vers sa droite.
		bar.rotation = Vector3(0.0, 0.0, {"go": 0.0, "stop": PI * 0.5, "left": -PI * 0.25, "right": PI * 0.25}.get(a, PI * 0.5))
