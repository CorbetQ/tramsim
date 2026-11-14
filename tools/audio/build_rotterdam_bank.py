#!/usr/bin/env python3
"""Build three short, source-derived Citadis traction regimes; never synthesize missing braking.
Input is the approved harmonic candidate, not a certified isolated motor. Original and
study files remain untouched. Run: python tools/audio/build_rotterdam_bank.py
"""
from pathlib import Path
import hashlib, importlib.util, json, subprocess, tempfile
import numpy as np
from scipy.io import wavfile
ROOT=Path(__file__).resolve().parents[2]; OUT=ROOT/'data/audio'
SOURCE=ROOT/'samples/analysis/revision3/rotterdam-motor-harmonic-candidate.flac'
spec=importlib.util.spec_from_file_location('base',OUT/'make_audio.py'); a=importlib.util.module_from_spec(spec);spec.loader.exec_module(a)
SR=a.SR
REGIMES={'carrier':{'start_s':2.0,'end_s':2.8,'estimated_speed_anchor_ms':1.0,'overlap_s':.08},
 'motor':{'start_s':4.0,'end_s':5.5,'estimated_speed_anchor_ms':4.0,'overlap_s':.15},
 'motor_hum':{'start_s':10.25,'end_s':12.75,'estimated_speed_anchor_ms':13.0,'overlap_s':.18}}
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def main():
 raw=subprocess.check_output(['ffmpeg','-v','error','-i',str(SOURCE),'-ac','1','-ar',str(SR),'-f','f32le','-'])
 x=np.frombuffer(raw,'<f4').astype(float)
 streams={}; segments={}
 for layer,window in REGIMES.items():
  cut=x[round(window['start_s']*SR):round(window['end_s']*SR)].copy()
  loop=a.loopify(cut,window['overlap_s'])
  # A tiny cosine guard reduces endpoint discontinuities; no global EQ/peak flattening.
  n=round(.008*SR); w=np.sin(np.linspace(0,np.pi/2,n))**2
  loop[:n]*=w;loop[-n:]*=w[::-1]
  loop-=loop.mean();gain_db=-20.-a.lufs(loop);loop*=10**(gain_db/20)
  target=OUT/'banks'/('rotterdam_traction_'+layer+'.ogg')
  with tempfile.TemporaryDirectory() as d:
   wavfile.write(Path(d)/'loop.wav',SR,loop.astype('float32'))
   subprocess.run(['ffmpeg','-v','error','-y','-i',str(Path(d)/'loop.wav'),'-c:a','libvorbis','-q:a','5','-fflags','+bitexact',str(target)],check=True)
  streams[layer]=str(target.relative_to(OUT))
  segments[layer]={**window,'duration_s':len(loop)/SR,'speed_anchor_estimated':True,
   'loop_sha256':sha(target),'input_window_pcm_float64_sha256':hashlib.sha256(cut.astype('<f8').tobytes()).hexdigest(),
   'normalization_gain_db':round(gain_db,4),'lufs_before_vorbis':round(a.lufs(loop),3),
   'sample_peak_dbfs':round(20*np.log10(max(abs(loop))),3),
   'processing':'source harmonic candidate only; resample16→32k; equal-amplitude overlap; 8ms cosine seam guard; DC removal; constant gain to -20LUFS. No synthesized partials, no global spectral flattening.'}
 source_meta=json.loads((ROOT/'samples/analysis/revision3/revision3-rotterdam-reconstruction.json').read_text())
 bank={'recorded':True,'traction_only':True,'source_motricity':'harmonic candidate from a documented departure; not certified isolated motor',
  'label':'Citadis Rotterdam — départ LG, apparentement non certifié 302',
  'recorded_family':'citadis_unidentified','streams':streams,'reference_speed_ms':4.0,'reference_speed_estimated':True,
  'pitch_bounds':[.94,1.16],'regime_transition_ms':[4.0,12.0],'startup_fade_speed_ms':2.5,
  'mix':{'motor':-10.,'motor_hum':-11.,'carrier':-14.,'rolling':-23.,'real_rail':-90.,'regen':-28.,'hvac':-32.,'ambience':-31.},
  'source':{'title':source_meta['title'],'author':source_meta['author'],'page':source_meta['page'],
    'license':source_meta['license'],'license_url':source_meta['license_url'],'source_preview_sha256':source_meta['source_sha256'],
    'candidate_path':str(SOURCE.relative_to(ROOT)),'candidate_sha256':sha(SOURCE),'duration_s':13.8,
    'candidate_processing':source_meta['processing'],'pure_motor_claim':False},
  'segments':segments,'braking_provenance':'No real deceleration available: captured traction layers mute on braking/coasting; separate existing regen remains procedural estimate.',
  'speed_policy':'Anchors and regime mapping are design estimates, not measured tram speed or inverter settings.',
  'generator':'tools/audio/build_rotterdam_bank.py'}
 p=OUT/'families.json';m=json.loads(p.read_text());m['banks']['rotterdam_citadis_traction']=bank
 m['profiles']['citadis_302'].update(bank='rotterdam_citadis_traction',quality='related_family')
 # Only the302 variant is redirected; the402 LeMans related fallback remains unchanged.
 if 'lemans__citadis_302' in m.get('variant_profiles',{}):m['variant_profiles']['lemans__citadis_302'].update(bank='rotterdam_citadis_traction',quality='related_family')
 m['design_revision']='2026-11-14 rotterdam-traction-regimes-v3'
 p.write_text(json.dumps(m,ensure_ascii=False,indent=2)+'\n')
 (OUT/'rotterdam-traction-manifest.json').write_text(json.dumps(bank,ensure_ascii=False,indent=2)+'\n')
 source_registry=OUT/'sources.json'
 registry=json.loads(source_registry.read_text())
 registry['rotterdam_traction_manifest']='rotterdam-traction-manifest.json'
 registry['rotterdam_traction_generator']='tools/audio/build_rotterdam_bank.py'
 source_registry.write_text(json.dumps(registry,ensure_ascii=False,indent=1)+'\n')
 print(json.dumps({'bank':'rotterdam_citadis_traction','streams':streams,'segments':segments},ensure_ascii=False,indent=2))
if __name__=='__main__':main()
