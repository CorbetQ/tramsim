class_name TramInterior
extends RefCounted
## Procedural, estimated fit-out from the existing family envelope and door plan.
## Not a manufacturer-verified interior. Only built for the boarded/nearby train.
static var _meshes := {}
static var _materials := {}
const EXTERIOR_LAYER := 1 << 19 # reserved only for the currently boarded shell

static func material(key: String, color: Color, metal: float = 0.0) -> StandardMaterial3D:
	if not _materials.has(key):
		var m := StandardMaterial3D.new();m.albedo_color=color;m.metallic=metal;m.roughness=0.35 if metal>0 else 0.75
		_materials[key]=m
	return _materials[key]

static func box(parent: Node3D, pos: Vector3, size_: Vector3, mat: Material) -> MeshInstance3D:
	var key := str(size_)
	if not _meshes.has(key):
		var mesh := BoxMesh.new();mesh.size=size_;_meshes[key]=mesh
	var n := MeshInstance3D.new();n.mesh=_meshes[key];n.material_override=mat;n.position=pos
	n.visibility_range_end=65;n.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;parent.add_child(n);return n

static func attach(rig: TramModel.Rig, profile: VehicleProfile) -> void:
	if CitadisInterior.attach(rig,profile):return
	var plan := TramModel.plan(rig.family)
	var floor_y := float(plan.get("floor_m",0.32))
	var width := profile.width_m
	var floor_mat := material("floor",Color("#414954"))
	var wall := material("wall",Color("#d8ddd9"))
	var seat := material("seat_"+profile.origin_city,Color("#235b75"))
	var steel := material("steel",Color("#c1c9cd"),0.75)
	var glass := material("glass",Color(.65,.8,.9,.12),.2)
	glass.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA;glass.roughness=.08
	for i in rig.modules.size():
		var module := rig.modules[i]
		if module.has_node("PassengerInterior"):continue
		var root := Node3D.new();root.name="PassengerInterior";module.add_child(root)
		var seats: Array[Vector3] = []
		var length := float(rig.module_lengths[i])
		var definitions: Array=plan.get("modules",[])
		var scale := length/float(definitions[i].length_m) if i<definitions.size() else 1.0
		if i==0:box(root,Vector3(0,1.45,-length*.5+2),Vector3(width-.2,2.25,.08),wall)
		if i==rig.modules.size()-1:box(root,Vector3(0,1.45,length*.5-2),Vector3(width-.2,2.25,.08),wall)
		box(root,Vector3(0,floor_y-0.06,0),Vector3(width-0.14,0.12,length-0.12),floor_mat)
		box(root,Vector3(0,2.62,0),Vector3(width-0.18,0.08,length-0.14),wall)
		for side in [-1,1]:
			var lower_height := maxf(.45,float(plan.get("body",{}).get("window_bottom_m",1.05))-floor_y)
			box(root,Vector3(side*(width*.5-.10),floor_y+lower_height*.5,0),Vector3(.06,lower_height,length-.18),wall)
			box(root,Vector3(side*(width*.5-.10),2.51,0),Vector3(.06,.2,length-.18),wall)
			if i<definitions.size():
				for window in definitions[i].get("windows",[]):
					var a := float(window.z0_m)*scale-length*.5;var b := float(window.z1_m)*scale-length*.5
					if b-a<.05:continue
					box(root,Vector3(side*(width*.5-.12),1.74,(a+b)*.5),Vector3(.008,1.33,b-a),glass)
					box(root,Vector3(side*(width*.5-.15),1.74,a),Vector3(.055,1.55,.06),wall)
			for j in maxi(1,floori((length-2)/1.65)):
				var z := -length*.5+1.2+j*1.65
				# Door vestibules remain clear. Front cab is not a passenger seat.
				var blocked := i==0 and z < -length*.5+2.0
				var defs: Array = plan.get("modules",[])
				if i<defs.size():
					for door in defs[i].get("doors",[]):
						if absf(z-(float(door.z_m)*scale-length*.5))<float(door.get("width_m",1.3))*.5+.65:blocked=true
				if blocked:continue
				box(root,Vector3(side*(width*.5-.48),floor_y+.44,z),Vector3(.58,.12,.62),seat)
				box(root,Vector3(side*(width*.5-.48),floor_y+.79,z+.27),Vector3(.58,.64,.09),seat)
				seats.append(Vector3(side*(width*.5-.48),floor_y+1.12,z))
				box(root,Vector3(side*.48,floor_y+1.04,z+.43),Vector3(.035,2.0,.035),steel)
		root.set_meta("seats",seats)
		batch(root)
		var lamp := OmniLight3D.new();lamp.position=Vector3(0,2.3,0);lamp.omni_range=minf(length,8);lamp.light_energy=.55;lamp.shadow_enabled=false
		lamp.distance_fade_enabled=true;lamp.distance_fade_begin=16;lamp.distance_fade_length=8;root.add_child(lamp)

static func batch(root: Node3D) -> void:
	var groups := {}
	var source_count := 0
	for child in root.get_children():
		if child is MeshInstance3D:
			source_count+=1
			var key := str(child.mesh.get_instance_id())+"/"+str(child.material_override.get_instance_id() if child.material_override!=null else 0)
			if not groups.has(key):groups[key]=[]
			groups[key].append(child)
	for key in groups:
		var nodes: Array = groups[key]
		var multi := MultiMesh.new();multi.transform_format=MultiMesh.TRANSFORM_3D;multi.mesh=nodes[0].mesh;multi.instance_count=nodes.size()
		for i in nodes.size():multi.set_instance_transform(i,nodes[i].transform)
		var instance := MultiMeshInstance3D.new();instance.multimesh=multi;instance.material_override=nodes[0].material_override
		instance.visibility_range_end=65;instance.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;root.add_child(instance)
		for node in nodes:root.remove_child(node);node.free()
	root.set_meta("unbatched_meshes",source_count);root.set_meta("batched_draw_groups",groups.size())

static func show(rig: TramModel.Rig, visible_: bool) -> void:
	for module in rig.modules:
		if module.has_node("PassengerInterior"):module.get_node("PassengerInterior").visible=visible_
		# Interior and exterior are separate draw layers; the painted exterior glazing
		# must not act as an opaque wall in the passenger camera.
		module.layers=EXTERIOR_LAYER if visible_ else 1
		if module.material_override is ShaderMaterial:module.material_override.set_shader_parameter("passenger_shell",visible_)
