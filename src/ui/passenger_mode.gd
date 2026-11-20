class_name PassengerMode
extends ExploreMode
## Uses the real AI sessions and rendered articulated modules. No dummy moving vehicle.
var walker := PassengerController.new()
var info: Label
var action: Button
var seat_button: Button
var touch_move := Vector2.ZERO
var _look_finger := -1
var _mouse_look := false
var _candidate: Dictionary = {}
var onboard_audio: TramAudio
var time_rate_hours_per_second := 0.0

func start(city_name: String, path: String, hour_: float, distance: float = 400.0, with_trams: bool = true) -> bool:
	if not super.start(city_name,path,hour_,distance,true):return false
	view.cam.near=.08
	view.cam.cull_mask=view.cam.cull_mask & ~TramInterior.EXTERIOR_LAYER
	var p: Vector3 = places[0].pos if not places.is_empty() else view.pos3(str(net.graph.edges.keys()[0]),0)
	# Start alongside the station track, not standing on it.
	walker.position=p+Vector3(3,0,0);walker.position.y=view.ground_at(walker.position)+PassengerController.EYE
	view.cam.rotation=Vector3.ZERO
	return true

func _build_ui() -> void:
	var safe := UiLayout.safe_insets(self)
	var top := _panel();top.position=Vector2(14+safe.x,14+safe.y);top.custom_minimum_size.x=minf(560,get_viewport_rect().size.x-28-safe.x-safe.z);add_child(top)
	var v := VBoxContainer.new();top.add_child(v)
	v.add_child(UiTheme.label_("PASSAGER · "+city,UiTheme.SIZE_BODY,UiTheme.TEXT,true))
	info=UiTheme.label_("Marchez jusqu’à une porte ouverte",UiTheme.SIZE_SMALL,UiTheme.TEXT);v.add_child(info)
	var row := HFlowContainer.new();v.add_child(row)
	action=_btn("Monter / descendre","tram",interact);row.add_child(action)
	seat_button=_btn("S’asseoir","free",toggle_seat);row.add_child(seat_button)
	row.add_child(_btn("Stations","search",toggle_list));row.add_child(_btn("Accueil","home",leave))
	if OS.has_feature("mobile"):
		var controls := HBoxContainer.new();controls.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT);controls.position=Vector2(16,-140);add_child(controls)
		for item in [["←",Vector2.LEFT],["↑",Vector2.UP],["↓",Vector2.DOWN],["→",Vector2.RIGHT]]:
			var b := Button.new();b.text=item[0];b.custom_minimum_size=Vector2(64,64);controls.add_child(b)
			var value: Vector2 = item[1]
			b.button_down.connect(func():touch_move=value);b.button_up.connect(func():touch_move=Vector2.ZERO)

func _btn(text_: String, icon_name: String, callback: Callable, kind: String = "normal") -> Button:
	var button := super._btn(text_,icon_name,callback,kind)
	button.icon=null;button.custom_minimum_size=Vector2(110,48)
	return button

func go_to(target: Vector3) -> void:
	if walker.train_id!="":return
	walker.position=target+Vector3(3,0,0);walker.position.y=view.ground_at(walker.position)+PassengerController.EYE
	if view.city:view.city.warm(walker.position)

func _walking_clear(a: Vector3,b: Vector3) -> bool:
	if ai!=null:
		for train in ai.trams:
			if not view.ai_view.rigs.has(train.train_id):continue
			var rig: TramModel.Rig=view.ai_view.rigs[train.train_id]
			for i in rig.modules.size():
				var local := rig.modules[i].global_transform.affine_inverse()*b
				if absf(local.x)<train.phys.profile.width_m*.5+.25 and absf(local.z)<rig.module_lengths[i]*.5+.25 and local.y>0 and local.y<3.5:return false
	if view.city==null:return true
	var city_scene := view.city
	var scale_x := float(city_scene.get("_x_scale"))
	var local_a := Vector3((a.x-city_scene.position.x)/scale_x,a.y,a.z-city_scene.position.z)
	var local_b := Vector3((b.x-city_scene.position.x)/scale_x,b.y,b.z-city_scene.position.z)
	for offset in [Vector3.ZERO,Vector3(.25,0,0),Vector3(0,0,.25),Vector3(-.25,0,0),Vector3(0,0,-.25)]:
		if city_scene.camera_clear(local_a+offset,local_b+offset)<.9999:return false
	return true

func _train() -> AiTram:
	if ai!=null:
		for t in ai.trams:
			if t.train_id==walker.train_id:return t
	return null

func _near_door() -> Dictionary:
	var best := {};var nearest := 2.7
	if ai==null:return best
	for t in ai.trams:
		if t.phys.speed>=.1 or not t.doors_open or not view.ai_view.rigs.has(t.train_id):continue
		var rig: TramModel.Rig=view.ai_view.rigs[t.train_id]
		var plan := TramModel.plan(rig.family)
		var defs: Array=plan.get("modules",[])
		for i in mini(defs.size(),rig.modules.size()):
			var length := float(rig.module_lengths[i])
			var scale := length/float(defs[i].length_m)
			for door in defs[i].get("doors",[]):
				for side in [-1,1]:
					if bool(plan.get("unidirectional",false)) and side<0:continue
					var openness := rig.door_t_right if side>0 else rig.door_t_left
					var local := Vector3(side*t.phys.profile.width_m*.5,float(plan.get("floor_m",.32))+PassengerController.EYE,float(door.z_m)*scale-length*.5)
					var at := rig.modules[i].global_transform*local
					var d := Vector2(at.x-walker.position.x,at.z-walker.position.z).length()
					if d<nearest and PassengerController.can_board(t.phys.speed,openness,d,at.y-walker.position.y):
						nearest=d;best={"train":t,"rig":rig,"module":i,"local":local,"outside":rig.modules[i].global_transform*(local+Vector3(side*1.0,0,0))}
	return best

func interact() -> void:
	if walker.train_id=="":
		_candidate=_near_door()
		if _candidate.is_empty():return
		var t: AiTram=_candidate.train
		var rig := view.ai_view.ensure_passenger_rig(view,t)
		var look := (rig.modules[int(_candidate.module)].global_basis.inverse()*view.cam.global_basis).get_euler()
		walker.yaw=look.y;walker.pitch=clampf(look.x,-1.2,1.2)
		TramInterior.attach(rig,t.phys.profile)
		TramInterior.show(rig,true)
		if is_instance_valid(onboard_audio):onboard_audio.queue_free()
		# Own the 3D anchor inside the audio node so alighting releases all voices.
		onboard_audio=TramAudio.new(null,null,rig.family);add_child(onboard_audio);onboard_audio.view=view
		walker.train_id=t.train_id;walker.ride_distance=rig.module_starts[int(_candidate.module)]+float(_candidate.local.z)+rig.module_lengths[int(_candidate.module)]*.5
		walker.lateral=0;walker.seated=false
		# Keep the actual occupied session from arbitrary anti-deadlock retirement.
		t.wait_s=0
	else:
		_candidate=_near_door()
		if _candidate.is_empty() or _candidate.train.train_id!=walker.train_id:return
		walker.position=_candidate.outside;walker.position.y=view.ground_at(walker.position)+PassengerController.EYE
		var look := view.cam.global_basis.get_euler();walker.yaw=look.y;walker.pitch=clampf(look.x,-1.2,1.2)
		TramInterior.show(_candidate.rig,false)
		if is_instance_valid(onboard_audio):onboard_audio.queue_free()
		onboard_audio=null
		walker.train_id="";walker.seated=false

func toggle_seat() -> void:
	var t := _train()
	if t==null or not view.ai_view.rigs.has(t.train_id):return
	if walker.seated:walker.seated=false;walker.lateral=0;return
	var rig: TramModel.Rig=view.ai_view.rigs[t.train_id]
	var best_distance := 1.6;var best := {};var seat_at := Vector3.ZERO
	for i in rig.modules.size():
		var root := rig.modules[i].get_node_or_null("PassengerInterior")
		if root==null:continue
		for local in root.get_meta("seats",[]):
			var at: Vector3=rig.modules[i].global_transform*local
			var distance := at.distance_to(walker.position)
			if distance<best_distance:best_distance=distance;best={"module":i};seat_at=local
	if best.is_empty():return
	walker.seated=true;walker.lateral=seat_at.x
	walker.ride_distance=rig.module_starts[int(best.module)]+rig.module_lengths[int(best.module)]*.5+seat_at.z

func _process(dt: float) -> void:
	if view==null:return
	dt=minf(dt,.1)
	hour=fposmod(hour+dt*time_rate_hours_per_second,24.0)
	weather.step(dt)
	var movement := touch_move
	if not get_viewport().gui_get_focus_owner() is LineEdit:
		if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_Z):movement.y-=1
		if Input.is_physical_key_pressed(KEY_S):movement.y+=1
		if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_Q):movement.x-=1
		if Input.is_physical_key_pressed(KEY_D):movement.x+=1
	var t := _train()
	if walker.train_id!="" and t==null:
		walker.train_id="";walker.seated=false;walker.position.y=view.ground_at(walker.position)+PassengerController.EYE
		if is_instance_valid(onboard_audio):onboard_audio.queue_free()
		onboard_audio=null
	if ai!=null:
		for tram_ai in ai.trams:weather.apply_to(tram_ai)
		if t!=null:t.wait_s=0
		ai.focus=Vector2(walker.position.x,walker.position.z);ai.step(dt,_dummy)
		view.ai_view.forced_detail=walker.train_id
		view.ai_view.sync(view,ai,walker.position,dt)
	t=_train()
	if t!=null and is_instance_valid(onboard_audio):onboard_audio.update(t,t.driver.cran*.25,false,false,false,dt)
	if t==null:walker.walk(movement,dt,view.ground_at,_walking_clear)
	elif view.ai_view.rigs.has(t.train_id):
		var rig: TramModel.Rig=view.ai_view.rigs[t.train_id]
		if not walker.seated:
			var relative_move := Vector3(movement.x,0,movement.y).limit_length().rotated(Vector3.UP,walker.yaw)
			walker.ride_distance=clampf(walker.ride_distance+relative_move.z*1.1*dt,2.0,rig.length-2.0)
			walker.lateral=clampf(walker.lateral+relative_move.x*dt,-.26,.26)
		var module_index := 0
		for i in rig.modules.size():
			if walker.ride_distance>=rig.module_starts[i]:module_index=i
		var floor_y := float(TramModel.plan(rig.family).get("floor_m",.32))
		var local := Vector3(walker.lateral,floor_y+(1.12 if walker.seated else PassengerController.EYE),walker.ride_distance-rig.module_starts[module_index]-rig.module_lengths[module_index]*.5)
		walker.position=rig.modules[module_index].global_transform*local
		view.cam.global_transform=rig.modules[module_index].global_transform*Transform3D(Basis.from_euler(Vector3(walker.pitch,walker.yaw,0)),local)
	if t==null:view.cam.position=walker.position;view.cam.rotation=Vector3(walker.pitch,walker.yaw,0)
	view.update_sectors(walker.position)
	if view.city:view.city.update(walker.position,1)
	view.day_night.set_hour(hour);view.day_night.set_ground(view.ground_at(walker.position))
	weather_view.apply(weather,view,t!=null)
	_candidate=_near_door();action.disabled=_candidate.is_empty()
	seat_button.disabled=t==null
	info.text=("À bord · ligne "+t.line+" · "+("assis" if walker.seated else "debout")) if t!=null else "À pied · approchez une porte ouverte à l’arrêt"

func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and not ev.echo:
		if ev.keycode==KEY_ESCAPE:leave()
		elif ev.keycode==KEY_E:interact()
		elif ev.keycode==KEY_F:toggle_seat()
	elif ev is InputEventMouseButton and ev.button_index==MOUSE_BUTTON_RIGHT:_mouse_look=ev.pressed
	elif ev is InputEventMouseMotion and _mouse_look:walker.look(ev.relative)
	elif ev is InputEventScreenTouch:
		if ev.pressed and _look_finger<0:_look_finger=ev.index
		elif not ev.pressed and ev.index==_look_finger:_look_finger=-1
	elif ev is InputEventScreenDrag and ev.index==_look_finger:walker.look(ev.relative)

func _input(ev: InputEvent) -> void:
	# Always release the looking finger, including releases consumed by a UI button.
	if ev is InputEventScreenTouch and not ev.pressed and ev.index==_look_finger:_look_finger=-1

func _notification(what: int) -> void:
	if what==NOTIFICATION_APPLICATION_FOCUS_OUT:touch_move=Vector2.ZERO;_mouse_look=false;_look_finger=-1

func _exit_tree() -> void:
	if ai!=null:
		for train in ai.trams.duplicate():train.remove()
		ai.trams.clear();ai.player=null
	if _dummy!=null:_dummy.ai=null
	ai=null;_dummy=null
	super._exit_tree()
