#!/usr/bin/env python3
"""Deterministic playable sound design. Requires ffmpeg, numpy/scipy.
Original recordings remain unchanged; *_designed derivatives inherit their source licence.
305 is a model, never a captured 305. Run from any directory.
"""
from pathlib import Path
import importlib.util, json, hashlib, subprocess, tempfile
import numpy as np
from scipy import signal, ndimage
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'data/audio'
spec=importlib.util.spec_from_file_location('base_audio',OUT/'make_audio.py')
a=importlib.util.module_from_spec(spec); spec.loader.exec_module(a)
rng=np.random.default_rng(305302)
SR=a.SR
report={}
def decode(p):
    raw=subprocess.check_output(['ffmpeg','-v','error','-i',str(p),'-f','f32le','-ac','1','-ar',str(SR),'-'])
    return np.frombuffer(raw,'<f4').astype(float)
def cyclic(x,lo=55,hi=1800):
    f=np.fft.rfftfreq(len(x),1/SR); z=np.fft.rfft(x)
    h=1/np.sqrt(1+(lo/np.maximum(f,.001))**6)/np.sqrt(1+(f/hi)**8)
    return np.fft.irfft(z*h,len(x))
def seam(x):
    # Full periodic overlap, not an amplitude fade to silence at every revolution.
    return a.loopify(x,.18)
def emit(name,x,loop=True,source=None):
    x-=x.mean()
    x=a.master(x,loop)
    path=OUT/name; path.parent.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory() as d:
        from scipy.io import wavfile
        w=Path(d)/'in.wav'; wavfile.write(w,SR,x.astype('float32'))
        subprocess.run(['ffmpeg','-v','error','-y','-i',str(w),'-c:a','libvorbis','-q:a','5',str(path)],check=True)
    report[name]={'source':source or 'original procedural model, project code licence',
                  'duration_s':round(len(x)/SR,3),'lufs_before_vorbis':round(a.lufs(x,not loop),2),
                  'peak_dbfs':round(20*np.log10(np.max(abs(x))),2),
                  'sha256':hashlib.sha256(path.read_bytes()).hexdigest()}
# Reduce stationary narrow resonances without flattening the broad mechanical texture.
# Limit each spectral bin to 9 dB over its local 55 Hz median envelope, blended 65%.
manifest=json.loads((OUT/'families.json').read_text())
for bank in manifest['banks'].values():
    if not bank.get('recorded'): continue
    for layer,path in list(bank['streams'].items()):
        original=path.replace('_designed.ogg','.ogg')
        x=decode(OUT/original); z=np.fft.rfft(x); p=abs(z)
        width=max(3,int(55*len(x)/SR)//2*2+1)
        med=ndimage.median_filter(p,size=width,mode='reflect')
        ratio=np.minimum(1,(med*2.82+1e-8)/np.maximum(p,1e-8))
        x=np.fft.irfft(z*(.35+.65*ratio),len(x))
        x=seam(cyclic(x,65,2600))
        # Two clips have large residual endpoint slopes after overlap. An 8 ms
        # raised-cosine micro-fade removes the seam transient (not a long loop fade).
        if original in ['banks/tfs_motor_hum.ogg','banks/urbos_motor.ogg']:
            n=int(.008*SR); ramp=np.sin(np.linspace(0,np.pi/2,n))**2
            x[:n]*=ramp; x[-n:]*=ramp[::-1]
        target=original.replace('.ogg','_designed.ogg')
        emit(target,x,source={'path':original,'licence':bank['source']['license'],
             'author':bank['source']['author'],'page':bank['source']['page']})
        bank['streams'][layer]=target
    bank['design_processing']='tools/audio/design_samples.py: local spectral prominence reduction, circular 65–2600 Hz filter, 180 ms overlap, BS.1770 -20 LUFS; no isolated-motor claim'
    bank['mix'].update(motor=-13.5,motor_hum=-13.5,carrier=-40.,rolling=-13.,regen=-22.)
emit('banks/real_rail_designed.ogg',seam(cyclic(decode(OUT/'real_rail.ogg'),55,2400)),source={'path':'real_rail.ogg','licence':'inherit data/audio/sources.json attribution'})
# Mechanical body around restrained periodic components rather than a dominant pure sine.
def model(fund,modern=False):
    T=8.; t=np.arange(int(T*SR))/SR
    body=a.unit(cyclic(a.colored(T,1.3),70,1100))
    bearing=a.unit(cyclic(a.colored(T,2),35,260))
    x=.65*body+.35*bearing
    for k,amp in [(1,.31),(2,.085),(3,.025)]:
        x+=amp*np.sin(2*np.pi*fund*k*t+.4*k)*(1+.035*np.sin(2*np.pi*2*t))
    if modern:
        x+=.07*np.sin(2*np.pi*450*t)*(1+.3*np.sin(2*np.pi*4*t))
    return cyclic(x,35,1300)
emit('motor.ogg',model(300))
emit('motor_hum.ogg',model(120))
emit('banks/citadis305_motor.ogg',model(300,True))
emit('banks/citadis305_motor_hum.ogg',model(120,True))
# Electrical braking has a separate dry, broad texture and a soft magnetic component.
T=8.; t=np.arange(int(T*SR))/SR
regen=.8*a.unit(cyclic(a.colored(T,1.5),120,1250))+.12*np.sin(2*np.pi*180*t)+.035*np.sin(2*np.pi*360*t)
emit('regen.ogg',regen)
# Existing carrier remains distinguishable but its narrow lines no longer dominate low-speed load.
emit('carrier.ogg',model(420)*.85+.15*a.unit(cyclic(a.colored(T,1),180,900)))
manifest['banks']['citadis305_model']={
 'recorded':False,'modeled':True,'label':'Citadis 305 — restitution modélisée, sans captation exacte',
 'recorded_family':None,'streams':{'motor':'banks/citadis305_motor.ogg','motor_hum':'banks/citadis305_motor_hum.ogg'},
 'mix':{'motor':-19.,'motor_hum':-15.,'carrier':-32.,'rolling':-11.,'real_rail':-23.,'regen':-20.},
 'provenance':'Original procedural mechanical / inverter model. Not derived from Citadis 403 recordings. Parameters are sound design estimates, not measured 305 inverter settings.',
 'design_processing':'tools/audio/design_samples.py, deterministic seed 305302'}
for family in ['citadis_x05','citadis_x05_nantes']:
    manifest['profiles'][family].update(bank='citadis305_model',quality='modeled',motor_pitch_factor=.94,hum_pitch_factor=1.02)
# Ensure explicit variant banks do not silently retain the 403 fallback.
for key,v in manifest.get('variant_profiles',{}).items():
    if '305' in key or '405' in key or 'x05' in key:
        v.update(bank='citadis305_model',quality='modeled')
manifest['design_revision']='2026-11-14 spectral-body-v1'
(OUT/'families.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
(OUT/'design-manifest.json').write_text(json.dumps({'generator':'tools/audio/design_samples.py','seed':305302,'files':report},ensure_ascii=False,indent=2)+'\n')
sources=json.loads((OUT/'sources.json').read_text())
sources['design_manifest']='design-manifest.json'
sources['design_generator']='tools/audio/design_samples.py (run after make_audio.py; authoritative for designed derivatives, motor, motor_hum, carrier and regen)'
for name,meta in report.items():
    if name in ['motor.ogg','motor_hum.ogg','carrier.ogg','regen.ogg']:
        sources['files'][name]={'origine':'synthèse tools/audio/design_samples.py',
          'licence':'création du projet (même licence que le code)',
          'description':'Modèle mécanique à bruit coloré dominant, composantes périodiques amorties ; aucune captation constructeur.',
          'lufs':meta['lufs_before_vorbis'],'duree_s':meta['duration_s']}
(OUT/'sources.json').write_text(json.dumps(sources,ensure_ascii=False,indent=1)+'\n')
print(f'{len(report)} assets generated; originals retained; 305 explicitly modeled')
