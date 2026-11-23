#!/usr/bin/env python3
"""Offline independent-body inventory, paths, textures, actual triangles and budgets."""
import argparse
import hashlib
import json
import math
import struct
from pathlib import Path
from audit_stock import ROOT, glb_info


def resource(root, value, folder):
    if not isinstance(value,str) or not value.startswith('res://'+folder+'/'):
        raise ValueError('Wrong resource category: '+str(value))
    path=(root/value[6:]).resolve()
    if not path.is_relative_to((root/folder).resolve()) or not path.is_file():
        raise ValueError('Missing/escaping resource: '+value)
    return path


def audit(root=ROOT):
    manifest=json.loads((root/'data/rolling_stock/parts_manifest.json').read_text())
    catalogue={e['id']:e for e in json.loads((root/'data/rolling_stock/variants/index.json').read_text())['entries']}
    report={'schema':1,'variants':{},'errors':[],'bodies':0,'model_bytes':0,'texture_bytes':0}
    measured={};textures={}
    if set(manifest['variants']) & set(manifest['native']):report['errors'].append('Variant duplicated between pipelines')
    for vid,entry in catalogue.items():
        try:
            hd=manifest['variants'].get(vid)
            bodies=hd['modules'] if hd else manifest['native'][vid]
            if len(bodies)!=entry['module_count']:raise ValueError('Wrong body count')
            if abs(sum(row['length_m'] for row in bodies)-entry['length'])>.02:raise ValueError('Wrong assembled length')
            report['bodies']+=len(bodies)
            recipes=[json.loads(resource(root,p,'tram_parts').read_text()) for p in hd['lods'].values()] if hd else [{'parts':bodies}]
            if hd:
                for cab in hd.get('cab',{}).values():
                    path=resource(root,cab,'tram_parts');info=glb_info(path,root/'tram_livery')
                    measured[path]={'sha256':info['sha256'],'bytes':info['bytes']}
            for recipe in recipes:
                rows=recipe['parts']
                if len(rows)!=len(bodies):raise ValueError('LOD body count changed')
                for i,row in enumerate(rows):
                    if row['index']!=i or not math.isfinite(row['length_m']) or row['length_m']<=0:raise ValueError('Invalid body index/dimension')
                    role=row['role']
                    if (i==0 and role!='end_a') or (i==len(rows)-1 and role!='end_b'):raise ValueError('End design order changed')
                    model=resource(root,row['file'],'tram_parts');texture=resource(root,row['texture'],'tram_livery')
                    category='extremites' if role.startswith('end_') else ('motrices' if role=='powered' else 'suspendues')
                    if model.relative_to(root/'tram_parts').parts[0]!=category:raise ValueError('Incorrect body category')
                    data=model.read_bytes()
                    if model not in measured:
                        if model.suffix=='.glb':
                            info=glb_info(model,root/'tram_livery')
                            if info['triangles']!=row['triangles']:raise ValueError('Wrong measured triangle count')
                            image_paths={(model.parent/uri).resolve() for uri in info['textures']}
                            if texture not in image_paths:raise ValueError('Body paint atlas not bound to the GLB')
                            json_length=struct.unpack_from('<I',data,12)[0]
                            doc=json.loads(data[20:20+json_length])
                            if 'module_%02d'%i not in {node.get('name') for node in doc['nodes']}:raise ValueError('Wrong body root/index')
                        elif data[:4] not in (b'RSCC',b'RSRC'):raise ValueError('Invalid Godot body resource')
                        measured[model]={'sha256':hashlib.sha256(data).hexdigest(),'bytes':len(data)}
                    if texture not in textures:
                        raw=texture.read_bytes()
                        if raw[:8]!=b'\x89PNG\r\n\x1a\n':raise ValueError('Invalid PNG')
                        width,height=struct.unpack_from('>II',raw,16)
                        if width>4096 or height>2048 or width<1 or height<1:raise ValueError('Invalid body texture dimensions')
                        textures[texture]={'sha256':hashlib.sha256(raw).hexdigest(),'bytes':len(raw),'width':width,'height':height}
            report['variants'][vid]={'bodies':len(bodies),'pipeline':'gltf' if hd else 'godot','front_design':entry['cab_profile']}
        except (OSError,ValueError,KeyError,TypeError) as error:report['errors'].append(vid+': '+str(error))
    report['model_bytes']=sum(v['bytes'] for v in measured.values());report['texture_bytes']=sum(v['bytes'] for v in textures.values())
    report['model_files']={str(k.relative_to(root)):v for k,v in measured.items()}
    report['texture_files']={str(k.relative_to(root)):v for k,v in textures.items()}
    return report


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--report',default='build/tram-parts/audit.json');args=parser.parse_args()
    report=audit();path=Path(args.report);path.parent.mkdir(parents=True,exist_ok=True);path.write_text(json.dumps(report,indent=2)+'\n')
    print('%d variants, %d independent bodies, %d errors'%(len(report['variants']),report['bodies'],len(report['errors'])))
    for error in report['errors']:print('FAIL:',error)
    raise SystemExit(bool(report['errors']))
if __name__=='__main__':main()
