"""Paths, atomic manifests and conservative licence policy."""
import hashlib
import json
import os
import re
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import urlsplit

ROOT = Path(__file__).resolve().parents[3]
CATALOGUE = 'data/audio/sources.json'
KINDS = {'recorded_exact', 'recorded_related', 'modeled', 'synthetic', 'ai_generated'}


def utc():
    return datetime.now(timezone.utc).isoformat()


def safe_path(root, name):
    """All studio writes/reads must stay in the selected workspace, outside .git."""
    root = Path(root).resolve()
    path = (root / name).resolve()
    if not path.is_relative_to(root) or '.git' in path.relative_to(root).parts:
        raise ValueError('Path outside allowed workspace')
    return path


def read_json(path):
    return json.loads(Path(path).read_text(encoding='utf-8'))


def write_json(path, data):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + '.part')
    tmp.write_text(json.dumps(data, ensure_ascii=False, indent=2, allow_nan=False) + '\n', encoding='utf-8')
    os.replace(tmp, path)


def sha256(path):
    h = hashlib.sha256()
    with Path(path).open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            h.update(chunk)
    return h.hexdigest()


def license_id(value):
    """Use exact official licence URLs/identifiers; never match permissive substrings."""
    value = (value or '').strip()
    if value in {'CC0', 'CC0 1.0'}: return 'CC0-1.0'
    if re.fullmatch(r'CC0-1\.0|CC-BY-(?:1\.0|2\.0|2\.5|3\.0|4\.0)|CC-BY-SA-(?:1\.0|2\.0|2\.5|3\.0|4\.0)', value):
        return value
    u = urlsplit(value)
    if u.hostname in {'creativecommons.org', 'www.creativecommons.org'} and u.scheme in {'https', 'http'}:
        path = u.path.rstrip('/')
        if re.fullmatch(r'/publicdomain/zero/1\.0(?:/legalcode|/deed(?:\.[a-z]+)?)?', path):
            return 'CC0-1.0'
        m = re.fullmatch(r'/licenses/(by|by-sa)/(1\.0|2\.0|2\.5|3\.0|4\.0)(?:/legalcode|/deed(?:\.[a-z]+)?)?', path)
        if m:
            return 'CC-' + m[1].upper() + '-' + m[2]
    # Legacy descriptive identifiers, not arbitrary free text.
    m = re.fullmatch(r'CC (BY(?:-SA)?) (1\.0|2\.0|2\.5|3\.0|4\.0)', value)
    return 'CC-' + m[1] + '-' + m[2] if m else 'UNKNOWN'


def permitted(entry, allow_sharealike=False):
    ident = license_id(entry.get('license_url', ''))
    named = license_id(entry.get('license', ''))
    if ident == 'UNKNOWN' or named == 'UNKNOWN' or named != ident:
        return False
    allowed = ident == 'CC0-1.0' or ident.startswith('CC-BY-') and not ident.startswith('CC-BY-SA-')
    if allow_sharealike:
        allowed |= ident.startswith('CC-BY-SA-')
    return bool(allowed and entry.get('author') and entry.get('source_url') and entry.get('evidence'))


def catalogue(root=ROOT):
    return read_json(safe_path(root, CATALOGUE))


def register(root, entry):
    data = catalogue(root)
    entries = data.setdefault('catalogue', {})
    prior = entries.get(entry['id'])
    if prior and prior.get('sha256') != entry.get('sha256'):
        raise ValueError('Identifier already belongs to different bytes')
    entries[entry['id']] = entry
    data['catalogue_schema'] = 1
    write_json(safe_path(root, CATALOGUE), data)


def duplicates(entries):
    groups = {}
    for key, row in entries.items():
        if row.get('sha256'):
            groups.setdefault(row['sha256'], []).append(key)
    return [ids for ids in groups.values() if len(ids) > 1]
