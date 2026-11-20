class_name CitadisInterior
extends RefCounted
## Reference-studied fit-out with Meshy seat kits and locally authored fixtures.
## Estimated arrangement, not manufacturer CAD; original geometry remains fallback.
static var _tubes := {}

static func pipe(parent: Node3D, a: Vector3, b: Vector3, mat: Material, radius: float=.018) -> void:
	var length := a.distance_to(b)
	if length<.001:return
	var key := "%.3f/%.3f"%[radius,length]
	if not _tubes.has(key):
		var mesh := CylinderMesh.new();mesh.top_radius=radius;mesh.bottom_radius=radius
		mesh.height=length;mesh.radial_segments=8;mesh.rings=1;_tubes[key]=mesh
	var node := MeshInstance3D.new();node.mesh=_tubes[key];node.material_override=mat
	var direction := (b-a).normalized()
	var x := Vector3.RIGHT if absf(direction.dot(Vector3.RIGHT))<.95 else Vector3.FORWARD
	var z := x.cross(direction).normalized();x=direction.cross(z).normalized()
	node.transform=Transform3D(Basis(x,direction,z),(a+b)*.5);parent.add_child(node)

static func attach(rig, profile: VehicleProfile) -> bool:
	if not CitadisMeshy.reference_interiors_enabled:return false
	var key := CitadisMeshy.key_for(profile.variant_id)
	if key=="":return false
	var seat_mesh := CitadisMeshy.seat(key)
	if seat_mesh==null:return false
	var nantes := key=="nantes405"
	var plan := StockGeometry.apply(TramModel.plan(rig.family),profile.fleet)
	var floor_y := float(plan.get("floor_m",.32));var width := profile.width_m
	var floor_mat := TramInterior.material("citadis_floor",Color("#42494d"))
	var wood_floor := TramInterior.material("nantes_wood_floor",Color("#9c876b"))
	var wall := TramInterior.material("citadis_warm_wall",Color("#e0e2da"))
	var silver := TramInterior.material("citadis_brushed_steel",Color("#aebbbf"),.65)
	var copper := TramInterior.material("nantes_copper",Color("#a76c46"),.55)
	var lime := TramInterior.material("irigo_lime",Color("#8eaf28"))
	var dark := TramInterior.material("citadis_screen",Color("#15282c"))
	var light := TramInterior.material("citadis_luminaire",Color("#f2f4dd"))
	light.emission_enabled=true;light.emission=Color("#e4ecd4");light.emission_energy_multiplier=.45
	var glass := TramInterior.material("citadis_partition",Color(.55,.72,.76,.16),.15)
	glass.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA;glass.roughness=.14
	for i in rig.modules.size():
		var module: Node3D=rig.modules[i]
		if module.has_node("PassengerInterior"):continue
		var root := Node3D.new();root.name="PassengerInterior";module.add_child(root)
		root.set_meta("reference_profile",key);root.set_meta("layout_accuracy","photo-estimated")
		var seats: Array[Vector3]=[]
		var length: float=rig.module_lengths[i]
		var definition: Dictionary=plan.modules[i]
		var ratio := length/float(definition.length_m)
		var doors: Array=[]
		for d in definition.get("doors",[]):doors.append([float(d.z_m)*ratio-length*.5,float(d.get("width_m",1.3))])
		var floor_size := Vector3(width-.15,.10,length-.08)
		TramInterior.box(root,Vector3(0,floor_y-.05,0),floor_size,floor_mat)
		if nantes:TramInterior.box(root,Vector3(0,floor_y+.004,0),Vector3(.55,.008,length-.10),wood_floor)
		TramInterior.box(root,Vector3(0,2.69,0),Vector3(width-.14,.09,length-.10),wall)
		for side in [-1,1]:
			var x: float=side*(width*.5-.12)
			TramInterior.box(root,Vector3(x,2.58,0),Vector3(.16,.13,length-.12),wall)
			TramInterior.box(root,Vector3(side*.72,2.632,0),Vector3(.12,.018,length-.22),light)
			# Real vestibules: lower panels stop at door apertures, unlike generic fit-out.
			var cuts: Array=[-length*.5+.08,length*.5-.08]
			for door in doors:cuts.append(door[0]-door[1]*.5);cuts.append(door[0]+door[1]*.5)
			cuts.sort()
			for k in cuts.size()-1:
				var a: float=cuts[k];var b: float=cuts[k+1];var middle := (a+b)*.5
				if in_door(middle,doors,.01):continue
				TramInterior.box(root,Vector3(x,.70,middle),Vector3(.075,.72,b-a),wall)
			for window in definition.get("windows",[]):
				var a := float(window.z0_m)*ratio-length*.5
				TramInterior.box(root,Vector3(x,1.77,a),Vector3(.055,1.50,.045),wall)
			# Keep all furniture clear of the door sweep and both driving cabs.
			var z := -length*.5+1.15
			while z<length*.5-.65:
				var cab: bool=(i==0 and z< -length*.5+2.45) or (i==rig.modules.size()-1 and z>length*.5-2.45)
				if not cab and not in_door(z,doors,.85):
					var centres: Array=[side*(width*.5-.55)] if nantes else [side*(width*.5-.32),side*(width*.5-.81)]
					for centre in centres:
						var chair := MeshInstance3D.new();chair.mesh=seat_mesh
						chair.position=Vector3(centre,floor_y,z)
						chair.rotation.y=PI if side>0 else 0.0
						root.add_child(chair)
						if nantes:
							for dx in [-.235,.235]:seats.append(Vector3(centre+dx,floor_y+1.12,z))
						else:seats.append(Vector3(centre,floor_y+1.12,z))
				z+=1.38
		for door in doors:
			for side in [-1,1]:
				var x: float=side*.48;var z := float(door[0])+float(door[1])*.5+.12
				# Tulip-shaped branching rails on Irigo, straight copper/steel on Naolib.
				var a := Vector3(x,floor_y,z);var b := Vector3(x,1.6,z)
				pipe(root,a,b,silver)
				if nantes:
					pipe(root,b,Vector3(x,2.60,z),copper)
				else:
					for dx in [-.24,.24]:
						var bend := Vector3(x+dx,2.27,z)
						pipe(root,b,bend,silver);pipe(root,bend,Vector3(x+dx,2.60,z),silver)
				TramInterior.box(root,Vector3(side*.87,1.15,z),Vector3(.12,.23,.16),copper if nantes else lime)
		# Information screens and grab rails do not intersect intercirculation.
		for end in [-1,1]:
			var z: float=end*(length*.5-.32)
			TramInterior.box(root,Vector3(0,2.33,z),Vector3(.57,.25,.055),dark)
			TramInterior.box(root,Vector3(0,2.35,z-end*.032),Vector3(.48,.022,.008),lime)
		if nantes:
			var mirror := TramInterior.material("nantes_ceiling_mirror",Color("#abbcc2"),.9)
			TramInterior.box(root,Vector3(0,2.634,0),Vector3(.46,.012,length-.2),mirror)
		else:
			# Original stylised botanical motif, not copied pixels from press photos.
			for j in maxi(1,int(length/1.3)):
				var z := -length*.5+.65+j*1.3
				for petal in 5:
					var angle := TAU*petal/5.0
					var flower := TramInterior.box(root,Vector3(.30+cos(angle)*.11,2.632,z+sin(angle)*.11),Vector3(.10,.006,.18),lime)
					flower.rotation.y= -angle
		if i==0 or i==rig.modules.size()-1:
			var z := (-length*.5+2.15) if i==0 else (length*.5-2.15)
			TramInterior.box(root,Vector3(0,1.51,z),Vector3(width-.2,2.24,.025),glass)
			for side in [-1,1]:pipe(root,Vector3(side*.50,floor_y,z),Vector3(side*.50,2.61,z),silver,.024)
		root.set_meta("seats",seats);root.set_meta("door_zones",doors)
		TramInterior.batch(root)
		var lamp := OmniLight3D.new();lamp.position=Vector3(0,2.3,0);lamp.omni_range=minf(length,8)
		lamp.light_energy=.5;lamp.shadow_enabled=false;lamp.distance_fade_enabled=true
		lamp.distance_fade_begin=14;lamp.distance_fade_length=7;root.add_child(lamp)
	return true

static func in_door(z: float, doors: Array, margin: float) -> bool:
	for door in doors:
		if absf(z-float(door[0]))<float(door[1])*.5+margin:return true
	return false
