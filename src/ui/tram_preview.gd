class_name TramPreview
extends SubViewportContainer
## Aperçu 3D tournant d'une rame (menu) : famille et livrée du réseau / de la ligne choisis.

var world: Node3D
var holder: Node3D
var cam: Camera3D

func _ready() -> void:
	stretch = true
	custom_minimum_size = Vector2(520, 380)
	var sv := SubViewport.new(); sv.own_world_3d = true; sv.msaa_3d = Viewport.MSAA_2X
	add_child(sv)
	world = Node3D.new(); sv.add_child(world)
	var dn := DayNight.new(); world.add_child(dn); dn.setup(world); dn.set_hour(15.5)
	dn.env.fog_enabled = false
	var g := MeshInstance3D.new(); var cm := CylinderMesh.new()
	cm.top_radius = 22.0; cm.bottom_radius = 22.0; cm.height = 0.2; cm.radial_segments = 24
	g.mesh = cm; g.position = Vector3(0, -0.1, 0)
	var gm := StandardMaterial3D.new(); gm.albedo_color = Color("#7d8a72"); g.material_override = gm; world.add_child(g)
	holder = Node3D.new(); world.add_child(holder)
	cam = Camera3D.new(); cam.fov = 40.0; world.add_child(cam)
	cam.position = Vector3(30, 11, -38); cam.look_at(Vector3(0, 1.2, 0))

func show_tram(meta: Dictionary, vehicle: VehicleProfile) -> void:
	for c in holder.get_children(): c.queue_free()
	var liv := TramModel.livery_for(meta, vehicle.fleet if vehicle else {})
	var fam: String = liv.family
	if vehicle != null:
		fam = vehicle.model_family if vehicle.model_family != "" else TramModel.PROFILE_FAMILY.get(vehicle.id, fam)
	var L := minf(vehicle.length_m if vehicle else 32.0, 44.0)
	var mods := TramModel.build(L, liv, fam)
	var seg := L / mods.size()
	for k in mods.size():
		mods[k].position = Vector3(0, 0, -L * 0.5 + seg * (k + 0.5))
		holder.add_child(mods[k])

func _process(dt: float) -> void:
	if holder: holder.rotate_y(dt * 0.35)
