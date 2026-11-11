extends SceneTree
## Vignettes du catalogue : une PNG 512×288 par plan (vue 3/4 avant, fond neutre), livrée du premier réseau de la flotte.
## xvfb-run -a -s "-screen 0 1600x900x24" <godot> --path . --rendering-driver opengl3 --resolution 1600x900 -s tools/render_thumbs.gd
## Option : -- <famille> … pour ne rendre que certaines familles.

const OUT := "res://data/rolling_stock/thumbs/"
const W := 512
const H := 288

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var only := Array(OS.get_cmdline_user_args())
	var sv := SubViewport.new(); sv.size = Vector2i(W * 2, H * 2); sv.own_world_3d = true
	sv.msaa_3d = Viewport.MSAA_4X; sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(sv)
	var world := Node3D.new(); sv.add_child(world)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR; env.background_color = Color("#c9ced3")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; env.ambient_light_color = Color("#dfe4ea"); env.ambient_light_energy = 0.35
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC; env.tonemap_white = 1.6
	var we := WorldEnvironment.new(); we.environment = env; world.add_child(we)
	var sun := DirectionalLight3D.new(); sun.light_energy = 0.85; sun.shadow_enabled = true
	sun.rotation_degrees = Vector3(-52, -35, 0); world.add_child(sun)
	var fill := DirectionalLight3D.new(); fill.light_energy = 0.25; fill.rotation_degrees = Vector3(-20, 150, 0); world.add_child(fill)
	var ground := MeshInstance3D.new(); var pm := PlaneMesh.new(); pm.size = Vector2(200, 200); ground.mesh = pm
	var gm := StandardMaterial3D.new(); gm.albedo_color = Color("#9aa0a6"); gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; ground.material_override = gm
	world.add_child(ground)
	for x in [-0.7175, 0.7175]:   # rails
		var r := MeshInstance3D.new(); var bm := BoxMesh.new(); bm.size = Vector3(0.07, 0.05, 120); r.mesh = bm
		var rm := StandardMaterial3D.new(); rm.albedo_color = Color("#6f757b"); rm.metallic = 0.6; r.material_override = rm
		r.position = Vector3(x, 0.025, 0); world.add_child(r)
	var cam := Camera3D.new(); cam.fov = 30.0; world.add_child(cam); cam.current = true
	var holder := Node3D.new(); world.add_child(holder)
	var liv_all: Dictionary = TramModel._liveries()
	var n := 0
	for id in TramModel.plan_ids():
		if not only.is_empty() and not id in only: continue
		var meta := _meta_for(id, liv_all)
		var liv := TramModel.livery_for(meta, {"family": id})
		var p := TramModel.plan(id)
		var L := minf(float(p.get("length_m", 32.0)), 46.0)
		var rig := TramModel.build_rig(liv, L)
		rig.layout_straight()
		rig.set_pantograph(true); rig.snap()
		for m in rig.modules: holder.add_child(m)
		# 3/4 avant : nez vers -z, caméra devant-côté droit
		var nose := Vector3(0, 1.6, -L * 0.5)
		var d := 3.0 + L * 0.44
		cam.position = nose + Vector3(d * 0.7, 1.8 + L * 0.06, -d * 0.62)
		cam.look_at(Vector3(0, 1.3, -L * 0.22))
		for k in 6: await process_frame
		await RenderingServer.frame_post_draw
		var img := sv.get_texture().get_image()
		img.resize(W, H, Image.INTERPOLATE_LANCZOS)
		img.save_png(ProjectSettings.globalize_path(OUT + id + ".png"))
		print("vignette ", id, " (", meta.get("source_id", "générique"), ")")
		for m in rig.modules: m.free()
		n += 1
	print("vignettes : ", n)
	quit(0)

## Réseau de référence d'une famille : réseau dont c'est la famille principale, sinon premier qui l'a en flotte.
func _meta_for(id: String, liv_all: Dictionary) -> Dictionary:
	var best := ""
	for src in liv_all:
		if str(src).begins_with("_"): continue
		var net: Dictionary = liv_all[src]
		if TramModel.family_id(str(net.get("family", ""))) == id: best = src; break
		if best == "":
			for f in net.get("fleet", []):
				if TramModel.family_id(str(f)) == id: best = src; break
	if id.ends_with("_nantes"): best = "nantes"
	return {"source_id": best, "id": best + "_1", "color": "#2a6db0"} if best != "" else {"source_id": "", "id": "generic"}
