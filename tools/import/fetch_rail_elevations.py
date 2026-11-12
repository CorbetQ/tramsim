#!/usr/bin/env python3
"""Altitudes et ouvrages BD TOPO IGN ; cache source, pagination et provenance conservés."""
import concurrent.futures, gzip, json, time, urllib.parse, urllib.request
from pathlib import Path
from fetch_railways import ROOT, bounds

OUT=ROOT/'data/geography/ign_rail';OUT.mkdir(parents=True,exist_ok=True)
ENDPOINT='https://data.geopf.fr/wfs/ows'
def fetch(path):
    out=OUT/(path.stem+'.json.gz')
    if out.exists():return path.stem,'cache'
    # Référence commerciale avant reconstruction, pour garder exactement la même emprise.
    ref=ROOT/'.cache/free_reference'/path.name
    bb=bounds(json.loads((ref if ref.exists() else path).read_text()))
    feats=[];start=0
    try:
        while True:
            q={'SERVICE':'WFS','VERSION':'2.0.0','REQUEST':'GetFeature','TYPENAMES':'BDTOPO_V3:troncon_de_voie_ferree',
               'BBOX':','.join(str(v) for v in bb)+',urn:ogc:def:crs:EPSG::4326','COUNT':'5000','STARTINDEX':str(start),'OUTPUTFORMAT':'application/json'}
            for attempt in range(3):
                try:
                    raw=urllib.request.urlopen(ENDPOINT+'?'+urllib.parse.urlencode(q),timeout=40).read();page=json.loads(raw)
                    if 'features' not in page:raise ValueError('Réponse WFS sans features')
                    break
                except Exception:
                    if attempt==2:raise
                    time.sleep(3)
            feats.extend(f for f in page['features'] if f['properties'].get('nature')=='Tramway')
            if len(page['features'])<5000:break
            start+=5000
        d={'type':'FeatureCollection','features':feats,'source':{'provider':'IGN BD TOPO','endpoint':ENDPOINT,'bbox':bb,'licence':'Licence Ouverte 2.0'}}
        out.write_bytes(gzip.compress(json.dumps(d,separators=(',',':')).encode(),mtime=0))
        return path.stem,f'{len(feats)} tronçons'
    except Exception as e:return path.stem,'ERREUR '+str(e)

if __name__=='__main__':
    errors=0
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as p:
        for city,msg in p.map(fetch,sorted((ROOT/'data/free').glob('*.json'))):
            print(city,msg,flush=True);errors+=int('ERREUR' in str(msg))
    raise SystemExit(1 if errors else 0)
