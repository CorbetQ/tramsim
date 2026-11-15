"""Disabled-by-default local Soundbox job submission. Never installs weights implicitly."""
import importlib.util
import json
import os
import shutil
import urllib.request
from urllib.parse import urlsplit
from .core import safe_path, read_json, write_json, utc

MODELS = {
    'stable-audio-open-small': {'code_license': 'MIT (stable-audio-tools)', 'weights_license': 'Stability AI Community (conditional)',
        'weights_url': 'https://huggingface.co/stabilityai/stable-audio-open-small', 'weights_bytes': 1676829212,
        'max_duration_s': 11, 'cpu': True, 'commercial': 'conditional; registration and current agreement must be reviewed', 'approved': False},
    'audiocpp-stable-audio-3-sfx': {'code_license': 'MIT (Soundbox); inspect installed audio.cpp revision separately',
        'weights_license': 'Stability AI Community (conditional)', 'weights_url': 'https://huggingface.co/stabilityai/stable-audio-3-small-sfx',
        'max_duration_s': 120, 'cpu': True, 'commercial': 'conditional; gated weights', 'approved': False},
    'audiogen': {'code_license': 'MIT', 'weights_license': 'CC-BY-NC-4.0', 'weights_url': 'https://github.com/facebookresearch/audiocraft/blob/main/LICENSE_weights',
        'cpu': True, 'commercial': 'NO', 'approved': False},
}


def hardware(root):
    def value(path):
        try:
            with open(path) as stream:
                return stream.read().strip()
        except OSError:
            return None
    return {'disk_free_bytes': shutil.disk_usage(root).free, 'cpu_host_count': os.cpu_count(),
            'cpu_quota': value('/sys/fs/cgroup/cpu.max'), 'memory_limit_bytes': value('/sys/fs/cgroup/memory.max'),
            'gpu_devices': [p for p in ('/dev/nvidia0', '/dev/dri/renderD128') if os.path.exists(p)],
            'torch_installed': importlib.util.find_spec('torch') is not None,
            'ffmpeg': shutil.which('ffmpeg'), 'godot': shutil.which('godot')}


def status(root):
    path = safe_path(root, '.cache/audio-studio/ai-config.json')
    config = read_json(path) if path.exists() else {'enabled': False, 'reason': 'No reviewed local weights configured. No AI inference has been performed.'}
    return {'config': config, 'hardware': hardware(root), 'models': MODELS}


def submit(root, prompt, seed=7, variations=1, duration=4):
    """Only explicitly installed, reviewed weights may run. Soundbox can auto-download on first run,
    therefore require a verified local weight file + installed model confirmation beforehand."""
    path = safe_path(root, '.cache/audio-studio/ai-config.json')
    config = read_json(path) if path.exists() else {}
    if not config.get('enabled'):
        raise ValueError('AI backend disabled. Configure reviewed local Soundbox/weights; no sound generated.')
    if not config.get('license_review') or not config.get('model_installed_confirmed'):
        raise ValueError('Explicit licence review and installed-model confirmation required')
    from .core import sha256
    weight = safe_path(root, config['weights_path'])
    if sha256(weight) != config['weights_sha256']:
        raise ValueError('Weights missing or fingerprint mismatch; no automatic download')
    model = config['model']
    if model not in MODELS or MODELS[model].get('commercial') == 'NO':
        raise ValueError('Unapproved model')
    if not 1 <= variations <= 4 or not 0 < duration <= MODELS[model]['max_duration_s'] or not 1 <= len(prompt) <= 2000:
        raise ValueError('Generation parameters out of range')
    base = config.get('url', 'http://127.0.0.1:17494')
    u = urlsplit(base)
    if u.scheme != 'http' or u.hostname not in {'127.0.0.1', 'localhost', '::1'} or u.username or u.query or u.path not in ('', '/'):
        raise ValueError('Only loopback Soundbox is permitted; no cloud endpoint')
    body = {'model': model, 'prompt': prompt, 'seed': int(seed), 'duration_s': duration, 'variations': variations,
            'steps': int(config.get('steps', 8)), 'cfg': float(config.get('cfg', 1.0))}
    req = urllib.request.Request(base.rstrip('/') + '/api/generate', data=json.dumps(body).encode(), headers={'Content-Type': 'application/json'})
    # Disable HTTP redirects entirely: a local adapter must never send prompts remotely.
    class NoRedirect(urllib.request.HTTPRedirectHandler):
        def redirect_request(self, *args):
            raise ValueError('AI endpoint redirect denied')
    with urllib.request.build_opener(NoRedirect()).open(req, timeout=30) as response:
        result = json.loads(response.read(1024 * 1024))
    if not isinstance(result.get('job_id'), str):
        raise ValueError('Soundbox did not return a job id')
    receipt = {'submitted_at': utc(), 'kind': 'ai_generated', 'status': 'submitted_not_generated', 'request': body,
               'job': result, 'model_weights_sha256': config['weights_sha256'], 'license_review': config['license_review'],
               'events_url': base.rstrip('/') + '/api/jobs/' + result['job_id'] + '/events'}
    # Do not use an untrusted job id as a path.
    import hashlib
    name = hashlib.sha256(result['job_id'].encode()).hexdigest()
    write_json(safe_path(root, '.cache/audio-studio/ai-jobs/' + name + '.json'), receipt)
    return receipt
