class_name TramPreview
extends SubViewportContainer
## Aperçu 3D tournant d'une rame (menu) : famille et livrée du réseau / de la ligne choisis.
## Démonstration des animations : cycle d'ouverture / fermeture des portes, pantographe levé.

var world: Node3D
var holder: Node3D
var cam: Camera3D
var rig: TramModel.Rig
var _cycle := 0.0
var _length:=32.0
var _view:="threequarter"
var auto_rotate:=false

func _init() -> void:
	custom_minimum_size = Vector2(520, 380)

func _ready() -> void:
	stretch = true
	var sv := SubViewport.new(); sv.own_world_3d = true; sv.msaa_3d = Viewport.MSAA_2X
	add_child(sv)
	world = Node3D.new(); sv.add_child(world)
	var dn := DayNight.new(); world.add_child(dn); dn.setup(world); dn.set_hour(15.5)
	dn.env.fog_enabled = false
	var g := MeshInstance3D.new(); var cm := CylinderMesh.new()
	cm.top_radius = 26.0; cm.bottom_radius = 26.0; cm.height = 0.2; cm.radial_segments = 24
	g.mesh = cm; g.position = Vector3(0, -0.1, 0)
	var gm := StandardMaterial3D.new(); gm.albedo_color = Color("#7d8a72"); g.material_override = gm; world.add_child(g)
	holder = Node3D.new(); world.add_child(holder)
	cam = Camera3D.new(); cam.fov = 40.0; world.add_child(cam)
	cam.position = Vector3(30, 11, -38); cam.look_at(Vector3(0, 1.2, 0))

func show_tram(meta: Dictionary, vehicle: VehicleProfile) -> void:
	for c in holder.get_children(): c.queue_free()
	var liv := TramModel.livery_for(meta, LineView.tram_entry(vehicle))
	var L := minf(vehicle.length_m if vehicle else float(liv.length), 48.0)
	rig = TramModel.build_rig(liv, L)
	rig.layout_straight()
	for m in rig.modules: holder.add_child(m)
	_cycle = 0.0;_length=L;set_view(_view)

func set_view(mode:String)->void:
	_view=mode;auto_rotate=false
	if not holder or not cam:return
	holder.rotation=Vector3.ZERO
	var target:=Vector3(0,1.6,0)
	if mode=="front":
		target.z=-_length*.5+.7;cam.position=Vector3(0,1.9,-_length*.5-7.5);cam.fov=32.0
	elif mode=="side":cam.position=Vector3(_length*1.32,3.8,0);cam.fov=34.0
	else:cam.position=Vector3(_length*.75+3,_length*.20+3,-_length*.72-3);cam.fov=34.0
	cam.look_at(target)

func _process(dt: float) -> void:
	if holder and auto_rotate: holder.rotate_y(dt * 0.35)
	if rig:
		_cycle = fmod(_cycle + dt, 12.0)
		rig.set_doors(_cycle > 3.0 and _cycle < 8.0)
		rig.set_pantograph(true)
		rig.update(dt)
