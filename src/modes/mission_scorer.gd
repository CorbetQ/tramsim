class_name MissionScorer
extends RefCounted
## Ponctualité : aucun départ anticipé, retard maximal 60 s ; fautes de sécurité = échec.

const MAX_LATE_S := 60.0

enum Result { OK, EARLY, LATE, MISSED_STOP }
var stops: Array[Dictionary] = []   # {name, result}
var failed: bool = false
var fail_reason: String = ""
var max_late_s := MAX_LATE_S        # tolérance (affluence d'événement : élargie)

func evaluate_departure(stop_name: String, scheduled_s: float, actual_s: float, stopped: bool = true) -> int:
	var r := Result.OK
	if not stopped:
		r = Result.MISSED_STOP
	elif actual_s < scheduled_s:
		r = Result.EARLY
	elif actual_s - scheduled_s > max_late_s:
		r = Result.LATE
	stops.append({"name": stop_name, "result": r})
	return r

func safety_fault(reason: String) -> void:  # collision, signal franchi, fin de voie
	failed = true
	fail_reason = reason

func success() -> bool:
	if failed:
		return false
	for s in stops:
		if s.result != Result.OK:
			return false
	return true
