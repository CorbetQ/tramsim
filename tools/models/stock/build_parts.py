#!/usr/bin/env python3
"""Independent animated body GLBs and one normalized paint atlas per body.

No photogrammetric overlays. Uses the same authored geometry as build_stock.py.
The full-bank assets remain a fallback during migration.
"""
import copy
import json
import os
from pathlib import Path
import numpy as np
from PIL import Image
import specs
from layout import Train
from citadis import Citadis
from geom import Builder
from build_stock import LODS, configure_texture_imports

ROOT = Path(specs.ROOT)


def descendants(builder, root):
    result = {root}
    for name in builder.order:
        if builder.nodes[name]['parent'] in result:
            result.add(name)
    return result


def part_texture(source, target, start, length, train_length):
    with Image.open(source) as raw:
        image = raw.convert('RGB')
        width, height = image.size
        side_h = round(height*.625)
        left = max(0, round(start/train_length*width)); right = min(width, max(left+1, round((start+length)/train_length*width)))
        side = image.crop((left,0,right,side_h)).resize((width,side_h),Image.Resampling.LANCZOS)
        result = image.copy();result.paste(side,(0,0))
        limit = 2048 if width>=4096 else (1024 if width>=2048 else width)
        result.thumbnail((limit,limit//2),Image.Resampling.LANCZOS)
        target.parent.mkdir(parents=True,exist_ok=True);result.save(target,optimize=True)


def export_part(builder, module, train, destination, atlas, original_dir, index):
    root = 'module_%02d' % index
    names = descendants(builder,root)
    result = Builder(root)
    result.nodes = {n:copy.deepcopy(builder.nodes[n]) for n in builder.order if n in names}
    result.nodes[root]['parent'] = None
    result.order = [n for n in builder.order if n in names]
    result.base = builder.nodes[root]['pos'].copy()
    result.mats = copy.deepcopy(builder.mats)
    start = module['z0f']; length = module['Lm']
    for (node, material), pieces in builder.geo.items():
        if node not in names: continue
        adjusted=[]
        for positions,normals,uv,indices in pieces:
            uv=uv.copy()
            if material.startswith('livery'):
                side=uv[:,1]<.625
                uv[side,0]=(uv[side,0]*train.L-start)/length
            adjusted.append((positions,normals,uv,indices))
        result.geo[(node,material)]=adjusted
    for name, material in result.mats.items():
        for slot in ('tex','normal','orm','emissive_tex'):
            if not material.get(slot): continue
            source=original_dir/material[slot]
            if name.startswith('livery') and slot=='tex':
                target=atlas
            else:
                category='interior' if any(x in source.name for x in ('fabric','floor','cab_')) else ('lights' if 'screen' in source.name else 'materials')
                target=ROOT/'tram_livery'/category/train.spec['network']/source.name
                target.parent.mkdir(parents=True,exist_ok=True)
                if not target.exists() or target.read_bytes()!=source.read_bytes():target.write_bytes(source.read_bytes())
            material[slot]=os.path.relpath(target,destination.parent).replace(os.sep,'/')
    # The suffix lets runtime painting identify the body without global UV assumptions.
    rename={n:n+'__part_%02d'%index for n in result.mats}
    result.mats={rename[n]:v for n,v in result.mats.items()}
    result.geo={(n,rename[m]):p for (n,m),p in result.geo.items()}
    destination.parent.mkdir(parents=True,exist_ok=True)
    return result.export(str(destination),generator='TramSim independent animated body / build_parts.py')


def main():
    mp=ROOT/'data/rolling_stock/parts_manifest.json'
    old=json.loads(mp.read_text()) if mp.exists() else {}
    manifest={'schema':1,'variants':{},'native':old.get('native',{})}
    for vid in specs.VARIANTS:
        spec=specs.load(vid);train=Train(spec)
        original=ROOT/'assets/models/rolling_stock'/spec['dir']
        recipe_dir=ROOT/'tram_parts/compositions'/vid;recipe_dir.mkdir(parents=True,exist_ok=True)
        entry={'lods':{},'modules':[],'livery':spec['network'],'front_style':spec['front_style']}
        for filename,q,tag in LODS:
            builder=Citadis(train,q,tag).build();rows=[]
            for i,module in enumerate(train.mods):
                category='extremites' if i in (0,len(train.mods)-1) else ('motrices' if module['bogie_z'] is not None else 'suspendues')
                role='end_a' if i==0 else ('end_b' if i==len(train.mods)-1 else ('powered' if category=='motrices' else 'suspended'))
                target=ROOT/'tram_parts'/category/spec['dir']/('caisse_%02d_%s.glb'%(i,filename))
                atlas=ROOT/'tram_livery/livery'/spec['network']/spec['dir']/('caisse_%02d_%s.png'%(i,tag))
                if not atlas.exists():part_texture(original/('textures/livery_%s.png'%tag),atlas,module['z0f'],module['Lm'],train.L)
                tris=export_part(builder,module,train,target,atlas,original,i)
                rows.append({'file':'res://'+target.relative_to(ROOT).as_posix(),'index':i,'role':role,'length_m':module['Lm'],'center_z':module['zc'],'texture':'res://'+atlas.relative_to(ROOT).as_posix(),'triangles':tris})
            recipe=recipe_dir/(filename+'.json');recipe.write_text(json.dumps({'schema':1,'variant':vid,'parts':rows},indent=2)+'\n')
            entry['lods'][filename]='res://'+recipe.relative_to(ROOT).as_posix()
            if q==0:entry['modules']=rows
        manifest['variants'][vid]=entry
        print(vid,len(train.mods),'independent bodies',flush=True)
    for directory in (ROOT/'tram_livery').rglob('*'):
        if directory.is_dir():configure_texture_imports(directory)
    (ROOT/'data/rolling_stock/parts_manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')


if __name__=='__main__':main()
