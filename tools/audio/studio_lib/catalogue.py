"""One catalogue inside the existing sources.json; legacy fields are preserved."""
import re
from pathlib import Path
from .core import catalogue, safe_path, read_json, write_json, sha256, license_id, duplicates, KINDS, utc
from .dsp import analyze


def import_existing(root):
    data = catalogue(root)
    entries = data.setdefault('catalogue', {})
    families = read_json(safe_path(root, 'data/audio/families.json'))
    free = {r['file']: r for r in read_json(safe_path(root, 'data/audio/free_sfx/SOURCES.json'))}
    bank_files = {}
    for bank_id, bank in families['banks'].items():
        for event, path in bank.get('streams', {}).items():
            bank_files[path] = (bank_id, bank, event)
    for path in sorted(safe_path(root, 'data/audio').rglob('*.ogg')):
        relative = str(path.relative_to(safe_path(root, 'data/audio')))
        key = 'asset:' + relative
        if key in entries and (entries[key].get('importer_version') == 2 or entries[key].get('parent_ids')) and entries[key].get('sha256') == sha256(path):
            continue
        old = data.get('files', {}).get(relative, {})
        # v2 shares the provenance of the original bank. Never call it a new original.
        item = bank_files.get(relative) or bank_files.get('v2/' + Path(relative).name) or bank_files.get('banks/' + Path(relative).name.replace('_designed', '')) or bank_files.get('v2/' + Path(relative).name.replace('_designed', ''))
        row = {'importer_version': 2, 'id': key, 'name': relative, 'path': str(path.relative_to(root)), 'kind': 'synthetic',
               'family': 'generic', 'event': path.stem, 'author': 'TramSim contributors',
               'license': 'LicenseRef-TramSim-Original', 'license_url': '',
               'source_url': 'https://github.com/CorbetQ/tramsim', 'retrieved_at': None,
               'quality': 'legacy_unreviewed', 'validation_status': 'legacy_preserved',
               'derived_files': [], 'transformations': [old.get('modifications', old.get('origine', 'Legacy generation; see DESIGN-CREDITS.md'))],
               'compatible_profiles': [], 'provenance_evidence': ['data/audio/DESIGN-CREDITS.md', 'CREDITS.md'],
               'original_retrieval_date_unknown': True}
        if item:
            bid, bank, event = item
            source = bank.get('source', {})
            row.update(bank=bid, event=event, family=bank.get('recorded_family', 'citadis_x05' if bank.get('modeled') else 'generic'),
                       kind='recorded_related' if bank.get('traction_only') else ('recorded_exact' if bank.get('recorded') else 'modeled'),
                       compatible_profiles=[k for k, p in families['profiles'].items() if p.get('bank') == bid],
                       transformations=[bank.get('design_processing', bank.get('segments', {}).get(event, {}).get('processing', 'See bank manifest'))])
            if source:
                row.update(author=source.get('author', ''), source_url=source.get('page', ''),
                           license=license_id(source.get('license_url', '')), license_url=source.get('license_url', ''),
                           source_sha256_legacy=source.get('sha256', source.get('source_preview_sha256')),
                           source_quality='lossy_preview' if 'freesound' in source.get('page', '') else 'legacy_capture_or_transcode',
                           source_notes=source.get('notes', ''))
        elif old.get('source'):
            # Legacy files not routed by a bank still require third-party attribution.
            text = old.get('licence', '')
            match = re.search(r'https://creativecommons.org/[^\s]+', text)
            row.update(kind='recorded_related', author=old.get('origine', '').split(' — ')[0],
                       source_url=old['source'], license_url=match[0] if match else '',
                       license=license_id(match[0]) if match else 'UNKNOWN')
        f = free.get(path.name) if path.parent.name == 'free_sfx' else None
        if f and f.get('page'):
            ident = f.get('license', 'UNKNOWN')
            row.update(kind='recorded_related' if 'garden' in path.name else 'synthetic', author=f['author'],
                       license=ident, license_url='https://creativecommons.org/publicdomain/zero/1.0/' if ident == 'CC0-1.0' else '',
                       source_url=f['page'], transformations=[f['processing']], source_sha256_legacy=f.get('sha256_original'))
        if path.name in {'real_rail.ogg', 'real_rail_designed.ogg', 'lyon-citadis-original.ogg'}:
            row.update(kind='recorded_related', author='Glaneur de sons', family='citadis_unidentified',
                       source_url='https://commons.wikimedia.org/wiki/File:Tram_sound_in_Lyon,_France.ogg',
                       license='CC-BY-3.0', license_url='https://creativecommons.org/licenses/by/3.0/',
                       event='rolling', transformations=['See tools/import/recorded_audio.py and design_samples.py'] if 'original' not in path.name else [])
        if row['license'].startswith('CC-BY-SA-'):
            row['license_exception'] = 'existing_sharealike_asset; preserve attribution and share-alike; default new downloads excluded'
        row.update(analyze(path))
        row['path'] = str(path.relative_to(root))
        row['technical_checked_at'] = utc()
        entries[key] = row
    data['catalogue_schema'] = 1
    data['catalogue_policy'] = 'Catalogue is authoritative for asset bytes/licences. Legacy files/segments are historical descriptions, not current measurements. families.json is runtime routing.'
    write_json(safe_path(root, 'data/audio/sources.json'), data)
    return {'entries': len(entries), 'duplicates': duplicates(entries)}


def validate(root, waveforms=False):
    entries = catalogue(root).get('catalogue', {})
    errors, warnings = [], []
    if not entries:
        errors.append('Catalogue empty; run catalogue import')
    required = {'id', 'name', 'family', 'event', 'source_url', 'author', 'license', 'license_url', 'sha256',
                'retrieved_at', 'duration_s', 'sample_rate', 'channels', 'quality', 'validation_status',
                'derived_files', 'transformations', 'compatible_profiles', 'kind', 'path'}
    for key, row in entries.items():
        missing = required - row.keys()
        if missing:
            errors.append(f'{key}: missing {sorted(missing)}')
        if row.get('id') != key or row.get('kind') not in KINDS:
            errors.append(f'{key}: invalid id/kind')
        if row.get('license') in {'UNKNOWN', ''}:
            errors.append(f'{key}: unknown licence')
        elif row['license'] != 'LicenseRef-TramSim-Original':
            if license_id(row['license']) == 'UNKNOWN' or license_id(row.get('license_url')) != license_id(row['license']):
                errors.append(f'{key}: licence evidence mismatch')
            if not row.get('author') or not row.get('source_url'):
                errors.append(f'{key}: missing attribution')
        for parent in row.get('parent_ids', []):
            if parent not in entries:
                errors.append(f'{key}: missing parent {parent}')
            else:
                p = entries[parent]
                if p.get('license') != row.get('license') or p.get('source_url') != row.get('source_url'):
                    errors.append(f'{key}: cannot discard source attribution/licence')
        try:
            path = safe_path(root, row['path'])
            if not path.is_file() and row.get('storage') == 'cache_original':
                warnings.append(f'{key}: optional original absent from local cache; fetch from verified provider to rebuild')
                continue
            if not path.is_file() or sha256(path) != row['sha256']:
                errors.append(f'{key}: missing file or SHA-256 mismatch')
                continue
            if waveforms and path.suffix in {'.ogg', '.wav', '.flac'}:
                m = analyze(path)
                if m['clipped_samples'] or m['rms_dbfs'] < -70:
                    errors.append(f'{key}: clipping or accidental silence')
                if m['peak_dbfs'] > -0.1:
                    warnings.append(f'{key}: limited headroom')
        except (ValueError, KeyError) as ex:
            errors.append(f'{key}: {ex}')
    return {'ok': not errors, 'entries': len(entries), 'errors': errors, 'warnings': warnings, 'duplicates': duplicates(entries)}


def attributions(root):
    groups = {}
    for row in catalogue(root).get('catalogue', {}).values():
        if row['license'] != 'LicenseRef-TramSim-Original':
            key = (row['author'], row['source_url'], row['license'], row['license_url'])
            groups.setdefault(key, []).append(row['name'])
    text = '# Audio source attributions\n\nGenerated from data/audio/sources.json (catalogue). Existing credits remain valid.\n\n'
    for (author, url, lic, licurl), assets in sorted(groups.items()):
        text += f'- {author} — {url} — [{lic}]({licurl}). Derivatives: {", ".join(assets)}.\n'
    return text


def add_local(root, manifest):
    """Register an owned/reviewed local source, including explicitly labelled AI exports.
    This never downloads anything or claims that Studio itself generated the file."""
    from .core import permitted, register, KINDS
    kind = manifest.get('kind')
    if kind not in KINDS:
        raise ValueError('Explicit source kind required')
    if not re.fullmatch(r'[a-zA-Z0-9_:.-]{3,100}', manifest.get('id', '')):
        raise ValueError('Invalid local source identifier')
    if manifest.get('license') != 'LicenseRef-TramSim-Original' and not permitted(manifest):
        raise ValueError('Local source rights/evidence not allowed; ambiguous files require human review')
    if manifest.get('license') == 'LicenseRef-TramSim-Original' and not manifest.get('ownership_review'):
        raise ValueError('Project ownership must be explicitly documented')
    if kind == 'ai_generated':
        required = {'model', 'prompt', 'seed', 'weights_sha256', 'license_review'}
        if required - manifest.get('ai_metadata', {}).keys():
            raise ValueError('AI exports require model, prompt, seed, weights hash and rights review')
        if not re.fullmatch(r'[0-9a-f]{64}', manifest['ai_metadata']['weights_sha256']):
            raise ValueError('Invalid AI weights fingerprint')
    path = safe_path(root, manifest['path'])
    measured = analyze(path)
    if measured['clipped_samples'] or measured['rms_dbfs'] < -70:
        raise ValueError('Local source clips or is silent')
    if manifest.get('sha256') and measured['sha256'] != manifest['sha256']:
        raise ValueError('Local source SHA-256 mismatch')
    row = dict(manifest)
    row.update(measured)
    row.update(sha256=measured['sha256'], path=str(path.relative_to(root)), quality='candidate',
               validation_status='technical_validated_human_pending', derived_files=[], transformations=manifest.get('transformations', []),
               compatible_profiles=manifest.get('compatible_profiles', []), retrieved_at=manifest.get('retrieved_at'))
    for key in ('name', 'family', 'event', 'author', 'license_url', 'source_url'):
        if key not in row:
            raise ValueError('Missing local metadata: ' + key)
    register(root, row)
    return row
