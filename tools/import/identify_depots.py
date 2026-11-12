#!/usr/bin/env python3
"""Identifier les dépôts nommés OSM même si les voies utilisent service=siding.
Fusionne les faisceaux d'un même site ; conserve les faisceaux sans nom séparément.
"""
import gzip,json,math
from pathlib import Path
from shapely.geometry import LineString,Point,Polygon
ROOT=Path(__file__).resolve().parents[2];R=6371008.8

def identify(path):
    net=json.loads(path.read_text());lat,lon=net['origin'];k=math.cos(math.radians(lat))
    def project(p):return (math.radians(p['lon']-lon)*R*k,-math.radians(p['lat']-lat)*R)
    source=json.loads(gzip.decompress((ROOT/f'data/geography/osm/{path.stem}.json.gz').read_bytes()))
    extra=ROOT/f'data/geography/osm/depot_{path.stem}.json.gz'
    if extra.exists():source['elements']+=json.loads(gzip.decompress(extra.read_bytes()))['elements']
    nodes={n['id']:n for n in source['elements'] if n['type']=='node'}
    areas=[]
    for area in source['elements']:
        tags=area.get('tags',{});name=tags.get('name','') or ('Dépôt cartographié' if tags.get('landuse')=='depot' else '')
        if area['type']=='way' and tags.get('landuse') in ('industrial','railway','depot') and name and (tags.get('landuse')=='depot' or any(w in name.lower() for w in ('dépôt','depot','maintenance','exploitation'))):
            if len(area.get('nodes',[]))<4 or not all(n in nodes for n in area['nodes']):continue
            polygon=Polygon([project(nodes[n]) for n in area['nodes']])
            if polygon.is_valid:areas.append((name,polygon,f"way/{area['id']}"))
    edges={e['id']:e for e in net['edges']};lines={e['id']:LineString(e['pts']) for e in net['edges']}
    depots=list(net.get('depots',[]))
    for name,polygon,source_id in areas:
        selected=[eid for eid,line in lines.items() if line.intersection(polygon).length>3]
        if not selected:continue
        # Une voie commerciale longeant un dépôt de bus ne suffit pas à créer un dépôt de tram.
        service=[eid for eid in selected if edges[eid]['service']]
        if not service and len(selected)<3:continue
        selected=set(selected);previous=[d for d in depots if selected.intersection(d['tracks'])]
        for d in previous:selected.update(d['tracks']);depots.remove(d)
        e=max((edges[eid] for eid in selected),key=lambda e:e['length']);point=lines[e['id']].interpolate(.5,normalized=True)
        depots.append({'name':name,'kind':'depot','position':list(point.coords[0]),'edge':e['id'],'offset':round(e['length']*.5,3),
                       'tracks':sorted(selected),'source':f'OpenStreetMap {source_id}, emprise nommée','verified_building':False})
    net['depots']=sorted(depots,key=lambda d:d['name']);net['coverage']['yards']=len(depots);net['coverage']['named_depots']=sum(d['kind']=='depot' and d['name']!='Dépôt cartographié' for d in depots)
    path.write_text(json.dumps(net,ensure_ascii=False,separators=(',',':'))+'\n')
    print(path.stem,len(depots),'sites,',net['coverage']['named_depots'],'nommés',flush=True)

if __name__=='__main__':
    for path in sorted((ROOT/'data/free').glob('*.json')):identify(path)
