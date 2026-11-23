extends RefCounted
## Modèle HD de test minimal, conforme à docs/refonte-visuelle/stock_manifest.md (caisses en boîtes,
## portes, pantographe articulé, émissifs, girouette, cabine avec toutes les commandes ctl_* et écrans).
## Écrit manifest.json + glb dans `out_dir` (user://…) : sert aux tests et aux captures tant que les
## modèles du modélisateur ne sont pas livrés.

var _mats := {}

func _mat(n: String, c: Color) -> StandardMaterial3D:
	if _mats.has(n): return _mats[n]
	var m := StandardMaterial3D.new(); m.resource_name = n; m.albedo_color = c; m.roughness = 0.5
	_mats[n] = m
	return m

func _box(parent: Node3D, n: String, pos: Vector3, size: Vector3, mat: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var b := BoxMesh.new(); b.size = size
	var am := ArrayMesh.new(); am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, b.get_mesh_arrays())
	am.surface_set_material(0, mat)
	var mi := MeshInstance3D.new(); mi.name = n; mi.mesh = am; mi.position = pos; mi.rotation = rot
	parent.add_child(mi)
	return mi

func _quad(parent: Node3D, n: String, pos: Vector3, size: Vector2, mat: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var q := QuadMesh.new(); q.size = size
	var am := ArrayMesh.new(); am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, q.get_mesh_arrays())
	am.surface_set_material(0, mat)
	var mi := MeshInstance3D.new(); mi.name = n; mi.mesh = am; mi.position = pos; mi.rotation = rot
	parent.add_child(mi)
	return mi

func _node(parent: Node3D, n: String, pos := Vector3.ZERO, rot := Vector3.ZERO) -> Node3D:
	var x := Node3D.new(); x.name = n; x.position = pos; x.rotation = rot; parent.add_child(x)
	return x

func _save(root: Node3D, p: String) -> int:
	for c in root.find_children("*", "", true, false): c.owner = root
	var doc := GLTFDocument.new(); var st := GLTFState.new()
	var e := doc.append_from_scene(root, st)
	if e == OK: e = doc.write_to_filesystem(st, p)
	root.free()
	return e

## Construit la variante `variant_id` pour `rig` (rig du modèle actuel : longueurs de caisses).
func build(out_dir: String, variant_id: String, rig, plan: Dictionary) -> Dictionary:
	var dir := out_dir.path_join("fixture_" + variant_id)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var n: int = rig.modules.size()
	var lens: Array = []
	for i in n: lens.append(snappedf(float(rig.module_lengths[i]), 0.0001))
	var mods: Array = plan.get("modules", [])
	var per_side := 0
	for md in mods: per_side += (md.get("doors", []) as Array).size()
	var panto_mod := n / 2
	var paint := _mat("paint_base", Color.WHITE); var front := _mat("paint_front", Color.WHITE)
	var skirt := _mat("paint_skirt", Color.GRAY); var glass := _mat("glass_side", Color(0.1, 0.1, 0.1))
	var em := _mat("em_lamp", Color(0.2, 0.2, 0.2)); var metal := _mat("metal", Color(0.3, 0.3, 0.32))
	for lod in 4:
		var root := Node3D.new(); root.name = "lod%d" % lod
		var door_n := 0
		for i in n:
			var L := float(lens[i])
			var m := _node(root, "module_%02d" % i)
			_box(m, "body", Vector3(0, 1.85, 0), Vector3(2.4, 2.9, L - 0.25), paint)
			if lod <= 2:
				_box(m, "skirt", Vector3(0, 0.45, 0), Vector3(2.36, 0.5, L - 0.3), skirt)
				_box(m, "windows", Vector3(0, 2.05, 0), Vector3(2.42, 1.0, L - 0.6), glass)
				if i == 0: _box(m, "nose", Vector3(0, 1.8, -L * 0.5 + 0.05), Vector3(2.3, 2.6, 0.2), front)
			if lod <= 1:
				var md: Dictionary = mods[i] if i < mods.size() else {}
				var sc := L / maxf(float(md.get("length_m", L)), 0.01)
				for d in md.get("doors", []):
					var zc := -L * 0.5 + float(d.z_m) * sc
					for side in ["L", "R"]:
						var x := 1.215 * (1.0 if side == "R" else -1.0)
						_box(m, "door_%d_%s_a" % [door_n, side], Vector3(x, 1.5, zc - 0.33), Vector3(0.04, 2.0, 0.64), _mat("paint_door", Color.WHITE))
						_box(m, "door_%d_%s_b" % [door_n, side], Vector3(x, 1.5, zc + 0.33), Vector3(0.04, 2.0, 0.64), _mat("paint_door", Color.WHITE))
					door_n += 1
				if i == panto_mod:
					var base := _node(m, "panto_base", Vector3(0, 3.35, 0))
					var lo := _node(base, "panto_lower", Vector3(0, 0.05, 0.6))
					_box(lo, "arm", Vector3(0, 0, -0.75), Vector3(0.08, 0.06, 1.5), metal)
					var up := _node(lo, "panto_upper", Vector3(0, 0, -1.5))
					_box(up, "arm", Vector3(0, 0, 0.7), Vector3(0.06, 0.05, 1.4), metal)
					var hd := _node(up, "panto_head", Vector3(0, 0, 1.4))
					_box(hd, "bow", Vector3.ZERO, Vector3(1.6, 0.05, 0.08), metal)
				_box(m, "em_interior_%d" % i, Vector3(0, 3.2, 0), Vector3(0.3, 0.02, L - 1.0), em)
			if lod <= 2 and (i == 0 or i == n - 1):
				var e := "A" if i == 0 else "B"
				var z := (-0.5 if i == 0 else 0.5) * L
				var s := -1.0 if i == 0 else 1.0
				for k in [-1, 1]:
					_box(m, "em_head_%s_%d" % [e, k + 1], Vector3(0.85 * k, 0.95, z + s * 0.14), Vector3(0.18, 0.12, 0.05), em)
					_box(m, "em_tail_%s_%d" % [e, k + 1], Vector3(0.95 * k, 1.25, z + s * 0.14), Vector3(0.1, 0.1, 0.05), em)
				_box(m, "em_dest_%s" % e, Vector3(0, 3.0, z + s * 0.14), Vector3(1.3, 0.22, 0.03), em)
				_node(m, "sign_dest_%s" % e, Vector3(0, 3.0, z + s * 0.16), Vector3(0, 0 if i == 0 else PI, 0))
				if lod == 0:
					var w := _node(m, "wiper_%s_0" % e, Vector3(0.4, 1.35, z + s * 0.17))
					_box(w, "blade", Vector3(0, 0.45, 0), Vector3(0.03, 0.9, 0.02), metal)
					var px := "" if i == 0 else "B_"
					for side in ["L", "R"]:
						var mr := _node(m, "mirror_%s%s" % [px, side], Vector3(1.25 * (-1.0 if side == "L" else 1.0), 2.4, z + s * 0.4))
						_box(mr, "arm", Vector3(0.12 * (-1.0 if side == "L" else 1.0), 0, 0), Vector3(0.25, 0.25, 0.05), metal)
					var proxy := _node(m, "cab_proxy_%s" % e)
					_box(proxy, "desk", Vector3(0, 1.1, z - s * -0.9), Vector3(1.4, 0.15, 0.5), metal)
		if _save(root, dir.path_join("lod%d.glb" % lod)) != OK: return {}
	# cabine (repère module_00)
	var L0 := float(lens[0]); var zf := -L0 * 0.5
	var cab := Node3D.new(); cab.name = "cab"
	var desk_mat := _mat("paint_desk", Color(0.18, 0.19, 0.2))
	_node(cab, "cam_driver", Vector3(0, 1.95, zf + 1.75), Vector3(deg_to_rad(-14.0), 0, 0))
	_box(cab, "desk", Vector3(0, 1.12, zf + 0.85), Vector3(1.9, 0.1, 0.62), desk_mat, Vector3(deg_to_rad(12.0), 0, 0))
	_box(cab, "desk_front", Vector3(0, 0.7, zf + 0.6), Vector3(1.9, 0.8, 0.1), desk_mat)
	_box(cab, "floor", Vector3(0, 0.35, zf + 1.4), Vector3(2.3, 0.05, 2.4), skirt)
	_box(cab, "roof", Vector3(0, 3.15, zf + 1.3), Vector3(2.3, 0.08, 2.6), paint)
	for k in [-1, 1]:
		_box(cab, "pillar_%d" % (k + 1), Vector3(1.05 * k, 2.15, zf + 0.25), Vector3(0.14, 2.0, 0.14), front)
		_box(cab, "wall_%d" % (k + 1), Vector3(1.18 * k, 0.9, zf + 1.4), Vector3(0.05, 1.1, 2.4), paint)
		_quad(cab, "side_glass_%d" % (k + 1), Vector3(1.18 * k, 2.2, zf + 1.4), Vector2(2.2, 1.3), glass, Vector3(0, -k * PI * 0.5, 0))
	_quad(cab, "windshield", Vector3(0, 2.15, zf + 0.22), Vector2(2.0, 1.7), _mat("glass_windshield", Color(0.1, 0.1, 0.1)))
	var x := -0.8
	for a in CabActions.actions():
		var c := _node(cab, CabActions.node_for(a), Vector3(x, 1.2, zf + 0.95))
		var kind := str(CabActions.ACTIONS[a].kind)
		if kind == "lever": _box(c, "handle", Vector3(0, 0.08, 0), Vector3(0.05, 0.16, 0.05), _mat("ctl_black", Color(0.05, 0.05, 0.05)))
		elif a == "emergency": _box(c, "cap", Vector3(0, 0.03, 0), Vector3(0.07, 0.04, 0.07), _mat("ctl_red", Color(0.8, 0.05, 0.05)))
		else: _box(c, "cap", Vector3(0, 0.02, 0), Vector3(0.05, 0.03, 0.05), _mat("ctl_grey", Color(0.5, 0.5, 0.5)))
		x += 0.16
	for i in ["doors", "panto", "power", "emergency", "sand", "headlights"].size():
		_box(cab, "em_lamp_" + ["doors", "panto", "power", "emergency", "sand", "headlights"][i], Vector3(-0.5 + i * 0.2, 1.42, zf + 0.62), Vector3(0.04, 0.04, 0.02), em)
	var sm := _mat("screen", Color.BLACK)
	_quad(cab, "screen_speed", Vector3(-0.45, 1.33, zf + 0.68), Vector2(0.24, 0.15), sm, Vector3(deg_to_rad(-20.0), 0, 0))
	_quad(cab, "screen_info", Vector3(0.45, 1.33, zf + 0.68), Vector2(0.28, 0.17), sm, Vector3(deg_to_rad(-20.0), 0, 0))
	_quad(cab, "screen_signal", Vector3(0.0, 1.36, zf + 0.66), Vector2(0.16, 0.1), sm, Vector3(deg_to_rad(-20.0), 0, 0))
	if _save(cab, dir.path_join("cab.glb")) != OK: return {}
	var entry := {"dir": dir.get_file(), "family": str(plan.get("id", "")), "length_m": rig.length, "width_m": 2.4,
		"modules": lens, "doors": per_side,
		"lods": {"LOD0": {"file": "lod0.glb"}, "LOD1": {"file": "lod1.glb"}, "LOD2": {"file": "lod2.glb"}, "LOD3": {"file": "lod3.glb"}},
		"cab": {"file": "cab.glb"}, "panto": {"module": panto_mod, "lower_deg": 35.0, "upper_deg": -70.0},
		"wiper": {"axis": "z", "sweep_deg": 90.0, "period_s": 1.2}, "mirror": {"fold_deg": 80.0}, "sign": {"width_m": 1.2},
		"controls": {"ctl_notch": {"kind": "lever", "axis": "x", "range_deg": [-30.0, 30.0]}, "ctl_pantograph": {"kind": "toggle", "axis": "z", "on_deg": 35.0}},
		"screens": {"screen_speed": {"px": [256, 160]}, "screen_info": {"px": [320, 200]}, "screen_signal": {"px": [160, 100]}},
		"license": "fixture de test"}
	return entry

static func write_manifest(out_dir: String, variants: Dictionary) -> String:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	var p := out_dir.path_join("manifest.json")
	var f := FileAccess.open(p, FileAccess.WRITE)
	f.store_string(JSON.stringify({"version": 1, "variants": variants}, "  "))
	f.close()
	return p
