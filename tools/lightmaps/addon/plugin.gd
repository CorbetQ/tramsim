@tool
extends EditorPlugin
## Cuisson LightmapGI sans intervention (refonte P1) : activé temporairement par tools/lightmaps/bake.sh.
## TRAMSIM_BAKE = liste de scènes res://…_bake.tscn séparées par des virgules. Pour chaque scène : ouverture,
## sélection du LightmapGI, clic sur « Bake Lightmaps » (bouton du greffon LightmapGI de l'éditeur), attente des
## données, enregistrement. Nécessite le RenderingDevice (Vulkan : GPU ou lavapipe sous xvfb).
var scenes: PackedStringArray

func _enter_tree() -> void:
	var v := OS.get_environment("TRAMSIM_BAKE")
	if v == "": return
	scenes = v.split(",", false)
	_run.call_deferred()

func _frames(n: int) -> void:
	for i in n: await get_tree().process_frame

func _bake_button() -> Button:
	for b in EditorInterface.get_base_control().find_children("*", "Button", true, false):
		var t := (b as Button).text.to_lower()
		if t.contains("bake lightmap") or t.contains("précalculer les lightmaps") or t.contains("lightmaps"):
			if (b as Button).is_visible_in_tree(): return b
	return null

func _run() -> void:
	await _frames(30)
	var rc := 0
	for path in scenes:
		EditorInterface.open_scene_from_path(path)
		await _frames(20)
		var root := EditorInterface.get_edited_scene_root()
		var lm: LightmapGI = root.get_node_or_null("LightmapGI") if root else null
		if lm == null: printerr("BAKE|%s|LightmapGI absent" % path); rc = 1; continue
		EditorInterface.get_selection().clear(); EditorInterface.get_selection().add_node(lm)
		EditorInterface.set_main_screen_editor("3D")
		await _frames(20)
		var b := _bake_button()
		if b == null: printerr("BAKE|%s|bouton de cuisson introuvable" % path); rc = 1; continue
		var t0 := Time.get_ticks_msec()
		b.pressed.emit()
		while lm.light_data == null and Time.get_ticks_msec() - t0 < 3600000: await _frames(10)
		if lm.light_data == null: printerr("BAKE|%s|échec ou délai dépassé" % path); rc = 1; continue
		EditorInterface.save_scene()
		print("BAKE|%s|ok|%.0f s" % [path, (Time.get_ticks_msec() - t0) / 1000.0])
	await _frames(10)
	get_tree().quit(rc)
