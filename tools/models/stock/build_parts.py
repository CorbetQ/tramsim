#!/usr/bin/env python3
"""Independent animated body GLBs and one normalized paint atlas per body.

No photogrammetric overlays. Uses the same authored geometry as build_stock.py.
The full-bank assets remain a fallback during migration.
"""
import copy
import json
import os
import struct
from pathlib import Path
import numpy as np
from PIL import Image
import specs
from layout import Train
from citadis import Citadis
from geom import Builder
from build_stock import LODS, configure_texture_imports

ROOT = Path(specs.ROOT)


def relocate_cab(source, destination, network, design):
    raw=source.read_bytes();size,kind=struct.unpack_from('<II',raw,12)
    doc=json.loads(raw[20:20+size]);binary=raw[20+size:]
    for image in doc.get('images',[]):
        original=(source.parent/image['uri']).resolve()
        category='interior' if 'metal' not in original.name else 'materials'
        target=ROOT/'tram_livery'/category/network/design/original.name
        target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(original.read_bytes())
        image['uri']=os.path.relpath(target,destination.parent).replace(os.sep,'/')
    encoded=json.dumps(doc,separators=(',',':'),ensure_ascii=False).encode()
    encoded+=b' '*((-len(encoded))%4)
    destination.parent.mkdir(parents=True,exist_ok=True)
    destination.write_bytes(struct.pack('<4sII',b'glTF',2,20+len(encoded)+len(binary))+struct.pack('<II',len(encoded),kind)+encoded+binary)


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
    from build_kits import main as build
    build()


if __name__ == '__main__':main()
