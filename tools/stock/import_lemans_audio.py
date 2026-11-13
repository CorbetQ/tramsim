#!/usr/bin/env python3
"""Extrait reproductible d'une captation CC0 de tram du Mans, aperçu public Freesound."""
import sys,json,hashlib,copy,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT/'tools/import'))
from build_audio_banks import make_loop,probe
source=ROOT/'.cache/audio_sources/lemans-458858.mp3'
url='https://cdn.freesound.org/previews/458/458858_8031303-hq.mp3'
if not source.exists():
 source.parent.mkdir(parents=True,exist_ok=True);subprocess.run(['curl','-fLsS','--max-time','45',url,'-o',str(source)],check=True)
path=ROOT/'data/audio/families.json';data=json.loads(path.read_text());bank=copy.deepcopy(data['banks']['citadis302']);bank['label']='Citadis du Mans — SamuelGremaud (captation de passage)';bank['recorded_family']='citadis_302';bank['source']={'title':'TRAM - 1','page':'https://freesound.org/people/SamuelGremaud/sounds/458858/','download_url':url,'author':'SamuelGremaud','license':'CC0','license_url':'https://creativecommons.org/publicdomain/zero/1.0/','sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'duration_s':float(probe(source)['format']['duration']),'notes':'Aperçu public haute qualité ; captation extérieure de passage au Mans, pas de moteur isolé. Régime et vitesse de référence estimés.'}
bank['streams']={};bank['segments']={}
for name,start in [('motor',5.0),('motor_hum',9.0)]:
 out=ROOT/'data/audio/banks'/('lemans302_'+name+'.ogg');bank['segments'][name]=make_loop(source,start,out);bank['streams'][name]='banks/'+out.name
bank['mix']['motor']=-17;bank['mix']['motor_hum']=-17
bank['reference_speed_ms']=8.;bank['reference_speed_estimated']=True;data['banks']['lemans302']=bank
data.setdefault('variant_profiles',{}).update({
 'lemans__citadis_302':dict(bank='lemans302',quality='exact_family',rubber=False),
 'lemans__citadis_402':dict(bank='lemans302',quality='related_family',rubber=False),
 'sarreguemines__flexity_link':dict(bank='',quality='synthetic',rubber=False),
 'saintlouis__flexity_bvb':dict(bank='',quality='synthetic',rubber=False),
 'annemasse__tango_tpg':dict(bank='',quality='synthetic',rubber=False),
 'leymen__tango_blt':dict(bank='',quality='synthetic',rubber=False)})
path.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n');print(json.dumps(bank['segments']))
