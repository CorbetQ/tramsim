#!/usr/bin/env python3
"""TramSim Audio Studio: safe, local, reproducible production commands."""
import argparse
import json
import subprocess
import sys
from pathlib import Path
from studio_lib.core import ROOT, safe_path, read_json, write_json, catalogue, register, utc
from studio_lib import ai, dsp, providers, banks
from studio_lib import catalogue as cat


def parser():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--root', type=Path, default=ROOT)
    s = p.add_subparsers(dest='command', required=True)
    s.add_parser('doctor')
    q = s.add_parser('search'); q.add_argument('provider', choices=['commons', 'freesound', 'kenney', 'opengameart', 'institutional']); q.add_argument('query'); q.add_argument('--limit', type=int, default=5); q.add_argument('--min-duration', type=float, default=0); q.add_argument('--max-duration', type=float, default=120); q.add_argument('--output')
    q = s.add_parser('research'); q.add_argument('--family', default='all'); q.add_argument('--limit', type=int, default=2); q.add_argument('--output', default='.cache/audio-studio/research-results.json')
    q = s.add_parser('inspect'); q.add_argument('title'); q.add_argument('--output')
    q = s.add_parser('fetch'); q.add_argument('candidate'); q.add_argument('--family', required=True); q.add_argument('--event', required=True); q.add_argument('--kind', choices=['recorded_exact', 'recorded_related'], default='recorded_related'); q.add_argument('--preview', action='store_true')
    q = s.add_parser('catalogue'); q.add_argument('action', choices=['import', 'add', 'list', 'validate', 'duplicates', 'credits']); q.add_argument('--manifest'); q.add_argument('--query', default=''); q.add_argument('--waveforms', action='store_true'); q.add_argument('--output')
    for command in ['process', 'loop']:
        q = s.add_parser(command); q.add_argument('source'); q.add_argument('output'); q.add_argument('--recipe', required=True); q.add_argument('--source-id'); q.add_argument('--family', default='generic'); q.add_argument('--event', default='effect')
    q = s.add_parser('segments'); q.add_argument('source'); q.add_argument('--seconds', type=float, default=3)
    q = s.add_parser('analyze'); q.add_argument('source'); q.add_argument('--output')
    q = s.add_parser('rates'); q.add_argument('source'); q.add_argument('--start', type=float, default=0); q.add_argument('--duration', type=float, default=4); q.add_argument('--output', default='.cache/audio-studio/rate-comparison.json')
    q = s.add_parser('compare'); q.add_argument('first'); q.add_argument('second'); q.add_argument('--output')
    q = s.add_parser('bank'); q.add_argument('action', choices=['build', 'rebuild', 'validate', 'activate']); q.add_argument('manifest_or_id', nargs='?'); q.add_argument('--family'); q.add_argument('--waveforms', action='store_true'); q.add_argument('--human-reviewed', action='store_true')
    q = s.add_parser('ai'); q.add_argument('action', choices=['status', 'models', 'configure', 'generate']); q.add_argument('--config'); q.add_argument('--prompt'); q.add_argument('--seed', type=int, default=7); q.add_argument('--variations', type=int, default=1); q.add_argument('--duration', type=float, default=4)
    q = s.add_parser('synth'); q.add_argument('output'); q.add_argument('--seed', type=int, default=7)
    q = s.add_parser('demo'); q.add_argument('--family', default='citadis_302'); q.add_argument('--variant', default='angers__citadis_302'); q.add_argument('--name', default='studio_demo'); q.add_argument('--expected-bank', default='rotterdam_citadis_traction'); q.add_argument('--audition-bank', default=''); q.add_argument('--traction-solo', action='store_true')
    s.add_parser('package-demos')
    q = s.add_parser('report'); q.add_argument('--output', default='.cache/audio-studio/report.json'); q.add_argument('--waveforms', action='store_true')
    q = s.add_parser('test'); q.add_argument('--godot', action='store_true')
    return p


def main(argv=None):
    a = parser().parse_args(argv)
    from studio_lib.locking import workspace_lock
    with workspace_lock(a.root.resolve()):
        return execute(a)


def execute(a):
    root = a.root.resolve()
    path = lambda name: safe_path(root, name)
    command = a.command
    if command == 'doctor':
        result = ai.hardware(root)
    elif command == 'search':
        result = providers.search(root, a.provider, a.query, a.limit, a.min_duration, a.max_duration)
    elif command == 'research':
        from studio_lib import research
        result = research.run(root, a.output, a.family, a.limit)
    elif command == 'inspect':
        result = providers.commons_inspect(providers.Client(root), a.title)
    elif command == 'fetch':
        candidate = read_json(path(a.candidate))
        if isinstance(candidate, list):
            if len(candidate) != 1:
                raise ValueError('Select one candidate into a JSON object before downloading')
            candidate = candidate[0]
        result = providers.fetch(root, candidate, a.family, a.event, a.kind, a.preview)
    elif command == 'catalogue':
        if a.action == 'import':
            result = cat.import_existing(root)
        elif a.action == 'add':
            if not a.manifest: raise ValueError('--manifest required')
            result = cat.add_local(root, read_json(path(a.manifest)))
        elif a.action == 'validate':
            result = cat.validate(root, a.waveforms)
        elif a.action == 'credits':
            result = cat.attributions(root)
        else:
            from studio_lib.core import duplicates
            entries = catalogue(root).get('catalogue', {})
            result = duplicates(entries) if a.action == 'duplicates' else [r for r in entries.values() if a.query.lower() in json.dumps(r, ensure_ascii=False).lower()]
    elif command in {'process', 'loop'}:
        recipe = read_json(path(a.recipe))
        if command == 'loop' and not recipe.get('loop_overlap'):
            raise ValueError('loop recipe requires loop_overlap seconds')
        source = path(a.source)
        if a.source_id:
            parent = catalogue(root)['catalogue'][a.source_id]
            from studio_lib.core import sha256
            if sha256(source) != parent['sha256']:
                raise ValueError('Source fingerprint mismatch')
        result = dsp.process(source, path(a.output), recipe)
        if a.source_id:
            row = dict(parent)
            row.update(result)
            row.update(id='asset:' + a.output, name=a.output, path=a.output, family=a.family, event=a.event,
                       parent_ids=[a.source_id], derived_files=[], transformations=[recipe],
                       quality='candidate', validation_status='technical_validated_human_pending')
            register(root, row)
    elif command == 'segments':
        result = dsp.segments(path(a.source), a.seconds)
    elif command == 'analyze':
        result = dsp.analyze(path(a.source))
    elif command == 'rates':
        result = {}
        for rate in (32000, 44100, 48000):
            output = path('.cache/audio-studio/rates/' + str(rate) + '.ogg')
            result[str(rate)] = dsp.process(path(a.source), output, {'start': a.start, 'duration': a.duration, 'rate': rate, 'channels': 1, 'ceiling_db': -2})
            result[str(rate)]['pcm_float_memory_bytes'] = int(result[str(rate)]['duration_s'] * rate * 4)
        result['note'] = 'Upsampling does not create absent detail. Compare the decoded source bandwidth and human audition before choosing a rate.'
    elif command == 'compare':
        result = dsp.compare(path(a.first), path(a.second))
    elif command == 'bank':
        if a.action == 'build':
            result = banks.build(root, read_json(path(a.manifest_or_id)))
        elif a.action == 'rebuild':
            result = banks.rebuild(root, a.manifest_or_id)
        elif a.action == 'validate':
            result = banks.validate(root, a.waveforms)
        else:
            result = banks.activate(root, a.manifest_or_id, a.family, a.human_reviewed)
    elif command == 'ai':
        if a.action == 'configure':
            config = read_json(path(a.config))
            if config.get('enabled') and not config.get('license_review'):
                raise ValueError('Explicit licence review required')
            write_json(path('.cache/audio-studio/ai-config.json'), config)
            result = ai.status(root)
        elif a.action == 'generate':
            result = ai.submit(root, a.prompt or '', a.seed, a.variations, a.duration)
        else:
            result = ai.status(root) if a.action == 'status' else ai.MODELS
    elif command == 'synth':
        # A deliberately labelled procedural fallback; this is not AI or an authentic door.
        import numpy as np
        from scipy import signal
        rate = 32000
        rng = np.random.default_rng(a.seed)
        t = np.arange(rate) / rate
        x = signal.sosfilt(signal.butter(2, [100, 1800], btype='bandpass', fs=rate, output='sos'), rng.normal(0, .07, rate))
        x *= np.sin(np.pi * t) ** 2
        dsp.export(x[:, None], rate, path(a.output))
        result = dsp.analyze(path(a.output))
        result.update(kind='synthetic', description='Procedural sliding mechanism test, not AI and not authentic tram recording', seed=a.seed)
        write_json(str(path(a.output)) + '.recipe.json', result)
    elif command == 'demo':
        import re
        if not re.fullmatch(r'[a-zA-Z0-9_-]{1,80}', a.name):
            raise ValueError('Invalid demo name')
        subprocess.run(['bash', 'tools/audio/capture_driving_audio.sh', a.family, a.variant, a.name, a.expected_bank,
                        'traction_solo' if a.traction_solo else 'full_mix', 'production_filters', a.audition_bank], cwd=root, check=True)
        result = dsp.analyze(path('samples/demos/' + a.name + '.wav'))
    elif command == 'package-demos':
        from studio_lib import demos
        result = demos.package(root)
    elif command == 'report':
        result = {'created_at': utc(), 'catalogue': cat.validate(root, a.waveforms), 'banks': banks.validate(root, a.waveforms), 'hardware': ai.hardware(root)}
        result['ok'] = result['catalogue']['ok'] and result['banks']['ok']
    elif command == 'test':
        subprocess.run([sys.executable, '-m', 'unittest', 'discover', '-s', 'tests', '-p', 'test_audio*.py'], cwd=root, check=True)
        if a.godot:
            for suite in ['audio', 'audio_families', 'audio_interlocks', 'audio_rotterdam', 'audio_variants', 'audio_studio']:
                subprocess.run(['godot', '--headless', '--path', '.', '-s', 'tests/test_' + suite + '.gd'], cwd=root, check=True, timeout=300)
        result = {'ok': True}
    if getattr(a, 'output', None):
        if isinstance(result, str):
            output = path(a.output); output.parent.mkdir(parents=True, exist_ok=True); output.write_text(result)
        else:
            write_json(path(a.output), result)
    print(result if isinstance(result, str) else json.dumps(result, ensure_ascii=False, indent=2, allow_nan=False))
    if isinstance(result, dict) and result.get('ok') is False:
        return 1
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (ValueError, KeyError, OSError, subprocess.SubprocessError) as ex:
        print(json.dumps({'ok': False, 'error': str(ex)}, ensure_ascii=False), file=sys.stderr)
        sys.exit(2)
