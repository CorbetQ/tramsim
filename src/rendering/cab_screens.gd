class_name CabScreens
extends Node
## Écrans du pupitre (`screen_*`) : un SubViewport par écran, texture appliquée en émissif au quad.
## Contenus : speed, notch, next_stop, signal, info. Rafraîchis à 5 Hz (texte), rendu à la demande.

const DEFAULT_PX := Vector2i(256, 160)
var viewports: Dictionary = {}   # contenu -> SubViewport
var labels: Dictionary = {}      # contenu -> Array[Label]
var lamp: Dictionary = {}        # contenu -> ColorRect (signal)
var _t := 0.0
var last: Dictionary = {}        # contenu -> texte affiché (tests)

func setup(model: Node, specs: Dictionary) -> void:
	for mi in model.find_children("screen_*", "MeshInstance3D", true, false):
		var key := str(mi.name).trim_prefix("screen_")
		var spec: Dictionary = specs.get(str(mi.name), {})
		var px: Array = spec.get("px", [DEFAULT_PX.x, DEFAULT_PX.y])
		var sv := SubViewport.new(); sv.name = "SV_" + key
		sv.size = Vector2i(int(px[0]), int(px[1])); sv.transparent_bg = false; sv.disable_3d = true
		sv.render_target_update_mode = SubViewport.UPDATE_ONCE
		add_child(sv)
		var bg := ColorRect.new(); bg.color = Color(0.07, 0.10, 0.13); bg.set_anchors_preset(Control.PRESET_FULL_RECT); sv.add_child(bg)
		var box := VBoxContainer.new(); box.set_anchors_preset(Control.PRESET_FULL_RECT); box.alignment = BoxContainer.ALIGNMENT_CENTER
		sv.add_child(box)
		var ls: Array = []
		var lines := 3 if key == "info" else 2
		for i in lines:
			var l := Label.new(); l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			l.add_theme_font_size_override("font_size", int(px[1] * (0.36 if i == 0 and not key in ["info", "signal", "next_stop"] else 0.17)))
			l.add_theme_color_override("font_color", Color(0.55, 0.95, 1.0) if i == 0 else Color(0.85, 0.9, 0.9))
			l.clip_text = true; box.add_child(l); ls.append(l)
		if key == "signal":
			var c := ColorRect.new(); c.custom_minimum_size = Vector2(px[1] * 0.3, px[1] * 0.3); c.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			box.add_child(c); box.move_child(c, 0); lamp[key] = c
		labels[key] = ls; viewports[key] = sv
		var m := StandardMaterial3D.new(); m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_texture = sv.get_texture(); m.emission_enabled = true; m.emission_texture = sv.get_texture(); m.emission_energy_multiplier = 0.6
		(mi as MeshInstance3D).material_override = m

func refresh(d: Dictionary, dt: float) -> void:
	_t -= dt
	if _t > 0.0 and dt > 0.0: return
	_t = 0.2
	for key in labels:
		var texts := _texts(str(key), d)
		var ls: Array = labels[key]
		var changed := false
		for i in ls.size():
			var t := str(texts[i]) if i < texts.size() else ""
			if (ls[i] as Label).text != t: (ls[i] as Label).text = t; changed = true
		if lamp.has(key): (lamp[key] as ColorRect).color = d.get("signal_color", Color(0.1, 0.9, 0.3))
		last[key] = " / ".join(texts)
		if changed: (viewports[key] as SubViewport).render_target_update_mode = SubViewport.UPDATE_ONCE

static func _texts(key: String, d: Dictionary) -> Array:
	var v := roundi(float(d.get("speed_kmh", 0.0)))
	var lim := roundi(float(d.get("limit_kmh", 0.0)))
	var n := float(d.get("notch", 0.0))
	var cran := ("T%d" % roundi(n * 4.0)) if n > 0.01 else (("URG" if n <= -0.99 else "F%d" % roundi(-n * 4.0)) if n < -0.01 else "N")
	var stop := str(d.get("next_stop", "—"))
	var dist := float(d.get("distance_m", -1.0))
	var dist_t := ("%d m" % roundi(dist)) if dist >= 15.0 else ("à quai" if dist >= 0.0 else "")
	match key:
		"speed": return ["%d km/h" % v, "limite %d" % lim]
		"notch": return [cran, "%d %%" % roundi(absf(n) * 100.0)]
		"next_stop": return [stop, dist_t]
		"signal": return [str(d.get("signal", "—")), ""]
		_: return ["%d km/h  %s" % [v, cran], stop + ("  " + dist_t if dist_t != "" else ""), str(d.get("signal", ""))]
