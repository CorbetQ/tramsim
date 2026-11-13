class_name StockCatalog
extends RefCounted
## Variantes et livrées d'origine indépendantes du réseau de conduite.
const INDEX := "res://data/rolling_stock/variants/index.json"
static var _entries:Array=[]
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
