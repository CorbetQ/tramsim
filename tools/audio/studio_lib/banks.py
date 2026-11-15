"""Candidate banks are additive. Activation requires explicit human audition acknowledgement."""
import re
from .core import safe_path, read_json, write_json, catalogue, register, sha256, license_id
from .dsp import process, analyze


def build(root, manifest):
    if not re.fullmatch(r'[a-z0-9_]{3,80}', manifest['id']):
        raise ValueError('Invalid bank identifier')
    families_path = safe_path(root, 'data/audio/families.json')
    families = read_json(families_path)
    if manifest['id'] in families['banks']:
        raise ValueError('Bank already exists; use a new revision identifier')
    if any(f not in families['profiles'] for f in manifest['compatible_families']):
        raise ValueError('Unknown compatible family')
    entries = catalogue(root).get('catalogue', {})
    streams, measured, derived = {}, {}, []
    for layer, spec in manifest['layers'].items():
        if layer not in {'motor', 'motor_hum', 'carrier', 'rolling', 'regen', 'squeal', 'hvac', 'ambience', 'birds', 'air', 'real_rail', 'joint', 'brake_mech', 'brake_release', 'emergency', 'door_open', 'door_chime', 'door_close', 'gong'}:
            raise ValueError('Unsupported runtime layer')
        source = entries[spec['source_id']]
        if (license_id(source.get('license')) == 'UNKNOWN' and source.get('license') != 'LicenseRef-TramSim-Original') or source.get('validation_status') == 'rejected':
            raise ValueError('Unapproved source')
        if source['license'].startswith('CC-BY-SA') and not source.get('license_exception'):
            raise ValueError('Sharealike source needs reviewed obligations')
        src = safe_path(root, source['path'])
        if sha256(src) != source['sha256']:
            raise ValueError('Original SHA-256 mismatch')
        relative = f"studio/{manifest['id']}_{layer}.ogg"
        dst = safe_path(root, 'data/audio/' + relative)
        result = process(src, dst, spec['recipe'])
        row = dict(source)
        key = 'asset:' + relative
        row.update(result)
        row.update(id=key, name=relative, path=str(dst.relative_to(root)), family=manifest['compatible_families'][0],
                   event=layer, quality='candidate', validation_status='technical_validated_human_pending',
                   parent_ids=[source['id']], derived_files=[], transformations=[spec['recipe']],
                   compatible_profiles=manifest['compatible_families'])
        derived.append(row)
        streams[layer] = relative
        measured[layer] = {k: result[k] for k in ('sha256', 'duration_s', 'sample_rate', 'channels', 'integrated_lufs', 'true_peak_dbfs_4x', 'seam_to_peak')}
    bank = {'label': manifest['label'], 'recorded': all(r['kind'].startswith('recorded') for r in derived),
            'streams': streams, 'segments': measured, 'compatible_families': manifest['compatible_families'],
            'source_classification': sorted({r['kind'] for r in derived}),
            'recorded_family': manifest['compatible_families'][0] if all(r['kind'] == 'recorded_exact' for r in derived) else '',
            'production_status': 'candidate_human_audition_required', 'mix': manifest.get('mix', {}),
            'studio_recipe': manifest, 'reference_speed_estimated': True}
    # Publish routing only after every layer has encoded and passed analysis.
    for row in derived:
        register(root, row)
    data = catalogue(root)
    for row in derived:
        parent = data['catalogue'][row['parent_ids'][0]]
        parent['derived_files'] = sorted(set(parent.get('derived_files', []) + [row['id']]))
    write_json(safe_path(root, 'data/audio/sources.json'), data)
    families['banks'][manifest['id']] = bank
    write_json(families_path, families)
    return bank


def validate(root, waveforms=False):
    f = read_json(safe_path(root, 'data/audio/families.json'))
    entries = catalogue(root).get('catalogue', {})
    by_path = {r['path']: r for r in entries.values()}
    errors = []
    for bid, bank in f['banks'].items():
        for layer, relative in bank.get('streams', {}).items():
            key = 'data/audio/' + relative
            path = safe_path(root, key)
            row = by_path.get(key)
            if not path.is_file() or not row or sha256(path) != row['sha256']:
                errors.append(f'{bid}/{layer}: missing or untracked/mismatched asset')
                continue
            if waveforms:
                m = analyze(path)
                if m['clipped_samples'] or m['rms_dbfs'] < -70 or not .1 < m['duration_s'] < 120:
                    errors.append(f'{bid}/{layer}: invalid waveform')
        if not bank.get('recorded') and not bank.get('modeled') and not bank.get('studio_recipe'):
            errors.append(f'{bid}: missing classification')
    for family, p in {**f['profiles'], **f.get('variant_profiles', {})}.items():
        if p.get('bank') and p['bank'] not in f['banks']:
            errors.append(f'{family}: missing bank')
    return {'ok': not errors, 'banks': len(f['banks']), 'errors': errors,
            'runtime_bytes': sum(p.stat().st_size for p in safe_path(root, 'data/audio').rglob('*.ogg'))}


def activate(root, bank_id, family, reviewed=False):
    if not reviewed:
        raise ValueError('Activation requires --human-reviewed after listening; metrics alone are insufficient')
    path = safe_path(root, 'data/audio/families.json')
    f = read_json(path)
    bank = f['banks'][bank_id]
    if family not in bank.get('compatible_families', []):
        raise ValueError('Bank not declared compatible with family')
    if not validate(root)['ok']:
        raise ValueError('Bank validation failed')
    write_json(safe_path(root, '.cache/audio-studio/families-before-activation.json'), f)
    f['profiles'][family]['bank'] = bank_id
    f['profiles'][family]['quality'] = ('exact_family' if bank.get('recorded_family') == family else 'related_family') if bank.get('recorded') else 'modeled'
    bank['production_status'] = 'human_reviewed'
    write_json(path, f)
    return {'activated': bank_id, 'family': family, 'note': 'Variant-specific overrides remain explicit and take precedence.'}


def rebuild(root, bank_id):
    bank = read_json(safe_path(root, 'data/audio/families.json'))['banks'][bank_id]
    manifest = bank['studio_recipe']
    entries = catalogue(root)['catalogue']
    results = {}
    for layer, spec in manifest['layers'].items():
        source = entries[spec['source_id']]
        path = safe_path(root, source['path'])
        if not path.exists():
            raise ValueError('Original absent; fetch the licensed source first')
        if sha256(path) != source['sha256']:
            raise ValueError('Original SHA-256 mismatch')
        output = safe_path(root, f'.cache/audio-studio/rebuild/{bank_id}_{layer}.ogg')
        measured = process(path, output, spec['recipe'])
        expected = sha256(safe_path(root, 'data/audio/' + bank['streams'][layer]))
        results[layer] = {'expected_sha256': expected, 'rebuilt_sha256': measured['sha256'], 'identical': expected == measured['sha256']}
    return {'ok': all(r['identical'] for r in results.values()), 'bank': bank_id, 'layers': results,
            'note': 'Byte identity is expected for the recorded FFmpeg/NumPy/SciPy toolchain; inspect differences after dependency upgrades.'}
