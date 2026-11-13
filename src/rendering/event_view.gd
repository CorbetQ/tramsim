class_name EventView
extends Node3D
## Rendu minimal des événements de mission (MissionEvents) : eau sur la voie, feuilles mortes
## sur les rails, balisage de chantier, véhicule engageant la voie. Construit une fois par
## session, puis seul l'état (obstacle dégagé) est mis à jour.

const SAMPLE_M := 4.0

var _session: MissionSession
var _obstacles: Array = []   # [[item, Node3D]]

## Point d'appel depuis LineView.update_from : crée la vue au premier passage, puis l'actualise.
static func sync(view: LineView, s: MissionSession) -> void:
	var ev: EventView = view.get_node_or_null("EventView")
	if s == null or s.events == null:
		if ev != null: ev.queue_free()
		return
	if ev == null or ev._session != s:
		if ev != null: view.remove_child(ev); ev.queue_free()
		ev = EventView.new(); ev.name = "EventView"
		view.add_child(ev)
		ev._build(view, s)
	ev._refresh()

func _build(view: LineView, s: MissionSession) -> void:
	_session = s
	for it in s.events.render_items():
		match str(it.kind):
			"flood", "flood_closed": _water(view, it.get("segments", []))
			"leaves": _leaves(view, it.get("segments", []))
			"works": _works(view, it.get("segments", []))
			"obstacle": _obstacles.append([it, _car(view, str(it.edge), float(it.offset))])

func _refresh() -> void:
	for pair in _obstacles:
		(pair[1] as Node3D).visible = str(pair[0].state) != "cleared"

static func _mat(c: Color, transparent: bool = false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.08 if transparent else 0.9
	if transparent:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.metallic_specular = 0.9
	return m

func _frames(view: LineView, segments: Array, step: float) -> Array:
	var out: Array = []
	for sg in segments:
		var e := str(sg[0]); var a := float(sg[1]); var b := float(sg[2])
		if not view.net.graph.edges.has(e): continue
		var n := maxi(1, ceili((b - a) / step))
		for i in n + 1: out.append(view._frame(e, lerpf(a, b, float(i) / n)))
	return out

## Nappe d'eau de 4 m de large, quelques centimètres au-dessus des rails.
func _water(view: LineView, segments: Array) -> void:
	for sg in segments:
		var fr := _frames(view, [sg], SAMPLE_M)
		if fr.size() < 2: continue
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
		st.set_normal(Vector3.UP)
		for f in fr:
			var t: Transform3D = f
			st.add_vertex(t * Vector3(-2.2, 0.12, 0.0))
			st.add_vertex(t * Vector3(2.2, 0.12, 0.0))
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		mi.material_override = _mat(Color(0.22, 0.32, 0.36, 0.78), true)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)

## Feuilles mortes éparses sur et entre les rails.
func _leaves(view: LineView, segments: Array) -> void:
	var fr := _frames(view, segments, 0.6)
	if fr.is_empty(): return
	var rng := RandomNumberGenerator.new(); rng.seed = 7
	var leaf := QuadMesh.new(); leaf.size = Vector2(0.12, 0.09)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = leaf
	mm.instance_count = fr.size() * 3
	var palette := [Color(0.55, 0.27, 0.07), Color(0.72, 0.45, 0.12), Color(0.45, 0.2, 0.08), Color(0.62, 0.52, 0.18)]
	for i in fr.size():
		for k in 3:
			var t: Transform3D = fr[i]
			var local := Transform3D(Basis(Vector3.RIGHT, -PI * 0.5).rotated(Vector3.UP, rng.randf() * TAU), Vector3(rng.randf_range(-1.1, 1.1), 0.19, rng.randf_range(-0.3, 0.3)))
			mm.set_instance_transform(i * 3 + k, t * local)
			mm.set_instance_color(i * 3 + k, palette[rng.randi() % palette.size()])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	var m := _mat(Color.WHITE); m.vertex_color_use_as_albedo = true; m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mmi.material_override = m
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)

## Balisage de chantier : barrières rouges et blanches de part et d'autre, panneaux en tête.
func _works(view: LineView, segments: Array) -> void:
	var fr := _frames(view, segments, 6.0)
	if fr.is_empty(): return
	var bar := BoxMesh.new(); bar.size = Vector3(0.1, 1.0, 2.0)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = bar
	mm.instance_count = fr.size() * 2
	for i in fr.size():
		var t: Transform3D = fr[i]
		for k in 2:
			mm.set_instance_transform(i * 2 + k, t * Transform3D(Basis(), Vector3(-2.3 if k == 0 else 2.3, 0.5, 0.0)))
			mm.set_instance_color(i * 2 + k, Color(0.85, 0.08, 0.06) if i % 2 == 0 else Color(0.95, 0.95, 0.92))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	var m := _mat(Color.WHITE); m.vertex_color_use_as_albedo = true
	mmi.material_override = m
	add_child(mmi)
	for t in [fr[0], fr[-1]]:
		var plate := MeshInstance3D.new()
		var box := BoxMesh.new(); box.size = Vector3(4.2, 0.5, 0.08)
		plate.mesh = box
		plate.material_override = _mat(Color(0.95, 0.7, 0.05))
		plate.transform = (t as Transform3D) * Transform3D(Basis(), Vector3(0.0, 1.4, 0.0))
		add_child(plate)

## Voiture engageant le gabarit (caisse simple légèrement en biais).
func _car(view: LineView, edge: String, offset: float) -> Node3D:
	var root := Node3D.new()
	if view.net.graph.edges.has(edge): root.transform = view._frame(edge, offset)
	var body := MeshInstance3D.new()
	var box := BoxMesh.new(); box.size = Vector3(1.8, 0.8, 4.3)
	body.mesh = box; body.material_override = _mat(Color(0.12, 0.28, 0.62))
	body.transform = Transform3D(Basis(Vector3.UP, 0.5), Vector3(1.1, 0.65, 0.0))
	root.add_child(body)
	var cabin := MeshInstance3D.new()
	var cb := BoxMesh.new(); cb.size = Vector3(1.6, 0.6, 2.2)
	cabin.mesh = cb; cabin.material_override = _mat(Color(0.15, 0.18, 0.22))
	cabin.transform = Transform3D(Basis(Vector3.UP, 0.5), Vector3(1.1, 1.35, 0.1))
	root.add_child(cabin)
	add_child(root)
	return root
