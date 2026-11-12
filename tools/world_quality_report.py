#!/usr/bin/env python3
"""Inventaire calculé des données livrées et des limites de rapprochement."""
import gzip,hashlib,json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
rows=[]
for path in sorted((ROOT/'data/free').glob('*.json')):
    n=json.loads(path.read_text());sc=json.loads((ROOT/f'data/scenes/{path.stem}.json').read_text());terrain=json.loads((ROOT/f'data/scenes/{path.stem}_terrain.json').read_text())
    buildings={b['source_id'] for d in n['depots'] for b in d.get('buildings',[])}
    row={'id':path.stem,'city':n['city'],'osm_base_date':n['source_date'],'sections':len(n['edges']),
         'service_sections':sum(bool(e['service']) for e in n['edges']),'platform_footprints':len(n.get('platforms',[])),
         'depot_and_yard_sites':len(n['depots']),'named_sites':n['coverage'].get('named_depots',0),'maintenance_buildings':len(buildings),
         'tunnel_sections':sum(bool(e.get('tunnel')) for e in n['edges']),'bridge_sections':sum(bool(e.get('bridge')) for e in n['edges']),
         'unmatched_stations':n['coverage']['unmatched_stations'],'missing_terrain_sections':n['coverage']['missing_terrain_segments'],
         'max_estimated_profile_adjustment_m':n['coverage']['max_profile_adjustment_m'],
         'scenery_tiles_added':sc.get('physical_network_extension_tiles',0),'terrain_tiles':terrain['tiles']}
    rows.append(row)
summary={'networks':len(rows),'commercial_network_files':len(list((ROOT/'data/networks').glob('*.json')))}
for key in ['sections','service_sections','platform_footprints','depot_and_yard_sites','named_sites','maintenance_buildings','tunnel_sections','bridge_sections','scenery_tiles_added']:
    summary[key]=sum(r[key] for r in rows)
missions=[]
for path in sorted((ROOT/'data/networks').glob('*.json')):
    n=json.loads(path.read_text());a=n.get('terrain_alignment',{})
    if a.get('unmatched_vertices'):missions.append({'id':n['id'],'unmatched_vertices':a['unmatched_vertices']})
sources=[]
for path in sorted((ROOT/'data/geography').rglob('*.gz')):
    sources.append({'path':str(path.relative_to(ROOT)),'sha256':hashlib.sha256(path.read_bytes()).hexdigest()})
report={'schema':1,'version':'0.8.0','summary':summary,'networks':rows,'commercial_geometry_exceptions':missions,'source_archives':sources,
        'limitations':['Les axes des missions restent les tracés GTFS ; leur profil vertical est raccordé au réseau physique.',
                       'Les altitudes interpolées, rampes lissées, hauteurs de quai et vitesses par défaut sont estimées.',
                       'Un faisceau de remisage ne représente pas nécessairement un dépôt distinct.',
                       'Les façades et ouvertures des hangars sont stylisées ; emprises et hauteurs proviennent des données source.',
                       'La signalisation et le trafic réel ne sont pas cartographiés dans ces jeux de données.']}
(ROOT/'docs/world-quality.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
print(json.dumps(summary,ensure_ascii=False))
