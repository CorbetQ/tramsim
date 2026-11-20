#!/usr/bin/env python3
"""Free sound pack; no API, credit or generation service. See free_sfx/SOURCES.json.
Usage: python tools/audio/build_free_sfx.py --originals /path/to/downloaded/files
Original filenames and SHA256 are recorded in SOURCES.json. ffmpeg required.
"""
import argparse, hashlib, json, pathlib, subprocess, tempfile
ROOT = pathlib.Path(__file__).resolve().parents[2]
OUT = ROOT / 'data/audio/free_sfx'

def encode(src, dst, filters, start=None, duration=None):
    cmd = ['ffmpeg', '-v', 'error', '-y']
    if start is not None: cmd += ['-ss', str(start)]
    cmd += ['-i', str(src)]
    if duration is not None: cmd += ['-t', str(duration)]
    cmd += ['-af', filters, '-ar', '32000', '-ac', '1', '-c:a', 'libvorbis', '-q:a', '5', str(OUT / dst)]
    subprocess.run(cmd, check=True)

def main():
    p = argparse.ArgumentParser(); p.add_argument('--originals', type=pathlib.Path, required=True)
    args = p.parse_args(); OUT.mkdir(parents=True, exist_ok=True)
    sources = []
    base = 'https://raw.githubusercontent.com/Calinou/kenney-interface-sounds/master/addons/kenney_interface_sounds/'
    for original, target in [('click_001.wav', 'ui_click.ogg'), ('back_001.wav', 'ui_back.ogg'), ('confirmation_001.wav', 'ui_confirm.ogg')]:
        src = args.originals / original
        encode(src, target, 'highpass=f=100,lowpass=f=4200,alimiter=limit=0.8,afade=t=in:d=0.003,afade=t=out:st=0.08:d=0.08,apad=pad_dur=0.01')
        sources.append(dict(file=target, original=original, download=base+original, author='Kenney', license='CC0-1.0', page='https://kenney.nl/assets/interface-sounds', sha256_original=hashlib.sha256(src.read_bytes()).hexdigest(), processing='100 Hz high-pass, 4.2 kHz low-pass, limiter, short fades; quiet game playback'))
    # 32 s of genuine European garden birds. Overlap tail/head for a continuous 30 s loop.
    src = args.originals / 'birds-original.ogg'
    with tempfile.TemporaryDirectory(dir='/dev/shm') as td:
        clip = pathlib.Path(td) / 'birds.wav'
        subprocess.run(['ffmpeg','-v','error','-y','-ss','8','-i',str(src),'-t','32','-ar','32000','-ac','1',str(clip)],check=True)
        # First 2 s are overlapped with the last 2 s; loop join falls inside the original recording.
        cmd=['ffmpeg','-v','error','-y','-i',str(clip),'-filter_complex',
             '[0:a]asplit=3[a][b][c];[a]atrim=start=2:end=30,asetpts=PTS-STARTPTS[body];[b]atrim=start=30:end=32,asetpts=PTS-STARTPTS,afade=t=out:d=2[tail];[c]atrim=start=0:end=2,asetpts=PTS-STARTPTS,afade=t=in:d=2[head];[tail][head]amix=inputs=2:normalize=0[join];[body][join]concat=n=2:v=0:a=1,highpass=f=180,lowpass=f=6500,loudnorm=I=-20:TP=-3:LRA=11[out]',
             '-map','[out]','-ar','32000','-c:a','libvorbis','-q:a','5',str(OUT/'garden_day.ogg')]
        subprocess.run(cmd,check=True)
    sources.append(dict(file='garden_day.ogg', author='Joseph Sardin', license='CC0-1.0', page='https://commons.wikimedia.org/wiki/File:Réveil_des_oiseaux.ogg', download='https://upload.wikimedia.org/wikipedia/commons/3/33/R%C3%A9veil_des_oiseaux.ogg', sha256_original=hashlib.sha256(src.read_bytes()).hexdigest(), processing='8–40 s, mono 32 kHz, 2 s overlap linear crossfade, 180–6500 Hz, -20 LUFS, loop 30 s', specificity='European garden birds, generic daytime outdoor layer; no tram or city attribution'))
    # Low wind body is generated locally; deliberately contains no chirps, voices or music.
    subprocess.run(['ffmpeg','-v','error','-y','-f','lavfi','-i','anoisesrc=color=brown:amplitude=0.3:duration=18:sample_rate=32000:seed=849', '-af','highpass=f=90,lowpass=f=900,afade=t=in:d=0.6,afade=t=out:st=17.4:d=0.6,loudnorm=I=-20:TP=-3:LRA=11', '-ar','32000','-ac','1','-c:a','libvorbis','-q:a','4',str(OUT/'air_movement.ogg')],check=True)
    sources.append(dict(file='air_movement.ogg', author='Tram Sim France', license='project', processing='Local deterministic brown-noise synthesis, filtered 90–900 Hz, 0.6 s edge fades', specificity='Designed air movement; not a field recording'))
    (OUT/'SOURCES.json').write_text(json.dumps(sources,ensure_ascii=False,indent=2)+'\n')
    manifest_path = ROOT / 'data/audio/sources.json'
    manifest = json.loads(manifest_path.read_text())
    for filename, author in [('garden_day.ogg', 'Joseph Sardin, Réveil des oiseaux, CC0'), ('air_movement.ogg', 'Synthèse locale déterministe de bruit brun')]:
        log = subprocess.run(['ffmpeg', '-hide_banner', '-i', str(OUT/filename), '-af', 'loudnorm=I=-20:TP=-3:LRA=11:print_format=json', '-f', 'null', '-'], capture_output=True, text=True, check=True).stderr
        stats, _ = json.JSONDecoder().raw_decode(log[log.rfind('{'):])
        manifest['files']['free_sfx/'+filename] = dict(origine=author, licence='CC0-1.0' if filename == 'garden_day.ogg' else 'création du projet (même licence que le code)', lufs=float(stats['input_i']), provenance='free_sfx/SOURCES.json')
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=1)+'\n')

if __name__ == '__main__': main()
