#!/usr/bin/env python3
"""Raccorder les missions commerciales à la même altimétrie / aux mêmes ouvrages que le réseau physique.
Les horaires et le graphe commercial GTFS restent inchangés ; la projection horizontale
GTFS est conservée et les écarts > 25 m sont signalés, jamais raccordés de force.
"""
import json,math
from pathlib import Path
import numpy as np
from shapely.geometry import LineString,Point
from shapely.strtree import STRtree
from physical_network import project_profile
from terrain import spans
ROOT=Path(__file__).resolve().parents[2];R=6371008.8

def update(path,free):
    net=json.loads(path.read_text());lat,lon=net['origin'];clat,clon=free['origin'];k=math.cos(math.radians(lat));ck=math.cos(math.radians(clat))
    edges=free['edges'];lines=[LineString(e['pts']) for e in edges];tree=STRtree(lines)
    arcs=[np.r_[0.,np.cumsum(np.linalg.norm(np.diff(e['pts'],axis=0),axis=1))] for e in edges]
    far=0
    for e in net['edges']:
        ps=np.array(e.get('pts',[]))
        if len(ps)<2:continue
        qs=ps.copy();qs[:,0]=ps[:,0]*ck/k+math.radians(lon-clon)*R*ck;qs[:,1]=ps[:,1]-math.radians(lat-clat)*R
        flags={'bridge':[],'tunnel':[]};ys=[]
        for j,q in enumerate(qs):
            p=Point(q);index=int(tree.nearest(p));distance=lines[index].distance(p)
            if distance>25:
                far+=1;ys.append(e['y'][j]);flags['bridge'].append(False);flags['tunnel'].append(False);continue
            arc=lines[index].project(p)
            ys.append(float(np.interp(arc,arcs[index],edges[index]['y']))+free['alt0']-net.get('alt0',free['alt0']))
            for kind in flags:flags[kind].append(bool(edges[index].get(kind)))
        e['y']=ys
        # Intervalles calculés dans l'abscisse de jeu de la mission, pas dans le repère du décor.
        arc=np.r_[0.,np.cumsum(np.linalg.norm(np.diff(ps,axis=0),axis=1))];arc*=e['length']/max(arc[-1],.001)
        for kind,mask in flags.items():
            intervals=[];start=None
            for j,active in enumerate(mask):
                if active and start is None:start=max(0.,(arc[j-1]+arc[j])*.5) if j else 0.
                if start is not None and (not active or j==len(mask)-1):
                    end=(arc[j-1]+arc[j])*.5 if not active else arc[j]
                    if end>start:intervals.append([round(start,3),round(end,3)])
                    start=None
            if intervals:e[kind]=intervals
            else:e.pop(kind,None)
        e.pop('trench',None)
    adjustment=project_profile(net['edges'])
    for e in net['edges']:
        e['y']=[round(y,4) for y in e['y']];e['grade']=round((e['y'][-1]-e['y'][0])/e['length'],5)
    net['terrain_alignment']={'source':'réseau physique OSM + profils IGN','unmatched_vertices':far,'max_gradient_adjustment_m':round(adjustment,3),'horizontal_geometry':'GTFS conservé'}
    path.write_text(json.dumps(net,ensure_ascii=False,separators=(',',':'))+'\n')
    print(path.stem,'sommets hors rapprochement',far,flush=True)

if __name__=='__main__':
    cities={p.stem:json.loads(p.read_text()) for p in (ROOT/'data/free').glob('*.json')}
    for path in sorted((ROOT/'data/networks').glob('*.json')):
        city=json.loads(path.read_text()).get('source_id')
        if city in cities:update(path,cities[city])
