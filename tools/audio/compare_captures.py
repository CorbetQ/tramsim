#!/usr/bin/env python3
"""Create equal-loudness listening copies from actual Godot captures, no resynthesis."""
import json, re, subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
DEMOS=ROOT/'samples/demos'; OUT=ROOT/'samples/listening'; OUT.mkdir(exist_ok=True)
reports={}
def measure(args):
 p=subprocess.run(['ffmpeg','-v','info',*args,'-af','loudnorm=I=-20:TP=-1:LRA=11:print_format=json','-f','null','-'],capture_output=True,text=True,check=True)
 return json.loads(re.findall(r'\{\s*"input_i".*?\}',p.stderr,re.S)[-1])
for model in ['302','305']:
 parts=[]
 for phase in ['before','after']:
  path=DEMOS/f'v2_{phase}_citadis_{model}.wav'
  full=measure(['-i',str(path)])
  gain=-20-float(full['input_i'])
  if float(full['input_tp'])+gain > -1: gain=-1-float(full['input_tp'])
  if phase=='after':
   target=OUT/f'v2_citadis_{model}_ecoute.mp3'
   subprocess.run(['ffmpeg','-v','error','-y','-i',str(path),'-af',f'volume={gain}dB','-c:a','libmp3lame','-b:a','128k',str(target)],check=True)
  # Departure only, identical prescribed 0-50km/h ramp; separate equal-loudness comparison.
  m=measure(['-ss','7','-t','16','-i',str(path)])
  g=min(-20-float(m['input_i']),-1-float(m['input_tp']))
  parts.append((path,g))
  reports[f'{model}_{phase}']={'full':full,'full_constant_gain_db':gain,'departure':m,'departure_constant_gain_db':g}
 target=OUT/f'v2_citadis_{model}_avant_apres.mp3'
 subprocess.run(['ffmpeg','-v','error','-y','-i',str(parts[0][0]),'-i',str(parts[1][0]),'-filter_complex',
  f'[0:a]atrim=start=7:duration=16,asetpts=PTS-STARTPTS,volume={parts[0][1]}dB[a];'
  f'anullsrc=r=48000:cl=stereo,atrim=duration=1[s];'
  f'[1:a]atrim=start=7:duration=16,asetpts=PTS-STARTPTS,volume={parts[1][1]}dB[b];'
  '[a][s][b]concat=n=3:v=0:a=1[out]', '-map','[out]','-c:a','libmp3lame','-b:a','128k',str(target)],check=True)
(OUT/'v2_levels.json').write_text(json.dumps(reports,indent=2)+'\n')
print('Four listening MP3s generated: actual Godot capture, constant presentation gain only.')
