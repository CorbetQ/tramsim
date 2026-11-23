class_name StockCatalog
extends RefCounted
## Variantes et livrées d'origine indépendantes du réseau de conduite.
const INDEX := "res://data/rolling_stock/variants/index.json"
static var _entries:Array=[]
const GROUP_PLANS := {
 "citadis_x05": ["citadis_x05", "citadis_x05_nantes", "citadis_compact"],
 "citadis_x02": ["citadis_302", "citadis_402", "citadis_reims", "citadis_tours"],
 "citadis_x03": ["citadis_403_strasbourg"],
 "flexity": ["flexity_marseille"],
 "tango": ["tango_rhonexpress"],
}
const GROUP_NAMES := {"citadis_x05":"Citadis X05", "citadis_x02":"Citadis X02", "citadis_x03":"Citadis X03", "flexity":"Flexity / Cityrunner", "flexity_link":"Flexity Link", "tango":"Stadler Tango"}

static func group_id(entry: Dictionary) -> String:
 var plan := str(entry.get("family", ""))
 # Several real vehicles share a rendering fallback, not their commercial family.
 if str(entry.get("id", ""))=="sarreguemines__flexity_link": return "flexity_link"
 if "Citadis 403" in str(entry.get("name", "")): return "citadis_x03"
 for group in GROUP_PLANS:
  if plan in GROUP_PLANS[group]: return group
 return plan

static func group_name(id: String) -> String:
 if GROUP_NAMES.has(id): return GROUP_NAMES[id]
 return str(TramModel.plan(id).get("name", id)).replace("Alstom ", "").replace("Bombardier ", "").replace(" [AJOUT]", "")

static func type_name(entry: Dictionary) -> String:
 var label := str(entry.get("name", ""))
 if str(entry.family)=="tfs": return "TFS 1" if str(entry.get("cab_profile",""))=="tfs_nantes" else "TFS 2"
 if "Citadis 3 CTS" in label: return "Citadis 3"
 if "Flexity Link" in label: return "Link"
 if str(entry.family)=="tango_rhonexpress": return "Rhônexpress" if "Rhônexpress" in label else "Be 6/10"
 if "Cityrunner" in label: return "Be 6/8"
 if "Flexity Outlook" in label: return "Outlook"
 if "Flexity Basel" in label: return "Basel"
 var regex := RegEx.new()
 regex.compile("\\b(205|301|302|305|401|402|403|405|100X|STE[1-6]|STE[12]|U 25500)\\b")
 var found := regex.search(str(entry.get("name", "")))
 if found: return found.get_string()+ (" NG" if found.get_string()=="403" and "403 NG" in label else "")
 if str(entry.family) == "urbos": return "Urbos 3"
 if str(entry.family) == "eurotram": return "Long" if str(entry.id).ends_with("_long") else "Court"
 return str(entry.get("family", "")).replace("_", " ").capitalize()

static func grouped(city: String = "") -> Array:
 var groups := {}
 for entry in entries():
  if city != "" and str(entry.city) != city: continue
  var id := group_id(entry)
  if not groups.has(id): groups[id] = {"id":id, "name":group_name(id), "variants":[], "types":[], "cities":[], "preview_family":entry.family}
  var group: Dictionary = groups[id]
  group.variants.append(entry)
  if not type_name(entry) in group.types: group.types.append(type_name(entry))
  if not entry.city in group.cities: group.cities.append(entry.city)
 var result: Array = groups.values()
 result.sort_custom(func(a,b): return str(a.name).naturalnocasecmp_to(str(b.name)) < 0)
 for group in result: group.types.sort_custom(func(a,b): return str(a).naturalnocasecmp_to(str(b)) < 0)
 return result

static func group_variants(id: String) -> Array:
 return entries().filter(func(e): return group_id(e) == id)
static func entries()->Array:
 if _entries.is_empty():
  var data:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(INDEX))
  _entries=data.get("entries",[])
  var patches:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/rolling_stock/variants/technical_overrides.json"))
  for entry in _entries:
   var patch:Dictionary=patches.get(str(entry.id),{})
   for key in ["technical","geometry"]:entry[key].merge(patch.get(key,{}),true)
   for key in patch.get("technical",{}):entry.estimated.erase(key)
   for source in patch.get("sources",[]):
    if not source in entry.sources:entry.sources.append(source)
 return _entries
static func find(id:String)->Dictionary:
 for entry in entries():
  if str(entry.id)==id or id in entry.get("aliases",[]):return entry
 return {}
static func resolve(entry:Dictionary,meta:Dictionary={})->Dictionary:
 if entry.has("id"):
  var exact:=find(str(entry.id))
  if not exact.is_empty():return entry.merged(exact,true)
 var source:=str(entry.get("network",meta.get("source_id","")))
 var family:=str(entry.get("family",""));var line:=str(entry.get("line",""));var fallback:Dictionary={}
 for candidate in entries():
  if candidate.fictional or str(candidate.network)!=source or str(candidate.family)!=family:continue
  if line==str(candidate.line) or line in candidate.get("lines",[]):return entry.merged(candidate,true)
  if fallback.is_empty():fallback=candidate
 return entry.merged(fallback,true) if not fallback.is_empty() else entry.duplicate(true)
static func native_for(meta:Dictionary)->Array:
 var source:=str(meta.get("source_id",""));var key:=str(meta.get("id","")).trim_prefix(source+"_").split("_")[0].to_lower()
 var preferred:Array=[];var others:Array=[]
 for entry in entries():
  if str(entry.network)!=source or entry.fictional:continue
  if source=="nantes" and str(meta.get("kind",""))=="tram-train" and str(entry.family)!="citadis_dualis":continue
  if source=="nantes" and key in ["1","2","3"]:
   if str(entry.family)=="citadis_dualis" or (key!="1" and str(entry.family)=="urbos"):continue
  if source=="idf" and key.begins_with("t") and not key in entry.get("lines",[]):continue
  if source=="orleans" and key in ["a","b"] and not key in entry.get("lines",[]):continue
  if source=="lyon" and key in ["t1","t2","t3","t4","t5","t6","t7"] and str(entry.family) in ["citadis_dualis","tango_rhonexpress"]:continue
  if key in entry.get("lines",[]):preferred.append(entry)
  else:others.append(entry)
 return preferred+others
static func requirements(supplies)->PackedStringArray:
 var result:=PackedStringArray();var all:Array=supplies if supplies is Array else [supplies]
 for value in all:
  var modes:Array=["overhead","aps"] if str(value)=="hybrid" else [str(value)]
  for mode in modes:
   if mode!="none" and not mode in result:result.append(mode)
 return result
static func issues(entry:Dictionary,supplies,guidance:String)->PackedStringArray:
 var out:=PackedStringArray();var modes: Array=entry.get("electric_modes",["overhead"])
 if str(entry.get("guidance","steel"))!=guidance:out.append("Guidage sur pneus" if entry.get("guidance")=="rubber_guided" else "Roulement sur rails")
 for mode in requirements(supplies):
  if not mode in modes:out.append({"aps":"APS requis","battery":"Autonomie sans LAC requise","overhead":"LAC requise"}.get(mode,mode+" requis"))
 return out
static func for_network(meta:Dictionary,supplies)->Array:
 var result:Array=[];var native:Array=[]
 for raw in entries():
  if not issues(raw,supplies,str(meta.get("guidance","steel"))).is_empty():continue
  var entry:Dictionary=raw.duplicate(true)
  # Seul l'écartement est adapté en libre ; jamais l'APS ni la technologie de guidage.
  entry.running_gauge_mm=int(meta.get("gauge_mm",1435))
  if str(entry.network)==str(meta.get("source_id","")) and not entry.fictional:native.append(entry)
  else:result.append(entry)
 return native+result
static var _origin_meta:Dictionary={}
static func origin_meta(entry:Dictionary)->Dictionary:
 var src:=str(entry.get("network",""));var line:=str(entry.get("line",""))
 var key:=src+"_"+line
 if not _origin_meta.has(key):
  var origin:Dictionary={"source_id":src,"id":key,"city":entry.get("city",src),"color":"#267c88"}
  var path:="res://data/free/%s.json"%src
  if FileAccess.file_exists(path):
   var data:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(path));origin.color=data.get("color","#267c88")
  for item in NetworkRegistry.entries():
   if str(item.city)==str(entry.get("city","")) and str(item.line).to_lower()==line:
    var data:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(str(item.path)));origin.color=data.get("color",origin.color);break
  _origin_meta[key]=origin
 return (_origin_meta[key] as Dictionary).duplicate(true)

static var _targets:Array=[]
static func targets()->Array:
 if not _targets.is_empty():return _targets
 for filename in DirAccess.get_files_at("res://data/free"):
  if not filename.ends_with(".json"):continue
  var path:="res://data/free/"+filename;var data:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(path))
  var modes:Array=[]
  for edge in data.get("edges",[]):
   var power:=str(edge.get("supply",data.get("supply","overhead")))
   if power!="none" and not power in modes:modes.append(power)
   for zone in edge.get("supply_zones",[]):
    if str(zone[2])!="none" and not str(zone[2]) in modes:modes.append(str(zone[2]))
  _targets.append({"path":path,"source_id":data.get("source_id",filename.get_basename()),"city":data.get("city",filename.get_basename()),"guidance":data.get("guidance","steel"),"supplies":modes,"gauge_mm":1000 if filename.get_basename() in ["lille","saintetienne"] else 1435})
 _targets.sort_custom(func(a,b):return str(a.city).naturalnocasecmp_to(str(b.city))<0)
 return _targets
