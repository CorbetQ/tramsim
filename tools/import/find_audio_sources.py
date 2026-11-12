#!/usr/bin/env python3
"""Recherche Commons par famille ; seules des métadonnées sont versionnées.
Les binaires sources restent dans .cache/audio_sources, hors des exports.
"""
import json,subprocess,urllib.parse,hashlib,re,html,time
from pathlib import Path
from datetime import datetime,timezone
ROOT=Path(__file__).resolve().parents[2]
QUERIES={'citadis_302':'Citadis 302','citadis_402':'Citadis 402','citadis_x01':'Citadis 301','citadis_x05':'Citadis 405','citadis_x05_nantes':'Citadis Nantes','citadis_403_strasbourg':'Citadis 403','citadis_reims':'Citadis Reims','citadis_tours':'Citadis Tours','citadis_compact':'Citadis Compact','tfs':'Nantes tramway','incentro':'Incentro','flexity_marseille':'Marseille tramway','urbos':'Urbos','eurotram':'Eurotram','avanto':'Avanto','citadis_dualis':'Dualis','tango_rhonexpress':'Stadler Tango','vevey_saint_etienne':'Saint Etienne tramway','breda_vlc':'Lille tramway','translohr':'Translohr'}
def api(params):
 cache=ROOT/'.cache/audio_sources/metadata';cache.mkdir(parents=True,exist_ok=True)
 url='https://commons.wikimedia.org/w/api.php?'+urllib.parse.urlencode(dict(action='query',format='json',**params));path=cache/(hashlib.sha256(url.encode()).hexdigest()+'.json')
 if path.exists():return json.loads(path.read_text())
 for attempt in range(3):
  try:
   raw=subprocess.check_output(['curl','-f','-L','-s','--max-time','20',url]);result=json.loads(raw);path.write_bytes(raw);time.sleep(.8);return result
  except subprocess.CalledProcessError:
   if attempt==2:raise
   time.sleep(1.5)
def value(info,key):return html.unescape(re.sub('<[^>]+>','',info.get('extmetadata',{}).get(key,{}).get('value',''))).strip()
def main():
 rows=[]
 for family,term in QUERIES.items():
  query=term+' filetype:video ; '+term+' filetype:audio'
  try:
   hits=[];errors=[]
   for kind in ['audio','video']:
    try:hits.extend(api({'list':'search','srnamespace':6,'srlimit':4,'srsearch':term+' filetype:'+kind}).get('query',{}).get('search',[]))
    except Exception as ex:errors.append(kind+': '+str(ex))
   candidates=[]
   if hits:
    result=api({'prop':'imageinfo','titles':'|'.join(hit['title'] for hit in hits),'iiprop':'url|extmetadata|size|mediatype'})
    for page in result.get('query',{}).get('pages',{}).values():
     if not page.get('imageinfo'):continue
     info=page['imageinfo'][0]
     media=info.get('mediatype') or ('VIDEO' if info.get('width',0)>0 else 'AUDIO')
     if not info.get('duration'):continue
     candidates.append(dict(title=page['title'],page=info.get('descriptionurl'),url=info.get('url'),bytes=info.get('size'),media_type=media,license=value(info,'LicenseShortName'),license_url=value(info,'LicenseUrl'),author=value(info,'Artist')))
   rows.append(dict(family=family,query=query,candidates=candidates,errors=errors,status='candidates' if candidates else ('source_unavailable' if errors else 'no_reusable_capture_identified_yet')))
   print(family,len(candidates),[(c['title'],c['license'],round(c['bytes']/1e6,1)) for c in candidates[:3]],flush=True)
  except Exception as ex:rows.append(dict(family=family,query=query,candidates=[],status='source_unavailable',error=str(ex)));print(family,str(ex),flush=True)
 (ROOT/'docs/audio-research.json').write_text(json.dumps({'searched_at':datetime.now(timezone.utc).isoformat(),'provider':'Wikimedia Commons API','families':rows},ensure_ascii=False,indent=2)+'\n')
if __name__=='__main__':main()
