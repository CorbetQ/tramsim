"""Remplace les résultats de recherche hors sujet par des fichiers identifiés."""
import sys,json
from pathlib import Path
sys.path.insert(0,str(Path(__file__).parent))
from fetch_references import api,field,download,search,INDEX,atomic_index
explicit={'montpellier__citadis_402__3':['File:Alstom Citadis 402 n°2087 TAM Boirargues.jpg','File:Tramway Montpellier Ligne 3 avant.JPG']}

queries={}
data=json.loads(INDEX.read_text())
for e in data['entries']:
 candidates=[]
 if e['id'] in explicit:
  result=api({'titles':'|'.join(explicit[e['id']]),'prop':'imageinfo','iiprop':'url|extmetadata|size','iiurlwidth':900})
  for p in result.get('query',{}).get('pages',{}).values():
   if not p.get('imageinfo'):continue
   i=p['imageinfo'][0];candidates.append(dict(title=p['title'],url=i['descriptionurl'],image_url=i.get('thumburl',i['url']),license=field(i,'LicenseShortName'),license_url=field(i,'LicenseUrl'),author=field(i,'Artist'),description=field(i,'ImageDescription'),date=field(i,'DateTimeOriginal')))
 elif e['id'] in queries:candidates=search(queries[e['id']])
 else:continue
 if not candidates:print('NO_MATCH',e['id'],flush=True);continue
 for k,r in enumerate(candidates[:4]):r['local_image']='references/'+e['id']+'-final-'+str(k+1)+'.jpg';r['review_status']='pending_subject_review';download((e,r))
 e['references']=candidates[:4];atomic_index(data);print(e['id'],[r['title'] for r in e['references']],flush=True)
atomic_index(data)
