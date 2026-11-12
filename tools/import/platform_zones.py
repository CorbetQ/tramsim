#!/usr/bin/env python3
"""Zones d'arrêt et recouvrement LAC/APS dérivés des quais OSM déjà livrés.
Aucun déplacement de voie/quai ni changement d'horaire. Une seule continuité
alignée est suivie aux nœuds ; les voies de service sont exclues.
"""
import json, math, unicodedata, re
from pathlib import Path
import numpy as np
from shapely.geometry import LineString, Polygon, Point
ROOT = Path(__file__).resolve().parents[2]

def norm(s):
    return re.sub('[^a-z0-9]', '', unicodedata.normalize('NFKD', s).encode('ascii', 'ignore').decode().lower())

class Network:
    def __init__(self, data):
        self.data = data
        self.edges = {e['id']: e for e in data['edges']}
        self.lines = {k: LineString(e['pts']) for k,e in self.edges.items()}
        self.incident = {}
        for k,e in self.edges.items():
            for node in [e['from'],e['to']]: self.incident.setdefault(node,[]).append(k)
    def point(self, k, off):
        e=self.edges[k]; line=self.lines[k]
        return line.interpolate(off / e['length'] * line.length)
    def tangent(self,k,off):
        e=self.edges[k]; a=np.array(self.point(k,max(0,off-1)).coords[0]); b=np.array(self.point(k,min(e['length'],off+1)).coords[0]); d=b-a
        return d/max(np.linalg.norm(d),1e-9)
    def walk(self,k,off,direction,budget=130):
        pieces=[]; seen=set()
        while budget>0.001 and k not in seen:
            seen.add(k); e=self.edges[k]; end=min(e['length'],off+budget) if direction>0 else max(0,off-budget)
            if abs(end-off)>0.001: pieces.append((k,off,end))
            budget-=abs(end-off)
            node=e['to'] if direction>0 else e['from']; heading=self.tangent(k,end)*direction; choices=[]
            for candidate in self.incident[node]:
                other=self.edges[candidate]
                if candidate in seen or other.get('service'): continue
                dr=1 if other['from']==node else -1; at=0 if dr>0 else other['length']
                alignment=float(np.dot(heading,self.tangent(candidate,at)*dr))
                if alignment>.65: choices.append((-alignment,candidate,dr,at))
            if not choices: break
            choices.sort(); _,k,direction,off=choices[0]
        return pieces
    def path(self,s):
        backward=self.walk(s['edge'],s['offset'],-1)
        forward=self.walk(s['edge'],s['offset'],1)
        pieces=[(k,b,a) for k,a,b in reversed(backward)]+forward
        points=[]; spans=[]; total=0.
        for k,a,b in pieces:
            length=abs(b-a)*self.lines[k].length/self.edges[k]['length']; coords=[self.point(k,a+(b-a)*t).coords[0] for t in np.linspace(0,1,max(2,math.ceil(length/2)+1))]
            points.extend(coords if not points else coords[1:]);spans.append((k,a,b,total,total+length)); total+=length
        return LineString(points),spans,sum(abs(b-a)*self.lines[k].length/self.edges[k]['length'] for k,a,b in backward)
    def segments(self,spans,lo,hi):
        out=[]
        for k,a,b,start,end in spans:
            l=max(lo,start);h=min(hi,end)
            if h-l<.02: continue
            x=a+(b-a)*(l-start)/(end-start);y=a+(b-a)*(h-start)/(end-start)
            out.append([k,round(min(x,y),3),round(max(x,y),3)])
        return out
    def boundaries(self,spans):
        intervals=[]
        junctions=[]
        for k,a,b,start,end in spans:
            e=self.edges[k]; cuts=sorted(set([min(a,b),max(a,b)]+[max(min(a,b),min(max(a,b),float(v))) for z in e.get('supply_zones',[]) for v in z[:2]]))
            for x,y in zip(cuts,cuts[1:]):
                if y-x<.001:continue
                mode=e.get('supply',self.data.get('supply','overhead'))
                for z in e.get('supply_zones',[]):
                    if z[0]<=(x+y)/2<z[1]:mode=z[2];break
                l=start+(x-a)/(b-a)*(end-start);h=start+(y-a)/(b-a)*(end-start)
                intervals.append((min(l,h),max(l,h),mode))
            # La section APS peut être sur la branche courbe, tandis que la
            # continuité la plus droite reste sous LAC (Foch–Maison Bleue).
            for off,at in [(a,start),(b,end)]:
                if min(abs(off),abs(off-e['length']))>.02:continue
                node=e['from'] if off<.02 else e['to'];modes=set()
                for branch in self.incident[node]:
                    other=self.edges[branch]
                    if other.get('service'):continue
                    x=.001 if other['from']==node else max(0,other['length']-.001)
                    mode=other.get('supply',self.data.get('supply','overhead'))
                    for zone in other.get('supply_zones',[]):
                        if zone[0]<=x<zone[1]:mode=zone[2];break
                    modes.add(mode)
                if {'aps','overhead'}.issubset(modes):junctions.append(at)
        intervals.sort();result=[]
        for left,right in zip(intervals,intervals[1:]):
            if {left[2],right[2]}=={'overhead','aps'} and abs(left[1]-right[0])<.05:result.append(right[0])
        return sorted(set(result+junctions))

def enrich(path):
    data=json.loads(path.read_text());net=Network(data);platforms=[]
    for p in data.get('platforms',[]):
        shape=Polygon(p['pts'])
        if shape.is_valid: platforms.append((p,shape))
    matched=0;transitions=0;overlaps={}
    for s in data['stations']:
        s.pop('stop_area',None)
        if not platforms: continue
        marker=net.point(s['edge'],s['offset'])
        near=[(p,shape) for p,shape in platforms if shape.distance(marker)<95 and (not p.get('name') or norm(p['name'])==norm(s['name']))]
        if not near: continue
        line,spans,zero=net.path(s); candidates=[]
        for p,shape in near:
            distance=shape.distance(line)
            if distance>12:continue
            projected=[line.project(Point(pt)) for pt in shape.exterior.coords]
            lo,hi=min(projected),max(projected)
            if hi-lo<8 or hi-lo>150 or zero<lo-12 or zero>hi+12:continue
            # Le quai le plus proche de cette voie, et non celui d'en face.
            candidates.append((distance+shape.distance(marker)*.01,p['osm_way'],p,lo,hi))
        if not candidates:continue
        _,_,p,lo,hi=min(candidates,key=lambda c:(c[0],c[1]))
        lo=max(0,min(lo,zero)-1);hi=min(line.length,max(hi,zero)+1)
        segments=net.segments(spans,lo,hi)
        s['stop_area']={'segments':segments,'source':'OSM platform projection','osm_way':p['osm_way'],'margin_m':1.0}
        matched+=1
        boundaries=net.boundaries(spans)
        boundary=min(boundaries,key=lambda b:max(lo-b,0,b-hi)) if boundaries else None
        if boundary is not None and max(lo-boundary,0,boundary-hi)<=30:
            transitions+=1;s['stop_area']['power_transition']=True
            for k,a,b in net.segments(spans,min(lo,boundary),max(hi,boundary)):
                overlaps.setdefault(k,[]).append([a,b])
    for e in data['edges']:
        e.pop('power_overlaps',None)
        merged=[]
        for lo,hi in sorted(overlaps.get(e['id'],[])):
            if merged and lo<=merged[-1][1]+.02:merged[-1][1]=max(hi,merged[-1][1])
            else:merged.append([lo,hi])
        if merged:e['power_overlaps']=merged
    data['stop_area_source']='OSM platform projection; nearest aligned track continuity; 1 m stop margin; dual LAC/APS when a mapped boundary is within 30 m of the platform'
    path.write_text(json.dumps(data,ensure_ascii=False,separators=(',',':'))+'\n')
    return {'file':str(path.relative_to(ROOT)) if path.is_relative_to(ROOT) else path.name,'stations':len(data['stations']),'platform_stop_areas':matched,'transition_stations':transitions,'dual_track_segments':len(overlaps)}

def main():
    report=[]
    for directory in ['networks','free']:
        for path in sorted((ROOT/'data'/directory).glob('*.json')):
            result=enrich(path);report.append(result);print(result,flush=True)
    (ROOT/'docs/platform-zones.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')

if __name__=='__main__':main()
