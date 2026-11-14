class_name AerialCityLOD
extends CityScene
## Static geographic proxy, prepared during city selection. No detailed terrain decoding,
## facade shaders, trees, props or tile streaming during the aerial camera movement.
const GRID := 40.0
var triangles := 0
var prepared := false
var _material: StandardMaterial3D

func warm(_center: Vector3, cancellation = null) -> bool:
	if prepared: return true
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.vertex_color_use_as_albedo = true
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var keys := table.duplicate()
	for k in _ter_table: keys[k] = true
	if terrain != null:
		for k in terrain.table: keys[k] = true
	# One draw call per 800 m patch, with frustum culling rather than thousands of objects.
	var patches := {}
	for k: Vector2i in keys:
		if cancellation != null and cancellation.cancelled(): return false
		var patch := Vector2i(floori(float(k.x) / 2.0), floori(float(k.y) / 2.0))
		if not patches.has(patch): patches[patch] = _Arrays.new()
		var a: _Arrays = patches[patch]
		var off := Vector2(k) * tile_m
		var ground := Color.from_string(str(style.get("ground", "#aaa899")), Color.GRAY)
		var cells := ceili(tile_m / GRID)
		for iz in cells:
			for ix in cells:
				var p := off + Vector2(ix, iz) * GRID
				var q := off + Vector2(minf((ix + 1) * GRID, tile_m), minf((iz + 1) * GRID, tile_m))
				var col := ground
				if terrain != null:
					var lc := terrain.land_class((p.x + q.x) * 0.5, (p.y + q.y) * 0.5)
					if lc >= 0: col = terrain.land_colors[lc]
				a.quad(_aerial_point(p), _aerial_point(Vector2(q.x, p.y)), _aerial_point(q), _aerial_point(Vector2(p.x, q.y)), col, -1.0)
		if table.has(k): _features(k, off, a)
	for k in patches:
		var a: _Arrays = patches[k]
		var mesh := MeshInstance3D.new(); mesh.mesh = _indexed_mesh(a); mesh.material_override = _material
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		triangles += a.count() / 3
		add_child(mesh)
	prepared = true
	stats.tiles = keys.size()
	return true

func update(_center: Vector3, _budget: int = 1) -> void:
	pass # Entire geographic proxy already resident; never create tiles in the cinematic.

func _aerial_point(p: Vector2, lift := 0.0) -> Vector3:
	return Vector3(p.x, (terrain.far_height(p.x, p.y) if terrain != null else 0.0) + lift, p.y)

func _features(k: Vector2i, off: Vector2, a: _Arrays) -> void:
	var o := _tile_data(k)
	var buildings := []
	var nb := buf.decode_u16(o); o += 2
	for b in nb:
		var n := buf.decode_u8(o); var h := buf.decode_u16(o + 2) * 0.1
		o += 5 if v2 else 4
		var ring := PackedVector2Array()
		for i in n:
			ring.append(off + Vector2(buf.decode_s16(o), buf.decode_s16(o + 2)) * 0.1); o += 4
		var nt := buf.decode_u8(o); o += 1
		buildings.append([ring, buf.slice(o, o + nt * 3), h]); o += nt * 3
	var np := buf.decode_u16(o); o += 2
	for i in np:
		var kind := buf.decode_u8(o); var nv := buf.decode_u16(o + 1); var nt := buf.decode_u16(o + 3); o += 5
		var pts := PackedVector2Array()
		for j in nv:
			pts.append(off + Vector2(buf.decode_s16(o), buf.decode_s16(o + 2)) * 0.1); o += 4
		var col := Color("#548b48")
		match kind:
			P_WATER: col = Color("#518b9e")
			P_FOREST: col = Color("#477940")
			P_GRASS: col = Color("#7f9f58")
			P_SPORT: col = Color("#7f9971")
			P_CEMETERY: col = Color("#8a9480")
		for j in nt:
			var i0 := buf.decode_u16(o); var i1 := buf.decode_u16(o + 2); var i2 := buf.decode_u16(o + 4); o += 6
			a.tri(_aerial_point(pts[i0], 0.12), _aerial_point(pts[i1], 0.12), _aerial_point(pts[i2], 0.12), col)
	var nl := buf.decode_u16(o); o += 2
	for i in nl:
		var cls := buf.decode_u8(o); var width_ := buf.decode_u8(o + 1) / 5.0; var n := buf.decode_u16(o + 2); o += 4
		var pts := PackedVector2Array()
		for j in n:
			pts.append(off + Vector2(buf.decode_s16(o), buf.decode_s16(o + 2)) * 0.1); o += 4
		if cls not in [L_MAJOR, L_ROAD, L_SMALL, L_PATH, L_RAIL]: continue
		var col := Color("#696b6c") if cls != L_PATH else Color("#c1b69a")
		for j in range(1, n):
			var side := (pts[j] - pts[j - 1]).orthogonal().normalized() * maxf(width_, 1.2) * 0.5
			a.quad(_aerial_point(pts[j - 1] - side, 0.24), _aerial_point(pts[j - 1] + side, 0.24), _aerial_point(pts[j] + side, 0.24), _aerial_point(pts[j] - side, 0.24), col, -1.0)
	if v2:
		var npt := buf.decode_u16(o); o += 2 + npt * 7
		var nlb := buf.decode_u16(o); o += 2
		for i in nlb:
			var length := buf.decode_u8(o + 5); o += 6 + length
	var roofs := PackedInt32Array()
	if v3:
		var nr := buf.decode_u16(o); o += 2
		for i in nr: roofs.append(buf.decode_u16(o + i * 2))
	for i in buildings.size():
		var b: Array = buildings[i]
		var ring: PackedVector2Array = b[0]
		if ring.size() < 3: continue
		var center := Vector2.ZERO
		for p in ring: center += p
		center /= ring.size()
		var y := _aerial_point(center).y + float(b[2])
		var color := _pal("roofs", i + hash(k))
		if i < roofs.size() and roofs[i] & 0x8000: color = _ortho_roof(roofs[i])
		for j in range(0, b[1].size(), 3):
			var p: Vector2 = ring[b[1][j]]; var q: Vector2 = ring[b[1][j + 1]]; var r: Vector2 = ring[b[1][j + 2]]
			a.tri(Vector3(p.x, y, p.y), Vector3(q.x, y, q.y), Vector3(r.x, y, r.y), color)

## Shared vertices greatly reduce upload size and vertex work on mobile GPUs.
func _indexed_mesh(a: _Arrays) -> ArrayMesh:
	var positions := PackedVector3Array(); var colors := PackedColorArray(); var indices := PackedInt32Array()
	var lookup := {}
	for i in a.v.size():
		var p: Vector3 = a.v[i]; var col: Color = a.c[i]
		var rgb := col.r8 * 65536 + col.g8 * 256 + col.b8
		var key := Vector4(p.x, p.y, p.z, float(rgb))
		if not lookup.has(key):
			lookup[key] = positions.size(); positions.append(p); colors.append(col)
		indices.append(lookup[key])
	var arrays := []; arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = positions; arrays[Mesh.ARRAY_COLOR] = colors; arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new(); mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
