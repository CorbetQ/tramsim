#!/usr/bin/env python3
"""Réseaux libres sur les axes de voies OSM : une arête par voie physique.

La topologie est exclusivement celle des identifiants de nœuds OSM : aucun
raccordement par proximité, aucune communication inventée. Les croisements
railway=railway_crossing restent deux voies indépendantes. Les profils IGN
existants sont interpolés près des lignes ; ailleurs on échantillonne le relief
livré. Ces altitudes restent estimées et ne sont pas un relevé ferroviaire.
"""
import argparse, gzip, json, math, sys, re, unicodedata, heapq
from collections import defaultdict
from pathlib import Path
import numpy as np
from scipy.ndimage import gaussian_filter1d
from shapely.geometry import LineString, Point, Polygon
from shapely.strtree import STRtree

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'tools/maintenance'))
from stitch_terrain import read_tiles
R=6371008.8

class Elevation:
    def __init__(self,city,old):
        self.tiles=read_tiles((ROOT/f'data/scenes/{city}_terrain.bin').read_bytes())
        self.alt0=old['alt0'];self.ign={};self.ign_hits=0
        frame=old['origin'];factor=math.cos(math.radians(frame[0]))
        source=ROOT/f'data/geography/ign_rail/{city}.json.gz'
        if source.exists():
            features=json.loads(gzip.decompress(source.read_bytes()))['features']
            by_kind=defaultdict(list)
            for feature in features:
                pr=feature['properties']
                try:kind=int(pr.get('position_par_rapport_au_sol') or 0)
                except (ValueError,TypeError):continue
                if kind==0 or not feature.get('geometry'):continue
                geom=feature['geometry'];ls=[geom['coordinates']] if geom['type']=='LineString' else geom['coordinates'] if geom['type']=='MultiLineString' else []
                for coords in ls:
                    if len(coords)<2 or any(len(p)<3 or not -100<p[2]<5000 for p in coords):continue
                    ps=[[math.radians(p[0]-frame[1])*R*factor,-math.radians(p[1]-frame[0])*R] for p in coords]
                    line=LineString(ps);arc=np.r_[0.,np.cumsum(np.linalg.norm(np.diff(ps,axis=0),axis=1))]
                    by_kind['bridge' if kind>0 else 'tunnel'].append((line,arc,np.array([p[2]-self.alt0 for p in coords])))
            for kind,items in by_kind.items():self.ign[kind]=(STRtree([v[0] for v in items]),items)
        self.edges=[e for e in old['edges'] if len(e.get('pts',[]))>1 and len(e.get('y',[]))==len(e['pts']) and not e.get('raw')]
        self.lines=[LineString(e['pts']) for e in self.edges];self.tree=STRtree(self.lines)
        self.arc=[np.r_[0.,np.cumsum(np.linalg.norm(np.diff(e['pts'],axis=0),axis=1))] for e in self.edges]
    def ground(self,x,z):
        k=(math.floor(x/400),math.floor(z/400))
        if k not in self.tiles:raise ValueError(f'Relief absent à {x:.0f},{z:.0f}')
        g=np.asarray(self.tiles[k][0]).reshape(41,41)
        fx=(x-k[0]*400)/10;fz=(z-k[1]*400)/10
        ix=min(39,int(fx));iz=min(39,int(fz));u=fx-ix;v=fz-iz
        return float(g[iz,ix]*(1-u)*(1-v)+g[iz,ix+1]*u*(1-v)+g[iz+1,ix]*(1-u)*v+g[iz+1,ix+1]*u*v)
    def at(self,p,kind=''):
        pt=Point(p)
        if kind in self.ign:
            tree,items=self.ign[kind];i=int(tree.nearest(pt));line,arc,ys=items[i]
            if line.distance(pt)<14.:
                self.ign_hits+=1
                return float(np.interp(line.project(pt),arc,ys))
        i=int(self.tree.nearest(pt));line=self.lines[i]
        if line.distance(pt)<30:
            return float(np.interp(line.project(pt),self.arc[i],self.edges[i]['y']))
        return self.ground(*p)


def project_profile(edges,max_grade=.08):
    # Projection lipschitzienne sur le graphe entier : deux enveloppes de Dijkstra.
    # La moyenne des enveloppes supérieure et inférieure respecte la rampe sur
    # CHAQUE segment, y compris aux jonctions, sans biais systématique vers le bas.
    vertex_of={};values=[];adj=[];edge_vertices=[]
    def vertex(key,value):
        if key not in vertex_of:vertex_of[key]=len(values);values.append(value);adj.append([])
        return vertex_of[key]
    for e in edges:
        ids=[]
        for j,y in enumerate(e['y']):
            key=e['from'] if j==0 else e['to'] if j==len(e['y'])-1 else (e['id'],j)
            ids.append(vertex(key,y))
        for j in range(len(ids)-1):
            cap=math.dist(e['pts'][j],e['pts'][j+1])*max_grade
            adj[ids[j]].append((ids[j+1],cap));adj[ids[j+1]].append((ids[j],cap))
        edge_vertices.append(ids)
    def envelope(original):
        out=list(original);heap=[(v,i) for i,v in enumerate(out)];heapq.heapify(heap)
        while heap:
            value,i=heapq.heappop(heap)
            if value>out[i]+1e-10:continue
            for j,cost in adj[i]:
                candidate=value+cost
                if candidate<out[j]-1e-10:
                    out[j]=candidate;heapq.heappush(heap,(candidate,j))
        return np.array(out)
    lower=envelope(values);upper=-envelope([-v for v in values]);profile=(lower+upper)*.5
    adjustment=float(np.max(np.abs(profile-np.array(values))))
    for e,ids in zip(edges,edge_vertices):e['y']=profile[ids].tolist()
    return adjustment


def build(city,old,osm):
    origin=old['origin']; k=math.cos(math.radians(origin[0]))
    def project(n):return (math.radians(n['lon']-origin[1])*R*k,-math.radians(n['lat']-origin[0])*R)
    nodes={n['id']:n for n in osm['elements'] if n['type']=='node'}
    ways=[w for w in osm['elements'] if w['type']=='way' and w.get('tags',{}).get('railway') in ('tram','light_rail','rail') and len(w.get('nodes',[]))>=2]
    # Lyon / IDF : éviter les tronçons isolés étrangers au réseau qui peuvent entrer dans la grande emprise.
    # Les voies en chantier sont déjà exclues par railway=construction, sans deviner leur mise en service.
    use=defaultdict(set)
    for w in ways:
        for n in w['nodes']:use[n].add(w['id'])
    cuts={n for n,ws in use.items() if len(ws)>1}
    cuts.update(n for w in ways for n in (w['nodes'][0],w['nodes'][-1]))
    elevation=Elevation(city,old)
    edges=[]; heads=defaultdict(list); missing=[]
    for w in ways:
        tags=w.get('tags',{});seq=[w['nodes'][0]];part=0
        for nid in w['nodes'][1:]:
            seq.append(nid)
            if nid not in cuts:continue
            if not all(n in nodes for n in seq):raise ValueError('Référence OSM absente')
            line=LineString([project(nodes[n]) for n in seq]); L=line.length
            if L<.3:seq=[nid];continue
            # Densification sans lissage latéral : ne pas déplacer les appareils de voie.
            arc=np.linspace(0,L,max(2,math.ceil(L/8)+1));ps=[list(line.interpolate(float(d)).coords[0]) for d in arc]
            kind='tunnel' if tags.get('tunnel','no') not in ('no','false','0','','building_passage') else 'bridge' if tags.get('bridge','no') not in ('no','false','0','') else ''
            hits=elevation.ign_hits
            try:ys=np.array([elevation.at(p,kind) for p in ps])
            except ValueError as ex:missing.append(str(ex));seq=[nid];continue
            if len(ys)>4:ys=gaussian_filter1d(ys,1.,mode='nearest')
            eid=f"osm:{w['id']}:{part}";part+=1
            ends=[f'osm:{seq[0]}',f'osm:{seq[-1]}']
            for end,ni,idx in [(0,seq[0],1),(1,seq[-1],-2)]:
                d=np.array(ps[idx])-np.array(ps[0 if end==0 else -1]);d/=np.linalg.norm(d)
                heads[ends[end]].append((len(edges),end,d))
            service=tags.get('service','');ms=tags.get('maxspeed','')
            try:lim=float(ms.replace(' mph',''))*(1.609344 if 'mph' in ms else 1.)
            except ValueError:lim=15. if service else 50.
            i=int(elevation.tree.nearest(line.interpolate(L*.5)));old_edge=elevation.edges[i]
            near=elevation.lines[i].distance(line.interpolate(L*.5))<30
            e=dict(id=eid,**{'from':ends[0],'to':ends[1]},length=round(L,3),pts=[[round(x,3),round(z,3)] for x,z in ps],
                y=ys.tolist(),grade=0.,physical=True,limit_kmh=lim,service=service,name=tags.get('name',''),
                lines=old_edge.get('lines',[]) if near else [],supply=old_edge.get('supply',old['supply']) if near else old['supply'],
                source={'provider':'OpenStreetMap','way':w['id'],'node_from':seq[0],'node_to':seq[-1],
                        'oneway':tags.get('oneway','unknown'),'layer':tags.get('layer','0'),
                        'rail_elevation':'IGN BD TOPO Z' if elevation.ign_hits>hits else 'interpolated IGN profile/terrain'})
            if tags.get('gauge','').isdigit():e['gauge_mm']=int(tags['gauge'])
            if tags.get('bridge','no') not in ('no','false','0',''):e['bridge']=[[0.,round(L,3)]]
            if tags.get('tunnel','no') not in ('no','false','0','','building_passage'):
                e['tunnel']=[[0.,round(L,3)]]
            if tags.get('tunnel')=='building_passage':e['covered']=True
            edges.append(e);seq=[nid]
    if not edges:raise ValueError('Aucune voie couverte par le relief')
    # Un croisement sans appareil de voie garde deux itinéraires indépendants,
    # même lorsque chacun est découpé en plusieurs ways OSM.
    for key,ends in list(heads.items()):
        node_id=int(key.split(':')[1])
        if nodes[node_id].get('tags',{}).get('railway')!='railway_crossing' or len(ends)<4:continue
        remaining=list(ends);del heads[key];pair=0
        while remaining:
            first=remaining.pop(0);group=[first]
            if remaining:
                j=min(range(len(remaining)),key=lambda j:np.dot(first[2],remaining[j][2]))
                group.append(remaining.pop(j))
            new_key=key+f':cross{pair}';pair+=1;heads[new_key]=group
            for i,end,_ in group:edges[i]['from' if end==0 else 'to']=new_key
    # Même nœud = même altitude et deux côtés géométriques. Aucun assemblage de nœuds voisins.
    for node,ends in heads.items():
        ref=ends[0][2]
        h=float(np.median([edges[i]['y'][0 if end==0 else -1] for i,end,_ in ends]))
        for i,end,d in ends:
            edges[i]['from_side' if end==0 else 'to_side']=1 if np.dot(d,ref)>=0 else -1
            edges[i]['y'][0 if end==0 else -1]=h
    adjustment=project_profile(edges)
    lines=[LineString(e['pts']) for e in edges];tree=STRtree(lines)
    # Parois extérieures uniquement : pas de garde-corps / mur entre deux voies parallèles.
    for i,e in enumerate(edges):
        for field in ('structure_left','structure_right'):e[field]=True
        p=lines[i].interpolate(.5,normalized=True);d=np.array(e['pts'][-1])-np.array(e['pts'][0]);d/=np.linalg.norm(d)
        for j in tree.query(p.buffer(6.)):
            j=int(j)
            if i==j:continue
            q=lines[j].interpolate(lines[j].project(p));v=np.array(q.coords[0])-np.array(p.coords[0]);dist=np.linalg.norm(v)
            other=edges[j];od=np.array(other['pts'][-1])-np.array(other['pts'][0]);od/=np.linalg.norm(od)
            if 2.0<dist<5.5 and abs(np.dot(d,od))>.9 and abs(np.interp(.5,np.linspace(0,1,len(e['y'])),e['y'])-np.interp(.5,np.linspace(0,1,len(other['y'])),other['y']))<1.5:
                side=d[0]*v[1]-d[1]*v[0];e['structure_right' if side>0 else 'structure_left']=False
        e['y']=[round(v,4) for v in e['y']];e['grade']=round((e['y'][-1]-e['y'][0])/e['length'],5)
    stations=[];unsnapped=[];relocated=[];station_keys={}
    def fold(name):return re.sub(r'[^a-z0-9]+','',unicodedata.normalize('NFKD',name).encode('ascii','ignore').decode().lower())
    named_stops=defaultdict(list)
    for node in nodes.values():
        if node.get('tags',{}).get('railway')=='tram_stop' and node['tags'].get('name'):
            named_stops[fold(node['tags']['name'])].append(node)
    by_id={e['id']:e for e in old['edges']}
    for s in old['stations']:
        source=by_id[s['edge']];l=LineString(source['pts']);position=s['offset']/source['length']*l.length
        p=l.interpolate(position);a=l.interpolate(max(0,position-.5));b=l.interpolate(min(l.length,position+.5))
        direction=np.array(b.coords[0])-np.array(a.coords[0]);direction/=max(np.linalg.norm(direction),1e-9)
        p=Point(p.x-direction[1]*1.75,p.y+direction[0]*1.75)
        i=int(tree.nearest(p));dist=lines[i].distance(p)
        source_node=None
        if dist>35:
            matches=named_stops.get(fold(s['name']),[])
            if matches:
                match=min(matches,key=lambda n:Point(project(n)).distance(p))
                delta=Point(project(match)).distance(p)
                if delta<350:
                    p=Point(project(match));source_node=match['id'];i=int(tree.nearest(p));dist=lines[i].distance(p)
                    relocated.append({'name':s['name'],'from_gtfs_m':round(delta,1),'osm_node':source_node})
        if dist>45:unsnapped.append({'name':s['name'],'distance_m':round(dist,1)});continue
        ns=dict(s,edge=edges[i]['id'],offset=round(min(edges[i]['length'],lines[i].project(p)),3),snap_m=round(dist,2))
        heading=np.array(edges[i]['pts'][-1])-np.array(edges[i]['pts'][0])
        ns['direction']=1 if np.dot(heading,direction)>=0 else -1
        if source_node:ns['source_osm_node']=source_node
        key=(ns['name'],ns['edge'],round(ns['offset']/8))
        if key in station_keys:
            previous=station_keys[key];previous['lines']=sorted(set(previous.get('lines',[])+ns.get('lines',[])))
        else:stations.append(ns);station_keys[key]=ns
    # Emprises de dépôt identifiées par leurs voies de remisage (service=yard).
    # L'emprise au sol du bâtiment reste celle de la scène IGN, sans hangar inventé.
    yards=[i for i,e in enumerate(edges) if e['service']=='yard'];clusters=[]
    for i in yards:
        hit=[c for c in clusters if any(lines[i].distance(lines[j])<90 for j in c)]
        group={i}
        for c in hit:group|=c;clusters.remove(c)
        clusters.append(group)
    depots=[]
    areas=[w for w in osm['elements'] if w['type']=='way' and w.get('tags',{}).get('landuse') in ('railway','industrial') and all(n in nodes for n in w.get('nodes',[])) and len(w.get('nodes',[]))>3]
    for num,group in enumerate(clusters,1):
        i=max(group,key=lambda j:edges[j]['length']);mid=lines[i].interpolate(.5,normalized=True);name=''
        for a in areas:
            p=Polygon([project(nodes[n]) for n in a['nodes']])
            if p.is_valid and p.buffer(20).contains(mid):name=a.get('tags',{}).get('name','');break
        depots.append({'name':name or f'Faisceau de remisage {num}', 'kind':'depot' if name else 'yard','position':list(mid.coords[0]),
                       'edge':edges[i]['id'],'offset':round(edges[i]['length']*.5,3),'tracks':[edges[j]['id'] for j in sorted(group)],
                       'source':'OpenStreetMap : service=yard','verified_building':False})
    platforms=[]
    for w in osm['elements']:
        tags=w.get('tags',{})
        if w['type']!='way' or tags.get('public_transport')!='platform' or len(w.get('nodes',[]))<2 or not all(n in nodes for n in w['nodes']):continue
        coords=[project(nodes[n]) for n in w['nodes']]
        if coords[0]!=coords[-1]:continue # emprises seulement, pas de largeur de quai inventée
        polygon=Polygon(coords)
        if not polygon.is_valid or polygon.area<2:continue
        point=polygon.representative_point();i=int(tree.nearest(point))
        if lines[i].distance(point)>35:continue
        ys=[]
        for q in coords[:-1]:
            point=Point(q);j=int(tree.nearest(point));line=lines[j];arc=np.r_[0.,np.cumsum(np.linalg.norm(np.diff(edges[j]['pts'],axis=0),axis=1))]
            ys.append(round(float(np.interp(line.project(point),arc,edges[j]['y'])),4))
        platforms.append({'osm_way':w['id'],'name':tags.get('name',''),'pts':[[round(x,3),round(z,3)] for x,z in coords[:-1]],'y':ys,
                          'height_m':.3,'height_estimated':True,'edge':edges[i]['id']})
    result={k:v for k,v in old.items() if k not in ('edges','nodes','stations','signals','roads','switches','crossovers','turnback_stations')}
    result.update(edges=edges,nodes=sorted(heads),stations=stations,signals=[],roads=[],depots=depots,
        line='réseau physique',long_name='Voies et remisages cartographiés',kind='free',free_only=True,provisional=False,missions=[],platforms=platforms,
        geometry_kind='physical',provenance='OpenStreetMap (ODbL 1.0), voies physiques et topologie des nœuds OSM ; altitudes interpolées des profils IGN existants et du terrain livré.',
        source_date=osm.get('osm3s',{}).get('timestamp_osm_base','unknown'),
        estimated=['altitudes des rails interpolées (pas de relevé ferroviaire)','vitesses lorsque maxspeed absent','alimentation lorsque non renseignée','signalisation réelle et positions des voitures non importées'],
        coverage={'osm_ways':len(ways),'edges':len(edges),'service_edges':sum(bool(e['service']) for e in edges),'yards':len(depots),
                  'unmatched_stations':unsnapped,'relocated_stations':relocated,'platforms':len(platforms),'max_profile_adjustment_m':round(adjustment,3),'missing_terrain_segments':len(missing)})
    return result

if __name__=='__main__':
    ap=argparse.ArgumentParser();ap.add_argument('cities',nargs='*');a=ap.parse_args()
    for path in sorted((ROOT/'data/free').glob('*.json')):
        if a.cities and path.stem not in a.cities:continue
        reference=ROOT/f'data/geography/reference/{path.stem}.json.gz'
        old=json.loads(gzip.decompress(reference.read_bytes()))
        osm=json.loads(gzip.decompress((ROOT/f'data/geography/osm/{path.stem}.json.gz').read_bytes()))
        net=build(path.stem,old,osm)
        path.write_text(json.dumps(net,ensure_ascii=False,separators=(',',':'))+'\n')
        from station_power import enrich
        enrich(path,osm) # quais ouverts, stop_position et alimentation OSM
        print(path.stem,json.dumps(net['coverage'],ensure_ascii=False),flush=True)
