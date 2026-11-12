#!/usr/bin/env python3
"""Enrichit les réseaux livrés depuis leur instantané OSM, sans modifier le relief.
Polygones conservés à l'identique ; quais ouverts : axe OSM + largeur estimée
explicitement (3 m sauf width renseigné). Aucun emplacement GTFS n'est inventé.
"""
import gzip,json,math,unicodedata,re
from pathlib import Path
import numpy as np
from shapely.geometry import Point,LineString,Polygon
from shapely.strtree import STRtree
ROOT=Path(__file__).resolve().parents[2]
R=6371008.8 # même rayon terrestre que CityScene et les voies physiques
def electrical_mode(tag,city):
 return {'contact_line':'overhead','ground-level_power_supply':'aps','no':'battery' if city=='nice' else 'none'}.get(tag)
def fold(x):return re.sub('[^a-z0-9]','',unicodedata.normalize('NFKD',x).encode('ascii','ignore').decode().lower())
def enrich(path,osm):
 d=json.loads(path.read_text());lat,lon=d['origin'][:2];k=math.cos(math.radians(lat))
 def p(n):return (math.radians(n['lon']-lon)*R*k,-math.radians(n['lat']-lat)*R)
 nodes={e['id']:e for e in osm['elements'] if e['type']=='node'}
 edges=d['edges'];lines=[LineString(e['pts']) for e in edges];tree=STRtree(lines);byway={}
 for e in osm['elements']:
  if e['type']=='way':byway[e['id']]=e
 named={}
 for n in nodes.values():
  t=n.get('tags',{})
  if t.get('railway')=='tram_stop' or t.get('public_transport')=='stop_position' and t.get('tram')=='yes':named.setdefault(fold(t.get('name','')),[]).append(n)
 moved=0
 for s in d['stations']:
  i=next((i for i,e in enumerate(edges) if e['id']==s['edge']),None)
  if i is None:continue
  line=lines[i];old=line.interpolate(s['offset']/edges[i]['length']*line.length)
  candidates=[n for n in named.get(fold(s['name']),[]) if Point(p(n)).distance(old)<400]
  if not candidates:continue
  # Nom + proximité dans le même quartier ; les arrêts directionnels restent distincts.
  exact=[n for n in candidates if str(s.get('stop_id','')) in [str(v) for key,v in n.get('tags',{}).items() if 'stop_id' in key or key.startswith('ref:')]]
  n=min(exact or candidates,key=lambda n:Point(p(n)).distance(old));pt=Point(p(n))
  j=int(tree.nearest(pt)) if d.get('geometry_kind')=='physical' else i
  if lines[j].distance(pt)>30:continue
  if d.get('geometry_kind')=='physical' and i!=j:
   before=np.array(line.interpolate(min(line.length,line.project(old)+.5)).coords[0])-np.array(line.interpolate(max(0,line.project(old)-.5)).coords[0])
   after=np.array(lines[j].interpolate(min(lines[j].length,lines[j].project(pt)+.5)).coords[0])-np.array(lines[j].interpolate(max(0,lines[j].project(pt)-.5)).coords[0])
   s['direction']=int(s.get('direction',1)) * (1 if np.dot(before,after)>=0 else -1)
  s['edge']=edges[j]['id'];s['offset']=round(lines[j].project(pt)/lines[j].length*edges[j]['length'],3)
  s['source_osm_node']=n['id'];s['stop_source']='OSM stop_position';s['projection_m']=round(lines[j].distance(pt),3);moved+=1
 for mission in d.get('missions',[]):
  if mission.get('stops'):
   first=d['stations'][mission['stops'][0]]
   mission['start_edge']=first['edge'];mission['start_offset']=max(0.,float(first['offset'])-20.)
 # Géométrie des quais dans le repère local de chaque mission également.
 platforms=[]
 for w in byway.values():
  t=w.get('tags',{})
  if t.get('public_transport')!='platform' and t.get('railway')!='platform':continue
  ids=w.get('nodes',[])
  if len(ids)<2 or not all(n in nodes for n in ids):continue
  coords=[p(nodes[n]) for n in ids];estimated=coords[0]!=coords[-1]
  if estimated:
   try:width=float(t.get('width','3').replace(',','.'))
   except ValueError:width=3.
   axis=LineString(coords);width=max(.6,min(width,12));near=int(tree.nearest(axis))
   if axis.distance(lines[near])-width/2<1.4:
    left=axis.buffer(width,single_sided=True,cap_style=2,join_style=2);right=axis.buffer(-width,single_sided=True,cap_style=2,join_style=2)
    polygon=max([left,right],key=lambda shape:shape.centroid.distance(lines[near]))
   else:polygon=axis.buffer(width/2,cap_style=2,join_style=2)
  else:polygon=Polygon(coords)
  if not polygon.is_valid or polygon.area<2:continue
  center=polygon.representative_point();i=int(tree.nearest(center))
  if lines[i].distance(center)>25:continue
  coords=list(polygon.exterior.coords)[:-1];ys=[]
  for q in coords:
   pt=Point(q);j=int(tree.nearest(pt));e=edges[j];arc=np.r_[0.,np.cumsum(np.linalg.norm(np.diff(e['pts'],axis=0),axis=1))]
   ys.append(round(float(np.interp(lines[j].project(pt),arc,e.get('y',[0]*len(arc)))),4))
  platforms.append(dict(osm_way=w['id'],name=t.get('name',''),pts=[[round(x,3),round(z,3)] for x,z in coords],y=ys,height_m=.3,height_estimated=True,width_estimated=estimated and 'width' not in t,geometry_source='OSM open way, estimated width away from track' if estimated else 'OSM polygon',edge=edges[i]['id'],shelter=t.get('shelter')=='yes'))
 d['platforms']=platforms;d['platform_source']='OpenStreetMap snapshot '+osm.get('osm3s',{}).get('timestamp_osm_base','unknown')
 # Les tags électriques OSM sont prioritaires sur l'ancien profil GTFS.
 rails=[];modes=[];services=[]
 for w in byway.values():
  t=w.get('tags',{});ids=w.get('nodes',[]);electric=t.get('electrified','')
  if t.get('railway') not in ('tram','light_rail') or len(ids)<2 or not all(n in nodes for n in ids):continue
  mode=electrical_mode(electric,d.get('source_id',''))
  if mode:rails.append(LineString([p(nodes[n]) for n in ids]));modes.append(mode);services.append(t.get('service',''))
 rt=STRtree(rails) if rails else None
 for e,line in zip(edges,lines):
  way=byway.get(e.get('source',{}).get('way'),{});electric=way.get('tags',{}).get('electrified','')
  exact=electrical_mode(electric,d.get('source_id',''))
  if exact:e['supply']=exact;e['supply_source']='OSM electrified='+electric;e.pop('supply_zones',None);continue
  if d.get('geometry_kind')=='physical' or rt is None:continue
  zones=[];count=max(1,math.ceil(e['length']/10))
  for a in range(count):
   lo=e['length']*a/count;hi=e['length']*(a+1)/count;along=(a+.5)/count*line.length;q=line.interpolate(along)
   tangent=np.array(line.interpolate(min(line.length,along+4)).coords[0])-np.array(line.interpolate(max(0,along-4)).coords[0]);tangent/=max(1e-9,np.linalg.norm(tangent))
   candidates=[]
   for j in rt.query(q.buffer(8)):
    rail=rails[j];s=rail.project(q);heading=np.array(rail.interpolate(min(rail.length,s+2)).coords[0])-np.array(rail.interpolate(max(0,s-2)).coords[0]);heading/=max(1e-9,np.linalg.norm(heading))
    alignment=abs(float(np.dot(tangent,heading)))
    if alignment<math.cos(math.radians(25)):continue
    score=rail.distance(q)+5*(1-alignment)+(3 if services[j] else 0)
    candidates.append((score,int(j)))
   mode=modes[min(candidates)[1]] if candidates else e.get('supply',d.get('supply','overhead'))
   if zones and zones[-1][2]==mode:zones[-1][1]=round(hi,3)
   else:zones.append([round(lo,3),round(hi,3),mode])
  e['supply_zones']=zones
 path.write_text(json.dumps(d,ensure_ascii=False,separators=(',',':'))+'\n')
 return moved,len(platforms)
if __name__=='__main__':
 report={}
 for source in sorted((ROOT/'data/geography/osm').glob('*.json.gz')):
  city=source.name.removesuffix('.json.gz')
  if city.startswith('depot_'):continue
  osm=json.loads(gzip.decompress(source.read_bytes()));paths=[ROOT/f'data/free/{city}.json']
  paths+=sorted((ROOT/'data/networks').glob(city+'_*.json'))
  report[city]={str(p.relative_to(ROOT)):enrich(p,osm) for p in paths if p.exists()}
  print(city,report[city],flush=True)
 (ROOT/'docs/station-power-import.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
 # Les emprises et les modes viennent d'être réimportés : recaler aussi les
 # zones opérationnelles pour éviter un ancien recouvrement devenu incohérent.
 from platform_zones import main as rebuild_platform_zones
 rebuild_platform_zones()
