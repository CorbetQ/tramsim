import sys,json
from pathlib import Path
sys.path.insert(0,str(Path(__file__).parent))
from fetch_references import api,search,download,field,atomic_index,INDEX
categories={'angers__citadis_x05':'Citadis 305 trams in Angers','marseille__urbos':'Urbos 3 in Marseille','besancon__citadis_x05':'Alstom Citadis 305 in Besançon','lille__citadis_x05':'Citadis trams in Lille','idf__citadis_x05__t1':'Citadis trams in Paris' }
queries={'lyon__citadis_x05':'"Lyon" "Citadis 405"','nice__citadis_x05':'"Nice" "Citadis 405"','nice__citadis_x05__t2':'"Nice" "Citadis 405"','montpellier__urbos':'"Montpellier" "CAF" -intérieur -interior -ecran -maquette','montpellier__urbos__5':'"Montpellier" "Urbos" -intérieur -interior -ecran -maquette','montpellier__citadis_402__1':'"Montpellier" "hirondelles" tram','montpellier__citadis_402__3':'"Montpellier" "ligne 3" tramway','idf__citadis_302__t2':'"Citadis" "T2" "Paris"','idf__citadis_x05__t1':'"Citadis 305" "T1"','besancon__citadis_x05':'"Besançon" "Citadis"','toulouse__citadis_302__ae':'"Toulouse" "Citadis"'}
data=json.loads(INDEX.read_text())
for e in data['entries']:
 if e['id'] not in categories and e['id'] not in queries:continue
 candidates=[]
 if e['id'] in categories:
  response=api({'generator':'categorymembers','gcmtitle':'Category:'+categories[e['id']],'gcmtype':'file','gcmlimit':30,'prop':'imageinfo','iiprop':'url|extmetadata|size','iiurlwidth':900})
  for p in response.get('query',{}).get('pages',{}).values():
   if not p.get('imageinfo'):continue
   i=p['imageinfo'][0];lic=field(i,'LicenseShortName')
   if not (lic.startswith('CC ') or lic in ['CC0','Public domain']):continue
   if not p['title'].lower().endswith(('.jpg','.jpeg','.png','.webp')):continue
   candidates.append(dict(title=p['title'],url=i['descriptionurl'],image_url=i.get('thumburl',i['url']),author=field(i,'Artist'),license=lic,license_url=field(i,'LicenseUrl'),date=field(i,'DateTimeOriginal'),description=field(i,'ImageDescription')[:1200],original_pixels=[i.get('width'),i.get('height')]))
 if not candidates:candidates=search(queries.get(e['id'],'"'+e['city']+'" "Citadis 305"'))
 if not candidates:print('EMPTY',e['id'],flush=True);continue
 for k,r in enumerate(candidates[:4]):
  r['local_image']='references/'+e['id']+'-review-'+str(k+1)+'.jpg';r['review_status']='pending_subject_review';download((e,r))
 e['references']=candidates[:4];atomic_index(data);print(e['id'],[r['title'] for r in e['references']],flush=True)
for e in data['entries']:
 if e['fictional']:
  e['references']=json.loads(json.dumps(next(x for x in data['entries'] if x['id']==e['inspired_by'])['references']))
  for r in e['references']:r['role']='Inspiration réelle ; cette rame fictive n’existe pas.'
atomic_index(data)
