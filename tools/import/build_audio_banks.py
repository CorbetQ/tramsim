#!/usr/bin/env python3
"""Banques courtes et reproductibles depuis captations Commons réutilisables.
Dépend de ffmpeg et numpy/scipy ; originaux exclus du dépôt et des exports.
"""
import json,subprocess,hashlib,re,tempfile,urllib.parse
from pathlib import Path
import numpy as np
from scipy.io import wavfile
from find_audio_sources import api,value,ROOT
SOURCES={
 'citadis302':('File:Alstom Citadis 302 in Moscow.webm','citadis_302','Citadis 302, Moscou'),
 'citadis402':("File:Départ d'une rame Citadis 402 de la station Porte d'Ivry.ogg",'citadis_402',"Citadis 402, Porte d’Ivry"),
 'citadis403':("File:Citadis 403 n°2040 CTS, ligne A, Langstross - Porte de l'Hôpital.ogg",'citadis_403_strasbourg','Citadis 403, Strasbourg'),
 'avanto':('File:T4 Bondy - Aulnay 07.ogv','avanto','Siemens Avanto, T4'),
 'tfs':('File:Arrivée du tram.webm','tfs','Alstom TFS, Nantes — rame 324'),
 'flexity':('File:Tramway de Marseille - Ligne 2 - Boulevard Philippon.ogv','flexity_marseille','Flexity Outlook, Marseille'),
 'urbos':('File:Luxembourg tram testing August 2017 (1).webm','urbos','CAF Urbos 3, Luxembourg')}
def probe(path):return json.loads(subprocess.check_output(['ffprobe','-v','error','-show_streams','-show_format','-of','json',str(path)]))
def loudness(path):
 p=subprocess.run(['ffmpeg','-hide_banner','-nostats','-i',str(path),'-af','loudnorm=I=-20:TP=-1:LRA=7:print_format=json','-f','null','-'],stdout=subprocess.DEVNULL,stderr=subprocess.PIPE,text=True,check=True)
 return json.loads(p.stderr[p.stderr.rfind('{'):p.stderr.rfind('}')+1])
def download(bank,title):
 result=api({'prop':'videoinfo','titles':title,'viprop':'url|extmetadata|size|derivatives'})
 page=next(iter(result.get('query',{}).get('pages',{}).values()));info=page.get('videoinfo',[])[0]
 license_=value(info,'LicenseShortName')
 if license_ not in ['CC BY 3.0','CC BY 4.0','CC BY-SA 3.0','CC BY-SA 4.0','CC0','Public domain']:raise ValueError('Licence non retenue: '+license_)
 url=info['url'].split('?')[0]
 if info['size']>32*1024*1024:
  variants=[d for d in info.get('derivatives',[]) if 'vp9' in d.get('transcodekey','')]
  if not variants:raise ValueError('Source trop volumineuse sans transcodage')
  url=min(variants,key=lambda d:d.get('bandwidth',99999999))['src']
 canonical=title.removeprefix('File:').replace(' ','_')
 path=ROOT/'.cache/audio_sources'/canonical
 if not path.exists():
  subprocess.run(['curl','-f','-L','-s','--max-time','60','--max-filesize','33554432','-o',str(path),url],check=True)
 data=probe(path)
 if not any(s['codec_type']=='audio' for s in data['streams']):raise ValueError('Pas de piste sonore')
 return path,dict(title=page['title'],page=info['descriptionurl'],download_url=url,license=license_,license_url=value(info,'LicenseUrl'),author=value(info,'Artist'),sha256=hashlib.sha256(path.read_bytes()).hexdigest(),duration_s=float(data['format']['duration']))
def make_loop(src,start,out):
 with tempfile.TemporaryDirectory() as tmp:
  raw=Path(tmp)/'source.wav';loop=Path(tmp)/'loop.wav'
  subprocess.run(['ffmpeg','-v','error','-y','-ss',str(start),'-i',str(src),'-t','4.5','-vn','-ar','32000','-ac','1','-af','highpass=f=65,lowpass=f=3800','-c:a','pcm_f32le',str(raw)],check=True)
  rate,a=wavfile.read(raw);a=a.astype(np.float32);cross=min(8000,len(a)//4)
  if len(a)<rate:raise ValueError('Extrait trop court')
  ramp=np.linspace(0,1,cross,dtype=np.float32)
  a=np.r_[a[cross:-cross],a[-cross:]*(1-ramp)+a[:cross]*ramp]
  wavfile.write(loop,rate,a)
  subprocess.run(['ffmpeg','-v','error','-y','-i',str(loop),'-af','loudnorm=I=-20:TP=-1.5:LRA=7','-ar','32000','-ac','1','-c:a','libvorbis','-q:a','4',str(out)],check=True)
  # Mesurer le fichier réellement distribué, pas seulement la consigne du filtre.
  measured=loudness(out);delta=-20-float(measured['input_i'])
  ceiling=-1.7-float(measured['input_tp']);gain=min(delta,ceiling)
  if abs(gain)>.05:
   adjusted=Path(tmp)/'adjusted.ogg'
   subprocess.run(['ffmpeg','-v','error','-y','-i',str(out),'-af',f'volume={gain:.4f}dB','-ar','32000','-ac','1','-c:a','libvorbis','-q:a','4',str(adjusted)],check=True)
   out.write_bytes(adjusted.read_bytes());measured=loudness(out)
  return dict(sha256=hashlib.sha256(out.read_bytes()).hexdigest(),start_s=round(start,3),duration_s=float(probe(out)['format']['duration']),lufs=float(measured['input_i']),true_peak_dbfs=float(measured['input_tp']),processing='mono 32 kHz, passe-bande 65–3800 Hz, raccord croisé 250 ms, normalisation')
def main():
 output=ROOT/'data/audio/banks';output.mkdir(exist_ok=True)
 banks={};records={};errors={}
 for bank,(title,family,label) in SOURCES.items():
  try:
   source,info=download(bank,title);streams={};segments={}
   duration=info['duration_s']
   for name,fraction in [('motor',.45 if bank=='urbos' else .20),('motor_hum',.55)]:
    target=output/(bank+'_'+name+'.ogg');start=max(0.,min(duration-4.6,duration*fraction))
    segments[name]=make_loop(source,start,target);streams[name]='banks/'+target.name
   banks[bank]=dict(recorded=True,label=label,recorded_family=family,streams=streams,reference_speed_ms=8.,reference_speed_estimated=True,mix={'motor':-12.,'motor_hum':-12.,'carrier':-45.,'rolling':-14.,'real_rail':-90.},source=info,segments=segments)
   for name,path in streams.items():records[path]=dict(origine=info['author']+' — '+info['title'],licence=info['license']+' '+info['license_url'],source=info['page'],modifications=segments[name]['processing'],lufs=segments[name]['lufs'],duree_s=segments[name]['duration_s'])
   print(bank,info['license'],segments,flush=True)
  except Exception as ex:errors[bank]=str(ex);print('SOURCE NON INTÉGRÉE',bank,str(ex),flush=True)
 # Pneu / roulement estimé : aucune texture de rail métallique sur Translohr.
 tyre=output/'tyre_rolling.ogg'
 subprocess.run(['ffmpeg','-v','error','-y','-f','lavfi','-i','anoisesrc=color=brown:sample_rate=32000:duration=6:seed=98731','-af','highpass=f=60,lowpass=f=1000,tremolo=f=8:d=0.12,loudnorm=I=-20:TP=-1.5:LRA=7','-ar','32000','-ac','1','-c:a','libvorbis','-q:a','4',str(tyre)],check=True)
 tyre_info=make_loop(tyre,0.,tyre);measured=loudness(tyre);records['banks/tyre_rolling.ogg']={'origine':'Synthèse de bruit de pneus, build_audio_banks.py','licence':'Création du projet','lufs':float(measured['input_i']),'duree_s':tyre_info['duration_s']}
 mapping={'tfs':'tfs','flexity_marseille':'flexity','citadis_302':'citadis302','citadis_402':'citadis402','citadis_403_strasbourg':'citadis403','avanto':'avanto','urbos':'urbos','citadis_reims':'citadis302','citadis_tours':'citadis402','citadis_compact':'citadis302','citadis_x05':'citadis403','citadis_x05_nantes':'citadis403'}
 pitch={'tfs':.68,'incentro':.9,'flexity_marseille':.83,'eurotram':.75,'citadis_dualis':1.02,'tango_rhonexpress':.94,'vevey_saint_etienne':.64,'breda_vlc':.6,'translohr':.86,'citadis_x01':.78}
 profiles={}
 for plan in sorted((ROOT/'data/rolling_stock/plans').glob('*.json')):
  family=plan.stem;bank=mapping.get(family,'');exact=bank in banks and banks[bank]['recorded_family']==family
  profiles[family]=dict(bank=bank if bank in banks else '',quality='exact_family' if exact else ('related_family' if bank in banks else 'synthetic'),motor_pitch_factor=pitch.get(family,1.),hum_pitch_factor=pitch.get(family,1.),rubber=family=='translohr')
  if family=='translohr':profiles[family]['streams']={'rolling':'banks/tyre_rolling.ogg'}
 # Identification visuelle : Nantes M2 324 = TFS ; Marseille = Flexity Outlook,
 # malgré la légende Commons qui emploie par erreur le nom Citadis.
 banks.get('tfs',{}).update(identification='Rame M2 324 visible à 10 s, série TFS 301–346 de Nantes')
 banks.get('flexity',{}).update(identification='Façade Flexity Outlook Marseille visible à 3 s ; légende Commons erronée')
 manifest={'schema':1,'sample_rate':32000,'profiles':profiles,'banks':banks,'unavailable_sources':errors,'note':'Exact = même famille, pas une captation de chaque réseau. Les apparentements et synthèses sont explicitement identifiés.'}
 (ROOT/'data/audio/families.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
 src=ROOT/'data/audio/sources.json';data=json.loads(src.read_text());data['files'].update(records);data['version']=4;data['statut']='Banques de captations par famille, apparentements et synthèses de remplacement documentés dans families.json.';src.write_text(json.dumps(data,ensure_ascii=False,indent=1)+'\n')
 (ROOT/'docs/audio-bank-coverage.json').write_text(json.dumps({'profiles':profiles,'sources':{key:value['source'] for key,value in banks.items()},'unavailable':errors},ensure_ascii=False,indent=2)+'\n')
if __name__=='__main__':main()
