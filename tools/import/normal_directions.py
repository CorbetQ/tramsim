#!/usr/bin/env python3
"""Sens normal des voies physiques : tags OSM, puis paires urbaines non ambiguës.
Ne modifie jamais les identifiants, la géométrie ou les itinéraires GTFS.
"""
import json,gzip,math
from pathlib import Path
import numpy as np
from shapely.geometry import LineString
from shapely.strtree import STRtree
ROOT=Path(__file__).resolve().parents[2]
def explicit(tags):
 if tags.get('oneway') in ('yes','1','true'):return 1
 if tags.get('oneway') in ('-1','reverse'):return -1
 return {'forward':1,'backward':-1}.get(tags.get('railway:preferred_direction'),0)
def enrich(path):
 n=json.loads(path.read_text());source=json.loads(gzip.decompress((ROOT/f'data/geography/osm/{path.stem}.json.gz').read_bytes()));ways={w['id']:w.get('tags',{}) for w in source['elements'] if w['type']=='way'}
 edges=n['edges'];lines=[LineString(e['pts']) for e in edges];tree=STRtree(lines);directions=[];headings=[]
 for e,line in zip(edges,lines):
  tags=ways.get(e.get('source',{}).get('way'),{});e['source']['railway']=tags.get('railway','tram');e['source']['preferred_direction']=tags.get('railway:preferred_direction','')
  value=explicit(tags);directions.append(value);e['preferred_direction']=value;e['direction_source']='OSM explicit' if value else 'unknown'
  mid=line.length/2;d=np.array(line.interpolate(min(line.length,mid+4)).coords[0])-np.array(line.interpolate(max(0,mid-4)).coords[0]);headings.append(d/max(np.linalg.norm(d),1e-8))
 for i,(e,line) in enumerate(zip(edges,lines)):
  if directions[i] or e.get('service') or e['source']['railway'] not in ('tram','light_rail'):continue
  p=line.interpolate(.5,normalized=True);matches=[];d=headings[i]
  for j in tree.query(p.buffer(8)):
   if j==i or edges[j].get('service') or edges[j]['source']['railway']!=e['source']['railway']:continue
   q=lines[j].interpolate(lines[j].project(p));v=np.array(q.coords[0])-np.array(p.coords[0]);distance=np.linalg.norm(v)
   if not 2.4<distance<8 or abs(np.dot(d,headings[j]))<math.cos(math.radians(15)):continue
   if abs(float(np.mean(e.get('y',[0])))-float(np.mean(edges[j].get('y',[0]))))>1:continue
   right=np.array([-d[1],d[0]]);side=float(np.dot(v,right));matches.append((distance,int(j),side))
  if not matches:continue
  matches.sort();distance,j,side=matches[0]
  if any(m[2]*side<0 and m[0]<distance+.5 for m in matches[1:]):continue
  if directions[j]:value=-directions[j]*(1 if np.dot(d,headings[j])>=0 else -1);kind='parallel explicit track'
  else:value=1 if side<0 else -1;kind='urban right-hand pair'
  e['preferred_direction']=value;e['direction_source']=kind
 path.write_text(json.dumps(n,ensure_ascii=False,separators=(',',':'))+'\n')
 print(path.stem,sum(bool(e['preferred_direction']) for e in edges),'/',len(edges),flush=True)
if __name__=='__main__':
 for path in sorted((ROOT/'data/free').glob('*.json')):enrich(path)
