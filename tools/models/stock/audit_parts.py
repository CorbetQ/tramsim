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
    report={'schema':2,'variants':{},'errors':[],'bodies':0,'model_bytes':0,'texture_bytes':0}
    measured={};textures={};kits={}
    def model(value,triangles=None):
        path=resource(root,value,'tram_parts')
        if path not in measured:
            data=path.read_bytes()
            if path.suffix=='.glb':
                info=glb_info(path,root/'tram_livery')
                if triangles is not None and info['triangles']!=triangles:raise ValueError('Wrong measured triangle count')
                for uri in info['textures']:
                    image=(path.parent/uri).resolve()
                    texture('res://'+image.relative_to(root.resolve()).as_posix())
            elif path.suffix!='.scn' or data[:4] not in (b'RSCC',b'RSRC'):raise ValueError('Invalid model resource')
            measured[path]={'sha256':hashlib.sha256(data).hexdigest(),'bytes':len(data)}
    def texture(value):
        path=resource(root,value,'tram_livery')
        if path not in textures:
            raw=path.read_bytes()
            if raw[:8]!=b'\x89PNG\r\n\x1a\n':raise ValueError('Invalid PNG')
            w,h=struct.unpack_from('>II',raw,16)
            if not (0<w<=4096 and 0<h<=2048):raise ValueError('Invalid texture dimensions')
            textures[path]={'sha256':hashlib.sha256(raw).hexdigest(),'bytes':len(raw),'width':w,'height':h}
    if manifest.get('schema')!=2:report['errors'].append('Canonical kit schema required')
    for kid,value in manifest.get('kits',{}).items():
        try:
            kit=json.loads(resource(root,value,'tram_parts').read_text());kits[kid]=kit
            if kit['id']!=kid or kit['schema']!=2:raise ValueError('Wrong kit identity')
            layout=kit['layout'];parts=kit['parts']
            if len(layout)!=kit['master_count'] or parts[layout[0]]['role']!='end_a' or parts[layout[-1]]['role']!='end_b':raise ValueError('Wrong body order/count')
            if abs(sum(kit['master_lengths'])-kit['master_length'])>.02:raise ValueError('Wrong master length')
            for key,part in parts.items():
                if part['length_m']<=0 or not math.isfinite(part['length_m']):raise ValueError('Invalid body dimension')
                if part['door_count']!=len(part['plan'].get('doors',[])):raise ValueError('Door count differs from body plan')
                category='extremites' if part['role'].startswith('end_') else ('motrices' if part['role']=='powered' else 'suspendues')
                for lod,value in part['models'].items():
                    path=resource(root,value,'tram_parts')
                    if path.parent.name!=kid or path.parent.parent.name!=category:raise ValueError('Model must belong to canonical design/role, not a type')
                    model(value,part.get('triangles',{}).get(lod))
                if part.get('palette'):texture(part['palette'])
            for value in kit.get('cab',{}).values():model(value)
            for gear in kit.get('equipment',{}).values():
                for lod,value in gear.get('models',{}).items():model(value,gear.get('triangles',{}).get(lod))
        except (OSError,ValueError,KeyError,TypeError,IndexError) as error:report['errors'].append(kid+': '+str(error))
    for vid,entry in catalogue.items():
        try:
            ref=manifest['variants'][vid];kit=kits[ref['kit']]
            if ref['count']!=entry['module_count'] or abs(ref['length_m']-entry['length'])>.02:raise ValueError('Wrong variant assembly parameters')
            style=manifest['liveries'][ref['livery']]
            if style['kit']!=kit['id']:raise ValueError('Incompatible paint kit')
            for key in kit['parts']:
                for value in style['parts'][key].values():texture(value)
            report['bodies']+=ref['count']
            report['variants'][vid]={'bodies':ref['count'],'pipeline':kit['renderer'],'kit':kit['id'],'livery':ref['livery']}
        except (OSError,ValueError,KeyError,TypeError) as error:report['errors'].append(vid+': '+str(error))
    report['kits']=len(kits)
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
