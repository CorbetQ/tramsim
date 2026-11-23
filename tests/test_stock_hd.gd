extends SceneTree
## Rames HD (P2) : manifeste valide, nœuds ctl_* pour chaque action de src/input, LOD conformes aux budgets
## §5.2, bascule LOD, animations (portes côté quai, pantographe, essuie-glace, manipulateur), émissifs,
## girouette, cabine cliquable, écrans en SubViewport. Modèles réels s'ils sont livrés, sinon modèle de test.
var fails := 0
func check(c: bool, m: String) -> void:
	if not c: fails += 1; printerr("ECHEC: ", m)
	else: print("ok: ", m)

const OUT := "user://stock_hd_test"
const VARIANTS := ["angers__citadis_x05", "nantes__citadis_x05_nantes", "angers__citadis_302"]

func _initialize() -> void: run.call_deferred()

func _livery(id: String) -> Dictionary:
	var e := StockCatalog.find(id)
	return TramModel.livery_for({"source_id": e.network, "id": e.network + "_1", "destination": "Test Terminus"}, e)

func _moved(a: Transform3D, b: Transform3D) -> bool:
	return a.origin.distance_to(b.origin) > 0.005 or not a.basis.is_equal_approx(b.basis)

func run() -> void:
	# --- actions de conduite : une touche et un nœud ctl_* chacune, sans doublon
	var keys := {}; var nodes := {}
	for a in CabActions.actions():
		check(CabActions.node_for(a).begins_with("ctl_"), "action %s : nœud %s" % [a, CabActions.node_for(a)])
		for k in CabActions.ACTIONS[a].keys:
			check(not keys.has(k), "touche %d unique (%s)" % [k, a]); keys[k] = a
		nodes[CabActions.node_for(a)] = a
	check(CabActions.action_for_node("ctl_bell") == "horn" and CabActions.action_for_node("traction_lever", {"traction_lever": "ctl_notch"}) == "notch", "nœuds supplémentaires et alias")
	var main_src := FileAccess.get_file_as_string("res://src/ui/main.gd")
	for a in CabActions.actions(): check(main_src.contains('"%s":' % a), "main.gd : action %s liée (cab_action)" % a)
	# --- modèles réels du modélisateur (s'ils existent)
	StockHD.manifest_path = StockHD.MANIFEST; StockHD.reset_cache()
	var real: Dictionary = StockHD.manifest().get("variants", {})
	if real.is_empty(): print("info: manifeste réel absent (", StockHD.MANIFEST, ") : modèle de test seul")
	for vid in real:
		StockHD.enabled = false
		var ref := TramModel.build_rig(_livery(vid))
		StockHD.enabled = true
		var err := StockHD.check(vid, ref)
		check(err.is_empty(), "modèle réel %s conforme %s" % [vid, ", ".join(err)])
		for m in ref.modules: m.free()
	# --- modèle de test minimal conforme au schéma
	var fx = load("res://tests/fixtures/stock_hd_fixture.gd").new()
	var entries := {}
	var refs := {}
	StockHD.enabled = false
	for vid in VARIANTS:
		var liv := _livery(vid)
		var ref := TramModel.build_rig(liv)
		refs[vid] = ref
		entries[vid] = fx.build(OUT, vid, ref, TramModel.plan(TramModel.family_id(str(liv.family))))
		check(not (entries[vid] as Dictionary).is_empty(), "modèle de test %s écrit" % vid)
	StockHD.enabled = true
	StockHD.manifest_path = fx.write_manifest(OUT, entries); StockHD.reset_cache()
	for vid in VARIANTS:
		var err := StockHD.check(vid, refs[vid])
		check(err.is_empty(), "modèle de test %s conforme %s" % [vid, ", ".join(err)])
		for m in (refs[vid] as TramModel.Rig).modules: m.free()
	# validation : un nœud requis manquant → variante refusée
	var broken: Dictionary = (entries[VARIANTS[0]] as Dictionary).duplicate(true)
	broken.modules = [1.0, 2.0]
	StockHD.manifest_path = fx.write_manifest(OUT + "_broken", {VARIANTS[0]: broken}); StockHD.reset_cache()
	var r0 := TramModel.build_rig(_livery(VARIANTS[0]))
	check(r0.hd == null and r0.modules[0].mesh != null, "variante non conforme : repli sur le modèle actuel")
	for m in r0.modules: m.free()
	StockHD.manifest_path = OUT.path_join("manifest.json"); StockHD.reset_cache()
	# --- LOD : distances §5.2, hystérésis, Mobile
	check(StockHD.lod_for(10) == 0 and StockHD.lod_for(50) == 1 and StockHD.lod_for(150) == 2 and StockHD.lod_for(400) == 3, "LOD par distance 25/80/250 m")
	check(StockHD.lod_for(26.0, 0) == 0 and StockHD.lod_for(26.0, 1) == 1, "hystérésis LOD0/LOD1")
	check(StockHD.lod_for(10, -1, true, true) == 1 and StockHD.lod_for(10, -1, true, false) == 0, "rames IA un cran plus bas en Mobile")
	var b := StockHD._budgets()
	check(int(b.LOD0.pc_tris) == 250000 and int(b.LOD3.mobile_tris) == 1000, "budgets lus depuis budgets.json")
	# --- rame HD : bascule LOD, portes, pantographe, émissifs, girouette
	var liv := _livery(VARIANTS[0])
	var rig := TramModel.build_rig(liv)
	check(rig.hd != null, "rame HD appliquée (Angers X05)")
	if rig.hd == null: _end(); return
	var holder := Node3D.new(); root.add_child(holder)
	for m in rig.modules: holder.add_child(m)
	rig.layout_straight()
	var hd = rig.hd
	check(rig.modules[0].mesh == null and hd.lods.size() == 4, "maillage actuel retiré, 4 LOD chargés")
	check(rig.triangles <= 250000, "LOD0 dans le budget PC (%d tris)" % rig.triangles)
	for l in 4:
		hd.set_lod(l)
		var ok := true
		for li in 4:
			for h in hd.lods[li]: ok = ok and (h as Node3D).visible == (li == l)
		check(ok, "bascule LOD%d : un seul niveau visible" % l)
	hd.set_lod(0)
	rig.set_doors(true, "right")
	for i in 40: rig.update(0.1)
	var moved_r := 0; var moved_l := 0
	for d in hd.doors:
		if _moved((d.node as Node3D).transform, d.rest):
			if float(d.side) > 0: moved_r += 1
			else: moved_l += 1
	check(moved_r > 0 and moved_l == 0, "portes : seul le côté quai (droite) s'ouvre (%d/%d)" % [moved_r, moved_l])
	rig.set_doors(false); for i in 40: rig.update(0.1)
	var all_closed := true
	for d in hd.doors: all_closed = all_closed and not _moved((d.node as Node3D).transform, d.rest)
	check(all_closed, "portes refermées")
	check(not hd.pantos.is_empty(), "pantographe articulé présent")
	var head_up: float = (hd.pantos[0].head as Node3D).global_position.y
	rig.set_pantograph(false); for i in 60: rig.update(0.1)
	var head_down: float = (hd.pantos[0].head as Node3D).global_position.y
	check(head_up - head_down > 0.5, "pantographe baissé (LAC→APS) : archet %.2f → %.2f m" % [head_up, head_down])
	rig.set_pantograph(true); for i in 60: rig.update(0.1)
	check(absf((hd.pantos[0].head as Node3D).global_position.y - head_up) < 0.01, "pantographe relevé")
	hd.update({"headlights": 1.0, "interior": true, "wiper": true, "destination": "Angers Roseraie"}, 0.3)
	check(hd.energy("head_A") > 0.0 and hd.energy("head_B") == 0.0, "phares à l'extrémité active seulement")
	check(hd.energy("tail_B") > 0.0 and hd.energy("tail_A") == 0.0, "feux arrière à l'extrémité opposée")
	check(hd.energy("interior") > 0.0, "plafonniers allumés (nuit/tunnel)")
	check(not hd.signs.is_empty() and (hd.signs[0] as Label3D).text == "ANGERS ROSERAIE", "girouette = destination de la mission")
	check(not hd.wipers.is_empty() and _moved((hd.wipers[0].node as Node3D).transform, hd.wipers[0].rest), "essuie-glace en marche (pluie)")
	for i in 30: hd.update({"wiper": false}, 0.1)
	check(not _moved((hd.wipers[0].node as Node3D).transform, hd.wipers[0].rest), "essuie-glace revenu en butée")
	hd.update({"mirrors_folded": true}, 1.0)
	check(not hd.mirrors.is_empty() and _moved((hd.mirrors[0].node as Node3D).transform, hd.mirrors[0].rest), "rétroviseurs rabattus")
	# --- cabine
	var cab: CabView = hd.ensure_cab(rig)
	check(cab != null and cab.camera_node != null, "cabine instanciée avec cam_driver")
	hd.set_cab_visible(true); hd.set_lod(-1)
	var present := {}
	for c in cab.controls: present[c.action] = true
	for a in CabActions.actions(): check(present.has(a), "cabine : %s lié à l'action %s" % [CabActions.node_for(a), a])
	var cam := Camera3D.new(); cam.fov = 62.0; root.add_child(cam); cam.current = true
	cam.global_transform = cab.camera_transform()
	await process_frame
	var notch_c := cab.control("notch")
	cab.update({"notch": 1.0}, 0.0)
	var t1: Transform3D = (notch_c.node as Node3D).transform
	cab.update({"notch": -1.0}, 0.0)
	check(_moved(t1, (notch_c.node as Node3D).transform) and _moved(t1, notch_c.rest), "manipulateur suit le cran réel")
	cab.pulse("doors"); cab.update({}, 0.05)
	var dc := cab.control("doors")
	check(_moved((dc.node as Node3D).transform, dc.rest), "bouton portes enfoncé à l'action")
	for i in 10: cab.update({}, 0.05)
	check(not _moved((dc.node as Node3D).transform, dc.rest), "bouton portes relâché")
	cab.pulse("headlights"); cab.update({}, 0.0)
	check(_moved((cab.control("headlights").node as Node3D).transform, cab.control("headlights").rest), "commutateur phares basculé")
	var visible_ctl := 0; var picked := 0
	var vp := root.get_visible_rect().size
	for c in cab.controls:
		var p: Vector3 = (c.node as Node3D).global_transform * (c.aabb as AABB).get_center()
		if cam.is_position_behind(p): continue
		var sp := cam.unproject_position(p)
		if sp.x < 0 or sp.y < 0 or sp.x > vp.x or sp.y > vp.y: continue
		visible_ctl += 1
		var hit := cab.pick(cam, sp)
		if str(hit.get("action", "")) == c.action: picked += 1
	check(visible_ctl == cab.controls.size(), "toutes les commandes visibles depuis cam_driver (%d/%d)" % [visible_ctl, cab.controls.size()])
	check(picked == visible_ctl and picked > 0, "clic/toucher sur chaque ctl_* → action (%d)" % picked)
	check(cab.pick(cam, Vector2(vp.x * 0.5, 5)).is_empty(), "clic hors pupitre : aucune action")
	cab.update({"speed_kmh": 42.4, "limit_kmh": 50, "notch": 0.5, "next_stop": "Ralliement", "distance_m": 230.0, "signal": "Voie libre"}, 0.0)
	check(str(cab.screens.last.get("speed", "")).begins_with("42 km/h"), "écran vitesse (SubViewport) : " + str(cab.screens.last.get("speed", "")))
	check(str(cab.screens.last.get("info", "")).contains("Ralliement") and str(cab.screens.last.get("info", "")).contains("T2"), "écran info : cran et prochain arrêt")
	check(cab.screens.viewports.size() == 3, "3 écrans screen_* en SubViewport")
	cab.update({"lamps": {"doors": true}}, 0.0)
	check((cab.lamps.doors[0] as StandardMaterial3D).emission_energy_multiplier > 1.0 and (cab.lamps.emergency[0] as StandardMaterial3D).emission_energy_multiplier < 0.1, "voyants pilotés par l'état")
	# matériaux : clearcoat sur la peinture, verre réfléchissant
	var clear := false; var glass := false
	for mi in hd.lods[0][0].find_children("*", "MeshInstance3D", true, false):
		var m := (mi as MeshInstance3D).get_surface_override_material(0)
		if m is BaseMaterial3D and (m as BaseMaterial3D).clearcoat_enabled: clear = true
		if m is BaseMaterial3D and (m as BaseMaterial3D).transparency != BaseMaterial3D.TRANSPARENCY_DISABLED and (m as BaseMaterial3D).metallic > 0.5: glass = true
	check(clear and glass, "livrée en clearcoat, vitrages réfléchissants")
	holder.queue_free(); cam.queue_free()
	await _main_integration()
	_end()

## Jeu complet (Angers A, rame HD de test) : vue cabine HD, touches et clic sur le pupitre.
func _main_integration() -> void:
	root.disable_3d = true
	var main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.save.settings.tutorial_done = true
	var net := NetworkLoader.new(); net.load_file("res://data/networks/angers_a.json")
	main.net_path = "res://data/networks/angers_a.json"
	main.vehicle = VehicleLibrary.default_for(net.meta)
	main.free_mode = false
	main.mission = net.missions()[2]
	main._start(); main.view.day_night.sun.shadow_enabled = false
	for i in 5: await process_frame
	var vid := str(main.view.livery.get("variant_id", ""))
	if main.view.rig.hd == null:
		print("info: matériel par défaut d'Angers A (", vid, ") sans modèle HD : intégration non testée"); main.queue_free(); return
	main.external_cam = false; main._apply_auto_ui()
	for i in 3: await process_frame
	check(main.view.has_hd_cab() and main.view.hd_lod == -1, "vue cabine HD (point d'attache cam_driver)")
	var cab: CabView = main.view.rig.hd.cab
	check(main.view.cam.global_transform.origin.distance_to(cab.camera_transform().origin) < 0.01, "caméra au point conducteur")
	main.weather.set_preset("rain"); main.weather.rain = 0.8; for i in 3: await process_frame
	check(main.view.rig.hd.wiper_amp > 0.0, "pluie : essuie-glace automatique")
	var ev := InputEventKey.new(); ev.keycode = KEY_H; ev.physical_keycode = KEY_H; ev.pressed = true
	main._input(ev)
	check(main.view.headlights_full, "touche H : pleins phares")
	await process_frame
	check(bool(cab.toggles.get("headlights", false)), "commutateur phares suit l'état")
	var dc := cab.control("doors")
	var p: Vector3 = (dc.node as Node3D).global_transform * (dc.aabb as AABB).get_center()
	var sp: Vector2 = main.view.cam.unproject_position(p)
	var was: bool = main.session.doors_open
	var click := InputEventMouseButton.new(); click.button_index = MOUSE_BUTTON_LEFT; click.pressed = true; click.position = sp; click.device = 0
	main._unhandled_input(click)
	await process_frame
	check(main.session.doors_open != was, "clic sur ctl_doors : portes %s" % ("ouvertes" if main.session.doors_open else "fermées"))
	check(cab.pressed("doors"), "retour visuel du bouton portes")
	main._doors(); await process_frame
	main._set_notch(0.75); for i in 20: await process_frame
	var nc := cab.control("notch")
	check(_moved((nc.node as Node3D).transform, nc.rest), "manipulateur de la cabine au cran du HUD")
	main.save.settings["cab_hud_min"] = false; main._toggle_cab_hud()
	var trip: Control = main.get_node_or_null("trip")
	check(trip != null and not trip.visible and main.get_node("alerts").visible, "HUD minimal en cabine (alertes conservées)")
	main._toggle_cab_hud()
	main.queue_free()
	await process_frame

func _end() -> void:
	print("TOTAL_ECHECS|", fails)
	quit(1 if fails > 0 else 0)
