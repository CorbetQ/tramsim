class_name TerrainClip
extends RefCounted
## Soustraction exacte d'une ouverture convexe, en conservant les altitudes interpolées.
## Les morceaux rendus sont convexes, même lorsque l'ouverture est entièrement dans un triangle.
static func capsule(a: Vector2, b: Vector2, radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for center in [a, b]:
		for i in 16:
			points.append(center + Vector2.from_angle(i * TAU / 16.0) * (radius + 0.04))
	var hull := Geometry2D.convex_hull(points)
	if hull.size() > 1 and hull[0].is_equal_approx(hull[-1]): hull.remove_at(hull.size() - 1)
	return hull

static func subtract(subject: PackedVector3Array, opening: PackedVector2Array) -> Array:
	var result: Array = []
	var remaining := subject
	var area := 0.0
	for i in opening.size(): area += opening[i].cross(opening[(i + 1) % opening.size()])
	var sign_ := 1.0 if area >= 0.0 else -1.0
	for i in opening.size():
		if remaining.size() < 3: break
		var a := opening[i]; var edge := opening[(i + 1) % opening.size()] - a
		var inside := PackedVector3Array(); var outside := PackedVector3Array()
		for j in remaining.size():
			var p := remaining[j]; var q := remaining[(j + 1) % remaining.size()]
			var dp := edge.cross(Vector2(p.x, p.z) - a) * sign_
			var dq := edge.cross(Vector2(q.x, q.z) - a) * sign_
			if dp >= 0.0: inside.append(p)
			else: outside.append(p)
			if (dp >= 0.0) != (dq >= 0.0):
				var hit := p.lerp(q, dp / (dp - dq))
				inside.append(hit); outside.append(hit)
		if outside.size() >= 3: result.append(outside)
		remaining = inside
	return result
