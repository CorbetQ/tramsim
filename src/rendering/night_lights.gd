class_name NightLights
extends Node3D
## Éclairage urbain de nuit (lot P4 « ambiance », docs/CDC_REFONTE_VISUELLE.md §6) : les lampadaires restent émissifs
## (tête M_LIGHT, bloom) avec leur halo au sol (StreetProps.HALO) ; les plus proches de la caméra reçoivent en plus une
## vraie lumière dynamique (SpotLight3D dirigé vers le sol, sans ombre, fondu en distance) tirée d'un réservoir borné par
## profil. Les voitures de la circulation les plus proches projettent leurs phares (SpotLight3D) sur PC.
## Budgets (lumières dynamiques simultanées, hors phare et plafonniers de tunnel de la rame) : `BUDGET`.
## Mobile : 3 lampadaires et aucun phare de voiture, soit au plus 8 lumières dynamiques avec la rame (limite moteur de
## 8 omni/spot par objet en Mobile).

const BUDGET := {
	"ultra": {"street": 16, "cars": 4},
	"high": {"street": 10, "cars": 2},
	"mobile": {"street": 3, "cars": 0},
	"fallback": {"street": 4, "cars": 0},
}
const LAMP_H := 6.2          # hauteur moyenne d'une tête de lampadaire au-dessus du halo
const RADIUS := 85.0         # rayon de recherche autour de la caméra
const PERIOD := 0.35         # réaffectation du réservoir (s)
const NIGHT_ON := 0.25       # seuil d'allumage (crépuscule)

var view
var profile := "high"
var street: Array[SpotLight3D] = []
var cars: Array[SpotLight3D] = []
var sources := PackedVector3Array()
var _t := 0.0
var _scan_t := 0.0
var _known := {}
var _shelter_n := 0
var active := 0

static func budget_for(p: String) -> Dictionary:
	return BUDGET.get(p, BUDGET.fallback)

func setup(v, profile_id: String = "") -> void:
	view = v; name = "night_lights"
	profile = profile_id if profile_id != "" else ("mobile" if DayNight.low_quality else VisualEffects.effective_profile("auto"))
	var b := budget_for(profile)
	for i in int(b.street):
		var l := SpotLight3D.new()
		l.spot_range = 13.0; l.spot_angle = 62.0; l.spot_attenuation = 0.9; l.spot_angle_attenuation = 1.6
		l.light_energy = 0.0; l.light_color = Color("#ffd9a8"); l.shadow_enabled = false
		l.light_specular = 0.6
		l.distance_fade_enabled = true; l.distance_fade_begin = RADIUS * 0.6; l.distance_fade_length = RADIUS * 0.3
		l.visible = false; add_child(l); street.append(l)
	for i in int(b.cars):
		var c := SpotLight3D.new()
		c.spot_range = 32.0; c.spot_angle = 24.0; c.spot_attenuation = 1.2; c.light_energy = 0.0
		c.light_color = Color("#fff4e2"); c.shadow_enabled = false
		c.distance_fade_enabled = true; c.distance_fade_begin = 60.0; c.distance_fade_length = 20.0
		c.visible = false; add_child(c); cars.append(c)

func set_profile(p: String) -> void:
	if p == profile: return
	for l in street + cars: l.queue_free()
	street.clear(); cars.clear()
	setup(view, p)

## Positions des têtes de lampadaires (halos au sol relevés) : nouvelles tuiles prises en compte au fil du streaming.
func _scan() -> void:
	var keep: Array = []
	for w in StreetProps.halo_sets:
		var mi = (w as WeakRef).get_ref()
		if mi == null: continue
		keep.append(w)
		var id: int = mi.get_instance_id()
		if _known.has(id) or not (mi as Node).is_inside_tree(): continue
		_known[id] = true
		var mm: MultiMesh = (mi as MultiMeshInstance3D).multimesh
		var xf: Transform3D = (mi as Node3D).global_transform
		for i in mm.instance_count:
			sources.append(xf * mm.get_instance_transform(i).origin + Vector3(0, LAMP_H, 0))
	StreetProps.halo_sets = keep
	# bandeaux LED et mâts lumineux des abris de station (StationShelters, repère de la vue)
	var xf: Transform3D = (view as Node3D).global_transform
	while _shelter_n < StationShelters.lights.size():
		sources.append(xf * StationShelters.lights[_shelter_n]); _shelter_n += 1

func _process(dt: float) -> void:
	if view == null or view.cam == null or view.day_night == null: return
	var night: float = view.day_night.night
	_t -= dt; _scan_t -= dt
	if _scan_t <= 0.0: _scan_t = 2.0; _scan()
	StationShelters.update_boards(view.cam.global_position, view.day_night.hour, dt)
	if _t > 0.0: return
	_t = PERIOD
	var k := clampf((night - NIGHT_ON) / 0.35, 0.0, 1.0)
	var cam: Camera3D = view.cam
	var cp := cam.global_position
	var fwd := -cam.global_basis.z
	active = 0
	if k <= 0.0:
		for l in street + cars: l.visible = false
		return
	# lampadaires : les plus proches, devant la caméra de préférence
	var best: Array = []
	if not street.is_empty():
		for p in sources:
			var d := p - cp
			var dist := d.length()
			if dist > RADIUS: continue
			var score := dist * (1.0 if d.dot(fwd) > -4.0 else 2.5)
			best.append([score, p])
		best.sort_custom(func(a, b): return a[0] < b[0])
	for i in street.size():
		var l := street[i]
		if i < best.size():
			l.visible = true
			l.global_transform = Transform3D(Basis.looking_at(Vector3.DOWN, Vector3.FORWARD), best[i][1])
			l.light_energy = 2.4 * k
			active += 1
		else: l.visible = false
	# phares des voitures de la circulation (les plus proches)
	var cl: Array = []
	if not cars.is_empty() and "car_nodes" in view:
		for n in view.car_nodes:
			if not (n as Node3D).is_visible_in_tree(): continue
			cl.append([(n as Node3D).global_position.distance_to(cp), n])
		cl.sort_custom(func(a, b): return a[0] < b[0])
	for i in cars.size():
		var c := cars[i]
		if i < cl.size() and float(cl[i][0]) < 80.0:
			var n: Node3D = cl[i][1]
			var f := -n.global_basis.z.normalized()
			c.visible = true
			c.global_transform = Transform3D(Basis.looking_at((f + Vector3(0, -0.08, 0)).normalized(), Vector3.UP), n.global_position + f * 2.3 + Vector3(0, 0.7, 0))
			c.light_energy = 3.0 * k
			active += 1
		else: c.visible = false
