extends SceneTree
## godot --headless --path . -s tests/test_ai_trams.gd
## Rames IA du mode mission : 30 min simulées dans trois villes, sans collision ni
## chevauchement (sections exclusives), avec circulation effective (arrêts en station,
## retournements) et sans bloquer indéfiniment le joueur.
var fails := 0
func check(c: bool, m: String) -> void:
	if not c: fails += 1; printerr("ECHEC: ", m)
	else: print("ok: ", m)

func _init() -> void:
	var vehicle := VehicleLibrary.citadis_302_hybride()
	var cities := OS.get_environment("AI_CITIES").split(",", false) if OS.get_environment("AI_CITIES") != "" else PackedStringArray(["angers", "grenoble", "bordeaux"])
	var minutes := float(OS.get_environment("AI_MINUTES")) if OS.get_environment("AI_MINUTES") != "" else 30.0
	for c in cities: _run(c, vehicle, minutes * 60.0)
	check(AiTrams.headway_s(8.0) < AiTrams.headway_s(14.0) and AiTrams.headway_s(14.0) < AiTrams.headway_s(22.5), "fréquences : pointe < creuse < soirée")
	print("TOTAL_ECHECS|%d" % fails)
	quit(1 if fails > 0 else 0)

func _run(city: String, vehicle: VehicleProfile, duration: float) -> void:
	var m: Dictionary = {}
	for x in MissionCatalog.for_city(city):
		if str(x.type) == "service": m = x; break
	check(not m.is_empty(), "%s : mission de service" % city)
	if m.is_empty(): return
	var s := MissionCatalog.create_session(m, vehicle)
	var ai := AiTrams.create(s, city, float(m.get("start_hour", 12.0)), 10)
	var spawned := ai.trams.size()
	if OS.get_environment("AI_TRACE") != "": ai.message.connect(func(t): print("    [%d s] %s" % [s.time_s, t]))
	check(spawned >= 3, "%s : %d rames IA en service (plafond 10)" % [city, spawned])
	var player := Autopilot.new(); player.enabled = true; player.line = str(m.line)
	var overlap := 0
	var start_pos := {}
	for t in ai.trams: start_pos[t.train_id] = 0.0
	var travelled := 0.0
	var served := 0
	var turnbacks := 0
	var dt := 0.1
	var t0 := Time.get_ticks_msec()
	var player_wait := 0.0
	var player_wait_max := 0.0
	while s.time_s < duration:
		if not s.finished:
			var n := player.control(s, dt)
			if s.interlocking.awaiting_reverse() and s.interlocking.can_reverse(s): s.reverse()
			s.tick(dt, n)
			player_wait = player_wait + dt if s.phys.speed < 0.05 and player.state != "dwell" else 0.0
			player_wait_max = maxf(player_wait_max, player_wait)
		else:
			s.time_s += dt
			ai.step(dt, s)
		# Sections exclusives : chaque rame occupe toutes les arêtes sous elle, et elle seule.
		for t in ai.trams:
			for e in t.route:
				if s.net.graph.edges[e].occupied_by != t.train_id: overlap += 1
			for e in s.route:
				if e in t.route: overlap += 1
		if roundi(s.time_s / dt) % 50 == 0:
			for t in ai.trams:
				travelled += t.phys.speed * 5.0
	for t in ai.trams:
		served += t.driver.stations_served; turnbacks += t.turnbacks
	var ms := Time.get_ticks_msec() - t0
	print("  %s : %d rames, %.0f km parcourus, %d arrêts, %d retournements, %d retraits, joueur '%s' attente max %d s, %d ms" % [city, ai.trams.size(), travelled / 1000.0, served, turnbacks, ai.removed, s.scorer.fail_reason, roundi(player_wait_max), ms])
	check(ai.collisions == 0, "%s : aucune collision entre rames" % city)
	check(overlap == 0, "%s : aucun chevauchement de sections" % city)
	check(travelled > 20000.0, "%s : les rames IA circulent (%.0f km)" % [city, travelled / 1000.0])
	check(served >= ai.trams.size(), "%s : arrêts en station desservis par les rames IA" % city)
	check(not s.scorer.fail_reason.contains("Collision"), "%s : le joueur n'est jamais percuté" % city)
	check(player_wait_max < AiTrams.YIELD_S + 120.0, "%s : le joueur n'est pas bloqué indéfiniment" % city)
	check(ai.removed <= spawned * 2, "%s : régulation limitée (%d retraits)" % [city, ai.removed])
	for t in ai.trams.duplicate(): t.remove()
