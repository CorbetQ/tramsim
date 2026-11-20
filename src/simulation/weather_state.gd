class_name WeatherState
extends RefCounted
## Estimated weather, not live meteorological data. Physics state is independent of rendering.
const PRESETS := {"clear":Vector2(0,0),"rain":Vector2(0.8,0.12),"fog":Vector2(0,0.8),"storm":Vector2(1,0.35)}
var rain := 0.0
var fog := 0.0
var wetness := 0.0
var adhesion := 0.26
var target := Vector2.ZERO
var transition_s := 30.0
var dynamic := false
var remaining_s := 90.0
var rng := RandomNumberGenerator.new()
var preset := "clear"

func configure(name_: String, seed_: int = 7) -> void:
	rng.seed=seed_;dynamic=name_=="dynamic";remaining_s=90
	set_preset("clear" if dynamic else name_)

func set_preset(name_: String) -> void:
	preset=name_ if PRESETS.has(name_) else "clear";target=PRESETS[preset]

func step(dt: float) -> void:
	if dt<=0 or not is_finite(dt): return
	if dynamic:
		remaining_s-=dt
		if remaining_s<=0:
			set_preset(["clear","rain","fog","storm"][rng.randi_range(0,3)])
			remaining_s+=rng.randf_range(90,240)
	var native := NativeSimulation.kernel()
	if native != null:
		var out: PackedFloat64Array = native.call("weather_step",PackedFloat64Array([rain,fog,wetness,target.x,target.y,0,transition_s,dt]))
		if out.size()==4: rain=out[0];fog=out[1];wetness=out[2];adhesion=out[3];return
	var blend := 1.0-exp(-dt/maxf(transition_s,0.1))
	rain=lerpf(rain,target.x,blend);fog=lerpf(fog,target.y,blend)
	wetness=lerpf(wetness,rain,1.0-exp(-dt/(20.0 if rain>wetness else 180.0)))
	adhesion=lerpf(0.26,0.12,clampf(wetness,0,1))

func apply_to(session: MissionSession) -> void:
	if not session.has_meta("weather_base_adhesion"):
		session.set_meta("weather_base_adhesion",session.events.base_adhesion if session.events!=null else session.phys.adhesion)
	var base := float(session.get_meta("weather_base_adhesion"))
	# Existing mission-specific slippery-rail conditions must never be erased by dry weather.
	if session.events != null: session.events.base_adhesion=minf(base,adhesion)
	else: session.phys.adhesion=minf(base,adhesion)

func snapshot() -> Dictionary:
	return {"version":1,"rain":rain,"fog":fog,"wetness":wetness,"target":[target.x,target.y],"dynamic":dynamic,"remaining_s":remaining_s,"rng_state":str(rng.state),"preset":preset,"transition_s":transition_s}

func restore(data: Dictionary) -> bool:
	if data.get("version")!=1 or not data.get("target") is Array or data.target.size()!=2: return false
	for key in ["rain","fog","wetness","remaining_s"]:
		if not (data.get(key) is float or data.get(key) is int) or not is_finite(float(data[key])): return false
	for value in data.target:
		if not (value is float or value is int) or not is_finite(float(value)): return false
	var duration: Variant = data.get("transition_s",30)
	if not (duration is float or duration is int) or not is_finite(float(duration)) or float(duration)<=0:return false
	rain=clampf(data.rain,0,1);fog=clampf(data.fog,0,1);wetness=clampf(data.wetness,0,1)
	target=Vector2(clampf(data.target[0],0,1),clampf(data.target[1],0,1));dynamic=bool(data.get("dynamic",false))
	remaining_s=float(data.remaining_s);rng.state=int(data.get("rng_state","7"));preset=str(data.get("preset","clear"))
	transition_s=float(duration)
	adhesion=lerpf(0.26,0.12,wetness);return true
