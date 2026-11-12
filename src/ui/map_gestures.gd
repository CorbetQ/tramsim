class_name MapGestures
extends RefCounted
## Un doigt : déplacement ou sélection au relâchement ; deux doigts : zoom ancré.
## Aucune sélection après un pincement, même après avoir relâché le premier doigt.
var fingers: Dictionary = {}
var moved := false
var start := Vector2.ZERO

func reset() -> void:
	fingers.clear(); moved = false

func feed(ev: InputEvent) -> Dictionary:
	if ev is InputEventScreenTouch:
		if ev.pressed:
			if fingers.is_empty(): start = ev.position; moved = false
			fingers[ev.index] = ev.position
			if fingers.size() > 1: moved = true
		else:
			if not fingers.has(ev.index): return {}
			fingers.erase(ev.index)
			if fingers.is_empty() and not moved and start.distance_to(ev.position) < 12.0:
				return {"select": ev.position}
	elif ev is InputEventScreenDrag and fingers.has(ev.index):
		var old: Vector2 = fingers[ev.index]
		fingers[ev.index] = ev.position
		if fingers.size() > 1:
			moved = true
			for id in fingers:
				if id == ev.index: continue
				var other: Vector2 = fingers[id]
				var before := old.distance_to(other)
				if before > 8.0:
					return {"zoom": ev.position.distance_to(other) / before,
						"anchor": (old + other) * 0.5, "pan": (ev.position - old) * 0.5}
		else:
			var was_moved := moved
			moved = moved or start.distance_to(ev.position) >= 12.0
			if moved: return {"pan": ev.position - (old if was_moved else start)}
	return {}
