extends SceneTree
## Refonte P0 : profils de qualité Ultra / Haut / Mobile / Repli (VisualEffects), choix automatique par renderer et
## GPU, plafonnement par le renderer actif, réglages effectivement posés ; chaîne de couleur (AgX, ciel, brouillard
## relatif au sol) de DayNight ; renderers et export (project.godot, export_presets.cfg). Sans rendu (--headless) :
## les renderers sont simulés par l'argument `method` d'apply_profile.
var fails := 0

func check(c: bool, m: String) -> void:
	if c: print("ok: ", m)
	else: fails += 1; printerr("ECHEC: ", m)

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var D := RenderingDevice.DEVICE_TYPE_DISCRETE_GPU
	var I := RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU
	check(VisualEffects.auto_profile("forward_plus", D, false) == "ultra", "auto : Forward+ GPU dédié → ultra")
	check(VisualEffects.auto_profile("forward_plus", I, false) == "high", "auto : Forward+ iGPU (Windows ARM64) → haut")
	check(VisualEffects.auto_profile("mobile", I, true) == "mobile", "auto : renderer Mobile → mobile")
	check(VisualEffects.auto_profile("gl_compatibility", D, false) == "fallback", "auto : Compatibility → repli")
	check(VisualEffects.effective_profile("ultra", "gl_compatibility", D) == "fallback", "ultra demandé en Compatibility → repli")
	check(VisualEffects.effective_profile("ultra", "mobile", I) == "mobile", "ultra demandé sur renderer Mobile → mobile")
	check(VisualEffects.effective_profile("fallback", "forward_plus", D) == "fallback", "repli forcé en Forward+ respecté")
	check(VisualEffects.effective_profile("cinematic", "forward_plus", D) == "ultra" and VisualEffects.normalize_id("economy") == "mobile", "anciens identifiants 0.13 convertis")
	check(VisualEffects.normalize_id("n'importe quoi") == "auto", "identifiant inconnu → auto")
	for id in VisualEffects.ORDER: check(VisualEffects.LABELS.has(id) and VisualEffects.PROFILES.has(id), "profil %s décrit et libellé (Réglages)" % id)

	var budgets: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://docs/refonte-visuelle/budgets.json"))
	var bp := {"ultra": "ultra_pc", "high": "high", "mobile": "mobile", "fallback": "fallback"}
	for id in VisualEffects.ORDER:
		var p: Dictionary = VisualEffects.PROFILES[id]
		var b: Dictionary = budgets.profiles[bp[id]]
		check(str(b.renderer) == str(p.renderer), "%s : renderer %s conforme à budgets.json" % [id, p.renderer])
		if b.has("shadow_atlas"): check(int(p.shadow_size) == int(b.shadow_atlas), "%s : atlas d'ombres %d" % [id, int(p.shadow_size)])

	# Application par profil, dans le renderer visé
	var vp := SubViewport.new(); root.add_child(vp)
	var host := Node3D.new(); vp.add_child(host)
	var dn := DayNight.new(); host.add_child(dn); dn.setup(host)
	var r := VisualEffects.apply_profile("ultra", dn.env, dn.sun, vp, "forward_plus")
	check(r.sdfgi and r.ssao and r.ssil and r.ssr and r.volumetric_fog, "ultra : SDFGI, SSAO, SSIL, SSR, brouillard volumétrique")
	check(r.taa and r.pcss and r.shadow_size == 4096 and r.shadow_soft >= 3, "ultra : TAA, PCSS, ombres 4096 filtrées")
	r = VisualEffects.apply_profile("high", dn.env, dn.sun, vp, "forward_plus")
	check(r.ssao and not r.sdfgi and not r.ssil and not r.ssr and not r.volumetric_fog and r.fog, "haut : SSAO seul, brouillard de hauteur")
	check(r.scaling == "fsr2" and r.scale < 1.0 and not r.taa and r.shadow_size == 2048, "haut : FSR2 %.2f, ombres 2048" % r.scale)
	r = VisualEffects.apply_profile("mobile", dn.env, dn.sun, vp, "mobile")
	check(not (r.sdfgi or r.ssao or r.ssil or r.ssr or r.volumetric_fog), "mobile : aucun effet Forward+ (renderer Mobile)")
	check(r.msaa == Viewport.MSAA_2X and r.scaling == "fsr" and is_equal_approx(r.scale, 0.75), "mobile : MSAA 2x + FSR1 0,75")
	r = VisualEffects.apply_profile("fallback", dn.env, dn.sun, vp, "gl_compatibility")
	check(r.fxaa and r.scaling == "bilinear" and r.scale == 1.0 and not r.taa and not r.pcss, "repli : FXAA, pleine résolution, pas de TAA ni PCSS")
	r = VisualEffects.apply_profile("ultra", dn.env, dn.sun, vp, "gl_compatibility")
	check(not (r.sdfgi or r.ssao or r.ssr or r.volumetric_fog or r.taa) and r.scaling == "bilinear", "ultra forcé en Compatibility : aucun effet indisponible activé")

	# Chaîne de couleur et brouillard (DayNight)
	check(dn.env.tonemap_mode == Environment.TONE_MAPPER_AGX, "tonemapper AgX")
	check(dn.env.ambient_light_source == Environment.AMBIENT_SOURCE_SKY and dn.env.background_mode == Environment.BG_SKY, "ambiance issue du ciel")
	check(dn.env.glow_enabled and dn.env.glow_hdr_threshold >= 1.0, "glow léger (sources émissives seulement)")
	dn.set_hour(13.0); var e_day := dn.env.tonemap_exposure
	dn.set_hour(23.5); var e_night := dn.env.tonemap_exposure
	check(e_day > 0.5 and e_night > e_day, "exposition jour %.2f / nuit %.2f" % [e_day, e_night])
	for i in 200: dn.set_ground(-17.0)   # lissage d'une image à l'autre
	check(dn.env.fog_enabled and absf(dn.env.fog_height + 27.0) < 0.05 and dn.env.fog_height_density > 0.0, "brouillard de hauteur relatif au sol (Angers −17 m)")
	var sky_code := FileAccess.get_file_as_string("res://src/rendering/shaders/sky.gdshader")
	check(sky_code.contains("airmass") and sky_code.contains("Henyey"), "ciel physique simplifié (masse d'air, Mie)")
	check(dn.sky_mat.get_shader_parameter("top_color") is Color, "teintes du ciel pilotables (WeatherView)")

	# Renderers et export
	var cfg := ConfigFile.new(); cfg.load("res://project.godot")
	check(cfg.get_value("rendering", "renderer/rendering_method") == "forward_plus", "PC : Forward+")
	check(cfg.get_value("rendering", "renderer/rendering_method.mobile") == "mobile", "Android : renderer Mobile")
	check(cfg.get_value("rendering", "rendering_device/fallback_to_opengl3", false) == true, "repli automatique Compatibility (OpenGL 3)")
	check(cfg.get_value("rendering", "textures/vram_compression/import_etc2_astc") == true and cfg.get_value("rendering", "textures/vram_compression/import_s3tc_bptc") == true, "compression VRAM ETC2/ASTC + S3TC/BPTC")
	var ex := ConfigFile.new(); ex.load("res://export_presets.cfg")
	for i in 3:
		var sec := "preset.%d.options" % i
		check(ex.get_value(sec, "shader_baker/enabled", false) == true, "%s : shader baker activé" % ex.get_value("preset.%d" % i, "name"))
		if ex.get_value("preset.%d" % i, "platform") == "Windows Desktop":
			check(ex.get_value(sec, "texture_format/s3tc_bptc", false) == true, "%s : S3TC/BPTC" % ex.get_value("preset.%d" % i, "name"))
	vp.queue_free()
	await process_frame
	print("TOTAL_ECHECS|%d" % fails)
	quit(1 if fails > 0 else 0)
