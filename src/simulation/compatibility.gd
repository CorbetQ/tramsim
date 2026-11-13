class_name Compatibility
extends RefCounted
## Compatibilité électrique réelle ; un réseau APS ne transforme pas la rame.
static func issues(p:VehicleProfile,net_supply,net_guidance:String)->PackedStringArray:
 var out:=PackedStringArray();var modes:=p.power_modes()
 for required in StockCatalog.requirements(net_supply):
  if not required in modes:out.append("alimentation : %s requise"%required)
 if p.guidance!=net_guidance:out.append("guidage : matériel %s / réseau %s"%[p.guidance,net_guidance])
 return out
static func mission_allowed(p:VehicleProfile,net_supply,net_guidance:String)->bool:
 return issues(p,net_supply,net_guidance).is_empty()
static func adaptation_notice(p:VehicleProfile,net_supply,net_guidance:String)->String:
 var problems:=issues(p,net_supply,net_guidance)
 return "" if problems.is_empty() else "Matériel incompatible : "+" ; ".join(problems)
