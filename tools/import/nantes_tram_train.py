#!/usr/bin/env python3
"""Ajoute les arrêts OSM T1/T2 aux voies physiques existantes, sans inventer de voies ni d'horaires.
Usage : nantes_tram_train.py CACHE (relations /full.json clisson.json, chateaubriant.json).
"""
import json,math,sys
from pathlib import Path
from shapely.geometry import LineString,Point
ROOT=Path(__file__).resolve().parents[2]
def build(cache):
 path=ROOT/'data/free/nantes.json';net=json.loads(path.read_text());origin=net['origin'];radius=6371008.8
 project=lambda lat,lon:[math.radians(lon-origin[1])*radius*math.cos(math.radians(origin[0])),-math.radians(lat-origin[0])*radius]
 entries=[];sources=[]
 for filename,ref,identifier in [('chateaubriant','TER T1','nantes_tt_t1'),('clisson','TER T2','nantes_tt_t2')]:
  doc=json.loads((Path(cache)/(filename+'.json')).read_text());rel=next(e for e in doc['elements'] if e['type']=='relation' and e.get('tags',{}).get('route')=='light_rail')
  nodes={e['id']:e for e in doc['elements'] if e['type']=='node'};ways={e['id']:e for e in doc['elements'] if e['type']=='way'}
  route=[m['ref'] for m in rel['members'] if m['type']=='way' and m.get('role','')==''];allowed=set(route)
  edges=[e for e in net['edges'] if e.get('source',{}).get('way') in allowed]
  assert {e['source']['way'] for e in edges}==allowed,'Géométrie physique incomplète'
  geometries=[LineString(e['pts']) for e in edges];directions={};prev=None
  for i,w in enumerate(route):
   ids=ways[w]['nodes'];start,end=ids[0],ids[-1]
   if prev is None:
    following=ways[route[min(i+1,len(route)-1)]]['nodes']
    forward=end in (following[0],following[-1])
   else:forward=start==prev
   directions[w]=(1 if forward else -1);prev=end if forward else start
  stops=[]
  for member in rel['members']:
   if member['type']!='node' or not member.get('role','').startswith('stop'):continue
   node=nodes[member['ref']];p=Point(project(node['lat'],node['lon']));i=min(range(len(edges)),key=lambda i:geometries[i].distance(p));edge=edges[i];line=geometries[i]
   distance=line.distance(p);assert distance<15,(node['id'],distance)
   waynodes=ways[edge['source']['way']]['nodes'];a=edge['source']['node_from'];b=edge['source']['node_to']
   direction=directions[edge['source']['way']]*(1 if waynodes.index(a)<waynodes.index(b) else -1)
   offset=round(min(edge['length'],max(0,line.project(p)/line.length*edge['length'])),3)
   stops.append({'name':node.get('tags',{}).get('name',str(node['id'])),'stop_id':'osm:'+str(node['id']),'edge':edge['id'],'offset':offset,'direction':direction,'dwell_s':30,'lines':[ref],'snap_m':round(distance,3),'source_osm_node':node['id'],'stop_source':'OpenStreetMap route stop_position','source_relation':rel['id']})
  assert len(stops)==(8 if filename=='clisson' else 11)
  net['stations']=[s for s in net['stations'] if ref not in s.get('lines',[])]+stops
  if ref not in net['lines']:net['lines'].append(ref)
  for edge in edges:
   if ref not in edge.setdefault('lines',[]):edge['lines'].append(ref)
  tags=rel['tags'];entries.append({'id':identifier,'city':'Nantes','line':ref,'long_name':tags['from']+' – '+tags['to'],'path':'res://data/free/nantes.json','kind':'tram-train','free_only':True,'guidance':'steel','supply':'overhead','stations':len(stops),'length_km':round(sum(e['length'] for e in edges)/1000,1),'missions':0,'source_relation':rel['id']})
  sources.append({'relation':rel['id'],'url':'https://www.openstreetmap.org/api/0.6/relation/'+str(rel['id'])+'/full.json','tags':tags,'ways':route,'stops':[{'node':m['ref'],'name':nodes[m['ref']].get('tags',{}).get('name'),'lat':nodes[m['ref']]['lat'],'lon':nodes[m['ref']]['lon']} for m in rel['members'] if m['type']=='node' and m.get('role','').startswith('stop')],'osm_base':doc.get('osm3s',{}).get('timestamp_osm_base')})
 path.write_text(json.dumps(net,ensure_ascii=False,separators=(',',':'))+'\n')
 (ROOT/'data/catalogue/free_lines.json').write_text(json.dumps({'schema':1,'networks':entries},ensure_ascii=False,indent=2)+'\n')
 (ROOT/'data/sources/nantes_tram_train.json').write_text(json.dumps({'schema':1,'licence':'ODbL 1.0 © OpenStreetMap contributors','retrieved':'2026-11-13','note':'Voies physiques existantes, arrêts projetés depuis les coordonnées OSM. Aucun horaire commercial inventé.','routes':sources},ensure_ascii=False,indent=2)+'\n')
 print([(e['line'],e['stations'],e['length_km']) for e in entries])
if __name__=='__main__':build(sys.argv[1])
