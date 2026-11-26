#!/usr/bin/env python3
"""One geometry kit per cab design. Counts/types are assembly parameters only."""
import copy
import json
from pathlib import Path
import re
import sys
import specs
from layout import Train
from citadis import Citadis
from build_parts import export_part, part_texture, relocate_cab
from build_stock import LODS, configure_texture_imports, SRC
from geom import Builder
from build_parts import descendants

ROOT=Path(specs.ROOT)
INDEX=ROOT/'data/rolling_stock/parts_manifest.json'


def kit_id(entry):
    cab=entry['cab_profile']
    special={'irigo305':'angers_x05','irigo302':'angers_x02','naolib':'nantes_x05',
             'tfs_nantes':'tfs1','tfs_paris':'tfs2','tfs_grenoble':'tfs2'}
    return special.get(cab,re.sub('[^a-z0-9_]+','_',cab.lower()))


def physical_module(module,length):
    result=copy.deepcopy(module);ratio=length/result['length_m'];result['length_m']=length
    for d in result.get('doors',[]):d['z_m']*=ratio
    for w in result.get('windows',[]):w['z0_m']*=ratio;w['z1_m']*=ratio
    for r in result.get('roof',[]):r['z_m']*=ratio
    if 'bogie_z_m' in result:result['bogie_z_m']*=ratio
    return result


def part_keys(modules):
    keys=[];first={}
    for i,m in enumerate(modules):
        role='end_a' if i==0 else ('end_b' if i==len(modules)-1 else ('powered' if m.get('bogie') else 'suspended'))
        key=role
        # A door-bearing motor and a motor without doors are different components,
        # independent of how many times they are used in a train.
        if key in first and len(modules[first[key]].get('doors',[]))!=len(m.get('doors',[])):
            key+='_doors' if m.get('doors') else '_nodoor'
        first.setdefault(key,i);keys.append(key)
    return keys,first


def export_equipment(builder,destination,original):
    names=descendants(builder,'panto_base');result=Builder('pantograph')
    result.nodes={n:copy.deepcopy(builder.nodes[n]) for n in builder.order if n in names}
    result.order=[n for n in builder.order if n in names]
    result.nodes['panto_base']['parent']=None;result.base=builder.nodes['panto_base']['pos'].copy()
    result.geo={(n,m):v for (n,m),v in builder.geo.items() if n in names}
    used={m for n,m in result.geo};result.mats={m:copy.deepcopy(builder.mats[m]) for m in used}
    for material in result.mats.values():
        for slot in ('tex','normal','orm','emissive_tex'):
            if material.get(slot):
                target=ROOT/'tram_livery/materials'/destination.parent.name/Path(material[slot]).name
                target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes((original/material[slot]).read_bytes())
                import os
                material[slot]=os.path.relpath(target,destination.parent).replace(os.sep,'/')
    destination.parent.mkdir(parents=True,exist_ok=True)
    return result.export(str(destination))


def main():
    entries=json.loads((ROOT/'data/rolling_stock/variants/index.json').read_text())['entries']
    groups={}
    for e in entries:groups.setdefault(kit_id(e),[]).append(e)
    only_hd='--hd-only' in sys.argv
    result=json.loads(INDEX.read_text()) if only_hd else {'schema':2,'kits':{},'variants':{},'liveries':{}}
    if result.get('schema')!=2:raise ValueError('Canonical schema 2 required for --hd-only')
    hd_master={'angers_x05':'angers__citadis_x05','angers_x02':'angers__citadis_302','nantes_x05':'nantes__citadis_x05_nantes'}
    # P4 : --kits=a,b (ou --kits=all) convertit ces kits en HD ; leur maître est la variante déjà maître du kit natif
    for arg in sys.argv[1:]:
        if arg.startswith('--kits='):
            wanted=arg[7:].split(',')
            for kid in groups:
                if kid not in hd_master and (wanted==['all'] or kid in wanted):
                    previous=result.get('kits',{}).get(kid)
                    old=json.loads((ROOT/previous.replace('res://','')).read_text()) if previous else {}
                    hd_master[kid]=old.get('master') or max(groups[kid],key=lambda e:e['module_count'])['id']
    if only_hd and '--kits=' in ' '.join(sys.argv):
        hd_master={k:v for k,v in hd_master.items() if k in wanted or wanted==['all']}
    for kid,rows in groups.items():
        if only_hd and kid not in hd_master:continue
        real=[e for e in rows if not e.get('fictional')]
        master=next((e for e in rows if e['id']==hd_master.get(kid)),max(real or rows,key=lambda e:e['module_count']))
        kit={'schema':2,'id':kid,'renderer':'hd' if kid in hd_master else 'native','master':master['id'],
             'master_count':master['module_count'],'master_length':master['length'],'parts':{},'layout':[],
             'presets':{},'frame':{},'cab':{}}
        for e in rows:
            type_=re.search(r'\b(205|301|302|305|401|402|403|405)\b',e['name'])
            type_=type_.group() if type_ else str(e['module_count'])+'-caisses'
            kit['presets'].setdefault(type_,{'count':e['module_count'],'length_m':e['length']})
            result['variants'][e['id']]={'kit':kid,'type':type_,'count':e['module_count'],'length_m':e['length'],
                                        'livery':kid if kit['renderer']=='hd' else ''}
        path=ROOT/'tram_parts/compositions'/(kid+'.json');path.parent.mkdir(parents=True,exist_ok=True)
        result['kits'][kid]='res://'+path.relative_to(ROOT).as_posix()
        if kit['renderer']=='hd':
            sp=specs.load(master['id']);train=Train(sp)
            original=(ROOT/'assets/models/rolling_stock' if master['id'] in specs.VARIANTS else Path(SRC))/sp['dir']
            kit['nose_profile']=copy.deepcopy(train.nose_style())
            plans=[physical_module(m,float(t['Lm'])) for m,t in zip(sp['plan_data']['modules'],train.mods)]
            keys,prototypes=part_keys(plans);kit['layout']=keys
            kit['master_lengths']=[m['Lm'] for m in train.mods]
            kit['frame']=copy.deepcopy(sp['plan_data']);kit['frame'].pop('modules',None)
            kit['frame']['front'].update(sp['plan_data']['front'])
            result['liveries'][kid]={'kit':kid,'parts':{}}
            panto_module=next(i for i,m in enumerate(plans) if any(r['type']=='pantograph' for r in m.get('roof',[])))
            panto_roof=next(r for r in plans[panto_module]['roof'] if r['type']=='pantograph')
            kit['equipment']={'pantograph':{'models':{},'triangles':{},'role':('powered' if plans[panto_module].get('bogie') else 'suspended'),
                'z_ratio':panto_roof['z_m']/plans[panto_module]['length_m'],'mount_y':train.h,'roof':copy.deepcopy(panto_roof)}}
            body_spec=copy.deepcopy(sp);body_spec['suppress_panto_geometry']=True;body_train=Train(body_spec)
            equipment_spec=copy.deepcopy(sp);equipment_spec['preserve_nodes']=True;equipment_train=Train(equipment_spec)
            for key,i in prototypes.items():
                plan=plans[i];role='end_a' if i==0 else ('end_b' if i==len(plans)-1 else ('powered' if plan.get('bogie') else 'suspended'))
                kit['parts'][key]={'role':role,'source_index':i,'root':'module_%02d'%i,'plan':plan,'length_m':plan['length_m'],
                                   'pantograph':False,
                                   'door_count':len(plan.get('doors',[])),'models':{},'triangles':{},'bindings':{}}
                result['liveries'][kid]['parts'][key]={}
                kit['parts'][key]['plan']['roof']=[r for r in plan.get('roof',[]) if r['type']!='pantograph']
            for filename,q,tag in LODS:
                builder=Citadis(body_train,q,tag).build()
                if q<=3:
                    gear=Citadis(equipment_train,q,tag).build()
                    target=ROOT/'tram_parts/equipements'/kid/('pantograph_'+filename+'.glb')
                    tri=export_equipment(gear,target,original)
                    kit['equipment']['pantograph']['models'][filename]='res://'+target.relative_to(ROOT).as_posix()
                    kit['equipment']['pantograph']['triangles'][filename]=tri
                for key,i in prototypes.items():
                    p=kit['parts'][key];category='extremites' if p['role'].startswith('end_') else ('motrices' if p['role']=='powered' else 'suspendues')
                    target=ROOT/'tram_parts'/category/kid/(key+'_'+filename+'.glb')
                    atlas=ROOT/'tram_livery/livery'/kid/(key+'_'+tag+'.png')
                    if tag not in result['liveries'][kid]['parts'][key]:
                        part_texture(original/('textures/livery_%s.png'%tag),atlas,train.mods[i]['z0f'],train.mods[i]['Lm'],train.L)
                    tri=export_part(builder,train.mods[i],train,target,atlas,original,i)
                    p['models'][filename]='res://'+target.relative_to(ROOT).as_posix();p['triangles'][filename]=tri
                    result['liveries'][kid]['parts'][key][tag]='res://'+atlas.relative_to(ROOT).as_posix()
            # P4 : livrées propres aux autres variantes du kit (réseau ou famille différents) : mêmes caisses, atlas dédiés
            if master['id'] not in specs.VARIANTS:
                import families, tempfile
                from citadis import materials, swatch_colors
                import textures as TX
                done={families.livery_key(master):kid}
                for e in rows:
                    key_=families.livery_key(e)
                    if key_ not in done:
                        lid='%s_%s_%s'%(kid,e['network'],key_);done[key_]=lid
                        other=copy.deepcopy(sp);auto=families.auto_spec(e['id'],kid)
                        for k in ('colors','livery_res','network','seat'):other[k]=auto[k]
                        t2=Train(other);Bm=Builder();materials(Bm,t2,0,'4k')
                        tmp=Path(tempfile.mkdtemp(prefix='liv_',dir=SRC))
                        TX.Painter(t2).paint().swatches(swatch_colors(Bm)).save(str(tmp),'livery')
                        result['liveries'][lid]={'kit':kid,'parts':{}}
                        for key,i in prototypes.items():
                            result['liveries'][lid]['parts'][key]={}
                            for _f,_q,tag in LODS:
                                if tag in result['liveries'][lid]['parts'][key]:continue
                                atlas=ROOT/'tram_livery/livery'/lid/(key+'_'+tag+'.png')
                                part_texture(tmp/('livery_%s.png'%tag),atlas,train.mods[i]['z0f'],train.mods[i]['Lm'],train.L)
                                result['liveries'][lid]['parts'][key][tag]='res://'+atlas.relative_to(ROOT).as_posix()
                    result['variants'][e['id']]['livery']=done[key_]
            for name in ('cab','cab_m'):
                target=ROOT/'tram_parts/extremites'/kid/(name+'.glb')
                relocate_cab(original/(name+'.glb'),target,sp['network'],kid)
                kit['cab'][name]='res://'+target.relative_to(ROOT).as_posix()
        path.write_text(json.dumps(kit,indent=2)+'\n')
    out=next((Path(a[12:]) for a in sys.argv if a.startswith('--index-out=')),INDEX)
    out.write_text(json.dumps(result,indent=2)+'\n')
    if out!=INDEX:return
    for directory in (ROOT/'tram_livery').rglob('*'):
        if directory.is_dir():configure_texture_imports(directory)
    if only_hd:print(len(hd_master),'HD design kits rebuilt; native kits and livery banks preserved')
    else:print(len(groups),'canonical design kits; native geometry/textures: tools/models/export_native_parts.gd')


if __name__=='__main__':main()
