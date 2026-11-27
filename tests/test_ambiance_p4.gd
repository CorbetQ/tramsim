extends SceneTree
## Lot P4 « ambiance » (docs/CDC_REFONTE_VISUELLE.md, « État P4 — ambiance ») : météo (chaussée mouillée, flaques, neige,
## brume matinale, pare-brise et balai), nuit (réservoir de lumières dynamiques borné par profil, ciel), abris de
## station par réseau (styles, mobilier, PID animé), feux R17 / R11 (aspects ↔ symboles allumés), gazon de voie.

var fails := 0

func check(c: bool, m: String) -> void:
	if c: print("ok: ", m)
	else: fails += 1; printerr("ECHEC: ", m)

class FakeView extends Node3D:
	var cam: Camera3D
	var day_night: DayNight
	var car_nodes: Array[MeshInstance3D] = []

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	_shaders()
	_weather()
	await _night_lights()
	_windscreen()
	_shelters()
	_signals()
	_grass()
	print("TOTAL_ECHECS|%d" % fails)
	quit(1 if fails > 0 else 0)

func _shaders() -> void:
	var common := FileAccess.get_file_as_string("res://src/rendering/shaders/pbr_common.gdshaderinc")
	check(common.contains("global uniform float wet;") and common.contains("global uniform float snow;") and common.contains("void pbr_weather("),
		"pbr_common : globaux wet/snow et pbr_weather (mouillé, flaques, neige)")
	for f in ["pbr_world.gdshader", "pbr_surface.gdshader", "station_paving.gdshader"]:
		check(FileAccess.get_file_as_string("res://src/rendering/shaders/" + f).contains("pbr_weather("), "%s : météo appliquée" % f)
	var proj := FileAccess.get_file_as_string("res://project.godot")
	check(proj.contains("\nwet={") and proj.contains("\nsnow={"), "project.godot : globaux de shader wet et snow déclarés")
	var sky := FileAccess.get_file_as_string("res://src/rendering/shaders/sky.gdshader")
	check(sky.contains("maria") and sky.contains("tw = ") and sky.contains("Vénus"), "ciel : lune (mers, phase), étoiles scintillantes, ceinture de Vénus")
	var ws := FileAccess.get_file_as_string("res://src/rendering/shaders/windscreen_rain.gdshader")
	check(ws.contains("hint_screen_texture") and ws.contains("clear_t[16]"), "pare-brise : réfraction de l'image et secteurs balayés")

func _weather() -> void:
	check(WeatherState.PRESETS.has("snow"), "préréglage neige légère")
	check(WeatherView.morning_mist(7.25) > 0.99 and WeatherView.morning_mist(4.5) == 0.0 and WeatherView.morning_mist(12.0) == 0.0
		and WeatherView.morning_mist(6.0) > 0.1, "brume matinale : maximale vers 7 h 15, nulle la nuit et l'après-midi")
	var vf := FileAccess.get_file_as_string("res://src/rendering/weather_view.gd")
	check(vf.contains("volumetric_fog_enabled") and vf.contains("volumetric_fog_density"), "brouillard volumétrique piloté (Ultra seulement : activé par le profil)")
	check(VisualEffects.PROFILES.ultra.ssr and VisualEffects.PROFILES.ultra.volumetric_fog and not VisualEffects.PROFILES.mobile.ssr,
		"reflets SSR et brouillard volumétrique réservés à Ultra")

func _night_lights() -> void:
	var b := NightLights.BUDGET
	var mob: Dictionary = b.mobile
	# rame : phare + 4 plafonniers de tunnel (LineView)
	check(int(mob.street) + int(mob.cars) + 1 + 4 <= 8, "Mobile : au plus 8 lumières dynamiques avec la rame (%d)" % (int(mob.street) + int(mob.cars) + 5))
	check(int(b.ultra.street) >= int(b.high.street) and int(b.high.street) >= int(b.mobile.street) and int(b.ultra.cars) >= int(b.high.cars),
		"budgets de lumières décroissants Ultra ≥ Haut ≥ Mobile")
	var v := FakeView.new(); root.add_child(v)
	v.cam = Camera3D.new(); v.add_child(v.cam)
	v.day_night = DayNight.new(); v.add_child(v.day_night); v.day_night.setup(v)
	var xfs: Array = []
	for i in 30: xfs.append(Transform3D(Basis.IDENTITY, Vector3(float(i) * 12.0 - 60.0, 0.1, -20.0)))
	StreetProps.halo_sets.clear()
	v.add_child(StreetProps.instances(StreetProps.HALO, xfs))
	var nl := NightLights.new(); v.add_child(nl); nl.setup(v, "high")
	v.day_night.set_hour(23.0)
	for i in 40: await process_frame
	await create_timer(0.8).timeout
	check(nl.sources.size() == 30, "lampadaires relevés depuis les halos au sol (%d)" % nl.sources.size())
	check(nl.active == int(b.high.street), "nuit : réservoir plein (%d / %d lampadaires)" % [nl.active, int(b.high.street)])
	var lit := 0
	for l in nl.street: if l.visible and l.light_energy > 0.5 and not l.shadow_enabled: lit += 1
	check(lit == int(b.high.street), "lampadaires dynamiques sans ombre, allumés")
	v.day_night.set_hour(13.0)
	await create_timer(0.8).timeout
	check(nl.active == 0, "jour : aucune lumière dynamique de lampadaire")
	nl.set_profile("mobile")
	check(nl.street.size() == int(mob.street) and nl.cars.size() == int(mob.cars), "profil Mobile : réservoir réduit")
	v.queue_free(); await process_frame

func _windscreen() -> void:
	var w := WindscreenRain.new()
	var t0 := WindscreenRain.now() - 0.001
	w.update_wiper(0.016, 0.9, false, -1.0, 0.0, 0.0, 0.0)
	check(w.cleared_since(t0) == 0, "pare-brise : sans balai, aucune zone essuyée")
	w.strength = 0.9
	w.update_wiper(0.016, 0.9, false, 0.0, deg_to_rad(90.0), 0.0, 0.0)
	w.update_wiper(0.016, 0.9, false, deg_to_rad(90.0), deg_to_rad(90.0), 0.0, 0.0)   # balai HD : un aller complet
	check(w.cleared_since(t0) == WindscreenRain.BINS, "balai HD : un aller essuie tous les secteurs")
	check(w.visible, "gouttes visibles sous la pluie")
	var w2 := WindscreenRain.new()
	var t1 := WindscreenRain.now() - 0.001
	for i in 30: w2.update_wiper(0.016, 0.9, true, -1.0, 0.0, 0.0, 0.0)   # balai simulé (rame non HD), ~0,5 s
	check(w2.cleared_since(t1) > 0 and w2.cleared_since(t1) < WindscreenRain.BINS, "balai simulé : secteurs essuyés progressivement")
	w.free(); w2.free()

func _shelters() -> void:
	var nets := ["angers", "nantes", "lyon", "bordeaux", "strasbourg", "montpellier", "grenoble", "idf", "lille", "toulouse"]
	var shapes := {}
	for n in nets:
		var st := StationShelters.style(n)
		check(st.network == n, "abri propre au réseau %s" % n)
		shapes[str(st.roof) + "/" + str(st.supports) + "/" + str(st.frame)] = true
	check(shapes.size() == nets.size(), "dix abris distincts (toiture, porteurs, teinte)")
	var kinds := {}
	for n in StationShelters.doc().networks: kinds[StationShelters.style(n).roof] = true
	check(kinds.size() >= 6, "six formes de toiture au moins (%s)" % ", ".join(kinds.keys()))
	check(StationShelters.style("inconnu").network == "default", "réseau sans fiche : abri par défaut")
	StationShelters.reset()
	var owner := Node3D.new(); root.add_child(owner)
	for n in nets:
		var g := LineView._Geo.new(); var gl := LineView._Geo.new()
		var count := StationShelters.build(owner, g, Vector3.ZERO, Vector3(0, 0, 1), Vector3(1, 0, 0), StationShelters.style(n), "Gare", "A", ["Nord", "Sud"], 2.6, gl)
		var tris := g.v.size() / 3
		check(count >= 10 and tris > 300 and tris < 6000 and gl.v.size() > 0, "%s : abri détaillé (%d éléments, %d triangles, vitrages)" % [n, count, tris])
	check(StationShelters.stats.pids == nets.size() and StationShelters.lights.size() >= nets.size(), "PID et bandeaux LED enregistrés")
	var pid := StationShelters.pid_text("A", ["Avrillé Ardenne", "Angers Roseraie"], 8.0, 17)
	check(pid.split("\n").size() == 2 and pid.contains("min"), "PID : deux directions, minutes")
	var pid2 := StationShelters.pid_text("A", ["Avrillé Ardenne", "Angers Roseraie"], 8.0 + 2.0 / 60.0, 17)
	check(pid != pid2, "PID animé : le décompte évolue")
	StationShelters._t = 0.0
	check(StationShelters.update_boards(Vector3.ZERO, 9.0, 0.1) == nets.size(), "PID proches rafraîchis")
	var bs := StationShelters.facing(Vector3(0.3, 0, -1))
	check(bs.determinant() > 0.99 and bs.z.dot(Vector3(0.3, 0, -1).normalized()) > 0.99, "textes d'abri jamais en miroir")
	owner.queue_free()

func _signals() -> void:
	for a in ["go", "left", "right", "caution", "stop", "inconnu"]:
		var s := SignalView.symbols(a)
		var on := int(s[0]) + int(s[2]) + int(s[3])
		check(on == 1, "R17 %s : un seul symbole allumé" % a)
	check(SignalView.symbols("go")[1] == 0.0 and SignalView.symbols("left")[1] < 0.0 and SignalView.symbols("right")[1] > 0.0, "R17 : barre verticale / oblique selon la direction")
	check(SignalView.symbols("stop")[3] and SignalView.symbols("caution")[2], "R17 : barre horizontale = arrêt, point = arrêt sauf impossibilité")
	for k in ["switch", "terminus", "block", "crossing"]:
		var m := SignalView.r17_body(k)
		check(m.get_surface_count() == 1 and m.surface_get_array_len(0) >= 600, "corps R17 %s détaillé (%d sommets)" % [k, m.surface_get_array_len(0) if m.get_surface_count() > 0 else 0])
	check(SignalView.r17_body("block") == SignalView.r17_body("block"), "corps partagé par type (un maillage)")
	var holder := Node3D.new(); root.add_child(holder)
	var rl := SignalView.road_light(holder, Transform3D.IDENTITY)
	SignalView.set_road_light(rl, true)
	check(rl.red.visible and not rl.green.visible and not rl.amber.visible, "R11 : rouge")
	SignalView.set_road_light(rl, true, true)
	check(rl.amber.visible and not rl.red.visible, "R11 : orange")
	SignalView.set_road_light(rl, false)
	check(rl.green.visible and not rl.red.visible, "R11 : vert")
	holder.queue_free()

func _grass() -> void:
	var pts: Array[Vector3] = []
	for i in 21: pts.append(Vector3(0, 0, -float(i) * 2.0))
	var nrm := TrackView.miter_normals(pts)
	var grassy: Array = []
	for i in 20: grassy.append(i < 10)
	var out: Array = []
	TrackView.grass_tufts(out, pts, nrm, 0.0, 1.435, grassy)
	var on_grass := true; var off_rail := true
	for x in out:
		var p: Vector3 = (x as Transform3D).origin
		if p.z < -20.5: on_grass = false
		if absf(absf(p.x) - 0.7175) < 0.19: off_rail = false
	check(out.size() > 15, "gazon de voie : touffes posées (%d sur 20 m)" % out.size())
	check(on_grass, "touffes seulement sur la plateforme gazonnée")
	check(off_rail, "touffes hors rails et longrines")
	var lv := FileAccess.get_file_as_string("res://src/rendering/line_view.gd")
	check(lv.contains("not DayNight.low_quality else null") and lv.contains("visibility_range_end = reach"), "Mobile : texture seule ; PC : touffes à portée courte")
