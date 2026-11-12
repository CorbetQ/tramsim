#!/usr/bin/env python3
"""Étendre le relief IGN aux vraies voies et ateliers absents du corridor GTFS initial."""
import gzip,json,math,sys
from pathlib import Path
import numpy as np
from terrain import Dem,Frame,SCRATCH
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'tools/maintenance'))
from stitch_terrain import read_tiles,stitch,encode

def extend(city):
    path=ROOT/f'data/scenes/{city}_terrain.bin';tiles=read_tiles(path.read_bytes())
    meta=json.loads(path.with_suffix('.json').read_text());scene=json.loads((ROOT/f'data/scenes/{city}.json').read_text())
    frame=Frame(*scene['origin']);wanted=set()
    osm=json.loads(gzip.decompress((ROOT/f'data/geography/osm/{city}.json.gz').read_bytes()))
    ns={e['id']:e for e in osm['elements'] if e['type']=='node'}
    for w in osm['elements']:
        if w['type']!='way' or w.get('tags',{}).get('railway') not in ('tram','light_rail','rail'):continue
        for n in w['nodes']:
            x,z=frame.fwd(ns[n]['lat'],ns[n]['lon']);k=(math.floor(x/400),math.floor(z/400))
            wanted.update((k[0]+dx,k[1]+dz) for dx in (-1,0,1) for dz in (-1,0,1))
    missing=sorted(wanted-tiles.keys())
    if not missing:return 0
    print(city,'extension',len(missing),'tuiles',flush=True)
    dem=Dem(frame,str(Path(SCRATCH)/'dem'),city)
    gx,gz=np.meshgrid(np.arange(41)*10.,np.arange(41)*10.)
    for k in missing:
        heights=dem(gx+k[0]*400,gz+k[1]*400)-meta['alt0']
        tiles[k]=[heights.ravel().tolist(),b'\x00\x00\x00'] # pas de niveau d'eau / tablier inventé
    stitch(tiles);temporary=path.with_suffix(".bin.part");temporary.write_bytes(encode(tiles));temporary.replace(path)
    meta.update(tiles=len(tiles),extension_source='IGN RGE ALTI WMS, emprise des voies physiques OSM',extended_tiles=len(missing))
    path.with_suffix('.json').write_text(json.dumps(meta,ensure_ascii=False,indent=1)+'\n')
    return len(missing)

if __name__=='__main__':
    for p in sorted((ROOT/'data/free').glob('*.json')):
        try:print(p.stem,extend(p.stem),'ajoutées',flush=True)
        except Exception as e:print(p.stem,'ERREUR',e,flush=True);raise
