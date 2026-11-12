#!/usr/bin/env python3
"""Niveler le sol sous les voies au sol ; préserver les ponts et tunnels documentés.
Les sommets communs sont soudés après traitement. Le relief hors du corridor de
14 m reste intact. À relancer après tout nouvel import d'altitude / de topologie.
"""
import json,sys,hashlib
from pathlib import Path
import numpy as np
from scipy.spatial import cKDTree
from stitch_terrain import read_tiles,stitch,encode
ROOT=Path(__file__).resolve().parents[2]

def signature(net):
    return hashlib.sha256(json.dumps([(e['id'],e['pts'],e['y'],e.get('bridge'),e.get('tunnel')) for e in net['edges']],separators=(',',':')).encode()).hexdigest()

def conform(city):
    net=json.loads((ROOT/f'data/free/{city}.json').read_text());samples=[];heights=[]
    meta_path=ROOT/f'data/scenes/{city}_terrain.json';meta=json.loads(meta_path.read_text());fingerprint=signature(net)
    if meta.get('ground_profile_signature')==fingerprint:
        print(city,'profil déjà conforme',flush=True);return
    for e in net['edges']:
        if e.get('bridge') or e.get('tunnel'):continue
        for p,y in zip(e['pts'],e['y']):samples.append(p);heights.append(y-.13)
    if not samples:return
    tree=cKDTree(samples);heights=np.asarray(heights);path=ROOT/f'data/scenes/{city}_terrain.bin';tiles=read_tiles(path.read_bytes())
    gx,gz=np.meshgrid(np.arange(41)*10.,np.arange(41)*10.);changed=0
    for (tx,tz),tile in tiles.items():
        q=np.stack([(gx+tx*400).ravel(),(gz+tz*400).ravel()],axis=1)
        dist,index=tree.query(q,distance_upper_bound=14.);valid=np.isfinite(dist)
        if not valid.any():continue
        old=np.asarray(tile[0]);target=heights[np.minimum(index,len(heights)-1)]
        weight=np.where(valid,np.clip((14-dist)/9.,0,1),0)
        result=old*(1-weight)+target*weight
        tile[0]=result.tolist();changed+=int(valid.sum())
    stitch(tiles);path.write_bytes(encode(tiles))
    meta['ground_profile_signature']=fingerprint;meta['ground_conformity']='sol adapté aux voies au sol, ponts et tunnels préservés'
    meta_path.write_text(json.dumps(meta,ensure_ascii=False,indent=1)+'\n')
    print(city,changed,'sommets nivelés',flush=True)

if __name__=='__main__':
    for p in sorted((ROOT/'data/free').glob('*.json')):conform(p.stem)
