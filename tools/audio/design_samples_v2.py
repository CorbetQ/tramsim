#!/usr/bin/env python3
"""Revision 2: preserve recorded identity, reduce shared masking, expose modeled x05.
Does not overwrite originals or revision1 audio. Run after freezing A/B baselines.
"""
from pathlib import Path
import json,hashlib,importlib.util,subprocess,tempfile
import numpy as np
ROOT=Path(__file__).resolve().parents[2]; OUT=ROOT/'data/audio'; SR=32000
spec=importlib.util.spec_from_file_location('base',OUT/'make_audio.py'); a=importlib.util.module_from_spec(spec); spec.loader.exec_module(a)
manifest=json.loads((OUT/'families.json').read_text()); report={}
def decode(path):
 return np.frombuffer(subprocess.check_output(['ffmpeg','-v','error','-i',str(OUT/path),'-f','f32le','-ac','1','-ar',str(SR),'-']),'<f4').astype(float)
def emit(name,x,source):
 x=a.master(x-x.mean(),True); path=OUT/name; path.parent.mkdir(exist_ok=True)
 with tempfile.TemporaryDirectory() as d:
  from scipy.io import wavfile
  wavfile.write(Path(d)/'x.wav',SR,x.astype('float32'))
  subprocess.run(['ffmpeg','-v','error','-y','-i',str(Path(d)/'x.wav'),'-c:a','libvorbis','-q:a','5',str(path)],check=True)
 report[name]={'source':source,'duration_s':len(x)/SR,'lufs':round(a.lufs(x),2),'sha256':hashlib.sha256(path.read_bytes()).hexdigest()}
for name,bank in manifest['banks'].items():
 if name not in ['citadis302', 'lemans302']: continue
 for layer,path in list(bank['streams'].items()):
  original=path.replace('_designed.ogg','.ogg')
  if original.startswith('v2/'): original='banks/'+Path(original).name
  x=decode(original)
  # Original source bandwidth and resonant structure retained. No spectral-peak suppression.
  x=a.loopify(x,.18)
  n=int(.008*SR); w=np.sin(np.linspace(0,np.pi/2,n))**2
  x[:n]*=w; x[-n:]*=w[::-1]
  target='v2/'+Path(original).stem+'.ogg'
  emit(target,x,{'path':original,'author':bank['source']['author'],'page':bank['source']['page'],'license':bank['source']['license']})
  bank['streams'][layer]=target
 bank['mix'].update(motor=-10.,motor_hum=-11.,carrier=-90.,rolling=-23.,real_rail=-90.,regen=-28.,hvac=-32.,ambience=-31.)
 bank['design_processing']='v2 source-preserving: original recorded bandwidth/partials, 180ms overlap, 8ms seam guard, -20LUFS. No spectral flattening. Common rail textures suppressed to avoid duplicating recorded rolling.'
# Keep the existing explicitly modeled 305 waveform until a real 305 reference
# can be analyzed. Only unmask it; do not invent another supposedly authentic timbre.
manifest['banks']['citadis305_model']['mix'].update(
 motor=-16.,motor_hum=-16.,carrier=-26.,rolling=-22.,real_rail=-90.,
 regen=-20.,hvac=-30.,ambience=-30.)
manifest['banks']['citadis305_model']['design_processing']='Existing modeled waveform unchanged; v2 reduces shared masking only. No exact305 recording obtained.'
manifest['design_revision']='2026-11-14 source-preserving-v2'
(OUT/'families.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
(OUT/'design-manifest-v2.json').write_text(json.dumps({'generator':'tools/audio/design_samples_v2.py','files':report},ensure_ascii=False,indent=2)+'\n')
print(f'v2: {len(report)} new derivatives; originals and v1 audio retained')
