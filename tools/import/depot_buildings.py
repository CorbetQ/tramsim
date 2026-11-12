#!/usr/bin/env python3
"""Hangars réels BD TOPO traversés par des voies de remisage OSM.
Ne crée ni hangar générique ni emprise fictive. Les ouvertures suivent les voies ;
leur architecture reste stylisée. Les fichiers source compressés sont conservés.
"""
import concurrent.futures,gzip,json,math,time,urllib.parse,urllib.request
from pathlib import Path
import numpy as np
from shapely.geometry import LineString,Polygon,shape,box
from shapely.ops import transform,unary_union
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'data/geography/depot_buildings';OUT.mkdir(exist_ok=True)
R=6371008.8;URL='https://data.geopf.fr/wfs/ows'

def enrich(path):
    net=json.loads(path.read_text());lat,lon=net['origin'];factor=math.cos(math.radians(lat));alt0=net['alt0']
    def project(x,y,z=None):return (math.radians(x-lon)*R*factor,-math.radians(y-lat)*R)
    def inverse(x,z):return lat-math.degrees(z/R),lon+math.degrees(x/(R*factor))
    edges={e['id']:e for e in net['edges']};cache=OUT/(path.stem+'.json.gz');sources={};queries=[]
    if cache.exists():
        previous=json.loads(gzip.decompress(cache.read_bytes()));sources={f['id']:f for f in previous['features']};queries=previous.get('requests',[])
    try:
        for depot in net.get('depots',[]):
            tracks=[LineString(edges[e]['pts']) for e in depot['tracks']];yard=unary_union(tracks);candidates=[]
            minx,minz,maxx,maxz=yard.buffer(35).bounds
            la0,lo0=inverse(minx,maxz);la1,lo1=inverse(maxx,minz)
            covered=False
            for url in queries:
                query=urllib.parse.parse_qs(urllib.parse.urlparse(url).query)
                bbox=query.get('BBOX',[''])[0].split(',')
                if len(bbox)>=4:
                    a,b,c,d=map(float,bbox[:4]);covered=covered or (a<=la0+1e-7 and b<=lo0+1e-7 and c>=la1-1e-7 and d>=lo1-1e-7)
            if not covered:
                bb=f'{la0},{lo0},{la1},{lo1},urn:ogc:def:crs:EPSG::4326'
                q={'SERVICE':'WFS','VERSION':'2.0.0','REQUEST':'GetFeature','TYPENAMES':'BDTOPO_V3:batiment','BBOX':bb,'COUNT':'5000','OUTPUTFORMAT':'application/json'}
                request=URL+'?'+urllib.parse.urlencode(q);queries.append(request)
                for attempt in range(3):
                    try:
                        page=json.loads(urllib.request.urlopen(request,timeout=35).read())
                        if 'features' not in page:raise ValueError('WFS sans features')
                        if len(page['features'])>=5000:raise ValueError('Emprise trop grande, pagination requise')
                        break
                    except Exception:
                        if attempt==2:raise
                        time.sleep(2)
                for f in page['features']:sources[f['id']]=f
            for f in sources.values():
                if not f.get('geometry'):continue
                g=transform(project,shape(f['geometry']))
                if not g.intersects(yard):continue
                parts=[g] if g.geom_type=='Polygon' else list(g.geoms) if g.geom_type=='MultiPolygon' else []
                for poly in parts:
                    if poly.area<80 or not poly.intersects(yard):continue
                    h=f['properties'].get('hauteur')
                    if h is None or not 4.5<=float(h)<=40:continue
                    p=poly.simplify(.3,preserve_topology=True)
                    # Au niveau des rails, puis hauteur de bâti IGN ; le sol n'est pas recalé à zéro.
                    sampled=[];portal_tracks=[]
                    for eid,line in zip(depot['tracks'],tracks):
                        if not line.intersects(poly):continue
                        e=edges[eid];arc=np.r_[0.,np.cumsum(np.linalg.norm(np.diff(e['pts'],axis=0),axis=1))]
                        for q in list(line.intersection(poly).geoms) if line.intersection(poly).geom_type=='MultiLineString' else [line.intersection(poly)]:
                            if q.geom_type!='LineString':continue
                            for xy in q.coords:sampled.append(float(np.interp(line.project(__import__('shapely').geometry.Point(xy)),arc,e['y'])))
                        portal_tracks.append(eid)
                    if not sampled:continue
                    candidates.append({'source_id':f['id'],'pts':[[round(x,3),round(z,3)] for x,z in list(p.exterior.coords)[:-1]],
                                       'height_m':float(h),'base_y':round(float(np.median(sampled)),3),'portal_tracks':portal_tracks})
            depot['buildings']=candidates;depot['verified_building']=bool(candidates)
        source={'provider':'IGN BD TOPO','licence':'Licence Ouverte 2.0','features':list(sources.values()),'requests':queries}
        cache.write_bytes(gzip.compress(json.dumps(source,separators=(',',':')).encode(),mtime=0))
        path.write_text(json.dumps(net,ensure_ascii=False,separators=(',',':'))+'\n')
        return path.stem,sum(len(d['buildings']) for d in net.get('depots',[]))
    except Exception as e:return path.stem,'ERREUR '+str(e)

if __name__=='__main__':
    errors=0
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        for city,count in pool.map(enrich,sorted((ROOT/'data/free').glob('*.json'))):
            print(city,count,'bâtiments',flush=True);errors+=int('ERREUR' in str(count))
    raise SystemExit(1 if errors else 0)
