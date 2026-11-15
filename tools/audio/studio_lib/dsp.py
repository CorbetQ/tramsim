"""Deterministic offline DSP. Float PCM internally; originals are never overwritten."""
import json
import math
import subprocess
from pathlib import Path
import numpy as np
import scipy
from scipy import signal
from .core import sha256, write_json


def run(args, **kwargs):
    return subprocess.run(args, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=180, **kwargs)


def probe(path):
    info = json.loads(run(['ffprobe', '-v', 'error', '-protocol_whitelist', 'file,pipe', '-show_streams', '-show_format', '-of', 'json', str(path)]).stdout)
    streams = [s for s in info['streams'] if s['codec_type'] == 'audio']
    if not streams:
        raise ValueError('No audio stream')
    s = streams[0]
    duration = float(s.get('duration', info['format'].get('duration', 0)))
    if not 0 < duration <= 7200 or int(s['channels']) > 8:
        raise ValueError('Invalid or excessive duration/channel count')
    return {'duration_s': duration, 'sample_rate': int(s['sample_rate']), 'channels': int(s['channels']), 'codec': s['codec_name']}


def decode(path, rate=None, channels=None, start=0, duration=None, filters=None):
    meta = probe(path)
    rate = int(rate or meta['sample_rate'])
    channels = int(channels or min(meta['channels'], 2))
    if rate not in (16000, 22050, 24000, 32000, 44100, 48000, 96000, 192000) or channels not in (1, 2):
        raise ValueError('Unsupported working format')
    duration = float(duration if duration is not None else min(meta['duration_s'] - start, 300))
    if start < 0 or not 0 < duration <= 300 or start >= meta['duration_s']:
        raise ValueError('Invalid segment (maximum 300 seconds per operation)')
    args = ['ffmpeg', '-v', 'error', '-nostdin', '-protocol_whitelist', 'file,pipe', '-ss', str(start), '-i', str(path), '-t', str(duration), '-vn']
    if filters:
        args += ['-af', filters]
    args += ['-ac', str(channels), '-ar', str(rate), '-f', 'f32le', '-']
    audio = np.frombuffer(run(args).stdout, dtype='<f4').reshape(-1, channels).astype(np.float64)
    if not len(audio) or not np.isfinite(audio).all():
        raise ValueError('Empty or invalid PCM')
    return audio, rate


def db(value):
    return float(20 * math.log10(max(float(value), 1e-12)))


def loudness(audio, rate):
    args = ['ffmpeg', '-v', 'info', '-nostdin', '-f', 'f32le', '-ar', str(rate), '-ac', str(audio.shape[1]), '-i', '-',
            '-af', 'loudnorm=I=-20:TP=-1:LRA=11:print_format=json', '-f', 'null', '-']
    text = run(args, input=audio.astype('<f4').tobytes()).stderr.decode()
    values = json.loads(text[text.rfind('{'):text.rfind('}') + 1])
    value = float(values['input_i'])
    return value if math.isfinite(value) else None


def metrics(audio, rate, integrated=True):
    mono = audio.mean(axis=1)
    rms = float(np.sqrt(np.mean(audio * audio)))
    peak = float(np.max(np.abs(audio)))
    true_peak = float(np.max(np.abs(signal.resample_poly(audio, 4, 1, axis=0))))
    f, power = signal.welch(mono, rate, nperseg=min(4096, len(mono)))
    total = float(power.sum())
    derivative = np.diff(audio, axis=0)
    seam = float(np.max(np.abs(audio[-1] - audio[0])))
    window = max(1, int(rate * .02))
    blocks = [float(np.sqrt(np.mean(audio[i:i + window] ** 2))) for i in range(0, len(audio), window)]
    return {'duration_s': len(audio) / rate, 'sample_rate': rate, 'channels': audio.shape[1],
            'rms_dbfs': db(rms), 'peak_dbfs': db(peak), 'true_peak_dbfs_4x': db(true_peak),
            'integrated_lufs': loudness(audio, rate) if integrated else None,
            'clipped_samples': int(np.count_nonzero(np.abs(audio) >= 1)),
            'silent_fraction_20ms': float(np.mean(np.array(blocks) < 10 ** (-65 / 20))),
            'seam_delta': seam, 'seam_to_peak': seam / max(peak, 1e-12),
            'derivative_p95': float(np.percentile(np.abs(derivative), 95)) if len(derivative) else 0,
            'spectral_centroid_hz': float((f * power).sum() / max(total, 1e-20)),
            'energy_above_12khz': float(power[f > 12000].sum() / max(total, 1e-20))}


def analyze(path):
    meta = probe(path)
    if meta['duration_s'] > 300:
        raise ValueError('Analyze a segment of long recordings first')
    audio, rate = decode(path)
    return dict(path=str(path), sha256=sha256(path), bytes=Path(path).stat().st_size, **metrics(audio, rate))


def loopify(audio, rate, overlap=.12):
    n = int(float(overlap) * rate)
    if n < 8 or len(audio) < 4 * n:
        raise ValueError('Loop must be at least four crossfade lengths')
    w = (.5 - .5 * np.cos(np.linspace(0, np.pi, n)))[:, None]
    blend = audio[-n:] * (1 - w) + audio[:n] * w
    out = np.concatenate([audio[n:-n], blend])
    # Tiny DC correction over the final 3ms. No periodic fade-to-silence.
    m = min(int(.003 * rate), len(out) // 8)
    delta = out[-1] - out[0]
    out[-m:] -= np.linspace(0, 1, m)[:, None] * delta
    return out


def export(audio, rate, path):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.suffix not in ('.wav', '.ogg', '.flac'):
        raise ValueError('Export requires WAV, FLAC or OGG')
    options = {'.wav': ['-c:a', 'pcm_s24le'], '.flac': ['-c:a', 'flac'], '.ogg': ['-c:a', 'libvorbis', '-q:a', '5']}[path.suffix]
    # bitexact fixes the Ogg serial to make same-version builds byte reproducible.
    args = ['ffmpeg', '-v', 'error', '-nostdin', '-y', '-f', 'f32le', '-ar', str(rate), '-ac', str(audio.shape[1]), '-i', '-',
            '-map_metadata', '-1', '-fflags', '+bitexact', '-flags:a', '+bitexact', *options, str(path)]
    run(args, input=audio.astype('<f4').tobytes())


def process(source, output, recipe):
    source, output = Path(source), Path(output)
    if source.resolve() == output.resolve():
        raise ValueError('Never overwrite an original')
    allowed = {'start', 'duration', 'rate', 'channels', 'highpass', 'lowpass', 'denoise_db', 'compress', 'eq', 'target_lufs', 'max_gain_db', 'ceiling_db', 'fade_ms', 'loop_overlap'}
    if set(recipe) - allowed:
        raise ValueError('Unknown recipe keys: ' + str(set(recipe) - allowed))
    filters = []
    if 'denoise_db' in recipe:
        strength = float(recipe['denoise_db'])
        if not 0.01 <= strength <= 30:
            raise ValueError('Denoise range 0.01..30 dB')
        filters.append(f'afftdn=nr={strength}')
    if recipe.get('compress'):
        filters.append('acompressor=threshold=0.25:ratio=2:attack=15:release=200:makeup=1')
    audio, rate = decode(source, recipe.get('rate'), recipe.get('channels'), float(recipe.get('start', 0)), recipe.get('duration'), ','.join(filters))
    audio -= audio.mean(axis=0)
    for name, btype in [('highpass', 'highpass'), ('lowpass', 'lowpass')]:
        if recipe.get(name):
            hz = float(recipe[name])
            if not 0 < hz < rate / 2:
                raise ValueError('Filter frequency outside Nyquist range')
            audio = signal.sosfiltfilt(signal.butter(3, hz, btype=btype, fs=rate, output='sos'), audio, axis=0)
    for band in recipe.get('eq', []):
        hz, width, gain = float(band['hz']), float(band['width_hz']), float(band['gain_db'])
        if not 0 < hz - width / 2 < hz + width / 2 < rate / 2 or abs(gain) > 12:
            raise ValueError('Invalid equalizer band')
        part = signal.sosfiltfilt(signal.butter(2, [hz - width / 2, hz + width / 2], btype='bandpass', fs=rate, output='sos'), audio, axis=0)
        audio += part * (10 ** (gain / 20) - 1)
    if recipe.get('loop_overlap'):
        audio = loopify(audio, rate, recipe['loop_overlap'])
    elif recipe.get('fade_ms', 5):
        n = min(int(float(recipe.get('fade_ms', 5)) * rate / 1000), len(audio) // 2)
        if n > 0:
            audio[:n] *= np.linspace(0, 1, n)[:, None]
            audio[-n:] *= np.linspace(1, 0, n)[:, None]
    current = loudness(audio, rate)
    gain_db = 0.0
    if recipe.get('target_lufs') is not None:
        if current is None:
            raise ValueError('Cannot normalize silence')
        gain_db = min(float(recipe['target_lufs']) - current, float(recipe.get('max_gain_db', 8)))
    true_peak = np.max(np.abs(signal.resample_poly(audio, 4, 1, axis=0)))
    ceiling = float(recipe.get('ceiling_db', -2))
    if not -18 <= ceiling <= -1:
        raise ValueError('True-peak ceiling must be -18..-1 dBFS')
    gain_db = min(gain_db, ceiling - db(true_peak))
    audio *= 10 ** (gain_db / 20)
    export(audio, rate, output)
    # Measure the actual encoded bytes, not just pre-Vorbis PCM.
    result = analyze(output)
    if result['true_peak_dbfs_4x'] > -1 or result['clipped_samples']:
        output.unlink()
        raise ValueError('Encoded output exceeds safety ceiling')
    result.update(source_sha256=sha256(source), recipe=recipe, applied_gain_db=gain_db,
                  toolchain={'ffmpeg': run(['ffmpeg', '-version']).stdout.decode().splitlines()[0], 'numpy': np.__version__, 'scipy': scipy.__version__})
    write_json(str(output) + '.recipe.json', result)
    return result


def compare(first, second):
    a, rate = decode(first, 32000, 1)
    b, _ = decode(second, 32000, 1)
    def spectrum(x):
        f, p = signal.welch(x[:, 0], rate, nperseg=min(4096, len(x)))
        return np.interp(np.geomspace(40, 15000, 96), f, 10 * np.log10(p + 1e-16))
    x, y = spectrum(a), spectrum(b)
    x -= x.mean(); y -= y.mean()
    return {'first': analyze(first), 'second': analyze(second),
            'log_spectrum_shape_rmse_db': float(np.sqrt(np.mean((x - y) ** 2))),
            'spectrum_correlation': float(np.corrcoef(x, y)[0, 1]) if x.std() and y.std() else None,
            'warning': 'Spectral similarity does not prove motor identity or perceptual realism. Human audition required.'}


def segments(path, seconds=3):
    audio, rate = decode(path, 16000, 1)
    n = int(seconds * rate)
    candidates = []
    for i in range(0, len(audio) - n + 1, max(n // 2, 1)):
        m = metrics(audio[i:i+n], rate, integrated=False)
        if m['rms_dbfs'] > -45 and not m['clipped_samples']:
            candidates.append({'start': i / rate, 'duration': seconds, 'metrics': m})
    return sorted(candidates, key=lambda x: x['metrics']['seam_to_peak'])[:10]
