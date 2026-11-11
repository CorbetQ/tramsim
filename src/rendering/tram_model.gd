class_name TramModel
extends RefCounted
## Rames low poly générées : caisse extrudée (jupe, caisse, vitrage, bandeau, toit), face avant paramétrique par
## famille, portes, soufflets, pantographe, équipements de toiture, feux, girouette ; livrée par réseau / ligne.
## Repère d'un module : x latéral, y vertical (0 = rail), -z = sens de marche.

const FAMILIES := {
	"citadis": {"w": 2.40, "h": 3.30, "nose": 1.6, "taper": 0.78, "rake": 0.55, "drop": 0.10, "segs": 5, "round": 1.6, "ws": 1.15, "light_y": 0.85},
	"citadis_x05": {"w": 2.40, "h": 3.30, "nose": 1.3, "taper": 0.88, "rake": 0.30, "drop": 0.05, "segs": 3, "round": 1.0, "ws": 1.10, "light_y": 0.80},
	"citadis_reims": {"w": 2.40, "h": 3.30, "nose": 2.1, "taper": 0.58, "rake": 0.85, "drop": 0.28, "segs": 6, "round": 2.4, "ws": 1.00, "light_y": 0.80},
	"citadis_tours": {"w": 2.40, "h": 3.30, "nose": 1.9, "taper": 0.70, "rake": 0.75, "drop": 0.12, "segs": 5, "round": 1.8, "ws": 1.05, "light_y": 0.80},
	"eurotram": {"w": 2.40, "h": 3.25, "nose": 2.0, "taper": 0.66, "rake": 0.95, "drop": 0.30, "segs": 6, "round": 2.8, "ws": 0.70, "light_y": 0.60},
	"tfs": {"w": 2.30, "h": 3.40, "nose": 0.9, "taper": 0.92, "rake": 0.15, "drop": 0.00, "segs": 2, "round": 1.0, "ws": 1.35, "light_y": 0.95},
	"translohr": {"w": 2.20, "h": 3.10, "nose": 1.5, "taper": 0.70, "rake": 0.60, "drop": 0.15, "segs": 5, "round": 1.8, "ws": 1.05, "light_y": 0.80},
	"flexity_marseille": {"w": 2.40, "h": 3.30, "nose": 2.4, "taper": 0.42, "rake": 0.50, "drop": 0.06, "segs": 6, "round": 1.3, "ws": 1.00, "light_y": 0.75},
	"urbos": {"w": 2.40, "h": 3.30, "nose": 1.5, "taper": 0.80, "rake": 0.50, "drop": 0.08, "segs": 4, "round": 1.4, "ws": 1.10, "light_y": 0.85},
	"urbos_short": {"w": 2.40, "h": 3.30, "nose": 1.4, "taper": 0.80, "rake": 0.55, "drop": 0.10, "segs": 4, "round": 1.5, "ws": 1.10, "light_y": 0.85, "modules": 3},
	"avanto": {"w": 2.65, "h": 3.60, "nose": 2.2, "taper": 0.62, "rake": 0.65, "drop": 0.12, "segs": 5, "round": 1.5, "ws": 1.20, "light_y": 0.95},
	"dualis": {"w": 2.65, "h": 3.60, "nose": 1.9, "taper": 0.72, "rake": 0.60, "drop": 0.10, "segs": 5, "round": 1.6, "ws": 1.20, "light_y": 0.95},
	"incentro": {"w": 2.40, "h": 3.30, "nose": 1.4, "taper": 0.82, "rake": 0.45, "drop": 0.12, "segs": 5, "round": 2.0, "ws": 1.10, "light_y": 0.85},
	"tango": {"w": 2.40, "h": 3.40, "nose": 1.6, "taper": 0.75, "rake": 0.50, "drop": 0.08, "segs": 4, "round": 1.5, "ws": 1.15, "light_y": 0.85},
	"breda": {"w": 2.40, "h": 3.40, "nose": 1.2, "taper": 0.85, "rake": 0.40, "drop": 0.15, "segs": 4, "round": 1.6, "ws": 1.15, "light_y": 0.90},
}

## Famille visuelle d'un profil de matériel (quand il ne s'agit pas du matériel propre au réseau).
const PROFILE_FAMILY := {"citadis_302": "citadis", "citadis_302_hybride": "citadis", "citadis_402_aps": "citadis",
	"translohr": "translohr", "citadis_dualis": "dualis", "tango_express": "tango"}

const GLASS_A := 0.5     # alpha < 0.75 : vitrage (éclairé la nuit)
const LAMP_A := 0.1      # alpha < 0.25 : feux, girouette (émissifs)

static var _liveries: Dictionary = {}

## Livrée résolue pour un réseau : défaut <- réseau <- ligne. "route" = couleur GTFS de la ligne.
static func livery_for(meta: Dictionary) -> Dictionary:
	if _liveries.is_empty():
		var f := FileAccess.open("res://data/liveries.json", FileAccess.READ)
		if f: _liveries = JSON.parse_string(f.get_as_text())
	var out: Dictionary = _liveries.get("default", {}).duplicate()
	var src := str(meta.get("source_id", ""))
	var net: Dictionary = _liveries.get("networks", {}).get(src, {})
	for k in net:
		if k != "lines": out[k] = net[k]
	var line_key := str(meta.get("id", "")).trim_prefix(src + "_").split("_")[0]
	var lines: Dictionary = net.get("lines", {})
	if lines.has(line_key):
		for k in lines[line_key]: out[k] = lines[line_key][k]
	var route := Color.from_string(str(meta.get("color", "#c8102e")), Color(0.78, 0.06, 0.18))
	if route.get_luminance() > 0.92: route = Color(0.2, 0.3, 0.45)  # couleur de ligne trop claire sur caisse blanche
	var res := {}
	for k in ["body", "accent", "window", "door", "front", "roof", "skirt"]:
		var v := str(out.get(k, "#888888"))
		res[k] = route if v == "route" else Color.from_string(v, Color.GRAY)
	for k in ["door", "front"]:
		if str(out.get(k, "")) == "accent": res[k] = res.accent
	res.family = str(out.get("family", "citadis"))
	res.style = str(out.get("style", "band"))
	return res

## Construit les modules (MeshInstance3D) d'une rame de longueur totale `length_m`.
static func build(length_m: float, livery: Dictionary, family: String = "") -> Array[MeshInstance3D]:
	var fam: Dictionary = FAMILIES.get(family if family != "" else livery.family, FAMILIES.citadis)
	var n := int(fam.get("modules", clampi(int(round(length_m / 7.5)), 3, 7)))
	var seg := length_m / n
	var mods: Array[MeshInstance3D] = []
	for i in n:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var b := _Builder.new(st, fam, livery)
		var z0 := -seg * 0.5 + 0.18
		var z1 := seg * 0.5 - 0.18
		b.body(z0, z1, i == 0, i == n - 1)
		b.doors(z0, z1, i == 0, i == n - 1)
		if i < n - 1: b.bellows(z1, seg * 0.5 + 0.18)
		if i == 0: b.nose(z0, -1.0, true)
		if i == n - 1: b.nose(z1, 1.0, false)
		if i == mini(1, n - 1): b.pantograph(0.0)
		elif i != 0 and i != n - 1: b.roof_box(0.0)
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		mi.material_override = Materials.tram(fam.h)
		mods.append(mi)
	return mods

class _Builder:
	var st: SurfaceTool
	var f: Dictionary
	var L: Dictionary
	var ring: Array = []      # [Vector2(x, y), bande] demi-profil droit, de bas en haut
	const BANDS := ["skirt", "body", "glass", "upper", "roof", "roof"]

	func _init(s: SurfaceTool, fam: Dictionary, liv: Dictionary) -> void:
		st = s; f = fam; L = liv
		var w: float = f.w * 0.5
		var h: float = f.h
		ring = [Vector2(w, 0.30), Vector2(w, 0.45), Vector2(w, 1.05), Vector2(w, 2.45), Vector2(w, h - 0.45),
			Vector2(w - 0.28, h - 0.12), Vector2(0.0, h)]

	func _col(band: String, front_zone: bool = false) -> Color:
		match band:
			"skirt": return L.skirt
			"glass":
				var g: Color = L.window; g.a = GLASS_A; return g
			"roof": return L.roof
			"upper":
				return L.front if (front_zone and L.style == "front_mask") else L.body
			"accent": return L.accent
		# caisse : bandeau d'accent sous les baies (style "band"), masque avant éventuel
		if front_zone: return L.front
		return L.body

	## Profil complet (droite puis gauche) avec bande de chaque segment.
	func _full() -> Array:
		var pts: Array = []
		for p in ring: pts.append(p)
		for k in range(ring.size() - 2, -1, -1): pts.append(Vector2(-ring[k].x, ring[k].y))
		return pts

	func _band_of(j: int) -> String:
		var n := ring.size() - 1
		var k := j if j < n else (2 * n - 1 - j)
		return BANDS[mini(k, BANDS.size() - 1)]

	func tri(a: Vector3, b: Vector3, c: Vector3, col: Color, out: Vector3) -> void:
		if (b - a).cross(c - a).dot(out) > 0.0:  # Godot : faces avant dans le sens horaire
			var t := b; b = c; c = t
		for v in [a, b, c]:
			st.set_color(col); st.add_vertex(v)

	func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, out: Vector3) -> void:
		tri(a, b, c, col, out); tri(a, c, d, col, out)

	func box(c: Vector3, s: Vector3, col: Color) -> void:
		var h := s * 0.5
		var p := [c + Vector3(-h.x, -h.y, -h.z), c + Vector3(h.x, -h.y, -h.z), c + Vector3(h.x, h.y, -h.z), c + Vector3(-h.x, h.y, -h.z),
			c + Vector3(-h.x, -h.y, h.z), c + Vector3(h.x, -h.y, h.z), c + Vector3(h.x, h.y, h.z), c + Vector3(-h.x, h.y, h.z)]
		quad(p[0], p[1], p[2], p[3], col, Vector3(0, 0, -1)); quad(p[5], p[4], p[7], p[6], col, Vector3(0, 0, 1))
		quad(p[4], p[0], p[3], p[7], col, Vector3(-1, 0, 0)); quad(p[1], p[5], p[6], p[2], col, Vector3(1, 0, 0))
		quad(p[3], p[2], p[6], p[7], col, Vector3(0, 1, 0)); quad(p[4], p[5], p[1], p[0], col, Vector3(0, -1, 0))

	func body(z0: float, z1: float, _front: bool, _rear: bool) -> void:
		var pts := _full()
		for j in range(pts.size() - 1):
			var a: Vector2 = pts[j]; var b: Vector2 = pts[j + 1]
			var mid := (a + b) * 0.5
			var out := Vector3(mid.x, mid.y - f.h * 0.5, 0.0)
			quad(Vector3(a.x, a.y, z0), Vector3(b.x, b.y, z0), Vector3(b.x, b.y, z1), Vector3(a.x, a.y, z1), _col(_band_of(j)), out)
		# bandeau d'accent sous les baies
		if L.style == "band":
			for side in [-1.0, 1.0]:
				var x: float = side * (f.w * 0.5 + 0.005)
				quad(Vector3(x, 0.88, z0), Vector3(x, 1.02, z0), Vector3(x, 1.02, z1), Vector3(x, 0.88, z1), L.accent, Vector3(side, 0, 0))

	func doors(z0: float, z1: float, front: bool, rear: bool) -> void:
		var len := z1 - z0
		var centers: Array = []
		if len > 5.0:
			centers = [z0 + len * 0.3, z0 + len * 0.72] if not front else [z0 + len * 0.62]
			if rear and not front: centers = [z0 + len * 0.38]
		else:
			centers = [(z0 + z1) * 0.5]
		for zc in centers:
			for side in [-1.0, 1.0]:
				var x: float = side * (f.w * 0.5 + 0.02)
				box(Vector3(x, 1.36, zc), Vector3(0.04, 2.05, 1.3), L.door)
				var g: Color = L.window; g.a = GLASS_A
				box(Vector3(x + side * 0.01, 1.62, zc - 0.33), Vector3(0.04, 1.2, 0.5), g)
				box(Vector3(x + side * 0.01, 1.62, zc + 0.33), Vector3(0.04, 1.2, 0.5), g)

	func bellows(z0: float, z1: float) -> void:
		var s := Vector3(f.w * 0.86, f.h - 0.55, z1 - z0 + 0.02)
		box(Vector3(0, 0.3 + s.y * 0.5, (z0 + z1) * 0.5), s, Color(0.12, 0.12, 0.13))

	## Face avant : anneaux successifs (largeur effilée, pare-brise incliné, toit plongeant) puis nez fermé.
	func nose(z_end: float, dir: float, is_front: bool) -> void:
		var base := _full()
		var segs: int = f.segs
		var prev: Array = []
		for p in base: prev.append(Vector3(p.x, p.y, z_end))
		var rings: Array = [prev]
		for k in range(1, segs + 1):
			var t := float(k) / segs
			var sw: float = 1.0 - (1.0 - f.taper) * pow(t, f.round)
			var cur: Array = []
			for p in base:
				var y: float = minf(p.y, f.h - f.drop * t * t * 1.4)
				var up := clampf((y - f.ws) / (f.h - f.ws), 0.0, 1.0)
				var z: float = z_end + dir * (f.nose * t - f.rake * f.nose * t * up * 0.6)
				cur.append(Vector3(p.x * sw, y, z))
			rings.append(cur)
		for k in range(1, rings.size()):
			var a: Array = rings[k - 1]; var b: Array = rings[k]
			var t := float(k) / segs
			for j in range(a.size() - 1):
				var band := _band_of(j)
				var y: float = (a[j].y + a[j + 1].y) * 0.5
				var col := _col(band, t > 0.2)
				if t > 0.25 and y > f.ws and y < f.h - 0.35:
					col = L.window; col.a = 0.8  # pare-brise : sombre, pas d'éclairage intérieur
				var out := Vector3((a[j].x + a[j + 1].x) * 0.5, y - f.h * 0.5, dir * 0.6)
				quad(a[j], a[j + 1], b[j + 1], b[j], col, out)
		# face avant fermée par bandes horizontales (jupe, masque, pare-brise, bandeau de girouette)
		var tip: Array = rings[-1]
		var m := ring.size() - 1
		var c := Vector3.ZERO
		for p in tip: c += p
		c /= tip.size()
		for k in range(m):
			var a0: Vector3 = tip[k]; var a1: Vector3 = tip[k + 1]
			var b0: Vector3 = tip[2 * m - k]; var b1: Vector3 = tip[2 * m - k - 1]
			var bulge := Vector3(0, 0, dir * 0.10)
			var y := (a0.y + a1.y) * 0.5
			var col: Color = L.skirt if y < 0.45 else L.front
			if y > f.ws and y < f.h - 0.35:
				col = L.window; col.a = 0.8
			# léger galbe : la ligne médiane avance un peu
			var ma := (a0 + b0) * 0.5 + bulge; var mb := (a1 + b1) * 0.5 + bulge
			quad(a0, a1, mb, ma, col, Vector3(0, 0, dir))
			quad(ma, mb, b1, b0, col, Vector3(0, 0, dir))
		# montants de pare-brise
		for side in [-1.0, 1.0]:
			var k0 := 3 if side > 0 else 2 * m - 3
			var p0: Vector3 = tip[k0]
			box(Vector3(p0.x * 0.98, (f.ws + f.h - 0.35) * 0.5, p0.z + dir * 0.02), Vector3(0.12, f.h - 0.35 - f.ws, 0.08), L.front)
		# feux (blancs à l'avant, rouges à l'arrière) et girouette
		var zt: float = c.z + dir * 0.13
		var lx: float = f.w * 0.5 * f.taper - 0.32
		var lamp := Color(1.0, 0.97, 0.85, LAMP_A) if is_front else Color(0.95, 0.12, 0.08, LAMP_A)
		for side in [-1.0, 1.0]:
			box(Vector3(side * lx, f.light_y, zt), Vector3(0.32, 0.14, 0.06), lamp)
		var y_dest: float = f.h - 0.5 - f.drop
		var zd: float = c.z + dir * 0.02 - dir * f.rake * f.nose * 0.5
		box(Vector3(0, y_dest, zd), Vector3(f.w * f.taper * 0.55, 0.2, 0.05), Color(1.0, 0.62, 0.1, LAMP_A))

	func pantograph(zc: float) -> void:
		var h: float = f.h
		var g := Color(0.25, 0.26, 0.28)
		box(Vector3(0, h + 0.08, zc), Vector3(1.0, 0.16, 1.6), Color(0.55, 0.57, 0.6))
		# losange (bras inclinés), archet
		var arm := 0.9
		for s in [-1.0, 1.0]:
			_beam(Vector3(0, h + 0.16, zc + s * 0.6), Vector3(0, h + 0.16 + arm, zc), 0.05, g)
		box(Vector3(0, h + 0.18 + arm, zc), Vector3(1.6, 0.05, 0.12), g)
		box(Vector3(0, h + 0.12, zc - 1.6), Vector3(1.2, 0.24, 1.0), L.roof.darkened(0.1))

	func roof_box(zc: float) -> void:
		box(Vector3(0, f.h + 0.12, zc), Vector3(1.4, 0.24, 2.2), L.roof.darkened(0.12))

	func _beam(a: Vector3, b: Vector3, t: float, col: Color) -> void:
		var d := b - a
		var n := d.cross(Vector3.RIGHT).normalized() * t
		var s := Vector3.RIGHT * t
		quad(a - s - n, a + s - n, b + s - n, b - s - n, col, -n)
		quad(a - s + n, a + s + n, b + s + n, b - s + n, col, n)
		quad(a - s - n, a - s + n, b - s + n, b - s - n, col, -s)
		quad(a + s - n, a + s + n, b + s + n, b + s - n, col, s)
