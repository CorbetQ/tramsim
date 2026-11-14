#!/usr/bin/env python3
"""Listening copies from recorded Godot output; constant gain, no added sound."""
import json,re,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];DEMOS=ROOT/'samples/demos';OUT=ROOT/'samples/listening'
def measure(args):
 r=subprocess.run(['ffmpeg','-v','info',*args,'-af','loudnorm=I=-20:TP=-1:LRA=11:print_format=json','-f','null','-'],capture_output=True,text=True,check=True)
 return json.loads(re.findall(r'\{\s*"input_i".*?\}',r.stderr,re.S)[-1])
def gain(m):return min(-20-float(m['input_i']),-1-float(m['input_tp']))
p=DEMOS/'approved_rotterdam_302.wav';before=DEMOS/'v2_after_citadis_302.wav'
m=measure(['-i',str(p)]);g=gain(m)
subprocess.run(['ffmpeg','-v','error','-y','-i',str(p),'-af',f'volume={g}dB','-c:a','libmp3lame','-b:a','128k',str(OUT/'approved_rotterdam_302_game.mp3')],check=True)
subprocess.run(['ffmpeg','-v','error','-y','-i',str(p),'-c:a','libvorbis','-q:a','4',str(p.with_suffix('.ogg'))],check=True)
a=measure(['-ss','7','-t','16','-i',str(before)]);b=measure(['-ss','7','-t','16','-i',str(p)])
subprocess.run(['ffmpeg','-v','error','-y','-i',str(before),'-i',str(p),'-filter_complex',f'[0:a]atrim=start=7:duration=16,asetpts=PTS-STARTPTS,volume={gain(a)}dB[a];anullsrc=r=48000:cl=stereo,atrim=duration=1[s];[1:a]atrim=start=7:duration=16,asetpts=PTS-STARTPTS,volume={gain(b)}dB[b];[a][s][b]concat=n=3:v=0:a=1[out]','-map','[out]','-c:a','libmp3lame','-b:a','128k',str(OUT/'approved_rotterdam_302_before_after.mp3')],check=True)
(OUT/'approved_rotterdam_levels.json').write_text(json.dumps({'full_game_before_gain':m,'full_gain_db':g,'comparison_before':a,'comparison_after':b,'comparison_gains_db':[gain(a),gain(b)],'comparison_timeline':'0-16s old bank v2, 16-17 silence, 17-33 new approved Rotterdam bank'},indent=2)+'\n')
print('Game recording and equal-loudness A/B rendered.')
