#!/usr/bin/env python3
"""Compléter les tuiles de décor manquantes le long des vraies voies OSM.
Conserve toutes les tuiles originales (orthophotos incluses), ajoute seulement les
nouvelles tuiles BD TOPO : bâti, voirie, eau, végétation et équipements.
"""
import json,math,struct,tempfile
from pathlib import Path
import ign_scene
ROOT=Path(__file__).resolve().parents[2]

def unpack(data):
    return ign_scene.read_tiles(data)[0]

def pack(tiles):
    return ign_scene.pack_tsc4(tiles)

def extend(city):
    path=ROOT/f'data/scenes/{city}.bin';original=unpack(path.read_bytes());net=json.loads((ROOT/f'data/free/{city}.json').read_text())
    selected=[]
    for e in net['edges']:
        if any((math.floor(x/400),math.floor(z/400)) not in original for x,z in e['pts']):selected.append(e)
    if not selected:return 0
    cache=ROOT/'.cache/geography/ign_scenery';cache.mkdir(parents=True,exist_ok=True)
    print(city,len(selected),'sections à compléter',flush=True)
    with tempfile.TemporaryDirectory() as td:
        td=Path(td);(td/'nets').mkdir();(td/'out').mkdir()
        subset=dict(net,edges=selected);(td/'nets'/f'{city}.json').write_text(json.dumps(subset))
        ign_scene.main(city,str(td/'nets'),str(td/'out'),str(cache))
        extra=unpack((td/'out'/f'{city}.bin').read_bytes());count=0
        for key,block in extra.items():
            if key not in original:original[key]=block;count+=1
        temporary=path.with_suffix(".bin.part");temporary.write_bytes(pack(original));temporary.replace(path)
        mp=path.with_suffix('.json');meta=json.loads(mp.read_text());meta['tiles']=len(original);meta['physical_network_extension_tiles']=count
        meta['extension_source']='IGN BD TOPO (Licence Ouverte 2.0), import des tuiles absentes autour des voies OSM'
        mp.write_text(json.dumps(meta,ensure_ascii=False,indent=1)+'\n')
    return count

if __name__=='__main__':
    for p in sorted((ROOT/'data/free').glob('*.json')):print(p.stem,extend(p.stem),'tuiles ajoutées',flush=True)
