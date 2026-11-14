#!/usr/bin/env python3
"""Reproducible objective PCM diagnostics; these measurements are not listening.

ffmpeg decodes mono 16 kHz in memory. Dominant peaks describe energy, not a
verified motor fundamental or speech detector. Window timings are source-local.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

import numpy as np
from scipy import signal

SR = 16000


def decode(path):
    return np.frombuffer(subprocess.check_output([
        'ffmpeg', '-v', 'error', '-i', str(path), '-vn', '-ac', '1',
        '-ar', str(SR), '-f', 'f32le', '-']), dtype='<f4').astype(float)


def db(x):
    return round(float(20 * np.log10(max(float(x), 1e-12))), 3)


def measure(x):
    if len(x) < 512:
        return {'error': 'less than 32 ms'}
    rms = np.sqrt(np.mean(x*x))
    f, p = signal.welch(x, SR, nperseg=min(4096, len(x)))
    total = max(float(p.sum()), 1e-24)
    peaks, _ = signal.find_peaks(p)
    peaks = sorted(peaks, key=lambda i: p[i], reverse=True)[:6]
    _, times, z = signal.stft(x, SR, nperseg=2048, noverlap=1024)
    z = abs(z)**2
    ff = np.fft.rfftfreq(2048, 1/SR)
    mask = (ff >= 80) & (ff <= 3000)
    tracks = ff[mask][np.argmax(z[mask], axis=0)]
    typical_step = np.sqrt(np.mean(np.diff(x)**2))
    frame_n = SR//5
    frames = [np.sqrt(np.mean(x[i:i+frame_n]**2)) for i in range(0, len(x)-frame_n+1, frame_n)]
    return {
        'duration_s': round(len(x)/SR, 4), 'rms_dbfs': db(rms),
        'sample_peak_dbfs': db(max(abs(x))),
        'oversampled_peak_dbfs': db(max(abs(signal.resample_poly(x, 4, 1)))),
        'near_clip_samples_pct': round(float(np.mean(abs(x) >= .999)*100), 6),
        'dc': round(float(np.mean(x)), 7),
        'crest_db': round(db(max(abs(x)))-db(rms), 3),
        'bands_energy_pct': {f'{lo}-{hi}_Hz': round(float(p[(f>=lo)&(f<hi)].sum()/total*100), 3)
                             for lo,hi in ((0,80),(80,250),(250,800),(800,1600),(1600,3000),(3000,6000),(6000,8001))},
        'dominant_peaks_hz': [round(float(f[i]), 2) for i in peaks],
        'strongest_bin_energy_pct': round(float(max(p)/total*100), 3),
        'dominant_track_p10_p50_p90_hz': [round(float(v), 2) for v in np.percentile(tracks,[10,50,90])],
        'rms_200ms_p10_p50_p90_dbfs': [db(v) for v in np.percentile(frames,[10,50,90])],
        'seam_jump_dbfs': db(abs(x[-1]-x[0])),
        'seam_jump_over_typical_step_db': db(abs(x[-1]-x[0])/max(typical_step,1e-12)),
        'head_tail_50ms_rms_difference_db': round(db(np.sqrt(np.mean(x[:800]**2)))-db(np.sqrt(np.mean(x[-800:]**2))),3),
    }


def analyze(path, windows=False):
    x = decode(path)
    out = {'path': str(path), 'sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
           'method': 'mono ffmpeg 16kHz decode; not listening', **measure(x)}
    if windows:
        out['windows'] = [{'start_s': float(t), **measure(x[t*SR:min((t+4)*SR,len(x))])}
                          for t in range(0, max(1, len(x)//SR-3), 2)]
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('paths', nargs='+', type=Path)
    ap.add_argument('--output', type=Path, required=True)
    ap.add_argument('--windows', action='store_true')
    a = ap.parse_args()
    paths = []
    for p in a.paths:
        paths.extend(sorted(v for v in p.rglob('*') if v.suffix.lower() in ('.ogg','.wav','.mp3','.webm','.m4a','.flac')) if p.is_dir() else [p])
    results = []
    for p in paths:
        try:
            results.append(analyze(p,a.windows))
        except (subprocess.CalledProcessError, ValueError) as e:
            results.append({'path':str(p),'error':str(e)})
    a.output.parent.mkdir(parents=True, exist_ok=True)
    a.output.write_text(json.dumps({'decode_sample_rate':SR,'limitations':['No perceptual listening or speech recognition performed.','16kHz analysis does not inspect content above 8kHz.','Peak track is not a motor fundamental estimate.','A seam jump within typical steps does not guarantee an inaudible loop.'], 'files':results}, ensure_ascii=False, indent=2)+'\n')
    print(f'{len(results)} files -> {a.output}')


if __name__ == '__main__':
    main()
