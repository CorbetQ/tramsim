#!/usr/bin/env python3
"""Nouvel inventaire rédigé depuis les sources Internet du registre CSV.
Le registre des variantes provient des sources ; les maillages utilisent les plans historiques améliorés.
Les photographies téléchargées sont conservées par identifiant, jamais utilisées comme preuve technique.
"""
import csv,json,copy
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];INDEX=ROOT/'data/rolling_stock/variants/index.json'
def build():
 old={e['id']:e for e in json.loads(INDEX.read_text()).get('entries',[])} if INDEX.exists() else {}
 entries=[]
 for r in csv.DictReader(open(Path(__file__).with_name('fleet_france.csv')),delimiter=';'):
  n=int(r['modules']);length=float(r['length']);modes=['overhead']+({'aps':['aps'],'battery':['battery']}.get(r['power'],[]))
  e=dict(id=r['id'],network=r['network'],city=r['city'],family=r['family'],name=r['name'],length=length,width=float(r['width']),line=r['line'],lines=[r['line']],electric_modes=modes,guidance='rubber_guided' if r['power']=='rubber' else 'steel',gauge_mm=1000 if r['network'] in ['lille','saintetienne','annemasse','saintlouis','leymen'] else 1435,fictional=False,cab_profile=r['cab'],module_count=n,technical={},estimated=['mass_t','power_kw','capacity','max_tractive_effort_n','braking','geometry'],geometry={},sources=[r['source']],references=old.get(r['id'],{}).get('references',[]),search_query='"'+r['name'].split(' ',1)[-1].split(' T')[0]+'" "'+(r['city'] if r['network']!='idf' else r['line'].upper())+'"',model_origin='Plan historique du jeu conservé, avec adaptations de caisses, cabine et livrée depuis les références.',status='current_or_historical')
  e['technical'].update(mass_t=round(length*1.25,1),power_kw=round(length*18/40)*40,capacity=round(length*6.4),max_speed_kmh=100 if r['family'] in ['citadis_dualis','avanto','tango_rhonexpress'] else 70)
  e['geometry']={'modules':n,'cab_profile':r['cab'],'unidirectional':r['network']=='saintetienne','height':3.35,'floor':.35}
  # Dimensions des caisses et implantations fines reconstruites : explicitement estimées.
  if r['family']=='tfs':e['geometry'].update(floor=.65,height=3.25)
  if r['family']=='translohr':e['geometry'].update(height=2.89,floor=.25)
  if r['family'] in ['citadis_dualis','avanto']:e['geometry'].update(height=3.6)
  if r['cab'] in ['irigo305','naolib']:e['geometry']['double_cab_doors']=True
  if r['cab'] in ['eurotram','cts403','cts403ng','cts3','naolib']:e['geometry']['cab_bogie']=True
  if r['network']=='angers' and r['family']=='citadis_x05':e['technical'].update(capacity=217,doors_per_side=6);e['estimated'].remove('capacity')
  if r['cab']=='naolib':e['technical'].update(capacity=300);e['estimated'].remove('capacity')
  if r['id'] in ['besancon__citadis_x05','toulouse__citadis_305','brest__citadis_305']:e['technical'].update(capacity=201,doors_per_side=6);e['estimated'].remove('capacity')
  if r['cab']=='cts3':e['technical'].update(capacity=286);e['estimated'].remove('capacity')
  if r['id']=='idf__citadis_x05__t1':e['technical'].update(capacity=200);e['estimated'].remove('capacity')
  entries.append(e)
 for src,cab,kind,length,origin in [('angers','irigo305','405',44.5,'angers__citadis_x05'),('dijon','dijon','405',44,'dijon__citadis_302'),('nantes','naolib','305',33,'nantes__citadis_x05_nantes')]:
  e=copy.deepcopy(next(x for x in entries if x['id']==origin));e.update(id=src+'__concept_citadis_'+kind,family='citadis_x05',name='Citadis '+kind+' '+{'angers':'Irigo','dijon':'Divia','nantes':'Naolib'}[src]+' — concept',fictional=True,inspired_by=origin,length=length,module_count=7 if kind=='405' else 5,lines=[],line='',fiction_note='Création fictive du simulateur ; aucune commande réelle.',estimated=['mass_t','power_kw','capacity','max_speed_kmh','geometry','length_m','width_m'],electric_modes=['overhead','aps']);e['geometry']['modules']=e['module_count'];e['technical'].update(mass_t=round(length*1.25,1),power_kw=840 if kind=='405' else 640,capacity=300 if kind=='405' else 217)
  for ref in e['references']:ref['role']='Inspiration ; cette rame fictive n’existe pas.'
  entries.append(e)
 from concept_variants import add_examples
 add_examples(entries)
 # Déduplique les affectations de lignes qui partagent une même rame et une même livrée.
 merges={'idf__citadis_302__t7':['idf__citadis_302__t8'],'idf__citadis_x05__t9':['idf__citadis_x05__t10'],'idf__citadis_dualis__t11':['idf__citadis_dualis__t4','idf__citadis_dualis__t12','idf__citadis_dualis__t13']}
 for main,duplicates in merges.items():
  target=next(e for e in entries if e['id']==main);target['aliases']=duplicates
  for duplicate in duplicates:
   other=next(e for e in entries if e['id']==duplicate);target['lines']+=other['lines'];target['sources']+=other['sources'];entries.remove(other)
  target['name']+=' / '+', '.join(x.upper() for x in target['lines'][1:])
 next(e for e in entries if e['id']=='lyon__citadis_402_2020')['aliases']=['lyon__citadis_x05']
 INDEX.write_text(json.dumps({'schema':2,'scope':'Rames modernes françaises et matériels transfrontaliers documentés ; séries actuelles et historiques, concepts séparés. Registre de recherche évolutif, exhaustivité nationale non certifiée.','baseline_commit':'9889556578c62f89ef77246a6f2c030e093c4e01','entries':entries},ensure_ascii=False,indent=2)+'\n')
 print(len(entries),'entrées indépendantes des anciens plans')
if __name__=='__main__':build()
