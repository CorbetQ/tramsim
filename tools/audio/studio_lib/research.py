"""Bounded, resumable official Commons searches across every game family."""
from .core import safe_path, read_json, write_json, utc
from . import providers

TERMS = {
 'citadis_302': 'Citadis 302', 'citadis_402': 'Citadis 402', 'citadis_403_strasbourg': 'Citadis 403 Strasbourg',
 'citadis_x01': 'Citadis 301', 'citadis_x05': 'Citadis 305', 'citadis_x05_nantes': 'Citadis Nantes',
 'citadis_compact': 'Citadis Compact', 'citadis_reims': 'tram Reims', 'citadis_tours': 'tram Tours',
 'avanto': 'Avanto tram', 'breda_vlc': 'tram Lille', 'citadis_dualis': 'Citadis Dualis',
 'eurotram': 'Eurotram', 'flexity_marseille': 'tram Marseille', 'incentro': 'Incentro',
 'tango_rhonexpress': 'Stadler Tango Rhonexpress', 'tfs': 'tram Nantes', 'translohr': 'Translohr',
 'urbos': 'Urbos tram', 'vevey_saint_etienne': 'tram Saint Etienne'}


def run(root, output, family='all', limit=2):
    path = safe_path(root, output)
    families = read_json(safe_path(root, 'data/audio/families.json'))['profiles']
    if family != 'all' and family not in families:
        raise ValueError('Unknown game family')
    result = read_json(path) if path.exists() else {'provider': 'Commons official API', 'started_at': utc(), 'families': {}}
    for key in families if family == 'all' else [family]:
        if key in result['families']:
            continue
        query = TERMS.get(key, key.replace('_', ' '))
        try:
            rows = providers.search(root, 'commons', query, limit)
            item = {'query': query, 'candidates': rows, 'material_identity_verified': False, 'note': 'Search ranking may return unrelated material. Review picture/description and sound before family assignment.', 'status': 'metadata_candidates_human_review' if rows else 'no_results'}
        except (OSError, ValueError) as ex:
            item = {'query': query, 'candidates': [], 'status': 'provider_error', 'error': str(ex)}
        result['families'][key] = dict(item, checked_at=utc())
        write_json(path, result)
        print('RESEARCH|' + key + '|' + item['status'], flush=True)
    return result
