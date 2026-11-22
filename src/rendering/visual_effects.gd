class_name VisualEffects
extends Node3D
## Profils de qualité (refonte P0, docs/CDC_REFONTE_VISUELLE.md §2.2, budgets dans docs/refonte-visuelle/budgets.json) :
##   ultra    : Forward+, GPU dédié — SDFGI, SSAO + SSIL, SSR, brouillard volumétrique, ombres 4096 + PCSS, TAA.
##   high     : Forward+, iGPU / Windows ARM64 — SSAO demi-résolution, brouillard de hauteur, ombres 2048, FSR2.
##   mobile   : renderer Mobile (Android Vulkan) — MSAA 2x + FSR1 0,75, ombres 2048, glow Mobile.
##   fallback : Compatibility (GLES3, repli automatique) — FXAA, ombres 2048, mêmes matériaux PBR.
## Choix automatique selon le renderer actif et le type de GPU (`auto_profile`) ; le joueur peut forcer un profil dans
## les Réglages (`save.settings.visual_profile`, « auto » par défaut). Un profil plus exigeant que le renderer actif
## est ramené au profil que ce renderer sait rendre (`effective_profile`) : aucune fonction indisponible n'est activée.
const ORDER := ["fallback", "mobile", "high", "ultra"]
const LABELS := {"auto": "Automatique", "ultra": "Ultra (PC, GPU dédié)", "high": "Haut (PC iGPU, Windows ARM)",
	"mobile": "Mobile (Android Vulkan)", "fallback": "Repli (OpenGL / Compatibility)"}
## Anciens identifiants (0.13) : economy/balanced/cinematic.
const LEGACY := {"economy": "mobile", "balanced": "high", "cinematic": "ultra"}
const PROFILES := {
	"ultra": {"renderer": "forward_plus", "sdfgi": true, "ssao": true, "ssao_half": false, "ssil": true, "ssr": true,
		"volumetric_fog": true, "shadow_size": 4096, "shadow_soft": 3, "pcss": true, "aa": "taa", "msaa": 0,
		"scaling": "bilinear", "scale": 1.0, "glow": 0.26, "reflection": true, "blur": 0.0, "shadow_distance": 220.0},
	"high": {"renderer": "forward_plus", "sdfgi": false, "ssao": true, "ssao_half": true, "ssil": false, "ssr": false,
		"volumetric_fog": false, "shadow_size": 2048, "shadow_soft": 2, "pcss": false, "aa": "fsr2", "msaa": 0,
		"scaling": "fsr2", "scale": 0.77, "glow": 0.2, "reflection": true, "blur": 0.0, "shadow_distance": 170.0},
	"mobile": {"renderer": "mobile", "sdfgi": false, "ssao": false, "ssao_half": true, "ssil": false, "ssr": false,
		"volumetric_fog": false, "shadow_size": 2048, "shadow_soft": 1, "pcss": false, "aa": "msaa", "msaa": 1,
		"scaling": "fsr", "scale": 0.75, "glow": 0.18, "reflection": true, "blur": 0.0, "shadow_distance": 110.0},
	"fallback": {"renderer": "gl_compatibility", "sdfgi": false, "ssao": false, "ssao_half": true, "ssil": false, "ssr": false,
		"volumetric_fog": false, "shadow_size": 2048, "shadow_soft": 1, "pcss": false, "aa": "fxaa", "msaa": 0,
		"scaling": "bilinear", "scale": 1.0, "glow": 0.18, "reflection": false, "blur": 0.0, "shadow_distance": 140.0},
}
## Rang maximal rendu par chaque renderer.
const RENDERER_CAP := {"forward_plus": "ultra", "mobile": "mobile", "gl_compatibility": "fallback", "dummy": "fallback"}

var profile := "high"
var requested := "auto"
var applied: Dictionary = {}
var view: LineView
var probe: ReflectionProbe
var _anchor := Vector3.INF
var _cooldown := 0.0
var _last_basis := Basis.IDENTITY
var _has_camera := false

static func renderer() -> String:
	return RenderingServer.get_current_rendering_method()

## Profil conseillé pour la plateforme et le GPU actifs.
static func auto_profile(method: String = "", adapter_type: int = -1, mobile_os: bool = OS.has_feature("mobile")) -> String:
	if method == "": method = renderer()
	if adapter_type < 0: adapter_type = RenderingServer.get_video_adapter_type()
	if method == "gl_compatibility" or method == "dummy" or method == "": return "fallback"
	if method == "mobile" or mobile_os: return "mobile"
	return "ultra" if adapter_type == RenderingDevice.DEVICE_TYPE_DISCRETE_GPU else "high"

static func normalize_id(id: String) -> String:
	id = LEGACY.get(id, id)
	return id if PROFILES.has(id) or id == "auto" else "auto"

## Profil réellement appliqué : demande du joueur (ou auto) bornée par ce que le renderer actif sait rendre.
static func effective_profile(id: String, method: String = "", adapter_type: int = -1) -> String:
	if method == "": method = renderer()
	id = normalize_id(id)
	if id == "auto": id = auto_profile(method, adapter_type)
	var cap: String = RENDERER_CAP.get(method, "fallback")
	return ORDER[mini(ORDER.find(id), ORDER.find(cap))]

## Applique un profil à un environnement, un soleil et une fenêtre ; renvoie les réglages effectivement posés.
static func apply_profile(id: String, env: Environment, sun: DirectionalLight3D, vp: Viewport, method: String = "") -> Dictionary:
	if method == "": method = renderer()
	var p: Dictionary = PROFILES[id]
	var fplus := method == "forward_plus"
	var r := {"profile": id, "renderer": method}
	if env != null:
		env.sdfgi_enabled = fplus and bool(p.sdfgi)
		if env.sdfgi_enabled:
			env.sdfgi_cascades = 4; env.sdfgi_min_cell_size = 0.25; env.sdfgi_use_occlusion = true
			env.sdfgi_read_sky_light = true; env.sdfgi_energy = 1.0; env.sdfgi_y_scale = Environment.SDFGI_Y_SCALE_75_PERCENT
		env.ssao_enabled = fplus and bool(p.ssao)
		if env.ssao_enabled:
			env.ssao_radius = 1.2; env.ssao_intensity = 1.6; env.ssao_power = 1.4; env.ssao_detail = 0.5
			env.ssao_light_affect = 0.0; env.ssao_ao_channel_affect = 1.0
		env.ssil_enabled = fplus and bool(p.ssil)
		if env.ssil_enabled: env.ssil_radius = 4.0; env.ssil_intensity = 0.8
		env.ssr_enabled = fplus and bool(p.ssr)
		if env.ssr_enabled: env.ssr_max_steps = 48; env.ssr_fade_in = 0.15; env.ssr_fade_out = 2.0
		env.volumetric_fog_enabled = fplus and bool(p.volumetric_fog)
		if env.volumetric_fog_enabled:
			env.volumetric_fog_density = 0.0025; env.volumetric_fog_length = 96.0
			env.volumetric_fog_albedo = Color(0.9, 0.92, 0.96); env.volumetric_fog_sky_affect = 0.0
			env.volumetric_fog_ambient_inject = 0.4; env.volumetric_fog_temporal_reprojection_enabled = true
		env.glow_enabled = true
		r.merge({"sdfgi": env.sdfgi_enabled, "ssao": env.ssao_enabled, "ssil": env.ssil_enabled, "ssr": env.ssr_enabled,
			"volumetric_fog": env.volumetric_fog_enabled, "fog": env.fog_enabled, "tonemap": env.tonemap_mode})
	if fplus:
		RenderingServer.environment_set_ssao_quality(RenderingServer.ENV_SSAO_QUALITY_HIGH if not bool(p.ssao_half) else RenderingServer.ENV_SSAO_QUALITY_LOW,
			bool(p.ssao_half), 0.5, 2, 50.0, 300.0)
	RenderingServer.directional_shadow_atlas_set_size(int(p.shadow_size), OS.has_feature("mobile"))
	RenderingServer.directional_soft_shadow_filter_set_quality(int(p.shadow_soft))
	RenderingServer.positional_soft_shadow_filter_set_quality(int(p.shadow_soft))
	r.shadow_size = int(p.shadow_size); r.shadow_soft = int(p.shadow_soft)
	if sun != null:
		sun.light_angular_distance = 0.53 if fplus and bool(p.pcss) else 0.0
		sun.directional_shadow_max_distance = float(p.shadow_distance)
		r.pcss = sun.light_angular_distance > 0.0
	if vp != null:
		var aa := str(p.aa)
		vp.use_taa = fplus and aa == "taa"
		vp.msaa_3d = int(p.msaa) as Viewport.MSAA
		vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if aa == "fxaa" else Viewport.SCREEN_SPACE_AA_DISABLED
		var mode := str(p.scaling)
		if mode == "fsr2" and not fplus: mode = "fsr"
		if mode == "fsr" and method == "gl_compatibility": mode = "bilinear"
		vp.scaling_3d_mode = {"bilinear": Viewport.SCALING_3D_MODE_BILINEAR, "fsr": Viewport.SCALING_3D_MODE_FSR,
			"fsr2": Viewport.SCALING_3D_MODE_FSR2}[mode]
		vp.scaling_3d_scale = float(p.scale) if mode != "bilinear" else 1.0
		r.merge({"taa": vp.use_taa, "msaa": vp.msaa_3d, "fxaa": vp.screen_space_aa == Viewport.SCREEN_SPACE_AA_FXAA,
			"scaling": mode, "scale": vp.scaling_3d_scale})
	return r

func setup(line: LineView, name_: String) -> void:
	view = line
	requested = normalize_id(name_)
	profile = effective_profile(requested)
	var params: Dictionary = PROFILES[profile]
	var dn: DayNight = view.day_night
	applied = apply_profile(profile, dn.env, dn.sun, get_viewport())
	set_process(bool(params.reflection) or float(params.blur) > 0)
	view.speed_material.set_shader_parameter("bloom_amount", params.glow if renderer() == "gl_compatibility" else 0.0)
	view.speed_material.set_shader_parameter("motion_amount", params.blur)
	if params.reflection:
		probe = ReflectionProbe.new(); probe.size = Vector3(42, 16, 42); probe.max_distance = 55
		probe.update_mode = ReflectionProbe.UPDATE_ONCE; probe.box_projection = true
		probe.ambient_mode = ReflectionProbe.AMBIENT_DISABLED
		add_child(probe)
	view.headlight.distance_fade_enabled = true; view.headlight.distance_fade_begin = 65; view.headlight.distance_fade_length = 20
	print("VISUAL|profil=%s|demande=%s|renderer=%s" % [profile, requested, renderer()])

func _process(dt: float) -> void:
	if view == null or view.cam == null: return
	_cooldown = maxf(0, _cooldown - dt)
	var p := view.cam.global_position
	# One local cubemap, recaptured on substantial movement, never six scene passes every frame.
	if probe != null and _cooldown <= 0 and (not _anchor.is_finite() or p.distance_to(_anchor) > 60):
		probe.position = p; _anchor = p; _cooldown = 12
		probe.update_mode = ReflectionProbe.UPDATE_ONCE
	var basis := view.cam.global_basis
	var motion := Vector2.ZERO
	if _has_camera:
		motion = Vector2((_last_basis.z - basis.z).dot(basis.x), (_last_basis.z - basis.z).dot(basis.y))
		if motion.length() > .12: motion = Vector2.ZERO # teleport/cut: no smear
	view.speed_material.set_shader_parameter("camera_motion", motion.limit_length(.025))
	_last_basis = basis; _has_camera = true
