#!/usr/bin/env python3
"""Niveaux réels de voirie IGN près des ouvrages, depuis le cache versionné
par l'import géographique. Lecture hors ligne ; aucune altitude n'est inventée.
"""
import json,struct,math,sys
from pathlib import Path
from shapely.geometry import LineString,box
from shapely.ops import unary_union
from terrain import cached_features,pos_sol,Frame
ROOT=Path(__file__).resolve().parents[2]
def build(city):
 meta=json.loads((ROOT/f'data/scenes/{city}.json').read_text());raw=(ROOT/f'data/scenes/{city}.bin').read_bytes();count=struct.unpack_from('<I',raw,4)[0]
 keys=[struct.unpack_from('<ii',raw,8+i*16) for i in range(count)];size=meta['tile_m'];xmin=min(x for x,z in keys)*size;zmin=min(z for x,z in keys)*size;xmax=(max(x for x,z in keys)+1)*size;zmax=(max(z for x,z in keys)+1)*size
 frame=Frame(*meta['origin']);lat0,lon0=frame.inv(xmin,zmax);lat1,lon1=frame.inv(xmax,zmin);lines=[]
 for ft in cached_features('troncon_de_route',str(ROOT/'.cache/geography/ign_scenery'),(lat0,lon0,lat1,lon1)):
  if not ft.get('geometry'):continue
  g=ft['geometry'];parts=[g['coordinates']] if g['type']=='LineString' else g['coordinates'] if g['type']=='MultiLineString' else []
  for part in parts:
   if len(part)<2:continue
   line=LineString([frame.fwd(p[1],p[0]) for p in part]);level=pos_sol(ft['properties'])
   if line.intersects(box(xmin,zmin,xmax,zmax)):lines.append((line,level))
 raised=[line for line,level in lines if level>0]
 region=unary_union([line.buffer(14) for line in raised]);segments=[]
 for line,level in lines:
  if level<0:continue
  clipped=line.intersection(region)
  pieces=[clipped] if clipped.geom_type=='LineString' else list(clipped.geoms) if clipped.geom_type=='MultiLineString' else []
  for piece in pieces:
   pts=list(piece.simplify(.15).coords)
   for a,b in zip(pts,pts[1:]):segments.append([round(a[0],2),round(a[1],2),round(b[0],2),round(b[1],2),level])
 data={'source':'BD TOPO IGN, position_par_rapport_au_sol, cache de l’import géographique','origin':meta['origin'],'segments':segments}
 (ROOT/f'data/scenes/{city}_road_levels.json').write_text(json.dumps(data,ensure_ascii=False,separators=(',',':'))+'\n')
 print(city,len(segments),flush=True)
if __name__=='__main__':
 identities=json.loads((ROOT/'data/city_identity.json').read_text())
 for city in identities:build(city)
