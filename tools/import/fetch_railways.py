#!/usr/bin/env python3
"""Extraits OSM reproductibles : vraies voies, voies de service et emprises ferroviaires.
Cache gzip conservé dans le dépôt avec les métadonnées Overpass (date de la base).
Deux requêtes concurrentes maximum ; aucune extrapolation si une source manque.
"""
import argparse, concurrent.futures, gzip, json, math, time, urllib.parse, urllib.request
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
ENDPOINT='https://overpass.openstreetmap.fr/api/interpreter'

def bounds(net):
    lat,lon=net['origin']; k=math.cos(math.radians(lat)); r=6371008.8
    ps=[p for e in net['edges'] for p in e.get('pts',[])]
    # Inclure les ateliers au-delà des terminus commerciaux.
    return (lat-math.degrees((max(p[1] for p in ps)+1500)/r),
            lon+math.degrees((min(p[0] for p in ps)-1500)/(r*k)),
            lat-math.degrees((min(p[1] for p in ps)-1500)/r),
            lon+math.degrees((max(p[0] for p in ps)+1500)/(r*k)))

def fetch(path):
    city=path.stem; out=ROOT/'data/geography/osm'/f'{city}.json.gz'
    if out.exists():
        cached=json.loads(gzip.decompress(out.read_bytes()))
        if cached.get('tramsim_source',{}).get('schema')==3:return city,'cache'
    reference=ROOT/f'data/geography/reference/{city}.json.gz'
    net=json.loads(gzip.decompress(reference.read_bytes())) if reference.exists() else json.loads(path.read_text())
    bbox=bounds(net); bb=','.join(f'{v:.6f}' for v in bbox)
    query=f'[out:json][timeout:35];(rel[route~"^(tram|light_rail)$"]({bb});rel[route=train][ref~"^(TT|T4|T11|T12|T13)$"]({bb});)->.routes;(way[railway=tram]({bb});way[railway=light_rail]({bb});way(r.routes)[railway=rail];way(r.routes)[public_transport=platform];way[public_transport=platform][tram=yes]({bb});nwr[landuse=industrial][name~"depot|dépôt|maintenance|exploitation",i]({bb});way[landuse=railway]({bb});nwr[depot=tram]({bb});nwr[railway=depot]({bb}););out body;>;out body qt;'
    for attempt in range(3):
        try:
            request=urllib.request.Request(ENDPOINT+'?data='+urllib.parse.quote(query),headers={'User-Agent':'TramSim-source-import/0.8'})
            raw=urllib.request.urlopen(request,timeout=50).read(); d=json.loads(raw)
            if d.get('remark') or not d.get('elements'):raise ValueError(d.get('remark','extrait vide'))
            d['tramsim_source']={'schema':3,'endpoint':ENDPOINT,'bbox':bbox,'licence':'ODbL 1.0','query':query}
            out.write_bytes(gzip.compress(json.dumps(d,ensure_ascii=False,separators=(',',':')).encode(),mtime=0))
            return city,f"{len(d['elements'])} éléments"
        except Exception as e:
            if attempt==2:return city,f'ERREUR {e}'
            time.sleep(3*(attempt+1))

if __name__=='__main__':
    ap=argparse.ArgumentParser();ap.add_argument('cities',nargs='*');a=ap.parse_args()
    paths=[p for p in sorted((ROOT/'data/free').glob('*.json')) if not a.cities or p.stem in a.cities]
    errors=0
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        for city,msg in pool.map(fetch,paths):
            print(city,msg,flush=True);errors+=int('ERREUR' in str(msg))
    raise SystemExit(1 if errors else 0)
