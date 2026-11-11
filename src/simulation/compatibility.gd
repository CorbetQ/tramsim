class_name Compatibility
extends RefCounted
## Compatibilité matériel / infrastructure. Le mode libre peut forcer un mode d'adaptation.

## net_supply : String ou Array de modes d'alimentation présents sur le réseau.
static func issues(p: VehicleProfile, net_supply, net_guidance: String) -> PackedStringArray:
	var out := PackedStringArray()
	var sup: Array = net_supply if net_supply is Array else [net_supply]
	for s in sup:
		if p.supply != s and p.supply != "hybrid":
			out.append("alimentation : matériel %s / réseau %s" % [p.supply, s])
			break
	if p.guidance != net_guidance:
		out.append("guidage : matériel %s / réseau %s" % [p.guidance, net_guidance])
	return out

static func mission_allowed(p: VehicleProfile, net_supply, net_guidance: String) -> bool:
	return issues(p, net_supply, net_guidance).is_empty()

## Retourne l'annonce à afficher avant le départ, ou "" si compatible.
static func adaptation_notice(p: VehicleProfile, net_supply, net_guidance: String) -> String:
	var i := issues(p, net_supply, net_guidance)
	if i.is_empty():
		return ""
	return "Mode d'adaptation : alimentation et guidage rendus compatibles, conduite conservée (" + "; ".join(i) + ")"
