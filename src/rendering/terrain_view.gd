class_name TerrainView
extends Node3D
## Sol continu d'une ville (data/scenes/<ville>_ground.bin, format TGR1, tools/import/terrain_mesh.py).
##
## Une triangulation contrainte par tuile de 400 m porte à la fois le relief et la voirie (chaussées, carrefours,
## trottoirs, îlots, plateforme tram, eau, végétation) : la voirie est drapée exactement sur le terrain, sans couche
## superposée. Les sommets des bords de tuile sont communs aux tuiles voisines (raccords sans déchirure).
## - height(x, z) : altitude exacte du maillage (barycentrique sur le triangle, index de cellules de 8 m, tuiles
##   décodées gardées dans un petit cache) ;
## - tile(k) : tuile décodée pour RoadView.build ;
## - couronne lointaine (grille de 100 m sur l'emprise + 8 km) : maillage de 8 km autour de la caméra (pas de 250 m,
##   reconstruit tous les FAR_REBUILD m). Au-delà de FAR_NEAR m, un shader rapproche les sommets de la caméra le
##   long de la ligne de visée (angle conservé) pour rester dans son plan lointain (1,6 km) : silhouette du relief
##   régional jusqu'à l'horizon, sans parallaxe faussée.
## Coordonnées : repère de la ville (CityScene), altitudes relatives à alt0.

const Q := 64.0
const CELL := 8.0
const MAX_CACHE := 40
const FAR_RADIUS := 8000.0
const FAR_STEP := 200.0       # divise exactement les tuiles de 400 m
const FAR_NEAR := 1150.0       # m : au-delà, rapprochement radial vers [FAR_NEAR, FAR_NEAR + 380 m]
const FAR_REBUILD := 1000.0

class Tile:
	var pos := PackedVector3Array()     # repère tuile (y : altitude relative à alt0)
	var tri := PackedInt32Array()       # 3 indices par triangle (a < b < c, orientation à recalculer)
	var mat := PackedByteArray()        # matériau (bits 0-4) | bordures (bits 5-7)
	var lines: Array = []               # décalques linéaires [type, PackedVector2Array (repère tuile), phase]
	var rects: Array = []               # décalques [type, centre Vector2, direction Vector2, largeur, longueur]
	var cell_start := PackedInt32Array()
	var cell_tris := PackedInt32Array()

var ok := false
var tile_m := 400.0
var min_height := 0.0
var table: Dictionary = {}          # Vector2i -> [offset, taille compressée, taille]
var ymin: Dictionary = {}           # Vector2i -> altitude minimale de la tuile
var keys: Array[Vector2i] = []      # ordre de la table (enregistrements de méta)
var _buf: PackedByteArray
var _wide_height := false
var _cache: Dictionary = {}
var _lru: Array[Vector2i] = []
var _meta := PackedByteArray()
# couronne lointaine
var _far_h := PackedFloat32Array()
var _far_x0 := 0.0
var _far_z0 := 0.0
var _far_step := 100.0
var _far_nx := 0
var _far_nz := 0
var _far_mesh: MeshInstance3D = null
var _far_at := Vector3(INF, INF, INF)
var _far_loaded := 0
var color := Color("#a9ab98")
# occupation du sol réelle (data/scenes/<ville>_land.bin, TLC1, tools/import/landcover.py) : classes par cellule
var land_ok := false
var land_colors: Array[Color] = []
var land_flags := PackedByteArray()
var _land: Array = []               # [détail (25 m), lointain (100 m)] : [x0, z0, pas, nx, nz, PackedByteArray]

static func path_for(c: String) -> String:
	return "res://data/scenes/%s_ground.bin" % c

static func available(c: String) -> bool:
	return FileAccess.file_exists(path_for(c))

func open(c: String) -> bool:
	_buf = FileAccess.get_file_as_bytes(path_for(c))
	if _buf.size() < 40: return false
	var magic := _buf.slice(0, 4).get_string_from_ascii()
	if magic not in ["TGR1", "TGR2"]: return false
	_wide_height = magic == "TGR2"
	tile_m = _buf.decode_float(8)
	var n := _buf.decode_u32(12)
	var far_off := _buf.decode_u32(16); var far_cs := _buf.decode_u32(20); var far_raw := _buf.decode_u32(24)
	var meta_off := _buf.decode_u32(28); var meta_cs := _buf.decode_u32(32); var meta_raw := _buf.decode_u32(36)
	min_height = INF
	for i in n:
		var o := 40 + i * 24
		var k := Vector2i(_buf.decode_s32(o), _buf.decode_s32(o + 4))
		table[k] = [_buf.decode_u32(o + 8), _buf.decode_u32(o + 12), _buf.decode_u32(o + 16)]
		ymin[k] = _buf.decode_float(o + 20)
		min_height = minf(min_height, ymin[k])
		keys.append(k)
	if n == 0: min_height = 0.0
	_meta = _buf.slice(meta_off, meta_off + meta_cs).decompress(meta_raw, FileAccess.COMPRESSION_BROTLI)
	var far := _buf.slice(far_off, far_off + far_cs).decompress(far_raw, FileAccess.COMPRESSION_BROTLI)
	if far.size() >= 16:
		_far_x0 = far.decode_float(0); _far_z0 = far.decode_float(4); _far_step = far.decode_float(8)
		_far_nx = far.decode_u16(12); _far_nz = far.decode_u16(14)
		_far_h.resize(_far_nx * _far_nz)
		for i in _far_nx * _far_nz: _far_h[i] = far.decode_s16(16 + i * 2) * 0.1
	_load_land(c)
	ok = true
	return true

func _load_land(c: String) -> void:
	var path := "res://data/scenes/%s_land.bin" % c
	if not FileAccess.file_exists(path): return
	var b := FileAccess.get_file_as_bytes(path)
	if b.size() < 9 or b.slice(0, 4).get_string_from_ascii() != "TLC1": return
	var n := b.decode_u8(8); var o := 9
	for i in n:
		land_colors.append(Color8(b[o], b[o + 1], b[o + 2])); land_flags.append(b[o + 3]); o += 4
	for r in 2:
		if o + 20 > b.size(): return
		var nx := b.decode_u16(o + 12); var nz := b.decode_u16(o + 14); var cs := b.decode_u32(o + 16)
		var raw := b.slice(o + 20, o + 20 + cs).decompress(nx * nz, FileAccess.COMPRESSION_BROTLI)
		if raw.size() != nx * nz: return
		_land.append([b.decode_float(o), b.decode_float(o + 4), b.decode_float(o + 8), nx, nz, raw])
		o += 20 + cs
	land_ok = true

## Classe d'occupation du sol au point (repère de la ville) : raster de détail, sinon lointain ; -1 si inconnue.
func land_class(x: float, z: float, far_only: bool = false) -> int:
	for r in range(1 if far_only else 0, _land.size()):
		var L: Array = _land[r]
		var ix := floori((x - L[0]) / L[2]); var iz := floori((z - L[1]) / L[2])
		if ix < 0 or iz < 0 or ix >= L[3] or iz >= L[4]: continue
		var c: int = L[5][iz * L[3] + ix]
		if c < land_colors.size(): return c
	return -1

## Teinte d'occupation du sol d'une tuile (18 x 18 : cellules de 25 m et une cellule de bord ; A = sillons),
## pour le shader du sol (land_tint). null sans données.
func land_image(k: Vector2i, fallback: Color) -> Image:
	if not land_ok: return null
	var img := Image.create(18, 18, false, Image.FORMAT_RGBA8)
	var ox := k.x * tile_m; var oz := k.y * tile_m
	for iz in 18:
		for ix in 18:
			var c := land_class(ox + (ix - 1) * 25.0 + 12.5, oz + (iz - 1) * 25.0 + 12.5)
			var col: Color = land_colors[c] if c >= 0 else fallback
			col.a = 1.0 if c >= 0 and land_flags[c] & 1 else 0.0
			img.set_pixel(ix, iz, col)
	return img

## Niveaux d'eau et tabliers (format des enregistrements TTR2), dans l'ordre de `keys`.
func meta_bytes() -> PackedByteArray:
	return _meta

func has_tile(k: Vector2i) -> bool:
	return table.has(k)

## Tuile décodée (cache LRU).
func tile(k: Vector2i) -> Tile:
	if _cache.has(k):
		return _cache[k]
	if not table.has(k): return null
	var e: Array = table[k]
	var d := _buf.slice(e[0], e[0] + e[1]).decompress(e[2], FileAccess.COMPRESSION_BROTLI)
	var t := Tile.new()
	var base := d.decode_float(0); var nv := d.decode_u32(4); var nt := d.decode_u32(8)
	var ox := 12; var oz := ox + nv * 2; var oy := oz + nv * 2
	t.pos.resize(nv)
	var x := 0; var z := 0; var y := 0
	for i in nv:
		x += d.decode_s16(ox + i * 2); z += d.decode_s16(oz + i * 2)
		y += d.decode_s32(oy + i * 4) if _wide_height else d.decode_s16(oy + i * 2)
		t.pos[i] = Vector3(x / Q, base + y * 0.01, z / Q)
	var oa := oy + nv * (4 if _wide_height else 2); var ob := oa + nt * 2; var oc := ob + nt * 2
	t.tri.resize(nt * 3)
	var a := 0
	for i in nt:
		a += d.decode_s16(oa + i * 2)
		var b := a + d.decode_s16(ob + i * 2)
		t.tri[i * 3] = a; t.tri[i * 3 + 1] = b; t.tri[i * 3 + 2] = b + d.decode_s16(oc + i * 2)
	var o := oc + nt * 2
	t.mat = d.slice(o, o + nt); o += nt
	if o + 2 <= d.size():
		var nl := d.decode_u16(o); o += 2
		for i in nl:
			var kind := d.decode_u8(o); var np := d.decode_u8(o + 1); var phase := d.decode_u16(o + 2) * 0.1; o += 4
			var pl := PackedVector2Array(); pl.resize(np)
			for j in np:
				pl[j] = Vector2(d.decode_s16(o) * 0.1, d.decode_s16(o + 2) * 0.1); o += 4
			t.lines.append([kind, pl, phase])
		var nr := d.decode_u16(o); o += 2
		for i in nr:
			var ang := d.decode_u16(o + 5) / 65535.0 * TAU
			t.rects.append([d.decode_u8(o), Vector2(d.decode_s16(o + 1) * 0.1, d.decode_s16(o + 3) * 0.1), Vector2(cos(ang), sin(ang)),
				d.decode_u8(o + 7) * 0.1, d.decode_u8(o + 8) * 0.1])
			o += 9
	_cache[k] = t
	_lru.append(k)
	if _lru.size() > MAX_CACHE:
		_cache.erase(_lru.pop_front())
	return t

func _index(t: Tile) -> void:
	var nc := int(ceil(tile_m / CELL))
	var count := PackedInt32Array(); count.resize(nc * nc + 1)
	var nt := t.tri.size() / 3
	var boxes := PackedInt32Array(); boxes.resize(nt * 4)
	for i in nt:
		var a := t.pos[t.tri[i * 3]]; var b := t.pos[t.tri[i * 3 + 1]]; var c := t.pos[t.tri[i * 3 + 2]]
		var x0 := clampi(floori(minf(a.x, minf(b.x, c.x)) / CELL), 0, nc - 1); var x1 := clampi(floori(maxf(a.x, maxf(b.x, c.x)) / CELL), 0, nc - 1)
		var z0 := clampi(floori(minf(a.z, minf(b.z, c.z)) / CELL), 0, nc - 1); var z1 := clampi(floori(maxf(a.z, maxf(b.z, c.z)) / CELL), 0, nc - 1)
		boxes[i * 4] = x0; boxes[i * 4 + 1] = x1; boxes[i * 4 + 2] = z0; boxes[i * 4 + 3] = z1
		for cz in range(z0, z1 + 1):
			for cx in range(x0, x1 + 1): count[cz * nc + cx + 1] += 1
	for i in nc * nc: count[i + 1] += count[i]
	t.cell_start = count.duplicate()
	t.cell_tris.resize(count[nc * nc])
	for i in nt:
		for cz in range(boxes[i * 4 + 2], boxes[i * 4 + 3] + 1):
			for cx in range(boxes[i * 4], boxes[i * 4 + 1] + 1):
				var c := cz * nc + cx
				t.cell_tris[count[c]] = i; count[c] += 1

## Altitude du maillage du sol au point (x, z) du repère de la ville ; NAN hors des tuiles.
func height(x: float, z: float) -> float:
	var k := Vector2i(floori(x / tile_m), floori(z / tile_m))
	var t := tile(k)
	if t == null: return NAN
	return tile_height(t, x - k.x * tile_m, z - k.y * tile_m)

## Altitude dans une tuile décodée (repère tuile).
func tile_height(t: Tile, px: float, pz: float) -> float:
	if t.cell_start.is_empty(): _index(t)
	var nc := int(ceil(tile_m / CELL))
	var c := clampi(floori(pz / CELL), 0, nc - 1) * nc + clampi(floori(px / CELL), 0, nc - 1)
	var best := INF; var hb := NAN
	for j in range(t.cell_start[c], t.cell_start[c + 1]):
		var i := t.cell_tris[j]
		var a := t.pos[t.tri[i * 3]]; var b := t.pos[t.tri[i * 3 + 1]]; var d := t.pos[t.tri[i * 3 + 2]]
		var v0x := b.x - a.x; var v0z := b.z - a.z; var v1x := d.x - a.x; var v1z := d.z - a.z
		var den := v0x * v1z - v1x * v0z
		if absf(den) < 1e-9: continue
		var wx := px - a.x; var wz := pz - a.z
		var u := (wx * v1z - v1x * wz) / den; var v := (v0x * wz - wx * v0z) / den
		var out := maxf(maxf(-u, -v), u + v - 1.0)
		if out <= 1e-5: return a.y + (b.y - a.y) * u + (d.y - a.y) * v
		if out < best:   # point sur une arête (arrondis) : triangle le plus proche
			best = out; hb = a.y + (b.y - a.y) * clampf(u, 0, 1) + (d.y - a.y) * clampf(v, 0, 1)
	return hb

# ------------------------------------------------------------------------------------------- couronne lointaine
## Altitude de la grille lointaine (bilinéaire), repère de la ville.
func far_height(x: float, z: float) -> float:
	if _far_nx < 2: return min_height
	var fx := clampf((x - _far_x0) / _far_step, 0.0, _far_nx - 1.001); var fz := clampf((z - _far_z0) / _far_step, 0.0, _far_nz - 1.001)
	var ix := int(fx); var iz := int(fz); var u := fx - ix; var v := fz - iz
	var h00 := _far_h[iz * _far_nx + ix]; var h10 := _far_h[iz * _far_nx + ix + 1]
	var h01 := _far_h[(iz + 1) * _far_nx + ix]; var h11 := _far_h[(iz + 1) * _far_nx + ix + 1]
	return lerpf(lerpf(h00, h10, u), lerpf(h01, h11, u), v)

## Relief lointain tel que maillé par la couronne (grille de FAR_STEP m, diagonale 00-11, 1,5 m sous le MNT) :
## sol des tuiles de décor lointain (CityScene._far_ground) et altitude hors des tuiles de sol.
func far_tri(x: float, z: float) -> float:
	var ix := floorf(x / FAR_STEP); var iz := floorf(z / FAR_STEP)
	var u := x / FAR_STEP - ix; var v := z / FAR_STEP - iz
	var x0 := ix * FAR_STEP; var z0 := iz * FAR_STEP
	var h00 := far_height(x0, z0); var h10 := far_height(x0 + FAR_STEP, z0)
	var h01 := far_height(x0, z0 + FAR_STEP); var h11 := far_height(x0 + FAR_STEP, z0 + FAR_STEP)
	var h := h00 + (h10 - h00) * u + (h11 - h10) * v if u >= v else h00 + (h11 - h01) * u + (h01 - h00) * v
	return h - 1.5

## Rapprochement radial (angle de vue conservé) au-delà de `near` : relief lointain dans le plan lointain de la caméra.
const FAR_SHADER := """
shader_type spatial;
render_mode world_vertex_coords, cull_disabled, specular_disabled;
uniform float near_m = 1150.0;
uniform float span_m = 380.0;
void vertex() {
	vec3 rel = VERTEX - CAMERA_POSITION_WORLD;
	float d = length(rel.xz);
	if (d > near_m && PROJECTION_MATRIX[3][3] < 0.5) {
		float r = near_m + span_m * (1.0 - exp(-(d - near_m) / 2500.0));
		VERTEX = CAMERA_POSITION_WORLD + rel * (r / d);
	}
}
void fragment() {
	ALBEDO = COLOR.rgb * 0.8;
	ROUGHNESS = 1.0;
}
"""

## Points intermédiaires du bord d'une tuile réellement affichée, dans l'ordre a -> b.
## Le bord du terrain lointain suit ainsi le profil complet, pas seulement les coins espacés de 200 m.
func _far_edge_points(a: Vector3, b: Vector3, loaded: Dictionary) -> Array[Vector3]:
	var result: Array[Vector3] = []
	var start := Vector2(a.x, a.z); var edge := Vector2(b.x - a.x, b.z - a.z)
	var outside := (start + Vector2(b.x, b.z)) * 0.5 + Vector2(edge.y, -edge.x).normalized() * 0.01
	var key := Vector2i(floori(outside.x / tile_m), floori(outside.y / tile_m))
	if not loaded.has(key): return result
	var detail := tile(key)
	if detail == null: return result
	var origin := Vector2(key.x, key.y) * tile_m
	var length2 := edge.length_squared()
	for local in detail.pos:
		var q := Vector2(local.x, local.z) + origin
		var fraction := (q - start).dot(edge) / length2
		if fraction <= 0.000001 or fraction >= 0.999999: continue
		if absf(edge.cross(q - start)) > 0.001 * sqrt(length2): continue
		result.append(Vector3(q.x, local.y, q.y))
	result.sort_custom(func(p: Vector3, q: Vector3): return Vector2(p.x - a.x, p.z - a.z).dot(edge) < Vector2(q.x - a.x, q.z - a.z).dot(edge))
	return result

## Met à jour la couronne lointaine autour de la caméra (repère de la ville, parent = CityScene).
func update_far(cam_city: Vector3, loaded: Dictionary = {}) -> void:
	if _far_nx < 2: return
	var signature := loaded.keys().hash()
	if signature == _far_loaded and Vector2(cam_city.x - _far_at.x, cam_city.z - _far_at.z).length() < FAR_REBUILD: return
	_far_at = cam_city
	_far_loaded = signature
	var n := int(FAR_RADIUS * 2.0 / FAR_STEP) + 1
	var x0 := snappedf(cam_city.x, FAR_STEP) - FAR_RADIUS; var z0 := snappedf(cam_city.z, FAR_STEP) - FAR_RADIUS
	var P := PackedVector3Array(); P.resize(n * n)
	for iz in n:
		for ix in n:
			var x := x0 + ix * FAR_STEP; var z := z0 + iz * FAR_STEP
			var h := far_height(x, z) - 1.5
			# Les arêtes de raccord utilisent les vraies altitudes des tuiles affichées.
			var k := Vector2i(floori(x / tile_m), floori(z / tile_m))
			for offset in [Vector2i.ZERO, Vector2i(-1, 0), Vector2i(0, -1), Vector2i(-1, -1)]:
				var candidate: Vector2i = k + offset
				if not loaded.has(candidate): continue
				var local := Vector2(x - candidate.x * tile_m, z - candidate.y * tile_m)
				if local.x < 0 or local.y < 0 or local.x > tile_m or local.y > tile_m: continue
				var detail := tile(candidate)
				if detail != null: h = tile_height(detail, local.x, local.y)
				break
			P[iz * n + ix] = Vector3(x, h, z)
	var V := PackedVector3Array(); var C := PackedColorArray(); var N := PackedVector3Array()
	for iz in n - 1:
		for ix in n - 1:
			var cx := x0 + (ix + 0.5) * FAR_STEP; var cz := z0 + (iz + 0.5) * FAR_STEP
			if loaded.has(Vector2i(floori(cx / tile_m), floori(cz / tile_m))): continue
			var a := P[iz * n + ix]; var b := P[iz * n + ix + 1]; var c := P[(iz + 1) * n + ix + 1]; var d := P[(iz + 1) * n + ix]
			var corners := [a, b, c, d]
			var rim: Array[Vector3] = []; var stitched := false
			for i in 4:
				rim.append(corners[i])
				var points := _far_edge_points(corners[i], corners[(i + 1) % 4], loaded)
				if not points.is_empty(): stitched = true; rim.append_array(points)
			var triangles: Array = []
			if stitched:
				var center := (a + b + c + d) * 0.25
				for i in rim.size(): triangles.append([center, rim[i], rim[(i + 1) % rim.size()]])
			else: triangles = [[a, b, c], [a, c, d]]
			for tri in triangles:
				var fn: Vector3 = (tri[2] - tri[0]).cross(tri[1] - tri[0]).normalized()
				if fn.length_squared() < 0.5: continue
				if fn.y < 0.0: fn = -fn
				var k_steep := clampf((1.0 - fn.y) * 5.0, 0.0, 1.0)
				for q in tri:
					var col := color
					if land_ok:   # occupation du sol régionale (cellules de 100 m), interpolée entre sommets
						var lc := land_class(q.x, q.z, true)
						if lc >= 0: col = land_colors[lc]
					V.append(q); N.append(fn); C.append(col.lerp(col.darkened(0.2), k_steep))
	if _far_mesh == null:
		_far_mesh = MeshInstance3D.new()
		_far_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var sh := Shader.new(); sh.code = FAR_SHADER
		var mat := ShaderMaterial.new(); mat.shader = sh
		mat.set_shader_parameter("near_m", FAR_NEAR)
		_far_mesh.material_override = mat
		add_child(_far_mesh)
	var arr := []; arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = V; arr[Mesh.ARRAY_NORMAL] = N; arr[Mesh.ARRAY_COLOR] = C
	var m := ArrayMesh.new()
	if V.size() > 0: m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	_far_mesh.mesh = m
	# boîte englobante : le maillage est rapproché par le shader, ne jamais l'écarter du rendu
	_far_mesh.custom_aabb = AABB(Vector3(x0, -5000, z0), Vector3(FAR_RADIUS * 2.0, 10000, FAR_RADIUS * 2.0))
