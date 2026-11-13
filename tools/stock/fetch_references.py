#!/usr/bin/env python3
"""Références de rames avec attributions ; pas de photographie sans licence conservée."""
import json,subprocess,urllib.parse,hashlib,re,html,time,sys
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
ROOT=Path(__file__).resolve().parents[2];CACHE=ROOT/'.cache/stock-references';OUT=ROOT/'docs/rolling-stock-rebuild';INDEX=ROOT/'data/rolling_stock/variants/index.json'
CACHE.mkdir(parents=True,exist_ok=True);(OUT/'references').mkdir(parents=True,exist_ok=True)
(OUT/'.gdignore').touch()
def api(params):
 url='https://commons.wikimedia.org/w/api.php?'+urllib.parse.urlencode(dict(action='query',format='json',**params));path=CACHE/(hashlib.sha256(url.encode()).hexdigest()+'.json')
 if path.exists():return json.loads(path.read_text())
 r=subprocess.run(['curl','-LsS','--max-time','45','-A','TramSimStockResearch/0.12 (reference collection for local development)','-w','\n%{http_code}',url],capture_output=True,text=True);raw,status=r.stdout.rsplit('\n',1)
 if status=='429':raise RuntimeError('RATE_LIMITED: recherche suspendue pour respecter Commons')
 if status!='200':raise RuntimeError('HTTP '+status)
 data=json.loads(raw);path.write_text(raw);time.sleep(10);return data
def field(info,name):return html.unescape(re.sub('<[^>]+>','',info.get('extmetadata',{}).get(name,{}).get('value',''))).strip()
def search(query):
 data=api(dict(generator='search',gsrsearch=query+' filetype:bitmap',gsrnamespace=6,gsrlimit=10,prop='imageinfo',iiprop='url|extmetadata|size',iiurlwidth=900))
 out=[]
 for p in data.get('query',{}).get('pages',{}).values():
  if not p.get('imageinfo'):continue
  i=p['imageinfo'][0];lic=field(i,'LicenseShortName')
  if not (lic.startswith('CC ') or lic in ['CC0','Public domain']):continue
  if not re.search(r'\.(jpg|jpeg|png|webp)$',p['title'],re.I):continue
  if re.search(r'interior|intérieur|interieur|logo|diagram|drawing|plan du|réseau|reseau|ticket|livr[eé]e.*svg',p['title'],re.I):continue
  if int(i.get('width',0))<500:continue
  out.append(dict(title=p['title'],url=i['descriptionurl'],image_url=i.get('thumburl',i['url']),author=field(i,'Artist'),license=lic,license_url=field(i,'LicenseUrl'),date=field(i,'DateTimeOriginal'),description=field(i,'ImageDescription')[:1200],original_pixels=[i.get('width'),i.get('height')],source_index=p.get('index',99)))
 return sorted(out,key=lambda p:p['source_index'])
def download(pair):
 row,ref=pair;target=OUT/ref['local_image'];target.parent.mkdir(parents=True,exist_ok=True)
 if target.exists() and ref.get('sha256') and hashlib.sha256(target.read_bytes()).hexdigest()==ref['sha256']:return
 r=subprocess.run(['curl','-fLsS','--max-time','45','--max-filesize','6000000','-o',str(target),ref['image_url']],capture_output=True)
 if r.returncode:ref['download_error']=r.returncode
 else:ref['sha256']=hashlib.sha256(target.read_bytes()).hexdigest();ref.pop('download_error',None)
def atomic_index(data):
 temporary=INDEX.with_suffix('.tmp');temporary.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n');temporary.replace(INDEX)
def main():
 data=json.loads(INDEX.read_text());history=[]
 history_path=OUT/'reference-search.json'
 if history_path.exists():history=json.loads(history_path.read_text())
 for row in data['entries']:
  if row['fictional']:continue
  if len(sys.argv)>1 and row['id'] not in sys.argv[1:]:continue
  if row.get('references') and all(r.get('external_only') or r.get('sha256') and (OUT/r['local_image']).exists() for r in row['references']):continue
  try:
   candidates=search(row['search_query'])
   if len(candidates)<3:
    city=row['city'] if row['network']!='idf' else 'Paris '+row['line'].upper()
    for p in search('tramway '+city):
     if not any(c['title']==p['title'] for c in candidates):candidates.append(p)
   selected=candidates[:4]
   for i,ref in enumerate(selected):ref['local_image']='references/'+row['id']+'-'+str(i+1)+'.jpg';ref['review_status']='pending_subject_review'
   row['references']=selected
   with ThreadPoolExecutor(max_workers=3) as pool:list(pool.map(download,[(row,r) for r in selected]))
   history.append(dict(id=row['id'],query=row['search_query'],candidates=[p['title'] for p in candidates],selected=[p['title'] for p in selected]));print(row['id'],len(selected),[p['title'] for p in selected],flush=True)
   atomic_index(data)
  except Exception as ex:
   print(row['id'],str(ex),flush=True)
   if 'RATE_LIMITED' in str(ex):break
 for row in data['entries']:
  if not row['fictional']:continue
  ref=next(e for e in data['entries'] if e['id']==row['inspired_by']);row['references']=json.loads(json.dumps(ref['references']))
  for image in row['references']:image['role']='Inspiration réelle ; cette rame fictive n’existe pas.'
 atomic_index(data);(OUT/'reference-search.json').write_text(json.dumps(history,ensure_ascii=False,indent=2)+'\n')
if __name__=='__main__':main()
