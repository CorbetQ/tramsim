extends SceneTree
var fails := 0
var checks := 0
func check(ok: bool, message: String) -> void:
	checks+=1
	if not ok:fails+=1;printerr("ECHEC: ",message)
	else:print("ok: ",message)
func _initialize() -> void:run.call_deferred()
func run() -> void:
	var native := NativeSimulation.kernel()
	print("BACKEND|","rust" if native!=null else "gdscript")
	var required := "--require-native" in OS.get_cmdline_user_args()
	check(not required or native!=null,"native availability matches requested backend")
	if native!=null:
		var a := TrainPhysics.new(VehicleLibrary.citadis_302())
		var b := TrainPhysics.new(VehicleLibrary.citadis_302())
		var same := true
		for i in 6000:
			var n := 1.0 if i%900<400 else (-.75 if i%900<750 else 0.0)
			var grade := .05*sin(i*.005)
			a.adhesion=.07 if i>3000 else .26;b.adhesion=a.adhesion
			a.sanding=i>4000;b.sanding=a.sanding
			a.power_available=i%800<700;b.power_available=a.power_available
			NativeSimulation.enabled=true;a.step(1.0/60,n,grade,i%1000>950)
			NativeSimulation.enabled=false;b.step(1.0/60,n,grade,i%1000>950)
			same=same and absf(a.velocity-b.velocity)<1e-8 and absf(a.position-b.position)<1e-6 and a.wheel_slip==b.wheel_slip and a.wheel_slide==b.wheel_slide
		check(same,"6000-step Rust/GDScript parity: slopes, braking, power, slip, sanding")
	NativeSimulation.enabled=native!=null
	var weather := WeatherState.new();weather.configure("rain");weather.transition_s=2
	for i in 1200:weather.step(.1)
	check(weather.rain>.79 and weather.wetness>.78 and weather.adhesion<.16,"rain wets rail and reduces grip progressively")
	var wet := TrainPhysics.new(VehicleLibrary.citadis_302());wet.adhesion=weather.adhesion
	var dry := TrainPhysics.new(VehicleLibrary.citadis_302())
	# Test a high-service-brake profile: moderate wet grip need not limit every tram.
	wet.profile.service_brake_ms2=1.5;dry.profile.service_brake_ms2=1.5
	check(wet.braking_distance(15)>dry.braking_distance(15),"wet braking prediction is longer than dry")
	weather.set_preset("clear")
	for i in 60:weather.step(.1)
	check(weather.rain<.05 and weather.wetness>.7,"rail stays wet after rainfall stops")
	var a_weather := WeatherState.new();a_weather.configure("dynamic",42)
	for i in 1000:a_weather.step(.1)
	var b_weather := WeatherState.new()
	check(b_weather.restore(a_weather.snapshot()),"weather state roundtrip including RNG")
	for i in 1500:a_weather.step(.1);b_weather.step(.1)
	check(a_weather.snapshot()==b_weather.snapshot(),"weather continuation deterministic after restore")
	check(not b_weather.restore({"version":1,"target":["bad",0]}),"malformed snapshot rejected")
	if native!=null:
		var c := WeatherState.new();var d := WeatherState.new();c.configure("rain");d.configure("rain")
		for i in 300:
			NativeSimulation.enabled=true;c.step(.1);NativeSimulation.enabled=false;d.step(.1)
		check(absf(c.wetness-d.wetness)<1e-10,"Rust/GDScript weather parity")
	NativeSimulation.enabled=true
	check(not PassengerController.can_board(1,1,1,0),"moving tram cannot be boarded")
	check(not PassengerController.can_board(0,0,1,0),"closed doors prevent boarding")
	check(not PassengerController.can_board(0,1,1,3),"vertically separated tracks prevent boarding")
	check(PassengerController.can_board(0,1,2,.4),"stationary accessible door permits boarding")
	var walker := PassengerController.new();walker.position=Vector3(0,1.65,0)
	walker.walk(Vector2.UP,1,func(_p):return 0.0,func(_a,_b):return true)
	check(absf(walker.position.z+1.4)<.001,"walking has human speed and no flying")
	var before := walker.position
	walker.walk(Vector2.UP,1,func(_p):return 0.0,func(_a,_b):return false)
	check(walker.position==before,"obstruction callback blocks movement")
	print("CHECKS|",checks,"|TOTAL_ECHECS|",fails);quit(1 if fails else 0)
