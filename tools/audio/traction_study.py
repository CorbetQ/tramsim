#!/usr/bin/env python3
"""Study harmonic candidates, not motor/source identity. No game assets changed.

STFT soft harmonic/percussive masks and continuity-constrained spectral ridge.
HPSS does not remove speech or distinguish motor from HVAC, bell, or rail tones.
Pitch ridges are spectral components, never certified shaft/stator frequencies.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

import numpy as np
from scipy import ndimage, signal
from PIL import Image

SR, FFT, HOP = 16000, 2048, 256


def decode(path, start, duration):
    raw = subprocess.check_output(['ffmpeg','-v','error','-ss',str(start),'-i',str(path),
                                  '-t',str(duration),'-ac','1','-ar',str(SR),'-f','f32le','-'])
    return np.frombuffer(raw,'<f4').astype(float)


def db(x):
    return float(20*np.log10(max(float(x),1e-12)))


def ridge(score, bins):
    """Viterbi, <=31.25 Hz per16ms hop, penalty0.18/bin. Not a fundamental."""
    previous=score[:,0].copy(); back=np.zeros(score.shape,np.int16)
    for t in range(1,score.shape[1]):
        choices=[]
        for shift in range(-4,5):
            candidate=np.roll(previous,shift)-.18*abs(shift)
            if shift>0: candidate[:shift]=-1e6
            elif shift<0: candidate[shift:]=-1e6
            choices.append(candidate)
        choices=np.array(choices); best=np.argmax(choices,axis=0)
        back[:,t]=np.arange(len(previous))-(best-4)
        previous=score[:,t]+choices[best,np.arange(len(previous))]
    indices=np.empty(score.shape[1],int);indices[-1]=np.argmax(previous)
    for t in range(len(indices)-1,0,-1):indices[t-1]=back[indices[t],t]
    return bins[indices]


def export_reconstruction(source,candidate,out,label):
    """24-bit FLAC pair sums exactly to the 24-bit source, before playback gain.

    Vorbis listening copies are lossy and therefore do not sum sample-exactly.
    All three use one common gain, never independent normalization.
    """
    scale=2**23
    common_gain=min(1.0,.95/max(np.max(abs(source)),np.max(abs(candidate)),np.max(abs(source-candidate))))
    source=source*common_gain;candidate=candidate*common_gain
    sq=np.rint(source*scale).astype(np.int64)
    hq=np.rint(candidate*scale).astype(np.int64)
    rq=sq-hq
    arrays={'source':sq,'harmonic-candidate':hq,'residual':rq}
    if any(np.max(abs(v))>=scale for v in arrays.values()):
        raise ValueError('24-bit headroom exceeded; common attenuation required')
    decoded={}
    paths={}
    for name,q in arrays.items():
        stem=out/(label+'-'+name)
        flac=stem.with_suffix('.flac');ogg=stem.with_suffix('.ogg')
        subprocess.run(['ffmpeg','-v','error','-y','-f','s32le','-ar',str(SR),'-ac','1','-i','-',
                        '-c:a','flac','-sample_fmt','s32','-bits_per_raw_sample','24',str(flac)],
                       input=(q.astype(np.int32)<<8).tobytes(),check=True)
        raw=subprocess.check_output(['ffmpeg','-v','error','-i',str(flac),'-f','s32le','-'])
        decoded[name]=np.frombuffer(raw,'<i4').astype(np.int64)>>8
        subprocess.run(['ffmpeg','-v','error','-y','-i',str(flac),'-c:a','libvorbis','-q:a','4',str(ogg)],check=True)
        paths[name]={'flac':str(flac),'ogg':str(ogg),'peak_dbfs':round(db(np.max(abs(q))/scale),3)}
    error=decoded['source']-decoded['harmonic-candidate']-decoded['residual']
    return {'source_window_seconds':[0,13.8],'sample_rate':SR,'channels':1,'common_gain':common_gain,
            'common_gain_db':round(db(common_gain),4),
            'gain_policy':'same fixed gain for all three to prevent source/codec overshoot; no independent normalization',
            'lossless_max_reconstruction_error_pcm24_lsb':int(np.max(abs(error))),
            'ogg_note':'Vorbis listening copies are lossy; exact equality applies only to FLAC decoded PCM24.',
            'author':'LG','title':'Streetcar04.wav','page':'https://freesound.org/people/LG/sounds/14279/',
            'license':'CC BY 4.0','license_url':'https://creativecommons.org/licenses/by/4.0/',
            'source':'samples/raw/spotting-rotterdam-citadis-lg-14279-preview.mp3',
            'identity':'Citadis departing in Rotterdam; related family, no certified French302/305 match',
            'processing':'mono16kHz excerpt; STFT harmonic+ridge soft mask; residual=source-candidate; PCM24 quantization',
            'listened':False,'pure_motor_claim':False,'files':paths}


def study(path,start,duration,out,label,export=False):
    x=decode(path,start,duration)
    f,t,z=signal.stft(x,SR,nperseg=FFT,noverlap=FFT-HOP)
    mag=abs(z)
    harmonic=ndimage.median_filter(mag,size=(1,31),mode='reflect')
    percussive=ndimage.median_filter(mag,size=(31,1),mode='reflect')
    hmask=harmonic**2/(harmonic**2+percussive**2+1e-20)
    local=ndimage.median_filter(mag,size=(31,1),mode='reflect')
    prominence=np.clip(np.log(np.maximum(mag,1e-12)/np.maximum(local,1e-12)),0,4)
    valid=(f>=100)&(f<=3000);bins=np.where(valid)[0]
    score=prominence[valid].copy();tracks=[];ridge_mask=np.zeros_like(mag)
    for _ in range(3):
        track=ridge(score,bins); tracks.append(track)
        for j,b in enumerate(track):
            d=abs(np.arange(len(f))-b)
            ridge_mask[:,j]=np.maximum(ridge_mask[:,j],np.exp(-.5*(d/1.5)**2))
            score[max(0,b-bins[0]-5):min(len(bins),b-bins[0]+6),j]=0
    # Weak smooth gate: no hard subtraction, no claim of speech removal.
    gate=np.clip((prominence-.35)/1.2,0,1)
    mask=np.maximum(hmask*.65,ridge_mask*gate)
    mask*=((f>=80)&(f<=3500))[:,None]
    _,candidate=signal.istft(z*mask,SR,nperseg=FFT,noverlap=FFT-HOP)
    candidate=candidate[:len(x)]
    energy=lambda v:float(np.mean(v*v))
    rows=[]
    for a in range(0,max(1,len(x)//SR-3),2):
        ii=(t>=a)&(t<a+4); power=np.sum(mag[:,ii]**2)
        bands={f'{lo}-{hi}':round(float(np.sum(mag[(f>=lo)&(f<hi)][:,ii]**2)/max(power,1e-20)*100),2)
               for lo,hi in [(0,100),(100,400),(400,800),(800,1600),(1600,3000),(3000,8001)]}
        rows.append({'start_s':start+a,'end_s':min(start+a+4,start+len(x)/SR),
                     'band_energy_pct':bands,'hpss_harmonic_energy_pct':round(float(np.sum(abs(z[:,ii]*hmask[:,ii])**2)/max(power,1e-20)*100),2)})
    track_info=[]
    for tr in tracks:
        vals=f[tr];prom=prominence[tr,np.arange(len(t))]
        track_info.append({'frequency_p10_p50_p90_hz':np.percentile(vals,[10,50,90]).round(2).tolist(),
                           'prominence_median_db':round(float(np.median(prom)*20/np.log(10)),2),
                           'samples':[{'source_seconds':round(float(start+t[i]),3),'hz':round(float(vals[i]),2),
                                       'prominence_db':round(float(prom[i]*20/np.log(10)),2)} for i in range(0,len(t),16)]})
    # Inspectable spectrogram: x=time, y=0..3.5kHz increasing upward, ridge1=white.
    q=(f<=3500);power=20*np.log10(np.maximum(mag[q],1e-8));power=np.clip((power-power.max()+65)/65,0,1)
    rgb=np.stack([power**.6,power**1.5,power**3],axis=-1)
    im=Image.fromarray((np.flipud(rgb)*255).astype('uint8')).resize((960,360))
    im.save(out/(label+'-spectrogram.png'))
    if export:
        # Keep source level, no normalization that makes contamination seem cleaner.
        subprocess.run(['ffmpeg','-v','error','-y','-f','f32le','-ar',str(SR),'-ac','1','-i','-',
                        '-c:a','libvorbis','-q:a','4',str(out/(label+'-harmonic-candidate.ogg'))],input=candidate.astype('<f4').tobytes(),check=True)
        if label=='rotterdam-motor':
            reconstruction=export_reconstruction(x,candidate,out,label)
            reconstruction['source_sha256']=hashlib.sha256(path.read_bytes()).hexdigest()
            (out/'revision3-rotterdam-reconstruction.json').write_text(json.dumps(reconstruction,ensure_ascii=False,indent=2)+'\n')
    return {'label':label,'source':str(path),'source_sha256':hashlib.sha256(path.read_bytes()).hexdigest(),
            'start_s':start,'duration_s':len(x)/SR,'input_rms_dbfs':round(db(np.sqrt(energy(x))),2),
            'candidate_rms_dbfs':round(db(np.sqrt(energy(candidate))),2),
            'candidate_energy_retained_pct':round(100*energy(candidate)/max(energy(x),1e-20),2),
            'candidate_exported':export,'track_method':'spectral ridge, not motor fundamental; may track bells/speech/rail',
            'tracks':track_info,'windows':rows}


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--output',type=Path,default=Path('samples/analysis/revision3'))
    ap.add_argument('--export-candidates',action='store_true')
    args=ap.parse_args();args.output.mkdir(parents=True,exist_ok=True)
    cases=[('moscow','samples/raw/citadis302-full.ogg',30,18,True),
           ('moscow-hum','samples/raw/citadis302-full.ogg',98,16,True),
           ('lemans','samples/raw/lemans302-original.mp3',3,14,True),
           ('t7-reference-only','samples/raw/spotting-citadis302-paris-t7-testing-reference.mp3',6,22,False),
           ('rotterdam-motor','samples/raw/spotting-rotterdam-citadis-lg-14279-preview.mp3',0,13.8,True),
           ('rotterdam-other','samples/raw/spotting-rotterdam-citadis-lg-18723-preview.mp3',0,13.1,True),
           ('rotterdam-onboard','samples/raw/spotting-rotterdam-citadis-lg-56878-preview.mp3',0,30,True),
           ('302-bank','data/audio/banks/citadis302_motor_designed.ogg',0,8,False),
           ('302-hum-bank','data/audio/banks/citadis302_motor_hum_designed.ogg',0,8,False)]
    rows=[]
    for label,path,start,duration,rights in cases:
        if Path(path).exists():
            rows.append(study(Path(path),start,duration,args.output,label,args.export_candidates and rights))
            print(label,'done',flush=True)
    report={'method':{'sample_rate':SR,'fft_size':FFT,'hop_samples':HOP,'hpss_temporal_median_frames':31,
                      'hpss_spectral_median_bins':31,'soft_mask_power':2,'limitations':['No listening performed','Not a motor source separator','Preserves speech harmonics and bells too','Changing motor tones may be classified percussive','No motor fundamental or manufacturer frequency inferred']},'cases':rows}
    (args.output/'revision3-traction.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')


if __name__=='__main__':main()
